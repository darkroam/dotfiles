"""Color and padding. Shell keeps its copy until the old file is removed."""
import os
import subprocess
import sys
import unicodedata

from axs.catalog import GROUPS, INTRO, MORE, RETIRED, SECTIONS, SIG, USE


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

PATH_TITLE = "当前规则路径："


def section_title(text):
    return bold(text)


def view_note(text):
    return dim(text)


def view_page(path_body, blocks, note):
    body = path_body.strip("\n")
    head = section_title(PATH_TITLE)
    parts = [head if not body else head + "\n" + body]
    for title, block in blocks:
        shown = block.strip("\n")
        title = section_title(title)
        parts.append(title if not shown else title + "\n" + shown)
    parts.append(view_note(note))
    return "\n\n".join(parts) + "\n"


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


EXAMPLE = '示例：axs s · axs n s · axs p sy on · eval "$(axs p u on)"'


def row(cmd, alias, desc):
    return f"{ident(pad(cmd, 24))}  {dim(pad(alias, 6))}  {dim(desc)}"


def layer_text(group):
    lines = []
    for _title, rows, _notes in SECTIONS:
        for cmd, _alias, desc in rows:
            parts = cmd.split()
            if len(parts) >= 3 and parts[1] == group:
                lines.append(f"{cmd}  {desc}")
    return "\n".join(lines) + "\n"


def help_text(verbose=False):
    lines = [bold("用法"), bold(pad("命令", 24) + "  别名"), dim(INTRO)]
    for title, rows, notes in SECTIONS:
        lines.append("")
        lines.append(bold(title))
        lines.extend(row(cmd, alias, desc) for cmd, alias, desc in rows)
        lines.extend(dim(note) for note in notes)
    lines.append(dim(EXAMPLE))
    tail = ["", "更多入口", *MORE, "", "退役名", *RETIRED] if verbose else ["更多入口：axs help --verbose"]
    lines.extend(dim(line) if line else line for line in tail)
    return "\n".join(lines) + "\n"




def call_usage(group, name):
    item = USE.get((group, name))
    if item:
        return "用法：" + bold(item[0]) + " " + dim(item[1])
    text = name if group == "top" else group + " " + name
    return "用法：" + bold("axs " + text)


def option_error(arg, shown):
    text = " ".join(shown) if shown else "（无）"
    return "未知选项：" + bold(arg) + "\n旗标：" + dim(text)


def command_error(group, word):
    words = [item for item in GROUPS[group][0] if not SIG[group][item][3]]
    lines = ["未知命令：" + bold(word) + dim("（属于 " + group + "）")]
    for item in words:
        desc = ""
        prefix = "axs " + group + " " + item
        for _title, rows, _notes in SECTIONS:
            for cmd, _alias, text in rows:
                if cmd == prefix or cmd.startswith(prefix + " "):
                    desc = text
                    break
            if desc:
                break
        lines.append(bold(item) + "  " + dim(desc))
    lines.append("用法：axs " + bold(group) + " " + bold("|".join(words)))
    return "\n".join(lines)
