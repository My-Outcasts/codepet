import unittest

from smoke.checks.launch import evaluate
from smoke.lib.build import Build
from smoke.lib.result import ERROR, FAIL, PASS


def build(signed=True, quarantined=False):
    return Build(
        path="/Applications/codepet.app", short_version="1.0", bundle_version="2",
        bundle_id="app.murror.codepet", signed=signed,
        signature="valid on disk" if signed else "code object is not signed at all",
        quarantined=quarantined, mtime=0.0,
    )


class Evaluate(unittest.TestCase):
    def test_a_good_launch_passes_and_says_how_fast(self):
        r = evaluate(build(), opened=True, process_seen=True, window_seen=True, elapsed=3.1)
        self.assertEqual(r.status, PASS)
        self.assertEqual(r.detail, "signed, not quarantined, window in 3.1s")

    def test_a_broken_signature_fails_before_anything_is_opened(self):
        r = evaluate(build(signed=False), opened=False, process_seen=False,
                     window_seen=False, elapsed=0.0)
        self.assertEqual(r.status, FAIL)
        self.assertIn("not signed", r.detail)

    def test_quarantine_fails_with_gatekeeper_named(self):
        r = evaluate(build(quarantined=True), opened=False, process_seen=False,
                     window_seen=False, elapsed=0.0)
        self.assertEqual(r.status, FAIL)
        self.assertIn("Gatekeeper", r.detail)

    def test_a_process_that_never_appeared_is_a_real_failure(self):
        r = evaluate(build(), opened=True, process_seen=False, window_seen=False, elapsed=45.0)
        self.assertEqual(r.status, FAIL)
        self.assertIn("no process", r.detail)

    def test_a_live_process_with_no_window_is_unobserved_not_broken(self):
        # count windows has reported 0 for a visibly open app. Calling that
        # FAIL would let a known lie manufacture a red build.
        r = evaluate(build(), opened=True, process_seen=True, window_seen=False, elapsed=45.0)
        self.assertEqual(r.status, ERROR)
        self.assertIn("0 windows", r.detail)

    def test_open_itself_failing_is_a_harness_error(self):
        r = evaluate(build(), opened=False, process_seen=False, window_seen=False,
                     elapsed=0.0)
        self.assertEqual(r.status, ERROR)


if __name__ == "__main__":
    unittest.main()
