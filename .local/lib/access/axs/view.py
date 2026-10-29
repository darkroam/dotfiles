"""Screens. Data to text only: no controller calls and no speed tests."""

from pathlib import Path

from axs.nodes import AUTO_TYPES, _is_group, group_numbers, node_numbers
from axs.render import display_width, layout_cells, ok, term_cols, view_page
from axs.routes import build, select_roots
from axs.rulelist import status_text


def _members(proxies, name):
    item = proxies.get(name)
    got = item.get("all") if isinstance(item, dict) else None
    return got if isinstance(got, list) else []


def _star(current):
    if not current:
        return "", ""
    return " [*]", " " + ok("[*]")


def render_select(proxies, depth=None, origin=None, view=False, width=None):
    if width is None:
        width = term_cols()
    gnums, nnums = group_numbers(proxies), node_numbers(proxies)
    roots = select_roots(proxies, origin)
    root_sel = [name for name in roots if proxies[name].get("type") == "Selector"]
    seen, lower, queue, index = set(root_sel), [], [], 0
    for name in root_sel:
        queue.extend(_members(proxies, name))
    while index < len(queue):
        member = queue[index]
        index += 1
        item = proxies.get(member)
        if member in seen or not _is_group(item):
            continue
        seen.add(member)
        if item.get("type") in AUTO_TYPES:
            continue
        if item.get("type") == "Selector":
            lower.append(member)
        queue.extend(_members(proxies, member))
    lower.sort(key=gnums.get)
    place = {name: "当前规则目标组" for name in root_sel}
    place.update((name, "成员引用") for name in lower)

    def group_text(parent, name):
        item = proxies[name]
        kind = str(item.get("type") or "-")
        star = _star(proxies[parent].get("now") == name)[1]
        if kind == "Selector" and name in place:
            return f"G{gnums[name]} {name} [Selector]{star} → 见{place[name]}"
        note = " 自动·手动切换会被覆盖" if kind in AUTO_TYPES else ""
        return f"G{gnums[name]} {name} [{kind}]{star}{note}"

    def leaf_pair(parent, name):
        number = nnums.get(name)
        head = f"N{number} " if number else ""
        plain_star, star = _star(proxies[parent].get("now") == name)
        return head + name + plain_star, head + name + star

    def block(name):
        kind = str(proxies[name].get("type") or "-")
        note = " 自动·手动切换会被覆盖" if kind in AUTO_TYPES else ""
        lines = [f"  G{gnums[name]} {name} [{kind}]{note}"]
        if kind != "Selector" or depth == 1:
            return "\n".join(lines)
        groups, leaves = [], []
        for member in _members(proxies, name):
            child = proxies.get(member)
            if not isinstance(child, dict):
                continue
            if _is_group(child):
                groups.append(group_text(name, member))
            else:
                leaves.append(leaf_pair(name, member))
        chunks = [[text] for text in groups]
        if leaves:
            gutter = display_width("  └─ ")
            chunks.append(layout_cells(leaves, max(1, width - gutter)))
        last = len(chunks) - 1
        for index, rows in enumerate(chunks):
            branch = "└─ " if index == last else "├─ "
            pad = "   " if index == last else "│  "
            for row_index, row in enumerate(rows):
                lines.append("  " + (branch if row_index == 0 else pad) + row)
        return "\n".join(lines)

    upper = "\n\n".join(block(name) for name in roots)
    low = "\n\n".join(block(name) for name in lower)
    if not view:
        chunks = ["规则入口"]
        if upper:
            chunks.append(upper)
        if low:
            chunks.extend(["成员引用", low])
        return "\n".join(chunks) + "\n"
    run = Path(origin).parent if origin is not None else None
    data = build(proxies, run) if run is not None else None
    path = status_text(data).strip("\n") if data else ""
    blocks = [("当前规则目标组（可切换）：", upper)]
    if low:
        blocks.append(("成员引用（仅被其他组引用的组）：", low))
    note = "说明：可手动切换项；每个 Selector 只展开一层，自动组只作终端。"
    return view_page(path, blocks, note)


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


