import unittest
from unittest.mock import Mock, patch, MagicMock

from smoke.lib import build as build_lib
from smoke.lib.watch import Fingerprint, fingerprint, is_fresh, may_drive, watch_loop
from smoke.lib.lock import LockHeld
import os
import plistlib
import shutil
import tempfile


def make_bundle(version="5", signed=True, info=None):
    root = tempfile.mkdtemp()
    app = os.path.join(root, "codepet.app")
    os.makedirs(os.path.join(app, "Contents", "_CodeSignature"))
    with open(os.path.join(app, "Contents", "Info.plist"), "wb") as f:
        f.write(info if info is not None else plistlib.dumps({"CFBundleVersion": version}))
    if signed:
        with open(os.path.join(app, "Contents", "_CodeSignature", "CodeResources"), "w") as f:
            f.write("<plist/>")
    return root, app


class Fingerprinting(unittest.TestCase):
    def bundle(self, **kw):
        root, app = make_bundle(**kw)
        self.addCleanup(shutil.rmtree, root)
        return app

    def sig(self, app):
        return os.path.join(app, "Contents", "_CodeSignature", "CodeResources")

    def test_it_is_the_bundle_version_and_the_signature_mtime(self):
        app = self.bundle(version="7")
        os.utime(self.sig(app), (1000.0, 1000.0))
        self.assertEqual(fingerprint(app), Fingerprint("7", 1000.0))

    def test_an_info_plist_touch_alone_is_not_a_new_build(self):
        # Info.plist is written early in a build; signing is the last write.
        app = self.bundle()
        os.utime(self.sig(app), (1000.0, 1000.0))
        before = fingerprint(app)
        os.utime(os.path.join(app, "Contents", "Info.plist"), (2000.0, 2000.0))
        self.assertFalse(is_fresh(fingerprint(app), before))

    def test_a_new_signature_is_a_new_build(self):
        app = self.bundle()
        os.utime(self.sig(app), (1000.0, 1000.0))
        before = fingerprint(app)
        os.utime(self.sig(app), (2000.0, 2000.0))
        self.assertTrue(is_fresh(fingerprint(app), before))

    def test_it_never_runs_codesign(self):
        app = self.bundle()
        with patch("subprocess.run", side_effect=AssertionError("subprocess per poll")):
            fingerprint(app)

    def test_no_bundle_is_build_missing(self):
        with self.assertRaises(build_lib.BuildMissing):
            fingerprint("/no/such/codepet.app")

    def test_an_unsigned_bundle_is_not_settled(self):
        with self.assertRaises(build_lib.BuildMissing):
            fingerprint(self.bundle(signed=False))

    def test_a_half_written_xml_plist_is_not_settled(self):
        # Truncated XML raises expat's ExpatError, which is NOT a ValueError.
        full = plistlib.dumps({"CFBundleVersion": "5"})
        with self.assertRaises(build_lib.BuildMissing):
            fingerprint(self.bundle(info=full[:len(full) // 2]))

    def test_a_half_written_binary_plist_is_not_settled(self):
        with self.assertRaises(build_lib.BuildMissing):
            fingerprint(self.bundle(info=b"bplist00\x00\x01"))

    def test_an_empty_plist_is_not_settled(self):
        with self.assertRaises(build_lib.BuildMissing):
            fingerprint(self.bundle(info=b""))

    def test_a_plist_that_is_not_a_dictionary_is_not_settled(self):
        with self.assertRaises(build_lib.BuildMissing):
            fingerprint(self.bundle(info=plistlib.dumps(["not", "a", "dict"])))


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
        # Same fingerprint repeats; without previous_fp = current, run would be retried.
        fp1 = Fingerprint("2", 100.0)
        # Pass 1: fp1 (outer) + fp1 (debounce), run crashes, previous_fp = fp1
        # Pass 2: fp1 (outer, not fresh), continues without running
        # Pass 3: fp1 (outer, not fresh), continues without running
        fingerprint_fn = Mock(return_value=fp1)
        run_fn = Mock(side_effect=[RuntimeError("test crash")])
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

        # Should have run exactly once; without previous_fp = current, would run 3 times
        self.assertEqual(run_fn.call_count, 1)
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

    def test_a_missing_bundle_says_waiting_once(self):
        fingerprint_fn = Mock(side_effect=build_lib.BuildMissing("app"))
        with patch("builtins.print") as print_mock:
            watch_loop("/x/codepet.app", "a@b.c", "/here", sleep=lambda s: None,
                       fingerprint_fn=fingerprint_fn, run=Mock(),
                       is_running=Mock(return_value=False), max_passes=4)
        waiting = [c for c in print_mock.call_args_list if "waiting for" in str(c)]
        self.assertEqual(len(waiting), 1)
        self.assertIn("/x/codepet.app", str(waiting[0]))

    def test_a_version_change_during_debounce_keeps_debouncing(self):
        # Same signature mtime, new CFBundleVersion: not settled yet.
        a, b = Fingerprint("5", 100.0), Fingerprint("6", 100.0)
        fingerprint_fn = Mock(side_effect=[a, b, b])
        report = Mock()
        report.verdict.return_value = "green"
        run_fn = Mock(return_value=(report, "/where"))
        with patch("builtins.print"), patch("smoke.lib.watch.Lock"), \
                patch("smoke.lib.watch.slack.format_message", return_value="m"), \
                patch("smoke.lib.watch.slack.should_post", return_value=False):
            watch_loop("/app", "a@b.c", "/here", sleep=lambda s: None,
                       fingerprint_fn=fingerprint_fn, run=run_fn,
                       is_running=Mock(return_value=False), max_passes=1)
        self.assertEqual(fingerprint_fn.call_count, 3)
        self.assertEqual(run_fn.call_count, 1)

    def test_watch_says_when_the_app_it_launched_is_still_running(self):
        report = Mock()
        report.verdict.return_value = "red"
        report.app_left_running = True
        with patch("builtins.print") as p, patch("smoke.lib.watch.Lock"), \
                patch("smoke.lib.watch.slack.format_message", return_value="m"), \
                patch("smoke.lib.watch.slack.should_post", return_value=False):
            watch_loop("/app", "a@b.c", "/here", sleep=lambda s: None,
                       fingerprint_fn=Mock(return_value=Fingerprint("2", 1.0)),
                       run=Mock(return_value=(report, "/w")),
                       is_running=Mock(return_value=False), max_passes=1)
        self.assertIn("smoke-launched app is still running", str(p.call_args_list))

    def test_the_uid_reaches_each_run(self):
        fp = Fingerprint("2", 100.0)
        report = Mock()
        report.verdict.return_value = "green"
        run_fn = Mock(return_value=(report, "/where"))
        with patch("builtins.print"), patch("smoke.lib.watch.Lock"), \
                patch("smoke.lib.watch.slack.format_message", return_value="m"), \
                patch("smoke.lib.watch.slack.should_post", return_value=False):
            watch_loop("/app", "a@b.c", "/here", sleep=lambda s: None,
                       fingerprint_fn=Mock(return_value=fp), run=run_fn,
                       is_running=Mock(return_value=False), max_passes=1, uid="u42", settle=3.0)
        self.assertEqual(run_fn.call_args[1]["uid"], "u42")
        self.assertEqual(run_fn.call_args[1]["settle"], 3.0)

    def test_transition_rule_posts_once(self):
        # Transition rule: post only when verdict changes.
        # Two runs with same verdict post once; third run with different verdict posts again.
        fp1 = Fingerprint("2", 100.0)
        fp2 = Fingerprint("2", 101.0)
        fp3 = Fingerprint("2", 102.0)
        # Pass 1: fp1 + run (green) -> should_post True (first) -> post
        # Pass 2: fp2 + run (green) -> should_post False (same verdict) -> no post
        # Pass 3: fp3 + run (red) -> should_post True (verdict changed) -> post
        fingerprint_fn = Mock(side_effect=[fp1, fp1, fp2, fp2, fp3, fp3])
        report1 = Mock()
        report1.verdict.return_value = "green"
        report2 = Mock()
        report2.verdict.return_value = "green"
        report3 = Mock()
        report3.verdict.return_value = "red"
        run_fn = Mock(side_effect=[(report1, "/where"), (report2, "/where"), (report3, "/where")])
        is_running_fn = Mock(return_value=False)
        read_webhook_fn = Mock(return_value="http://hook")
        post_fn = Mock(return_value=(True, ""))

        def sleep_mock(duration):
            pass

        with patch("builtins.print"):
            with patch("smoke.lib.watch.Lock") as lock_mock:
                with patch("smoke.lib.watch.slack.format_message", return_value="test message"):
                    lock_mock.return_value.__enter__ = Mock(return_value=None)
                    lock_mock.return_value.__exit__ = Mock(return_value=None)
                    # Use real should_post, not mocked; it reads verdict change from previous_verdict
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
                        max_passes=3,
                    )

        # Should have run three times (three fingerprint changes)
        self.assertEqual(run_fn.call_count, 3)
        # Should have posted twice: on first run (verdict=None->green) and on verdict change (green->red)
        # Without previous_verdict tracking, would post three times
        self.assertEqual(post_fn.call_count, 2)


if __name__ == "__main__":
    unittest.main()
