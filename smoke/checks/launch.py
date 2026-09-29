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
