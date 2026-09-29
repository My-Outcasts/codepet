"""Check 4 -- does a task run to a deliverable?

Opt-in, because it spends real credits on every run. Watch mode never calls
it with requested=True.

The needle can be satisfied by a plain chat reply that echoes it, not only a
filed deliverable. A presence in the store is not proof it was filed as a
deliverable; it is proof *something* replied with that text.
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


def evaluate(requested, sent, deliverable_persisted, token, log_error, timeout=300):
    evidence = [log_error] if log_error else []
    if not requested:
        return Result(NAME, SKIP, 0.0, "not requested (pass --with-task to spend credits)")
    if not sent:
        return Result(NAME, ERROR, 0.0, "could not ask the app to run a task", evidence)
    if not deliverable_persisted:
        return Result(NAME, FAIL, 0.0,
                      "no deliverable persisted for task probe %s within %ds" % (token, timeout), evidence)
    return Result(NAME, PASS, 0.0,
                  "deliverable needle seen for %s (not proof it was filed as a deliverable)" % token, evidence)


def run(token, capture, requested, db_dir=store.DEFAULT_DB, timeout=300):
    if not requested:
        return evaluate(False, False, False, token, None)

    started = time.time()

    # Before typing anything, check if app is running.
    if not drive.is_running():
        return Result(NAME, ERROR, time.time() - started,
                      "the app is not running; nothing to type into")

    sent = False
    try:
        drive.focus()
        drive.type_text(probe_text(token))
        drive.press_enter()
        sent = True
    except drive.DriveError as e:
        result = evaluate(True, False, False, token, str(e), timeout=timeout)
        result.duration = time.time() - started
        return result

    try:
        persisted = store.wait_for(db_dir, deliverable_needle(token), timeout=timeout)
        # Quit the app BEFORE the fallback read so the memtable flushes
        drive.quit_app()
        if not persisted:
            persisted = store.contains(db_dir, deliverable_needle(token))
    except store.StoreMissing:
        result = Result(NAME, ERROR, time.time() - started, "no database at %s" % db_dir,
                        [first_error(capture.lines())] if first_error(capture.lines()) else [])
        return result
    finally:
        drive.quit_app()

    result = evaluate(True, sent, persisted, token, first_error(capture.lines()), timeout=timeout)
    result.duration = time.time() - started
    return result
