"""Numbers, switch, and the speed cache."""

from axs.codes import USAGE, FAIL
import json
import os
import sys
import time
from pathlib import Path

from axs.mihomo import GROUP_TYPES, load_proxies, read_secret, request, select_path
from axs.render import tone

def _ansi(code, text):
    if text == "":
        return text
    return tone(code, text)


def _as_exit3(exc):
    code = exc.code if isinstance(exc.code, int) else USAGE
    raise SystemExit(FAIL if code == USAGE else code)

def _proxies(secret_path, api):
    try:
        return load_proxies(secret_path, api)
    except SystemExit as exc:
        _as_exit3(exc)

def group_numbers(proxies):
    names = sorted(name for name, item in proxies.items() if _is_group(item))
    return {name: index for index, name in enumerate(names, 1)}

def _prefixed(token, prefix):
    size = len(prefix)
    if len(token) <= size or token[:size].casefold() != prefix.casefold():
        return None
    body = token[size:]
    if body.isascii() and body.isdigit() and str(int(body)) == body:
        return int(body)
    return None

def resolve_group_name(proxies, token):
    if token in proxies:
        return (token, "") if _is_group(proxies[token]) else (None, "不是策略组")
    wanted = _prefixed(token, "G")
    if wanted is not None:
        for name, number in group_numbers(proxies).items():
            if number == wanted:
                return name, ""
    return None, "组不存在"


AUTO_LABEL = {"URLTest": "url-test", "Fallback": "fallback", "LoadBalance": "load-balance"}
AUTO_TYPES = frozenset(AUTO_LABEL)

def node_numbers(proxies):
    names = sorted(name for name, item in proxies.items() if isinstance(item, dict) and item.get("type") not in GROUP_TYPES)
    return {name: index for index, name in enumerate(names, 1)}

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
    _mid, leaf = selection_parts(proxies)
    return leaf if leaf in numbers else None

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

def cached_delay(run_dir, name):
    value = load_delays(run_dir).get(name, "-")
    if value is None or value == "":
        return "-"
    return str(value)

def resolve_switch_name(proxies, members, token):
    if token in members:
        return token
    wanted = _prefixed(token, "N")
    if wanted is not None:
        for name, number in node_numbers(proxies).items():
            if number == wanted and name in members:
                return name
        return None
    wanted = _prefixed(token, "G")
    if wanted is None:
        return None
    for name, number in group_numbers(proxies).items():
        if number == wanted and name in members:
            return name
    return None

def select_proxy(secret_path, api, group, token, run_dir=""):
    proxies = _proxies(secret_path, api)
    group, err = resolve_group_name(proxies, group)
    if err:
        sys.stderr.write(err + "\n")
        raise SystemExit(FAIL)
    item = proxies[group]
    members = item.get("all") if isinstance(item.get("all"), list) else []
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
    # group test colors stdout; the cache must stay numeric
    while "\033[" in text:
        start = text.find("\033[")
        end = text.find("m", start + 2)
        if end < 0:
            break
        text = text[:start] + text[end + 1 :]
    return text

def write_node_cache(dest, group, lines, ok=True):
    path = Path(dest)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    delays = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.startswith("{"):
                continue
            try:
                old = json.loads(line)
            except json.JSONDecodeError:
                old = {}
            delays = old if isinstance(old, dict) else {}
            break
    for line in lines:
        text = _plain(line).strip()
        if " " not in text:
            continue
        name, value = text.rsplit(" ", 1)
        if not name or name == group:
            continue
        try:
            delays[name] = int(value)
        except ValueError:
            continue
    state = "ok" if ok else "fail"
    body = f"ts={int(time.time())}\nresult={state}\n{json.dumps(delays, ensure_ascii=False)}\n"
    tmp = path.with_name("." + path.name + ".tmp")
    tmp.write_text(body, encoding="utf-8")
    tmp.chmod(0o600)
    os.replace(tmp, path)
    path.chmod(0o600)
