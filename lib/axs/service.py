"""Service lifecycle, status, and the command bodies that used to live in shell."""

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

from axs.config import CONFIG, PID, SECRET, URL, USERINFO, mihomo_path, read_ports, status_ports
from axs.core import (
    active,
    alive,
    format_span,
    gen_secret,
    manual_etime,
    next_refresh,
    prime,
    read_pid,
    run_systemctl,
    service_up,
    systemd_etime,
    systemd_on,
    unix_now,
    write_cache,
)
from axs.mihomo import load_proxies, version_ok
from axs.net import port_open
from axs.nodes import follow_leaf, group_numbers, load_delays, node_numbers, paint_cell
from axs.proxy import status_summary
from axs.render import bad, bold, die, dim, display_width, emph, label, layout_cells, ok, term_cols
from axs.routes import build
from axs.rulelist import status_text
from axs.subscription import classify, clean_names, refresh_run, status_sub

def run_dir():
    chosen = os.environ.get("AXS_RUN")
    if chosen:
        return chosen
    return str(Path(__file__).resolve().parents[2] / "run")

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

def captured(func, *args):
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            func(*args)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
        return code, buf.getvalue()
    return 0, buf.getvalue()

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


def terminal_text(proxies, data, run):
    gnums, nnums = group_numbers(proxies), node_numbers(proxies)
    delays, blocks = load_delays(run), []
    for name in data["terminals"]:
        item = proxies.get(name) or {}
        kind = str(item.get("type") or "")
        members = item.get("all") if isinstance(item.get("all"), list) else []
        now = item.get("now") if isinstance(item.get("now"), str) else ""
        leaf = "" if kind == "LoadBalance" else (follow_leaf(proxies, now) or "")
        current = f"N{nnums[leaf]} {leaf}" if leaf in nnums else "-"
        head_line = f"G{gnums[name]} {name} [{kind}] → {current} · {len(members)} 个成员"
        shown = []
        for member in members:
            if member not in nnums:
                continue
            delay = delays.get(member, "-")
            shown.append((member, "-" if delay in (None, "") else str(delay)))
        width = len(f"N{max((nnums[member] for member, _delay in shown), default=1)}")
        wide = max((display_width(delay) for _member, delay in shown), default=1)
        entries = []
        for member, delay in shown:
            marker = "[*] " if member == leaf else "    "
            num_text = f"{'N' + str(nnums[member]):>{width}}"
            delay_text = f"{delay:>{wide}}"
            plain = f"{marker}{num_text} {member} {delay_text}"
            entries.append((plain, paint_cell(marker, num_text, member, delay_text, member == leaf, delay)))
        blocks.append("\n".join([head_line, *layout_cells(entries, term_cols())]))
    return ("\n\n".join(blocks) + "\n") if blocks else ""


def show_rule_nodes(run, secret, api):
    try:
        proxies = load_proxies(secret, api)
    except SystemExit as exc:
        code = exc.code if isinstance(exc.code, int) else USAGE
        raise SystemExit(FAIL if code == USAGE else code)
    data = build(proxies, run)
    if data is None:
        die(DOWN, "服务：未运行")
    path, tail = status_text(data), terminal_text(proxies, data, run)
    sys.stdout.write(path + ("\n" + tail if path and tail else tail))


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
    row("路径    ", lines[0] if lines else dim("-"))
    for line in lines[1:]:
        row("        ", line)


def status(run):
    running, port_ok, api_ok, api, mixed = service_section(run)
    head("节点")
    write_node_status(run, api if port_ok and api_ok else "")
    code, block = captured(status_sub, Path(run) / USERINFO, unix_now())
    lines = block.splitlines()
    if code or len(lines) < 2:
        sub_value, kind = dim("未知"), "unknown"
    else:
        sub_value, kind = lines[0], lines[-1]
    head("订阅")
    row("剩余    ", sub_value)
    head("测试")
    row("net     ", cache_value(run, "net-test"))
    row("node    ", cache_value(run, "node-test"))
    status_summary(run, mixed)
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
        if not (Path(run) / URL).is_file():
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
