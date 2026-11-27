"""Text helpers shared by the guard and the scorer: folding, tokens, names and numbers (Polish and English)."""

import re
import unicodedata

_EXTRA = {"ł": "l", "Ł": "l", "đ": "d", "ø": "o"}


def fold(text):
    """Lower case without diacritics (also `ł`, which NFKD keeps), punctuation turned into spaces."""
    text = "".join(_EXTRA.get(c, c) for c in (text or ""))
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c)).casefold()
    text = re.sub(r"[^\w@.:]+", " ", text)
    text = re.sub(r"(?<!\d)[.:]|[.:](?!\d)", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def tokens(text):
    return [t for t in fold(text).split(" ") if t]


STOP = {
    "at", "from", "of", "the", "and", "team", "z", "ze", "i", "oraz", "pan", "pani", "panem", "panu", "pana",
    "mr", "mrs", "ms", "w", "we", "do", "dla", "na",
}


def name_token_matches(name_token, text_token):
    """A name in another case (`Ola`/`Oli`, `Tomek`/`Tomka`, `Halina`/`Halinie`) shares a long prefix."""
    if name_token == text_token:
        return True
    n = len(name_token)
    need = max(2, n - 1) if n <= 4 else max(3, n - 2)
    return len(text_token) >= need and text_token[:need] == name_token[:need]


def name_supported(name, haystack_tokens):
    """Every content token of the name appears (in some case) among the transcript's tokens."""
    parts = [t for t in tokens(name) if t not in STOP and not t.isdigit()]
    if not parts:
        return False
    return all(any(name_token_matches(p, t) for t in haystack_tokens) for p in parts)


def names_match(a, b):
    """Two person strings name the same person: some content token of one matches one of the other."""
    ta = [t for t in tokens(a) if t not in STOP]
    tb = [t for t in tokens(b) if t not in STOP]
    return any(name_token_matches(x, y) or name_token_matches(y, x) for x in ta for y in tb)


# --- numbers -------------------------------------------------------------------------------------------------------

_PL_UNITS = {
    "zero": 0, "jeden": 1, "jedna": 1, "jedno": 1, "jednego": 1, "dwa": 2, "dwie": 2, "dwoch": 2, "dwu": 2,
    "trzy": 3, "trzech": 3, "cztery": 4, "czterech": 4, "piec": 5, "pieciu": 5, "szesc": 6, "szesciu": 6,
    "siedem": 7, "siedmiu": 7, "osiem": 8, "osmiu": 8, "dziewiec": 9, "dziewieciu": 9,
    "dziesiec": 10, "dziesieciu": 10, "jedenascie": 11, "jedenastu": 11, "dwanascie": 12, "dwunastu": 12,
    "trzynascie": 13, "trzynastu": 13, "czternascie": 14, "czternastu": 14, "pietnascie": 15, "pietnastu": 15,
    "szesnascie": 16, "szesnastu": 16, "siedemnascie": 17, "siedemnastu": 17, "osiemnascie": 18,
    "osiemnastu": 18, "dziewietnascie": 19, "dziewietnastu": 19,
}
_PL_TENS = {
    "dwadziescia": 20, "dwudziestu": 20, "trzydziesci": 30, "trzydziestu": 30, "czterdziesci": 40,
    "czterdziestu": 40, "piecdziesiat": 50, "piecdziesieciu": 50, "szescdziesiat": 60, "szescdziesieciu": 60,
    "siedemdziesiat": 70, "siedemdziesieciu": 70, "osiemdziesiat": 80, "osiemdziesieciu": 80,
    "dziewiecdziesiat": 90, "dziewiecdziesieciu": 90,
}
_PL_HUNDREDS = {
    "sto": 100, "stu": 100, "dwiescie": 200, "dwustu": 200, "trzysta": 300, "trzystu": 300, "czterysta": 400,
    "czterystu": 400, "piecset": 500, "pieciuset": 500, "szescset": 600, "szesciuset": 600, "siedemset": 700,
    "siedmiuset": 700, "osiemset": 800, "osmiuset": 800, "dziewiecset": 900, "dziewieciuset": 900,
}
_PL_THOUSAND = {"tysiac", "tysiace", "tysiecy", "tysiaca", "tysiacach"}
_EN_UNITS = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
    "seventeen": 17, "eighteen": 18, "nineteen": 19,
}
_EN_TENS = {
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
}
_PL_ORD = {
    "pierwszy": 1, "pierwszego": 1, "drugi": 2, "drugiego": 2, "trzeci": 3, "trzeciego": 3, "czwarty": 4,
    "czwartego": 4, "piaty": 5, "piatego": 5, "szosty": 6, "szostego": 6, "siodmy": 7, "siodmego": 7, "osmy": 8,
    "osmego": 8, "dziewiaty": 9, "dziewiatego": 9, "dziesiaty": 10, "dziesiatego": 10, "jedenasty": 11,
    "jedenastego": 11, "dwunasty": 12, "dwunastego": 12, "trzynasty": 13, "trzynastego": 13, "czternasty": 14,
    "czternastego": 14, "pietnasty": 15, "pietnastego": 15, "szesnasty": 16, "szesnastego": 16,
    "siedemnasty": 17, "siedemnastego": 17, "osiemnasty": 18, "osiemnastego": 18, "dziewietnasty": 19,
    "dziewietnastego": 19, "dwudziesty": 20, "dwudziestego": 20, "trzydziesty": 30, "trzydziestego": 30,
}
_EN_ORD = {
    "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
    "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15,
    "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19, "twentieth": 20, "thirtieth": 30,
}

