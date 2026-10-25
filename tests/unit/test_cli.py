#!/usr/bin/env python3
"""Alias order and the three help/usage snapshots, imported directly."""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.cli import (
    DOWN, EXPIRED, FAIL, GROUPS, LOCK, ResolveError, USAGE,
    _alias_marks, _list_flags, _usage_word, main as cli_main, resolve_token, usage_text,
)
from axs.render import (
    SECTIONS, bad, bold, dim, display_width, emph, help_text, ident, label, ok, tone, use_color, warn,
)

GOLDEN = ROOT / "tests" / "golden"
EXACT = (
    ("s", "top", "status"),
    ("status", "top", "status"),
    ("sta", "top", "status"),
    ("stat", "top", "status"),
    ("se", "top", "service"),
    ("service", "top", "service"),
    ("n", "top", "node"),
    ("node", "top", "node"),
    ("g", "top", "group"),
    ("group", "top", "group"),
    ("r", "top", "rule"),
    ("rule", "top", "rule"),
    ("su", "top", "subscription"),
    ("sub", "top", "subscription"),
    ("subscription", "top", "subscription"),
    ("ne", "top", "network"),
    ("net", "top", "network"),
    ("network", "top", "network"),
    ("p", "top", "proxy"),
    ("proxy", "top", "proxy"),
    ("c", "top", "clean"),
    ("clean", "top", "clean"),
    ("h", "top", "help"),
    ("he", "top", "help"),
    ("?", "top", "help"),
    ("--help", "top", "help"),
    ("-h", "top", "help"),
    ("health", "top", "health"),
    ("k", "top", "health"),
    ("s", "service", "status"),
    ("sta", "service", "start"),
    ("sto", "service", "stop"),
    ("re", "service", "restart"),
    ("e", "service", "ensure"),
    ("en", "service", "enable"),
    ("di", "service", "disable"),
    ("he", "service", "health"),
    ("health", "service", "health"),
    ("s", "node", "show"),
    ("show", "node", "show"),
    ("sh", "node", "show"),
    ("s", "group", "show"),
    ("sw", "group", "switch"),
    ("m", "group", "members"),
    ("t", "group", "test"),
    ("mem", "group", "members"),
    ("s", "rule", "show"),
    ("a", "rule", "add"),
    ("d", "rule", "del"),
    ("show", "rule", "show"),
    ("s", "subscription", "show"),
    ("r", "subscription", "refresh"),
    ("c", "subscription", "clean"),
    ("ref", "subscription", "refresh"),
    ("t", "network", "test"),
    ("i", "network", "ip"),
    ("test", "network", "test"),
    ("u", "proxy", "user"),
    ("sy", "proxy", "system"),
    ("se", "proxy", "session"),
    ("user", "proxy", "user"),
)
AMBIGUOUS = (
    ("st", "service", "候选：status start stop"),
    ("s", "proxy", "候选：system session"),
)
UNKNOWN = (
    ("nope", "top"),
    ("x", "top"),
    ("o", "top"),
    ("u", "top"),
    ("nw", "top"),
    ("sto", "top"),
    ("re", "top"),
    ("e", "top"),
    ("st", "proxy"),
    ("l", "node"),
    ("g", "subscription"),
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
    if len(lines) != 8:
        raise SystemExit("usage lines")
    expect = {
        0: ("s tatus", "c lean", "h elp"),
        1: ("se rvice", "s tatus", "sta rt", "sto p", "re start", "e nsure", "en able", "di sable"),
        2: ("su bscription", "s how", "r efresh", "c lean"),
        3: ("r ule", "s how", "a dd", "d el"),
        4: ("n ode", "s how"),
        5: ("g roup", "s how", "m embers", "sw itch", "t est"),
        6: ("t est", "i p"),
        7: ("p roxy", "u ser", "sy stem", "se ssion"),
    }
    for index, pairs in expect.items():
        for pair in pairs:
            alias, rest = pair.split(" ", 1)
            if marked(alias, rest) not in lines[index]:
                raise SystemExit(f"line {index} missing {alias}")
    health = _usage_word("health", "service")
    help_word = _usage_word("help", "top")
    if health != marked("he", "alth") or help_word != marked("h", "elp"):
        raise SystemExit("quiet top alias")
    actions = bold("on") + "|" + bold("off") + "|" + bold("status")
    if actions not in lines[7] or marked("s", "tatus") in lines[7]:
        raise SystemExit("proxy actions")
    if bold("enable") not in lines[7]:
        raise SystemExit("system enable should stay bold")


def check_help_aliases():
    from axs.rules import ADD

    sub = {name: short for short, name in ADD.items() if short != name}
    shown = {}
    for _title, rows, _notes in SECTIONS:
        for cmd, alias, _desc in rows:
            parts = cmd.split()
            if len(parts) > 3:
                key = (parts[1] + " " + parts[2], parts[3])
            elif len(parts) == 2:
                key = ("top", parts[1])
            else:
                key = (parts[1], parts[2])
            shown.setdefault(key, set()).add(alias)
    for (group, word), aliases in shown.items():
        expect = sub[word] if " " in group else _alias_marks(GROUPS[group][1]).get(word, "")
        nonempty = {item for item in aliases if item}
        if expect and nonempty != {expect}:
            raise SystemExit(f"help alias {group} {word}")
        if not expect and nonempty:
            raise SystemExit(f"help extra alias {group} {word}")



def check_help_heads(help_plain):
    heads = (
        ("服务", "service"),
        ("订阅", "subscription"),
        ("规则", "rule"),
        ("节点", "node"),
        ("组", "group"),
        ("网络", "network"),
        ("代理", "proxy"),
        ("清理", "clean"),
    )
    marks = _alias_marks(GROUPS["top"][1])
    titles = [item[0] for item in SECTIONS]
    if len(titles) != len(heads):
        raise SystemExit("help section count")
    for (zh, command), title in zip(heads, titles):
        alias = marks.get(command)
        want = f"{zh}（{command} / {alias}）" if alias else f"{zh}（{command}）"
        if title != want or title not in help_plain.splitlines():
            raise SystemExit("help head " + want)
    for line in help_plain.splitlines():
        if not line.startswith("axs "):
            continue
        if line[24:26] != "  " or line[32:34] != "  ":
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
        (["group", "show", "x"], USAGE, "用法错误\n"),
        (["node", "show", "nope"], USAGE, "用法错误\n"),
        (["group", "members"], USAGE, "用法错误，先看 group show\n"),
        (["group", "members", "a", "b"], USAGE, "用法错误\n"),
        (["group", "members", "--x"], USAGE, "用法错误\n"),
        (["group", "switch"], USAGE, "用法错误，用 group members 查看成员\n"),
        (["group", "switch", "g"], USAGE, "用法错误，用 group members 查看成员\n"),
        (["group", "switch", "g", "n", "x"], USAGE, "用法错误\n"),
        (["group", "test", "g", "x"], USAGE, "用法错误\n"),
        (["group", "show"], DOWN, "服务：未运行\n"),
        (["group", "members", "1"], DOWN, "服务：未运行\n"),
        (["node"], DOWN, "服务：未运行\n"),
        (["node", "show"], DOWN, "服务：未运行\n"),
        (["group", "test"], DOWN, "服务：未运行\n"),
        (["group", "switch", "g", "n"], DOWN, "服务：未运行\n"),
        (["health"], DOWN, "未运行\n"),
        (["k"], DOWN, "未运行\n"),
        (["health", "x"], USAGE, "用法错误\n"),
        (["k", "x"], USAGE, "用法错误\n"),
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
    if "health" in help_plain or "health" in usage_text():
        raise SystemExit("health is listed")
    check_help_heads(help_plain)
    if '示例：axs s · axs n s · axs p sy on' not in help_plain:
        raise SystemExit("help example")
    os.environ["AXS_COLOR"] = "always"
    colored = usage_text()
    os.environ["AXS_COLOR"] = "never"
    plain = usage_text()
    import re
    stripped = re.sub(r"\033\[[0-9;]*m", "", colored)
    if stripped != plain or plain.count("\n") != 8:
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
