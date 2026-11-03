// Carica galleria.html (la galleria delle foto, lib/gallery.rb) in jsdom con
// dati di prova, come gal_report li mette nello stampo, e verifica:
// intestazione e numeri del giro, foto con i loro appunti, commenti dell'IA
// al loro posto, mappa del giro, rullino, filtro per autore, foto in grande
// (frecce, Esc, #3z), presentazione, il tavolo con le foto da spostare,
// destra-sinistra, galleria vuota, testi del modello mai presi per HTML.
//   Prima volta:  cd tests/panel && npm install
//   Esecuzione:   node tests/panel/test_galleria.js   (oppure tests\run_tests.bat)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const { JSDOM, VirtualConsole } = require('jsdom');
const TPL = fs.readFileSync(path.join(ROOT, 'galleria.html'), 'utf8');
const it = JSON.parse(fs.readFileSync(path.join(ROOT, 'lang', 'it.json'), 'utf8'));
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if(!c) process.exitCode = 1; };

// i testi come GAL_TXT in lib/gallery.rb
const src = fs.readFileSync(path.join(ROOT, 'lib', 'gallery.rb'), 'utf8');
const map = [...src.match(/GAL_TXT = \{([\s\S]*?)\}\.freeze/)[1].matchAll(/'(\w+)' => '([\w.]+)'/g)];
const TXT = Object.fromEntries(map.map(m => [m[1], it[m[2]]]));
ok(map.length >= 18 && Object.values(TXT).every(v => typeof v === 'string' && v), `i ${map.length} testi della pagina ci sono (it)`);

const foto = (n, o) => Object.assign({ n, file: `foto_${String(n).padStart(3, '0')}.jpg`, w: 1600, h: 900, by: 'explorer', t: n * 10,
                                       clock: '20:1' + n + ':00', what: 'Cosa ' + n + '.', why: 'Perché ' + n + '.', title: 'Titolo ' + n,
                                       pos: [n * 2, n, 1.7], yaw: n * 30 }, o || {});
