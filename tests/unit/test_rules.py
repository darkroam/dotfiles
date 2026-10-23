#!/usr/bin/env python3
"""Rule lines, install/reload rollback, and the merge forwarders."""
import contextlib
import io
import os
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.config import write_defaults  # noqa: E402
from axs.rules import check, mutate, rule_line, rules_add, rules_del  # noqa: E402

FIXTURE = ROOT / "tests" / "fixtures" / "subscription.yaml"
API = "127.0.0.1:9"
KEPT = "DOMAIN kept.example DIRECT\n"


def fail(message):
    raise SystemExit(message)


def invoke(func, *args):
    out, err = io.StringIO(), io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            func(*args)
    except SystemExit as exc:
        return exc.code if exc.code is not None else 0, out.getvalue(), err.getvalue()
    return 0, out.getvalue(), err.getvalue()


def check_lines(tmp):
    if rule_line("via", ".example.com", "PROXY") != "DOMAIN-SUFFIX example.com PROXY":
        fail("suffix line")
    if rule_line("direct", "example.com", "") != "DOMAIN example.com DIRECT":
        fail("direct line")
    code, _out, err = invoke(rule_line, "via", "http://example.com", "PROXY")
    if code != 1 or err != "用法\n":
        fail(f"bad domain {code} {err!r}")
    code, _out, err = invoke(rule_line, "via", "example.com", "")
    if code != 1 or err != "用法\n":
        fail(f"empty group {code} {err!r}")
    path = Path(tmp) / "rules.list"
    rules_add(path, "DOMAIN example.com DIRECT")
    rules_add(path, "DOMAIN example.com PROXY")
    rules_add(path, "DOMAIN-SUFFIX other.com DIRECT")
    if path.read_text(encoding="utf-8") != "DOMAIN example.com PROXY\nDOMAIN-SUFFIX other.com DIRECT\n":
        fail("add did not replace the host")
    rules_del(path, ".example.com")
    if path.read_text(encoding="utf-8") != "DOMAIN-SUFFIX other.com DIRECT\n":
        fail("del missed the host")
    rules_del(Path(tmp) / "missing.list", "example.com")


def check_down(run):
    (run / "rules.list").write_text(KEPT, encoding="utf-8")
    code, out, err = invoke(mutate, run, "add", "0", "", ["via", ".example.com", "PROXY"])
    if code != 0 or out != "已写入，启动时生效\n" or err:
        fail(f"down add {code} {out!r} {err!r}")
    text = (run / "rules.list").read_text(encoding="utf-8")
    if "DOMAIN-SUFFIX example.com PROXY" not in text or "kept.example" not in text:
        fail("down add lost a line")
    if (run / "config.yaml").exists():
        fail("down add built a config")


def check_rejected(run):
    fake = run / "fake"
    fake.mkdir()
    (fake / "groups").write_text("PROXY\n", encoding="utf-8")
    (fake / "reload").write_text("204\n", encoding="utf-8")
    (run / "secret").write_text("test-secret-value\n", encoding="utf-8")
    (run / "rules.list").write_text(KEPT, encoding="utf-8")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    before = (run / "rules.list").read_text(encoding="utf-8")
    code, _out, err = invoke(check, run, "add", "1", API, ["via", "example.com", "OTHER"])
    if code != 3 or err != "组名不存在\n" or (run / "rules.list").read_text(encoding="utf-8") != before:
        fail(f"unknown group {code} {err!r}")
    if (run / ".snap").exists():
        fail("unknown group took a snapshot")
    (fake / "down").write_text("", encoding="utf-8")
    code, _out, err = invoke(check, run, "add", "1", API, ["via", "example.com", "PROXY"])
    if code != 3 or err != "控制器\n控制器\n":
        fail(f"api down {code} {err!r}")
    if (run / "rules.list").read_text(encoding="utf-8") != before:
        fail("api down wrote rules")
    (fake / "down").unlink()


def prepare_sub(run, reload_code):
    fake = run / "fake"
    fake.mkdir()
    (fake / "groups").write_text("PROXY\n", encoding="utf-8")
    (fake / "reload").write_text(f"{reload_code}\n", encoding="utf-8")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    shutil.copy(FIXTURE, run / "subscription.yaml")
    (run / "rules.list").write_text(KEPT, encoding="utf-8")
    (run / "config.yaml").write_text("SENTINEL-OLD\n", encoding="utf-8")
    (run / "secret").write_text("test-secret-value\n", encoding="utf-8")
    write_defaults(run / "override.yaml", 1, API)


