import unittest
from unittest import mock

from smoke.lib.build import Build
from smoke.lib.report import Report
from smoke.lib.result import ERROR, FAIL, PASS, SKIP, Result
from smoke.lib.slack import format_message, should_post, post, read_webhook


def a_report(results, mode="installed build"):
    build = Build("/Applications/codepet.app", "1.0", "2", "app.murror.codepet",
                  True, "valid on disk", False, 0.0)
    return Report(build=build, results=results, mode=mode, started=0.0, finished=134.0)


class Formatting(unittest.TestCase):
    def test_a_failing_run_leads_with_red_and_the_build(self):
        report = a_report([
            Result("launch", PASS, 3.1, "signed, Gatekeeper accepts, window in 3.1s"),
            Result("auth", PASS, 0.2, "account present in the local store (nguyen@murror.app)"),
            Result("chat", FAIL, 90.0, "no reply persisted for probe f3a91c",
                   ["ChatTransport: non-streaming retry refused: billing"]),
            Result("task", SKIP, 0.0, "skipped (chat failed)"),
        ])
        text = format_message(report)
        self.assertTrue(text.startswith("\U0001F534 Codepet smoke — 1.0 (2)"))
        self.assertIn("installed build", text)
        self.assertIn("2m14s", text)
        self.assertIn("no reply persisted for probe f3a91c", text)
        # the app's own words, so the channel answers "what broke"
        self.assertIn("non-streaming retry refused: billing", text)

    def test_the_header_escapes_slack_markup(self):
        build = Build("/x.app", "1.0 <beta>", "2&3", "app.murror.codepet",
                      True, "valid on disk", False, 0.0)
        report = Report(build=build, results=[Result("launch", PASS, 1.0, "fine")],
                        mode="local <build> & co", started=0.0, finished=1.0)
        head = format_message(report).split("\n")[0]
        self.assertIn("1.0 &lt;beta&gt; (2&amp;3)", head)
        self.assertIn("local &lt;build&gt; &amp; co", head)
        self.assertNotIn("<", head)

    def test_a_green_run_leads_with_green(self):
        text = format_message(a_report([Result("launch", PASS, 3.1, "fine")]))
        self.assertTrue(text.startswith("\U0001F7E2"))

    def test_an_errored_run_is_not_green(self):
        text = format_message(a_report([Result("launch", ERROR, 1.0, "no windows")]))
        self.assertFalse(text.startswith("\U0001F7E2"))

    def test_evidence_on_pass_result_is_not_emitted(self):
        report = a_report([
            Result("launch", PASS, 1.0, "fine", ["evidence here"]),
        ])
        text = format_message(report)
        self.assertNotIn("evidence here", text)

    def test_a_1000_char_evidence_line_is_capped_at_300(self):
        long_evidence = "x" * 1000
        report = a_report([
            Result("chat", FAIL, 1.0, "failed", [long_evidence]),
        ])
        text = format_message(report)
        self.assertIn("x" * 299 + "…", text)
        self.assertNotIn("x" * 300, text)

    def test_multiline_evidence_emits_only_first_line(self):
        report = a_report([
            Result("chat", FAIL, 1.0, "failed", ["line 1\nline 2\nline 3"]),
        ])
        text = format_message(report)
        self.assertIn("line 1", text)
        self.assertNotIn("line 2", text)

    def test_slack_markup_is_escaped_in_detail_and_evidence(self):
        report = a_report([
            Result("chat", FAIL, 1.0, "detail with <tag> & symbol", ["evidence with > bracket"]),
        ])
        text = format_message(report)
        self.assertIn("&lt;tag&gt;", text)
        self.assertIn("&amp;", text)
        self.assertIn("&gt;", text)


class PostErrors(unittest.TestCase):
    @mock.patch("smoke.lib.slack.urllib.request.urlopen")
    def test_timeout_error_returns_false_without_exposing_secret(self, mock_urlopen):
        mock_urlopen.side_effect = TimeoutError("timed out")
        ok, msg = post("https://hooks.slack.com/SECRET", "text")
        self.assertFalse(ok)
        self.assertNotIn("SECRET", msg)
        self.assertIn("TimeoutError", msg)

    @mock.patch("smoke.lib.slack.urllib.request.urlopen")
    def test_connection_reset_error_returns_false_without_exposing_secret(self, mock_urlopen):
        mock_urlopen.side_effect = ConnectionResetError("connection reset")
        ok, msg = post("https://hooks.slack.com/SECRET", "text")
        self.assertFalse(ok)
        self.assertNotIn("SECRET", msg)
        self.assertIn("ConnectionResetError", msg)

    @mock.patch("smoke.lib.slack.urllib.request.urlopen")
    def test_value_error_returns_false_without_exposing_secret(self, mock_urlopen):
        mock_urlopen.side_effect = ValueError("bad url https://hooks.slack.com/SECRET")
        ok, msg = post("https://hooks.slack.com/SECRET", "text")
        self.assertFalse(ok)
        self.assertNotIn("SECRET", msg)
        self.assertIn("ValueError", msg)

    @mock.patch("smoke.lib.slack.urllib.request.urlopen")
    def test_response_status_302_returns_false_with_status(self, mock_urlopen):
        mock_resp = mock.Mock()
        mock_resp.status = 302
        mock_urlopen.return_value.__enter__.return_value = mock_resp
        ok, msg = post("https://hooks.slack.com/test", "text")
        self.assertFalse(ok)
        self.assertIn("302", msg)

    @mock.patch("smoke.lib.slack.urllib.request.urlopen")
    def test_response_status_200_returns_true(self, mock_urlopen):
        mock_resp = mock.Mock()
        mock_resp.status = 200
        mock_urlopen.return_value.__enter__.return_value = mock_resp
        ok, msg = post("https://hooks.slack.com/test", "text")
        self.assertTrue(ok)
        self.assertIn("posted", msg)


class ReadWebhookErrors(unittest.TestCase):
    def test_directory_path_returns_none(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            result = read_webhook(d)
            self.assertIsNone(result)

    def test_invalid_utf8_bytes_returns_none(self):
        import tempfile
        import os
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "webhook")
            with open(path, "wb") as f:
                f.write(b"\xff\xfe invalid utf-8")
            result = read_webhook(path)
            self.assertIsNone(result)


class TransitionRule(unittest.TestCase):
    def test_a_plain_run_always_posts(self):
        self.assertTrue(should_post("run", "green", previous_verdict="green"))

    def test_watch_stays_silent_on_an_unchanged_verdict(self):
        self.assertFalse(should_post("watch", "green", previous_verdict="green"))

    def test_watch_speaks_up_when_green_turns_red(self):
        self.assertTrue(should_post("watch", "red", previous_verdict="green"))

    def test_watch_speaks_up_on_the_very_first_run(self):
        self.assertTrue(should_post("watch", "green", previous_verdict=None))


if __name__ == "__main__":
    unittest.main()
