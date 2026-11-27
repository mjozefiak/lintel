"""The field guard of the actions-detection spike (in the spirit of `NotesFactGuard`).

Every proposed action is checked against the transcript before it could reach a card:

* `quote` must be a verbatim part of ONE utterance (folded: case, diacritics and punctuation ignored); otherwise the
  action is dropped. The action's `speaker` is then set to that utterance's speaker.
* persons (`to`, `participants`, `assignee`) must be named in the transcript (a speaker label or a word, in any
  grammatical case); an unsupported person is removed.
* e-mail addresses must appear verbatim; an unsupported one is removed.
* the date (`date` of an event, `due` of a mail or ticket) must follow from `date_phrase` (or, without one, from the
  quote's line) by the code's own resolver (`dates.resolve`): a date no reading allows is replaced by the only
  reading or removed. When neither says a day, a date read from the two lines around the quote is kept; anything
  else is removed. A neighbouring line never replaces a date.
* the time must be said near the quote (digits or an hour word); otherwise removed.
* every number in `title` and `description` must be said in the transcript; a title with an unsupported number
  drops the action, a description with one is emptied.

The report counts what each rule did. Nothing here logs text.
"""

import copy
import datetime
import re

from dates import resolve
from textnorm import digit_numbers, fold, name_supported, spoken_numbers, tokens

PERSON_LIST_FIELDS = ("to", "participants")
NEIGHBOURHOOD = 2

_PL_HOURS = {
    1: ["pierwsz"], 2: ["drug"], 3: ["trzeci"], 4: ["czwart"], 5: ["piat"], 6: ["szost"], 7: ["siodm"],
    8: ["osm"], 9: ["dziewiat"], 10: ["dziesiat"], 11: ["jedenast"], 12: ["dwunast", "poludni"],
    13: ["trzynast"], 14: ["czternast"], 15: ["pietnast"], 16: ["szesnast"], 17: ["siedemnast"],
    18: ["osiemnast"], 19: ["dziewietnast"], 20: ["dwudziest"], 21: ["dwudziest"], 22: ["dwudziest"],
    23: ["dwudziest"],
}
_EN_HOURS = {
    1: ["one"], 2: ["two"], 3: ["three"], 4: ["four"], 5: ["five"], 6: ["six"], 7: ["seven"], 8: ["eight"],
    9: ["nine"], 10: ["ten"], 11: ["eleven"], 12: ["twelve", "noon"],
}


def date_field(action):
    return "date" if action.get("type") == "calendar" else "due"


def locate_quote(meeting, quote):
    """The utterance that holds the quote, or None. `...` splits a quote into parts that must appear in order."""
    if not quote or not isinstance(quote, str):
        return None
    text = quote.strip()
    for speaker in meeting.speakers:
        if text.startswith(speaker + ":"):
            text = text[len(speaker) + 1:]
    parts = [fold(p) for p in re.split(r"\.\.\.|…", text)]
    parts = [p for p in parts if p]
    if not parts:
        return None
    for u in meeting.utterances:
        body = fold(u.text)
        position = 0
        ok = True
        for p in parts:
            found = body.find(p, position)
            if found < 0 or not _word_bounded(body, found, len(p)):
                ok = False
                break
            position = found + len(p)
        if ok:
            return u
    return None


def _word_bounded(body, start, length):
    before = start == 0 or body[start - 1] == " "
    after = start + length == len(body) or body[start + length] == " "
    return before and after


def transcript_tokens(meeting):
    out = []
    for u in meeting.utterances:
        out.extend(tokens(u.text))
        out.extend(tokens(u.speaker))
    return out


def _neighbourhood(meeting, utterance):
    lo = max(1, utterance.id - NEIGHBOURHOOD)
    hi = min(len(meeting.utterances), utterance.id + NEIGHBOURHOOD)
    return [u for u in meeting.utterances if lo <= u.id <= hi]


def time_supported(value, texts):
    match = re.fullmatch(r"(\d{1,2}):(\d{2})", value or "")
    if not match:
        return False
    hour, minute = int(match.group(1)), int(match.group(2))
    folded = " " + " ".join(fold(t) for t in texts) + " "
    if minute == 30:
        # "wpół do trzeciej" is 2:30 (or 14:30)
        for h in {hour, hour - 12 if hour > 12 else hour}:
            for stem in _PL_HOURS.get(h + 1, []):
                if re.search(r" wpol do %s\w* " % stem, folded):
                    return True
    hour_ok = False
    for h in {hour, hour - 12 if hour > 12 else hour}:
        if re.search(r"(?<!\d)0?%d(?:[:.]\d{2})?(?!\d)" % h, folded):
            hour_ok = True
        for stem in _PL_HOURS.get(h, []) + _EN_HOURS.get(h, []):
            if re.search(r" %s\w* " % stem, folded):
                hour_ok = True
    if not hour_ok:
        return False
    if minute == 0:
        return True
    if minute == 30 and re.search(r" (trzydziesci|thirty|half) ", folded):
        return True
    return bool(re.search(r"(?<!\d)%02d(?!\d)" % minute, folded)) or float(minute) in spoken_numbers(" ".join(texts))


