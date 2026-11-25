# Obraz w trakcie spotkania: jak działa w Granoli i u konkurencji (2026-11-25)

Research do speca #282 (`2026-11-25-meeting-screenshots-and-templates.md`, pytania Q-1, Q-3, Q-4, Q-9, Q-10). Właściciel zapytał: „Zbadajmy dokładniej, jak te zrzuty działają w Granola, czy inni konkurenci to mają, a jeżeli tak, to jak to tam działa”. Dokument niczego nie implementuje i nie zmienia speca.

**Metoda.** Wyszukiwanie i czytanie stron 2026-11-25 (dokumentacja, changelogi, blogi producentów, mirrory Message Center Microsoftu, recenzje, Product Hunt, G2). Dla Granoli dodatkowo oględziny zainstalowanej aplikacji (7.821.0) na Macu właściciela: `Info.plist`, teksty interfejsu w `app.asar`, flagi funkcji w `local-state.json` i wyłącznie **metadane** (wymiary, czas, adres) obrazów w pamięci podręcznej. Żadnego obrazu nie otwierano i nie cytuje się treści notatek. Pomiary lokalne (OCR, model multimodalny) zrobiono na tym Macu na obrazach testowych, nie na danych właściciela.

**Oznaczenia.** **[F]** fakt z oficjalnego źródła (dokumentacja, changelog, blog producenta, wpis pracownika); **[U]** relacja użytkowników, recenzentów lub stron trzecich (także konkurencji); **[L]** ustalenie z lokalnych oględzin aplikacji; **[W]** wniosek autora. Daty stron: data publikacji albo „dost. 2026-11-25”, gdy strona jej nie podaje. Reddit był niedostępny dla narzędzi wyszukiwania, więc opinii użytkowników jest mało; tam, gdzie nic nie znaleziono, jest to napisane.

---

## 1. Najważniejsze

1. **Granola ma dziś dwie drogi obrazu, nie trzy.** (a) Ręczne: zwykły zrzut systemowy wklejony albo przeciągnięty do własnych notatek (JPG/PNG, od 04.11.2024). (b) **Snapshots** (5.10.2026): automatyczne zrzuty **cudzego** udostępnianego ekranu, robione lokalnie z okna aplikacji spotkania (Accessibility + Screen Recording), wysyłane do chmury Granoli, opisywane tekstem przez model i dokładane do notatek. Przycisk zrzutu na żądanie („NubSnap”) i propozycja „dołącz zrzut, który właśnie zrobiłeś” były etapami prototypu, nie są udokumentowaną funkcją. Funkcja z bety „capture shared screens” to właśnie Snapshots, dziś już nie oznaczone jako beta.
2. **Właściciel najpewniej korzysta ze Snapshots [L+W].** 38 obrazów z 25.11 w pamięci Granoli ma rozmiar okna (ok. 1605–1623 × 794–803 px, kilka 2201 × 1089), adresy z identyfikatorem SHA-256 w CloudFront Granoli i pojawiają się seriami; plik `screen-capture-analytics.json.enc` zmienił się 25.11 o 13:16; flaga ręcznego zrzutu `capture_moment` jest wyłączona. To pasuje do automatycznego zrzutu udostępnianego ekranu, a nie do ręcznie wklejonych zrzutów (te miałyby rozmiar ekranu albo zaznaczenia i nie przychodziłyby po kilkanaście w minucie).
3. **Co Granola robi z obrazem [L, potwierdzone częściowo przez F].** Każda klatka idzie z tytułem i opisem spotkania oraz fragmentem transkrypcji do serwera w trybie `evaluate`: model decyduje „zachowaj / pomiń”, rozpoznaje duplikaty (`duplicate_of`) i pisze **opis** (`description`). Zachowane opisy trafiają do promptu notatek jako wiersze `[czas] Screenshot N: opis`. Obrazy leżą w stosie „Images” pod notatką, nie w tekście; są dostępne dla czatu, MCP (`get_meeting_attachment`) i API (`type: "screenshot"`, `captured_at`, `description`). Uczestnicy nie są informowani; Granola tylko przypomina użytkownikowi o zgodzie.
4. **Na rynku obraz ma niewielu.** Zrzuty do notatek mają: Otter (automatycznie co ~10 s + przycisk; bot i od 10.2026 aplikacja desktopowa), Google Meet (automatycznie, slajd ≥ 10 s, do Google Doc), Granola (automatycznie), Shadow (automatycznie, lokalnie), Tactiq (tylko przycisk). Teams intelligent recap wprowadza treść udostępnianego ekranu do podsumowania (chmura, licencja Copilot); zrzuty przy notatkach podaje tylko blog [U], tekst Microsoftu ich nie wymienia. Zoom czyta udostępniany ekran **OCR-em** i używa (w 2025) tylko tytułów slajdów, obrazów nie zapisuje. Fireflies, Fathom, tl;dv, Read.ai, MeetGeek, Avoma, Krisp i Bluedot nagrywają **wideo** bez rozumienia treści. Wispr Flow, Jamie, Notion, Supernormal, Char/Hyprnote i Meetily obrazu nie mają.
5. **Nikt lokalny i prywatny nie zamienia obrazu w tekst do notatek.** Granola, Otter, Google, Microsoft i Zoom robią to w chmurze. Shadow trzyma zrzuty lokalnie, ale do pytań wysyła je do chmury i nie mówi jak. Lokalne OCR (Vision) dla Lintela to wyróżnik, nie standard.
6. **Opinii użytkowników prawie nie ma.** Snapshots ma 7 tygodni i zero niezależnych dyskusji; o slajdach Ottera jest jedna pochwała na G2; o Google Meet są skargi na prywatność (poufne slajdy z cenami w Docu wysłanym wszystkim zaproszonym). Nie da się dziś powiedzieć, jak często ludzie z tego korzystają.

