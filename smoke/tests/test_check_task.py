import unittest
from unittest import mock

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

    def test_no_deliverable_fails_and_names_the_timeout(self):
        r = evaluate(requested=True, sent=True, deliverable_persisted=False,
                     token="f3a91c", log_error=None, timeout=300)
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)
        self.assertIn("300", r.detail)

    def test_no_deliverable_fails(self):
        r = evaluate(requested=True, sent=True, deliverable_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, FAIL)
        self.assertIn("f3a91c", r.detail)

    def test_failing_to_drive_it_is_an_error(self):
        r = evaluate(requested=True, sent=False, deliverable_persisted=False,
                     token="f3a91c", log_error=None)
        self.assertEqual(r.status, ERROR)


class Run(unittest.TestCase):
    def test_app_not_running_returns_error_immediately(self):
        # Before typing anything, check if app is running.
        # If not, return ERROR and never call type_text.
        from smoke.checks.task import run

        token = "abc123"
        with mock.patch("smoke.lib.drive.is_running", return_value=False):
            with mock.patch("smoke.lib.drive.focus"):
                with mock.patch("smoke.lib.drive.type_text") as mock_type:
                    r = run(token, mock.MagicMock(lines=lambda: []), requested=True)
                    self.assertEqual(r.status, ERROR)
                    self.assertIn("not running", r.detail)
                    mock_type.assert_not_called()

    def test_store_missing_quits_the_app_and_returns_error(self):
        # If store.wait_for raises StoreMissing, quit_app() must still run.
        from smoke.lib import store
        from smoke.checks.task import run

        token = "abc123"
        with mock.patch("smoke.lib.drive.is_running", return_value=True):
            with mock.patch("smoke.lib.drive.focus"):
                with mock.patch("smoke.lib.drive.type_text"):
                    with mock.patch("smoke.lib.drive.press_enter"):
                        with mock.patch("smoke.lib.drive.quit_app") as mock_quit:
                            with mock.patch("smoke.lib.store.wait_for") as mock_wait:
                                mock_wait.side_effect = store.StoreMissing()
                                r = run(token, mock.MagicMock(lines=lambda: []), requested=True)
                                self.assertEqual(r.status, ERROR)
                                mock_quit.assert_called_once()


if __name__ == "__main__":
    unittest.main()
