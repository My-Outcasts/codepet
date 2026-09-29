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
