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

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))

from axs.config import CIDRS  # noqa: E402
from axs.core import write_defaults  # noqa: E402
from axs.rulelist import cmd_list, rule_id  # noqa: E402
from axs.rules import check, cmd_add, cmd_del, mutate, rule_line, rules_add, rules_del  # noqa: E402

FIXTURE = TEST / "fixtures" / "subscription.yaml"
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



def check_node(run):
    if rule_line("node", ".example.com", "leaf") != "DOMAIN-SUFFIX example.com leaf":
        fail("node suffix")
    if rule_line("node", "example.com", "DIRECT") != "DOMAIN example.com DIRECT":
        fail("node builtin line")
    code, _out, err = invoke(rule_line, "node", "example.com", "bad name")
    if code != 1 or err != "节点名不能含空白或逗号\n":
        fail(f"node space {code} {err!r}")
    code, _out, err = invoke(rule_line, "node", "example.com", "a,b")
    if code != 1 or err != "节点名不能含空白或逗号\n":
        fail(f"node comma {code} {err!r}")
    code, _out, err = invoke(rule_line, "node", "example.com", "bad\tname")
    if code != 1 or err != "节点名不能含空白或逗号\n":
        fail(f"node tab {code} {err!r}")
    code, _out, err = invoke(rule_line, "node", "example.com", "")
    if code != 1 or err != "用法错误\n":
        fail(f"node empty {code} {err!r}")
    code, _out, err = invoke(rule_line, "via", "example.com", "bad name")
    if code != 1 or err != "用法错误\n":
        fail(f"via space {code} {err!r}")
    fake = run / "fake"
    fake.mkdir()
    (fake / "proxies.json").write_text(
        json.dumps({"proxies": {"PROXY": {"type": "Selector"}, "auto": {"type": "URLTest"}, "leaf": {"type": "Shadowsocks"}}}),
        encoding="utf-8",
    )
    (run / "secret").write_text("test-secret-value\n", encoding="utf-8")
    os.environ["AXS_FAKE_DIR"] = str(fake)
    code, _out, err = invoke(check, run, "add", "1", API, ["node", "example.com", "leaf"])
    if code or err:
        fail(f"node ok {code} {err!r}")
    code, _out, err = invoke(check, run, "add", "1", API, ["node", "example.com", "PROXY"])
    if code != 3 or err != "不是节点\n":
        fail(f"node group {code} {err!r}")
    code, _out, err = invoke(check, run, "add", "1", API, ["node", "example.com", "auto"])
    if code != 3 or err != "不是节点\n":
        fail(f"node auto {code} {err!r}")
    code, _out, err = invoke(check, run, "add", "1", API, ["node", "example.com", "gone"])
    if code != 3 or err != "节点不存在\n":
        fail(f"node missing {code} {err!r}")
    for name in ("DIRECT", "REJECT"):
        code, _out, err = invoke(check, run, "add", "1", API, ["node", "example.com", name])
        if code or err:
            fail(f"node {name} {code} {err!r}")
    (fake / "down").write_text("", encoding="utf-8")
    code, _out, err = invoke(check, run, "add", "1", API, ["node", "example.com", "leaf"])
    if code != 3 or err != "控制器失败\n控制器失败\n":
        fail(f"node api {code} {err!r}")
    (fake / "down").unlink()
    code, out, err = invoke(mutate, run, "add", "0", "", ["node", "down.example", "gone"])
    if code or out != "已写入，启动时生效\n" or err:
        fail(f"node down {code} {out!r} {err!r}")
    if "DOMAIN down.example gone" not in (run / "rules.list").read_text(encoding="utf-8"):
        fail("node down did not write")
    before = (run / "rules.list").read_text(encoding="utf-8")
    code, _out, err = invoke(mutate, run, "add", "0", "", ["node", "example.com", "bad name"])
    if code != 1 or err != "节点名不能含空白或逗号\n" or (run / "rules.list").read_text(encoding="utf-8") != before:
        fail(f"node space kept {code} {err!r}")
    code, out, err = invoke(cmd_add, run, ["n", ".alias.example", "leaf"])
    if code or "DOMAIN-SUFFIX alias.example leaf" not in (run / "rules.list").read_text(encoding="utf-8"):
        fail(f"alias n {code} {out!r} {err!r}")
    code, _out, err = invoke(cmd_add, run, ["nope", "example.com", "leaf"])
    if code != 1 or err != "用法错误\n":
        fail(f"alias nope {code} {err!r}")


