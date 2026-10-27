"""Command tree. Data only: no parsing, dispatch, or layout."""

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
        "nw": "network",
        "c": "clean",
        "h": "help",
        "?": "help",
        "--help": "help",
        "-h": "help",
        "health": "health",
        "k": "health",
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
    "node": ("status show".split(), {"s": "status", "sh": "show"}),
    "group": ("status members switch test".split(), {"s": "status", "sw": "switch", "m": "members", "t": "test"}),
    "rule": ("status show add del".split(), {"s": "status", "sh": "show", "a": "add", "d": "del"}),
    "subscription": ("status refresh clean".split(), {"s": "status", "r": "refresh", "c": "clean"}),
    "network": ("test ip".split(), {"t": "test", "i": "ip"}),
    "proxy": ("status user system session".split(), {"s": "status", "u": "user", "sy": "system", "se": "session"}),
}

INTRO = "单字符优先；冲突用两字母；前缀亦可"

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
        ("axs subscription status", "s", "流量与到期"),
        ("axs subscription refresh", "r", "拉取并重载"),
        ("axs subscription clean", "c", "删除订阅缓存"),
    ), ()),
    ("规则（rule / r）", (
        ("axs rule status", "s", "规则路径，不含成员"),
        ("axs rule show", "sh", "按顺序编号；来源 prepend/local/provider；--local 只看本地"),
        ("axs rule add via", "v", "域名 + 组"),
        ("axs rule add direct", "d", "域名"),
        ("axs rule add node", "n", "域名 + 节点"),
        ("axs rule del", "d", "<域名|RID|规则全文>"),
    ), ()),
    ("节点（node / n）", (
        ("axs node status", "s", "当前规则路径与末端组"),
        ("axs node show", "sh", "--all 全量叶子；--full 树；--depth"),
    ), ()),
    ("组（group / g）", (
        ("axs group status", "s", "策略组与当前节点"),
        ("axs group members", "m", "组成员：编号、类型、当前、延迟"),
        ("axs group switch", "sw", "组号或组名，再接节点"),
        ("axs group test", "t", "测延迟，可接组号或组名"),
    ), ()),
    ("网络（network）", (
        ("axs network test", "t", "测连通，可接网址"),
        ("axs network ip", "i", "经代理查出口 IP"),
    ), ()),
    ("代理（proxy / p）", (
        ("axs proxy status", "s", "三层汇总"),
        ("axs proxy user", "u", "当前 shell 环境（on|off|status）"),
        ("axs proxy system", "sy", "运行时 on|off；持久 enable|disable"),
        ("axs proxy session", "se", "登录持久 enable|disable|status"),
    ), ()),
    ("清理（clean / c）", (
        ("axs clean", "c", "删除本地配置，可加 --yes"),
    ), ()),
)

# (最少位置参数, 最多位置参数或 None, 旗标, 是否隐藏)。旗标以 = 结尾还要吃下一个词，以 ! 结尾则帮助不列。
SIG = {
    "top": {
        "status": (0, 0, (), False), "clean": (0, 0, ("--yes",), False),
        "help": (0, 0, (), False), "health": (0, 0, (), True),
    },
    "service": {
        "status": (0, 0, (), False), "start": (0, 0, (), False), "stop": (0, 0, (), False), "restart": (0, 0, (), False),
        "ensure": (0, 0, (), False), "enable": (0, 0, (), False), "disable": (0, 0, (), False), "health": (0, 0, (), True),
    },
    "node": {
        "status": (0, 0, (), False),
        "show": (0, 0, ("--full", "--all", "--flat!", "-l!", "--depth="), False),
    },
    "group": {
        "status": (0, 0, (), False), "members": (1, 1, (), False),
        "switch": (2, 2, (), False), "test": (0, 1, (), False),
    },
    "rule": {
        "status": (0, 0, (), False), "show": (0, 0, ("--local",), False),
        "add": (2, 3, (), False), "del": (1, 1, (), False),
    },
    "subscription": {
        "status": (0, 0, (), False), "refresh": (0, 0, (), False), "clean": (0, 0, ("--yes",), False),
    },
    "network": {"test": (0, None, (), False), "ip": (0, 0, (), False)},
    "proxy": {
        "status": (0, 0, (), False), "user": (1, 1, (), False),
        "system": (1, 1, (), False), "session": (1, 1, (), False),
    },
}

# 带参或带旗标命令的一行用法：(命令, 说明)。零参命令由分发拼接。
USE = {
    ("top", "clean"): ("axs clean", "[--yes]"), ("subscription", "clean"): ("axs subscription clean", "[--yes]"),
    ("node", "show"): ("axs node show", "[--full|--all] [--depth N]"),
    ("group", "members"): ("axs group members", "<组>（先看 group status）"), ("group", "switch"): ("axs group switch", "<组> <成员>"), ("group", "test"): ("axs group test", "[组]"),
    ("rule", "show"): ("axs rule show", "[--local]"), ("rule", "add"): ("axs rule add", "direct|via|node <域名> [组或节点]"), ("rule", "del"): ("axs rule del", "<域名|RID|规则全文>"),
    ("network", "test"): ("axs network test", "[网址 ...]"),
    ("proxy", "user"): ("axs proxy user", "on|off|status"), ("proxy", "system"): ("axs proxy system", "on|off|enable|disable|status"),
    ("proxy", "session"): ("axs proxy session", "enable|disable|status"),
}
