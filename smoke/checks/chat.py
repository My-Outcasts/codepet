"""Check 3 -- does a chat turn round-trip through the founder's local Claude Code?

This is the check that proves app -> the founder's local Claude Code -> model -> back, which no
unit test can: CompanyStore is driven through injected closures, and the
local Claude Code runs under the founder's own plan and configuration.

The verdict is read from the app's local chat transcript,
~/.codepet/accounts/<uid>/company_chats.json (see smoke/lib/transcript.py).
It is NOT read from the Firestore LevelDB: since 25 September the app keeps
chat in that file and "never Firestore" (codepet/Services/ChatThreadArchive.swift:5-10),
so a LevelDB scan could only ever have missed.

The verdict needle is the run token REVERSED. The probe we type contains the
token; only a genuine reply can contain it backwards. A pass needs our probe
as a founder message and, later in the same thread, a companion message with
the reversed token. A needle present in our own message would prove nothing.

Composer focus is NOT verified. We wait `settle` seconds after launch, then
activate the app and type, trusting the composer to hold keyboard focus. If it
does not, the probe never reaches the transcript and this reads as ERROR
("keystrokes did not reach the chat"), not as a broken chat. An app-side flag
saying the composer is focused would close that gap, but it is a product
change and the founder's decision.
"""

import time
import uuid

from smoke.lib import drive, transcript
from smoke.lib.logstream import first_error
from smoke.lib.result import ERROR, FAIL, PASS, Result

NAME = "chat"
SETTLE = 8.0
TOKEN_LEN = 12
MAX_MINTS = 20


def mint_token():
    while True:
        token = uuid.uuid4().hex[:TOKEN_LEN]
        # Reject palindromes: if token == token[::-1], then reply_needle(token) == token,
        # so finding it would prove our probe was saved, not that anything replied.
        if token != token[::-1]:
            return token


def fresh_token(token, before, mint=None):
    """Re-mint while the reversed needle is ALREADY in the transcript.

    A reply needle that pre-exists the run would pass without anything
    replying. 12 hex chars make that vanishingly rare, which is exactly why
    it gets a guard instead of a belief.
    """
    mint = mint or mint_token
    for _ in range(MAX_MINTS):
        if not before.contains(reply_needle(token)):
            return token
        token = mint()
    raise RuntimeError("could not mint a token absent from the transcript")


def probe_text(token):
    return (
        "smoke test %s -- reply with this code written backwards, nothing else: %s"
        % (token, token)
    )


def reply_needle(token):
    return token[::-1]


def evaluate(sent, probe_seen, reply_seen, token, log_error, timeout=90):
    evidence = [log_error] if log_error else []
    if not sent:
        return Result(NAME, ERROR, 0.0, "could not type the probe into the app", evidence)
    if not probe_seen:
        return Result(NAME, ERROR, 0.0,
                      "probe %s is not in the chat transcript -- the keystrokes did "
                      "not reach the chat" % token, evidence)
    if not reply_seen:
        return Result(NAME, FAIL, 0.0,
                      "no reply to probe %s in the chat transcript within %ds"
                      % (token, timeout), evidence)
    return Result(NAME, PASS, 0.0, "reply round-tripped for probe %s" % token, evidence)


def _log_evidence(capture):
    line = first_error(capture.lines())
    return [line] if line else []


def run(token, capture, uid=None, accounts_root=None, timeout=90, settle=SETTLE,
        poll=2.0, sleep=time.sleep, now=time.monotonic):
    started = time.time()

    def error(detail):
        return Result(NAME, ERROR, time.time() - started, detail, _log_evidence(capture))

    try:
        account_dir = transcript.resolve_account_dir(uid, root=accounts_root)
    except transcript.TranscriptMissing as e:
        return error("no chat transcript to read: %s" % e)

    # A window on screen is not a composer ready for keys: typing into a
    # launch still in progress drops keystrokes on the floor.
    sleep(settle)

    try:
        token = fresh_token(token, transcript.load(account_dir))
    except transcript.TranscriptMissing as e:
        return error("could not read the chat transcript: %s" % e)

    sent = False
    try:
        try:
            drive.focus()
            drive.type_text(probe_text(token))
            drive.press_enter()
            sent = True
        except drive.DriveError as e:
            result = evaluate(False, False, False, token, str(e), timeout=timeout)
            result.duration = time.time() - started
            return result

        # Poll while the app runs -- saves are atomic, so a live read is safe
        # and a hit returns in seconds. It only decides when to stop waiting.
        deadline = now() + timeout
        while True:
            try:
                if transcript.load(account_dir).reply_seen(token):
                    break
            except transcript.TranscriptMissing:
                pass  # a mid-run read is not the verdict; the one after quit is
            if now() >= deadline:
                break
            sleep(poll)
    finally:
        drive.quit_app()

    # The VERDICT is read after quit: saves are queued async
    # (ChatThreadArchive.swift:52), so only a quit app has finished writing.
    try:
        final = transcript.load(account_dir)
    except transcript.TranscriptMissing as e:
        return error("could not read the chat transcript: %s" % e)

    result = evaluate(sent, final.probe_seen(token), final.reply_seen(token), token,
                      first_error(capture.lines()), timeout=timeout)
    result.duration = time.time() - started
    return result
