"""Groups, node list, delay, switch, and the speed cache."""

from axs.codes import USAGE, FAIL
import json
import os
import sys
import time
from pathlib import Path

from axs.mihomo import GROUP_TYPES, delay_path, load_proxies, read_secret, request, select_path
from axs.render import bold, dim, display_width, emph, ident, layout_cells, ok, term_cols, tone, use_color

DELAY_URL = "https://www.gstatic.com/generate_204"

def _fail(message):
    from axs.core import fail

    fail(message)


def _ansi(code, text):
    if text == "":
        return text
    return tone(code, text)


def _as_exit3(exc):
    code = exc.code if isinstance(exc.code, int) else USAGE
    raise SystemExit(FAIL if code == USAGE else code)

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
    raise SystemExit(FAIL)

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
    if not use_color():
        return plain
    mark = emph("32", "[*]") + " " if selected else marker
    lead = len(num_text) - len(num_text.lstrip(" "))
    number = (" " * lead) + dim(num_text.lstrip(" "))
    shown = emph("32", name) if selected else name
    dlead = len(delay_text) - len(delay_text.lstrip(" "))
    body = delay_text.lstrip(" ")
    delay = (" " * dlead) + _ansi(delay_code(delay_raw), body)
    return f"{mark}{number} {shown} {delay}"

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
        raise SystemExit(FAIL)
    item = proxies[group]
    if not isinstance(item, dict) or item.get("type") not in GROUP_TYPES:
        sys.stderr.write("不是策略组\n")
        raise SystemExit(FAIL)
    members = item.get("all") if isinstance(item, dict) else None
    if not isinstance(members, list):
        members = []
    node = resolve_switch_name(proxies, members, token)
    if node is None:
        sys.stderr.write("节点不存在\n")
        raise SystemExit(FAIL)
    secret = read_secret(secret_path, api)
    body = json.dumps({"name": node}).encode()
    try:
        request(secret, api, "PUT", select_path(group), body)
    except SystemExit as exc:
        _as_exit3(exc)
    sys.stdout.write(f"{group}\t{node}\t{cached_delay(run_dir, node)}\n")

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
    secret = read_secret(secret_path, api)
    try:
        raw = request(secret, api, "GET", delay_path(group, url))
    except SystemExit:
        raise SystemExit(FAIL)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        _fail("控制器失败")
    if not isinstance(payload, dict):
        _fail("控制器失败")
    for name, value in payload.items():
        try:
            shown = str(int(value))
            code = delay_code(value)
        except (TypeError, ValueError):
            shown = "超时"
            code = "31"
        title = ident(name) if name == group else name
        sys.stdout.write(f"{title} {_ansi(code, shown)}\n")

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
