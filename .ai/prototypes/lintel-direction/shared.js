/* Lintel UX direction sketches: shared copy (en/pl), state and interactions.
   Every sketch file loads this and defines window.SKETCH = {id, name, screens:{onb,home,set}}.
   Query: ?screen=onb|home|set&theme=light|dark&lang=en|pl&chrome=0&demo=done|listening&more=1
   All data is fictional. */
(function () {
  'use strict';

  const COPY = {
    en: {
      app: 'Lintel',
      steps: ['Welcome', 'Access', 'Shortcut', 'Try it', 'Meetings'],
      stepOf: 'Step 4 of 5',
      onbTitle: 'Say something. Lintel will type it.',
      onbHint: 'Hold ⌥ Space, say a sentence, then let go.',
      onbOr: 'No microphone handy? Press and hold the button instead.',
      to: 'To', subject: 'Subject', toName: 'Marta Nowak', subj: 'Q4 budget',
      bodyPh: 'Your words appear here.',
      result: 'Hi Marta, I went through the Q4 numbers and they look good. Can we go over the travel budget on Thursday?',
      success: 'That’s it. It works the same in Mail, Slack, Word and every other app.',
      hold: 'Hold to talk', listening: 'Listening…', letGo: 'Let go when you’re done.', typing: 'Typing…',
      again: 'Try again',
      back: 'Back', skip: 'Skip for now', cont: 'Continue',
      privacy: 'Your voice is turned into text on this Mac. Nothing is sent anywhere.',
      key: '⌥ Space', keyAlt: '⌥', keySpace: 'Space',
      date: 'Monday, 23 November', greet: 'Good afternoon, Anna',
      nav: { home: 'Home', notes: 'All notes', meetings: 'Meetings', dictations: 'Dictations', dictionary: 'Dictionary', settings: 'Settings' },
      searchNotes: 'Search notes',
      dictTitle: 'Dictate in any app', dictSub: 'Hold ⌥ Space wherever you can type.',
      recTitle: 'Record a meeting', recSub: 'Lintel writes the notes when the call ends.',
      startRec: 'Start Recording', recording: 'Recording', stop: 'Stop',
      recent: 'Recent', seeAll: 'See all',
      items: [
        { k: 'meeting', t: 'Client call: Nordlys Energy', m: 'Meeting · 42 min', b: 'Notes ready', w: 'Today, 11:30' },
        { k: 'meeting', t: 'Weekly sales sync', m: 'Meeting · 28 min', b: '3 follow-ups', w: 'Today, 9:00' },
        { k: 'dictation', t: 'Email to Marta about the Q4 budget', m: 'Dictation · 118 words', b: '', w: 'Yesterday' },
        { k: 'note', t: 'Notes for the board update', m: 'Note', b: '', w: 'Friday' }
      ],
      setup: 'Finish setting up', setupN: '3 of 5 done', hide: 'Hide',
      checklist: [
        { t: 'Let Lintel type into other apps', done: true },
        { t: 'Choose your shortcut', done: true },
        { t: 'Try your first dictation', done: true },
        { t: 'Hear the other people in a call', done: false, a: 'Allow' },
        { t: 'Add names you use often', done: false, a: 'Open Dictionary' }
      ],
      settings: 'Settings', searchSet: 'Search settings',
      side: {
        core: [['general', 'General'], ['dictation', 'Dictation'], ['meetings', 'Meetings'], ['notes', 'Notes'], ['dictionary', 'Dictionary']],
        addonsH: 'Add-ons',
        addons: [['search', 'Quick search'], ['clipboard', 'Clipboard history'], ['windows', 'Window layouts']],
        rest: [['privacy', 'Privacy & Data'], ['ai', 'AI on this Mac']]
      },
      status: 'Ready to dictate', statusSub: 'Microphone allowed · English and Polish',
      secShortcut: 'Shortcut', rowDictate: 'Dictate',
      helpDictate: 'Hold to talk. Or tap once to start and once to stop.',
      secWriting: 'Writing', rowTidy: 'Tidy up my text', helpTidy: 'Removes “um”s, fixes punctuation and keeps your words.',
      rowLang: 'Languages I speak', langVal: 'English, Polish', change: 'Change…',
      secWords: 'Names and words', rowDict: 'Dictionary', helpDict: '12 words Lintel always spells your way', openDict: 'Open Dictionary',
      secHistory: 'History', rowKeep: 'Keep my dictations', keepVal: '30 days', helpKeep: 'Older ones are deleted on their own.',
      more: 'More options', rowMic: 'Microphone', micVal: 'MacBook Pro Microphone',
      rowRestore: 'After pasting, put back what I had copied',
      q: { shortcut: 'How do you start?', writing: 'How should your text look?', words: 'Which words matter to you?', history: 'How long should Lintel remember?' },
      illoCap: 'Works in every app you write in.',
      bar: { screen: 'Screen', onb: 'Onboarding', home: 'Home', set: 'Settings', theme: 'Theme', light: 'Light', dark: 'Dark', lang: 'Language', all: 'All directions' }
    },
    pl: {
      app: 'Lintel',
      steps: ['Witaj', 'Dostęp', 'Skrót', 'Wypróbuj', 'Spotkania'],
      stepOf: 'Krok 4 z 5',
      onbTitle: 'Powiedz coś. Lintel to napisze.',
      onbHint: 'Przytrzymaj ⌥ Spację, powiedz zdanie i puść.',
      onbOr: 'Nie masz pod ręką mikrofonu? Przytrzymaj przycisk.',
      to: 'Do', subject: 'Temat', toName: 'Marta Nowak', subj: 'Budżet na IV kwartał',
      bodyPh: 'Tu pojawią się Twoje słowa.',
      result: 'Cześć Marto, liczby za IV kwartał wyglądają dobrze. Czy możemy w czwartek omówić budżet na podróże?',
      success: 'To wszystko. Tak samo działa w Mailu, Slacku, Wordzie i każdej innej aplikacji.',
      hold: 'Przytrzymaj, aby mówić', listening: 'Słucham…', letGo: 'Puść, gdy skończysz.', typing: 'Piszę…',
      again: 'Spróbuj jeszcze raz',
      back: 'Wstecz', skip: 'Pomiń na razie', cont: 'Dalej',
      privacy: 'Głos zamienia się w tekst na tym Macu. Nic nie jest nigdzie wysyłane.',
      key: '⌥ Spacja', keyAlt: '⌥', keySpace: 'Spacja',
      date: 'Poniedziałek, 23 listopada', greet: 'Dzień dobry, Anno',
      nav: { home: 'Start', notes: 'Wszystkie notatki', meetings: 'Spotkania', dictations: 'Dyktowania', dictionary: 'Słownik', settings: 'Ustawienia' },
      searchNotes: 'Szukaj w notatkach',
      dictTitle: 'Dyktuj w dowolnej aplikacji', dictSub: 'Przytrzymaj ⌥ Spację wszędzie, gdzie możesz pisać.',
      recTitle: 'Nagraj spotkanie', recSub: 'Lintel napisze notatki, gdy rozmowa się skończy.',
      startRec: 'Zacznij nagrywać', recording: 'Nagrywanie', stop: 'Zatrzymaj',
      recent: 'Ostatnie', seeAll: 'Pokaż wszystkie',
      items: [
        { k: 'meeting', t: 'Rozmowa z klientem: Nordlys Energy', m: 'Spotkanie · 42 min', b: 'Notatki gotowe', w: 'Dziś, 11:30' },
        { k: 'meeting', t: 'Cotygodniowe spotkanie sprzedaży', m: 'Spotkanie · 28 min', b: '3 zadania', w: 'Dziś, 9:00' },
        { k: 'dictation', t: 'E-mail do Marty o budżecie na IV kwartał', m: 'Dyktowanie · 118 słów', b: '', w: 'Wczoraj' },
        { k: 'note', t: 'Notatki do raportu dla zarządu', m: 'Notatka', b: '', w: 'Piątek' }
      ],
      setup: 'Dokończ konfigurację', setupN: '3 z 5 gotowe', hide: 'Ukryj',
      checklist: [
        { t: 'Pozwól Lintel pisać w innych aplikacjach', done: true },
        { t: 'Wybierz skrót', done: true },
        { t: 'Wypróbuj pierwsze dyktowanie', done: true },
        { t: 'Słysz innych uczestników rozmowy', done: false, a: 'Zezwól' },
        { t: 'Dodaj nazwy, których często używasz', done: false, a: 'Otwórz Słownik' }
      ],
      settings: 'Ustawienia', searchSet: 'Szukaj w ustawieniach',
      side: {
        core: [['general', 'Ogólne'], ['dictation', 'Dyktowanie'], ['meetings', 'Spotkania'], ['notes', 'Notatki'], ['dictionary', 'Słownik']],
        addonsH: 'Dodatki',
        addons: [['search', 'Szybkie wyszukiwanie'], ['clipboard', 'Historia schowka'], ['windows', 'Układy okien']],
        rest: [['privacy', 'Prywatność i dane'], ['ai', 'AI na tym Macu']]
      },
      status: 'Gotowe do dyktowania', statusSub: 'Mikrofon dozwolony · angielski i polski',
      secShortcut: 'Skrót', rowDictate: 'Dyktuj',
      helpDictate: 'Przytrzymaj, aby mówić. Albo stuknij raz, by zacząć, i drugi raz, by skończyć.',
      secWriting: 'Pisanie', rowTidy: 'Porządkuj mój tekst', helpTidy: 'Usuwa „yyy”, poprawia interpunkcję i zachowuje Twoje słowa.',
      rowLang: 'Języki, którymi mówię', langVal: 'angielski, polski', change: 'Zmień…',
      secWords: 'Nazwy i słowa', rowDict: 'Słownik', helpDict: '12 słów, które Lintel zawsze pisze po Twojemu', openDict: 'Otwórz Słownik',
      secHistory: 'Historia', rowKeep: 'Przechowuj moje dyktowania', keepVal: '30 dni', helpKeep: 'Starsze usuwają się same.',
      more: 'Więcej opcji', rowMic: 'Mikrofon', micVal: 'Mikrofon MacBooka Pro',
      rowRestore: 'Po wklejeniu przywróć to, co było skopiowane',
      q: { shortcut: 'Jak zaczynasz?', writing: 'Jak ma wyglądać Twój tekst?', words: 'Które słowa są dla Ciebie ważne?', history: 'Jak długo Lintel ma pamiętać?' },
      illoCap: 'Działa w każdej aplikacji, w której piszesz.',
      bar: { screen: 'Ekran', onb: 'Wprowadzenie', home: 'Start', set: 'Ustawienia', theme: 'Motyw', light: 'Jasny', dark: 'Ciemny', lang: 'Język', all: 'Wszystkie kierunki' }
    }
  };

  const P = {
    home: '<path d="M2.5 7.5 8 3l5.5 4.5V13a.5.5 0 0 1-.5.5H10V10H6v3.5H3a.5.5 0 0 1-.5-.5Z"/>',
    note: '<path d="M4 2.5h5.5L12.5 5.5V13a.5.5 0 0 1-.5.5H4a.5.5 0 0 1-.5-.5V3a.5.5 0 0 1 .5-.5Z"/><path d="M9.5 2.5v3h3M5.5 8.5h5M5.5 11h3.5"/>',
    meeting: '<circle cx="5.5" cy="6" r="2"/><circle cx="11" cy="6.5" r="1.6"/><path d="M2 13c.4-2.2 1.8-3.3 3.5-3.3S8.6 10.8 9 13M9.6 10.4c.4-.3.9-.5 1.4-.5 1.4 0 2.4 1 2.8 3.1"/>',
    mic: '<rect x="6" y="2" width="4" height="7.5" rx="2"/><path d="M3.5 8a4.5 4.5 0 0 0 9 0M8 12.5V14.5"/>',
    book: '<path d="M3 3.2c1.8-.6 3.5-.4 5 .6v9.4c-1.5-1-3.2-1.2-5-.6ZM13 3.2c-1.8-.6-3.5-.4-5 .6v9.4c1.5-1 3.2-1.2 5-.6Z"/>',
    gear: '<circle cx="8" cy="8" r="2"/><path d="M8 1.8v1.7M8 12.5v1.7M1.8 8h1.7M12.5 8h1.7M3.6 3.6l1.2 1.2M11.2 11.2l1.2 1.2M3.6 12.4l1.2-1.2M11.2 4.8l1.2-1.2"/>',
    search: '<circle cx="7" cy="7" r="4.2"/><path d="m10.2 10.2 3.3 3.3"/>',
    check: '<path d="m3.5 8.3 3 3 6-6.6"/>',
    chev: '<path d="m6 4 4 4-4 4"/>',
    chevd: '<path d="m4 6 4 4 4-4"/>',
    clip: '<rect x="4" y="3" width="8" height="10.5" rx="1"/><path d="M6 3V2h4v1"/>',
    grid: '<rect x="2.5" y="2.5" width="4.5" height="11" rx=".8"/><rect x="9" y="2.5" width="4.5" height="5" rx=".8"/><rect x="9" y="9.5" width="4.5" height="4" rx=".8"/>',
    lock: '<rect x="3.5" y="7" width="9" height="6.5" rx="1"/><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2"/>',
    chip: '<rect x="4" y="4" width="8" height="8" rx="1.2"/><path d="M6 1.8V4M10 1.8V4M6 12v2.2M10 12v2.2M1.8 6H4M1.8 10H4M12 6h2.2M12 10h2.2"/>',
    sliders: '<path d="M3 4.5h10M3 11.5h10"/><circle cx="6" cy="4.5" r="1.5"/><circle cx="10.5" cy="11.5" r="1.5"/>',
    globe: '<circle cx="8" cy="8" r="5.8"/><path d="M2.3 8h11.4M8 2.2c1.7 1.6 2.5 3.5 2.5 5.8s-.8 4.2-2.5 5.8C6.3 12.2 5.5 10.3 5.5 8s.8-4.2 2.5-5.8Z"/>',
    clock: '<circle cx="8" cy="8" r="5.8"/><path d="M8 4.8V8l2.2 1.4"/>',
    kbd: '<rect x="1.8" y="4" width="12.4" height="8" rx="1.2"/><path d="M4.5 6.6h.01M7 6.6h.01M9.5 6.6h.01M12 6.6h.01M5 9.5h6"/>',
    text: '<path d="M3 4h10M3 7h10M3 10h7M3 13h5"/>',
    rec: '<circle cx="8" cy="8" r="4.5"/>'
  };

  const kindIcon = { meeting: 'meeting', dictation: 'mic', note: 'note' };
  const sideIcon = { general: 'sliders', dictation: 'mic', meetings: 'meeting', notes: 'note', dictionary: 'book', search: 'search', clipboard: 'clip', windows: 'grid', privacy: 'lock', ai: 'chip' };

  const H = {
    ic: (n, cls) => `<svg class="ic ${cls || ''}" viewBox="0 0 16 16" aria-hidden="true">${P[n] || ''}</svg>`,
    mark: (cls) => `<svg class="mark ${cls || ''}" viewBox="0 0 256 256" aria-hidden="true"><path fill="currentColor" d="M99.01 19.82A112 112 0 1 1 19.82 99.01L64.25 110.92A66 66 0 1 0 110.92 64.25Z"/><circle cx="128" cy="128" r="34" fill="var(--accent)"/></svg>`,
    kindIcon, sideIcon,
    esc: (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
  };

  const qs = new URLSearchParams(location.search);
  const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const S = {
    screen: ['onb', 'home', 'set'].includes(qs.get('screen')) ? qs.get('screen') : 'onb',
    theme: qs.get('theme') === 'dark' || qs.get('theme') === 'light' ? qs.get('theme') : (prefersDark ? 'dark' : 'light'),
    lang: qs.get('lang') === 'pl' ? 'pl' : 'en',
    chrome: qs.get('chrome') !== '0',
    dict: ['done', 'listening'].includes(qs.get('demo')) ? qs.get('demo') : 'idle',
    typed: 0,
    rec: false, recSec: 0,
    more: qs.get('more') === '1',
    toggles: { tidy: true, restore: true },
    setupHidden: false,
    nav: 'home', pane: 'dictation'
  };
  if (S.dict === 'done') S.typed = 9999;

  function t() { return COPY[S.lang]; }

  function syncURL() {
    const p = new URLSearchParams(location.search);
    p.set('screen', S.screen); p.set('theme', S.theme); p.set('lang', S.lang);
    history.replaceState(null, '', location.pathname + '?' + p.toString());
  }

  const DIRS = [['a-quiet-native.html', 'A · Quiet Native'], ['b-paper-and-ink.html', 'B · Paper & Ink'], ['c-friendly-guide.html', 'C · Friendly Guide']];

  function bar() {
    const c = t().bar;
    const seg = (key, opts) => `<span class="sk-seg" role="group" aria-label="${key}">${opts.map(([v, l]) => `<button type="button" data-set="${key}" data-val="${v}" aria-pressed="${S[key] === v}">${l}</button>`).join('')}</span>`;
    const here = location.pathname.split('/').pop();
    return `<div id="sk-bar"><b>${H.esc(window.SKETCH.name)}</b>
      <label>${c.screen}</label>${seg('screen', [['onb', c.onb], ['home', c.home], ['set', c.set]])}
      <label>${c.theme}</label>${seg('theme', [['light', c.light], ['dark', c.dark]])}
      <label>${c.lang}</label>${seg('lang', [['en', 'EN'], ['pl', 'PL']])}
      <nav>${DIRS.map(([f, n]) => `<a href="${f}?screen=${S.screen}&theme=${S.theme}&lang=${S.lang}" ${f === here ? 'aria-current="page"' : ''}>${n}</a>`).join('')}</nav></div>`;
  }

  let rendered = false;
  function render() {
    const root = document.getElementById('app');
    document.documentElement.lang = S.lang;
    document.documentElement.className = S.theme + (S.chrome ? '' : ' nochrome');
    const scr = window.SKETCH.screens[S.screen](S, t(), H);
    root.innerHTML = (S.chrome ? bar() : '') + `<div class="stage">${scr}</div>`;
    if (!rendered && qs.get('more') === '1') { const m = root.querySelector('.main'); if (m) m.scrollTop = m.scrollHeight; }
    rendered = true;
  }

  // Dictation simulation: idle -> listening (while held) -> typing -> done.
  let typer = null;
  function startListen() {
    if (S.screen !== 'onb' || S.dict === 'listening' || S.dict === 'typing') return;
    S.dict = 'listening'; S.typed = 0; render();
  }
  function stopListen() {
    if (S.dict !== 'listening') return;
    const full = t().result.length;
    if (reduced) { S.dict = 'done'; S.typed = full; render(); return; }
    S.dict = 'typing'; render();
    clearInterval(typer);
    typer = setInterval(() => {
      S.typed += 3;
      if (S.typed >= full) { S.typed = full; S.dict = 'done'; clearInterval(typer); }
      render();
    }, 22);
  }

  let recTimer = null;
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-set],[data-act],[data-nav],[data-pane]');
    if (!el) return;
    if (el.dataset.set) {
      S[el.dataset.set] = el.dataset.val;
      if (el.dataset.set === 'lang' && S.dict === 'done') S.typed = 9999;
      syncURL(); render(); return;
    }
    if (el.dataset.nav) { S.nav = el.dataset.nav; if (S.nav === 'settings') { S.screen = 'set'; syncURL(); } render(); return; }
    if (el.dataset.pane) { S.pane = el.dataset.pane; render(); return; }
    const a = el.dataset.act;
    if (a === 'toggle') { const k = el.dataset.key; S.toggles[k] = !S.toggles[k]; render(); }
    else if (a === 'more') { S.more = !S.more; render(); }
    else if (a === 'again') { S.dict = 'idle'; S.typed = 0; render(); }
    else if (a === 'next') { S.screen = 'home'; syncURL(); render(); }
    else if (a === 'backhome') { S.screen = 'home'; S.nav = 'home'; syncURL(); render(); }
    else if (a === 'hide') { S.setupHidden = true; render(); }
    else if (a === 'rec') {
      S.rec = !S.rec; S.recSec = 0; clearInterval(recTimer);
      if (S.rec) recTimer = setInterval(() => { S.recSec++; render(); }, 1000);
      render();
    }
  });
  document.addEventListener('pointerdown', (e) => { if (e.target.closest('[data-act=hold]')) { e.preventDefault(); startListen(); } });
  document.addEventListener('pointerup', stopListen);
  document.addEventListener('pointercancel', stopListen);
  document.addEventListener('keydown', (e) => { if (e.code === 'Space' && e.altKey) { e.preventDefault(); if (!e.repeat) startListen(); } });
  document.addEventListener('keyup', (e) => { if (e.code === 'Space' || e.key === 'Alt') stopListen(); });

  window.LINTEL = {
    COPY, H, S, render,
    recTime: () => `0:${String(S.recSec).padStart(2, '0')}`,
    typedText: () => t().result.slice(0, S.typed)
  };
  document.addEventListener('DOMContentLoaded', render);
})();