def check_forward():
    if (ROOT / "lib" / "merge.py").exists() or (ROOT / "lib" / "common.sh").exists():
        fail("forwarding layer remains")
    source = (ROOT / "axs" / "rules.py").read_text(encoding="utf-8")
    listed = (ROOT / "axs" / "rulelist.py").read_text(encoding="utf-8")
    for name in ("def has_group", "def rules_add", "def rules_del"):
        if name not in source:
            fail("rules lost " + name)
    if "def parse_rule" in source or "def lookup_group" in (ROOT / "axs" / "nodes.py").read_text(encoding="utf-8"):
        fail("dead helper remains")
    if "def rule_id" in source or "def cmd_list" in source:
        fail("rules kept the view")
    if any(name not in listed for name in ("def rule_id", "def cmd_list", "def resolve_delete")):
        fail("rulelist lost the view")



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
    logic = "AND,((DOMAIN,a.com),(DOMAIN,b.com)),PROXY"
    spec = [
        ("prepend", "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"),
        ("prepend", v6),
        ("prepend", "DOMAIN-SUFFIX,local,DIRECT"),
        ("local", "DOMAIN,mine.example,PROXY"),
        ("provider", "GEOSITE,ads,REJECT"),
        ("provider", "MATCH,PROXY"),
        ("provider", logic),
    ]
    want = "".join(f"{i}  {rule_id(kind, line)}  {kind:<8}  {line}\n" for i, (kind, line) in enumerate(spec, 1))
    local_line = "DOMAIN mine.example PROXY"
    local_want = f"1  {rule_id('local', local_line)}  local     {local_line}\n"
    with tempfile.TemporaryDirectory(prefix="axs-rule-list-") as tmp:
        run = Path(tmp)
        code, out, err = invoke(cmd_list, run)
        if code != 2 or out or err != "服务：未运行\n":
            fail(f"list down {code} {out!r} {err!r}")
        (run / "rules.list").write_text("DOMAIN mine.example PROXY\n# keep\n", encoding="utf-8")
        code, out, err = invoke(cmd_list, run, True)
        if code != 0 or out != local_want or err:
            fail(f"local {code} {out!r} {err!r}")
        (run / "override.yaml").write_text("prepend-rules:\n  - DOMAIN-SUFFIX,local,DIRECT\n", encoding="utf-8")
        (run / "config.yaml").write_text(
            "rules:\n"
            "  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve\n"
            f"  - {v6}\n"
            "  - DOMAIN-SUFFIX,local,DIRECT\n"
            "  - DOMAIN,mine.example,PROXY\n"
            "  - GEOSITE,ads,REJECT\n"
            "  - MATCH,PROXY\n"
            f"  - {logic}\n",
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
        mihomo = TEST / "fixtures" / "fake-mihomo"
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
            if code != 0 or out != want or "no-resolve" not in out or err:
                fail(f"up ignores controller {code} {out!r} {err!r}")
            (fake / "rules.json").write_text(json.dumps({"rules": [
                {"type": "IPCIDR", "payload": "10.0.0.0/8", "proxy": "DIRECT", "size": -1},
                {"type": "Match", "payload": "", "proxy": "PROXY"},
            ]}), encoding="utf-8")
            code, out, err = invoke(cmd_list, run)
            if code != 0 or out != want or "no-resolve" not in out or logic not in out or err:
                fail(f"controller ignored {code} {out!r} {err!r}")
            code, out, err = invoke(cmd_list, run, True)
            if code != 0 or out != local_want or err:
                fail(f"local while up {code} {out!r}")
        finally:
            proc.kill()
            proc.wait()
            os.environ.pop("AXS_FAKE_DIR", None)
            os.environ.pop("AXS_API", None)
            os.environ.pop("AXS_MIHOMO", None)



def release_lock():
    from axs.core import _HELD

    while _HELD:
        _HELD.pop().close()


def check_del():
    os.environ["AXS_COLOR"] = "never"
    with tempfile.TemporaryDirectory(prefix="axs-rule-del-") as tmp:
        run = Path(tmp)
        (run / "rules.list").write_text("DOMAIN mine.example PROXY\nDOMAIN other.example DIRECT\n", encoding="utf-8")
        code, out, err = invoke(cmd_list, run, True)
        mine = next(line.split()[1] for line in out.splitlines() if "mine.example" in line)
        other = next(line.split()[1] for line in out.splitlines() if "other.example" in line)
        if rule_id("local", "DOMAIN mine.example PROXY") != rule_id("local", "DOMAIN,mine.example,REJECT") or mine == other:
            fail("local id is not the domain")
        pre = "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"
        if rule_id("prepend", pre) == rule_id("prepend", pre.replace(",no-resolve", "")):
            fail("prepend id dropped the flag")
        (run / "rules.list").write_text("DOMAIN mine.example REJECT\n", encoding="utf-8")
        code, out, err = invoke(cmd_list, run, True)
        if code or err or out.split()[1] != mine:
            fail(f"target change {code} {out!r} {err!r}")
        (run / "rules.list").write_text("DOMAIN mine.example PROXY\n", encoding="utf-8")
        (run / "config.yaml").write_text(
            "rules:\n  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve\n  - DOMAIN,mine.example,PROXY\n  - GEOSITE,ads,REJECT\n",
            encoding="utf-8",
        )
        before = (run / "rules.list").read_text(encoding="utf-8")
        code, out, err = invoke(cmd_del, run, [rule_id("prepend", pre)])
        if code != 3 or out or err != "不是本地规则\n" or (run / "rules.list").read_text(encoding="utf-8") != before:
            fail(f"nonlocal id {code} {out!r} {err!r}")
        code, out, err = invoke(cmd_del, run, ["GEOSITE,ads,REJECT"])
        if code != 3 or out or err != "不是本地规则\n" or (run / "rules.list").read_text(encoding="utf-8") != before:
            fail(f"nonlocal text {code} {out!r} {err!r}")
        code, out, err = invoke(cmd_del, run, ["DOMAIN,missing.example,PROXY"])
        if code != 3 or out or err != "规则不存在\n" or (run / "rules.list").read_text(encoding="utf-8") != before:
            fail(f"missing text {code} {out!r} {err!r}")
        code, out, err = invoke(cmd_del, run, ["R000000"])
        if code != 3 or out or err != "规则不存在\n" or (run / "rules.list").read_text(encoding="utf-8") != before:
            fail(f"missing id {code} {out!r} {err!r}")
        code, out, err = invoke(cmd_del, run, [mine])
        if code or err or "mine.example" in (run / "rules.list").read_text(encoding="utf-8") or out != "已删除，启动时生效\n" or not (run / ".snap").is_dir():
            fail(f"del id {code} {out!r} {err!r}")
        release_lock()
        (run / "rules.list").write_text(before, encoding="utf-8")
        code, out, err = invoke(cmd_del, run, ["DOMAIN,mine.example,PROXY"])
        if code or err or out != "已删除，启动时生效\n" or (run / "rules.list").read_text(encoding="utf-8").strip():
            fail(f"del text {code} {out!r} {err!r}")
        release_lock()
        for token in ("gone.example", "Rzzzzz"):
            (run / "rules.list").write_text(before, encoding="utf-8")
            code, out, err = invoke(cmd_del, run, [token])
            if code != 3 or out or err != "规则不存在\n" or (run / "rules.list").read_text(encoding="utf-8") != before:
                fail(f"domain miss {token} {code} {out!r} {err!r}")


def main():
    check_forward()
    with tempfile.TemporaryDirectory(prefix="axs-rules-") as tmp:
        check_lines(tmp)
        try:
            check_node(Path(tmp))
        finally:
            os.environ.pop("AXS_FAKE_DIR", None)
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
    check_del()
    print("rules ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
