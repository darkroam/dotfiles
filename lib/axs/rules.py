"""Rule lines, then the merge-install-reload-rollback chain."""
import sys
from pathlib import Path

from axs.config import CONFIG, CONFIG_NEW, OVERRIDE, RULES, SECRET, SUBSCRIPTION
from axs.core import atomic_write, install_file, restore_snapshot, snapshot
from axs.subscription import build_file


def _fail(message):
    from axs.core import fail

    fail(message)


def _exit3(message=None):
    if message:
        sys.stderr.write(message + "\n")
    raise SystemExit(3)


def _die(message):
    # shell say_err colors this line; build and reload already printed a plain copy
    import os

    from axs.render import bad

    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        text = bad(message)
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
    _exit3(text)


def rule_line(kind, domain, group):
    if kind not in ("via", "direct"):
        _fail("用法")
    if "://" in domain or any(ch in domain for ch in "/?#,* \t"):
        _fail("用法")
    if domain.startswith("."):
        host = domain.lstrip(".")
        form = "DOMAIN-SUFFIX"
    else:
        host = domain
        form = "DOMAIN"
    if not host or host.startswith("-") or ".." in host:
        _fail("用法")
    if kind == "direct":
        policy = "DIRECT"
    else:
        if not group or any(ch in group for ch in " ,\t"):
            _fail("用法")
        policy = group
    return f"{form} {host} {policy}"


def parse_rule(kind, domain, group):
    sys.stdout.write(rule_line(kind, domain, group) + "\n")


def rules_add(path, line):
    parts = line.split()
    if len(parts) != 3:
        _fail("用法")
    path = Path(path)
    rows = []
    if path.is_file():
        rows = [item for item in path.read_text(encoding="utf-8").splitlines() if item.strip()]
    rows = [item for item in rows if item.split()[1:2] != [parts[1]]]
    rows.append(line.strip())
    atomic_write(path, "\n".join(rows) + "\n")


def rules_del(path, domain):
    host = domain.lstrip(".") if domain.startswith(".") else domain
    path = Path(path)
    if not path.is_file():
        return
    rows = []
    for item in path.read_text(encoding="utf-8").splitlines():
        parts = item.split()
        if len(parts) == 3 and parts[1] == host:
            continue
        if item.strip():
            rows.append(item)
    atomic_write(path, ("\n".join(rows) + "\n") if rows else "")


def has_group(secret_path, api, name):
    from axs.mihomo import group_names

    try:
        names = group_names(secret_path, api)
    except (SystemExit, OSError):
        _exit3("控制器")
    if name not in names:
        _exit3("组名不存在")


def _apply_kept(run, api):
    staged = run / CONFIG_NEW
    try:
        build_file(run / SUBSCRIPTION, run / OVERRIDE, run / SECRET, run / RULES, staged)
    except SystemExit:
        restore_snapshot(run)
        _die("校验失败")
    install_file(staged, run / CONFIG)
    from axs.mihomo import reload_core

    try:
        reload_core(run / SECRET, api, run / CONFIG)
    except SystemExit:
        restore_snapshot(run)
        _die("重载失败")


def _checked(op, args):
    if op == "add":
        kind = args[0]
        domain = args[1]
        group = args[2] if len(args) > 2 else ""
        return rule_line(kind, domain, group), domain, group
    domain = args[0]
    rule_line("direct", domain, "")
    return "", domain, ""


def check(run, op, running, api, args):
    _checked(op, args)
    if running == "1" and op == "add" and args[0] == "via":
        has_group(Path(run) / SECRET, api, args[2])


def mutate(run, op, running, api, args):
    # group lookup stays in check(); the shell calls that before the lock
    line, domain, _group = _checked(op, args)
    run = Path(run)
    snapshot(run)
    if op == "add":
        rules_add(run / RULES, line)
    else:
        rules_del(run / RULES, domain)
    if running != "1":
        sys.stdout.write("已写入，启动时生效\n")
        return
    if not (run / SUBSCRIPTION).is_file():
        restore_snapshot(run)
        _die("没有订阅")
    from axs.core import gen_secret

    gen_secret(run / SECRET)
    _apply_kept(run, api)
