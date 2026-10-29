#!/usr/bin/env python3
"""Kernel checks and socket audit for the lab stand-in."""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.request
from pathlib import Path

import yaml

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))
from axs.config import LOOPBACK  # noqa: E402


def ipv4_loopback(hexip):
    number = int.from_bytes(bytes.fromhex(hexip), "little")
    return (number >> 24) == 127


def ipv6_bytes(hexip):
    raw = bytearray(16)
    for index in range(4):
        word = bytes.fromhex(hexip[index * 8:(index + 1) * 8])
        raw[index * 4:(index + 1) * 4] = word[::-1]
    return bytes(raw)


def ipv6_loopback(hexip):
    raw = ipv6_bytes(hexip)
    if raw == b"\x00" * 15 + b"\x01":
        return True
    return raw[:12] == b"\x00" * 10 + b"\xff\xff" and raw[12] == 127


def dns_name(port):
    return f"{LOOPBACK}:{int(port)}"


def subscription(proxy_port, marker, dns_port):
    # hosts rewrites the name before rules, so a DOMAIN rule would never match.
    rules = []
    if marker:
        rules.append("DOMAIN,marker.test,DIRECT")
    rules.append("MATCH,DIRECT")
    upstream = dns_name(dns_port)
    data = {
        "mixed-port": 1,
        "mode": "global",
        "allow-lan": True,
        "ipv6": False,
        "external-controller": LOOPBACK + ":1",
        "secret": "from-sub",
        "geo-auto-update": False,
        "tun": {"enable": True},
        "dns": {
            "enable": False,
            "listen": LOOPBACK + ":1",
            "enhanced-mode": "redir-host",
            "ipv6": False,
            "nameserver": [upstream],
            "default-nameserver": [upstream],
        },
        "proxies": [
            {
                "name": "local",
                "type": "http",
                "server": LOOPBACK,
                "port": int(proxy_port),
            },
            {
                # Port 9 is an empty shell. switch must not dial it.
                "name": "spare",
                "type": "http",
                "server": LOOPBACK,
                "port": 9,
            },
        ],
        "proxy-groups": [{
            "name": "PROXY",
            "type": "select",
            "proxies": ["local", "spare"],
        }],
        "rules": rules,
    }
    return yaml.safe_dump(data, allow_unicode=True, sort_keys=False)


def kernel(standin):
    good = f"""\
mixed-port: 17897
allow-lan: false
mode: rule
log-level: error
external-controller: {LOOPBACK}:19097
secret: local-test-secret
geo-auto-update: false
tun:
  enable: false
dns:
  enable: false
proxies:
  - name: local
    type: http
    server: {LOOPBACK}
    port: 9
proxy-groups:
  - name: PROXY
    type: select
    proxies: [local]
rules:
  - MATCH,DIRECT
"""
    bad = good.replace("  - MATCH,DIRECT\n", "  - DOMAIN,missing.local,NOTAGROUP\n  - MATCH,DIRECT\n")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "good").mkdir()
        (root / "bad").mkdir()
        (root / "good" / "config.yaml").write_text(good, encoding="utf-8")
        (root / "bad" / "config.yaml").write_text(bad, encoding="utf-8")
        ok = subprocess.run([standin.mihomo_bin(), "-t", "-d", str(root / "good")], capture_output=True, text=True)
        no = subprocess.run([standin.mihomo_bin(), "-t", "-d", str(root / "bad")], capture_output=True, text=True)
    if ok.returncode != 0:
        sys.stderr.write("good config rejected\n")
        return 1
    text = no.stdout + no.stderr
    if no.returncode == 0 or "not found" not in text:
        sys.stderr.write("unknown group was not rejected\n")
        return 1
    for line in text.splitlines():
        if "not found" in line:
            message = line.split("msg=", 1)[-1].strip().strip('"')
            sys.stdout.write(message + "\n")
            break
    sys.stdout.write(f"kernel-exit {no.returncode}\n")
    return 0


