"""Capture the app's os.Logger output as evidence.

Verdicts do NOT come from here, and that is a deliberate limit. The app has
103 log call sites and they are overwhelmingly error-path: a missing line
cannot prove a success happened. What this is for is telling a person WHY a
check failed, in the app's own words, instead of "timed out".
"""

import re
import subprocess
import time
from dataclasses import dataclass

SUBSYSTEM = "app.murror.codepet"
PREDICATE = 'subsystem == "%s"' % SUBSYSTEM

# The real shape of `log show/stream --style compact`, e.g.
# 2026-09-24 06:52:11.936 E  codepet[4211:1604] [sub:cat] message
LINE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) "
    r"(?P<ty>\S{1,2})\s+"
    r"(?P<process>[^\[]+)\[(?P<pid>\d+):[0-9a-fA-F]+\] "
    r"\[(?P<subsystem>[^:\]]+):(?P<category>[^\]]+)\] "
    r"(?P<message>.*)$"
)

ERROR_TYPES = ("E", "F")


@dataclass
class LogLine:
    ts: str
    ty: str
    process: str
    pid: int
    subsystem: str
    category: str
    message: str

    @property
    def is_error(self):
        return self.ty in ERROR_TYPES


def parse_line(raw):
    """Return a LogLine, or None for headers and lines carrying no subsystem."""
    m = LINE.match(raw.rstrip("\n"))
    if not m:
        return None
    return LogLine(
        ts=m.group("ts"),
        ty=m.group("ty"),
        process=m.group("process").strip(),
        pid=int(m.group("pid")),
        subsystem=m.group("subsystem"),
        category=m.group("category"),
        message=m.group("message"),
    )


def parse(text):
    return [l for l in (parse_line(r) for r in text.splitlines()) if l]


def first_error(lines):
    """The one line worth putting in a Slack message."""
    for line in lines:
        if line.is_error:
            return "%s: %s" % (line.category, line.message)
    return None


class Capture:
    """Stream the app's log to a file for the life of a run."""

    def __init__(self, path, predicate=PREDICATE, argv=None):
        self.path = path
        self.argv = argv or [
            "/usr/bin/log", "stream", "--style", "compact", "--predicate", predicate
        ]
        self._proc = None
        self._fh = None

    def __enter__(self):
        self._fh = open(self.path, "w", encoding="utf-8")
        self._proc = subprocess.Popen(
            self.argv, stdout=self._fh, stderr=subprocess.STDOUT
        )
        return self

    def wait_for_output(self, timeout=10):
        """Block until the stream has written something, or give up."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.text().strip():
                return True
            time.sleep(0.2)
        return False

    def text(self):
        try:
            with open(self.path, encoding="utf-8", errors="replace") as f:
                return f.read()
        except FileNotFoundError:
            return ""

    def lines(self):
        return parse(self.text())

    def __exit__(self, *exc):
        if self._proc and self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._proc.kill()
        if self._fh:
            self._fh.close()
        return False
