# Smoke Test and Slack Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `smoke/`, a dependency-free Python tool that launches the real Codepet app, proves four behaviours against ground truth on disk, and reports the verdict to Slack.

**Architecture:** One check pipeline, three modes (`run`, `run --dev`, `watch`). Checks are pure functions over captured evidence — log text and LevelDB bytes — so they unit-test against fixtures. Exactly one file (`drive.py`) touches the UI, confining accessibility flakiness to a single blast radius.

**Tech Stack:** Python 3 stdlib only (`unittest`, `plistlib`, `subprocess`, `urllib`). macOS `log`, `codesign`, `xattr`, `open`, `osascript`, `pgrep`.

**Spec:** `docs/superpowers/specs/2026-09-24-smoke-test-slack-report-design.md`

## Global Constraints

- **Python 3 stdlib only.** No `pip install`, ever. `plyvel` and `fswatch` are not available and must not become prerequisites. Local Python is 3.14.4.
- **Tests are `unittest`**, run with `python3 -m unittest discover -s smoke/tests -t . -v`.
- Subsystem and bundle id are both `app.murror.codepet`.
- LevelDB lives at `~/Library/Application Support/firestore/__FIRAPP_DEFAULT/devpet-8f4b1/main`.
- **Never `defaults write`.** A leftover sandbox container silently redirects the domain and `defaults read` confirms the lie. Launch flags go through `open --args`.
- **Never `pkill`.** If the founder's app is running, defer.
- **Read the LevelDB only after the app has quit.** It holds a single-process lock.
- Statuses are exactly `pass` / `fail` / `error` / `skip`. A check that could not run is never a pass.
- One commit per task.
- Work on `feat/smoke-test`, branched from `origin/main`.

---

### Task 1: Scaffold and the Result contract

**Files:**
- Create: `smoke/lib/__init__.py`, `smoke/tests/__init__.py`, `smoke/.gitignore`
- Create: `smoke/lib/result.py`
- Test: `smoke/tests/test_result.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `PASS`, `FAIL`, `ERROR`, `SKIP`, `GREEN`, `RED`, `UNVERIFIED` (str constants); `Result(name, status, duration=0.0, detail="", evidence=[])` with `.to_dict()`; `run_verdict(results) -> str`; `skip_rest(names, reason) -> list[Result]`.

- [ ] **Step 1: Create the branch and directories**

```bash
cd ~/Developer/codepet
git fetch --prune origin
git checkout -b feat/smoke-test origin/main
mkdir -p smoke/lib smoke/checks smoke/tests
touch smoke/lib/__init__.py smoke/checks/__init__.py smoke/tests/__init__.py
printf 'runs/\n__pycache__/\n*.pyc\nwebhook.txt\n' > smoke/.gitignore
```

- [ ] **Step 2: Write the failing test**

Create `smoke/tests/test_result.py`:

```python
import unittest

from smoke.lib.result import (
    ERROR, FAIL, GREEN, PASS, RED, SKIP, UNVERIFIED,
    Result, run_verdict, skip_rest,
)


class RunVerdict(unittest.TestCase):
    def test_a_failure_makes_the_run_red(self):
        results = [Result("launch", PASS), Result("chat", FAIL)]
        self.assertEqual(run_verdict(results), RED)

    def test_a_broken_harness_is_red_not_green(self):
        # ERROR means we did not observe anything. It must not pass just
        # because no check actually reported a product defect.
        results = [Result("launch", PASS), Result("chat", ERROR)]
        self.assertEqual(run_verdict(results), RED)

    def test_everything_skipped_is_unverified_not_green(self):
        # ci-test.sh shipped reporting a non-building target as green.
        # A run that observed nothing is not a pass.
        results = [Result("launch", SKIP), Result("chat", SKIP)]
        self.assertEqual(run_verdict(results), UNVERIFIED)

    def test_all_passing_is_green(self):
        self.assertEqual(run_verdict([Result("launch", PASS)]), GREEN)


class SkipRest(unittest.TestCase):
    def test_it_names_the_reason_on_every_skipped_check(self):
        results = skip_rest(["auth", "chat"], "launch failed")
        self.assertEqual([r.name for r in results], ["auth", "chat"])
        self.assertTrue(all(r.status == SKIP for r in results))
        self.assertTrue(all(r.detail == "launch failed" for r in results))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run it and watch it fail**

Run: `cd ~/Developer/codepet && python3 -m unittest smoke.tests.test_result -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.result'`

- [ ] **Step 4: Write the implementation**

Create `smoke/lib/result.py`:

```python
"""The one record every check returns, and how a run's verdict is computed.

The four statuses are not cosmetic. scripts/ci-test.sh once reported a test
target that failed to COMPILE as a dead host -- in green, having verified
nothing at all. A check that could not run must never read as a check that
passed, so "the harness broke" and "the product broke" are different words
here, and neither of them is a pass.
"""

from dataclasses import asdict, dataclass, field

PASS = "pass"
FAIL = "fail"
ERROR = "error"
SKIP = "skip"

GREEN = "green"
RED = "red"
UNVERIFIED = "unverified"


@dataclass
class Result:
    name: str
    status: str
    duration: float = 0.0
    detail: str = ""
    evidence: list = field(default_factory=list)

    def to_dict(self):
        return asdict(self)


def run_verdict(results):
    """RED if anything failed or errored, GREEN only if something passed."""
    if any(r.status in (FAIL, ERROR) for r in results):
        return RED
    if any(r.status == PASS for r in results):
        return GREEN
    return UNVERIFIED


def skip_rest(names, reason):
    """Mark downstream checks skipped so the report names ONE broken thing."""
    return [Result(name=n, status=SKIP, detail=reason) for n in names]
```

- [ ] **Step 5: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_result -v`
Expected: `Ran 5 tests` / `OK`

- [ ] **Step 6: Commit**

```bash
git add smoke/
git commit -m "Add the smoke-test Result contract and its four statuses"
```

---

### Task 2: Log capture and parsing

**Files:**
- Create: `smoke/lib/logstream.py`
- Test: `smoke/tests/test_logstream.py`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `SUBSYSTEM`, `PREDICATE`; `LogLine(ts, ty, process, pid, subsystem, category, message)` with `.is_error`; `parse_line(raw) -> LogLine | None`; `parse(text) -> list[LogLine]`; `first_error(lines) -> str | None`; `Capture(path, predicate=PREDICATE, argv=None)` as a context manager exposing `.text()`.

**Note:** the fixture lines below are the REAL shape of `log show --style compact`, captured on 24 September from `/usr/bin/log`. The header row and kernel-shaped lines (which carry `()` instead of `[subsystem:category]`) are included deliberately, because both appear in real output and both must parse to `None`.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_logstream.py`:

```python
import os
import tempfile
import unittest

from smoke.lib.logstream import Capture, first_error, parse, parse_line

REAL = """Timestamp               Ty Process[PID:TID]
2026-09-24 06:52:11.936 E  codepet[4211:1604] [app.murror.codepet:ChatTransport] non-streaming retry refused: billing
2026-09-24 06:52:12.101 Df codepet[4211:1604] [app.murror.codepet:ChatTurn] chat turn routed to the founder's Claude Code
2026-09-24 10:59:12.476 Df kernel[0:34bf4f5] () wlan0: not our line
"""


class Parsing(unittest.TestCase):
    def test_the_header_row_is_not_a_log_line(self):
        self.assertIsNone(parse_line("Timestamp               Ty Process[PID:TID]"))

    def test_a_line_without_a_subsystem_is_not_ours(self):
        raw = "2026-09-24 10:59:12.476 Df kernel[0:34bf4f5] () wlan0: not our line"
        self.assertIsNone(parse_line(raw))

    def test_it_splits_subsystem_category_and_message(self):
        line = parse_line(
            "2026-09-24 06:52:11.936 E  codepet[4211:1604] "
            "[app.murror.codepet:ChatTransport] non-streaming retry refused: billing"
        )
        self.assertEqual(line.category, "ChatTransport")
        self.assertEqual(line.subsystem, "app.murror.codepet")
        self.assertEqual(line.message, "non-streaming retry refused: billing")
        self.assertEqual(line.pid, 4211)
        self.assertTrue(line.is_error)

    def test_a_default_line_is_not_an_error(self):
        lines = parse(REAL)
        turn = [l for l in lines if l.category == "ChatTurn"][0]
        self.assertFalse(turn.is_error)

    def test_parse_drops_the_two_unparseable_rows(self):
        self.assertEqual(len(parse(REAL)), 2)


class FirstError(unittest.TestCase):
    def test_it_reports_category_and_message(self):
        self.assertEqual(
            first_error(parse(REAL)),
            "ChatTransport: non-streaming retry refused: billing",
        )

    def test_it_is_none_when_nothing_went_wrong(self):
        clean = parse(
            "2026-09-24 06:52:12.101 Df codepet[4211:1604] "
            "[app.murror.codepet:ChatTurn] all good\n"
        )
        self.assertIsNone(first_error(clean))


class CaptureToFile(unittest.TestCase):
    def test_it_writes_the_subprocess_output_and_stops_it(self):
        # argv is injectable precisely so this test needs no real app.
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "log.txt")
            with Capture(path, argv=["/bin/sh", "-c", "echo hello; sleep 30"]) as cap:
                cap.wait_for_output(timeout=5)
            self.assertIn("hello", cap.text())


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_logstream -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.logstream'`

- [ ] **Step 3: Write the implementation**

Create `smoke/lib/logstream.py`:

```python
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

ERROR_TYPES = ("E", "Er", "Fa")


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
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_logstream -v`
Expected: `Ran 8 tests` / `OK`

- [ ] **Step 5: Verify the regex against live output, not just the fixture**

Run:

