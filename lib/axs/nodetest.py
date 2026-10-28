"""Leaf delay tests. Does not switch or edit config."""

import json
import os
import sys
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from axs.codes import DOWN, FAIL, USAGE
from axs.config import SECRET, api_address
from axs.core import service_up
from axs.leafdelay import classify, delay_ms, delay_timeout, workers
from axs.mihomo import DELAY, PROXIES, _QUIET, load_proxies, read_secret, request
from axs.nodes import _is_group, _prefixed, group_numbers, node_numbers, write_node_cache
from axs.nodelist import render_rows
from axs.progress import Progress
from axs.render import call_usage, die

DELAY_URL = "https://www.gstatic.com/generate_204"
_SKIP_TYPES = {"Compatible", "Pass", "Reject", "RejectDrop"}
_SKIP_PREFIX = ("剩余流量", "网址", "过期时间", "回家页")


def resolve_leaf(proxies, token):
    numbers = node_numbers(proxies)
    if token in numbers:
        return token, ""
    if token.isascii() and token.isdigit():
        return None, "usage"
    if _is_group(proxies.get(token)):
        return None, "usage"
    wanted = _prefixed(token, "N")
    if wanted is not None:
        for name, number in numbers.items():
            if number == wanted:
                return name, ""
    return None, "missing"


def testable(name, proxies):
    item = proxies.get(name)
    if not isinstance(item, dict) or item.get("type") in _SKIP_TYPES:
        return False
    return not name.startswith(_SKIP_PREFIX)


def selectable(proxies):
    numbers = group_numbers(proxies)
    found, ordered = set(), []
    for group in sorted(numbers, key=numbers.get):
        item = proxies.get(group)
        if not isinstance(item, dict) or item.get("type") != "Selector" or group == "GLOBAL":
            continue
        members = item.get("all")
        if not isinstance(members, list):
            continue
        for member in members:
            if not isinstance(member, str) or member in found:
                continue
            if not testable(member, proxies) or _is_group(proxies.get(member)):
                continue
            found.add(member)
            ordered.append(member)
    return ordered


def partition(proxies):
    chosen = set(selectable(proxies))
    numbers = node_numbers(proxies)
    leaves = [name for name in sorted(numbers, key=numbers.get) if testable(name, proxies)]
    return [name for name in leaves if name in chosen], [name for name in leaves if name not in chosen]


def proxy_path(name, url):
    quoted = urllib.parse.quote(name, safe="")
    query = urllib.parse.urlencode({"timeout": str(delay_ms()), "url": url})
    return f"{PROXIES}/{quoted}{DELAY}?{query}"


def one_delay(secret, api, name, url, timeout):
    token = _QUIET.set(True)
    try:
        raw = request(secret, api, "GET", proxy_path(name, url), timeout=timeout)
    except SystemExit as exc:
        return None, classify(exc.code)
    finally:
        _QUIET.reset(token)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        return None, "超时"
    if isinstance(payload, dict) and type(payload.get("delay")) is int:
        return payload["delay"], ""
    return None, "超时"


def run_tests(secret, api, names, url, progress=False):
    bar = Progress(len(names), "测速") if progress else None
    found = {}

    def finish(name, value):
        found[name] = value
        if bar:
            bar.advance()

    try:
        if len(names) <= 1:
            for name in names:
                finish(name, one_delay(secret, api, name, url, delay_timeout()))
            return [(name, found[name][0], found[name][1]) for name in names]
        pool = ThreadPoolExecutor(max_workers=max(1, min(workers(), len(names))))
        try:
            futures = {pool.submit(one_delay, secret, api, name, url, delay_timeout()): name for name in names}
            for future in as_completed(futures):
                finish(futures[future], future.result())
        finally:
            pool.shutdown(wait=True)
    finally:
        if bar:
            bar.finish()
    return [(name, found[name][0], found[name][1]) for name in names]


def _usage():
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        text = call_usage("node", "test")
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
    sys.stderr.write(text + "\n")
    raise SystemExit(USAGE)


def cmd_test(run, args):
    flag = "--all" in args
    tokens = [arg for arg in args if arg != "--all"]
    if flag == bool(tokens) or len(tokens) > 1:
        _usage()
    if not service_up(run):
        die(DOWN, "服务：未运行")
    api = api_address(run)
    if not api:
        die(FAIL, "控制器失败")
    secret_path = Path(run) / SECRET
    try:
        proxies = load_proxies(secret_path, api)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else FAIL
        raise SystemExit(FAIL if code == USAGE else code)
    if flag:
        chosen, skipped = partition(proxies)
        names = chosen
    else:
        name, err = resolve_leaf(proxies, tokens[0])
        if err == "usage":
            _usage()
        if err or not testable(name, proxies):
            die(FAIL, "节点不存在")
        if name not in set(selectable(proxies)):
            chosen, skipped, names = [], [name], []
        else:
            chosen, skipped, names = [name], [], [name]
    url = os.environ.get("AXS_DELAY_URL") or DELAY_URL
    secret = read_secret(secret_path, api)
    rows = run_tests(secret, api, names, url, flag)
    rows.extend((name, None, "不可选") for name in skipped)
    sys.stdout.write(render_rows(node_numbers(proxies), rows, flag))
    cached = [f"{name} {delay}" for name, delay, _reason in rows if type(delay) is int]
    ok = all(delay is not None for _name, delay, _reason in rows)
    write_node_cache(Path(run) / "cache" / "node-test", "", cached, ok)
    if not ok:
        raise SystemExit(FAIL)
