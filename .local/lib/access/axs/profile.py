"""Merged profile and rule-source words. No fetch and no controller calls."""

from pathlib import Path

import yaml

from axs.config import CIDRS, LOOPBACK, OVERRIDE, RULES, RULE_WORDS, atomic_write
from axs.core import fail

DROP_PORTS = ("port", "socks-port", "redir-port", "tproxy-port")


def merge_dict(base, over):
    if not isinstance(base, dict) or not isinstance(over, dict):
        return over
    out = dict(base)
    for key, value in over.items():
        if key == "prepend-rules":
            continue
        if isinstance(out.get(key), dict) and isinstance(value, dict):
            out[key] = merge_dict(out[key], value)
        else:
            out[key] = value
    return out


def load_profile(path):
    raw = Path(path).read_bytes()
    if raw.lstrip().startswith(b"<"):
        fail("校验失败")
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError:
        fail("校验失败")
    proxies = data.get("proxies") if isinstance(data, dict) else None
    if not isinstance(proxies, list) or not proxies:
        fail("校验失败")
    if not all(isinstance(item, dict) and item.get("server") for item in proxies):
        fail("校验失败")
    return data


def load_local_rules(path):
    path = Path(path)
    if not path.is_file():
        return []
    rules = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 3 or parts[0] not in ("DOMAIN", "DOMAIN-SUFFIX"):
            fail("校验失败")
        rules.append(f"{parts[0]},{parts[1]},{parts[2]}")
    return rules


def dedupe(items):
    seen = []
    for item in items:
        if item not in seen:
            seen.append(item)
    return seen


def build_file(sub_path, override_path, secret_path, rules_path, out_path):
    sub = load_profile(sub_path)
    over = yaml.safe_load(Path(override_path).read_text(encoding="utf-8"))
    if not isinstance(over, dict):
        fail("校验失败")
    secret = Path(secret_path).read_text(encoding="utf-8").strip()
    if len(secret) < 8:
        fail("校验失败")
    merged = merge_dict(sub, over)
    controller = merged.get("external-controller")
    if not isinstance(controller, str) or not controller.startswith(LOOPBACK + ":"):
        fail("校验失败")
    extra = over.get("prepend-rules") or []
    if not isinstance(extra, list):
        fail("校验失败")
    base_rules = merged.get("rules") or []
    if not isinstance(base_rules, list):
        fail("校验失败")
    merged["rules"] = dedupe(CIDRS + extra + load_local_rules(rules_path) + base_rules)
    merged.pop("prepend-rules", None)
    for key in DROP_PORTS:
        merged.pop(key, None)
    merged["tun"] = {"enable": False}
    merged["secret"] = secret
    merged["mode"] = over.get("mode") or "rule"
    atomic_write(out_path, yaml.safe_dump(merged, allow_unicode=True, sort_keys=False))


def rule_word(kind):
    text = "" if kind is None else str(kind)
    return RULE_WORDS.get(text, text.upper())


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
