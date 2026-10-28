#!/usr/bin/env python3
"""Subscription merge, cleanup names, and rollback. No network."""
import os
import sys
import tempfile
from pathlib import Path

import yaml

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))
from axs.config import (  # noqa: E402
    CIDRS,
    CONFIG,
    CONFIG_BAK,
    DEFAULT_API,
    DEFAULT_DNS_LISTEN,
    DEFAULT_MIXED,
    FETCH_BODY,
    FETCH_HEADER,
    PID,
    PREPEND,
    SUBSCRIPTION,
    LIST,
    URL,
    USERINFO,
)
from axs.core import write_defaults  # noqa: E402
from axs.subscription import (  # noqa: E402
    build_file,
    check_url,
    clean_names,
    clear_fetch,
    install_merged,
    rollback,
    dispatch,
    subscription_line,
    take_snapshot,
)


def fail(message):
    raise SystemExit(message)


def check_merge(work):
    secret = "test-secret-value"
    (work / "secret").write_text(secret + "\n", encoding="utf-8")
    (work / "rules.list").write_text("DOMAIN-SUFFIX added.example PROXY\n", encoding="utf-8")
    override = work / "override.yaml"
    merged = work / "out.yaml"
    write_defaults(override, DEFAULT_MIXED, DEFAULT_API)
    build_file(
        TEST / "fixtures" / "subscription.yaml",
        override,
        work / "secret",
        work / "rules.list",
        merged,
    )
    data = yaml.safe_load(merged.read_text(encoding="utf-8"))
    expect = {
        "mode": "rule",
        "mixed-port": int(DEFAULT_MIXED),
        "allow-lan": False,
        "ipv6": True,
        "log-level": "info",
        "external-controller": DEFAULT_API,
        "secret": secret,
    }
    for key, value in expect.items():
        if data.get(key) != value:
            fail(f"{key}: {data.get(key)!r}")
    if data["dns"]["enable"] is not True or data["dns"]["listen"] != DEFAULT_DNS_LISTEN:
        fail(f"dns: {data['dns']!r}")
    if data["dns"]["nameserver"] != ["192.0.2.53"]:
        fail("nameserver overwritten")
    if data["tun"] != {"enable": False}:
        fail(f"tun: {data['tun']!r}")
    for key in ("port", "socks-port", "redir-port", "tproxy-port", "prepend-rules"):
        if key in data:
            fail(f"left {key}")
    rules = data["rules"]
    head = CIDRS + list(PREPEND) + ["DOMAIN-SUFFIX,added.example,PROXY", "MATCH,PROXY"]
    if rules != head:
        fail("rule order")
    if rules.count("DOMAIN-SUFFIX,localhost,DIRECT") != 1:
        fail("localhost duplicated")
    text = merged.read_text(encoding="utf-8")
    if "from-sub-should-not-win" in text or "canary.invalid" in text:
        fail("subscription secret leaked into config")


def check_forward():
    if (ROOT / "lib" / "merge.py").exists():
        fail("merge remains")
    if build_file.__module__ != "axs.subscription":
        fail("build module")


def check_names():
    config = (CONFIG, CONFIG_BAK, USERINFO, FETCH_BODY, FETCH_HEADER, PID, LIST, SUBSCRIPTION, URL)
    sub = (SUBSCRIPTION, USERINFO, FETCH_BODY, FETCH_HEADER)
    if clean_names("config") != config or clean_names("other") != sub:
        fail("clean names")


