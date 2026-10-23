#!/usr/bin/env python3
"""Subscription merge, cleanup names, and rollback. No network."""
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))
from axs.config import (  # noqa: E402
    CONFIG,
    CONFIG_BAK,
    DEFAULT_API,
    DEFAULT_DNS_LISTEN,
    DEFAULT_MIXED,
    write_defaults,
    FETCH_BODY,
    FETCH_HEADER,
    PID,
    PREPEND,
    SUBSCRIPTION,
    URL,
    USERINFO,
)
from axs.subscription import (  # noqa: E402
    build_file,
    check_url,
    clean_names,
    clear_fetch,
    install_merged,
    rollback,
    take_snapshot,
)

CIDRS = [
    "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
    "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
    "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
    "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
    "IP-CIDR6,::1/128,DIRECT,no-resolve",
    "IP-CIDR6,fc00::/7,DIRECT,no-resolve",
    "IP-CIDR6,fe80::/10,DIRECT,no-resolve",
]


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
        ROOT / "tests" / "fixtures" / "subscription.yaml",
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
    config = (CONFIG, CONFIG_BAK, USERINFO, FETCH_BODY, FETCH_HEADER, PID)
    sub = (URL, SUBSCRIPTION, USERINFO, FETCH_BODY, FETCH_HEADER)
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


def main():
    check_forward()
    check_names()
    with tempfile.TemporaryDirectory(prefix="axs-sub-") as tmp:
        work = Path(tmp)
        check_merge(work)
        check_install_and_rollback(work)
        check_url_reject(work)
    print("subscription ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