def check_reload_fail(run):
    prepare_sub(run, 500)
    code, out, err = invoke(mutate, run, "add", "1", API, ["direct", "new.example"])
    if code != 3 or out or err != "控制器\n重载失败\n重载失败\n":
        fail(f"reload fail {code} {out!r} {err!r}")
    if (run / "rules.list").read_text(encoding="utf-8") != KEPT:
        fail("reload fail kept the edit")
    if (run / "config.yaml").read_text(encoding="utf-8") != "SENTINEL-OLD\n":
        fail("reload fail kept the config")
    if (run / "config.yaml.bak").read_text(encoding="utf-8") != "SENTINEL-OLD\n":
        fail("reload fail bak")


def check_no_sub(run):
    (run / "rules.list").write_text(KEPT, encoding="utf-8")
    code, _out, err = invoke(mutate, run, "add", "1", API, ["direct", "new.example"])
    if code != 3 or err != "没有订阅\n":
        fail(f"no sub {code} {err!r}")
    if (run / "rules.list").read_text(encoding="utf-8") != KEPT:
        fail("no sub kept the edit")
    if (run / "secret").exists():
        fail("no sub created a secret")
    os.environ["AXS_COLOR"] = "always"
    try:
        code, _out, err = invoke(mutate, run, "add", "1", API, ["direct", "new.example"])
    finally:
        os.environ.pop("AXS_COLOR", None)
    if code != 3 or err != "\033[31m没有订阅\033[0m\n":
        fail(f"no sub color {code} {err!r}")


def check_build_fail(run):
    (run / "subscription.yaml").write_text("proxies: []\n", encoding="utf-8")
    (run / "rules.list").write_text(KEPT, encoding="utf-8")
    (run / "config.yaml").write_text("SENTINEL-OLD\n", encoding="utf-8")
    code, out, err = invoke(mutate, run, "add", "1", API, ["direct", "new.example"])
    if code != 3 or out or err != "校验失败\n校验失败\n":
        fail(f"build fail {code} {out!r} {err!r}")
    if (run / "rules.list").read_text(encoding="utf-8") != KEPT:
        fail("build fail kept the edit")
    if (run / "config.yaml").read_text(encoding="utf-8") != "SENTINEL-OLD\n":
        fail("build fail replaced config")


def check_applied(run):
    prepare_sub(run, 204)
    code, out, err = invoke(mutate, run, "add", "1", API, ["direct", "new.example"])
    if code != 0 or out or err:
        fail(f"apply {code} {out!r} {err!r}")
    rules = (run / "rules.list").read_text(encoding="utf-8")
    if rules != KEPT + "DOMAIN new.example DIRECT\n":
        fail("apply rules")
    if "new.example" not in (run / "config.yaml").read_text(encoding="utf-8"):
        fail("apply config missed the rule")
    if (run / "config.yaml.new").exists():
        fail("staged config remained")
    if (run / "config.yaml.bak").read_text(encoding="utf-8") != "SENTINEL-OLD\n":
        fail("apply bak")


def check_forward():
    if (ROOT / "lib" / "merge.py").exists() or (ROOT / "lib" / "common.sh").exists():
        fail("forwarding layer remains")
    source = (ROOT / "lib" / "axs" / "rules.py").read_text(encoding="utf-8")
    for name in ("def has_group", "def parse_rule", "def rules_add", "def rules_del"):
        if name not in source:
            fail("rules lost " + name)



def check_one_query(run):
    prepare_sub(run, 204)
    log = run / "fake" / "log"
    log.write_text("", encoding="utf-8")
    code, out, err = invoke(check, run, "add", "1", API, ["via", "example.com", "PROXY"])
    if code != 0 or out or err:
        fail(f"via check {code} {out!r} {err!r}")
    code, out, err = invoke(mutate, run, "add", "1", API, ["via", "example.com", "PROXY"])
    if code != 0 or err:
        fail(f"via mutate {code} {out!r} {err!r}")
    if log.read_text(encoding="utf-8").count("GET /proxies") != 1:
        fail("via queried twice")
    if "DOMAIN example.com PROXY" not in (run / "rules.list").read_text(encoding="utf-8"):
        fail("via rule missing")

def main():
    check_forward()
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        check_lines(tmp)
    os.environ.pop("AXS_FAKE_DIR", None)
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        check_down(Path(tmp))
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        try:
            check_rejected(Path(tmp))
        finally:
            os.environ.pop("AXS_FAKE_DIR", None)
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        try:
            check_reload_fail(Path(tmp))
        finally:
            os.environ.pop("AXS_FAKE_DIR", None)
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        check_no_sub(Path(tmp))
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        check_build_fail(Path(tmp))
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        try:
            check_applied(Path(tmp))
        finally:
            os.environ.pop("AXS_FAKE_DIR", None)
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        try:
            check_one_query(Path(tmp))
        finally:
            os.environ.pop("AXS_FAKE_DIR", None)
    print("rules ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
