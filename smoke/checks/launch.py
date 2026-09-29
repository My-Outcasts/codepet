"""Check 1 -- does the shipped artefact start at all?

Signature and Gatekeeper are judged BEFORE the app is opened. Gatekeeper is the
likeliest failure for a downloaded build and deserves its own sentence rather
than arriving disguised as a launch timeout. The quarantine flag is only
reported: a notarized app carrying it launches fine.
"""

import os
import time

from smoke.lib import build as build_lib
from smoke.lib import drive
from smoke.lib.result import ERROR, FAIL, PASS, Result

NAME = "launch"


def evaluate(build, opened, process_seen, window_seen, elapsed, gatekeeper=None):
    if not build.signed:
        return Result(NAME, FAIL, elapsed, "not signed: %s" % build.signature)
    if gatekeeper is not None and not gatekeeper[0]:
        return Result(NAME, FAIL, elapsed,
                      "Gatekeeper rejects the app: %s" % gatekeeper[1])
    if not opened:
        return Result(NAME, ERROR, elapsed, "could not ask the system to open the app")
    if not process_seen:
        return Result(NAME, FAIL, elapsed, "no process after %.0fs" % elapsed)
    if not window_seen:
        return Result(NAME, ERROR, elapsed,
                      "process alive but System Events reported 0 windows -- "
                      "assistive access may have dropped")
    verdict = ("Gatekeeper accepts" if gatekeeper is not None
               else "Gatekeeper not assessed (local build)")
    detail = "signed, %s, window in %.1fs" % (verdict, elapsed)
    if build.quarantined:
        detail += ", quarantined"
    return Result(NAME, PASS, elapsed, detail)


def run(app_path, timeout=45, evidence_dir=None, assess_gatekeeper=True):
    started = time.time()
    try:
        target = build_lib.identify(app_path)
    except build_lib.BuildMissing:
        return Result(NAME, ERROR, 0.0, "no app bundle at %s" % app_path)

    gatekeeper = build_lib.assess_gatekeeper(app_path) if assess_gatekeeper else None
    if not target.signed or (gatekeeper is not None and not gatekeeper[0]):
        return evaluate(target, False, False, False, time.time() - started,
                        gatekeeper)

    try:
        drive.launch(app_path)
    except drive.DriveError:
        return evaluate(target, False, False, False, time.time() - started,
                        gatekeeper)

    process_seen = drive.wait_until(drive.is_running, timeout=timeout)
    window_seen = process_seen and drive.wait_until(
        lambda: drive.window_count() > 0, timeout=timeout
    )
    result = evaluate(target, True, process_seen, window_seen,
                      time.time() - started, gatekeeper)

    # A screenshot is worth more than the sentence "0 windows", and it must be
    # taken NOW -- after teardown there is nothing left to photograph.
    if evidence_dir and result.status != PASS and process_seen:
        shot = os.path.join(evidence_dir, "launch.png")
        if drive.screenshot(shot):
            result.evidence.append(shot)
    return result
