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
                                with mock.patch("smoke.checks.task.first_error") as mock_first_error:
                                    mock_first_error.return_value = "F some error"
                                    r = run(token, mock.MagicMock(lines=lambda: []), requested=True)
                                    self.assertEqual(r.status, ERROR)
                                    mock_quit.assert_called_once()
                                    # Verify evidence includes the log error
                                    self.assertIn("F some error", r.evidence)

    def test_quit_app_is_called_before_fallback_store_read(self):
        # The fallback store.contains reads only work if the app has quit
        # (memtable flushes on quit). quit_app() must run BEFORE those reads.
        from smoke.lib import store
        from smoke.checks.task import run

        token = "abc123"
        call_order = []

        def track_quit(*args, **kwargs):
            call_order.append("quit_app")
            return True

        def track_contains(*args, **kwargs):
            call_order.append("contains")
            return False

        with mock.patch("smoke.lib.drive.is_running", return_value=True):
            with mock.patch("smoke.lib.drive.focus"):
                with mock.patch("smoke.lib.drive.type_text"):
                    with mock.patch("smoke.lib.drive.press_enter"):
                        with mock.patch("smoke.lib.drive.quit_app", side_effect=track_quit):
                            with mock.patch("smoke.lib.store.wait_for", return_value=False):
                                with mock.patch("smoke.lib.store.contains", side_effect=track_contains):
                                    r = run(token, mock.MagicMock(lines=lambda: []), requested=True)
                                    # quit_app should be called before the first contains
                                    self.assertIn("quit_app", call_order)
                                    self.assertIn("contains", call_order)
                                    quit_index = call_order.index("quit_app")
                                    first_contains_index = call_order.index("contains")
                                    self.assertLess(quit_index, first_contains_index,
                                                   "quit_app must be called before fallback store.contains reads")


if __name__ == "__main__":
    unittest.main()
