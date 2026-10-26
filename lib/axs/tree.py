"""Topology for node show --full. Numbers come from nodes.py."""

from axs.nodes import (
    _is_group,
    group_numbers,
    node_numbers,
)
from pathlib import Path

from axs.render import display_width, term_cols, view_page
from axs.routes import build
from axs.rulelist import status_text


def min_group_depth(proxies, roots):
    depth, pending = {}, []
    for name in roots:
        if name in depth:
            continue
        depth[name] = 1
        pending.append(name)
    index = 0
    while index < len(pending):
        name = pending[index]
        index += 1
        members = proxies[name].get("all")
        if not isinstance(members, list):
            continue
        nxt = depth[name] + 1
        for member in members:
            if member in depth or not _is_group(proxies.get(member)):
                continue
            depth[member] = nxt
            pending.append(member)
    return depth


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


def render_tree(proxies, depth=None, width=None, origin=None, view=False):
    if width is None:
        width = term_cols()
    gnums = group_numbers(proxies)
    nnums = node_numbers(proxies)

    def group_line(name, prefix, mark):
        kind = str(proxies[name].get("type") or "-")
        return f"{prefix}G{gnums[name]} {name} [{kind}]{mark}"

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

    def blocks(parent, members, base, level, stack, section):
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
            lines.extend(expand(block, branch, cont, level + 1, stack, mark, section))
        return lines

    def expand(name, line_prefix, child_base, level, stack, mark, section):
        if name in home or level != depths.get(name, level):
            return [point(name, line_prefix)]
        lines = [group_line(name, line_prefix, mark)]
        home[name] = section
        if depth is not None and level >= depth:
            return lines
        members = proxies[name].get("all")
        if not isinstance(members, list):
            return lines
        return lines + blocks(name, members, child_base, level, stack + [name], section)

    def point(name, prefix):
        tail = "（上方）" if name in home else "（下方）"
        return f"{prefix}→ 见 G{gnums[name]} {name}{tail}"

    home = {}
    roots = tree_roots(proxies)
    depths = min_group_depth(proxies, roots)
    upper = []
    for name in roots:
        upper.extend(expand(name, "", "", 1, [], "", ""))
    body = "\n".join(upper)
    if not view:
        return body + "\n"
    data = build(proxies, Path(origin).parent) if origin is not None else None
    path = status_text(data).strip("\n") if data else ""
    note = "说明：完整拓扑；每组只在最小深度处展开一次，不带延迟。"
    return view_page(path, [("完整拓扑：", body)], note)


