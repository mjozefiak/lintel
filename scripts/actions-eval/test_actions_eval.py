"""Unit tests of the actions-detection spike harness: `python3 -I -m unittest discover scripts/actions-eval`."""

import datetime
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import corpus  # noqa: E402
import guard  # noqa: E402
import prompt  # noqa: E402
import run  # noqa: E402
import score  # noqa: E402
from dates import resolve  # noqa: E402
from textnorm import digit_numbers, fold, name_supported, names_match, spoken_numbers, tokens  # noqa: E402

D = datetime.date


class CorpusTests(unittest.TestCase):
    def test_corpus_size_and_languages(self):
        meetings = corpus.load_all()
        langs = [m.lang for m in meetings]
        self.assertTrue(8 <= langs.count("pl") <= 12)
        self.assertEqual(langs.count("en"), 4)

    def test_gold_refers_to_real_utterances_and_types(self):
        for m in corpus.load_all():
            self.assertIn(m.self_label, m.speakers, m.id)
            ids = set()
            for item in m.gold["actions"] + m.gold.get("traps", []):
                self.assertNotIn(item["id"], ids, m.id)
                ids.add(item["id"])
                for e in item["evidence"]:
                    self.assertTrue(1 <= e <= len(m.utterances), "%s %s" % (m.id, item["id"]))
            for a in m.gold["actions"]:
                self.assertTrue(set(a["type"]) <= {"email", "calendar", "jira"}, m.id)
                for name in a["fields"]:
                    self.assertIn(name, score.FIELDS, m.id)
                self.assertTrue(any(m.utterances[e - 1].speaker == m.self_label for e in a["evidence"]),
                                "%s %s: the user must speak in the evidence" % (m.id, a["id"]))
            for t in m.gold.get("traps", []):
                self.assertIn(t["kind"], ("other_speaker", "rejected", "condition_failed", "vague", "withdrawn", "hedge"))

    def test_gold_dates_follow_from_the_transcript(self):
        """Every gold date is one the guard's resolver reads from the evidence (the guard keeps right answers)."""
        for m in corpus.load_all():
            for a in m.gold["actions"]:
                for key in ("date", "due"):
                    values = a["fields"].get(key)
                    if not values:
                        continue
                    evidence = " . ".join(m.utterances[e - 1].text for e in a["evidence"])
                    readings = resolve(evidence, m.date)
                    self.assertTrue(set(D.fromisoformat(v) for v in values) & readings,
                                    "%s %s %s %s" % (m.id, a["id"], values, sorted(readings)))

    def test_padding_keeps_the_gold_on_the_same_lines(self):
        m = corpus.load("pl06-recruiting")
        p = corpus.padded(m, 3)
        self.assertEqual(len(p.utterances), 4 * len(m.utterances))
        for a, b in zip(m.gold["actions"] + m.gold["traps"], p.gold["actions"] + p.gold["traps"]):
            self.assertEqual([m.utterances[e - 1].text for e in a["evidence"]],
                             [p.utterances[e - 1].text for e in b["evidence"]])
        self.assertTrue(all(p.utterances[i].speaker != m.self_label for i in range(1, len(p.utterances), 4)))

    def test_prompt_carries_the_header_and_calendar(self):
        m = corpus.load("pl01-sprint")
        system, user = prompt.messages(m)
        self.assertIn('"actions"', system)
        self.assertIn('Meeting date: 2026-11-18 (Wednesday). The user is "Marta". Language: Polish.', user)
        self.assertIn("2026-11-24 Tuesday", user)
        self.assertIn("[00:46] Marta: Jasne, założę ticket", user)


class TextTests(unittest.TestCase):
    def test_fold(self):
        self.assertEqual(fold("Łukasz, PŁATNOŚCI!"), "lukasz platnosci")
        self.assertEqual(fold("o 10:30, wersja 17.4."), "o 10:30 wersja 17.4")

    def test_names_in_other_cases(self):
        heard = tokens("przypiszę Oli i Tomkowi, wyślij Halinie, pana Kowala")
        for name in ("Ola", "Tomek", "Halina", "Adam Kowal" if False else "Kowal"):
            self.assertTrue(name_supported(name, heard), name)
        self.assertFalse(name_supported("Zbigniew", heard))
        self.assertTrue(names_match("Natalii", "Natalia"))
        self.assertFalse(names_match("Robert", "Zosia"))

    def test_spoken_numbers(self):
        self.assertIn(12.0, spoken_numbers("rabat dwanaście procent"))
        self.assertIn(45.0, spoken_numbers("na czterdzieści pięć stanowisk"))
        self.assertIn(18400.0, spoken_numbers("osiemnaście tysięcy czterysta złotych"))
        self.assertIn(7250.0, spoken_numbers("seven thousand two hundred fifty dollars"))
        self.assertIn(0.4, spoken_numbers("zero point four percent"))
        self.assertIn(17.4, spoken_numbers("iOS w wersji 17.4"))
        self.assertIn(88231.0, spoken_numbers("numer 88231"))
        self.assertEqual(digit_numbers("koszt 18 400 zł, iOS 17.4"), [18400.0, 17.4])
        self.assertEqual(digit_numbers("od 9:00 do 10:30"), [9.0, 10.0, 30.0])
        self.assertIn(11.0, spoken_numbers("na piątek o jedenastej"))
        self.assertIn(9.0, spoken_numbers("od dziewiątej do dwunastej"))