class Report(object):
    KEYS = (
        "proposed", "kept", "dropped_quote", "dropped_title_number", "speaker_fixed", "person_removed",
        "email_removed", "date_fixed", "date_removed", "time_removed", "description_number", "condition_unquoted",
    )

    def __init__(self):
        for key in self.KEYS:
            setattr(self, key, 0)

    def add(self, other):
        for key in self.KEYS:
            setattr(self, key, getattr(self, key) + getattr(other, key))

    def as_dict(self):
        return dict((key, getattr(self, key)) for key in self.KEYS)


def check_action(meeting, action, known_tokens=None, numbers=None):
    """(guarded action or None, per-action findings). Findings name the rule, never the text."""
    findings = []
    known_tokens = known_tokens if known_tokens is not None else transcript_tokens(meeting)
    numbers = numbers if numbers is not None else spoken_numbers(" ".join(u.text for u in meeting.utterances))
    act = copy.deepcopy(action)
    utterance = locate_quote(meeting, act.get("quote"))
    if utterance is None:
        return None, ["dropped_quote"]
    act["_utterance"] = utterance.id
    if (act.get("speaker") or "").strip() != utterance.speaker:
        findings.append("speaker_fixed")
        act["speaker"] = utterance.speaker

    for field in PERSON_LIST_FIELDS:
        values = act.get(field)
        if isinstance(values, list):
            kept = [v for v in values if isinstance(v, str) and name_supported(v, known_tokens)]
            findings.extend(["person_removed"] * (len(values) - len(kept)))
            act[field] = kept
    assignee = act.get("assignee")
    if isinstance(assignee, str) and assignee.strip() and not name_supported(assignee, known_tokens):
        findings.append("person_removed")
        act["assignee"] = None

    emails = act.get("to_emails")
    if isinstance(emails, list):
        raw = " ".join(u.text for u in meeting.utterances).casefold()
        kept = [e for e in emails if isinstance(e, str) and e.casefold() in raw]
        findings.extend(["email_removed"] * (len(emails) - len(kept)))
        act["to_emails"] = kept

    field = date_field(act)
    value = act.get(field)
    if isinstance(value, str) and value.strip():
        try:
            given = datetime.date.fromisoformat(value.strip())
        except ValueError:
            given = None
        readings = set()
        phrase = act.get("date_phrase")
        if isinstance(phrase, str) and phrase.strip():
            whole = fold(" ".join(u.text for u in meeting.utterances))
            if fold(phrase) and fold(phrase) in whole:
                readings = resolve(phrase, meeting.date)
        if not readings:
            readings = resolve(utterance.text, meeting.date)
        nearby = resolve(" . ".join(u.text for u in _neighbourhood(meeting, utterance)), meeting.date)
        if given is not None and (given in readings or (not readings and given in nearby)):
            act[field] = given.isoformat()
        elif len(readings) == 1:
            findings.append("date_fixed")
            act[field] = next(iter(readings)).isoformat()
        else:
            findings.append("date_removed")
            act[field] = None

    if isinstance(act.get("time"), str) and act["time"].strip():
        if not time_supported(act["time"].strip(), [u.text for u in _neighbourhood(meeting, utterance)]):
            findings.append("time_removed")
            act["time"] = None

    if any(n not in numbers for n in digit_numbers(act.get("title") or "")):
        return None, findings + ["dropped_title_number"]
    if any(n not in numbers for n in digit_numbers(act.get("description") or "")):
        findings.append("description_number")
        act["description"] = ""

    condition = act.get("condition")
    if isinstance(condition, str) and condition.strip():
        words = set(tokens(condition))
        heard = set(known_tokens)
        if words and len(words & heard) / float(len(words)) < 0.6:
            findings.append("condition_unquoted")
    return act, findings


def check(meeting, actions):
    """(kept actions, Report, per-action findings in input order)."""
    report = Report()
    known = transcript_tokens(meeting)
    numbers = spoken_numbers(" ".join(u.text for u in meeting.utterances))
    kept = []
    per_action = []
    for action in actions:
        report.proposed += 1
        guarded, findings = check_action(meeting, action, known, numbers)
        per_action.append(findings)
        for f in findings:
            setattr(report, f, getattr(report, f) + 1)
        if guarded is not None:
            report.kept += 1
            kept.append(guarded)
    return kept, report, per_action
