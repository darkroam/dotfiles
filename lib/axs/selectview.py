"""One-layer blocks for node show. Full topology stays in tree.py."""

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
