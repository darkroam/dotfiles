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

DELAY_URL = "https://www.gstatic.com/generate_204"
DEFAULT_URLS = (
    "https://www.github.com",
    "https://www.google.com",
    "https://www.youtube.com",
)
GROUP_TYPES = {"Selector", "URLTest", "Fallback", "LoadBalance", "Relay"}
LOOPBACK = {"127.0.0.1", "localhost", "::1"}
CIDRS = [
    "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
    "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
    "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
    "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
    "IP-CIDR6,::1/128,DIRECT,no-resolve",
    "IP-CIDR6,fc00::/7,DIRECT,no-resolve",
    "IP-CIDR6,fe80::/10,DIRECT,no-resolve",
]
PREPEND = [
    "DOMAIN-SUFFIX,localhost,DIRECT",
    "DOMAIN-SUFFIX,local,DIRECT",
    "DOMAIN-SUFFIX,goproxy.cn,DIRECT",
    "DOMAIN-SUFFIX,ghproxy.com,DIRECT",
    "DOMAIN-SUFFIX,gh-proxy.com,DIRECT",
]
DROP_PORTS = ("port", "socks-port", "redir-port", "tproxy-port")


def fail(message):
    sys.stderr.write(message + "\n")
    raise SystemExit(1)


def atomic_write(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, text.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, path)
    os.chmod(path, 0o600)


def write_defaults(path, mixed, api):
    if not str(api).startswith("127.0.0.1:"):
        fail("控制器必须在本机回环")
    data = {
        "mixed-port": int(mixed),
        "mode": "rule",
        "allow-lan": False,
        "log-level": "info",
        "ipv6": True,
        "external-controller": str(api),
        "tun": {"enable": False},
        "dns": {"enable": True, "listen": "127.0.0.1:1053"},
        "prepend-rules": list(PREPEND),
    }
    atomic_write(path, yaml.safe_dump(data, allow_unicode=True, sort_keys=False))


def merge_dict(base, over):
    if not isinstance(base, dict) or not isinstance(over, dict):
        return over
    out = dict(base)
    for key, value in over.items():
        if key == "prepend-rules":
            continue
        if isinstance(out.get(key), dict) and isinstance(value, dict):
            out[key] = merge_dict(out[key], value)
        else:
            out[key] = value
    return out


def load_profile(path):
    raw = Path(path).read_bytes()
    if raw.lstrip().startswith(b"<"):
        fail("校验失败")
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError:
        fail("校验失败")
    proxies = data.get("proxies") if isinstance(data, dict) else None
    if not isinstance(proxies, list) or not proxies:
        fail("校验失败")
    if not all(isinstance(item, dict) and item.get("server") for item in proxies):
        fail("校验失败")
    return data


def load_local_rules(path):
    path = Path(path)
    if not path.is_file():
        return []
    rules = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 3 or parts[0] not in ("DOMAIN", "DOMAIN-SUFFIX"):
            fail("校验失败")
        rules.append(f"{parts[0]},{parts[1]},{parts[2]}")
    return rules


def dedupe(items):
    seen = []
    for item in items:
        if item not in seen:
            seen.append(item)
    return seen


def build_file(sub_path, override_path, secret_path, rules_path, out_path):
    sub = load_profile(sub_path)
    over = yaml.safe_load(Path(override_path).read_text(encoding="utf-8"))
    if not isinstance(over, dict):
        fail("校验失败")
    secret = Path(secret_path).read_text(encoding="utf-8").strip()
    if len(secret) < 8:
        fail("校验失败")
    merged = merge_dict(sub, over)
    controller = merged.get("external-controller")
    if not isinstance(controller, str) or not controller.startswith("127.0.0.1:"):
        fail("校验失败")
    extra = over.get("prepend-rules") or []
    if not isinstance(extra, list):
        fail("校验失败")
    base_rules = merged.get("rules") or []
    if not isinstance(base_rules, list):
        fail("校验失败")
    merged["rules"] = dedupe(CIDRS + extra + load_local_rules(rules_path) + base_rules)
    merged.pop("prepend-rules", None)
    for key in DROP_PORTS:
        merged.pop(key, None)
    merged["tun"] = {"enable": False}
    merged["secret"] = secret
    merged["mode"] = over.get("mode") or "rule"
    atomic_write(out_path, yaml.safe_dump(merged, allow_unicode=True, sort_keys=False))


def gen_secret(path):
    path = Path(path)
    if path.is_file() and len(path.read_text(encoding="utf-8").strip()) >= 8:
        os.chmod(path, 0o600)
        return
    import secrets

    atomic_write(path, secrets.token_hex(16) + "\n")


