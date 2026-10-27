#!/usr/bin/env python3
"""Alias order, exit codes, and command-argument checks."""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.catalog import GROUPS, SIG
from axs.cli import (
    DOWN, EXPIRED, FAIL, LOCK, ResolveError, USAGE,
    _list_flags, main as cli_main, resolve_token,
)
from axs.render import bad, bold, dim, emph, ident, label, ok, tone, use_color, warn

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
    ("nw", "top", "network"),
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
    ("s", "node", "status"),
    ("status", "node", "status"),
    ("sh", "node", "show"),
    ("show", "node", "show"),
    ("s", "group", "status"),
    ("status", "group", "status"),
    ("sw", "group", "switch"),
    ("m", "group", "members"),
    ("t", "group", "test"),
    ("mem", "group", "members"),
    ("s", "rule", "status"),
    ("sh", "rule", "show"),
    ("a", "rule", "add"),
    ("d", "rule", "del"),
    ("show", "rule", "show"),
    ("status", "rule", "status"),
    ("s", "subscription", "status"),
    ("status", "subscription", "status"),
    ("r", "subscription", "refresh"),
    ("c", "subscription", "clean"),
    ("ref", "subscription", "refresh"),
    ("t", "network", "test"),
    ("i", "network", "ip"),
    ("test", "network", "test"),
    ("s", "proxy", "status"),
    ("st", "proxy", "status"),
    ("status", "proxy", "status"),
    ("u", "proxy", "user"),
    ("sy", "proxy", "system"),
    ("se", "proxy", "session"),
    ("user", "proxy", "user"),
)
AMBIGUOUS = (
    ("st", "service", "候选：status start stop"),
)
UNKNOWN = (
    ("nope", "top"),
    ("x", "top"),
    ("o", "top"),
    ("u", "top"),
    ("sto", "top"),
    ("re", "top"),
    ("e", "top"),
    ("l", "node"),
    ("g", "subscription"),
)



def resolve(word, group):
    words, aliases = GROUPS[group]
    return resolve_token(word, words, aliases)



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
        (["group", "status", "x"], USAGE, "用法错误\n"),
        (["node", "show", "nope"], USAGE, "用法错误\n"),
        (["group", "members"], USAGE, "用法错误，先看 group status\n"),
        (["group", "members", "a", "b"], USAGE, "用法错误\n"),
        (["group", "members", "--x"], USAGE, "用法错误\n"),
        (["group", "switch"], USAGE, "用法错误，用 group members 查看成员\n"),
        (["group", "switch", "g"], USAGE, "用法错误，用 group members 查看成员\n"),
        (["group", "switch", "g", "n", "x"], USAGE, "用法错误\n"),
        (["group", "test", "g", "x"], USAGE, "用法错误\n"),
        (["group", "status"], DOWN, "服务：未运行\n"),
        (["group", "members", "1"], DOWN, "服务：未运行\n"),
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
        from axs.render import layer_text
        for name in ("node", "group", "rule", "subscription", "proxy", "service"):
            out_buf, err_buf = io.StringIO(), io.StringIO()
            code = 0
            try:
                with contextlib.redirect_stdout(out_buf), contextlib.redirect_stderr(err_buf):
                    cli_main([name])
            except SystemExit as exc:
                code = exc.code if isinstance(exc.code, int) else 1
            if code != 0 or err_buf.getvalue() or out_buf.getvalue() != layer_text(name):
                raise SystemExit(f"bare {name} -> {code} {err_buf.getvalue()!r} {out_buf.getvalue()!r}")



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



def check_sig():
    words = {name: set(items[0]) for name, items in GROUPS.items()}
    if set(SIG) != set(words):
        raise SystemExit("sig groups")
    hidden = {("top", "health"), ("service", "health")}
    if set(SIG["top"]) != {"status", "clean", "help", "health"}:
        raise SystemExit("top sig")
    for group, spec in SIG.items():
        if group != "top" and set(spec) != words[group]:
            raise SystemExit("sig words " + group)
        for name, row in spec.items():
            least, most, flags, secret = row
            if type(least) is not int or least < 0 or (most is not None and (type(most) is not int or most < least)):
                raise SystemExit(f"sig range {group} {name}")
            if type(flags) is not tuple or any(type(flag) is not str or not flag for flag in flags):
                raise SystemExit(f"sig flags {group} {name}")
            if secret is not ((group, name) in hidden):
                raise SystemExit(f"sig hidden {group} {name}")
    expect = {
        ("group", "members"): (1, 1, ()),
        ("group", "switch"): (2, 2, ()),
        ("group", "test"): (0, 1, ()),
        ("rule", "add"): (2, 3, ()),
        ("rule", "del"): (1, 1, ()),
        ("rule", "show"): (0, 0, ("--local",)),
        ("network", "test"): (0, None, ()),
        ("network", "ip"): (0, 0, ()),
        ("node", "show"): (0, 0, ("--full", "--all", "--flat!", "-l!", "--depth=")),
        ("proxy", "user"): (1, 1, ()),
        ("top", "clean"): (0, 0, ("--yes",)),
    }
    for key, want in expect.items():
        if SIG[key[0]][key[1]][:3] != want:
            raise SystemExit("sig value " + " ".join(key))


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
    if (USAGE, DOWN, FAIL, LOCK, EXPIRED) != (1, 2, 3, 4, 5):
        raise SystemExit("exit codes")
    check_node_args()
    check_color()
    check_sig()
    print(f"alias matrix {len(EXACT) + len(AMBIGUOUS) + len(UNKNOWN)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
