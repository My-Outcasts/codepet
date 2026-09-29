import unittest

from smoke.lib.result import (
    ERROR, FAIL, GREEN, PASS, RED, SKIP, UNVERIFIED,
    Result, run_verdict, skip_rest,
)


class RunVerdict(unittest.TestCase):
    def test_a_failure_makes_the_run_red(self):
        results = [Result("launch", PASS), Result("chat", FAIL)]
        self.assertEqual(run_verdict(results), RED)

    def test_a_broken_harness_is_red_not_green(self):
        # ERROR means we did not observe anything. It must not pass just
        # because no check actually reported a product defect.
        results = [Result("launch", PASS), Result("chat", ERROR)]
        self.assertEqual(run_verdict(results), RED)

    def test_everything_skipped_is_unverified_not_green(self):
        # ci-test.sh shipped reporting a non-building target as green.
        # A run that observed nothing is not a pass.
        results = [Result("launch", SKIP), Result("chat", SKIP)]
        self.assertEqual(run_verdict(results), UNVERIFIED)

    def test_all_passing_is_green(self):
        self.assertEqual(run_verdict([Result("launch", PASS)]), GREEN)


class SkipRest(unittest.TestCase):
    def test_it_names_the_reason_on_every_skipped_check(self):
        results = skip_rest(["auth", "chat"], "launch failed")
        self.assertEqual([r.name for r in results], ["auth", "chat"])
        self.assertTrue(all(r.status == SKIP for r in results))
        self.assertTrue(all(r.detail == "launch failed" for r in results))


if __name__ == "__main__":
    unittest.main()