class DateTests(unittest.TestCase):
    WED = D(2026, 11, 18)

    def test_relative_words(self):
        self.assertEqual(resolve("do jutra", self.WED), {D(2026, 11, 19)})
        self.assertEqual(resolve("pojutrze", D(2026, 11, 23)), {D(2026, 11, 25)})
        self.assertEqual(resolve("dziś wieczorem", self.WED), {self.WED})
        self.assertEqual(resolve("by end of day", self.WED), {self.WED})

    def test_weekdays(self):
        self.assertEqual(resolve("do piątku", self.WED), {D(2026, 11, 20)})
        self.assertEqual(resolve("w przyszły wtorek", self.WED), {D(2026, 11, 24), D(2026, 12, 1)})
        self.assertEqual(resolve("next Friday", self.WED), {D(2026, 11, 20), D(2026, 11, 27)})
        self.assertEqual(resolve("środowe demo", D(2026, 11, 26)), {D(2026, 12, 2)})
        self.assertEqual(resolve("środowisko testowe", self.WED), set())

    def test_explicit_days(self):
        self.assertEqual(resolve("na trzeciego grudnia", D(2026, 11, 23)), {D(2026, 12, 3)})
        self.assertEqual(resolve("termin trzydziesty listopada", D(2026, 11, 25)), {D(2026, 11, 30)})
        self.assertEqual(resolve("for December first at ten", D(2026, 11, 23)), {D(2026, 12, 1)})
        self.assertEqual(resolve("do 1.12", D(2026, 11, 23)), {D(2026, 12, 1)})

    def test_weekday_in_a_later_week(self):
        tue = D(2026, 11, 24)
        self.assertIn(D(2026, 12, 7), resolve("za dwa tygodnie w poniedziałek", tue))
        self.assertIn(D(2026, 12, 2), resolve("za tydzień w środę", tue))
        self.assertIn(D(2026, 12, 7), resolve("two weeks from now on Monday", tue) | resolve("in two weeks on Monday", tue))

    def test_end_of_week(self):
        self.assertEqual(resolve("do końca tygodnia", D(2026, 11, 23)), {D(2026, 11, 27), D(2026, 11, 29)})


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.m = corpus.load("pl01-sprint")

    def action(self, **fields):
        base = {"type": "jira", "quote": "założę ticket na eksport CSV z polskimi znakami", "speaker": "Marta",
                "title": "Eksport CSV z polskimi znakami", "description": "", "assignee": "Ola", "due": "2026-11-20",
                "date_phrase": "do piątku", "condition": None}
        base.update(fields)
        return base

    def test_a_correct_action_passes_unchanged(self):
        kept, report, findings = guard.check(self.m, [self.action()])
        self.assertEqual(len(kept), 1)
        self.assertEqual(findings, [[]])
        self.assertEqual(kept[0]["due"], "2026-11-20")

    def test_a_quote_not_in_the_transcript_drops_the_action(self):
        kept, report, _ = guard.check(self.m, [self.action(quote="założę ticket na migrację bazy")])
        self.assertEqual(kept, [])
        self.assertEqual(report.dropped_quote, 1)

    def test_quote_is_case_and_punctuation_blind_but_word_bounded(self):
        self.assertIsNotNone(guard.locate_quote(self.m, "Jasne, założę ticket na eksport CSV..."))
        self.assertIsNotNone(guard.locate_quote(self.m, "Marta: Zrobię nam retro ... o czternastej"))
        self.assertIsNone(guard.locate_quote(self.m, "asne, założę"))

    def test_speaker_is_taken_from_the_line(self):
        kept, report, _ = guard.check(self.m, [self.action(speaker="Tomek")])
        self.assertEqual(kept[0]["speaker"], "Marta")
        self.assertEqual(report.speaker_fixed, 1)

    def test_invented_person_email_and_number(self):
        kept, report, _ = guard.check(self.m, [self.action(
            assignee="Zbigniew", description="Dotyczy 300 klientów.", to_emails=["ola@firma.pl"])])
        self.assertIsNone(kept[0]["assignee"])
        self.assertEqual(kept[0]["description"], "")
        self.assertEqual(kept[0]["to_emails"], [])
        self.assertEqual((report.person_removed, report.description_number, report.email_removed), (1, 1, 1))
        kept, report, _ = guard.check(self.m, [self.action(title="Eksport CSV dla 300 klientów")])
        self.assertEqual((kept, report.dropped_title_number), ([], 1))

    def test_dates(self):
        kept, report, _ = guard.check(self.m, [self.action(due="2026-11-21")])
        self.assertEqual((kept[0]["due"], report.date_fixed), ("2026-11-20", 1))
        # without a phrase the line says "do piątku" and "w poniedziałek": two readings, neither given, removed
        kept, report, _ = guard.check(self.m, [self.action(due="2026-11-21", date_phrase=None)])
        self.assertEqual((kept[0]["due"], report.date_removed), (None, 1))
        kept, report, _ = guard.check(self.m, [self.action(date_phrase=None)])
        self.assertEqual(kept[0]["due"], "2026-11-20")
        m3 = corpus.load("pl03-one-on-one")
        kept, report, _ = guard.check(m3, [{"type": "jira", "quote": "Założę ticket na refaktor modułu płatności",
                                            "speaker": "Ewa", "title": "Refaktor", "due": "2026-11-30"}])
        self.assertEqual((kept[0]["due"], report.date_removed), (None, 1))

    def test_time(self):
        retro = {"type": "calendar", "quote": "Zrobię nam retro w przyszły wtorek o czternastej", "speaker": "Marta",
                 "title": "Retro", "date": "2026-11-24", "date_phrase": "w przyszły wtorek", "time": "14:00",
                 "participants": ["Tomek", "Ola"]}
        kept, report, _ = guard.check(self.m, [retro])
        self.assertEqual((kept[0]["time"], report.time_removed), ("14:00", 0))
        agency = corpus.load("pl12-long-agency")
        pitch = {"type": "calendar", "quote": "umówię nas na prezentację dla Lavendo w czwartek o wpół do trzeciej",
                 "speaker": "Ja", "title": "Prezentacja", "date": "2026-11-26", "time": "14:30"}
        self.assertEqual(guard.check(agency, [pitch])[0][0]["time"], "14:30")
        pitch["time"] = "15:30"
        self.assertIsNone(guard.check(agency, [pitch])[0][0]["time"])
        retro["time"] = "15:00"
        kept, report, _ = guard.check(self.m, [retro])
        self.assertEqual((kept[0]["time"], report.time_removed), (None, 1))


