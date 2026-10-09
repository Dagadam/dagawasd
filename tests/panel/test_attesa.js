// Carica attesa.html (la finestra durante il video) in jsdom con un finto
// `sketchup`, e verifica: battute in tutte le lingue senza segnaposto rimasti,
// avanzamento, traguardi, finale, tasti e scrittura da destra a sinistra.
//   Prima volta:  cd tests/panel && npm install
//   Esecuzione:   node tests/panel/test_attesa.js   (oppure tests\run_tests.bat)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const { JSDOM } = require('jsdom');
const html = fs.readFileSync(path.join(ROOT, 'attesa.html'), 'utf8');
const LANG = path.join(ROOT, 'lang');
const langs = {};
for(const f of fs.readdirSync(LANG)){
  if(!f.endsWith('.json') || f === 'index.json') continue;
  const d = JSON.parse(fs.readFileSync(path.join(LANG, f), 'utf8'));
  langs[f.slice(0, -5)] = Object.fromEntries(Object.entries(d).filter(([k]) => /^(att|fun)\./.test(k)));
}
const rtl = JSON.parse(fs.readFileSync(path.join(LANG, 'index.json'), 'utf8')).languages.filter(l => l.rtl).map(l => l.code);
const calls = [];
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  beforeParse(w){
    w.sketchup = {};
    for(const n of ['ready', 'stop', 'close', 'open']) w.sketchup[n] = a => calls.push([n, a]);
    w.matchMedia = () => ({ matches: false });
  }
});
const w = dom.window;
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if(!c) process.exitCode = 1; };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const $ = id => w.document.getElementById(id);

// Statistiche come le manda attesa_stats: valori che accendono molte battute
const STATS = { name:'Giro', model:'Faro', m:340.4, up:7.2, down:1.1, turn:1100, rec:130.5, kmh:4.2, speed:1.5,
  fps:60, total:7800, vid:130, w:3840, h:2160, format:'avi', faces:21345, mats:12, comps:14, scenes:3, weather:true };

