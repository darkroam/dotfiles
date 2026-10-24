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
    "status service node group rule subscription network proxy clean help".split(),
    {
        "s": "status",
        "se": "service",
        "n": "node",
        "g": "group",
        "r": "rule",
        "su": "subscription",
        "p": "proxy",
        "c": "clean",
        "h": "help",
        "?": "help",
        "--help": "help",
        "-h": "help",
    },
)
GROUPS = {
    "top": TOP,
    "service": (
        "status start stop restart ensure enable disable health".split(),
        {
            "s": "status",
            "sta": "start",
            "sto": "stop",
            "re": "restart",
            "e": "ensure",
            "en": "enable",
            "di": "disable",
            "he": "health",
        },
    ),
    "node": ("show".split(), {"s": "show"}),
    "group": ("show members switch test".split(), {"s": "show", "sw": "switch", "m": "members", "t": "test"}),
    "rule": ("show add del".split(), {"s": "show", "a": "add", "d": "del"}),
    "subscription": ("show refresh clean".split(), {"s": "show", "r": "refresh", "c": "clean"}),
    "network": ("test ip".split(), {"t": "test", "i": "ip"}),
    "proxy": ("user system session".split(), {"u": "user", "sy": "system", "se": "session"}),
}

INTRO = "单字符优先；冲突用两字母；前缀亦可"
EXAMPLE = '示例：axs s · axs n s · axs p sy on · eval "$(axs p u on)"'
SECTIONS = (
    ("服务（service / se）", (
        ("axs status", "s", "查看全部状态"),
        ("axs service status", "s", "状态、自启、端口、控制器"),
        ("axs service start", "sta", "启动服务"),
        ("axs service stop", "sto", "停止服务"),
        ("axs service restart", "re", "重启服务"),
        ("axs service ensure", "e", "保证服务在跑"),
        ("axs service enable", "en", "打开开机自启"),
        ("axs service disable", "di", "关闭开机自启"),
    ), ()),
    ("订阅（subscription / su）", (
        ("axs subscription show", "s", "查看订阅剩余"),
        ("axs subscription refresh", "r", "拉取并重载"),
        ("axs subscription clean", "c", "删除订阅缓存"),
    ), ()),
    ("规则（rule / r）", (
        ("axs rule show", "s", "运行时规则；--local 只看本地"),
        ("axs rule add via", "a", "域名 + 组"),
        ("axs rule add direct", "", "域名"),
        ("axs rule del", "d", "删除域名规则"),
    ), ()),
    ("节点（node / n）", (
        ("axs node show", "s", "--full|--select 树（--depth），--flat 表"),
    ), ()),
    ("组（group / g）", (
        ("axs group show", "s", "策略组与当前节点"),
        ("axs group members", "m", "组成员：编号、类型、当前、延迟"),
        ("axs group switch", "sw", "组号或组名，再接节点"),
        ("axs group test", "t", "测延迟，可接组号或组名"),
    ), ()),
    ("网络（network）", (
        ("axs network test", "t", "测连通，可接网址"),
        ("axs network ip", "i", "经代理查出口 IP"),
    ), ()),
    ("代理（proxy / p）", (
        ("axs proxy user", "u", "当前 shell 环境（on|off|status）"),
        ("axs proxy system", "sy", "运行时 on|off；持久 enable|disable"),
        ("axs proxy session", "se", "登录持久 enable|disable|status"),
    ), ()),
    ("清理（clean / c）", (
        ("axs clean", "c", "删除本地配置，可加 --yes"),
    ), ()),
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
    return f"{ident(pad(cmd, 24))}  {dim(pad(alias, 6))}  {dim(desc)}"


def help_text():
    lines = [bold("用法"), bold(pad("命令", 24) + "  别名"), dim(INTRO)]
    for title, rows, notes in SECTIONS:
        lines.append("")
        lines.append(bold(title))
        lines.extend(row(cmd, alias, desc) for cmd, alias, desc in rows)
        lines.extend(dim(note) for note in notes)
    lines.append(dim(EXAMPLE))
    return "\n".join(lines) + "\n"


def _alias_marks(aliases):
    marks = {}
    for alias, command in aliases.items():
        if alias.isalnum() and alias in command and len(alias) > len(marks.get(command, "")):
            marks[command] = alias
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
        alias = _alias_marks(GROUPS[group][1]).get(word)
    return _paint_marked(word, alias)


def _pipes(words, group=None):
    return "|".join(_usage_word(word, group) for word in words)


def usage_text():
    # Usage is stderr. Color follows that stream, not stdout.
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        flags = "|".join(_usage_word(flag) for flag in ("--full", "--select", "--flat"))
        lines = [
            "用法：axs " + _pipes(["status", "clean", "help"], "top"),
            "      axs " + _usage_word("service", "top") + " " + _pipes(["status", "start", "stop", "restart", "ensure", "enable", "disable"], "service"),
            "      axs " + _usage_word("subscription", "top") + " " + _pipes(["show", "refresh", "clean"], "subscription"),
            "      axs " + _usage_word("rule", "top") + " " + _pipes(["show", "add", "del"], "rule"),
            "      axs " + _usage_word("node", "top") + " " + _usage_word("show", "node") + " " + flags + " " + _usage_word("--depth") + " N",
            "      axs " + _usage_word("group", "top") + " " + _pipes(["show", "members", "switch", "test"], "group"),
            "      axs " + _usage_word("network", "top") + " " + _pipes(["test", "ip"], "network"),
            "      axs "
            + _usage_word("proxy", "top")
            + " "
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



def _list_flags(args):
    mode = ""
    depth = None
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in ("--full", "--flat", "-l", "--select"):
            if mode:
                die(USAGE, "用法错误")
            mode = "flat" if arg in ("--flat", "-l") else "select" if arg == "--select" else "full"
            index += 1
            continue
        if arg != "--depth":
            die(USAGE, "用法错误")
        if depth is not None or index + 1 >= len(args):
            die(USAGE, "用法错误")
        token = args[index + 1]
        if not (token.isascii() and token.isdigit() and str(int(token)) == token and int(token) >= 1):
            die(USAGE, "用法错误")
        depth = int(token)
        index += 2
    if depth is not None and mode not in ("full", "select"):
        die(USAGE, "用法错误")
    return mode, depth


def _proxies(secret, api):
    from axs.nodes import load_proxies

    try:
        return load_proxies(secret, api)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
        raise SystemExit(FAIL if code == USAGE else code)


def _show_tree(secret, api, mode, depth):
    from axs.tree import render_tree

    sys.stdout.write(render_tree(_proxies(secret, api), depth, mode=mode, origin=secret))


def _node(run, kind, args):
    from pathlib import Path

    from axs.config import SECRET, api_address, read_ports
    from axs.nodes import DELAY_URL, default_group, delay, lookup_group, select_proxy, show_groups, show_nodes, write_node_cache
    from axs.service import captured, service_up, write_cache
    import os
    if kind == "groups" and args:
        die(USAGE, "用法错误")
    if kind == "members" and (len(args) != 1 or args[0].startswith("-")):
        die(USAGE, "用法错误，先看 group show" if not args else "用法错误")
    if kind == "test" and len(args) > 1:
        die(USAGE, "用法错误")
    if kind == "switch" and len(args) != 2:
        die(USAGE, "用法错误，用 group members 查看成员" if len(args) < 2 else "用法错误")
    list_mode, depth = "", None
    if kind == "list":
        list_mode, depth = _list_flags(args)
    if kind == "test":
        if not service_up(run):
            die(DOWN, "服务：未运行")
        _mixed, api = read_ports(run)
        secret_path = Path(run) / SECRET
        group = args[0] if args else ""
        if group:
            code, out = captured(lookup_group, secret_path, api, group)
        else:
            code, out = captured(default_group, secret_path, api)
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
        die(FAIL, "控制器失败")
    secret = Path(run) / SECRET
    if kind == "groups":
        show_groups(secret, api)
    elif kind == "list":
        if list_mode in ("full", "select"):
            _show_tree(secret, api, list_mode, depth)
        elif list_mode == "flat":
            show_nodes(secret, api, "flat")
        else:
            show_nodes(secret, api, str(run))
    elif kind == "members":
        from axs.tree import show_members

        show_members(_proxies(secret, api), args[0], str(run))
    else:
        select_proxy(secret, api, args[0], args[1], str(run))


def main(argv):
    from axs.net import net_ip, net_test
    from axs.proxy import proxy_session, proxy_system, proxy_user
    from axs.rules import cmd_add, cmd_del, cmd_list
    from axs.service import boot, clean, ensure, health, prime, restart, run_dir, service_status, start, status, stop
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
    if cmd == "status":
        status(run)
    elif cmd == "clean":
        clean(run, "config", rest)
    elif cmd == "service":
        op, extra = _take("service", rest)
        if op == "ensure":
            ensure(run, extra)
        elif extra:
            die(USAGE, "用法错误")
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
    elif cmd == "subscription":
        op, extra = _take("subscription", rest)
        if op == "show":
            show_userinfo(Path(run) / USERINFO, unix_now())
        elif op == "refresh":
            _refresh(run)
        elif op == "clean":
            clean(run, "sub", extra)
        else:
            _usage()
    elif cmd == "rule":
        op, extra = _take("rule", rest)
        if op == "show":
            if extra not in ([], ["--local"]):
                die(USAGE, "用法错误")
            cmd_list(run, extra == ["--local"])
        elif op == "add":
            cmd_add(run, extra)
        elif op == "del":
            cmd_del(run, extra)
        else:
            _usage()
    elif cmd == "node":
        if not rest:
            _node(run, "list", [])
        else:
            _op, extra = _take("node", rest)
            _node(run, "list", extra)
    elif cmd == "group":
        op, extra = _take("group", rest)
        kind = {"show": "groups", "members": "members", "switch": "switch", "test": "test"}[op]
        _node(run, kind, extra)
    elif cmd == "network":
        op, extra = _take("network", rest)
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