def _api(secret_path, api):
    if not str(api).startswith("127.0.0.1:"):
        fail("控制器必须在本机回环")
    path = Path(secret_path)
    if not path.is_file():
        fail("控制器")
    secret = path.read_text(encoding="utf-8").strip()
    if len(secret) < 8:
        fail("控制器")
    return secret


def _fake_exchange(method, path, secret, body=None):
    directory = Path(os.environ["AXS_FAKE_DIR"])
    flag = "yes" if secret and len(secret) >= 8 else "no"
    extra = ""
    if body:
        extra = " body=" + body.decode("utf-8", "replace")
    with (directory / "log").open("a", encoding="utf-8") as handle:
        handle.write(f"{method} {path} auth={flag}{extra}\n")
    if (directory / "down").is_file():
        fail("控制器")
    pure = path.split("?", 1)[0]
    if method == "PUT" and pure.startswith("/proxies/"):
        code_path = directory / "select"
        code = int(code_path.read_text(encoding="utf-8").strip() or "204") if code_path.is_file() else 204
        if code >= 300:
            fail("控制器")
        return b""
    if method == "PUT":
        code = int((directory / "reload").read_text(encoding="utf-8").strip() or "204")
        if code >= 300:
            fail("控制器")
        return b""
    if pure == "/version":
        return b'{"version":"fake"}'
    if pure == "/proxies":
        ready = directory / "proxies.json"
        if ready.is_file():
            return ready.read_bytes()
        text = (directory / "groups").read_text(encoding="utf-8") if (directory / "groups").is_file() else ""
        payload = {
            name: {"type": "Selector", "now": "a", "all": ["a"]}
            for name in text.split()
        }
        return json.dumps({"proxies": payload}).encode()
    if pure.startswith("/group/") and pure.endswith("/delay"):
        ready = directory / "delay.json"
        if ready.is_file():
            return ready.read_bytes()
        name = urllib.parse.unquote(pure.split("/")[2])
        delay = int((directory / "delay").read_text(encoding="utf-8").strip() or "0")
        return json.dumps({name: delay}).encode()
    fail("控制器")


