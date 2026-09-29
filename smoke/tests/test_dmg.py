import os
import tempfile
import unittest
from unittest import mock

from smoke.lib import dmg
import urllib.error

from smoke.lib.dmg import DmgError, app_in, parse_device, parse_mount_point
from smoke.lib.result import ERROR, FAIL

# Real `hdiutil attach -plist` output is XML; with -nobrowse and no -plist it
# prints tab-separated rows and the mount point is the last field of the row
# that has one.
REAL = (
    "/dev/disk4          \tGUID_partition_scheme\t\n"
    "/dev/disk4s1        \tApple_HFS             \t/Volumes/Codepet\n"
)


class MountPoint(unittest.TestCase):
    def test_it_takes_the_volume_path(self):
        self.assertEqual(parse_mount_point(REAL), "/Volumes/Codepet")

    def test_no_volume_row_is_an_error_not_an_empty_string(self):
        with self.assertRaises(DmgError):
            parse_mount_point("/dev/disk4\tGUID_partition_scheme\t\n")


class AppIn(unittest.TestCase):
    def test_it_finds_the_single_app_bundle(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "codepet.app", "Contents"))
            self.assertEqual(app_in(d), os.path.join(d, "codepet.app"))

    def test_a_volume_with_no_app_is_an_error(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(DmgError):
                app_in(d)


def done(rc=0, out="", err=""):
    return mock.Mock(returncode=rc, stdout=out, stderr=err)


class Install(unittest.TestCase):
    def run_install(self, attach_out, copytree=None, detach_rc=0, spctl=(0, "accepted")):
        calls = []

        def fake_run(cmd, **k):
            calls.append(cmd)
            if cmd[0] == "/usr/sbin/spctl":
                return done(spctl[0], "", spctl[1])
            if cmd[1] == "attach":
                return done(0, attach_out)
            return done(detach_rc)

        patches = [
            mock.patch.object(dmg.subprocess, "run", fake_run),
            mock.patch.object(dmg, "download", lambda u, d: d),
        ]
        if copytree is not None:
            patches.append(mock.patch.object(dmg.shutil, "copytree", copytree))
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        with tempfile.TemporaryDirectory() as w:
            try:
                return calls, dmg.install("http://x/y.dmg", w), None
            except DmgError as e:
                return calls, None, e

    def test_the_image_is_assessed_before_it_is_mounted(self):
        with mock.patch.object(dmg, "app_in", lambda m: "/Volumes/Codepet/codepet.app"):
            calls, _, err = self.run_install(REAL, copytree=lambda *a, **k: None)
        self.assertIsNone(err)
        spctl = calls[0]
        self.assertEqual(spctl[:-1], ["/usr/sbin/spctl", "-a", "-t", "open", "--context",
                                      "context:primary-signature", "-vv"])
        self.assertTrue(spctl[-1].endswith("Codepet.dmg"))
        self.assertEqual(calls[1][1], "attach")

    def test_a_rejected_image_is_a_fail_and_is_never_mounted(self):
        # CLAUDE.md failure #4: notarytool and stapler accepted an unsigned
        # image; spctl -a -t open was the only check that caught it.
        calls, _, err = self.run_install(
            REAL, spctl=(3, "/w/Codepet.dmg: rejected\nsource=no usable signature"))
        self.assertEqual(err.status, FAIL)
        self.assertEqual(str(err),
                         "the disk image is not signed/notarized: /w/Codepet.dmg: rejected")
        self.assertEqual(len(calls), 1)  # no attach, nothing to detach

    def test_spctl_that_cannot_run_is_an_error(self):
        def boom(cmd, **k):
            raise FileNotFoundError("spctl")
        with mock.patch.object(dmg.subprocess, "run", boom):
            with self.assertRaises(DmgError) as cm:
                dmg.assess_image("/w/Codepet.dmg")
        self.assertEqual(cm.exception.status, ERROR)

    def test_parse_device_takes_the_first_disk_node(self):
        self.assertEqual(parse_device(REAL), "/dev/disk4")

    def test_no_volume_row_still_detaches_by_device_node(self):
        calls, _, err = self.run_install("/dev/disk4\tGUID_partition_scheme\t\n")
        self.assertIsNotNone(err)
        self.assertEqual(calls[-1], ["/usr/bin/hdiutil", "detach", "/dev/disk4"])

    def test_a_copy_failure_is_a_dmg_error_and_still_detaches(self):
        def boom(*a, **k):
            raise OSError("disk full")
        with mock.patch.object(dmg, "app_in", lambda m: "/Volumes/Codepet/codepet.app"):
            calls, _, err = self.run_install(REAL, copytree=boom)
        self.assertIn("disk full", str(err))
        self.assertEqual(calls[-1], ["/usr/bin/hdiutil", "detach", "/Volumes/Codepet"])

    def test_a_failed_detach_is_reported(self):
        with mock.patch.object(dmg, "app_in", lambda m: "/Volumes/Codepet/codepet.app"):
            _, _, err = self.run_install(REAL, copytree=lambda *a, **k: None,
                                         detach_rc=1)
        self.assertIn("could not detach", str(err))

    def test_a_failed_detach_does_not_mask_the_earlier_error(self):
        _, _, err = self.run_install("/dev/disk4\tx\t\n", detach_rc=1)
        self.assertIn("mounted nothing", str(err))


class Download(unittest.TestCase):
    def fetch(self, exc):
        def boom(url, dest):
            raise exc
        with mock.patch.object(dmg.urllib.request, "urlretrieve", boom):
            with self.assertRaises(DmgError) as cm:
                dmg.download("https://x/Codepet.dmg", "/w/Codepet.dmg")
        return cm.exception

    def test_a_404_is_a_fail(self):
        # The link a user clicks leads nowhere: the product is broken.
        e = self.fetch(urllib.error.HTTPError("https://x", 404, "Not Found", {}, None))
        self.assertEqual(e.status, FAIL)
        self.assertIn("HTTP 404", str(e))

    def test_another_http_error_is_an_error(self):
        e = self.fetch(urllib.error.HTTPError("https://x", 503, "Unavailable", {}, None))
        self.assertEqual(e.status, ERROR)
        self.assertIn("HTTP 503", str(e))

    def test_a_network_failure_is_an_error(self):
        e = self.fetch(urllib.error.URLError("no route to host"))
        self.assertEqual(e.status, ERROR)

    def test_a_plain_dmg_error_defaults_to_error(self):
        self.assertEqual(DmgError("x").status, ERROR)


if __name__ == "__main__":
    unittest.main()