---

## 2. Granola (szczegółowo)

### 2.1 Trzy ścieżki opisane publicznie (dwie do notatek, jedna w czacie)

| Ścieżka | Wyzwalacz | Od kiedy | Źródło |
|---|---|---|---|
| A. Obraz wklejony/przeciągnięty do prywatnych notatek | użytkownik (zrzut systemowy, potem ⌘V) | 04.11.2024 | [F] https://granola.ai/updates ; https://docs.granola.ai/help-center/taking-notes/taking-notes-in-granola#adding-images (dost. 2026-11-25) |
| B. **Snapshots**: zrzuty cudzego udostępnianego ekranu | automatycznie po włączeniu w Ustawieniach | 05.10.2026 | [F] https://docs.granola.ai/help-center/taking-notes/capture-shared-screens (dost. 2026-11-25); https://x.com/meetgranola/status/2107171596615946464 |
| C. Pliki i obrazy w czacie Granoli | przycisk załącznika | 05.06.2025 | [F] https://granola.ai/updates |

- [F] „To add your own screenshot, take one with your computer as usual and paste it into your note.” Własny ekran tylko ręcznie (strona Snapshots, wyżej).
- [U] Zdanie „nie osadzamy obrazu w tekście, ale AI widzi go jako kontekst” pochodzi ze starej strony `granola.ai/docs/docs/101/duringyourmeeting/note-taking-tools`, która dziś przekierowuje (308) do nowego help center; na żywej stronie go nie ma. Nie zweryfikowano.

### 2.2 Historia Snapshots (blog inżyniera, 06.10.2026)

[F] https://www.granola.ai/blog/some-ideas-take-a-few-fridays
- styczeń: „NubSnap”, przycisk zrzutu w pływającym okienku („Nub”), czyli **zrzut na żądanie**;
- marzec: wykrycie zrzutu zrobionego przez użytkownika i propozycja dołączenia (klawisz G);
- lipiec: automatyczne zapisywanie udostępnianego ekranu Google Meet przez rozszerzenie Chrome;
- wrzesień: automatyczne wykrywanie w aplikacji Mac (Meet, Zoom, Teams) przez Accessibility.
- Powód zmiany kierunku, wpis członka zespołu: „but you still had to remember to take the screenshot … you're not really being present” (https://x.com/mehedih_/status/2107175901553385657, 10.2026, tekst z wyszukiwarki). Najlepsza opinia testerów wewnętrznych: „I didn't have to think about it, and the images were waiting in my note.”
- [L] W aplikacji 7.821.0 kod przycisku w okienku nadal istnieje (`takeScreenshot`, `screenshotEnabled`, `capturingScreenshot`), ale flaga `capture_moment` jest u właściciela wyłączona. [W] Zrzut na żądanie jest ukryty albo wycofany, nie jest funkcją produktu.

### 2.3 Jak działa Snapshots

**Wyzwalanie i zakres** [F, strona Snapshots]
- Tylko ekran udostępniany przez **kogoś innego**, nigdy własny. Granola zrzuca „the shared window or content, not your whole desktop”; jeśli prowadzący udostępnia cały pulpit, na zrzut trafia wszystko, co pokazuje.
- Zrzuty wstrzymują się, gdy okno spotkania jest niewidoczne („Paused screen capture”). Wyłącznik „Turn off for this meeting” przy notatce i przy wskaźniku spotkania.
- Gdy funkcja jest wyłączona, przy cudzym udostępnianiu Granola może zaproponować „Auto-capture shared screen” (najwyżej raz dziennie przez trzy dni). [L] W aplikacji: „Want to automatically capture shared screen context?” i „Clear screen capture offer history”.
- macOS 14+: Accessibility wymagane („the switch stays off until this is granted”), Screen Recording na prośbę systemu, bez ponownego uruchamiania. Windows 11+: bez uprawnień. Obsługiwane: Zoom (aplikacja), Meet w Chrome, Teams (aplikacja i przeglądarki Chromium); nie: Safari, Firefox, Zoom w przeglądarce. Wskazówka: „If snapshots don't appear in Zoom, try Gallery view.”
- [L] `Info.plist` Granoli opisuje Screen Recording tylko jako „uses screen capture to transcribe system audio”, choć to samo uprawnienie służy do Snapshots. Moduły natywne: `screen_capture.node`, `ax_meeting_detector.node`, `accessibility_tree.node`, `tcc.node`.
- [L] Osobne pływające okno „Screen capture notice” ze stanami `capture-notice`, `capture-starting`, `capturing`, `capture-paused`; teksty „Snapshot starts once access is allowed”, „Hide screenshotting notice”.
- Częstotliwość i sposób usuwania duplikatów: w dokumentacji **nie znaleziono**; zob. niżej, co widać w aplikacji.

