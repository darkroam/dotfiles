#!/usr/bin/env python3
"""Alias order and the three help/usage snapshots, imported directly."""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.cli import (
    DOWN, EXPIRED, FAIL, GROUPS, LOCK, ResolveError, SECTIONS, USAGE,
    _alias_marks, _list_flags, _usage_word, help_text, main as cli_main, resolve_token, usage_text,
)
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
    ("m", "node", "members"),
    ("mem", "node", "members"),
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



def marked(alias, rest):
    return emph("36", alias) + (bold(rest) if rest else "")


def check_usage_color(colored):
    os.environ["AXS_COLOR"] = "always"
    lines = colored.splitlines()
    if len(lines) != 7:
        raise SystemExit("usage lines")
    expect = {
        0: ("sta rt", "sto p", "s tatus", "re start", "e nsure", "c lean"),
        1: ("se rvice", "e nable", "d isable"),
        2: ("su b", "g et", "r efresh", "c lean"),
        3: ("r ule", "l ist", "a dd", "d el"),
        4: ("n ode", "g roups", "m embers", "l ist", "t est", "s witch"),
        5: ("ne t", "t est"),
        6: ("p roxy", "u ser", "sy stem", "se ssion"),
    }
    for index, pairs in expect.items():
        for pair in pairs:
            alias, rest = pair.split(" ", 1)
            if marked(alias, rest) not in lines[index]:
                raise SystemExit(f"line {index} missing {alias}")
    health = _usage_word("health", "top")
    help_word = _usage_word("help", "top")
    if health != marked("he", "alth") or help_word != marked("h", "elp"):
        raise SystemExit("quiet top alias")
    actions = bold("on") + "|" + bold("off") + "|" + bold("status")
    if actions not in lines[6] or marked("s", "tatus") in lines[6]:
        raise SystemExit("proxy actions")
    if bold("enable") not in lines[6]:
        raise SystemExit("system enable should stay bold")


def check_help_aliases():
    shown = {}
    for _title, rows, _notes in SECTIONS:
        for cmd, alias, _desc in rows:
            parts = cmd.split()
            group, word = ("top", parts[1]) if len(parts) == 2 else (parts[1], parts[2])
            shown.setdefault((group, word), set()).add(alias)
    for key, aliases in shown.items():
        group, word = key
        expect = _alias_marks(GROUPS[group][1]).get(word, "")
        nonempty = {item for item in aliases if item}
        if expect and nonempty != {expect}:
            raise SystemExit(f"help alias {group} {word}")
        if not expect and nonempty:
            raise SystemExit(f"help extra alias {group} {word}")



def check_help_heads(help_plain):
    heads = (
        ("服务", "service"),
        ("订阅", "sub"),
        ("规则", "rule"),
        ("节点", "node"),
        ("网络", "net"),
        ("代理", "proxy"),
        ("清理", "clean"),
    )
    marks = _alias_marks(GROUPS["top"][1])
    titles = [item[0] for item in SECTIONS]
    if len(titles) != len(heads):
        raise SystemExit("help section count")
    for (zh, command), title in zip(heads, titles):
        want = f"{zh}（{command} / {marks[command]}）"
        if title != want or title not in help_plain.splitlines():
            raise SystemExit("help head " + want)
    for line in help_plain.splitlines():
        if not line.startswith("axs "):
            continue
        if line[22:24] != "  " or line[30:32] != "  ":
            raise SystemExit("help columns " + line)



def check_node_args():
    import contextlib
    import io
    import tempfile

    os.environ["AXS_COLOR"] = "never"
    os.environ["AXS_SYSTEMD"] = "0"
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            _list_flags(["nope"])
    except SystemExit as exc:
        if exc.code != USAGE:
            raise SystemExit("list unknown flag")
    else:
        raise SystemExit("list unknown accepted")
    cases = (
        (["node", "groups", "x"], USAGE, "用法错误\n"),
        (["node", "list", "nope"], USAGE, "用法错误\n"),
        (["node", "members"], USAGE, "用法错误，先看 node groups\n"),
        (["node", "members", "a", "b"], USAGE, "用法错误\n"),
        (["node", "members", "--x"], USAGE, "用法错误\n"),
        (["node", "switch"], USAGE, "用法错误，用 node members 查看成员\n"),
        (["node", "switch", "g"], USAGE, "用法错误，用 node members 查看成员\n"),
        (["node", "switch", "g", "n", "x"], USAGE, "用法错误\n"),
        (["node", "test", "g", "x"], USAGE, "用法错误\n"),
        (["node", "groups"], DOWN, "服务：未运行\n"),
        (["node", "members", "1"], DOWN, "服务：未运行\n"),
        (["node", "list"], DOWN, "服务：未运行\n"),
        (["node", "test"], DOWN, "服务：未运行\n"),
        (["node", "switch", "g", "n"], DOWN, "服务：未运行\n"),
    )
    with tempfile.TemporaryDirectory(prefix="axs-node-args-") as tmp:
        os.environ["AXS_RUN"] = tmp
        for argv, want, err in cases:
            out_buf, err_buf = io.StringIO(), io.StringIO()
            code = 0
            try:
                with contextlib.redirect_stdout(out_buf), contextlib.redirect_stderr(err_buf):
                    cli_main(argv)
            except SystemExit as exc:
                code = exc.code if isinstance(exc.code, int) else 1
            if code != want or err_buf.getvalue() != err or out_buf.getvalue():
                raise SystemExit(f"{argv} -> {code} {err_buf.getvalue()!r} {out_buf.getvalue()!r}")


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
    check_help_heads(help_plain)
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
    if "\033" in plain:
        raise SystemExit("never still has ansi")
    check_usage_color(colored)
    check_help_aliases()
    check_color()
    check_node_args()
    saved_color = os.environ.get("AXS_COLOR")
    os.environ.pop("AXS_COLOR", None)
    os.environ.pop("NO_COLOR", None)
    os.environ["AXS_TTY_ERR"] = "0"
    if "\033" in usage_text():
        raise SystemExit("non-tty usage has ansi")
    if saved_color is None:
        os.environ.pop("AXS_COLOR", None)
    else:
        os.environ["AXS_COLOR"] = saved_color
    os.environ.pop("AXS_TTY_ERR", None)
    print(f"alias matrix {len(EXACT) + len(AMBIGUOUS) + len(UNKNOWN)}; help golden 3")
    return 0


if __name__ == "__main__":
    sys.exit(main())
