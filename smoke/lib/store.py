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
    for p in data_files(db_dir):
        try:
            if _file_contains(p, needle, chunk):
                return True
        except FileNotFoundError:
            # File was deleted by LevelDB compaction between listing and open.
            # Skip it and continue searching remaining files.
            continue
    return False


def count(db_dir, needle):
    if not needle:
        raise ValueError("an empty needle matches everything")
    total = 0
    for path in data_files(db_dir):
        try:
            with open(path, "rb") as f:
                total += f.read().count(needle)
        except FileNotFoundError:
            # File was deleted by LevelDB compaction between listing and open.
            # Skip it and continue counting in remaining files.
            continue
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
