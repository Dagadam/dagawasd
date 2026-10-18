// Carica panel.html in jsdom con un finto oggetto `sketchup`, applica i testi
// italiani e verifica la ricerca e la tabella materiali.
//   Prima volta:  cd tests/panel && npm install
//   Esecuzione:   node tests/panel/test_panel.js   (oppure tests\run_tests.bat)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const { JSDOM } = require('jsdom');
const html = fs.readFileSync(path.join(ROOT, 'panel.html'), 'utf8');
const it = JSON.parse(fs.readFileSync(path.join(ROOT, 'lang', 'it.json'), 'utf8'));
const en = JSON.parse(fs.readFileSync(path.join(ROOT, 'lang', 'en.json'), 'utf8'));
const saved = [];
const logCalls = [];
const presetCalls = [];
const pathCalls = [];
const pasteCalls = [];
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  beforeParse(w){
    w.sketchup = {
      request_settings(){}, save_settings(j){ saved.push(JSON.parse(j)); },
      toggle(){}, set_language(){}, reset_materials(){ saved.push('RESET'); },
      read_log(){ logCalls.push('read'); }, clear_log(){ logCalls.push('clear'); },
      weather_preset(id){ presetCalls.push(id); },
      path_cmd(j){ pathCalls.push(JSON.parse(j)); },
      panel_paste(){ pasteCalls.push(1); }
    };
    w.HTMLElement.prototype.scrollIntoView = function(){};
  }
});
const w = dom.window;
const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if(!c) process.exitCode = 1; };
// DEFAULT e DEFAULT_KEYS letti da lib/config.rb: come fa Ruby con setDefaults, e
// così il test verifica anche che i default esistano in un posto solo.
const rb = fs.readFileSync(path.join(ROOT, 'lib', 'config.rb'), 'utf8');
const VK = {};
for(const m of rb.matchAll(/^\s*(VK_\w+)\s*=\s*(0x[0-9A-F]+)/gm)) VK[m[1]] = parseInt(m[2], 16);
const block = (name) => rb.slice(rb.indexOf(name + ' = {'), rb.indexOf('}.freeze', rb.indexOf(name + ' = {')));
const RB_DEF = {};
for(const m of block('DEFAULT').matchAll(/'(\w+)'\s*=>\s*(true|false|-?\d+(?:\.\d+)?)/g))
  RB_DEF[m[1]] = m[2] === 'true' ? true : m[2] === 'false' ? false : parseFloat(m[2]);
for(const m of block('DEFAULT').matchAll(/'(\w+)'\s*=>\s*'([^']*)'/g)) RB_DEF[m[1]] = m[2];   // colori e scelte
RB_DEF.keys = {};
for(const m of block('DEFAULT_KEYS').matchAll(/'(\w+)'\s*=>\s*(VK_\w+)/g)) RB_DEF.keys[m[1]] = VK[m[2]];
RB_DEF.key_labels = {};

