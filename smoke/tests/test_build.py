import os
import plistlib
import tempfile
import unittest

from smoke.lib.build import (
    Build, BuildMissing, identify, parse_codesign, parse_quarantine, read_info,
)


def make_bundle(d, short="1.0", version="2"):
    contents = os.path.join(d, "codepet.app", "Contents")
    os.makedirs(contents)
    with open(os.path.join(contents, "Info.plist"), "wb") as f:
        plistlib.dump(
            {
                "CFBundleShortVersionString": short,
                "CFBundleVersion": version,
                "CFBundleIdentifier": "app.murror.codepet",
            },
            f,
        )
    return os.path.join(d, "codepet.app")


class Codesign(unittest.TestCase):
    def test_silence_and_zero_means_valid(self):
        self.assertEqual(parse_codesign(0, ""), (True, "valid on disk"))

    def test_it_keeps_the_first_line_of_the_real_complaint(self):
        signed, detail = parse_codesign(
            1, "codepet.app: code object is not signed at all\nIn architecture: arm64\n"
        )
        self.assertFalse(signed)
        self.assertEqual(detail, "codepet.app: code object is not signed at all")

    def test_a_failure_with_no_message_still_says_something(self):
        self.assertEqual(parse_codesign(1, "   \n"), (False, "unknown signing failure"))


class Quarantine(unittest.TestCase):
    def test_it_detects_the_gatekeeper_flag(self):
        self.assertTrue(parse_quarantine("com.apple.quarantine\ncom.apple.macl\n"))

    def test_no_attributes_means_not_quarantined(self):
        self.assertFalse(parse_quarantine(""))


class Identity(unittest.TestCase):
    def test_it_reads_the_bundle_and_labels_it(self):
        with tempfile.TemporaryDirectory() as d:
            app = make_bundle(d)
            info = read_info(app)
            self.assertEqual(info["CFBundleIdentifier"], "app.murror.codepet")
            b = Build(app, "1.0", "2", "app.murror.codepet", True, "ok", False, 0.0)
            self.assertEqual(b.label(), "1.0 (2)")

    def test_a_missing_bundle_raises(self):
        with self.assertRaises(BuildMissing):
            identify("/Applications/NoSuchThing.app")


if __name__ == "__main__":
    unittest.main()
