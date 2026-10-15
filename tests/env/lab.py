#!/usr/bin/env python3
"""Loopback subscription, target, and HTTP proxy. Never resolves or dials off-loop."""
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import yaml

MIHOMO = os.environ.get("AXS_ENV_MIHOMO", str(Path.home() / ".local/bin/mihomo"))
ALLOWED = {"127.0.0.1", "localhost", "target.test"}


def mihomo_bin():
    return MIHOMO


def trip(var, host):
    with (Path(var) / "tripwire").open("a", encoding="utf-8") as handle:
        handle.write((host or "") + "\n")


def allowed(var, host):
    name = (host or "").strip("[]").lower().rstrip(".")
    if name in ALLOWED:
        return True
    trip(var, name)
    return False


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


def subscription(proxy_port, marker):
    rules = []
    if marker:
        rules.append("DOMAIN,marker.test,DIRECT")
    rules.append("MATCH,DIRECT")
    data = {
        "mixed-port": 1,
        "mode": "global",
        "allow-lan": True,
        "ipv6": False,
        "external-controller": "127.0.0.1:1",
        "secret": "from-sub",
        "geo-auto-update": False,
        "tun": {"enable": True},
        "dns": {
            "enable": False,
            "listen": "127.0.0.1:1",
            "nameserver": ["127.0.0.1:9"],
        },
        "hosts": {"target.test": "127.0.0.1"},
        "proxies": [{
            "name": "local",
            "type": "http",
            "server": "127.0.0.1",
            "port": int(proxy_port),
        }],
        "proxy-groups": [{
            "name": "PROXY",
            "type": "select",
            "proxies": ["local"],
        }],
        "rules": rules,
    }
    return yaml.safe_dump(data, allow_unicode=True, sort_keys=False)


def userinfo(var):
    mode = "ok"
    path = Path(var) / "expire"
    if path.is_file():
        mode = path.read_text(encoding="utf-8").strip() or "ok"
    now = int(__import__("time").time())
    if mode == "none":
        return ""
    if mode == "past":
        expire = now - 10
    elif mode == "soon":
        expire = now + 86400
    else:
        expire = now + 40 * 86400
    return f"upload=1; download=2; total=3; expire={expire}"


def rules_text(path):
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    rules = data.get("rules") if isinstance(data, dict) else None
    if not isinstance(rules, list):
        return ""
    return "\n".join(str(item) for item in rules)


class Target(BaseHTTPRequestHandler):
    var = None

    def log_message(self, fmt, *args):
        path = urllib.parse.urlsplit(self.path).path
        with (Path(self.var) / "http.log").open("a", encoding="utf-8") as handle:
            handle.write(path + "\n")

    def _send(self, code, body, content_type, extra=None):
        payload = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        if extra:
            for key, value in extra.items():
                if value:
                    self.send_header(key, value)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        host = (self.headers.get("Host") or "").split(":")[0]
        if host and not allowed(self.var, host) and host not in ("127.0.0.1",):
            self._send(403, b"", "text/plain")
            return
        path = urllib.parse.urlsplit(self.path).path
        if path == "/sub":
            if (Path(self.var) / "bad").is_file():
                self._send(200, b"<html>\n", "text/html")
                return
            marker = (Path(self.var) / "marker").is_file()
            body = subscription(self.server.proxy_port, marker)
            self._send(200, body, "text/yaml", {"subscription-userinfo": userinfo(self.var)})
            return
        if path == "/who":
            body = b"node\n" if self.headers.get("X-Env-Hop") == "node" else b"direct\n"
            self._send(200, body, "text/plain")
            return
        if path == "/204":
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self._send(404, b"", "text/plain")


def split_hostport(value, default_port):
    text = value.strip()
    if text.startswith("["):
        host, _, rest = text[1:].partition("]")
        port = rest[1:] if rest.startswith(":") else str(default_port)
        return host, int(port)
    if text.count(":") == 1:
        host, port = text.rsplit(":", 1)
        return host, int(port)
    return text, default_port