def pair_check(var, standin):
    # shortcut: PermissionError means this process cannot send on a socket, skip; a normal session still runs the pair.
    left = right = None
    try:
        left, right = socket.socketpair()
        left.send(b"x")
    except PermissionError:
        return 0
    finally:
        if left is not None:
            left.close()
        if right is not None:
            right.close()

    def once(payload):
        left, right = socket.socketpair()
        box = {}

        def run():
            try:
                standin.handle_proxy(right, var)
                box["err"] = None
            except Exception as exc:
                box["err"] = exc

        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        left.settimeout(2)
        left.sendall(payload)
        data = b""
        try:
            while True:
                chunk = left.recv(4096)
                if not chunk:
                    break
                data += chunk
        except OSError:
            pass
        thread.join(timeout=2)
        left.close()
        return data, box.get("err"), thread.is_alive()

    data, err, alive = once(b"GET http://target.test:9/who HTTP/1.1\r\nHost: target.test:9\r\n\r\n")
    if err or alive or b"node" not in data:
        sys.stderr.write("proxy who\n")
        return 1
    data, err, alive = once(b"GET http://canary.invalid/ HTTP/1.1\r\nHost: canary.invalid\r\n\r\n")
    tripped = (var / "tripwire").read_text(encoding="utf-8")
    if err or alive or b"403" not in data or "canary.invalid" not in tripped:
        sys.stderr.write("proxy canary\n")
        return 1
    return 0


def merge_check(standin):
    sys.path.insert(0, str(ROOT))
    from axs.config import write_override
    from axs.core import gen_secret
    from axs.profile import build_file

    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        sub = folder / "sub.yaml"
        sub.write_text(subscription(9, False, 18095), encoding="utf-8")
        write_override(folder / "override.yaml", "18093", LOOPBACK + ":18094")
        gen_secret(folder / "secret")
        (folder / "rules.list").write_text("DOMAIN target.test PROXY\n", encoding="utf-8")
        build_file(
            sub,
            folder / "override.yaml",
            folder / "secret",
            folder / "rules.list",
            folder / "config.yaml",
        )
        proc = subprocess.run(
            [standin.mihomo_bin(), "-t", "-d", str(folder)],
            capture_output=True, text=True,
        )
        body = (folder / "config.yaml").read_text(encoding="utf-8")
    if proc.returncode != 0:
        sys.stderr.write("merged config rejected\n")
        return 1
    if "from-sub" in body or "canary.invalid" in body:
        sys.stderr.write("subscription secret kept\n")
        return 1
    if "hosts:" in body or "DOMAIN,target.test,PROXY" not in body or LOOPBACK + ":18095" not in body or "redir-host" not in body:
        sys.stderr.write("merged shape\n")
        return 1
    tops = [
        line.split(":", 1)[0]
        for line in body.splitlines()
        if line and not line[0].isspace() and not line.startswith("-")
    ]
    if tops != [
        "mixed-port", "mode", "allow-lan", "ipv6", "external-controller", "secret",
        "geo-auto-update", "tun", "dns", "proxies", "proxy-groups", "rules", "log-level",
    ]:
        sys.stderr.write("yaml key order\n")
        return 1
    return 0


def dns_check(var, standin):
    good = standin.answer_dns(standin.dns_query("target.test"), var)
    if good is None or bytes(int(part) for part in LOOPBACK.split(".")) not in good or (good[3] & 0x0F) != 0:
        sys.stderr.write("dns target\n")
        return 1
    bad = standin.answer_dns(standin.dns_query("canary.invalid"), var)
    if bad is None or (bad[3] & 0x0F) != 3 or bytes(int(part) for part in LOOPBACK.split(".")) in bad:
        sys.stderr.write("dns canary\n")
        return 1
    if "canary.invalid" not in (var / "tripwire").read_text(encoding="utf-8"):
        sys.stderr.write("dns tripwire\n")
        return 1
    other = standin.answer_dns(standin.dns_query("example.com"), var)
    tripped = (var / "tripwire").read_text(encoding="utf-8")
    if other is None or (other[3] & 0x0F) != 3 or "example.com" in tripped:
        sys.stderr.write("dns other\n")
        return 1
    return 0


