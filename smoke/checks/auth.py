"""Check 2 -- did the app restore a signed-in session?

The verdict comes from the app's own Auth log line, which AuthManager writes
on every auth state change (Managers/AuthManager.swift):

    signed in: uid=<uid> anonymous=false hasName=true

That is the app saying it holds a session, for which account. A signed-in
line for the expected uid is PASS; one for another uid, an anonymous one, or
a "signed out" is FAIL.

It used to look for the account EMAIL in the Firestore LevelDB. That was a
presence check standing in for a session, and on 1 Oct it read a signed-in
build 6 as FAIL: the email was in the cache 0 times while the uid was there
703 times, with no compressed block to hide it. The only Swift that writes the
email to Firestore is FeatureFeedbackManager, so the 3 hits a scan found on
24 September were incidental documents the cache has since dropped. The
LevelDB scan stays as the fallback for a run whose log captured no auth line.
"""

import re
import time

from smoke.lib import store
from smoke.lib.result import ERROR, FAIL, PASS, Result

NAME = "auth"
SIGNED_IN = re.compile(r"signed in: uid=(?P<uid>\S+) anonymous=(?P<anon>\w+)")


def session_from_log(lines):
    """("in", uid, anonymous) for the LAST auth state line, ("out", None, None),
    or None if the log has no auth state line at all."""
    state = None
    for line in lines:
        if getattr(line, "category", None) != "Auth":
            continue
        m = SIGNED_IN.search(line.message)
        if m:
            state = ("in", m.group("uid"), m.group("anon") == "true")
        elif line.message.strip() == "signed out":
            state = ("out", None, None)
    return state


def from_session(state, account, uid=None):
    kind, got, anonymous = state
    if kind == "out":
        return Result(NAME, FAIL, 0.0, "the app reported signed out (%s)" % account)
    if anonymous:
        return Result(NAME, FAIL, 0.0, "the app restored an ANONYMOUS session (uid=%s)" % got)
    if uid and got != uid:
        return Result(NAME, FAIL, 0.0,
                      "the app is signed in as uid=%s, expected uid=%s" % (got, uid))
    return Result(NAME, PASS, 0.0, "session restored for uid=%s (%s)" % (got, account))


def evaluate(found, account):
    if found:
        return Result(NAME, PASS, 0.0, "account present in the local store (%s)" % account)
    return Result(NAME, FAIL, 0.0, "account %s not found in the local store" % account)


def run(account, db_dir=store.DEFAULT_DB, lines=(), uid=None):
    started = time.time()
    state = session_from_log(lines)
    if state is not None:
        result = from_session(state, account, uid=uid)
    else:
        try:
            found = store.contains(db_dir, account.encode("utf-8"))
        except store.StoreMissing:
            return Result(NAME, ERROR, time.time() - started, "no database at %s" % db_dir)
        result = evaluate(found, account)
    result.duration = time.time() - started
    return result
