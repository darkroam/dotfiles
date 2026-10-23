"""Three proxy layers."""

from axs.codes import USAGE, FAIL
import os
import shutil
import subprocess
import sys
from pathlib import Path

from axs.config import (
    BYPASS,
    LEGACY_SESSION_FLAG,
    LEGACY_SYSTEM_FLAG,
    LOOPBACK,
    SESSION_FLAG,
    SOCKS5,
    SYSTEM_FLAG,
    proxy_mixed,
)
from axs.render import bad, bold, dim, label, ok

GS = "org.gnome.system.proxy"
SYSTEM_HOOK = "axs proxy system identity (managed)"
SESSION_HOOK = "axs proxy session (managed)"


def _quit(code, message=None):
    if message:
        previous = os.environ.get("AXS_PAINT_FD")
        os.environ["AXS_PAINT_FD"] = "2"
        try:
            message = bad(message)
        finally:
            if previous is None:
                os.environ.pop("AXS_PAINT_FD", None)
            else:
                os.environ["AXS_PAINT_FD"] = previous
        sys.stderr.write(message + "\n")
    raise SystemExit(code)


def _line(text):
    sys.stdout.write(text + "\n")


def _need_one(args):
    if len(args) != 1:
        _quit(USAGE, "用法错误")
    return args[0]


def _port(run):
    return proxy_mixed(run)


def _want(port):
    return f"http://{LOOPBACK}:{port}"


def _socks(port):
    return f"{SOCKS5}{LOOPBACK}:{port}"


def _ignore_hosts():
    return "[" + ",".join("'" + host + "'" for host in BYPASS.split(",")) + "]"


def _user_current():
    for key in ("http_proxy", "HTTPS_PROXY", "https_proxy"):
        value = os.environ.get(key)
        if value:
            return value
    return ""


def _xprofile():
    chosen = os.environ.get("AXS_XPROFILE")
    if chosen:
        return chosen
    return str(Path(os.environ.get("HOME", "")) / ".config/x11/xprofile")


def _hook_missing(path, marker):
    file = Path(path)
    try:
        text = file.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return True
    return marker not in text


def _flag(run, name):
    path = Path(run) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.close(fd)
    os.chmod(path, 0o600)
    return path


def _unlink(path):
    Path(path).unlink(missing_ok=True)