# hours are said with feminine ordinals: "o jedenastej", "na dziewiątą", "czternasta"
_PL_HOUR_STEMS = {
    "pierwsz": 1, "drug": 2, "trzeci": 3, "czwart": 4, "piat": 5, "szost": 6, "siodm": 7, "osm": 8, "dziewiat": 9,
    "dziesiat": 10, "jedenast": 11, "dwunast": 12, "trzynast": 13, "czternast": 14, "pietnast": 15, "szesnast": 16,
    "siedemnast": 17, "osiemnast": 18, "dziewietnast": 19, "dwudziest": 20,
}
for _stem, _value in _PL_HOUR_STEMS.items():
    for _ending in ("a", "ej", "e"):
        _PL_ORD.setdefault(_stem + _ending, _value)

ORDINALS = dict(_PL_ORD)
ORDINALS.update(_EN_ORD)


def ordinal_value(words):
    """`dwudziestego pierwszego` / `twenty first` / `trzeciego` as a day number, else None."""
    words = [w for w in words if w]
    if not words:
        return None
    if len(words) == 2 and words[0] in ("dwudziesty", "dwudziestego", "twenty", "trzydziesty", "trzydziestego", "thirty"):
        base = 20 if words[0] in ("dwudziesty", "dwudziestego", "twenty") else 30
        unit = ORDINALS.get(words[1])
        if unit is not None and unit < 10:
            return base + unit
    if len(words) == 1:
        return ORDINALS.get(words[0])
    return None


def _word_value(token):
    for table in (_PL_UNITS, _PL_TENS, _PL_HUNDREDS, _EN_UNITS, _EN_TENS):
        if token in table:
            return table[token]
    return None


def spoken_numbers(text):
    """Every number written in words or digits in the text (`osiemnaście tysięcy czterysta` -> 18400)."""
    found = set()
    raw = (text or "").replace(" ", " ")
    for match in re.finditer(r"\d+(?:[ ,.]\d{3})+(?!\d)|\d+(?:[.,]\d+)?", raw):
        s = match.group(0)
        if re.fullmatch(r"\d+(?:[ ,.]\d{3})+", s):
            found.add(float(re.sub(r"[ ,.]", "", s)))
            # `17.4` style versions also read as a decimal
        try:
            found.add(float(s.replace(",", ".")))
        except ValueError:
            pass
        for part in re.split(r"[ ,.]", s):
            if part.isdigit():
                found.add(float(part))
    words = tokens(raw)
    i = 0
    while i < len(words):
        total, current, used = 0, 0, False
        j = i
        while j < len(words):
            w = words[j]
            v = _word_value(w)
            if v is not None:
                current += v
                used = True
            elif w in _PL_THOUSAND or w == "thousand":
                total += max(current, 1) * 1000
                current = 0
                used = True
            elif w == "hundred" and used:
                current *= 100
            elif w in ("and",) and used:
                pass
            elif w in ("point", "przecinek") and used and j + 1 < len(words) and _word_value(words[j + 1]) is not None:
                decimals = ""
                k = j + 1
                while k < len(words) and _word_value(words[k]) is not None and _word_value(words[k]) < 10:
                    decimals += str(_word_value(words[k]))
                    k += 1
                if decimals:
                    found.add(float("%d.%s" % (total + current, decimals)))
                j = k - 1
            else:
                break
            j += 1
        if used:
            found.add(float(total + current))
            # every prefix value too, so "dwadzieścia procent" and "czterdzieści pięć" both count
            sub = 0
            for w in words[i:j]:
                v = _word_value(w)
                if v is not None:
                    sub += v
                    found.add(float(sub))
            i = j
        else:
            o = ordinal_value(words[i:i + 2]) or ordinal_value(words[i:i + 1])
            if o is not None:
                found.add(float(o))
            i += 1
    return found


def digit_numbers(text):
    """Numbers written with digits in a model's field, as floats (`18 400` -> 18400, `17.4` -> 17.4)."""
    out = []
    raw = (text or "").replace(" ", " ")
    for match in re.finditer(r"(?<!\d)(\d{1,2}):(\d{2})(?!\d)", raw):
        out.append(float(int(match.group(1))))
        if match.group(2) != "00":
            out.append(float(int(match.group(2))))
    raw = re.sub(r"(?<!\d)\d{1,2}:\d{2}(?!\d)", " ", raw)
    for match in re.finditer(r"\d{1,3}(?:[ ,]\d{3})+(?!\d)|\d+(?:[.,]\d+)?", raw):
        s = match.group(0)
        if re.fullmatch(r"\d{1,3}(?:[ ,]\d{3})+", s):
            out.append(float(re.sub(r"[ ,]", "", s)))
        else:
            out.append(float(s.replace(",", ".")))
    return out
