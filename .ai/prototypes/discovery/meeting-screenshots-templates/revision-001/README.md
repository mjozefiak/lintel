# Prototyp: zrzuty ekranu w trakcie spotkania i szablony notatek (rewizja 001)

- **Brief:** `~/.lintel-agents/2026-11-25/briefs/proto-granola.md` (poza repozytorium; brief orkiestratora, nie `product-brief.md`).
- **Spec:** `.ai/specs/2026-11-25-meeting-screenshots-and-templates.md`.
- **Data:** 2026-11-25. Poprzednia rewizja: brak.
- **Raport z panelu syntetycznego:** brak (nie uruchamiano; to nie jest ścieżka discovery z `om-synthetic-users`).
- **Otwieranie:** otwórz `index.html` w przeglądarce (działa offline, bez serwera). „Zacznij od nowa” w nagłówku przywraca stan początkowy. Wszystkie dane są wymyślone. Szkic niczego nie dowodzi o popycie ani o gotowości produkcyjnej.

## Odchylenie od formatu skilla

Skill `om-mockup-prototype` zaleca neutralną szarą stylistykę. Ten szkic używa palety i kształtu pastylki ze szkicu #273 (`.ai/specs/assets/minimal-hud/index.html` na gałęzi `spec/ux-minimal-hud`) i układu okna z #255, bo właściciel ocenia, czy przycisk zrzutu pasuje do minimalnej pastylki. Wygląd i tak ustala galeria SwiftUI (#248).

## Aktor, start, cel

- **Aktor:** osoba nagrywająca spotkanie w Lintelu (pracownik biurowy, nie musi znać IT).
- **Start:** spotkanie jest nagrywane, widać pastylkę spotkania; zgoda na nagrywanie ekranu nie była jeszcze pytana.
- **Cel (zrzuty):** w trakcie spotkania jednym kliknięciem zapisać to, co widać w oknie spotkania (slajd, tabela), i znaleźć to potem przy notatce.
- **Cel (szablony):** dostać notatkę w układzie pasującym do rodzaju spotkania (1:1, standup, klient, rekrutacja albo własny), bez utraty zasady „tylko to, co padło”.

## Ekrany i stany

