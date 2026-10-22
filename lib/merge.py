#!/usr/bin/env python3
"""Merge a subscription with the local override. Never prints the URL or secret."""
import http.client
import json
import os
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import yaml

from axs.core import atomic_write

DELAY_URL = "https://www.gstatic.com/generate_204"
DEFAULT_URLS = (
    "https://www.github.com",
    "https://www.google.com",
    "https://www.youtube.com",
)
GROUP_TYPES = {"Selector", "URLTest", "Fallback", "LoadBalance", "Relay"}
LOOPBACK = {"127.0.0.1", "localhost", "::1"}


def fail(message):
    sys.stderr.write(message + "\n")
    raise SystemExit(1)


from axs.mihomo import (  # noqa: E402
    delay_path,
    probe,
    proxies_path,
    read_secret as _api,
    reload_path,
    request as _request,
    select_path,
    version_path,
)

from axs.subscription import (  # noqa: E402
    build_file,
    check_fetched,
    check_url,
    classify,
    clean_names,
    clear_fetch,
    fetch,
    install_merged,
    rollback,
    show_userinfo,
    status_sub,
    take_snapshot,
    write_userinfo,
)

from axs.rules import (  # noqa: E402
    check,
    has_group,
    mutate,
    parse_rule,
    rules_add,
    rules_del,
)


def write_defaults(path, mixed, api):
    from axs.config import write_override

    try:
        write_override(path, mixed, api)
    except ValueError as exc:
        fail(str(exc))


def gen_secret(path):
    path = Path(path)
    if path.is_file() and len(path.read_text(encoding="utf-8").strip()) >= 8:
        os.chmod(path, 0o600)
        return
    import secrets

    atomic_write(path, secrets.token_hex(16) + "\n")


def load_proxies(secret_path, api):
    secret = _api(secret_path, api)
    raw = _request(secret, api, "GET", proxies_path())
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        fail("控制器")
    proxies = payload.get("proxies") if isinstance(payload, dict) else None
    if not isinstance(proxies, dict):
        fail("控制器")
    return proxies


def group_names(secret_path, api):
    proxies = load_proxies(secret_path, api)
    names = []
    for name, item in proxies.items():
        if isinstance(item, dict) and item.get("type") in GROUP_TYPES:
            names.append(name)
    return names


def _as_exit3(exc):
    code = exc.code if isinstance(exc.code, int) else 1
    raise SystemExit(3 if code == 1 else code)


def _now(item):
    now = item.get("now") if isinstance(item, dict) else None
    if not isinstance(now, str) or now == "":
        return "-"
    return now


def show_groups(secret_path, api):
    try:
        proxies = load_proxies(secret_path, api)
    except SystemExit as exc:
        _as_exit3(exc)
    rows = []
    for name in sorted(proxies):
        item = proxies[name]
        if not isinstance(item, dict) or item.get("type") not in GROUP_TYPES:
            continue
        now = _now(item)
        shown = dim(now) if now == "-" else emph("32", now)
        rows.append(f"{ident(name)}\t{dim(str(item.get('type')))}\t{shown}")
    if rows:
        sys.stdout.write("\n".join(rows) + "\n")


AUTO_LABEL = {
    "URLTest": "url-test",
    "Fallback": "fallback",
    "LoadBalance": "load-balance",
}


def node_numbers(proxies):
    names = sorted(
        name
        for name, item in proxies.items()
        if isinstance(item, dict) and item.get("type") not in GROUP_TYPES
    )
    return {name: index for index, name in enumerate(names, 1)}


def _show_nodes_full(proxies):
    rows = []
    for name, item in proxies.items():
        if not isinstance(item, dict) or item.get("type") in GROUP_TYPES:
            continue
        kind = item.get("type") or "-"
        hits = []
        for gname, gitem in proxies.items():
            if not isinstance(gitem, dict) or gitem.get("type") not in GROUP_TYPES:
                continue
            members = gitem.get("all") or []
            if isinstance(members, list) and name in members:
                star = "*" if gitem.get("now") == name else ""
                hits.append((gname, f"{star}\t{name}\t{kind}\t{gname}"))
        if hits:
            rows.extend((name, gname, line) for gname, line in hits)
        else:
            rows.append((name, "-", f"\t{name}\t{kind}\t-"))
    rows.sort()
    if rows:
        sys.stdout.write("\n".join(line for _, _, line in rows) + "\n")