def selfcheck(standin):
    var = Path(tempfile.mkdtemp())
    try:
        if not ipv4_loopback("0100007F") or ipv4_loopback("08080808"):
            sys.stderr.write("ipv4 parse\n")
            return 1
        if not ipv6_loopback("00000000000000000000000001000000"):
            sys.stderr.write("ipv6 parse\n")
            return 1
        if ipv6_loopback("00000000000000000000000008080808"):
            sys.stderr.write("ipv6 public accepted\n")
            return 1
        if not standin.allowed(var, "target.test") or standin.allowed(var, "canary.invalid"):
            sys.stderr.write("allow list\n")
            return 1
        if (var / "tripwire").read_text(encoding="utf-8").strip() != "canary.invalid":
            sys.stderr.write("tripwire\n")
            return 1
        text = subscription(9, True, 18095)
        if "canary.invalid" in text or "hosts:" in text or "marker.test" not in text:
            sys.stderr.write("subscription shape\n")
            return 1
        if LOOPBACK + ":18095" not in text or "redir-host" not in text:
            sys.stderr.write("subscription dns\n")
            return 1
        if "name: spare" not in text:
            sys.stderr.write("spare node\n")
            return 1
        if dns_check(var, standin):
            return 1
        if pair_check(var, standin):
            return 1
    finally:
        shutil.rmtree(var)
    return 0


def socket_inodes(pid):
    inodes = set()
    folder = Path(f"/proc/{pid}/fd")
    if not folder.is_dir():
        return None
    for entry in folder.iterdir():
        try:
            target = os.readlink(entry)
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            inodes.add(target[8:-1])
    return inodes


def audit(pid):
    inodes = socket_inodes(pid)
    if not inodes:
        sys.stderr.write("no sockets\n")
        return 1
    matched = False
    bad = []
    for name in ("tcp", "tcp6"):
        lines = Path(f"/proc/net/{name}").read_text(encoding="utf-8").splitlines()[1:]
        for line in lines:
            parts = line.split()
            if len(parts) < 10 or parts[9] not in inodes:
                continue
            matched = True
            remote = parts[2]
            hexip, hexport = remote.split(":")
            if int(hexport, 16) == 0:
                continue
            loop = ipv6_loopback(hexip) if name == "tcp6" else ipv4_loopback(hexip)
            if not loop:
                bad.append(name)
    if bad:
        sys.stderr.write("off-loop\n")
        return 1
    if not matched:
        sys.stderr.write("no tcp socket\n")
        return 1
    return 0


def reload_bad(run, api):
    run = Path(run)
    secret = (run / "secret").read_text(encoding="utf-8").strip()
    data = yaml.safe_load((run / "config.yaml").read_text(encoding="utf-8"))
    rules = list(data.get("rules") or [])
    rules.insert(0, "DOMAIN,missing.local,NOTAGROUP")
    data["rules"] = rules
    bad = run.parent / "bad-config.yaml"
    bad.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")
    os.chmod(bad, 0o600)
    body = json.dumps({"path": str(bad), "payload": ""}).encode()
    req = urllib.request.Request(
        f"http://{api}/configs?force=true",
        data=body,
        method="PUT",
        headers={"Authorization": "Bearer " + secret, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            sys.stdout.write(str(resp.status) + "\n")
    except urllib.error.HTTPError as exc:
        sys.stdout.write(str(exc.code) + "\n")
    return 0


def poke(port, var):
    try:
        conn = socket.create_connection((LOOPBACK, int(port)), timeout=2)
    except OSError as exc:
        sys.stderr.write(f"poke failed: {exc.errno}\n")
        return 1
    try:
        conn.sendall(b"GET http://canary.invalid/ HTTP/1.1\r\nHost: canary.invalid\r\n\r\n")
        conn.recv(256)
    finally:
        conn.close()
    text = (Path(var) / "tripwire").read_text(encoding="utf-8") if (Path(var) / "tripwire").is_file() else ""
    if "canary.invalid" not in text:
        sys.stderr.write("canary was not tripped\n")
        return 1
    return 0

def main(argv, standin):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "selfcheck":
        return selfcheck(standin)
    if cmd == "kernel":
        return kernel(standin)
    if cmd == "merge-check":
        return merge_check(standin)
    if cmd == "audit":
        return audit(int(argv[2]))
    if cmd == "reload-bad":
        return reload_bad(argv[2], argv[3])
    if cmd == "poke":
        return poke(argv[2], argv[3])
    sys.stderr.write("usage\n")
    return 1
