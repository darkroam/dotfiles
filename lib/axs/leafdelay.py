"""Leaf delays from Selector measurements. First valid integer wins, in G# order."""

import json
import os
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

from axs.mihomo import DELAY, GROUP, _QUIET, request
from axs.nodes import _is_group, group_numbers, node_numbers


def workers():
    raw = os.environ.get("AXS_TEST_WORKERS", "").strip()
    try:
        value = int(raw) if raw else 8
    except ValueError:
        return 8
    return value if 1 <= value <= 32 else 8


def delay_ms():
    raw = os.environ.get("AXS_DELAY_TIMEOUT_MS", "").strip()
    try:
        value = int(raw)
    except ValueError:
        return 5000
    return value if value > 0 else 5000


def coverage(proxies):
    _order, owned = mapping(proxies)
    leaves = node_numbers(proxies)
    covered = sum(name in owned for name in leaves)
    return covered, len(leaves)


def mapping(proxies):
    numbers = group_numbers(proxies)
    order = [
        name for name in sorted(numbers, key=numbers.get)
        if isinstance(proxies.get(name), dict) and proxies[name].get("type") == "Selector"
    ]
    owned = {}
    for group in order:
        item = proxies.get(group)
        members = item.get("all") if isinstance(item, dict) else None
        if not isinstance(members, list):
            continue
        for member in members:
            if not isinstance(member, str) or _is_group(proxies.get(member)):
                continue
            if not isinstance(proxies.get(member), dict):
                continue
            names = owned.setdefault(member, [])
            if group not in names:
                names.append(group)
    return order, owned


def split(proxies, names):
    order, owned = mapping(proxies)
    if len(names) == 1:
        return list(owned.get(names[0], ())), []
    wanted = set(names)
    groups = [group for group in order if any(group in owned.get(name, ()) for name in wanted)]
    return groups, []


def measure(secret, api, proxies, names, url, timeout, worker_count, on_step=None):
    groups, _skip = split(proxies, names)
    found = _groups(secret, api, groups, url, timeout, worker_count, on_step)
    _order, owned = mapping(proxies)
    rows = {}
    for name in names:
        rows[name] = _pick(name, owned[name], found) if name in owned else (None, "不可选")
    return [(name, rows[name][0], rows[name][1]) for name in names]


def classify(code):
    text = code if isinstance(code, str) else ""
    prefix = "控制器失败：HTTP "
    if text.startswith(prefix):
        number = text[len(prefix):].strip()
        if number == "503":
            return "不可测"
        if number == "504":
            return "超时"
        return "HTTP " + number
    return text or "超时"


def _pick(leaf, groups, found):
    first = None
    for group in groups:
        payload, reason = found.get(group, (None, "超时"))
        if isinstance(payload, dict) and leaf in payload and type(payload[leaf]) is int:
            return payload[leaf], ""
        if first is not None:
            continue
        if not isinstance(payload, dict):
            first = reason or "超时"
        elif leaf not in payload:
            first = "未覆盖"
        else:
            first = "超时"
    return None, first or "超时"


def _groups(secret, api, groups, url, timeout, worker_count, on_step):
    def fetch(group):
        return _get(secret, api, _group_path(group, url), timeout)

    return _run(groups, fetch, worker_count, on_step)


def _run(items, fetch, worker_count, on_step):
    found = {}
    if not items:
        return found

    def finish(key, value):
        found[key] = value
        if on_step:
            on_step()

    if len(items) == 1:
        finish(items[0], fetch(items[0]))
        return found
    workers = max(1, min(worker_count, len(items)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(fetch, key): key for key in items}
        for future in as_completed(futures):
            finish(futures[future], future.result())
    return found


def _get(secret, api, path, timeout):
    token = _QUIET.set(True)
    try:
        raw = request(secret, api, "GET", path, timeout=timeout)
    except SystemExit as exc:
        return None, classify(exc.code)
    finally:
        _QUIET.reset(token)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        return None, "超时"
    if not isinstance(payload, dict):
        return None, "超时"
    return payload, ""


def _group_path(group, url):
    quoted = urllib.parse.quote(group, safe="")
    query = urllib.parse.urlencode({"timeout": str(delay_ms()), "url": url})
    return f"{GROUP}{quoted}{DELAY}?{query}"
