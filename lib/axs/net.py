"""Connectivity, open ports, and egress."""

from axs.codes import USAGE, DOWN, FAIL
from axs.config import LOOPBACK, LOOPBACK_HOSTS
import http.client
import os
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
        return int((time.monotonic() - started) * 1000)
    except urllib.error.HTTPError:
        return int((time.monotonic() - started) * 1000)
    except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException):
        return None


def _net_table(rows):
    from axs.render import bad, bold, dim, display_width, ok

    result_w = max(display_width(label) for label, _delay, _url in rows)
    delay_w = max(display_width(delay) for _label, delay, _url in rows)
    lines = [bold("连通性（经代理）"), "结果 / 延迟 / 目标"]
    for label, delay, url in rows:
        paint = ok if label == "通" else bad
        shown = dim(delay) if delay == "-" else delay
        left = paint(label) + " " * (result_w - display_width(label))
        mid = " " * (delay_w - display_width(delay)) + shown
        lines.append(f"{left}  {mid}  {url}")
    return "\n".join(lines) + "\n"


def net_run(urls_path, proxy, timeout_ms, given):
    timeout = int(timeout_ms) / 1000
    failed = False
    rows = []
    for url in net_targets(urls_path, given):
        delay = _one_try(url, proxy, timeout)
        if delay is None:
            delay = _one_try(url, proxy, timeout)
        if delay is None:
            failed = True
            rows.append(("不通", "-", url))
        else:
            rows.append(("通", str(delay), url))
    sys.stdout.write(_net_table(rows))
    raise SystemExit(FAIL if failed else 0)


def egress(proxy, url):
    if os.environ.get("AXS_FORBID_NET") == "1":
        sys.stderr.write("公网地址查询被禁止（AXS_FORBID_NET=1）\n")
        raise SystemExit(FAIL)
    handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
    opener = urllib.request.build_opener(handler)
    try:
        with opener.open(url, timeout=10) as resp:
            text = resp.read(200).decode("utf-8", "replace").strip()
    except Exception as exc:
        sys.stderr.write(f"公网地址查询失败（{url}）：{exc}\n")
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
