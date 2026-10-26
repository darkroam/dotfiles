"""Topology for node show --full and --select. Numbers come from nodes.py."""

from axs.nodes import (
    AUTO_TYPES,
    _is_group,
    follow_leaf,
    group_numbers,
    node_numbers,
    selection_parts,
)
from axs.render import display_width, term_cols
from axs.routes import select_roots


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
        note = " 自动·手动切换会被覆盖" if select and kind in AUTO_TYPES else ""
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
            if select and (block in home or block in lower_set):
                lines.append(point(block, branch))
                continue
            mark = " *" if proxies[parent].get("now") == block else ""
            lines.extend(expand(block, branch, cont, level + 1, stack, mark, section))
        return lines

    def expand(name, line_prefix, child_base, level, stack, mark, section):
        if not select and name in home:
            return [point(name, line_prefix)]
        lines = [group_line(name, line_prefix, mark)]
        if select and str(proxies[name].get("type") or "") in AUTO_TYPES:
            return lines
        home[name] = section
        if depth is not None and level >= depth:
            return lines
        members = proxies[name].get("all")
        if not isinstance(members, list):
            return lines
        return lines + blocks(name, members, child_base, level, stack + [name], section)

    def point(name, prefix):
        tail = "" if not select else ("（上方）" if home.get(name) == "上" else "（下方）")
        return f"{prefix}→ 见 G{gnums[name]} {name}{tail}"

    lines, home, lower_set = [exit_line(proxies)], {}, set()
    roots = select_roots(proxies, origin) if select else tree_roots(proxies)
    lower = []
    if select:
        seen = set(roots)
        for root_name in roots:
            item = proxies.get(root_name)
            if not _is_group(item) or item.get("type") != "Selector":
                continue
            members = item.get("all")
            if not isinstance(members, list):
                continue
            for name in members:
                child = proxies.get(name)
                if name in seen or not _is_group(child) or child.get("type") != "Selector":
                    continue
                seen.add(name)
                lower.append(name)
        lower.sort(key=gnums.get)
        lower_set.update(lower)
        lines.append("规则入口")
    for name in roots:
        lines.extend(expand(name, "", "", 1, [], "", "上" if select else ""))
    if lower:
        lines.append("成员引用")
        for name in lower:
            lines.extend([point(name, "")] if name in home else expand(name, "", "", 1, [], "", "下"))
    return "\n".join(lines) + "\n"


