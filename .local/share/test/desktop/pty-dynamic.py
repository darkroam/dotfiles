#!/usr/bin/env python3
"""Real PTY test for btmenu --dynamic.

Fake bluetoothctl, real fzf and real timeout. Without timeout --foreground,
fzf is not the terminal's foreground job, stops on SIGTTIN, and Esc never
arrives. Answers the cursor-position query so a raw PTY can drive fzf.
"""

import fcntl
import os
import pty
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

BTMENU = os.path.join(os.path.expanduser("~"), ".local", "bin", "btmenu")
MAC = "AA:BB:CC:DD:EE:01"
QUERIES = (
    (b"\x1b[6n", b"\x1b[1;1R", "cpr"),
    (b"\x1b[?2004$p", b"\x1b[?2004;2$y", "paste"),
)
BTCTL = """#!/bin/sh
printf '%s\\n' "$*" >> "$BT_LOG"
props=${BT_LOG}.props
[ -f "$props" ] || printf 'Paired: no\\nTrusted: no\\nConnected: no\\n' > "$props"
set_prop() {
	awk -v k="$1" -v v="$2" '
		$1 == k { print k " " v; seen = 1; next }
		{ print }
		END { if (!seen) print k " " v }
	' "$props" > "$props.new" && mv "$props.new" "$props"
}
while [ $# -gt 0 ]; do
	case $1 in
		--timeout|--agent) shift 2 ;;
		*) break ;;
	esac
done
if [ $# -eq 0 ]; then
	printf 'Agent registered\\n'
	while IFS= read -r line; do
		printf '%s\\n' "$line" >> "$BT_LOG"
		case $line in
			"pair "*) set_prop Paired: yes ;;
		esac
	done
	exit 0
fi
case ${1:-} in
	list) printf 'Controller 00:00:00:00:00:01 Test\\n' ;;
	show) printf '\\tPowered: yes\\n' ;;
	devices) printf 'Device AA:BB:CC:DD:EE:01 Headset\\n' ;;
	info) cat "$props" ;;
	trust) set_prop Trusted: yes ;;
	connect) set_prop Connected: yes ;;
	scan)
		if [ -t 0 ]; then
			printf 'scan-stdin-tty\\n' >> "$BT_LOG"
		fi
		;;
esac
exit 0
"""



def fzf_state(pid):
    try:
        out = subprocess.check_output(
            ["ps", "-o", "stat=,cmd=", "-s", str(pid)],
            text=True,
            errors="replace",
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        stat, cmd = parts
        base = os.path.basename(cmd.split()[0])
        if base == "fzf":
            return stat + " " + cmd
    return ""


def answer(fd, buf, done):
    for needle, reply, key in QUERIES:
        if key not in done and needle in buf:
            os.write(fd, reply)
            done.add(key)


def kill_session(pid):
    subprocess.run(
        ["pkill", "-KILL", "-s", str(pid)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def wait_exit(pid, fd, seconds):
    end = time.time() + seconds
    while time.time() < end:
        wid, status = os.waitpid(pid, os.WNOHANG)
        if wid == pid:
            return status
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                os.read(fd, 8192)
            except OSError:
                pass
    return None


def snippet(buf):
    text = buf.decode("utf-8", "replace")
    keep = []
    for ch in text:
        if ch.isprintable() or ch == "\n":
            keep.append(ch)
    return "".join(keep)[-240:]


def case(mode):
    work = tempfile.mkdtemp(prefix="btmenu-pty-")
    pid = None
    fd = None
    try:
        bindir = os.path.join(work, "bin")
        rundir = os.path.join(work, "run")
        os.makedirs(bindir)
        os.makedirs(rundir, mode=0o700)
        log = os.path.join(work, "bt.log")
        open(log, "w").close()
        btctl = os.path.join(bindir, "bluetoothctl")
        with open(btctl, "w", encoding="utf-8") as handle:
            handle.write(BTCTL)
        os.chmod(btctl, 0o755)
        for name in ("notify-send", "pkill"):
            path = os.path.join(bindir, name)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("#!/bin/sh\nexit 0\n")
            os.chmod(path, 0o755)
        env = os.environ.copy()
        for key in (
            "FZF_DEFAULT_OPTS",
            "FZF_DEFAULT_COMMAND",
            "FZF_API_KEY",
            "FZF_DEFAULT_OPTS_FILE",
        ):
            env.pop(key, None)
        env["BT_LOG"] = log
        env["XDG_RUNTIME_DIR"] = rundir
        env["TERM"] = "xterm-256color"
        env["STATUSBAR"] = "btmenu-test"
        env["PATH"] = os.pathsep.join(
            [bindir, os.path.dirname(BTMENU), env.get("PATH", "/usr/bin")]
        )
        pid, fd = pty.fork()
        if pid == 0:
            os.execvpe(BTMENU, [BTMENU, "--dynamic"], env)
            os._exit(127)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        buf = b""
        answered = set()
        sent = False
        deadline = time.time() + 4
        while time.time() < deadline:
            state = fzf_state(pid)
            if state.startswith("T"):
                kill_session(pid)
                pid = None
                return "fzf stopped (%s); list=%s" % (
                    state,
                    "yes" if b"Headset" in buf else "no",
                )
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    buf += os.read(fd, 8192)
                except OSError:
                    pass
            answer(fd, buf, answered)
            if not sent and b"Headset" in buf and "cpr" in answered:
                os.write(fd, b"\x1b" if mode == "esc" else b"\r")
                sent = True
                break
            wid, _ = os.waitpid(pid, os.WNOHANG)
            if wid == pid:
                pid = None
                return "exited before a choice (%s)" % snippet(buf)
        if not sent:
            state = fzf_state(pid)
            kill_session(pid)
            pid = None
            return "list not visible (%s) %s" % (state or "no fzf", snippet(buf))
        status = wait_exit(pid, fd, 8)
        if status is None:
            state = fzf_state(pid)
            kill_session(pid)
            pid = None
            return "key did not exit (%s)" % (state or "gone")
        pid = None
        with open(log, encoding="utf-8", errors="replace") as handle:
            logged = handle.read()
        if "scan-stdin-tty" in logged:
            return "scan stole the tty"
        if "scan on" not in logged:
            return "scan did not start"
        paired = "pair " + MAC in logged
        if mode == "esc":
            if paired:
                return "esc still paired"
            if os.waitstatus_to_exitcode(status) != 0:
                return "esc status %s" % status
            print("pty esc captured: Headset")
            return None
        if not paired:
            return "enter did not pair (%s)" % snippet(logged.encode())
        if os.waitstatus_to_exitcode(status) != 0:
            return "enter status %s" % status
        print("pty enter captured: Headset")
        return None
    finally:
        if pid:
            kill_session(pid)
        if fd is not None:
            os.close(fd)
        shutil.rmtree(work, ignore_errors=True)


def main():
    failed = False
    for mode in ("esc", "enter"):
        msg = case(mode)
        if msg:
            failed = True
            print("FAIL pty %s: %s" % (mode, msg), file=sys.stderr)
        else:
            print("ok pty %s" % mode)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