def check_install_and_rollback(work):
    body = work / FETCH_BODY
    body.write_text("new-body\n", encoding="utf-8")
    (work / CONFIG).write_text("old-config\n", encoding="utf-8")
    (work / SUBSCRIPTION).write_text("old-sub\n", encoding="utf-8")
    (work / "rules.list").write_text("old-rule\n", encoding="utf-8")
    take_snapshot(work)
    install_merged(body, work / CONFIG)
    if (work / CONFIG).read_text(encoding="utf-8") != "new-body\n":
        fail("install missed")
    if (work / (CONFIG + ".bak")).read_text(encoding="utf-8") != "old-config\n":
        fail("bak missed")
    if body.exists():
        fail("install left the staged file")
    (work / "rules.list").write_text("edited\n", encoding="utf-8")
    rollback(work)
    if (work / CONFIG).read_text(encoding="utf-8") != "old-config\n":
        fail("rollback config")
    if (work / "rules.list").read_text(encoding="utf-8") != "old-rule\n":
        fail("rollback rules")
    (work / FETCH_BODY).write_text("temp\n", encoding="utf-8")
    (work / FETCH_HEADER).write_text("temp\n", encoding="utf-8")
    clear_fetch(work)
    if (work / FETCH_BODY).exists() or (work / FETCH_HEADER).exists():
        fail("fetch temp remains")
    if (work / ".snap" / CONFIG).exists():
        fail("snap config remains")


def check_url_reject(work):
    path = work / "url"
    path.write_text("https://example.invalid/link/\\?x\n", encoding="utf-8")
    try:
        check_url(path)
    except SystemExit as exc:
        if exc.code != 3:
            fail(f"url code {exc.code}")
        return
    fail("backslash accepted")



def check_soon(work):
    os.environ["AXS_COLOR"] = "never"
    path = work / "userinfo"
    now = 1700000000
    path.write_text(f"expire={now + 86400}\n", encoding="utf-8")
    text, kind = subscription_line(path, now)
    if kind != "soon" or text != "剩余 1 天（警告）":
        fail(text)
    path.write_text(f"expire={now + 40 * 86400}\n", encoding="utf-8")
    text, kind = subscription_line(path, now)
    if kind != "ok" or "警告" in text or not text.startswith("剩余 "):
        fail(text)
    path.write_text("expire=1\n", encoding="utf-8")
    text, kind = subscription_line(path, now)
    if kind != "expired" or text != "剩余 已过期" or "警告" in text:
        fail(text)
    path.write_text("upload=1\n", encoding="utf-8")
    text, kind = subscription_line(path, now)
    if kind != "unknown" or text != "剩余 未知 · 上传 1.0B" or "警告" in text:
        fail(text)


def _exit(action):
    try:
        action()
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else 1
    return 0


def _capture(action):
    import contextlib
    import io
    out, err = io.StringIO(), io.StringIO()
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = _exit(action)
        return code, out.getvalue(), err.getvalue()
    finally:
        from axs.core import _HELD
        while _HELD:
            _HELD.pop().close()