const DATA = {
  id: '2026-10-28_20-19-38', title: 'Giro <b>uno</b>', model: 'stromboli', date: '2026-10-28 20:19:38', lang: 'it', rtl: false,
  txt: TXT,
  photos: [foto(1), foto(2, { by: 'you', why: null, title: null, what: '<img src=x onerror="window.rotto=1"> la vista. Altro' }),
           foto(3), foto(4, { by: 'ai', what: 'La statua </script> nel cortile', why: 'Mi piace' }), foto(5, { pos: null, yaw: null })],
  track: [[0, 0, 0], [3, 1, 12], [6, 2, 25], [9, 4, 41], [12, 5, 60]],
  notes: [[2, 'Prima di tutto'], [21, 'Fra la 2 e la 3'], [22, 'Ancora'], [23, 'E ancora'], [24, 'Il quarto, su un altro post-it'], [55, 'Alla fine']]
};
// come gal_report: il JSON al posto del segnaposto, '</' spezzato
const page = d => {
  ok(TPL.split('/*DATI*/null').length === 2, 'lo stampo ha un segnaposto per i dati') || 0;
  return TPL.replace('/*DATI*/null', () => JSON.stringify(d).replace(/<\//g, '<\\/'));
};
function open(d, url){
  const errs = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', e => { if(!/Not implemented/.test(e.message)) errs.push(e.message); });
  vc.on('error', e => errs.push(String(e)));
  const dom = new JSDOM(page(d), {
    url: url || 'http://localhost/foto/galleria.html', runScripts: 'dangerously', pretendToBeVisual: true, virtualConsole: vc,
    beforeParse(w){ w.HTMLElement.prototype.scrollIntoView = function(){ w.scrolled = this; }; }
  });
  return { w: dom.window, d: dom.window.document, errs };
}
const ev = (w, el, type, o) => el.dispatchEvent(new w.MouseEvent(type, Object.assign({ bubbles: true, cancelable: true, button: 0 }, o || {})));
const key = (w, el, k) => el.dispatchEvent(new w.KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));

// ── in fila ──
{
  const { w, d, errs } = open(DATA);
  const $ = id => d.getElementById(id);
  ok(!errs.length, 'la pagina si carica senza errori' + (errs.length ? ': ' + errs[0] : ''));
  ok($('title').textContent === 'Giro <b>uno</b>' && !$('title').querySelector('b') && d.title === 'Giro <b>uno</b>',
     'il titolo è testo, anche con dei < >');
  ok(!d.querySelector('.note img') && !w.rotto && d.body.textContent.includes('La statua </script> nel cortile'),
     'i testi del modello restano testo; un </script> nei testi non rompe la pagina');
  const st = $('stats').textContent;
  ok(st.includes('1:00') && st.includes('13 m') && st.includes('5 foto'), `numeri del giro: ${st.trim().replace(/\s+/g, ' ')}`);
  const who = [...$('who').querySelectorAll('button')].map(b => b.textContent);
  ok(who.length === 4 && who[0] === it['gal.all'] + ' · 5' && who.includes(it['gal.by_you'] + ' · 1') && who.includes(it['gal.by_ai'] + ' · 1'),
     'il filtro per autore, coi conteggi: ' + who.join(' | '));
  const kinds = [...d.querySelectorAll('#strip > .spread')].map(s => s.dataset.k).join('');
  ok(kinds === 'routepppppend', 'in fila: il giro, le 5 foto, la scheda in fondo');
  ok(d.querySelectorAll('#strip .polaroid').length === 5 && d.querySelectorAll('#strip .note').length === 5 &&
     d.querySelectorAll('#strip .polaroid.dev').length === 5, 'ogni foto col suo foglietto; senza IntersectionObserver già sviluppate');
  const n2 = d.querySelectorAll('#strip .note')[1];
  const vis2 = x => w.getComputedStyle(x).display !== 'none';
  const secs2 = [...n2.querySelectorAll('.sec')];
  ok(secs2.length === 2 && vis2(secs2[0]) && secs2[0].textContent.includes(it['gal.what']) && !vis2(secs2[1]) && n2.querySelector('.stamp.you') &&
     n2.querySelector('.stamp').textContent === it['gal.by_you'], 'la foto di chi cammina: che cosa senza perché, timbro «tu»');
  const caps = [...d.querySelectorAll('#strip .cap .tt')].map(x => x.textContent);
  ok(caps[0] === 'Titolo 1' && caps[1] === '<img src=x onerror="window', 'didascalia: il titolo, o il che cosa fino al primo punto');
  ok(d.querySelectorAll('#strip .note svg').length >= 4 && d.querySelectorAll('#strip .nmeta')[0].textContent.includes('20:11'),
     'sul foglietto la bussola e l\'ora');
  // i commenti dell'IA: prima della prima foto, poi dopo la foto che li precede; tre per post-it
  const seq = [...d.querySelectorAll('#strip > *')].map(e => e.classList.contains('said') ? 'S' + e.querySelectorAll('.postit').length : (e.dataset.i != null ? e.dataset.i : e.dataset.k[0])).join(',');
  ok(seq === 'r,S1,0,1,S2,2,3,4,S1,e', 'i commenti dell\'IA al loro posto nel giro (' + seq + ')');
  ok(d.querySelector('.said .postit h4').textContent === it['gal.said'] && d.querySelectorAll('.said')[1].querySelectorAll('p').length === 4,
     'il primo post-it ha il titolo; il quarto commento va su un altro');
  // la mappa del giro
  const sheet = d.querySelector('#strip .sheet svg.route');
  ok(sheet && sheet.querySelectorAll('.pin').length === 4 && sheet.querySelectorAll('.pin .cone').length === 4 &&
     [...sheet.querySelectorAll('.lbl')].some(t => / m$/.test(t.textContent)), 'la mappa: foto numerate (non quella senza posizione), coni di vista, scala');
  ok(d.querySelector('.sheet .pencil') && d.querySelectorAll('#mini .pin').length === 4, 'la matita sul foglio, la mappa piccola');
  // il rullino
  const fr = $('frames').querySelectorAll('.fr');
  ok(fr.length === 6 && fr[0].classList.contains('fr-route') && fr[1].querySelector('img').getAttribute('src') === 'foto_001.jpg',
     'il rullino: il giro e le 5 miniature');
  w.scrolled = null;
  fr[3].click();
  ok(w.scrolled === d.querySelector('#strip .spread[data-i="2"]'), 'un clic sul rullino porta alla foto');
  ok($('ct').textContent === it['gal.route'] && fr[0].classList.contains('on'), 'all\'inizio il contatore dice il giro');
  // la scheda in fondo
  const end = d.querySelector('.endcard');
  ok(end.textContent.includes(it['gal.end']) && end.textContent.includes('13 m'), 'la scheda in fondo, coi numeri');
  // il filtro
  $('who').querySelector('.you').click();
  const hid = [...d.querySelectorAll('#strip > .spread[data-k="p"]')].map(s => s.hidden ? 0 : 1).join('');
  ok(hid === '01000' && [...fr].filter(f => f.hidden).length === 4 && sheet.querySelectorAll('.pin[hidden]').length === 3,
     'filtro «tu»: restano la sua foto, la sua miniatura e il suo segnaposto');
  $('who').querySelector('.all').click();
  ok(!d.querySelector('#strip > .spread[hidden]') && $('who').querySelector('.all').getAttribute('aria-pressed') === 'true', 'e «tutte» le rimette');
  // in grande
  d.querySelectorAll('#strip .polaroid')[2].click();
  const lb = $('lb');
  ok(lb.classList.contains('on') && lb.querySelector('.polaroid .cap .no').textContent === '№ 3' && lb.querySelector('.note'),
     'clic su una foto: in grande, col foglietto');
  key(w, d.body, 'ArrowRight');
  ok(lb.querySelector('.cap .no').textContent === '№ 4', 'freccia: la prossima');
  key(w, d.body, 'ArrowLeft'); key(w, d.body, 'ArrowLeft'); key(w, d.body, 'ArrowLeft'); key(w, d.body, 'ArrowLeft');
  ok(lb.querySelector('.cap .no').textContent === '№ 1' && $('lbprev').disabled, 'alla prima la freccia indietro si ferma');
  key(w, d.body, 'Escape');
  ok(!lb.classList.contains('on'), 'Esc la chiude');
  // presentazione
  $('play').click();
  ok(lb.classList.contains('on') && $('lbplay').getAttribute('aria-pressed') === 'true' && $('lbprog').classList.contains('run'),
     'Presentazione: in grande, con la barra che corre');
  key(w, d.body, ' ');
  ok($('lbplay').getAttribute('aria-pressed') === 'false' && !$('lbprog').classList.contains('run'), 'lo spazio la mette in pausa');
  key(w, d.body, 'Escape');
  // filtro e foto in grande: le frecce restano fra quelle mostrate
  $('who').querySelector('.ai').click();
  d.querySelectorAll('#strip .polaroid')[3].click();
  ok($('lbnext').disabled && $('lbprev').disabled, 'col filtro le frecce non escono dalle foto mostrate');
  key(w, d.body, 'Escape');
  $('who').querySelector('.all').click();
  ok(!errs.length, 'nessun errore usandola' + (errs.length ? ': ' + errs[0] : ''));
}

// ── #3z: la foto 3 in grande dall'indirizzo ──
{
  const { d } = open(DATA, 'http://localhost/foto/galleria.html#3z');
  ok(d.getElementById('lb').classList.contains('on') && d.querySelector('#lb .cap .no').textContent === '№ 3', '#3z apre la foto 3 in grande');
}

// ── sparse sul tavolo ──
{
  const { w, d, errs } = open(DATA);
  const $ = id => d.getElementById(id);
  $('vTable').click();
  const tis = d.querySelectorAll('#deskIn .ti');
  ok(!$('desk').hidden && $('strip').hidden && !$('tidy').hidden && tis.length === 6 && $('vTable').getAttribute('aria-pressed') === 'true',
     'sparse sul tavolo: il foglio del giro e le 5 foto, «Rimettile in ordine»');
  ok([...tis].every(t => t.style.getPropertyValue('inset-inline-start') && t.style.top && t.style.getPropertyValue('--rot')),
     'ognuna al suo posto, un po\' storta');
  ok($('hint').textContent === it['gal.hint.table'] && $('ct').textContent === '5 foto', 'il suggerimento e il contatore del tavolo');
  const t1 = tis[1], x0 = parseFloat(t1.style.getPropertyValue('inset-inline-start')), y0 = parseFloat(t1.style.top);
  ev(w, t1.querySelector('img'), 'pointerdown', { clientX: 100, clientY: 100 });
  ev(w, $('desk'), 'pointermove', { clientX: 160, clientY: 140 });
  ok(t1.classList.contains('lift'), 'presa: si solleva');
  ev(w, w, 'pointerup', { clientX: 160, clientY: 140 });
  const x1 = parseFloat(t1.style.getPropertyValue('inset-inline-start')), y1 = parseFloat(t1.style.top);
  ok(Math.round(x1 - x0) === 60 && Math.round(y1 - y0) === 40 && !t1.classList.contains('lift') && !$('lb').classList.contains('on'),
     `trascinata di 60, 40: resta lì (${Math.round(x1 - x0)}, ${Math.round(y1 - y0)}), e non si apre`);
  const saved = JSON.parse(w.localStorage.getItem('dagawasd-galleria/2026-10-28_20-19-38/2026-10-28 20:19:38'));
  ok(saved && saved.v === 1 && saved.it['0'][0] === Math.round(x1), 'la disposizione resta per la prossima volta');
  ok(+t1.style.zIndex > +tis[2].style.zIndex, 'quella presa va sopra le altre');
  ev(w, tis[2].querySelector('img'), 'pointerdown', { clientX: 10, clientY: 10 });
  ev(w, w, 'pointerup', { clientX: 11, clientY: 10 });
  ok($('lb').classList.contains('on') && d.querySelector('#lb .cap .no').textContent === '№ 2', 'un clic senza spostarla: in grande');
  key(w, d.body, 'Escape');
  const xk = parseFloat(tis[3].style.getPropertyValue('inset-inline-start'));
  key(w, tis[3], 'ArrowRight');
  ok(parseFloat(tis[3].style.getPropertyValue('inset-inline-start')) === xk + 12, 'anche con le frecce della tastiera');
  $('tidy').click();
  ok(parseFloat(t1.style.getPropertyValue('inset-inline-start')) === x0 && w.localStorage.getItem('dagawasd-galleria/2026-10-28_20-19-38/2026-10-28 20:19:38') === 'null',
     '«Rimettile in ordine»: tornano a righe, e si dimentica la disposizione');
  ok(w.localStorage.getItem('dagawasd-galleria/2026-10-28_20-19-38/2026-10-28 20:19:38/view') === '"table"', 'la pagina ricorda il modo scelto');
  $('vStrip').click();
  ok(!$('strip').hidden && $('desk').hidden && $('tidy').hidden, 'e torna in fila');
  ok(!errs.length, 'nessun errore sul tavolo' + (errs.length ? ': ' + errs[0] : ''));
}

// ── destra-sinistra, galleria vuota, testi che mancano ──
{
  const { d, errs } = open(Object.assign({}, DATA, { rtl: true, lang: 'ar' }));
  ok(d.documentElement.dir === 'rtl' && d.documentElement.lang === 'ar' && d.querySelector('.note p').getAttribute('dir') === 'auto' &&
     d.querySelector('.cap .no').getAttribute('dir') === 'ltr' && !errs.length,
     'arabo: pagina da destra, i testi del modello nella loro direzione, i numeri da sinistra');
}
{
  const { d, errs } = open({ id: 'x', title: 'Vuota', photos: [], track: [], txt: TXT });
  ok(d.querySelector('.empty').textContent === '0 foto' && d.getElementById('play').hidden && d.getElementById('seg').hidden &&
     !d.querySelector('.spread') && !errs.length, 'senza foto: lo dice, niente presentazione né tavolo');
}
{
  const { d, errs } = open({ photos: [foto(1, { pos: null })], track: [] });
  ok(d.querySelector('.note h3').textContent === 'What' && !d.querySelector('.sheet') && d.querySelectorAll('#strip > .spread').length === 2 &&
     !errs.length, 'senza testi e senza giro: in inglese, niente mappa');
}

// ── modificare i testi, dove sono (WYSIWYG) ──
// le modifiche dentro la pagina come le scrive gal_report; la cartella delle
// foto finta (File System Access) per «Salva nella cartella».
const withEd = (d, ed) => page(d).replace('/*MODIFICHE*/null/*FINE*/',
  () => '/*MODIFICHE*/' + JSON.stringify(ed).replace(/</g, '\\u003c').replace(/\*\//g, '*\\/') + '/*FINE*/');
const ITKEY = 'dagawasd-galleria/2026-10-28_20-19-38/2026-10-28 20:19:38/modifiche';
function openEd(html, o){
  o = o || {};
  const errs = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', e => { if(!/Not implemented/.test(e.message)) errs.push(e.message); });
  const dom = new JSDOM(html, {
    url: 'http://localhost/foto/galleria.html', runScripts: 'dangerously', pretendToBeVisual: true, virtualConsole: vc,
    beforeParse(w){
      w.HTMLElement.prototype.scrollIntoView = function(){ w.scrolled = this; };
      if(o.draft) w.localStorage.setItem(ITKEY, JSON.stringify(o.draft));
      if(o.dir) w.showDirectoryPicker = async () => o.dir.h;
    }
  });
  return { w: dom.window, d: dom.window.document, errs };
}
function fakeDir(name, files){
  const writes = {};
  const h = { name, kind: 'directory',
    async getFileHandle(n, opt){
      if(!(n in files) && !(opt && opt.create)){ const e = new Error('manca ' + n); e.name = 'NotFoundError'; throw e; }
      return { async getFile(){ return { async text(){ return files[n]; } }; },
               async createWritable(){ let b = ''; return { async write(t){ b += t; }, async close(){ files[n] = b; writes[n] = b; } }; } };
    },
    async queryPermission(){ return 'granted'; }, async requestPermission(){ return 'granted'; } };
  return { h, files, writes };
}
const tick = ms => new Promise(r => setTimeout(r, ms || 30));
const typeIn = (w, x, s) => { x.textContent = s; key(w, x, 'Enter'); };
(async () => {
  ok(page(DATA).split('/*MODIFICHE*/null/*FINE*/').length === 2, 'lo stampo ha un segnaposto per le modifiche');
  {
    const { w, d, errs } = openEd(page(DATA));
    const $ = id => d.getElementById(id);
    const cap1 = () => d.querySelector('#strip .spread[data-i="0"] .cap .tt');
    ok($('edit') && !$('edit').hidden && $('editL').textContent === it['gal.ed.edit'] && $('editcard').hidden &&
       !d.body.classList.contains('editing'), 'il pulsante «' + it['gal.ed.edit'] + '»; il foglietto della modifica nascosto');
    $('edit').click();
    ok(d.body.classList.contains('editing') && !$('editcard').hidden && $('edit').getAttribute('aria-pressed') === 'true' &&
       $('edT').textContent.includes(it['gal.ed.title']) && cap1().getAttribute('tabindex') === '0',
       'modificando: il foglietto giallo, i testi raggiungibili col tasto Tab');
    ok(!$('edS').textContent && $('edSave').hidden, 'ancora nessuna modifica: nessuno stato, niente da salvare');
    ev(w, cap1(), 'click');
    ok(cap1().getAttribute('contenteditable') && cap1().classList.contains('typing') && !$('lb').classList.contains('on'),
       'un clic sul titolo lo apre dove sta, invece di aprire la foto');
    const sx = w.scrolled;
    cap1().textContent = 'Il cratere';
    key(w, cap1(), 'ArrowRight');
    ok(w.scrolled === sx && cap1().getAttribute('contenteditable'), 'scrivendo, le frecce restano al testo (la fila non scorre)');
    key(w, cap1(), 'Enter');
    ok(!cap1().hasAttribute('contenteditable') && cap1().textContent === 'Il cratere' && cap1().classList.contains('mod'),
       'Invio conferma: il titolo nuovo, col segno a matita');
    ok(d.querySelector('.fr[data-pi="0"]').title === '1 · Il cratere' &&
       d.querySelector('#strip .polaroid[data-pi="0"]').getAttribute('aria-label') === '1 · Il cratere',
       'il titolo nuovo anche nel rullino e per chi legge lo schermo');
    let dr = JSON.parse(w.localStorage.getItem(ITKEY));
    ok(dr && dr.v === 1 && dr.ed.photos['1'].title === 'Il cratere', 'la modifica aspetta in questo browser');
    ok($('edS').textContent === it['gal.ed.st_browser'] && $('edSave').textContent === it['gal.ed.download'] && !$('edSub').hidden &&
       $('edSub').textContent.includes('2026-10-28_20-19-38'), 'browser che non scrive nelle cartelle: «' + it['gal.ed.download'] + '», e dove metterlo');
    // Esc annulla
    const what2 = d.querySelector('#strip .spread[data-i="1"] .note p[data-ed="what"]');
    const prima = what2.textContent;
    ev(w, what2, 'click');
    what2.textContent = 'Non va bene';
    key(w, what2, 'Escape');
    ok(what2.textContent === prima && !what2.hasAttribute('contenteditable') && d.body.classList.contains('editing'), 'Esc annulla: il testo di prima');
    // un testo vuotato: guardando sparisce, modificando resta (per riscriverlo)
    ev(w, what2, 'click');
    typeIn(w, what2, '   ');
    const sec = what2.closest('.sec');
    ok(sec.classList.contains('empty') && w.getComputedStyle(sec).display !== 'none' && what2.getAttribute('data-ph') === it['gal.ed.ph_what'],
       'un testo vuotato: modificando resta, col suggerimento «' + it['gal.ed.ph_what'] + '»');
    // il perché che non c'era, su due righe
    const why2 = d.querySelector('#strip .spread[data-i="1"] .note p[data-ed="why"]');
    ev(w, why2, 'click');
    why2.textContent = 'Riga uno\nriga due';
    key(w, why2, 'Enter');
    ok(why2.textContent === 'Riga uno\nriga due' && !why2.closest('.sec').classList.contains('empty'), 'un perché che mancava; due righe restano due');
    // tornare all'originale
    ev(w, cap1(), 'click');
    ok(!$('edchip').hidden, 'sopra un testo cambiato: «' + it['gal.ed.orig'] + '»');
    $('edOrig').click();
    ok(cap1().textContent === 'Titolo 1' && !cap1().classList.contains('mod') && !JSON.parse(w.localStorage.getItem(ITKEY)).ed.photos['1'],
       '↺ rimette il titolo di SketchUp, e la modifica sparisce');
    // il timbro e il titolo della galleria
    const st1 = d.querySelector('#strip .spread[data-i="0"] .stamp');
    ev(w, st1, 'click'); typeIn(w, st1, 'Marco');
    ev(w, $('title'), 'click'); typeIn(w, $('title'), 'Stromboli, di sera');
    ok(st1.textContent === 'Marco' && st1.classList.contains('explorer') && $('title').textContent === 'Stromboli, di sera' &&
       d.title === 'Stromboli, di sera', 'il timbro dice chi vuoi (il filtro resta per autore); il titolo della galleria anche nella scheda');
    // togliere una foto
    const sp3 = d.querySelector('#strip .spread[data-i="2"]');
    sp3.querySelector('.edx').click();
    ok(sp3.classList.contains('gone') && !sp3.hidden && sp3.querySelector('.edx').textContent === '↺' &&
       sp3.querySelector('.edx').getAttribute('aria-label') === it['gal.ed.unhide'] && $('stats').textContent.includes('4 foto'),
       'togliere una foto: modificando resta, sbiadita, con ↺; i numeri contano 4 foto');
    // un commento dell'IA vuotato
    const said = d.querySelector('.said span[data-ed="said"]');
    ev(w, said, 'click'); typeIn(w, said, '');
    $('edDone').click();
    ok(!d.body.classList.contains('editing') && $('editcard').hidden && cap1().getAttribute('tabindex') == null,
       '«' + it['gal.ed.done'] + '»: si torna a guardare');
    ok(sp3.hidden && d.querySelector('.fr[data-pi="2"]').hidden, 'guardando, la foto tolta non c\'è (né nel rullino)');
    ok(w.getComputedStyle(sec).display === 'none' && w.getComputedStyle(said.parentNode).display === 'none',
       'guardando, il testo vuotato e il commento tolto non si vedono');
    ev(w, cap1(), 'click');
    ok(!d.querySelector('#strip .cap .tt[contenteditable]'), 'guardando, un clic sul titolo non lo apre');
    key(w, d.body, 'Escape');
    $('play').click();
    const seen = [d.querySelector('#lb .cap .no').textContent];
    for(let k = 0; k < 6 && !$('lbnext').disabled; k++){ $('lbnext').click(); seen.push(d.querySelector('#lb .cap .no').textContent); }
    ok(seen.length === 4 && !seen.includes('№ 3'), 'la presentazione salta la foto tolta: ' + seen.join(' '));
    key(w, d.body, 'Escape');
    dr = JSON.parse(w.localStorage.getItem(ITKEY));
    ok(dr.ed.title === 'Stromboli, di sera' && dr.ed.photos['1'].by === 'Marco' && dr.ed.photos['2'].what === '' &&
       dr.ed.photos['3'].hide === true && Object.values(dr.ed.notes).includes(''),
       'tutto nella bozza: titolo, timbro, testo vuotato, foto tolta, commento tolto');
    ok(!errs.length, 'nessun errore modificando' + (errs.length ? ': ' + errs[0] : ''));
  }
  // la pagina con le modifiche dentro (da gal_report o da «Salva nella cartella»)
  {
    const ed = { v: 1, title: 'Titolo <b>nuovo</b>', photos: { '4': { what: '<img src=x onerror="window.rotto=1"> */ </script>' }, '5': { hide: true } },
                 notes: { '2.00': 'Detto meglio' } };
    const { w, d, errs } = openEd(withEd(DATA, ed));
    ok(!errs.length && d.getElementById('title').textContent === 'Titolo <b>nuovo</b>' && !w.rotto &&
       d.querySelector('#strip .spread[data-i="3"] .note p').textContent === '<img src=x onerror="window.rotto=1"> */ </script>',
       'le modifiche nella pagina si vedono, e restano testo (anche con */ e </script>)');
    ok(d.querySelector('#strip .spread[data-i="4"]').hidden && d.getElementById('stats').textContent.includes('4 foto') &&
       [...d.querySelectorAll('.said span')].some(s => s.textContent === 'Detto meglio'), 'la foto tolta non c\'è, il commento è quello riscritto');
    d.getElementById('edit').click();
    ok(d.getElementById('edS').textContent === it['gal.ed.st_folder'] && d.getElementById('edSave').hidden,
       'modifiche già nella cartella: «' + it['gal.ed.st_folder'] + '», niente da salvare');
  }
  // la bozza si ritrova; «Salva nella cartella»; poi si salva da sé
  {
    const empty = { v: 1, photos: {}, notes: {} };
    const files = { 'galleria.json': JSON.stringify({ photos: DATA.photos.map(p => ({ file: p.file })) }), 'galleria.html': withEd(DATA, empty) };
    const fd = fakeDir('2026-10-28_20-19-38', files);
    const { w, d, errs } = openEd(withEd(DATA, empty), { dir: fd, draft: { v: 1, ed: { v: 1, photos: { '1': { title: 'Dalla bozza' } }, notes: {} } } });
    const $ = id => d.getElementById(id);
    ok(d.querySelector('#strip .spread[data-i="0"] .cap .tt').textContent === 'Dalla bozza', 'la bozza di questo browser si ritrova');
    $('edit').click();
    ok($('edS').textContent === it['gal.ed.st_browser'] && $('edSave').textContent === it['gal.ed.save'] &&
       $('edSub').textContent === it['gal.ed.pick'].replace('%{dir}', '2026-10-28_20-19-38'), '«' + it['gal.ed.save'] + '», e quale cartella scegliere');
    $('edSave').click();
    await tick(60);
    const saved = JSON.parse(fd.writes['galleria_modifiche.json'] || 'null');
    ok(saved && saved.v === 1 && saved.photos['1'].title === 'Dalla bozza' && saved.saved, 'scritto galleria_modifiche.json nella cartella');
    const m = /\/\*MODIFICHE\*\/([\s\S]*?)\/\*FINE\*\//.exec(fd.writes['galleria.html'] || '');
    ok(m && JSON.parse(m[1]).photos['1'].title === 'Dalla bozza', 'e nella pagina stessa: mandandola a qualcuno, le modifiche ci sono');
    ok($('edS').textContent === it['gal.ed.st_folder'] && $('edS').classList.contains('folder') && $('edSave').hidden &&
       w.localStorage.getItem(ITKEY) === 'null', 'salvate: «' + it['gal.ed.st_folder'] + '», la bozza non serve più');
    const c2 = d.querySelector('#strip .spread[data-i="1"] .cap .tt');
    ev(w, c2, 'click'); typeIn(w, c2, 'Il porto');
    await tick(900);
    ok(JSON.parse(fd.files['galleria_modifiche.json']).photos['2'].title === 'Il porto' && $('edS').textContent === it['gal.ed.st_folder'],
       'cartella scelta: le modifiche dopo si salvano da sé');
    ok(!errs.length, 'nessun errore salvando' + (errs.length ? ': ' + errs[0] : ''));
  }
  // la cartella sbagliata
  {
    const fd = fakeDir('Documenti', { 'galleria.json': JSON.stringify({ photos: [{ file: 'altro.jpg' }] }) });
    const { w, d } = openEd(page(DATA), { dir: fd });
    d.getElementById('edit').click();
    const c = d.querySelector('#strip .spread[data-i="0"] .cap .tt');
    ev(w, c, 'click'); typeIn(w, c, 'X');
    d.getElementById('edSave').click();
    await tick(60);
    ok(!fd.writes['galleria_modifiche.json'] && d.getElementById('edS').textContent === it['gal.ed.st_wrong'].replace('%{dir}', '2026-10-28_20-19-38') &&
       d.getElementById('edS').classList.contains('err'), 'un\'altra cartella: non scrive, e dice quale scegliere');
  }
})();
// le foto in %APPDATA% (D.spare): anche con Edge si scaricano le modifiche
(async () => {
  const fd = fakeDir('x', {});
  const { w, d } = openEd(page(Object.assign({}, DATA, { spare: true })), { dir: fd });
  d.getElementById('edit').click();
  const c = d.querySelector('#strip .spread[data-i="0"] .cap .tt');
  ev(w, c, 'click'); typeIn(w, c, 'Y');
  ok(d.getElementById('edSave').textContent === it['gal.ed.download'], 'foto in %APPDATA%: «' + it['gal.ed.download'] + '» anche dove il browser scrive nelle cartelle');
})();
