"""Command words, aliases, and the help text they print."""
from axs.render import bold, dim, ident, pad


class ResolveError(Exception):
    def __init__(self, code, message=""):
        self.code = code
        self.message = message


TOP = (
    "start stop status restart health ensure clean help service sub rule node net proxy".split(),
    {
        "s": "status",
        "n": "node",
        "p": "proxy",
        "r": "rule",
        "u": "sub",
        "c": "clean",
        "e": "ensure",
        "h": "help",
        "?": "help",
        "k": "health",
        "x": "start",
        "o": "stop",
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
    "proxy": ("user system session".split(), {"u": "user", "s": "system", "e": "session"}),
}

USAGE = """\
用法：axs start|stop|status|restart|ensure|clean
      axs service enable|disable
      axs sub get|refresh|clean
      axs rule list|add|del
      axs node groups|list|test|switch
      axs net test
      axs proxy user on|off|status; system on|off|enable|disable|status; session enable|disable|status
"""

INTRO = "单字符精确优先；未命中则唯一前缀。多个候选退出 1 并列出。h 与 ? 是这份帮助"
SECTIONS = (
    ("服务", (
        ("axs start", "x", "启动服务"),
        ("axs stop", "o", "停止服务"),
        ("axs restart", "-", "重启服务"),
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
        ("axs rule add direct", "a", "直连，后接域名"),
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
        ("axs proxy system", "s", "运行时 on|off；持久 enable|disable"),
        ("axs proxy session", "e", "登录持久 enable|disable|status"),
    ), (
        "status 分五节：服务、节点、订阅、测试、代理。标签对齐，节标题加粗",
        "会话 effect：active、pending、-、no-x-session。persist disabled 时 effect 为 -",
        "session 的 on|off 已移除，改用 enable|disable。system on 不再写标识开关",
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


def usage_text():
    return USAGE
