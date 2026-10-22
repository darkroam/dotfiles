#!/usr/bin/env python3
"""Port reads, install, snapshot, lock, and the systemd cache."""
import contextlib
import io
import os
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

import merge  # noqa: E402
from axs.config import (  # noqa: E402
    DEFAULT_API,
    DEFAULT_DNS_LISTEN,
    DEFAULT_MIXED,
    api_address,
    proxy_mixed,
    read_ports,
    status_ports,
)
from axs.config import LOCK  # noqa: E402
from axs.core import (  # noqa: E402
    LockBusy,
    SystemdCache,
    atomic_write,
    install_file,
    lock,
    restore_snapshot,
    snapshot,
)


def mode(path):
    return oct(path.stat().st_mode)[-3:]


def check_ports(tmp):
    run = Path(tmp)
    run.mkdir(parents=True)
    mixed, api = status_ports(run, {})
    if (mixed, api) != (str(DEFAULT_MIXED), DEFAULT_API):
        raise SystemExit(f"fallback {mixed} {api}")
    if api_address(run, {}) is not None:
        raise SystemExit("api should be missing")
    mixed, api = read_ports(run, {})
    if (mixed, api) != (str(DEFAULT_MIXED), DEFAULT_API):
        raise SystemExit(f"created {mixed} {api}")
    if proxy_mixed(run, {}) != str(DEFAULT_MIXED):
        raise SystemExit("proxy mixed")
    text = (run / "override.yaml").read_text(encoding="utf-8")
    if DEFAULT_DNS_LISTEN not in text:
        raise SystemExit("dns default missing")
    if status_ports(run, {"AXS_MIXED_PORT": "18080", "AXS_API": "127.0.0.1:18081"}) != (
        "18080",
        "127.0.0.1:18081",
    ):
        raise SystemExit("status env did not win")
    if read_ports(run, {"AXS_MIXED_PORT": "18080", "AXS_API": "127.0.0.1:18081"}) != (
        str(DEFAULT_MIXED),
        DEFAULT_API,
    ):
        raise SystemExit("existing override was rewritten")
    if api_address(run, {}) != DEFAULT_API:
        raise SystemExit("api from file")
    if api_address(run, {"AXS_API": "127.0.0.1:18081"}) != "127.0.0.1:18081":
        raise SystemExit("api env")
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err):
            merge.write_defaults(run / "bad.yaml", 1, "10.0.0.1:1")
    except SystemExit as exc:
        if exc.code != 1 or "回环" not in err.getvalue():
            raise SystemExit(f"loopback code {exc.code}") from exc
    else:
        raise SystemExit("non-loopback accepted")


def check_install(tmp):
    base = Path(tmp)
    base.mkdir(parents=True)
    src_dir = base / "src"
    run = base / "run"
    src_dir.mkdir()
    run.mkdir()
    src = src_dir / "config.yaml"
    dest = run / "config.yaml"
    dest.write_text("old\n", encoding="utf-8")
    src.write_text("new\n", encoding="utf-8")
    install_file(src, dest)
    if dest.read_text(encoding="utf-8") != "new\n":
        raise SystemExit("install missed")
    if (run / "config.yaml.bak").read_text(encoding="utf-8") != "old\n":
        raise SystemExit("bak missed")
    if mode(dest) != "600" or mode(run / "config.yaml.bak") != "600":
        raise SystemExit("install mode")
    if (run / "config.yaml.tmp").exists():
        raise SystemExit("tmp left behind")
    same = run / "next.yaml"
    same.write_text("same\n", encoding="utf-8")
    install_file(same, dest)
    if dest.read_text(encoding="utf-8") != "same\n" or same.exists():
        raise SystemExit("same-dir move")
    if (run / "config.yaml.bak").read_text(encoding="utf-8") != "new\n":
        raise SystemExit("same-dir bak was not the previous file")
    fresh_src = src_dir / "fresh.yaml"
    fresh_src.write_text("only\n", encoding="utf-8")
    fresh = run / "fresh.yaml"
    install_file(fresh_src, fresh)
    if fresh.read_text(encoding="utf-8") != "only\n" or (run / "fresh.yaml.bak").exists():
        raise SystemExit("missing dest created a bak")
    if mode(fresh) != "600":
        raise SystemExit("fresh mode")
    os.chmod(run, 0o755)
    atomic_write(run / "secret", "abc\n")
    if (run / "secret").read_text(encoding="utf-8") != "abc\n":
        raise SystemExit("atomic body")
    if mode(run / "secret") != "600" or mode(run) != "700":
        raise SystemExit("atomic mode")
    if (run / "secret.tmp").exists():
        raise SystemExit("atomic tmp left")


