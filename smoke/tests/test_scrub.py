"""transcript.scrub -- the smoke run takes its own chats back out of RECENT (build 6, bug #11).

It edits a founder's real transcript, so most of these pin what it must NOT touch.
"""

import json
import os
import shutil
import unittest

from smoke.checks import chat
from smoke.lib import transcript
from smoke.tests.test_transcript import account_with


class Scrub(unittest.TestCase):
    def setUp(self):
        self.root, self.dir = account_with()
        self.addCleanup(shutil.rmtree, self.root)
        self.path = os.path.join(self.dir, transcript.FILENAME)

    def raw(self):
        with open(self.path) as f:
            return json.load(f)

    def test_the_probe_the_check_types_is_a_probe(self):
        # Ties the matcher to the text actually typed: a reworded probe would
        # otherwise stop being cleaned up without anything going red.
        self.assertTrue(transcript.is_probe(chat.probe_text(chat.mint_token())))

    def test_a_founder_who_writes_smoke_test_is_not_a_probe(self):
        for text in ["smoke test", "smoke test the landing page",
                     "smoke test a1b2c3d4e5f6 -- reply with this code in capital letters, "
                     "nothing else: 0badc0ffee11",            # tokens differ
                     "please: smoke test a1b2c3d4e5f6 -- reply with this code in capital "
                     "letters, nothing else: a1b2c3d4e5f6"]:  # not the whole message
            self.assertFalse(transcript.is_probe(text), text)

    def test_smoke_only_threads_go_and_the_founders_messages_stay(self):
        removed = transcript.scrub(self.dir)
        self.assertEqual(removed, 5)
        threads = self.raw()
        self.assertEqual(len(threads), 1, "the two smoke-only threads are dropped")
        texts = [m["text"] for m in threads[0]["messages"]]
        self.assertEqual(texts, ["An earlier reply that happens to say 0BADC0FFEE11 and C0C0A1A2A3A4.",
                                 "I will type it myself: D00D12345678"])

    def test_kept_fields_pass_through_untouched(self):
        before = {t["id"]: t for t in self.raw()}
        transcript.scrub(self.dir)
        for t in self.raw():
            original = before[t["id"]]
            self.assertEqual({k: v for k, v in t.items() if k != "messages"},
                             {k: v for k, v in original.items() if k != "messages"})
            for m in t["messages"]:
                self.assertIn(m, original["messages"])

    def test_a_second_scrub_changes_nothing(self):
        transcript.scrub(self.dir)
        mtime = os.stat(self.path).st_mtime_ns
        self.assertEqual(transcript.scrub(self.dir), 0)
        self.assertEqual(os.stat(self.path).st_mtime_ns, mtime, "no rewrite when nothing matched")

    def test_no_file_is_nothing_to_do(self):
        os.remove(self.path)
        self.assertEqual(transcript.scrub(self.dir), 0)
        self.assertFalse(os.path.exists(self.path))

    def test_a_file_that_is_not_the_apps_shape_is_left_alone(self):
        with open(self.path, "w") as f:
            json.dump({"not": "a thread list"}, f)
        with self.assertRaises(transcript.TranscriptMissing):
            transcript.scrub(self.dir)
        self.assertEqual(self.raw(), {"not": "a thread list"})
        self.assertEqual([n for n in os.listdir(self.dir) if n.startswith(".company_chats.")], [],
                         "no temp file left behind")


if __name__ == "__main__":
    unittest.main()
