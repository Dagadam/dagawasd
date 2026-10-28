// Carica exprofiles.html (i profili dell'esploratore autonomo) in jsdom con
// un finto `sketchup`, e verifica: testi in tutte le lingue, elenco dei
// profili, valori nel formato della lingua, cursori che provano dal vivo e
// salvano al rilascio, campi, ripristino di un singolo valore, pulsanti,
// scrittura da destra a sinistra.
//   Prima volta:  cd tests/panel && npm install
//   Esecuzione:   node tests/panel/test_exprofiles.js   (oppure tests\run_tests.bat)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const { JSDOM } = require('jsdom');
const html = fs.readFileSync(path.join(ROOT, 'exprofiles.html'), 'utf8');
const LANG = path.join(ROOT, 'lang');
const langs = {};
for(const f of fs.readdirSync(LANG)){
  if(!f.endsWith('.json') || f === 'index.json') continue;
  const d = JSON.parse(fs.readFileSync(path.join(LANG, f), 'utf8'));
  langs[f.slice(0, -5)] = Object.fromEntries(Object.entries(d).filter(([k]) => /^xp\./.test(k)));
}
const calls = [];
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  beforeParse(w){
    w.sketchup = {};
    for(const n of ['ready', 'use', 'set', 'act']) w.sketchup[n] = a => calls.push([n, a]);
    w.matchMedia = () => ({ matches: false });
  }
});
const w = dom.window;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if(!c) process.exitCode = 1; };
const $ = id => w.document.getElementById(id);
const sets = () => calls.filter(c => c[0] === 'set').map(c => JSON.parse(c[1]));

// Come li manda lib/exprofiles.rb (xp_state)
const BASE = { speed: 1.1, standoff: 1.2, max_drop: 0.8, mode: 'auto', bob: true, turn_speed: 110, pitch_max: 50,
               step_time: 0.45, dwell: 1.8, attention: 25, commit: 2.5, sticky: 1.4, curiosity: 1, boredom: 20,
               roam: 1, whim: 0.04, continuity: 1, w_object: 1, w_shape: 1, w_detail: 1, w_color: 1, w_rare: 1, pixels: false,
               zoom: false, zoom_fill: 0.5, zoom_max: 6, zoom_hold: 1.5, jump: true, orbit: 0 };
const PROF = [
  { id: 'balanced', name: 'Equilibrato', desc: 'Il solito', builtin: true, modified: true },
  { id: 'curious', name: 'Curioso', desc: 'Si annoia', builtin: true, modified: false },
  { id: 'u1', name: 'Il <mio>', desc: '', builtin: false, modified: false }
];
const stato = (o = {}) => Object.assign({ profiles: PROF, active: 'balanced', values: Object.assign({}, BASE, { speed: 1.6 }),
  base: BASE, running: false, running_profile: null, busy: false }, o);

