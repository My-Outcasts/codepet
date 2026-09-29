import os
import tempfile
import unittest

from smoke.lib.dmg import DmgError, app_in, parse_mount_point

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


if __name__ == "__main__":
    unittest.main()
