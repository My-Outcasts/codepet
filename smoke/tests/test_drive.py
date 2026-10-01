import unittest
from unittest.mock import patch, MagicMock

from smoke.lib import drive
from smoke.lib.drive import as_applescript_string, wait_until, launch, osascript, DriveError


class Escaping(unittest.TestCase):
    def test_a_plain_string_is_quoted(self):
        self.assertEqual(as_applescript_string("hello"), '"hello"')

    def test_double_quotes_are_escaped(self):
        # Unescaped, this ends the AppleScript string early and the rest of
        # the probe becomes syntax -- the script fails for a reason that has
        # nothing to do with the app.
        self.assertEqual(as_applescript_string('say "hi"'), '"say \\"hi\\""')

    def test_backslashes_are_escaped_before_quotes(self):
        self.assertEqual(as_applescript_string("a\\b"), '"a\\\\b"')


class Launch(unittest.TestCase):
    def test_it_raises_if_app_is_running_and_args_provided(self):
        # open -a <app> --args ... on an already-running instance silently
        # drops --args and exits 0. Detect this and fail explicitly.
        with patch("smoke.lib.drive.is_running", return_value=True):
            with self.assertRaises(DriveError) as cm:
                launch("/Applications/Codepet.app", args=["--demo"])
            self.assertIn("already running", str(cm.exception))

    def test_it_allows_launch_with_args_if_not_running(self):
        # If app is not running, subprocess.run should be called with --args
        with patch("smoke.lib.drive.is_running", return_value=False):
            with patch("smoke.lib.drive.subprocess.run") as mock_run:
                mock_run.return_value = MagicMock(returncode=0)
                launch("/Applications/Codepet.app", args=["--demo"])
                # Verify subprocess.run was called with --args
                call_args = mock_run.call_args[0][0]
                self.assertIn("--args", call_args)
                self.assertIn("--demo", call_args)

    def test_it_allows_launch_without_args_even_if_running(self):
        # Launching without args is OK even if app is running
        with patch("smoke.lib.drive.is_running", return_value=True):
            with patch("smoke.lib.drive.subprocess.run") as mock_run:
                mock_run.return_value = MagicMock(returncode=0)
                launch("/Applications/Codepet.app")  # No args
                # Should not raise
                mock_run.assert_called_once()


class Osascript(unittest.TestCase):
    def test_it_raises_on_whitespace_only_stderr(self):
        # (p.stderr or "osascript failed").strip().splitlines()[0] raises
        # IndexError on "   \n" because strip() leaves empty string.
        with patch("smoke.lib.drive.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1, stderr="   \n")
            with self.assertRaises(DriveError) as cm:
                osascript("some script")
            # Should raise with a fallback message, not IndexError
            self.assertIn("failed", str(cm.exception))

    def test_it_raises_with_message_on_normal_error(self):
        with patch("smoke.lib.drive.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1, stderr="script error\nmore details\n")
            with self.assertRaises(DriveError) as cm:
                osascript("some script")
            self.assertEqual(str(cm.exception), "script error")


class WaitUntil(unittest.TestCase):
    def test_it_returns_true_as_soon_as_the_predicate_holds(self):
        calls = {"n": 0}

        def ready():
            calls["n"] += 1
            return calls["n"] >= 2

        self.assertTrue(wait_until(ready, timeout=5, interval=0.01))
        self.assertEqual(calls["n"], 2)

    def test_it_gives_up_and_says_so(self):
        self.assertFalse(wait_until(lambda: False, timeout=0.2, interval=0.05))


class Keystrokes(unittest.TestCase):
    def test_nothing_is_typed_when_another_app_is_frontmost(self):
        # A keystroke goes to whatever is in front. Typing into a Simulator
        # that took focus mid-run is the failure this refuses.
        with patch.object(drive, "is_frontmost", return_value=False), \
                patch.object(drive, "osascript") as run:
            with self.assertRaises(DriveError):
                drive.type_text("probe")
            with self.assertRaises(DriveError):
                drive.press_enter()
            run.assert_not_called()

    def test_it_types_when_codepet_is_frontmost(self):
        with patch.object(drive, "is_frontmost", return_value=True), \
                patch.object(drive, "osascript") as run:
            drive.type_text("probe")
            self.assertIn('keystroke "probe"', run.call_args[0][0])


class OpenComposer(unittest.TestCase):
    def scripts(self, present, splash):
        sent = []
        with patch.object(drive, "composer_present", lambda: next(present)), \
                patch.object(drive, "on_splash", return_value=splash), \
                patch.object(drive, "osascript", sent.append):
            drive.open_composer(timeout=1, sleep=lambda s: None)
        return sent

    def test_the_splash_button_is_pressed_when_no_composer_is_on_screen(self):
        sent = self.scripts(iter([False, True]), splash=True)
        self.assertIn("click button 1 of group 1 of window 1", sent[0])
        self.assertIn("set focused of " + drive.COMPOSER, sent[1])

    def test_an_already_open_composer_is_only_focused(self):
        sent = self.scripts(iter([True]), splash=False)
        self.assertEqual(len(sent), 1)
        self.assertIn("set focused of " + drive.COMPOSER, sent[0])

    def test_no_button_is_pressed_off_the_splash(self):
        # Home has many buttons; button 1 there is not "Let's go".
        sent = self.scripts(iter([False, True]), splash=False)
        self.assertFalse(any("click button" in s for s in sent))

    def test_no_composer_after_launch_is_a_drive_error(self):
        with patch.object(drive, "composer_present", return_value=False), \
                patch.object(drive, "on_splash", return_value=True), \
                patch.object(drive, "osascript"):
            with self.assertRaises(DriveError):
                drive.open_composer(timeout=0.1, sleep=lambda s: None)

    def test_no_script_clicks_a_screen_point(self):
        sent = self.scripts(iter([False, True]), splash=True)
        self.assertFalse(any("click at" in s for s in sent))


if __name__ == "__main__":
    unittest.main()