w.addEventListener('load', async () => {
  try {
    ok(calls.length === 1 && calls[0][0] === 'ready', 'caricata, chiede i dati a Ruby (ready)');
    ok(w.document.body.classList.contains('attende'), 'finché Ruby non risponde resta nascosta');

    // Ogni lingua: nessun testo mancante (resterebbe la chiave) né segnaposto rimasto
    const rotti = [];
    for(const [c, s] of Object.entries(langs)){
      w.init({ strings: s, lang: c, rtl: c === 'ar' || c === 'he', look: {} });
      w.show(stato({ running: true, running_profile: 'balanced' }));
      const corpo = w.document.body.cloneNode(true);
      corpo.querySelectorAll('script').forEach(s => s.remove());
      const testo = corpo.textContent + w.document.title +
        [...w.document.querySelectorAll('[title]')].map(e => e.title).join(' ');
      if(/\bxp\.[a-z]/.test(testo) || /\{v\}|%\{name\}/.test(testo)) rotti.push(c);
    }
    ok(rotti.length === 0, `testi completi in tutte le ${Object.keys(langs).length} lingue${rotti.length ? ': ' + rotti.join(', ') : ''}`);
    ok(w.document.documentElement.dir === 'ltr', 'dopo l\'ultima lingua (zh) da sinistra a destra');

    // Italiano
    w.init({ strings: langs.it, lang: 'it', rtl: false, look: { theme: 'dark', accent: '#00c9a7' } });
    w.show(stato());
    ok(!w.document.body.classList.contains('attende'), 'arrivati i valori, si vede');
    const voci = [...$('elenco').querySelectorAll('.prof')];
    ok(voci.length === 3 && voci[0].classList.contains('on') && $('elenco').querySelector('.sep') &&
       voci[2].querySelector('b').textContent === 'Il <mio>', 'elenco: già pronti, una riga, i tuoi (nomi come testo, non HTML)');
    ok(voci[0].textContent.includes(langs.it['xp.modified']) && voci[2].textContent.includes(langs.it['xp.mine']), 'segnati «modificato» e «tuo»');
    ok($('nome').textContent === 'Equilibrato' && $('desc').textContent === 'Il solito', 'nome e descrizione del profilo in uso');
    ok($('f-speed').value === '1,6' && $('r-speed').value === '1.6' && $('f-whim').value === '4' && $('f-zoom_fill').value === '50',
       'numeri nel formato della lingua; le parti in percentuale × 100');
    ok($('w-speed').classList.contains('mod') && !$('w-dwell').classList.contains('mod'), 'il valore cambiato rispetto all\'originale è segnato');
    ok($('z-speed').title === 'Torna a 1,1 m/s', `↺: «${$('z-speed').title}»`);
    ok($('b-rename').disabled && $('b-delete').disabled && !$('b-reset').disabled, 'profilo già pronto e modificato: Ripristina sì, Rinomina ed Elimina no');
    ok($('b-run').textContent.includes(langs.it['xp.start']) && !$('b-run').disabled, 'pulsante Esplora');
    ok(!$('vivo').classList.contains('si'), 'fermo: nessuna nota «dal vivo»');

    // Cursore: mentre si trascina prova dal vivo (save false, al più ogni 120 ms), al rilascio salva
    calls.length = 0;
    const r = $('r-speed');
    r.value = '2'; r.dispatchEvent(new w.Event('input'));
    r.value = '2.5'; r.dispatchEvent(new w.Event('input'));
    ok($('f-speed').value === '2,5', 'il numero accanto segue il cursore');
    ok(sets().length === 1 && sets()[0].v === 2 && sets()[0].save === false, 'il primo movimento parte subito, senza salvare');
    await sleep(160);
    ok(sets().length === 2 && sets()[1].v === 2.5 && sets()[1].save === false, 'gli altri al più ogni 120 ms (l\'ultimo arriva)');
    r.dispatchEvent(new w.Event('change'));
    ok(sets().pop().save === true, 'rilasciato: salva');

    // Percentuale: il cursore mostra 0–100, a Ruby va la frazione
    calls.length = 0;
    $('r-whim').value = '30'; $('r-whim').dispatchEvent(new w.Event('change'));
    ok(sets()[0].k === 'whim' && Math.abs(sets()[0].v - 0.3) < 1e-9, 'capriccio 30 % → 0.3');

    // Campo di testo: virgola, Invio, testo non numerico
    calls.length = 0;
    $('f-dwell').value = '3,5';
    $('f-dwell').dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Enter' }));
    ok(sets()[0].k === 'dwell' && sets()[0].v === 3.5 && sets()[0].save === true, 'sosta 3,5 + Invio → set {dwell, 3.5, salva}');
    calls.length = 0;
    $('f-dwell').value = 'boh';
    $('f-dwell').dispatchEvent(new w.Event('change'));
    ok(sets().length === 0 && $('f-dwell').value === '1,8', 'un testo che non è un numero: niente a Ruby, torna il valore');

    // Caselle e scelte
    calls.length = 0;
    $('f-zoom').checked = true; $('f-zoom').dispatchEvent(new w.Event('change'));
    $('f-mode').value = 'fly'; $('f-mode').dispatchEvent(new w.Event('change'));
    ok(sets()[0].k === 'zoom' && sets()[0].v === true && sets()[1].k === 'mode' && sets()[1].v === 'fly', 'casella dello zoom e scelta del modo');
    ok([...$('f-mode').options].map(o => o.textContent).join('/') === 'Automatico/A piedi/In volo', 'il modo con i nomi tradotti');

    // ↺ rimanda il valore originale
    calls.length = 0;
    $('z-speed').click();
    ok(sets()[0].k === 'speed' && sets()[0].v === 1.1 && sets()[0].save === true, '↺ rimette la velocità originale');

    // Scelta di un profilo, pulsanti
    calls.length = 0;
    voci[1].click();
    ok(calls[0] && calls[0][0] === 'use' && calls[0][1] === 'curious', 'clic su un profilo → use');
    calls.length = 0;
    $('b-new').click(); $('b-reset').click();
    ok(calls.map(c => c[1]).join() === 'new,reset', 'Nuovo, Ripristina → act');

    // Un profilo tuo, in uso dall'esploratore: niente valori originali, Ferma
    w.show(stato({ active: 'u1', base: null, running: true, running_profile: 'u1' }));
    ok(!$('b-rename').disabled && !$('b-delete').disabled && $('b-reset').disabled, 'profilo tuo: Rinomina ed Elimina sì, Ripristina no');
    ok(!w.document.querySelector('.riga.mod') && $('desc').textContent === '', 'niente segni di modifica né descrizione');
    ok($('vivo').classList.contains('si') && $('vivo').textContent === langs.it['xp.live'], 'nota: le modifiche valgono subito');
    calls.length = 0;
    $('b-run').click();
    ok($('b-run').textContent.includes(langs.it['xp.stop']) && calls[0][1] === 'stop', 'mentre esplora il pulsante ferma');
    w.show(stato({ busy: true }));
    ok($('b-run').disabled, 'occupato (camminata, video, ponte): Esplora spento');

    // Mentre si scrive in un campo, un aggiornamento non lo cancella
    $('f-attention').focus();
    $('f-attention').value = '4';
    w.show(stato());
    ok($('f-attention').value === '4', 'un aggiornamento non cancella quello che si sta scrivendo');
    $('f-attention').dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Enter' }));
    w.show(stato({ values: Object.assign({}, BASE, { attention: 3 }) }));     // Ruby: nei limiti, 3 s
    ok($('f-attention').value === '3', 'confermato con Invio: il campo mostra il valore nei limiti rimandato da Ruby');
    $('f-attention').blur();

    // Da destra a sinistra
    w.init({ strings: langs.ar, lang: 'ar', rtl: true, look: {} });
    ok(w.document.documentElement.dir === 'rtl' && w.document.documentElement.lang === 'ar', 'arabo: da destra a sinistra');

    // Mai il menu del browser
    const ev = new w.MouseEvent('contextmenu', { cancelable: true, bubbles: true });
    w.document.body.dispatchEvent(ev);
    ok(ev.defaultPrevented, 'tasto destro: niente menu del browser');
  } catch(e){
    ok(false, 'eccezione: ' + e.stack);
  }
  console.log(process.exitCode ? '\nCI SONO TEST FALLITI' : '\nTUTTI I TEST PASSATI');
  w.close();
});
