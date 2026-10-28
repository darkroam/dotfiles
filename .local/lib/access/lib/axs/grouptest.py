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
from axs.mihomo import DELAY, GROUP, _QUIET, load_proxies, read_secret, request
from axs.nodes import _is_group, group_numbers, resolve_group_name, write_node_cache
from axs.nodelist import render_group_block
from axs.progress import Progress
from axs.render import call_usage, die

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
        sys.stderr.write(call_usage("group", "test") + "\n")
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
    raise SystemExit(USAGE)


def _split(args):
    flag = "--all" in args
    tokens = [arg for arg in args if arg != "--all"]
    if flag == bool(tokens) or len(tokens) > 1:
        _usage()
    return flag, tokens


def _reason(exc):
    text = exc.code if isinstance(exc.code, str) else ""
    if text.startswith("控制器失败"):
        return text
    return "控制器失败" if not text else "控制器失败：" + text


def _payload(secret, api, group, url, quiet=False):
    token = _QUIET.set(True) if quiet else None
    try:
        try:
            raw = request(secret, api, "GET", delay_path(group, url), timeout=delay_timeout())
        except SystemExit as exc:
            if not quiet:
                raise SystemExit(FAIL)
            return None, _reason(exc)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            payload = None
        if isinstance(payload, dict):
            return payload, ""
        if quiet:
            return None, "控制器失败：响应格式错误"
        fail("控制器失败：响应格式错误")
    finally:
        if token is not None:
            _QUIET.reset(token)


def _members(proxies, payload):
    members, cached = [], []
    for name, value in payload.items():
        number = value if type(value) is int else None
        is_group = _is_group(proxies.get(name))
        members.append((name, number, is_group))
        if number is not None and not is_group:
            cached.append(f"{name} {number}")
    return members, cached


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


def _show(numbers, proxies, group, payload, reason):
    kind = str(proxies[group].get("type") or "-")
    if reason:
        return render_group_block(numbers, group, kind, [], reason), []
    members, cached = _members(proxies, payload)
    return render_group_block(numbers, group, kind, members), cached


def _one(run, secret, api, proxies, group, url):
    dest = Path(run) / "cache" / "node-test"
    try:
        payload = _payload(secret, api, group, url)[0]
    except SystemExit as exc:
        write_node_cache(dest, "", [], False)
        raise SystemExit(exc.code if isinstance(exc.code, int) else FAIL)
    text, cached = _show(group_numbers(proxies), proxies, group, payload, "")
    sys.stdout.write(text + "\n")
    write_node_cache(dest, group, cached)


def _all(run, secret, api, proxies, url):
    numbers = group_numbers(proxies)
    groups = sorted(numbers, key=numbers.get)
    bar = Progress(len(groups), "测速")
    chunks, cached, failed = [], [], False
    dest = Path(run) / "cache" / "node-test"
    try:
        for group in groups:
            payload, reason = _payload(secret, api, group, url, True)
            text, extra = _show(numbers, proxies, group, payload, reason)
            chunks.append(text)
            if reason:
                failed = True
            else:
                cached.extend(extra)
            bar.advance()
    finally:
        bar.finish()
    sys.stdout.write("\n\n".join(chunks) + ("\n" if chunks else ""))
    write_node_cache(dest, "", cached, not failed)
    if failed:
        raise SystemExit(FAIL)


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
