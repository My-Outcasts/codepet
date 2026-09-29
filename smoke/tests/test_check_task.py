import unittest

from smoke.checks.task import deliverable_needle, evaluate, probe_text
from smoke.lib.result import ERROR, FAIL, PASS, SKIP


class Needle(unittest.TestCase):
    def test_it_is_token_scoped_not_the_bare_word(self):
        # "deliverable" alone had 15 hits in the live store before any run.
        self.assertEqual(deliverable_needle("abc123"), b"smoke-deliverable-321cba")

    def test_the_needle_does_not_appear_in_the_probe_we_type(self):
        token = "abc123"
        self.assertNotIn(deliverable_needle(token).decode(), probe_text(token))


class Evaluate(unittest.TestCase):
    def test_not_requested_is_skipped_and_says_why(self):
        r = evaluate(requested=False, sent=False, deliverable_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, SKIP)
        self.assertIn("--with-task", r.detail)

    def test_a_deliverable_in_the_store_passes(self):
        r = evaluate(requested=True, sent=True, deliverable_persisted=True,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, PASS)

    def test_no_deliverable_fails(self):
        r = evaluate(requested=True, sent=True, deliverable_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)

    def test_failing_to_drive_it_is_an_error(self):
        r = evaluate(requested=True, sent=False, deliverable_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)


if __name__ == "__main__":
    unittest.main()
