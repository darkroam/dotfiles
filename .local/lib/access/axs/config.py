"""Defaults, paths, kernel binary, and the four port reads. No network and no color."""
import os
from pathlib import Path

import yaml

DEFAULT_MIXED = 7897
# IPv4 host written into URLs and controller checks. Not the whole allow-list.
LOOPBACK = "127.0.0.1"
_BYPASS_HOSTS = ("localhost", LOOPBACK, "::1")
# Names treated as on-box. Membership test, not an address string.
LOOPBACK_HOSTS = frozenset(_BYPASS_HOSTS)
BYPASS = ",".join(_BYPASS_HOSTS)
DEFAULT_API = LOOPBACK + ":9097"
DEFAULT_DNS_LISTEN = LOOPBACK + ":1053"
SOCKS5 = "socks5://"
PREPEND = (
    "DOMAIN-SUFFIX,localhost,DIRECT",
    "DOMAIN-SUFFIX,local,DIRECT",
    "DOMAIN-SUFFIX,goproxy.cn,DIRECT",
    "DOMAIN-SUFFIX,ghproxy.com,DIRECT",
    "DOMAIN-SUFFIX,gh-proxy.com,DIRECT",
)
CIDRS = [
    "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
    "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
    "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
    "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
    "IP-CIDR6," + next(host for host in LOOPBACK_HOSTS if ":" in host) + "/128,DIRECT,no-resolve",
    "IP-CIDR6,fc00::/7,DIRECT,no-resolve",
    "IP-CIDR6,fe80::/10,DIRECT,no-resolve",
]
RULE_WORDS = dict(
    pair.split()
    for pair in (
        "Domain DOMAIN|DomainSuffix DOMAIN-SUFFIX|DomainKeyword DOMAIN-KEYWORD|"
        "DomainRegex DOMAIN-REGEX|DomainWildcard DOMAIN-WILDCARD|GeoSite GEOSITE|"
        "GeoIP GEOIP|SrcGeoIP SRC-GEOIP|IPASN IP-ASN|SrcIPASN SRC-IP-ASN|"
        "IPCIDR IP-CIDR|SrcIPCIDR SRC-IP-CIDR|IPSuffix IP-SUFFIX|SrcIPSuffix SRC-IP-SUFFIX|"
        "SrcPort SRC-PORT|DstPort DST-PORT|InPort IN-PORT|DSCP DSCP|InUser IN-USER|"
        "InName IN-NAME|InType IN-TYPE|ProcessName PROCESS-NAME|ProcessPath PROCESS-PATH|"
        "ProcessNameRegex PROCESS-NAME-REGEX|ProcessPathRegex PROCESS-PATH-REGEX|"
        "ProcessNameWildcard PROCESS-NAME-WILDCARD|ProcessPathWildcard PROCESS-PATH-WILDCARD|"
        "RuleSet RULE-SET|Network NETWORK|Uid UID|SubRules SUB-RULE|Match MATCH|"
        "AND AND|OR OR|NOT NOT"
    ).split("|")
)

OVERRIDE = "override.yaml"
CONFIG = "config.yaml"
SUBSCRIPTION = "subscription.yaml"
RULES = "rules.list"
SECRET = "secret"
LOCK = "refresh.lock"
PID = "mihomo.pid"
SNAP = ".snap"
USERINFO = "userinfo"
URL = "subscription.url"
LIST = "subscriptions.list"
CACHE = "cache"
SYSTEM_FLAG = "proxy-system.flag"
SESSION_FLAG = "proxy-session.flag"
SNAP_NAMES = (CONFIG, SUBSCRIPTION, RULES, LIST)
FETCH_BODY = "fetch.yaml"
FETCH_HEADER = "fetch.hdr"
CONFIG_NEW = CONFIG + ".new"
CONFIG_BAK = CONFIG + ".bak"
URLS = "urls"
LEGACY_SYSTEM_FLAG = "gsettings-identity"
LEGACY_SESSION_FLAG = "session-proxy"
RUN_FILES = (
    OVERRIDE,
    CONFIG,
    CONFIG_BAK,
    CONFIG_NEW,
    SUBSCRIPTION,
    RULES,
    SECRET,
    LOCK,
    PID,
    SNAP,
    USERINFO,
    URL,
    LIST,
    CACHE,
    SYSTEM_FLAG,
    SESSION_FLAG,
    FETCH_BODY,
    FETCH_HEADER,
    URLS,
    LEGACY_SYSTEM_FLAG,
    LEGACY_SESSION_FLAG,
)


def mihomo_path():
    return os.environ.get("AXS_MIHOMO") or str(Path.home() / ".local" / "bin" / "mihomo")


def override_body(mixed, api):
    return {
        "mixed-port": int(mixed),
        "mode": "rule",
        "allow-lan": False,
        "log-level": "info",
        "ipv6": True,
        "external-controller": str(api),
        "tun": {"enable": False},
        "dns": {"enable": True, "listen": DEFAULT_DNS_LISTEN},
        "prepend-rules": list(PREPEND),
    }


def atomic_write(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, text.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, path)
    os.chmod(path, 0o600)


def write_override(path, mixed, api):
    if not str(api).startswith(LOOPBACK + ":"):
        raise ValueError("控制器必须在本机回环")
    text = yaml.safe_dump(override_body(mixed, api), allow_unicode=True, sort_keys=False)
    atomic_write(path, text)


def _env(env):
    return os.environ if env is None else env


def _field(path, key):
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    return data[key]


def ensure_run(run):
    path = Path(run)
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, 0o700)
    return path


def ensure_override(run, env=None):
    env = _env(env)
    run = ensure_run(run)
    path = run / OVERRIDE
    if path.is_file():
        return path
    mixed = env.get("AXS_MIXED_PORT") or DEFAULT_MIXED
    api = env.get("AXS_API") or DEFAULT_API
    write_override(path, mixed, api)
    return path


def read_ports(run, env=None):
    path = ensure_override(run, env)
    return str(_field(path, "mixed-port")), str(_field(path, "external-controller"))


def status_ports(run, env=None):
    env = _env(env)
    path = Path(run) / OVERRIDE
    if env.get("AXS_MIXED_PORT"):
        mixed = env["AXS_MIXED_PORT"]
    elif path.is_file():
        mixed = _field(path, "mixed-port")
    else:
        mixed = DEFAULT_MIXED
    if env.get("AXS_API"):
        api = env["AXS_API"]
    elif path.is_file():
        api = _field(path, "external-controller")
    else:
        api = DEFAULT_API
    return str(mixed), str(api)


def api_address(run, env=None):
    env = _env(env)
    if env.get("AXS_API"):
        return env["AXS_API"]
    path = Path(run) / OVERRIDE
    if not path.is_file():
        return None
    return str(_field(path, "external-controller"))


def proxy_mixed(run, env=None):
    return read_ports(run, env)[0]
