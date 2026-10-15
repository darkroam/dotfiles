#!/usr/bin/env python3
"""Offline merge assertions. Reads the fixture, never the network."""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib"))
import merge  # noqa: E402

CIDRS = [
    "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
    "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
    "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
    "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
    "IP-CIDR6,::1/128,DIRECT,no-resolve",
    "IP-CIDR6,fc00::/7,DIRECT,no-resolve",
    "IP-CIDR6,fe80::/10,DIRECT,no-resolve",
]
PREPEND = [
    "DOMAIN-SUFFIX,localhost,DIRECT",
    "DOMAIN-SUFFIX,local,DIRECT",
    "DOMAIN-SUFFIX,goproxy.cn,DIRECT",
    "DOMAIN-SUFFIX,ghproxy.com,DIRECT",
    "DOMAIN-SUFFIX,gh-proxy.com,DIRECT",
]


def main():
    work = Path(sys.argv[1])
    secret = "test-secret-value"
    (work / "secret").write_text(secret + "\n", encoding="utf-8")
    (work / "rules.list").write_text(
        "DOMAIN-SUFFIX added.example PROXY\n", encoding="utf-8"
    )
    override = work / "override.yaml"
    merged = work / "out.yaml"
    merge.write_defaults(override, "7897", "127.0.0.1:9097")
    merge.build_file(
        ROOT / "tests" / "fixtures" / "subscription.yaml",
        override,
        work / "secret",
        work / "rules.list",
        merged,
    )
    data = yaml.safe_load(merged.read_text(encoding="utf-8"))
    expect = {
        "mode": "rule",
        "mixed-port": 7897,
        "allow-lan": False,
        "ipv6": True,
        "log-level": "info",
        "external-controller": "127.0.0.1:9097",
        "secret": secret,
    }
    for key, value in expect.items():
        if data.get(key) != value:
            raise SystemExit(f"{key}: {data.get(key)!r}")
    if data["dns"]["enable"] is not True or data["dns"]["listen"] != "127.0.0.1:1053":
        raise SystemExit(f"dns: {data['dns']!r}")
    if data["dns"]["nameserver"] != ["192.0.2.53"]:
        raise SystemExit("nameserver overwritten")
    if data["tun"] != {"enable": False}:
        raise SystemExit(f"tun: {data['tun']!r}")
    for key in ("port", "socks-port", "redir-port", "tproxy-port", "prepend-rules"):
        if key in data:
            raise SystemExit(f"left {key}")
    rules = data["rules"]
    head = CIDRS + PREPEND + ["DOMAIN-SUFFIX,added.example,PROXY", "MATCH,PROXY"]
    if rules != head:
        raise SystemExit("rule order\n" + "\n".join(rules))
    if rules.count("DOMAIN-SUFFIX,localhost,DIRECT") != 1:
        raise SystemExit("localhost duplicated")
    if "from-sub-should-not-win" in merged.read_text(encoding="utf-8"):
        raise SystemExit("subscription secret leaked into config")
    if "canary.invalid" in merged.read_text(encoding="utf-8"):
        raise SystemExit("url leaked into config")
    print("merge ok")


if __name__ == "__main__":
    main()
