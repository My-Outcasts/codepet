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
