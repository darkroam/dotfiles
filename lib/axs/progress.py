"""Stderr progress bar. Silent off a TTY or when AXS_PROGRESS=0."""

import os
import sys

from axs.render import use_color


class Progress:
    def __init__(self, total, label):
        self.total = total
        self.label = label
        self.done = 0
        self._width = 0
        self.on = _on()

    def advance(self):
        if not self.on:
            return
        self.done += 1
        self._draw()

    def finish(self):
        if not self.on or self._width == 0:
            return
        if use_color(2):
            sys.stderr.write("\r\033[K")
        else:
            sys.stderr.write("\r" + (" " * self._width) + "\r")
        sys.stderr.flush()
        self._width = 0

    def _draw(self):
        slots = 10
        filled = 0 if self.total <= 0 else min(slots, self.done * slots // self.total)
        text = f"{self.label} [{'#' * filled}{'-' * (slots - filled)}] {self.done}/{self.total}"
        shown = f"\033[90m{text}\033[0m" if use_color(2) else text
        sys.stderr.write("\r" + shown)
        sys.stderr.flush()
        self._width = len(text)


def _on():
    if os.environ.get("AXS_PROGRESS", "").strip() == "0":
        return False
    return sys.stderr.isatty()
