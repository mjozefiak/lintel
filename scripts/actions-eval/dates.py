"""Deterministic resolution of date phrases (Polish and English) against the meeting date.

`resolve(phrase, meeting_date)` returns the set of dates the phrase can mean; an empty set means the code found no
date expression it knows. Ambiguous phrases give every reading (`next Friday` -> two Fridays, `do końca tygodnia`
-> Friday and Sunday), so the guard only refuses a date no reading allows.
"""

import calendar
import datetime
import re

from textnorm import fold, ordinal_value

_PL_WEEKDAY = [
    r"poniedzial(?:ek|ku|kowe|kowy|kowego|kowym)",
    r"wtor(?:ek|ku|kowe|kowy|kowego|kowym)",
    r"srod(?:a|e|y|zie|owe|owy|owego|owym)",
    r"czwart(?:ek|ku|kowe|kowy|kowego|kowym)",
    r"piat(?:ek|ku|kowe|kowy|kowego|kowym)",
    r"sobot(?:a|e|y|nie|nia)",
    r"niedziel(?:a|e|i)",
]
_EN_WEEKDAY = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
_PL_MONTH = ["stycz", "lut", "mar", "kwie", "maj", "czerw", "lip", "sierp", "wrze", "pazdz", "listopad", "grud"]
_PL_MONTH_RE = (
    r"(stycznia|styczen|lutego|luty|marca|marzec|kwietnia|kwiecien|maja|maj|czerwca|czerwiec|lipca|lipiec|"
    r"sierpnia|sierpien|wrzesnia|wrzesien|pazdziernika|pazdziernik|listopada|listopad|grudnia|grudzien)"
)
_EN_MONTH = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
             "november", "december"]
_EN_MONTH_RE = r"(" + "|".join(_EN_MONTH) + r")"
_NEXT = r"(?:przyszl\w*|nastepn\w*|next|kolejn\w*)"


def _month_index(word):
    w = word.lower()
    for i, m in enumerate(_EN_MONTH):
        if w == m:
            return i + 1
    for i, stem in enumerate(_PL_MONTH):
        if w.startswith(stem):
            return i + 1
    return None


def _year_for(month, day, base):
    """The nearest such date not long before the meeting (a December date said in November is this year)."""
    for year in (base.year, base.year + 1):
        try:
            d = datetime.date(year, month, day)
        except ValueError:
            continue
        if d >= base - datetime.timedelta(days=31):
            return d
    return None


def _next_weekday(base, weekday):
    delta = (weekday - base.weekday()) % 7
    if delta == 0:
        delta = 7
    return base + datetime.timedelta(days=delta)


def resolve(phrase, base):
    text = " " + fold(phrase) + " "
    out = set()

    def day(n):
        out.add(base + datetime.timedelta(days=n))

    if re.search(r" (pojutrze|day after tomorrow) ", text):
        day(2)
    elif re.search(r" (jutro|jutra|jutrze|tomorrow) ", text):
        day(1)
    if re.search(r" (dzis|dzisiaj|dzisiejsz\w*|wieczorem|today|tonight|end of (the )?day|eod|this evening) ", text):
        day(0)
    if re.search(r" (za tydzien|in a week|a week from now|in one week) ", text):
        day(7)
    if re.search(r" (za dwa tygodnie|in two weeks|in 2 weeks|za 2 tygodnie) ", text):
        day(14)
    if re.search(r" (do )?konc\w* (tego )?tygodnia | end of (the |this )?week ", text):
        friday = base + datetime.timedelta(days=(4 - base.weekday()) % 7)
        out.add(friday)
        out.add(friday + datetime.timedelta(days=2))
    if re.search(r" (do )?konc\w* (tego )?miesiaca | end of (the |this )?month ", text):
        out.add(datetime.date(base.year, base.month, calendar.monthrange(base.year, base.month)[1]))

    for weeks, words in ((1, r"za tydzien|in a week|in one week|a week from now"),
                         (2, r"za dwa tygodnie|za 2 tygodnie|in two weeks|in 2 weeks|two weeks from now")):
        for index, pattern in enumerate(_PL_WEEKDAY + _EN_WEEKDAY):
            if re.search(r" (?:%s) (?:\w+ )?(?:%s) " % (words, pattern), text):
                later = base + datetime.timedelta(days=7 * weeks)
                out.add(later + datetime.timedelta(days=(index % 7) - later.weekday()))

    for index, pattern in enumerate(_PL_WEEKDAY + _EN_WEEKDAY):
        weekday = index % 7
        for match in re.finditer(r" (?:(%s) )?(?:\w+ )?(%s) " % (_NEXT, pattern), text):
            first = _next_weekday(base, weekday)
            out.add(first)
            if match.group(1) or re.search(r"(w przyszlym tygodniu|next week)", text):
                out.add(first + datetime.timedelta(days=7))

    # 3 grudnia / trzeciego grudnia / 3.12 / December 1st / 1 December / December first
    for match in re.finditer(r" (\d{1,2}) " + _PL_MONTH_RE + " ", text):
        d = _year_for(_month_index(match.group(2)), int(match.group(1)), base)
        if d:
            out.add(d)
    words = text.split()
    for i, w in enumerate(words):
        if _month_index(w) and (re.fullmatch(_PL_MONTH_RE, w) or re.fullmatch(_EN_MONTH_RE, w)):
            month = _month_index(w)
            candidates = []
            for size in (2, 1):
                before = words[max(0, i - size):i]
                if len(before) == size:
                    candidates.append(ordinal_value(before))
                after = words[i + 1:i + 1 + size]
                if len(after) == size:
                    candidates.append(ordinal_value(after))
            if i + 1 < len(words):
                m = re.fullmatch(r"(\d{1,2})(st|nd|rd|th)?", words[i + 1])
                if m:
                    candidates.append(int(m.group(1)))
            if i > 0:
                m = re.fullmatch(r"(\d{1,2})(st|nd|rd|th)?", words[i - 1])
                if m:
                    candidates.append(int(m.group(1)))
            for n in candidates:
                if n:
                    d = _year_for(month, n, base)
                    if d:
                        out.add(d)
                        break
    for match in re.finditer(r" (\d{1,2})\.(\d{1,2})(?:\.(\d{4}))? ", text):
        try:
            month, n = int(match.group(2)), int(match.group(1))
            d = datetime.date(int(match.group(3)), month, n) if match.group(3) else _year_for(month, n, base)
        except ValueError:
            d = None
        if d:
            out.add(d)
    for match in re.finditer(r" (\d{4})-(\d{2})-(\d{2}) ", text):
        try:
            out.add(datetime.date(int(match.group(1)), int(match.group(2)), int(match.group(3))))
        except ValueError:
            pass
    return out
