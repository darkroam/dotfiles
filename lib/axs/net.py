"""Connectivity and egress."""

from axs.codes import USAGE, DOWN, FAIL
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
LOOPBACK = {"127.0.0.1", "localhost", "::1"}


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
    raise SystemExit(FAIL if failed else 0)


def egress(proxy, url):
    if os.environ.get("AXS_FORBID_NET") == "1":
        sys.stderr.write("出口查询失败\n")
        raise SystemExit(FAIL)
    handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
    opener = urllib.request.build_opener(handler)
    try:
        with opener.open(url, timeout=10) as resp:
            text = resp.read(200).decode("utf-8", "replace").strip()
    except Exception:
        sys.stderr.write("出口查询失败\n")
        raise SystemExit(FAIL)
    print(text)


def net_ip(run, args):
    from axs.config import read_ports
    from axs.render import die
    from axs.service import port_open

    if args:
        die(USAGE, "用法")
    mixed, _api = read_ports(run)
    if not port_open(mixed):
        die(DOWN, "入站：不通")
    egress(f"http://127.0.0.1:{mixed}", "https://ipinfo.io/ip")


def net_test(run, args):
    from axs.config import URLS, read_ports
    from axs.render import die
    from axs.service import port_open, write_cache

    try:
        net_precheck(Path(run) / URLS, list(args))
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
        if code == 1:
            die(USAGE, "用法")
        die(FAIL, "禁止外网")
    mixed, _api = read_ports(run)
    if not port_open(mixed):
        die(DOWN, "入站：不通")
    timeout = os.environ.get("AXS_NET_TIMEOUT_MS") or "5000"
    try:
        net_run(Path(run) / URLS, f"http://127.0.0.1:{mixed}", timeout, list(args))
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
    else:
        code = 0
    write_cache(run, "net-test", "ok" if code == 0 else "fail")
    if code:
        raise SystemExit(code)
