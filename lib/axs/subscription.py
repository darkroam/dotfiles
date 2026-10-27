"""Fetch, check, merge, install, roll back, and clean a subscription."""

from axs.codes import FAIL
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

import yaml

from axs.config import (
    CONFIG,
    CONFIG_BAK,
    FETCH_BODY,
    FETCH_HEADER,
    PID,
    SNAP,
    SUBSCRIPTION,
    LOOPBACK,
    CIDRS,
    URL,
    USERINFO,
)
from axs.core import atomic_write, fail, install_file, restore_snapshot, snapshot
from axs.render import dim, emph


take_snapshot = snapshot
rollback = restore_snapshot
install_merged = install_file

DROP_PORTS = ("port", "socks-port", "redir-port", "tproxy-port")

def merge_dict(base, over):
    if not isinstance(base, dict) or not isinstance(over, dict):
        return over
    out = dict(base)
    for key, value in over.items():
        if key == "prepend-rules":
            continue
        if isinstance(out.get(key), dict) and isinstance(value, dict):
            out[key] = merge_dict(out[key], value)
        else:
            out[key] = value
    return out

def load_profile(path):
    raw = Path(path).read_bytes()
    if raw.lstrip().startswith(b"<"):
        fail("校验失败")
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError:
        fail("校验失败")
    proxies = data.get("proxies") if isinstance(data, dict) else None
    if not isinstance(proxies, list) or not proxies:
        fail("校验失败")
    if not all(isinstance(item, dict) and item.get("server") for item in proxies):
        fail("校验失败")
    return data

def load_local_rules(path):
    path = Path(path)
    if not path.is_file():
        return []
    rules = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 3 or parts[0] not in ("DOMAIN", "DOMAIN-SUFFIX"):
            fail("校验失败")
        rules.append(f"{parts[0]},{parts[1]},{parts[2]}")
    return rules

def dedupe(items):
    seen = []
    for item in items:
        if item not in seen:
            seen.append(item)
    return seen

def build_file(sub_path, override_path, secret_path, rules_path, out_path):
    sub = load_profile(sub_path)
    over = yaml.safe_load(Path(override_path).read_text(encoding="utf-8"))
    if not isinstance(over, dict):
        fail("校验失败")
    secret = Path(secret_path).read_text(encoding="utf-8").strip()
    if len(secret) < 8:
        fail("校验失败")
    merged = merge_dict(sub, over)
    controller = merged.get("external-controller")
    if not isinstance(controller, str) or not controller.startswith(LOOPBACK + ":"):
        fail("校验失败")
    extra = over.get("prepend-rules") or []
    if not isinstance(extra, list):
        fail("校验失败")
    base_rules = merged.get("rules") or []
    if not isinstance(base_rules, list):
        fail("校验失败")
    merged["rules"] = dedupe(CIDRS + extra + load_local_rules(rules_path) + base_rules)
    merged.pop("prepend-rules", None)
    for key in DROP_PORTS:
        merged.pop(key, None)
    merged["tun"] = {"enable": False}
    merged["secret"] = secret
    merged["mode"] = over.get("mode") or "rule"
    atomic_write(out_path, yaml.safe_dump(merged, allow_unicode=True, sort_keys=False))

YAML_TYPES = {
    "text/yaml",
    "application/yaml",
    "application/x-yaml",
    "text/x-yaml",
    "text/plain",
    "application/octet-stream",
}

def check_url(path):
    raw = Path(path).read_text(encoding="utf-8", errors="replace")
    url = raw.strip("\r\n")
    if url != url.strip() or any(ch.isspace() for ch in url) or "\\" in url:
        sys.stderr.write("链接含转义字符（如 \\?），请去掉反斜杠\n")
        raise SystemExit(FAIL)

def _header_field(text, name):
    prefix = name.lower() + ":"
    for line in text.splitlines():
        if line.lower().startswith(prefix):
            return line.split(":", 1)[1].strip()
    return ""

def _yaml_type(value):
    if not value or not value.strip():
        return True
    main = value.split(";", 1)[0].strip().lower()
    return main in YAML_TYPES or main.endswith("/yaml") or main.endswith("+yaml")

def check_fetched(body_path, header_path):
    body_file = Path(body_path)
    body = body_file.read_bytes() if body_file.is_file() else b""
    header = ""
    header_file = Path(header_path)
    if header_file.is_file():
        header = header_file.read_text(encoding="utf-8", errors="replace")
    status = _header_field(header, "x-axs-status") or "-"
    ctype = _header_field(header, "x-axs-content-type")
    html = body.lstrip().startswith(b"<")
    if body.strip() and _yaml_type(ctype) and not html:
        return
    shown = ctype or ("text/html" if html else "-")
    sys.stderr.write(
        f"订阅返回空内容/非 YAML（HTTP {status}, {shown}），请检查链接\n"
    )
    raise SystemExit(FAIL)