class ScoreTests(unittest.TestCase):
    def test_match_trap_and_fields(self):
        m = corpus.load("pl01-sprint")
        actions = [
            {"type": "jira", "quote": "założę ticket na eksport CSV", "speaker": "Marta", "title": "Eksport CSV",
             "assignee": "Oli", "due": "2026-11-20", "condition": None},
            {"type": "email", "quote": "Ja wyślę mu maila z podsumowaniem po spotkaniu", "speaker": "Ola",
             "title": "Podsumowanie", "to": ["klient"]},
            {"type": "calendar", "quote": "retro w przyszły wtorek", "speaker": "Marta", "title": "Retro",
             "date": "2026-12-01", "time": "14:00", "participants": ["Tomek"]},
            {"type": "jira", "quote": "migracja całej bazy", "speaker": "Tomek", "title": "Migracja"},
        ]
        s = score.score_meeting(m, actions)
        self.assertEqual((s["tp"], s["fp"], s["fn"]), (2, 2, 0))
        self.assertEqual(s["classes"], ["match", "trap:other_speaker", "match", "bad_quote"])
        self.assertEqual(s["all_fields_ok"], 1)
        self.assertEqual(sorted(s["field_errors"]), ["a2:date", "a2:participants"])
        t = score.total([s])
        self.assertAlmostEqual(t["precision"], 0.5)
        self.assertAlmostEqual(t["recall"], 1.0)

    def test_parse_answer(self):
        self.assertEqual(run.parse_answer('```json\n{"actions": [{"type": "jira"}]}\n```'), ([{"type": "jira"}], True))
        self.assertEqual(run.parse_answer("no json"), ([], False))
        self.assertEqual(run.parse_answer('{"actions": []}'), ([], True))


if __name__ == "__main__":
    unittest.main()
