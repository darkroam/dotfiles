"""Fetch, check, merge, install, roll back, and clean a subscription."""

from axs.codes import FAIL, USAGE
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


from axs.config import (
    CONFIG,
    CONFIG_BAK,
    FETCH_BODY,
    FETCH_HEADER,
    PID,
    SNAP,
    SUBSCRIPTION,
    LIST,
    URL,
    USERINFO,
)
from axs.core import atomic_write, fail, hold_lock, install_file, restore_snapshot, snapshot, unix_now
from axs.profile import build_file
from axs.render import die
from axs.subslist import classify, subscription_line
import axs.subslist as subslist


take_snapshot = snapshot
rollback = restore_snapshot
install_merged = install_file

YAML_TYPES = {
    "text/yaml",
    "application/yaml",
    "application/x-yaml",
    "text/x-yaml",
    "text/plain",
    "application/octet-stream",
}

def check_url(path):
    raw = Path(path).read_text(encoding="utf-8", errors="replace")
    url = raw.strip("\r\n")
    if url != url.strip() or any(ch.isspace() for ch in url) or "\\" in url:
        sys.stderr.write("链接含转义字符（如 \\?），请去掉反斜杠\n")
        raise SystemExit(FAIL)

def _header_field(text, name):
    prefix = name.lower() + ":"
    for line in text.splitlines():
        if line.lower().startswith(prefix):
            return line.split(":", 1)[1].strip()
    return ""

def _yaml_type(value):
    if not value or not value.strip():
        return True
    main = value.split(";", 1)[0].strip().lower()
    return main in YAML_TYPES or main.endswith("/yaml") or main.endswith("+yaml")

def check_fetched(body_path, header_path):
    body_file = Path(body_path)
    body = body_file.read_bytes() if body_file.is_file() else b""
    header = ""
    header_file = Path(header_path)
    if header_file.is_file():
        header = header_file.read_text(encoding="utf-8", errors="replace")
    status = _header_field(header, "x-axs-status") or "-"
    ctype = _header_field(header, "x-axs-content-type")
    html = body.lstrip().startswith(b"<")
    if body.strip() and _yaml_type(ctype) and not html:
        return
    shown = ctype or ("text/html" if html else "-")
    sys.stderr.write(
        f"订阅返回空内容/非 YAML（HTTP {status}, {shown}），请检查链接\n"
    )
    raise SystemExit(FAIL)

