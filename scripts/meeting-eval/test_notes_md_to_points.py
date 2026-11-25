import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import notes_md  # noqa: E402
import notes_md_to_points as tool  # noqa: E402
import score_notes  # noqa: E402

OLD_PL = """## Podsumowanie

Zespół omówił zmianę kuriera.

## Decyzje

- Zwykłe paczki idą nowym kurierem.

## Zadania

- [ ] Ustawić kuriera w sklepie — osoba: Julia, termin: piątek
- [ ] Zapytać o zwrot — osoba: Do przypisania

### Omówione tematy

- Paczki dochodzą po pięciu dniach.

### Opóźnienia

- Kurier jest droższy.

## Otwarte kwestie

- Kto zapłaci za październik?

## Uczestnicy

Hanna, Bartek
"""

NEW_EN = """# Courier switch

The team compared two couriers and chose one.

### Delays
- Parcels arrive late.
- The new courier costs more.

## Decisions made
- Regular parcels go to the new courier.

## Next steps
- [ ] Set the default courier — owner: Julia, due: Friday
- [ ] Ask for a refund — owner: Unassigned

## Participants
Hanna, Bartek
"""

OTHER_APP = """## Budget review
- Spend is on plan.
  - Marketing is slightly over.

## Next Steps
- Send the report
"""


def kinds(points):
    return [p["kind"] for p in points]


class MarkdownToPointsTests(unittest.TestCase):
    def test_old_polish_layout(self):
        points = tool.points_from_markdown(OLD_PL)
        self.assertEqual(
            kinds(points), ["summary", "decision", "task", "task", "key_point", "key_point", "question"]
        )
        task = points[2]
        self.assertEqual((task["owner"], task["due"]), ("Julia", "piątek"))
        self.assertEqual(task["text"], "Ustawić kuriera w sklepie")
        self.assertIsNone(points[3]["owner"])  # "Do przypisania" is no owner

    def test_new_layout_title_intro_and_topics(self):
        points = tool.points_from_markdown(NEW_EN)
        self.assertEqual(kinds(points), ["summary", "key_point", "key_point", "decision", "task", "task"])
        self.assertEqual(points[4]["owner"], "Julia")
        self.assertIsNone(points[5]["owner"])
        self.assertNotIn("Courier switch", json.dumps(points))  # the title is no point

    def test_unknown_headings_are_topics_and_next_steps_are_tasks(self):
        points = tool.points_from_markdown(OTHER_APP)
        self.assertEqual(kinds(points), ["key_point", "key_point", "task"])
        self.assertEqual(points[2]["text"], "Send the report")

    def test_decoration_is_removed(self):
        points = tool.points_from_markdown("## 📌 Decisions\n- **Bold** [link](http://x.invalid) and `code`\n")
        self.assertEqual(points, [{"kind": "decision", "text": "Bold link and code", "quote": None}])

    def test_the_result_is_valid_for_the_scorer(self):
        data = tool.build(OLD_PL, "demo")
        score_notes.validate_notes(data)
        self.assertEqual(data["schema"], 1)
        self.assertEqual(data["meeting"], "demo")

    def test_cli_writes_the_file_and_prints_only_numbers(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "notes.md")
            out = os.path.join(tmp, "notes.json")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(NEW_EN)
            import contextlib
            import io

            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = tool.main(["--notes", path, "--meeting", "demo", "--out", out])
            self.assertEqual(code, 0)
            self.assertNotIn("courier", buffer.getvalue().lower())
            self.assertIn("points=6", buffer.getvalue())
            with open(out, encoding="utf-8") as handle:
                self.assertEqual(json.load(handle)["schema"], 1)
            # The file holds note text: owner-only, also when it already existed with wider rights.
            self.assertEqual(os.stat(out).st_mode & 0o777, 0o600)
            os.chmod(out, 0o644)
            with contextlib.redirect_stdout(io.StringIO()):
                tool.main(["--notes", path, "--meeting", "demo", "--out", out])
            self.assertEqual(os.stat(out).st_mode & 0o777, 0o600)

    def test_missing_file_is_a_usage_error(self):
        self.assertEqual(tool.main(["--notes", "/nonexistent/x.md", "--meeting", "m"]), 2)

    def test_normalize_folds_polish_letters(self):
        self.assertEqual(notes_md.normalize("Podjęte decyzje ✅"), "podjete decyzje")
        self.assertEqual(notes_md.normalize("Następne kroki"), "nastepne kroki")


if __name__ == "__main__":
    unittest.main()
