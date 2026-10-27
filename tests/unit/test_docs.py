#!/usr/bin/env python3
"""Docs: links resolve, banned words stay out, help is not copied."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.catalog import SECTIONS  # noqa: E402

DOCS = ROOT / "docs"
BANNED = ("未跟踪", "孵化中", "还没测")
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
        slugs = [slug(title) for title in titles(text)]
        if len(slugs) != len(set(slugs)):
            fail(path.name + " has a repeated heading slug")
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
    if "`axs g m <组>`" not in readme:
        fail("readme missing members")
    for dead in ("axs n m", "axs n l", "axs e"):
        if dead in readme:
            fail("readme keeps dead example " + dead)
    for word in ("池", "成员", "引用", "编号"):
        if word not in design:
            fail("design missing " + word)
    if "| 动作 | 缺参 |" not in design:
        fail("design missing the arg matrix")
    arch = (DOCS / "architecture.md").read_text(encoding="utf-8")
    if "tree     service" not in arch:
        fail("layer diagram lost tree")
    if "| rules | subscription |" not in arch:
        fail("ledger")
    if "不得引用任何 axs 模块" not in arch:
        fail("render sink")
    if "`lib/axs/tree.py`" not in arch:
        fail("tree file row")
    if "`lib/axs/selectview.py`" not in arch:
        fail("selectview file row")
    if "`lib/axs/nodeview.py`" not in arch:
        fail("nodeview file row")
    if "| `lib/axs/catalog.py` | 命令树数据与子命令签名。不解析、不分发、不排版 | 160 行 |" not in arch:
        fail("catalog ceiling")
    sentence = "用法：axs group members <组>（先看 group status）"
    if design.count(sentence) != 2:
        fail("members hint")
    if "提示先看 group status" in design:
        fail("old members hint")
    parse = design.split("## 解析", 1)[1].split("## 退出码", 1)[0]
    for phrase in (
        "未知命令：xxx（属于 group）",
        "未知选项：--x",
        "旗标：（无）",
        "候选：",
        "需要 --yes",
        "不是本地规则",
        "整页用法",
        "用法：axs proxy user on|off|status",
        "用法：axs proxy system on|off|enable|disable|status",
        "用法：axs proxy session enable|disable|status",
    ):
        if phrase not in parse:
            fail("parse " + phrase)
    if "更多入口：axs help --verbose" not in parse or "help -v" not in parse:
        fail("verbose docs")
    if design.count("用法：axs group switch <组> <成员>") != 2 or "提示用 members 看成员" in design:
        fail("switch usage")
    if "`tests/unit/test_render.py`" not in arch:
        fail("test_render row")
    if "阶段 2 记录" in arch or "步 13" in arch:
        fail("process narrative")
    heads = titles(design)
    if "模型与术语" not in heads or heads.index("模型与术语") > heads.index("解析"):
        fail("model chapter")
    for name in ("术语表", "规则与匹配顺序", "选择与出口", "视图与编号", "运维"):
        if name not in heads:
            fail("missing section " + name)
    if "不占 `N#`" in design or "内置策略和悬空名没有编号" in design:
        fail("builtin still unnumbered")
    if "但占 `N#`" not in design or "`N#` 覆盖全部叶子端点" not in design:
        fail("builtin number")
    if design.count("池") != 1 or "load_proxies" not in design or "不另造 pool" not in design:
        fail("pool")
    if design.count("悬空名不是成员") != 1:
        fail("dangling")
    start = design.split("### 规则与匹配顺序", 1)
    if len(start) != 2:
        fail("rules section")
    body = start[1].split("### 选择与出口", 1)[0]
    if len(body.splitlines()) > 80:
        fail("rules section too long")
    for phrase in (
        "首个命中",
        "no-resolve",
        "rules.list",
        "behavior",
        "mrs",
        "DOMAIN-SUFFIX,example.com",
        "不保证本订阅会出现这些类型",
        "组名不存在",
    ):
        if phrase not in body:
            fail("rules section missing " + phrase)
    ref = "design.md#模型与术语"
    for name in ("README.md", "constraints.md", "roadmap.md", "architecture.md"):
        other = (DOCS / name).read_text(encoding="utf-8")
        if ref not in other:
            fail(name + " missing the term link")
        if "术语表" in other or "悬空名不是成员" in other:
            fail(name + " redefines terms")
    print("docs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
