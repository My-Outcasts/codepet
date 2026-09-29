import os
import shutil
import unittest
from unittest import mock

from smoke.checks import chat
from smoke.checks.chat import evaluate, mint_token, probe_text, reply_needle
from smoke.lib import transcript
from smoke.lib.result import ERROR, FAIL, PASS
from smoke.tests.test_transcript import FIXTURE, OTHER_THREAD, REPLIED, account_with


class Probe(unittest.TestCase):
    def test_a_token_is_unique_per_run(self):
        self.assertNotEqual(mint_token(), mint_token())

    def test_palindromes_are_rejected_to_prevent_false_pass(self):
        # A palindromic token makes reply_needle(token) == token,
        # so finding it in the store would prove our probe was saved,
        # not that anything replied. Loop until we get a non-palindrome.
        with mock.patch("smoke.checks.chat.uuid.uuid4") as mock_uuid:
            # Return a palindrome first, then a non-palindrome
            mock_uuid.side_effect = [
                mock.MagicMock(hex="abccba123456789abcdef0123456789"),  # palindrome at [:6] = "abccba"
                mock.MagicMock(hex="abcdef123456789abcdef0123456789"),  # non-palindrome at [:6] = "abcdef"
            ]
            token = mint_token()
            # Should loop past the palindrome and return the non-palindrome
            self.assertEqual(token, "abcdef")
            self.assertNotEqual(token, token[::-1])

    def test_the_reply_needle_does_not_appear_in_the_probe_we_type(self):
        # If it did, finding it would prove our own message was saved --
        # not that anything replied.
        token = "abc123"
        self.assertNotIn(reply_needle(token), probe_text(token))

    def test_the_needle_is_the_token_backwards(self):
        self.assertEqual(reply_needle("abc123"), "321cba")


class Evaluate(unittest.TestCase):
    def test_a_reply_in_the_transcript_passes(self):
        r = evaluate(sent=True, probe_seen=True, reply_seen=True,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, PASS)

    def test_no_reply_fails_and_names_the_timeout(self):
        r = evaluate(sent=True, probe_seen=True, reply_seen=False,
                     token="f3a91c", log_error=None, timeout=120)
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)
        self.assertIn("120", r.detail)

    def test_no_reply_fails_and_quotes_the_app(self):
        r = evaluate(sent=True, probe_seen=True, reply_seen=False,
                     token="f3a91c",
                     log_error="ChatTransport: non-streaming retry refused: billing")
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)
        self.assertIn("ChatTransport", r.evidence[0])

    def test_a_probe_missing_from_the_transcript_means_we_never_typed_it(self):
        # Our own message not reaching the transcript means the UI never received
        # the keystrokes -- a harness problem, not a broken chat pipeline.
        r = evaluate(sent=True, probe_seen=False, reply_seen=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)
        self.assertIn("keystrokes did not reach the chat", r.detail)

    def test_failing_to_type_at_all_is_an_error(self):
        r = evaluate(sent=False, probe_seen=False, reply_seen=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)


def no_log():
    return mock.MagicMock(lines=lambda: [])


class Run(unittest.TestCase):
    """chat.run end to end against the hand-traced transcript fixture.

    Only the UI is faked. The "app" is a side effect that writes the fixture
    into the account directory the way ChatThreadArchive would.
    """

    def setUp(self):
        self.root, self.dir = account_with(fixture=None)
        self.addCleanup(shutil.rmtree, self.root)
        self.path = os.path.join(self.dir, transcript.FILENAME)
        self.events = []
        self.typed = []

    def app_writes_fixture(self, *a, **k):
        shutil.copy(FIXTURE, self.path)

    def go(self, token=REPLIED, on_type=None, on_quit=None, uid="uid123", **kw):
        events, typed = self.events, self.typed

        def type_text(text):
            events.append("type")
            typed.append(text)
            if on_type:
                on_type()

        def quit_app(*a, **k):
            events.append("quit")
            if on_quit:
                on_quit()
            return True

        kw.setdefault("timeout", 0)
        kw.setdefault("sleep", lambda s: events.append(("sleep", s)))
        with mock.patch.object(chat.drive, "focus", lambda: events.append("focus")), \
                mock.patch.object(chat.drive, "type_text", type_text), \
                mock.patch.object(chat.drive, "press_enter", lambda: events.append("enter")), \
                mock.patch.object(chat.drive, "quit_app", quit_app):
            return chat.run(token, no_log(), uid=uid, accounts_root=self.root, **kw)

    def test_a_reply_in_the_transcript_passes(self):
        r = self.go(on_type=self.app_writes_fixture)
        self.assertEqual(r.status, PASS, r.detail)
        self.assertIn(REPLIED, r.detail)

    def test_a_probe_with_no_reply_in_its_thread_fails(self):
        r = self.go(token=OTHER_THREAD, on_type=self.app_writes_fixture)
        self.assertEqual(r.status, FAIL, r.detail)

    def test_a_probe_that_never_reached_the_transcript_is_an_error(self):
        r = self.go(on_type=None)
        self.assertEqual(r.status, ERROR)
        self.assertIn("keystrokes did not reach the chat", r.detail)

    def test_the_verdict_is_read_after_quit(self):
        # The reply only lands as the app quits (an async save draining).
        # A verdict taken from the live poll alone would call this a FAIL.
        r = self.go(on_quit=self.app_writes_fixture)
        self.assertEqual(r.status, PASS, r.detail)

    def test_the_app_is_quit_once_the_reply_is_seen(self):
        self.go(on_type=self.app_writes_fixture)
        self.assertIn("quit", self.events)
        self.assertLess(self.events.index("type"), self.events.index("quit"))

    def test_an_unresolvable_account_is_an_error_and_drives_nothing(self):
        r = self.go(uid="nobody")
        self.assertEqual(r.status, ERROR)
        self.assertIn("no chat transcript", r.detail)
        self.assertNotIn("type", self.events)

    def test_an_unreadable_transcript_after_quit_is_an_error(self):
        def corrupt():
            with open(self.path, "w") as f:
                f.write("{not json")
        r = self.go(on_type=self.app_writes_fixture, on_quit=corrupt)
        self.assertEqual(r.status, ERROR)
        self.assertIn("could not read the chat transcript", r.detail)

    def test_a_drive_error_is_an_error_and_still_quits(self):
        def fail():
            raise chat.drive.DriveError("assistive access dropped")
        r = self.go(on_type=fail)
        self.assertEqual(r.status, ERROR)
        self.assertIn("quit", self.events)

    def test_it_waits_the_default_settle_before_touching_the_ui(self):
        self.go(on_type=self.app_writes_fixture)
        self.assertEqual(self.events[0], ("sleep", 8.0))
        self.assertLess(self.events.index(("sleep", 8.0)), self.events.index("focus"))

    def test_the_settle_is_configurable(self):
        self.go(on_type=self.app_writes_fixture, settle=2.5)
        self.assertEqual(self.events[0], ("sleep", 2.5))

    def test_it_polls_until_the_reply_lands(self):
        clock = [0.0]
        polls = []

        def sleep(s):
            polls.append(s)
            clock[0] += s
            if polls.count(2.0) == 3:
                self.app_writes_fixture()

        r = self.go(timeout=60, poll=2.0, settle=0, sleep=sleep, now=lambda: clock[0])
        self.assertEqual(r.status, PASS, r.detail)
        self.assertEqual(polls.count(2.0), 3)


if __name__ == "__main__":
    unittest.main()
