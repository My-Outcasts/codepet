import importlib.machinery
import importlib.util
import os
import contextlib
import json
import tempfile
import unittest
from unittest import mock

from smoke.lib import runner
from smoke.lib.result import ERROR, FAIL, PASS, SKIP, Result

from smoke.lib.runner import downstream_of, order

CLI_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "smoke")


def load_cli():
    loader = importlib.machinery.SourceFileLoader("smoke_cli", CLI_PATH)
    spec = importlib.util.spec_from_loader("smoke_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class Ordering(unittest.TestCase):
    def test_the_declared_report_order_is_launch_auth_chat_task(self):
        # This is the order a REPORT reads in. Execution order differs (auth
        # reads the store only after chat has quit the app); see
        # Execute.test_the_checks_execute_launch_chat_auth_task.
        self.assertEqual(order(), ["launch", "auth", "chat", "task"])

    def test_a_failed_launch_skips_everything_after_it(self):
        self.assertEqual(downstream_of("launch"), ["auth", "chat", "task"])

    def test_a_failed_chat_skips_only_the_task(self):
        self.assertEqual(downstream_of("chat"), ["task"])


class Execute(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        rec = self.calls

        def check(name, status):
            def run(*a, **k):
                rec.append(name)
                return Result(name, status, 0.0, "")
            return run

        self.check = check
        self.drive = mock.Mock()
        self.drive.DriveError = runner.drive.DriveError
        self.quit_ok = True
        self.drive.quit_app.side_effect = lambda *a, **k: rec.append("quit") or self.quit_ok

        @contextlib.contextmanager
        def fake_capture(path):
            yield mock.Mock()

        self.patches = [
            mock.patch.object(runner, "drive", self.drive),
            mock.patch.object(runner, "Capture", fake_capture),
            mock.patch.object(runner.chat_check, "mint_token", lambda: "tok"),
        ]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)

    def go(self, launch=PASS, chat=PASS, with_task=False, chat_fn=None):
        with mock.patch.object(runner.launch_check, "run", self.check("launch", launch)), \
                mock.patch.object(runner.chat_check, "run", chat_fn or self.check("chat", chat)), \
                mock.patch.object(runner.auth_check, "run", self.check("auth", PASS)), \
                mock.patch.object(runner.task_check, "run", self.check("task", SKIP)):
            report, where = runner.execute("/nonexistent.app", "test", with_task,
                                           "a@b.c", runs_root=self.tmp.name)
        return {r.name: r for r in report.results}, where

    def _launch_kwargs(self, mode):
        m = mock.Mock(return_value=Result("launch", FAIL, 0.0, ""))
        with mock.patch.object(runner.launch_check, "run", m):
            runner.execute("/nonexistent.app", mode, False, "a@b.c",
                           runs_root=self.tmp.name)
        return m.call_args[1]

    def test_the_uid_reaches_the_chat_check(self):
        seen = {}

        def chat_run(*a, **k):
            seen.update(k)
            return Result("chat", PASS, 0.0, "")
        with mock.patch.object(runner.launch_check, "run", self.check("launch", PASS)), \
                mock.patch.object(runner.chat_check, "run", chat_run), \
                mock.patch.object(runner.auth_check, "run", self.check("auth", PASS)):
            runner.execute("/nonexistent.app", "test", False, "a@b.c",
                           runs_root=self.tmp.name, uid="u42", accounts_root="/acc")
        self.assertEqual(seen["uid"], "u42")
        self.assertEqual(seen["accounts_root"], "/acc")
        self.assertEqual(seen["settle"], 8.0)

    def test_the_checks_execute_launch_chat_auth_task(self):
        got, _ = self.go(with_task=True)
        ran = [c for c in self.calls if c != "quit"]
        self.assertEqual(ran, ["launch", "chat", "auth", "task"])
        # ...and the report still reads in the declared order.
        self.assertEqual(list(got), order())

    def test_a_local_build_is_not_assessed_by_gatekeeper(self):
        self.assertFalse(self._launch_kwargs("local build")["assess_gatekeeper"])

    def test_an_installed_or_downloaded_build_is_assessed(self):
        self.assertTrue(self._launch_kwargs("installed build")["assess_gatekeeper"])
        self.assertTrue(self._launch_kwargs("downloaded build")["assess_gatekeeper"])

    def test_a_failed_launch_skips_the_rest(self):
        got, _ = self.go(launch=FAIL)
        self.assertEqual([got[n].status for n in ("auth", "chat", "task")], [SKIP] * 3)
        self.assertNotIn("chat", self.calls)

    def test_the_app_is_quit_before_auth_reads_the_db(self):
        got, _ = self.go(chat=ERROR)
        self.assertLess(self.calls.index("quit"), self.calls.index("auth"))

    def test_an_app_that_will_not_quit_is_an_auth_error_and_the_store_is_not_read(self):
        self.quit_ok = False
        got, where = self.go()
        self.assertEqual(got["auth"].status, ERROR)
        self.assertEqual(got["auth"].detail, "app did not quit; store not read")
        self.assertNotIn("auth", self.calls)

    def test_an_app_that_will_not_quit_is_recorded_on_the_report(self):
        self.quit_ok = False
        with mock.patch.object(runner.launch_check, "run", self.check("launch", PASS)), \
                mock.patch.object(runner.chat_check, "run", self.check("chat", PASS)), \
                mock.patch.object(runner.auth_check, "run", self.check("auth", PASS)):
            report, where = runner.execute("/nonexistent.app", "test", False, "a@b.c",
                                           runs_root=self.tmp.name)
        self.assertTrue(report.app_left_running)
        self.assertEqual(runner.still_running_note(report), runner.STILL_RUNNING)
        with open(os.path.join(where, "report.json")) as f:
            self.assertTrue(json.load(f)["app_left_running"])

    def test_a_clean_quit_leaves_no_note(self):
        with mock.patch.object(runner.launch_check, "run", self.check("launch", PASS)), \
                mock.patch.object(runner.chat_check, "run", self.check("chat", PASS)), \
                mock.patch.object(runner.auth_check, "run", self.check("auth", PASS)):
            report, _ = runner.execute("/nonexistent.app", "test", False, "a@b.c",
                                       runs_root=self.tmp.name)
        self.assertFalse(report.app_left_running)
        self.assertIsNone(runner.still_running_note(report))

    def test_a_failed_chat_skips_the_task_even_when_requested(self):
        got, _ = self.go(chat=FAIL, with_task=True)
        self.assertEqual(got["task"].status, SKIP)
        self.assertIn("chat", got["task"].detail)
        self.assertNotIn("task", self.calls)

    def test_a_crashing_check_is_reported_not_raised(self):
        def boom(*a, **k):
            raise RuntimeError("kaboom")
        got, where = self.go(chat_fn=boom)
        self.assertEqual(got["chat"].status, ERROR)
        self.assertIn("check crashed", got["chat"].detail)
        self.assertEqual(got["task"].status, SKIP)
        self.assertIn("quit", self.calls)
        with open(os.path.join(where, "report.json")) as f:
            self.assertEqual(json.load(f)["verdict"], "red")
        self.assertTrue(os.path.exists(os.path.join(where, "report.html")))

    def test_a_requested_task_relaunches_nothing(self):
        # The task check drives nothing yet; a relaunch would cost a launch
        # and, once typed into, credits -- for a check that can only SKIP.
        got, _ = self.go(with_task=True)
        self.drive.launch.assert_not_called()

    def test_a_requested_task_reaches_the_real_check_as_a_skip(self):
        with mock.patch.object(runner.launch_check, "run", self.check("launch", PASS)), \
                mock.patch.object(runner.chat_check, "run", self.check("chat", PASS)), \
                mock.patch.object(runner.auth_check, "run", self.check("auth", PASS)):
            report, _ = runner.execute("/nonexistent.app", "test", True, "a@b.c",
                                       runs_root=self.tmp.name)
        task = {r.name: r for r in report.results}["task"]
        self.assertEqual(task.status, SKIP)
        self.assertIn("not yet verifiable", task.detail)
        self.drive.launch.assert_not_called()


class Cli(unittest.TestCase):
    def test_a_running_app_defers_the_run_and_is_never_quit(self):
        cli = load_cli()
        with mock.patch.object(cli.drive, "is_running", return_value=True), \
                mock.patch.object(cli, "execute") as ex, \
                mock.patch.object(cli, "Lock") as lock:
            rc = cli.main(["run", "--account", "a@b.c"])
        self.assertEqual(rc, 2)
        ex.assert_not_called()
        lock.assert_not_called()

    def test_no_account_is_refused_before_anything_runs(self):
        cli = load_cli()
        env = {k: v for k, v in os.environ.items() if k != "CODEPET_SMOKE_ACCOUNT"}
        with mock.patch.dict(os.environ, env, clear=True), \
                mock.patch.object(cli.drive, "is_running", return_value=False), \
                mock.patch.object(cli, "execute") as ex, \
                mock.patch.object(cli, "Lock") as lock:
            rc = cli.main(["run"])
        self.assertEqual(rc, 2)
        ex.assert_not_called()
        lock.assert_not_called()

    def test_the_account_can_come_from_the_environment(self):
        cli = load_cli()
        with mock.patch.dict(os.environ, {"CODEPET_SMOKE_ACCOUNT": "x@y.z"}):
            args = cli.parse(["run"])
        self.assertEqual(args.account, "x@y.z")

    def test_uid_is_passed_to_execute(self):
        cli = load_cli()
        report = mock.Mock()
        report.verdict.return_value = "green"
        with mock.patch.object(cli.drive, "is_running", return_value=False), \
                mock.patch.object(cli, "execute", return_value=(report, "/r")) as ex, \
                mock.patch.object(cli, "Lock"), \
                mock.patch.object(cli.slack, "format_message", return_value="msg"), \
                mock.patch.object(cli.slack, "read_webhook", return_value=None):
            cli.main(["run", "--account", "a@b.c", "--dev", "/x.app", "--uid", "u42"])
        self.assertEqual(ex.call_args[1]["uid"], "u42")
        self.assertEqual(ex.call_args[1]["settle"], 8.0)

    def test_the_cli_says_when_the_app_it_launched_is_still_running(self):
        cli = load_cli()
        report = mock.Mock()
        report.verdict.return_value = "red"
        report.app_left_running = True
        with mock.patch.object(cli.drive, "is_running", return_value=False), \
                mock.patch.object(cli, "execute", return_value=(report, "/r")), \
                mock.patch.object(cli, "Lock"), \
                mock.patch.object(cli.slack, "format_message", return_value="msg"), \
                mock.patch("builtins.print") as p:
            cli.main(["run", "--account", "a@b.c", "--dev", "/x.app"])
        self.assertIn("smoke-launched app is still running", str(p.call_args_list))

    def test_settle_is_a_flag_on_run_and_watch(self):
        cli = load_cli()
        self.assertEqual(cli.parse(["run", "--settle", "3"]).settle, 3.0)
        self.assertEqual(cli.parse(["watch", "/x.app", "--settle", "3"]).settle, 3.0)
        self.assertEqual(cli.parse(["run"]).settle, 8.0)

    def test_watch_gets_the_uid(self):
        cli = load_cli()
        import smoke.lib.watch as watch_mod
        with mock.patch.object(watch_mod, "watch_loop", return_value=0) as wl:
            cli.main(["watch", "/x.app", "--account", "a@b.c", "--uid", "u42"])
        self.assertEqual(wl.call_args[1]["uid"], "u42")
        self.assertEqual(wl.call_args[1]["settle"], 8.0)

    def _run_with_dmg(self, argv, install):
        cli = load_cli()
        report = mock.Mock()
        report.verdict.return_value = "green"
        with mock.patch.object(cli.drive, "is_running", return_value=False), \
                mock.patch.object(cli.dmg, "install", install), \
                mock.patch.object(cli, "execute", return_value=(report, "/r")) as ex, \
                mock.patch.object(cli, "Lock") as lock, \
                mock.patch.object(cli.slack, "format_message", return_value="msg"), \
                mock.patch.object(cli.slack, "read_webhook", return_value=None):
            rc = cli.main(argv)
        return cli, rc, ex, lock

    def test_dmg_tests_the_installed_copy_as_a_downloaded_build(self):
        install = mock.Mock(return_value="/w/codepet.app")
        cli, rc, ex, _ = self._run_with_dmg(
            ["run", "--account", "a@b.c", "--dmg", "https://x/y.dmg"], install)
        self.assertEqual(rc, 0)
        self.assertEqual(install.call_args[0][0], "https://x/y.dmg")
        self.assertEqual(ex.call_args[0][:2], ("/w/codepet.app", "downloaded build"))

    def test_a_bare_dmg_uses_the_download_page(self):
        install = mock.Mock(return_value="/w/codepet.app")
        cli, rc, ex, _ = self._run_with_dmg(["run", "--account", "a@b.c", "--dmg"], install)
        self.assertEqual(install.call_args[0][0], cli.dmg.DEFAULT_URL)

    def _failed_install(self, error):
        cli = load_cli()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        real = runner.report_failed_launch

        def failed(label, mode, launch):
            return real(label, mode, launch, runs_root=tmp.name)
        with mock.patch.object(cli.drive, "is_running", return_value=False), \
                mock.patch.object(cli.dmg, "install", mock.Mock(side_effect=error)), \
                mock.patch.object(cli, "report_failed_launch", failed), \
                mock.patch.object(cli, "execute") as ex, \
                mock.patch.object(cli, "Lock") as lock, \
                mock.patch.object(cli.slack, "read_webhook", return_value="http://hook"), \
                mock.patch.object(cli.slack, "post", return_value=(True, "posted")) as post, \
                mock.patch("builtins.print"):
            rc = cli.main(["run", "--account", "a@b.c", "--dmg"])
        return rc, ex, lock, post

    def test_a_404_install_is_a_launch_fail_that_reaches_slack(self):
        from smoke.lib.dmg import DmgError
        rc, ex, lock, post = self._failed_install(
            DmgError("could not download https://x: HTTP 404", FAIL))
        self.assertEqual(rc, 1)
        ex.assert_not_called()
        lock.assert_not_called()
        text = post.call_args[0][1]
        self.assertTrue(text.startswith("\U0001F534"))
        self.assertIn("HTTP 404", text)
        self.assertIn("❌ Launch", text)

    def test_another_install_failure_is_a_launch_error_that_reaches_slack(self):
        from smoke.lib.dmg import DmgError
        rc, _, _, post = self._failed_install(DmgError("hdiutil attach failed"))
        self.assertEqual(rc, 1)
        self.assertIn("⚠️ Launch", post.call_args[0][1])


class FailedLaunchReport(unittest.TestCase):
    def test_it_writes_a_report_with_the_rest_skipped(self):
        with tempfile.TemporaryDirectory() as root:
            report, where = runner.report_failed_launch(
                "https://x/Codepet.dmg", "downloaded build",
                Result("launch", FAIL, 0.0, "the disk image is not signed/notarized: x"),
                runs_root=root)
            got = {r.name: r.status for r in report.results}
            self.assertEqual(got, {"launch": FAIL, "auth": SKIP, "chat": SKIP, "task": SKIP})
            self.assertEqual([r.name for r in report.results], order())
            with open(os.path.join(where, "report.json")) as f:
                data = json.load(f)
            self.assertEqual(data["verdict"], "red")
            self.assertEqual(data["mode"], "downloaded build")
            self.assertTrue(os.path.exists(os.path.join(where, "report.html")))


if __name__ == "__main__":
    unittest.main()