def read_request(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            return None
        data += chunk
        if len(data) > 65536:
            return None
    head, rest = data.split(b"\r\n\r\n", 1)
    lines = head.decode("iso-8859-1", "replace").split("\r\n")
    method, target, _proto = lines[0].split(" ", 2)
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    need = int(headers.get("content-length") or "0")
    while len(rest) < need:
        chunk = conn.recv(4096)
        if not chunk:
            break
        rest += chunk
    return method.upper(), target, headers, rest[:need]


def pipe(src, dst):
    try:
        while True:
            chunk = src.recv(65536)
            if not chunk:
                break
            dst.sendall(chunk)
    except OSError:
        pass


def reply_text(conn, body):
    payload = body.encode()
    conn.sendall(
        f"HTTP/1.1 200 OK\r\nContent-Length: {len(payload)}\r\nConnection: close\r\n\r\n".encode()
        + payload
    )


def parse_target(method, target, headers):
    if method == "CONNECT":
        host, port = split_hostport(target, 443)
        return host, port, ""
    if target.startswith("http://"):
        parts = urllib.parse.urlsplit(target)
        path = parts.path or "/"
        if parts.query:
            path += "?" + parts.query
        return parts.hostname or "", parts.port or 80, path
    host, port = split_hostport(headers.get("host", ""), 80)
    path = target if target.startswith("/") else "/"
    return host, port, path


def forward(conn, port, method, path, body):
    upstream = socket.create_connection(("127.0.0.1", port), timeout=3)
    request = (
        f"{method} {path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "X-Env-Hop: node\r\n"
        "Connection: close\r\n"
        f"Content-Length: {len(body)}\r\n\r\n"
    ).encode() + body
    upstream.sendall(request)
    pipe(upstream, conn)
    upstream.close()


def handle_proxy(conn, var):
    try:
        parsed = read_request(conn)
        if parsed is None:
            return
        method, target, headers, body = parsed
        host, port, path = parse_target(method, target, headers)
        if not allowed(var, host):
            conn.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
            return
        if method == "CONNECT":
            conn.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            inner = read_request(conn)
            if inner is None:
                return
            method, target, headers, body = inner
            _host, _port, path = parse_target(method, target, headers)
        if path.split("?", 1)[0] == "/who":
            reply_text(conn, "node\n")
            return
        forward(conn, port, method, path, body)
    except OSError:
        try:
            conn.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
        except OSError:
            pass
    finally:
        conn.close()


def serve(var, http_port, proxy_port):
    var = Path(var)
    var.mkdir(parents=True, exist_ok=True)
    os.chmod(var, 0o700)
    Target.var = str(var)
    try:
        httpd = ThreadingHTTPServer(("127.0.0.1", int(http_port)), Target)
    except OSError as exc:
        sys.stderr.write(f"bind failed: {exc.errno}\n")
        return 1
    httpd.proxy_port = int(proxy_port)
    try:
        proxy = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        proxy.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        proxy.bind(("127.0.0.1", int(proxy_port)))
        proxy.listen(32)
    except OSError as exc:
        httpd.server_close()
        sys.stderr.write(f"bind failed: {exc.errno}\n")
        return 1
    stop = threading.Event()

    def accept_proxy():
        proxy.settimeout(0.3)
        while not stop.is_set():
            try:
                conn, _addr = proxy.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=handle_proxy, args=(conn, var), daemon=True).start()

    threading.Thread(target=accept_proxy, daemon=True).start()
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    (var / "lab.pid").write_text(str(os.getpid()) + "\n", encoding="utf-8")
    (var / "ready").write_text("ok\n", encoding="utf-8")

    def halt(signum, _frame):
        stop.set()
        httpd.shutdown()
        proxy.close()

    signal.signal(signal.SIGTERM, halt)
    signal.signal(signal.SIGINT, halt)
    stop.wait()
    httpd.server_close()
    return 0


def kernel():
    good = """\
mixed-port: 17897
allow-lan: false
mode: rule
log-level: error
external-controller: 127.0.0.1:19097
secret: local-test-secret
geo-auto-update: false
tun:
  enable: false
dns:
  enable: false
proxies:
  - name: local
    type: http
    server: 127.0.0.1
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
        ok = subprocess.run([mihomo_bin(), "-t", "-d", str(root / "good")], capture_output=True, text=True)
        no = subprocess.run([mihomo_bin(), "-t", "-d", str(root / "bad")], capture_output=True, text=True)
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


def pair_check(var):
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
                handle_proxy(right, var)
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


def merge_check():
    root = Path(__file__).resolve().parents[2]
    merge = root / "lib" / "merge.py"
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        sub = folder / "sub.yaml"
        sub.write_text(subscription(9, False), encoding="utf-8")
        subprocess.check_call(
            ["python3", str(merge), "defaults", str(folder / "override.yaml"), "18093", "127.0.0.1:18094"],
            stdout=subprocess.DEVNULL,
        )
        subprocess.check_call(
            ["python3", str(merge), "gen-secret", str(folder / "secret")],
            stdout=subprocess.DEVNULL,
        )
        (folder / "rules.list").write_text("DOMAIN target.test PROXY\n", encoding="utf-8")
        subprocess.check_call(
            [
                "python3", str(merge), "build",
                str(sub), str(folder / "override.yaml"), str(folder / "secret"),
                str(folder / "rules.list"), str(folder / "config.yaml"),
            ],
            stdout=subprocess.DEVNULL,
        )
        proc = subprocess.run(
            [mihomo_bin(), "-t", "-d", str(folder)],
            capture_output=True, text=True,
        )
        body = (folder / "config.yaml").read_text(encoding="utf-8")
    if proc.returncode != 0:
        sys.stderr.write("merged config rejected\n")
        return 1
    if "from-sub" in body or "canary.invalid" in body:
        sys.stderr.write("subscription secret kept\n")
        return 1
    if "DOMAIN,target.test,PROXY" not in body or "127.0.0.1:9" not in body:
        sys.stderr.write("merged shape\n")
        return 1
    return 0


def selfcheck():
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
        if not allowed(var, "target.test") or allowed(var, "canary.invalid"):
            sys.stderr.write("allow list\n")
            return 1
        if (var / "tripwire").read_text(encoding="utf-8").strip() != "canary.invalid":
            sys.stderr.write("tripwire\n")
            return 1
        text = subscription(9, True)
        if "canary.invalid" in text or "target.test" not in text or "marker.test" not in text:
            sys.stderr.write("subscription shape\n")
            return 1
        if pair_check(var):
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
        conn = socket.create_connection(("127.0.0.1", int(port)), timeout=2)
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


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "selfcheck":
        return selfcheck()
    if cmd == "kernel":
        return kernel()
    if cmd == "merge-check":
        return merge_check()
    if cmd == "serve":
        return serve(argv[2], argv[3], argv[4])
    if cmd == "audit":
        return audit(int(argv[2]))
    if cmd == "reload-bad":
        return reload_bad(argv[2], argv[3])
    if cmd == "poke":
        return poke(argv[2], argv[3])
    if cmd == "has":
        sys.stdout.write("yes\n" if argv[3] in rules_text(argv[2]).splitlines() else "no\n")
        return 0
    sys.stderr.write("usage\n")
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except IndexError:
        sys.stderr.write("usage\n")
        raise SystemExit(1)
