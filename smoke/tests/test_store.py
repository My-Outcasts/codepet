import os
import tempfile
import unittest

from smoke.lib.store import StoreMissing, contains, count, data_files, wait_for


class DataFiles(unittest.TestCase):
    def test_it_takes_ldb_and_log_and_ignores_the_rest(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ("001.ldb", "002.log", "CURRENT", "LOCK", "LOG"):
                open(os.path.join(d, name), "wb").close()
            self.assertEqual(
                [os.path.basename(p) for p in data_files(d)], ["001.ldb", "002.log"]
            )

    def test_a_missing_database_raises_rather_than_reporting_absence(self):
        # Absence of the DB is a harness ERROR, not a product FAIL. Returning
        # False here would quietly turn "we could not look" into "not there".
        with self.assertRaises(StoreMissing):
            contains("/no/such/db", b"anything")


class Contains(unittest.TestCase):
    def test_it_finds_a_token_in_an_ldb_file(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "001.ldb"), "wb") as f:
                f.write(b"\x00\x01junk smoke-f3a91c junk\xff")
            self.assertTrue(contains(d, b"smoke-f3a91c"))

    def test_it_does_not_find_what_is_not_there(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "001.ldb"), "wb") as f:
                f.write(b"nothing of interest")
            self.assertFalse(contains(d, b"smoke-f3a91c"))

    def test_it_finds_a_token_split_across_a_chunk_boundary(self):
        # The bug this guards: reading in chunks without carrying an overlap
        # misses any needle that straddles two reads, and the check then
        # reports a working app as broken.
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "001.ldb"), "wb") as f:
                f.write(b"aaaa" + b"TOKEN" + b"bbbb")
            self.assertTrue(contains(d, b"TOKEN", chunk=4))

    def test_an_empty_needle_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "001.ldb"), "wb").close()
            with self.assertRaises(ValueError):
                contains(d, b"")

    def test_a_file_deleted_between_listing_and_open_is_skipped(self):
        # LevelDB deletes .log/.ldb files during compaction. If a file
        # disappears between data_files() glob and _file_contains() open,
        # skip it gracefully instead of crashing. Other files are still
        # searched and found.
        from unittest.mock import patch
        from smoke.lib import store

        with tempfile.TemporaryDirectory() as d:
            path1 = os.path.join(d, "001.ldb")
            path2 = os.path.join(d, "002.ldb")
            with open(path1, "wb") as f:
                f.write(b"junk")
            with open(path2, "wb") as f:
                f.write(b"needle")

            # Patch data_files to delete path1 after returning the list
            # (simulating compaction deleting the file)
            orig_data_files = store.data_files
            def fake_data_files(db_dir):
                result = orig_data_files(db_dir)
                if path1 in result:
                    os.remove(path1)  # Delete after listing
                return result

            with patch.object(store, "data_files", side_effect=fake_data_files):
                # Should find needle in remaining files, not crash on deleted path1
                self.assertTrue(contains(d, b"needle"))


class Count(unittest.TestCase):
    def test_it_totals_across_files(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "001.ldb"), "wb") as f:
                f.write(b"X X")
            with open(os.path.join(d, "002.log"), "wb") as f:
                f.write(b"X")
            self.assertEqual(count(d, b"X"), 3)

    def test_a_file_deleted_between_listing_and_count_is_skipped(self):
        # LevelDB deletes .log/.ldb files during compaction. If a file
        # disappears between data_files() glob and open, skip it gracefully.
        # Count remaining files.
        from unittest.mock import patch
        from smoke.lib import store

        with tempfile.TemporaryDirectory() as d:
            path1 = os.path.join(d, "001.ldb")
            path2 = os.path.join(d, "002.ldb")
            with open(path1, "wb") as f:
                f.write(b"X X")
            with open(path2, "wb") as f:
                f.write(b"X")

            # Patch data_files to delete path1 after returning the list
            orig_data_files = store.data_files
            def fake_data_files(db_dir):
                result = orig_data_files(db_dir)
                if path1 in result:
                    os.remove(path1)  # Delete after listing
                return result

            with patch.object(store, "data_files", side_effect=fake_data_files):
                # Should count only from remaining file (1 X), not crash
                self.assertEqual(count(d, b"X"), 1)


class WaitFor(unittest.TestCase):
    def test_it_returns_as_soon_as_the_needle_lands(self):
        # Raw byte reads do not take LevelDB's lock, so we can poll while the
        # app is still running instead of paying a fixed 90s sleep.
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "001.ldb")
            open(path, "wb").close()
            slept = []

            def fake_sleep(seconds):
                slept.append(seconds)
                if len(slept) == 2:
                    with open(path, "wb") as f:
                        f.write(b"smoke-f3a91c")

            ticks = iter([0.0, 2.0, 4.0, 6.0, 8.0])
            self.assertTrue(
                wait_for(d, b"smoke-f3a91c", timeout=30, interval=2.0,
                         sleep=fake_sleep, now=lambda: next(ticks))
            )
            self.assertEqual(len(slept), 2)

    def test_it_gives_up_at_the_deadline(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "001.ldb"), "wb").close()
            ticks = iter([0.0, 5.0, 11.0])
            self.assertFalse(
                wait_for(d, b"never", timeout=10, interval=1.0,
                         sleep=lambda s: None, now=lambda: next(ticks))
            )


if __name__ == "__main__":
    unittest.main()
