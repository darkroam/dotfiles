#!/usr/bin/env python3
"""Merge a subscription with the local override. Never prints the URL or secret."""
import sys
from pathlib import Path

from axs.core import fail, gen_secret

DELAY_URL = "https://www.gstatic.com/generate_204"


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

from axs.net import (  # noqa: E402
    egress,
    net_precheck,
    net_run,
)

def write_defaults(path, mixed, api):
    from axs.config import write_override

    try:
        write_override(path, mixed, api)
    except ValueError as exc:
        fail(str(exc))


def version_ok(secret_path, api):
    secret = _api(secret_path, api)
    try:
        _request(secret, api, "GET", version_path())
    except SystemExit:
        raise SystemExit(3)


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
