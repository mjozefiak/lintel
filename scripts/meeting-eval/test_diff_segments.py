import contextlib
import io
import json
import os
import tempfile
import unittest

import diff_segments as d


def row(start, end, text, track="mic", repaired=None):
    value = {"track": track, "startMs": start, "endMs": end, "text": text}
    if repaired is not None:
        value["repaired"] = repaired
    return value


def result(*rows):
    return {"schema": 1, "asr": {"segments": list(rows)}}


class DiffTests(unittest.TestCase):
    def test_identical_results_change_nothing(self):
        r = result(row(0, 5000, "jeden dwa trzy cztery pięć"), row(6000, 6500, "tak"))
        report = d.diff(r, r)
        self.assertEqual(report["changed"], [])
        self.assertEqual(report["matched"], 2)

    def test_a_short_change_is_listed_and_not_long(self):
        before = result(row(0, 1500, "okej"), row(2000, 9000, "jeden dwa trzy cztery pięć"))
        after = result(row(0, 1500, "okay"), row(2000, 9000, "jeden dwa trzy cztery pięć"))
        report = d.diff(before, after)
        self.assertEqual([c["key"] for c in report["changed"]], ["mic@0-1500"])
        self.assertEqual(report["long"], [])

    def test_long_means_over_two_seconds_and_over_three_words_before(self):
        # 2 s exactly with many words: short (≤ 2 s).
        self.assertFalse(d.is_long(row(0, 2000, "a b c d e f")))
        # 10 s with 3 words: short (≤ 3 words).
        self.assertFalse(d.is_long(row(0, 10000, "a b c")))
        self.assertTrue(d.is_long(row(0, 2001, "a b c d")))
        before = result(row(0, 4000, "a b c d"))
        after = result(row(0, 4000, "x"))
        report = d.diff(before, after)
        self.assertEqual(len(report["long"]), 1)
        self.assertEqual(report["long"][0]["wordsBefore"], 4)
        self.assertEqual(report["long"][0]["wordsAfter"], 1)

    def test_unmatched_rows_are_counted_not_compared(self):
        before = result(row(0, 1000, "a"), row(5000, 9000, "a b c d e"))
        after = result(row(0, 1000, "a"), row(5000, 9100, "x y"))
        report = d.diff(before, after)
        self.assertEqual(report["changed"], [])
        self.assertEqual((report["onlyBefore"], report["onlyAfter"]), (1, 1))

    def test_tracks_are_part_of_the_key(self):
        before = result(row(0, 1000, "a", "mic"), row(0, 1000, "b", "system"))
        after = result(row(0, 1000, "a", "mic"), row(0, 1000, "c", "system"))
        self.assertEqual([c["key"] for c in d.diff(before, after)["changed"]], ["system@0-1000"])

    def test_repaired_only_ignores_changes_of_the_live_hint(self):
        before = result(row(0, 5000, "a b c d e"), row(6000, 6500, "okej"))
        after = result(row(0, 5000, "x y z w v", repaired=False), row(6000, 6500, "okay", repaired=True))
        self.assertEqual(len(d.diff(before, after)["long"]), 1)
        report = d.diff(before, after, repaired_only=True)
        self.assertEqual([c["key"] for c in report["changed"]], ["mic@6000-6500"])
        self.assertEqual(report["long"], [])

    def test_a_malformed_result_is_an_input_error(self):
        with self.assertRaises(ValueError):
            d.diff({"asr": {}}, result())
        with self.assertRaises(ValueError):
            d.diff(result({"track": "mic", "startMs": 0, "endMs": 1}), result())


class MainTests(unittest.TestCase):
    def run_main(self, before, after, *flags):
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for name, value in (("before.json", before), ("after.json", after)):
                path = os.path.join(directory, name)
                with open(path, "w", encoding="utf-8") as handle:
                    if isinstance(value, str):
                        handle.write(value)
                    else:
                        json.dump(value, handle)
                paths.append(path)
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = d.main(paths + list(flags))
            return code, out.getvalue(), err.getvalue()

    def test_exit_zero_when_no_long_segment_changed_and_no_text_is_printed(self):
        code, out, _ = self.run_main(
            result(row(0, 1000, "sekretne słowo")), result(row(0, 1000, "tajne hasło", repaired=True)))
        self.assertEqual(code, 0)
        self.assertIn("changed mic@0-1000 durationMs=1000 words=2->2 repaired=True long=no", out)
        self.assertNotIn("sekretne", out)
        self.assertNotIn("tajne", out)

    def test_exit_one_when_a_long_segment_changed(self):
        code, out, _ = self.run_main(
            result(row(0, 5000, "jeden dwa trzy cztery")), result(row(0, 5000, "one two three four")))
        self.assertEqual(code, 1)
        self.assertIn("long=1", out)
        self.assertNotIn("jeden", out)

    def test_exit_two_on_usage_and_input_errors(self):
        self.assertEqual(self.run_main(result(), result(), "--bogus")[0], 2)
        self.assertEqual(self.run_main("not json", result())[0], 2)
        self.assertEqual(self.run_main({"asr": {}}, result())[0], 2)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(d.main(["only-one.json"]), 2)


if __name__ == "__main__":
    unittest.main()
