"""Rule-target chains from the installed config and the live pool. No color."""

from pathlib import Path

import yaml

from axs.config import CONFIG
from axs.mihomo import GROUP_TYPES, rule_parts
from axs.nodes import AUTO_TYPES, _is_group, follow_leaf, group_numbers, node_numbers

_YAML = {
    "select": "Selector",
    "selector": "Selector",
    "url-test": "URLTest",
    "urltest": "URLTest",
    "fallback": "Fallback",
    "load-balance": "LoadBalance",
    "loadbalance": "LoadBalance",
    "relay": "Relay",
}


def _group_type(item):
    if not isinstance(item, dict):
        return ""
    kind = item.get("type")
    return kind if kind in GROUP_TYPES else ""


def _now(item):
    now = item.get("now") if isinstance(item, dict) else None
    return now if isinstance(now, str) and now else ""


def _yaml_type(raw):
    if raw in GROUP_TYPES:
        return raw
    return _YAML.get(str(raw).lower(), "")


def _load(run):
    path = Path(run) / CONFIG
    if not path.is_file():
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return None
    if not isinstance(data, dict) or not isinstance(data.get("rules"), list):
        return None
    lines = [item for item in data["rules"] if isinstance(item, str)]
    groups = {}
    rows = data.get("proxy-groups")
    if isinstance(rows, list):
        for row in rows:
            if isinstance(row, dict) and isinstance(row.get("name"), str):
                groups[row["name"]] = _yaml_type(row.get("type") or "")
    return lines, groups


def _bump(row, word):
    for index, (have, count) in enumerate(row):
        if have == word:
            row[index] = (have, count + 1)
            return
    row.append((word, 1))


def _walk(proxies, start):
    hops, seen, name = [], set(), start
    while name and name not in seen and _group_type(proxies.get(name)):
        seen.add(name)
        item = proxies[name]
        hops.append(name)
        now = _now(item)
        if item.get("type") in AUTO_TYPES:
            return hops, (follow_leaf(proxies, now) or "") if now else ""
        if not now or now in seen:
            return hops, ""
        if not _group_type(proxies.get(now)):
            return hops, now
        name = now
    return hops, ""


def _target(name, groups, gnums, nnums, counts, kinds, hops, leaf):
    return {
        "name": name,
        "type": groups.get(name) or "",
        "gnum": gnums.get(name),
        "count": counts[name],
        "kinds": list(kinds[name]),
        "hops": [
            {"name": hop, "type": groups.get(hop) or "", "gnum": gnums.get(hop)}
            for hop in hops
        ],
        "leaf": {"name": leaf, "nnum": nnums.get(leaf)} if leaf else None,
    }


def build(proxies, run):
    loaded = _load(run)
    if loaded is None:
        return None
    lines, yaml_groups = loaded
    # Empty pool: controller is down, so the chain stays unresolved.
    live = bool(proxies)
    if live:
        groups = {name: _group_type(item) for name, item in proxies.items()}
        groups = {name: kind for name, kind in groups.items() if kind}
    else:
        groups = {name: kind for name, kind in yaml_groups.items() if kind}
    order, counts, kinds, other = [], {}, {}, 0
    for line in lines:
        parsed = rule_parts(line)
        if not parsed or not parsed[2]:
            continue
        policy = parsed[2]
        if policy not in groups:
            other += 1
            continue
        if policy not in counts:
            order.append(policy)
            counts[policy] = 0
            kinds[policy] = []
        counts[policy] += 1
        _bump(kinds[policy], str(parsed[0]).upper())
    gnums = group_numbers(proxies) if live else {}
    nnums = node_numbers(proxies) if live else {}
    targets, terminals = [], []
    for name in order:
        hops, leaf = _walk(proxies, name) if live else ([], "")
        last = hops[-1] if hops else ""
        if last and groups.get(last) in AUTO_TYPES and last not in terminals:
            terminals.append(last)
        targets.append(_target(name, groups, gnums, nnums, counts, kinds, hops, leaf))
    return {"live": live, "other": other, "terminals": terminals, "targets": targets}

def select_roots(proxies, origin):
    from axs.mihomo import rule_parts

    path = None if origin is None else Path(origin).parent / CONFIG
    if path is None or not path.is_file():
        return []
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return []
    rules = data.get("rules") if isinstance(data, dict) else None
    if not isinstance(rules, list):
        return []
    names, seen = [], set()
    for item in rules:
        parsed = rule_parts(item)
        name = parsed[2] if parsed else ""
        if name and name not in seen and _is_group(proxies.get(name)):
            seen.add(name)
            names.append(name)
    return names