| Id | Ekran / stan | Akcja | Następny stan | Reguły / założenia |
|---|---|---|---|---|
| `pill` | Pastylka w spoczynku: pierścień, czas, stop | najechanie albo Tab | pojawia się aparat (po fokusie też) | D-MIN, Q-2 |
| `pill` | Aparat bez pytanej zgody | klik | „Zrzuty wymagają zgody na nagrywanie ekranu · Pozwól” | D-TCC |
| `pill` | Zgoda jest | klik / ⌃⌥S | błysk, „Zrzut dodany · Cofnij” przez 4 s, potem spoczynek | A-1 (skrót), Q-1 |
| `pill` | Po zrzucie | Cofnij | zrzut usunięty, fokus wraca na aparat | — |
| `pill` | Odmowa zgody | klik | „Brak zgody na nagrywanie ekranu · Ustawienia · ✕” | D-TCC |
| `pill` | Okno spotkania niewidoczne | — | „Nie widzę okna spotkania · Zrzut ekranu · ✕” | Q-1, A-2 |
| `pill` | Zrzut nie udał się | Spróbuj ponownie | zrzut dodany | — |
| `permission` | Własne wyjaśnienie przed oknem systemu | Dalej / Nie teraz | okno systemu (symulowane) / bez zmian | D-TCC, Q-4 (treść 3. punktu zależy od wariantu) |
| `permission` | Okno systemu (symulacja) | zezwól / odmów | powrót do pastylki ze zrzutem / tekst o wklejaniu ⌘V | A-3 |
| `recording` | Panel nagrywania (#255) z wyborem szablonu i Moimi notatkami | Dodaj tekst, Zrzut okna spotkania, Zatrzymaj i napisz notatki | zrzut w Moich notatkach w miejscu kursora; notatka | Q-3, Q-14 |
| `note` | Notatka: pasek „Szablon: … · Zmień”, zakładki Notatki / Moje notatki / Transkrypcja | Zmień → szablon → Napisz od nowa | „Piszę notatki od nowa…” → nowe sekcje, komunikat | Q-5, D-REGEN |
| `note` | Warianty miejsca zrzutów | przełącznik | Moje notatki / pasek „Zrzuty ekranu (n)” / przy temacie | Q-3 |
| `note` | Podgląd zrzutu | Kopiuj, Pokaż w transkrypcji, Usuń zrzut, Zamknij | fokus na znaczniku zrzutu w transkrypcji; usunięcie do Ostatnio usuniętych | D-RD |
| `templates` | Lista szablonów (5 wbudowanych + własne) | Ustaw jako domyślny, Duplikuj, Edytuj, Usuń, Nowy szablon | komunikaty stanu | Q-6, Q-7 |
| `editor` | Edytor: nazwa, opis, do 8 sekcji, „Zawsze na końcu”, podgląd | Zapisz bez nazwy / z pustym nagłówkiem / poprawnie | błąd przy polu z fokusem / błąd sekcji / zapis i powrót | Q-8, A-4 |
| `settings` | Ustawienia → Spotkania (szablon, zrzuty, zakres) i Prywatność i dane (co trafia do piszącego notatki) | wariant Q-4 | tekst pomocy, plakietka, tabela przepływu danych | Q-4, Q-9 |
| `notfound` | Nieznany fragment URL | Wróć do pastylki | `#pill` | — |

Poza prototypem: Ustawienia systemowe macOS (symulowane jednym oknem), edycja treści notatki Lintela (piórko, #255), wyszukiwanie, eksport, Ostatnio usunięte (tylko komunikat).

## Reguły i decyzje, które szkic zachowuje (źródła)

- **D-MIN** pastylki skrajnie minimalne, komunikaty tylko przy problemie, jednolinijkowe: decyzja właściciela 2026-11-25 (`briefs/_common.md`), spec #273.
- **D-TCC** nagrywanie ekranu tylko za zgodą, pytanie dopiero przy pierwszym użyciu, dane lokalnie i szyfrowane jak reszta biblioteki: brief `proto-granola.md`.
- **D-MINE** „Moje notatki” pisze tylko człowiek, Lintel ich nie zmienia: #255 (Q8/Q9, warstwa `mine`).
- **D-RD** każde usunięcie idzie do Ostatnio usuniętych na 30 dni: decyzja właściciela 2026-11-24 (#247/#255).
- **D-REGEN** ponowne pisanie notatki chroni poprawki użytkownika mechanizmem propozycji: #257 (Data Model), istniejące zachowanie.
- **OD1 (#257)** bez czasów i bez oznaczeń AI w treści notatki Lintela. Szkic pokazuje czas tylko przy zrzucie (podpis obrazu i znacznik w transkrypcji), nie w treści notatki; czy to zgodne z OD1, to pytanie Q-12b w specu.
- **OD6 (#257)** wierność ponad pokrycie: szablon nie może dodać zmyśleń; tekst przy edytorze to mówi wprost.

## Założenia (do sprawdzenia)

- **[ZAŁOŻENIE A-1]** Skrót ⌃⌥S jest wolny i nie koliduje z ⌃⌥Space / ⌃⌥M z #247. Sprawdzić w `SymbolicHotkeys` i u właściciela.
- **[ZAŁOŻENIE A-2]** Lintel umie wskazać okno aplikacji spotkania (bundle id z detektora spotkań albo aplikacja, która używa mikrofonu). Spike w fazie 0 speca.
- **[ZAŁOŻENIE A-3]** Zachowanie zgody na nagrywanie ekranu na macOS 26 (czy po nadaniu potrzeba ponownego uruchomienia, jak często system przypomina, czy `SCContentSharingPicker` omija TCC). Spike w fazie 0.
- **[ZAŁOŻENIE A-4]** Limity edytora (8 sekcji, nagłówek 40 znaków, wskazówka 200, opis 300) mieszczą się w kontekście modelu wbudowanego (8192 tokenów) razem z transkryptem kawałka. Do policzenia w fazie szablonów.
- **[ZAŁOŻENIE A-5]** Treść notatek w szkicu (sekcje szablonu „Rozmowa z klientem”, „1:1”) to ilustracja kształtu, nie wynik modelu.

## Sprawdzenie (bramka jakości)

**Przegląd statyczny:** wszystkie odwołania lokalne (brak `http`, poza przestrzenią nazw SVG), brak `fetch`, storage, cookies; formularze mają `preventDefault`; dane wymyślone; tekst użytkownika trafia do węzłów tekstowych. Wynik: zaliczony po poprawkach opisanych niżej.

**Przejście w przeglądarce:** `agent-browser` 0.35.2 z lokalnej pamięci podręcznej (`~/.cache/agent-tools/agent-browser/v0.35.2/`; deskryptor przypina 0.38.2, więc sumy kontrolnej tej wersji nie sprawdzałem), sesja izolowana `proto-granola`, `file://`, okno 1280×900 i 390×844. Sesja zamknięta (`close`).

| # | Akcja | Oczekiwane | Zaobserwowane | Dowód |
|---|---|---|---|---|
| 1 | start `#pill` | pastylka: pierścień, 42:10, stop | tak | `evidence/01-pill-idle-pl-light.png`, `01b-pill-hover-pl-light.png` |
| 2 | klik aparatu bez zgody | linia „Zrzuty wymagają zgody… · Pozwól” | tak | `02-pill-need-permission.png` |
| 3 | Pozwól → Dalej → zezwól | powrót do `#pill`, „Zrzut dodany · Cofnij” | tak | `03-pill-captured-undo.png` |
| 4 | Cofnij | „Zrzut usunięty.”, 0 zrzutów, fokus na aparacie | tak | — |
| 5 | panel nagrywania: tekst + 2 zrzuty, szablon, Zatrzymaj | `#note`, szablon „Rozmowa z klientem”, fokus na nagłówku | tak | `04-…`, `05-…` |
| 6 | zakładka Moje notatki | 2 zrzuty w miejscu wstawienia | tak | `06-…` |
| 7 | warianty Q-3 i Q-5 | pasek „Zrzuty ekranu (2)”; zrzuty przy temacie; „Nie padło…” | tak | `07-…`, `08-…` |
| 8 | podgląd → Pokaż w transkrypcji | fokus na znaczniku zrzutu 12:07 | tak | `09-…`, `10-…` |
| 9 | Zmień → 1:1 → Napisz od nowa | dialog, stan „Piszę…”, nowe sekcje, komunikat | tak | `11-…`, `12-…` |
| 10 | Zarządzaj szablonami → Nowy → Zapisz pusty | błąd „Nadaj szablonowi nazwę.”, fokus w polu | tak | `13-…`, `14-…` |
| 11 | nazwa bez nagłówka sekcji → Zapisz | „Każda sekcja potrzebuje nagłówka.”, fokus w sekcji 1 | tak | — |
| 12 | poprawne dane → Zapisz | powrót do listy, „Zapisano szablon…”, 6 szablonów | tak | `15-…`, `15b-…`, `16-…` |
| 13 | Ustaw jako domyślny, Usuń własny | komunikaty, 5 szablonów | tak | — |
| 14 | wstecz / dalej przeglądarki | `#editor` / `#templates` | tak | — |
| 15 | `#nope` | ekran „Nie ma takiego ekranu” z linkiem | tak | `17-unknown-fragment.png` |
| 16 | odmowa, brak okna, błąd zrzutu, Spróbuj ponownie | linie z jedną akcją i ✕; ponowienie dodaje zrzut | tak | `18-…`, `19-…`, `20-…` |
| 17 | Ustawienia, warianty Q-4 | tekst pomocy, plakietka, tabela, punkt w arkuszu zgody | tak | `21-…`–`23-…` |
| 18 | EN + ciemny | wszystkie teksty po angielsku, ciemne powierzchnie | tak | `24-…`–`26b-…` |
| 19 | szerokość 390 | brak poziomego przewijania (390 = 390) | tak | `27-narrow-recording.png` |
| 20 | klawiatura: Tab do aparatu, Enter, Tab+Enter | aparat dostaje fokus i się pokazuje; prośba o zgodę; `#permission` z fokusem na nagłówku | tak | `28-keyboard-focus-camera.png` |
| 21 | Zacznij od nowa | `#pill`, 0 zrzutów, zgoda „nie pytano”, komunikat o resecie | tak | — |

**Naprawione w trakcie:** (1) aparat ukryty `display:none` był nieosiągalny klawiaturą i niewidoczny dla czytnika ekranu; teraz jest zwinięty, ale fokusowalny, i rozwija się przy fokusie (ten sam wymóg trafia do speca); (2) komunikaty stanu zostawały w poprzednim języku po przełączeniu PL/EN; (3) błąd „Każda sekcja potrzebuje nagłówka” nie znikał po poprawce.

**Nie sprawdzono:** VoiceOver (tylko drzewo dostępności z `snapshot`), Increase Contrast, zachowanie prawdziwego panelu bez aktywacji (najechanie na pastylkę aplikacji w tle, #273 R2), prawdziwe okno zgody macOS.

Verification: passed (dla zachowania szkicu; nie dla założeń produktowych).
