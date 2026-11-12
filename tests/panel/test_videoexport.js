// Carica videoexport.html (la finestra Esporta video dei percorsi) in jsdom con
// un finto `sketchup`, e verifica: testi in tutte le lingue, numeri del video,
// impostazioni rimandate a Ruby, fotogrammi dal x al y (controlli e note),
// video o cartella che hanno già fotogrammi, Riprendi, In coda, registro,
// Invio ed Esc, occupato.
//   Prima volta:  cd tests/panel && npm install
//   Esecuzione:   node tests/panel/test_videoexport.js   (oppure tests\run_tests.bat)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const { JSDOM } = require('jsdom');
const html = fs.readFileSync(path.join(ROOT, 'videoexport.html'), 'utf8');
const LANG = path.join(ROOT, 'lang');
// come lib/videoexport.rb: i testi ve. e i nomi delle impostazioni del pannello
const PANEL = /^(ve\.|f\.path_video_(format|size|fps|weather)$|f\.path_speed$|o\.path_video_(format|size)\.)/;
const langs = {};
for(const f of fs.readdirSync(LANG).sort()){   // in ordine: la cartella non lo garantisce (su FAT/exFAT è quello di creazione)
  if(!f.endsWith('.json') || f === 'index.json') continue;
  const d = JSON.parse(fs.readFileSync(path.join(LANG, f), 'utf8'));
  langs[f.slice(0, -5)] = Object.fromEntries(Object.entries(d).filter(([k]) => PANEL.test(k)));
}
const calls = [];
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  beforeParse(w){
    w.sketchup = {};
    for(const n of ['ready', 'set', 'browse', 'target', 'go', 'log', 'cancel']) w.sketchup[n] = a => calls.push([n, a]);
    w.matchMedia = () => ({ matches: false });
  }
});
const w = dom.window;
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if(!c) process.exitCode = 1; };
const $ = id => w.document.getElementById(id);
const last = n => calls.filter(c => c[0] === n).pop();
const scrivi = (id, v) => { $(id).value = v; $(id).dispatchEvent(new w.Event('input', { bubbles: true })); };
const cambia = (id, v) => { if(v !== undefined) $(id).value = v; $(id).dispatchEvent(new w.Event('change', { bubbles: true })); };
const tasto = (k, el) => (el || w.document.body).dispatchEvent(new w.KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));

const stato = (o = {}) => Object.assign({ name: 'Giro <del> faro', dur: 278.8, total: 8365, fps: 30, w: 1920, h: 1080, format: 'avi', size: 'fhd',
  speed: 1, weather: true, target: 'C:\\Video\\Giro.avi', log: 'C:\\Video\\Giro.log', log_exists: false, log_last: null, busy: false }, o);

