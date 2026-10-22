"""Color and padding. Shell keeps its copy until the old file is removed."""
import os


def use_color(fd=1):
    mode = os.environ.get("AXS_COLOR")
    if mode == "always":
        return True
    if mode == "never":
        return False
    if "NO_COLOR" in os.environ:
        return False
    key = "AXS_TTY_ERR" if str(fd) == "2" else "AXS_TTY_OUT"
    return os.environ.get(key) == "1"


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


def paint(code, text):
    return tone(code, text)


def pad(text, width):
    # printf '%-Ns' counts bytes. A character pad would shift the Chinese header.
    gap = width - len(text.encode())
    if gap <= 0:
        return text
    return text + (" " * gap)
