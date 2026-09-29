"""Re-run the checks whenever the local build changes.

fswatch is not installed and does not become a prerequisite, so this polls
and debounces -- a build writes many files, and running against a
half-written bundle proves nothing.

The fingerprint is the mtime of Contents/_CodeSignature/CodeResources plus
CFBundleVersion read straight from Info.plist. Signing is the LAST write of
a build, so CodeResources changing means a build finished; Info.plist's own
mtime changes early, while the binary is still being linked. Nothing here
runs codesign: a subprocess every two seconds for the life of a watch is
cost with no verdict in it (the launch check verifies the signature).

A bundle that is not there yet, an Info.plist that is missing or
half-written, or a bundle with no CodeResources all count as BuildMissing:
not settled, keep waiting. The cost is that an unsigned build is never run.
"""

import os
import plistlib
import time
import xml.parsers.expat
from dataclasses import dataclass

from smoke.lib import build as build_lib
from smoke.lib import drive, slack
from smoke.lib.lock import Lock, LockHeld
from smoke.lib.runner import execute


@dataclass
class Fingerprint:
    bundle_version: str
    mtime: float


# plistlib raises InvalidFileException (a ValueError) for a binary plist cut
# short, and expat's ExpatError -- NOT a ValueError -- for XML cut short.
UNREADABLE_PLIST = (plistlib.InvalidFileException, ValueError, OSError,
                    xml.parsers.expat.ExpatError)


def fingerprint(app_path):
    contents = os.path.join(app_path, "Contents")
    try:
        with open(os.path.join(contents, "Info.plist"), "rb") as f:
            info = plistlib.load(f)
        if not isinstance(info, dict):
            raise ValueError("Info.plist is not a dictionary")
        signed_at = os.path.getmtime(os.path.join(contents, "_CodeSignature",
                                                  "CodeResources"))
    except UNREADABLE_PLIST as e:
        raise build_lib.BuildMissing("%s: %s" % (app_path, e))
    return Fingerprint(str(info.get("CFBundleVersion", "?")), signed_at)


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


def watch_loop(
    app_path,
    account,
    here,
    poll=2.0,
    debounce=3.0,
    *,
    sleep=time.sleep,
    fingerprint_fn=None,
    run=None,
    is_running=None,
    post_fn=None,
    read_webhook_fn=None,
    max_passes=None,
    uid=None,
    settle=8.0,
):
    if fingerprint_fn is None:
        fingerprint_fn = fingerprint
    if run is None:
        run = execute
    if is_running is None:
        is_running = drive.is_running
    if post_fn is None:
        post_fn = slack.post
    if read_webhook_fn is None:
        read_webhook_fn = slack.read_webhook

    previous_fp = None
    previous_verdict = None
    deferred_for_fp = None
    passes = 0
    said_waiting = False
    print("watching %s -- ctrl-c to stop" % app_path)

    while True:
        passes += 1
        if max_passes is not None and passes > max_passes:
            break

        try:
            current = fingerprint_fn(app_path)
        except build_lib.BuildMissing:
            # Once, not every two seconds: a watch started before the first
            # build would otherwise scroll this line forever.
            if not said_waiting:
                print("waiting for %s" % app_path)
                said_waiting = True
            sleep(poll)
            continue
        said_waiting = False

        if not is_fresh(current, previous_fp):
            sleep(poll)
            continue

        # Debounce: wait for the build to stop writing.
        debounce_success = True
        while True:
            sleep(debounce)
            try:
                settled = fingerprint_fn(app_path)
            except build_lib.BuildMissing:
                # Bundle removed during debounce; restart polling from top
                debounce_success = False
                break
            if settled == current:
                break
            current = settled

        if not debounce_success:
            sleep(poll)
            continue

        may, why = may_drive(is_running(), we_launched_it=False)
        if not may:
            # Print once per fingerprint, not every pass
            if deferred_for_fp != current:
                print(why)
                deferred_for_fp = current
            sleep(poll)
            continue

        try:
            with Lock(os.path.join(here, "runs", ".lock")):
                report, where = run(app_path, "local build", False, account, uid=uid, settle=settle)
        except LockHeld:
            sleep(poll)
            continue
        except KeyboardInterrupt:
            raise
        except Exception as e:
            print("run crashed: %s: %s" % (type(e).__name__, e))
            previous_fp = current
            sleep(poll)
            continue

        previous_fp = current
        text = slack.format_message(report)
        print(text)

        verdict = report.verdict()
        if slack.should_post("watch", verdict, previous_verdict):
            url = read_webhook_fn("~/.config/codepet-smoke/webhook.txt")
            if url:
                ok, detail = post_fn(url, text)
                print(detail)
        previous_verdict = verdict