w.addEventListener('load', () => {
  try {
    ok(calls.length === 1 && calls[0][0] === 'ready', 'caricata, chiede i dati a Ruby (ready)');
    ok(w.document.body.classList.contains('attende'), 'finché Ruby non risponde resta nascosta');

    const rotti = [];
    for(const [c, s] of Object.entries(langs)){
      w.init({ strings: s, lang: c, rtl: c === 'ar' || c === 'he', look: {} });
      w.show(stato({ busy: true, avi: { n: 2412, a: 1, b: 2412 }, next: 2413, log_exists: true, log_last: 'x' }));
      $('append').checked = true; scrivi('from', 2000);
      const corpo = w.document.body.cloneNode(true);
      corpo.querySelectorAll('script').forEach(s => s.remove());
      corpo.querySelectorAll('option').forEach(o => { corpo.appendChild(w.document.createTextNode(' ' + o.textContent)); });
      if(/\b(ve|f|o)\.[a-z]/.test(corpo.textContent + w.document.title) || /%\{/.test(corpo.textContent)) rotti.push(c);
      w.show(stato({ format: 'png', png: { n: 3, a: 1, b: 3 } }));
      const corpo2 = w.document.body.cloneNode(true);
      corpo2.querySelectorAll('script').forEach(s => s.remove());
      if(/\b(ve|f|o)\.[a-z]|%\{/.test(corpo2.textContent)) rotti.push(c + ' (png)');
      calls.length = 0;
    }
    ok(rotti.length === 0, `testi completi in tutte le ${Object.keys(langs).length} lingue${rotti.length ? ': ' + rotti.join(', ') : ''}`);

    // L'italiano, da una pagina nuova
    const dom2 = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true, beforeParse(x){
      x.sketchup = {}; for(const n of ['ready', 'set', 'browse', 'target', 'go', 'log', 'cancel']) x.sketchup[n] = a => calls.push([n, a]);
      x.matchMedia = () => ({ matches: false }); } });
    const v = dom2.window;
    v.addEventListener('load', () => {
      try {
        const $ = id => v.document.getElementById(id);
        const scrivi = (id, val) => { $(id).value = val; $(id).dispatchEvent(new v.Event('input', { bubbles: true })); };
        const cambia = (id, val) => { if(val !== undefined) $(id).value = val; $(id).dispatchEvent(new v.Event('change', { bubbles: true })); };
        const L = langs.it;
        calls.length = 0;
        v.init({ strings: L, lang: 'it', rtl: false, look: { theme: 'dark' } });
        v.show(stato());
        ok(!v.document.body.classList.contains('attende'), 'arrivati i dati, si vede');
        ok($('sub').textContent.includes('«Giro <del> faro»') && $('sub').textContent.includes('4:39') && $('sub').textContent.includes('8365'.slice(0, 1)),
           'sotto il titolo: nome (come testo), durata, fotogrammi');
        ok($('fmt').value === 'avi' && $('size').value === 'fhd' && $('fps').value === '30' && $('weather').checked && $('target').value === 'C:\\Video\\Giro.avi',
           'impostazioni e file come li manda Ruby');
        ok($('from').value === '1' && $('to').value === '8365' && $('of').textContent === 'di 8365'.replace('8365', Number(8365).toLocaleString('it')),
           'fotogrammi: tutti, dal 1 all\'ultimo');
        ok($('rinfo').textContent.includes('4:38.80') && !$('b-go').disabled && $('r-append').style.display === 'none' && !$('resume').classList.contains('si'),
           'durata del pezzo (4:38.80), Esporta acceso, niente coda né ripresa con un file nuovo');
        ok($('b-log').disabled && $('logpath').textContent.includes('C:\\Video\\Giro.log'), 'registro: dove starà, Apri spento finché non c\'è');

        // Impostazioni → Ruby
        calls.length = 0;
        cambia('fmt', 'png'); cambia('size', 'uhd'); cambia('fps', '25'); cambia('speed', '1.5');
        $('weather').checked = false; cambia('weather');
        const sets = calls.filter(c => c[0] === 'set').map(c => JSON.parse(c[1]));
        ok(JSON.stringify(sets) === JSON.stringify([{ path_video_format: 'png' }, { path_video_size: 'uhd' }, { path_video_fps: 25 }, { path_speed: 1.5 }, { path_video_weather: false }]),
           'ogni impostazione cambiata va a Ruby (set)');
        cambia('target', 'D:\\altro.avi');
        $('b-browse').click();
        ok(last('target')[1] === 'D:\\altro.avi' && last('browse'), 'percorso scritto a mano (target) e Sfoglia (browse)');

        // Fotogrammi
        scrivi('from', 5000); scrivi('to', 4000);
        ok($('b-go').disabled && $('warn').className.includes('bad'), 'il primo dopo l\'ultimo: Esporta spento, avviso');
        scrivi('to', 9000);
        ok($('b-go').disabled, 'oltre la fine: Esporta spento');
        scrivi('to', 6000);
        ok(!$('b-go').disabled && $('rinfo').textContent.includes('1001') && $('rinfo').textContent.includes('2:46.63'),
           'dal 5000 al 6000: 1001 fotogrammi, dall\'istante 2:46.63');
        calls.length = 0;
        $('b-go').click();
        ok(JSON.stringify(JSON.parse(last('go')[1])) === JSON.stringify({ from: 5000, to: 6000, append: false }), 'Esporta → go {from, to, append}');
        // Il totale cambia (fps): l'ultimo che era la fine resta la fine, gli altri restano
        $('b-all').click();
        ok($('from').value === '1' && $('to').value === '8365', 'Tutti');
        v.show(stato({ total: 6970, fps: 25 }));
        ok($('to').value === '6970' && $('from').value === '1', 'cambiati gli fps: l\'ultimo segue la fine');

        // Video che ha già fotogrammi: Riprendi, In coda
        v.show(stato({ avi: { n: 2412, a: 1, b: 2412 }, next: 2413, log_exists: true, log_last: '2026-11-12 15:10:05  Interrotto: ultimo fotogramma scritto 2412' }));
        ok($('resume').classList.contains('si') && $('has').textContent.includes('2412') && $('b-resume').textContent === 'Riprendi dal 2413',
           'un video con 2412 fotogrammi: lo dice e propone Riprendi dal 2413');
        ok($('tnote').textContent.includes(L['ve.replace']) && $('tnote').className.includes('warn') && $('r-append').style.display === '',
           'senza «in coda» avvisa che verrà sostituito; la casella In coda c\'è');
        ok(!$('b-log').disabled && $('loglast').textContent.includes('Interrotto'), 'registro: Apri acceso e l\'ultima riga');
        $('b-resume').click();
        ok($('from').value === '2413' && $('to').value === '8365' && $('append').checked && !$('tnote').textContent.includes(L['ve.replace']),
           'Riprendi: dal 2413 alla fine, in coda, niente più avviso');
        scrivi('from', 3000);
        ok($('warn').textContent.includes('2413') && !$('b-go').disabled, 'in coda ma non dal seguente: avvisa del salto, si può lo stesso');
        scrivi('from', 2413);
        calls.length = 0;
        v.document.getElementById('from').dispatchEvent(new v.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
        ok(JSON.stringify(JSON.parse(last('go')[1])) === JSON.stringify({ from: 2413, to: 8365, append: true }), 'Invio esporta: in coda dal 2413');
        $('b-log').click();
        ok(last('log'), 'Apri il registro (log)');
        v.show(stato({ avi_other: true, exists: true }));
        ok($('tnote').textContent === L['ve.avi_other'] && $('r-append').style.display === 'none' && !$('append').checked,
           'un file che non va in coda: lo dice, niente casella In coda');

        // Immagini
        v.show(stato({ format: 'png', target: 'C:\\Video\\Giro', png: { n: 3000, a: 1, b: 3000 }, next: 3001 }));
        $('b-all').click();
        ok($('tnote').textContent.includes('3000') && $('tnote').textContent.includes(L['ve.png_clear']), 'cartella con immagini, dal 1: verranno cancellate');
        $('b-resume').click();
        ok($('from').value === '3001' && $('tnote').textContent.includes(L['ve.png_keep']) && $('r-append').style.display === 'none',
           'Riprendi dal 3001: restano; niente In coda per le immagini');

        // Esc, occupato, percorso sparito
        calls.length = 0;
        v.document.body.dispatchEvent(new v.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        ok(last('cancel'), 'Esc chiude');
        v.show(stato({ busy: true }));
        ok($('b-go').disabled && $('occ').classList.contains('si'), 'occupato: Esporta spento, nota');
        v.show({ name: 'Sparito', missing: true, busy: false });
        ok($('b-go').disabled && $('sub').textContent.includes('Sparito'), 'percorso che non c\'è più: Esporta spento');

        v.init({ strings: langs.he, lang: 'he', rtl: true, look: {} });
        ok(v.document.documentElement.dir === 'rtl', 'ebraico: da destra a sinistra');
      } catch(e){
        ok(false, 'eccezione: ' + e.stack);
      }
      console.log(process.exitCode ? '\nCI SONO TEST FALLITI' : '\nTUTTI I TEST PASSATI');
      v.close();
    });
  } catch(e){
    ok(false, 'eccezione: ' + e.stack);
    console.log('\nCI SONO TEST FALLITI');
  }
  w.close();
});
