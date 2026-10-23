#!/usr/bin/env python3
"""Merge a subscription with the local override. Never prints the URL or secret."""
import http.client
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from axs.core import fail, gen_secret

DELAY_URL = "https://www.gstatic.com/generate_204"
DEFAULT_URLS = (
    "https://www.github.com",
    "https://www.google.com",
    "https://www.youtube.com",
)
LOOPBACK = {"127.0.0.1", "localhost", "::1"}


from axs.mihomo import (  # noqa: E402
    group_names,
    probe,
    read_secret as _api,
    reload_core,
    request as _request,
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


from axs.nodes import (  # noqa: E402
    default_group,
    delay,
    select_proxy,
    show_groups,
    show_nodes,
    status_nodes,
    write_node_cache,
)

def write_defaults(path, mixed, api):
    from axs.config import write_override

    try:
        write_override(path, mixed, api)
    except ValueError as exc:
        fail(str(exc))










































































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


def version_ok(secret_path, api):
    secret = _api(secret_path, api)
    try:
        _request(secret, api, "GET", version_path())
    except SystemExit:
        raise SystemExit(3)










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
