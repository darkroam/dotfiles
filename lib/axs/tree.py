"""Tree rendering for node show and group members. Numbers come from nodes.py."""

import sys
from pathlib import Path

import yaml

from axs.codes import FAIL
from axs.config import CONFIG
from axs.nodes import (
    AUTO_TYPES,
    _is_group,
    follow_leaf,
    group_numbers,
    delay_code,
    load_delays,
    node_numbers,
    resolve_group_name,
    selection_parts,
)
from axs.render import display_width, emph, term_cols, tone, use_color


def exit_line(proxies):
    if _is_group(proxies.get("主代理")):
        mid, leaf = selection_parts(proxies)
        if not mid:
            return "当前出口：主代理 → -"
        return f"当前出口：主代理 → {mid}→ {leaf or '-'}"
    item = proxies.get("GLOBAL")
    if not _is_group(item):
        return "当前出口：-"
    now = item.get("now") if isinstance(item.get("now"), str) and item.get("now") else ""
    leaf = follow_leaf(proxies, now) if now else None
    return f"当前出口：GLOBAL → {leaf or now or '-'}"


def select_roots(proxies, origin):
    from axs.mihomo import rule_parts

    if origin is None:
        return []
    path = Path(origin).parent / CONFIG
    if not path.is_file():
        return []
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return []
    rules = data.get("rules") if isinstance(data, dict) else None
    if not isinstance(rules, list):
        return []
    names = []
    seen = set()
    for item in rules:
        parsed = rule_parts(item)
        if not parsed:
            continue
        name = parsed[2]
        if not name or name in seen or not _is_group(proxies.get(name)):
            continue
        seen.add(name)
        names.append(name)
    return names


def tree_roots(proxies):
    groups = [name for name, item in proxies.items() if _is_group(item)]
    referenced = set()
    for name in groups:
        members = proxies[name].get("all")
        if not isinstance(members, list):
            continue
        referenced.update(member for member in members if _is_group(proxies.get(member)))
    roots = sorted(name for name in groups if name not in referenced)
    if roots:
        return roots
    if _is_group(proxies.get("主代理")):
        return ["主代理"]
    if _is_group(proxies.get("GLOBAL")):
        return ["GLOBAL"]
    return sorted(groups)


def render_tree(proxies, depth=None, width=None, mode="full", origin=None):
    if width is None:
        width = term_cols()
    gnums = group_numbers(proxies)
    nnums = node_numbers(proxies)
    select = mode == "select"

    def group_line(name, prefix, mark):
        kind = str(proxies[name].get("type") or "-")
        note = " 自动·手选会被覆盖" if select and kind in AUTO_TYPES else ""
        return f"{prefix}G{gnums[name]} {name} [{kind}]{mark}{note}"

    def leaf_text(parent, name):
        item = proxies.get(name)
        kind = str(item.get("type")) if isinstance(item, dict) and item.get("type") else "-"
        number = nnums.get(name)
        text = f"N{number} {name} [{kind}]" if number else f"{name} [{kind}]"
        if proxies[parent].get("now") == name:
            text += " [*]"
        return text

    def pack(cells, prefix_width):
        widest = max(display_width(cell) for cell in cells)
        room = width - prefix_width
        if room < widest:
            room = widest
        cols = max(1, (room + 2) // (widest + 2))
        rows = []
        for start in range(0, len(cells), cols):
            chunk = cells[start : start + cols]
            parts = []
            for index, cell in enumerate(chunk):
                pad = "" if index == len(chunk) - 1 else " " * (widest - display_width(cell))
                parts.append(cell + pad)
            rows.append("  ".join(parts))
        return rows

    def blocks(parent, members, base, level, stack):
        grouped = []
        leaves = []

        def flush():
            nonlocal leaves
            if leaves:
                grouped.append(leaves)
                leaves = []

        for member in members:
            item = proxies.get(member)
            if _is_group(item):
                flush()
                grouped.append(member)
            elif select and not isinstance(item, dict):
                continue
            else:
                leaves.append(member)
        flush()
        lines = []
        for index, block in enumerate(grouped):
            last = index == len(grouped) - 1
            branch = base + ("└─ " if last else "├─ ")
            cont = base + ("   " if last else "│  ")
            if isinstance(block, list):
                rows = pack([leaf_text(parent, name) for name in block], display_width(branch))
                for row_index, row in enumerate(rows):
                    lines.append((branch if row_index == 0 else cont) + row)
                continue
            if block in stack:
                lines.append(f"{branch}↩ G{gnums[block]} {block}（回到上层）")
                continue
            mark = " *" if proxies[parent].get("now") == block else ""
            lines.extend(expand(block, branch, cont, level + 1, stack, mark))
        return lines

    def expand(name, line_prefix, child_base, level, stack, mark):
        lines = [group_line(name, line_prefix, mark)]
        if select and str(proxies[name].get("type") or "") in AUTO_TYPES:
            return lines
        if depth is not None and level >= depth:
            return lines
        members = proxies[name].get("all")
        if not isinstance(members, list):
            return lines
        return lines + blocks(name, members, child_base, level, stack + [name])

    lines = [exit_line(proxies)]
    roots = select_roots(proxies, origin) if select else tree_roots(proxies)
    for name in roots:
        lines.extend(expand(name, "", "", 1, [], ""))
    return "\n".join(lines) + "\n"


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
