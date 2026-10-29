"""Rule lines, then the merge-install-reload-rollback chain."""

from axs.codes import USAGE, FAIL
import sys
from pathlib import Path

from axs.config import CONFIG, CONFIG_NEW, OVERRIDE, RULES, SECRET, SUBSCRIPTION
from axs.core import atomic_write, install_file, restore_snapshot, snapshot
from axs.profile import build_file


def _fail(message):
    from axs.core import fail

    fail(message)


def _exit3(message=None):
    if message:
        sys.stderr.write(message + "\n")
    raise SystemExit(FAIL)


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
    if kind not in ("via", "direct", "node"):
        _fail("用法错误")
    if "://" in domain or any(ch in domain for ch in "/?#,* \t"):
        _fail("用法错误")
    host = domain.lstrip(".") if domain.startswith(".") else domain
    if not host or host.startswith("-") or ".." in host:
        _fail("用法错误")
    form = "DOMAIN-SUFFIX" if domain.startswith(".") else "DOMAIN"
    if kind == "direct":
        return f"{form} {host} DIRECT"
    if not group:
        _fail("用法错误")
    if any(ch in group for ch in " ,\t"):
        if kind == "node":
            _fail("节点名不能含空白或逗号")
        _fail("用法错误")
    return f"{form} {host} {group}"




def rules_add(path, line):
    parts = line.split()
    if len(parts) != 3:
        _fail("用法错误")
    path = Path(path)
    rows = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
    rows = [item for item in rows if item.strip() and item.split()[1:2] != [parts[1]]]
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
        _exit3("控制器失败")
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


ADD = {"d": "direct", "direct": "direct", "v": "via", "via": "via", "n": "node", "node": "node"}


def _leaf(secret_path, api, name):
    if name in ("DIRECT", "REJECT"):
        return
    from axs.mihomo import GROUP_TYPES, load_proxies

    try:
        item = load_proxies(secret_path, api).get(name)
    except (SystemExit, OSError):
        _exit3("控制器失败")
    if not isinstance(item, dict):
        _exit3("节点不存在")
    if item.get("type") in GROUP_TYPES:
        _exit3("不是节点")


def check(run, op, running, api, args):
    _checked(op, args)
    if running == "1" and op == "add" and len(args) > 2:
        path = Path(run) / SECRET
        if args[0] == "via":
            has_group(path, api, args[2])
        elif args[0] == "node":
            _leaf(path, api, args[2])


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
        verb = "已删除" if op == "del" else "已写入"
        sys.stdout.write(verb + "，启动时生效\n")
        return
    if not (run / SUBSCRIPTION).is_file():
        restore_snapshot(run)
        _die("没有订阅")
    from axs.core import gen_secret

    gen_secret(run / SECRET)
    _apply_kept(run, api)


def _mutate_live(run, op, args):
    from axs.config import read_ports
    from axs.core import hold_lock, service_up

    running, api = ("1", read_ports(run)[1]) if service_up(run) else ("0", "")
    check(run, op, running, api, args)
    hold_lock(run)
    mutate(run, op, running, api, args)


def cmd_add(run, args):
    from axs.render import die

    kind = ADD.get(args[0]) if args else None
    if (kind == "direct" and len(args) == 2) or (kind in ("via", "node") and len(args) == 3):
        _mutate_live(run, "add", [kind, *args[1:]])
        return
    die(USAGE, "用法错误")


def cmd_del(run, args):
    from axs.render import die
    from axs.rulelist import has_local, is_selector, resolve_delete

    if len(args) != 1:
        die(USAGE, "用法错误")
    token = args[0]
    if is_selector(token):
        token = resolve_delete(run, token)
    else:
        rule_line("direct", token, "")
        if not has_local(run, token):
            die(FAIL, "规则不存在")
    _mutate_live(run, "del", [token])
