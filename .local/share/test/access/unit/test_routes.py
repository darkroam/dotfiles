#!/usr/bin/env python3
"""Rule-target chains: counts, hops, and the down state."""
import ast
import os
import subprocess
import sys
import tempfile
from pathlib import Path

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))

from axs.nodes import group_numbers, node_numbers  # noqa: E402
from axs.routes import build  # noqa: E402
from axs.rulelist import status_text  # noqa: E402


def fail(message):
    raise SystemExit(message)


def write_config(run, body):
    (run / "config.yaml").write_text(body, encoding="utf-8")


def check_limits():
    lines = (ROOT / "axs" / "routes.py").read_text(encoding="utf-8").splitlines()
    if len(lines) > 160:
        fail("routes lines")
    tree = ast.parse((ROOT / "axs" / "routes.py").read_text(encoding="utf-8"))
    banned = {"rulelist", "tree", "service", "render"}
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("axs."):
            if node.module.split(".", 1)[1] in banned:
                fail("routes import " + node.module)
    arch = (ROOT.parent.parent / "share" / "docs" / "project" / "access-architecture.md").read_text(encoding="utf-8")
    if "`axs/routes.py`" not in arch or "\n routes   nodelist\n" not in arch:
        fail("architecture")


def check_chain():
    proxies = {
        "主代理": {"type": "Selector", "now": "自动", "all": ["自动", "甲"]},
        "自动": {"type": "URLTest", "now": "甲", "all": ["甲", "乙"]},
        "均衡": {"type": "LoadBalance", "all": ["乙"]},
        "甲": {"type": "Shadowsocks"},
        "乙": {"type": "Shadowsocks"},
    }
    with tempfile.TemporaryDirectory() as tmp:
        run = Path(tmp)
        write_config(
            run,
            "rules:\n"
            "  - DOMAIN,a.example,主代理\n"
            "  - DOMAIN-SUFFIX,b.example,主代理\n"
            "  - RULE-SET,ads,主代理\n"
            "  - MATCH,均衡\n"
            "  - DOMAIN,c.example,甲\n"
            "  - MATCH,DIRECT\n",
        )
        data = build(proxies, run)
    if data["other"] != 2 or data["terminals"] != ["自动", "均衡"]:
        fail("counts " + str((data["other"], data["terminals"])))
    names = [item["name"] for item in data["targets"]]
    if names != ["主代理", "均衡"]:
        fail("order " + " ".join(names))
    head, balance = data["targets"]
    if head["count"] != 3 or head["kinds"] != [("DOMAIN", 1), ("DOMAIN-SUFFIX", 1), ("RULE-SET", 1)]:
        fail("kinds " + str(head["kinds"]))
    if [hop["name"] for hop in head["hops"]] != ["主代理", "自动"] or head["leaf"]["name"] != "甲":
        fail("chain")
    if balance["leaf"] is not None or balance["kinds"] != [("MATCH", 1)]:
        fail("balance")
    gnums, nnums = group_numbers(proxies), node_numbers(proxies)
    lines = status_text(data).splitlines()
    want = [
        f"G{gnums['主代理']} 主代理 [Selector] · 规则 3（DOMAIN 1、DOMAIN-SUFFIX 1、RULE-SET 1） → G{gnums['自动']} 自动 [URLTest] → N{nnums['甲']} 甲",
        f"G{gnums['均衡']} 均衡 [LoadBalance] · 规则 1（MATCH 1） → -",
    ]
    if lines != want or "[*]" in status_text(data):
        fail("text\n" + "\n".join(lines))


def check_hops():
    with tempfile.TemporaryDirectory() as tmp:
        run = Path(tmp)
        write_config(run, "rules:\n  - MATCH,主代理\n")
        continued = build(
            {
                "主代理": {"type": "Selector", "now": "手动", "all": ["手动"]},
                "手动": {"type": "Selector", "now": "乙", "all": ["乙"]},
                "乙": {"type": "Shadowsocks"},
            },
            run,
        )
        if [hop["name"] for hop in continued["targets"][0]["hops"]] != ["主代理", "手动"]:
            fail("continue")
        if continued["terminals"] or continued["targets"][0]["leaf"]["name"] != "乙":
            fail("continue leaf")
        stopped = build(
            {
                "主代理": {"type": "Selector", "now": "自动", "all": ["自动"]},
                "自动": {"type": "URLTest", "now": "手动", "all": ["手动"]},
                "手动": {"type": "Selector", "now": "甲", "all": ["甲"]},
                "甲": {"type": "Shadowsocks"},
            },
            run,
        )
        hops = [hop["name"] for hop in stopped["targets"][0]["hops"]]
        if hops != ["主代理", "自动"] or stopped["targets"][0]["leaf"]["name"] != "甲":
            fail("stop " + " ".join(hops))


def check_shared():
    with tempfile.TemporaryDirectory() as tmp:
        run = Path(tmp)
        write_config(run, "rules:\n  - MATCH,入口\n  - DOMAIN,a.example,旁路\n")
        data = build(
            {
                "入口": {"type": "Selector", "now": "自动", "all": ["自动"]},
                "旁路": {"type": "Selector", "now": "自动", "all": ["自动"]},
                "自动": {"type": "URLTest", "now": "甲", "all": ["甲"]},
                "甲": {"type": "Shadowsocks"},
            },
            run,
        )
    if data["terminals"] != ["自动"]:
        fail("shared " + " ".join(data["terminals"]))


def check_down():
    with tempfile.TemporaryDirectory() as tmp:
        run = Path(tmp)
        if build({}, run) is not None:
            fail("missing config")
        (run / "config.yaml").write_text(":\n", encoding="utf-8")
        if build({}, run) is not None:
            fail("bad yaml")
        write_config(
            run,
            "proxy-groups:\n"
            "  - name: 主代理\n"
            "    type: select\n"
            "rules:\n"
            "  - DOMAIN,a.example,主代理\n"
            "  - DOMAIN,b.example,主代理\n"
            "  - MATCH,DIRECT\n",
        )
        data = build({}, run)
    if data["live"] or data["other"] != 1 or data["terminals"]:
        fail("down meta")
    target = data["targets"][0]
    if target["name"] != "主代理" or target["count"] != 2 or target["hops"] or target["leaf"]:
        fail("down target")
    if target["kinds"] != [("DOMAIN", 2)] or target["type"] != "Selector":
        fail("down kinds")
    text = status_text(data)
    if text != "主代理 [Selector] · 规则 2（DOMAIN 2） → 当前选择：-\n":
        fail("down text " + text)
    if "[*]" in text or text.startswith("G"):
        fail("down number")


def check_cli_down():
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin"),
        "HOME": "/tmp",
        "LANG": "C.UTF-8",
        "AXS_COLOR": "never",
        "AXS_SYSTEMD": "0",
        "AXS_FORBID_NET": "1",
    }
    with tempfile.TemporaryDirectory() as tmp:
        env["AXS_RUN"] = tmp
        env["HOME"] = tmp
        result = subprocess.run(
            [str(ROOT / "bin" / "axs"), "rule", "status"],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
    if result.returncode != 2 or result.stderr.strip() != "服务：未运行":
        fail(f"cli down {result.returncode} {result.stderr!r}")


def main():
    check_limits()
    check_chain()
    check_hops()
    check_shared()
    check_down()
    check_cli_down()
    print("routes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
