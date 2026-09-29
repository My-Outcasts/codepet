import os
import tempfile
import unittest

from smoke.lib.logstream import Capture, first_error, parse, parse_line

REAL = """Timestamp               Ty Process[PID:TID]
2026-09-24 06:52:11.936 E  codepet[4211:1604] [app.murror.codepet:ChatTransport] non-streaming retry refused: billing
2026-09-24 06:52:12.101 Df codepet[4211:1604] [app.murror.codepet:ChatTurn] chat turn routed to the founder's Claude Code
2026-09-24 10:59:12.476 Df kernel[0:34bf4f5] () wlan0: not our line
"""


class Parsing(unittest.TestCase):
    def test_the_header_row_is_not_a_log_line(self):
        self.assertIsNone(parse_line("Timestamp               Ty Process[PID:TID]"))

    def test_a_line_without_a_subsystem_is_not_ours(self):
        raw = "2026-09-24 10:59:12.476 Df kernel[0:34bf4f5] () wlan0: not our line"
        self.assertIsNone(parse_line(raw))

    def test_it_splits_subsystem_category_and_message(self):
        line = parse_line(
            "2026-09-24 06:52:11.936 E  codepet[4211:1604] "
            "[app.murror.codepet:ChatTransport] non-streaming retry refused: billing"
        )
        self.assertEqual(line.category, "ChatTransport")
        self.assertEqual(line.subsystem, "app.murror.codepet")
        self.assertEqual(line.message, "non-streaming retry refused: billing")
        self.assertEqual(line.pid, 4211)
        self.assertTrue(line.is_error)

    def test_a_default_line_is_not_an_error(self):
        lines = parse(REAL)
        turn = [l for l in lines if l.category == "ChatTurn"][0]
        self.assertFalse(turn.is_error)

    def test_parse_drops_the_two_unparseable_rows(self):
        self.assertEqual(len(parse(REAL)), 2)


class FirstError(unittest.TestCase):
    def test_it_reports_category_and_message(self):
        self.assertEqual(
            first_error(parse(REAL)),
            "ChatTransport: non-streaming retry refused: billing",
        )

    def test_it_is_none_when_nothing_went_wrong(self):
        clean = parse(
            "2026-09-24 06:52:12.101 Df codepet[4211:1604] "
            "[app.murror.codepet:ChatTurn] all good\n"
        )
        self.assertIsNone(first_error(clean))


class CaptureToFile(unittest.TestCase):
    def test_it_writes_the_subprocess_output_and_stops_it(self):
        # argv is injectable precisely so this test needs no real app.
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "log.txt")
            with Capture(path, argv=["/bin/sh", "-c", "echo hello; sleep 30"]) as cap:
                cap.wait_for_output(timeout=5)
            self.assertIn("hello", cap.text())


if __name__ == "__main__":
    unittest.main()
