import unittest
from unittest.mock import Mock, patch, MagicMock

from smoke.lib import build as build_lib
from smoke.lib.watch import Fingerprint, is_fresh, may_drive, watch_loop
from smoke.lib.lock import LockHeld


class Freshness(unittest.TestCase):
    def test_the_first_sighting_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("2", 100.0), None))

    def test_an_unchanged_bundle_is_not_fresh(self):
        # The stale-build trap, caught by the tool instead of by a person
        # concluding their change did not work.
        f = Fingerprint("2", 100.0)
        self.assertFalse(is_fresh(f, Fingerprint("2", 100.0)))

    def test_a_new_mtime_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("2", 200.0), Fingerprint("2", 100.0)))

    def test_a_new_bundle_version_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("3", 100.0), Fingerprint("2", 100.0)))


class Hijacking(unittest.TestCase):
    def test_it_drives_when_nothing_is_running(self):
        may, why = may_drive(app_running=False, we_launched_it=False)
        self.assertTrue(may)

    def test_it_defers_to_the_founders_own_app(self):
        may, why = may_drive(app_running=True, we_launched_it=False)
        self.assertFalse(may)
        self.assertIn("your app is running", why)

    def test_it_may_drive_an_app_it_launched_itself(self):
        may, why = may_drive(app_running=True, we_launched_it=True)
        self.assertTrue(may)


