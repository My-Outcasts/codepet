import json
import os
import shutil
import tempfile
import unittest

from smoke.lib import transcript
from smoke.lib.transcript import (TranscriptMissing, TranscriptUnreadable, load,
                                  resolve_account_dir)

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures",
                       "company_chats.json")

# The fixture is hand-written from the Swift Codable types (see the docstring
# of smoke/lib/transcript.py for the citations), never copied from a real file.
REPLIED = "a1b2c3d4e5f6"        # probe, then a companion reply, same thread
OTHER_THREAD = "0badc0ffee11"   # reversed token only in a DIFFERENT thread
BEFORE = "c0c0a1a2a3a4"         # reversed token BEFORE the probe, same thread
FOUNDER_ECHO = "d00d12345678"   # the founder, not the companion, typed it reversed


def account_with(fixture=FIXTURE):
    root = tempfile.mkdtemp()
    d = os.path.join(root, "uid123")
    os.makedirs(d)
    if fixture:
        shutil.copy(fixture, os.path.join(d, transcript.FILENAME))
    return root, d


class Schema(unittest.TestCase):
    def setUp(self):
        self.root, self.dir = account_with()
        self.addCleanup(shutil.rmtree, self.root)
        self.t = load(self.dir)

    def test_it_reads_every_thread_and_message(self):
        self.assertEqual(len(self.t.threads), 3)
        self.assertEqual([len(t.messages) for t in self.t.threads], [2, 1, 4])

    def test_a_reply_later_in_the_same_thread_is_seen(self):
        self.assertTrue(self.t.probe_seen(REPLIED))
        self.assertTrue(self.t.reply_seen(REPLIED))

    def test_a_reversed_token_in_another_thread_is_not_a_reply(self):
        self.assertTrue(self.t.probe_seen(OTHER_THREAD))
        self.assertTrue(self.t.contains(OTHER_THREAD[::-1]))
        self.assertFalse(self.t.reply_seen(OTHER_THREAD))

    def test_a_reversed_token_before_the_probe_is_not_a_reply(self):
        self.assertTrue(self.t.probe_seen(BEFORE))
        self.assertFalse(self.t.reply_seen(BEFORE))

    def test_the_founder_typing_it_reversed_is_not_a_reply(self):
        self.assertTrue(self.t.probe_seen(FOUNDER_ECHO))
        self.assertFalse(self.t.reply_seen(FOUNDER_ECHO))

    def test_a_companion_message_is_not_a_probe(self):
        # The reversed REPLIED token is only in a companion message.
        self.assertFalse(self.t.probe_seen(REPLIED[::-1]))

    def test_an_empty_needle_is_refused(self):
        with self.assertRaises(ValueError):
            self.t.contains("")


class Loading(unittest.TestCase):
    def test_no_file_is_an_empty_transcript(self):
        root, d = account_with(fixture=None)
        self.addCleanup(shutil.rmtree, root)
        self.assertEqual(load(d).threads, [])

    def test_a_non_json_file_is_unreadable_not_empty(self):
        root, d = account_with(fixture=None)
        self.addCleanup(shutil.rmtree, root)
        with open(os.path.join(d, transcript.FILENAME), "w") as f:
            f.write('[{"id": "x", "messa')
        with self.assertRaises(TranscriptUnreadable):
            load(d)

    def test_the_wrong_shape_is_unreadable(self):
        root, d = account_with(fixture=None)
        self.addCleanup(shutil.rmtree, root)
        for bad in ({"threads": []}, [{"id": "x"}],
                    [{"id": "x", "messages": [{"text": "hi"}]}]):
            with open(os.path.join(d, transcript.FILENAME), "w") as f:
                json.dump(bad, f)
            with self.assertRaises(TranscriptUnreadable):
                load(d)

    def test_unreadable_is_a_kind_of_missing(self):
        # Callers map TranscriptMissing to ERROR; unreadable must land there too.
        self.assertTrue(issubclass(TranscriptUnreadable, TranscriptMissing))


class Resolve(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root)

    def mk(self, name):
        os.makedirs(os.path.join(self.root, name))
        return os.path.join(self.root, name)

    def test_an_explicit_uid_wins(self):
        a = self.mk("aaa")
        self.mk("bbb")
        self.assertEqual(resolve_account_dir("aaa", root=self.root,
                                             env={"CODEPET_SMOKE_UID": "bbb"}), a)

    def test_the_environment_is_next(self):
        self.mk("aaa")
        b = self.mk("bbb")
        self.assertEqual(resolve_account_dir(None, root=self.root,
                                             env={"CODEPET_SMOKE_UID": "bbb"}), b)

    def test_a_single_account_dir_is_used(self):
        a = self.mk("aaa")
        with open(os.path.join(self.root, "stray.txt"), "w"):
            pass  # a file is not an account
        self.assertEqual(resolve_account_dir(None, root=self.root, env={}), a)

    def test_two_account_dirs_without_a_uid_is_an_error_not_a_guess(self):
        self.mk("aaa")
        self.mk("bbb")
        with self.assertRaises(TranscriptMissing) as cm:
            resolve_account_dir(None, root=self.root, env={})
        self.assertIn("--uid", str(cm.exception))

    def test_no_account_dirs_is_an_error(self):
        with self.assertRaises(TranscriptMissing):
            resolve_account_dir(None, root=self.root, env={})

    def test_no_accounts_root_is_an_error(self):
        with self.assertRaises(TranscriptMissing):
            resolve_account_dir(None, root=os.path.join(self.root, "nope"), env={})

    def test_a_named_uid_that_does_not_exist_is_an_error(self):
        self.mk("aaa")
        with self.assertRaises(TranscriptMissing):
            resolve_account_dir("zzz", root=self.root, env={})

    def test_the_uid_is_stripped_the_way_the_app_strips_it(self):
        # ChatThreadArchive.swift:32 keeps letters, digits, "-" and "_".
        a = self.mk("abc")
        self.assertEqual(resolve_account_dir("a/b.c", root=self.root, env={}), a)


if __name__ == "__main__":
    unittest.main()
