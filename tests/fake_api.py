#!/usr/bin/env python3
"""Loopback controller double. Never dials out."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GROUPS = [item for item in os.environ.get("FAKE_GROUPS", "PROXY").split(",") if item]
RELOAD = int(os.environ.get("FAKE_RELOAD", "204"))
LOG = os.environ["FAKE_LOG"]
DELAY = int(os.environ.get("FAKE_DELAY", "0"))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _note(self):
        auth = self.headers.get("Authorization", "")
        flag = "yes" if auth.startswith("Bearer ") and len(auth) > 12 else "no"
        with open(LOG, "a", encoding="utf-8") as handle:
            handle.write(f"{self.command} {self.path} auth={flag}\n")

    def _send(self, code, body=b""):
        self.send_response(code)
        if body:
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        self._note()
        path = self.path.split("?", 1)[0]
        if path == "/version":
            self._send(200, b'{"version":"fake"}')
            return
        if path == "/proxies":
            proxies = {
                name: {"type": "Selector", "now": "a", "all": ["a"]}
                for name in GROUPS
            }
            self._send(200, json.dumps({"proxies": proxies}).encode())
            return
        if path.startswith("/group/") and path.endswith("/delay"):
            name = path.split("/")[2]
            self._send(200, json.dumps({name: DELAY}).encode())
            return
        self._send(404)

    def do_PUT(self):
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        self._note()
        self._send(RELOAD)


def main():
    port = int(sys.argv[1])
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