w.addEventListener('load', () => {
  // prima che Ruby mandi le impostazioni nessun salvataggio: il modulo è vuoto
  w.eval('setLevel(2, true); saveNow()');
  ok(saved.length === 0, 'nessun salvataggio prima di loadSettings (interruttori non ancora caricati)');
  w.eval(`applyLang(${JSON.stringify({ strings: Object.assign({}, en, it), languages: [], current: 'it', resolved: 'it' })})`);
  ok(!/const DEF = \{\s*move_speed/.test(html), 'panel.html non contiene più una copia dei default');
  w.eval(`setDefaults(${JSON.stringify(RB_DEF)})`);
  w.eval(`loadSettings(${JSON.stringify(RB_DEF)})`);
  ok(Object.keys(RB_DEF.keys).length === 12 && RB_DEF.move_speed > 0, 'default letti da lib/config.rb (12 tasti)');
  const mats = [
    { id:'legno', name:'', density:600, restitution:0.3, friction:0.5, keywords:'legno, wood', icon:'wood' },
    { id:'c1', name:'Sughero', density:240, restitution:0.5, friction:0.6, keywords:'sughero, cork', icon:'cork' }
  ];
  w.eval(`loadSettings(${JSON.stringify({ move_speed: 3.2, materials: mats, panel_level: 3 })})`);
  const d = w.document, q = d.getElementById('q');
  ok(w.eval('LEVEL') === 3 && d.querySelector('#lvsw button[data-lvl="3"]').classList.contains('act'),
     'panel_level dalle impostazioni seleziona "Molto avanzate"');
  ok(!!q, 'casella di ricerca presente nella barra dei tab');
  ok(d.querySelectorAll('#matbody tr').length === 2, 'tabella materiali: 2 righe');

  const type = (s) => { q.value = s; w.eval('runSearch(true)'); };
  // 1. impostazione in un altro tab: deve saltarci e evidenziarla
  type('rotella');
  const row = d.querySelector('.row[data-k="wheel_zoom"]');
  ok(row && row.classList.contains('hit'), '"rotella" evidenzia Zoom con la rotella');
  ok(row.querySelector('mark') && row.querySelector('mark').textContent.toLowerCase() === 'rotella', 'testo evidenziato con <mark>');
  ok(d.querySelector('#tabs1 button[data-t="camera"]').classList.contains('hit'), 'tab Camera evidenziato');
  ok(w.eval('curTab') === 'camera', 'salta al tab con risultati');
  ok(d.querySelector('#tabs2 button.act').classList.contains('hit'), 'sotto-tab attivo evidenziato');
  // 2. senza accenti / maiuscole
  type('DENSITA');
  ok(d.querySelector('.row[data-k="obj_density"]').classList.contains('hit'), '"DENSITA" trova "Densità" (accenti e maiuscole ignorati)');
  // 3. tabella materiali (valore di un input)
  type('cork');
  ok([...d.querySelectorAll('#matbody tr')][1].classList.contains('hit'), '"cork" trova la riga Sughero dalle parole chiave');
  ok(d.querySelector('#tabs2 button[data-s="mattab"]').dataset.n === '1', 'contatore sul sotto-tab materiali');
  // 4. legenda tasti
  type('shift');
  ok(d.querySelectorAll('table.keys tr.hit').length >= 2, '"shift" trova le righe della legenda');
  // 5. nessun risultato
  type('zzzzqqq');
  ok(q.classList.contains('none') && d.getElementById('qcnt').textContent === it['ui.search_none'], 'nessun risultato: bordo rosso e "nessuno"');
  // 6. svuotare
  q.value = 'zoom'; w.eval('runSearch(false)');
  q.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
  ok(d.querySelectorAll('.hit').length === 0 && !d.querySelector('mark'), 'Esc svuota ed elimina le evidenziazioni');
  // 7. Invio passa al riquadro successivo
  type('forza');
  const first = w.eval('curTab + "/" + curSub[curTab]');
  q.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Enter' }));
  const second = w.eval('curTab + "/" + curSub[curTab]');
  ok(first !== second, `Invio passa al riquadro successivo (${first} → ${second})`);
  // 8. la ricerca sopravvive al cambio lingua
  w.eval(`applyLang(${JSON.stringify({ strings: en, languages: [], current: 'en', resolved: 'en' })})`);
  ok(d.getElementById('q').value === 'forza', 'il testo cercato resta dopo il cambio lingua');
  const n1 = saved.length;
  w.eval('saveNow()');
  ok(saved.length === n1, 'dopo il cambio lingua nessun salvataggio finché Ruby non rimanda i valori');
  w.eval(`loadSettings(${JSON.stringify(RB_DEF)})`);   // come fa Ruby dopo applyLang
  // 9. salvataggio della tabella materiali
  w.eval('madd()');
  const last = saved.filter(x => x !== 'RESET').pop();
  ok(last.materials && last.materials.length === 3, 'Aggiungi materiale salva 3 righe');
  w.eval('micon(0)');
  ok(saved.filter(x => x !== 'RESET').pop().materials[0].icon === 'stone', 'clic sull\'icona: wood → stone');

  // 10. livelli di dettaglio: la ricerca vede solo ciò che il livello mostra
  const qq = d.getElementById('q');
  const find = (s) => { qq.value = s; w.eval('runSearch(true)'); };
  const css = (el) => w.getComputedStyle(el).display;
  w.eval('selTab("objects"); selSub("rb")');
  w.eval('setLevel(1, true)');
  ok(saved.filter(x => x !== 'RESET').pop().panel_level === 1, 'cambiare livello lo salva nelle impostazioni');
  ok(css(d.querySelector('.row[data-k="coyote_time"]')) === 'none', 'base: coyote time nascosto');
  ok(css(d.querySelector('.row[data-k="move_speed"]')) !== 'none', 'base: velocità base visibile');
  ok(w.eval('curTab + "/" + curSub[curTab]') !== 'objects/rb', 'base: il riquadro Corpo rigido (vuoto) viene abbandonato');
  ok(css(d.querySelector('#tabs1 button[data-t="objects"]')) !== 'none', 'base: tab Oggetti resta (ha impostazioni base)');
  find('coyote');
  ok(d.querySelectorAll('.hit').length === 0 && qq.classList.contains('none'), 'base: "coyote" non trova impostazioni molto avanzate');
  find('cork');
  ok(d.querySelectorAll('#matbody tr.hit').length === 0, 'base: la tabella materiali (avanzata) è esclusa dalla ricerca');
  w.eval('setLevel(2, true)');
  find('cork');
  ok(d.querySelectorAll('#matbody tr.hit').length === 1, 'avanzate: la tabella materiali torna cercabile');
  find('coyote');
  ok(d.querySelectorAll('.hit').length === 0, 'avanzate: "coyote" ancora escluso');
  w.eval('setLevel(3, true)');
  find('coyote');
  ok(d.querySelector('.row[data-k="coyote_time"]').classList.contains('hit') && w.eval('curTab') === 'player',
     'molto avanzate: "coyote" trovato e aperto');
  // 11. guida "?": modal nella lingua attiva, tasti come <kbd>, Esc/clic fuori chiudono
  w.eval(`applyLang(${JSON.stringify({ strings: Object.assign({}, en, it), languages: [], current: 'it', resolved: 'it' })})`);
  const modal = d.getElementById('help');
  ok(!modal.classList.contains('open'), 'guida chiusa all\'avvio');
  d.getElementById('btnHelp').click();
  ok(modal.classList.contains('open'), 'clic su "?" apre la guida');
  ok(d.getElementById('helpTitle').textContent === it['help.title'], 'titolo della guida in italiano');
  ok(modal.querySelectorAll('li').length === 7 && modal.querySelectorAll('kbd').length >= 10, 'guida: 7 punti con i tasti in <kbd>');
  ok(!modal.textContent.includes('help.'), 'guida: nessuna chiave di traduzione mancante');
  qq.value = 'zoom';
  d.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
  ok(!modal.classList.contains('open'), 'Esc chiude la guida');
  d.getElementById('btnHelp').click();
  modal.dispatchEvent(new w.MouseEvent('click', { bubbles: true }));
  ok(!modal.classList.contains('open'), 'clic fuori dal riquadro chiude la guida');
  w.eval(`applyLang(${JSON.stringify({ strings: en, languages: [], current: 'en', resolved: 'en' })})`);
  ok(d.getElementById('helpTitle').textContent === en['help.title'], 'la guida segue il cambio lingua');

  // di nuovo in italiano, con i valori come li rimanda Ruby dopo applyLang
  w.eval(`applyLang(${JSON.stringify({ strings: Object.assign({}, en, it), languages: [], current: 'it', resolved: 'it' })})`);
  w.eval(`setDefaults(${JSON.stringify(RB_DEF)}); loadSettings(${JSON.stringify(RB_DEF)})`);

  // 12. valori modificati: pallino/↺ sulla riga, ripristino singolo
  w.eval('setLevel(3, false)');
  const rowMs = d.querySelector('.row[data-k="move_speed"]');
  ok(!rowMs.classList.contains('mod'), 'valore predefinito: nessun segno di modifica');
  const nb = d.getElementById('move_speed_v');
  nb.value = '5,5'; w.eval(`sb(document.getElementById('move_speed_v'), 'move_speed'); fix('move_speed')`);
  ok(rowMs.classList.contains('mod'), 'valore cambiato: riga segnata come modificata');
  const n0 = saved.length;
  rowMs.querySelector('.rst').click();
  ok(!rowMs.classList.contains('mod') && nb.value === '3.2', '↺ riporta al predefinito (3.2)');
  ok(saved.length > n0 && saved[saved.length - 1].move_speed === 3.2, '↺ salva subito');
  // modifica nascosta dal livello: pallino sul pulsante del livello
  d.getElementById('coyote_time_v').value = '0.3'; w.eval(`fix('coyote_time')`);
  w.eval('setLevel(1, false)');
  ok(d.querySelector('#lvsw button[data-lvl="3"]').classList.contains('mod') &&
     !d.querySelector('#lvsw button[data-lvl="2"]').classList.contains('mod'),
     'base: pallino su "Molto avanzate" per il coyote time modificato e nascosto');
  w.eval(`resetOne('coyote_time')`);
  ok(!d.querySelector('#lvsw button.mod'), 'ripristinato: nessun pallino sui livelli');
  // Ripristina default non tocca lingua, livello, tasti
  w.eval('KEYS.jump = 70; KEYS.cursor = 32; renderKeys()');
  w.eval('resetAll()');
  ok(w.eval('LEVEL') === 1 && w.eval('KEYS.jump') === 70, 'Ripristina default lascia livello e tasti');
  w.eval('resetKeys()');

  // 13. tasti personalizzabili
  w.eval('selTab("system"); selSub("keys")');
  const kbJump = () => d.querySelector('.kb[data-act="jump"]');
  ok(kbJump() && kbJump().textContent === 'Space', 'legenda: il salto mostra Space');
  const press = (keyCode, key) => d.dispatchEvent(new w.KeyboardEvent('keydown', { keyCode, key, bubbles: true }));
  kbJump().click();
  ok(kbJump().classList.contains('wait'), 'clic: il tasto attende la nuova pressione');
  press(9, 'Tab');
  ok(kbJump().classList.contains('wait') && d.getElementById('status').textContent === it['keys.reserved'],
     'Tab è riservato: resta in attesa e lo segnala nella barra in basso');
  press(74, 'j');
  ok(kbJump().textContent === 'J' && kbJump().classList.contains('mod'), 'Salto → J, segnato come modificato');
  let last2 = saved[saved.length - 1];
  ok(last2.keys.jump === 74, 'il nuovo tasto viene salvato (keys.jump = 74)');
  // scambio: C (accovacciati) sul salto → il salto prende J? no: jump=J, ora assegno C al salto
  kbJump().click(); press(67, 'c');
  ok(w.eval('KEYS.jump') === 67 && w.eval('KEYS.crouch') === 74, 'tasto già usato: i due comandi si scambiano');
  kbJump().click(); press(192, 'ò');
  ok(kbJump().textContent === 'Ò' && saved[saved.length - 1].key_labels.jump === 'Ò', 'tasto di punteggiatura: etichetta dal layout (Ò)');
  kbJump().click(); press(27, 'Escape');
  ok(!kbJump().classList.contains('wait') && w.eval('KEYS.jump') === 192, 'Esc annulla senza cambiare');
  d.getElementById('btnHelp').click();
  ok(d.getElementById('helpBody').textContent.includes('Ò'), 'la guida mostra il tasto scelto al posto di Space');
  d.getElementById('helpX').click();
  w.eval('resetKeys()');
  ok(kbJump().textContent === 'Space' && !d.querySelector('.kb.mod'), 'Ripristina tasti torna ai predefiniti');

  // 14. barra in basso: spiegazione dell'impostazione sotto il mouse
  w.eval('setLevel(3, false); selTab("player"); selSub("jump")');
  const st = d.getElementById('status');
  w.eval('FLASH = null');   // il messaggio lampo del test 13 durerebbe ancora 1,8 s
  d.querySelector('.row[data-k="coyote_time"] .lbl').dispatchEvent(new w.MouseEvent('mouseover', { bubbles: true }));
  ok(st.classList.contains('info') && st.textContent.includes(it['d.coyote_time']), 'hover: spiegazione lunga nella barra in basso');
  ok(st.textContent.includes(it['ui.range']) && st.textContent.includes('0.12'), 'hover: intervallo e valore predefinito');
  d.getElementById('content').dispatchEvent(new w.MouseEvent('mouseleave'));
  ok(!st.classList.contains('info') && !st.textContent.includes(it['d.coyote_time']), 'uscendo torna il messaggio normale');

  // 15. backup
  w.eval('selTab("system"); selSub("backup")');
  ok(!!d.querySelector('#pane_system_backup button'), 'sotto-tab Backup con i pulsanti esporta/importa');

  // 16. registro errori: ⚠ solo con voci, finestra con il testo da Ruby
  const btnLog = d.getElementById('btnLog');
  w.eval('setLogCount(0)');
  ok(btnLog.hidden, 'registro vuoto: nessun ⚠ nella barra in alto');
  w.eval('setLogCount(2)');
  ok(!btnLog.hidden && btnLog.textContent === '⚠ 2', 'registro con 2 voci: ⚠ 2');
  w.eval('selTab("system"); selSub("log")');
  d.querySelector('#pane_system_log button').click();
  const logm = d.getElementById('logm');
  ok(logm.classList.contains('open') && logCalls[logCalls.length - 1] === 'read', 'il pulsante apre la finestra e chiede il registro a Ruby');
  const sample = '2026-09-27 10:00:01 [tick] NoMethodError: x <b>\n    main.rb:10\n'
               + '2026-09-27 10:00:02 [draw] TypeError: y\n    main.rb:20\n';
  w.eval(`showLog(${JSON.stringify({ path: 'C:/x/dagawasd.log', text: sample })})`);
  const pre = d.getElementById('logPre');
  ok(pre.textContent.includes('[tick] NoMethodError: x <b>') && !pre.querySelector('b'), 'testo mostrato così com\'è (niente HTML interpretato)');
  ok(pre.querySelectorAll('.ts').length === 2 && btnLog.textContent === '⚠ 2', 'date evidenziate e contatore allineato');
  ok(d.getElementById('logPath').textContent === 'C:/x/dagawasd.log', 'percorso del file mostrato');
  d.getElementById('logClear').click();
  ok(logCalls[logCalls.length - 1] === 'clear', 'Svuota chiede a Ruby di svuotare il registro');
  w.eval(`showLog({ path: 'C:/x/dagawasd.log', text: '' })`);
  ok(pre.textContent === it['log.empty'] && btnLog.hidden, 'registro svuotato: messaggio "nessun errore" e ⚠ nascosto');
  d.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
  ok(!logm.classList.contains('open'), 'Esc chiude la finestra del registro');
  btnLog.hidden = false; btnLog.click();
  ok(logm.classList.contains('open'), 'anche il ⚠ in alto apre il registro');
  w.eval('closeLog()');

  // 17. Ctrl+Home: riga nella legenda, Home riservato
  w.eval('setLevel(3, false); selTab("system"); selSub("keys")');
  ok([...d.querySelectorAll('table.keys tr')].some(r => r.textContent.includes('Home') && r.textContent.includes(it['keys.panel'])),
     'legenda: Ctrl+Home apre il pannello');
  d.querySelector('.kb[data-act="jump"]').click(); press(36, 'Home');
  ok(d.querySelector('.kb[data-act="jump"]').classList.contains('wait') && w.eval('KEYS.jump') === 32, 'Home è riservato');
  press(27, 'Escape');

  // 18. Aspetto
  const cssv = (n) => d.documentElement.style.getPropertyValue('--' + n).trim();
  w.eval(`loadSettings(${JSON.stringify(RB_DEF)})`);
  w.eval('selTab("system"); selSub("look")');
  ok(!!d.getElementById('pane_system_look') && d.querySelector('#tabs2 button[data-s="look"]'), 'sotto-tab Aspetto in Sistema');
  ok(cssv('acc') === RB_DEF.ui_accent && cssv('bg') === '#151515', `tema scuro predefinito applicato (--acc ${cssv('acc')}, --bg ${cssv('bg')})`);
  const rb2 = fs.readFileSync(path.join(ROOT, 'lib', 'config.rb'), 'utf8');
  const choices = {};
  for(const m of rb2.slice(rb2.indexOf('LOOK_CHOICES = {')).matchAll(/'(\w+)'\s*=>\s*%w\[([^\]]*)\]/g)) choices[m[1]] = m[2].trim().split(/\s+/);
  const nChoice = w.eval(`Object.values(FIELDS).filter(f => f.type === 'choice').length`);
  const same = Object.keys(choices).length === nChoice && Object.keys(choices).every(k =>
    JSON.stringify(w.eval(`choiceVals(FIELDS['${k}'])`).slice().sort()) === JSON.stringify(choices[k].slice().sort()));
  ok(same, 'le scelte del pannello coincidono con LOOK_CHOICES di lib/config.rb');
  // tema chiaro: sfondo chiaro, salvato
  const theme = d.getElementById('ui_theme');
  theme.value = 'light'; theme.dispatchEvent(new w.Event('change'));
  ok(cssv('bg') === '#f5f6f8' && saved[saved.length - 1].ui_theme === 'light', 'tema Chiaro: sfondo chiaro e salvato');
  ok(d.querySelector('.row[data-k="ui_theme"]').classList.contains('mod'), 'tema cambiato: riga segnata come modificata');
  // colore: casella esadecimale (anche abbreviata), valore non valido rifiutato
  const hx = d.getElementById('ui_accent_v');
  hx.value = 'f0a'; hx.dispatchEvent(new w.Event('input'));
  ok(cssv('acc') === '#ff00aa' && d.getElementById('ui_accent').value === '#ff00aa', '"f0a" → #ff00aa, selettore allineato');
  hx.value = 'zzz'; hx.dispatchEvent(new w.Event('input'));
  ok(hx.classList.contains('bad') && cssv('acc') === '#ff00aa', 'colore non valido: bordo rosso, resta l\'ultimo buono');
  hx.dispatchEvent(new w.Event('blur'));
  ok(hx.value === '#ff00aa' && !hx.classList.contains('bad') && saved[saved.length - 1].ui_accent === '#ff00aa',
     'uscendo dalla casella torna il colore valido e viene salvato');
  // carattere, dimensione, icone dei tab, logo
  const font = d.getElementById('ui_font');
  font.value = 'georgia'; font.dispatchEvent(new w.Event('change'));
  ok(cssv('font').startsWith('Georgia'), 'carattere Georgia applicato');
  d.getElementById('ui_font_size_v').value = '18'; w.eval(`fix('ui_font_size')`);
  ok(cssv('fs') === '18px', 'dimensione del testo 18 px');
  const ti = d.getElementById('ui_tab_icons');
  ti.value = 'icons'; ti.dispatchEvent(new w.Event('change'));
  ok(d.body.classList.contains('ti-icons') && d.querySelector('#tabs1 button[data-t="system"] svg') &&
     d.querySelector('#tabs1 button[data-t="system"]').title === it['tab.system'], 'solo icone: icona SVG e nome nel suggerimento');
  const logo = d.getElementById('ui_logo');
  logo.value = 'none'; logo.dispatchEvent(new w.Event('change'));
  ok(d.getElementById('logo').textContent === '', 'icona del titolo: nessuna');
  // sfondo personalizzato: righe spente finché l'interruttore è spento
  ok(d.querySelector('.row[data-k="ui_bg"]').classList.contains('off'), 'sfondo proprio disattivato: riga attenuata');
  d.getElementById('ui_custom_colors').click();
  d.getElementById('ui_bg_v').value = '#203040'; w.eval(`fixHex('ui_bg')`);
  ok(cssv('bg') === '#203040' && !d.querySelector('.row[data-k="ui_bg"]').classList.contains('off'), 'sfondo proprio applicato');
  // dipendenze fuori dall'aspetto: il dolly segue la costruzione dal vivo,
  // la sua velocità segue il dolly (e a catena la costruzione dal vivo)
  const off = k => d.querySelector(`.row[data-k="${k}"]`).classList.contains('off');
  w.eval(`loadSettings({bridge_live:false, bridge_orbit:true})`);
  ok(off('bridge_orbit') && off('bridge_orbit_speed'), 'costruzione dal vivo spenta: dolly e velocità attenuati');
  d.getElementById('bridge_live').click();
  ok(!off('bridge_orbit') && !off('bridge_orbit_speed'), 'costruzione dal vivo accesa: dolly e velocità normali');
  d.getElementById('bridge_orbit').click();
  ok(!off('bridge_orbit') && off('bridge_orbit_speed'), 'dolly spento: solo la velocità attenuata');
  // Finestre e tasti (tools/finestre.ps1): spento di default, il mouse e la sua durata lo seguono
  w.eval(`loadSettings({bridge_windows:false, bridge_windows_mouse:true})`);
  ok(RB_DEF.bridge_windows === false && off('bridge_windows_mouse') && off('bridge_mouse_time'),
     'finestre e tasti spenti (default): «Mostra il mouse» e durata attenuati');
  d.getElementById('bridge_windows').click();
  ok(!off('bridge_windows_mouse') && !off('bridge_mouse_time'), 'accesi: mouse e durata normali');
  d.getElementById('bridge_windows_mouse').click();
  ok(off('bridge_mouse_time'), 'mouse nascosto: solo la durata attenuata');
  // Camera › Visuale: sguardo col tastierino, velocità attenuate se spento
  const padRows = [...d.querySelectorAll('#pane_camera_view .row')].map(r => r.dataset.k).filter(k => k.startsWith('pad_look'));
  ok(padRows.join() === 'pad_look,pad_look_speed,pad_look_speed_v,pad_look_accel', `Camera › Visuale: gruppo Tastierino con 4 righe (${padRows.join()})`);
  w.eval(`loadSettings({pad_look:false})`);
  ok(off('pad_look_speed') && off('pad_look_accel') && !off('pad_look'), 'tastierino spento: velocità e accelerazione attenuate');
  d.getElementById('pad_look').click();
  ok(!off('pad_look_speed') && !off('pad_look_speed_v'), 'tastierino acceso: righe normali');
  // Meteo › Data e ora: ora in HH:MM, nome del mese, dipendenze con '!'
  w.eval(`loadSettings({sky_enabled:false, sky_now:false, sky_flow:true, sky_hour:17.5, sky_month:2})`);
  ok(d.getElementById('sky_hour_v').value === '17:30', `ora mostrata come 17:30 (${d.getElementById('sky_hour_v').value})`);
  ok(d.querySelector('.row[data-k="sky_month"] .unit').textContent === 'febbraio', 'mese 2 = febbraio, nella lingua del pannello');
  d.getElementById('sky_hour_v').value = '6:15'; w.eval(`fix('sky_hour')`);
  ok(w.eval('collect()').sky_hour === 6.25 && d.getElementById('sky_hour_v').value === '06:15', 'scrivere 6:15 salva 6,25 ore');
  ok(off('sky_now') && off('sky_hour') && off('sky_day_minutes'), 'cielo spento: righe attenuate');
  d.getElementById('sky_enabled').click();
  ok(!off('sky_now') && !off('sky_hour') && !off('sky_day_minutes'), 'cielo acceso: righe normali');
  d.getElementById('sky_now').click();
  ok(off('sky_hour') && off('sky_flow') && off('sky_day_minutes') && !off('sky_shadows'), 'ora attuale: data, ora e scorrere attenuati');
  // Situazioni pronte: sette pulsanti con nome e descrizione tradotti, il clic chiama Ruby
  const wps = [...d.querySelectorAll('#pane_weather_presets .wp')];
  ok(wps.length === 7 && wps.every(b => b.querySelector('b').textContent && !b.querySelector('b').textContent.startsWith('wp.')
     && b.querySelector('span').textContent), `situazioni: ${wps.length} pulsanti con nome e descrizione`);
  ok(wps.some(b => b.querySelector('b').textContent === 'Notte di neve'), 'nomi nella lingua del pannello (Notte di neve)');
  wps.find(b => b.dataset.wp === 'storm').click();
  ok(presetCalls.join() === 'storm', 'il clic su Temporale estivo chiama weather_preset("storm")');
  // Luogo: la tendina compila latitudine, longitudine e fuso e mostra il luogo che corrisponde
  d.getElementById('sky_now').click();
  ok(off('sky_city') && off('sky_lat'), 'luogo del modello: luoghi pronti e coordinate attenuati');
  d.getElementById('sky_place_custom').click();
  ok(!off('sky_city') && !off('sky_lat'), 'luogo personalizzato: coordinate attive');
  const city = d.getElementById('sky_city');
  city.value = 'tromso'; city.dispatchEvent(new w.Event('change'));
  const sv = w.eval('collect()');
  ok(sv.sky_lat === 69.65 && sv.sky_lon === 18.96 && sv.sky_tz === 1 && sv.sky_place_custom === true,
     `Tromsø compila le coordinate (${sv.sky_lat}, ${sv.sky_lon}, UTC+${sv.sky_tz})`);
  ok(sv.sky_city === undefined, 'la tendina dei luoghi non è un\'impostazione salvata');
  d.getElementById('sky_lat_v').value = '70,5'; w.eval(`fix('sky_lat')`);
  ok(city.selectedIndex === -1, 'coordinate cambiate a mano: nessun luogo pronto selezionato');
  d.getElementById('sky_lat_v').value = '-90'; w.eval(`fix('sky_lat')`);
  ok(city.value === 'sp' && city.options[city.selectedIndex].textContent === 'Polo Sud', 'latitudine −90: Polo Sud (nome tradotto)');
  w.eval(`setSky({on:true, overlay:true, custom:true, y:2026, mo:6, d:21, h:0, mi:0, place:'Roma, Italia', lat:69.65, lon:18.96,
                 sun:3, moon:10, phase:1, moon_up:false})`);
  ok(d.getElementById('skyStatus').textContent.includes('Tromsø') && !d.getElementById('skyStatus').textContent.includes('Roma'),
     'stato con luogo personalizzato: il nome del luogo scelto, non quello del modello');
  w.eval(`setSky({on:true, overlay:true, y:2026, mo:6, d:21, h:21, mi:5, place:'Roma, Italia', lat:41.88, lon:12.5,
                 sun:-3, moon:62, phase:3, moon_up:true})`);
  const sst = d.getElementById('skyStatus').textContent;
  ok(sst.includes('21:05') && sst.includes('Roma, Italia') && sst.includes('giugno') && sst.includes('gibbosa crescente') &&
     sst.includes('3° sotto'), `stato del cielo: ${sst}`);
  // animazioni e descrizioni
  d.getElementById('ui_animations').click(); d.getElementById('ui_hints').click();
  ok(d.body.classList.contains('noanim') && d.body.classList.contains('nohints'), 'animazioni e descrizioni spente');
  // anteprima del mirino
  const st2 = d.getElementById('hud_cross_style');
  st2.value = 'crossdot'; st2.dispatchEvent(new w.Event('change'));
  ok(d.querySelectorAll('#hudsvg path').length === 2 && d.querySelectorAll('#hudsvg circle').length === 1,
     'anteprima: croce con punto e barra di carica');
  d.getElementById('hud_cross_outline').click();
  ok(d.querySelectorAll('#hudsvg circle').length === 2, 'anteprima: bordo scuro disegnato sotto');
  // infoHTML per una scelta (il lampo "tasto riservato" del test 17 durerebbe ancora 1,8 s)
  w.eval('FLASH = null');
  d.querySelector('.row[data-k="ui_theme"] .lbl').dispatchEvent(new w.MouseEvent('mouseover', { bubbles: true }));
  ok(d.getElementById('status').textContent.includes(it['o.ui_theme.dark']) && !d.getElementById('status').textContent.includes(it['ui.range']),
     'barra in basso: predefinito "Scuro", nessun intervallo');
  // la cache fa ripartire il pannello con l'aspetto scelto
  ok(w.eval('LOOK_CACHE.ui_theme') === 'light', 'aspetto ricordato per la prossima apertura (LOOK_CACHE ? localStorage)');
  // ripristino
  d.querySelector('#pane_system_look .mbtns button').click();
  const last3 = saved[saved.length - 1];
  ok(last3.ui_theme === 'dark' && last3.ui_accent === RB_DEF.ui_accent && !last3.hud_cross_outline &&
     cssv('bg') === '#151515' && d.body.classList.contains('ti-text') && d.getElementById('logo').textContent === '⚡',
     'Ripristina aspetto: tutto torna ai predefiniti');
  ok(!d.querySelector('#pane_system_look .row.mod'), 'nessuna riga dell\'Aspetto segnata come modificata');
  // livelli: base mostra solo l'essenziale dell'Aspetto
  w.eval('setLevel(1, false)');
  const vis = [...d.querySelectorAll('#pane_system_look .row')].filter(r => w.getComputedStyle(r).display !== 'none').map(r => r.dataset.k);
  ok(vis.includes('ui_theme') && vis.includes('hud_cross_color') && !vis.includes('ui_radius') && !vis.includes('ui_bg'),
     `base: ${vis.length} impostazioni dell'Aspetto visibili`);
  // respawn nel Salto
  ok(!!d.querySelector('#pane_player_jump .row[data-k="respawn_fall_time"]') && RB_DEF.respawn_fall_time === 5,
     'Salto: durata della caduta prima del respawn (predefinita 5 s)');
  ok(RB_DEF.respawn_exit_count === 2 && RB_DEF.respawn_calm_time === 2 &&
     +d.querySelector('#pane_player_jump .row[data-k="respawn_exit_count"]')?.dataset.lv === 3 &&
     +d.querySelector('#pane_player_jump .row[data-k="respawn_calm_time"]')?.dataset.lv === 3,
     'Salto: uscita dopo respawn di seguito e tempo per azzerarli (livello 3, predefiniti 2 e 2 s)');

  // 19. Ponte per Claude: interruttore (avanzate) e stato da Ruby
  w.eval('setLevel(2, false); selTab("system"); selSub("bridge")');
  const bs = d.getElementById('bridgeStatus');
  ok(!!d.getElementById('bridge_enabled') && RB_DEF.bridge_enabled === false, 'Sistema › Ponte Claude: interruttore, spento di default');
  w.eval('setBridge({on: true, port: 47811})');
  ok(bs.classList.contains('on') && bs.textContent.includes(it['bridge.on'].replace('{port}', '47811')), 'stato: attivo sulla porta 47811');
  w.eval('setBridge({on: false, fail: true})');
  ok(!bs.classList.contains('on') && bs.textContent.includes(it['bridge.fail']), 'stato: nessuna porta libera');
  w.eval(`applyLang(${JSON.stringify({ strings: Object.assign({}, en, it), languages: [], current: 'it', resolved: 'it' })})`);
  ok(d.getElementById('bridgeStatus').textContent.includes(it['bridge.fail']), 'lo stato sopravvive al cambio lingua');

  // 20. Coppie minimo/massimo: portandone uno oltre l'altro, l'altro segue
  const rbPairs = [...rb.slice(rb.indexOf('MIN_MAX_PAIRS')).split('.freeze')[0].matchAll(/%w\[(\w+) (\w+)\]/g)]
    .map(m => [m[1], m[2]]);
  ok(rbPairs.length === 3 && JSON.stringify(rbPairs) === JSON.stringify(w.eval('PAIRS')),
     'coppie minimo/massimo uguali in panel.html e lib/config.rb');
  w.eval(`loadSettings(${JSON.stringify(Object.assign({}, RB_DEF, { kick_force_min: 3, kick_force: 8,
    throw_force_min: 3, throw_force_max: 15, crouch_height: 0.9, eye_height: 1.7 }))})`);
  const vbox = k => d.getElementById(k + '_v');
  vbox('kick_force_min').value = '12'; w.eval("fix('kick_force_min')");
  let ps = saved[saved.length - 1];
  ok(ps.kick_force_min === 12 && ps.kick_force === 12 && vbox('kick_force').value === '12.0',
     'calcio: minimo portato oltre il massimo → il massimo lo segue (12)');
  vbox('kick_force').value = '1'; vbox('kick_force').dispatchEvent(new w.Event('input'));
  ok(vbox('kick_force_min').value === '12.0', 'mentre si digita il massimo il minimo non si muove');
  w.eval("fix('kick_force')"); ps = saved[saved.length - 1];
  ok(ps.kick_force === 1 && ps.kick_force_min === 1, '…a fine digitazione sì (1 e 1)');
  const tsl = d.getElementById('throw_force_max');
  tsl.value = '2'; tsl.dispatchEvent(new w.Event('input')); w.eval('saveNow()'); ps = saved[saved.length - 1];
  ok(ps.throw_force_max === 2 && ps.throw_force_min === 2, 'lancio: slider del massimo sotto il minimo → il minimo lo segue');
  vbox('eye_height').value = '0.6'; w.eval("fix('eye_height')"); ps = saved[saved.length - 1];
  ok(ps.eye_height === 0.6 && ps.crouch_height === 0.6, 'altezza in piedi sotto quella accovacciata → accovacciata 0,6 m');
  ok(d.querySelector('.row[data-k="crouch_height"]').classList.contains('mod'), 'il valore spostato risulta modificato');
  w.eval("resetOne('eye_height')"); ps = saved[saved.length - 1];
  ok(ps.eye_height === RB_DEF.eye_height && ps.crouch_height === 0.6, 'ripristinando il massimo il minimo, già in ordine, resta');

  // Percorsi: elenco vuoto, poi due percorsi con i comandi
  const pl = () => d.getElementById('pathList');
  ok(!!pl() && pl().textContent.includes(it['path.empty']), 'Percorsi: senza percorsi la spiegazione di come registrarne uno');
  w.eval(`setPaths(${JSON.stringify([{ name: 'Giro del faro', dur: 75.4, date: '2026-10-04' }, { name: 'Scala "a" <b>', dur: 4, date: '2026-10-04' }])})`);
  const rows = pl().querySelectorAll('.prow');
  ok(rows.length === 2 && rows[0].textContent.includes('1:15') && rows[1].querySelector('.pn').textContent === 'Scala "a" <b>',
     'due percorsi in elenco, con la durata (1:15) e i nomi presi alla lettera');
  rows[1].querySelectorAll('button')[2].click();
  rows[0].querySelector('button.pgo').click();
  ok(JSON.stringify(pathCalls) === JSON.stringify([{ cmd: 'frames', name: 'Scala "a" <b>' }, { cmd: 'play', name: 'Giro del faro' }]),
     'i pulsanti mandano a Ruby comando e nome');
  // Posizioni nel modello (lib/pathkeys.rb): «Modifica», poi Nascondi/Mostra, ↺ solo se c'è la registrazione
  const btns = r => [...r.querySelectorAll('button')].map(x => x.textContent.trim());
  ok(btns(rows[0]).includes('◆ ' + it['path.edit']) && !btns(rows[0]).includes('↺') && !rows[0].querySelector('.pk'),
     'senza posizioni: il pulsante «Modifica», niente ↺');
  w.eval(`setPaths(${JSON.stringify([{ name: 'Giro', dur: 12, date: '1', keys: 7, shown: true, rec: true },
                                     { name: 'Nuovo', dur: 2, date: '2', keys: 2, shown: false, rec: false }])})`);
  const r2 = pl().querySelectorAll('.prow');
  ok(btns(r2[0]).includes(it['path.hide']) && btns(r2[0]).includes('↺') && r2[0].querySelector('.pk').textContent.includes('7'),
     'con le posizioni visibili: «Nascondi», ↺ e quante sono');
  ok(btns(r2[1]).includes(it['path.show']) && !btns(r2[1]).includes('↺'), 'nascoste: «Mostra»; senza registrazione niente ↺');
  pathCalls.length = 0;
  [...r2[0].querySelectorAll('button')].find(x => x.textContent.trim() === it['path.hide']).click();
  [...r2[0].querySelectorAll('button')].find(x => x.textContent.trim() === '↺').click();
  d.querySelector('.pnew button').click();
  ok(JSON.stringify(pathCalls) === JSON.stringify([{ cmd: 'edit', name: 'Giro' }, { cmd: 'revert', name: 'Giro' }, { cmd: 'new', name: '' }]),
     'Nascondi, ↺ e «Nuovo dalla vista» arrivano a Ruby');
  // Elenco delle posizioni: il triangolo lo apre sotto al percorso, rientrato; resta aperto ai setPaths
  ok(!r2[0].querySelector('.ptog'), 'senza pts niente triangolo');
  const giro = pts => [{ name: 'Giro', dur: 12, date: '1', keys: pts.length, shown: true, rec: true, pts },
                       { name: 'Nuovo', dur: 2, date: '2', keys: 2, shown: false, rec: false, pts: [{ t: 0, p: 0, v: 0, z: 1 }, { t: 2, p: 0, v: 0, z: 1 }] }];
  w.eval(`setPaths(${JSON.stringify(giro([{ t: 0, p: 0, v: 0, z: 1 }, { t: 5.2, p: 2.5, v: 1.8, z: 2 }, { t: 75, p: 0, v: 0, z: 1 }]))})`);
  ok(pl().querySelectorAll('.ptog').length === 2 && !pl().querySelector('.ppts'), 'con le posizioni: triangolo, elenco chiuso');
  pl().querySelector('.ptog').click();
  let pp = pl().querySelectorAll('.pitem')[0].querySelectorAll('.ppts .ppt');
  ok(pp.length === 3 && pl().querySelector('.ptog').classList.contains('open') && pl().querySelectorAll('.ppts').length === 1,
     'aperto il primo: tre posizioni sotto di lui, il secondo resta chiuso');
  ok(pp[0].textContent === '10:00' && pp[1].textContent.includes('0:05') && pp[1].textContent.includes('⏸ 2.5 s')
     && pp[1].textContent.includes('1.8 m/s') && pp[1].textContent.includes('×2') && pp[2].textContent === '31:15',
     'numero e arrivo; sosta, velocità e zoom solo se ci sono');
  pathCalls.length = 0;
  pp[1].click();
  ok(JSON.stringify(pathCalls) === JSON.stringify([{ cmd: 'key', name: 'Giro', i: 1 }]), 'clic su una posizione: Ruby ne apre il pannello');
  w.eval(`setPaths(${JSON.stringify(giro([{ t: 0, p: 0, v: 0, z: 1 }, { t: 4, p: 0, v: 0, z: 1 }]))})`);
  ok(pl().querySelectorAll('.ppts .ppt').length === 2, 'nuovo elenco da Ruby (sfera cancellata): resta aperto, con due posizioni');
  pl().querySelector('.ptog').click();
  ok(!pl().querySelector('.ppts'), 'di nuovo il triangolo: si richiude');
  ok(!!d.getElementById('path_video_size') && !!d.getElementById('path_smooth'), 'sotto l\'elenco le impostazioni dei percorsi');
  const all = w.eval('Object.keys(FIELDS).length');
  const lv = n => w.eval(`Object.values(FIELDS).filter(f => f.lv === ${n}).length`);
  console.log(`     ripartizione: ${lv(1)} base · ${lv(2)} avanzate · ${lv(3)} molto avanzate (tot ${all})`);

  // Pacchetto per l'Extension Warehouse: niente ponte, niente sezione (a nessun livello, nemmeno cercando)
  w.eval(`applyLang(${JSON.stringify({ strings: Object.assign({}, en, it), languages: [], current: 'it', resolved: 'it', bridge: false })})`);
  w.eval('setLevel(3, true)');
  d.querySelector('#tabs1 button[data-t="system"]').click();
  const subs = [...d.querySelectorAll('#tabs2 button')].filter(b => w.getComputedStyle(b).display !== 'none').map(b => b.dataset.s);
  ok(!subs.includes('bridge') && subs.includes('lang'), `senza ponte: Sistema senza la sezione Ponte Claude (${subs.join(', ')})`);
  const cerca = (t) => { d.getElementById('q').value = t; w.eval('runSearch(true)'); };   // #q è ricreato da applyLang
  cerca(it['f.bridge_enabled']);
  ok(!d.querySelector('.row[data-k="bridge_enabled"]').classList.contains('hit'), 'senza ponte: la ricerca non trova le sue impostazioni');
  cerca(it['f.move_speed']);
  ok(d.querySelector('.row[data-k="move_speed"]').classList.contains('hit'), 'senza ponte: il resto della ricerca funziona');

  // ── Menu del destro: mai quello del browser; nelle caselle il nostro, tradotto ──
  const menu = el => !el.dispatchEvent(new w.MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 50, clientY: 50 }));
  const aperto = () => d.getElementById('menuctx').classList.contains('aperto');
  ok(menu(d.getElementById('btnSave')) && !aperto(), 'destro fuori dalle caselle: niente menu del browser, nessun menu');
  const qm = d.getElementById('q');
  qm.value = 'velocità';
  qm.setSelectionRange(0, 0);
  ok(menu(qm) && aperto(), 'destro nella casella di ricerca: niente menu del browser, si apre il nostro');
  ok(d.getElementById('t-cut').textContent === it['ke.cut'] && d.getElementById('t-paste').textContent === it['ke.paste'],
     `in italiano: ${it['ke.cut']}, ${it['ke.copy']}, ${it['ke.paste']}`);
  ok(d.getElementById('c-copy').disabled && !d.getElementById('c-paste').disabled, 'niente selezionato: Copia spento, Incolla acceso');
  d.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
  ok(!aperto(), 'Esc lo chiude');
  let inputs = 0;
  qm.addEventListener('input', () => { inputs++; });
  qm.value = '';
  menu(qm);
  d.getElementById('c-paste').click();
  ok(pasteCalls.length === 1 && !aperto(), 'Incolla: gli appunti si chiedono a Ruby (panel_paste)');
  w.eval('incolla("velocità\\r\\n")');
  ok(qm.value === 'velocità' && inputs === 1, 'il testo entra nella casella e la ricerca riparte come scrivendo');
  const nbm = d.querySelector('.nbox');
  ok(nbm && menu(nbm) && aperto(), 'anche nelle caselle dei valori');
  d.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'Escape' }));
});