```bash
python3 -c "
from smoke.lib.logstream import parse
import subprocess
out = subprocess.run(['/usr/bin/log','show','--last','6h','--style','compact',
                      '--predicate','subsystem == \"com.apple.dock\"'],
                     capture_output=True, text=True).stdout
print('parsed', len(parse(out)), 'of', len(out.splitlines()), 'raw lines')
"
```

Expected: a non-zero parsed count. If it prints `parsed 0`, the regex does not match real output and must be fixed before proceeding — the fixture is not the authority, the live format is.

- [ ] **Step 6: Commit**

```bash
git add smoke/lib/logstream.py smoke/tests/test_logstream.py
git commit -m "Capture and parse the app's os.Logger output as run evidence"
```

---

### Task 3: LevelDB presence scanning

**Files:**
- Create: `smoke/lib/store.py`
- Test: `smoke/tests/test_store.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `DEFAULT_DB` (str); `data_files(db_dir) -> list[str]`; `contains(db_dir, needle: bytes, chunk=CHUNK) -> bool`; `count(db_dir, needle: bytes) -> int`; `wait_for(db_dir, needle, timeout, interval=2.0, sleep=time.sleep, now=time.monotonic) -> bool`; `StoreMissing(Exception)`.

**Verified, not assumed:** on 24 September a scan of the live database found `nguyen@murror.app` 3 times and `projects/` 217 times across 2,774,671 bytes, instantly. The approach works and the auth needle exists.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_store.py`:

```python
import os
import tempfile
import unittest

from smoke.lib.store import StoreMissing, contains, count, data_files, wait_for


class DataFiles(unittest.TestCase):
    def test_it_takes_ldb_and_log_and_ignores_the_rest(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ("001.ldb", "002.log", "CURRENT", "LOCK", "LOG"):
                open(os.path.join(d, name), "wb").close()
            self.assertEqual(
                [os.path.basename(p) for p in data_files(d)], ["001.ldb", "002.log"]
            )

    def test_a_missing_database_raises_rather_than_reporting_absence(self):
        # Absence of the DB is a harness ERROR, not a product FAIL. Returning
        # False here would quietly turn "we could not look" into "not there".
        with self.assertRaises(StoreMissing):
            contains("/no/such/db", b"anything")


class Contains(unittest.TestCase):
    def test_it_finds_a_token_in_an_ldb_file(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "001.ldb"), "wb") as f:
                f.write(b"\x00\x01junk smoke-f3a91c junk\xff")
            self.assertTrue(contains(d, b"smoke-f3a91c"))

    def test_it_does_not_find_what_is_not_there(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "001.ldb"), "wb") as f:
                f.write(b"nothing of interest")
            self.assertFalse(contains(d, b"smoke-f3a91c"))

    def test_it_finds_a_token_split_across_a_chunk_boundary(self):
        # The bug this guards: reading in chunks without carrying an overlap
        # misses any needle that straddles two reads, and the check then
        # reports a working app as broken.
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "001.ldb"), "wb") as f:
                f.write(b"aaaa" + b"TOKEN" + b"bbbb")
            self.assertTrue(contains(d, b"TOKEN", chunk=4))

    def test_an_empty_needle_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "001.ldb"), "wb").close()
            with self.assertRaises(ValueError):
                contains(d, b"")


class Count(unittest.TestCase):
    def test_it_totals_across_files(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "001.ldb"), "wb") as f:
                f.write(b"X X")
            with open(os.path.join(d, "002.log"), "wb") as f:
                f.write(b"X")
            self.assertEqual(count(d, b"X"), 3)


class WaitFor(unittest.TestCase):
    def test_it_returns_as_soon_as_the_needle_lands(self):
        # Raw byte reads do not take LevelDB's lock, so we can poll while the
        # app is still running instead of paying a fixed 90s sleep.
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "001.ldb")
            open(path, "wb").close()
            slept = []

            def fake_sleep(seconds):
                slept.append(seconds)
                if len(slept) == 2:
                    with open(path, "wb") as f:
                        f.write(b"smoke-f3a91c")

            ticks = iter([0.0, 2.0, 4.0, 6.0, 8.0])
            self.assertTrue(
                wait_for(d, b"smoke-f3a91c", timeout=30, interval=2.0,
                         sleep=fake_sleep, now=lambda: next(ticks))
            )
            self.assertEqual(len(slept), 2)

    def test_it_gives_up_at_the_deadline(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "001.ldb"), "wb").close()
            ticks = iter([0.0, 5.0, 11.0])
            self.assertFalse(
                wait_for(d, b"never", timeout=10, interval=1.0,
                         sleep=lambda s: None, now=lambda: next(ticks))
            )


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_store -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.store'`

- [ ] **Step 3: Write the implementation**

Create `smoke/lib/store.py`:

```python
"""Presence questions against the Firestore LevelDB, without a LevelDB client.

plyvel is not installed and does not become a prerequisite, so this does not
speak the LevelDB protocol. It scans the .ldb and .log files for byte patterns.

The limit is stated rather than discovered: this proves a value IS PRESENT.
It cannot prove structure, cannot read a value it was not told to look for,
and will see a key a compaction has tombstoned but not yet removed. That is
enough because every question asked here is about a token this run just
minted, which cannot pre-exist the run.

If a future check needs to read STATE rather than confirm presence, this is
the seam to replace, and plyvel becomes the honest answer at that point.
"""

import glob
import os
import time

DEFAULT_DB = os.path.expanduser(
    "~/Library/Application Support/firestore/__FIRAPP_DEFAULT/devpet-8f4b1/main"
)

DATA_SUFFIXES = (".ldb", ".log")
CHUNK = 1 << 20


class StoreMissing(Exception):
    """The database is not where we expected. We could not look."""


def data_files(db_dir):
    if not os.path.isdir(db_dir):
        raise StoreMissing(db_dir)
    found = []
    for suffix in DATA_SUFFIXES:
        found.extend(glob.glob(os.path.join(db_dir, "*" + suffix)))
    return sorted(found)


def _file_contains(path, needle, chunk):
    overlap = len(needle) - 1
    tail = b""
    with open(path, "rb") as f:
        while True:
            block = f.read(chunk)
            if not block:
                return False
            if needle in tail + block:
                return True
            tail = (tail + block)[-overlap:] if overlap else b""


def contains(db_dir, needle, chunk=CHUNK):
    if not needle:
        raise ValueError("an empty needle matches everything")
    return any(_file_contains(p, needle, chunk) for p in data_files(db_dir))


def count(db_dir, needle):
    if not needle:
        raise ValueError("an empty needle matches everything")
    total = 0
    for path in data_files(db_dir):
        with open(path, "rb") as f:
            total += f.read().count(needle)
    return total


def wait_for(db_dir, needle, timeout, interval=2.0, sleep=time.sleep, now=time.monotonic):
    """Poll until the needle appears, or the deadline passes.

    Reading the raw .ldb/.log bytes does NOT take LevelDB's lock -- that lock
    guards opening the database, not reading its files -- so this can run
    while the app is still up. What a live read can be is STALE: a write
    still sitting in the memtable is not on disk yet. So a True here is
    trustworthy and a False is not, which is why callers quit the app and
    read once more before calling it a failure.
    """
    deadline = now() + timeout
    while True:
        if contains(db_dir, needle):
            return True
        if now() >= deadline:
            return False
        sleep(interval)
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_store -v`
Expected: `Ran 9 tests` / `OK`

- [ ] **Step 5: Prove it against the real database**

Run:

```bash
python3 -c "
from smoke.lib.store import DEFAULT_DB, count
print('email hits:', count(DEFAULT_DB, b'nguyen@murror.app'))
"
```

Expected: a non-zero count (3 on 24 September). A zero here means the auth check in Task 7 has no needle and the account identifier must be re-derived before continuing.

- [ ] **Step 6: Commit**

```bash
git add smoke/lib/store.py smoke/tests/test_store.py
git commit -m "Scan the Firestore LevelDB for presence without a LevelDB client"
```

---

### Task 4: Build identity

**Files:**
- Create: `smoke/lib/build.py`
- Test: `smoke/tests/test_build.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `Build(path, short_version, bundle_version, bundle_id, signed, signature, quarantined, mtime)` with `.label()` and `.to_dict()`; `read_info(app_path) -> dict`; `parse_codesign(returncode, stderr) -> (bool, str)`; `parse_quarantine(xattr_stdout) -> bool`; `identify(app_path) -> Build`; `BuildMissing(Exception)`.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_build.py`:

```python
import os
import plistlib
import tempfile
import unittest

from smoke.lib.build import (
    Build, BuildMissing, identify, parse_codesign, parse_quarantine, read_info,
)


def make_bundle(d, short="1.0", version="2"):
    contents = os.path.join(d, "codepet.app", "Contents")
    os.makedirs(contents)
    with open(os.path.join(contents, "Info.plist"), "wb") as f:
        plistlib.dump(
            {
                "CFBundleShortVersionString": short,
                "CFBundleVersion": version,
                "CFBundleIdentifier": "app.murror.codepet",
            },
            f,
        )
    return os.path.join(d, "codepet.app")


class Codesign(unittest.TestCase):
    def test_silence_and_zero_means_valid(self):
        self.assertEqual(parse_codesign(0, ""), (True, "valid on disk"))

    def test_it_keeps_the_first_line_of_the_real_complaint(self):
        signed, detail = parse_codesign(
            1, "codepet.app: code object is not signed at all\nIn architecture: arm64\n"
        )
        self.assertFalse(signed)
        self.assertEqual(detail, "codepet.app: code object is not signed at all")

    def test_a_failure_with_no_message_still_says_something(self):
        self.assertEqual(parse_codesign(1, "   \n"), (False, "unknown signing failure"))


class Quarantine(unittest.TestCase):
    def test_it_detects_the_gatekeeper_flag(self):
        self.assertTrue(parse_quarantine("com.apple.quarantine\ncom.apple.macl\n"))

    def test_no_attributes_means_not_quarantined(self):
        self.assertFalse(parse_quarantine(""))


class Identity(unittest.TestCase):
    def test_it_reads_the_bundle_and_labels_it(self):
        with tempfile.TemporaryDirectory() as d:
            app = make_bundle(d)
            info = read_info(app)
            self.assertEqual(info["CFBundleIdentifier"], "app.murror.codepet")
            b = Build(app, "1.0", "2", "app.murror.codepet", True, "ok", False, 0.0)
            self.assertEqual(b.label(), "1.0 (2)")

    def test_a_missing_bundle_raises(self):
        with self.assertRaises(BuildMissing):
            identify("/Applications/NoSuchThing.app")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_build -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.build'`

