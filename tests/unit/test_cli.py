#!/usr/bin/env python3
"""Alias order and the three help/usage snapshots, imported directly."""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.cli import DOWN, EXPIRED, FAIL, GROUPS, LOCK, ResolveError, USAGE, help_text, resolve_token, usage_text
from axs.render import bad, bold, dim, display_width, emph, ident, label, ok, tone, use_color, warn

GOLDEN = ROOT / "tests" / "golden"
EXACT = (
    ("s", "top", "status"),
    ("status", "top", "status"),
    ("sta", "top", "start"),
    ("sto", "top", "stop"),
    ("su", "top", "sub"),
    ("se", "top", "service"),
    ("he", "top", "health"),
    ("h", "top", "help"),
    ("?", "top", "help"),
    ("--help", "top", "help"),
    ("-h", "top", "help"),
    ("ne", "top", "net"),
    ("re", "top", "restart"),
    ("ens", "top", "ensure"),
    ("stat", "top", "status"),
    ("n", "top", "node"),
    ("node", "top", "node"),
    ("g", "node", "groups"),
    ("gro", "node", "groups"),
    ("sy", "proxy", "system"),
    ("se", "proxy", "session"),
    ("ge", "sub", "get"),
)
AMBIGUOUS = (
    ("st", "top", "候选：start stop status"),
    ("s", "proxy", "候选：system session"),
)
UNKNOWN = (
    ("nope", "top"),
    ("x", "top"),
    ("o", "top"),
    ("k", "top"),
    ("u", "top"),
    ("st", "proxy"),
)


def resolve(word, group):
    words, aliases = GROUPS[group]
    return resolve_token(word, words, aliases)


def golden(name):
    text = (GOLDEN / name).read_text(encoding="utf-8")
    head, rest = text.split("\n--- stdout\n", 1)
    stdout, stderr = rest.split("--- stderr\n", 1)
    return int(head.split(": ", 1)[1]), stdout, stderr


def check_color():
    saved = {key: os.environ.get(key) for key in ("AXS_COLOR", "NO_COLOR", "AXS_TTY_OUT", "AXS_TTY_ERR", "AXS_PAINT_FD")}
    try:
        os.environ["AXS_COLOR"] = "always"
        os.environ.pop("NO_COLOR", None)
        assert tone("32", "on") == "\033[32mon\033[0m"
        assert ok("on") == "\033[32mon\033[0m"
        assert warn("mid") == "\033[33mmid\033[0m"
        assert bad("off") == "\033[31moff\033[0m"
        assert label("k") == dim("k") == "\033[90mk\033[0m"
        assert ident("axs") == "\033[36maxs\033[0m"
        assert bold("用法") == "\033[1m用法\033[0m"
        assert emph("32", "on") == "\033[1;32mon\033[0m"
        os.environ["NO_COLOR"] = "1"
        assert bold("用法") == "\033[1m用法\033[0m"
        os.environ["AXS_COLOR"] = "never"
        assert ok("on") == "on"
        os.environ.pop("AXS_COLOR")
        os.environ.pop("NO_COLOR")
        os.environ["AXS_TTY_OUT"] = "0"
        os.environ["AXS_TTY_ERR"] = "1"
        os.environ["AXS_PAINT_FD"] = "1"
        assert bad("e") == "e"
        os.environ["AXS_PAINT_FD"] = "2"
        assert bad("e") == "\033[31me\033[0m"
        for key in ("AXS_COLOR", "NO_COLOR", "AXS_TTY_OUT", "AXS_TTY_ERR", "AXS_PAINT_FD"):
            os.environ.pop(key, None)

        class _TTY:
            def __init__(self, yes):
                self.yes = yes

            def isatty(self):
                return self.yes

        real_out, real_err = sys.stdout, sys.stderr
        try:
            sys.stdout, sys.stderr = _TTY(True), _TTY(False)
            if use_color(1) is not True or use_color(2) is not False:
                raise SystemExit("isatty fallback")
            sys.stdout, sys.stderr = _TTY(False), _TTY(True)
            if use_color(1) is not False or use_color(2) is not True:
                raise SystemExit("isatty fallback swapped")
            os.environ["AXS_TTY_OUT"] = "0"
            if use_color(1) is not False:
                raise SystemExit("tty flag beats isatty")
        finally:
            sys.stdout, sys.stderr = real_out, real_err
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def main():
    for word, group, want in EXACT:
        got = resolve(word, group)
        if got != want:
            raise SystemExit(f"{group} {word!r} -> {got!r}, want {want!r}")
    for word, group, message in AMBIGUOUS:
        try:
            resolve(word, group)
        except ResolveError as exc:
            if exc.code != 1 or exc.message != message:
                raise SystemExit(f"{group} {word!r} ambiguous {exc.code} {exc.message!r}") from exc
        else:
            raise SystemExit(f"{group} {word!r} should be ambiguous")
    for word, group in UNKNOWN:
        try:
            resolve(word, group)
        except ResolveError as exc:
            if exc.code != 2 or exc.message:
                raise SystemExit(f"{group} {word!r} unknown {exc.code} {exc.message!r}") from exc
        else:
            raise SystemExit(f"{group} {word!r} should be unknown")
    os.environ["AXS_COLOR"] = "never"
    checks = (
        ("help--default.txt", 0, help_text(), ""),
        ("usage--bare.txt", 1, "", usage_text()),
        ("usage--unknown.txt", 1, "", usage_text()),
    )
    for name, code, stdout, stderr in checks:
        got_code, got_out, got_err = golden(name)
        if (got_code, got_out, got_err) != (code, stdout, stderr):
            raise SystemExit(f"golden {name} mismatch")
    help_plain = help_text()
    if "分五节" in help_plain or "会话 effect" in help_plain or "已移除" in help_plain:
        raise SystemExit("help still has internal notes")
    if "a       直连" in help_plain:
        raise SystemExit("direct still repeats alias a")
    if "颜色只是增强" in help_plain or "\n例：" in help_plain:
        raise SystemExit("help still has redundant lines")
    if "单字符优先；冲突用两字母；前缀亦可" not in help_plain:
        raise SystemExit("help intro")
    if '示例：axs s · axs n l · axs p sy on' not in help_plain:
        raise SystemExit("help example")
    os.environ["AXS_COLOR"] = "always"
    colored = usage_text()
    os.environ["AXS_COLOR"] = "never"
    plain = usage_text()
    import re
    stripped = re.sub(r"\033\[[0-9;]*m", "", colored)
    if stripped != plain or plain.count("\n") != 7:
        raise SystemExit("usage highlight changed the plain text")
    if (USAGE, DOWN, FAIL, LOCK, EXPIRED) != (1, 2, 3, 4, 5):
        raise SystemExit("exit codes")
    if display_width("a中") != 3:
        raise SystemExit("display width")
    if "\033[36m[x]\033[0m" in colored:
        raise SystemExit("start marker")
    if "\033[1ms\033[0m\033[1;36mta\033[0m\033[1mrt\033[0m" not in colored:
        raise SystemExit("start alias")
    if "\033[1ms\033[0m\033[1;36mto\033[0m\033[1mp\033[0m" not in colored:
        raise SystemExit("stop alias")
    if "\033[1;36ms\033[0m\033[1mtatus\033[0m" not in colored:
        raise SystemExit("status letter")
    if "\033[1;36m" in colored.split("roxy", 1)[1]:
        raise SystemExit("proxy line marked a command alias")
    check_color()
    print(f"alias matrix {len(EXACT) + len(AMBIGUOUS) + len(UNKNOWN)}; help golden 3")
    return 0


if __name__ == "__main__":
    sys.exit(main())
