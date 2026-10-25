"""Color and padding. Shell keeps its copy until the old file is removed."""
import os
import subprocess
import sys
import unicodedata


def use_color(fd=1):
    mode = os.environ.get("AXS_COLOR")
    if mode == "always":
        return True
    if mode == "never":
        return False
    if "NO_COLOR" in os.environ:
        return False
    key = "AXS_TTY_ERR" if str(fd) == "2" else "AXS_TTY_OUT"
    if key in os.environ:
        return os.environ.get(key) == "1"
    stream = sys.stderr if str(fd) == "2" else sys.stdout
    return stream.isatty()


def tone(code, text):
    fd = os.environ.get("AXS_PAINT_FD", "1")
    if use_color(fd):
        return f"\033[{code}m{text}\033[0m"
    return text


def label(text):
    return tone("90", text)


def ident(text):
    return tone("36", text)


def ok(text):
    return tone("32", text)


def warn(text):
    return tone("33", text)


def bad(text):
    return tone("31", text)


def dim(text):
    return tone("90", text)


def bold(text):
    return tone("1", text)


def emph(code, text):
    return tone(f"1;{code}", text)


def die(code, message):
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        text = bad(message)
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
    sys.stderr.write(text + "\n")
    raise SystemExit(code)



def pad(text, width):
    # printf '%-Ns' counts bytes. A character pad would shift the Chinese header.
    gap = width - len(text.encode())
    if gap <= 0:
        return text
    return text + (" " * gap)

def display_width(text):
    # shortcut: 制表符和组合字符按 1 列，名称里出现再改
    return sum(2 if unicodedata.east_asian_width(char) in ("W", "F") else 1 for char in text)

def term_cols():
    raw = os.environ.get("COLUMNS", "").strip()
    if raw.isdigit() and int(raw) > 0:
        return int(raw)
    try:
        out = subprocess.check_output(
            ["tput", "cols"], stderr=subprocess.DEVNULL, text=True, timeout=2
        ).strip()
    except (OSError, subprocess.SubprocessError, ValueError):
        out = ""
    if out.isdigit() and int(out) > 0:
        return int(out)
    return 80

def layout_cells(entries, width):
    if not entries:
        return []
    widest = max(display_width(plain) for plain, _ in entries)
    cols = max(1, (width + 2) // (widest + 2))
    lines = []
    row = []
    for index, item in enumerate(entries, 1):
        row.append(item)
        if len(row) != cols and index != len(entries):
            continue
        pieces = []
        for pos, (plain, colored) in enumerate(row):
            pad = ""
            if pos != len(row) - 1:
                pad = " " * (widest - display_width(plain))
            pieces.append(colored + pad)
        lines.append("  ".join(pieces))
        row = []
    return lines


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
        ("axs subscription show", "s", "流量与到期"),
        ("axs subscription refresh", "r", "拉取并重载"),
        ("axs subscription clean", "c", "删除订阅缓存"),
    ), ()),
    ("规则（rule / r）", (
        ("axs rule show", "s", "按顺序编号；来源 prepend/local/provider；--local 只看本地"),
        ("axs rule add via", "v", "域名 + 组"),
        ("axs rule add direct", "d", "域名"),
        ("axs rule add node", "n", "域名 + 节点"),
        ("axs rule del", "d", "删除域名规则"),
    ), ()),
    ("节点（node / n）", (
        ("axs node show", "s", "--full 树；--select 规则入口/成员引用，每组一次，自动组为终端；--flat；--depth"),
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


