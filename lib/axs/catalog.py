"""Command tree. Data only: no parsing, dispatch, or layout."""

from axs.sections import SECTIONS

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
    "node": ("status show test".split(), {"s": "status", "sh": "show", "t": "test"}),
    "group": ("status members switch test".split(), {"s": "status", "sw": "switch", "m": "members", "t": "test"}),
    "rule": ("status show add del".split(), {"s": "status", "sh": "show", "a": "add", "d": "del"}),
    "subscription": ("status show add rm switch refresh clean".split(), {"s": "status", "sh": "show", "a": "add", "rm": "rm", "sw": "switch", "r": "refresh", "c": "clean"}),
    "network": ("test ip".split(), {"t": "test", "i": "ip"}),
    "proxy": ("status user system session".split(), {"s": "status", "u": "user", "sy": "system", "se": "session"}),
}

INTRO = "单字符优先；冲突用两字母；前缀亦可"

# (最少位置参数, 最多位置参数或 None, 旗标, 是否隐藏)。旗标以 = 结尾还要吃下一个词，以 ! 结尾则帮助不列。
SIG = {
    "top": {
        "status": (0, 0, (), False), "clean": (0, 0, ("--yes",), False),
        "help": (0, 0, ("-v", "--verbose"), False), "health": (0, 0, (), True),
    },
    "service": {
        "status": (0, 0, (), False), "start": (0, 0, (), False), "stop": (0, 0, (), False), "restart": (0, 0, (), False),
        "ensure": (0, 0, (), False), "enable": (0, 0, (), False), "disable": (0, 0, (), False), "health": (0, 0, (), True),
    },
    "node": {
        "status": (0, 0, (), False),
        "show": (0, 0, ("--full", "--all", "--flat!", "-l!", "--depth="), False),
        "test": (0, 1, ("--all",), False),
    },
    "group": {
        "status": (0, 0, (), False), "members": (1, 1, (), False),
        "switch": (2, 2, (), False), "test": (0, 1, ("--all",), False),
    },
    "rule": {
        "status": (0, 0, (), False), "show": (0, 0, ("--local",), False),
        "add": (2, 3, (), False), "del": (1, 1, (), False),
    },
    "subscription": {
        "status": (0, 0, (), False), "show": (0, 0, (), False), "add": (1, 1, (), False),
        "rm": (1, 1, (), False), "switch": (1, 1, (), False), "refresh": (0, 0, (), False), "clean": (0, 0, ("--yes",), False),
    },
    "network": {"test": (0, None, (), False), "ip": (0, 0, (), False)},
    "proxy": {
        "status": (0, 0, (), False), "user": (1, 1, (), False),
        "system": (1, 1, (), False), "session": (1, 1, (), False),
    },
}

# 带参或带旗标命令的一行用法：(命令, 说明)。零参命令由分发拼接。
USE = {
    ("top", "clean"): ("axs clean", "[--yes]"), ("top", "help"): ("axs help", "[-v|--verbose]"),
    ("subscription", "add"): ("axs subscription add", "<URL>"), ("subscription", "rm"): ("axs subscription rm", "<S#>"), ("subscription", "switch"): ("axs subscription switch", "<S#>"), ("subscription", "clean"): ("axs subscription clean", "[--yes]"),
    ("node", "show"): ("axs node show", "[--full|--all] [--depth N]"),
    ("node", "test"): ("axs node test", "<名称|N#>|--all"),
    ("group", "members"): ("axs group members", "<组>（先看 group status）"), ("group", "switch"): ("axs group switch", "<组> <成员>"), ("group", "test"): ("axs group test", "<名称|G#>|--all"),
    ("rule", "show"): ("axs rule show", "[--local]"), ("rule", "add"): ("axs rule add", "direct|via|node <域名> [组或节点]"), ("rule", "del"): ("axs rule del", "<域名|RID|规则全文>"),
    ("network", "test"): ("axs network test", "[网址 ...]"),
    ("proxy", "user"): ("axs proxy user", "on|off|status"), ("proxy", "system"): ("axs proxy system", "on|off|enable|disable|status"),
    ("proxy", "session"): ("axs proxy session", "enable|disable|status"),
}

MORE = (
    ("health / k", "顶级隐藏健康检查"),
    ("service health / he", "只报失败一行"),
    ("node show --flat / -l", "机器可读 TSV"),
)
RETIRED = (
    ("node show", "node status", "当前路径与末端组"),
    ("--select", "node show", "可选树"),
    ("group show", "group status", "策略组与当前选择"),
    ("rule show status", "rule status", "当前规则路径"),
)
