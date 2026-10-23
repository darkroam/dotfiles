"""Command words, aliases, and the help text they print."""

from axs.codes import DOWN, EXPIRED, FAIL, LOCK, USAGE
import os
import sys

from axs.render import bold, die, dim, emph, ident, pad


class ResolveError(Exception):
    def __init__(self, code, message=""):
        self.code = code
        self.message = message


TOP = (
    "start stop status restart health ensure clean help service sub rule node net proxy".split(),
    {
        "s": "status",
        "su": "sub",
        "se": "service",
        "sta": "start",
        "sto": "stop",
        "e": "ensure",
        "h": "help",
        "?": "help",
        "n": "node",
        "ne": "net",
        "p": "proxy",
        "r": "rule",
        "re": "restart",
        "c": "clean",
        "he": "health",
        "--help": "help",
        "-h": "help",
    },
)
GROUPS = {
    "top": TOP,
    "service": ("enable disable".split(), {"e": "enable", "d": "disable"}),
    "sub": ("get refresh clean".split(), {"g": "get", "r": "refresh", "c": "clean"}),
    "rule": ("list add del".split(), {"l": "list", "a": "add", "d": "del"}),
    "node": ("groups list test switch".split(), {"g": "groups", "l": "list", "t": "test", "s": "switch"}),
    "net": ("test ip".split(), {"t": "test", "i": "ip"}),
    "proxy": ("user system session".split(), {"u": "user", "sy": "system", "se": "session"}),
}

INTRO = "别名精确优先；未命中则唯一前缀。多个候选退出 1 并列出。h 与 ? 是这份帮助"
SECTIONS = (
    ("服务", (
        ("axs start", "sta", "启动服务"),
        ("axs stop", "sto", "停止服务"),
        ("axs restart", "re", "重启服务"),
        ("axs status", "s", "查看状态"),
        ("axs ensure", "e", "保证服务在跑"),
        ("axs service enable", "e", "打开开机自启"),
        ("axs service disable", "d", "关闭开机自启"),
    ), ("例：axs status",)),
    ("订阅", (
        ("axs sub get", "g", "查看订阅剩余"),
        ("axs sub refresh", "r", "拉取并重载"),
        ("axs sub clean", "c", "删除订阅缓存"),
    ), ("例：axs sub get",)),
    ("规则", (
        ("axs rule list", "l", "列出域名规则"),
        ("axs rule add via", "a", "经策略组，后接域名和组"),
        ("axs rule add direct", "", "直连，后接域名"),
        ("axs rule del", "d", "删除域名规则"),
    ), ("例：axs rule list",)),
    ("节点", (
        ("axs node groups", "g", "策略组与当前节点"),
        ("axs node list", "l", "节点列表"),
        ("axs node test", "t", "测延迟，可接组名"),
        ("axs node switch", "s", "切换节点，后接组和节点"),
    ), ("例：axs node list",)),
    ("网络", (
        ("axs net test", "t", "测连通，可接网址"),
        ("axs net ip", "i", "经代理查出口 IP"),
    ), ("例：axs net test",)),
    ("代理", (
        ("axs proxy user", "u", "当前 shell 环境（on|off|status）"),
        ("axs proxy system", "sy", "运行时 on|off；持久 enable|disable"),
        ("axs proxy session", "se", "登录持久 enable|disable|status"),
    ), (
        '例：eval "$(axs proxy user on)"',
    )),
    ("清理", (
        ("axs clean", "c", "删除本地配置，可加 --yes"),
    ), (
        "例：axs clean --yes",
        "颜色只是增强，管道或 NO_COLOR 下信息仍完整",
    )),
)


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


def row(cmd, alias, desc):
    return f"{ident(pad(cmd, 22))}  {dim(pad(alias, 6))}  {dim(desc)}"


def help_text():
    lines = [bold("用法"), bold(pad("命令", 22) + "  别名"), dim(INTRO)]
    for title, rows, notes in SECTIONS:
        lines.append("")
        lines.append(bold(title))
        lines.extend(row(cmd, alias, desc) for cmd, alias, desc in rows)
        lines.extend(dim(note) for note in notes)
    return "\n".join(lines) + "\n"


def _alias_marks(aliases):
    marks = {}
    for alias, command in aliases.items():
        if alias.isalnum() and alias in command and len(alias) > len(marks.get(command, "")):
            marks[command] = alias
    return marks


_USAGE_MARK = _alias_marks(TOP[1])


def _paint_marked(word, alias=None):
    if not alias or alias not in word:
        return bold(word)
    start = word.index(alias)
    end = start + len(alias)
    # A multi-letter prefix keeps the first letter command-bold: s**ta**rt, not **sta**rt.
    if len(alias) > 1 and start == 0:
        start = 1
    chunks = []
    if start:
        chunks.append(bold(word[:start]))
    chunks.append(emph("36", word[start:end]))
    if end < len(word):
        chunks.append(bold(word[end:]))
    return "".join(chunks)


def _usage_word(word, mark=True):
    if mark:
        return _paint_marked(word, _USAGE_MARK.get(word))
    return bold(word)