class Loop(unittest.TestCase):
    def test_build_missing_during_debounce_does_not_raise(self):
        # If the bundle is briefly removed during debounce, restart polling.
        # This catches the stale binary case where the build folder is renamed.
        fp_calls = [
            Fingerprint("2", 100.0),  # outer loop: fresh
            build_lib.BuildMissing("app"),  # debounce: bundle removed
            Fingerprint("2", 101.0),  # restart: bundle back, new mtime
            build_lib.BuildMissing("app"),  # debounce again
        ]
        fingerprint_fn = Mock(side_effect=fp_calls)
        run_fn = Mock()
        is_running_fn = Mock(return_value=False)
        post_fn = Mock()

        sleep_log = []

        def sleep_mock(duration):
            sleep_log.append(duration)

        with patch("builtins.print"):
            watch_loop(
                "/app",
                "account@test.com",
                "/here",
                sleep=sleep_mock,
                fingerprint_fn=fingerprint_fn,
                run=run_fn,
                is_running=is_running_fn,
                post_fn=post_fn,
                max_passes=2,
            )

        # Should have called fingerprint 4 times, never raised
        self.assertEqual(fingerprint_fn.call_count, 4)
        # Should never have run (debounce kept crashing)
        run_fn.assert_not_called()

    def test_execute_exception_does_not_raise(self):
        # If a run crashes, consume the build and keep watching.
        fp1 = Fingerprint("2", 100.0)
        fp2 = Fingerprint("2", 101.0)
        # Pass 1: fp1 (outer) + fp1 (debounce), run crashes
        # Pass 2: fp2 (outer) + fp2 (debounce), run succeeds
        # Pass 3: fp2 (outer, not fresh), continues
        fingerprint_fn = Mock(side_effect=[fp1, fp1, fp2, fp2, fp2])
        report_mock = Mock()
        report_mock.verdict.return_value = "green"
        run_fn = Mock(side_effect=[RuntimeError("test crash"), (report_mock, "/where")])
        is_running_fn = Mock(return_value=False)
        post_fn = Mock(return_value=(True, ""))

        def sleep_mock(duration):
            pass

        with patch("builtins.print") as print_mock:
            with patch("smoke.lib.watch.Lock") as lock_mock:
                with patch("smoke.lib.watch.slack.format_message", return_value="test message"):
                    with patch("smoke.lib.watch.slack.should_post", return_value=False):
                        lock_mock.return_value.__enter__ = Mock(return_value=None)
                        lock_mock.return_value.__exit__ = Mock(return_value=None)
                        watch_loop(
                            "/app",
                            "account@test.com",
                            "/here",
                            sleep=sleep_mock,
                            fingerprint_fn=fingerprint_fn,
                            run=run_fn,
                            is_running=is_running_fn,
                            post_fn=post_fn,
                            max_passes=3,
                        )

        # Should have tried to run twice
        self.assertEqual(run_fn.call_count, 2)
        # Should have printed the crash
        printed = str(print_mock.call_args_list)
        self.assertIn("run crashed", printed)
        self.assertIn("RuntimeError", printed)

    def test_founder_app_running_defers_once_per_fingerprint(self):
        # If founder app is running, defer and print once per fingerprint.
        # Multiple passes with the same fingerprint should not print again.
        fp = Fingerprint("2", 100.0)
        fingerprint_fn = Mock(return_value=fp)
        run_fn = Mock()
        is_running_fn = Mock(return_value=True)
        post_fn = Mock()

        sleep_log = []

        def sleep_mock(duration):
            sleep_log.append(duration)

        with patch("builtins.print") as print_mock:
            watch_loop(
                "/app",
                "account@test.com",
                "/here",
                sleep=sleep_mock,
                fingerprint_fn=fingerprint_fn,
                run=run_fn,
                is_running=is_running_fn,
                post_fn=post_fn,
                max_passes=3,
            )

        # Should never run
        run_fn.assert_not_called()
        # Should print "deferred" only once (per pass it appears, but logic defers once per fp)
        printed_lines = [str(call) for call in print_mock.call_args_list]
        deferred_count = sum(1 for line in printed_lines if "deferred" in line)
        self.assertEqual(deferred_count, 1)

    def test_unchanged_fingerprint_after_run_not_rerun(self):
        # After a run completes, if fingerprint is unchanged, do not run again.
        fp1 = Fingerprint("2", 100.0)
        fp2 = Fingerprint("2", 101.0)
        # Pass 1: fp1 (outer) + fp1 (debounce), run succeeds
        # Pass 2: fp2 (outer) + fp2 (debounce), run succeeds
        # Pass 3: fp2 (outer, not fresh), continues
        fingerprint_fn = Mock(side_effect=[fp1, fp1, fp2, fp2, fp2])
        report_mock = Mock()
        report_mock.verdict.return_value = "green"
        run_fn = Mock(return_value=(report_mock, "/where"))
        is_running_fn = Mock(return_value=False)
        post_fn = Mock(return_value=(True, ""))

        def sleep_mock(duration):
            pass

        with patch("builtins.print"):
            with patch("smoke.lib.watch.Lock") as lock_mock:
                with patch("smoke.lib.watch.slack.format_message", return_value="test message"):
                    with patch("smoke.lib.watch.slack.should_post", return_value=False):
                        lock_mock.return_value.__enter__ = Mock(return_value=None)
                        lock_mock.return_value.__exit__ = Mock(return_value=None)
                        watch_loop(
                            "/app",
                            "account@test.com",
                            "/here",
                            sleep=sleep_mock,
                            fingerprint_fn=fingerprint_fn,
                            run=run_fn,
                            is_running=is_running_fn,
                            post_fn=post_fn,
                            max_passes=3,
                        )

        # Should run only twice (once per fresh fingerprint)
        self.assertEqual(run_fn.call_count, 2)

    def test_transition_rule_posts_once(self):
        # Two runs with same verdict should post only once (transition rule).
        fp1 = Fingerprint("2", 100.0)
        fp2 = Fingerprint("2", 101.0)
        # Pass 1: fp1 (outer) + fp1 (debounce), run succeeds (green)
        # Pass 2: fp2 (outer) + fp2 (debounce), run succeeds (green, same verdict)
        # Pass 3 would start but max_passes=2 stops after pass 2
        fingerprint_fn = Mock(side_effect=[fp1, fp1, fp2, fp2])
        report1 = Mock()
        report1.verdict.return_value = "green"
        report2 = Mock()
        report2.verdict.return_value = "green"
        run_fn = Mock(side_effect=[(report1, "/where"), (report2, "/where")])
        is_running_fn = Mock(return_value=False)
        read_webhook_fn = Mock(return_value="http://hook")
        post_fn = Mock(return_value=(True, ""))

        def sleep_mock(duration):
            pass

        with patch("builtins.print"):
            with patch("smoke.lib.watch.Lock") as lock_mock:
                with patch("smoke.lib.watch.slack.format_message", return_value="test message"):
                    with patch("smoke.lib.watch.slack.should_post", side_effect=[True, False]):
                        lock_mock.return_value.__enter__ = Mock(return_value=None)
                        lock_mock.return_value.__exit__ = Mock(return_value=None)
                        watch_loop(
                            "/app",
                            "account@test.com",
                            "/here",
                            sleep=sleep_mock,
                            fingerprint_fn=fingerprint_fn,
                            run=run_fn,
                            is_running=is_running_fn,
                            post_fn=post_fn,
                            read_webhook_fn=read_webhook_fn,
                            max_passes=2,
                        )

        # Should have run twice (two fingerprint changes)
        self.assertEqual(run_fn.call_count, 2)
        # Should have posted only once (verdict unchanged on second run)
        self.assertEqual(post_fn.call_count, 1)


if __name__ == "__main__":
    unittest.main()
