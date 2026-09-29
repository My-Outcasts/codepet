import importlib.machinery
import importlib.util
import os
import unittest
from unittest import mock

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


if __name__ == "__main__":
    unittest.main()
