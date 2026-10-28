"""Lock, process check, atomic install, snapshot, and the systemd-mode cache."""
from axs.codes import USAGE
import fcntl
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from axs.config import CONFIG, LOCK, PID, SNAP, SNAP_NAMES, atomic_write, mihomo_path, write_override


class LockBusy(Exception):
    pass


def install_file(src, dest):
    src, dest = Path(src), Path(dest)
    if dest.is_file():
        bak = Path(str(dest) + ".bak")
        shutil.copy2(dest, bak)
        os.chmod(bak, 0o600)
    if src.parent == dest.parent:
        os.replace(src, dest)
    else:
        tmp = Path(str(dest) + ".tmp")
        shutil.copy2(src, tmp)
        os.chmod(tmp, 0o600)
        os.replace(tmp, dest)
    os.chmod(dest, 0o600)


def snapshot(run):
    run = Path(run)
    snap = run / SNAP
    snap.mkdir(parents=True, exist_ok=True)
    os.chmod(snap, 0o700)
    for name in SNAP_NAMES:
        src = run / name
        dest = snap / name
        if src.is_file():
            shutil.copy2(src, dest)
        else:
            dest.unlink(missing_ok=True)


def restore_snapshot(run):
    run = Path(run)
    snap = run / SNAP
    for name in SNAP_NAMES:
        src = snap / name
        dest = run / name
        if src.is_file():
            shutil.copy2(src, dest)
            os.chmod(dest, 0o600)
        else:
            dest.unlink(missing_ok=True)
    saved = snap / CONFIG
    if saved.is_file():
        bak = run / (CONFIG + ".bak")
        shutil.copy2(saved, bak)
        os.chmod(bak, 0o600)


def lock(run):
    from axs.config import ensure_run

    path = ensure_run(run) / LOCK
    handle = open(path, "a+")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        raise LockBusy("锁被占用")
    return handle


_HELD = []


def hold_lock(run):
    from axs.codes import LOCK as BUSY
    from axs.render import die

    try:
        _HELD.append(lock(run))
    except LockBusy as exc:
        die(BUSY, str(exc))


def read_pid(run):
    text = (Path(run) / PID).read_text(encoding="utf-8")
    while text.endswith("\n"):
        text = text[:-1]
    return text


def alive(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def service_up(run, quiet=False):
    pidfile = Path(run) / PID
    if not pidfile.is_file():
        return False
    pid = read_pid(run)
    if not pid.isdigit():
        if not quiet:
            sys.stderr.write("告警：mihomo.pid 不是数字\n")
        return False
    if not alive(int(pid)):
        return False
    path = Path(f"/proc/{pid}/cmdline")
    try:
        fields = path.read_bytes().split(b"\0")
    except OSError:
        return False
    return mihomo_path().encode() in fields


def detect_systemd(env, show):
    forced = env.get("AXS_SYSTEMD", "")
    if forced in ("0", "1"):
        return forced
    try:
        state = show() or ""
    except OSError:
        state = ""
    return "1" if "".join(state.split()) == "loaded" else "0"


class SystemdCache:
    def __init__(self):
        self.mode = None

    def get(self, env, show):
        if self.mode is None:
            self.mode = detect_systemd(env, show)
        return self.mode


def fail(message):
    sys.stderr.write(message + "\n")
    raise SystemExit(USAGE)


def write_defaults(path, mixed, api):
    try:
        write_override(path, mixed, api)
    except ValueError as exc:
        fail(str(exc))


def gen_secret(path):
    path = Path(path)
    if path.is_file() and len(path.read_text(encoding="utf-8").strip()) >= 8:
        os.chmod(path, 0o600)
        return
    import secrets

    atomic_write(path, secrets.token_hex(16) + "\n")


_MODE = SystemdCache()


def run_systemctl(args, capture=False, quiet=False):
    cmd = [os.environ.get("AXS_SYSTEMCTL") or "systemctl", "--user", *args]
    stdout = stderr = None
    if quiet:
        stdout = stderr = subprocess.DEVNULL
    elif capture:
        stdout = subprocess.PIPE
        stderr = subprocess.DEVNULL
    return subprocess.run(cmd, stdout=stdout, stderr=stderr, text=True)


def prime():
    def show():
        return run_systemctl(["show", "axs.service", "-p", "LoadState", "--value"], capture=True).stdout

    _MODE.get(os.environ, show)


def systemd_on():
    if _MODE.mode is None:
        prime()
    return _MODE.mode == "1"


def active():
    return run_systemctl(["is-active", "axs.service"], quiet=True).returncode == 0


def unix_now():
    proc = subprocess.run(["date", "+%s"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    stamp = proc.stdout.strip()
    return int(stamp) if stamp.isdigit() else 0


def clock(stamp):
    proc = subprocess.run(["date", "-d", str(stamp), "+%H:%M"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def format_span(secs, suffix):
    if secs < 60:
        return f"{secs} 秒{suffix}"
    if secs < 3600:
        return f"{secs // 60} 分钟{suffix}"
    if secs < 86400:
        return f"{secs // 3600} 小时{suffix}"
    return f"{secs // 86400} 天{suffix}"


def manual_etime(pid):
    proc = subprocess.run(["ps", "-o", "etimes=", "-p", str(pid)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    text = "".join(proc.stdout.split())
    if not text.isdigit():
        return "-"
    return format_span(int(text), "")


def systemd_etime():
    stamp = run_systemctl(["show", "axs.service", "-p", "ActiveEnterTimestamp", "--value"], capture=True).stdout.strip()
    if stamp in ("", "n/a", "N/A"):
        return "-"
    proc = subprocess.run(["date", "-d", stamp, "+%s"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    start = proc.stdout.strip()
    if not start.isdigit():
        return "-"
    return format_span(max(0, unix_now() - int(start)), "")


def _first_usec(raw, key):
    pattern = re.compile(rf'.*"{re.escape(key)}"\s*:\s*([0-9]+)')
    for line in raw.splitlines():
        found = pattern.search(line)
        if not found:
            continue
        if found.group(1) == "0":
            return None
        return int(found.group(1))
    return None


def next_refresh():
    raw = run_systemctl(["list-timers", "--output=json", "axs-refresh.timer"], capture=True).stdout
    nxt = _first_usec(raw, "next")
    left = _first_usec(raw, "left")
    if nxt is None or left is None:
        return "-"
    delta = max(0, (left // 1000000) - unix_now())
    hm = clock(f"@{(nxt // 1000000)}")
    if not hm:
        return "-"
    return f"下次 {hm}（{format_span(delta, '后')}）"


def write_cache(run, name, result):
    directory = Path(run) / "cache"
    directory.mkdir(parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    tmp = directory / f".{name}.{os.getpid()}"
    tmp.write_text(f"ts={unix_now()}\nresult={result}\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, directory / name)


def session_pid():
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
    pid = session_pid()
    path = Path(f"/proc/{pid}/environ") if pid else None
    if path is None or not path.is_file() or not os.access(path, os.R_OK):
        return 2, ""
    prefix = f"{key}=".encode()
    for item in path.read_bytes().split(b"\0"):
        if item.startswith(prefix):
            return 0, item[len(prefix):].decode("utf-8", "replace")
    return 1, ""