def _request(secret, api, method, path, body=None):
    if os.environ.get("AXS_FAKE_DIR"):
        return _fake_exchange(method, path, secret, body)
    req = urllib.request.Request(
        f"http://{api}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": "Bearer " + secret,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            raw = resp.read()
            if resp.status >= 300:
                fail("控制器")
            return raw
    except urllib.error.HTTPError as exc:
        if exc.code >= 300:
            fail("控制器")
        raise
    except (urllib.error.URLError, TimeoutError, OSError):
        fail("控制器")


def load_proxies(secret_path, api):
    secret = _api(secret_path, api)
    raw = _request(secret, api, "GET", "/proxies")
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
        shown = dim(now) if now == "-" else ok(now)
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


def current_selection(proxies, numbers):
    main = proxies.get("主代理")
    if not _is_group(main):
        return "当前：无", None
    now = main.get("now")
    target = proxies.get(now) if isinstance(now, str) and now else None
    if not isinstance(target, dict):
        return "当前：无", None
    kind = target.get("type")
    if kind in AUTO_LABEL:
        label = f"{now}（自动，{AUTO_LABEL[kind]}）"
    else:
        label = f"{now}（手动）"
    leaf = follow_leaf(proxies, now)
    if leaf in numbers:
        return f"当前：主代理 → {label}→ {leaf} 第{numbers[leaf]}个", leaf
    return f"当前：主代理 → {label}→ -", None


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
    mark = ok("[*]") + " " if selected else marker
    lead = len(num_text) - len(num_text.lstrip(" "))
    number = (" " * lead) + dim(num_text.lstrip(" "))
    shown = ok(name) if selected else name
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
    quoted = urllib.parse.quote(group, safe="")
    body = json.dumps({"name": node}).encode()
    try:
        _request(secret, api, "PUT", f"/proxies/{quoted}", body)
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


def has_group(secret_path, api, name):
    try:
        names = group_names(secret_path, api)
    except (SystemExit, OSError):
        sys.stderr.write("控制器\n")
        raise SystemExit(3)
    if name not in names:
        sys.stderr.write("组名不存在\n")
        raise SystemExit(3)


def reload_core(secret_path, api, config_path):
    secret = _api(secret_path, api)
    body = json.dumps({"path": str(config_path), "payload": ""}).encode()
    try:
        _request(secret, api, "PUT", "/configs?force=true", body)
    except SystemExit:
        fail("重载失败")


def version_ok(secret_path, api):
    secret = _api(secret_path, api)
    try:
        _request(secret, api, "GET", "/version")
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
    query = urllib.parse.urlencode({"timeout": "5000", "url": url})
    quoted = urllib.parse.quote(group, safe="")
    try:
        raw = _request(secret, api, "GET", f"/group/{quoted}/delay?{query}")
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


YAML_TYPES = {
    "text/yaml",
    "application/yaml",
    "application/x-yaml",
    "text/x-yaml",
    "text/plain",
    "application/octet-stream",
}


def check_url(path):
    raw = Path(path).read_text(encoding="utf-8", errors="replace")
    url = raw.strip("\r\n")
    if url != url.strip() or any(ch.isspace() for ch in url) or "\\" in url:
        sys.stderr.write("链接含转义字符（如 \\?），请去掉反斜杠\n")
        raise SystemExit(3)


def _header_field(text, name):
    prefix = name.lower() + ":"
    for line in text.splitlines():
        if line.lower().startswith(prefix):
            return line.split(":", 1)[1].strip()
    return ""


def _yaml_type(value):
    if not value or not value.strip():
        return True
    main = value.split(";", 1)[0].strip().lower()
    return main in YAML_TYPES or main.endswith("/yaml") or main.endswith("+yaml")


def check_fetched(body_path, header_path):
    body_file = Path(body_path)
    body = body_file.read_bytes() if body_file.is_file() else b""
    header = ""
    header_file = Path(header_path)
    if header_file.is_file():
        header = header_file.read_text(encoding="utf-8", errors="replace")
    status = _header_field(header, "x-axs-status") or "-"
    ctype = _header_field(header, "x-axs-content-type")
    html = body.lstrip().startswith(b"<")
    if body.strip() and _yaml_type(ctype) and not html:
        return
    shown = ctype or ("text/html" if html else "-")
    sys.stderr.write(
        f"订阅返回空内容/非 YAML（HTTP {status}, {shown}），请检查链接\n"
    )
    raise SystemExit(3)


def fetch(urlfile, body_path, header_path):
    if os.environ.get("AXS_FORBID_NET") == "1":
        fail("离线测试拒绝联网")
    url = Path(urlfile).read_text(encoding="utf-8").strip()
    if not url.startswith(("http://", "https://")):
        fail("拉取失败")
    req = urllib.request.Request(url, headers={"User-Agent": "axs"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            payload = resp.read()
            info = resp.headers.get("subscription-userinfo", "")
            status = getattr(resp, "status", None) or 200
            ctype = resp.headers.get("content-type") or ""
    except (urllib.error.URLError, TimeoutError, OSError):
        fail("拉取失败")
    Path(body_path).write_bytes(payload)
    Path(header_path).write_text(
        "subscription-userinfo: " + info + "\n"
        + f"x-axs-status: {status}\n"
        + f"x-axs-content-type: {ctype}\n",
        encoding="utf-8",
    )


def write_userinfo(header_path, out_path):
    text = Path(header_path).read_text(encoding="utf-8", errors="replace")
    value = ""
    for line in text.splitlines():
        if line.lower().startswith("subscription-userinfo:"):
            value = line.split(":", 1)[1].strip()
    fields = {}
    for part in value.split(";"):
        if "=" not in part:
            continue
        key, raw = part.split("=", 1)
        fields[key.strip()] = raw.strip()
    lines = []
    for key in ("upload", "download", "total", "expire"):
        if key in fields and fields[key].isdigit():
            lines.append(f"{key}={fields[key]}")
    atomic_write(out_path, ("\n".join(lines) + ("\n" if lines else "")))


def classify(userinfo_path, now):
    path = Path(userinfo_path)
    if not path.is_file():
        return "unknown", None
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key] = value
    if "expire" not in fields:
        return "unknown", None
    expire = int(fields["expire"])
    now = int(now)
    if expire <= now:
        return "expired", 0
    days = (expire - now) // 86400
    if expire - now < 3 * 86400:
        return "soon", days
    return "ok", days


def show_userinfo(path, now):
    path = Path(path)
    if not path.is_file():
        sys.stdout.write("未知\n")
        return
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key] = value
    if not fields:
        sys.stdout.write("未知\n")
        return
    labels = (("upload", "上传"), ("download", "下载"), ("total", "总量"))
    for key, lab in labels:
        if key in fields:
            sys.stdout.write(f"{label(lab + ':')} {fields[key]}\n")
    kind, days = classify(path, now)
    if kind == "expired":
        sys.stdout.write(bad("已过期") + "\n")
    elif kind == "unknown":
        sys.stdout.write(dim("未知") + "\n")
    elif kind == "soon":
        sys.stdout.write(label("剩余:") + " " + warn(f"{days} 天") + "\n")
    else:
        sys.stdout.write(label("剩余:") + " " + ok(f"{days} 天") + "\n")



STATUS_GROUPS = ("主代理", "自动选择", "GLOBAL")


def _userinfo_fields(path):
    fields = {}
    file = Path(path)
    if not file.is_file():
        return fields
    for line in file.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key] = value
    return fields