def check_snapshot(tmp):
    run = Path(tmp)
    run.mkdir(parents=True)
    (run / "config.yaml").write_text("c\n", encoding="utf-8")
    os.chmod(run / "config.yaml", 0o640)
    (run / "subscription.yaml").write_text("s\n", encoding="utf-8")
    (run / "rules.list").write_text("r\n", encoding="utf-8")
    (run / ".snap").mkdir()
    (run / ".snap" / "rules.list").write_text("stale\n", encoding="utf-8")
    snapshot(run)
    (run / "rules.list").unlink()
    snapshot(run)
    if (run / ".snap" / "rules.list").exists():
        raise SystemExit("stale snap remained")
    if mode(run / ".snap" / "config.yaml") != "640":
        raise SystemExit("snap changed mode")
    (run / "config.yaml").write_text("dirty\n", encoding="utf-8")
    (run / "config.yaml.bak").write_text("keep\n", encoding="utf-8")
    (run / "subscription.yaml").unlink()
    restore_snapshot(run)
    if (run / "config.yaml").read_text(encoding="utf-8") != "c\n":
        raise SystemExit("config not restored")
    if (run / "subscription.yaml").read_text(encoding="utf-8") != "s\n":
        raise SystemExit("sub not restored")
    if (run / "rules.list").exists():
        raise SystemExit("missing snap did not delete rules")
    if (run / "config.yaml.bak").read_text(encoding="utf-8") != "c\n":
        raise SystemExit("bak contract")
    if mode(run / "config.yaml") != "600" or mode(run / "config.yaml.bak") != "600":
        raise SystemExit("restore mode")
    if mode(run / ".snap") != "700":
        raise SystemExit("snap dir mode")
    (run / "notes").write_text("keep\n", encoding="utf-8")
    (run / ".snap" / "config.yaml").unlink()
    restore_snapshot(run)
    if (run / "config.yaml").exists():
        raise SystemExit("absent snap config left the live file")
    if (run / "config.yaml.bak").read_text(encoding="utf-8") != "c\n":
        raise SystemExit("absent snap config rewrote bak")
    if (run / "notes").read_text(encoding="utf-8") != "keep\n":
        raise SystemExit("restore removed an unrelated file")


def check_lock(tmp):
    run = Path(tmp)
    held = threading.Event()
    release = threading.Event()
    errors = []

    def holder():
        handle = lock(run)
        held.set()
        if not release.wait(2):
            errors.append("holder timed out")
        handle.close()

    thread = threading.Thread(target=holder)
    thread.start()
    if not held.wait(2):
        raise SystemExit("holder did not lock")
    try:
        lock(run)
    except LockBusy as exc:
        if str(exc) != "锁被占用":
            raise SystemExit(f"lock text {exc}") from exc
    else:
        raise SystemExit("lock was not exclusive")
    release.set()
    thread.join(2)
    if thread.is_alive() or errors:
        raise SystemExit("holder stuck")
    again = lock(run)
    again.close()
    if not (run / LOCK).is_file() or mode(run) != "700":
        raise SystemExit("lock path or run mode")


def check_systemd():
    calls = {"n": 0}

    def show():
        calls["n"] += 1
        return "loaded\n"

    if SystemdCache().get({"AXS_SYSTEMD": "0"}, show) != "0" or calls["n"] != 0:
        raise SystemExit("forced mode queried systemd")
    cache = SystemdCache()
    if cache.get({}, show) != "1" or cache.get({}, show) != "1" or calls["n"] != 1:
        raise SystemExit("systemd cache recomputed")
    if SystemdCache().get({}, lambda: "not-loaded") != "0":
        raise SystemExit("unloaded")
    calls["n"] = 0
    if SystemdCache().get({"AXS_SYSTEMD": "1"}, show) != "1" or calls["n"] != 0:
        raise SystemExit("forced on queried systemd")
    env = {"AXS_SYSTEMD": "2"}
    if SystemdCache().get(env, lambda: " loaded \n") != "1" or "AXS_SYSTEMD_MODE" in env:
        raise SystemExit("whitespace or env write")
    if SystemdCache().get({}, lambda: (_ for _ in ()).throw(OSError("down"))) != "0":
        raise SystemExit("show failure")
    other = SystemdCache()
    if other.mode is not None or other.get({}, lambda: "loaded") != "1":
        raise SystemExit("caches are not independent")


def main():
    with tempfile.TemporaryDirectory(prefix="axs-core-") as tmp:
        check_ports(Path(tmp) / "ports")
        check_install(Path(tmp) / "install")
        check_snapshot(Path(tmp) / "snap")
        check_lock(Path(tmp) / "lock")
    check_systemd()
    print("core primitives")
    return 0


if __name__ == "__main__":
    sys.exit(main())
