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
    def test_the_checks_run_in_dependency_order(self):
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
        self.drive.quit_app.side_effect = lambda *a, **k: rec.append("quit")

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
                mock.patch.object(runner.task_check, "run", self.check("task", PASS)), \
                mock.patch.object(runner.task_check, "evaluate",
                                  lambda req, *a, **k: Result(
                                      "task", FAIL if req else SKIP, 0.0, "")):
            report, where = runner.execute("/nonexistent.app", "test", with_task,
                                           "a@b.c", runs_root=self.tmp.name)
        return {r.name: r for r in report.results}, where

    def test_a_failed_launch_skips_the_rest(self):
        got, _ = self.go(launch=FAIL)
        self.assertEqual([got[n].status for n in ("auth", "chat", "task")], [SKIP] * 3)
        self.assertNotIn("chat", self.calls)

    def test_the_app_is_quit_before_auth_reads_the_db(self):
        got, _ = self.go(chat=ERROR)
        self.assertLess(self.calls.index("quit"), self.calls.index("auth"))

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

    def test_a_failed_relaunch_is_a_task_error(self):
        def launch(app, args=()):
            raise runner.drive.DriveError("no")
        self.drive.launch.side_effect = launch
        got, _ = self.go(with_task=True)
        self.assertEqual(got["task"].status, ERROR)
        self.assertIn("could not relaunch", got["task"].detail)


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

    def test_a_failed_install_returns_2_without_lock_or_run(self):
        from smoke.lib.dmg import DmgError
        install = mock.Mock(side_effect=DmgError("boom"))
        cli, rc, ex, lock = self._run_with_dmg(["run", "--account", "a@b.c", "--dmg"], install)
        self.assertEqual(rc, 2)
        ex.assert_not_called()
        lock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