def status_nodes(secret_path, api):
    found = {name: "-" for name in STATUS_GROUPS}
    try:
        proxies = load_proxies(secret_path, api)
    except SystemExit:
        proxies = {}
    if isinstance(proxies, dict):
        for name in STATUS_GROUPS:
            item = proxies.get(name)
            if isinstance(item, dict):
                found[name] = _now(item)
    bits = []
    for name in STATUS_GROUPS:
        now = found[name]
        shown = dim(now) if now == "-" else ok(now)
        bits.append(f"{ident(name)} = {shown}")
    sys.stdout.write(label("节点：") + "；".join(bits) + "\n")


def status_sub(path, now):
    kind, days = classify(path, now)
    if kind == "expired":
        phrase = bad("已过期，剩余 0 天")
    elif kind == "soon":
        phrase = warn(f"警告，剩余 {days} 天")
    elif kind == "ok":
        phrase = ok(f"有效，剩余 {days} 天")
    else:
        phrase = dim("未知")
    text = label("订阅：") + phrase
    bits = []
    fields = _userinfo_fields(path)
    for key, lab in (("upload", "上传"), ("download", "下载"), ("total", "总量")):
        if key in fields and fields[key] != "":
            bits.append(f"{lab} {fields[key]}")
    if bits:
        text += "，" + " ".join(bits)
    sys.stdout.write(text + "\n" + kind + "\n")


def parse_rule(kind, domain, group):
    if kind not in ("via", "direct"):
        fail("用法")
    if "://" in domain or any(ch in domain for ch in "/?#,* \t"):
        fail("用法")
    if domain.startswith("."):
        host = domain.lstrip(".")
        form = "DOMAIN-SUFFIX"
    else:
        host = domain
        form = "DOMAIN"
    if not host or host.startswith("-") or ".." in host:
        fail("用法")
    if kind == "direct":
        policy = "DIRECT"
    else:
        if not group or any(ch in group for ch in " ,\t"):
            fail("用法")
        policy = group
    sys.stdout.write(f"{form} {host} {policy}\n")


def rules_add(path, line):
    parts = line.split()
    if len(parts) != 3:
        fail("用法")
    path = Path(path)
    rows = []
    if path.is_file():
        rows = [item for item in path.read_text(encoding="utf-8").splitlines() if item.strip()]
    rows = [item for item in rows if item.split()[1:2] != [parts[1]]]
    rows.append(line.strip())
    atomic_write(path, "\n".join(rows) + "\n")


def rules_del(path, domain):
    if domain.startswith("."):
        host = domain.lstrip(".")
    else:
        host = domain
    path = Path(path)
    if not path.is_file():
        return
    rows = []
    for item in path.read_text(encoding="utf-8").splitlines():
        parts = item.split()
        if len(parts) == 3 and parts[1] == host:
            continue
        if item.strip():
            rows.append(item)
    atomic_write(path, ("\n".join(rows) + "\n") if rows else "")


def probe(host, port):
    directory = os.environ.get("AXS_FAKE_DIR")
    if directory:
        listed = ""
        path = Path(directory) / "open-ports"
        if path.is_file():
            listed = path.read_text(encoding="utf-8")
        if str(port) not in listed.split():
            raise SystemExit(1)
        return
    import socket

    sock = socket.socket()
    sock.settimeout(0.3)
    try:
        sock.connect((host, int(port)))
    except OSError:
        raise SystemExit(1)
    finally:
        sock.close()


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "defaults":
        write_defaults(argv[2], argv[3], argv[4])
    elif cmd == "build":
        build_file(argv[2], argv[3], argv[4], argv[5], argv[6])
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
    elif cmd == "parse-rule":
        parse_rule(argv[2], argv[3], argv[4] if len(argv) > 4 else "")
    elif cmd == "rules-add":
        rules_add(argv[2], argv[3])
    elif cmd == "rules-del":
        rules_del(argv[2], argv[3])
    elif cmd == "probe":
        probe(argv[2], argv[3])
    else:
        fail("用法")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except IndexError:
        fail("用法")
