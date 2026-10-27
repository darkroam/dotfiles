"""Connectivity, open ports, and egress."""

from axs.codes import USAGE, DOWN, FAIL
from axs.config import LOOPBACK, LOOPBACK_HOSTS
import http.client
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_URLS = (
    "https://www.github.com",
    "https://www.google.com",
    "https://www.youtube.com",
)


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
        if os.environ.get("AXS_FORBID_NET") == "1" and parsed.hostname not in LOOPBACK_HOSTS:
            forbid = True
    if bad:
        raise SystemExit(USAGE)
    if forbid:
        raise SystemExit(FAIL)


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
        return int((time.monotonic() - started) * 1000), ""
    except urllib.error.HTTPError:
        return int((time.monotonic() - started) * 1000), ""
    except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException) as exc:
        return None, _net_reason(exc)


def _net_reason(exc):
    reason = getattr(exc, "reason", exc)
    text = str(reason).lower()
    if isinstance(reason, TimeoutError) or "timed out" in text:
        return "超时"
    if isinstance(reason, ssl.SSLError) or "certificate" in text or type(reason).__name__.lower().startswith("ssl"):
        return "SSL"
    if isinstance(reason, ConnectionRefusedError) or "refused" in text:
        return "拒绝"
    return "连接失败"


def _net_table(rows):
    from axs.render import bad, bold, dim, display_width, ok

    head = ("结果", "延迟", "目标", "原因")
    plain = [head, *rows]
    widths = [max(display_width(row[i]) for row in plain) for i in range(3)]

    def line(cells, colored):
        parts = []
        for index, cell in enumerate(cells):
            shown = colored[index]
            if index == 3:
                if cell:
                    parts.append(shown)
                continue
            if index == 1:
                pad = " " * (widths[index] - display_width(cell))
                parts.append(pad + shown)
            else:
                parts.append(shown + " " * (widths[index] - display_width(cell)))
        return "  ".join(parts)

    lines = [bold("连通性（经代理）"), line(head, head)]
    for label, delay, url, reason in rows:
        paint = ok(label) if label == "通" else bad(label)
        shown = dim(delay) if delay == "-" else delay
        lines.append(line((label, delay, url, reason), (paint, shown, url, reason)))
    return "\n".join(lines) + "\n"


def _fake_reason():
    # shortcut: seccomp turns a closed port into EPERM, drop when golden no longer dials
    fake = os.environ.get("AXS_FAKE_DIR")
    if not fake:
        return ""
    path = Path(fake) / "net-result"
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8").strip()


def net_run(urls_path, proxy, timeout_ms, given):
    timeout = int(timeout_ms) / 1000
    forced = _fake_reason()
    failed = False
    rows = []
    for url in net_targets(urls_path, given):
        if forced:
            failed = True
            rows.append(("不通", "-", url, forced))
            continue
        delay, reason = _one_try(url, proxy, timeout)
        if delay is None:
            delay, reason = _one_try(url, proxy, timeout)
        if delay is None:
            failed = True
            rows.append(("不通", "-", url, reason))
        else:
            rows.append(("通", f"{delay}ms", url, ""))
    sys.stdout.write(_net_table(rows))
    raise SystemExit(FAIL if failed else 0)


def _ip_timeout():
    raw = os.environ.get("AXS_NET_TIMEOUT_MS", "").strip()
    try:
        value = int(raw) if raw else 10000
    except ValueError:
        return 10
    return (value if value > 0 else 10000) / 1000


def _ip_reason(exc):
    if isinstance(exc, urllib.error.HTTPError):
        return f"HTTP {exc.code}"
    return "超时" if _net_reason(exc) == "超时" else "连接失败"


def egress(proxy, url):
    if os.environ.get("AXS_FORBID_NET") == "1":
        sys.stderr.write("公网地址查询被禁止（AXS_FORBID_NET=1）\n")
        raise SystemExit(FAIL)
    handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
    opener = urllib.request.build_opener(handler)
    try:
        with opener.open(url, timeout=_ip_timeout()) as resp:
            text = resp.read(200).decode("utf-8", "replace").strip()
    except Exception as exc:
        sys.stderr.write(f"公网地址查询失败（{url}）：{_ip_reason(exc)}\n")
        raise SystemExit(FAIL)
    print(f"公网地址 {text}")


def port_open(port):
    from axs.mihomo import probe

    try:
        probe(LOOPBACK, port)
    except SystemExit:
        return False
    return True


def net_ip(run, args):
    from axs.config import read_ports
    from axs.render import die

    if args:
        die(USAGE, "用法错误")
    mixed, _api = read_ports(run)
    if not port_open(mixed):
        die(DOWN, f"入站：不通（{LOOPBACK}:{mixed} 未监听，先 axs ensure）")
    egress(f"http://{LOOPBACK}:{mixed}", "https://ipinfo.io/ip")


def net_test(run, args):
    from axs.config import URLS, read_ports
    from axs.render import die
    from axs.core import write_cache

    try:
        net_precheck(Path(run) / URLS, list(args))
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
        if code == 1:
            die(USAGE, "用法错误")
        die(FAIL, "禁止外网")
    mixed, _api = read_ports(run)
    if not port_open(mixed):
        die(DOWN, "入站：不通")
    timeout = os.environ.get("AXS_NET_TIMEOUT_MS") or "5000"
    try:
        net_run(Path(run) / URLS, f"http://{LOOPBACK}:{mixed}", timeout, list(args))
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
    else:
        code = 0
    write_cache(run, "net-test", "ok" if code == 0 else "fail")
    if code:
        raise SystemExit(code)
