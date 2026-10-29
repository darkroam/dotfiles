"""Node and group view commands. Parsing stays in cli."""

import contextlib
import io
import sys

from axs.codes import DOWN, FAIL, USAGE
from axs.mihomo import load_proxies
from axs.nodes import _as_exit3, current_selection, load_delays, node_numbers, speed_line
from axs.render import die, display_width, layout_cells, term_cols, view_page
from axs.routes import build
from axs.rulelist import status_text
from axs.view import _show_nodes_full, group_table, paint_cell, rule_page


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
    from axs.view import show_members
    from axs.nodes import select_proxy
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


def show_rule_nodes(run, secret, api):
    try:
        proxies = load_proxies(secret, api)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
        raise SystemExit(FAIL if code == USAGE else code)
    data = build(proxies, run)
    if data is None:
        die(DOWN, "服务：未运行")
    sys.stdout.write(rule_page(proxies, data, run))


def show_all(run, secret, api):
    import contextlib
    import io

    from axs.nodes import speed_line

    data = None
    try:
        data = build(load_proxies(secret, api), run)
    except SystemExit:
        data = None
    path = status_text(data).strip("\n") if data else ""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        show_nodes(secret, api, str(run))
    note = "说明：全部叶子节点；组关系见 --full。叶子含节点与内置策略，不含策略组。"
    title = f"全部叶子端点（{speed_line(run)}）："
    sys.stdout.write(view_page(path, [(title, buf.getvalue())], note))


def show_groups(secret_path, api):
    from axs.nodes import _proxies as read_proxies

    sys.stdout.write(group_table(read_proxies(secret_path, api)))


def show_nodes(secret_path, api, mode=""):
    try:
        proxies = load_proxies(secret_path, api)
    except SystemExit as exc:
        _as_exit3(exc)
    if mode == "flat":
        _show_nodes_full(proxies)
        return
    numbers = node_numbers(proxies)
    star = current_selection(proxies, numbers)
    delays = load_delays(mode)
    shown = []
    for name in sorted(numbers, key=numbers.get):
        delay = delays.get(name, "-")
        if delay is None or delay == "":
            delay = "-"
        shown.append((name, str(delay)))
    num_width = len(f"N{max(numbers.values())}") if numbers else 1
    delay_width = max((display_width(delay) for _, delay in shown), default=1)
    entries = []
    for name, delay in shown:
        marker = "[*] " if name == star else "    "
        num_text = f"{'N' + str(numbers[name]):>{num_width}}"
        delay_text = f"{delay:>{delay_width}}"
        plain = f"{marker}{num_text} {name} {delay_text}"
        colored = paint_cell(marker, num_text, name, delay_text, name == star, delay)
        entries.append((plain, colored))
    lines = layout_cells(entries, term_cols())
    sys.stdout.write("\n".join(lines) + "\n")

