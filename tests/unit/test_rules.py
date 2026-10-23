#!/usr/bin/env python3
"""Rule lines, install/reload rollback, and the merge forwarders."""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.config import write_defaults  # noqa: E402
from axs.rules import check, cmd_list, mutate, rule_line, rules_add, rules_del  # noqa: E402
from axs.subscription import CIDRS  # noqa: E402

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
    if code != 1 or err != "用法错误\n":
        fail(f"bad domain {code} {err!r}")
    code, _out, err = invoke(rule_line, "via", "example.com", "")
    if code != 1 or err != "用法错误\n":
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
    if code != 3 or err != "控制器失败\n控制器失败\n":
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
    if code != 3 or out or err != "控制器失败\n重载失败\n重载失败\n":
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


def check_list():
    os.environ["AXS_COLOR"] = "never"
    v6 = next(item for item in CIDRS if item.startswith("IP-CIDR6,"))
    _kind, payload, policy, *_rest = v6.split(",")
    v6_body = f"IP-CIDR,{payload},{policy}"
    want = (
        "1 prepend  IP-CIDR,10.0.0.0/8,DIRECT\n"
        f"2 prepend  {v6_body}\n"
        "3 prepend  DOMAIN-SUFFIX,local,DIRECT\n"
        "4 local    DOMAIN,mine.example,PROXY\n"
        "5 provider GEOSITE,ads,REJECT\n"
        "6 provider MATCH,PROXY\n"
    )
    with tempfile.TemporaryDirectory(prefix="axs-rule-list-") as tmp:
        run = Path(tmp)
        code, out, err = invoke(cmd_list, run)
        if code != 2 or out or err != "服务：未运行\n":
            fail(f"list down {code} {out!r} {err!r}")
        (run / "rules.list").write_text("DOMAIN mine.example PROXY\n# keep\n", encoding="utf-8")
        code, out, err = invoke(cmd_list, run, True)
        if code != 0 or out != "DOMAIN mine.example PROXY\n# keep\n" or err:
            fail(f"local {code} {out!r} {err!r}")
        (run / "override.yaml").write_text("prepend-rules:\n  - DOMAIN-SUFFIX,local,DIRECT\n", encoding="utf-8")
        (run / "config.yaml").write_text(
            "rules:\n"
            "  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve\n"
            f"  - {v6}\n"
            "  - DOMAIN-SUFFIX,local,DIRECT\n"
            "  - DOMAIN,mine.example,PROXY\n"
            "  - GEOSITE,ads,REJECT\n"
            "  - MATCH,PROXY\n",
            encoding="utf-8",
        )
        code, out, err = invoke(cmd_list, run, False)
        if code != 0 or out != want or err:
            fail(f"config list {code} {out!r} {err!r}")
        fake = run / "fake"
        fake.mkdir()
        (run / "secret").write_text("test-secret-value\n", encoding="utf-8")
        os.environ["AXS_FAKE_DIR"] = str(fake)
        os.environ["AXS_API"] = API
        mihomo = ROOT / "tests" / "fixtures" / "fake-mihomo"
        os.environ["AXS_MIHOMO"] = str(mihomo)
        proc = subprocess.Popen([str(mihomo)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            (run / "mihomo.pid").write_text(f"{proc.pid}\n", encoding="utf-8")
            from axs.core import service_up
            for _ in range(20):
                if service_up(run):
                    break
                time.sleep(0.05)
            else:
                fail("fake core did not stay up")
            code, out, err = invoke(cmd_list, run)
            if code != 3 or out or err != "控制器失败\n":
                fail(f"api down {code} {out!r} {err!r}")
            (fake / "rules.json").write_text(json.dumps({"rules": [
                {"type": "IPCIDR", "payload": "10.0.0.0/8", "proxy": "DIRECT", "size": -1},
                {"type": "IPCIDR", "payload": payload, "proxy": "DIRECT"},
                {"type": "DomainSuffix", "payload": "local", "proxy": "DIRECT"},
                {"type": "Domain", "payload": "mine.example", "proxy": "PROXY", "extra": {"disabled": False}},
                {"type": "GeoSite", "payload": "ads", "proxy": "REJECT"},
                {"type": "Match", "payload": "", "proxy": "PROXY"},
            ]}), encoding="utf-8")
            code, out, err = invoke(cmd_list, run)
            if code != 0 or out != want or err:
                fail(f"api list {code} {out!r} {err!r}")
            code, out, err = invoke(cmd_list, run, True)
            if code != 0 or not out.startswith("DOMAIN mine.example PROXY\n"):
                fail(f"local while up {code} {out!r}")
        finally:
            proc.kill()
            proc.wait()
            os.environ.pop("AXS_FAKE_DIR", None)
            os.environ.pop("AXS_API", None)
            os.environ.pop("AXS_MIHOMO", None)


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
    check_list()
    print("rules ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
