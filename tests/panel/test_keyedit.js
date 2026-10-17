// Carica keyedit.html (il pannello di una sfera dei percorsi) in jsdom con un
// finto `sketchup`, e verifica: testi in tutte le lingue, valori nel formato
// della lingua, campi che mandano a Ruby il numero giusto, anteprima,
// navigazione ai capi, velocità automatica, scrittura da destra a sinistra.
//   Prima volta:  cd tests/panel && npm install
//   Esecuzione:   node tests/panel/test_keyedit.js   (oppure tests\run_tests.bat)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const { JSDOM } = require('jsdom');
const html = fs.readFileSync(path.join(ROOT, 'keyedit.html'), 'utf8');
const LANG = path.join(ROOT, 'lang');
const langs = {};
for(const f of fs.readdirSync(LANG)){
  if(!f.endsWith('.json') || f === 'index.json') continue;
  const d = JSON.parse(fs.readFileSync(path.join(LANG, f), 'utf8'));
  langs[f.slice(0, -5)] = Object.fromEntries(Object.entries(d).filter(([k]) => /^ke\./.test(k)));
}
const calls = [];
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  beforeParse(w){
    w.sketchup = {};
    for(const n of ['ready', 'set', 'nav', 'preview', 'act', 'paste']) w.sketchup[n] = a => calls.push([n, a]);
    w.matchMedia = () => ({ matches: false });
  }
});
const w = dom.window;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if(!c) process.exitCode = 1; };
const $ = id => w.document.getElementById(id);
const last = n => calls.filter(c => c[0] === n).pop();
const V = { path: 'Giro', i: 1, n: 3, x: 1.5, y: -2.25, z: 1.7, ground: 1.7, az: 90, pitch: -5.5, roll: 0,
            fov: 70, zoom: 1, pause: 0, v: 0, v_auto: 1.4, seg: 4.25, arrive: 0, preview: false, busy: false };