def check_list(work):
    from axs.core import restore_snapshot, snapshot
    os.environ["AXS_COLOR"] = "never"
    os.environ["AXS_FETCH"] = str(TEST / "fixtures" / "fake-fetch")
    os.environ["FIXTURE_SUB"] = str(TEST / "fixtures" / "subscription.yaml")
    url_a = "https://a.example/token-a"
    url_b = "https://b.example/path/token-b?k=secret"
    (work / URL).write_text(url_a + "\n", encoding="utf-8")
    code, _out, err = _capture(lambda: dispatch(work, "refresh", []))
    if code != 0 or err:
        fail("migrate refresh " + err)
    listed = (work / LIST).read_text(encoding="utf-8")
    if listed != "axs-subscriptions 1 2\nS1 * " + url_a + "\n":
        fail("migrated list")
    if (work / URL).exists() or (work / LIST).stat().st_mode & 0o777 != 0o600:
        fail("migrate mode")
    code, shown, _err = _capture(lambda: dispatch(work, "show", []))
    if code != 0 or shown != "S1 * a.example\n" or "token" in shown:
        fail("show leaked " + shown)
    code, out, _err = _capture(lambda: dispatch(work, "status", []))
    if code != 0 or not out.startswith("S1 · a.example · 剩余 ") or "token" in out:
        fail("status prefix " + out)
    code, _out, err = _capture(lambda: dispatch(work, "add", [url_b]))
    if code != 0:
        fail("add " + err)
    code, _out, err = _capture(lambda: dispatch(work, "add", [url_b]))
    if code != 3 or err != "链接重复\n":
        fail("dup " + err)
    code, _out, err = _capture(lambda: dispatch(work, "rm", ["S1"]))
    if code != 3 or err != "先 switch\n" or "S1 * " not in (work / LIST).read_text(encoding="utf-8"):
        fail("rm active " + err)
    code, _out, err = _capture(lambda: dispatch(work, "rm", ["2"]))
    if code != 1 or err != "编号只认 S#\n":
        fail("bare " + err)
    code, _out, err = _capture(lambda: dispatch(work, "rm", ["s2"]))
    if code != 0 or "S2 " in (work / LIST).read_text(encoding="utf-8"):
        fail("rm s2 " + err)
    code, _out, err = _capture(lambda: dispatch(work, "add", ["https://c.example/token-c"]))
    text = (work / LIST).read_text(encoding="utf-8")
    if code != 0 or "S3 * " in text or "S3 - https://c.example/token-c" not in text:
        fail("reuse " + text)
    before = text
    os.environ["AXS_FETCH"] = str(TEST / "fixtures" / "fake-fetch-fail")
    code, _out, err = _capture(lambda: dispatch(work, "switch", ["S3"]))
    if code != 3 or (work / LIST).read_text(encoding="utf-8") != before:
        fail("switch rollback " + err)
    os.environ["AXS_FETCH"] = str(TEST / "fixtures" / "fake-fetch")
    code, _out, err = _capture(lambda: dispatch(work, "switch", ["s3"]))
    text = (work / LIST).read_text(encoding="utf-8")
    if code != 0 or "S3 * https://c.example/token-c" not in text or "S1 * " in text:
        fail("switch star " + text + err)
    code, shown, _err = _capture(lambda: dispatch(work, "show", []))
    if "token" in shown or "secret" in shown or "S3 * c.example" not in shown:
        fail("show after switch " + shown)
    code, _out, err = _capture(lambda: dispatch(work, "switch", ["S9"]))
    if code != 3 or "订阅不存在" not in err:
        fail("missing id " + err)
    (work / LIST).write_text("nope\n", encoding="utf-8")
    code, _out, err = _capture(lambda: dispatch(work, "show", []))
    if code != 3 or err != "订阅列表损坏\n":
        fail("corrupt " + err)
    (work / LIST).unlink()
    (work / URL).write_text("https://example.invalid/link/\\?x\n", encoding="utf-8")
    code, _out, err = _capture(lambda: dispatch(work, "refresh", []))
    if code != 3 or (work / LIST).exists() or not (work / URL).is_file():
        fail("bad migrate")
    (work / URL).unlink()
    (work / LIST).write_text("axs-subscriptions 1\n", encoding="utf-8")
    code, _out, err = _capture(lambda: dispatch(work, "refresh", []))
    if code != 3 or err != "没有订阅\n":
        fail("no active " + err)
    (work / LIST).write_text("OLD\n", encoding="utf-8")
    snapshot(work)
    (work / LIST).write_text("NEW\n", encoding="utf-8")
    restore_snapshot(work)
    if (work / LIST).read_text(encoding="utf-8") != "OLD\n":
        fail("snap list")


def main():
    check_forward()
    check_names()
    with tempfile.TemporaryDirectory(prefix="axs-sub-") as tmp:
        work = Path(tmp)
        check_merge(work)
        check_install_and_rollback(work)
        check_url_reject(work)
        check_soon(work)
    with tempfile.TemporaryDirectory(prefix="axs-list-") as tmp:
        check_list(Path(tmp))
    print("subscription ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
