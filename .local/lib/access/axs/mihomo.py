"""Controller client. Rollback and rule meaning stay with the caller."""

from axs.codes import USAGE
from axs.config import LOOPBACK
import contextvars
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PROXIES = "/proxies"
VERSION = "/version"
RELOAD = "/configs?force=true"
GROUP = "/group/"
DELAY = "/delay"
RULES_PATH = "/rules"
_QUIET = contextvars.ContextVar("axs_controller_quiet", default=False)


def proxies_path():
    return PROXIES


def version_path():
    return VERSION


def reload_path():
    return RELOAD


def select_path(name):
    return PROXIES + "/" + urllib.parse.quote(name, safe="")


def _fail(message):
    if _QUIET.get():
        raise SystemExit(message)
    sys.stderr.write(message + "\n")
    raise SystemExit(USAGE)


def read_secret(secret_path, api):
    if not str(api).startswith(LOOPBACK + ":"):
        _fail("控制器失败：不在回环")
    try:
        secret = Path(secret_path).read_text(encoding="utf-8").strip()
    except OSError:
        _fail("控制器失败：密钥不可读")
    if len(secret) < 8:
        _fail("控制器失败：密钥过短")
    return secret


def _link_error(exc, timeout):
    reason = getattr(exc, "reason", exc)
    if isinstance(reason, TimeoutError) or "timed out" in str(reason).lower():
        return f"控制器失败：请求超时（{timeout} 秒）"
    detail = reason if getattr(exc, "reason", None) is not None else exc
    return f"控制器失败：连接失败（{detail}）"


def _fake_exchange(method, path, secret, body=None):
    directory = Path(os.environ["AXS_FAKE_DIR"])
    flag = "yes" if secret and len(secret) >= 8 else "no"
    extra = ""
    if body:
        extra = " body=" + body.decode("utf-8", "replace")
    with (directory / "log").open("a", encoding="utf-8") as handle:
        handle.write(f"{method} {path} auth={flag}{extra}\n")
    if (directory / "down").is_file():
        _fail("控制器失败")
    pure = path.split("?", 1)[0]
    if method == "PUT" and pure.startswith(PROXIES + "/"):
        code_path = directory / "select"
        code = int(code_path.read_text(encoding="utf-8").strip() or "204") if code_path.is_file() else 204
        if code >= 300:
            _fail("控制器失败")
        return b""
    if method == "PUT":
        code = int((directory / "reload").read_text(encoding="utf-8").strip() or "204")
        if code >= 300:
            _fail("控制器失败")
        return b""
    if pure == VERSION:
        return b'{"version":"fake"}'
    if pure == PROXIES:
        ready = directory / "proxies.json"
        if ready.is_file():
            return ready.read_bytes()
        text = (directory / "groups").read_text(encoding="utf-8") if (directory / "groups").is_file() else ""
        payload = {
            name: {"type": "Selector", "now": "a", "all": ["a"]}
            for name in text.split()
        }
        return json.dumps({"proxies": payload}).encode()
    if method == "GET" and pure.startswith(PROXIES + "/") and pure.endswith(DELAY):
        name = urllib.parse.unquote(pure[len(PROXIES) + 1 : -len(DELAY)])
        value = _leaf_delay(directory, name)
        return json.dumps({"delay": value}).encode() if type(value) is int else b'{"delay":null}'
    if pure.startswith(GROUP) and pure.endswith(DELAY):
        ready = directory / "delay.json"
        if ready.is_file():
            return ready.read_bytes()
        name = urllib.parse.unquote(pure[len(GROUP) : -len(DELAY)])
        delay = int((directory / "delay").read_text(encoding="utf-8").strip() or "0")
        return json.dumps({name: delay}).encode()
    if method == "GET" and pure == RULES_PATH:
        ready = directory / "rules.json"
        if ready.is_file():
            return ready.read_bytes()
    _fail("控制器失败")


def _leaf_delay(directory, name):
    ready = directory / "delay.json"
    if ready.is_file():
        data = json.loads(ready.read_text(encoding="utf-8"))
        return data.get(name) if isinstance(data, dict) else None
    path = directory / "delay"
    if path.is_file():
        return int(path.read_text(encoding="utf-8").strip() or "0")
    return None


def request(secret, api, method, path, body=None, timeout=5):
    if os.environ.get("AXS_FAKE_DIR"):
        return _fake_exchange(method, path, secret, body)
    req = urllib.request.Request(
        f"http://{api}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": "Bearer " + secret,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            if resp.status >= 300:
                _fail(f"控制器失败：HTTP {resp.status}")
            return raw
    except urllib.error.HTTPError as exc:
        _fail(f"控制器失败：HTTP {exc.code}")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        _fail(_link_error(exc, timeout))


def probe(host, port):
    directory = os.environ.get("AXS_FAKE_DIR")
    if directory:
        listed = ""
        path = Path(directory) / "open-ports"
        if path.is_file():
            listed = path.read_text(encoding="utf-8")
        if str(port) not in listed.split():
            raise SystemExit(USAGE)
        return
    import socket

    sock = socket.socket()
    sock.settimeout(0.3)
    try:
        sock.connect((host, int(port)))
    except OSError:
        raise SystemExit(USAGE)
    finally:
        sock.close()


GROUP_TYPES = {"Selector", "URLTest", "Fallback", "LoadBalance", "Relay"}


def load_proxies(secret_path, api):
    secret = read_secret(secret_path, api)
    raw = request(secret, api, "GET", proxies_path())
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        _fail("控制器失败：响应格式错误")
    proxies = payload.get("proxies") if isinstance(payload, dict) else None
    if not isinstance(proxies, dict):
        _fail("控制器失败：响应格式错误")
    return proxies


def group_names(secret_path, api):
    proxies = load_proxies(secret_path, api)
    names = []
    for name, item in proxies.items():
        if isinstance(item, dict) and item.get("type") in GROUP_TYPES:
            names.append(name)
    return names


def reload_core(secret_path, api, config_path):
    secret = read_secret(secret_path, api)
    body = json.dumps({"path": str(config_path), "payload": ""}).encode()
    try:
        request(secret, api, "PUT", reload_path(), body)
    except SystemExit:
        _fail("重载失败")


def version_ok(secret_path, api):
    secret = read_secret(secret_path, api)
    try:
        request(secret, api, "GET", version_path())
    except SystemExit:
        failed = 3
        raise SystemExit(failed)


