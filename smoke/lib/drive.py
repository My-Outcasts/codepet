"""The ONLY file that drives the UI.

`count windows` has reported 0 while the app was visibly on screen, and
assistive access can drop mid-session. So this file does the smallest thing
the four checks allow -- launch, focus, type, Enter -- and every failure it
raises is a DriveError, which callers translate to ERROR rather than FAIL.
We could not observe; that is not the same as the app being broken.

Launch flags go through `open --args`, never `defaults write`: a leftover
sandbox container silently redirects the app.murror.codepet domain, and
`defaults read` then confirms the lie.
"""

import subprocess
import time

BUNDLE_ID = "app.murror.codepet"
PROCESS_NAME = "codepet"


class DriveError(RuntimeError):
    """The harness could not drive the app. Not a product defect."""


def as_applescript_string(text):
    """Quote a Python string so AppleScript sees exactly these characters."""
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % escaped


def osascript(script, timeout=20):
    try:
        p = subprocess.run(
            ["/usr/bin/osascript", "-e", script],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise DriveError("osascript timed out after %ss" % timeout)
    if p.returncode != 0:
        lines = (p.stderr or "osascript failed").strip().splitlines()
        message = lines[0] if lines else "osascript failed"
        raise DriveError(message)
    return p.stdout.strip()


def wait_until(predicate, timeout, interval=0.5):
    deadline = time.time() + timeout
    while True:
        if predicate():
            return True
        if time.time() >= deadline:
            return False
        time.sleep(interval)


def launch(app_path, args=()):
    if args and is_running():
        raise DriveError("app already running; launch flags would be ignored")
    cmd = ["/usr/bin/open", "-a", app_path]
    if args:
        cmd.append("--args")
        cmd.extend(args)
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise DriveError((p.stderr or "open failed").strip())


def is_running():
    return subprocess.run(
        ["/usr/bin/pgrep", "-x", PROCESS_NAME], capture_output=True
    ).returncode == 0


def pid():
    p = subprocess.run(["/usr/bin/pgrep", "-x", PROCESS_NAME], capture_output=True, text=True)
    if p.returncode != 0:
        return None
    return int(p.stdout.split()[0])


def window_count():
    """Best effort. A 0 here is NOT proof of no window -- see module docstring."""
    try:
        out = osascript(
            'tell application "System Events" to count windows of '
            'application process %s' % as_applescript_string(PROCESS_NAME)
        )
        return int(out or 0)
    except (DriveError, ValueError):
        return 0


def focus():
    osascript('tell application id %s to activate' % as_applescript_string(BUNDLE_ID))


def type_text(text):
    osascript(
        'tell application "System Events" to keystroke %s' % as_applescript_string(text)
    )


def press_enter():
    osascript('tell application "System Events" to key code 36')


def quit_app(timeout=20):
    """Ask nicely. Never pkill -- a sibling session may own this app."""
    if not is_running():
        return True
    try:
        osascript('tell application id %s to quit' % as_applescript_string(BUNDLE_ID))
    except DriveError:
        pass
    return wait_until(lambda: not is_running(), timeout=timeout)


def screenshot(path):
    return subprocess.run(
        ["/usr/sbin/screencapture", "-x", "-o", path], capture_output=True
    ).returncode == 0
