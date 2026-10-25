"""Rule identity, source labels, and the show lines. Not install or reload."""

from axs.codes import DOWN, FAIL
import hashlib
import re
import sys
from pathlib import Path

import yaml

from axs.config import CONFIG, RULES

_RID = re.compile(r"^R[0-9a-f]{6}$")


def rule_id(source, line):
    basis = line
    if source == "local":
        from axs.mihomo import rule_parts

        parsed = rule_parts(line)
        if parsed is not None:
            basis = parsed[1]
    return "R" + hashlib.sha256(basis.encode()).hexdigest()[:6]


def _kept_lines(path):
    if not path.is_file():
        return []
    kept = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.strip() and not raw.lstrip().startswith("#"):
            kept.append(raw)
    return kept


def _classify(run, lines, source=None):
    from axs.mihomo import _rule_key, _sources, rule_parts

    prepend, local = (set(), set()) if source else _sources(run)
    labeled = []
    for line in lines:
        if source:
            labeled.append((source, line))
            continue
        parsed = rule_parts(line)
        key = _rule_key(*parsed) if parsed else None
        if key in prepend:
            kind = "prepend"
        elif key in local:
            kind = "local"
        else:
            kind = "provider"
        labeled.append((kind, line))
    return labeled


def _show_lines(run, lines, source=None):
    labeled = _classify(run, lines, source)
    if not labeled:
        return ""
    width = len(str(len(labeled)))
    rows = [
        f"{index:>{width}}  {rule_id(kind, line)}  {kind:<8}  {line}"
        for index, (kind, line) in enumerate(labeled, 1)
    ]
    return "\n".join(rows) + "\n"


def _config_lines(run):
    path = Path(run) / CONFIG
    if not path.is_file():
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError:
        return None
    rules = data.get("rules") if isinstance(data, dict) else None
    if not isinstance(rules, list):
        return None
    return [item for item in rules if isinstance(item, str)]


def is_selector(token):
    return _RID.fullmatch(token) is not None or "," in token


def has_local(run, domain):
    host = domain.lstrip(".") if domain.startswith(".") else domain
    path = Path(run) / RULES
    rows = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
    return any(len(parts) == 3 and parts[1] == host for parts in (item.split() for item in rows))


def resolve_delete(run, token):
    from axs.mihomo import rule_parts
    from axs.render import die

    run = Path(run)
    by_id = _RID.fullmatch(token) is not None
    hits = []
    config = _config_lines(run)
    for kind, line in _classify(run, config or []):
        matched = rule_id(kind, line) == token if by_id else line == token
        if matched:
            hits.append((kind, line))
    for line in _kept_lines(run / RULES):
        matched = rule_id("local", line) == token if by_id else line == token
        if matched:
            hits.append(("local", line))
    if not hits:
        die(FAIL, "规则不存在")
    if any(kind != "local" for kind, _line in hits):
        die(FAIL, "不是本地规则")
    parsed = rule_parts(hits[0][1])
    if not parsed or not parsed[1]:
        die(FAIL, "规则不存在")
    return parsed[1]


def cmd_list(run, local=False):
    run = Path(run)
    if local:
        sys.stdout.write(_show_lines(run, _kept_lines(run / RULES), "local"))
        return
    from axs.render import die

    lines = _config_lines(run)
    if lines is None:
        die(DOWN, "服务：未运行")
    sys.stdout.write(_show_lines(run, lines))