def _is_group(item):
    return isinstance(item, dict) and item.get("type") in GROUP_TYPES


def follow_leaf(proxies, name):
    seen = set()
    while isinstance(name, str) and name and name not in seen:
        seen.add(name)
        item = proxies.get(name)
        if not isinstance(item, dict):
            return None
        if item.get("type") not in GROUP_TYPES:
            return name
        name = item.get("now")
    return None


def selection_parts(proxies):
    main = proxies.get("主代理")
    if not _is_group(main):
        return None, None
    now = main.get("now")
    target = proxies.get(now) if isinstance(now, str) and now else None
    if not isinstance(target, dict):
        return None, None
    kind = target.get("type")
    if kind in AUTO_LABEL:
        mid = f"{now}（自动，{AUTO_LABEL[kind]}）"
    else:
        mid = f"{now}（手动）"
    return mid, follow_leaf(proxies, now)


def current_selection(proxies, numbers):
    mid, leaf = selection_parts(proxies)
    if mid is None:
        return "当前：无", None
    if leaf in numbers:
        return f"当前：主代理 → {mid}→ {leaf} 第{numbers[leaf]}个", leaf
    return f"当前：主代理 → {mid}→ -", None


def pick_test_group(proxies):
    groups = {
        name: item
        for name, item in proxies.items()
        if _is_group(item)
    }
    main = groups.get("主代理")
    if main is not None:
        return "主代理"
    autos = sorted(name for name, item in groups.items() if item.get("type") in AUTO_LABEL)
    if autos:
        return autos[0]
    others = sorted(name for name in groups if name != "GLOBAL")
    if others:
        return others[0]
    return None


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
    sys.stderr.write("没有可测组\n")
    for name in listed:
        sys.stderr.write(name + "\n")
    raise SystemExit(3)


def want_color():
    mode = os.environ.get("AXS_COLOR")
    if mode == "always":
        return True
    if mode == "never":
        return False
    if "NO_COLOR" in os.environ:
        return False
    # Captured output is not a tty. The shell records the real stdout.
    if os.environ.get("AXS_TTY_OUT") == "1":
        return True
    return sys.stdout.isatty()


def ansi(code, text):
    if not want_color() or text == "":
        return text
    return f"\033[{code}m{text}\033[0m"


def label(text):
    return ansi("90", text)


def ident(text):
    return ansi("36", text)


def ok(text):
    return ansi("32", text)


def warn(text):
    return ansi("33", text)


def bad(text):
    return ansi("31", text)


def dim(text):
    return ansi("90", text)


def bold(text):
    return ansi("1", text)


def emph(code, text):
    return ansi(f"1;{code}", text)


def delay_code(value):
    try:
        number = int(value)
    except (TypeError, ValueError):
        return "90"
    if number < 100:
        return "32"
    if number <= 200:
        return "33"
    return "31"


def display_width(text):
    # shortcut: 制表符和组合字符按 1 列，名称里出现再改
    return sum(2 if unicodedata.east_asian_width(char) in ("W", "F") else 1 for char in text)


def term_cols():
    raw = os.environ.get("COLUMNS", "").strip()
    if raw.isdigit() and int(raw) > 0:
        return int(raw)
    try:
        out = subprocess.check_output(
            ["tput", "cols"], stderr=subprocess.DEVNULL, text=True, timeout=2
        ).strip()
    except (OSError, subprocess.SubprocessError, ValueError):
        out = ""
    if out.isdigit() and int(out) > 0:
        return int(out)
    return 80


def cache_path(run_dir):
    if not run_dir:
        return None
    path = Path(run_dir) / "cache" / "node-test"
    return path if path.is_file() else None


