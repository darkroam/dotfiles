"""Leaf and group delay tests. Does not switch or edit config."""

from axs.codes import DOWN, FAIL, USAGE
from axs.config import SECRET, api_address, read_ports
from axs.core import service_up
from axs.leafdelay import measure, split, workers as _workers
from axs.mihomo import DELAY, GROUP, load_proxies, read_secret, request
from axs.nodes import AUTO_LABEL, _ansi, _as_exit3, _is_group, _prefixed, delay_code, lookup_group, node_numbers, write_node_cache
from axs.nodelist import render_rows
from axs.progress import Progress
from axs.render import call_usage, die, ident
import contextlib
import io
import json
import os
import sys
import urllib.parse
from pathlib import Path


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


_SKIP_TYPES = {"Compatible", "Pass", "Reject", "RejectDrop"}
_SKIP_PREFIX = ("剩余流量", "网址", "过期时间", "回家页")


def testable(name, proxies):
    item = proxies.get(name)
    if not isinstance(item, dict) or item.get("type") in _SKIP_TYPES:
        return False
    return not name.startswith(_SKIP_PREFIX)


def run_tests(secret, api, proxies, names, url, progress=False):
    groups, _skip = split(proxies, names)
    bar = Progress(len(groups), "测速") if progress else None
    try:
        return measure(
            secret, api, proxies, names, url, delay_timeout(), _workers(),
            bar.advance if bar else None,
        )
    finally:
        if bar:
            bar.finish()


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
        names = [name for name in sorted(numbers, key=numbers.get) if testable(name, proxies)]
    else:
        name, err = resolve_leaf(proxies, tokens[0])
        if err == "usage":
            _usage()
        if err or not testable(name, proxies):
            die(FAIL, "节点不存在")
        names = [name]
    url = os.environ.get("AXS_DELAY_URL") or DELAY_URL
    secret = read_secret(secret_path, api)
    rows = run_tests(secret, api, proxies, names, url, flag)
    sys.stdout.write(render_rows(numbers, rows, flag))
    lines = [f"{name} {delay}" for name, delay, _reason in rows if type(delay) is int]
    ok = all(delay is not None for _name, delay, _reason in rows)
    write_node_cache(Path(run) / "cache" / "node-test", "", lines, ok)
    if not ok:
        raise SystemExit(FAIL)


DELAY_URL = "https://www.gstatic.com/generate_204"


def delay_path(group, url, timeout="5000"):
    quoted = urllib.parse.quote(group, safe="")
    query = urllib.parse.urlencode({"timeout": str(timeout), "url": url})
    return f"{GROUP}{quoted}{DELAY}?{query}"


def delay_timeout():
    raw = os.environ.get("AXS_DELAY_TIMEOUT", "").strip()
    try:
        value = int(raw)
    except ValueError:
        return 60
    return value if value > 0 else 60


def _fail(message):
    from axs.core import fail
    fail(message)


def pick_test_group(proxies):
    groups = {name: item for name, item in proxies.items() if _is_group(item)}
    if "主代理" in groups:
        return "主代理"
    autos = sorted(name for name, item in groups.items() if item.get("type") in AUTO_LABEL)
    if autos:
        return autos[0]
    others = sorted(name for name in groups if name != "GLOBAL")
    return others[0] if others else None


def default_group(secret_path, api):
    try:
        proxies = load_proxies(secret_path, api)
    except SystemExit as exc:
        _as_exit3(exc)
    name = pick_test_group(proxies)
    if name:
        sys.stdout.write(name + "\n")
        return
    listed = sorted(name for name, item in proxies.items() if _is_group(item))
    sys.stderr.write("没有可测组\n" + "".join(name + "\n" for name in listed))
    raise SystemExit(FAIL)


def delay(secret_path, api, group, url):
    secret = read_secret(secret_path, api)
    try:
        raw = request(secret, api, "GET", delay_path(group, url), timeout=delay_timeout())
    except SystemExit:
        raise SystemExit(FAIL)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        _fail("控制器失败：响应格式错误")
    if not isinstance(payload, dict):
        _fail("控制器失败：响应格式错误")
    for name, value in payload.items():
        try:
            shown = str(int(value))
            code = delay_code(value)
        except (TypeError, ValueError):
            shown = "超时"
            code = "31"
        title = ident(name) if name == group else name
        sys.stdout.write(f"{title} {_ansi(code, shown)}\n")


def _capture(func, *args):
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            func(*args)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
        return code, buf.getvalue()
    return 0, buf.getvalue()


def run_group(run, args):
    if not service_up(run):
        die(DOWN, "服务：未运行")
    _mixed, api = read_ports(run)
    secret_path = Path(run) / SECRET
    group = args[0] if args else ""
    if group:
        code, out = _capture(lookup_group, secret_path, api, group)
    else:
        code, out = _capture(default_group, secret_path, api)
    if code:
        raise SystemExit(code)
    group = out.strip("\n")
    if not group:
        die(FAIL, "组名不存在")
    url = os.environ.get("AXS_DELAY_URL") or DELAY_URL
    code, out = _capture(delay, Path(run) / SECRET, api, group, url)
    sys.stdout.write(out)
    if code == 0:
        write_node_cache(Path(run) / "cache" / "node-test", group, out.splitlines())
        return
    write_node_cache(Path(run) / "cache" / "node-test", "", [], False)
    raise SystemExit(code)
