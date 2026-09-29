import unittest
from unittest import mock

from smoke.checks import launch as launch_mod
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
        r = evaluate(build(), opened=True, process_seen=True, window_seen=True,
                     elapsed=3.1, gatekeeper=(True, "accepted"))
        self.assertEqual(r.status, PASS)
        self.assertEqual(r.detail, "signed, Gatekeeper accepts, window in 3.1s")

    def test_an_unassessed_build_says_so(self):
        r = evaluate(build(), opened=True, process_seen=True, window_seen=True,
                     elapsed=3.1, gatekeeper=None)
        self.assertEqual(r.detail,
                         "signed, Gatekeeper not assessed (local build), window in 3.1s")

    def test_a_broken_signature_fails_before_anything_is_opened(self):
        r = evaluate(build(signed=False), opened=False, process_seen=False,
                     window_seen=False, elapsed=0.0)
        self.assertEqual(r.status, FAIL)
        self.assertIn("not signed", r.detail)

    def test_quarantine_alone_never_fails(self):
        r = evaluate(build(quarantined=True), opened=True, process_seen=True,
                     window_seen=True, elapsed=3.1, gatekeeper=(True, "accepted"))
        self.assertEqual(r.status, PASS)
        self.assertIn("quarantined", r.detail)

    def test_a_gatekeeper_rejection_fails_naming_gatekeeper(self):
        r = evaluate(build(quarantined=True), opened=False, process_seen=False,
                     window_seen=False, elapsed=0.0, gatekeeper=(False, "rejected"))
        self.assertEqual(r.status, FAIL)
        self.assertEqual(r.detail, "Gatekeeper rejects the app: rejected")

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


class Run(unittest.TestCase):
    def go(self, gatekeeper_result, assess=True):
        with mock.patch.object(launch_mod.build_lib, "identify", return_value=build()), \
                mock.patch.object(launch_mod.build_lib, "assess_gatekeeper",
                                  return_value=gatekeeper_result) as ag, \
                mock.patch.object(launch_mod, "drive") as drv:
            drv.DriveError = Exception
            drv.wait_until.return_value = True
            r = launch_mod.run("/x.app", assess_gatekeeper=assess)
        return r, ag, drv

    def test_a_rejected_app_is_never_opened(self):
        r, ag, drv = self.go((False, "rejected"))
        self.assertEqual(r.status, FAIL)
        drv.launch.assert_not_called()

    def test_an_accepted_app_is_opened(self):
        r, ag, drv = self.go((True, "accepted"))
        self.assertEqual(r.status, PASS)
        drv.launch.assert_called_once()

    def test_a_local_build_is_not_assessed(self):
        r, ag, drv = self.go((False, "x"), assess=False)
        ag.assert_not_called()
        self.assertEqual(r.status, PASS)
        self.assertIn("not assessed", r.detail)


if __name__ == "__main__":
    unittest.main()
