"""Group delay tests. Does not switch or edit config."""

import json
import os
import sys
import urllib.parse
from pathlib import Path

from axs.codes import DOWN, FAIL, USAGE
from axs.config import SECRET, api_address
from axs.core import fail, service_up
from axs.leafdelay import delay_timeout
from axs.mihomo import DELAY, GROUP, load_proxies, read_secret, request
from axs.nodes import _ansi, _is_group, delay_code, group_numbers, resolve_group_name, write_node_cache
from axs.progress import Progress
from axs.render import call_usage, die, ident

DELAY_URL = "https://www.gstatic.com/generate_204"


def delay_path(group, url, timeout="5000"):
    quoted = urllib.parse.quote(group, safe="")
    query = urllib.parse.urlencode({"timeout": str(timeout), "url": url})
    return f"{GROUP}{quoted}{DELAY}?{query}"


def resolve_test_group(proxies, token):
    if token in proxies and _is_group(proxies.get(token)):
        return token, ""
    if token.isascii() and token.isdigit():
        return None, "usage"
    return resolve_group_name(proxies, token)


def _usage():
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        text = call_usage("group", "test")
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
    sys.stderr.write(text + "\n")
    raise SystemExit(USAGE)


def _split(args):
    flag = "--all" in args
    tokens = [arg for arg in args if arg != "--all"]
    if flag == bool(tokens) or len(tokens) > 1:
        _usage()
    return flag, tokens


def _payload(secret, api, group, url):
    try:
        raw = request(secret, api, "GET", delay_path(group, url), timeout=delay_timeout())
    except SystemExit:
        raise SystemExit(FAIL)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        fail("控制器失败：响应格式错误")
    if not isinstance(payload, dict):
        fail("控制器失败：响应格式错误")
    return payload


def _rows(proxies, group, payload):
    lines, cached = [], []
    for name, value in payload.items():
        try:
            number = int(value)
            shown, code = str(number), delay_code(value)
        except (TypeError, ValueError):
            number, shown, code = None, "超时", "31"
        title = ident(name) if name == group else name
        lines.append(f"{title} {_ansi(code, shown)}")
        if number is not None and not _is_group(proxies.get(name)):
            cached.append(f"{name} {number}")
    return lines, cached


def _load(run):
    api = api_address(run)
    if not api:
        die(FAIL, "控制器失败")
    try:
        proxies = load_proxies(Path(run) / SECRET, api)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else FAIL
        raise SystemExit(FAIL if code == USAGE else code)
    return api, proxies


def _one(run, secret, api, proxies, group, url):
    dest = Path(run) / "cache" / "node-test"
    try:
        payload = _payload(secret, api, group, url)
    except SystemExit as exc:
        write_node_cache(dest, "", [], False)
        raise SystemExit(exc.code if isinstance(exc.code, int) else FAIL)
    lines, cached = _rows(proxies, group, payload)
    sys.stdout.write("".join(line + "\n" for line in lines))
    write_node_cache(dest, group, cached)


def _all(run, secret, api, proxies, url):
    numbers = group_numbers(proxies)
    groups = sorted(numbers, key=numbers.get)
    bar = Progress(len(groups), "测速")
    chunks, cached = [], []
    dest = Path(run) / "cache" / "node-test"
    try:
        for group in groups:
            kind = str(proxies[group].get("type") or "-")
            chunks.append(f"G{numbers[group]} {group} [{kind}]")
            lines, extra = _rows(proxies, group, _payload(secret, api, group, url))
            chunks.extend(lines)
            cached.extend(extra)
            bar.advance()
    except SystemExit as exc:
        write_node_cache(dest, "", [], False)
        raise SystemExit(exc.code if isinstance(exc.code, int) else FAIL)
    finally:
        bar.finish()
    sys.stdout.write("\n".join(chunks) + ("\n" if chunks else ""))
    write_node_cache(dest, "", cached)


def run(run_dir, args):
    flag, tokens = _split(args)
    if not service_up(run_dir):
        die(DOWN, "服务：未运行")
    api, proxies = _load(run_dir)
    url = os.environ.get("AXS_DELAY_URL") or DELAY_URL
    secret = read_secret(Path(run_dir) / SECRET, api)
    if flag:
        _all(run_dir, secret, api, proxies, url)
        return
    group, err = resolve_test_group(proxies, tokens[0])
    if err == "usage":
        _usage()
    if err:
        die(FAIL, err)
    _one(run_dir, secret, api, proxies, group, url)
