import unittest

from smoke.checks.auth import evaluate, run
from smoke.lib.result import ERROR, FAIL, PASS


class Evaluate(unittest.TestCase):
    def test_a_persisted_account_passes_and_names_it(self):
        r = evaluate(found=True, account="nguyen@murror.app")
        self.assertEqual(r.status, PASS)
        self.assertEqual(r.detail, "session restored for nguyen@murror.app")

    def test_no_account_in_the_store_is_a_real_failure(self):
        r = evaluate(found=False, account="nguyen@murror.app")
        self.assertEqual(r.status, FAIL)
        self.assertIn("no session", r.detail)


class Run(unittest.TestCase):
    def test_a_missing_database_is_an_error_not_a_failure(self):
        # We could not look. That is not evidence of a signed-out app.
        r = run("nguyen@murror.app", db_dir="/no/such/db")
        self.assertEqual(r.status, ERROR)
        self.assertIn("no database", r.detail)


if __name__ == "__main__":
    unittest.main()
