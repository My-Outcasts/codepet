import unittest
from unittest import mock

from smoke.checks import task
from smoke.checks.task import evaluate, run
from smoke.lib.result import SKIP


class Evaluate(unittest.TestCase):
    def test_not_requested_is_skipped_and_says_how_to_ask(self):
        r = evaluate(requested=False)
        self.assertEqual(r.status, SKIP)
        self.assertIn("--with-task", r.detail)

    def test_requested_is_skipped_as_not_yet_verifiable(self):
        # A chat echo of a needle is not "a terminal state with a deliverable".
        r = evaluate(requested=True)
        self.assertEqual(r.status, SKIP)
        self.assertEqual(r.detail,
                         "task outcome not yet verifiable (no record-specific needle)")


class Run(unittest.TestCase):
    def test_a_requested_task_drives_nothing_and_spends_nothing(self):
        drive = mock.Mock()
        with mock.patch("smoke.lib.drive.launch", drive.launch), \
                mock.patch("smoke.lib.drive.focus", drive.focus), \
                mock.patch("smoke.lib.drive.type_text", drive.type_text), \
                mock.patch("smoke.lib.drive.press_enter", drive.press_enter):
            r = run("abc123abc124", mock.Mock(), requested=True)
        self.assertEqual(r.status, SKIP)
        self.assertIn("not yet verifiable", r.detail)
        self.assertEqual(drive.mock_calls, [])

    def test_the_task_module_does_not_import_the_driver(self):
        # The cheapest way to be sure it spends no credits: it cannot type.
        self.assertFalse(hasattr(task, "drive"))


if __name__ == "__main__":
    unittest.main()