w.addEventListener('load', async () => {
  try {
    ok(calls.length === 1 && calls[0][0] === 'ready', 'caricata, chiede i dati a Ruby (ready)');
    ok(w.document.body.classList.contains('attende'), 'finché Ruby non risponde resta nascosta');

    // Ogni lingua: nessun testo mancante (resterebbe la chiave) né segnaposto rimasto
    let rotti = [];
    for(const [c, s] of Object.entries(langs)){
      w.init({ strings: s, lang: c, rtl: c === 'ar' || c === 'he', look: {} });
      w.show(V);
      const corpo = w.document.body.cloneNode(true);
      corpo.querySelectorAll('script').forEach(s => s.remove());          // il codice contiene le chiavi
      const testo = corpo.textContent + w.document.title +
        [...w.document.querySelectorAll('[title]')].map(e => e.title).join(' ');
      if(/\bke\.[a-z]/.test(testo) || /\{(path|i|n|v|s|t)\}/.test(testo)) rotti.push(c);
    }
    ok(rotti.length === 0, `testi completi in tutte le ${Object.keys(langs).length} lingue${rotti.length ? ': ' + rotti.join(', ') : ''}`);

    // Italiano: numeri con la virgola, titolo, stato dei pulsanti
    w.init({ strings: langs.it, lang: 'it', rtl: false, look: { theme: 'dark', accent: '#00c9a7' } });
    w.show(V);
    ok(!w.document.body.classList.contains('attende'), 'arrivati i valori, si vede');
    ok($('titolo').textContent === 'Giro · posizione 1 di 3', `titolo: «${$('titolo').textContent}»`);
    ok($('f-x').value === '1,50' && $('f-y').value === '-2,25' && $('f-pitch').value === '-5,5', 'numeri nel formato della lingua (virgola)');
    ok($('b-prev').disabled && !$('b-next').disabled, 'sulla prima: «precedente» spento, «successiva» acceso');
    ok($('f-vauto').checked && $('f-v').disabled && $('f-v').value === '1,40', 'velocità automatica: casella spuntata, campo spento col valore del percorso');
    ok($('t-seg').textContent.includes('4,3') && $('t-arrive').textContent.includes('0,0 s'), 'durata del tratto e arrivo');

    // Un campo confermato manda il numero (anche scritto con la virgola)
    calls.length = 0;
    $('f-z').value = '2,5';
    $('f-z').dispatchEvent(new w.Event('change'));
    const s = last('set');
    ok(s && JSON.parse(s[1]).f === 'z' && JSON.parse(s[1]).v === 2.5, 'quota 2,5 → set {f: z, v: 2.5}');
    calls.length = 0;
    $('f-roll').value = 'abc';
    $('f-roll').dispatchEvent(new w.Event('change'));
    ok(!last('set') && $('f-roll').value === '0,0', 'un testo che non è un numero: niente a Ruby, torna il valore');
    $('f-fov').value = '45';
    $('f-fov').dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Enter' }));
    ok(last('set') && JSON.parse(last('set')[1]).f === 'fov', 'Invio nel campo conferma come uscire dal campo');

    // Velocità propria, anteprima, pulsanti
    $('f-vauto').checked = false;
    $('f-vauto').dispatchEvent(new w.Event('change'));
    ok(JSON.parse(last('set')[1]).f === 'vauto' && JSON.parse(last('set')[1]).v === false, 'tolta «Automatica»: Ruby lo sa');
    w.show(Object.assign({}, V, { v: 2.5, i: 3 }));
    ok(!$('f-v').disabled && $('f-v').value === '2,50' && !$('f-vauto').checked, 'velocità propria: campo acceso col suo valore');
    ok(!$('b-prev').disabled && $('b-next').disabled, 'sull\'ultima: «successiva» spento');
    $('anteprima').click();
    ok(last('preview') && last('preview')[1] === true, 'spuntata l\'anteprima: preview(true)');
    $('b-prev').click();
    ok(last('nav') && last('nav')[1] === -1, '◀: nav(-1)');
    for(const [b, a] of [['b-view', 'from_view'], ['b-insert', 'insert'], ['b-delete', 'delete']]){
      $(b).click();
      ok(last('act') && last('act')[1] === a, `${b}: act(${a})`);
    }
    w.show(Object.assign({}, V, { busy: true }));
    ok(w.document.body.classList.contains('occupato'), 'durante una riproduzione i comandi si spengono');

    // Da destra a sinistra: verso del documento e frecce scambiate
    w.init({ strings: langs.he, lang: 'he', rtl: true, look: {} });
    w.show(V);
    ok(w.document.documentElement.dir === 'rtl' && $('b-prev').textContent === '▶', 'ebraico: da destra a sinistra, «precedente» punta a destra');

    // ── Pulsanti − e + ───────────────────────────────────────────────
    w.init({ strings: langs.it, lang: 'it', rtl: false, look: {} });
    w.show(V);
    const giu = b => $(b).dispatchEvent(new w.MouseEvent('pointerdown', { button: 0 }));
    const su = b => $(b).dispatchEvent(new w.MouseEvent('pointerup', { button: 0 }));
    const sets = () => calls.filter(c => c[0] === 'set').map(c => JSON.parse(c[1]));
    ok($('m-z') && $('p-z') && $('m-z').textContent === '−' && $('p-z').textContent === '+', 'ogni campo ha − prima e + dopo');
    calls.length = 0;
    giu('p-z'); su('p-z');
    ok(sets().length === 1 && sets()[0].f === 'z' && Math.abs(sets()[0].v - 1.8) < 1e-9 && $('f-z').value === '1,80', '+ sulla quota: 1,70 → 1,80 m, mandato a Ruby');
    calls.length = 0;
    giu('m-az'); su('m-az');
    ok(sets().length === 1 && sets()[0].f === 'az' && sets()[0].v === 85, '− sulla direzione: 90° → 85° (passo 5°)');
    calls.length = 0;
    giu('p-pitch');
    await sleep(700);                                    // 400 ms d'attesa, poi un passo ogni 90 ms
    su('p-pitch');
    const s2 = sets();
    ok(s2.length === 1 && s2[0].f === 'pitch' && s2[0].v >= -5.5 + 4, `tenuto premuto: scorre (${s2.length && s2[0].v}°) e a Ruby va una volta sola, al rilascio`);
    calls.length = 0;
    await sleep(300);
    ok(sets().length === 0, 'rilasciato, si ferma');
    w.show(Object.assign({}, V, { ground: null }));
    ok($('m-ground').disabled && $('p-ground').disabled, 'niente terreno sotto: − e + spenti come il campo');
    ok($('m-v').disabled && $('p-v').disabled, 'velocità automatica: − e + spenti');
    calls.length = 0;
    giu('p-ground'); su('p-ground');
    ok(sets().length === 0, 'un pulsante spento non manda nulla');
    w.show(Object.assign({}, V, { v: 2.5 }));
    calls.length = 0;
    giu('m-v'); su('m-v');
    ok(sets().length === 1 && Math.abs(sets()[0].v - 2.4) < 1e-9, 'velocità propria: − da 2,50 a 2,40 m/s');

    // ── Destro su − o +: il valore scorre da solo ────────────────────
    const menu = el => !el.dispatchEvent(new w.MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
    ok(menu($('p-z')) && menu($('titolo')), 'clic destro su − o + (e nel resto del pannello): niente menu del browser');
    // Caselle di testo: il menu nostro, tradotto, con Taglia, Copia, Incolla
    ok(menu($('f-z')) && $('menuctx').classList.contains('aperto'), 'destro in una casella: niente menu del browser, si apre il nostro');
    ok($('t-cut').textContent === 'Taglia' && $('t-copy').textContent === 'Copia' && $('t-paste').textContent === 'Incolla',
       'in italiano: Taglia, Copia, Incolla');
    ok($('c-cut').disabled && $('c-copy').disabled && !$('c-paste').disabled, 'niente selezionato: Taglia e Copia spenti, Incolla acceso');
    w.document.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
    ok(!$('menuctx').classList.contains('aperto'), 'Esc lo chiude');
    $('f-z').value = '1,70';
    $('f-z').setSelectionRange(0, 1);
    menu($('f-z'));
    ok(!$('c-cut').disabled && !$('c-copy').disabled, 'con una selezione Taglia e Copia si accendono');
    let comando = null;
    w.document.execCommand = c => { comando = c; return true; };
    $('c-copy').click();
    ok(comando === 'copy' && !$('menuctx').classList.contains('aperto'), 'Copia: il comando copia del browser, menu chiuso');
    calls.length = 0;
    $('f-z').setSelectionRange(0, 4);
    menu($('f-z'));
    $('c-paste').click();
    ok(last('paste'), 'Incolla: gli appunti si chiedono a Ruby (la pagina non può leggerli)');
    w.incolla('3,25\r\n');
    ok($('f-z').value === '3,25' && !last('set'), 'il testo entra al posto della selezione (senza a capo), non ancora confermato');
    $('f-z').dispatchEvent(new w.Event('blur'));
    ok(last('set') && JSON.parse(last('set')[1]).f === 'z' && JSON.parse(last('set')[1]).v === 3.25, 'uscendo dalla casella si conferma: 3,25 m');
    w.show(Object.assign({}, V, { ground: null }));
    $('menuctx').classList.remove('aperto');
    menu($('f-ground'));
    ok(!$('menuctx').classList.contains('aperto'), 'casella spenta: nessun menu');
    w.init({ strings: langs.de, lang: 'de', rtl: false, look: {} });
    ok($('t-paste').textContent === 'Einfügen', 'in tedesco: Einfügen');
    w.init({ strings: langs.it, lang: 'it', rtl: false, look: {} });
    w.show(V);
    calls.length = 0;
    const destro = b => $(b).dispatchEvent(new w.MouseEvent('pointerdown', { button: 2, bubbles: true, cancelable: true }));
    const sinistro = el => { el.dispatchEvent(new w.MouseEvent('pointerdown', { button: 0, bubbles: true, cancelable: true }));
                             el.dispatchEvent(new w.MouseEvent('click', { button: 0, bubbles: true, cancelable: true })); };
    destro('p-z');
    ok($('p-z').classList.contains('corre'), 'destro su +: parte, il pulsante si illumina');
    await sleep(1000);
    const z1 = Number($('f-z').value.replace(',', '.'));
    const corsi = sets();
    ok(z1 > 1.7 + 0.8 && z1 < 1.7 + 1.2, `dopo un secondo circa un'unità in più (${z1} m)`);
    ok(corsi.length >= 6 && corsi.length <= 12 && corsi.every(s => s.f === 'z' && s.run && s.run === corsi[0].run),
       `a SketchUp circa 10 volte al secondo (${corsi.length}), tutte della stessa corsa`);
    const passi = new Set(corsi.map(s => Math.round(s.v * 100) % 1 === 0));
    ok(passi.size === 1 && passi.has(true), 'valori a centesimi');
    calls.length = 0;
    sinistro($('b-next'));
    const fine = sets();
    ok(!$('p-z').classList.contains('corre') && fine.length === 1 && fine[0].run === corsi[0].run &&
       Math.abs(fine[0].v - Number($('f-z').value.replace(',', '.'))) < 1e-9, 'un clic sinistro la ferma sul valore del momento');
    ok(!last('nav'), 'il clic che ferma non preme ciò che ha sotto (qui «successiva»)');
    await sleep(300);
    ok(sets().length === 1, 'fermata: non manda più nulla');
    calls.length = 0;
    w.show(V);
    destro('m-az');
    await sleep(500);
    destro('m-az');
    const az = sets();
    ok(!$('m-az').classList.contains('corre') && az.length >= 3 && az[az.length - 1].v < 90 && az[az.length - 1].v > 89,
       `destro su −: la direzione scende (${az.length && az[az.length - 1].v}°); un altro destro la ferma`);
    ok(menu($('m-az')), 'e dopo il destro che ferma niente menu');
  } catch(e){
    ok(false, 'eccezione: ' + e.stack);
  }
  console.log(process.exitCode ? '\nTEST FALLITI' : '\nTUTTI I TEST PASSATI');
});
