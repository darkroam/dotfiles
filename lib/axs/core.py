"""Lock, atomic install, snapshot, and the systemd-mode cache."""
import fcntl
import os
import shutil
import sys
from pathlib import Path

from axs.config import CONFIG, LOCK, SNAP, SNAP_NAMES


class LockBusy(Exception):
    pass


def atomic_write(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, text.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, path)
    os.chmod(path, 0o600)


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
    raise SystemExit(1)


def gen_secret(path):
    path = Path(path)
    if path.is_file() and len(path.read_text(encoding="utf-8").strip()) >= 8:
        os.chmod(path, 0o600)
        return
    import secrets

    atomic_write(path, secrets.token_hex(16) + "\n")