- [ ] **Step 3: Write the implementation**

Create `smoke/lib/build.py`:

```python
"""Identify the binary under test. Every report states which build it judged.

The mtime is read from Info.plist because that is what changes on a rebuild,
and because "still looks the same" has meant "you are testing yesterday's
binary" often enough in this project to be worth a machine check.
"""

import os
import plistlib
import subprocess
from dataclasses import asdict, dataclass


class BuildMissing(Exception):
    """There is no app bundle at that path."""


@dataclass
class Build:
    path: str
    short_version: str
    bundle_version: str
    bundle_id: str
    signed: bool
    signature: str
    quarantined: bool
    mtime: float

    def label(self):
        return "%s (%s)" % (self.short_version, self.bundle_version)

    def to_dict(self):
        return asdict(self)


def _info_path(app_path):
    return os.path.join(app_path, "Contents", "Info.plist")


def read_info(app_path):
    try:
        with open(_info_path(app_path), "rb") as f:
            return plistlib.load(f)
    except FileNotFoundError:
        raise BuildMissing(app_path)


def parse_codesign(returncode, stderr):
    """`codesign -v` exits 0 and says nothing at all when the bundle is valid."""
    if returncode == 0:
        return True, "valid on disk"
    lines = [l.strip() for l in (stderr or "").splitlines() if l.strip()]
    return False, lines[0] if lines else "unknown signing failure"


def parse_quarantine(xattr_stdout):
    return "com.apple.quarantine" in (xattr_stdout or "")


def identify(app_path):
    info = read_info(app_path)
    cs = subprocess.run(
        ["/usr/bin/codesign", "-v", app_path], capture_output=True, text=True
    )
    signed, signature = parse_codesign(cs.returncode, cs.stderr)
    xa = subprocess.run(["/usr/bin/xattr", app_path], capture_output=True, text=True)
    return Build(
        path=app_path,
        short_version=str(info.get("CFBundleShortVersionString", "?")),
        bundle_version=str(info.get("CFBundleVersion", "?")),
        bundle_id=str(info.get("CFBundleIdentifier", "?")),
        signed=signed,
        signature=signature,
        quarantined=parse_quarantine(xa.stdout),
        mtime=os.path.getmtime(_info_path(app_path)),
    )
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_build -v`
Expected: `Ran 7 tests` / `OK`

- [ ] **Step 5: Commit**

```bash
git add smoke/lib/build.py smoke/tests/test_build.py
git commit -m "Identify the build under test: version, signature, quarantine, mtime"
```

---

### Task 5: The UI driver

**Files:**
- Create: `smoke/lib/drive.py`
- Test: `smoke/tests/test_drive.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `BUNDLE_ID`, `PROCESS_NAME`; `DriveError(Exception)`; `as_applescript_string(text) -> str`; `osascript(script, timeout=20) -> str`; `launch(app_path, args=()) -> None`; `is_running() -> bool`; `pid() -> int | None`; `window_count() -> int`; `quit_app(timeout=20) -> bool`; `wait_until(predicate, timeout, interval=0.5) -> bool`; `screenshot(path) -> bool`.

**Why this file is small:** it is the only place that touches the UI. `count windows` has reported 0 while the app was visibly on screen, and assistive access can drop mid-session, so every assertion added here is a future false red. Keep it to launch, focus, type, Enter.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_drive.py`:

```python
import unittest

from smoke.lib.drive import as_applescript_string, wait_until


class Escaping(unittest.TestCase):
    def test_a_plain_string_is_quoted(self):
        self.assertEqual(as_applescript_string("hello"), '"hello"')

    def test_double_quotes_are_escaped(self):
        # Unescaped, this ends the AppleScript string early and the rest of
        # the probe becomes syntax -- the script fails for a reason that has
        # nothing to do with the app.
        self.assertEqual(as_applescript_string('say "hi"'), '"say \\"hi\\""')

    def test_backslashes_are_escaped_before_quotes(self):
        self.assertEqual(as_applescript_string("a\\b"), '"a\\\\b"')


class WaitUntil(unittest.TestCase):
    def test_it_returns_true_as_soon_as_the_predicate_holds(self):
        calls = {"n": 0}

        def ready():
            calls["n"] += 1
            return calls["n"] >= 2

        self.assertTrue(wait_until(ready, timeout=5, interval=0.01))
        self.assertEqual(calls["n"], 2)

    def test_it_gives_up_and_says_so(self):
        self.assertFalse(wait_until(lambda: False, timeout=0.2, interval=0.05))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_drive -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.drive'`

- [ ] **Step 3: Write the implementation**

Create `smoke/lib/drive.py`:

```python
"""The ONLY file that drives the UI.

`count windows` has reported 0 while the app was visibly on screen, and
assistive access can drop mid-session. So this file does the smallest thing
the four checks allow -- launch, focus, type, Enter -- and every failure it
raises is a DriveError, which callers translate to ERROR rather than FAIL.
We could not observe; that is not the same as the app being broken.

Launch flags go through `open --args`, never `defaults write`: a leftover
sandbox container silently redirects the app.murror.codepet domain, and
`defaults read` then confirms the lie.
"""

import subprocess
import time

BUNDLE_ID = "app.murror.codepet"
PROCESS_NAME = "codepet"


class DriveError(RuntimeError):
    """The harness could not drive the app. Not a product defect."""


def as_applescript_string(text):
    """Quote a Python string so AppleScript sees exactly these characters."""
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % escaped


def osascript(script, timeout=20):
    try:
        p = subprocess.run(
            ["/usr/bin/osascript", "-e", script],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise DriveError("osascript timed out after %ss" % timeout)
    if p.returncode != 0:
        raise DriveError((p.stderr or "osascript failed").strip().splitlines()[0])
    return p.stdout.strip()


def wait_until(predicate, timeout, interval=0.5):
    deadline = time.time() + timeout
    while True:
        if predicate():
            return True
        if time.time() >= deadline:
            return False
        time.sleep(interval)


def launch(app_path, args=()):
    cmd = ["/usr/bin/open", "-a", app_path]
    if args:
        cmd.append("--args")
        cmd.extend(args)
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise DriveError((p.stderr or "open failed").strip())


def is_running():
    return subprocess.run(
        ["/usr/bin/pgrep", "-x", PROCESS_NAME], capture_output=True
    ).returncode == 0


def pid():
    p = subprocess.run(["/usr/bin/pgrep", "-x", PROCESS_NAME], capture_output=True, text=True)
    if p.returncode != 0:
        return None
    return int(p.stdout.split()[0])


def window_count():
    """Best effort. A 0 here is NOT proof of no window -- see module docstring."""
    try:
        out = osascript(
            'tell application "System Events" to count windows of '
            'application process %s' % as_applescript_string(PROCESS_NAME)
        )
        return int(out or 0)
    except (DriveError, ValueError):
        return 0


def focus():
    osascript('tell application id %s to activate' % as_applescript_string(BUNDLE_ID))


def type_text(text):
    osascript(
        'tell application "System Events" to keystroke %s' % as_applescript_string(text)
    )


def press_enter():
    osascript('tell application "System Events" to key code 36')


def quit_app(timeout=20):
    """Ask nicely. Never pkill -- a sibling session may own this app."""
    if not is_running():
        return True
    try:
        osascript('tell application id %s to quit' % as_applescript_string(BUNDLE_ID))
    except DriveError:
        pass
    return wait_until(lambda: not is_running(), timeout=timeout)


def screenshot(path):
    return subprocess.run(
        ["/usr/sbin/screencapture", "-x", "-o", path], capture_output=True
    ).returncode == 0
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_drive -v`
Expected: `Ran 5 tests` / `OK`

- [ ] **Step 5: Commit**

```bash
git add smoke/lib/drive.py smoke/tests/test_drive.py
git commit -m "Add the UI driver, confined to launch, focus, type and Enter"
```

---

### Task 6: The launch check

**Files:**
- Create: `smoke/checks/launch.py`
- Test: `smoke/tests/test_check_launch.py`

**Interfaces:**
- Consumes: `Result`, `PASS`/`FAIL`/`ERROR` from `smoke.lib.result`; `Build` from `smoke.lib.build`; `drive`.
- Produces: `evaluate(build, opened, process_seen, window_seen, elapsed) -> Result`; `run(app_path, timeout=45, evidence_dir=None) -> Result`.

**The key judgement:** if the process is alive but System Events reports no window for the whole timeout, that is `ERROR`, not `FAIL`. `count windows` returning 0 for a visible app is a known lie in this environment, and a known lie must not be allowed to manufacture a red build.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_check_launch.py`:

```python
import unittest

from smoke.checks.launch import evaluate
from smoke.lib.build import Build
from smoke.lib.result import ERROR, FAIL, PASS


