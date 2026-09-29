"""Check 3 -- does a chat turn round-trip through the founder's local Claude Code?

This is the check that proves app -> the founder's local Claude Code -> model -> back, which no
unit test can: CompanyStore is driven through injected closures, and the
local Claude Code runs under the founder's own plan and configuration.

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
    while True:
        token = uuid.uuid4().hex[:6]
        # Reject palindromes: if token == token[::-1], then reply_needle(token) == token,
        # so finding it would prove our probe was saved, not that anything replied.
        if token != token[::-1]:
            return token


def probe_text(token):
    return (
        "smoke test %s -- reply with this code written backwards, nothing else: %s"
        % (token, token)
    )


def reply_needle(token):
    return token[::-1].encode("utf-8")


def evaluate(sent, probe_persisted, reply_persisted, token, log_error, timeout=90):
    evidence = [log_error] if log_error else []
    if not sent:
        return Result(NAME, ERROR, 0.0, "could not type the probe into the app", evidence)
    if not probe_persisted:
        return Result(NAME, ERROR, 0.0,
                      "the probe never reached the store -- the app did not receive "
                      "the keystrokes", evidence)
    if not reply_persisted:
        return Result(NAME, FAIL, 0.0,
                      "no reply persisted for probe %s within %ds" % (token, timeout), evidence)
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
        result = evaluate(False, False, False, token, str(e), timeout=timeout)
        result.duration = time.time() - started
        return result

    # Poll the raw files while the app runs -- a hit is trustworthy and
    # returns in seconds. Then quit and read ONCE more, because a miss may
    # only mean the write is still in the memtable.
    try:
        reply_persisted = store.wait_for(db_dir, reply_needle(token), timeout=timeout)
        if not reply_persisted:
            reply_persisted = store.contains(db_dir, reply_needle(token))
        probe_persisted = store.contains(db_dir, token.encode("utf-8"))
    except store.StoreMissing:
        result = Result(NAME, ERROR, time.time() - started, "no database at %s" % db_dir,
                        [first_error(capture.lines())] if first_error(capture.lines()) else [])
        return result
    finally:
        drive.quit_app()

    result = evaluate(sent, probe_persisted, reply_persisted, token,
                      first_error(capture.lines()), timeout=timeout)
    result.duration = time.time() - started
    return result
