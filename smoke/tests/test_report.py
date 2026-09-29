import json
import os
import tempfile
import unittest

from smoke.lib.build import Build
from smoke.lib.report import Report, write_html, write_json
from smoke.lib.result import FAIL, PASS, RED, SKIP, UNVERIFIED, Result


def a_build():
    return Build("/Applications/codepet.app", "1.0", "2", "app.murror.codepet",
                 True, "valid on disk", False, 0.0)


def a_report(results):
    return Report(build=a_build(), results=results, mode="installed build",
                  started=100.0, finished=234.0)


class Shape(unittest.TestCase):
    def test_it_carries_the_verdict_and_the_build_label(self):
        r = a_report([Result("launch", PASS), Result("chat", FAIL)])
        self.assertEqual(r.verdict(), RED)
        self.assertEqual(r.build.label(), "1.0 (2)")
        self.assertEqual(r.duration(), 134.0)

    def test_a_run_of_nothing_but_skips_is_unverified(self):
        self.assertEqual(a_report([Result("task", SKIP)]).verdict(), UNVERIFIED)


class Files(unittest.TestCase):
    def test_json_round_trips_every_check(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "report.json")
            write_json(a_report([Result("launch", PASS, 3.1, "window in 3.1s")]), path)
            with open(path) as f:
                data = json.load(f)
            self.assertEqual(data["verdict"], "green")
            self.assertEqual(data["build"]["bundle_version"], "2")
            self.assertEqual(data["results"][0]["detail"], "window in 3.1s")

    def test_html_names_the_build_and_every_check(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "report.html")
            write_html(a_report([Result("launch", PASS), Result("chat", FAIL, 0, "no reply")]), path)
            html = open(path, encoding="utf-8").read()
            self.assertIn("1.0 (2)", html)
            self.assertIn("no reply", html)
            self.assertIn("<html", html)


if __name__ == "__main__":
    unittest.main()
