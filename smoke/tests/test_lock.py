import os
import tempfile
import unittest

from smoke.lib.lock import Lock, LockHeld


class Locking(unittest.TestCase):
    def test_a_second_holder_is_refused(self):
        # Two runs -- or two parallel Claude sessions -- must not drive the
        # app at once.
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, ".lock")
            with Lock(path):
                with self.assertRaises(LockHeld):
                    with Lock(path):
                        pass

    def test_the_lock_is_released_after_the_block(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, ".lock")
            with Lock(path):
                pass
            with Lock(path):
                pass  # no raise


if __name__ == "__main__":
    unittest.main()
