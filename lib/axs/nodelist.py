"""Group table and node list rendering. Numbers and delay stay in nodes."""

import sys

from axs.mihomo import GROUP_TYPES, load_proxies
from axs.nodes import (
    _ansi,
    _as_exit3,
    _proxies,
    current_selection,
    delay_code,
    group_numbers,
    load_delays,
    node_numbers,
)
from axs.render import bold, dim, display_width, emph, ident, layout_cells, term_cols, tone, use_color

def _now(item):
    now = item.get("now") if isinstance(item, dict) else None
    if not isinstance(now, str) or now == "":
        return "-"
    return now

def group_table(proxies):
    numbers = group_numbers(proxies)
    rows = [(f"G{numbers[n]}", n, str(proxies[n].get("type")), _now(proxies[n])) for n in sorted(numbers, key=numbers.get)]
    if not rows:
        return ""
    widths = [max(display_width(row[i]) for row in rows) for i in range(3)]
    lines = []
    for num, name, kind, now in rows:
        plain = (num.rjust(widths[0]), name, kind)
        shown = (plain[0], ident(name), dim(kind))
        body = "  ".join(c + " " * (w - display_width(t)) for c, t, w in zip(shown, plain, widths))
        lines.append(body + "  " + (dim("-") if now == "-" else "→ " + emph("32", now)))
    return "\n".join(lines) + "\n"

def show_groups(secret_path, api):
    sys.stdout.write(group_table(_proxies(secret_path, api)))

def _show_nodes_full(proxies):
    rows = []
    for name, item in proxies.items():
        if not isinstance(item, dict) or item.get("type") in GROUP_TYPES:
            continue
        kind = item.get("type") or "-"
        hits = []
        for gname, gitem in proxies.items():
            if not isinstance(gitem, dict) or gitem.get("type") not in GROUP_TYPES:
                continue
            members = gitem.get("all") or []
            if isinstance(members, list) and name in members:
                star = "*" if gitem.get("now") == name else ""
                hits.append((gname, f"{star}\t{name}\t{kind}\t{gname}"))
        if hits:
            rows.extend((name, gname, line) for gname, line in hits)
        else:
            rows.append((name, "-", f"\t{name}\t{kind}\t-"))
    rows.sort()
    if rows:
        sys.stdout.write("\n".join(line for _, _, line in rows) + "\n")

def paint_cell(marker, num_text, name, delay_text, selected, delay_raw):
    plain = f"{marker}{num_text} {name} {delay_text}"
    if not use_color():
        return plain
    mark = emph("32", "[*]") + " " if selected else marker
    lead = len(num_text) - len(num_text.lstrip(" "))
    number = (" " * lead) + dim(num_text.lstrip(" "))
    shown = emph("32", name) if selected else name
    dlead = len(delay_text) - len(delay_text.lstrip(" "))
    body = delay_text.lstrip(" ")
    delay = (" " * dlead) + _ansi(delay_code(delay_raw), body)
    return f"{mark}{number} {shown} {delay}"

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


def render_rows(numbers, rows, heading):
    width = len(str(max(numbers.values()))) if numbers else 1
    lines = [bold("测速（全部叶子）")] if heading else []
    ordered = sorted(rows, key=lambda item: numbers[item[0]])
    for name, delay, reason in ordered:
        if delay is None:
            plain = reason or "超时"
            shown = tone("31", plain)
        else:
            plain = f"{delay}ms"
            shown = tone(delay_code(delay), plain)
        label = f"N{numbers[name]:>{width}}"
        lines.append(f"{label} {name} {shown}")
    return "\n".join(lines) + ("\n" if lines else "")