def _session_pid():
    pid = os.environ.get("AXS_SESSION_PID", "")
    if pid:
        return pid
    try:
        result = subprocess.run(
            ["pgrep", "-x", "dwm"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError:
        return ""
    lines = [line for line in result.stdout.splitlines() if line]
    return lines[0] if lines else ""


def session_value(key):
    pid = _session_pid()
    path = Path(f"/proc/{pid}/environ") if pid else None
    if path is None or not path.is_file() or not os.access(path, os.R_OK):
        return 2, ""
    prefix = f"{key}=".encode()
    for item in path.read_bytes().split(b"\0"):
        if item.startswith(prefix):
            return 0, item[len(prefix) :].decode("utf-8", "replace")
    return 1, ""


def _gnome(value):
    return "GNOME" in value.split(":")


def _gs_set(schema, key, value):
    result = subprocess.run(["gsettings", "set", schema, key, value])
    if result.returncode != 0:
        _quit(FAIL, "gsettings 失败")


def _gs_get(schema, key):
    result = subprocess.run(
        ["gsettings", "get", schema, key],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    text = result.stdout.replace("'", "")
    return text[:-1] if text.endswith("\n") else text


def _need_gsettings():
    if shutil.which("gsettings") is None:
        _quit(FAIL, "没有 gsettings 命令")


def proxy_user(run, args):
    sub = _need_one(args)
    port = _port(run)
    if sub == "on":
        sys.stderr.write('提示：需 eval "$(axs proxy user on)" 才会生效\n')
        for line in (
            f"export http_proxy={_want(port)}",
            f"export https_proxy={_want(port)}",
            f"export all_proxy={_socks(port)}",
            f"export no_proxy={BYPASS}",
            f"export HTTP_PROXY={_want(port)}",
            f"export HTTPS_PROXY={_want(port)}",
            f"export ALL_PROXY={_socks(port)}",
            f"export NO_PROXY={BYPASS}",
        ):
            _line(line)
        return
    if sub == "off":
        _line("unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY")
        return
    if sub == "status":
        cur = _user_current()
        if cur == _want(port):
            _line(f"user: {ok('on')} ({cur})")
            return
        _line(f"user: {dim('off')} ({cur or 'unset'})")
        _quit(USAGE)
    _quit(USAGE, "用法错误")


def proxy_system(run, args):
    sub = _need_one(args)
    flag = Path(run) / SYSTEM_FLAG
    profile = _xprofile()
    if sub in ("on", "off", "status"):
        _need_gsettings()
    if sub == "on":
        port = _port(run)
        _gs_set(GS, "mode", "manual")
        _gs_set(GS + ".http", "host", LOOPBACK)
        _gs_set(GS + ".http", "port", port)
        _gs_set(GS + ".https", "host", LOOPBACK)
        _gs_set(GS + ".https", "port", port)
        _gs_set(GS, "ignore-hosts", _ignore_hosts())
        _line(f"system：{ok('on')}（{LOOPBACK}:{port}）")
        return
    if sub == "off":
        _gs_set(GS, "mode", "none")
        _line(f"system：{bad('off')}")
        return
    if sub == "enable":
        _flag(run, SYSTEM_FLAG)
        _unlink(Path(run) / LEGACY_SYSTEM_FLAG)
        _line(f"system：{ok('enabled')}（重登 X 后 libproxy/Edge 才会读取 gsettings）")
        return
    if sub == "disable":
        _unlink(flag)
        _line(f"system：{bad('disabled')}")
        return
    if sub != "status":
        _quit(USAGE, "用法错误")
    port = _port(run)
    mode = _gs_get(GS, "mode")
    host = _gs_get(GS + ".http", "host")
    sport = _gs_get(GS + ".http", "port")
    if mode == "manual" and host == LOOPBACK and sport == port:
        _line(f"system: {ok('on')} (mode={mode} host={host} port={sport})")
        code = 0
    else:
        _line(f"system: {dim('off')} (mode={mode} host={host} port={sport})")
        code = USAGE
    if flag.is_file() and _hook_missing(profile, SYSTEM_HOOK):
        _line(f"persist: {ok('enabled')} (xprofile hook missing)")
    elif flag.is_file():
        _line(f"persist: {ok('enabled')}")
    else:
        _line(f"persist: {dim('disabled')}")
    rc, desk = session_value("XDG_CURRENT_DESKTOP")
    if rc == 0 and _gnome(desk):
        _line(f"desktop: {ok('effective')}")
    elif rc == 2:
        _line(f"desktop: {dim('no x session')}")
    else:
        _line(f"desktop: {dim('pending')}")
    if code:
        _quit(code)


def proxy_session(run, args):
    sub = _need_one(args)
    flag = Path(run) / SESSION_FLAG
    profile = _xprofile()
    if sub == "enable":
        _flag(run, SESSION_FLAG)
        _unlink(Path(run) / LEGACY_SESSION_FLAG)
        _line(f"session：{ok('enabled')}（下次登录 X 生效）")
        return
    if sub == "disable":
        _unlink(flag)
        _line(f"session：{bad('disabled')}")
        return
    if sub != "status":
        _quit(USAGE, "用法错误")
    port = _port(run)
    if not flag.is_file():
        _line(f"session: persist {dim('disabled')} · effect {dim('-')}")
        _quit(USAGE)
    if _hook_missing(profile, SESSION_HOOK):
        _line(f"session: persist {ok('enabled')} (xprofile hook missing)")
        _quit(USAGE)
    rc, live = session_value("http_proxy")
    if rc == 2:
        _line(f"session: persist {ok('enabled')} · effect {dim('no-x-session')}")
        _quit(USAGE)
    if rc == 0 and live == _want(port):
        _line(f"session: persist {ok('enabled')} · effect {ok('active')}")
        return
    _line(f"session: persist {ok('enabled')} · effect {dim('pending')}")
    _quit(USAGE)


def _word(text):
    return ok(text) if text in ("on", "enabled", "active") else dim(text)


def _row(name, value):
    sys.stdout.write("  " + label(name) + value + "\n")


def status_summary(run, port):
    current = os.environ.get("http_proxy") or os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy") or ""
    user = "on" if current == _want(port) else "off"
    system = "off"
    if shutil.which("gsettings"):
        mode = _gs_get(GS, "mode")
        host = _gs_get(GS + ".http", "host")
        sport = _gs_get(GS + ".http", "port")
        if mode == "manual" and host == LOOPBACK and sport == str(port):
            system = "on"
    system_flag = "enabled" if (Path(run) / SYSTEM_FLAG).is_file() else "disabled"
    session_flag = "enabled" if (Path(run) / SESSION_FLAG).is_file() else "disabled"
    effect = "-"
    if session_flag == "enabled":
        effect = "pending"
        rc, live = session_value("http_proxy")
        if rc == 2:
            effect = "no-x-session"
        elif rc == 0 and live == _want(port):
            effect = "active"
    sys.stdout.write(bold("代理") + "\n")
    _row("user    ", _word(user))
    _row("system  ", f"{_word(system)}（persist {_word(system_flag)}）")
    _row("session ", f"{dim('persist')} {_word(session_flag)} · {dim('effect')} {_word(effect)}")
