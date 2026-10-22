#!/usr/bin/env python3
"""Controller paths and the fake exchange. No network."""
import contextlib
import io
import json
import os
import sys
import tempfile
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib"))

from axs.mihomo import (  # noqa: E402
    delay_path,
    probe,
    proxies_path,
    read_secret,
    reload_path,
    request,
    select_path,
    version_path,
)


def main():
    if select_path("a b") != "/proxies/" + quote("a b", safe=""):
        raise SystemExit("select path")
    delayed = delay_path("g", "https://example.test/x")
    if delayed != "/group/" + quote("g", safe="") + "/delay?timeout=5000&url=https%3A%2F%2Fexample.test%2Fx":
        raise SystemExit(f"delay path {delayed}")
    if (proxies_path(), version_path(), reload_path()) != ("/proxies", "/version", "/configs?force=true"):
        raise SystemExit("fixed paths")
    saved = os.environ.get("AXS_FAKE_DIR")
    try:
        with tempfile.TemporaryDirectory(prefix="axs-mihomo-") as tmp:
            fake = Path(tmp)
            os.environ["AXS_FAKE_DIR"] = str(fake)
            secret_path = fake / "secret"
            secret_path.write_text("test-secret-value\n", encoding="utf-8")
            err = io.StringIO()
            try:
                with contextlib.redirect_stderr(err):
                    read_secret(secret_path, "10.0.0.1:1")
            except SystemExit:
                if "回环" not in err.getvalue():
                    raise SystemExit("loopback message missing") from None
            else:
                raise SystemExit("non-loopback secret accepted")
            secret = read_secret(secret_path, "127.0.0.1:9")
            (fake / "proxies.json").write_text(
                '{"proxies":{"g":{"type":"Selector","now":"a","all":["a"]}}}\n',
                encoding="utf-8",
            )
            payload = json.loads(request(secret, "127.0.0.1:9", "GET", proxies_path()))
            if "g" not in payload["proxies"]:
                raise SystemExit("proxies body")
            if json.loads(request(secret, "127.0.0.1:9", "GET", version_path()))["version"] != "fake":
                raise SystemExit("version body")
            (fake / "delay").write_text("7\n", encoding="utf-8")
            got = json.loads(request(secret, "127.0.0.1:9", "GET", delay_path("g", "http://127.0.0.1/")))
            if got != {"g": 7}:
                raise SystemExit(f"delay body {got}")
            (fake / "reload").write_text("204\n", encoding="utf-8")
            if request(secret, "127.0.0.1:9", "PUT", reload_path(), b"{}") != b"":
                raise SystemExit("reload body")
            if request(secret, "127.0.0.1:9", "PUT", select_path("g"), b'{"name":"a"}') != b"":
                raise SystemExit("select body")
            log = (fake / "log").read_text(encoding="utf-8")
            if f"PUT {select_path('g')} auth=yes" not in log or f"PUT {reload_path()} auth=yes" not in log:
                raise SystemExit("request log")
            (fake / "open-ports").write_text("9\n", encoding="utf-8")
            probe("127.0.0.1", 9)
            try:
                probe("127.0.0.1", 10)
            except SystemExit as exc:
                if exc.code != 1:
                    raise SystemExit(f"probe code {exc.code}") from exc
            else:
                raise SystemExit("closed port probed open")
            captured = {}

            class Response:
                status = 204

                def read(self):
                    return b"ok"

                def __enter__(self):
                    return self

                def __exit__(self, *_args):
                    return False

            def urlopen(req, timeout):
                captured["url"] = req.full_url
                captured["timeout"] = timeout
                captured["auth"] = req.get_header("Authorization")
                return Response()

            os.environ.pop("AXS_FAKE_DIR")
            import axs.mihomo as mihomo

            original = mihomo.urllib.request.urlopen
            mihomo.urllib.request.urlopen = urlopen
            try:
                if request(secret, "127.0.0.1:9", "GET", proxies_path()) != b"ok":
                    raise SystemExit("live body")
            finally:
                mihomo.urllib.request.urlopen = original
            if captured != {
                "url": "http://127.0.0.1:9/proxies",
                "timeout": 5,
                "auth": "Bearer " + secret,
            }:
                raise SystemExit(f"url build {captured}")
    finally:
        if saved is None:
            os.environ.pop("AXS_FAKE_DIR", None)
        else:
            os.environ["AXS_FAKE_DIR"] = saved
    print("mihomo client")
    return 0


if __name__ == "__main__":
    sys.exit(main())