def fetch(urlfile, body_path, header_path):
    if os.environ.get("AXS_FORBID_NET") == "1":
        fail("离线测试拒绝联网")
    url = Path(urlfile).read_text(encoding="utf-8").strip()
    if not url.startswith(("http://", "https://")):
        fail("拉取失败")
    req = urllib.request.Request(url, headers={"User-Agent": "axs"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            payload = resp.read()
            info = resp.headers.get("subscription-userinfo", "")
            status = getattr(resp, "status", None) or 200
            ctype = resp.headers.get("content-type") or ""
    except (urllib.error.URLError, TimeoutError, OSError):
        fail("拉取失败")
    Path(body_path).write_bytes(payload)
    Path(header_path).write_text(
        "subscription-userinfo: " + info + "\n"
        + f"x-axs-status: {status}\n"
        + f"x-axs-content-type: {ctype}\n",
        encoding="utf-8",
    )

def write_userinfo(header_path, out_path):
    text = Path(header_path).read_text(encoding="utf-8", errors="replace")
    value = ""
    for line in text.splitlines():
        if line.lower().startswith("subscription-userinfo:"):
            value = line.split(":", 1)[1].strip()
    fields = {}
    for part in value.split(";"):
        if "=" not in part:
            continue
        key, raw = part.split("=", 1)
        fields[key.strip()] = raw.strip()
    lines = []
    for key in ("upload", "download", "total", "expire"):
        if key in fields and fields[key].isdigit():
            lines.append(f"{key}={fields[key]}")
    atomic_write(out_path, ("\n".join(lines) + ("\n" if lines else "")))

def classify(userinfo_path, now):
    path = Path(userinfo_path)
    if not path.is_file():
        return "unknown", None
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key] = value
    if "expire" not in fields:
        return "unknown", None
    expire = int(fields["expire"])
    now = int(now)
    if expire <= now:
        return "expired", 0
    days = (expire - now) // 86400
    if expire - now < 3 * 86400:
        return "soon", days
    return "ok", days

def human_bytes(raw):
    # shortcut: float 在约 9 PB 以上会偏，流量真到那种量级再改整数
    try:
        value = int(raw)
    except (TypeError, ValueError):
        return str(raw)
    if value < 0:
        return str(raw)
    scaled = float(value)
    unit = "B"
    for name in ("K", "M", "G", "T"):
        if scaled < 1024:
            break
        scaled /= 1024
        unit = name
    return f"{scaled:.1f}{unit}"

def subscription_line(path, now):
    kind, days = classify(path, now)
    if kind == "expired":
        rest = emph("31", "已过期")
    elif kind == "soon":
        rest = emph("33", f"{days} 天（警告）")
    elif kind == "ok":
        rest = emph("32", f"{days} 天")
    else:
        rest = dim("未知")
    bits = []
    fields = _userinfo_fields(path)
    for key, lab in (("upload", "上传"), ("download", "下载"), ("total", "总量")):
        if key in fields and fields[key] != "":
            bits.append(f"{lab} {human_bytes(fields[key])}")
    text = "剩余 " + rest
    if bits:
        text += " · " + " · ".join(bits)
    return text, kind

def show_userinfo(path, now):
    text, _kind = subscription_line(path, now)
    sys.stdout.write(text + "\n")

def _userinfo_fields(path):
    fields = {}
    file = Path(path)
    if not file.is_file():
        return fields
    for line in file.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key] = value
    return fields

def clean_names(kind):
    if kind == "config":
        return (CONFIG, CONFIG_BAK, USERINFO, FETCH_BODY, FETCH_HEADER, PID)
    return (URL, SUBSCRIPTION, USERINFO, FETCH_BODY, FETCH_HEADER)


def clear_fetch(run):
    run = Path(run)
    for name in (FETCH_BODY, FETCH_HEADER):
        (run / name).unlink(missing_ok=True)
    snap = run / SNAP
    for name in (CONFIG, SUBSCRIPTION):
        (snap / name).unlink(missing_ok=True)


def refresh_run(run):
    import subprocess

    from axs.config import CONFIG_NEW, OVERRIDE, RULES, SECRET, ensure_override, read_ports
    from axs.core import gen_secret, hold_lock, service_up
    from axs.mihomo import reload_core
    from axs.render import die

    runp = Path(run)
    hold_lock(run)
    url = runp / URL
    if not url.is_file():
        die(FAIL, "没有订阅")
    os.chmod(url, 0o600)
    check_url(url)
    body = str(runp / FETCH_BODY)
    hdr = str(runp / FETCH_HEADER)
    helper = os.environ.get("AXS_FETCH")
    if helper:
        if subprocess.run([helper, str(url), body, hdr]).returncode != 0:
            die(FAIL, "拉取失败")
    else:
        try:
            fetch(str(url), body, hdr)
        except SystemExit:
            die(FAIL, "拉取失败")
    check_fetched(body, hdr)
    ensure_override(run)
    gen_secret(runp / SECRET)
    _mixed, api = read_ports(run)
    snapshot(runp)
    try:
        build_file(body, runp / OVERRIDE, runp / SECRET, runp / RULES, runp / CONFIG_NEW)
    except SystemExit:
        restore_snapshot(runp)
        die(FAIL, "校验失败")
    install_file(runp / CONFIG_NEW, runp / CONFIG)
    if Path(body) != runp / SUBSCRIPTION:
        install_file(body, runp / SUBSCRIPTION)
    if service_up(run):
        try:
            reload_core(runp / SECRET, api, runp / CONFIG)
        except SystemExit:
            restore_snapshot(runp)
            die(FAIL, "重载失败")
    write_userinfo(hdr, runp / USERINFO)
    clear_fetch(run)
