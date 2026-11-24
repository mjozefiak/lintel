/* Lintel UX direction sketch (revision 2, 2026-11-24): one direction, "Quiet Native with warmth".
   Query: ?screen=explorer|empty|note|rec|dict|set|onb  &page=general|dictation|meetings|ai|privacy|addons|about|quick
          &step=goal|privacy|access|try|meeting  &theme=light|dark  &lang=en|pl  &tone=warm|neutral  &ts=m|l|xl
          &chrome=0  &tab=notes|mine|transcript  &warn=1  &more=1  &sheet=delete  &q=<settings search>  &ai=claude
          &demo=listening|done  &goal=both|dict|meet  &addon=quick  &audit=1
   All names and data are fictional. */
(function () {
  'use strict';

  const COPY = {
    en: {
      bar: { screen: 'Screen', explorer: 'Notes', empty: 'Empty', note: 'Note', rec: 'Recording', dict: 'Dictionary', set: 'Settings', onb: 'Welcome', theme: 'Theme', light: 'Light', dark: 'Dark', lang: 'Language', tone: 'Tone', warm: 'Warm', neutral: 'Neutral' },
      app: 'Lintel', searchNotes: 'Search notes', record: 'Record Meeting', settings: 'Settings', stop: 'Stop',
      nav: { all: 'All notes', meetings: 'Meetings', dictations: 'Dictations', folders: 'Folders', newFolder: 'New Folder', dictionary: 'Dictionary' },
      folders: [['clients', 'Clients'], ['recruiting', 'Recruiting']],
      setup: { t: 'Finish setting up · 3 of 5', next: 'Hear other people in calls', act: 'Allow', close: 'Hide' },
      groups: ['Today', 'Yesterday', 'Friday'], now: 'Now',
      items: [
        { id: 'nordlys', k: 'meeting', f: 'clients', t: 'Client call: Nordlys Energy', m: 'Meeting · 42 min · 3 tasks', w: '11:30', g: 0 },
        { id: 'sync', k: 'meeting', t: 'Weekly sales sync', m: 'Meeting · 28 min · 4 tasks', work: 'Writing notes…', p: 0.6, w: '9:00', g: 0 },
        { id: 'marta', k: 'dictation', t: 'Email to Marta about the Q4 budget', m: 'Dictation · 118 words', w: '16:10', g: 1 },
        { id: 'interview', k: 'meeting', f: 'recruiting', t: 'Interview: product designer', m: 'Meeting · 35 min · 2 tasks', w: '13:00', g: 1 },
        { id: 'board', k: 'dictation', t: 'Notes for the board update', m: 'Dictation · 240 words', w: '10:15', g: 2 },
        { id: 'fjord', k: 'meeting', f: 'clients', t: 'Kick-off with Fjord Legal', m: 'Meeting · 51 min', fail: 'Notes not written', w: '15:00', g: 2 }
      ],
      newRec: { t: 'Meeting, 24 November, 15:02', m: 'Meeting · 12 min', rec: 'Recording' },
      note: {
        meta: 'Today, 11:30 · 42 min · You, Marek Lis, Ingrid Halvorsen', onMac: 'On this Mac', open: 'Open', copy: 'Copy', back: 'All notes',
        tabs: ['Notes', 'My notes', 'Transcript'],
        sumH: 'Summary', sum: 'Nordlys accepts the price if work starts in January. Ingrid needs the service levels in writing before she signs.',
        decH: 'Decisions', dec: ['Work starts on 12 January.', 'The price stays as quoted, with no discount.'],
        taskH: 'Tasks', tasks: [['You', 'Send the price list to Ingrid', 'by Friday'], ['Marek Lis', 'Write up the service levels', 'by Wednesday'], ['Ingrid Halvorsen', 'Confirm the start date with her board', '']],
        foot: 'Lintel wrote these notes from the recording, on this Mac. Your own notes are under My notes.',
        mineHelp: 'Only you write here. Lintel never changes these notes.',
        mine: ['Ingrid OK with the price if we start in Jan', 'Ask Marek about the wording of the service levels', 'She mentioned a second office in Bergen, follow up in Q1'],
        tr: [['You', 'Thanks for making time, Ingrid. Shall we start with the price?'], ['Ingrid Halvorsen', 'Yes. We can accept it if you can start in January.'], ['Marek Lis', 'January works for us. I’ll send the service levels this week.'], ['Ingrid Halvorsen', 'Good. I need them before I go to the board.']]
      },
      failed: { t: 'Lintel couldn’t write the notes for this meeting.', s: 'The recording and transcript are safe. Try again, or read the transcript.', b: 'Try Again' },
      dictNote: { meta: 'Yesterday, 16:10 · Dictation · pasted into Mail', body: 'Hi Marta, I went through the Q4 numbers and they look good. Can we go over the travel budget on Thursday? I’d like to move two trips to January.' },
      rec: {
        live: 'Recording', hears: 'Lintel hears you and the other people in the call.', pad: 'My notes',
        padPh: 'Type your own notes. Lintel keeps them exactly as you write them.', padLines: ['Fjord wants the contract in Norwegian and English', 'Ask Ola about the deadline'],
        stopWrite: 'Stop and Write Notes', tell: 'Remember to tell people you are recording.',
        warnT: 'Lintel can’t hear the other people in this call.', warnS: 'Allow call audio, or check that the call isn’t muted.', warnB: 'Fix Call Audio'
      },
      empty: { t: 'Your notes will appear here', s: 'Record a meeting and Lintel writes the notes. Or hold ⌥ Space to dictate in any app.', b: 'Try Dictation', noFolders: 'No folders yet' },
      dict: { t: 'Dictionary', s: 'Names and words Lintel always spells your way.', add: 'Add Word', search: 'Search words', remove: 'Remove',
        words: [['Nordlys Energy', 'Added by you'], ['Ingrid Halvorsen', 'Added by you'], ['Fjord Legal', 'Learned from your corrections'], ['Wierzbicki', 'Learned from your corrections'], ['Bergen', 'Added by you']] },
      key: '⌥ Space',
      set: {
        search: 'Search settings', more: 'More options', off: 'Off', on: 'On', offN: (n) => `${n} off`,
        side: { general: 'General', dictation: 'Dictation', meetings: 'Meetings & notes', ai: 'AI assistant', privacy: 'Privacy & data', addons: 'Add-ons', about: 'About & help', quick: 'Quick search', clip: 'Clipboard history', win: 'Window layouts' },
        general: { lang: 'Languages I speak', langVal: 'English, Polish', langHelp: 'Used for dictation and meetings.', change: 'Change…', mic: 'Microphone', micVal: 'Automatic', micHelp: 'Uses your headset when it’s connected.', size: 'Text size', login: 'Open Lintel when I log in', dock: 'Show Lintel in the Dock', early: 'Try new features early', earlyHelp: 'Get test versions before everyone else.' },
        dictation: { status: 'Ready to dictate', statusSub: 'Microphone allowed · English, Polish', shortcut: 'Shortcut', shortcutHelp: 'Hold to talk. Tap twice to keep talking.', tidy: 'Tidy up my text', tidyHelp: 'Removes “um”s and fixes punctuation. Keeps your words.', dict: 'Dictionary', dictVal: '12 words', open: 'Open', kept: 'Dictations are kept for 30 days', keptLink: 'Change in Privacy & data', restore: 'After pasting, put back what I had copied', raw: 'Paste my last dictation unedited', setKey: 'Set Shortcut', foot: 'Your voice is turned into text on this Mac.' },
        meetings: { status: 'Hears only you for now', statusSub: 'Allow call audio so notes include the other people.', allow: 'Allow…', rec: 'Record a meeting', recHelp: 'Starts and stops recording from any app.', setKey: 'Set Shortcut', suggest: 'Suggest recording when a call starts', suggestHelp: 'Zoom, Microsoft Teams, Google Meet and Slack.', name: 'Your name in notes', nameVal: 'Anna Kowalska', writer: 'Notes written by', writerVal: 'This Mac', writerLink: 'Change in AI assistant', exp: 'Export all notes', expBtn: 'Export…', write: 'Write notes after each meeting', never: 'Never suggest recording in', neverVal: 'No apps', addApp: 'Add App…', check: 'Check call audio', checkBtn: 'Check', foot: 'Recordings and notes stay on this Mac.' },
        ai: { statusMac: 'Notes and tidy-up are written on this Mac', statusClaude: 'Meeting notes are written by Claude', q: 'Who writes your notes and tidies your text', mac: 'This Mac', macHelp: 'Private and works offline. Slower on older Macs.', claude: 'Claude (your account)', claudeHelp: 'Better notes on any Mac. Your words are sent to Anthropic.', use: 'Use Claude for', useNotes: 'Meeting notes', useDict: 'Dictation', consent: 'Lintel asks you before the first meeting is sent.', local: 'Assistant on this Mac', localVal: 'Recommended for this Mac', dl: 'Downloaded files', dlVal: '3.7 GB', show: 'Show', remove: 'Remove…', own: 'Use my own AI server', footMac: 'Nothing leaves this Mac unless you choose Claude.', footClaude: 'Recordings stay on this Mac. Only the transcript goes to Claude.' },
        privacy: {
          lead: 'Recordings, notes and dictations stay on this Mac.', leadLink: 'Who writes your notes: AI assistant',
          useH: 'What Lintel can use', allowed: 'Allowed', allow: 'Allow…',
          perms: { mic: ['Microphone', 'To hear you when you dictate or record.'], call: ['Hear other people in a call', 'So notes include what the others say.'], type: ['Type into other apps', 'So your words appear where your cursor is.'] },
          keepH: 'What Lintel keeps', audio: 'Meeting audio', audioVal: 'Delete when notes are ready', dict: 'Dictations', dictVal: '30 days',
          delH: 'Delete', del: 'Delete my data', delHelp: 'Choose what to delete. You see how much first.', delBtn: 'Delete…',
          notes: 'Notes and transcripts', notesVal: 'Keep forever', remind: 'Remind me to tell people I’m recording',
          sheetT: 'Delete my data', sheetS: 'Choose what to delete.', warn: 'This can’t be undone.', cancel: 'Cancel',
          opts: [['dict', 'All dictations', '128 dictations', 'Delete 128 Dictations'], ['meet', 'All meetings and notes', '42 meetings with their notes and audio', 'Delete 42 Meetings'], ['all', 'Everything', 'Dictations, meetings, notes and the Dictionary', 'Delete Everything']]
        },
        addons: { lead: 'Extra tools. All off until you turn them on.', items: { quick: 'Open apps and files from the keyboard.', clip: 'Find anything you copied.', win: 'Arrange windows with a shortcut.' }, onHelp: 'Its page is now in the sidebar.' },
        quick: { status: 'Choose a shortcut to start', shortcut: 'Shortcut', setKey: 'Set Shortcut', files: 'Also search files', folders: 'Folders', foldersVal: 'Home folder', change: 'Change…', order: 'Result order', hidden: 'Show hidden files', skip: 'Skip these folders', over: 'Start over', overBtn: 'Start Over', foot: 'Searches only file names, on this Mac.' },
        clip: { never: 'Never save from these apps', neverVal: '1Password, Keychain Access' },
        win: { gap: 'Space between windows', gapVal: 'Small' },
        about: { status: 'Lintel 1.0 beta 2 · Up to date', check: 'Check Now', auto: 'Update automatically', news: 'What’s new', welcome: 'Show welcome again', show: 'Show', report: 'Send a problem report', reportHelp: 'You see exactly what is sent before anything leaves your Mac.', send: 'Send…', ack: 'Acknowledgements', open: 'Open' },
        results: (q) => `Results for “${q}”`, none: (q) => `No settings match “${q}”.`, noneHelp: 'Try another word, like “microphone” or “delete”.'
      },
      onb: {
        tag: 'Your words, on this Mac.', stepOf: (i, n) => `Step ${i} of ${n}`,
        names: { goal: 'Your goal', privacy: 'Privacy', access: 'Access', try: 'Try dictation', meeting: 'First meeting' },
        back: 'Back', cont: 'Continue', finish: 'Open Lintel',
        goal: { h: 'What would you like Lintel to do?', s: 'You can change this later in Settings.', dict: ['Type what I say', 'Hold a key and talk. Your words appear in any app.'], meet: ['Write my meeting notes', 'Lintel listens to your calls and writes the notes.'], both: ['Both', 'You can turn either one off later.'] },
        privacy: { h: 'Your words stay on this Mac', s: 'This is how Lintel works, from the first day.', pts: ['Recordings, notes and dictations are saved on this Mac, encrypted.', 'Nothing is sent anywhere. Later you can choose Claude to write notes; Lintel asks first.', 'No account and no sign-up.'], consent: 'When you record a meeting, tell the other people. Lintel reminds you.' },
        access: { h: 'Lintel needs your OK for a few things', s: 'macOS asks you to confirm each one.', sys: 'Opens System Settings', skip: 'You can skip any of these and allow them later in Settings → Privacy & data.' },
        try: { h: 'Say something. Lintel will type it.', s: 'Hold ⌥ Space, say a sentence, then let go.', change: 'Change shortcut', to: 'To', subject: 'Subject', toName: 'Marta Nowak', subj: 'Q4 budget', ph: 'Your words appear here.', result: 'Hi Marta, I went through the Q4 numbers and they look good. Can we go over the travel budget on Thursday?', hold: 'Hold to Talk', listening: 'Listening…', letGo: 'Let go when you’re done.', success: 'That’s it. It works the same in Mail, Slack, Word and every other app.', again: 'Try again', skipLine: 'Can’t talk right now? Continue, and try it later from the menu bar.', foot: 'Your voice is turned into text on this Mac.' },
        meeting: { h: 'Your first meeting', s: 'When a call starts in Zoom, Teams or Google Meet, Lintel asks if you want to record it.', cap: 'What you’ll see', bubble: 'Record this call?', rec: 'Record', notNow: 'Not Now', or: 'You can also press Record Meeting in the Lintel window.', check: 'Check call audio', checkHelp: 'Plays a short sound and checks that Lintel hears it.', checkBtn: 'Check', checkOk: 'Lintel hears call audio.', tell: 'Tell people you’re recording. It’s polite, and often required.' }
      }
    },
    pl: {
      bar: { screen: 'Ekran', explorer: 'Notatki', empty: 'Pusto', note: 'Notatka', rec: 'Nagrywanie', dict: 'Słownik', set: 'Ustawienia', onb: 'Powitanie', theme: 'Motyw', light: 'Jasny', dark: 'Ciemny', lang: 'Język', tone: 'Ton', warm: 'Ciepły', neutral: 'Neutralny' },
      app: 'Lintel', searchNotes: 'Szukaj w notatkach', record: 'Nagraj spotkanie', settings: 'Ustawienia', stop: 'Zatrzymaj',
      nav: { all: 'Wszystkie notatki', meetings: 'Spotkania', dictations: 'Dyktowania', folders: 'Foldery', newFolder: 'Nowy folder', dictionary: 'Słownik' },
      folders: [['clients', 'Klienci'], ['recruiting', 'Rekrutacja']],
      setup: { t: 'Dokończ konfigurację · 3 z 5', next: 'Słysz innych w rozmowach', act: 'Zezwól', close: 'Ukryj' },
      groups: ['Dziś', 'Wczoraj', 'Piątek'], now: 'Teraz',
      items: [
        { id: 'nordlys', k: 'meeting', f: 'clients', t: 'Rozmowa z klientem: Nordlys Energy', m: 'Spotkanie · 42 min · 3 zadania', w: '11:30', g: 0 },
        { id: 'sync', k: 'meeting', t: 'Cotygodniowe spotkanie sprzedaży', m: 'Spotkanie · 28 min · 4 zadania', work: 'Piszę notatki…', p: 0.6, w: '9:00', g: 0 },
        { id: 'marta', k: 'dictation', t: 'E-mail do Marty o budżecie na IV kwartał', m: 'Dyktowanie · 118 słów', w: '16:10', g: 1 },
        { id: 'interview', k: 'meeting', f: 'recruiting', t: 'Rozmowa rekrutacyjna: projektant produktu', m: 'Spotkanie · 35 min · 2 zadania', w: '13:00', g: 1 },
        { id: 'board', k: 'dictation', t: 'Notatki do raportu dla zarządu', m: 'Dyktowanie · 240 słów', w: '10:15', g: 2 },
        { id: 'fjord', k: 'meeting', f: 'clients', t: 'Spotkanie otwierające z Fjord Legal', m: 'Spotkanie · 51 min', fail: 'Notatki nienapisane', w: '15:00', g: 2 }
      ],
      newRec: { t: 'Spotkanie, 24 listopada, 15:02', m: 'Spotkanie · 12 min', rec: 'Nagrywanie' },
      note: {
        meta: 'Dziś, 11:30 · 42 min · Ty, Marek Lis, Ingrid Halvorsen', onMac: 'Na tym Macu', open: 'Otwórz', copy: 'Kopiuj', back: 'Wszystkie notatki',
        tabs: ['Notatki', 'Moje notatki', 'Transkrypcja'],
        sumH: 'Podsumowanie', sum: 'Nordlys akceptuje cenę, jeśli prace ruszą w styczniu. Ingrid chce dostać poziomy usług na piśmie, zanim podpisze umowę.',
        decH: 'Ustalenia', dec: ['Prace ruszają 12 stycznia.', 'Cena zostaje bez zmian, bez rabatu.'],
        taskH: 'Zadania', tasks: [['Ty', 'Wyślij cennik do Ingrid', 'do piątku'], ['Marek Lis', 'Opisz poziomy usług', 'do środy'], ['Ingrid Halvorsen', 'Potwierdzi termin startu z zarządem', '']],
        foot: 'Lintel napisał te notatki z nagrania, na tym Macu. Twoje własne notatki są w Moich notatkach.',
        mineHelp: 'Tu piszesz tylko Ty. Lintel nigdy nie zmienia tych notatek.',
        mine: ['Ingrid OK z ceną, jeśli startujemy w styczniu', 'Zapytać Marka o zapis poziomów usług', 'Wspomniała o drugim biurze w Bergen, wrócić w I kw.'],
        tr: [['Ty', 'Dziękuję za czas, Ingrid. Zaczniemy od ceny?'], ['Ingrid Halvorsen', 'Tak. Akceptujemy ją, jeśli zaczniecie w styczniu.'], ['Marek Lis', 'Styczeń nam pasuje. W tym tygodniu wyślę poziomy usług.'], ['Ingrid Halvorsen', 'Dobrze. Potrzebuję ich przed posiedzeniem zarządu.']]
      },
      failed: { t: 'Lintel nie zdołał napisać notatek z tego spotkania.', s: 'Nagranie i transkrypcja są bezpieczne. Spróbuj ponownie albo przeczytaj transkrypcję.', b: 'Spróbuj ponownie' },
      dictNote: { meta: 'Wczoraj, 16:10 · Dyktowanie · wklejone do Maila', body: 'Cześć Marto, liczby za IV kwartał wyglądają dobrze. Czy możemy w czwartek omówić budżet na podróże? Chciałabym przenieść dwa wyjazdy na styczeń.' },
      rec: {
        live: 'Nagrywanie', hears: 'Lintel słyszy Ciebie i pozostałe osoby w rozmowie.', pad: 'Moje notatki',
        padPh: 'Pisz własne notatki. Lintel zachowa je dokładnie tak, jak je napiszesz.', padLines: ['Fjord chce umowę po norwesku i po angielsku', 'Zapytać Olę o termin'],
        stopWrite: 'Zatrzymaj i napisz notatki', tell: 'Pamiętaj, by uprzedzić rozmówców o nagrywaniu.',
        warnT: 'Lintel nie słyszy innych osób w tej rozmowie.', warnS: 'Zezwól na dźwięk rozmowy albo sprawdź, czy rozmowa nie jest wyciszona.', warnB: 'Napraw dźwięk rozmowy'
      },
      empty: { t: 'Tu pojawią się Twoje notatki', s: 'Nagraj spotkanie, a Lintel napisze notatki. Albo przytrzymaj ⌥ Spację, by dyktować w dowolnej aplikacji.', b: 'Wypróbuj dyktowanie', noFolders: 'Nie ma jeszcze folderów' },
      dict: { t: 'Słownik', s: 'Nazwy i słowa, które Lintel zawsze pisze po Twojemu.', add: 'Dodaj słowo', search: 'Szukaj słów', remove: 'Usuń',
        words: [['Nordlys Energy', 'Dodane przez Ciebie'], ['Ingrid Halvorsen', 'Dodane przez Ciebie'], ['Fjord Legal', 'Zapamiętane z Twoich poprawek'], ['Wierzbicki', 'Zapamiętane z Twoich poprawek'], ['Bergen', 'Dodane przez Ciebie']] },
      key: '⌥ Spacja',
      set: {
        search: 'Szukaj w ustawieniach', more: 'Więcej opcji', off: 'Wył.', on: 'Wł.', offN: (n) => `${n} wył.`,
        side: { general: 'Ogólne', dictation: 'Dyktowanie', meetings: 'Spotkania i notatki', ai: 'Asystent AI', privacy: 'Prywatność i dane', addons: 'Dodatki', about: 'Pomoc i informacje', quick: 'Szybkie wyszukiwanie', clip: 'Historia schowka', win: 'Układy okien' },
        general: { lang: 'Języki, w których mówię', langVal: 'angielski, polski', langHelp: 'Do dyktowania i spotkań.', change: 'Zmień…', mic: 'Mikrofon', micVal: 'Automatycznie', micHelp: 'Używa słuchawek, gdy są podłączone.', size: 'Wielkość tekstu', login: 'Otwieraj Lintel po zalogowaniu', dock: 'Pokazuj Lintel w Docku', early: 'Testuj nowości wcześniej', earlyHelp: 'Dostawaj wersje testowe przed innymi.' },
        dictation: { status: 'Gotowe do dyktowania', statusSub: 'Mikrofon dozwolony · angielski, polski', shortcut: 'Skrót', shortcutHelp: 'Przytrzymaj, by mówić. Stuknij dwa razy, by mówić dłużej.', tidy: 'Porządkuj mój tekst', tidyHelp: 'Usuwa „yyy” i poprawia interpunkcję. Zostawia Twoje słowa.', dict: 'Słownik', dictVal: '12 słów', open: 'Otwórz', kept: 'Dyktowania są przechowywane 30 dni', keptLink: 'Zmień w Prywatności i danych', restore: 'Po wklejeniu przywróć to, co było skopiowane', raw: 'Wklej ostatnie dyktowanie bez poprawek', setKey: 'Ustaw skrót', foot: 'Głos zamienia się w tekst na tym Macu.' },
        meetings: { status: 'Na razie słyszy tylko Ciebie', statusSub: 'Zezwól na dźwięk rozmowy, by notatki obejmowały innych.', allow: 'Zezwól…', rec: 'Nagraj spotkanie', recHelp: 'Zaczyna i kończy nagrywanie z każdej aplikacji.', setKey: 'Ustaw skrót', suggest: 'Proponuj nagrywanie, gdy zaczyna się rozmowa', suggestHelp: 'Zoom, Microsoft Teams, Google Meet i Slack.', name: 'Twoje imię w notatkach', nameVal: 'Anna Kowalska', writer: 'Notatki pisze', writerVal: 'Ten Mac', writerLink: 'Zmień w Asystencie AI', exp: 'Eksportuj wszystkie notatki', expBtn: 'Eksportuj…', write: 'Pisz notatki po każdym spotkaniu', never: 'Nigdy nie proponuj nagrywania w', neverVal: 'Brak aplikacji', addApp: 'Dodaj aplikację…', check: 'Sprawdź dźwięk rozmowy', checkBtn: 'Sprawdź', foot: 'Nagrania i notatki zostają na tym Macu.' },
        ai: { statusMac: 'Notatki i porządkowanie tekstu powstają na tym Macu', statusClaude: 'Notatki ze spotkań pisze Claude', q: 'Kto pisze notatki i porządkuje tekst', mac: 'Ten Mac', macHelp: 'Prywatnie i bez internetu. Wolniej na starszych Macach.', claude: 'Claude (Twoje konto)', claudeHelp: 'Lepsze notatki na każdym Macu. Twoje słowa trafiają do Anthropic.', use: 'Używaj Claude do', useNotes: 'Notatki ze spotkań', useDict: 'Dyktowanie', consent: 'Lintel zapyta Cię, zanim wyśle pierwsze spotkanie.', local: 'Asystent na tym Macu', localVal: 'Zalecany dla tego Maca', dl: 'Pobrane pliki', dlVal: '3,7 GB', show: 'Pokaż', remove: 'Usuń…', own: 'Użyj własnego serwera AI', footMac: 'Nic nie opuszcza tego Maca, dopóki nie wybierzesz Claude.', footClaude: 'Nagrania zostają na tym Macu. Do Claude trafia tylko transkrypcja.' },
        privacy: {
          lead: 'Nagrania, notatki i dyktowania zostają na tym Macu.', leadLink: 'Kto pisze notatki: Asystent AI',
          useH: 'Do czego Lintel ma dostęp', allowed: 'Dozwolone', allow: 'Zezwól…',
          perms: { mic: ['Mikrofon', 'Aby słyszeć Cię podczas dyktowania i nagrywania.'], call: ['Słysz innych w rozmowie', 'Aby notatki obejmowały to, co mówią inni.'], type: ['Pisz w innych aplikacjach', 'Aby Twoje słowa pojawiały się tam, gdzie kursor.'] },
          keepH: 'Co Lintel przechowuje', audio: 'Dźwięk spotkań', audioVal: 'Usuń, gdy notatki są gotowe', dict: 'Dyktowania', dictVal: '30 dni',
          delH: 'Usuwanie', del: 'Usuń moje dane', delHelp: 'Wybierz, co usunąć. Najpierw zobaczysz, ile tego jest.', delBtn: 'Usuń…',
          notes: 'Notatki i transkrypcje', notesVal: 'Przechowuj zawsze', remind: 'Przypominaj, by uprzedzać o nagrywaniu',
          sheetT: 'Usuń moje dane', sheetS: 'Wybierz, co usunąć.', warn: 'Tego nie da się cofnąć.', cancel: 'Anuluj',
          opts: [['dict', 'Wszystkie dyktowania', '128 dyktowań', 'Usuń 128 dyktowań'], ['meet', 'Wszystkie spotkania i notatki', '42 spotkania z notatkami i dźwiękiem', 'Usuń 42 spotkania'], ['all', 'Wszystko', 'Dyktowania, spotkania, notatki i Słownik', 'Usuń wszystko']]
        },
        addons: { lead: 'Dodatkowe narzędzia. Wyłączone, dopóki ich nie włączysz.', items: { quick: 'Otwieraj aplikacje i pliki z klawiatury.', clip: 'Znajdź wszystko, co było skopiowane.', win: 'Układaj okna skrótem klawiszowym.' }, onHelp: 'Jego strona jest teraz w pasku bocznym.' },
        quick: { status: 'Wybierz skrót, aby zacząć', shortcut: 'Skrót', setKey: 'Ustaw skrót', files: 'Szukaj też plików', folders: 'Foldery', foldersVal: 'Folder domowy', change: 'Zmień…', order: 'Kolejność wyników', hidden: 'Pokazuj ukryte pliki', skip: 'Pomijaj te foldery', over: 'Zacznij od nowa', overBtn: 'Zacznij od nowa', foot: 'Szuka tylko nazw plików, na tym Macu.' },
        clip: { never: 'Nigdy nie zapisuj z tych aplikacji', neverVal: '1Password, Pęk kluczy' },
        win: { gap: 'Odstęp między oknami', gapVal: 'Mały' },
        about: { status: 'Lintel 1.0 beta 2 · Aktualna wersja', check: 'Sprawdź teraz', auto: 'Aktualizuj automatycznie', news: 'Co nowego', welcome: 'Pokaż powitanie ponownie', show: 'Pokaż', report: 'Zgłoś problem', reportHelp: 'Zobaczysz dokładnie, co zostanie wysłane, zanim cokolwiek opuści Twojego Maca.', send: 'Zgłoś…', ack: 'Licencje i podziękowania', open: 'Otwórz' },
        results: (q) => `Wyniki dla „${q}”`, none: (q) => `Żadne ustawienie nie pasuje do „${q}”.`, noneHelp: 'Spróbuj innego słowa, np. „mikrofon” albo „usuń”.'
      },
      onb: {
        tag: 'Twoje słowa, na tym Macu.', stepOf: (i, n) => `Krok ${i} z ${n}`,
        names: { goal: 'Twój cel', privacy: 'Prywatność', access: 'Dostęp', try: 'Wypróbuj dyktowanie', meeting: 'Pierwsze spotkanie' },
        back: 'Wstecz', cont: 'Dalej', finish: 'Otwórz Lintel',
        goal: { h: 'W czym Lintel ma Ci pomagać?', s: 'Zmienisz to później w Ustawieniach.', dict: ['Pisać to, co mówię', 'Przytrzymaj klawisz i mów. Słowa pojawią się w każdej aplikacji.'], meet: ['Pisać notatki ze spotkań', 'Lintel słucha rozmów i pisze notatki.'], both: ['Jedno i drugie', 'Każde z nich wyłączysz później.'] },
        privacy: { h: 'Twoje słowa zostają na tym Macu', s: 'Tak Lintel działa od pierwszego dnia.', pts: ['Nagrania, notatki i dyktowania są zapisywane na tym Macu, zaszyfrowane.', 'Nic nie jest nigdzie wysyłane. Później możesz wybrać Claude do pisania notatek; Lintel najpierw zapyta.', 'Bez konta i bez rejestracji.'], consent: 'Gdy nagrywasz spotkanie, uprzedź rozmówców. Lintel Ci o tym przypomni.' },
        access: { h: 'Lintel potrzebuje Twojej zgody na kilka rzeczy', s: 'macOS poprosi o potwierdzenie każdej z nich.', sys: 'Otwiera Ustawienia systemowe', skip: 'Każdą z nich możesz pominąć i włączyć później w Ustawieniach → Prywatność i dane.' },
        try: { h: 'Powiedz coś. Lintel to napisze.', s: 'Przytrzymaj ⌥ Spację, powiedz zdanie i puść.', change: 'Zmień skrót', to: 'Do', subject: 'Temat', toName: 'Marta Nowak', subj: 'Budżet na IV kwartał', ph: 'Tu pojawią się Twoje słowa.', result: 'Cześć Marto, liczby za IV kwartał wyglądają dobrze. Czy możemy w czwartek omówić budżet na podróże?', hold: 'Przytrzymaj i mów', listening: 'Słucham…', letGo: 'Puść, gdy skończysz.', success: 'To wszystko. Tak samo działa w Mailu, Slacku, Wordzie i każdej innej aplikacji.', again: 'Spróbuj jeszcze raz', skipLine: 'Nie możesz teraz mówić? Kliknij Dalej i spróbuj później z paska menu.', foot: 'Głos zamienia się w tekst na tym Macu.' },
        meeting: { h: 'Twoje pierwsze spotkanie', s: 'Gdy zaczyna się rozmowa w Zoomie, Teams lub Google Meet, Lintel zapyta, czy ją nagrać.', cap: 'Co zobaczysz', bubble: 'Nagrać tę rozmowę?', rec: 'Nagraj', notNow: 'Nie teraz', or: 'Możesz też kliknąć Nagraj spotkanie w oknie Lintel.', check: 'Sprawdź dźwięk rozmowy', checkHelp: 'Odtwarza krótki dźwięk i sprawdza, czy Lintel go słyszy.', checkBtn: 'Sprawdź', checkOk: 'Lintel słyszy dźwięk rozmowy.', tell: 'Uprzedzaj rozmówców o nagrywaniu. To uprzejme, a często wymagane.' }
      }
    }
  };

  // Settings search index: [page, row, inMore, en label, pl label, synonyms]. One home per setting.
  const INDEX = [
    ['general', 'lang', 0, 'Languages I speak', 'Języki, w których mówię', 'language polish english jezyk polski angielski'],
    ['general', 'mic', 0, 'Microphone', 'Mikrofon', 'mic headset headphones sluchawki'],
    ['general', 'size', 0, 'Text size', 'Wielkość tekstu', 'bigger larger font zoom wiekszy czcionka'],
    ['general', 'login', 0, 'Open Lintel when I log in', 'Otwieraj Lintel po zalogowaniu', 'login startup start launch logowanie uruchamiaj'],
    ['general', 'dock', 0, 'Show Lintel in the Dock', 'Pokazuj Lintel w Docku', 'dock icon ikona'],
    ['general', 'early', 1, 'Try new features early', 'Testuj nowości wcześniej', 'beta test testowe'],
    ['dictation', 'shortcut', 0, 'Dictation shortcut', 'Skrót dyktowania', 'hotkey key keyboard skrot klawisz dyktuj'],
    ['dictation', 'tidy', 0, 'Tidy up my text', 'Porządkuj mój tekst', 'clean changes my words punctuation porzadkuj zmienia slowa interpunkcja poprawia'],
    ['dictation', 'dict', 0, 'Dictionary', 'Słownik', 'spell spelling names words literuj pisownia nazwy slowa'],
    ['dictation', 'restore', 1, 'After pasting, put back what I had copied', 'Po wklejeniu przywróć to, co było skopiowane', 'clipboard paste schowek wklej'],
    ['dictation', 'raw', 1, 'Paste my last dictation unedited', 'Wklej ostatnie dyktowanie bez poprawek', 'raw original oryginal'],
    ['meetings', 'rec', 0, 'Record a meeting shortcut', 'Skrót nagrywania spotkania', 'record hotkey nagraj skrot'],
    ['meetings', 'suggest', 0, 'Suggest recording when a call starts', 'Proponuj nagrywanie, gdy zaczyna się rozmowa', 'zoom teams meet slack call rozmowa proponuj'],
    ['meetings', 'name', 0, 'Your name in notes', 'Twoje imię w notatkach', 'my name imie nazwisko'],
    ['meetings', 'export', 0, 'Export all notes', 'Eksportuj wszystkie notatki', 'export backup eksport kopia'],
    ['meetings', 'write', 1, 'Write notes after each meeting', 'Pisz notatki po każdym spotkaniu', 'summary podsumowanie'],
    ['meetings', 'never', 1, 'Never suggest recording in', 'Nigdy nie proponuj nagrywania w', 'slack huddle apps aplikacje nigdy'],
    ['meetings', 'check', 1, 'Check call audio', 'Sprawdź dźwięk rozmowy', 'sound test zoom dzwiek test'],
    ['ai', 'choice', 0, 'Who writes your notes', 'Kto pisze notatki', 'claude ai assistant company firma asystent'],
    ['ai', 'dl', 1, 'Downloaded files', 'Pobrane pliki', 'disk space storage free up miejsce dysk'],
    ['ai', 'own', 1, 'Use my own AI server', 'Użyj własnego serwera AI', 'server serwer own wlasny'],
    ['privacy', 'mic', 0, 'Microphone access', 'Dostęp do mikrofonu', 'permission allow uprawnienie zgoda mikrofon'],
    ['privacy', 'call', 0, 'Hear other people in a call', 'Słysz innych w rozmowie', 'zoom call audio others dzwiek rozmowy inni uprawnienie'],
    ['privacy', 'type', 0, 'Type into other apps', 'Pisz w innych aplikacjach', 'accessibility paste permission dostepnosc wklejanie uprawnienie'],
    ['privacy', 'audio', 0, 'Meeting audio', 'Dźwięk spotkań', 'recordings stop saving nagrania zapisywanie przechowuj'],
    ['privacy', 'dict', 0, 'Keep dictations', 'Przechowuj dyktowania', 'history historia keep przechowuj'],
    ['privacy', 'del', 0, 'Delete my data', 'Usuń moje dane', 'delete erase remove clear usun wymaz skasuj'],
    ['privacy', 'notes', 1, 'Keep notes and transcripts', 'Przechowuj notatki i transkrypcje', 'forever keep zawsze przechowuj'],
    ['privacy', 'remind', 1, 'Remind me to tell people I’m recording', 'Przypominaj, by uprzedzać o nagrywaniu', 'consent tell reminder zgoda uprzedz przypomnienie'],
    ['addons', 'quick', 0, 'Quick search', 'Szybkie wyszukiwanie', 'launcher open apps files spotlight aplikacje pliki'],
    ['addons', 'clip', 0, 'Clipboard history', 'Historia schowka', 'clipboard copied schowek skopiowane'],
    ['addons', 'win', 0, 'Window layouts', 'Układy okien', 'windows arrange okna ukladaj'],
    ['about', 'auto', 0, 'Update automatically', 'Aktualizuj automatycznie', 'update version aktualizacja wersja'],
    ['about', 'welcome', 0, 'Show welcome again', 'Pokaż powitanie ponownie', 'onboarding welcome powitanie'],
    ['about', 'report', 0, 'Send a problem report', 'Zgłoś problem', 'bug problem help blad pomoc'],
    ['about', 'ack', 0, 'Acknowledgements', 'Licencje i podziękowania', 'licenses licencje']
  ];

  const P = {
    note: '<path d="M4 2.5h5.5L12.5 5.5V13a.5.5 0 0 1-.5.5H4a.5.5 0 0 1-.5-.5V3a.5.5 0 0 1 .5-.5Z"/><path d="M9.5 2.5v3h3M5.5 8.5h5M5.5 11h3.5"/>',
    mic: '<rect x="6" y="2" width="4" height="7.5" rx="2"/><path d="M3.5 8a4.5 4.5 0 0 0 9 0M8 12.5V14.5"/>',
    meeting: '<circle cx="5.5" cy="6" r="2"/><circle cx="11" cy="6.5" r="1.6"/><path d="M2 13c.4-2.2 1.8-3.3 3.5-3.3S8.6 10.8 9 13M9.6 10.4c.4-.3.9-.5 1.4-.5 1.4 0 2.4 1 2.8 3.1"/>',
    stack: '<path d="M3 5.5h10M3 8.5h10M3 11.5h10"/>',
    book: '<path d="M3 3.2c1.8-.6 3.5-.4 5 .6v9.4c-1.5-1-3.2-1.2-5-.6ZM13 3.2c-1.8-.6-3.5-.4-5 .6v9.4c1.5-1 3.2-1.2 5-.6Z"/>',
    gear: '<circle cx="8" cy="8" r="2"/><path d="M8 1.8v1.7M8 12.5v1.7M1.8 8h1.7M12.5 8h1.7M3.6 3.6l1.2 1.2M11.2 11.2l1.2 1.2M3.6 12.4l1.2-1.2M11.2 4.8l1.2-1.2"/>',
    search: '<circle cx="7" cy="7" r="4.2"/><path d="m10.2 10.2 3.3 3.3"/>',
    check: '<path d="m3.5 8.3 3 3 6-6.6"/>',
    chev: '<path d="m6 4 4 4-4 4"/>', chevd: '<path d="m4 6 4 4 4-4"/>', chevl: '<path d="m10 4-4 4 4 4"/>',
    folder: '<path d="M2.5 4.5a1 1 0 0 1 1-1h3l1.5 1.5h4.5a1 1 0 0 1 1 1V12a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1Z"/>',
    plus: '<path d="M8 3.5v9M3.5 8h9"/>', x: '<path d="m4.5 4.5 7 7M11.5 4.5l-7 7"/>',
    lock: '<rect x="3.5" y="7" width="9" height="6.5" rx="1"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/>',
    sliders: '<path d="M3 4.5h10M3 11.5h10"/><circle cx="6" cy="4.5" r="1.5"/><circle cx="10.5" cy="11.5" r="1.5"/>',
    spark: '<path d="M8 2.5v3M8 10.5v3M2.5 8h3M10.5 8h3"/><circle cx="8" cy="8" r="1.6"/>',
    puzzle: '<path d="M3 5.5h2.5a1.5 1.5 0 1 1 3 0H11v2.5a1.5 1.5 0 1 1 0 3V13H3Z"/>',
    info: '<circle cx="8" cy="8" r="5.8"/><path d="M8 7.2v3.6M8 5.2h.01"/>',
    warn: '<path d="M8 2.5 14 13H2Z"/><path d="M8 6.5v3M8 11.2h.01"/>',
    copy: '<rect x="5" y="5" width="8" height="8.5" rx="1"/><path d="M3 10.5V3.5a1 1 0 0 1 1-1h6"/>',
    expand: '<path d="M9.5 2.5h4v4M13.5 2.5 9 7M6.5 13.5h-4v-4M2.5 13.5 7 9"/>',
    clip: '<rect x="4" y="3" width="8" height="10.5" rx="1"/><path d="M6 3V2h4v1"/>',
    grid: '<rect x="2.5" y="2.5" width="4.5" height="11" rx=".8"/><rect x="9" y="2.5" width="4.5" height="5" rx=".8"/><rect x="9" y="9.5" width="4.5" height="4" rx=".8"/>',
    shield: '<path d="M8 2 13 4v4c0 3-2.2 5-5 6-2.8-1-5-3-5-6V4Z"/>'
  };
  const RING = 'M99.01 19.82A112 112 0 1 1 19.82 99.01L64.25 110.92A66 66 0 1 0 110.92 64.25Z';

  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const ic = (n, cls) => `<svg class="ic ${cls || ''}" viewBox="0 0 16 16" aria-hidden="true">${P[n] || ''}</svg>`;
  // The working ring: one shape for the brand mark, the note-type mark, live state, progress and the empty state.
  function ring(kind, size, p) {
    const s = `width="${size}" height="${size}"`;
    const v = 'viewBox="0 0 256 256" aria-hidden="true"';
    if (kind === 'progress') {
      const full = 466, c = 559;
      return `<svg class="ring r-progress" ${s} ${v}><circle class="tr" cx="128" cy="128" r="89" stroke-dasharray="${full} ${c}" transform="rotate(255 128 128)"/><circle class="pg" cx="128" cy="128" r="89" stroke-dasharray="${(full * p).toFixed(1)} ${c}" transform="rotate(255 128 128)"/></svg>`;
    }
    if (kind === 'open') return `<svg class="ring r-open" ${s} ${v}><path class="op" d="${RING}"/></svg>`;
    const dot = kind === 'dictation' ? '' : '<circle class="rd" cx="128" cy="128" r="34"/>';
    return `<svg class="ring r-${kind}" ${s} ${v}><path class="rp" d="${RING}"/>${dot}</svg>`;
  }

  const qs = new URLSearchParams(location.search);
  const pick = (k, list, d) => (list.includes(qs.get(k)) ? qs.get(k) : d);
  const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const S = {
    screen: pick('screen', ['explorer', 'empty', 'note', 'rec', 'dict', 'set', 'onb'], 'explorer'),
    page: pick('page', ['general', 'dictation', 'meetings', 'ai', 'privacy', 'addons', 'about', 'quick', 'clip', 'win'], 'dictation'),
    step: pick('step', ['goal', 'privacy', 'access', 'try', 'meeting'], 'goal'),
    theme: pick('theme', ['light', 'dark'], prefersDark ? 'dark' : 'light'),
    lang: pick('lang', ['en', 'pl'], 'en'),
    tone: pick('tone', ['warm', 'neutral'], 'warm'),
    ts: pick('ts', ['m', 'l', 'xl'], 'm'),
    chrome: qs.get('chrome') !== '0',
    tab: pick('tab', ['notes', 'mine', 'transcript'], ''),
    warn: qs.get('warn') === '1',
    more: qs.get('more') === '1',
    sheet: qs.get('sheet') === 'delete' ? 'delete' : '',
    delOpt: 'meet',
    q: qs.get('q') || '',
    hl: '',
    ai: qs.get('ai') === 'claude' ? 'claude' : 'mac',
    useDict: false,
    goal: pick('goal', ['both', 'dict', 'meet'], 'both'),
    perms: { mic: false, type: false, call: false },
    checked: false,
    dict: pick('demo', ['listening', 'done'], 'idle'),
    typed: 0,
    filter: 'all', sel: pick('sel', ['nordlys', 'sync', 'marta', 'interview', 'board', 'fjord'], 'nordlys'), setupHidden: false,
    recSec: 761, procP: null,
    toggles: { tidy: true, restore: true, login: true, dock: true, early: false, suggest: true, write: true, remind: true, auto: true, files: true, own: false, quick: false, clip: false, win: false },
    audit: qs.get('audit') === '1'
  };
  if (qs.get('addon') === 'quick') S.toggles.quick = true;
  if (S.dict === 'done') S.typed = 9999;
  if (S.screen === 'onb' && ['try', 'meeting'].includes(S.step)) S.perms = { mic: true, type: true, call: false };

  const t = () => COPY[S.lang];
  const sw = (k, label) => `<button class="sw" role="switch" aria-checked="${S.toggles[k]}" aria-label="${esc(label)}" data-act="toggle" data-key="${k}"></button>`;
  const lights = (act) => `<span class="lights">${act ? `<button data-act="${act}" aria-label="Close"><i></i></button>` : '<i></i>'}<i></i><i></i></span>`;
  const row = (id, label, help, ctl) => `<div class="row ${S.hl === id ? 'hl' : ''}" data-row="${id}"><div class="lbl">${label}${help ? `<div class="help">${help}</div>` : ''}</div>${ctl || ''}</div>`;
  const pop = (v) => `<button class="pop">${v}${ic('chevd')}</button>`;
  const disc = (c) => `<button class="disc" data-act="more" aria-expanded="${S.more}">${ic(S.more ? 'chevd' : 'chev')}${c.set.more}</button>`;

  // ---------- main window ----------
  function sidebar(c, empty) {
    const n = c.nav;
    const cnt = empty ? { all: 0, meetings: 0, dictations: 0 } : { all: 42, meetings: 18, dictations: 24 };
    const it = (k, icn, label, num) => `<button class="si ${S.screen !== 'dict' && S.filter === k ? 'on' : ''}" data-filter="${k}">${icn}<span>${label}</span>${num !== undefined ? `<span class="n">${num}</span>` : ''}</button>`;
    const folders = empty
      ? `<div class="ne">${c.empty.noFolders}</div>`
      : c.folders.map(([k, l]) => it(k, ic('folder'), l, k === 'clients' ? 9 : 4)).join('');
    return `<aside class="side">${lights()}
      ${it('all', ic('stack'), n.all, cnt.all)}${it('meetings', ring('meeting', 15), n.meetings, cnt.meetings)}${it('dictations', ring('dictation', 15), n.dictations, cnt.dictations)}
      <div class="sh">${n.folders}</div>${folders}
      <button class="si add" data-act="noop">${ic('plus')}<span>${n.newFolder}</span></button>
      <span class="sp"></span>
      <button class="si ${S.screen === 'dict' ? 'on' : ''}" data-go="dict">${ic('book')}<span>${n.dictionary}</span><span class="n">${empty ? 0 : 12}</span></button></aside>`;
  }

  function toolbar(c, opts) {
    const o = opts || {};
    const recCtl = S.screen === 'rec'
      ? `<span class="livepill" role="status">${ring('live', 16)}<span>${c.rec.live} · ${recTime()}</span><button class="btn" data-act="stoprec">${c.stop}</button></span>`
      : `<button class="btn pri" data-act="rec">${ring('mark', 15)}<span>${c.record}</span></button>`;
    return `<div class="tb">${o.back ? `<button class="back" data-go="explorer">${ic('chevl')}${c.note.back}</button>` : ''}
      <label class="field">${ic('search')}<input placeholder="${esc(c.searchNotes)}" aria-label="${esc(c.searchNotes)}"></label>
      <span class="sp"></span>${recCtl}<button class="iconbtn" data-go="set" aria-label="${esc(c.settings)}" title="${esc(c.settings)} (⌘,)">${ic('gear')}</button></div>`;
  }

  function items(c) {
    let list = c.items.slice();
    if (S.procP !== null) list = [Object.assign({}, c.items[0], { id: 'new', f: '', t: c.newRec.t, m: c.newRec.m, work: c.items[1].work, p: S.procP, w: '15:02', g: 0 })].concat(list);
    if (S.filter === 'meetings') list = list.filter((x) => x.k === 'meeting');
    else if (S.filter === 'dictations') list = list.filter((x) => x.k === 'dictation');
    else if (S.filter !== 'all') list = list.filter((x) => x.f === S.filter);
    return list;
  }

  function listCol(c) {
    const list = items(c);
    let out = '';
    if (!S.setupHidden && S.screen !== 'rec') {
      out += `<div class="setup"><div class="tx"><div class="t">${c.setup.t}</div><div>${c.setup.next}</div></div><button class="btn" data-go="set" data-page="privacy">${c.setup.act}</button><button class="iconbtn" data-act="hidesetup" aria-label="${c.setup.close}" title="${c.setup.close}">${ic('x')}</button></div>`;
    }
    if (S.screen === 'rec') {
      out += `<div class="gl">${c.now}</div><button class="li on">${ring('live', 15)}<span class="tx"><span class="t">${c.newRec.t}</span><span class="m work">${c.newRec.rec} · ${recTime()}</span></span></button>`;
    }
    let g = -1;
    for (const x of list) {
      if (x.g !== g) { g = x.g; out += `<div class="gl">${c.groups[g]}</div>`; }
      const on = S.screen !== 'rec' && S.sel === x.id;
      const working = x.p !== undefined && x.p < 1;
      const mark = working ? ring('progress', 15, x.p) : ring(x.k, 15);
      const meta = working ? `<span class="m work">${x.work}</span>` : x.fail ? `<span class="m">${x.m} · <span class="failt">${x.fail}</span></span>` : `<span class="m">${x.m}</span>`;
      out += `<button class="li ${on ? 'on' : ''}" data-item="${x.id}" aria-current="${on}">${mark}<span class="tx"><span class="t">${x.t}</span>${meta}</span><span class="w">${x.w}</span></button>`;
    }
    return `<nav class="list" aria-label="${c.nav.all}">${out}</nav>`;
  }

  function noteBody(c, tab) {
    const n = c.note;
    if (tab === 'mine') return `<div class="minehelp">${n.mineHelp}</div><div class="mine">${n.mine.map((l) => `<div>${esc(l)}</div>`).join('')}</div>`;
    if (tab === 'transcript') return `<div style="margin-top:10px">${n.tr.map(([s, l]) => `<div class="tline"><span class="s">${s}</span><span>${l}</span></div>`).join('')}</div>`;
    return `<div class="note"><div class="h3">${n.sumH}</div><p>${n.sum}</p>
      <div class="h3">${n.decH}</div><ul>${n.dec.map((d) => `<li>${d}</li>`).join('')}</ul>
      <div class="h3">${n.taskH}</div>${n.tasks.map(([w, x, d]) => `<div class="task"><button class="cb" role="checkbox" aria-checked="false" aria-label="${esc(x)}"></button><span><span class="who">${w}:</span> ${x}${d ? ` <span class="who">· ${d}</span>` : ''}</span></div>`).join('')}
      <div class="nfoot">${n.foot}</div></div>`;
  }

  function noteView(c, full) {
    const n = c.note;
    const item = items(c).find((x) => x.id === S.sel) || c.items[0];
    const tab = S.tab || (full ? 'mine' : 'notes');
    if (item.k === 'dictation') {
      return `<div class="nhead"><div class="sp"><h1 class="ntitle">${item.t}</h1><div class="nmeta">${c.dictNote.meta}</div></div><button class="btn">${ic('copy')}${n.copy}</button></div>
        <div style="margin-top:8px"><span class="chip">${ring('dictation', 11)}${n.onMac}</span></div><p class="mine" style="margin-top:16px">${c.dictNote.body}</p>`;
    }
    const tabs = n.tabs.map((l, i) => { const k = ['notes', 'mine', 'transcript'][i]; return `<button role="tab" aria-selected="${tab === k}" data-tab="${k}">${l}</button>`; }).join('');
    const head = item.id === 'nordlys' ? n.meta : item.m;
    if (item.fail && tab === 'notes') {
      const f = c.failed;
      return `<div class="nhead"><div class="sp"><h1 class="ntitle">${item.t}</h1><div class="nmeta">${head}</div></div></div>
        <div class="tabs" role="tablist">${tabs}</div><div class="warnbox" role="alert">${ic('warn')}<div class="tx"><b>${f.t}</b>${f.s}</div><button class="btn" data-act="noop">${f.b}</button></div>`;
    }
    return `<div class="nhead"><div class="sp"><h1 class="ntitle">${item.t}</h1><div class="nmeta">${head}</div></div>${full ? '' : `<button class="btn" data-go="note">${ic('expand')}${n.open}</button>`}<button class="btn">${ic('copy')}${n.copy}</button></div>
      <div style="margin-top:8px"><span class="chip">${ring('meeting', 11)}${n.onMac}</span></div>
      <div class="tabs" role="tablist">${tabs}</div>${noteBody(c, tab)}`;
  }

  function explorer(c) {
    return `<div class="win mainw">${sidebar(c)}<div class="content">${toolbar(c)}<div class="body2">${listCol(c)}<article class="prev">${noteView(c, false)}</article></div></div></div>`;
  }

  function emptyScr(c) {
    const e = c.empty;
    return `<div class="win mainw">${sidebar(c, true)}<div class="content">${toolbar(c)}<div class="empty">${ring('open', 96)}<h2>${e.t}</h2><p>${e.s}</p><button class="btn lg" data-go="onb" data-step="try">${ring('dictation', 14)}${e.b}</button></div></div></div>`;
  }

  function noteScr(c) {
    return `<div class="win mainw"><div class="content"><div style="display:flex;align-items:center;padding-left:16px;border-bottom:1px solid var(--hair)">${lights()}<div style="flex:1">${toolbar(c, { back: true }).replace('class="tb"', 'class="tb" style="border:0"')}</div></div><div class="detail"><div class="in">${noteView(c, true)}</div></div></div></div>`;
  }

  function recScr(c) {
    const r = c.rec;
    const warn = S.warn ? `<div class="warnbox" role="alert">${ic('warn')}<div class="tx"><b>${r.warnT}</b>${r.warnS}</div><button class="btn" data-go="set" data-page="privacy">${r.warnB}</button></div>` : '';
    const prev = `<h1 class="ntitle">${c.newRec.t}</h1><div class="nmeta">${r.tell}</div>
      <div class="live" style="margin-top:14px"><div class="top">${ring('live', 40)}<div><div class="t">${r.live} · ${recTime()}</div><div class="s">${S.warn ? '' : r.hears}</div></div></div>
      <div class="acts"><button class="btn pri" data-act="stoprec">${r.stopWrite}</button></div></div>${warn}
      <div class="h3" style="margin-top:18px">${r.pad}</div><div class="pad" role="textbox" aria-label="${r.pad}" tabindex="0">${r.padLines.map((l) => `<div>${l}</div>`).join('')}<span class="caret"></span></div>
      <div class="minehelp">${r.padPh}</div>`;
    return `<div class="win mainw">${sidebar(c)}<div class="content">${toolbar(c)}<div class="body2">${listCol(c)}<article class="prev">${prev}</article></div></div></div>`;
  }

  function dictScr(c) {
    const d = c.dict;
    return `<div class="win mainw">${sidebar(c)}<div class="content">${toolbar(c)}<div class="dpage"><h2>${d.t}</h2><div class="help" style="font-size:1rem">${d.s}</div>
      <div class="dtools"><label class="field">${ic('search')}<input placeholder="${d.search}" aria-label="${d.search}"></label><button class="btn">${ic('plus')}${d.add}</button></div>
      <div class="group">${d.words.map(([w, m]) => `<div class="row"><div class="lbl">${w}<div class="help">${m}</div></div><button class="btn">${d.remove}</button></div>`).join('')}</div></div></div></div>`;
  }

  // ---------- settings window ----------
  const PAGES = ['general', 'dictation', 'meetings', 'ai', 'privacy'];
  const PAGE_IC = { general: 'sliders', dictation: 'mic', meetings: 'meeting', ai: 'spark', privacy: 'shield', addons: 'puzzle', about: 'info', quick: 'search', clip: 'clip', win: 'grid' };

  function setSidebar(c) {
    const s = c.set;
    const it = (k, sub, extra) => `<button class="si ${sub ? 'sub' : ''} ${!S.q && S.page === k ? 'on' : ''}" data-page="${k}">${ic(PAGE_IC[k])}<span>${s.side[k]}</span>${extra || ''}</button>`;
    const offN = ['quick', 'clip', 'win'].filter((k) => !S.toggles[k]).length;
    const subs = ['quick', 'clip', 'win'].filter((k) => S.toggles[k]).map((k) => it(k, true)).join('');
    return `<aside class="side">${lights('closeset')}
      <label class="field" style="margin-bottom:10px">${ic('search')}<input id="ssearch" value="${esc(S.q)}" placeholder="${esc(s.search)}" aria-label="${esc(s.search)}"></label>
      ${PAGES.map((k) => it(k)).join('')}<div class="sh"></div>${it('addons', false, offN ? `<span class="badge-off">${s.offN(offN)}</span>` : '')}${subs}
      <span class="sp"></span>${it('about')}</aside>`;
  }

  function permState(c, k) {
    const p = c.set.privacy;
    const granted = k === 'call' ? false : true;
    return granted ? `<span class="ok">${ic('check')}${p.allowed}</span>` : `<button class="btn" data-act="noop">${p.allow}</button>`;
  }

  function pageBody(c) {
    const s = c.set, more = S.more;
    const pfoot = (txt, kind) => `<div class="foot">${kind === 'ring' ? ring('mark', 13) : ic('lock')}${txt}</div>`;
    switch (S.page) {
      case 'general': {
        const g = s.general;
        const size = `<span class="seg" role="group" aria-label="${g.size}">${['m', 'l', 'xl'].map((v) => `<button aria-pressed="${S.ts === v}" data-ts="${v}">${{ m: 'M', l: 'L', xl: 'XL' }[v]}</button>`).join('')}</span>`;
        return `<div class="group">${row('lang', g.lang, `${g.langVal} · ${g.langHelp}`, `<button class="btn">${g.change}</button>`)}${row('mic', g.mic, g.micHelp, pop(g.micVal))}${row('size', g.size, '', size)}${row('login', g.login, '', sw('login', g.login))}${row('dock', g.dock, '', sw('dock', g.dock))}</div>
          ${disc(c)}${more ? `<div class="group">${row('early', g.early, g.earlyHelp, sw('early', g.early))}</div>` : ''}`;
      }
      case 'dictation': {
        const d = s.dictation;
        return `<div class="status" role="status">${ring('mark', 18)}<div><div class="t">${d.status}</div><div class="help">${d.statusSub}</div></div></div>
          <div class="group" style="margin-top:14px">${row('shortcut', d.shortcut, d.shortcutHelp, `<kbd>${c.key}</kbd>`)}${row('tidy', d.tidy, d.tidyHelp, sw('tidy', d.tidy))}${row('dict', d.dict, d.dictVal, `<button class="btn" data-go="dict">${d.open}</button>`)}${row('kept', d.kept, '', `<button class="link" data-page="privacy" data-hl="dict">${d.keptLink} ›</button>`)}</div>
          ${disc(c)}${more ? `<div class="group">${row('restore', d.restore, '', sw('restore', d.restore))}${row('raw', d.raw, '', `<button class="btn">${d.setKey}</button>`)}</div>` : ''}${pfoot(d.foot)}`;
      }
      case 'meetings': {
        const m = s.meetings;
        return `<div class="status warnst" role="status">${ic('warn')}<div style="flex:1"><div class="t">${m.status}</div><div class="help">${m.statusSub}</div></div><button class="btn" data-page="privacy" data-hl="call">${m.allow}</button></div>
          <div class="group" style="margin-top:14px">${row('rec', m.rec, m.recHelp, `<button class="btn">${m.setKey}</button>`)}${row('suggest', m.suggest, m.suggestHelp, sw('suggest', m.suggest))}${row('name', m.name, '', `<span class="pop" style="min-width:140px">${m.nameVal}</span>`)}${row('writer', `${m.writer}: <b>${S.ai === 'claude' ? 'Claude' : m.writerVal}</b>`, '', `<button class="link" data-page="ai">${m.writerLink} ›</button>`)}${row('export', m.exp, '', `<button class="btn">${m.expBtn}</button>`)}</div>
          ${disc(c)}${more ? `<div class="group">${row('write', m.write, '', sw('write', m.write))}${row('never', m.never, m.neverVal, `<button class="btn">${m.addApp}</button>`)}${row('check', m.check, '', `<button class="btn">${m.checkBtn}</button>`)}</div>` : ''}${pfoot(m.foot)}`;
      }
      case 'ai': {
        const a = s.ai, cl = S.ai === 'claude';
        const rad = (k, l, h) => `<button class="radrow" role="radio" aria-checked="${S.ai === k}" data-ai="${k}"><span class="rad"></span><span><span style="font-weight:600">${l}</span><div class="help">${h}</div></span></button>`;
        const use = cl ? `<div class="gh">${a.use}</div><div class="group">${row('usenotes', a.useNotes, '', `<button class="cb" role="checkbox" aria-checked="true" aria-label="${a.useNotes}">${ic('check')}</button>`)}${row('usedict', a.useDict, '', `<button class="cb" role="checkbox" aria-checked="${S.useDict}" data-act="usedict" aria-label="${a.useDict}">${S.useDict ? ic('check') : ''}</button>`)}</div><div class="help" style="margin:6px 2px 0">${a.consent}</div>` : '';
        return `<div class="status" role="status">${ring('mark', 18)}<div class="t">${cl ? a.statusClaude : a.statusMac}</div></div>
          <div class="gh">${a.q}</div><div class="group ${S.hl === 'choice' ? 'hl' : ''}" role="radiogroup" aria-label="${a.q}" data-row="choice">${rad('mac', a.mac, a.macHelp)}${rad('claude', a.claude, a.claudeHelp)}</div>${use}
          ${disc(c)}${more ? `<div class="group">${row('local', a.local, '', pop(a.localVal))}${row('dl', a.dl, a.dlVal, `<button class="btn">${a.show}</button><button class="btn">${a.remove}</button>`)}${row('own', a.own, '', sw('own', a.own))}</div>` : ''}${pfoot(cl ? a.footClaude : a.footMac)}`;
      }
      case 'privacy': {
        const p = s.privacy;
        const perm = (k) => row(k, p.perms[k][0], p.perms[k][1], permState(c, k));
        return `<p class="lead">${p.lead} <button class="link" data-page="ai">${p.leadLink} ›</button></p>
          <div class="gh">${p.useH}</div><div class="group">${perm('mic')}${perm('call')}${perm('type')}</div>
          <div class="gh">${p.keepH}</div><div class="group">${row('audio', p.audio, '', pop(p.audioVal))}${row('dict', p.dict, '', pop(p.dictVal))}</div>
          <div class="gh">${p.delH}</div><div class="group">${row('del', p.del, p.delHelp, `<button class="btn danger" data-act="sheet">${p.delBtn}</button>`)}</div>
          ${disc(c)}${more ? `<div class="group">${row('notes', p.notes, '', pop(p.notesVal))}${row('remind', p.remind, '', sw('remind', p.remind))}</div>` : ''}`;
      }
      case 'addons': {
        const a = s.addons;
        const r = (k) => row(k, s.side[k], S.toggles[k] ? `${a.items[k]} ${a.onHelp}` : a.items[k], `<span class="swl">${S.toggles[k] ? s.on : s.off}${sw(k, s.side[k])}</span>`);
        return `<p class="lead">${a.lead}</p><div class="group" style="margin-top:14px">${r('quick')}${r('clip')}${r('win')}</div>`;
      }
      case 'quick': {
        const q = s.quick;
        return `<div class="status warnst" role="status">${ic('info')}<div class="t">${q.status}</div></div>
          <div class="group" style="margin-top:14px">${row('qshort', q.shortcut, '', `<button class="btn">${q.setKey}</button>`)}${row('files', q.files, '', sw('files', q.files))}${row('folders', q.folders, q.foldersVal, `<button class="btn">${q.change}</button>`)}</div>
          ${disc(c)}${more ? `<div class="group">${row('order', q.order, '', '<span>›</span>')}${row('hidden', q.hidden, '', '<button class="sw" role="switch" aria-checked="false"></button>')}${row('skip', q.skip, '', '<span>›</span>')}${row('over', q.over, '', `<button class="btn">${q.overBtn}</button>`)}</div>` : ''}${pfoot(q.foot)}`;
      }
      case 'clip': return `<div class="group">${row('cshort', s.quick.shortcut, '', '<kbd>⌘⇧V</kbd>')}${row('cnever', s.clip.never, s.clip.neverVal, `<button class="btn">${s.meetings.addApp}</button>`)}</div>`;
      case 'win': return `<div class="group">${row('wshort', s.quick.shortcut, '', `<button class="btn">${s.quick.setKey}</button>`)}${row('wgap', s.win.gap, '', pop(s.win.gapVal))}</div>`;
      case 'about': {
        const a = s.about;
        return `<div class="status" role="status">${ring('mark', 18)}<div class="t" style="flex:1">${a.status}</div><button class="btn">${a.check}</button></div>
          <div class="group" style="margin-top:14px">${row('auto', a.auto, '', sw('auto', a.auto))}${row('news', a.news, '', `<button class="btn">${a.open}</button>`)}${row('welcome', a.welcome, '', `<button class="btn" data-go="onb" data-step="goal">${a.show}</button>`)}${row('report', a.report, a.reportHelp, `<button class="btn">${a.send}</button>`)}${row('ack', a.ack, '', `<button class="btn">${a.open}</button>`)}</div>`;
      }
    }
    return '';
  }

  const fold = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/ł/g, 'l');
  function searchResults(c) {
    const s = c.set, q = fold(S.q.trim());
    const words = q.split(/\s+/).filter(Boolean);
    const hits = INDEX.filter((e) => { const hay = fold(`${e[3]} ${e[4]} ${e[5]}`); return words.every((w) => hay.includes(w)); });
    if (!hits.length) return `<h2 class="ph2">${s.results(esc(S.q))}</h2><p>${s.none(esc(S.q))}</p><p class="help">${s.noneHelp}</p>`;
    return `<h2 class="ph2">${s.results(esc(S.q))}</h2><div class="group">${hits.map((e) => `<button class="res" data-res="${e[0]}:${e[1]}:${e[2]}"><span>${S.lang === 'pl' ? e[4] : e[3]}</span><span class="p">${s.side[e[0]]}${e[2] ? ` › ${s.more}` : ''}</span></button>`).join('')}</div>`;
  }

  function sheet(c) {
    const p = c.set.privacy;
    const opt = p.opts.find((o) => o[0] === S.delOpt);
    return `<div class="scrim"><div class="sheet" role="dialog" aria-modal="true" aria-label="${p.sheetT}"><h3>${p.sheetT}</h3><div class="help" style="margin-bottom:12px">${p.sheetS}</div>
      <div class="group" role="radiogroup">${p.opts.map(([k, l, n]) => `<button class="radrow" role="radio" aria-checked="${S.delOpt === k}" data-del="${k}"><span class="rad"></span><span><span style="font-weight:600">${l}</span><div class="help">${n}</div></span></button>`).join('')}</div>
      <div class="note-ln danger-t">${ic('warn')}${p.warn}</div>
      <div class="acts"><button class="btn lg pri" data-act="closesheet" autofocus>${p.cancel}</button><button class="btn lg danger" data-act="closesheet">${opt[3]}</button></div></div></div>`;
  }

  function settingsScr(c) {
    const s = c.set;
    const isTop = ['dictation', 'meetings'].includes(S.page);
    const title = isTop ? `<h2 class="ph2">${s.side[S.page]}<span class="sp"></span><span class="swl">${s.on}<button class="sw" role="switch" aria-checked="true" aria-label="${s.side[S.page]}"></button></span></h2>` : `<h2 class="ph2">${s.side[S.page]}</h2>`;
    const body = S.q ? searchResults(c) : title + pageBody(c);
    return `<div class="win setw">${setSidebar(c)}<main class="spage">${body}</main>${S.sheet ? sheet(c) : ''}</div>`;
  }

  // ---------- onboarding ----------
  function onbSteps() {
    const st = ['goal', 'privacy', 'access'];
    if (S.goal !== 'meet') st.push('try');
    if (S.goal !== 'dict') st.push('meeting');
    return st;
  }
  function permRows(c) {
    const p = c.set.privacy, o = c.onb.access;
    const ks = ['mic'].concat(S.goal !== 'meet' ? ['type'] : []).concat(S.goal !== 'dict' ? ['call'] : []);
    return `<div class="group">${ks.map((k) => row(`p-${k}`, p.perms[k][0], p.perms[k][1] + (k !== 'mic' ? ` <span class="help">(${o.sys})</span>` : ''), S.perms[k] ? `<span class="ok">${ic('check')}${p.allowed}</span>` : `<button class="btn" data-perm="${k}">${p.allow.replace('…', '')}</button>`)).join('')}</div>`;
  }
  function onbScr(c) {
    const o = c.onb, steps = onbSteps();
    if (!steps.includes(S.step)) S.step = steps[steps.length - 1];
    const i = steps.indexOf(S.step);
    const list = steps.map((k, j) => `<div class="ost ${j < i ? 'done' : j === i ? 'cur' : ''}" aria-current="${j === i ? 'step' : 'false'}"><span class="num">${j < i ? ic('check') : j + 1}</span>${o.names[k]}</div>`).join('');
    let body = '';
    if (S.step === 'goal') {
      const g = o.goal;
      const opt = (k, kind) => `<button class="opt" role="radio" aria-checked="${S.goal === k}" data-goal="${k}">${kind}<span class="tx"><b>${g[k][0]}</b><span class="help" style="font-size:1rem">${g[k][1]}</span></span><span class="rad"></span></button>`;
      body = `<h1>${g.h}</h1><p class="sub">${g.s}</p><div class="opts" role="radiogroup" aria-label="${g.h}">${opt('dict', ring('dictation', 22))}${opt('meet', ring('meeting', 22))}${opt('both', ring('mark', 22))}</div>`;
    } else if (S.step === 'privacy') {
      const p = o.privacy;
      body = `<h1>${p.h}</h1><p class="sub">${p.s}</p><ul class="points">${p.pts.map((x, j) => `<li>${ic(['lock', 'shield', 'check'][j])}<span>${x}</span></li>`).join('')}</ul>${S.goal !== 'dict' ? `<div class="note-ln">${ic('info')}<span>${p.consent}</span></div>` : ''}`;
    } else if (S.step === 'access') {
      const a = o.access;
      body = `<h1>${a.h}</h1><p class="sub">${a.s}</p>${permRows(c)}<div class="note-ln">${ic('info')}<span>${a.skip}</span></div>`;
    } else if (S.step === 'try') {
      const y = o.try;
      let txt;
      if (S.dict === 'idle') txt = `<span class="ph">${y.ph}</span>`;
      else if (S.dict === 'listening') txt = `<span class="listen">${ring('live', 16)}${y.listening} <span style="color:var(--sec);font-weight:400">${y.letGo}</span></span>`;
      else txt = esc(y.result.slice(0, S.typed)) + (S.dict === 'typing' ? '<span class="caret"></span>' : '');
      const done = S.dict === 'done';
      body = `<h1>${y.h}</h1><p class="sub">${y.s} <button class="link" data-act="noop">${y.change}</button></p>
        <div class="group mail"><div class="row"><span class="k">${y.to}</span><span>${y.toName}</span></div><div class="row"><span class="k">${y.subject}</span><span>${y.subj}</span></div><div class="txt" aria-live="polite">${txt}</div></div>
        ${done ? `<div class="success">${ic('check')}<span>${y.success} <button class="link" data-act="again">${y.again}</button></span></div>`
          : `<div class="hold"><button class="holdbtn" data-act="hold" aria-pressed="${S.dict === 'listening'}">${S.dict === 'listening' ? ring('live', 16) : ring('dictation', 16)}<span>${S.dict === 'listening' ? y.listening : y.hold}</span><kbd>${c.key}</kbd></button></div><div class="note-ln">${ic('info')}<span>${y.skipLine}</span></div>`}
        <div class="foot">${ic('lock')}${y.foot}</div>`;
    } else {
      const m = o.meeting;
      body = `<h1>${m.h}</h1><p class="sub">${m.s}</p>
        <div class="mock" aria-hidden="true"><div class="cap">${m.cap}</div><span class="bubble">${ring('mark', 20)}<b>${m.bubble}</b><span class="btn tint">${m.rec}</span><span class="btn">${m.notNow}</span></span></div>
        <div class="help" style="font-size:1rem;margin-bottom:14px">${m.or}</div>
        <div class="group">${row('check', m.check, S.checked ? `<span class="ok">${ic('check')}${m.checkOk}</span>` : m.checkHelp, `<button class="btn" data-act="check">${m.checkBtn}</button>`)}</div>
        <div class="note-ln">${ic('info')}<span>${m.tell}</span></div>`;
    }
    const last = i === steps.length - 1;
    return `<div class="win onbw" role="dialog" aria-label="${c.app}"><aside class="oside">${lights()}<div class="obrand">${ring('mark', 26)}${c.app}</div><div class="otag">${o.tag}</div>${list}</aside>
      <div class="oright"><div class="obody"><div class="ostep">${o.stepOf(i + 1, steps.length)}</div>${body}</div>
      <div class="ofoot">${i > 0 ? `<button class="btn lg" data-act="oback">${o.back}</button>` : ''}<span class="sp"></span><button class="btn lg pri" data-act="onext">${last ? o.finish : o.cont}</button></div></div></div>`;
  }

  // ---------- shell ----------
  function recTime() { const m = Math.floor(S.recSec / 60), s = S.recSec % 60; return `${m}:${String(s).padStart(2, '0')}`; }

  function bar() {
    const b = t().bar;
    const seg = (key, opts) => `<span class="sk-seg" role="group" aria-label="${key}">${opts.map(([v, l]) => `<button type="button" data-set="${key}" data-val="${v}" aria-pressed="${S[key] === v}">${l}</button>`).join('')}</span>`;
    return `<div id="sk-bar"><b>Lintel · sketch</b><label>${b.screen}</label>${seg('screen', ['explorer', 'empty', 'note', 'rec', 'dict', 'set', 'onb'].map((k) => [k, b[k]]))}
      <label>${b.theme}</label>${seg('theme', [['light', b.light], ['dark', b.dark]])}<label>${b.lang}</label>${seg('lang', [['en', 'EN'], ['pl', 'PL']])}
      <label>${b.tone}</label>${seg('tone', [['warm', b.warm], ['neutral', b.neutral]])}</div>`;
  }

  function syncURL() {
    const p = new URLSearchParams();
    p.set('screen', S.screen); if (S.screen === 'set') p.set('page', S.page); if (S.screen === 'onb') p.set('step', S.step);
    p.set('theme', S.theme); p.set('lang', S.lang); if (S.tone !== 'warm') p.set('tone', S.tone); if (S.ts !== 'm') p.set('ts', S.ts);
    if (!S.chrome) p.set('chrome', '0');
    history.replaceState(null, '', location.pathname + '?' + p.toString());
  }

  const SCREENS = { explorer, empty: emptyScr, note: noteScr, rec: recScr, dict: dictScr, set: settingsScr, onb: onbScr };
  function render() {
    const root = document.getElementById('app');
    const focusSearch = document.activeElement && document.activeElement.id === 'ssearch';
    document.documentElement.lang = S.lang;
    document.documentElement.className = `${S.theme} ${S.tone} ts-${S.ts}${S.chrome ? '' : ' nochrome'}`;
    root.innerHTML = (S.chrome ? bar() : '') + `<div class="stage">${SCREENS[S.screen](t())}</div>`;
    if (focusSearch) { const el = document.getElementById('ssearch'); el.focus(); el.setSelectionRange(el.value.length, el.value.length); }
    if (S.hl) { const el = root.querySelector(`[data-row="${S.hl}"]`); if (el) el.scrollIntoView({ block: 'center' }); }
    if (S.audit) audit();
  }

  // ---------- interactions ----------
  let typer = null, recTimer = null, procTimer = null;
  function startListen() { if (S.screen !== 'onb' || S.step !== 'try' || S.dict === 'listening' || S.dict === 'typing') return; S.dict = 'listening'; S.typed = 0; render(); }
  function stopListen() {
    if (S.dict !== 'listening') return;
    const full = t().onb.try.result.length;
    if (reduced) { S.dict = 'done'; S.typed = full; render(); return; }
    S.dict = 'typing'; render(); clearInterval(typer);
    typer = setInterval(() => { S.typed += 3; if (S.typed >= full) { S.typed = full; S.dict = 'done'; clearInterval(typer); } render(); }, 22);
  }
  function go(screen, extra) {
    S.screen = screen; S.more = false; S.hl = ''; S.sheet = '';
    if (extra && extra.page) S.page = extra.page;
    if (extra && extra.step) S.step = extra.step;
    if (screen === 'note') S.tab = '';
    syncURL(); render();
  }

  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-set],[data-act],[data-go],[data-page],[data-filter],[data-item],[data-tab],[data-ts],[data-ai],[data-res],[data-del],[data-goal],[data-perm]');
    if (!el) return;
    const d = el.dataset;
    if (d.set) { S[d.set] = d.val; if (d.set === 'screen') { S.more = false; S.hl = ''; S.sheet = ''; } syncURL(); render(); return; }
    if (d.go) { go(d.go, { page: d.page, step: d.step }); return; }
    if (d.page) { S.page = d.page; S.q = ''; S.more = false; S.hl = d.hl || ''; render(); return; }
    if (d.filter) { S.filter = d.filter; if (S.screen === 'dict') S.screen = 'explorer'; const l = items(t()); if (l.length && !l.find((x) => x.id === S.sel)) S.sel = l[0].id; render(); return; }
    if (d.item) { S.sel = d.item; S.tab = ''; render(); return; }
    if (d.tab) { S.tab = d.tab; render(); return; }
    if (d.ts) { S.ts = d.ts; syncURL(); render(); return; }
    if (d.ai) { S.ai = d.ai; render(); return; }
    if (d.del) { S.delOpt = d.del; render(); return; }
    if (d.goal) { S.goal = d.goal; render(); return; }
    if (d.perm) { S.perms[d.perm] = true; render(); return; }
    if (d.res) { const [p, r, m] = d.res.split(':'); S.page = p; S.more = m === '1'; S.hl = r; S.q = ''; render(); return; }
    const a = d.act;
    if (a === 'toggle') { S.toggles[d.key] = !S.toggles[d.key]; render(); }
    else if (a === 'more') { S.more = !S.more; render(); }
    else if (a === 'again') { S.dict = 'idle'; S.typed = 0; render(); }
    else if (a === 'hidesetup') { S.setupHidden = true; render(); }
    else if (a === 'closeset') { go('explorer'); }
    else if (a === 'sheet') { S.sheet = 'delete'; render(); }
    else if (a === 'closesheet') { S.sheet = ''; render(); }
    else if (a === 'usedict') { S.useDict = !S.useDict; render(); }
    else if (a === 'check') { S.checked = true; render(); }
    else if (a === 'onext') { const st = onbSteps(), i = st.indexOf(S.step); if (i < st.length - 1) { S.step = st[i + 1]; syncURL(); render(); } else go('empty'); }
    else if (a === 'oback') { const st = onbSteps(), i = st.indexOf(S.step); if (i > 0) { S.step = st[i - 1]; syncURL(); render(); } }
    else if (a === 'rec') { S.recSec = 0; clearInterval(recTimer); recTimer = setInterval(() => { S.recSec++; if (S.screen === 'rec') render(); }, 1000); go('rec'); }
    else if (a === 'stoprec') {
      clearInterval(recTimer); S.procP = reduced ? 1 : 0.05; S.sel = 'new'; S.filter = 'all'; go('explorer');
      clearInterval(procTimer);
      if (!reduced) procTimer = setInterval(() => { S.procP = Math.min(1, S.procP + 0.05); if (S.procP >= 1) clearInterval(procTimer); render(); }, 250);
    }
  });
  document.addEventListener('dblclick', (e) => { const el = e.target.closest('[data-item]'); if (el) { S.sel = el.dataset.item; go('note'); } });
  document.addEventListener('input', (e) => { if (e.target.id === 'ssearch') { S.q = e.target.value; S.hl = ''; render(); } });
  document.addEventListener('pointerdown', (e) => { if (e.target.closest('[data-act=hold]')) { e.preventDefault(); startListen(); } });
  document.addEventListener('pointerup', stopListen);
  document.addEventListener('pointercancel', stopListen);
  document.addEventListener('keydown', (e) => {
    if (e.code === 'Space' && e.altKey) { e.preventDefault(); if (!e.repeat) startListen(); return; }
    if (e.key === ',' && e.metaKey) { e.preventDefault(); go('set'); return; }
    if (e.key === 'Escape') { if (S.sheet) { S.sheet = ''; render(); } else if (S.q) { S.q = ''; render(); } else if (S.screen === 'set' || S.screen === 'note') go('explorer'); }
  });
  document.addEventListener('keyup', (e) => { if (e.code === 'Space' || e.key === 'Alt') stopListen(); });

  // ---------- audit (?audit=1): facts for the foolproof checklist, written into <pre id="audit"> ----------
  const JARGON = /\b(model|llm|server|serwer|address|endpoint|bundle id|index|indeks|ranking|diagnostics|diagnostyk\w*|launcher|plugin|wtyczk\w*|parakeet|whisper|gguf|token\w*|diarization)\b/i;
  function audit() {
    const win = document.querySelector('.win');
    const out = { trunc: [], spill: [], scroll: [], primaries: 0, jargon: [], targets: [] };
    win.querySelectorAll('*').forEach((el) => {
      const cs = getComputedStyle(el);
      const text = (el.innerText || '').trim().slice(0, 60);
      if ((cs.overflow === 'hidden' || cs.textOverflow === 'ellipsis' || (cs.webkitLineClamp && cs.webkitLineClamp !== 'none')) && text && el.clientHeight > 0) {
        if (el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1) {
          if (!el.classList.contains('win') && !el.matches('.prev,.list,.spage,.obody,.detail,.dpage')) out.trunc.push(text);
        }
      }
      if (el.matches('.prev,.list,.spage,.obody,.detail,.dpage') && el.scrollHeight > el.clientHeight + 1) out.scroll.push(el.className.split(' ')[0]);
      const hasText = Array.from(el.childNodes).some((n) => n.nodeType === 3 && n.textContent.trim());
      if (hasText) {
        let clip = el.parentElement;
        while (clip && clip !== win && !['hidden', 'auto', 'scroll'].includes(getComputedStyle(clip).overflowX)) clip = clip.parentElement;
        const r = el.getBoundingClientRect(), cr = (clip || win).getBoundingClientRect();
        if (r.right > cr.right + 1 || r.left < cr.left - 1) out.spill.push(text);
      }
      if (el.matches('button,[role=switch],[role=checkbox],[role=radio],input')) {
        const r = el.getBoundingClientRect();
        if (r.width && (r.height < 16 || r.width < 16) && !el.closest('.lights')) out.targets.push(`${el.tagName}:${Math.round(r.width)}x${Math.round(r.height)}:${text}`);
      }
    });
    out.primaries = Array.from(win.querySelectorAll('.btn.pri')).filter((b) => !b.closest('.mock')).length;
    const basics = win.cloneNode(true);
    basics.querySelectorAll('[aria-expanded=true] ~ .group, .mock, input').forEach((n) => n.remove());
    const words = basics.textContent;
    const m = words.match(new RegExp(JARGON.source, 'gi'));
    if (m) out.jargon = Array.from(new Set(m));
    let pre = document.getElementById('audit');
    if (!pre) { pre = document.createElement('pre'); pre.id = 'audit'; document.body.appendChild(pre); }
    pre.textContent = JSON.stringify(out);
  }

  window.LINTEL = { COPY, INDEX, S, render };
  document.addEventListener('DOMContentLoaded', render);
})();
