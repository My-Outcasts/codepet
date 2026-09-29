import unittest

from smoke.lib.watch import Fingerprint, is_fresh, may_drive


class Freshness(unittest.TestCase):
    def test_the_first_sighting_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("2", 100.0), None))

    def test_an_unchanged_bundle_is_not_fresh(self):
        # The stale-build trap, caught by the tool instead of by a person
        # concluding their change did not work.
        f = Fingerprint("2", 100.0)
        self.assertFalse(is_fresh(f, Fingerprint("2", 100.0)))

    def test_a_new_mtime_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("2", 200.0), Fingerprint("2", 100.0)))

    def test_a_new_bundle_version_is_fresh(self):
        self.assertTrue(is_fresh(Fingerprint("3", 100.0), Fingerprint("2", 100.0)))


class Hijacking(unittest.TestCase):
    def test_it_drives_when_nothing_is_running(self):
        may, why = may_drive(app_running=False, we_launched_it=False)
        self.assertTrue(may)

    def test_it_defers_to_the_founders_own_app(self):
        may, why = may_drive(app_running=True, we_launched_it=False)
        self.assertFalse(may)
        self.assertIn("your app is running", why)

    def test_it_may_drive_an_app_it_launched_itself(self):
        may, why = may_drive(app_running=True, we_launched_it=True)
        self.assertTrue(may)


if __name__ == "__main__":
    unittest.main()
