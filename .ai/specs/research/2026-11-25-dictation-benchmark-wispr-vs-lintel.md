# Dyktowanie: Lintel vs Wispr Flow — wyniki benchmarku (2026-11-25)

## Metoda

- Te same nagrania odtwarzane do wirtualnego mikrofonu BlackHole 2ch. Sterownik `tools/dictate-drive` wciska skrót aplikacji i czyta tekst wklejony do TextEdit.
- Ocena: `tools/score_dictation.py` (WER/CER z polską normalizacją, trafione terminy `must`, autopoprawki `must_not`, opóźnienie od puszczenia klawisza do tekstu).
- Lintel 0.1.0-beta.1: Parakeet Ultra + porządkowanie Qwen3-30B-A3B (`CleanupPrompt` v1, `FormatterGuard` zakres długości 0.6–1.15).
- Wispr Flow Pro.
- Dane i wyniki: `~/DeveloperTools/lintel-market-benchmark/` (`results/dictation/`).

## FLEURS (czytany tekst, 60 zdań na język)

### Polski (PL, 60 zdań)

| Aplikacja | WER % | CER % | Opóźnienie p50 / p90 |
|---|---|---|---|
| Lintel cleanup | 7.8 | 3.4 | 0.87 s / 1.11 s |
| Lintel raw | 6.5 | 1.7 | 0.13 s / 0.13 s |
| Wispr Flow | 6.4 | 1.9 | 1.09 s / 1.35 s |

### Angielski (EN, 59 zdań, bez 1883)

| Aplikacja | WER % | CER % | Opóźnienie p50 / p90 |
|---|---|---|---|
| Lintel cleanup | 6.5 | 3.3 | 0.60 s / 0.72 s |
| Lintel raw | 5.5 | 2.3 | 0.13 s / 0.13 s |
| Wispr Flow | 4.9 | 1.9 | 0.38 s / 0.49 s |

**Wniosek:** po polsku sam Parakeet dorównuje Wisprowi; porządkowanie dokłada +1,3 pkt WER i ~0,75 s. Po angielsku różnica ASR wynosi 0,6 pkt (nazwy własne: „Eric Duret” zamiast „Erik the Red”).

## Korpus głosu właściciela (40 wypowiedzi PL/EN: maile, czat, autopoprawki, terminy, liczby, listy, kod, mieszanie języków)

| Aplikacja | WER % | CER % | Terminy % | Autopoprawki OK % | Zostawione zakazane % | Opóźnienie p50 / p90 |
|---|---|---|---|---|---|---|
| Lintel raw | 30.3 | 16.9 | 69 | 0 | 62 | 0.13 s / 0.14 s |
| Lintel cleanup | 25.2 | 15.3 | 74 | 29 | 25 | 0.63 s / 0.97 s |
| Wispr Flow | 20.6 | 10.4 | 73 | 71 | 8 | 0.63 s / 0.86 s |

### WER % wg kategorii

| Kategoria | Lintel cleanup | Lintel raw | Wispr |
|---|---|---|---|
| chat | 19.5 | 19.6 | 23.7 |
| code | 59.1 | 72.7 | 42.4 |
| code-switch | 51.1 | 57.2 | 29.2 |
| keep-not-correction | 18.8 | 18.8 | 0.0 |
| list | 42.6 | 38.9 | 13.0 |
| long | 25.3 | 27.3 | 28.7 |
| mail | 15.6 | 17.1 | 15.4 |
| numbers | 12.2 | 12.5 | 12.5 |
| self-correction | 45.8 | 84.7 | 27.8 |
| terms | 20.3 | 20.8 | 15.6 |

## Problemy Lintela (dowody)

1. **Porządkowanie zmienia sens (krytyczne).**
   - „pizzę na szesnastą, sorry, na siedemnastą” → raw poprawnie: „na 16, sorry na 17”; cleanup odwrócone: „na 17, sorry, na 16”.
   - „6 cali deszczu” → „60 mm”.
   - „szympansy na sawannie” → „ludzie”.
   - „na urlokie” (ASR) → „na Europie”.
   - Usuwa szczegóły: „(Larson and LaFasto, 1989, p109)” → bez roku i strony; „przepięknej” wycięte.
   - Przeredagowuje poprawne zdania: „zredukowanie” → „zmniejszenie”; „women travellers” → „female travelers”.
   - Przyczyny w kodzie:
     - `CleanupPrompt` pozwala na „fix obvious recognition errors”.
     - `FormatterGuard` przyjmuje wynik krótszy nawet o 40% i nie sprawdza liczb.
     - Przykład w prompcie zostawia „at ten” słownie, mimo reguły o liczbach.
2. **Autopoprawki działają rzadko:** 29% wobec 71% u Wispra. Przykład: „dwadzieścia tysięcy, to znaczy dwadzieścia pięć” zostaje w całości; Wispr: „25 000 zł”.
3. **Brak list:** nawet po „po pierwsze, po drugie” Lintel pisze jednym zdaniem; Wispr zawsze robi listę.
4. **Mieszanie PL/EN i kod:** Parakeet gubi język. „Zróbmy szybki follow-up” → „Sr. všetky follow up” (słowacki). „w Jirze” → „w bliżże”. „endpointu” → „and Pointu”.
5. **Utrata tekstu:** raz na 240 dyktowań Lintel (tryb raw) wkleił tylko połowę wypowiedzi (FLEURS EN 1883: „…is 15 meters, construction” i koniec).
6. **Opóźnienie:** raw 0,13 s (najszybszy); cleanup 0,6–0,9 s.

## Słabości Wispr Flow

- Nie usuwa polskiej autopoprawki „we wtorek… albo jednak w środę”.
- Na liście zakupów „kawa ziarnista” → „kawa, żelki”.
- Opóźnienie po polsku: 1,1 s.

## Decyzja i prośba właściciela (2026-11-25)

Lintel ma mieć kilka trybów porządkowania z regulowaną siłą, jak Wispr Flow. Propozycja:

- **Lekki:** interpunkcja, wielkie litery, usunięcie wtrąceń „yyy”, liczby cyframi; bez zmiany słów. Można pominąć model dla czystego tekstu.
- **Standardowy:** wszystko z poziomu Lekkiego, plus autopoprawki i listy po „po pierwsze”.
- **Pełny:** wszystko z poziomu Standardowego, plus układ maila, akapity i lekka redakcja.

Na każdym poziomie liczby, nazwy i szczegóły muszą zostać jak w transkrypcie.

## Następne kroki (priorytet)

1. **Wierność:** `CleanupPrompt` v2 (zakaz przeliczania, skracania i zmiany liczb; przykłady: autopoprawka z liczbą, lista, mail) oraz `FormatterGuard` sprawdzający, że każda liczba z transkryptu jest w wyniku, i ostrzejszy zakres długości.
2. **Poziomy porządkowania** (ustawienie).
3. **Język przy mieszaniu PL/EN:** przypięcie języka lub Whisper turbo — zmierzyć na tym samym korpusie.
4. **Utrata połowy tekstu** (1/240): zbadać przyczynę.

Każdą zmianę mierzyć ponownie tym samym korpusem (`dictate-drive` + `score_dictation.py`), bez udziału właściciela.
