"""Resolve words and print usage. The command tree lives in catalog."""

from axs.codes import DOWN, EXPIRED, FAIL, LOCK, USAGE
import os
import sys

from axs.catalog import GROUPS, SIG
from axs.render import bold, call_usage, command_error, die, emph, help_text, layer_text, option_error


class ResolveError(Exception):
    def __init__(self, code, message=""):
        self.code = code
        self.message = message


def resolve_token(word, words, aliases):
    if word in aliases:
        return aliases[word]
    if word in words:
        return word
    hits = [name for name in words if word and name.startswith(word)]
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        raise ResolveError(1, "候选：" + " ".join(hits))
    raise ResolveError(2)


def _alias_marks(aliases, words=()):
    marks = {}
    for alias, command in aliases.items():
        if alias.isalnum() and alias in command and len(alias) > len(marks.get(command, "")):
            marks[command] = alias
    for command in words:
        if marks.get(command):
            continue
        for size in range(1, len(command) + 1):
            head = command[:size]
            if sum(name.startswith(head) for name in words) == 1:
                marks[command] = head
                break
    return marks


def _paint_marked(word, alias=None):
    if not alias or alias not in word:
        return bold(word)
    start = word.index(alias)
    end = start + len(alias)
    chunks = []
    if start:
        chunks.append(bold(word[:start]))
    chunks.append(emph("36", word[start:end]))
    if end < len(word):
        chunks.append(bold(word[end:]))
    return "".join(chunks)


def _usage_word(word, group=None):
    alias = None
    if group:
        names, aliases = GROUPS[group]
        alias = _alias_marks(aliases, names).get(word)
    return _paint_marked(word, alias)


def _pipes(words, group=None):
    return "|".join(_usage_word(word, group) for word in words)


def usage_text():
    # Usage is stderr. Color follows that stream, not stdout.
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        flags = "|".join(_usage_word(flag) for flag in ("--full", "--all"))
        lines = [
            "用法：axs " + _usage_word("service", "top") + " " + _pipes(["status", "start", "stop", "restart", "ensure", "enable", "disable"], "service"),
            "      axs " + _usage_word("subscription", "top") + " " + _pipes(["status", "show", "add", "rm", "switch", "refresh", "clean"], "subscription"),
            "      axs " + _usage_word("rule", "top") + " " + _pipes(["status", "show", "add", "del"], "rule"),
            "      axs " + _usage_word("group", "top") + " " + _pipes(["status", "members", "switch", "test"], "group"),
            "      axs " + _usage_word("node", "top") + " " + _pipes(["status", "show", "test"], "node") + " " + flags + " " + _usage_word("--depth") + " N",
            "      axs " + _usage_word("network", "top") + " " + _pipes(["test", "ip"], "network"),
            "      axs "
            + _usage_word("proxy", "top")
            + " "
            + _usage_word("status", "proxy")
            + "; "
            + _usage_word("user", "proxy")
            + " "
            + _pipes(["on", "off", "status"])
            + "; "
            + _usage_word("system", "proxy")
            + " "
            + _pipes(["on", "off", "enable", "disable", "status"])
            + "; "
            + _usage_word("session", "proxy")
            + " "
            + _pipes(["enable", "disable", "status"]),
            "      axs " + _pipes(["status", "clean", "help"], "top"),
        ]
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
    return "\n".join(lines) + "\n"


def _usage():
    sys.stderr.write(usage_text())
    code = USAGE
    raise SystemExit(code)


def _emit(build):
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        text = build()
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
    sys.stderr.write(text if text.endswith("\n") else text + "\n")
    raise SystemExit(USAGE)


def _spec(flags):
    known, shown = {}, []
    for flag in flags:
        hidden = flag.endswith("!")
        token = flag[:-1] if hidden else flag
        takes = token.endswith("=")
        name = token[:-1] if takes else token
        known[name] = takes
        if not hidden:
            shown.append(name + (" N" if takes else ""))
    return known, shown


def _bound(group, name, args):
    least, most, flags, _hidden = SIG[group][name]
    known, shown = _spec(flags)
    count = index = 0
    while index < len(args):
        arg = args[index]
        if len(arg) > 1 and arg.startswith("-"):
            if arg not in known:
                _emit(lambda arg=arg, shown=tuple(shown): option_error(arg, shown))
            if known[arg] and index + 1 >= len(args):
                _emit(lambda group=group, name=name: call_usage(group, name))
            index += 2 if known[arg] else 1
            continue
        count += 1
        index += 1
    if count < least or (most is not None and count > most):
        _emit(lambda group=group, name=name: call_usage(group, name))


