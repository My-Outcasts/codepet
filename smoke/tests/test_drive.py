import unittest

from smoke.lib.drive import as_applescript_string, wait_until


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


if __name__ == "__main__":
    unittest.main()