w.addEventListener('load', async () => {
  try {
    ok(calls.length === 1 && calls[0][0] === 'ready', 'caricata, chiede i dati a Ruby (ready)');

    // ── Tutte le lingue: ogni battuta ha i suoi valori ───────────────
    const jokes = w.eval('JOKES.map(j => j.k)');
    const q = { k: 900, total: 7800, frac: .115, el: 600, ok: true, spf: .66, eta: 4550, mb: 380, est: 3300, vpm: 1.5 };
    const finals = { n: '21', time: '0:02', mb: '1,2' };
    let bad = [];
    for(const [code, L] of Object.entries(langs)){
      w.eval(`L = ${JSON.stringify(L)}; LANG = ${JSON.stringify(code)};`);
      for(const k of jokes){
        const out = w.eval(`(() => { const j = JOKES.find(x => x.k === ${JSON.stringify(k)}); return fill(T(j.k), j.v ? j.v(${JSON.stringify(STATS)}, ${JSON.stringify(q)}) : {}); })()`);
        if(out.includes('%{') || out === k) bad.push(`${code} ${k}`);
      }
      for(const k of ['fun.start', 'fun.p25', 'fun.p50', 'fun.p75', 'fun.p90', 'fun.done', 'fun.done_png', 'fun.stopped',
                      'fun.stopped_png', 'fun.none', 'fun.full', 'fun.error']){
        const out = w.eval(`fill(T(${JSON.stringify(k)}), ${JSON.stringify(Object.assign({ total: '7.800' }, finals))})`);
        if(out.includes('%{') || out === k) bad.push(`${code} ${k}`);
      }
    }
    ok(bad.length === 0, `${jokes.length} battute e i finali in ${Object.keys(langs).length} lingue, nessun segnaposto rimasto${bad.length ? ': ' + bad.slice(0, 8).join(', ') : ''}`);
    const cond = w.eval(`JOKES.filter(j => { try { j.w(${JSON.stringify(STATS)}, ${JSON.stringify(q)}); return false; } catch(e){ return true; } }).map(j => j.k)`);
    ok(cond.length === 0, 'nessuna condizione va in errore');
    const empty = w.eval(`JOKES.filter(j => { try { return j.w({}, { ok: false }); } catch(e){ return true; } }).map(j => j.k)`);
    ok(empty.join() === 'fun.click', `senza statistiche resta solo la battuta sempre valida (${empty.join(', ')})`);

    // ── Avvio in italiano ────────────────────────────────────────────
    const look = { theme: 'dark', accent: '#00c9a7', highlight: '#ffd166', danger: '#c04747' };
    w.eval(`init(${JSON.stringify({ strings: langs.it, lang: 'it', rtl: false, look, image: null, stats: STATS })})`);
    w.eval(`progress({ k: 0, total: 7800, bytes: 0, el: 0.4 })`);
    await sleep(450);
    ok(/7\.?800/.test($('battuta').textContent) && !$('battuta').innerHTML.includes('%{'), `prima battuta con i fotogrammi: «${$('battuta').textContent}»`);
    ok($('b-stop').textContent === langs.it['att.stop'] && $('b-close').hidden && $('b-file').hidden, 'in corso: solo «Interrompi»');
    ok($('stat').querySelectorAll('dt').length === 10 && $('stat').textContent.includes('3840×2160 · 60 fps'), '10 statistiche, risoluzione e fps');
    ok($('stat').textContent.includes('21.345') && $('stat').textContent.includes('340 m'), 'numeri col separatore italiano');
    ok(w.document.documentElement.style.getPropertyValue('--acc') === '#00c9a7', 'accento del pannello');

    w.eval('lastSay = -1e9');      // la battuta di prima è stata letta: il traguardo non aspetta
    w.eval(`progress({ k: 2000, total: 7800, bytes: 52428800, el: 1300 })`);
    ok($('pct').textContent === '25%' && $('riemp').style.width.startsWith('25.6'), `barra al ${$('pct').textContent}`);
    await sleep(450);
    ok($('battuta').textContent === langs.it['fun.p25'], 'superato un quarto: lo dice subito');
    ok($('stat').textContent.includes('50 MB') && $('stat').textContent.includes('→ ~195 MB'), 'MB scritti e stima finale');

    // ── Esc ──────────────────────────────────────────────────────────
    calls.length = 0;
    w.document.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
    ok(calls.length === 1 && calls[0][0] === 'stop', 'Esc durante l\'esportazione: stop');

    // ── Finale ───────────────────────────────────────────────────────
    w.eval(`finish({ why: 'fine', n: 7800, time: '2:10', mb: 210.4, file: 'C:\\\\Video\\\\Giro.avi', el: 5200 })`);
    await sleep(450);
    ok($('battuta').textContent.includes('2:10') && $('battuta').textContent.includes('210,4'), `finale: «${$('battuta').textContent}»`);
    ok($('pct').textContent === '100%' && w.document.body.classList.contains('finito'), 'barra piena');
    ok($('b-stop').hidden && !$('b-close').hidden && !$('b-file').hidden && !$('b-dir').hidden, 'alla fine: guarda, cartella, chiudi');
    ok($('dove').textContent.includes('C:\\Video\\Giro.avi'), 'dove sta il file');
    calls.length = 0;
    $('b-file').click(); $('b-dir').click();
    w.document.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
    ok(JSON.stringify(calls) === JSON.stringify([['open', 'file'], ['open', 'dir'], ['close', '']]), 'pulsanti e Esc dopo la fine: apri file, apri cartella, chiudi');
    const before = $('battuta').textContent;
    w.eval('nextJoke()');
    await sleep(450);
    ok($('battuta').textContent === before, 'finito: le battute non cambiano più il finale');

    // ── Interrotta subito, PNG ───────────────────────────────────────
    w.eval(`FIN = null; init(${JSON.stringify({ strings: langs.it, lang: 'it', rtl: false, look, stats: Object.assign({}, STATS, { format: 'png' }) })}); finish({ why: 'interrotto', n: 0, time: '0:00', mb: 0, dir: 'C:\\\\x', el: 1 })`);
    await sleep(450);
    ok($('battuta').textContent === langs.it['fun.none'] && $('b-dir').hidden && $('b-file').hidden, 'fermata prima del primo fotogramma: niente da aprire');

    // ── Destra a sinistra ────────────────────────────────────────────
    const r = rtl[0];
    w.eval(`FIN = null; init(${JSON.stringify({ strings: langs[r], lang: r, rtl: true, look, stats: STATS })})`);
    await sleep(450);
    ok(w.document.documentElement.dir === 'rtl' && w.document.body.classList.contains('rtl'), `${r}: pagina da destra a sinistra`);
    ok(/[0-9]/.test($('stat').textContent) && !/[\u0660-\u0669]/.test($('stat').textContent), `${r}: cifre latine come nel resto dell'estensione`);
    ok($('battuta').querySelectorAll('bdi').length >= 1, `${r}: numeri isolati con <bdi>`);
  } catch(e){
    ok(false, 'eccezione: ' + e.stack);
  }
  w.close();
  console.log(process.exitCode ? '\nCI SONO TEST FALLITI' : '\nTUTTI I TEST PASSATI');
});
