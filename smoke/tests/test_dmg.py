import os
import tempfile
import unittest
from unittest import mock

from smoke.lib import dmg
from smoke.lib.dmg import DmgError, app_in, parse_device, parse_mount_point

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
    def run_install(self, attach_out, copytree=None, detach_rc=0):
        calls = []

        def fake_run(cmd, **k):
            calls.append(cmd)
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


if __name__ == "__main__":
    unittest.main()