def load_delays(run_dir):
    path = cache_path(run_dir)
    if path is None:
        return {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.startswith("{"):
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            return {}
        if not isinstance(data, dict):
            return {}
        return data
    return {}


def speed_line(run_dir):
    path = cache_path(run_dir)
    if path is None:
        return "最近测速：-"
    ts = ""
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("ts="):
            ts = line[3:]
            break
    if not ts.isdigit():
        return "最近测速：-"
    age = int(time.time()) - int(ts)
    if age < 0:
        age = 0
    if age < 60:
        rel = f"{age} 秒前"
    elif age < 3600:
        rel = f"{age // 60} 分钟前"
    elif age < 86400:
        rel = f"{age // 3600} 小时前"
    else:
        rel = f"{age // 86400} 天前"
    return f"最近测速：{rel}"


def paint_cell(marker, num_text, name, delay_text, selected, delay_raw):
    plain = f"{marker}{num_text} {name} {delay_text}"
    if not want_color():
        return plain
    mark = emph("32", "[*]") + " " if selected else marker
    lead = len(num_text) - len(num_text.lstrip(" "))
    number = (" " * lead) + dim(num_text.lstrip(" "))
    shown = emph("32", name) if selected else name
    dlead = len(delay_text) - len(delay_text.lstrip(" "))
    body = delay_text.lstrip(" ")
    delay = (" " * dlead) + ansi(delay_code(delay_raw), body)
    return f"{mark}{number} {shown} {delay}"


def layout_cells(entries, width):
    if not entries:
        return []
    widest = max(display_width(plain) for plain, _ in entries)
    cols = max(1, (width + 2) // (widest + 2))
    lines = []
    row = []
    for index, item in enumerate(entries, 1):
        row.append(item)
        if len(row) != cols and index != len(entries):
            continue
        pieces = []
        for pos, (plain, colored) in enumerate(row):
            pad = ""
            if pos != len(row) - 1:
                pad = " " * (widest - display_width(plain))
            pieces.append(colored + pad)
        lines.append("  ".join(pieces))
        row = []
    return lines


def show_nodes(secret_path, api, mode=""):
    try:
        proxies = load_proxies(secret_path, api)
    except SystemExit as exc:
        _as_exit3(exc)
    if mode == "--full":
        _show_nodes_full(proxies)
        return
    numbers = node_numbers(proxies)
    head, star = current_selection(proxies, numbers)
    delays = load_delays(mode)
    shown = []
    for name in sorted(numbers, key=numbers.get):
        delay = delays.get(name, "-")
        if delay is None or delay == "":
            delay = "-"
        shown.append((name, str(delay)))
    num_width = len(str(max(numbers.values()))) if numbers else 1
    delay_width = max((display_width(delay) for _, delay in shown), default=1)
    entries = []
    for name, delay in shown:
        marker = "[*] " if name == star else "    "
        num_text = f"{numbers[name]:>{num_width}}"
        delay_text = f"{delay:>{delay_width}}"
        plain = f"{marker}{num_text} {name} {delay_text}"
        colored = paint_cell(marker, num_text, name, delay_text, name == star, delay)
        entries.append((plain, colored))
    lines = [bold(head), bold(speed_line(mode)), *layout_cells(entries, term_cols())]
    sys.stdout.write("\n".join(lines) + "\n")


def cached_delay(run_dir, name):
    value = load_delays(run_dir).get(name, "-")
    if value is None or value == "":
        return "-"
    return str(value)


def resolve_switch_name(proxies, members, token):
    if token in members:
        return token
    if token.isdigit() and str(int(token)) == token:
        wanted = int(token)
        for name, number in node_numbers(proxies).items():
            if number == wanted:
                return name if name in members else None
    return None


def select_proxy(secret_path, api, group, token, run_dir=""):
    try:
        proxies = load_proxies(secret_path, api)
    except SystemExit as exc:
        _as_exit3(exc)
    if group not in proxies:
        sys.stderr.write("组不存在\n")
        raise SystemExit(3)
    item = proxies[group]
    if not isinstance(item, dict) or item.get("type") not in GROUP_TYPES:
        sys.stderr.write("不是策略组\n")
        raise SystemExit(3)
    members = item.get("all") if isinstance(item, dict) else None
    if not isinstance(members, list):
        members = []
    node = resolve_switch_name(proxies, members, token)
    if node is None:
        sys.stderr.write("节点不存在\n")
        raise SystemExit(3)
    secret = _api(secret_path, api)
    body = json.dumps({"name": node}).encode()
    try:
        _request(secret, api, "PUT", select_path(group), body)
    except SystemExit as exc:
        _as_exit3(exc)
    sys.stdout.write(f"{group}\t{node}\t{cached_delay(run_dir, node)}\n")


def net_targets(urls_path, given):
    if given:
        return list(given)
    rows = []
    path = Path(urls_path)
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            text = line.strip()
            if text and not text.startswith("#"):
                rows.append(text)
    return rows or list(DEFAULT_URLS)


def net_precheck(urls_path, given):
    bad = False
    forbid = False
    for url in net_targets(urls_path, given):
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            bad = True
            continue
        if os.environ.get("AXS_FORBID_NET") == "1" and parsed.hostname not in LOOPBACK:
            forbid = True
    if bad:
        raise SystemExit(1)
    if forbid:
        raise SystemExit(3)


def _one_try(url, proxy, timeout):
    class Keep(urllib.request.HTTPErrorProcessor):
        def http_response(self, request, response):
            return response

        https_response = http_response

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({"http": proxy, "https": proxy}),
        NoRedirect,
        Keep,
    )
    started = time.monotonic()
    try:
        with opener.open(url, timeout=timeout) as resp:
            resp.read(1)
        return int((time.monotonic() - started) * 1000)
    except urllib.error.HTTPError:
        return int((time.monotonic() - started) * 1000)
    except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException):
        return None


