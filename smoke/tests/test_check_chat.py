import unittest
from unittest import mock

from smoke.checks.chat import evaluate, mint_token, probe_text, reply_needle
from smoke.lib.result import ERROR, FAIL, PASS


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
        self.assertNotIn(reply_needle(token).decode(), probe_text(token))

    def test_the_needle_is_the_token_backwards(self):
        self.assertEqual(reply_needle("abc123"), b"321cba")


class Evaluate(unittest.TestCase):
    def test_a_reply_that_reached_the_store_passes(self):
        r = evaluate(sent=True, probe_persisted=True, reply_persisted=True,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, PASS)

    def test_no_reply_fails_and_names_the_timeout(self):
        r = evaluate(sent=True, probe_persisted=True, reply_persisted=False,
                     token="f3a91c", log_error=None, timeout=120)
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)
        self.assertIn("120", r.detail)

    def test_no_reply_fails_and_quotes_the_app(self):
        r = evaluate(sent=True, probe_persisted=True, reply_persisted=False,
                     token="f3a91c",
                     log_error="ChatTransport: non-streaming retry refused: billing")
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)
        self.assertIn("ChatTransport", r.evidence[0])

    def test_a_probe_that_never_persisted_means_we_never_typed_it(self):
        # Our own message not reaching the store means the UI never received
        # the keystrokes -- a harness problem, not a broken chat pipeline.
        r = evaluate(sent=True, probe_persisted=False, reply_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)
        self.assertIn("never reached", r.detail)

    def test_failing_to_type_at_all_is_an_error(self):
        r = evaluate(sent=False, probe_persisted=False, reply_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)


class Run(unittest.TestCase):
    def test_store_missing_quits_the_app_and_returns_error_with_evidence(self):
        # If store.wait_for raises StoreMissing, quit_app() must still run.
        from smoke.lib import store, drive

        token = "abc123"
        with mock.patch("smoke.lib.drive.focus"):
            with mock.patch("smoke.lib.drive.type_text"):
                with mock.patch("smoke.lib.drive.press_enter"):
                    with mock.patch("smoke.lib.drive.quit_app") as mock_quit:
                        with mock.patch("smoke.lib.store.wait_for") as mock_wait:
                            mock_wait.side_effect = store.StoreMissing()
                            with mock.patch("smoke.checks.chat.first_error") as mock_first_error:
                                mock_first_error.return_value = "E some error"
                                from smoke.checks.chat import run
                                r = run(token, mock.MagicMock(lines=lambda: []))
                                self.assertEqual(r.status, ERROR)
                                mock_quit.assert_called_once()


if __name__ == "__main__":
    unittest.main()