def build(signed=True, quarantined=False):
    return Build(
        path="/Applications/codepet.app", short_version="1.0", bundle_version="2",
        bundle_id="app.murror.codepet", signed=signed,
        signature="valid on disk" if signed else "code object is not signed at all",
        quarantined=quarantined, mtime=0.0,
    )


class Evaluate(unittest.TestCase):
    def test_a_good_launch_passes_and_says_how_fast(self):
        r = evaluate(build(), opened=True, process_seen=True, window_seen=True, elapsed=3.1)
        self.assertEqual(r.status, PASS)
        self.assertEqual(r.detail, "signed, not quarantined, window in 3.1s")

    def test_a_broken_signature_fails_before_anything_is_opened(self):
        r = evaluate(build(signed=False), opened=False, process_seen=False,
                     window_seen=False, elapsed=0.0)
        self.assertEqual(r.status, FAIL)
        self.assertIn("not signed", r.detail)

    def test_quarantine_fails_with_gatekeeper_named(self):
        r = evaluate(build(quarantined=True), opened=False, process_seen=False,
                     window_seen=False, elapsed=0.0)
        self.assertEqual(r.status, FAIL)
        self.assertIn("Gatekeeper", r.detail)

    def test_a_process_that_never_appeared_is_a_real_failure(self):
        r = evaluate(build(), opened=True, process_seen=False, window_seen=False, elapsed=45.0)
        self.assertEqual(r.status, FAIL)
        self.assertIn("no process", r.detail)

    def test_a_live_process_with_no_window_is_unobserved_not_broken(self):
        # count windows has reported 0 for a visibly open app. Calling that
        # FAIL would let a known lie manufacture a red build.
        r = evaluate(build(), opened=True, process_seen=True, window_seen=False, elapsed=45.0)
        self.assertEqual(r.status, ERROR)
        self.assertIn("0 windows", r.detail)

    def test_open_itself_failing_is_a_harness_error(self):
        r = evaluate(build(), opened=False, process_seen=False, window_seen=False,
                     elapsed=0.0)
        self.assertEqual(r.status, ERROR)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_check_launch -v`
Expected: `ModuleNotFoundError: No module named 'smoke.checks.launch'`

- [ ] **Step 3: Write the implementation**

Create `smoke/checks/launch.py`:

```python
"""Check 1 -- does the shipped artefact start at all?

Signature and quarantine are read BEFORE the app is opened. Gatekeeper is the
likeliest failure for a downloaded build and deserves its own sentence rather
than arriving disguised as a launch timeout.
"""

import os
import time

from smoke.lib import build as build_lib
from smoke.lib import drive
from smoke.lib.result import ERROR, FAIL, PASS, Result

NAME = "launch"


def evaluate(build, opened, process_seen, window_seen, elapsed):
    if not build.signed:
        return Result(NAME, FAIL, elapsed, "not signed: %s" % build.signature)
    if build.quarantined:
        return Result(NAME, FAIL, elapsed,
                      "quarantined -- Gatekeeper will block the first launch")
    if not opened:
        return Result(NAME, ERROR, elapsed, "could not ask the system to open the app")
    if not process_seen:
        return Result(NAME, FAIL, elapsed, "no process after %.0fs" % elapsed)
    if not window_seen:
        return Result(NAME, ERROR, elapsed,
                      "process alive but System Events reported 0 windows -- "
                      "assistive access may have dropped")
    return Result(NAME, PASS, elapsed, "signed, not quarantined, window in %.1fs" % elapsed)


def run(app_path, timeout=45, evidence_dir=None):
    started = time.time()
    try:
        target = build_lib.identify(app_path)
    except build_lib.BuildMissing:
        return Result(NAME, ERROR, 0.0, "no app bundle at %s" % app_path)

    if not target.signed or target.quarantined:
        return evaluate(target, False, False, False, time.time() - started)

    try:
        drive.launch(app_path)
        opened = True
    except drive.DriveError as e:
        return evaluate(target, False, False, False, time.time() - started)

    process_seen = drive.wait_until(drive.is_running, timeout=timeout)
    window_seen = process_seen and drive.wait_until(
        lambda: drive.window_count() > 0, timeout=timeout
    )
    result = evaluate(target, opened, process_seen, window_seen, time.time() - started)

    # A screenshot is worth more than the sentence "0 windows", and it must be
    # taken NOW -- after teardown there is nothing left to photograph.
    if evidence_dir and result.status != PASS and process_seen:
        shot = os.path.join(evidence_dir, "launch.png")
        if drive.screenshot(shot):
            result.evidence.append(shot)
    return result
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_check_launch -v`
Expected: `Ran 6 tests` / `OK`

- [ ] **Step 5: Commit**

```bash
git add smoke/checks/launch.py smoke/tests/test_check_launch.py
git commit -m "Add the launch check, with a 0-window read treated as unobserved"
```

---

### Task 7: The auth check

**Files:**
- Create: `smoke/checks/auth.py`
- Test: `smoke/tests/test_check_auth.py`

**Interfaces:**
- Consumes: `Result` constants; `smoke.lib.store`.
- Produces: `evaluate(found, account) -> Result`; `run(account, db_dir=store.DEFAULT_DB) -> Result`.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_check_auth.py`:

```python
import unittest

from smoke.checks.auth import evaluate, run
from smoke.lib.result import ERROR, FAIL, PASS


class Evaluate(unittest.TestCase):
    def test_a_persisted_account_passes_and_names_it(self):
        r = evaluate(found=True, account="nguyen@murror.app")
        self.assertEqual(r.status, PASS)
        self.assertEqual(r.detail, "session restored for nguyen@murror.app")

    def test_no_account_in_the_store_is_a_real_failure(self):
        r = evaluate(found=False, account="nguyen@murror.app")
        self.assertEqual(r.status, FAIL)
        self.assertIn("no session", r.detail)


class Run(unittest.TestCase):
    def test_a_missing_database_is_an_error_not_a_failure(self):
        # We could not look. That is not evidence of a signed-out app.
        r = run("nguyen@murror.app", db_dir="/no/such/db")
        self.assertEqual(r.status, ERROR)
        self.assertIn("no database", r.detail)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_check_auth -v`
Expected: `ModuleNotFoundError: No module named 'smoke.checks.auth'`

- [ ] **Step 3: Write the implementation**

Create `smoke/checks/auth.py`:

```python
"""Check 2 -- did the session survive to the store?

Read AFTER the app quits. LevelDB holds a single-process lock, and reading
underneath a live app is how this codebase has produced phantom results.

The needle is the account email, which a scan of the live database on
24 September found 3 times. No screen-scraping, no keychain poking.
"""

import time

from smoke.lib import store
from smoke.lib.result import ERROR, FAIL, PASS, Result

NAME = "auth"


def evaluate(found, account):
    if found:
        return Result(NAME, PASS, 0.0, "session restored for %s" % account)
    return Result(NAME, FAIL, 0.0, "no session for %s in the local store" % account)


def run(account, db_dir=store.DEFAULT_DB):
    started = time.time()
    try:
        found = store.contains(db_dir, account.encode("utf-8"))
    except store.StoreMissing:
        return Result(NAME, ERROR, time.time() - started, "no database at %s" % db_dir)
    result = evaluate(found, account)
    result.duration = time.time() - started
    return result
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_check_auth -v`
Expected: `Ran 3 tests` / `OK`

- [ ] **Step 5: Commit**

```bash
git add smoke/checks/auth.py smoke/tests/test_check_auth.py
git commit -m "Add the auth check, reading the store only after the app quits"
```

---

### Task 8: The chat round-trip check

**Files:**
- Create: `smoke/checks/chat.py`
- Test: `smoke/tests/test_check_chat.py`

**Interfaces:**
- Consumes: `Result` constants; `smoke.lib.store`, `smoke.lib.drive`, `smoke.lib.logstream`.
- Produces: `mint_token() -> str`; `probe_text(token) -> str`; `reply_needle(token) -> bytes`; `evaluate(sent, probe_persisted, reply_persisted, token, log_error) -> Result`; `run(token, capture, db_dir=store.DEFAULT_DB, timeout=90) -> Result`.

**Why the needle is the token reversed:** the check must prove *a reply came back*, not merely that our own message was saved. If the needle appeared in the probe we typed, finding it would prove nothing. The probe asks for the code written backwards, so `321cba` can only exist in the store if something replied.

If model compliance proves flaky in practice, the documented fallback is two weaker signals together — probe persisted **and** a completed `ChatTurn` with no `ChatTransport` error — but start strict, because a strict check that occasionally errors is better than a loose one that is always green.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_check_chat.py`:

```python
import unittest

from smoke.checks.chat import evaluate, mint_token, probe_text, reply_needle
from smoke.lib.result import ERROR, FAIL, PASS


class Probe(unittest.TestCase):
    def test_a_token_is_unique_per_run(self):
        self.assertNotEqual(mint_token(), mint_token())

    def test_the_reply_needle_does_not_appear_in_the_probe_we_type(self):
        # If it did, finding it would prove our own message was saved --
        # not that anything replied.
        token = "abc123"
        self.assertNotIn(reply_needle(token).decode(), probe_text(token))

    def test_the_needle_is_the_token_backwards(self):
        self.assertEqual(reply_needle("abc123"), b"321cba")


