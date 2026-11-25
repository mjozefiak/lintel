import json
import os
import tempfile
import unittest

import score_loss as loss


def seg(start, end, text):
    return (float(start), float(end), loss.words_of(text))


def turn(start, end, text):
    return (float(start), float(end), loss.words_of(text))


def write(directory, name, data):
    path = os.path.join(directory, name)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle)
    return path


class AnalyseTests(unittest.TestCase):
    def test_every_word_found_is_no_loss(self):
        ref = [turn(0, 4000, "one two three four")]
        row = loss.analyse(ref, [seg(0, 4000, "one two three four")])
        self.assertEqual(row["lost"], 0)
        self.assertEqual(row["extra"], 0)

    def test_a_turn_with_no_segment_is_lost_outside(self):
        ref = [turn(0, 2000, "one two"), turn(10_000, 12_000, "three four")]
        row = loss.analyse(ref, [seg(0, 2000, "one two")])
        self.assertEqual(row["lost"], 2)
        self.assertEqual(row["outsideLost"], 2)
        self.assertEqual(row["insideLost"], 0)
        self.assertEqual(row["outside500Lost"], 2)
        self.assertAlmostEqual(row["lostRate"], 0.5)

    def test_a_word_missing_inside_a_segment_is_inside_not_outside(self):
        ref = [turn(0, 4000, "one two three four")]
        row = loss.analyse(ref, [seg(0, 4000, "one three four")])
        self.assertEqual(row["lost"], 1)
        self.assertEqual(row["insideLost"], 1)
        self.assertEqual(row["outsideLost"], 0)

    def test_a_lost_word_next_to_a_segment_edge_counts_for_the_edge_zone(self):
        # The first word of the reference turn sits 125 ms into the segment, the rest is found.
        ref = [turn(0, 2000, "one two three four five six seven eight")]
        row = loss.analyse(ref, [seg(0, 2000, "two three four five six seven eight")])
        self.assertEqual(row["nearEdgeLost"], 1)
        self.assertEqual(row["middleLost"], 0)

    def test_a_cut_segment_is_recognised_by_its_length(self):
        ref = [turn(0, 16_000, "a b c d e f g h")]
        row = loss.analyse(ref, [seg(0, 15_000, "a b c d e f g h")])
        self.assertEqual(row["cutSegments"], 1)
        row = loss.analyse(ref, [seg(0, 14_000, "a b c d e f g h")])
        self.assertEqual(row["cutSegments"], 0)

    def test_words_the_transcript_has_and_the_reference_lacks_are_extra(self):
        ref = [turn(0, 2000, "one two")]
        row = loss.analyse(ref, [seg(0, 2000, "one two ghost words")])
        self.assertEqual(row["extra"], 2)

    def test_fillers_count_on_neither_side(self):
        self.assertEqual(loss.words_of("Um, yes uh mm"), ["yes"])


class LoadTests(unittest.TestCase):
    def test_gold_and_whisper_references_both_load(self):
        with tempfile.TemporaryDirectory() as directory:
            gold = write(directory, "gold.json", {"transcript": [{"start": 1.0, "end": 2.0, "text": "Hello there"}]})
            raw = write(
                directory, "raw.json",
                {"transcription": [{"offsets": {"from": 1000, "to": 2000}, "text": " Hello there"}]})
            self.assertEqual(loss.load_reference(gold), loss.load_reference(raw))
            self.assertEqual(loss.load_reference(gold), [(1000.0, 2000.0, ["hello", "there"])])

    def test_main_prints_numbers_only(self):
        with tempfile.TemporaryDirectory() as directory:
            gold = write(directory, "gold.json", {"transcript": [{"start": 0, "end": 2, "text": "secretword one"}]})
            result = write(
                directory, "run.json",
                {"asr": {"segments": [{"track": "system", "startMs": 0, "endMs": 2000, "text": "secretword one"}]}})
            import contextlib
            import io

            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                loss.main(["--reference", gold, result])
            self.assertNotIn("secretword", out.getvalue())
            self.assertIn("run", out.getvalue())


if __name__ == "__main__":
    unittest.main()