def net_run(urls_path, proxy, timeout_ms, given):
    timeout = int(timeout_ms) / 1000
    failed = False
    for url in net_targets(urls_path, given):
        delay = _one_try(url, proxy, timeout)
        if delay is None:
            delay = _one_try(url, proxy, timeout)
        if delay is None:
            failed = True
            sys.stdout.write(f"不通\t-\t{url}\n")
        else:
            sys.stdout.write(f"通\t{delay}\t{url}\n")
    raise SystemExit(3 if failed else 0)


def reload_core(secret_path, api, config_path):
    secret = _api(secret_path, api)
    body = json.dumps({"path": str(config_path), "payload": ""}).encode()
    try:
        _request(secret, api, "PUT", reload_path(), body)
    except SystemExit:
        fail("重载失败")


def version_ok(secret_path, api):
    secret = _api(secret_path, api)
    try:
        _request(secret, api, "GET", version_path())
    except SystemExit:
        raise SystemExit(3)


def _plain(text):
    # node test colors stdout; the cache must stay numeric
    while "\033[" in text:
        start = text.find("\033[")
        end = text.find("m", start + 2)
        if end < 0:
            break
        text = text[:start] + text[end + 1 :]
    return text


def write_node_cache(dest, group, lines):
    path = Path(dest)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    delays = {}
    for line in lines:
        text = _plain(line).strip()
        if " " not in text:
            continue
        name, value = text.rsplit(" ", 1)
        if name == group:
            continue
        try:
            delays[name] = int(value)
        except ValueError:
            delays[name] = value
    body = f"ts={int(time.time())}\nresult=ok\n{json.dumps(delays, ensure_ascii=False)}\n"
    tmp = path.with_name("." + path.name + ".tmp")
    tmp.write_text(body, encoding="utf-8")
    tmp.chmod(0o600)
    os.replace(tmp, path)
    path.chmod(0o600)


def delay(secret_path, api, group, url):
    secret = _api(secret_path, api)
    try:
        raw = _request(secret, api, "GET", delay_path(group, url))
    except SystemExit:
        raise SystemExit(3)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        fail("控制器")
    if not isinstance(payload, dict):
        fail("控制器")
    for name, value in payload.items():
        try:
            shown = str(int(value))
            code = delay_code(value)
        except (TypeError, ValueError):
            shown = "超时"
            code = "31"
        title = ident(name) if name == group else name
        sys.stdout.write(f"{title} {ansi(code, shown)}\n")


def status_nodes(secret_path, api):
    proxies = {}
    try:
        loaded = load_proxies(secret_path, api)
    except SystemExit:
        loaded = {}
    if isinstance(loaded, dict):
        proxies = loaded
    mid, leaf = selection_parts(proxies)
    if leaf not in node_numbers(proxies):
        leaf = None
    global_item = proxies.get("GLOBAL")
    global_now = _now(global_item) if _is_group(global_item) else "-"
    leaf_shown = emph("32", leaf) if leaf else dim("-")
    if mid:
        chain = f"→ {ident(mid)}→ {leaf_shown}"
    else:
        chain = f"→ {dim('-')}"
    gshown = dim(global_now) if global_now == "-" else ok(global_now)
    sys.stdout.write(chain + "\n" + gshown + "\n")


