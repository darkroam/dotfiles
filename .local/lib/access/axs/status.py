"""Status pages. Above service, below cli. Does not start or stop anything."""

import sys
from pathlib import Path

from axs.codes import DOWN, FAIL, EXPIRED
from axs.config import SECRET, USERINFO, status_ports
from axs.core import (
    active,
    format_span,
    manual_etime,
    next_refresh,
    read_pid,
    run_systemctl,
    service_up,
    systemd_etime,
    systemd_on,
    unix_now,
)
from axs.mihomo import load_proxies
from axs.net import port_open
from axs.proxy import proxy_status_rows
from axs.render import bad, bold, dim, emph, label, ok
from axs.routes import build
from axs.rulelist import status_text
from axs.service import controller_ok
from axs.subscription import subscription_line


def cache_value(run, name):
    path = Path(run) / "cache" / name
    if not path.is_file():
        return dim("-")
    ts = result = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("ts=") and not ts:
            ts = line[3:]
        elif line.startswith("result=") and not result:
            result = line[7:]
    if not ts.isdigit():
        return dim("-")
    rel = format_span(max(0, unix_now() - int(ts)), "前")
    if name == "net-test":
        bit = ok("全部通") if result == "ok" else bad("有不通")
        return f"{dim(rel)} · {bit}"
    return dim(rel)


def head(title):
    sys.stdout.write(bold(title) + "\n")


def row(name, value):
    sys.stdout.write("  " + label(name) + value + "\n")


def service_section(run):
    running = 0
    if systemd_on():
        if active():
            pid = "".join(
                run_systemctl(["show", "axs.service", "-p", "MainPID", "--value"], capture=True).stdout.split()
            )
            if not pid.isdigit() or pid == "0":
                pid = "-"
            state = f"{emph('32', '运行中')}（systemd，pid {dim(pid)}，{dim(systemd_etime())}）"
            running = 1
        else:
            state = f"{emph('31', '未运行')}（systemd）"
    elif service_up(run):
        pid = read_pid(run)
        state = f"{emph('32', '运行中')}（手动，pid {dim(pid)}，{dim(manual_etime(pid))}）"
        running = 1
    else:
        state = f"{emph('31', '未运行')}（手动）"
    mixed, api = status_ports(run)
    port_ok = port_open(mixed)
    api_ok = controller_ok(run, api)
    port_bit = f"{dim(str(mixed))} {ok('监听') if port_ok else bad('不通')}"
    api_bit = f"{dim(api.rsplit(':', 1)[-1])} {ok('可达') if api_ok else bad('不通')}"
    if systemd_on():
        enabled = run_systemctl(["is-enabled", "axs.service"], quiet=True).returncode == 0
        boot = f"{ok('enabled') if enabled else bad('disabled')}（刷新：{next_refresh()}）"
    else:
        boot = dim("-")
    head("服务")
    row("状态    ", state)
    row("端口    ", f"{port_bit} · 控制器 {api_bit}")
    row("自启    ", boot)
    return running, port_ok, api_ok, api, mixed


def service_status(run):
    running, port_ok, api_ok, _api, _mixed = service_section(run)
    if running == 0 or not port_ok:
        raise SystemExit(DOWN)
    if not api_ok:
        raise SystemExit(FAIL)


def node_status_lines(proxies, run):
    data = build(proxies, run) if proxies else None
    if not data or not data.get("live"):
        return []
    return status_text(data).splitlines()


def write_node_status(run, api):
    proxies = {}
    if api:
        try:
            loaded = load_proxies(Path(run) / SECRET, api)
        except SystemExit:
            loaded = {}
        if isinstance(loaded, dict):
            proxies = loaded
    lines = node_status_lines(proxies, run)
    if not lines:
        sys.stdout.write("  " + dim("-") + "\n")
        return
    for line in lines:
        sys.stdout.write("  " + line + "\n")


def status(run):
    running, port_ok, api_ok, api, _mixed = service_section(run)
    text, kind = subscription_line(Path(run) / USERINFO, unix_now())
    head("订阅")
    sys.stdout.write("  " + text + "\n")
    head("路由")
    write_node_status(run, api if port_ok and api_ok else "")
    head("测速")
    row("net     ", cache_value(run, "net-test"))
    row("node    ", cache_value(run, "node-test"))
    head("代理")
    for line in proxy_status_rows(run):
        sys.stdout.write("  " + line + "\n")
    if running == 0 or not port_ok:
        code = DOWN
    elif not api_ok:
        code = FAIL
    elif kind == "expired":
        code = EXPIRED
    else:
        code = 0
    if code:
        raise SystemExit(code)

