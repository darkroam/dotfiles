"""Defaults, run-file names, and the four port reads. No network and no color."""
import os
from pathlib import Path

import yaml

DEFAULT_MIXED = 7897
DEFAULT_API = "127.0.0.1:9097"
DEFAULT_DNS_LISTEN = "127.0.0.1:1053"
PREPEND = (
    "DOMAIN-SUFFIX,localhost,DIRECT",
    "DOMAIN-SUFFIX,local,DIRECT",
    "DOMAIN-SUFFIX,goproxy.cn,DIRECT",
    "DOMAIN-SUFFIX,ghproxy.com,DIRECT",
    "DOMAIN-SUFFIX,gh-proxy.com,DIRECT",
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
CACHE = "cache"
SYSTEM_FLAG = "proxy-system.flag"
SESSION_FLAG = "proxy-session.flag"
SNAP_NAMES = (CONFIG, SUBSCRIPTION, RULES)
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
    CACHE,
    SYSTEM_FLAG,
    SESSION_FLAG,
    FETCH_BODY,
    FETCH_HEADER,
    URLS,
    LEGACY_SYSTEM_FLAG,
    LEGACY_SESSION_FLAG,
)


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


def write_override(path, mixed, api):
    if not str(api).startswith("127.0.0.1:"):
        raise ValueError("控制器必须在本机回环")
    from axs.core import atomic_write

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


def write_defaults(path, mixed, api):
    try:
        write_override(path, mixed, api)
    except ValueError as exc:
        from axs.core import fail

        fail(str(exc))
