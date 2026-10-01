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


# The composer's place in the accessibility tree, read off a live build 6 on 1 Oct.
# It is absent on the splash and on every other screen, which is what lets its
# presence double as "the chat is on screen".
COMPOSER = "text field 1 of scroll area 2 of group 1 of window 1"


def _in_process(expr):
    return 'tell application "System Events" to tell process %s to %s' % (
        as_applescript_string(PROCESS_NAME), expr)


def is_frontmost():
    try:
        return osascript(_in_process("get frontmost")) == "true"
    except DriveError:
        return False


def composer_present():
    try:
        return osascript(_in_process("exists " + COMPOSER)) == "true"
    except DriveError:
        return False


def on_splash():
    """The splash is the one screen with no composer and a single button."""
    try:
        return osascript(_in_process(
            "count buttons of group 1 of window 1")) == "1" and not composer_present()
    except DriveError:
        return False


def open_composer(timeout=20.0, sleep=time.sleep):
    """Get from launch to a focused composer, or raise DriveError.

    Every launch opens on SplashView, which continues on a click and on no key
    (Views/SplashView.swift), so keystrokes typed at it vanish. And on the home
    screen the composer does not take focus by itself. Both cost a run that
    typed a probe into nothing.

    Both steps go through the accessibility tree, never a screen point. A
    `click at` the window's middle reaches SwiftUI's onTapGesture as an AX
    press, which it ignores (three tries, 1 Oct, the splash stayed up), and a
    fixed point once landed in another app because the window was on a second
    display at x=-1410. Pressing the splash's one button works wherever the
    window is.
    """
    if not composer_present():
        if on_splash():
            osascript(_in_process("click button 1 of group 1 of window 1"))
        if not wait_until(composer_present, timeout=timeout):
            raise DriveError("no chat composer on screen %ds after launch" % timeout)
    osascript(_in_process("set focused of %s to true" % COMPOSER))
    sleep(0.5)


def enter_text(text):
    """Put text in the composer through the accessibility tree.

    Not keystrokes: they go through the input method, and with Vietnamese
    Telex active on 1 Oct the probe arrived as "smoke tét ... reply with thí
    code". A hex token can be rewritten the same way. Setting the value
    reaches SwiftUI's binding (measured on build 6: sent, replied in 6 s).
    """
    if not is_frontmost():
        raise DriveError("codepet is not the frontmost app; not writing into another app")
    osascript(_in_process("set value of %s to %s" % (COMPOSER, as_applescript_string(text))))


def composer_text():
    return osascript(_in_process("get value of " + COMPOSER))


def type_text(text):
    # A keystroke goes to whatever is frontmost. On 1 Oct a Simulator window
    # took focus mid-run; typing then would have sent the probe into it.
    if not is_frontmost():
        raise DriveError("codepet is not the frontmost app; not typing into another app")
    osascript(
        'tell application "System Events" to keystroke %s' % as_applescript_string(text)
    )


def press_enter():
    if not is_frontmost():
        raise DriveError("codepet is not the frontmost app; not pressing Enter in another app")
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
