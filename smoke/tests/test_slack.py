import unittest

from smoke.lib.build import Build
from smoke.lib.report import Report
from smoke.lib.result import ERROR, FAIL, PASS, SKIP, Result
from smoke.lib.slack import format_message, should_post


def a_report(results, mode="installed build"):
    build = Build("/Applications/codepet.app", "1.0", "2", "app.murror.codepet",
                  True, "valid on disk", False, 0.0)
    return Report(build=build, results=results, mode=mode, started=0.0, finished=134.0)


class Formatting(unittest.TestCase):
    def test_a_failing_run_leads_with_red_and_the_build(self):
        report = a_report([
            Result("launch", PASS, 3.1, "signed, not quarantined, window in 3.1s"),
            Result("auth", PASS, 0.2, "session restored for nguyen@murror.app"),
            Result("chat", FAIL, 90.0, "no reply persisted for probe f3a91c",
                   ["ChatTransport: non-streaming retry refused: billing"]),
            Result("task", SKIP, 0.0, "skipped (chat failed)"),
        ])
        text = format_message(report)
        self.assertTrue(text.startswith("\U0001F534 Codepet smoke — 1.0 (2)"))
        self.assertIn("installed build", text)
        self.assertIn("2m14s", text)
        self.assertIn("no reply persisted for probe f3a91c", text)
        # the app's own words, so the channel answers "what broke"
        self.assertIn("non-streaming retry refused: billing", text)

    def test_a_green_run_leads_with_green(self):
        text = format_message(a_report([Result("launch", PASS, 3.1, "fine")]))
        self.assertTrue(text.startswith("\U0001F7E2"))

    def test_an_errored_run_is_not_green(self):
        text = format_message(a_report([Result("launch", ERROR, 1.0, "no windows")]))
        self.assertFalse(text.startswith("\U0001F7E2"))


class TransitionRule(unittest.TestCase):
    def test_a_plain_run_always_posts(self):
        self.assertTrue(should_post("run", "green", previous_verdict="green"))

    def test_watch_stays_silent_on_an_unchanged_verdict(self):
        self.assertFalse(should_post("watch", "green", previous_verdict="green"))

    def test_watch_speaks_up_when_green_turns_red(self):
        self.assertTrue(should_post("watch", "red", previous_verdict="green"))

    def test_watch_speaks_up_on_the_very_first_run(self):
        self.assertTrue(should_post("watch", "green", previous_verdict=None))


if __name__ == "__main__":
    unittest.main()
