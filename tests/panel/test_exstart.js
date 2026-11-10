// Carica exstart.html (la finestra di avvio dell'esploratore) in jsdom con un
// finto `sketchup`, e verifica: testi in tutte le lingue, profilo in uso
// preselezionato, scelta col clic e con le frecce, casella del percorso,
// Invio ed Esc, scelta che resta se l'elenco cambia, occupato.
//   Prima volta:  cd tests/panel && npm install
//   Esecuzione:   node tests/panel/test_exstart.js   (oppure tests\run_tests.bat)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const { JSDOM } = require('jsdom');
const html = fs.readFileSync(path.join(ROOT, 'exstart.html'), 'utf8');
const LANG = path.join(ROOT, 'lang');
const langs = {};
for(const f of fs.readdirSync(LANG).sort()){   // in ordine: la cartella non lo garantisce (su FAT/exFAT è quello di creazione)
  if(!f.endsWith('.json') || f === 'index.json') continue;
  const d = JSON.parse(fs.readFileSync(path.join(LANG, f), 'utf8'));
  langs[f.slice(0, -5)] = Object.fromEntries(Object.entries(d).filter(([k]) => /^xs\./.test(k)));
}
const calls = [];
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  beforeParse(w){
    w.sketchup = {};
    for(const n of ['ready', 'go', 'edit', 'cancel']) w.sketchup[n] = a => calls.push([n, a]);
    w.matchMedia = () => ({ matches: false });
    w.HTMLElement.prototype.scrollIntoView = () => {};
  }
});
const w = dom.window;
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if(!c) process.exitCode = 1; };
const $ = id => w.document.getElementById(id);
const last = n => calls.filter(c => c[0] === n).pop();
const key = k => w.document.getElementById('elenco').dispatchEvent(new w.KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));

const PROF = [
  { id: 'balanced', name: 'Equilibrato', desc: 'Il solito', builtin: true },
  { id: 'curious', name: 'Curioso', desc: 'Si annoia', builtin: true },
  { id: 'photographer', name: 'Fotografo', desc: 'Zoom', builtin: true },
  { id: 'u1', name: 'Il <mio>', desc: '', builtin: false }
];
const stato = (o = {}) => Object.assign({ profiles: PROF, active: 'curious', record: true, busy: false }, o);
const scelto = () => (w.document.querySelector('.prof.on') || {}).dataset;

w.addEventListener('load', () => {
  try {
    ok(calls.length === 1 && calls[0][0] === 'ready', 'caricata, chiede i dati a Ruby (ready)');
    ok(w.document.body.classList.contains('attende'), 'finché Ruby non risponde resta nascosta');

    const rotti = [];
    for(const [c, s] of Object.entries(langs)){
      w.init({ strings: s, lang: c, rtl: c === 'ar' || c === 'he', look: {} });
      w.show(stato({ busy: true }));
      const corpo = w.document.body.cloneNode(true);
      corpo.querySelectorAll('script').forEach(s => s.remove());
      if(/\bxs\.[a-z]/.test(corpo.textContent + w.document.title)) rotti.push(c);
    }
    ok(rotti.length === 0, `testi completi in tutte le ${Object.keys(langs).length} lingue${rotti.length ? ': ' + rotti.join(', ') : ''}`);

    // Pagina nuova per ogni prova vera: l'italiano
    w.init({ strings: langs.it, lang: 'it', rtl: false, look: { theme: 'dark' } });
    w.show(stato());
    ok(!w.document.body.classList.contains('attende'), 'arrivati i dati, si vede');
    ok(w.document.querySelectorAll('.prof').length === 4 && scelto().id === 'curious', 'quattro profili, scelto quello in uso');
    const mio = w.document.querySelectorAll('.prof')[3];
    ok(mio.querySelector('b').textContent === 'Il <mio>' && mio.textContent.includes(langs.it['xs.mine']), 'profilo tuo: nome come testo, segnato «tuo profilo»');
    ok($('rec').checked && $('t-rec').textContent === langs.it['xs.record'], 'casella «Registra il percorso» come l\'ultima volta (spuntata)');
    ok(!$('b-go').disabled && !$('occ').classList.contains('si'), 'si può partire');

    // Clic, frecce (in giro), Invio
    w.document.querySelectorAll('.prof')[2].click();
    ok(scelto().id === 'photographer', 'clic: Fotografo');
    key('ArrowDown');
    ok(scelto().id === 'u1', 'freccia giù: il profilo dopo');
    key('ArrowDown');
    ok(scelto().id === 'balanced', 'dall\'ultimo si torna al primo');
    key('ArrowUp');
    $('rec').click();
    ok(!$('rec').checked, 'tolta la spunta del percorso');
    calls.length = 0;
    key('Enter');
    const g = last('go');
    ok(g && JSON.parse(g[1]).profile === 'u1' && JSON.parse(g[1]).record === false, 'Invio → go {profile: u1, record: false}');

    // L'elenco cambia (un profilo modificato nell'altra finestra): la scelta fatta qui resta
    w.show(stato({ profiles: PROF.concat([{ id: 'u2', name: 'Altro', desc: '', builtin: false }]), record: true }));
    ok(scelto().id === 'u1' && !$('rec').checked && w.document.querySelectorAll('.prof').length === 5, 'elenco rifatto: scelta e spunta restano');

    // Doppio clic parte; pulsanti
    calls.length = 0;
    w.document.querySelectorAll('.prof')[1].dispatchEvent(new w.MouseEvent('click', { bubbles: true }));
    w.document.querySelectorAll('.prof')[1].dispatchEvent(new w.MouseEvent('dblclick', { bubbles: true }));
    ok(last('go') && JSON.parse(last('go')[1]).profile === 'curious', 'doppio clic su un profilo: parte con quello');
    calls.length = 0;
    $('b-go').click(); $('b-edit').click(); $('b-cancel').click();
    ok(calls.map(c => c[0]).join() === 'go,edit,cancel', 'pulsanti Esplora, Modifica i profili, Annulla');
    calls.length = 0;
    w.document.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    ok(last('cancel'), 'Esc chiude');

    // Occupato: non parte, e lo dice
    w.show(stato({ busy: true }));
    calls.length = 0;
    key('Enter');
    ok($('b-go').disabled && $('occ').classList.contains('si') && !last('go'), 'occupato: Esplora spento, nota, Invio non parte');

    w.init({ strings: langs.he, lang: 'he', rtl: true, look: {} });
    ok(w.document.documentElement.dir === 'rtl', 'ebraico: da destra a sinistra');
  } catch(e){
    ok(false, 'eccezione: ' + e.stack);
  }
  console.log(process.exitCode ? '\nCI SONO TEST FALLITI' : '\nTUTTI I TEST PASSATI');
  w.close();
});
