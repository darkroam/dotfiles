"""Parse and write subscriptions.list. Caller holds the lock for writes."""

from pathlib import Path
from urllib.parse import urlsplit

from axs.codes import FAIL, USAGE
from axs.config import LIST, URL, atomic_write
from axs.render import die, dim, emph

HEADER = "axs-subscriptions 1"


def _sid_ok(sid):
    return len(sid) > 1 and sid[0] == "S" and sid[1] != "0" and sid[1:].isdigit()


def _header(line):
    parts = line.split(" ")
    if parts[0] != "axs-subscriptions" or parts[1:][:1] != ["1"] or len(parts) not in (2, 3):
        return None
    if len(parts) == 2:
        return 0
    token = parts[2]
    if token.isdigit() and token[0] != "0":
        return int(token)
    return None


def parse(text):
    lines = text.splitlines()
    if not lines or not text.endswith("\n"):
        die(FAIL, "订阅列表损坏")
    nxt = _header(lines[0])
    if nxt is None:
        die(FAIL, "订阅列表损坏")
    rows, seen_id, seen_url, stars = [], set(), set(), 0
    for line in lines[1:]:
        parts = line.split(" ")
        if len(parts) != 3 or parts[1] not in ("*", "-") or not _sid_ok(parts[0]):
            die(FAIL, "订阅列表损坏")
        sid, mark, url = parts
        if sid in seen_id or url in seen_url or any(ch.isspace() for ch in url):
            die(FAIL, "订阅列表损坏")
        seen_id.add(sid)
        seen_url.add(url)
        active = mark == "*"
        stars += active
        rows.append((sid, active, url))
    if rows and stars != 1:
        die(FAIL, "订阅列表损坏")
    best = max((int(sid[1:]) for sid, _active, _url in rows), default=0)
    if nxt == 0:
        nxt = best + 1
    elif nxt <= best:
        die(FAIL, "订阅列表损坏")
    return nxt, rows


def render(nxt, rows):
    lines = [HEADER + " " + str(nxt)]
    for sid, active, url in rows:
        lines.append(sid + (" * " if active else " - ") + url)
    return "\n".join(lines) + "\n"


def load(run):
    file = Path(run) / LIST
    if not file.is_file():
        return 1, []
    try:
        return parse(file.read_text(encoding="utf-8"))
    except (OSError, UnicodeError):
        die(FAIL, "订阅列表损坏")


def save(run, nxt, rows):
    atomic_write(Path(run) / LIST, render(nxt, rows))


def resolve(token):
    if len(token) > 1 and token[0] in "Ss" and token[1] != "0" and token[1:].isdigit():
        return "S" + token[1:]
    die(USAGE, "编号只认 S#")


def find(rows, token):
    sid = resolve(token)
    for row in rows:
        if row[0] == sid:
            return row
    die(FAIL, "订阅不存在")


def added(nxt, rows, url):
    if any(row[2] == url for row in rows):
        die(FAIL, "链接重复")
    return nxt + 1, rows + [("S" + str(nxt), not rows, url)]


def removed(nxt, rows, token):
    row = find(rows, token)
    if row[1]:
        die(FAIL, "先 switch")
    return nxt, [item for item in rows if item[0] != row[0]]


def activated(rows, sid):
    return [(row_id, row_id == sid, url) for row_id, _active, url in rows]


def host_of(url):
    return urlsplit(url).hostname or "-"


def has_source(run):
    run = Path(run)
    if (run / LIST).is_file():
        _nxt, rows = load(run)
        return any(row[1] for row in rows)
    return (run / URL).is_file()


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
