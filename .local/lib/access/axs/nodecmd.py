"""Node and group view commands. Parsing stays in cli."""

import sys

from axs.codes import DOWN, FAIL, USAGE
from axs.render import die


def _list_flags(args):
    mode = ""
    depth = None
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in ("--full", "--flat", "-l", "--all"):
            if mode:
                die(USAGE, "用法错误")
            mode = {"--flat": "flat", "-l": "flat", "--all": "all"}.get(arg, "full")
            index += 1
            continue
        if arg != "--depth":
            die(USAGE, "用法错误")
        if depth is not None or index + 1 >= len(args):
            die(USAGE, "用法错误")
        token = args[index + 1]
        if not (token.isascii() and token.isdigit() and str(int(token)) == token and int(token) >= 1):
            die(USAGE, "用法错误")
        depth = int(token)
        index += 2
    if depth is not None and mode not in ("", "full"):
        die(USAGE, "用法错误")
    return mode, depth


def _proxies(secret, api):
    from axs.nodes import load_proxies

    try:
        return load_proxies(secret, api)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
        raise SystemExit(FAIL if code == USAGE else code)


def _show_tree(secret, api, mode, depth):
    proxies = _proxies(secret, api)
    if mode == "select":
        from axs.view import render_select as draw
    else:
        from axs.view import render_tree as draw
    sys.stdout.write(draw(proxies, depth, origin=secret, view=True))


def run(run, kind, args):
    from pathlib import Path

    from axs.config import SECRET, api_address
    from axs.nodelist import show_groups, show_nodes
    from axs.nodes import select_proxy
    from axs.view import show_all, show_members, show_rule_nodes
    from axs.service import service_up
    list_mode, depth = "", None
    if kind == "list":
        list_mode, depth = _list_flags(args)
    if not service_up(run):
        die(DOWN, "服务：未运行")
    api = api_address(run)
    if not api:
        die(FAIL, "控制器失败")
    secret = Path(run) / SECRET
    if kind == "groups":
        show_groups(secret, api)
    elif kind == "status":
        show_rule_nodes(run, secret, api)
    elif kind == "list":
        if list_mode == "flat":
            show_nodes(secret, api, "flat")
        elif list_mode == "all":
            show_all(run, secret, api)
        elif list_mode == "full":
            _show_tree(secret, api, "full", depth)
        else:
            _show_tree(secret, api, "select", depth)
    elif kind == "members":
        show_members(_proxies(secret, api), args[0], str(run))
    else:
        select_proxy(secret, api, args[0], args[1], str(run))
