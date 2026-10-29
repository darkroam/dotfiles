"""Start, stop, ensure, health, and clean. Status pages live in status.py."""

from axs.codes import USAGE, DOWN, FAIL, EXPIRED
import contextlib
import io
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

from axs.config import CONFIG, PID, SECRET, USERINFO, mihomo_path, read_ports, status_ports
from axs.core import (
    active,
    alive,
    gen_secret,
    read_pid,
    run_systemctl,
    service_up,
    systemd_on,
    unix_now,
)
from axs.mihomo import version_ok
from axs.net import port_open
from axs.render import bad, bold, die, dim, label, ok
from axs.subslist import has_source
from axs.subscription import classify, clean_names, refresh_run

def run_dir():
    chosen = os.environ.get("AXS_RUN")
    if chosen:
        return chosen
    return str(Path(__file__).resolve().parents[1] / "run")

def controller_ok(run, api):
    secret = Path(run) / SECRET
    if not secret.is_file():
        return False
    sink = io.StringIO()
    try:
        with contextlib.redirect_stderr(sink):
            version_ok(secret, api)
    except SystemExit:
        return False
    return True














def plain(code, text):
    sys.stderr.write(text + "\n")
    raise SystemExit(code)

def health(run):
    if systemd_on():
        if not active():
            plain(DOWN, "未运行")
    elif not service_up(run, quiet=True):
        plain(DOWN, "未运行")
    mixed, api = status_ports(run)
    if not port_open(mixed):
        plain(DOWN, "端口不通")
    if not controller_ok(run, api):
        plain(FAIL, "控制器不通")
    try:
        kind, _days = classify(Path(run) / USERINFO, unix_now())
    except (OSError, ValueError):
        kind = ""
    if kind == "expired":
        plain(EXPIRED, "订阅过期")

def launch(run):
    argv = [mihomo_path(), "-d", str(run)]
    if shutil.which("setsid"):
        argv.insert(0, "setsid")
    proc = subprocess.Popen(
        argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    (Path(run) / PID).write_text(f"{proc.pid}\n", encoding="utf-8")

def start(run):
    if systemd_on():
        if active():
            return
        if run_systemctl(["start", "axs.service"]).returncode != 0:
            die(FAIL, "启动失败")
        return
    if service_up(run):
        return
    mixed, _api = read_ports(run)
    if port_open(mixed):
        die(DOWN, "端口已被占用")
    if not (Path(run) / CONFIG).is_file():
        die(FAIL, "没有配置")
    gen_secret(Path(run) / SECRET)
    launch(run)
    time.sleep(0.1)
    if not service_up(run):
        die(FAIL, "启动失败")

def stop(run):
    if systemd_on():
        if run_systemctl(["stop", "axs.service"]).returncode != 0:
            die(FAIL, "停止失败")
        return
    pidfile = Path(run) / PID
    if not service_up(run):
        pidfile.unlink(missing_ok=True)
        return
    pid = int(read_pid(run))
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
    for _ in range(20):
        if not alive(pid):
            break
        time.sleep(0.05)
    if alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    pidfile.unlink(missing_ok=True)

def restart(run):
    if systemd_on():
        if run_systemctl(["restart", "axs.service"]).returncode != 0:
            die(FAIL, "启动失败")
        return
    stop(run)
    start(run)

def ensure(run, args):
    if args:
        die(USAGE, "用法错误")
    manual = not systemd_on()
    if not manual and active():
        return
    if manual and service_up(run):
        return
    mixed, _api = read_ports(run)
    if port_open(mixed):
        die(DOWN, "端口已被占用")
    if not (Path(run) / CONFIG).is_file():
        if not has_source(run):
            die(FAIL, "没有订阅")
        refresh_run(run)
    if manual:
        start(run)
        return
    if run_systemctl(["start", "axs.service"]).returncode != 0:
        die(FAIL, "启动失败")

def boot(run, op):
    del run
    if not systemd_on():
        die(FAIL, "没有 systemd")
    if run_systemctl([op, "axs.service", "axs-refresh.timer"]).returncode != 0:
        die(FAIL, "自启失败")
    word = ok("enabled") if op == "enable" else bad("disabled")
    sys.stdout.write(label("开机自启：") + word + "\n")

def _prompt():
    previous = os.environ.get("AXS_PAINT_FD")
    os.environ["AXS_PAINT_FD"] = "2"
    try:
        text = bold("确认删除？[y/N] ")
    finally:
        if previous is None:
            os.environ.pop("AXS_PAINT_FD", None)
        else:
            os.environ["AXS_PAINT_FD"] = previous
    sys.stderr.write(text)
    sys.stderr.flush()

def clean(run, kind, args):
    if len(args) > 1:
        die(USAGE, "用法错误")
    yes = False
    if args:
        if args[0] != "--yes":
            die(USAGE, "用法错误")
        yes = True
    if service_up(run):
        die(DOWN, "服务在运行，先 axs service stop")
    root = os.path.realpath(run) if Path(run).is_dir() else ""
    paths = []
    for name in clean_names(kind):
        if "/" in name or ".." in name:
            die(FAIL, "路径越界")
        path = Path(run) / name
        if not (path.is_symlink() or path.exists()):
            continue
        resolved = os.path.realpath(path)
        if root and not resolved.startswith(root + os.sep):
            die(FAIL, "路径越界")
        paths.append(path)
    if not yes:
        if paths:
            shown = "".join(f"{path}\n" for path in paths)
            sys.stdout.write(dim(shown).rstrip("\n"))
        if not sys.stdin.isatty():
            die(USAGE, "需要 --yes")
        _prompt()
        answer = sys.stdin.readline()
        if answer.endswith("\n"):
            answer = answer[:-1]
        if answer not in ("y", "Y", "yes", "YES"):
            die(USAGE, "需要 --yes")
    deleted = False
    for path in paths:
        if path.is_symlink() or path.exists():
            try:
                path.unlink()
            except OSError:
                die(FAIL, "删除失败")
            deleted = True
    if deleted:
        sys.stdout.write(ok("已删除") + "\n")
