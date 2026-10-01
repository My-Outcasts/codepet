import unittest

from smoke.checks.auth import evaluate, run, session_from_log
from smoke.lib.logstream import LogLine
from smoke.lib.result import ERROR, FAIL, PASS


def auth(message, category="Auth"):
    return LogLine("2026-10-01 14:44:09.049", "E", "codepet", 1, "app.murror.codepet",
                   category, message)


SIGNED_IN = auth("signed in: uid=lcpWe88kXTQHsnE5GEnEzwjPcYW2 anonymous=false hasName=true")


class Evaluate(unittest.TestCase):
    def test_a_persisted_account_passes_and_names_it(self):
        r = evaluate(found=True, account="nguyen@murror.app")
        self.assertEqual(r.status, PASS)
        self.assertEqual(r.detail, "account present in the local store (nguyen@murror.app)")
        # A presence check must not claim a live session; chat proves that.
        self.assertNotIn("session", r.detail)

    def test_no_account_in_the_store_is_a_real_failure(self):
        r = evaluate(found=False, account="nguyen@murror.app")
        self.assertEqual(r.status, FAIL)
        self.assertIn("not found in the local store", r.detail)
        self.assertIn("nguyen@murror.app", r.detail)


class Run(unittest.TestCase):
    def test_a_missing_database_is_an_error_not_a_failure(self):
        # We could not look. That is not evidence of a signed-out app.
        r = run("nguyen@murror.app", db_dir="/no/such/db")
        self.assertEqual(r.status, ERROR)
        self.assertIn("no database", r.detail)


class FromLog(unittest.TestCase):
    """The 1 Oct run: signed in, email absent from the cache, read as FAIL."""

    def test_a_signed_in_line_for_the_expected_uid_passes_without_the_store(self):
        r = run("giang@murror.app", db_dir="/no/such/db", lines=[SIGNED_IN],
                uid="lcpWe88kXTQHsnE5GEnEzwjPcYW2")
        self.assertEqual(r.status, PASS, r.detail)
        self.assertIn("session restored", r.detail)

    def test_another_uid_is_a_failure(self):
        r = run("giang@murror.app", db_dir="/no/such/db", lines=[SIGNED_IN], uid="someoneelse")
        self.assertEqual(r.status, FAIL)
        self.assertIn("expected uid=someoneelse", r.detail)

    def test_an_anonymous_session_is_a_failure(self):
        r = run("a@b.c", db_dir="/no/such/db",
                lines=[auth("signed in: uid=u1 anonymous=true hasName=false")])
        self.assertEqual(r.status, FAIL)
        self.assertIn("ANONYMOUS", r.detail)

    def test_the_last_state_wins(self):
        self.assertEqual(session_from_log([SIGNED_IN, auth("signed out")]), ("out", None, None))
        r = run("a@b.c", db_dir="/no/such/db", lines=[SIGNED_IN, auth("signed out")])
        self.assertEqual(r.status, FAIL)

    def test_other_categories_are_ignored(self):
        self.assertIsNone(session_from_log([auth("signed out", category="LocalTransport")]))

    def test_no_auth_line_falls_back_to_the_store(self):
        r = run("a@b.c", db_dir="/no/such/db", lines=[])
        self.assertEqual(r.status, ERROR)
        self.assertIn("no database", r.detail)


if __name__ == "__main__":
    unittest.main()
