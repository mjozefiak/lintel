/* Lintel post-meeting actions: clickable prototype, iteration 3 (2026-11-26).
   Built on the accepted direction sketch (.ai/prototypes/lintel-direction, owner decisions 2026-11-24): notes explorer,
   working ring, warm neutrals, Verdigris only on the primary button, the selection and live state.
   Query: ?screen=note|inbox|apps|after  &pop=<action id: open the task hover card>  &tab=notes|actions|mine|transcript  &state=ready|finding|none|done|errors|offline  &phase=proc|ready  &after=stay|dot|none
          &mail=acct|mcp|nomail  &theme=light|dark  &lang=en|pl  &ts=m|l|xl  &chrome=0  &sel=<action id>
   All names, addresses and data are fictional. Nothing here is a decision until the owner picks it (see README). */
(function () {
  'use strict';

  const COPY = {
    en: {
      bar: { screen: 'Screen', note: 'Meeting note', inbox: 'Actions inbox', apps: 'Connected apps', after: 'After the meeting', layout: 'Where (Q3)', tab: 'Tab', inline: 'In Notes', inboxL: 'Tab + inbox', state: 'State', ready: 'Ready', finding: 'Finding', none: 'None found', done: 'All done', errors: 'Errors', offline: 'Not connected', mail: 'Account (Q1, Q2 decided)', acct: 'Google/Microsoft', mcp: 'Connector (MCP)', nomail: 'No account', theme: 'Theme', light: 'Light', dark: 'Dark', lang: 'Language' },
      me: 'Anna Nowak', meMail: 'anna.nowak@brightline.example',
      searchNotes: 'Search notes', record: 'Record Meeting', settings: 'Settings',
      nav: { all: 'All notes', meetings: 'Meetings', dictations: 'Dictations', actions: 'Actions', folders: 'Folders', newFolder: 'New Folder', dictionary: 'Dictionary' },
      folders: [['clients', 'Clients'], ['recruiting', 'Recruiting']],
      groups: ['Today', 'Yesterday', 'Friday'],
      items: [
        { id: 'nordlys', k: 'meeting', t: 'Client call: Nordlys Energy', m: 'Meeting · 42 min', w: '11:30', g: 0 },
        { id: 'sync', k: 'meeting', t: 'Weekly sales sync', m: 'Meeting · 28 min', w: '9:00', g: 0 },
        { id: 'marta', k: 'dictation', t: 'Email to Marta about the Q4 budget', m: 'Dictation · 118 words', w: '16:10', g: 1 },
        { id: 'interview', k: 'meeting', t: 'Interview: product designer', m: 'Meeting · 35 min', w: '13:00', g: 1 },
        { id: 'board', k: 'dictation', t: 'Notes for the board update', m: 'Dictation · 240 words', w: '10:15', g: 2 }
      ],
      acts: (n) => (n === 1 ? '1 action' : `${n} actions`), waiting: (n) => `${n} to review`, finding: 'Finding actions…',
      note: {
        meta: 'Today, 11:30 · 42 min · You, Marek Lis, Ingrid Halvorsen', onMac: 'On this Mac', open: 'Open', copy: 'Copy',
        tabs: { notes: 'Notes', actions: 'Actions', mine: 'My notes', transcript: 'Transcript' },
        sumH: 'Summary', sum: 'Nordlys accepts the price if work starts in January. Ingrid needs the service levels in writing before she signs.',
        decH: 'Decisions', dec: ['Work starts on 12 January.', 'The price stays as quoted, with no discount.'],
        taskH: 'Tasks', tasks: [['You', 'Send Ingrid a recap', 'today', 'a1'], ['You', 'Set up the kick-off on 12 January', '', 'a2'], ['Marek Lis', 'Write up the service levels', 'by Wednesday', 'a3'], ['You', 'Send the contract draft to Nordlys’ lawyer', '', 'a4'], ['You or Marek Lis', 'Book a room in Bergen for the workshop', '', 'a5'], ['Ingrid Halvorsen', 'Confirm the start date with her board', '']],
        toActions: (n) => `Lintel prepared ${n} actions from this meeting.`, review: 'Review Actions',
        foot: 'Lintel wrote these notes from the recording, on this Mac.',
        mine: ['Ingrid OK with the price if we start in Jan', 'Ask Marek about the wording of the service levels'],
        mineHelp: 'Only you write here. Lintel never changes these notes.',
        tr: [['You', 'Thanks for making time, Ingrid. Shall we start with the price?'], ['Ingrid Halvorsen', 'Yes. We can accept it if you can start in January.'], ['You', 'January works. Let’s put the kick-off on the 12th at ten, with Marek.', 'a2'], ['Marek Lis', 'I’ll write up the service levels by Wednesday.', 'a3'], ['Ingrid Halvorsen', 'Please send the contract draft to our lawyer, olsen@fjordlaw.example.', 'a4'], ['?', 'I’ll book a room in Bergen for the workshop.', 'a5'], ['You', 'Great. I’ll send you a short recap today.', 'a1']],
        unsure: 'You or Marek Lis'
      },
      sync: { meta: 'Today, 9:00 · 28 min · You, Marek Lis, Ola Berg', sum: 'Pipeline is on track for Q4. The CRM export bug slows down the weekly report.', dec: ['The Q4 forecast is due on Monday.'], tasks: [['You', 'Log the CRM export bug for the CRM team', '', 's1'], ['You', 'Block time for the Q4 forecast', 'Friday', 's2']] },
      a: {
        hdr: (n, w) => (w ? `${n} actions · ${w} need you` : `${n} actions`), hdrSub: 'Check each one, then approve it.',
        allDone: 'All done', allDoneSub: (d, x) => `${d} done${x ? `, ${x} dismissed` : ''}. Changes in Lintel don’t change what was sent.`,
        trust: 'Nothing is sent, booked or created until you click.',
        st: { ready: 'Ready', need: 'Needs you', sending: 'Sending…', dismissed: 'Dismissed', failed: 'Didn’t go through', disconnected: 'Not connected', expired: 'Sign in again' },
        doneSt: { mail: 'Sent', event: 'Added', jira: 'Created', linear: 'Created' },
        said: (w) => `${w}:`, unsureWho: 'You or Marek Lis:', showTr: 'Show in Transcript',
        k: { to: 'To', cc: 'Cc', subject: 'Subject', body: 'Message', title: 'Title', when: 'When', guests: 'Guests', where: 'Where', desc: 'Description', cal: 'Calendar', project: 'Project', type: 'Type', summary: 'Summary', assignee: 'Assignee', due: 'Due', team: 'Team', priority: 'Priority', component: 'Component' },
        addTo: 'Add a recipient', addGuest: 'Add a guest',
        approve: { mail: 'Send', event: 'Add to Calendar', eventGuests: (n) => `Add and Invite ${n} People`, jira: 'Create in Jira', linear: 'Create in Linear' },
        draft: 'Open as Draft', dismiss: 'Dismiss', restore: 'Restore', retry: 'Try Again', undo: 'Undo',
        keys: [['⌘↩', 'approve'], ['⌘⌫', 'dismiss']],
        sendAs: (m) => `Sends from ${m} (Google).`, mcpAs: 'Sends through your mail connector, as you.', draftOnly: 'No mail account is connected, so this opens as a draft in your mail app.', connectMail: 'Connect Google or Microsoft',
        calAs: 'Google sends the invitations from your account.', calMcp: 'Through your calendar connector. Invitations come from your account.', calIcs: 'No Google or Microsoft account: the event goes to Calendar on this Mac and the invitation opens as an email draft with an .ics file. Replies won’t update the event.', icsBtn: 'Add and Draft Invitation', calMine: 'Goes to Calendar on this Mac. No one else is invited.',
        jiraAs: 'Created in brightline.atlassian.net as you.', linAs: 'Through Linear’s connector. Linear gets exactly these fields.',
        edited: 'Edited',
        res: {
          mail: (t) => `Sent at ${t} · Open in Gmail`, event: (n) => (n ? `Added to Work · ${n} invitations sent · Open in Calendar` : 'Added to Calendar on this Mac · Open in Calendar'),
          jira: 'Created SALES-142 · Open in Jira', linear: 'Created CRM-88 · Open in Linear', dismissed: 'Dismissed'
        },
        toast: { mail: (s) => `Sending in ${s} s`, event: 'Added to Calendar', jira: 'Created in Jira', linear: 'Created in Linear', dismissed: 'Action dismissed' },
        guardT: (w) => `${w} asked for this`, guardS: 'Lintel doesn’t copy addresses or links from other people’s words. Check who should get this email.',
        guardHint: 'She said an address. Type it here if it’s right.', needTo: 'Add who gets this email.',
        needWho: 'Choose who will do it.', unsureT: 'Lintel isn’t sure who said this', unsureS: 'You and Marek Lis were on the same microphone. Who will do it?', notTask: 'No one, dismiss',
        errMail: ['No internet connection', 'The email is kept here. Send it when you’re back online.'],
        errJira: ['Jira needs a component for this project', 'Pick one below and try again.'],
        discJira: ['Jira isn’t connected', 'Connect it to create this ticket. The draft stays here.'], connect: 'Connect Jira…', copyTxt: 'Copy Text',
        expired: ['Your Google sign-in expired', 'Sign in again to send this. Nothing was sent.'], signIn: 'Sign In Again',
        findT: 'Finding actions in this meeting…', findS: 'You can keep working. Lintel lets you know when they’re ready.',
        noneT: 'No actions in this meeting', noneS: 'Lintel didn’t hear an email to send, a meeting to set up or a ticket to create. Your tasks are in Notes.', showNotes: 'Show Notes',
        inlineH: 'Ready to do', inActions: 'Show in Actions', popVia: { mail: 'Email', event: 'Calendar', jira: 'Jira ticket', linear: 'Linear issue' }, taskHint: 'Point at a task to see the action Lintel prepared.'
      },
      A: {
        a1: { type: 'mail', by: 'You', t: 'Email Ingrid a recap', q: 'Great. I’ll send you a short recap today.',
          to: [['Ingrid Halvorsen', 'ingrid.halvorsen@nordlys.example']], subject: 'Recap: we start on 12 January',
          body: 'Hi Ingrid,\n\nThanks for today. A short recap:\n– We start on 12 January.\n– The price stays as quoted.\n– Marek sends you the service levels by Wednesday.\n\nI’ve also sent you an invite for the kick-off.\n\nBest,\nAnna' },
        a2: { type: 'event', by: 'You', t: 'Set up the kick-off on 12 January', q: 'January works. Let’s put the kick-off on the 12th at ten, with Marek.',
          title: 'Kick-off: Nordlys Energy', when: 'Mon 12 Jan 2027', time: '10:00 – 11:00', guests: [['Ingrid Halvorsen', 'ingrid.halvorsen@nordlys.example'], ['Marek Lis', 'marek.lis@brightline.example']], where: 'Google Meet', cal: 'Work',
          desc: 'Start of the Nordlys Energy project: plan, service levels, who does what in January.' },
        a3: { type: 'jira', by: 'Marek Lis', t: 'Ticket: write up the service levels', q: 'I’ll write up the service levels by Wednesday.',
          project: 'SALES · Sales ops', itype: 'Task', summary: 'Write up the service levels for Nordlys Energy', assignee: 'Marek Lis', due: 'Wed 2 Dec',
          desc: 'Nordlys Energy needs the service levels in writing before Ingrid Halvorsen signs.' },
        a4: { type: 'mail', by: 'Ingrid Halvorsen', guard: true, t: 'Email the contract draft to Nordlys’ lawyer', q: 'Please send the contract draft to our lawyer, olsen@fjordlaw.example.',
          to: [], subject: 'Contract draft: Nordlys Energy', body: 'Hello,\n\nIngrid Halvorsen asked me to send you the contract draft for the work starting on 12 January. I’ll attach it before sending.\n\nBest regards,\nAnna Nowak' },
        a5: { type: 'jira', by: '?', unsure: true, t: 'Ticket: book a room in Bergen for the workshop', q: 'I’ll book a room in Bergen for the workshop.',
          project: 'SALES · Sales ops', itype: 'Task', summary: 'Book a room in Bergen for the Nordlys workshop', assignee: '', due: '',
          desc: 'Room for the January workshop with Nordlys Energy in Bergen.' },
        s1: { type: 'linear', by: 'You', t: 'Issue: CRM export drops the last row', q: 'I’ll log the export bug for the CRM team.',
          team: 'CRM', summary: 'CSV export drops the last row', priority: 'High', desc: 'Seen by sales twice this week. Steps: export any list with more than 100 rows.' },
        s2: { type: 'event', by: 'You', mine: true, t: 'Block 2 hours for the Q4 forecast', q: 'I’ll block Friday morning for the forecast.',
          title: 'Q4 forecast (focus)', when: 'Fri 27 Nov', time: '9:00 – 11:00', guests: [], where: '', cal: 'Calendar on this Mac', desc: '' }
      },
      inbox: { t: 'Actions', s: 'Everything Lintel prepared after your meetings, in one place.', empty: 'Nothing to review' },
      after: {
        procHover: ['Writing notes', 'Finding actions'], ready: (n) => n ? `Ready · ${n} actions` : 'Ready', open: 'Open', close: 'Close', replay: 'Play again', phaseL: 'Pill', proc: 'Processing', readyL: 'Ready', afterL: 'After the pill (Q15)', stay: 'Stays until closed', dot: '8 s, then a dot on the ring', none: '8 s, nothing',
        cap2: 'P10 (owner): after the audio is saved, the pill shows only the closing ring (#273, OD-9; hover: what it is doing). When the notes AND the actions are ready it turns into “Ready · 5 actions · Open”; the meeting row and the Actions inbox show the count. No macOS notification. Open goes to the meeting’s Notes. What stays after the pill is Q15 (toolbar).',
        notifT: '5 actions ready', notifS: 'Client call: Nordlys Energy · 2 need you', notifB: 'Review', now: 'now',
        menu: [['Record Meeting', '⌃⌥M'], ['Actions to review', '5'], ['Open Lintel', ''], ['Settings…', '⌘,']],
        cap: 'Q6: how you learn that actions are ready. Shown here: one macOS notification per meeting, and a dot on the menu bar ring while something waits. The list row also says “5 to review”.'
      },
      set: {
        side: { general: 'General', dictation: 'Dictation', meetings: 'Meetings & notes', ai: 'AI assistant', apps: 'Connected apps', privacy: 'Privacy & data', addons: 'Add-ons', about: 'About & help' },
        lead: 'After a meeting, Lintel prepares emails, invites and tickets in these apps. Nothing is sent until you approve it.',
        mailH: 'Email and calendar', toolsH: 'Work tools',
        google: ['Google', 'anna.nowak@brightline.example · sends the emails and invites you approve'],
        ms: ['Microsoft 365', 'Outlook mail and calendar'], mailMcp: ['Other mail', 'Through a connector from Lintel’s list'], macCal: ['Calendar on this Mac', 'Events just for you, without guests'],
        jira: ['Jira', 'brightline.atlassian.net · your key is kept in your keychain'], linear: ['Linear', 'Through Linear’s own connector'], asana: ['Asana', 'Through Asana’s own connector'],
        connected: 'Connected', allowed: 'Allowed', notConn: 'Not connected', connect: 'Connect…', disconnect: 'Disconnect', remove: 'Remove',
        missing: 'Missing an app? Tell us which one.',
        foot: 'Actions are found by the assistant that writes your notes: This Mac. Change it in AI assistant.'
      }
    },
    pl: {
      bar: { screen: 'Ekran', note: 'Notatka ze spotkania', inbox: 'Skrzynka akcji', apps: 'Połączone aplikacje', after: 'Po spotkaniu', layout: 'Gdzie (P3)', tab: 'Zakładka', inline: 'W Notatkach', inboxL: 'Zakładka + skrzynka', state: 'Stan', ready: 'Gotowe', finding: 'Szukanie', none: 'Brak', done: 'Wszystko zrobione', errors: 'Błędy', offline: 'Bez połączenia', mail: 'Konto (P1, P2 zdecydowane)', acct: 'Google/Microsoft', mcp: 'Łącznik (MCP)', nomail: 'Bez konta', theme: 'Motyw', light: 'Jasny', dark: 'Ciemny', lang: 'Język' },
      me: 'Anna Nowak', meMail: 'anna.nowak@brightline.example',
      searchNotes: 'Szukaj w notatkach', record: 'Nagraj spotkanie', settings: 'Ustawienia',
      nav: { all: 'Wszystkie notatki', meetings: 'Spotkania', dictations: 'Dyktowania', actions: 'Akcje', folders: 'Foldery', newFolder: 'Nowy folder', dictionary: 'Słownik' },
      folders: [['clients', 'Klienci'], ['recruiting', 'Rekrutacja']],
      groups: ['Dzisiaj', 'Wczoraj', 'Piątek'],
      items: [
        { id: 'nordlys', k: 'meeting', t: 'Rozmowa z klientem: Nordlys Energy', m: 'Spotkanie · 42 min', w: '11:30', g: 0 },
        { id: 'sync', k: 'meeting', t: 'Cotygodniowy sync sprzedaży', m: 'Spotkanie · 28 min', w: '9:00', g: 0 },
        { id: 'marta', k: 'dictation', t: 'Mail do Marty o budżecie na Q4', m: 'Dyktowanie · 118 słów', w: '16:10', g: 1 },
        { id: 'interview', k: 'meeting', t: 'Rozmowa rekrutacyjna: projektant produktu', m: 'Spotkanie · 35 min', w: '13:00', g: 1 },
        { id: 'board', k: 'dictation', t: 'Notatki do raportu dla zarządu', m: 'Dyktowanie · 240 słów', w: '10:15', g: 2 }
      ],
      acts: (n) => (n === 1 ? '1 akcja' : n < 5 ? `${n} akcje` : `${n} akcji`), waiting: (n) => `${n} do sprawdzenia`, finding: 'Szukam akcji…',
      note: {
        meta: 'Dzisiaj, 11:30 · 42 min · Ty, Marek Lis, Ingrid Halvorsen', onMac: 'Na tym Macu', open: 'Otwórz', copy: 'Kopiuj',
        tabs: { notes: 'Notatki', actions: 'Akcje', mine: 'Moje notatki', transcript: 'Transkrypt' },
        sumH: 'Podsumowanie', sum: 'Nordlys akceptuje cenę, jeśli prace ruszą w styczniu. Ingrid potrzebuje poziomów usług na piśmie, zanim podpisze.',
        decH: 'Decyzje', dec: ['Prace startują 12 stycznia.', 'Cena zostaje jak w ofercie, bez rabatu.'],
        taskH: 'Zadania', tasks: [['Ty', 'Wysłać Ingrid podsumowanie', 'dziś', 'a1'], ['Ty', 'Umówić spotkanie startowe 12 stycznia', '', 'a2'], ['Marek Lis', 'Spisać poziomy usług', 'do środy', 'a3'], ['Ty', 'Wysłać projekt umowy prawnikowi Nordlys', '', 'a4'], ['Ty albo Marek Lis', 'Zarezerwować salę w Bergen na warsztat', '', 'a5'], ['Ingrid Halvorsen', 'Potwierdzić termin startu z zarządem', '']],
        toActions: (n) => `Lintel przygotował z tego spotkania ${n} akcji.`, review: 'Sprawdź akcje',
        foot: 'Lintel napisał te notatki z nagrania, na tym Macu.',
        mine: ['Ingrid OK z ceną, jeśli start w styczniu', 'Zapytać Marka o brzmienie poziomów usług'],
        mineHelp: 'Tu piszesz tylko Ty. Lintel nigdy nie zmienia tych notatek.',
        tr: [['Ty', 'Dzięki, że znalazłaś czas, Ingrid. Zaczniemy od ceny?'], ['Ingrid Halvorsen', 'Tak. Przyjmiemy ją, jeśli zaczniecie w styczniu.'], ['Ty', 'Styczeń pasuje. Umówmy start na dwunastego o dziesiątej, z Markiem.', 'a2'], ['Marek Lis', 'Spiszę poziomy usług do środy.', 'a3'], ['Ingrid Halvorsen', 'Proszę wysłać projekt umowy naszemu prawnikowi, olsen@fjordlaw.example.', 'a4'], ['?', 'Zarezerwuję salę w Bergen na warsztat.', 'a5'], ['Ty', 'Świetnie. Wyślę Ci dziś krótkie podsumowanie.', 'a1']],
        unsure: 'Ty albo Marek Lis'
      },
      sync: { meta: 'Dzisiaj, 9:00 · 28 min · Ty, Marek Lis, Ola Berg', sum: 'Lejek sprzedaży na Q4 idzie zgodnie z planem. Błąd eksportu z CRM spowalnia cotygodniowy raport.', dec: ['Prognoza Q4 do poniedziałku.'], tasks: [['Ty', 'Zgłosić zespołowi CRM błąd eksportu', '', 's1'], ['Ty', 'Zablokować czas na prognozę Q4', 'piątek', 's2']] },
      a: {
        hdr: (n, w) => (w ? `Akcje: ${n} · ${w} czeka na Ciebie` : `Akcje: ${n}`), hdrSub: 'Sprawdź każdą i zatwierdź.',
        allDone: 'Wszystko zrobione', allDoneSub: (d, x) => `Zrobione: ${d}${x ? `, odrzucone: ${x}` : ''}. Zmiany w Lintelu nie zmieniają tego, co już wysłano.`,
        trust: 'Nic nie zostanie wysłane, umówione ani założone, dopóki nie klikniesz.',
        st: { ready: 'Gotowe', need: 'Czeka na Ciebie', sending: 'Wysyłam…', dismissed: 'Odrzucone', failed: 'Nie udało się', disconnected: 'Brak połączenia', expired: 'Zaloguj się ponownie' },
        doneSt: { mail: 'Wysłane', event: 'Dodane', jira: 'Założone', linear: 'Założone' },
        said: (w) => `${w}:`, unsureWho: 'Ty albo Marek Lis:', showTr: 'Pokaż w transkrypcie',
        k: { to: 'Do', cc: 'DW', subject: 'Temat', body: 'Treść', title: 'Tytuł', when: 'Kiedy', guests: 'Goście', where: 'Gdzie', desc: 'Opis', cal: 'Kalendarz', project: 'Projekt', type: 'Typ', summary: 'Tytuł', assignee: 'Osoba', due: 'Termin', team: 'Zespół', priority: 'Priorytet', component: 'Komponent' },
        addTo: 'Dodaj odbiorcę', addGuest: 'Dodaj gościa',
        approve: { mail: 'Wyślij', event: 'Dodaj do kalendarza', eventGuests: (n) => `Dodaj i zaproś ${n} osoby`, jira: 'Załóż w Jirze', linear: 'Załóż w Linear' },
        draft: 'Otwórz jako szkic', dismiss: 'Odrzuć', restore: 'Przywróć', retry: 'Spróbuj ponownie', undo: 'Cofnij',
        keys: [['⌘↩', 'zatwierdź'], ['⌘⌫', 'odrzuć']],
        sendAs: (m) => `Wysyłka z ${m} (Google).`, mcpAs: 'Wysyłka przez Twój łącznik poczty, jako Ty.', draftOnly: 'Nie masz połączonej poczty, więc mail otworzy się jako szkic w Twojej aplikacji pocztowej.', connectMail: 'Połącz Google lub Microsoft',
        calAs: 'Zaproszenia wyśle Google z Twojego konta.', calMcp: 'Przez Twój łącznik kalendarza. Zaproszenia przyjdą z Twojego konta.', calIcs: 'Bez konta Google ani Microsoft: wydarzenie trafi do Kalendarza na tym Macu, a zaproszenie otworzy się jako szkic maila z plikiem .ics. Odpowiedzi gości nie zaktualizują wydarzenia.', icsBtn: 'Dodaj i przygotuj zaproszenie', calMine: 'Trafi do Kalendarza na tym Macu. Nikt inny nie jest zapraszany.',
        jiraAs: 'Zakładane w brightline.atlassian.net jako Ty.', linAs: 'Przez łącznik Linear. Linear dostaje dokładnie te pola.',
        edited: 'Zmienione',
        res: {
          mail: (t) => `Wysłano o ${t} · Otwórz w Gmailu`, event: (n) => (n ? `Dodano do kalendarza Praca · wysłano zaproszenia: ${n} · Otwórz w Kalendarzu` : 'Dodano do Kalendarza na tym Macu · Otwórz w Kalendarzu'),
          jira: 'Założono SALES-142 · Otwórz w Jirze', linear: 'Założono CRM-88 · Otwórz w Linear', dismissed: 'Odrzucone'
        },
        toast: { mail: (s) => `Wysyłka za ${s} s`, event: 'Dodano do kalendarza', jira: 'Założono w Jirze', linear: 'Założono w Linear', dismissed: 'Akcja odrzucona' },
        guardT: (w) => `Prosi o to ${w}`, guardS: 'Lintel nie przepisuje adresów ani linków ze słów innych osób. Sprawdź, kto ma dostać ten mail.',
        guardHint: 'Padł adres. Wpisz go tu, jeśli się zgadza.', needTo: 'Dodaj, kto ma dostać ten mail.',
        needWho: 'Wybierz, kto to zrobi.', unsureT: 'Lintel nie wie, kto to powiedział', unsureS: 'Ty i Marek Lis mówiliście do jednego mikrofonu. Kto to zrobi?', notTask: 'Nikt, odrzuć',
        errMail: ['Brak internetu', 'Mail czeka tutaj. Wyślij go, gdy wróci połączenie.'],
        errJira: ['Jira wymaga komponentu w tym projekcie', 'Wybierz go poniżej i spróbuj ponownie.'],
        discJira: ['Jira nie jest połączona', 'Połącz ją, żeby założyć ten ticket. Szkic zostaje tutaj.'], connect: 'Połącz Jirę…', copyTxt: 'Kopiuj tekst',
        expired: ['Logowanie do Google wygasło', 'Zaloguj się ponownie, żeby to wysłać. Nic nie zostało wysłane.'], signIn: 'Zaloguj się ponownie',
        findT: 'Szukam akcji w tym spotkaniu…', findS: 'Możesz dalej pracować. Lintel da znać, gdy będą gotowe.',
        noneT: 'Brak akcji w tym spotkaniu', noneS: 'Lintel nie usłyszał maila do wysłania, spotkania do umówienia ani ticketu do założenia. Twoje zadania są w Notatkach.', showNotes: 'Pokaż notatki',
        inlineH: 'Gotowe do zrobienia', inActions: 'Pokaż w Akcjach', popVia: { mail: 'Mail', event: 'Kalendarz', jira: 'Ticket w Jirze', linear: 'Zgłoszenie w Linear' }, taskHint: 'Najedź na zadanie, żeby zobaczyć akcję przygotowaną przez Lintel.'
      },
      A: {
        a1: { type: 'mail', by: 'Ty', t: 'Mail do Ingrid z podsumowaniem', q: 'Świetnie. Wyślę Ci dziś krótkie podsumowanie.',
          to: [['Ingrid Halvorsen', 'ingrid.halvorsen@nordlys.example']], subject: 'Podsumowanie: startujemy 12 stycznia',
          body: 'Cześć Ingrid,\n\ndziękuję za dzisiejszą rozmowę. Krótko podsumowuję:\n– startujemy 12 stycznia,\n– cena zostaje jak w ofercie,\n– Marek prześle Ci poziomy usług do środy.\n\nWysłałam też zaproszenie na spotkanie startowe.\n\nPozdrawiam\nAnna' },
        a2: { type: 'event', by: 'Ty', t: 'Spotkanie startowe 12 stycznia', q: 'Styczeń pasuje. Umówmy start na dwunastego o dziesiątej, z Markiem.',
          title: 'Start projektu: Nordlys Energy', when: 'pon. 12 sty 2027', time: '10:00 – 11:00', guests: [['Ingrid Halvorsen', 'ingrid.halvorsen@nordlys.example'], ['Marek Lis', 'marek.lis@brightline.example']], where: 'Google Meet', cal: 'Praca',
          desc: 'Start projektu Nordlys Energy: plan, poziomy usług, kto co robi w styczniu.' },
        a3: { type: 'jira', by: 'Marek Lis', t: 'Ticket: spisać poziomy usług', q: 'Spiszę poziomy usług do środy.',
          project: 'SALES · Sales ops', itype: 'Zadanie', summary: 'Spisać poziomy usług dla Nordlys Energy', assignee: 'Marek Lis', due: 'śr. 2 gru',
          desc: 'Nordlys Energy potrzebuje poziomów usług na piśmie, zanim Ingrid Halvorsen podpisze.' },
        a4: { type: 'mail', by: 'Ingrid Halvorsen', guard: true, t: 'Mail z projektem umowy do prawnika Nordlys', q: 'Proszę wysłać projekt umowy naszemu prawnikowi, olsen@fjordlaw.example.',
          to: [], subject: 'Projekt umowy: Nordlys Energy', body: 'Dzień dobry,\n\nIngrid Halvorsen poprosiła mnie o przesłanie projektu umowy na prace startujące 12 stycznia. Dołączę go przed wysłaniem.\n\nZ pozdrowieniami\nAnna Nowak' },
        a5: { type: 'jira', by: '?', unsure: true, t: 'Ticket: zarezerwować salę w Bergen na warsztat', q: 'Zarezerwuję salę w Bergen na warsztat.',
          project: 'SALES · Sales ops', itype: 'Zadanie', summary: 'Zarezerwować salę w Bergen na warsztat z Nordlys', assignee: '', due: '',
          desc: 'Sala na styczniowy warsztat z Nordlys Energy w Bergen.' },
        s1: { type: 'linear', by: 'Ty', t: 'Zgłoszenie: eksport z CRM gubi ostatni wiersz', q: 'Zgłoszę błąd eksportu zespołowi CRM.',
          team: 'CRM', summary: 'Eksport CSV gubi ostatni wiersz', priority: 'Wysoki', desc: 'Sprzedaż trafiła na to dwa razy w tym tygodniu. Kroki: wyeksportuj dowolną listę z ponad 100 wierszami.' },
        s2: { type: 'event', by: 'Ty', mine: true, t: 'Zablokować 2 godziny na prognozę Q4', q: 'Zablokuję sobie piątkowy poranek na prognozę.',
          title: 'Prognoza Q4 (skupienie)', when: 'pt. 27 lis', time: '9:00 – 11:00', guests: [], where: '', cal: 'Kalendarz na tym Macu', desc: '' }
      },
      inbox: { t: 'Akcje', s: 'Wszystko, co Lintel przygotował po Twoich spotkaniach, w jednym miejscu.', empty: 'Nic do sprawdzenia' },
      after: {
        procHover: ['Piszę notatki', 'Szukam akcji'], ready: (n) => n ? `Gotowe · ${n} akcji` : 'Gotowe', open: 'Otwórz', close: 'Zamknij', replay: 'Odtwórz jeszcze raz', phaseL: 'Pastylka', proc: 'Przetwarzanie', readyL: 'Gotowe', afterL: 'Po pastylce (P15)', stay: 'Zostaje do zamknięcia', dot: '8 s, potem kropka na pierścieniu', none: '8 s, nic',
        cap2: 'P10 (właściciel): po zapisaniu audio pastylka pokazuje tylko zamykający się pierścień (#273, OD-9; po najechaniu: co robi). Gdy notatki I akcje są gotowe, zmienia się w „Gotowe · 5 akcji · Otwórz”; wiersz spotkania i skrzynka Akcje pokazują licznik. Bez powiadomienia macOS. Otwórz prowadzi do Notatek spotkania. Co zostaje po pastylce: P15 (pasek u góry).',
        notifT: '5 akcji gotowych', notifS: 'Rozmowa z klientem: Nordlys Energy · 2 czekają na Ciebie', notifB: 'Sprawdź', now: 'teraz',
        menu: [['Nagraj spotkanie', '⌃⌥M'], ['Akcje do sprawdzenia', '5'], ['Otwórz Lintel', ''], ['Ustawienia…', '⌘,']],
        cap: 'P6: skąd wiesz, że akcje są gotowe. Tu: jedno powiadomienie macOS na spotkanie i kropka na pierścieniu w pasku menu, póki coś czeka. Wiersz na liście mówi też „5 do sprawdzenia”.'
      },
      set: {
        side: { general: 'Ogólne', dictation: 'Dyktowanie', meetings: 'Spotkania i notatki', ai: 'Asystent AI', apps: 'Połączone aplikacje', privacy: 'Prywatność i dane', addons: 'Dodatki', about: 'O programie i pomoc' },
        lead: 'Po spotkaniu Lintel przygotowuje maile, zaproszenia i tickety w tych aplikacjach. Nic nie zostanie wysłane, dopóki tego nie zatwierdzisz.',
        mailH: 'Poczta i kalendarz', toolsH: 'Narzędzia do pracy',
        google: ['Google', 'anna.nowak@brightline.example · wysyła zatwierdzone przez Ciebie maile i zaproszenia'],
        ms: ['Microsoft 365', 'Poczta i kalendarz Outlook'], mailMcp: ['Inna poczta', 'Przez łącznik z listy Lintela'], macCal: ['Kalendarz na tym Macu', 'Wydarzenia tylko dla Ciebie, bez gości'],
        jira: ['Jira', 'brightline.atlassian.net · klucz jest w Twoim pęku kluczy'], linear: ['Linear', 'Przez własny łącznik Linear'], asana: ['Asana', 'Przez własny łącznik Asany'],
        connected: 'Połączone', allowed: 'Dozwolone', notConn: 'Niepołączone', connect: 'Połącz…', disconnect: 'Odłącz', remove: 'Usuń',
        missing: 'Brakuje aplikacji? Napisz, której.',
        foot: 'Akcje znajduje ten sam asystent, który pisze notatki: Ten Mac. Zmienisz to w Asystencie AI.'
      }
    }
  };

  const P = {
    note: '<path d="M4 2.5h5.5L12.5 5.5V13a.5.5 0 0 1-.5.5H4a.5.5 0 0 1-.5-.5V3a.5.5 0 0 1 .5-.5Z"/><path d="M9.5 2.5v3h3M5.5 8.5h5M5.5 11h3.5"/>',
    stack: '<path d="M3 5.5h10M3 8.5h10M3 11.5h10"/>',
    book: '<path d="M3 3.2c1.8-.6 3.5-.4 5 .6v9.4c-1.5-1-3.2-1.2-5-.6ZM13 3.2c-1.8-.6-3.5-.4-5 .6v9.4c1.5-1 3.2-1.2 5-.6Z"/>',
    gear: '<circle cx="8" cy="8" r="2"/><path d="M8 1.8v1.7M8 12.5v1.7M1.8 8h1.7M12.5 8h1.7M3.6 3.6l1.2 1.2M11.2 11.2l1.2 1.2M3.6 12.4l1.2-1.2M11.2 4.8l1.2-1.2"/>',
    search: '<circle cx="7" cy="7" r="4.2"/><path d="m10.2 10.2 3.3 3.3"/>',
    check: '<path d="m3.5 8.3 3 3 6-6.6"/>', chevd: '<path d="m4 6 4 4 4-4"/>', chev: '<path d="m6 4 4 4-4 4"/>',
    folder: '<path d="M2.5 4.5a1 1 0 0 1 1-1h3l1.5 1.5h4.5a1 1 0 0 1 1 1V12a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1Z"/>',
    plus: '<path d="M8 3.5v9M3.5 8h9"/>', x: '<path d="m4.5 4.5 7 7M11.5 4.5l-7 7"/>',
    lock: '<rect x="3.5" y="7" width="9" height="6.5" rx="1"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/>',
    warn: '<path d="M8 2.5 14 13H2Z"/><path d="M8 6.5v3M8 11.2h.01"/>',
    copy: '<rect x="5" y="5" width="8" height="8.5" rx="1"/><path d="M3 10.5V3.5a1 1 0 0 1 1-1h6"/>',
    expand: '<path d="M9.5 2.5h4v4M13.5 2.5 9 7M6.5 13.5h-4v-4M2.5 13.5 7 9"/>',
    mail: '<rect x="2" y="3.5" width="12" height="9" rx="1.5"/><path d="m2.5 4.5 5.5 4.3 5.5-4.3"/>',
    cal: '<rect x="2.5" y="3.5" width="11" height="10" rx="1.5"/><path d="M2.5 6.8h11M5.5 2v2.8M10.5 2v2.8"/>',
    ticket: '<path d="M2.5 4.5h11v2a1.5 1.5 0 0 0 0 3v2h-11v-2a1.5 1.5 0 0 0 0-3Z"/><path d="M6 4.5v7" stroke-dasharray="1.2 1.4"/>',
    plug: '<path d="M6 2v3M10 2v3M4.5 5h7v2.5a3.5 3.5 0 0 1-7 0ZM8 11v3"/>',
    person: '<circle cx="8" cy="5.5" r="2.5"/><path d="M3 13.5c.6-2.6 2.6-4 5-4s4.4 1.4 5 4"/>',
    shield: '<path d="M8 2 13 4v4c0 3-2.2 5-5 6-2.8-1-5-3-5-6V4Z"/>',
    q: '<circle cx="8" cy="8" r="5.8"/><path d="M6.3 6.3a1.8 1.8 0 1 1 2.5 1.6c-.5.2-.8.6-.8 1.1v.4M8 11.3h.01"/>',
    undo: '<path d="M5.5 4 2.5 7l3 3"/><path d="M2.5 7h7a3.5 3.5 0 0 1 0 7H8"/>',
    out: '<path d="M9.5 2.5h4v4M13.5 2.5 8 8M11.5 9.5v3a1 1 0 0 1-1 1h-7a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1h3"/>',
    sliders: '<path d="M3 4.5h10M3 11.5h10"/><circle cx="6" cy="4.5" r="1.5"/><circle cx="10.5" cy="11.5" r="1.5"/>',
    mic: '<rect x="6" y="2" width="4" height="7.5" rx="2"/><path d="M3.5 8a4.5 4.5 0 0 0 9 0M8 12.5V14.5"/>',
    meeting: '<circle cx="5.5" cy="6" r="2"/><circle cx="11" cy="6.5" r="1.6"/><path d="M2 13c.4-2.2 1.8-3.3 3.5-3.3S8.6 10.8 9 13M9.6 10.4c.4-.3.9-.5 1.4-.5 1.4 0 2.4 1 2.8 3.1"/>',
    spark: '<path d="M8 2.5v3M8 10.5v3M2.5 8h3M10.5 8h3"/><circle cx="8" cy="8" r="1.6"/>',
    puzzle: '<path d="M3 5.5h2.5a1.5 1.5 0 1 1 3 0H11v2.5a1.5 1.5 0 1 1 0 3V13H3Z"/>',
    info: '<circle cx="8" cy="8" r="5.8"/><path d="M8 7.2v3.6M8 5.2h.01"/>',
    inbox: '<path d="M2.5 9.5 4 3.5h8l1.5 6v3a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1Z"/><path d="M2.5 9.5h3l1 1.5h3l1-1.5h3"/>'
  };
  const TYPE_IC = { mail: 'mail', event: 'cal', jira: 'ticket', linear: 'plug' };
  const RING = 'M99.01 19.82A112 112 0 1 1 19.82 99.01L64.25 110.92A66 66 0 1 0 110.92 64.25Z';
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const ic = (n, cls) => `<svg class="ic ${cls || ''}" viewBox="0 0 16 16" aria-hidden="true">${P[n] || ''}</svg>`;
  function ring(kind, size, p) {
    const s = `width="${size}" height="${size}"`, v = 'viewBox="0 0 256 256" aria-hidden="true"';
    if (kind === 'progress') { const full = 466, c = 559; return `<svg class="ring r-progress" ${s} ${v}><circle class="tr" cx="128" cy="128" r="89" stroke-dasharray="${full} ${c}" transform="rotate(255 128 128)"/><circle class="pg" cx="128" cy="128" r="89" stroke-dasharray="${(full * p).toFixed(1)} ${c}" transform="rotate(255 128 128)"/></svg>`; }
    if (kind === 'open') return `<svg class="ring r-open" ${s} ${v}><path class="op" d="${RING}"/></svg>`;
    const dot = kind === 'dictation' ? '' : '<circle class="rd" cx="128" cy="128" r="34"/>';
    return `<svg class="ring r-${kind}" ${s} ${v}><path class="rp" d="${RING}"/>${dot}</svg>`;
  }

  const qs = new URLSearchParams(location.search);
  const pick = (k, list, d) => (list.includes(qs.get(k)) ? qs.get(k) : d);
  const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const NORD = ['a1', 'a2', 'a3', 'a4', 'a5'], SYNC = ['s1', 's2'];
  const S = {
    screen: pick('screen', ['note', 'inbox', 'apps', 'after'], 'note'),
    layout: 'inbox', // Q3 decided: Actions tab + Actions inbox in the sidebar
    state: pick('state', ['ready', 'finding', 'none', 'done', 'errors', 'offline'], 'ready'),
    phase: pick('phase', ['proc', 'ready'], 'proc'), // P10: the pill after the recording
    after: pick('after', ['stay', 'dot', 'none'], 'stay'), // Q15 (open): what stays once the Ready pill is gone
    pillGone: false,
    mail: pick('mail', ['acct', 'mcp', 'nomail'], 'acct'),
    theme: pick('theme', ['light', 'dark'], prefersDark ? 'dark' : 'light'),
    lang: pick('lang', ['en', 'pl'], 'en'),
    ts: pick('ts', ['m', 'l', 'xl'], 'm'),
    chrome: qs.get('chrome') !== '0',
    item: pick('item', ['nordlys', 'sync'], 'nordlys'),
    tab: pick('tab', ['notes', 'actions', 'mine', 'transcript'], 'notes'), // Q4 decided: a meeting always opens on Notes
    pop: null,
    open: qs.get('sel') || 'a1',
    st: {}, edits: {}, who: {}, err: {}, toast: null, hlq: '', component: ''
  };
  if (S.screen === 'inbox') S.layout = 'inbox';
  const t = () => COPY[S.lang];
  const A = (id) => Object.assign({}, t().A[id], S.edits[id] || {});

  function applyState() {
    S.st = { a1: 'ready', a2: 'ready', a3: 'ready', a4: 'need', a5: 'need', s1: 'ready', s2: 'ready' };
    S.who = {}; S.err = {}; S.toast = null; S.component = '';
    if (S.state === 'done') Object.assign(S.st, { a1: 'done', a2: 'done', a3: 'done', a4: 'dismissed', a5: 'done' }), (S.who.a5 = 'me');
    if (S.state === 'errors') Object.assign(S.st, { a1: 'failed', a3: 'failed' }), (S.open = qs.get('sel') || 'a3');
    if (S.state === 'offline') Object.assign(S.st, { a1: 'expired', a2: 'expired', a3: 'disconnected' }), (S.open = qs.get('sel') || 'a3');
  }
  applyState();

  // ---------- helpers ----------
  const lights = () => '<span class="lights"><i></i><i></i><i></i></span>';
  const pop = (v) => `<button class="pop">${esc(v)}${ic('chevd')}</button>`;
  const ids = (item) => (item === 'sync' ? SYNC : NORD);
  const waiting = (item) => ids(item).filter((id) => ['ready', 'need', 'failed', 'expired', 'disconnected'].includes(S.st[id])).length;
  const needs = (item) => ids(item).filter((id) => ['need', 'failed', 'expired', 'disconnected'].includes(S.st[id])).length;
  const guestsOf = (a) => (a.guests || []).length;
  const whoName = (id, a) => {
    if (!a.unsure) return a.by;
    if (S.who[id] === 'me') return t().note.tasks[0][0];
    if (S.who[id] === 'marek') return 'Marek Lis';
    return null;
  };

  // ---------- main window ----------
  function sidebar(c) {
    const n = c.nav;
    const on = (k) => (S.screen === 'inbox' ? k === 'actions' : k === 'all');
    const it = (k, icn, label, num, cls) => `<button class="si ${on(k) ? 'on' : ''}" ${k === 'actions' ? 'data-go="inbox"' : k === 'all' ? 'data-go="note"' : ''}>${icn}<span>${label}</span>${num !== undefined ? `<span class="n ${cls || ''}">${num}</span>` : ''}</button>`;
    const w = waiting('nordlys') + waiting('sync');
    const actionsRow = S.layout === 'inbox' ? it('actions', ic('inbox'), n.actions, w || undefined, 'wait') : '';
    return `<aside class="side">${lights()}
      ${it('all', ic('stack'), n.all, 42)}${it('meetings', ring('meeting', 15), n.meetings, 18)}${it('dictations', ring('dictation', 15), n.dictations, 24)}${actionsRow}
      <div class="sh">${n.folders}</div>${c.folders.map(([k, l]) => it(k, ic('folder'), l, k === 'clients' ? 9 : 4)).join('')}
      <button class="si add">${ic('plus')}<span>${n.newFolder}</span></button><span class="sp"></span>
      <button class="si">${ic('book')}<span>${n.dictionary}</span><span class="n">12</span></button></aside>`;
  }
  function toolbar(c) {
    return `<div class="tb"><label class="field">${ic('search')}<input placeholder="${esc(c.searchNotes)}" aria-label="${esc(c.searchNotes)}"></label>
      <span class="sp"></span><button class="btn pri">${ring('mark', 15)}<span>${c.record}</span></button><button class="iconbtn" data-go="apps" aria-label="${esc(c.settings)}" title="${esc(c.settings)} (⌘,)">${ic('gear')}</button></div>`;
  }
  function rowMeta(c, x) {
    if (x.k !== 'meeting' || !['nordlys', 'sync'].includes(x.id)) return `<span class="m">${x.m}</span>`;
    if (x.id === 'nordlys' && S.state === 'finding') return `<span class="m">${x.m} · <span class="m work" style="display:inline">${c.finding}</span></span>`;
    if (x.id === 'nordlys' && S.state === 'none') return `<span class="m">${x.m}</span>`;
    const w = waiting(x.id);
    return `<span class="m">${x.m} · ${w ? c.waiting(w) : c.acts(ids(x.id).length)}</span>`;
  }
  function listCol(c) {
    let out = '', g = -1;
    for (const x of c.items) {
      if (x.g !== g) { g = x.g; out += `<div class="gl">${c.groups[g]}</div>`; }
      const on = S.item === x.id;
      const mark = x.id === 'nordlys' && S.state === 'finding' ? ring('progress', 15, 0.7) : ring(x.k, 15);
      out += `<button class="li ${on ? 'on' : ''}" ${['nordlys', 'sync'].includes(x.id) ? `data-item="${x.id}"` : ''} aria-current="${on}">${mark}<span class="tx"><span class="t">${x.t}</span>${rowMeta(c, x)}</span><span class="w">${x.w}</span></button>`;
    }
    return `<nav class="list" aria-label="${c.nav.all}">${out}</nav>`;
  }

  // ---------- one action ----------
  function statusLabel(c, id, a) {
    const s = S.st[id], L = c.a.st;
    if (s === 'done') return `<span class="stt done">${ic('check')}${c.a.doneSt[a.type]}</span>`;
    if (s === 'need') return `<span class="stt need">${L.need}</span>`;
    if (s === 'failed') return `<span class="stt fail">${L.failed}</span>`;
    if (s === 'disconnected' || s === 'expired') return `<span class="stt need">${L[s]}</span>`;
    if (s === 'sending') return `<span class="stt">${L.sending}</span>`;
    if (s === 'dismissed') return `<span class="stt">${L.dismissed}</span>`;
    return `<span class="stt">${L.ready}</span>`;
  }
  function subLine(c, id, a) {
    const k = c.a.k;
    if (a.type === 'mail') return a.to.length ? `${k.to}: ${a.to.map((p) => p[0]).join(', ')}` : `${k.to}: —`;
    if (a.type === 'event') return `${a.when}, ${a.time}${guestsOf(a) ? ` · ${guestsOf(a)} ${S.lang === 'pl' ? 'gości' : 'guests'}` : ''}`;
    if (a.type === 'jira') { const w = a.unsure ? whoName(id, a) : a.assignee; return `Jira · ${a.project.split(' · ')[0]}${w ? ` · ${w}` : ''}`; }
    return `Linear · ${a.team}`;
  }
  function evidence(c, id, a) {
    const w = a.unsure ? whoName(id, a) : a.by;
    const label = w ? c.a.said(w) : c.a.unsureWho;
    return `<div class="ev"><span class="who">${esc(label)}</span><span class="q">${S.lang === 'pl' ? '„' : '“'}${esc(a.q)}”</span>${S.screen === 'note' ? `<button class="link" data-tr="${id}">${c.a.showTr}</button>` : ''}</div>`;
  }
  const field = (id, key, val, ph, req) => `<input class="in2 ${req ? 'req' : ''}" data-edit="${id}" data-key="${key}" value="${esc(val)}" placeholder="${esc(ph || '')}" aria-label="${esc(ph || key)}">`;
  const area = (id, key, val, rows) => `<textarea class="in2 ${(rows || 7) <= 3 ? 'short' : ''}" data-edit="${id}" data-key="${key}" rows="${rows || 7}" aria-label="${key}">${esc(val)}</textarea>`;
  const people = (list, ph, req) => `<div class="chips ${req ? 'req' : ''}">${list.map(([n, m]) => `<span class="pchip">${esc(n)} <span class="em">${esc(m)}</span><button class="iconbtn" style="width:18px;height:18px" aria-label="Remove ${esc(n)}">${ic('x')}</button></span>`).join('')}<input placeholder="${esc(ph)}" aria-label="${esc(ph)}"></div>`;

  function form(c, id, a) {
    const k = c.a.k;
    if (a.type === 'mail') {
      const need = a.guard && !a.to.length;
      return `<div class="fg"><span class="k">${k.to}</span><div>${people(a.to, c.a.addTo, need && S.err[id] === 'to')}${need ? `<div class="hint ${S.err[id] === 'to' ? 'warn' : ''}" style="margin-top:4px">${S.err[id] === 'to' ? c.a.needTo : c.a.guardHint}</div>` : ''}</div>
        <span class="k">${k.subject}</span>${field(id, 'subject', a.subject)}
        <span class="k top">${k.body}</span>${area(id, 'body', a.body, 9)}</div>`;
    }
    if (a.type === 'event') {
      return `<div class="fg"><span class="k">${k.title}</span>${field(id, 'title', a.title)}
        <span class="k">${k.when}</span><div class="two">${pop(a.when)}${pop(a.time)}</div>
        ${a.mine ? '' : `<span class="k">${k.guests}</span>${people(a.guests, c.a.addGuest)}${S.mail === 'nomail' ? '' : `<span class="k">${k.where}</span><div class="two">${pop(a.where)}</div>`}`}
        ${a.desc ? `<span class="k top">${k.desc}</span>${area(id, 'desc', a.desc, 3)}` : ''}
        <span class="k">${k.cal}</span><div class="two">${pop(S.mail === 'nomail' && !a.mine ? t().set.macCal[0] : a.cal)}</div></div>`;
    }
    if (a.type === 'jira') {
      const who = a.unsure ? whoName(id, a) || '' : a.assignee;
      const comp = S.st[id] === 'failed' ? `<span class="k">${k.component}</span><div class="two"><button class="pop" style="box-shadow:0 0 0 1.5px var(--danger)" data-act="component" data-id="${id}">${S.component || (S.lang === 'pl' ? 'Wybierz…' : 'Choose…')}${ic('chevd')}</button></div>` : '';
      return `<div class="fg"><span class="k">${k.project}</span><div class="two">${pop(a.project)}${pop(a.itype)}</div>${comp}
        <span class="k">${k.summary}</span>${field(id, 'summary', a.summary)}
        <span class="k">${k.assignee}</span><div class="two">${pop(who || (S.lang === 'pl' ? 'Nieprzypisane' : 'Unassigned'))}${a.due ? pop(a.due) : `<span class="hint">${k.due}: —</span>`}</div>
        <span class="k top">${k.desc}</span>${area(id, 'desc', a.desc, 3)}</div>`;
    }
    return `<div class="fg"><span class="k">${k.team}</span><div class="two">${pop(a.team)}${pop(a.priority)}</div>
      <span class="k">${k.summary}</span>${field(id, 'summary', a.summary)}
      <span class="k top">${k.desc}</span>${area(id, 'desc', a.desc, 3)}</div>`;
  }
  function viaLine(c, a) {
    if (a.type === 'mail') return S.mail === 'nomail' ? `${c.a.draftOnly} <button class="link" data-go="apps" style="color:var(--ink)">${c.a.connectMail} ›</button>` : S.mail === 'mcp' ? c.a.mcpAs : c.a.sendAs(c.meMail);
    if (a.type === 'event') return a.mine || !guestsOf(a) ? c.a.calMine : S.mail === 'nomail' ? c.a.calIcs : S.mail === 'mcp' ? c.a.calMcp : c.a.calAs;
    if (a.type === 'jira') return c.a.jiraAs;
    return c.a.linAs;
  }
  function buttons(c, id, a) {
    const ap = c.a.approve;
    let label = a.type === 'mail' ? ap.mail : a.type === 'event' ? (guestsOf(a) ? ap.eventGuests(guestsOf(a)) : ap.event) : ap[a.type];
    if (a.type === 'mail' && S.mail === 'nomail') label = c.a.draft;
    if (a.type === 'event' && guestsOf(a) && S.mail === 'nomail') label = c.a.icsBtn;
    const s = S.st[id];
    let pri = `<button class="btn pri lg" data-act="approve" data-id="${id}">${label}</button>`;
    if (s === 'failed') pri = `<button class="btn pri lg" data-act="approve" data-id="${id}">${c.a.retry}</button>`;
    if (s === 'disconnected') pri = `<button class="btn pri lg" data-act="reconnect" data-id="${id}">${c.a.connect}</button>`;
    if (s === 'expired') pri = `<button class="btn pri lg" data-act="reconnect" data-id="${id}">${c.a.signIn}</button>`;
    const draft = a.type === 'mail' && S.mail !== 'nomail' && s !== 'expired' ? `<button class="btn lg">${ic('out')}${c.a.draft}</button>` : '';
    const copy = s === 'disconnected' ? `<button class="btn lg">${ic('copy')}${c.a.copyTxt}</button>` : '';
    return `<div class="cacts">${pri}${draft}${copy}<button class="btn lg" data-act="dismiss" data-id="${id}">${c.a.dismiss}</button><span class="keys">${c.a.keys.map(([k, l]) => `<kbd>${k}</kbd>${l}`).join(' ')}</span></div>`;
  }
  function notices(c, id, a) {
    let h = '';
    const s = S.st[id];
    if (s === 'failed') { const [b, x] = a.type === 'mail' ? c.a.errMail : c.a.errJira; h += `<div class="cerr" role="alert">${ic('warn')}<div><b>${b}</b>${x}</div></div>`; }
    if (s === 'disconnected') { const [b, x] = c.a.discJira; h += `<div class="guard" role="status">${ic('plug')}<div><b>${b}</b>${x}</div></div>`; }
    if (s === 'expired') { const [b, x] = c.a.expired; h += `<div class="guard" role="status">${ic('lock')}<div><b>${b}</b>${x}</div></div>`; }
    if (a.guard && s !== 'done' && s !== 'dismissed') h += `<div class="guard">${ic('shield')}<div><b>${esc(c.a.guardT(a.by))}</b>${c.a.guardS}</div></div>`;
    if (a.unsure && !S.who[id] && s !== 'dismissed') {
      const me = t().note.tasks[0][0];
      h += `<div class="guard">${ic('q')}<div style="flex:1"><b>${c.a.unsureT}</b>${c.a.unsureS}${S.err[id] === 'who' ? `<div class="hint warn" style="margin-top:4px">${c.a.needWho}</div>` : ''}<div class="whos"><button class="pop" data-who="me" data-id="${id}">${me}</button><button class="pop" data-who="marek" data-id="${id}">Marek Lis</button><button class="pop" data-act="dismiss" data-id="${id}">${c.a.notTask}</button></div></div></div>`;
    }
    return h;
  }
  function resultLine(c, id, a) {
    const s = S.st[id], r = c.a.res;
    if (s === 'dismissed') return `<div class="res2">${r.dismissed} · <button class="link" data-act="restore" data-id="${id}">${c.a.restore}</button></div>`;
    if (s === 'sending') return `<div class="res2">${c.a.st.sending}</div>`;
    if (s !== 'done') return '';
    const txt = a.type === 'mail' ? r.mail('11:52') : a.type === 'event' ? r.event(guestsOf(a)) : r[a.type];
    const [head, link] = txt.split(' · ').length > 2 ? [txt.split(' · ').slice(0, -1).join(' · '), txt.split(' · ').pop()] : txt.split(' · ');
    return `<div class="res2">${ic('check')}<span>${head}</span>${link ? `<button class="link">${link} ${ic('out')}</button>` : ''}</div>`;
  }
  function actionCard(c, id) {
    const a = A(id), s = S.st[id];
    const isOpen = S.open === id && !['done', 'dismissed', 'sending'].includes(s);
    const ed = S.edits[id] ? `<span class="edited">${c.a.edited}</span>` : '';
    const head = `<button class="ar" data-open="${id}" aria-expanded="${isOpen}"><span class="ti">${ic(TYPE_IC[a.type])}</span><span class="tx"><span class="t">${esc(a.t)}${ed}</span><span class="m">${esc(subLine(c, id, a))}</span></span>${statusLabel(c, id, a)}</button>`;
    const body = isOpen ? `<div class="ab">${evidence(c, id, a)}${notices(c, id, a)}${form(c, id, a)}<div class="sendas">${viaLine(c, a)}</div>${buttons(c, id, a)}</div>` : '';
    return `<div class="ac ${isOpen ? 'open' : ''} ${s === 'dismissed' ? 'dim' : ''}" data-card="${id}">${head}${body}${isOpen ? '' : resultLine(c, id, a)}</div>`;
  }
  function actionsBlock(c, item) {
    if (item === 'nordlys' && S.state === 'finding') return `<div class="astate">${ring('progress', 44, 0.7)}<h3>${c.a.findT}</h3><p>${c.a.findS}</p></div><div class="alist"><div class="skel"></div><div class="skel"></div><div class="skel"></div></div>`;
    if (item === 'nordlys' && S.state === 'none') return `<div class="astate">${ring('open', 64)}<h3>${c.a.noneT}</h3><p>${c.a.noneS}</p><button class="btn" data-tab="notes">${c.a.showNotes}</button></div>`;
    const list = ids(item);
    const w = waiting(item), n = needs(item);
    const d = list.filter((id) => S.st[id] === 'done').length, x = list.filter((id) => S.st[id] === 'dismissed').length;
    const head = w ? `<div class="ahead"><span class="t">${c.a.hdr(list.length, n)}</span><span class="s">${c.a.hdrSub}</span></div>` : `<div class="ahead"><span class="t">${ic('check')} ${c.a.allDone}</span><span class="s">${c.a.allDoneSub(d, x)}</span></div>`;
    return `${head}<div class="alist">${list.map((id) => actionCard(c, id)).join('')}</div><div class="trust">${ic('lock')}${c.a.trust}</div>`;
  }

  // ---------- note ----------
  function noteBody(c, tab, item) {
    const n = c.note;
    if (tab === 'actions') return actionsBlock(c, item);
    if (tab === 'mine') return `<div class="minehelp">${n.mineHelp}</div><div class="mine">${n.mine.map((l) => `<div>${esc(l)}</div>`).join('')}</div>`;
    if (tab === 'transcript') return `<div style="margin-top:10px">${n.tr.map(([s, l, id]) => `<div class="tline" ${id && S.hlq === id ? 'style="background:var(--tint);border-radius:6px;margin:0 -8px;padding:5px 8px"' : ''}><span class="s">${s === '?' ? n.unsure : s}</span><span>${l}</span></div>`).join('')}</div>`;
    const src = S.item === 'sync' ? c.sync : n;
    const showActs = !(S.item === 'nordlys' && ['finding', 'none'].includes(S.state));
    const task = ([w, x, d, id]) => {
      const linked = id && showActs;
      const a = linked ? A(id) : null, st = linked ? S.st[id] : '';
      const mark = linked ? `<span class="tmark ${['need', 'failed', 'expired', 'disconnected'].includes(st) ? 'need' : st === 'done' ? 'done' : ''}" aria-hidden="true">${ic(st === 'done' ? 'check' : TYPE_IC[a.type])}</span>` : '';
      return `<div class="task ${linked ? 'linked' : ''}" ${linked ? `data-task="${id}" tabindex="0" aria-describedby="tpop-${id}"` : ''}><span class="cb" role="checkbox" aria-checked="${st === 'done'}"></span><span><span class="who">${w}:</span> ${x}${d ? ` <span class="who">· ${d}</span>` : ''}${mark}</span></div>`;
    };
    const tasks = `<div class="h3">${n.taskH}</div><div class="tasks">${src.tasks.map(task).join('')}${S.pop ? taskPop(c) : ''}</div>`;
    return `<div class="note"><div class="h3">${n.sumH}</div><p>${src.sum}</p><div class="h3">${n.decH}</div><ul>${src.dec.map((d) => `<li>${d}</li>`).join('')}</ul>${tasks}<div class="nfoot">${n.foot}</div></div>`;
  }
  function taskPop(c) {
    const id = S.pop.id, a = A(id), st = S.st[id], k = c.a.k;
    let lines = '';
    if (a.type === 'mail') lines = `<div><span class="pk">${k.to}</span> ${a.to.length ? esc(a.to.map((p) => p[0]).join(', ')) : '—'}</div><div><span class="pk">${k.subject}</span> ${esc(a.subject)}</div><div class="pv">${esc(a.body.split('\n').filter(Boolean).slice(1, 2).join(' '))}</div>`;
    else if (a.type === 'event') lines = `<div><span class="pk">${k.when}</span> ${esc(a.when)}, ${esc(a.time)}</div>${guestsOf(a) ? `<div><span class="pk">${k.guests}</span> ${esc(a.guests.map((g) => g[0]).join(', '))}</div>` : ''}`;
    else if (a.type === 'jira') { const w = a.unsure ? whoName(id, a) : a.assignee; lines = `<div><span class="pk">${k.project}</span> ${esc(a.project)}</div><div><span class="pk">${k.assignee}</span> ${w ? esc(w) : '—'}${a.due ? ` · ${esc(a.due)}` : ''}</div><div class="pv">${esc(a.summary)}</div>`; }
    else lines = `<div><span class="pk">${k.team}</span> ${esc(a.team)} · ${esc(a.priority)}</div><div class="pv">${esc(a.summary)}</div>`;
    const note = a.guard && st === 'need' ? `<div class="pn">${ic('shield')}${esc(c.a.guardT(a.by))}</div>` : a.unsure && !S.who[id] ? `<div class="pn">${ic('q')}${c.a.unsureT}</div>` : '';
    return `<div class="tpop" id="tpop-${id}" role="tooltip" style="top:${S.pop.top}px;left:${S.pop.left}px" data-pop="${id}"><div class="ph3"><span class="ti">${ic(TYPE_IC[a.type])}</span><div class="tx"><div class="pt">${esc(a.t)}</div><div class="pm">${c.a.popVia[a.type]}</div></div>${statusLabel(c, id, a)}</div><div class="pl">${lines}</div>${note}<div class="pa"><button class="btn" data-goact="${id}">${c.a.inActions} ${ic('chev')}</button></div></div>`;
  }
  function noteView(c) {
    const n = c.note, item = c.items.find((x) => x.id === S.item);
    const keys = ['notes', 'actions', 'mine', 'transcript'];
    let tab = S.tab; if (!keys.includes(tab)) tab = 'notes';
    const w = waiting(S.item);
    const tabs = keys.map((k) => `<button role="tab" aria-selected="${tab === k}" data-tab="${k}">${n.tabs[k]}${k === 'actions' && w && !(S.item === 'nordlys' && ['finding', 'none'].includes(S.state)) ? `<span class="cnt">${w}</span>` : ''}</button>`).join('');
    return `<div class="nhead"><div class="sp"><h1 class="ntitle">${item.t}</h1><div class="nmeta">${S.item === 'sync' ? c.sync.meta : n.meta}</div></div><button class="btn">${ic('expand')}${n.open}</button><button class="btn">${ic('copy')}${n.copy}</button></div>
      <div style="margin-top:8px"><span class="chip">${ring('meeting', 11)}${n.onMac}</span></div>
      <div class="tabs" role="tablist">${tabs}</div>${noteBody(c, tab, S.item)}`;
  }
  function toastEl(c) {
    if (!S.toast) return '';
    const T = S.toast;
    const txt = T.kind === 'mail' ? c.a.toast.mail(T.left) : c.a.toast[T.kind];
    return `<div class="toast" role="status">${T.kind === 'mail' ? '' : ic('check')}<span>${txt}</span><button class="btn" data-act="undo">${ic('undo')}${c.a.undo}</button></div>`;
  }
  function noteScr(c) {
    return `<div class="win mainw">${sidebar(c)}<div class="content">${toolbar(c)}<div class="body2">${listCol(c)}<article class="prev">${noteView(c)}</article></div></div>${toastEl(c)}</div>`;
  }

  // ---------- inbox (layout C) ----------
  function inboxScr(c) {
    const groups = [['nordlys', NORD], ['sync', SYNC]];
    let out = `<div style="padding:16px 20px 4px"><div class="ntitle">${c.inbox.t}</div><div class="help">${c.inbox.s}</div></div>`;
    for (const [item, list] of groups) {
      const it = c.items.find((x) => x.id === item);
      out += `<div class="gl">${it.t} · ${it.w}</div>`;
      for (const id of list) {
        const a = A(id), s = S.st[id];
        const st = ['need', 'failed', 'expired', 'disconnected'].includes(s) ? `<span class="m need">${c.a.st[s] || ''}</span>` : s === 'done' ? `<span class="m">${c.a.doneSt[a.type]}</span>` : s === 'dismissed' ? `<span class="m">${c.a.st.dismissed}</span>` : `<span class="m">${esc(subLine(c, id, a))}</span>`;
        out += `<button class="ir ${S.open === id ? 'on' : ''}" data-open="${id}"><span class="ti">${ic(TYPE_IC[a.type])}</span><span class="tx"><span class="t">${esc(a.t)}</span>${st}</span></button>`;
      }
    }
    const id = S.open, a = A(id), s = S.st[id];
    const it = c.items.find((x) => x.id === (SYNC.includes(id) ? 'sync' : 'nordlys'));
    const detail = ['done', 'dismissed', 'sending'].includes(s)
      ? `<div class="cardhead"><span class="ti">${ic(TYPE_IC[a.type])}</span><div><div class="ntitle" style="font-size:1.154rem">${esc(a.t)}</div></div>${statusLabel(c, id, a)}</div><div class="from">${it.t}</div>${resultLine(c, id, a).replace('res2', 'res2" style="padding-left:48px')}${SYNC.includes(id) ? gradOffer(c) : ''}`
      : `<div class="cardhead"><span class="ti">${ic(TYPE_IC[a.type])}</span><div style="flex:1"><div class="ntitle" style="font-size:1.154rem">${esc(a.t)}</div></div>${statusLabel(c, id, a)}</div><div class="from">${it.t} · ${it.w}</div>
        <div class="ab">${evidence(c, id, a)}${notices(c, id, a)}${form(c, id, a)}<div class="sendas">${viaLine(c, a)}</div>${buttons(c, id, a)}</div><div class="trust">${ic('lock')}${c.a.trust}</div>`;
    return `<div class="win mainw">${sidebar(c)}<div class="content">${toolbar(c)}<div class="body2"><nav class="list alist2">${out}</nav><article class="dpane">${detail}</article></div></div>${toastEl(c)}</div>`;
  }

  // ---------- settings: Connected apps ----------
  function appsScr(c) {
    const s = c.set;
    const PG = [['general', 'sliders'], ['dictation', 'mic'], ['meetings', 'meeting'], ['ai', 'spark'], ['apps', 'plug'], ['privacy', 'shield'], ['addons', 'puzzle'], ['about', 'info']];
    const side = `<aside class="side">${lights()}<label class="field" style="margin:0 0 10px">${ic('search')}<input placeholder="${S.lang === 'pl' ? 'Szukaj w ustawieniach' : 'Search settings'}"></label>${PG.map(([k, i]) => `<button class="si ${k === 'apps' ? 'on' : ''}">${ic(i)}<span>${s.side[k]}</span></button>`).join('')}</aside>`;
    const row = (cls, ab, [n, h], right) => `<div class="row"><span class="appi ${cls}">${ab}</span><div class="lbl">${n}<div class="help">${h}</div></div>${right}</div>`;
    const jiraState = S.state === 'offline' ? `<span class="okdot off">${s.notConn}</span><button class="btn">${s.connect}</button>` : `<span class="okdot">${s.connected}</span><button class="btn">${s.remove}</button>`;
    const gState = S.mail !== 'acct' ? `<button class="btn">${s.connect}</button>` : S.state === 'offline' ? `<span class="okdot warn">${c.a.st.expired}</span><button class="btn">${c.a.signIn}</button>` : `<span class="okdot">${s.connected}</span><button class="btn">${s.disconnect}</button>`;
    const body = `<h2 class="ph2">${ic('plug')}${s.side.apps}</h2><p class="lead">${s.lead}</p>
      <div class="gh">${s.mailH}</div><div class="group">${row('g', 'G', s.google, gState)}${row('c', ic('cal'), s.macCal, `<span class="okdot">${s.allowed}</span>`)}${row('c', 'M', s.ms, `<button class="btn">${s.connect}</button>`)}${row('c', ic('plug'), s.mailMcp, S.mail === 'mcp' ? `<span class="okdot">${s.connected}</span><button class="btn">${s.disconnect}</button>` : `<button class="btn">${s.connect}</button>`)}</div>
      <div class="gh">${s.toolsH}</div><div class="group">${row('j', 'J', s.jira, jiraState)}${row('l', 'L', s.linear, `<button class="btn">${s.connect}</button>`)}${row('a', 'A', s.asana, `<button class="btn">${s.connect}</button>`)}</div>
      <div class="foot" style="margin-top:8px"><button class="link" style="color:var(--sec)">${s.missing}</button></div>
      <div class="foot">${ring('mark', 13)}${s.foot}</div>`;
    return `<div class="win setw">${side}<div class="spage">${body}</div></div>`;
  }

  // ---------- after the meeting: the pill (P10) ----------
  const pRing = (work) => `<svg class="pglyph pring ${work ? 'work' : ''}" viewBox="0 0 20 20" aria-hidden="true"><circle class="arc" cx="10" cy="10" r="7" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" pathLength="100" stroke-dasharray="${work ? '45 100' : '80 100'}" transform="rotate(-60 10 10)"/><circle cx="10" cy="10" r="2.6" fill="currentColor"/></svg>`;
  const pCheck = '<svg class="pglyph" viewBox="0 0 20 20" aria-hidden="true" style="color:var(--plive)"><circle cx="10" cy="10" r="8" fill="currentColor"/><path d="m6.2 10.2 2.6 2.6 5-5.4" stroke="var(--pon)" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  function afterScr(c) {
    const f = c.after, n = ids('nordlys').length;
    const seg = (key, opts) => `<span class="sk-seg" role="group" aria-label="${key}" style="margin-left:6px">${opts.map(([v, l]) => `<button type="button" data-set="${key}" data-val="${v}" aria-pressed="${S[key] === v}">${l}</button>`).join('')}</span>`;
    const pill = S.pillGone ? '' : S.phase === 'proc'
      ? `<div class="pill" tabindex="0" role="status" aria-label="${f.procHover.join(', ')}">${pRing(true)}<span class="more"><span class="psec">${f.procHover[S.procStep || 0]}</span></span></div>`
      : `<div class="pill" role="status">${pCheck}<span>${f.ready(n)}</span><button class="pact" data-go="note">${f.open}</button><button class="px" data-act="pillx" aria-label="${f.close}"><svg viewBox="0 0 12 12"><path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg></button></div>`;
    const dot = S.pillGone && S.after === 'dot';
    return `<div class="vstack"><div class="desk"><div class="mbar"><b></b><span>Finder</span><span class="sp"></span><span class="${dot ? 'mbadge' : ''}" style="display:inline-grid">${ring('mark', 15)}</span><span>${S.lang === 'pl' ? 'czw. 11:52' : 'Thu 11:52'}</span></div>
      <div class="pillstage">${pill}</div></div>
      <div class="caption">${f.cap2}<div style="margin-top:8px;display:flex;flex-wrap:wrap;gap:6px 12px;align-items:center"><span>${f.phaseL}</span>${seg('phase', [['proc', f.proc], ['ready', f.readyL]])}<span>${f.afterL}</span>${seg('after', [['stay', f.stay], ['dot', f.dot], ['none', f.none]])}<button class="btn" data-act="replay">${f.replay}</button></div></div></div>`;
  }

  // ---------- shell ----------
  function bar() {
    const b = t().bar;
    const seg = (key, opts) => `<span class="sk-seg" role="group" aria-label="${key}">${opts.map(([v, l]) => `<button type="button" data-set="${key}" data-val="${v}" aria-pressed="${S[key] === v}">${l}</button>`).join('')}</span>`;
    return `<div id="sk-bar"><b>Lintel · actions · iteration 3</b><label>${b.screen}</label>${seg('screen', [['note', b.note], ['inbox', b.inbox], ['apps', b.apps], ['after', b.after]])}
      <label>${b.state}</label>${seg('state', ['ready', 'finding', 'none', 'done', 'errors', 'offline'].map((k) => [k, b[k]]))}
      <label>${b.mail}</label>${seg('mail', [['acct', b.acct], ['mcp', b.mcp], ['nomail', b.nomail]])}
      <label>${b.theme}</label>${seg('theme', [['light', b.light], ['dark', b.dark]])}<label>${b.lang}</label>${seg('lang', [['en', 'EN'], ['pl', 'PL']])}
      ${seg('ts', [['m', 'M'], ['l', 'L'], ['xl', 'XL']])}<button type="button" class="sk-seg" style="background:none;color:#F1EEE9;padding:3px 9px" data-act="reset">Reset</button></div>`;
  }
  function syncURL() {
    const p = new URLSearchParams();
    p.set('screen', S.screen); p.set('state', S.state); if (S.mail !== 'acct') p.set('mail', S.mail);
    p.set('theme', S.theme); p.set('lang', S.lang); if (S.ts !== 'm') p.set('ts', S.ts); if (!S.chrome) p.set('chrome', '0');
    if (S.item !== 'nordlys') p.set('item', S.item); if (S.tab !== 'notes') p.set('tab', S.tab); if (S.open !== 'a1') p.set('sel', S.open);
    if (S.screen === 'after') { p.set('phase', S.phase); if (S.after !== 'stay') p.set('after', S.after); }
    history.replaceState(null, '', location.pathname + '?' + p.toString());
  }
  const SCREENS = { note: noteScr, inbox: inboxScr, apps: appsScr, after: afterScr };
  function render() {
    const root = document.getElementById('app');
    const f = document.activeElement, fk = f && f.dataset && f.dataset.edit ? [f.dataset.edit, f.dataset.key, f.selectionStart] : null;
    document.documentElement.lang = S.lang;
    document.documentElement.className = `${S.theme} warm ts-${S.ts}${S.chrome ? '' : ' nochrome'}`;
    root.innerHTML = (S.chrome ? bar() : '') + `<div class="stage">${SCREENS[S.screen](t())}</div>`;
    if (fk) { const el = root.querySelector(`[data-edit="${fk[0]}"][data-key="${fk[1]}"]`); if (el) { el.focus(); try { el.setSelectionRange(fk[2], fk[2]); } catch (e) { /* ignore */ } } }
  }

  // ---------- interactions ----------
  let timer = null;
  function nextOpen(after) {
    const list = ids(SYNC.includes(after) ? 'sync' : 'nordlys');
    const nx = list.find((id) => id !== after && ['ready', 'need', 'failed', 'expired', 'disconnected'].includes(S.st[id]));
    S.open = nx || after;
  }
  function finishToast() { clearInterval(timer); timer = null; if (S.toast && S.toast.kind === 'mail') S.st[S.toast.id] = 'done'; S.toast = null; render(); }
  function approve(id) {
    const a = A(id);
    if (a.unsure && !S.who[id]) { S.err[id] = 'who'; render(); return; }
    if (a.type === 'mail' && !a.to.length && !(S.edits[id] && S.edits[id].toTyped)) { S.err[id] = 'to'; render(); return; }
    if (a.type === 'jira' && S.st[id] === 'failed' && !S.component) { render(); return; }
    clearInterval(timer);
    if (S.toast && S.toast.kind === 'mail') S.st[S.toast.id] = 'done';
    if (a.type === 'mail' && S.mail !== 'nomail') {
      S.st[id] = 'sending'; S.toast = { kind: 'mail', id, left: 10, prev: 'ready' };
      timer = setInterval(() => { S.toast.left--; if (S.toast.left <= 0) finishToast(); else render(); }, reduced ? 1000 : 1000);
    } else {
      S.st[id] = 'done'; S.toast = { kind: a.type === 'mail' ? 'mail' : a.type, id };
      if (a.type === 'mail') S.toast = null;
      timer = setTimeout(() => { S.toast = null; render(); }, 6000);
    }
    nextOpen(id); render();
  }
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-set],[data-act],[data-go],[data-item],[data-tab],[data-open],[data-who],[data-tr],[data-goact]');
    if (!el) return;
    const d = el.dataset;
    if (d.set) {
      S[d.set] = d.val;
      if (d.set === 'screen' && d.val === 'inbox') S.layout = 'inbox';
      if (d.set === 'layout' && d.val !== 'inbox' && S.screen === 'inbox') S.screen = 'note';
      if (d.set === 'phase' || d.set === 'after') { clearTimeout(pillT); clearInterval(procT); S.pillGone = false; if (S.phase === 'ready') armPill(); }
      if (d.set === 'screen' && d.val === 'after') { syncURL(); playPill(); return; }
      if (d.set === 'state') { S.open = d.val === 'errors' || d.val === 'offline' ? 'a3' : 'a1'; S.item = 'nordlys'; S.tab = 'notes'; S.edits = {}; applyState(); }
      syncURL(); render(); return;
    }
    if (d.go) { S.screen = d.go; if (d.go === 'inbox') S.layout = 'inbox'; syncURL(); render(); return; }
    if (d.item) { S.item = d.item; S.open = d.item === 'sync' ? 's1' : 'a1'; syncURL(); render(); return; }
    if (d.tab) { S.tab = d.tab; S.hlq = ''; S.pop = null; syncURL(); render(); return; }
    if (d.open) { S.open = S.open === d.open && S.screen === 'note' ? '' : d.open; render(); return; }
    if (d.who) { S.who[d.id] = d.who; S.st[d.id] = 'ready'; delete S.err[d.id]; render(); return; }
    if (d.tr) { S.hlq = d.tr; S.tab = 'transcript'; render(); return; }
    if (d.goact) { S.pop = null; S.tab = 'actions'; S.open = d.goact; syncURL(); render(); document.querySelector(`[data-card="${d.goact}"]`)?.scrollIntoView({ block: 'nearest' }); return; }
    const a = d.act, id = d.id;
    if (a === 'approve') approve(id);
    else if (a === 'dismiss') { S.st[id] = 'dismissed'; clearInterval(timer); S.toast = { kind: 'dismissed', id, prev: id }; timer = setTimeout(() => { S.toast = null; render(); }, 6000); nextOpen(id); render(); }
    else if (a === 'restore') { S.st[id] = t().A[id].guard || t().A[id].unsure ? 'need' : 'ready'; S.open = id; render(); }
    else if (a === 'undo') { if (S.toast) { const T = S.toast; S.st[T.id] = t().A[T.id].guard || (t().A[T.id].unsure && !S.who[T.id]) ? 'need' : 'ready'; S.open = T.id; } clearInterval(timer); clearTimeout(timer); S.toast = null; render(); }
    else if (a === 'reconnect') { S.st[id] = 'ready'; if (id === 'a3') { S.st.a1 = S.st.a1 === 'expired' ? 'ready' : S.st.a1; S.st.a2 = S.st.a2 === 'expired' ? 'ready' : S.st.a2; } render(); }
    else if (a === 'component') { S.component = S.lang === 'pl' ? 'Umowy' : 'Contracts'; render(); }
    else if (a === 'pillx') { clearTimeout(pillT); S.pillGone = true; render(); }
    else if (a === 'replay') playPill();
    else if (a === 'reset') { clearInterval(timer); clearTimeout(timer); S.edits = {}; S.hlq = ''; S.item = 'nordlys'; S.tab = 'notes'; S.open = S.state === 'errors' || S.state === 'offline' ? 'a3' : 'a1'; applyState(); render(); const st = document.querySelector('[role=status]'); if (st) st.focus(); }
  });
  document.addEventListener('input', (e) => {
    const el = e.target;
    if (el.dataset.edit) { const id = el.dataset.edit; S.edits[id] = Object.assign(S.edits[id] || {}, { [el.dataset.key]: el.value }); return; }
    const chips = el.closest('.chips');
    if (chips) { const card = el.closest('[data-card]') || document.querySelector('.dpane'); const id = card && card.dataset.card ? card.dataset.card : S.open; S.edits[id] = Object.assign(S.edits[id] || {}, { toTyped: el.value.trim().length > 0 }); if (S.err[id] === 'to' && el.value.trim()) { delete S.err[id]; } }
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && e.metaKey && S.open) { e.preventDefault(); approve(S.open); return; }
    if (e.key === 'Backspace' && e.metaKey && S.open) { e.preventDefault(); document.querySelector(`[data-act=dismiss][data-id="${S.open}"]`)?.click(); return; }
    if (e.key === 'Escape' && S.pop) { S.pop = null; render(); return; }
    if (e.key === 'Escape' && S.toast) { S.toast = null; render(); }
  });
  // Task hover card (Q4): after a short delay, a task linked to an action shows the action; it stays while the pointer is on it.
  let hoverT = null, leaveT = null;
  function showPop(taskEl) {
    const box = taskEl.closest('.tasks'); if (!box) return;
    const r = taskEl.getBoundingClientRect(), b = box.getBoundingClientRect();
    S.pop = { id: taskEl.dataset.task, top: Math.round(r.bottom - b.top + 4), left: Math.round(Math.min(r.left - b.left + 26, Math.max(0, b.width - 360))) };
    render();
  }
  document.addEventListener('mouseover', (e) => {
    const tk = e.target.closest('[data-task]'), pp = e.target.closest('[data-pop]');
    if (pp || (tk && S.pop && S.pop.id === tk.dataset.task)) { clearTimeout(leaveT); return; }
    clearTimeout(hoverT);
    if (tk) hoverT = setTimeout(() => showPop(tk), reduced ? 0 : 450);
  });
  document.addEventListener('mouseout', (e) => {
    const from = e.target.closest('[data-task],[data-pop]'); if (!from) return;
    const to = e.relatedTarget && e.relatedTarget.closest ? e.relatedTarget.closest('[data-task],[data-pop]') : null;
    if (to) return;
    clearTimeout(hoverT);
    if (S.pop) { clearTimeout(leaveT); leaveT = setTimeout(() => { S.pop = null; render(); }, 200); }
  });
  document.addEventListener('focusin', (e) => { const tk = e.target.closest('[data-task]'); if (tk && (!S.pop || S.pop.id !== tk.dataset.task)) { showPop(tk); const el = document.querySelector(`[data-task="${tk.dataset.task}"]`); if (el) el.focus(); } });
  // P10 pill: processing (closing ring, hover says what it does) → Ready · N actions → per Q15.
  let pillT = null, procT = null;
  function armPill() { clearTimeout(pillT); if (S.after !== 'stay') pillT = setTimeout(() => { S.pillGone = true; render(); }, 8000); }
  function playPill() {
    clearTimeout(pillT); clearInterval(procT);
    S.phase = 'proc'; S.procStep = 0; S.pillGone = false; render();
    procT = setInterval(() => {
      S.procStep++;
      if (S.procStep >= 2) { clearInterval(procT); S.phase = 'ready'; syncURL(); render(); armPill(); return; }
      render();
    }, 2500);
  }
  render();
  if (S.screen === 'after' && !qs.get('phase')) playPill(); else if (S.screen === 'after' && S.phase === 'ready') armPill();
  if (qs.get('pop')) { const tk = document.querySelector(`[data-task="${qs.get('pop')}"]`); if (tk) showPop(tk); }
})();
