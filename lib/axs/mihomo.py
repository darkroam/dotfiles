"""Controller client. Rollback and rule meaning stay with the caller."""

from axs.codes import USAGE
from axs.config import CIDRS, LOOPBACK, OVERRIDE, RULES
import yaml
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PROXIES = "/proxies"
VERSION = "/version"
RELOAD = "/configs?force=true"
GROUP = "/group/"
DELAY = "/delay"
RULES_PATH = "/rules"


def proxies_path():
    return PROXIES


def version_path():
    return VERSION


def reload_path():
    return RELOAD


def select_path(name):
    return PROXIES + "/" + urllib.parse.quote(name, safe="")


def delay_path(group, url, timeout="5000"):
    quoted = urllib.parse.quote(group, safe="")
    query = urllib.parse.urlencode({"timeout": str(timeout), "url": url})
    return f"{GROUP}{quoted}{DELAY}?{query}"


def _fail(message):
    sys.stderr.write(message + "\n")
    raise SystemExit(USAGE)


def read_secret(secret_path, api):
    if not str(api).startswith(LOOPBACK + ":"):
        _fail("控制器必须在本机回环")
    path = Path(secret_path)
    if not path.is_file():
        _fail("控制器失败")
    secret = path.read_text(encoding="utf-8").strip()
    if len(secret) < 8:
        _fail("控制器失败")
    return secret


def _fake_exchange(method, path, secret, body=None):
    directory = Path(os.environ["AXS_FAKE_DIR"])
    flag = "yes" if secret and len(secret) >= 8 else "no"
    extra = ""
    if body:
        extra = " body=" + body.decode("utf-8", "replace")
    with (directory / "log").open("a", encoding="utf-8") as handle:
        handle.write(f"{method} {path} auth={flag}{extra}\n")
    if (directory / "down").is_file():
        _fail("控制器失败")
    pure = path.split("?", 1)[0]
    if method == "PUT" and pure.startswith(PROXIES + "/"):
        code_path = directory / "select"
        code = int(code_path.read_text(encoding="utf-8").strip() or "204") if code_path.is_file() else 204
        if code >= 300:
            _fail("控制器失败")
        return b""
    if method == "PUT":
        code = int((directory / "reload").read_text(encoding="utf-8").strip() or "204")
        if code >= 300:
            _fail("控制器失败")
        return b""
    if pure == VERSION:
        return b'{"version":"fake"}'
    if pure == PROXIES:
        ready = directory / "proxies.json"
        if ready.is_file():
            return ready.read_bytes()
        text = (directory / "groups").read_text(encoding="utf-8") if (directory / "groups").is_file() else ""
        payload = {
            name: {"type": "Selector", "now": "a", "all": ["a"]}
            for name in text.split()
        }
        return json.dumps({"proxies": payload}).encode()
    if pure.startswith(GROUP) and pure.endswith(DELAY):
        ready = directory / "delay.json"
        if ready.is_file():
            return ready.read_bytes()
        name = urllib.parse.unquote(pure[len(GROUP) : -len(DELAY)])
        delay = int((directory / "delay").read_text(encoding="utf-8").strip() or "0")
        return json.dumps({name: delay}).encode()
    if method == "GET" and pure == RULES_PATH:
        ready = directory / "rules.json"
        if ready.is_file():
            return ready.read_bytes()
    _fail("控制器失败")


def request(secret, api, method, path, body=None):
    if os.environ.get("AXS_FAKE_DIR"):
        return _fake_exchange(method, path, secret, body)
    req = urllib.request.Request(
        f"http://{api}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": "Bearer " + secret,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            raw = resp.read()
            if resp.status >= 300:
                _fail("控制器失败")
            return raw
    except urllib.error.HTTPError as exc:
        if exc.code >= 300:
            _fail("控制器失败")
        raise
    except (urllib.error.URLError, TimeoutError, OSError):
        _fail("控制器失败")


def probe(host, port):
    directory = os.environ.get("AXS_FAKE_DIR")
    if directory:
        listed = ""
        path = Path(directory) / "open-ports"
        if path.is_file():
            listed = path.read_text(encoding="utf-8")
        if str(port) not in listed.split():
            raise SystemExit(USAGE)
        return
    import socket

    sock = socket.socket()
    sock.settimeout(0.3)
    try:
        sock.connect((host, int(port)))
    except OSError:
        raise SystemExit(USAGE)
    finally:
        sock.close()


GROUP_TYPES = {"Selector", "URLTest", "Fallback", "LoadBalance", "Relay"}


def load_proxies(secret_path, api):
    secret = read_secret(secret_path, api)
    raw = request(secret, api, "GET", proxies_path())
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        _fail("控制器失败")
    proxies = payload.get("proxies") if isinstance(payload, dict) else None
    if not isinstance(proxies, dict):
        _fail("控制器失败")
    return proxies


def group_names(secret_path, api):
    proxies = load_proxies(secret_path, api)
    names = []
    for name, item in proxies.items():
        if isinstance(item, dict) and item.get("type") in GROUP_TYPES:
            names.append(name)
    return names


def reload_core(secret_path, api, config_path):
    secret = read_secret(secret_path, api)
    body = json.dumps({"path": str(config_path), "payload": ""}).encode()
    try:
        request(secret, api, "PUT", reload_path(), body)
    except SystemExit:
        _fail("重载失败")


def version_ok(secret_path, api):
    secret = read_secret(secret_path, api)
    try:
        request(secret, api, "GET", version_path())
    except SystemExit:
        failed = 3
        raise SystemExit(failed)


_RULE_WORDS = dict(
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


def rule_word(kind):
    text = "" if kind is None else str(kind)
    return _RULE_WORDS.get(text, text.upper())


def _rule_key(kind, payload, policy):
    word = rule_word("" if kind is None else str(kind))
    if word == "IP-CIDR6":
        word = "IP-CIDR"
    return word, "" if payload is None else str(payload), "" if policy is None else str(policy)


def rule_parts(text):
    if not isinstance(text, str) or not text.strip() or text.lstrip().startswith("#"):
        return None
    bits = [bit.strip() for bit in text.split(",")] if "," in text else text.split()
    if len(bits) >= 3:
        return bits[0], bits[1], bits[2]
    if len(bits) == 2 and bits[0].upper() == "MATCH":
        return bits[0], "", bits[1]
    return None


def _bag(lines):
    found = set()
    for line in lines:
        if not isinstance(line, str):
            continue
        parsed = rule_parts(line)
        if parsed:
            found.add(_rule_key(*parsed))
    return found


def _sources(run):
    run = Path(run)
    lines = list(CIDRS)
    path = run / OVERRIDE
    data = None
    if path.is_file():
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except yaml.YAMLError:
            data = None
    extra = data.get("prepend-rules") if isinstance(data, dict) else None
    if isinstance(extra, list):
        lines.extend(extra)
    local = (run / RULES).read_text(encoding="utf-8").splitlines() if (run / RULES).is_file() else []
    return _bag(lines), _bag(local)