def _take(group, argv):
    if not argv:
        _usage()
    words, aliases = GROUPS[group]
    try:
        name = resolve_token(argv[0], words, aliases)
    except ResolveError as exc:
        if exc.code == 1 and exc.message:
            sys.stderr.write(exc.message + "\n")
            code = USAGE
            raise SystemExit(code)
        if group == "top":
            _usage()
        _emit(lambda group=group, word=argv[0]: command_error(group, word))
    if name in SIG[group]:
        _bound(group, name, argv[1:])
    return name, argv[1:]


def _rule_status(run):
    from pathlib import Path

    from axs.codes import FAIL
    from axs.config import SECRET, api_address
    from axs.core import service_up
    from axs.mihomo import load_proxies
    from axs.routes import build
    from axs.rulelist import status_text

    proxies = {}
    if service_up(run):
        api = api_address(run)
        if not api:
            die(FAIL, "控制器失败")
        try:
            proxies = load_proxies(Path(run) / SECRET, api)
        except SystemExit as exc:
            code = exc.code if isinstance(exc.code, int) else FAIL
            raise SystemExit(FAIL if code == USAGE else code)
    data = build(proxies, run)
    if data is None:
        die(DOWN, "服务：未运行")
    sys.stdout.write(status_text(data, header=True))



def cmd_help(run, rest):
    del run
    sys.stdout.write(help_text(bool(rest)))


def cmd_status(run, rest):
    del rest
    from axs.status import status

    status(run)


def cmd_clean(run, rest):
    from axs.service import clean

    clean(run, "config", rest)


def cmd_health(run, rest):
    del rest
    from axs.service import health

    health(run)


def cmd_service(run, rest):
    from axs.service import boot, ensure, health, restart, start, stop
    from axs.status import service_status

    op, extra = _take("service", rest)
    if op == "ensure":
        ensure(run, extra)
    elif op == "status":
        service_status(run)
    elif op == "start":
        start(run)
    elif op == "stop":
        stop(run)
    elif op == "restart":
        restart(run)
    elif op == "health":
        health(run)
    else:
        boot(run, op)


def cmd_subscription(run, rest):
    from axs.service import clean
    from axs.subscription import dispatch as sub_dispatch

    op, extra = _take("subscription", rest)
    if op == "clean":
        clean(run, "sub", extra)
    else:
        sub_dispatch(run, op, extra)


def cmd_rule(run, rest):
    from axs.codes import USAGE
    from axs.render import die
    from axs.rulelist import cmd_list
    from axs.rules import cmd_add, cmd_del

    op, extra = _take("rule", rest)
    if op == "status":
        _rule_status(run)
    elif op == "show":
        if extra not in ([], ["--local"]):
            die(USAGE, "用法错误")
        else:
            cmd_list(run, extra == ["--local"])
    elif op == "add":
        cmd_add(run, extra)
    elif op == "del":
        cmd_del(run, extra)


def cmd_node(run, rest):
    import axs.nodecmd as nodecmd
    import axs.speed as speed

    op, extra = _take("node", rest)
    if op == "test":
        speed.cmd_test(run, extra)
    else:
        nodecmd.run(run, "status" if op == "status" else "list", extra)


def cmd_group(run, rest):
    import axs.nodecmd as nodecmd
    import axs.speed as speed

    op, extra = _take("group", rest)
    if op == "test":
        speed.run(run, extra)
    else:
        kind = {"status": "groups", "members": "members", "switch": "switch"}[op]
        nodecmd.run(run, kind, extra)


def cmd_network(run, rest):
    from axs.net import net_ip, net_test

    op, extra = _take("network", rest)
    if op == "test":
        net_test(run, extra)
    elif op == "ip":
        net_ip(run, extra)


def cmd_proxy(run, rest):
    from axs.proxy import proxy_session, proxy_status, proxy_system, proxy_user
    from axs.proxylan import run as lan_run

    op, extra = _take("proxy", rest)
    if op == "status":
        proxy_status(run)
    elif op == "lan":
        lan_run(run, extra)
    else:
        {"user": proxy_user, "system": proxy_system, "session": proxy_session}[op](run, extra)


def main(argv):
    import sys as _sys

    from axs.catalog import ROUTE
    from axs.config import LOOPBACK
    from axs.core import prime
    from axs.service import run_dir

    prime()
    if not argv:
        _usage()
    cmd, rest = _take("top", argv)
    run = run_dir()
    if cmd in {"service", "node", "group", "rule", "subscription", "proxy", "network"} and not rest:
        sys.stdout.write(layer_text(cmd, LOOPBACK))
        return
    getattr(_sys.modules[__name__], ROUTE[cmd])(run, rest)
