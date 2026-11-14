// Carica videoexport.html (la finestra Esporta video dei percorsi) in jsdom con
// un finto `sketchup`, e verifica: testi in tutte le lingue, numeri del video,
// impostazioni rimandate a Ruby, livelli Base/Avanzate, fotogrammi dal x al y
// (numeri o tempi, controlli e note), video o cartella che hanno già
// fotogrammi (nuovo, in coda, rifai un tratto), Riprendi, bozza, audio,
// cosa fare alla fine, registro, Invio ed Esc, occupato.
//   Prima volta:  cd tests/panel && npm install
//   Esecuzione:   node tests/panel/test_videoexport.js   (oppure tests\run_tests.bat)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const { JSDOM } = require('jsdom');
const html = fs.readFileSync(path.join(ROOT, 'videoexport.html'), 'utf8');
const LANG = path.join(ROOT, 'lang');
// come lib/videoexport.rb: i testi ve. e i nomi delle impostazioni del pannello
const PANEL = /^(ve\.(?!lg\.)|lvl\.[12]$|f\.path_video_(format|size|fps|weather)$|f\.path_speed$|o\.path_video_(format|size)\.)/;
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
    for(const n of ['ready', 'set', 'browse', 'target', 'audio', 'go', 'log', 'cancel']) w.sketchup[n] = a => calls.push([n, a]);
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
  speed: 1, weather: true, target: 'C:\\Video\\Giro.avi', log: 'C:\\Video\\Giro.log', log_exists: false, log_last: null, busy: false,
  quality: 90, sheet: true, awake: true, notify: true, level: 1, modified: false, audio: null,
  draft: { fps: 5, total: 1395, w: 960, h: 540, target: 'C:\\Video\\Giro - bozza.avi' } }, o);