def egress(proxy, url):
    if os.environ.get("AXS_FORBID_NET") == "1":
        sys.stderr.write("出口查询失败\n")
        raise SystemExit(3)
    handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
    opener = urllib.request.build_opener(handler)
    try:
        with opener.open(url, timeout=10) as resp:
            text = resp.read(200).decode("utf-8", "replace").strip()
    except Exception:
        sys.stderr.write("出口查询失败\n")
        raise SystemExit(3)
    print(text)


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "defaults":
        write_defaults(argv[2], argv[3], argv[4])
    elif cmd == "build":
        build_file(argv[2], argv[3], argv[4], argv[5], argv[6])
    elif cmd == "snap":
        take_snapshot(argv[2])
    elif cmd == "rollback":
        rollback(argv[2])
    elif cmd == "install":
        install_merged(argv[2], argv[3])
    elif cmd == "clear-fetch":
        clear_fetch(argv[2])
    elif cmd == "clean-names":
        sys.stdout.write("\n".join(clean_names(argv[2])) + "\n")
    elif cmd == "gen-secret":
        gen_secret(argv[2])
    elif cmd == "has-group":
        has_group(argv[2], argv[3], argv[4])
    elif cmd == "groups":
        for name in group_names(argv[2], argv[3]):
            sys.stdout.write(name + "\n")
    elif cmd == "default-group":
        default_group(argv[2], argv[3])
    elif cmd == "groups-show":
        show_groups(argv[2], argv[3])
    elif cmd == "node-list":
        show_nodes(argv[2], argv[3], argv[4] if len(argv) > 4 else "")
    elif cmd == "select":
        select_proxy(argv[2], argv[3], argv[4], argv[5], argv[6] if len(argv) > 6 else "")
    elif cmd == "cache-node":
        write_node_cache(argv[2], argv[3], Path(argv[4]).read_text(encoding="utf-8").splitlines())
    elif cmd == "net-precheck":
        net_precheck(argv[2], argv[3:])
    elif cmd == "net-run":
        net_run(argv[2], argv[3], argv[4], argv[5:])
    elif cmd == "reload":
        reload_core(argv[2], argv[3], argv[4])
    elif cmd == "version":
        version_ok(argv[2], argv[3])
    elif cmd == "delay":
        delay(argv[2], argv[3], argv[4], argv[5] if len(argv) > 5 else DELAY_URL)
    elif cmd == "check-url":
        check_url(argv[2])
    elif cmd == "check-fetched":
        check_fetched(argv[2], argv[3])
    elif cmd == "fetch":
        fetch(argv[2], argv[3], argv[4])
    elif cmd == "userinfo":
        write_userinfo(argv[2], argv[3])
    elif cmd == "show-userinfo":
        show_userinfo(argv[2], argv[3])
    elif cmd == "classify":
        kind, _days = classify(argv[2], argv[3])
        sys.stdout.write(kind + "\n")
    elif cmd == "status-nodes":
        status_nodes(argv[2], argv[3])
    elif cmd == "status-sub":
        status_sub(argv[2], argv[3])
    elif cmd == "rules-check":
        check(argv[2], argv[3], argv[4], argv[5], argv[6:])
    elif cmd == "rules-mutate":
        mutate(argv[2], argv[3], argv[4], argv[5], argv[6:])
    elif cmd == "parse-rule":
        parse_rule(argv[2], argv[3], argv[4] if len(argv) > 4 else "")
    elif cmd == "rules-add":
        rules_add(argv[2], argv[3])
    elif cmd == "rules-del":
        rules_del(argv[2], argv[3])
    elif cmd == "egress":
        egress(argv[2], argv[3] if len(argv) > 3 else "https://ipinfo.io/ip")
    elif cmd == "probe":
        probe(argv[2], argv[3])
    else:
        fail("用法")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except IndexError:
        fail("用法")
