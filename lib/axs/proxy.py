"""Three proxy layers. Status summary in the shell stays until service moves."""
import os
import shutil
import subprocess
import sys
from pathlib import Path

from axs.config import (
    LEGACY_SESSION_FLAG,
    LEGACY_SYSTEM_FLAG,
    SESSION_FLAG,
    SYSTEM_FLAG,
    proxy_mixed,
)
from axs.render import bad, dim, ok

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
        _quit(1, "用法")
    return args[0]


def _port(run):
    return proxy_mixed(run)


def _want(port):
    return f"http://127.0.0.1:{port}"


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
        _quit(3, "gsettings 失败")


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
        _quit(3, "没有 gsettings")


def proxy_user(run, args):
    sub = _need_one(args)
    port = _port(run)
    if sub == "on":
        sys.stderr.write('提示：需 eval "$(axs proxy user on)" 才会生效\n')
        for line in (
            f"export http_proxy={_want(port)}",
            f"export https_proxy={_want(port)}",
            f"export all_proxy=socks5://127.0.0.1:{port}",
            "export no_proxy=localhost,127.0.0.1,::1",
            f"export HTTP_PROXY={_want(port)}",
            f"export HTTPS_PROXY={_want(port)}",
            f"export ALL_PROXY=socks5://127.0.0.1:{port}",
            "export NO_PROXY=localhost,127.0.0.1,::1",
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
        _quit(1)
    _quit(1, "用法")


def proxy_system(run, args):
    sub = _need_one(args)
    flag = Path(run) / SYSTEM_FLAG
    profile = _xprofile()
    if sub in ("on", "off", "status"):
        _need_gsettings()
    if sub == "on":
        port = _port(run)
        _gs_set(GS, "mode", "manual")
        _gs_set(GS + ".http", "host", "127.0.0.1")
        _gs_set(GS + ".http", "port", port)
        _gs_set(GS + ".https", "host", "127.0.0.1")
        _gs_set(GS + ".https", "port", port)
        _gs_set(GS, "ignore-hosts", "['localhost','127.0.0.1','::1']")
        _line(f"system：{ok('on')}（127.0.0.1:{port}）")
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
        _quit(1, "用法")
    port = _port(run)
    mode = _gs_get(GS, "mode")
    host = _gs_get(GS + ".http", "host")
    sport = _gs_get(GS + ".http", "port")
    if mode == "manual" and host == "127.0.0.1" and sport == port:
        _line(f"system: {ok('on')} (mode={mode} host={host} port={sport})")
        code = 0
    else:
        _line(f"system: {dim('off')} (mode={mode} host={host} port={sport})")
        code = 1
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
        _quit(1, "用法")
    port = _port(run)
    if not flag.is_file():
        _line(f"session: persist {dim('disabled')} · effect {dim('-')}")
        _quit(1)
    if _hook_missing(profile, SESSION_HOOK):
        _line(f"session: persist {ok('enabled')} (xprofile hook missing)")
        _quit(1)
    rc, live = session_value("http_proxy")
    if rc == 2:
        _line(f"session: persist {ok('enabled')} · effect {dim('no-x-session')}")
        _quit(1)
    if rc == 0 and live == _want(port):
        _line(f"session: persist {ok('enabled')} · effect {ok('active')}")
        return
    _line(f"session: persist {ok('enabled')} · effect {dim('pending')}")
    _quit(1)
