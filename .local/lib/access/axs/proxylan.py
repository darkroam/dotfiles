"""LAN listen switch. Does not touch the three proxy layers."""

import os
import subprocess
import sys
from pathlib import Path

import yaml

from axs.codes import FAIL, USAGE
from axs.config import CONFIG, LOOPBACK, SECRET, atomic_write, ensure_override, read_ports
from axs.mihomo import reload_core
from axs.net import port_open
from axs.render import call_usage, die, warn

BIND_ALL = "*"
WARN = "混合端口无认证，仅限可信局域网"


def run(run, args):
    verb = ""
    yes = False
    for arg in args:
        if arg == "--yes":
            yes = True
        elif verb:
            _usage()
        else:
            verb = arg
    if verb == "status":
        sys.stdout.write(status_text(run))
        return
    if verb == "on":
        if not yes:
            _warn("局域网监听无认证，确认后加 --yes")
            _usage()
        _apply(run, True)
        return
    if verb == "off":
        _apply(run, False)
        return
    _usage()


def summary(run):
    _path, _raw, data = _load(run)
    allow = data.get("allow-lan") is True
    bind = data.get("bind-address") or "-"
    return ("on" if allow else "off"), allow, str(bind)


def status_text(run):
    _state, allow, bind = summary(run)
    mixed, _api = read_ports(run)
    lans = ", ".join(_lan_addrs()) or "-"
    lines = [
        f"allow-lan  {'true' if allow else 'false'}",
        f"bind       {bind}",
        f"端口       {mixed}",
        f"LAN        {lans}",
        WARN,
    ]
    return "\n".join(lines) + "\n"


def _apply(run, enable):
    from axs.config import CONFIG_NEW, RULES, SUBSCRIPTION
    from axs.core import hold_lock, install_file
    from axs.profile import build_file

    hold_lock(run)
    run = Path(run)
    path, raw, data = _load(run)
    config = run / CONFIG
    config_raw = config.read_text(encoding="utf-8") if config.is_file() else None
    data["allow-lan"] = bool(enable)
    data["bind-address"] = BIND_ALL if enable else LOOPBACK
    atomic_write(path, yaml.safe_dump(data, allow_unicode=True, sort_keys=False))
    try:
        if (run / SUBSCRIPTION).is_file():
            build_file(run / SUBSCRIPTION, path, run / SECRET, run / RULES, run / CONFIG_NEW)
            install_file(run / CONFIG_NEW, config)
        mixed, api = read_ports(run)
        reload_core(run / SECRET, api, config)
        opened = port_open(mixed)
    except SystemExit:
        opened = False
    if not opened:
        atomic_write(path, raw)
        if config_raw is None:
            config.unlink(missing_ok=True)
        else:
            atomic_write(config, config_raw)
        die(FAIL, "回环端口未保持，已恢复 override")


def _load(run):
    path = ensure_override(run)
    raw = path.read_text(encoding="utf-8")
    data = yaml.safe_load(raw)
    if not isinstance(data, dict):
        die(FAIL, "override 损坏")
    return path, raw, data


def _lan_addrs():
    try:
        out = subprocess.run(
            ["ip", "-4", "-o", "addr", "show", "scope", "global"],
            capture_output=True, text=True, timeout=2, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    found = []
    for line in out.stdout.splitlines():
        parts = line.split()
        if "inet" not in parts:
            continue
        ip = parts[parts.index("inet") + 1].split("/", 1)[0]
        if ip and not ip.startswith(LOOPBACK) and ip not in found:
            found.append(ip)
    return found


def _warn(text):
    _paint(lambda: sys.stderr.write(warn(text) + "\n"))


def _usage():
    _paint(lambda: sys.stderr.write(call_usage("proxy", "lan") + "\n"))
    raise SystemExit(USAGE)


def _paint(write):
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        write()
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
