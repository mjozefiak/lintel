# Lintel: pierwszy miesiąc marketingu (24.11 – 31.12.2026)

> Status: **propozycja do akceptacji właściciela**. Budżet: 0 zł (domena i certyfikat Developer ID już są).
> Źródła (research agentów, 2026-11-23, z URL-ami i oznaczeniami FACT/INFERENCE/UNVERIFIED):
> - `research/2026-11-23-marketing-competitor-gtm.md` — Wispr Flow, Superwhisper, VoiceInk, Meetily, Hyprnote
> - `research/2026-11-23-marketing-channels.md` — kanały, zasady subredditów, timing Show HN, polskie kanały
> - `research/2026-11-23-marketing-community-feedback.md` — jak zamienić userów w zgłaszających issues
> - audyt gotowości repo (podsumowany w sekcji „Tydzień 0”)

## Cel miesiąca

Nie zasięg, tylko **20–50 prawdziwych użytkowników, z których ~10 zgłasza issues albo rozmawia z autorem**. Wszystko poniżej jest pod to ustawione: mało kanałów, każdy z prośbą o feedback i z łatwą drogą do niego.

## Czego uczy konkurencja (skrót)

- **Wispr Flow** nie urósł dzięki reklamom na starcie. Pierwsza fala to: gęsta sieć (VC i founderzy z Doliny), **founder osobiście onboardujący pierwszych userów**, jeden mocno przygotowany Product Hunt (#1 dnia i tygodnia), potem długie posty userów i foundera na X/LinkedIn. Reklamy, UGC za 500 mln wyświetleń, afiliacja i celebryci przyszli dopiero z pieniędzmi z VC — **do pominięcia**.
- **Superwhisper**: Show HN w pierwszej osobie („zbudowałem, bo wkurzało mnie natywne dyktowanie”), darmowy lokalny tier, bardzo częste release'y ogłaszane na X.
- **VoiceInk / Meetily** (open source): gwiazdki przyszły z **„darmowa alternatywa dla <znana płatna marka>”**, katalogów (AlternativeTo, openalternative), Homebrew i regularnych artykułów (Meetily: seria na dev.to). Ich zwykłe Show HN miały 2–4 punkty.
- **Wniosek z HN**: tytuły z nazwą produktu dostawały 2–43 punkty; „Free alternative to Wispr Flow, Superwhisper…” (freeflow, 02.2026) — 277 punktów. Framing robi różnicę.
- **Nisza jest zatłoczona** (OpenWhisper, Ghost Pepper, Yap, Handy, VoiceInk, Meetily, HushScribe). Sam „lokalny Whisper” nie wystarczy. Wyróżniki Lintela, które są prawdziwe dziś: **dyktowanie + notatki ze spotkań z mówcami w jednej szyfrowanej aplikacji, bez bota, bez konta, polski jako pełnoprawny język, podpisane i notaryzowane** (sprawdzone 2026-11-23: `spctl` → „Notarized Developer ID”, staple OK — wielu konkurentów OSS tego nie ma).

## Pozycjonowanie na start

- **EN (HN, Reddit, katalogi):** „Free, open-source alternative to Wispr Flow and Granola. Dictation and meeting notes that run on your Mac.”
- **PL:** „Darmowe dyktowanie i notatki ze spotkań, które działają na Twoim Macu. Po polsku. Open source, zrobione w Polsce.”
- Prowadzimy rozpoznawaniem mowy na urządzeniu; lokalny LLM jest drugi (r/opensource i część społeczności odrzuca „AI projects”).
- **Nie mówimy:** „nic nie opuszcza Maca” (modele pobierają się z Hugging Face, są aktualizacje), nie chwalimy jakości polskiego liczbami, których nie zmierzyliśmy, zawsze podajemy wymagania: macOS 26, Apple silicon, model notatek ~2,5 GB, etykiety mówców do 90 min nagrania.

## Tydzień 0 (24–30.11): napraw, zanim ktokolwiek zobaczy

Blokery z audytu, w kolejności:

1. **Appcast 404** — `SUFeedURL` = `https://lintelapp.com/appcast.xml` zwraca 404. Bez tego pierwsi userzy utkną na beta.1 bez poprawek. **Najważniejsze.**
2. **README i opis repo** prowadzą launcherem (dyktowanie i spotkania są 4. i 5., „off by default”). Przepisać: nagłówek jak wyżej, 2 GIF-y po 10–20 s (dyktowanie do Slacka, spotkanie → transkrypt z mówcami → notatka), sekcja „Co się pobiera i ile waży”, sekcja „Feedback”. To samo w opisie i topicach repo.
3. **Strona**: zdjąć `noindex` (flaga `SITE_LIVE`), poprawić link do pobrania z `mjozefiak/Pounce` na `mjozefiak/lintel`, usunąć stare `docs/index.html` + `pages.yml`.
4. **Drogi feedbacku**:
   - włączyć GitHub Discussions (kategorie: Announcements, Q&A, Ideas, Beta testers, Show and tell); przypiąć „Start here — przedstaw się (Mac, jak dyktujesz, jaki komunikator)” i „Co Lintel ma robić dalej?”;
   - `config.yml`: `blank_issues_enabled: false`, `contact_links` do Q&A, Ideas i „Porozmawiaj z autorem (15 min)”;
   - w aplikacji menu Pomoc: „Zgłoś błąd…”, „Zaproponuj funkcję…”, „Dyskusje”, „Porozmawiaj z autorem” — URL-e wypełniają tylko wersję, macOS, chip i włączone funkcje, nigdy treści użytkownika (mały spec + PR);
   - darmowy link do kalendarza (Cal.com free / Google Calendar appointment) na 15 min.
5. **Test na czystym Macu 8/16 GB**: instalacja z DMG, dyktowanie i jedno spotkanie od początku do końca; spisać uczciwe wymagania.
6. **Własny tap Homebrew** (`brew install --cask mjozefiak/tap/lintel`); główne repo Homebrew wymaga 225 gwiazdek przy zgłoszeniu przez autora — później.
7. **Konta**: zacząć normalnie komentować na r/macapps i r/LocalLLaMA (bez linków) — karma i historia przed postem. Profil na X/Bluesky/LinkedIn z linkiem do repo.
8. Lista **20–30 osób z własnej sieci** (dev, founderzy, managerowie z dużą liczbą spotkań, osoby z RSI/ADHD), którym napiszesz osobiście w tygodniu 1.

## Tydzień 1 (1–7.12): cichy start, Polska i własna sieć

Polska pierwsza: najbardziej wyrozumiali testerzy i jedyny rynek, gdzie „po polsku” jest unikalne.

- **Osobisty onboarding (kopia Wispra w małej skali):** wiadomości do 20–30 osób, cel 10 instalacji na 15-minutowym callu. Prośba: „używaj tydzień, zgłoś wszystko, co boli, w Issues lub mi napisz”.
- **LinkedIn PL** (pon./wt.): post osobisty z natywnym wideo notatek ze spotkania po polsku, link w pierwszym komentarzu.
- **Wykop Mikroblog** (#programowanie #apple #macos #opensource): „zrobiłem po godzinach”, GIF, prośba o feedback.
- **Katalogi (jednorazowo, ~2 h):** PR-y do awesome-mac (jaywcjlove), open-source-mac-os-apps (serhii-londar), awesome-mac-open-source; wpisy w AlternativeTo i openalternative.co jako alternatywa dla Wispr Flow, Granola, Superwhisper, Raycast, Maccy.
- **r/macapps** (śr./czw.): post „I built…” z GIF-em, ujawnienie autorstwa, znane ograniczenia, prośba o issues. Limit: 1 post na 30 dni.
- **r/selfhosted**: tylko cotygodniowy megathread nowych projektów.
- Pod koniec tygodnia **beta.2** z poprawkami od pierwszych userów i sekcją „Dzięki @…”.

## Tydzień 2 (8–14.12): Show HN i technika

- **Show HN w nocy z niedzieli 13.12 na poniedziałek 14.12, ok. 23:00–01:00 UTC** (00:00–02:00 w Polsce). Tytuł:
  *„Show HN: Lintel – free, open-source Wispr Flow and Granola alternative for macOS”*.
  Link prosto do repo. Pierwszy komentarz: dlaczego, stack (Parakeet/WhisperKit, llama.cpp, SQLCipher), uczciwe ograniczenia, o jaki feedback prosisz. Zarezerwuj 3–4 h na odpowiedzi. Nigdy nie proś o głosy.
- **r/LocalLLaMA** (2–3 dni później): post techniczny — Parakeet vs WhisperKit, prompt do czyszczenia tekstu, zużycie pamięci, liczby z własnego Maca. Inny tekst niż na r/macapps.
- **Polskie media:** krótki mail do iMagazine i Spider's Web („polski deweloper, darmowa aplikacja, polski język, dane zostają na Macu”) oraz zgłoszenie do unknowNews.

## Tydzień 3 (15–21.12): domknięcie i content

- **DevHunt**.
- **LinkedIn EN**: wideo notatek ze spotkania, „no bot joins your call”.
- **10 osobistych maili do małych i średnich kanałów YouTube**, które robiły filmy „free Mac apps” / „Wispr Flow alternatives”. Do tego **TidBITS** (temat maila zaczyna się od „PITCH”). Potrzebne: demo 60 s, press kit (ikona, zrzuty, akapit).
- **Artykuł nr 1 na dev.to** (wzór Meetily): „A free, local alternative to Wispr Flow on macOS — how it works”.
- **beta.3** z sekcją podziękowań.

## Tydzień 4 (22–31.12): święta — bez launchy

24–26.12 to martwy czas, więc nie startujemy niczego nowego.

- Odpowiadać na issues i dyskusje.
- Zebrać cytaty do „wall of love”.
- Zaktualizować publiczną roadmapę (GitHub Project: Now / Next / Later / Ideas).
- Retro miesiąca i przygotowanie na styczeń: **Product Hunt** (z galerią, wideo, cytatami userów i, jeśli się uda, znanym hunterem), Console.dev, Changelog, artykuł nr 2.

## Rytm codzienny (cały miesiąc)

- Na każde issue i dyskusję **odpowiedź w ciągu 24 h**, z konkretnym następnym krokiem. Badania łączą jakość pierwszej odpowiedzi z tym, czy człowiek wraca.
- 20–30 min dziennie na X/Bluesky/Mastodon: krótkie nagrania ekranu, odpowiedzi w wątkach o Wispr Flow i lokalnym AI. Własny timeline przy 0 obserwujących nie daje zasięgu.
- Release co 1–2 tygodnie z „Dzięki @…” w notatkach. Nigdy nie wgrywać DMG ponownie do tego samego release'u (zeruje licznik pobrań).

## Czego nie robić

- r/opensource i r/MacOS: ich zasady wykluczają Lintela (projekty z AI; aplikacje spoza App Store).
- Ten sam tekst wklejany w wiele subów; prośby o głosy.
- Discord na start (pusty wygląda na martwy, a rozmowy nie są indeksowane). Dopiero gdy ludzie poproszą.
- Reklamy, afiliacja, gamifikowana lista oczekujących: nie ma tu czego dawać, a kosztują.

## Pomiar bez analityki

Codzienna GitHub Action zapisuje do JSON na gałęzi `metrics`: `traffic/views`, `traffic/clones`, `traffic/popular/referrers` (API trzyma tylko 14 dni) i `download_count` DMG. Tygodniowa notatka:

- pobrania DMG,
- odwiedzający repo i top referrery,
- gwiazdki,
- **issues i dyskusje od osób innych niż autor oraz liczba różnych zgłaszających** (główna miara),
- mediana czasu do pierwszej odpowiedzi,
- odbyte rozmowy.

Propozycja celów na 31.12 (decyzja właściciela, nie wynik researchu): 300 pobrań, 100 gwiazdek, 10 różnych zewnętrznych zgłaszających, 8 rozmów.

## Decyzje dla właściciela

1. Główny nagłówek: „alternatywa dla Wispr Flow **i** Granola” (propozycja) czy tylko jedna z nich?
2. Czy dajesz publiczny link na 15-minutowe rozmowy i ile slotów tygodniowo?
3. Czy posty na Wykopie i LinkedInie idą z Twojego imiennego konta (rekomendacja: tak, „zrobiłem” działa lepiej niż marka)?
4. Czy Show HN 13/14.12 pasuje do kalendarza (3–4 h odpowiedzi w nocy)?
5. Kto robi blokery z tygodnia 0: agenci na PR-ach (appcast, README, menu Pomoc, Discussions, tap Homebrew), czy część ręcznie?
