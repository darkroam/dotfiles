"""Leaf delay tests. Does not switch or edit config."""

from axs.codes import DOWN, FAIL, USAGE
from axs.config import SECRET, api_address
from axs.core import service_up
from axs.mihomo import DELAY, PROXIES, _QUIET, delay_timeout, load_proxies, read_secret, request
from axs.nodes import DELAY_URL, _is_group, _prefixed, delay_code, node_numbers, write_node_cache
from axs.render import bold, call_usage, die, tone
import json
import os
import sys
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def _workers():
    raw = os.environ.get("AXS_TEST_WORKERS", "").strip()
    try:
        value = int(raw) if raw else 8
    except ValueError:
        return 8
    return value if 1 <= value <= 32 else 8


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


def _measure(secret, api, name, url):
    quoted = urllib.parse.quote(name, safe="")
    query = urllib.parse.urlencode({"timeout": "5000", "url": url})
    path = f"{PROXIES}/{quoted}{DELAY}?{query}"
    token = _QUIET.set(True)
    try:
        raw = request(secret, api, "GET", path, timeout=delay_timeout())
    except SystemExit as exc:
        reason = exc.code if isinstance(exc.code, str) and exc.code else "超时"
        return None, reason
    finally:
        _QUIET.reset(token)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        return None, "超时"
    value = payload.get("delay") if isinstance(payload, dict) else None
    if type(value) is not int:
        return None, "超时"
    return value, ""


def render_rows(numbers, rows, heading):
    width = len(str(max(numbers.values()))) if numbers else 1
    lines = [bold("测速（全部叶子）")] if heading else []
    ordered = sorted(rows, key=lambda item: numbers[item[0]])
    for name, delay, reason in ordered:
        if delay is None:
            plain = reason or "超时"
            shown = tone("31", plain)
        else:
            plain = f"{delay}ms"
            shown = tone(delay_code(delay), plain)
        label = f"N{numbers[name]:>{width}}"
        lines.append(f"{label} {name} {shown}")
    return "\n".join(lines) + ("\n" if lines else "")


def run_tests(secret, api, numbers, names, url):
    found = {}

    def fetch(name):
        delay, reason = _measure(secret, api, name, url)
        return name, delay, reason

    if len(names) < 2:
        for name in names:
            found[name] = fetch(name)[1:]
    else:
        workers = max(1, min(_workers(), len(names)))
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(fetch, name) for name in names]
            for future in as_completed(futures):
                name, delay, reason = future.result()
                found[name] = (delay, reason)
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
    numbers = node_numbers(proxies)
    if flag:
        names = sorted(numbers, key=numbers.get)
    else:
        name, err = resolve_leaf(proxies, tokens[0])
        if err == "usage":
            _usage()
        if err:
            die(FAIL, "节点不存在")
        names = [name]
    url = os.environ.get("AXS_DELAY_URL") or DELAY_URL
    secret = read_secret(secret_path, api)
    rows = run_tests(secret, api, numbers, names, url)
    sys.stdout.write(render_rows(numbers, rows, flag))
    lines = [f"{name} {delay}" for name, delay, _reason in rows if type(delay) is int]
    ok = all(delay is not None for _name, delay, _reason in rows)
    write_node_cache(Path(run) / "cache" / "node-test", "", lines, ok)
    if not ok:
        raise SystemExit(FAIL)