def _pipes(words, mark=True):
    return "|".join(_usage_word(word, mark) for word in words)


def usage_text():
    # Usage is stderr. Color follows that stream, not stdout.
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        lines = [
            "用法：axs " + _pipes(["start", "stop", "status", "restart", "ensure", "clean"]),
            "      axs " + _usage_word("service") + " " + _pipes(["enable", "disable"], False),
            "      axs " + _usage_word("sub") + " " + _pipes(["get", "refresh", "clean"]),
            "      axs " + _usage_word("rule") + " " + _pipes(["list", "add", "del"], False),
            "      axs " + _usage_word("node") + " " + _pipes(["groups", "list", "test", "switch"], False),
            "      axs " + _usage_word("net") + " " + _usage_word("test", False),
            "      axs "
            + _usage_word("proxy")
            + " "
            + _usage_word("user", False)
            + " "
            + _pipes(["on", "off", "status"], False)
            + "; "
            + _usage_word("system", False)
            + " "
            + _pipes(["on", "off", "enable", "disable", "status"], False)
            + "; "
            + _usage_word("session", False)
            + " "
            + _pipes(["enable", "disable", "status"], False),
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
        _usage()
    return name, argv[1:]


def _node(run, kind, args):
    from pathlib import Path

    from axs.config import SECRET, api_address, read_ports
    from axs.nodes import DELAY_URL, default_group, delay, select_proxy, show_groups, show_nodes, write_node_cache
    from axs.service import captured, service_up, write_cache
    import os
    if kind == "switch" and len(args) != 2:
        die(USAGE, "用法")
    if kind == "list":
        full = False
        for arg in args:
            if arg in ("--full", "-l"):
                full = True
            else:
                die(USAGE, "用法")
    if kind == "test":
        if not service_up(run):
            die(DOWN, "服务：未运行")
        _mixed, api = read_ports(run)
        group = args[0] if args else ""
        if not group:
            code, out = captured(default_group, Path(run) / SECRET, api)
            if code:
                raise SystemExit(code)
            group = out.strip("\n")
        if not group:
            die(FAIL, "组名不存在")
        url = os.environ.get("AXS_DELAY_URL") or DELAY_URL
        code, out = captured(delay, Path(run) / SECRET, api, group, url)
        sys.stdout.write(out)
        if code == 0:
            write_node_cache(Path(run) / "cache" / "node-test", group, out.splitlines())
            return
        write_cache(run, "node-test", "fail")
        raise SystemExit(code)
    if not service_up(run):
        die(DOWN, "服务：未运行")
    api = api_address(run)
    if not api:
        die(FAIL, "控制器")
    secret = Path(run) / SECRET
    if kind == "groups":
        show_groups(secret, api)
    elif kind == "list":
        show_nodes(secret, api, "--full" if full else str(run))
    else:
        select_proxy(secret, api, args[0], args[1], str(run))


def main(argv):
    from axs.net import net_ip, net_test
    from axs.proxy import proxy_session, proxy_system, proxy_user
    from axs.rules import cmd_add, cmd_del, cmd_list
    from axs.service import boot, clean, ensure, health, prime, restart, run_dir, start, status, stop
    from axs.subscription import refresh_run as _refresh, show_userinfo
    from axs.core import unix_now
    from axs.config import USERINFO
    from pathlib import Path

    prime()
    if not argv:
        _usage()
    cmd, rest = _take("top", argv)
    run = run_dir()
    if cmd == "help":
        if rest:
            _usage()
        sys.stdout.write(help_text())
        return
    if cmd == "start":
        start(run)
    elif cmd == "stop":
        stop(run)
    elif cmd == "restart":
        restart(run)
    elif cmd == "status":
        status(run)
    elif cmd == "health":
        health(run)
    elif cmd == "ensure":
        ensure(run, rest)
    elif cmd == "clean":
        clean(run, "config", rest)
    elif cmd == "service":
        op, extra = _take("service", rest)
        if extra:
            die(USAGE, "用法")
        boot(run, op)
    elif cmd == "sub":
        op, extra = _take("sub", rest)
        if op == "get":
            show_userinfo(Path(run) / USERINFO, unix_now())
        elif op == "refresh":
            _refresh(run)
        elif op == "clean":
            clean(run, "sub", extra)
        else:
            _usage()
    elif cmd == "rule":
        op, extra = _take("rule", rest)
        if op == "list":
            cmd_list(run)
        elif op == "add":
            cmd_add(run, extra)
        elif op == "del":
            cmd_del(run, extra)
        else:
            _usage()
    elif cmd == "node":
        op, extra = _take("node", rest)
        _node(run, op, extra)
    elif cmd == "net":
        op, extra = _take("net", rest)
        if op == "test":
            net_test(run, extra)
        elif op == "ip":
            net_ip(run, extra)
        else:
            _usage()
    elif cmd == "proxy":
        op, extra = _take("proxy", rest)
        {"user": proxy_user, "system": proxy_system, "session": proxy_session}[op](run, extra)
    else:
        _usage()
