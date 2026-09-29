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
    print("watching %s -- ctrl-c to stop" % app_path)

    while True:
        passes += 1
        if max_passes is not None and passes > max_passes:
            break

        try:
            current = fingerprint_fn(app_path)
        except build_lib.BuildMissing:
            sleep(poll)
            continue

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
            if settled.mtime == current.mtime:
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
                report, where = run(app_path, "local build", False, account)
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