class Evaluate(unittest.TestCase):
    def test_a_reply_that_reached_the_store_passes(self):
        r = evaluate(sent=True, probe_persisted=True, reply_persisted=True,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, PASS)

    def test_no_reply_fails_and_quotes_the_app(self):
        r = evaluate(sent=True, probe_persisted=True, reply_persisted=False,
                     token="f3a91c",
                     log_error="ChatTransport: non-streaming retry refused: billing")
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)
        self.assertIn("ChatTransport", r.evidence[0])

    def test_a_probe_that_never_persisted_means_we_never_typed_it(self):
        # Our own message not reaching the store means the UI never received
        # the keystrokes -- a harness problem, not a broken chat pipeline.
        r = evaluate(sent=True, probe_persisted=False, reply_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)
        self.assertIn("never reached", r.detail)

    def test_failing_to_type_at_all_is_an_error(self):
        r = evaluate(sent=False, probe_persisted=False, reply_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_check_chat -v`
Expected: `ModuleNotFoundError: No module named 'smoke.checks.chat'`

- [ ] **Step 3: Write the implementation**

Create `smoke/checks/chat.py`:

```python
"""Check 3 -- does a chat turn round-trip through the deployed functions?

This is the check that proves app -> functions -> model -> back, which no
unit test can: CompanyStore is driven through injected closures, and the
deployed functions read their key from Secret Manager, so chat can die in
production while every local test is green.

The verdict needle is the run token REVERSED. The probe we type contains the
token; only a genuine reply can contain it backwards. A needle present in our
own message would prove nothing.
"""

import time
import uuid

from smoke.lib import drive, store
from smoke.lib.logstream import first_error
from smoke.lib.result import ERROR, FAIL, PASS, Result

NAME = "chat"


def mint_token():
    return uuid.uuid4().hex[:6]


def probe_text(token):
    return (
        "smoke test %s -- reply with this code written backwards, nothing else: %s"
        % (token, token)
    )


def reply_needle(token):
    return token[::-1].encode("utf-8")


def evaluate(sent, probe_persisted, reply_persisted, token, log_error):
    evidence = [log_error] if log_error else []
    if not sent:
        return Result(NAME, ERROR, 0.0, "could not type the probe into the app", evidence)
    if not probe_persisted:
        return Result(NAME, ERROR, 0.0,
                      "the probe never reached the store -- the app did not receive "
                      "the keystrokes", evidence)
    if not reply_persisted:
        return Result(NAME, FAIL, 0.0,
                      "no reply persisted for probe %s" % token, evidence)
    return Result(NAME, PASS, 0.0, "reply round-tripped for probe %s" % token, evidence)


def run(token, capture, db_dir=store.DEFAULT_DB, timeout=90):
    started = time.time()
    sent = False
    try:
        drive.focus()
        drive.type_text(probe_text(token))
        drive.press_enter()
        sent = True
    except drive.DriveError as e:
        result = evaluate(False, False, False, token, str(e))
        result.duration = time.time() - started
        return result

    # Poll the raw files while the app runs -- a hit is trustworthy and
    # returns in seconds. Then quit and read ONCE more, because a miss may
    # only mean the write is still in the memtable.
    try:
        reply_persisted = store.wait_for(db_dir, reply_needle(token), timeout=timeout)
        drive.quit_app()
        if not reply_persisted:
            reply_persisted = store.contains(db_dir, reply_needle(token))
        probe_persisted = store.contains(db_dir, token.encode("utf-8"))
    except store.StoreMissing:
        result = Result(NAME, ERROR, time.time() - started, "no database at %s" % db_dir)
        return result

    result = evaluate(sent, probe_persisted, reply_persisted, token,
                      first_error(capture.lines()))
    result.duration = time.time() - started
    return result
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_check_chat -v`
Expected: `Ran 7 tests` / `OK`

- [ ] **Step 5: Commit**

```bash
git add smoke/checks/chat.py smoke/tests/test_check_chat.py
git commit -m "Add the chat round-trip check, proved by a reversed-token reply"
```

---

### Task 9: The task-run check

**Files:**
- Create: `smoke/checks/task.py`
- Test: `smoke/tests/test_check_task.py`

**Interfaces:**
- Consumes: `Result` constants; `smoke.lib.store`, `smoke.lib.drive`, `smoke.lib.logstream`.
- Produces: `evaluate(requested, sent, deliverable_persisted, token, log_error) -> Result`; `run(token, capture, requested, db_dir=store.DEFAULT_DB, timeout=300) -> Result`.

**Opt-in.** It spends real credits, so the runner only calls it with `--with-task`, and watch mode never does. When not requested it returns `SKIP` — and `SKIP` must not colour the run.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_check_task.py`:

```python
import unittest

from smoke.checks.task import deliverable_needle, evaluate, probe_text
from smoke.lib.result import ERROR, FAIL, PASS, SKIP


class Needle(unittest.TestCase):
    def test_it_is_token_scoped_not_the_bare_word(self):
        # "deliverable" alone had 15 hits in the live store before any run.
        self.assertEqual(deliverable_needle("abc123"), b"smoke-deliverable-321cba")

    def test_the_needle_does_not_appear_in_the_probe_we_type(self):
        token = "abc123"
        self.assertNotIn(deliverable_needle(token).decode(), probe_text(token))


class Evaluate(unittest.TestCase):
    def test_not_requested_is_skipped_and_says_why(self):
        r = evaluate(requested=False, sent=False, deliverable_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, SKIP)
        self.assertIn("--with-task", r.detail)

    def test_a_deliverable_in_the_store_passes(self):
        r = evaluate(requested=True, sent=True, deliverable_persisted=True,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, PASS)

    def test_no_deliverable_fails(self):
        r = evaluate(requested=True, sent=True, deliverable_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)

    def test_failing_to_drive_it_is_an_error(self):
        r = evaluate(requested=True, sent=False, deliverable_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_check_task -v`
Expected: `ModuleNotFoundError: No module named 'smoke.checks.task'`

- [ ] **Step 3: Write the implementation**

Create `smoke/checks/task.py`:

```python
"""Check 4 -- does a task run to a deliverable?

Opt-in, because it spends real credits on every run. Watch mode never calls
it with requested=True.
"""

import time

from smoke.lib import drive, store
from smoke.lib.logstream import first_error
from smoke.lib.result import ERROR, FAIL, PASS, SKIP, Result

NAME = "task"


def probe_text(token):
    return (
        "smoke test %s -- run a small task and title its deliverable "
        "'smoke-deliverable-' followed by this code written backwards: %s"
        % (token, token)
    )


def deliverable_needle(token):
    """Token-scoped, and reversed so the probe we type cannot contain it.

    The first draft of this check searched for the bare word "deliverable".
    A scan of the live store on 24 September found it 15 times ALREADY, so
    the check would have reported PASS against a completely broken task
    pipeline -- green, forever, and believed.
    """
    return ("smoke-deliverable-" + token[::-1]).encode("utf-8")


def evaluate(requested, sent, deliverable_persisted, token, log_error):
    evidence = [log_error] if log_error else []
    if not requested:
        return Result(NAME, SKIP, 0.0, "not requested (pass --with-task to spend credits)")
    if not sent:
        return Result(NAME, ERROR, 0.0, "could not ask the app to run a task", evidence)
    if not deliverable_persisted:
        return Result(NAME, FAIL, 0.0,
                      "no deliverable persisted for task probe %s" % token, evidence)
    return Result(NAME, PASS, 0.0, "task reached a deliverable for %s" % token, evidence)


def run(token, capture, requested, db_dir=store.DEFAULT_DB, timeout=300):
    if not requested:
        return evaluate(False, False, False, token, None)

    started = time.time()
    sent = False
    try:
        drive.focus()
        drive.type_text(probe_text(token))
        drive.press_enter()
        sent = True
    except drive.DriveError as e:
        result = evaluate(True, False, False, token, str(e))
        result.duration = time.time() - started
        return result

    try:
        persisted = store.wait_for(db_dir, deliverable_needle(token), timeout=timeout)
        drive.quit_app()
        if not persisted:
            persisted = store.contains(db_dir, deliverable_needle(token))
    except store.StoreMissing:
        return Result(NAME, ERROR, time.time() - started, "no database at %s" % db_dir)

    result = evaluate(True, sent, persisted, token, first_error(capture.lines()))
    result.duration = time.time() - started
    return result
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_check_task -v`
Expected: `Ran 6 tests` / `OK`

- [ ] **Step 5: Commit**

```bash
git add smoke/checks/task.py smoke/tests/test_check_task.py
git commit -m "Add the opt-in task-run check"
```

---

### Task 10: The report

**Files:**
- Create: `smoke/lib/report.py`
- Test: `smoke/tests/test_report.py`

**Interfaces:**
- Consumes: `Result`, `run_verdict`, status constants; `Build`.
- Produces: `Report(build, results, mode, started, finished)` with `.verdict()`, `.duration()`, `.to_dict()`; `write_json(report, path)`; `write_html(report, path)`; `run_dir(root, when) -> str`.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_report.py`:

```python
import json
import os
import tempfile
import unittest

from smoke.lib.build import Build
from smoke.lib.report import Report, write_html, write_json
from smoke.lib.result import FAIL, PASS, RED, SKIP, UNVERIFIED, Result


def a_build():
    return Build("/Applications/codepet.app", "1.0", "2", "app.murror.codepet",
                 True, "valid on disk", False, 0.0)


def a_report(results):
    return Report(build=a_build(), results=results, mode="installed build",
                  started=100.0, finished=234.0)


class Shape(unittest.TestCase):
    def test_it_carries_the_verdict_and_the_build_label(self):
        r = a_report([Result("launch", PASS), Result("chat", FAIL)])
        self.assertEqual(r.verdict(), RED)
        self.assertEqual(r.build.label(), "1.0 (2)")
        self.assertEqual(r.duration(), 134.0)

    def test_a_run_of_nothing_but_skips_is_unverified(self):
        self.assertEqual(a_report([Result("task", SKIP)]).verdict(), UNVERIFIED)


class Files(unittest.TestCase):
    def test_json_round_trips_every_check(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "report.json")
            write_json(a_report([Result("launch", PASS, 3.1, "window in 3.1s")]), path)
            with open(path) as f:
                data = json.load(f)
            self.assertEqual(data["verdict"], "green")
            self.assertEqual(data["build"]["bundle_version"], "2")
            self.assertEqual(data["results"][0]["detail"], "window in 3.1s")

    def test_html_names_the_build_and_every_check(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "report.html")
            write_html(a_report([Result("launch", PASS), Result("chat", FAIL, 0, "no reply")]), path)
            html = open(path, encoding="utf-8").read()
            self.assertIn("1.0 (2)", html)
            self.assertIn("no reply", html)
            self.assertIn("<html", html)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_report -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.report'`

- [ ] **Step 3: Write the implementation**

Create `smoke/lib/report.py`:

```python
"""The record of a run. Slack is a notification about this, not the record."""

import html as html_mod
import json
import os
import time
from dataclasses import dataclass, field

from smoke.lib.result import ERROR, FAIL, PASS, SKIP, run_verdict

STATUS_MARK = {PASS: "PASS", FAIL: "FAIL", ERROR: "ERROR", SKIP: "SKIP"}


@dataclass
class Report:
    build: object
    results: list = field(default_factory=list)
    mode: str = "installed build"
    started: float = 0.0
    finished: float = 0.0

    def verdict(self):
        return run_verdict(self.results)

    def duration(self):
        return self.finished - self.started

    def to_dict(self):
        return {
            "verdict": self.verdict(),
            "mode": self.mode,
            "duration": self.duration(),
            "started": self.started,
            "build": self.build.to_dict(),
            "results": [r.to_dict() for r in self.results],
        }


def run_dir(root, when=None):
    stamp = time.strftime("%Y-%m-%d-%H%M%S", time.localtime(when or time.time()))
    path = os.path.join(root, stamp)
    os.makedirs(path, exist_ok=True)
    return path


def write_json(report, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(report.to_dict(), f, indent=2)


def write_html(report, path):
    rows = []
    for r in report.results:
        rows.append(
            "<tr><td>%s</td><td>%s</td><td>%.1fs</td><td>%s</td></tr>"
            % (
                html_mod.escape(STATUS_MARK.get(r.status, r.status)),
                html_mod.escape(r.name),
                r.duration,
                html_mod.escape(r.detail),
            )
        )
    body = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>Codepet smoke %s</title>"
        "<style>body{font:14px -apple-system,sans-serif;margin:2rem;}"
        "table{border-collapse:collapse}td{padding:.3rem .8rem;border-bottom:1px solid #ddd}"
        "</style></head><body>"
        "<h1>Codepet smoke &mdash; %s</h1>"
        "<p>%s &middot; %s &middot; %.0fs</p>"
        "<table>%s</table></body></html>"
    ) % (
        html_mod.escape(report.verdict()),
        html_mod.escape(report.build.label()),
        html_mod.escape(report.verdict()),
        html_mod.escape(report.mode),
        report.duration(),
        "".join(rows),
    )
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_report -v`
Expected: `Ran 4 tests` / `OK`

- [ ] **Step 5: Commit**

```bash
git add smoke/lib/report.py smoke/tests/test_report.py
git commit -m "Write each run to report.json and report.html"
```

---

### Task 11: Slack formatting and delivery

**Files:**
- Create: `smoke/lib/slack.py`
- Test: `smoke/tests/test_slack.py`

**Interfaces:**
- Consumes: `Report`; status constants.
- Produces: `format_message(report) -> str`; `read_webhook(path) -> str | None`; `post(webhook_url, text) -> (bool, str)`; `should_post(mode, verdict, previous_verdict) -> bool`.

**The transition rule lives here.** Watch mode runs dozens of times a day; posting each result makes the channel unreadable and trains everyone to mute it.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_slack.py`:

```python
import unittest

from smoke.lib.build import Build
from smoke.lib.report import Report
from smoke.lib.result import ERROR, FAIL, PASS, SKIP, Result
from smoke.lib.slack import format_message, should_post


def a_report(results, mode="installed build"):
    build = Build("/Applications/codepet.app", "1.0", "2", "app.murror.codepet",
                  True, "valid on disk", False, 0.0)
    return Report(build=build, results=results, mode=mode, started=0.0, finished=134.0)


class Formatting(unittest.TestCase):
    def test_a_failing_run_leads_with_red_and_the_build(self):
        report = a_report([
            Result("launch", PASS, 3.1, "signed, not quarantined, window in 3.1s"),
            Result("auth", PASS, 0.2, "session restored for nguyen@murror.app"),
            Result("chat", FAIL, 90.0, "no reply persisted for probe f3a91c",
                   ["ChatTransport: non-streaming retry refused: billing"]),
            Result("task", SKIP, 0.0, "skipped (chat failed)"),
        ])
        text = format_message(report)
        self.assertTrue(text.startswith("\U0001F534 Codepet smoke — 1.0 (2)"))
        self.assertIn("installed build", text)
        self.assertIn("2m14s", text)
        self.assertIn("no reply persisted for probe f3a91c", text)
        # the app's own words, so the channel answers "what broke"
        self.assertIn("non-streaming retry refused: billing", text)

    def test_a_green_run_leads_with_green(self):
        text = format_message(a_report([Result("launch", PASS, 3.1, "fine")]))
        self.assertTrue(text.startswith("\U0001F7E2"))

    def test_an_errored_run_is_not_green(self):
        text = format_message(a_report([Result("launch", ERROR, 1.0, "no windows")]))
        self.assertFalse(text.startswith("\U0001F7E2"))


class TransitionRule(unittest.TestCase):
    def test_a_plain_run_always_posts(self):
        self.assertTrue(should_post("run", "green", previous_verdict="green"))

    def test_watch_stays_silent_on_an_unchanged_verdict(self):
        self.assertFalse(should_post("watch", "green", previous_verdict="green"))

    def test_watch_speaks_up_when_green_turns_red(self):
        self.assertTrue(should_post("watch", "red", previous_verdict="green"))

    def test_watch_speaks_up_on_the_very_first_run(self):
        self.assertTrue(should_post("watch", "green", previous_verdict=None))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_slack -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.slack'`

- [ ] **Step 3: Write the implementation**

Create `smoke/lib/slack.py`:

```python
"""Post the verdict to Slack.

Slack never rewrites the verdict. The local report is the record; this is a
notification about it. A failed post leaves the run exactly as the checks
found it -- a green run whose message did not deliver is still a green run.
"""

import json
import os
import urllib.error
import urllib.request

from smoke.lib.result import ERROR, FAIL, GREEN, PASS, SKIP

MARK = {PASS: "✅", FAIL: "❌", ERROR: "⚠️", SKIP: "⏭️"}
VERDICT_MARK = {"green": "\U0001F7E2", "red": "\U0001F534", "unverified": "⚠️"}


def _duration(seconds):
    m, s = divmod(int(seconds), 60)
    return "%dm%02ds" % (m, s) if m else "%ds" % s


def format_message(report):
    head = "%s Codepet smoke — %s  ·  %s  ·  %s" % (
        VERDICT_MARK.get(report.verdict(), "⚠️"),
        report.build.label(),
        report.mode,
        _duration(report.duration()),
    )
    lines = [head]
    for r in report.results:
        lines.append("%s %-10s %s" % (MARK.get(r.status, "?"), r.name.title(), r.detail))
    for r in report.results:
        for e in r.evidence:
            lines.append("   %s" % e)
    return "\n".join(lines)


def should_post(mode, verdict, previous_verdict):
    """Watch mode speaks only when the verdict CHANGES."""
    if mode != "watch":
        return True
    return previous_verdict != verdict


def read_webhook(path):
    try:
        with open(os.path.expanduser(path), encoding="utf-8") as f:
            url = f.read().strip()
        return url or None
    except FileNotFoundError:
        return None


def post(webhook_url, text):
    payload = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status == 200, "posted"
    except urllib.error.URLError as e:
        return False, "slack post failed: %s" % e
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_slack -v`
Expected: `Ran 7 tests` / `OK`

- [ ] **Step 5: Commit**

```bash
git add smoke/lib/slack.py smoke/tests/test_slack.py
git commit -m "Format and deliver the Slack summary, silent on unchanged watch verdicts"
```

---

### Task 12: The runner and the `run` mode

**Files:**
- Create: `smoke/smoke` (executable), `smoke/lib/runner.py`, `smoke/lib/lock.py`
- Test: `smoke/tests/test_runner.py`, `smoke/tests/test_lock.py`

**Interfaces:**
- Consumes: every module above.
- Produces: `Lock(path)` context manager raising `LockHeld`; `execute(app_path, mode, with_task, db_dir, runs_root, account) -> Report`.

- [ ] **Step 1: Write the failing tests**

Create `smoke/tests/test_lock.py`:

```python
import os
import tempfile
import unittest

from smoke.lib.lock import Lock, LockHeld


class Locking(unittest.TestCase):
    def test_a_second_holder_is_refused(self):
        # Two runs -- or two parallel Claude sessions -- must not drive the
        # app at once.
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, ".lock")
            with Lock(path):
                with self.assertRaises(LockHeld):
                    with Lock(path):
                        pass

    def test_the_lock_is_released_after_the_block(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, ".lock")
            with Lock(path):
                pass
            with Lock(path):
                pass  # no raise


if __name__ == "__main__":
    unittest.main()
```

Create `smoke/tests/test_runner.py`:

```python
import unittest

from smoke.lib.result import ERROR, FAIL, PASS, SKIP, Result
from smoke.lib.runner import downstream_of, order


class Ordering(unittest.TestCase):
    def test_the_checks_run_in_dependency_order(self):
        self.assertEqual(order(), ["launch", "auth", "chat", "task"])

    def test_a_failed_launch_skips_everything_after_it(self):
        names = downstream_of("launch")
        self.assertEqual(names, ["auth", "chat", "task"])

    def test_a_failed_chat_skips_only_the_task(self):
        self.assertEqual(downstream_of("chat"), ["task"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them and watch them fail**

Run: `python3 -m unittest smoke.tests.test_lock smoke.tests.test_runner -v`
Expected: `ModuleNotFoundError` for `smoke.lib.lock`

- [ ] **Step 3: Write the lock**

Create `smoke/lib/lock.py`:

```python
"""One run at a time. A sibling session must not drive the app underneath us."""

import fcntl
import os


class LockHeld(Exception):
    """Another run holds the lock."""


class Lock:
    def __init__(self, path):
        self.path = path
        self._fh = None

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self._fh = open(self.path, "w")
        try:
            fcntl.flock(self._fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self._fh.close()
            self._fh = None
            raise LockHeld(self.path)
        return self

    def __exit__(self, *exc):
        if self._fh:
            fcntl.flock(self._fh, fcntl.LOCK_UN)
            self._fh.close()
        return False
```

- [ ] **Step 4: Write the runner**

Create `smoke/lib/runner.py`:

```python
"""Run the checks in order, and never invent a verdict.

Teardown lives in a finally: a crashed check must not leave the app holding
the LevelDB lock and blocking the next xcodebuild test.
"""

import os
import time

from smoke.checks import auth as auth_check
from smoke.checks import chat as chat_check
from smoke.checks import launch as launch_check
from smoke.checks import task as task_check
from smoke.lib import build as build_lib
from smoke.lib import drive, store
from smoke.lib.logstream import Capture
from smoke.lib.report import Report, run_dir, write_html, write_json
from smoke.lib.result import ERROR, FAIL, PASS, Result, skip_rest

ORDER = ["launch", "auth", "chat", "task"]


def order():
    return list(ORDER)


def downstream_of(name):
    return ORDER[ORDER.index(name) + 1:]


def execute(app_path, mode, with_task, account, db_dir=None, runs_root=None):
    db_dir = db_dir or store.DEFAULT_DB
    runs_root = runs_root or os.path.join(os.path.dirname(__file__), "..", "runs")
    started = time.time()
    where = run_dir(os.path.abspath(runs_root))
    results = []

    try:
        target = build_lib.identify(app_path)
    except build_lib.BuildMissing:
        target = build_lib.Build(app_path, "?", "?", "?", False,
                                 "no bundle at %s" % app_path, False, 0.0)

    with Capture(os.path.join(where, "log.txt")) as capture:
        try:
            first = launch_check.run(app_path, evidence_dir=where)
            results.append(first)
            if first.status in (FAIL, ERROR):
                results.extend(skip_rest(downstream_of("launch"),
                                         "launch %s" % first.status))
            else:
                token = chat_check.mint_token()
                chat = chat_check.run(token, capture, db_dir=db_dir)
                # chat quits the app, so auth reads a released lock.
                results.append(auth_check.run(account, db_dir=db_dir))
                results.append(chat)
                if chat.status in (FAIL, ERROR):
                    results.append(task_check.evaluate(
                        with_task, False, False, token, None))
                    results[-1].detail = "skipped (chat %s)" % chat.status
                elif with_task:
                    # Only pay for a relaunch when the task check will really run.
                    drive.launch(app_path)
                    drive.wait_until(drive.is_running, timeout=45)
                    results.append(task_check.run(
                        chat_check.mint_token(), capture, True, db_dir=db_dir))
                else:
                    results.append(task_check.evaluate(
                        False, False, False, "", None))
        finally:
            drive.quit_app()

    # Put the results back in declared order so the report always reads the same.
    results.sort(key=lambda r: ORDER.index(r.name) if r.name in ORDER else 99)
    report = Report(build=target, results=results, mode=mode,
                    started=started, finished=time.time())
    write_json(report, os.path.join(where, "report.json"))
    write_html(report, os.path.join(where, "report.html"))
    return report, where
```

- [ ] **Step 5: Write the CLI**

Create `smoke/smoke`:

```python
#!/usr/bin/env python3
"""Codepet smoke test.

    smoke run                 the installed /Applications/codepet.app
    smoke run --dev PATH      a local build
    smoke run --with-task     also spend credits on a task run
    smoke watch PATH          re-run whenever that build changes
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from smoke.lib import slack
from smoke.lib.lock import Lock, LockHeld
from smoke.lib.runner import execute

INSTALLED = "/Applications/codepet.app"
DEFAULT_ACCOUNT = "nguyen@murror.app"
WEBHOOK = "~/.config/codepet-smoke/webhook.txt"


def main(argv=None):
    p = argparse.ArgumentParser(prog="smoke")
    sub = p.add_subparsers(dest="cmd", required=True)

    run = sub.add_parser("run")
    run.add_argument("--dev", metavar="PATH", help="a local build instead of the installed app")
    run.add_argument("--with-task", action="store_true", help="also run the task check (costs credits)")
    run.add_argument("--slack", action="store_true", help="post even in --dev mode")
    run.add_argument("--account", default=DEFAULT_ACCOUNT)

    watch = sub.add_parser("watch")
    watch.add_argument("path", help="the built .app to watch")
    watch.add_argument("--account", default=DEFAULT_ACCOUNT)

    args = p.parse_args(argv)
    here = os.path.dirname(os.path.abspath(__file__))

    if args.cmd == "watch":
        from smoke.lib.watch import watch_loop
        return watch_loop(args.path, args.account, here)

    app_path = args.dev or INSTALLED
    mode = "local build" if args.dev else "installed build"
    try:
        with Lock(os.path.join(here, "runs", ".lock")):
            report, where = execute(app_path, mode, args.with_task, args.account)
    except LockHeld:
        print("another smoke run holds the lock; not driving the app")
        return 2

    text = slack.format_message(report)
    print(text)
    print("\nreport: %s" % where)

    if not args.dev or args.slack:
        url = slack.read_webhook(WEBHOOK)
        if not url:
            print("no webhook at %s -- not posted" % WEBHOOK)
        else:
            ok, detail = slack.post(url, text)
            print(detail)

    return 0 if report.verdict() == "green" else 1


if __name__ == "__main__":
    sys.exit(main())
```

Then: `chmod +x smoke/smoke`

- [ ] **Step 6: Run the tests and watch them pass**

Run: `python3 -m unittest smoke.tests.test_lock smoke.tests.test_runner -v`
Expected: `Ran 5 tests` / `OK`

- [ ] **Step 7: Run the whole suite**

Run: `python3 -m unittest discover -s smoke/tests -t . -v`
Expected: `OK`, roughly 50 tests

- [ ] **Step 8: Commit**

```bash
git add smoke/
git commit -m "Wire the runner, the run lock and the smoke CLI"
```

---

### Task 13: Watch mode

**Files:**
- Create: `smoke/lib/watch.py`
- Test: `smoke/tests/test_watch.py`

**Interfaces:**
- Consumes: `execute`, `Lock`, `slack.should_post`, `build_lib.identify`.
- Produces: `Fingerprint(bundle_version, mtime)`; `fingerprint(app_path) -> Fingerprint`; `is_fresh(current, previous) -> bool`; `may_drive(app_running, we_launched_it) -> (bool, str)`; `watch_loop(app_path, account, here, poll=2.0, debounce=3.0)`.

**Three guards, and all three have bitten this project:**
1. *Freshness.* Refuse to report on a bundle that did not change — "still looks the same" has meant a stale binary too many times.
2. *Never hijack.* If the founder's app is running, defer. No `pkill`. A running app also kills an `xcodebuild test` host.
3. *Transitions only.* Silence while green.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_watch.py`:

```python
import unittest

from smoke.lib.watch import Fingerprint, is_fresh, may_drive


class Freshness(unittest.TestCase):
    def test_the_first_sighting_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("2", 100.0), None))

    def test_an_unchanged_bundle_is_not_fresh(self):
        # The stale-build trap, caught by the tool instead of by a person
        # concluding their change did not work.
        f = Fingerprint("2", 100.0)
        self.assertFalse(is_fresh(f, Fingerprint("2", 100.0)))

    def test_a_new_mtime_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("2", 200.0), Fingerprint("2", 100.0)))

    def test_a_new_bundle_version_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("3", 100.0), Fingerprint("2", 100.0)))


class Hijacking(unittest.TestCase):
    def test_it_drives_when_nothing_is_running(self):
        may, why = may_drive(app_running=False, we_launched_it=False)
        self.assertTrue(may)

    def test_it_defers_to_the_founders_own_app(self):
        may, why = may_drive(app_running=True, we_launched_it=False)
        self.assertFalse(may)
        self.assertIn("your app is running", why)

    def test_it_may_drive_an_app_it_launched_itself(self):
        may, why = may_drive(app_running=True, we_launched_it=True)
        self.assertTrue(may)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_watch -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.watch'`

- [ ] **Step 3: Write the implementation**

Create `smoke/lib/watch.py`:

```python
"""Re-run the checks whenever the local build changes.

fswatch is not installed and does not become a prerequisite, so this polls
Info.plist's mtime and debounces -- a build writes many files, and running
against a half-written bundle proves nothing.
"""

import os
import time
from dataclasses import dataclass

from smoke.lib import build as build_lib
from smoke.lib import drive, slack
from smoke.lib.lock import Lock, LockHeld
from smoke.lib.runner import execute


@dataclass
class Fingerprint:
    bundle_version: str
    mtime: float


def fingerprint(app_path):
    info_plist = os.path.join(app_path, "Contents", "Info.plist")
    target = build_lib.identify(app_path)
    return Fingerprint(target.bundle_version, os.path.getmtime(info_plist))


def is_fresh(current, previous):
    if previous is None:
        return True
    return (current.bundle_version, current.mtime) != (
        previous.bundle_version, previous.mtime
    )


def may_drive(app_running, we_launched_it):
    """Never pkill. A running app is either the founder's or ours."""
    if app_running and not we_launched_it:
        return False, "deferred: your app is running"
    return True, ""


def watch_loop(app_path, account, here, poll=2.0, debounce=3.0):
    previous_fp = None
    previous_verdict = None
    print("watching %s -- ctrl-c to stop" % app_path)

    while True:
        try:
            current = fingerprint(app_path)
        except build_lib.BuildMissing:
            time.sleep(poll)
            continue

        if not is_fresh(current, previous_fp):
            time.sleep(poll)
            continue

        # Debounce: wait for the build to stop writing.
        while True:
            time.sleep(debounce)
            settled = fingerprint(app_path)
            if settled.mtime == current.mtime:
                break
            current = settled

        may, why = may_drive(drive.is_running(), we_launched_it=False)
        if not may:
            print(why)
            time.sleep(poll)
            continue

        try:
            with Lock(os.path.join(here, "runs", ".lock")):
                report, where = execute(app_path, "local build", False, account)
        except LockHeld:
            time.sleep(poll)
            continue

        previous_fp = current
        text = slack.format_message(report)
        print(text)

        verdict = report.verdict()
        if slack.should_post("watch", verdict, previous_verdict):
            url = slack.read_webhook("~/.config/codepet-smoke/webhook.txt")
            if url:
                ok, detail = slack.post(url, text)
                print(detail)
        previous_verdict = verdict
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_watch -v`
Expected: `Ran 7 tests` / `OK`

- [ ] **Step 5: Run the entire suite**

Run: `python3 -m unittest discover -s smoke/tests -t . -v`
Expected: `OK`, roughly 57 tests

- [ ] **Step 6: Break a guard deliberately and watch it go red**

This project has shipped five tests in one plan that could not fail. Prove these can:

```bash
python3 - <<'EOF'
import re, pathlib
p = pathlib.Path("smoke/lib/watch.py")
s = p.read_text()
p.write_text(s.replace("if previous is None:\n        return True", "if previous is None:\n        return True\n    return True"))
EOF
python3 -m unittest smoke.tests.test_watch -v
```

Expected: `test_an_unchanged_bundle_is_not_fresh` FAILS. Then restore:

```bash
git checkout smoke/lib/watch.py
python3 -m unittest smoke.tests.test_watch -v
```

Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add smoke/lib/watch.py smoke/tests/test_watch.py
git commit -m "Add watch mode, with freshness, no-hijack and transition guards"
```

---

### Task 14: Install from the download page

**Files:**
- Create: `smoke/lib/dmg.py`
- Modify: `smoke/smoke` (add `--dmg`)
- Test: `smoke/tests/test_dmg.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `DEFAULT_URL`; `DmgError(Exception)`; `parse_mount_point(hdiutil_stdout) -> str`; `app_in(mount_point) -> str`; `download(url, dest) -> str`; `install(url, workdir) -> str` returning the installed app path.

**Why this closes the loop:** the whole project started from "I will install another version from `https://code-pet.com/download` to test if it work". The page is live and serves `/download/Codepet.dmg`. A tool that cannot fetch the artefact leaves the most error-prone step — download, mount, copy, de-quarantine — as the one part still done by hand.

**It does not delete anything.** Replacing `/Applications/codepet.app` is the founder's call, so `install` copies to a working directory and returns that path for `--dmg` to test in place.

- [ ] **Step 1: Write the failing test**

Create `smoke/tests/test_dmg.py`:

```python
import os
import tempfile
import unittest

from smoke.lib.dmg import DmgError, app_in, parse_mount_point

# Real `hdiutil attach -plist` output is XML; with -nobrowse and no -plist it
# prints tab-separated rows and the mount point is the last field of the row
# that has one.
REAL = (
    "/dev/disk4          \tGUID_partition_scheme\t\n"
    "/dev/disk4s1        \tApple_HFS             \t/Volumes/Codepet\n"
)


class MountPoint(unittest.TestCase):
    def test_it_takes_the_volume_path(self):
        self.assertEqual(parse_mount_point(REAL), "/Volumes/Codepet")

    def test_no_volume_row_is_an_error_not_an_empty_string(self):
        with self.assertRaises(DmgError):
            parse_mount_point("/dev/disk4\tGUID_partition_scheme\t\n")


class AppIn(unittest.TestCase):
    def test_it_finds_the_single_app_bundle(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "codepet.app", "Contents"))
            self.assertEqual(app_in(d), os.path.join(d, "codepet.app"))

    def test_a_volume_with_no_app_is_an_error(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(DmgError):
                app_in(d)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and watch it fail**

Run: `python3 -m unittest smoke.tests.test_dmg -v`
Expected: `ModuleNotFoundError: No module named 'smoke.lib.dmg'`

- [ ] **Step 3: Write the implementation**

Create `smoke/lib/dmg.py`:

```python
"""Fetch and mount the shipped disk image.

This exists because the artefact under test should be the one a user actually
downloads, not one already sitting on this Mac. Download, mount, copy and
de-quarantine are four steps with four ways to go wrong, and doing them by
hand is what this whole tool is replacing.

Nothing in /Applications is touched. Replacing an installed app is the
founder's decision, so the copy lands in a working directory.
"""

import glob
import os
import shutil
import subprocess
import urllib.request

DEFAULT_URL = "https://code-pet.com/download/Codepet.dmg"


class DmgError(Exception):
    """The image could not be fetched, mounted, or read."""


def download(url, dest):
    try:
        urllib.request.urlretrieve(url, dest)
    except OSError as e:
        raise DmgError("could not download %s: %s" % (url, e))
    return dest


def parse_mount_point(hdiutil_stdout):
    for row in (hdiutil_stdout or "").splitlines():
        fields = [f.strip() for f in row.split("\t") if f.strip()]
        if fields and fields[-1].startswith("/Volumes/"):
            return fields[-1]
    raise DmgError("hdiutil mounted nothing under /Volumes")


def app_in(mount_point):
    found = glob.glob(os.path.join(mount_point, "*.app"))
    if not found:
        raise DmgError("no .app bundle on %s" % mount_point)
    return found[0]


def install(url, workdir):
    """Download, mount, copy out, detach. Returns the local app path."""
    os.makedirs(workdir, exist_ok=True)
    image = download(url, os.path.join(workdir, "Codepet.dmg"))

    attach = subprocess.run(
        ["/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", image],
        capture_output=True, text=True,
    )
    if attach.returncode != 0:
        raise DmgError((attach.stderr or "hdiutil attach failed").strip())

    mount_point = parse_mount_point(attach.stdout)
    try:
        source = app_in(mount_point)
        target = os.path.join(workdir, os.path.basename(source))
        if os.path.exists(target):
            shutil.rmtree(target)
        shutil.copytree(source, target, symlinks=True)
    finally:
        subprocess.run(["/usr/bin/hdiutil", "detach", mount_point],
                       capture_output=True)
    return target
```

- [ ] **Step 4: Run it and watch it pass**

Run: `python3 -m unittest smoke.tests.test_dmg -v`
Expected: `Ran 4 tests` / `OK`

- [ ] **Step 5: Add the flag to the CLI**

In `smoke/smoke`, add to the `run` parser, directly after the `--dev` argument:

```python
    run.add_argument("--dmg", nargs="?", const=None, metavar="URL",
                     help="download and test the shipped image (default: the download page)")
```

and replace the two lines that choose the target:

```python
    app_path = args.dev or INSTALLED
    mode = "local build" if args.dev else "installed build"
```

with:

```python
    if getattr(args, "dmg", None) is not None or "--dmg" in (argv or sys.argv):
        from smoke.lib import dmg
        url = args.dmg or dmg.DEFAULT_URL
        try:
            app_path = dmg.install(url, os.path.join(here, "runs", "downloaded"))
        except dmg.DmgError as e:
            print("could not install from %s: %s" % (url, e))
            return 2
        mode = "downloaded build"
    else:
        app_path = args.dev or INSTALLED
        mode = "local build" if args.dev else "installed build"
```

**Note the quarantine interaction:** a downloaded image carries `com.apple.quarantine`, so the launch check will correctly report `FAIL — quarantined`. That is the right answer for an unsigned release and exactly the Gatekeeper break worth catching. To test the app *past* Gatekeeper, clear it deliberately and say so in the run:

```bash
xattr -dr com.apple.quarantine smoke/runs/downloaded/codepet.app
```

- [ ] **Step 6: Run the whole suite**

Run: `python3 -m unittest discover -s smoke/tests -t . -v`
Expected: `OK`, roughly 61 tests

- [ ] **Step 7: Commit**

```bash
git add smoke/lib/dmg.py smoke/tests/test_dmg.py smoke/smoke
git commit -m "Download, mount and test the shipped disk image"
```

---

## First real run

These three are recorded as open questions in the spec. None block implementation; all three block the first green run.

- [ ] **Invite the Claude app to the Slack channel.** `C0C3Y0QP6Q5` currently returns `channel_not_found`. Run `/invite @Claude` in that channel.
- [ ] **Create the incoming webhook** and store it:

```bash
mkdir -p ~/.config/codepet-smoke
printf '%s\n' 'https://hooks.slack.com/services/...' > ~/.config/codepet-smoke/webhook.txt
chmod 600 ~/.config/codepet-smoke/webhook.txt
```

- [ ] **Create the dedicated probe project** in the app, so smoke traffic never mixes into real founder work.
- [ ] **Run it for real:** `./smoke/smoke run`
- [ ] **Confirm the checks can actually go red** — quit mid-run, or point `--dev` at an unsigned build, and verify the report says `error` rather than `fail` where it should.
