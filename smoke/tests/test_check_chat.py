import unittest

from smoke.checks.chat import evaluate, mint_token, probe_text, reply_needle
from smoke.lib.result import ERROR, FAIL, PASS


class Probe(unittest.TestCase):
    def test_a_token_is_unique_per_run(self):
        self.assertNotEqual(mint_token(), mint_token())

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


if __name__ == "__main__":
    unittest.main()
