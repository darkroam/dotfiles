#!/usr/bin/env python3
"""Docs: links resolve, banned words stay out, help is not copied."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.cli import SECTIONS  # noqa: E402

DOCS = ROOT / "docs"
BANNED = ("未跟踪", "孵化中")
PY_SENTENCE = "python3 是全部命令的硬依赖"


def fail(message):
    raise SystemExit(message)


def titles(text):
    found = []
    for line in text.splitlines():
        match = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
        if match:
            found.append(match.group(1).strip().replace("`", ""))
    return found


def slug(title):
    title = title.lower()
    title = re.sub(r"[^\w\u4e00-\u9fff\- ]+", "", title, flags=re.UNICODE)
    return re.sub(r"\s+", "-", title.strip())


def anchors(text):
    return {slug(title) for title in titles(text)}


def check_links(path, text):
    for match in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", text):
        target = match.group(1).strip()
        if target.startswith(("http://", "https://", "mailto:")):
            continue
        if target.startswith("#"):
            if target[1:] not in anchors(text):
                fail(path.name + " missing anchor " + target)
            continue
        file_part, _, frag = target.partition("#")
        dest = (path.parent / file_part).resolve()
        if not dest.is_file():
            fail(path.name + " missing " + file_part)
        if frag and frag not in anchors(dest.read_text(encoding="utf-8")):
            fail(path.name + " missing " + target)


def copied_help(design):
    copied = 0
    for _title, rows, _notes in SECTIONS:
        for cmd, alias, _desc in rows:
            if not alias:
                continue
            if re.search(r"\|\s*`?" + re.escape(cmd) + r"`?\s*\|", design):
                copied += 1
    return copied


def main():
    files = sorted(DOCS.glob("*.md"))
    names = {path.name for path in files}
    if names != {"README.md", "architecture.md", "constraints.md", "design.md", "roadmap.md"}:
        fail("docs set changed")
    for path in files:
        text = path.read_text(encoding="utf-8")
        for word in BANNED:
            if word in text:
                fail(path.name + " has a banned word")
        check_links(path, text)
    design = (DOCS / "design.md").read_text(encoding="utf-8")
    if re.search(r"\|[^\n]*命令[^\n]*\|[^\n]*别名", design):
        fail("design copies the command table")
    if copied_help(design) >= 3:
        fail("design copies help rows")
    if "目录" in titles(design):
        fail("design still draws a tree")
    readme = (DOCS / "README.md").read_text(encoding="utf-8")
    if PY_SENTENCE not in readme:
        fail("readme missing the python3 sentence")
    print("docs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