**Co dzieje się z obrazem**
- [F] „Granola takes them for you, attaches them to your note and uses them to improve your meeting notes.” „Snapshots are uploaded to Granola so they can be synced to your note.”
- [F] UI: stos **Images** na dole notatki, nad czatem; w trakcie napis „Capturing”; miniatury, pełny rozmiar po kliknięciu, usuwanie (najechanie + x); panel „Taking snapshots” przy wskaźniku spotkania. Brak obrazów w treści notatki i przy czasie.
- [F] API, changelog 11.2026 (v1.7.0): `attachments` z `type: "screenshot"`, `captured_at`, `description` (https://docs.granola.ai/api-reference/changelog przez https://docs.granola.ai/llms-full.txt, dost. 2026-11-25). MCP: `get_meeting_attachment` („What was on the pricing slide in today's review?”). Strona konektora Claude: „Claude can also see the slides, charts and designs shared in your meetings” (https://claude.com/connectors/granola, dost. 2026-11-25).
- [F] Ustawienia przestrzeni roboczej: `screen_share_context_enabled` i osobno `public_api_screenshots_enabled` („Whether API keys may retrieve shared-screen screenshots from this workspace”).
- [L] Przebieg w kodzie klienta (teksty z `app.asar`, bez treści użytkownika):
  - każda klatka jest wysyłana z `meeting_title`, `meeting_description` i kontekstem transkrypcji w trybie `evaluate`; odpowiedź ma pola `keep`, `reason`, `decision` (`new` / duplikat), `duplicate_of`, `description`, `model`;
  - walidacja: „Kept screenshots require a description; skipped screenshots must have none”;
  - opisy zachowanych zrzutów są składane do kontekstu jako `[captured_at] Screenshot ${n}: ${description}`;
  - pierwsza klatka po włączeniu może ominąć ocenę („Relevancy check bypassed”);
  - limit rozmiaru („Screen capture image exceeds the size limit”), obraz złożony z kafelków (`tiles`, `composite_data_url`).
  - [W] Czyli: lokalny zrzut okna co jakiś czas → model w chmurze odrzuca nieistotne klatki i duplikaty i pisze opis → **tekst opisu**, nie piksele, zasila notatki; obraz zostaje załącznikiem.
- [F] Przetwarzanie tylko w chmurze: Granola nie ma modelu na urządzeniu; notatki piszą modele dostawców (OpenAI, Anthropic, Google) (https://docs.granola.ai/llms-full.txt).

**Prywatność**
- [F] Obrazy w chmurze Granoli (AWS, USA). Brak osobnej retencji zrzutów (auto-usuwanie dotyczy tylko transkrypcji). Redakcja danych osobowych obejmuje tylko transkrypcje: „Notes you type and attachments are not redacted.” (https://docs.granola.ai/llms-full.txt)
- [F] Uczestnicy nie są powiadamiani przez samą funkcję. Granola pisze do użytkownika: „Always get consent when taking snapshots of shared screens. Recording and screen capture laws vary.” W Enterprise funkcja jest wyłączona, dopóki administrator jej nie włączy.
- [U] Obrazy jako PNG pod adresem z identyfikatorem treści w CloudFront, według zgłaszającego dostępne bez uwierzytelnienia (GitHub, 06.10.2026: https://github.com/elsehow/BigBrain/issues/133). Nie weryfikowano dostępu.

**Opinie użytkowników.** Nie znaleziono wątków na Reddit, HN, Product Hunt ani w App Store o Snapshots. Digg agregujący premierę: „No comments yet” (https://digg.com/ai/uo478av4, dost. 2026-11-25). Jedyne zgłoszenie: problem z pobraniem obrazów przez MCP (issue wyżej).

---

## 3. Pozostałe produkty

### Wispr Flow (Notetaker od 05.08.2026)
- [F] Brak przechwytywania obrazu: notetaker nagrywa mikrofon i dźwięk systemu („It hears only audio available to your computer”, https://docs.wisprflow.ai/articles/4497184932-notetaker-privacy-and-security-overview, dost. 2026-11-25). Screen Recording służy tylko do dźwięku systemu na macOS 13–14.3. Jedyne ustawienie ekranowe działa odwrotnie: ukrywa okna Wispr przed udostępnianiem ekranu (https://docs.wisprflow.ai/articles/9319084321-notetaker-settings-explained-beta).
- [F] Scratchpad przyjmuje wklejone obrazy (do 10 na notatkę, 5 MB), widoczne w „My thoughts” spotkania na iPhonie (https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes). Nie znaleziono dowodu, że podsumowanie je czyta.
- [U] Na r/WisprFlow: podsumowania „are not as good as granola”; nikt nie prosi o zrzuty slajdów (cytaty za https://tldv.io/blog/wispr-flow-notetaker-review/, 25.09.2026).

### Otter.ai
- [F] Automatyczne zrzuty slajdów i udostępnianego ekranu przez bota (Zoom, Meet, Teams), sprawdzanie co ~10 s, tylko „unique slides”; ręczny przycisk z ikoną obrazu (https://help.otter.ai/hc/en-us/articles/5093321813911-Automated-Slide-Capture-Overview, utw. 2022-03-29, akt. 2026-04-24). Od 2023 na wszystkich planach (https://otter.ai/blog/otter-surpasses-1-billion-meetings-transcribed-and-launches-otterpilot-tm-the-smart-ai-meeting-assistant-to-eliminate-note-taking-and-automate-meeting-summaries, 14.02.2023).
- [F] Aplikacja desktopowa bez bota: automatyczne zrzuty udostępnianej treści w Zoom i Teams, „Otter processes these screenshots to identify relevant content and determines which images should be added”; przycisk aparatu po najechaniu na udostępnianą treść; domyślnie włączone poza Enterprise (https://help.otter.ai/hc/en-us/articles/44255228081559-Desktop-Automatic-Screenshots, utw. 2026-10-14).
- [F] Obrazy w transkrypcji w chwili zrzutu, przeglądarka wszystkich obrazów, pobieranie, usuwanie. AI Chat w trybie Advanced odpowiada na pytania o obrazy (tylko web, jedno spotkanie, trzeba użyć słów „slides”/„screenshots”) (https://help.otter.ai/hc/en-us/articles/33060176539671-Image-Enriched-Conversation-AI-Chat, utw. 2025-06-25). [W] Brak dowodu, że treść slajdów idzie do zwykłego podsumowania.
- [F] Chmura; automatyczne udostępnianie rozmowy (z obrazami) wszystkim zaproszonym jest opcją. [U] Pozew zbiorowy (N.D. Cal., 2025) zarzuca m.in., że e-maile z transkrypcją i zrzutami trafiają do zaproszonych, którzy nie byli na spotkaniu (streszczenie konkurenta: https://tldv.io/blog/ai-meeting-recorder-lawsuits/, 06.05.2026).
- [U] G2: „automatically captures high-resolution screenshots of slides … aligns them with the timestamped transcript” (https://www.g2.com/products/otter-ai/reviews, dost. 2026-11-25). Skarg na zrzuty nie znaleziono.

### Fireflies, Fathom, tl;dv, Read.ai, MeetGeek, Avoma (wideo bez rozumienia obrazu)
- [F] Fireflies: „Capture meeting video” przez bota, 720p (Pro/Business), 1080p (Enterprise); nie przez rozszerzenie Chrome (https://guide.fireflies.ai/articles/1980499609, dost. 2026-11-25).
- [F] Fathom: wideo przez bota; wideo bez bota w becie na Macu (Zoom; Meet z rozszerzeniem), uprawnienia mikrofon, Accessibility, „screen & system audio” (https://help.fathom.video/en/articles/11577345, https://www.fathom.ai/features/bot-free-capture, dost. 2026-11-25).
- [F] tl;dv: tryb bez bota „captures audio only. It does not record: video, screen sharing” (https://intercom.help/tldv/en/articles/14433337-recording-without-a-bot, dost. 2026-11-25); wideo przez bota.
- [F] Read.ai: wideo i odtwarzanie tylko Enterprise/Enterprise+ (https://www.read.ai/plans-pricing, dost. 2026-11-25).
- [F] MeetGeek: wideo i nagrywanie udostępnianego ekranu od planu Pro (https://intercom.help/meetgeekai/en/articles/8021140-discover-post-meeting-features). [U] Prośba o wyłączanie wideo per spotkanie (https://meetgeek.featurebase.app/p/turn-off-video-and-shared-screen-recording-on-a-per).
- [F] Avoma: bot nagrywa dźwięk i wideo z udostępnianiem; klipy 30–90 s (https://help.avoma.com/how-avoma-joins-and-records-your-meetings, https://help.avoma.com/snippets).
- Dla wszystkich: zrzutów, wyciągania slajdów, OCR i czytania ekranu przez AI **nie znaleziono**. [U] Recenzent przeszedł z Fireflies na tl;dv, bo często musi wracać do udostępnianego ekranu (https://efficient.app/apps/fireflies).

### Supernormal
- [F] Wycofał nagrywanie wideo i dźwięku (02.03.2026) oraz bota i rozszerzenie (02.04.2026); dziś tylko aplikacja desktopowa bez obrazu (https://help.supernormal.com/en/articles/13890833-how-and-why-has-supernormal-changed-this-past-year, akt. 2026-04-17).

### Zoom (AI Companion, od 2026 „Meeting Summary with AI”)
- [F, przez dokumentację uczelni] Ustawienie „Use screen share content with OCR”: OCR treści udostępnianego ekranu na serwerach Zoom, do podsumowania (https://ithelp.brown.edu/kb/articles/zoom-ai-companion, dost. 2026-11-25).
- [F, pracownik Zoom, 03.2025] „OCR only works for slides sharing. There is a machine learning model to classify the screen shared image”; podsumowanie używa „only slide titles” (wątek Zoom Community, cytat z wyszukiwarki). Obrazów nie zapisuje. Nowszego stanu nie znaleziono.
- [F] Opcja Zero Data Retention obejmuje „screen shared content via OCR” (https://www.zoom.com/en/lp/zoom-ai-whitepaper).
- [U] Użytkownik uczelni: ważny tekst z ekranu i czatu „not mentioned in the content in the AI Summary” (ten sam wątek, 2025).

### Microsoft Teams (Copilot, intelligent recap)
- Dwie różne pozycje roadmapy:
  - [F, mirror Message Center] **490052 / MC1115314**: „Intelligent meeting recap can incorporate content shared on screen in the AI-based summary … It captures details that are shown when a participant shares their screen”; GA luty 2026, licencja Microsoft 365 Copilot, „available by default with no admin controls”; status „Launched” w mirrorze (https://mc.merill.net/message/RM490052, akt. 13.04.2026; https://www.itelio.com/en/microsoft-message-center/MC1115314, akt. 28.01.2026). Wcześniej podobno raz anulowana (13.08.2025) i przywrócona; przy recenzji nie znaleziono tego w historii żadnego z mirrorów (nie zweryfikowano).
  - [U] Blog: „The captured screenshot will be shown alongside the relevant meeting notes” (https://supersimple365.com/intelligent-recap-in-teams-to-include-supporting-screenshots/, 29.07.2025, akt. 29.01.2026). Tekst Microsoftu w mirrorach nie wspomina zrzutów.
  - [F, mirror] **325873** „Copilot in Teams can analyze content shared on-screen” (pytania do Copilota w trakcie spotkania, wymagało nagrywania): zapowiedź Ignite 2024, **anulowana 16–17.07.2026** („We have decided not to move forward with this change at this time”) (https://app.cloudscout.one/evergreen-item/325873/).
- [W] Microsoft wprowadził obraz do podsumowania (chmura, licencja Copilot), a wycofał się z rozmowy z Copilotem o ekranie na żywo.

### Google Meet (Gemini „Take notes for me”)
- [F] Automatyczne zrzuty prezentowanej treści (slajdy, wykresy, diagramy) do Google Doc z notatkami, gdy prezentacja jest na ekranie ≥ 10 s; domyślnie włączone; prezentujący widzi baner „Gemini may improve your notes with screenshots” i może wyłączyć; administrator: „zawsze” albo „tylko przy nagrywaniu” (https://support.google.com/meet/answer/14754931, dost. 2026-11-25; https://workspaceupdates.googleblog.com/2026/07/visual-screenshots-in-google-meet-meeting-notes-will-soon-be-generally-available-pre-configure-admin-settings-in-advance.html, 27.07.2026; https://workspaceupdates.googleblog.com/2026/08/visual-screenshots-now-included-in-Google-Meet-meeting-notes.html, 03.08.2026). Plany Business/Enterprise Standard/Plus i edukacyjne.
- Czy Gemini czyta obrazy do podsumowania: **nie znaleziono**; Google pisze tylko, że są „included”. Zrzutu na żądanie brak.
- [U] Skargi na prywatność: slajdy z ofertą cenową jako obrazy w Docu wysłanym wszystkim zaproszonym (https://gleamhub.net/en/media/0671-google-meet-meeting-notes-visual-screenshots-admin-default/, 05.08.2026); „a notice is not the same as informed approval” (https://openveil.app/blog/google-meet-ai-screenshots-slides-privacy, 28.07.2026); w rekrutacji zrzut edytora kandydata trafia do notatek (https://interviewersignal.com/blog/gemini-in-google-meet-for-interviews, 21.10.2026).

### Notion AI Meeting Notes
- [F] Tylko dźwięk; dla etykiet mówców w Zoom używa Accessibility i „doesn't record the screen” (https://www.notion.com/help/set-up-ai-meeting-notes-for-google-meet-and-zoom, dost. 2026-11-25). Obrazu brak.

### Tactiq (rozszerzenie Chrome)
- [F] Przycisk aparatu w widżecie, zrzut „instantly added to your meeting transcript”; usuwanie tylko w trakcie spotkania (https://help.tactiq.io/en/articles/5858522-how-to-capture-and-share-screenshots-during-meetings, 14.10.2025). OCR ani AI na obrazach: nie znaleziono. Zakres (karta/okno): nie znaleziono.

### Krisp
- [F] Nagrywanie **wideo** ekranu (cały pulpit albo okno) na żądanie z aplikacji/widżetu, pauza; Screen Recording przy pierwszym użyciu; plany płatne; wideo w koncie web (https://krisp.ai/blog/introducing-screen-recording-for-meetings/, 10.2024; https://krisp.ai/blog/how-to-screen-record-on-mac/, 10.2025). Użycie w notatkach: nie znaleziono.

### Jamie
- [F] Tylko dźwięk, usuwany po transkrypcji: „Will Jamie also record videos? No.” (https://www.meetjamie.ai/en/blog/in-person-meetings, dost. 2026-11-25). [W] Brak obrazu jest tu cechą prywatności.

### Bluedot
- [F] Wideo z okna Zoom/udostępniania (rozszerzenie i aplikacja); „won't capture information directly from video slides” (https://www.bluedothq.com/tools/ai-video-note-taker, dost. 2026-11-25). Dokumentacja jest sprzeczna co do nagrywania cudzego udostępniania i miejsca przechowywania (chmura vs dysk).

### Shadow (shadow.do, tylko Mac)
- [F] Automatyczne „Smart Screenshots” okna spotkania „whenever something changes”; w zakładce Transcript obok rozmowy; pytania o to, „what was shown”; zrzuty „stored locally”, poza urządzenie tylko przy funkcjach AI (https://www.shadow.do/, dost. 2026-11-25; https://www.producthunt.com/p/shadow-4/shadow-now-remembers-what-s-on-your-screen). OCR czy model obrazowy: nie znaleziono.
- [U] „its ability to capture screenshots as it records and transcribes, providing additional context” (https://www.producthunt.com/products/shadow-4/reviews).

### Pozostałe, krótko
- Rewind/Limitless: przechwytywanie ekranu wyłączone 19.12.2025 po przejęciu przez Metę (https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/).
- Screenpipe: lokalnie, stale: zrzut + drzewo dostępności, OCR awaryjnie (https://screenpi.pe/blog/ai-meeting-assistant-2026).
- Char/Hyprnote, Meetily: tylko dźwięk; zrzutów nie znaleziono.

---

## 4. Tabela porównawcza

| Produkt | Obraz | Wyzwalacz | Zakres / mechanizm | Co dalej z obrazem | Gdzie w UI | Lokalnie / chmura | Uczestnicy informowani |
|---|---|---|---|---|---|---|---|
| **Granola** | zrzuty (Snapshots) + wklejanie | auto; ręcznie tylko zrzut systemowy | okno aplikacji spotkania, tylko cudze udostępnianie; Accessibility + Screen Recording | model w chmurze: zachowaj/pomiń, duplikaty, **opis tekstowy do notatek**; czat, MCP, API | stos „Images” pod notatką | chmura | nie (przypomnienie dla użytkownika) |
| Wispr Flow | brak (wklejanie w Scratchpad) | — | — | — | — | chmura | opcjonalny komunikat w czacie |
| **Otter** | zrzuty slajdów | auto co ~10 s + przycisk | bot; od 10.2026 aplikacja desktopowa (Zoom, Teams) | wybór unikalnych; pytania w AI Chat (Advanced) | w transkrypcji przy czasie | chmura | bot widoczny; opcjonalny e-mail |
| Fireflies / Fathom / tl;dv / Read.ai / MeetGeek / Avoma | wideo | auto (bot); Fathom bez bota w becie | strumień spotkania | odtwarzanie, klipy; brak rozumienia obrazu | odtwarzacz obok transkrypcji | chmura | bot widoczny |
| Supernormal, Jamie, Notion, Char, Meetily | brak | — | — | — | — | — | — |
| **Zoom** | tekst (OCR), bez obrazu | ustawienie | serwer, klasyfikator slajdów | OCR → podsumowanie (2025: tytuły) | — | chmura | komunikat AI Companion |
| **Teams** | podsumowanie udostępnianego ekranu (+ zrzuty wg bloga) | auto, bez ustawień admina | serwer | do recap | przy notatkach (wg bloga) | chmura | nie znaleziono |
| **Google Meet** | zrzuty prezentacji | auto (≥ 10 s) | serwer, strumień prezentacji | wstawione do Doc; czytanie przez Gemini nie potwierdzone | w Google Doc | chmura | baner dla prezentującego |
| Tactiq | zrzuty | tylko przycisk | rozszerzenie Chrome | załącznik | w transkrypcji | chmura | nie |
| Krisp | wideo | przycisk | ekran lub okno, Screen Recording | konto web | osobno | chmura | nie znaleziono |
| Bluedot | wideo | przycisk / auto | okno, karta | AI ignoruje slajdy | odtwarzacz | chmura (sprzeczne) | tryb dyskretny |
| **Shadow** | zrzuty | auto przy zmianie | okno spotkania | wyszukiwanie, pytania (sposób nieznany) | w transkrypcji przy czasie | lokalnie, chmura przy AI | nie znaleziono |

---

## 5. Wzorce obecne na rynku

1. **Automatyczne zrzuty udostępnianego ekranu z wyborem klatek** (Granola, Otter, Google Meet, Shadow). Coś wykrywa udostępnianie, robi klatki co kilka sekund i odrzuca duplikaty (Otter: „unique slides”, Google: ≥ 10 s, Granola: model ocenia trafność i duplikaty, Shadow: zmiana obrazu). Kierunek rynku w 2026: Granola i Otter przeszły z przycisku na automat, bo użytkownik zapomina kliknąć.
2. **Obraz → tekst → notatki** (Granola: opis z modelu; Zoom: OCR tytułów slajdów; Teams: podsumowanie treści ekranu). Do podsumowania trafia tekst, a obraz zostaje załącznikiem. Wszystko w chmurze.
3. **Obraz jako załącznik do przejrzenia i pytań** (Otter: w transkrypcji + AI Chat; Shadow: w transkrypcji + wyszukiwanie; Tactiq: przycisk; Granola: stos „Images” + MCP; Google: w Docu). Dwa sposoby pokazania: przy czasie w transkrypcji (Otter, Shadow, Tactiq) albo w osobnej galerii (Granola).
4. **Wideo zamiast zrzutów** (Fireflies, Fathom, tl;dv, Read.ai, MeetGeek, Avoma, Krisp, Bluedot). Ważne dla demo i odtwarzania, bez rozumienia treści, zwykle w płatnym planie i zwykle tylko z botem. Na drugim biegunie produkty, które świadomie nie biorą obrazu (Jamie: „no video”, Wispr Flow, Notion).

Wspólna luka: nikt nie łączy **lokalnego** przetwarzania obrazu z notatkami. Najczęstsze skargi dotyczą prywatności: automatyczny zrzut łapie poufne slajdy i rozchodzi się z notatką (Google Meet, pozew przeciw Otterowi).

---

## 6. Ryzyka techniczne dla Lintela (macOS 26, Mac)

Pomiary [L] zrobiono na MacBooku Pro M4 Max 128 GB z **macOS 27.0.1**, na syntetycznym slajdzie 1920×1080 z gęstymi polskimi znakami; na macOS 26 i na słabszych Macach trzeba je powtórzyć (faza Z0 speca).

**Uprawnienie Screen Recording (największy koszt UX).**
- [L] Lintel łapie dziś dźwięk systemu przez Core Audio process taps (`CoreAudioProcessTapBackend.swift`, `NSAudioCaptureUsageDescription`), **bez** ScreenCaptureKit. Zrzuty dodają więc zupełnie nowe uprawnienie TCC, którego użytkownik dziś nie widzi.
- [F] Przykład Apple dla ScreenCaptureKit: „After you grant permission, you need to restart the app to enable capture” (https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos, dost. 2026-11-25). [U] `CGPreflightScreenCaptureAccess()` zwraca `false` do ponownego uruchomienia; podpis ad hoc gubi zgodę przy każdym buildzie (https://developer.apple.com/forums/thread/819406). Granola twierdzi, że restart nie jest potrzebny.
- [F] Od macOS 15 system okresowo pyta ponownie: „X is requesting to bypass the system private window picker and directly access your screen and audio” z „Allow For One Month”; DTS odtworzył to dla zwykłego `SCScreenshotManager.captureImage` (https://developer.apple.com/forums/thread/765103, 2024). Tydzień zmieniono na miesiąc w becie 15 (https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/). Czy na 26 nadal tak jest: **nie znaleziono** źródła 2025–2026 ani za, ani przeciw. Uprawnienie „Persistent Content Capture” jest dla aplikacji VNC, nie dla Lintela.
- [F] Fioletowy wskaźnik nagrywania przy Centrum sterowania w trakcie przechwytywania; nie da się go wyłączyć.
- [F] Apple zaleca systemowy wybór treści `SCContentSharingPicker` (macOS 14+). Czy zwalnia ze zgody TCC i z comiesięcznego pytania: [U] sprzeczne relacje (https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/, 2023), **nie zweryfikowano na 26**. Koszt: jedno kliknięcie wyboru okna na spotkanie.
- [W] Ścieżki bez żadnej zgody: wklejenie/przeciągnięcie obrazu (A2 w specu). Wykrywanie zrzutu systemowego (A3) wymaga czytania folderu zrzutów (zwykle Biurko, chronione TCC).

**OCR na Macu (Vision).**
- [F] `RecognizeDocumentsRequest` (WWDC25, sesja 272) zwraca strukturę dokumentu (tekst, tabele, listy).
- [L] Lista języków na 27.0.1: `VNRecognizeTextRequest` rewizja 3 w trybie dokładnym, `RecognizeTextRequest` i `RecognizeDocumentsRequest` mają **`pl-PL`** (33 języki). Tryb szybki i rewizja 2 polskiego nie mają. WWDC25 mówiło o 26 językach na macOS 26, więc obecność `pl` na 26.0 trzeba sprawdzić (rewizja 3 miała polski wcześniej, więc to prawdopodobne [W]).
- [L] Szybkość i jakość: tryb dokładny `pl-PL` ok. **70 ms** na slajd po rozgrzaniu, 1 błąd („Źródło” → „Żródło” w stopce 20 pt); `RecognizeDocumentsRequest` ok. 77 ms, 2 błędy. Pierwsze wywołanie w nowym procesie trwało raz 28,9 s (ładowanie modelu), więc model trzeba rozgrzać przy starcie nagrywania. Tryb szybki gubi polskie znaki („Zwiokszyc”), nie nadaje się.
- [W] Prawdziwe zrzuty z Zooma/Meet (kompresja wideo, małe czcionki) wypadną gorzej; trzeba zmierzyć na nagraniach z `~/Screens/Meetings`.

**Model multimodalny na Macu.**
- [L] Framework `llama` b11600, który Lintel już osadza, ma `mtmd.h` i 261 symboli `mtmd_*`: obraz przez libmtmd nie wymaga nowej zależności, tylko pliku `mmproj` na model i powiązań w Swift.
- [L] Odczyt tego samego slajdu (llama.cpp z Homebrew, Metal, M4 Max): Gemma 3 4B Q4_K_M (3,1 GB razem z mmproj) kodowanie obrazu **0,64 s**; Qwen2.5-VL 3B (2,6 GB) **2,3 s**; Qwen2.5-VL 7B (5,2 GB) **2,1 s**. Wszystkie trzy poprawnie przepisały polski tytuł i budżet „1 250 000 zł netto”. Czas na M1/M2: **nie zmierzono**; [U] artykuł podaje 1,5–4 s kodowania na Apple silicon bez nazwy układu (https://arxiv.org/html/2601.19139v1).
- [W] Koszt dla Lintela: kolejne 2,6–5 GB do pobrania i pamięci, a `LLMLease` trzyma jeden model naraz, więc model obrazowy konkurowałby z modelem notatek (Qwen3) o to samo miejsce. Zysk względem OCR: wykresy, diagramy i układ, nie zwykły tekst slajdu.
- [F] Apple Foundation Models: na macOS 26 obrazów nie przyjmuje („Foundation Models does not currently support images as input”, https://developer.apple.com/forums/thread/811714, 01.2026); obsługa obrazów (`Attachment`, `OCRTool`) przychodzi z cyklem OS 27 (WWDC26, sesja 241: https://developer.apple.com/videos/play/wwdc2026/241/). Kontekst 8192 tokenów wystarcza na opis pojedynczego obrazu, nie na całe spotkanie.

**Obraz do Claude.**
- [F] CLI przyjmuje bloki obrazu przez `--input-format stream-json` (https://code.claude.com/docs/en/cli-reference, https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode, dost. 2026-11-25). Koszt obrazu: `⌈w/28⌉ × ⌈h/28⌉` tokenów, limit 4784 (modele wysokiej rozdzielczości) albo 1568; na modelach wysokiej rozdzielczości (Claude 4.7 i nowsze) 1920×1080 = 2691 tokenów, 2560×1440 = 4784; na standardowych 1920×1080 jest zmniejszane do 1560 tokenów (https://platform.claude.com/docs/en/build-with-claude/vision). [W] Przy 4 $/M tokenów wejścia (Opus 5.5 według tej strony) to ok. 0,011 $ za zrzut 1080p, ok. 0,33 $ za 30 slajdów.
- [L] Próba z CLI 2.1.332 (Haiku, jeden slajd 960 px) zadziałała, ale bez izolacji wczytała kontekst Claude Code hosta: 131 630 tokenów i 0,13 $ za jedno pytanie. Integracja musi być w pełni izolowana (jak dziś dostawca notatek z `--tools ""`), co trzeba sprawdzić testem izolacji.

**Prawo i prywatność.**
- [F] Obraz rozpoznawalnej osoby to dane osobowe (RODO art. 4 pkt 1); wyjątek do użytku osobistego jest wąski (TSUE C-212/13 *Ryneš*), więc przy spotkaniach służbowych nie obowiązuje [W]. Zdjęcie staje się daną biometryczną dopiero przy technicznej identyfikacji (motyw 51). AI Act art. 5 ust. 1 lit. f zakazuje rozpoznawania emocji w pracy. Art. 81 prawa autorskiego: rozpowszechnianie wizerunku wymaga zgody (eksport/udostępnianie notatki z twarzami).
- [U] Zoom i Teams nie powiadamiają o zrzutach ekranu robionych przez uczestników; lokalny zrzut jest dla innych niewidoczny, tak jak lokalne nagranie dźwięku.
- [W] Wniosek: zrzucać tylko udostępnianą treść, nie siatkę z kamerami; żadnego rozpoznawania twarzy ani nastroju; obraz szyfrowany lokalnie; żadnej automatycznej wysyłki do uczestników (zarzut wobec Ottera, skargi na Google Meet).

---

## 7. Rekomendacja dla Lintela

**Wniosek z rynku [W].** Rynek idzie w stronę automatu (Granola, Otter, Google), bo użytkownik zapomina kliknąć, a wartość leży w **tekście** z obrazu, nie w samym obrazie (Granola dokłada opisy do promptu, Zoom OCR, Teams podsumowanie). Wszyscy robią to w chmurze. Lintel może zrobić to samo lokalnie i tanio, bo OCR Vision kosztuje ok. 70 ms na slajd. Największym kosztem nie jest model, tylko nowe uprawnienie Screen Recording z comiesięcznym pytaniem systemu.

**Propozycja (do decyzji właściciela, odpowiada na Q-1, Q-3, Q-4, Q-9, Q-10 w #282):**

1. **Teraz: wklejanie i przeciąganie obrazu do Moich notatek** (zero zgód; tak robią Granola i Wispr). Bez zmian względem propozycji Q-13.
2. **v1: zrzut okna spotkania na polecenie** (aparat w pastylce po najechaniu, skrót, przycisk w panelu), zgoda Screen Recording pytana dopiero przy pierwszym użyciu, po wyjaśnieniu Lintela. Zakres: samo okno aplikacji spotkania (Q-1 a). To jedyny wariant, w którym pytanie systemu pojawia się wyłącznie u osób, które funkcji chcą.
3. **v1: lokalny OCR każdego zrzutu** (Vision, tryb dokładny, rewizja 3, `pl-PL` + `en-US`). Tekst służy do wyszukiwania i jako **słownik pisowni** nazw dla piszącego notatki (Q-4 b, Q-9 a); liczby ze slajdu nie wchodzą do notatki jako fakty, dopóki strażnik faktów nie dostanie osobnej reguły. Ta zmiana względem propozycji speca (Q-4 a: „nic”) wynika z pomiaru: koszt jest pomijalny, a dane nie opuszczają Maca. Tekst ze zrzutu idzie do Claude tylko po nowej wersji zgody na dostawcę.
4. **Miejsce w UI:** pasek „Zrzuty (n)” pod notatką i znacznik w transkrypcji w chwili zrzutu (wzorzec Otter/Shadow/Tactiq dla transkrypcji, Granola dla paska); notatka Lintela bez obrazów w tekście (zgodnie z OD1). To wariant Q-3 b z dodatkiem znacznika, a nie a: wstawianie w miejscu kursora wymaga skupienia na edytorze w trakcie rozmowy.
5. **Później, jako opcja domyślnie wyłączona: automatyczne zrzuty cudzego udostępnianego ekranu** (wzorzec Granoli): wykrycie udostępniania przez Accessibility, klatka co kilka sekund, duplikaty odrzucane lokalnie (skrót obrazu + różnica tekstu OCR), pauza przy ukrytym oknie, wyłącznik per spotkanie, jednolinijkowy komunikat w pastylce. Warunek: Z0 pokaże, jak często macOS 26 pyta ponownie o zgodę i czy Lintel potrafi znaleźć widok udostępniania w Zoom, Meet (Chrome) i Teams.
6. **Nie teraz: model obrazowy na Macu ani obraz do Claude.** Model obrazowy dokłada 2,6–5 GB, ok. 0,6–2,3 s na klatkę na M4 Max (wolniej na starszych Macach) i konkuruje z modelem notatek w `LLMLease`; daje głównie wykresy i diagramy. Wrócić, gdy właściciel uzna, że wykresy są potrzebne, albo gdy Foundation Models z obrazami (OS 27) będzie dostępne bez pobierania.
7. **Nie robimy:** nagrywania wideo, zrzutów siatki z kamerami, rozpoznawania twarzy, automatycznego udostępniania zrzutów uczestnikom.

**Ryzyka.**
- Uprawnienie Screen Recording: nowy krok, możliwe ponowne uruchomienie aplikacji, comiesięczne pytanie systemu i fioletowy wskaźnik. Dla biurowego użytkownika to wygląda jak „Lintel nagrywa ekran”; treść wyjaśnienia jest kluczowa. Do sprawdzenia `SCContentSharingPicker` jako droga bez TCC (Z0).
- Spotkanie w przeglądarce: zrzut okna Chrome może złapać inne karty, powiadomienia i prywatne dane; stąd „Cofnij” i podgląd.
- Jakość OCR na prawdziwych zrzutach (kompresja wideo, małe czcionki, ź/ż) nieznana; zmierzyć na nagraniach właściciela przed decyzją o roli tekstu w notatkach.
- Tekst ze slajdu to dane, nie polecenia (wstrzyknięcie promptu przez slajd); w wariancie „słownik” ryzyko jest małe.
- RODO i wizerunek: zrzut może zawierać twarze i cudze dane; zakres „samo udostępnianie” i lokalne szyfrowanie ograniczają ryzyko, ale go nie usuwają. Eksport notatki ze zrzutami to rozpowszechnianie.
- Wszystkie pomiary z macOS 27.0.1 na M4 Max; na macOS 26 i M1 trzeba je powtórzyć.

---

## 8. Czego nie wiadomo

- Jak często Granola robi klatki i według jakiego modelu ocenia trafność (serwer, niewidoczne w kliencie).
- Czy użytkownicy faktycznie korzystają ze zrzutów: brak niezależnych danych i dyskusji (Reddit niedostępny w tym researchu).
- Czy Gemini w Meet czyta zrzuty do podsumowania; czy Zoom w 2026 używa więcej niż tytułów slajdów; czy Teams recap pokazuje zrzuty (tylko blog).
- Jak Shadow zamienia obraz w odpowiedzi (OCR czy model obrazowy) i czy wysyła obrazy do chmury.
- Czy 38 obrazów z 25.11 to na pewno Snapshots właściciela (wniosek z metadanych; obrazów nie otwierano, dane Granoli są zaszyfrowane). Wystarczy, że właściciel potwierdzi w Ustawieniach Granoli (Preferences → Features → „Take snapshots of shared screens”).
