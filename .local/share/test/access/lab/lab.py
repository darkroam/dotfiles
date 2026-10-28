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

_here = Path(__file__).resolve()
TEST = next(p for p in (_here.parent, *_here.parents) if (p / "run.sh").is_file() and (p / "support").is_dir())
ROOT = next(p / ".local/lib/access" for p in _here.parents if (p / ".local/lib/access/bin/axs").is_file())
sys.path.insert(0, str(ROOT))
from axs.config import LOOPBACK, LOOPBACK_HOSTS  # noqa: E402

MIHOMO = os.environ.get("AXS_ENV_MIHOMO", str(Path.home() / ".local/bin/mihomo"))
ALLOWED = {host for host in LOOPBACK_HOSTS if ":" not in host} | {"target.test"}


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


def _decode_dns_name(data, offset):
    labels = []
    seen = 0
    while True:
        if offset >= len(data) or seen > 8:
            return None
        length = data[offset]
        if length == 0:
            return ".".join(labels).lower()
        if length & 0xC0:
            return None
        offset += 1
        labels.append(data[offset:offset + length].decode("ascii", "replace"))
        offset += length
        seen += 1


def _question_end(data):
    offset = 12
    while offset < len(data):
        length = data[offset]
        if length == 0:
            return offset + 5
        if length & 0xC0:
            return offset + 6
        offset += 1 + length
    return None


def answer_dns(query, var):
    if len(query) < 12 or int.from_bytes(query[4:6], "big") < 1:
        return None
    end = _question_end(query)
    if end is None or end > len(query):
        return None
    name = _decode_dns_name(query, 12)
    if name is None:
        return None
    qtype = int.from_bytes(query[end - 4:end - 2], "big")
    own = name == "target.test" or (name.endswith(".test") and name != "test")
    if name.endswith(".invalid"):
        trip(var, name)
    rcode = 0 if own else 3
    byte2 = 0x84 | (query[2] & 0x01)
    byte3 = 0x80 | (0 if own else rcode)
    if own and qtype == 28:
        byte3 = 0x80
    header = bytearray(query[:2] + bytes((byte2, byte3)) + query[4:6] + b"\x00\x00\x00\x00\x00\x00")
    question = query[12:end]
    if not own or qtype != 1:
        return bytes(header) + question
    header[6:8] = (1).to_bytes(2, "big")
    answer = b"\xc0\x0c" + (1).to_bytes(2, "big") + (1).to_bytes(2, "big")
    answer += (60).to_bytes(4, "big") + (4).to_bytes(2, "big") + bytes(int(part) for part in LOOPBACK.split("."))
    return bytes(header) + question + answer


def dns_query(name, qtype=1):
    labels = b"".join(bytes((len(part),)) + part.encode() for part in name.split(".")) + b"\x00"
    return b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00" + labels + qtype.to_bytes(2, "big") + b"\x00\x01"


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
        if host and not allowed(self.var, host) and host not in (LOOPBACK,):
            self._send(403, b"", "text/plain")
            return
        path = urllib.parse.urlsplit(self.path).path
        if path == "/sub":
            if (Path(self.var) / "bad").is_file():
                self._send(200, b"<html>\n", "text/html")
                return
            marker = (Path(self.var) / "marker").is_file()
            body = _checks().subscription(self.server.proxy_port, marker, self.server.dns_port)
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
    upstream = socket.create_connection((LOOPBACK, port), timeout=3)
    request = (
        f"{method} {path} HTTP/1.1\r\n"
        f"Host: {LOOPBACK}:{port}\r\n"
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


def serve(var, http_port, proxy_port, dns_port):
    var = Path(var)
    var.mkdir(parents=True, exist_ok=True)
    os.chmod(var, 0o700)
    Target.var = str(var)
    try:
        httpd = ThreadingHTTPServer((LOOPBACK, int(http_port)), Target)
    except OSError as exc:
        sys.stderr.write(f"bind failed: {exc.errno}\n")
        return 1
    httpd.proxy_port = int(proxy_port)
    httpd.dns_port = int(dns_port)
    try:
        proxy = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        proxy.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        proxy.bind((LOOPBACK, int(proxy_port)))
        proxy.listen(32)
    except OSError as exc:
        httpd.server_close()
        sys.stderr.write(f"bind failed: {exc.errno}\n")
        return 1
    try:
        dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        dns.bind((LOOPBACK, int(dns_port)))
    except OSError as exc:
        proxy.close()
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

    def read_dns():
        dns.settimeout(0.3)
        while not stop.is_set():
            try:
                data, addr = dns.recvfrom(2048)
            except socket.timeout:
                continue
            except OSError:
                break
            if not str(addr[0]).startswith(LOOPBACK.split(".", 1)[0] + "."):
                trip(var, str(addr[0]))
                continue
            reply = answer_dns(data, var)
            if reply:
                try:
                    dns.sendto(reply, addr)
                except OSError:
                    pass

    threading.Thread(target=accept_proxy, daemon=True).start()
    threading.Thread(target=read_dns, daemon=True).start()
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    (var / "lab.pid").write_text(str(os.getpid()) + "\n", encoding="utf-8")
    (var / "ready").write_text("ok\n", encoding="utf-8")

    def halt(signum, _frame):
        stop.set()
        httpd.shutdown()
        proxy.close()
        dns.close()

    signal.signal(signal.SIGTERM, halt)
    signal.signal(signal.SIGINT, halt)
    stop.wait()
    httpd.server_close()
    return 0

def _checks():
    import importlib.util
    path = Path(__file__).with_name("audit.py")
    spec = importlib.util.spec_from_file_location("axs_lab_audit", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "serve":
        return serve(argv[2], argv[3], argv[4], argv[5])
    if cmd == "has":
        sys.stdout.write("yes\n" if argv[3] in rules_text(argv[2]).splitlines() else "no\n")
        return 0
    if cmd in {"selfcheck", "kernel", "merge-check", "audit", "reload-bad", "poke"}:
        return _checks().main(argv, sys.modules["__main__"])
    sys.stderr.write("usage\n")
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except IndexError:
        sys.stderr.write("usage\n")
        raise SystemExit(1)
