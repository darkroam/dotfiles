"""Delay timeout, worker count, and HTTP reason helpers."""

import os


def workers():
    raw = os.environ.get("AXS_TEST_WORKERS", "").strip()
    try:
        value = int(raw) if raw else 8
    except ValueError:
        return 8
    return value if 1 <= value <= 32 else 8


def delay_ms():
    raw = os.environ.get("AXS_DELAY_TIMEOUT_MS", "").strip()
    try:
        value = int(raw)
    except ValueError:
        return 5000
    return value if value > 0 else 5000


def delay_timeout():
    raw = os.environ.get("AXS_DELAY_TIMEOUT", "").strip()
    try:
        value = int(raw)
    except ValueError:
        return 60
    return value if value > 0 else 60


def classify(code):
    text = code if isinstance(code, str) else ""
    prefix = "控制器失败：HTTP "
    if text.startswith(prefix):
        number = text[len(prefix):].strip()
        if number == "503":
            return "不可测"
        if number == "504":
            return "超时"
        return "HTTP " + number
    return text or "超时"