w.addEventListener('load', () => {
  try {
    ok(calls.length === 1 && calls[0][0] === 'ready', 'caricata, chiede i dati a Ruby (ready)');
    ok(w.document.body.classList.contains('attende'), 'finché Ruby non risponde resta nascosta');

    const rotti = [];
    for(const [c, s] of Object.entries(langs)){
      w.init({ strings: s, lang: c, rtl: c === 'ar' || c === 'he', look: {} });
      w.show(stato({ busy: true, avi: { n: 2412, a: 1, b: 2412 }, next: 2413, log_exists: true, log_last: 'x' }));
      $('m-append').click(); scrivi('from', 2000);
      const corpo0 = w.document.body.cloneNode(true);
      corpo0.querySelectorAll('script').forEach(s => s.remove());
      if(/\b(ve|f|o|lvl)\.[a-z0-9]|%\{/.test(corpo0.textContent)) rotti.push(c + ' (in coda)');
      $('m-patch').click(); scrivi('from', 3000);   // rifai fuori dal video: avviso
      w.show(stato({ audio: { file: 'C:\\m\\a.wav', ok: true, s: 100, rate: 44100, ch: 2 }, modified: true, fps: 25 }));
      cambia('after', 'shutdown'); $('draft').checked = true; cambia('draft');
      const corpo = w.document.body.cloneNode(true);
      corpo.querySelectorAll('script').forEach(s => s.remove());
      corpo.querySelectorAll('option').forEach(o => { corpo.appendChild(w.document.createTextNode(' ' + o.textContent)); });
      if(/\b(ve|f|o|lvl)\.[a-z0-9]/.test(corpo.textContent + w.document.title) || /%\{/.test(corpo.textContent)) rotti.push(c);
      w.show(stato({ format: 'png', png: { n: 3, a: 1, b: 3 } }));
      const corpo2 = w.document.body.cloneNode(true);
      corpo2.querySelectorAll('script').forEach(s => s.remove());
      if(/\b(ve|f|o|lvl)\.[a-z0-9]|%\{/.test(corpo2.textContent)) rotti.push(c + ' (png)');
      calls.length = 0;
    }
    ok(rotti.length === 0, `testi completi in tutte le ${Object.keys(langs).length} lingue${rotti.length ? ': ' + rotti.join(', ') : ''}`);

    // L'italiano, da una pagina nuova
    const dom2 = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true, beforeParse(x){
      x.sketchup = {}; for(const n of ['ready', 'set', 'browse', 'target', 'audio', 'go', 'log', 'cancel']) x.sketchup[n] = a => calls.push([n, a]);
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
        ok($('rinfo').textContent.includes('4:38.80') && !$('b-go').disabled && $('modes').hidden && !$('resume').classList.contains('si'),
           'durata del pezzo (4:38.80), Esporta acceso, niente scelte né ripresa con un file nuovo');
        ok($('b-log').disabled && $('logpath').textContent.includes('C:\\Video\\Giro.log'), 'registro: dove starà, Apri spento finché non c\'è');

        // Livelli: Base nasconde le righe avanzate; Avanzate le mostra e lo dice a Ruby
        ok(v.document.body.dataset.lv === '1' && $('lv1').classList.contains('act') && !$('lv2').classList.contains('mod') && $('n-where').textContent === '3',
           'Base: Audio e Registro nascosti, Dove salvare è il 3; nessun pallino con tutto come sempre');
        calls.length = 0;
        $('lv2').click();
        ok(v.document.body.dataset.lv === '2' && $('lv2').classList.contains('act') && $('n-where').textContent === '4' && $('n-after').textContent === '5' &&
           JSON.stringify(JSON.parse(last('set')[1])) === JSON.stringify({ path_video_level: 2 }), 'Avanzate: tutte le sezioni, numerate 1–6, scelta salvata (set)');
        $('lv1').click();
        v.show(stato({ quality: 75 }));
        ok($('lv2').classList.contains('mod'), 'in Base, una scelta avanzata diversa dal solito (qualità 75): pallino su Avanzate');
        v.show(stato());
        ok(!$('lv2').classList.contains('mod'), 'tornata come sempre: niente pallino');

        // Impostazioni → Ruby
        calls.length = 0;
        cambia('fmt', 'png'); cambia('size', 'uhd'); cambia('fps', '25'); cambia('speed', '1.5'); cambia('quality', '80');
        $('weather').checked = false; cambia('weather');
        $('notify').checked = false; cambia('notify');
        $('sheet').checked = false; cambia('sheet');
        $('awake').checked = false; cambia('awake');
        const sets = calls.filter(c => c[0] === 'set').map(c => JSON.parse(c[1]));
        ok(JSON.stringify(sets) === JSON.stringify([{ path_video_format: 'png' }, { path_video_size: 'uhd' }, { path_video_fps: 25 }, { path_speed: 1.5 },
           { path_video_quality: 80 }, { path_video_weather: false }, { path_video_notify: false }, { path_video_sheet: false }, { path_video_awake: false }]),
           'ogni impostazione cambiata va a Ruby (set)');
        cambia('target', 'D:\\altro.avi');
        $('b-browse').click();
        ok(last('target')[1] === 'D:\\altro.avi' && last('browse'), 'percorso scritto a mano (target) e Sfoglia (browse)');
        v.show(stato({ format: 'png', target: 'C:\\Video\\Giro' }));
        ok($('r-quality').style.display === 'none', 'immagini PNG: niente qualità JPEG');
        v.show(stato());

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
        ok(JSON.stringify(JSON.parse(last('go')[1])) === JSON.stringify({ from: 5000, to: 6000, mode: 'new', draft: false, after: 'none' }),
           'Esporta → go {from, to, mode, draft, after}');
        // Come tempi del video: 1:00 è il fotogramma 1801 (a 30 al secondo)
        scrivi('from', '1:00'); scrivi('to', '1:02,5');
        ok($('rinfo').textContent.startsWith('fotogrammi 1801–1876') && !$('b-go').disabled, 'tempi (1:00 → 1:02,5): i fotogrammi 1801–1876');
        calls.length = 0;
        $('b-go').click();
        ok(JSON.parse(last('go')[1]).from === 1801 && JSON.parse(last('go')[1]).to === 1876, 'e a Ruby vanno i numeri');
        scrivi('from', '1:7x');
        ok($('b-go').disabled, 'un tempo scritto male: Esporta spento');
        // Il totale cambia (fps): l'ultimo che era la fine resta la fine, gli altri restano
        $('b-all').click();
        ok($('from').value === '1' && $('to').value === '8365', 'Tutti');
        v.show(stato({ total: 6970, fps: 25 }));
        ok($('to').value === '6970' && $('from').value === '1', 'cambiati gli fps: l\'ultimo segue la fine');
        v.show(stato());

        // Video che ha già fotogrammi: Riprendi, in coda, rifai
        v.show(stato({ avi: { n: 2412, a: 1, b: 2412 }, next: 2413, log_exists: true, log_last: '2026-11-12 15:10:05: interrotto, ultimo fotogramma scritto 2412' }));
        ok($('resume').classList.contains('si') && $('has').textContent.includes('2412') && $('b-resume').textContent === 'Riprendi dal 2413',
           'un video con 2412 fotogrammi: lo dice e propone Riprendi dal 2413');
        ok(!$('modes').hidden && $('m-new').checked && $('tnote').textContent.includes(L['ve.replace']) && $('tnote').className.includes('warn') &&
           $('r-append').style.display === '', 'tutti dal 1: «Nuovo video», con l\'avviso che verrà sostituito; c\'è anche In coda');
        ok(!$('b-log').disabled && $('loglast').textContent.includes('interrotto'), 'registro: Apri acceso e l\'ultima riga');
        $('b-resume').click();
        ok($('from').value === '2413' && $('to').value === '8365' && $('m-append').checked && !$('tnote').textContent.includes(L['ve.replace']),
           'Riprendi: dal 2413 alla fine, in coda, niente più avviso');
        scrivi('from', 3000);
        ok($('warn').textContent.includes('2413') && !$('b-go').disabled, 'in coda ma non dal seguente: avvisa del salto, si può lo stesso');
        scrivi('from', 2413);
        calls.length = 0;
        v.document.getElementById('from').dispatchEvent(new v.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
        ok(JSON.parse(last('go')[1]).mode === 'append' && JSON.parse(last('go')[1]).from === 2413, 'Invio esporta: in coda dal 2413');
        $('b-log').click();
        ok(last('log'), 'Apri il registro (log)');
        // Un tratto dentro il video: «Rifai» scelto da sé
        v.show(stato({ avi: { n: 8365, a: 1, b: 8365 }, target: 'C:\\Video\\Altro.avi' }));
        scrivi('from', 4000); scrivi('to', 4100);
        ok($('m-patch').checked && $('l-patch').textContent === L['ve.mode_patch'] && !$('b-go').disabled, 'dal 4000 al 4100 di un video intero: «Rifai» da sé');
        calls.length = 0;
        $('b-go').click();
        ok(JSON.parse(last('go')[1]).mode === 'patch', 'go con mode patch');
        $('m-new').click();
        ok($('m-new').checked && $('tnote').textContent.includes(L['ve.replace']), 'scelto a mano «Nuovo video»: resta, con l\'avviso');
        scrivi('from', 4001);
        ok($('m-new').checked, 'e resta anche cambiando i fotogrammi');
        v.show(stato({ avi: { n: 2412, a: 1, b: 2412 }, next: 2413, target: 'C:\\Video\\Terzo.avi' }));
        ok($('from').value === '2413' && $('to').value === '8365' && $('m-append').checked,
           'scelto un video lasciato a metà: propone dal 2413 alla fine, in coda');
        $('m-new').click(); scrivi('from', 1);
        $('m-append').click();
        ok($('from').value === '2413' && $('to').value === '8365' && !$('b-go').disabled, 'dal 1 si sceglie «In coda»: si parte dal 2413');
        scrivi('from', 5);
        ok($('b-go').disabled && $('warn').className.includes('bad') && $('warn').textContent.includes('2413'),
           'in coda dal 5 a un video che arriva al 2412: Esporta spento (rifarebbe il film da capo)');
        $('m-patch').click(); scrivi('from', 2000); scrivi('to', 3000);
        ok($('b-go').disabled && $('warn').className.includes('bad') && $('warn').textContent.includes('2412'), 'rifai oltre la fine del video: Esporta spento, avviso');
        v.show(stato({ avi_other: true, exists: true, target: 'C:\\Video\\Strano.avi' }));
        ok($('tnote').textContent === L['ve.avi_other'] && $('modes').hidden, 'un file che non va in coda: lo dice, niente scelte');

        // Bozza
        v.show(stato({ target: 'C:\\Video\\Giro.avi' }));
        $('b-all').click();
        $('draft').checked = true; cambia('draft');
        ok($('h-draft').textContent.includes('960×540') && $('h-draft').textContent.includes('Giro - bozza.avi') && $('target').disabled && $('b-browse').disabled,
           'bozza: misure piccole, file a parte, il percorso del video vero non si tocca');
        calls.length = 0;
        $('b-go').click();
        ok(JSON.parse(last('go')[1]).draft === true && JSON.parse(last('go')[1]).mode === 'new', 'go con draft');
        $('draft').checked = false; cambia('draft');

        // Audio
        calls.length = 0;
        $('b-audio').click();
        ok(last('audio')[1] === 'pick' && $('afile').textContent === L['ve.audio_none'] && $('b-noaudio').disabled, 'Sfoglia l\'audio (audio pick); senza audio, Togli spento');
        v.show(stato({ audio: { file: 'C:\\Musica\\theme.wav', ok: true, s: 281.8, rate: 44100, ch: 2, bits: 16 } }));
        ok($('afile').textContent === 'C:\\Musica\\theme.wav' && $('ainfo').textContent.includes('4:42') && $('ainfo').textContent.includes('44.100') &&
           $('awarn').textContent === '' && !$('b-go').disabled, 'audio di 4:42, più lungo del video: info, nessun avviso');
        $('b-noaudio').click();
        ok(last('audio')[1] === 'clear', 'Togli (audio clear)');
        v.show(stato({ audio: { file: 'C:\\Musica\\corto.wav', ok: true, s: 60, rate: 48000, ch: 1 } }));
        ok($('awarn').textContent.includes('1:00') && $('awarn').textContent.includes('4:39') && !$('b-go').disabled, 'audio più corto: avvisa, si può lo stesso');
        v.show(stato({ audio: { file: 'C:\\Musica\\rotto.wav', ok: false } }));
        ok($('b-go').disabled && $('awarn').className.includes('bad') && $('awarn').textContent.includes('rotto.wav'), 'audio illeggibile: Esporta spento');
        v.show(stato({ format: 'png', target: 'C:\\Video\\Giro', audio: { file: 'C:\\Musica\\theme.wav', ok: true, s: 281.8, rate: 44100, ch: 2 } }));
        ok($('ainfo').textContent.includes(L['ve.audio_png']), 'con le immagini: lo mette crea_video.bat');

        // Alla fine
        v.show(stato({ modified: true }));
        ok($('after').value === 'none' && $('afterh').textContent === '' && $('afterw').textContent === '', 'alla fine: niente, di solito');
        cambia('after', 'shutdown');
        ok($('afterh').textContent === L['ve.after.h'] && $('afterw').textContent === L['ve.after_unsaved'], 'spegni con il modello non salvato: avvisa');
        cambia('after', 'sleep');
        ok($('afterw').textContent === '', 'sospendi: nessun avviso');
        calls.length = 0;
        $('b-go').click();
        ok(JSON.parse(last('go')[1]).after === 'sleep', 'go con after');
        v.init({ strings: L, lang: 'it', rtl: false, look: {} });
        ok($('after').value === 'sleep', 'la scelta resta anche se la lingua cambia');
        cambia('after', 'none');

        // Immagini
        v.show(stato({ format: 'png', target: 'C:\\Video\\Giro', png: { n: 3000, a: 1, b: 3000 }, next: 3001 }));
        $('b-all').click();
        ok($('tnote').textContent.includes('3000') && $('tnote').textContent.includes(L['ve.png_clear']) && $('m-new').checked &&
           $('l-new').textContent === L['ve.mode_png_new'], 'cartella con immagini, tutte: ricomincia da capo, verranno cancellate');
        $('b-resume').click();
        ok($('from').value === '3001' && $('m-patch').checked && $('l-patch').textContent === L['ve.mode_png_keep'] &&
           !$('tnote').textContent.includes(L['ve.png_clear']) && $('r-append').style.display === 'none',
           'Riprendi dal 3001: le altre restano; niente In coda per le immagini');

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