def fetch(urlfile, body_path, header_path):
    if os.environ.get("AXS_FORBID_NET") == "1":
        fail("离线测试拒绝联网")
    url = Path(urlfile).read_text(encoding="utf-8").strip()
    if not url.startswith(("http://", "https://")):
        fail("拉取失败")
    req = urllib.request.Request(url, headers={"User-Agent": "axs"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            payload = resp.read()
            info = resp.headers.get("subscription-userinfo", "")
            status = getattr(resp, "status", None) or 200
            ctype = resp.headers.get("content-type") or ""
    except (urllib.error.URLError, TimeoutError, OSError):
        fail("拉取失败")
    Path(body_path).write_bytes(payload)
    Path(header_path).write_text(
        "subscription-userinfo: " + info + "\n"
        + f"x-axs-status: {status}\n"
        + f"x-axs-content-type: {ctype}\n",
        encoding="utf-8",
    )

def write_userinfo(header_path, out_path):
    text = Path(header_path).read_text(encoding="utf-8", errors="replace")
    value = ""
    for line in text.splitlines():
        if line.lower().startswith("subscription-userinfo:"):
            value = line.split(":", 1)[1].strip()
    fields = {}
    for part in value.split(";"):
        if "=" not in part:
            continue
        key, raw = part.split("=", 1)
        fields[key.strip()] = raw.strip()
    lines = []
    for key in ("upload", "download", "total", "expire"):
        if key in fields and fields[key].isdigit():
            lines.append(f"{key}={fields[key]}")
    atomic_write(out_path, ("\n".join(lines) + ("\n" if lines else "")))

def clean_names(kind):
    if kind == "config":
        return (CONFIG, CONFIG_BAK, USERINFO, FETCH_BODY, FETCH_HEADER, PID, LIST, SUBSCRIPTION, URL)
    return (SUBSCRIPTION, USERINFO, FETCH_BODY, FETCH_HEADER)


def clear_fetch(run):
    run = Path(run)
    for name in (FETCH_BODY, FETCH_HEADER):
        (run / name).unlink(missing_ok=True)
    snap = run / SNAP
    for name in (CONFIG, SUBSCRIPTION):
        (snap / name).unlink(missing_ok=True)


def migrate(run):
    run = Path(run)
    legacy = run / URL
    if (run / LIST).is_file() or not legacy.is_file():
        return
    check_url(legacy)
    url = legacy.read_text(encoding="utf-8").strip("\r\n")
    subslist.save(run, 2, [("S1", True, url)])
    legacy.unlink()


def _checked_url(run, raw):
    dest = Path(run) / (URL + ".chk")
    try:
        atomic_write(dest, raw + "\n")
        check_url(dest)
        return dest.read_text(encoding="utf-8").strip("\r\n")
    finally:
        dest.unlink(missing_ok=True)


def _refresh_locked(run, url=None):
    import subprocess

    from axs.config import CONFIG_NEW, OVERRIDE, RULES, SECRET, ensure_override, read_ports
    from axs.core import gen_secret, service_up
    from axs.mihomo import reload_core

    runp = Path(run)
    migrate(runp)
    if url is None:
        _nxt, rows = subslist.load(runp)
        chosen = [row for row in rows if row[1]]
        if len(chosen) != 1:
            die(FAIL, "没有订阅")
        url = chosen[0][2]
    staged = runp / (URL + ".tmp")
    try:
        atomic_write(staged, url + "\n")
        check_url(staged)
        body, hdr = str(runp / FETCH_BODY), str(runp / FETCH_HEADER)
        helper = os.environ.get("AXS_FETCH")
        if helper:
            if subprocess.run([helper, str(staged), body, hdr]).returncode != 0:
                die(FAIL, "拉取失败")
        else:
            try:
                fetch(str(staged), body, hdr)
            except SystemExit:
                die(FAIL, "拉取失败")
        check_fetched(body, hdr)
        ensure_override(run)
        gen_secret(runp / SECRET)
        _mixed, api = read_ports(run)
        snapshot(runp)
        try:
            build_file(body, runp / OVERRIDE, runp / SECRET, runp / RULES, runp / CONFIG_NEW)
        except SystemExit:
            restore_snapshot(runp)
            die(FAIL, "校验失败")
        install_file(runp / CONFIG_NEW, runp / CONFIG)
        if Path(body) != runp / SUBSCRIPTION:
            install_file(body, runp / SUBSCRIPTION)
        if service_up(run):
            try:
                reload_core(runp / SECRET, api, runp / CONFIG)
            except SystemExit:
                restore_snapshot(runp)
                die(FAIL, "重载失败")
        write_userinfo(hdr, runp / USERINFO)
        clear_fetch(run)
    finally:
        staged.unlink(missing_ok=True)


def refresh_run(run, url=None):
    hold_lock(run)
    _refresh_locked(run, url)


def _locked(run):
    hold_lock(run)
    migrate(run)
    return subslist.load(run)


def cmd_add(run, args):
    nxt, rows = _locked(run)
    subslist.save(run, *subslist.added(nxt, rows, _checked_url(run, args[0])))


def cmd_rm(run, args):
    nxt, rows = _locked(run)
    subslist.save(run, *subslist.removed(nxt, rows, args[0]))


def _read(run):
    runp = Path(run)
    if not (runp / LIST).is_file() and (runp / URL).is_file():
        hold_lock(run)
    migrate(runp)
    return subslist.load(runp)


def cmd_show(run):
    _nxt, rows = _read(run)
    for sid, active, url in rows:
        sys.stdout.write(sid + (" * " if active else " - ") + subslist.host_of(url) + "\n")


def cmd_status(run):
    _nxt, rows = _read(run)
    chosen = [row for row in rows if row[1]]
    prefix = ""
    if len(chosen) == 1:
        prefix = chosen[0][0] + " · " + subslist.host_of(chosen[0][2]) + " · "
    text, _kind = subscription_line(Path(run) / USERINFO, unix_now())
    sys.stdout.write(prefix + text + "\n")


def cmd_switch(run, args):
    nxt, rows = _locked(run)
    row = subslist.find(rows, args[0])
    _refresh_locked(run, row[2])
    subslist.save(run, nxt, subslist.activated(rows, row[0]))


def dispatch(run, op, extra):
    if op == "status":
        cmd_status(run)
    elif op == "show":
        cmd_show(run)
    elif op == "refresh":
        refresh_run(run)
    elif op == "add":
        cmd_add(run, extra)
    elif op == "rm":
        cmd_rm(run, extra)
    elif op == "switch":
        cmd_switch(run, extra)
    else:
        die(USAGE, "用法错误")
