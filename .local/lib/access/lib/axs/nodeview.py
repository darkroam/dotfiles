"""node status page and the members table. No topology."""

import sys

from axs.codes import DOWN, FAIL, USAGE
from axs.mihomo import load_proxies
from axs.nodes import (
    _is_group,
    delay_code,
    follow_leaf,
    group_numbers,
    load_delays,
    node_numbers,
    resolve_group_name,
)
from axs.nodelist import paint_cell, show_nodes
from axs.render import die, display_width, emph, layout_cells, term_cols, tone, use_color, view_page
from axs.routes import build
from axs.rulelist import status_text


def terminal_text(proxies, data, run):
    gnums, nnums = group_numbers(proxies), node_numbers(proxies)
    delays, blocks = load_delays(run), []
    for name in data["terminals"]:
        item = proxies.get(name) or {}
        kind = str(item.get("type") or "")
        members = item.get("all") if isinstance(item.get("all"), list) else []
        now = item.get("now") if isinstance(item.get("now"), str) else ""
        leaf = "" if kind == "LoadBalance" else (follow_leaf(proxies, now) or "")
        current = f"N{nnums[leaf]} {leaf}" if leaf in nnums else "-"
        head_line = f"G{gnums[name]} {name} [{kind}] → {current} · {len(members)} 个成员"
        shown = []
        for member in members:
            if member not in nnums:
                continue
            delay = delays.get(member, "-")
            shown.append((member, "-" if delay in (None, "") else str(delay)))
        width = len(f"N{max((nnums[member] for member, _delay in shown), default=1)}")
        wide = max((display_width(delay) for _member, delay in shown), default=1)
        entries = []
        for member, delay in shown:
            marker = "[*] " if member == leaf else "    "
            num_text = f"{'N' + str(nnums[member]):>{width}}"
            delay_text = f"{delay:>{wide}}"
            plain = f"{marker}{num_text} {member} {delay_text}"
            entries.append((plain, paint_cell(marker, num_text, member, delay_text, member == leaf, delay)))
        blocks.append("\n".join([head_line, *layout_cells(entries, term_cols())]))
    return ("\n\n".join(blocks) + "\n") if blocks else ""


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


def rule_page(proxies, data, run):
    path = status_text(data).strip("\n")
    tail = terminal_text(proxies, data, run).strip("\n")
    blocks = [("末端组（链尾自动组）：", tail)] if tail else []
    note = "说明：当前状态＝当前规则路径＋链尾自动组；node show 查可选树，--full 完整拓扑，--all 全部叶子。"
    return view_page(path, blocks, note)


def render_members(proxies, group, delays):
    item = proxies[group]
    members = item.get("all") if isinstance(item.get("all"), list) else []
    if not members:
        return "（无成员）\n"
    now = item.get("now") if isinstance(item.get("now"), str) else ""
    if not isinstance(delays, dict):
        delays = {}
    gnums = group_numbers(proxies)
    nnums = node_numbers(proxies)
    rows = []
    for name in members:
        child = proxies.get(name)
        if _is_group(child):
            ident = f"G{gnums[name]}"
            kind = str(child.get("type") or "-")
        else:
            number = nnums.get(name)
            ident = f"N{number}" if number else "-"
            kind = str(child.get("type") or "-") if isinstance(child, dict) else "-"
        mark = "[*]" if name == now else ""
        delay = delays.get(name, "-")
        if delay is None or delay == "":
            delay = "-"
        rows.append((ident, str(name), kind, mark, str(delay)))
    widths = [max(display_width(row[index]) for row in rows) for index in range(5)]
    color = use_color()
    lines = []
    for row in rows:
        parts = []
        for index in range(4):
            shown = emph("32", row[index]) if color and index == 3 and row[index] == "[*]" else row[index]
            parts.append(shown + " " * (widths[index] - display_width(row[index])))
        delay = row[4]
        shown = tone(delay_code(delay), delay) if color else delay
        parts.append(" " * (widths[4] - display_width(delay)) + shown)
        lines.append("  ".join(parts))
    return "\n".join(lines) + "\n"


def show_members(proxies, token, run_dir):
    name, err = resolve_group_name(proxies, token)
    if err:
        sys.stderr.write(err + "\n")
        raise SystemExit(FAIL)
    sys.stdout.write(render_members(proxies, name, load_delays(run_dir)))


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
