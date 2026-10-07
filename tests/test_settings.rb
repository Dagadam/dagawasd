# Impostazioni: tasti personalizzati, riga di stato, importazione e registro errori.
#   Esecuzione:  ruby -E UTF-8 tests/test_settings.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
F = DagaWASD::FPSWalk
F.load_cfg
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
cfg = F.instance_variable_get(:@cfg)

# ── Caricamento da main.rb: menu e barra registrati ──────────────
plug = UI.menu('Plugins').items.find { |n, _| n == 'DagaWASD' }
ok(plug && plug[1].items.size == 2, 'main.rb carica lib/ e registra il sottomenu DagaWASD (2 voci)')
tb = UI.toolbars.find { |x| x.name == 'DagaWASD' }
ok(tb && tb.items.size == 2, 'barra degli strumenti DagaWASD con 2 pulsanti')
ok(F::PLUGIN_DIR == File.expand_path('..', __dir__), 'PLUGIN_DIR è la cartella dell\'estensione, non lib/')

# ── Tasti: pulizia ───────────────────────────────────────────────
dk = F::DEFAULT_KEYS
ok(F.sanitize_keys(nil) == dk, 'nessun tasto salvato → predefiniti')
ok(F.sanitize_keys(dk.merge('jump' => 74))['jump'] == 74, 'tasto valido accettato (Salto → J)')
ok(F.sanitize_keys(dk.merge('jump' => '74'))['jump'] == 74, 'codice come stringa numerica accettato')
ok(F.sanitize_keys(dk.merge('jump' => F::VK_ESC))['jump'] == dk['jump'], 'ESC è riservato → torna al predefinito')
ok(F.sanitize_keys(dk.merge('jump' => 999))['jump'] == dk['jump'], 'codice fuori intervallo → predefinito')
ok(F.sanitize_keys(dk.merge('jump' => F::VK_W)) == dk, 'due azioni sullo stesso tasto → tutti predefiniti')
ok(F.sanitize_key_labels('jump' => 'Ò', 'bogus' => 'X', 'kick' => '') == { 'jump' => 'Ò' },
   'etichette: solo azioni note e testi non vuoti')

# ── Tasti: mappa effettiva e tasti inghiottiti ───────────────────
cfg['keys'] = dk.merge('jump' => 0x4A, 'use' => 0x45, 'run' => 0x11)   # J, E, Ctrl
F.refresh_keys
sw = F.instance_variable_get(:@swallow)
ok(sw.include?(0x4A) && sw.include?(0x45), 'i nuovi tasti vengono intercettati in modalità FPS')
ok(!sw.include?(F::VK_SPACE), 'Space non più usato: torna a SketchUp')
ok(!sw.include?(F::VK_LALT) && !sw.include?(F::VK_ALT), 'Alt non più usato: non viene più intercettato')
ok(!sw.include?(F::VK_CONTROL) && !sw.include?(0xA2), 'Ctrl (corsa) non viene mai intercettato')
ok(sw.include?(F::VK_ESC) && sw.include?(F::VK_UP), 'ESC e frecce restano sempre intercettati')
ok(F.key_of?(0xA2, 'run') && F.key_of?(0xA3, 'run'), 'Ctrl sinistro e destro valgono come Ctrl')
keys = F.instance_variable_get(:@keys)
keys[0x4A] = true
ok(F.pressed?('jump'), 'pressed?: Salto su J premuto')
keys[0x4A] = false

# ── Riga di stato con i tasti scelti ─────────────────────────────
cfg['language'] = 'it'
F.load_lang
cfg['key_labels'] = { 'use' => 'E' }
hud = F.hud_text
ok(hud.include?('J salta') && hud.include?('E aziona') && hud.include?('Ctrl corri'), "riga di stato aggiornata: #{hud}")
ok(hud.include?('WASD muovi') && hud.include?('C accovacciati'), 'i tasti invariati restano come nella traduzione')
cfg['keys'] = dk.merge('forward' => 0x5A, 'left' => 0x51)   # AZERTY: Z Q S D
cfg['key_labels'] = {}
F.refresh_keys
ok(F.hud_text.include?('ZQSD muovi'), 'movimento AZERTY: "ZQSD muovi"')
cfg['keys'] = dk.dup; F.refresh_keys
ok(F.hud_text == F.t('rt.hud'), 'tasti predefiniti: riga di stato identica alla traduzione')

# ── Importazione ─────────────────────────────────────────────────
before = cfg.dup
n = F.import_values('dagawasd_settings' => 1, 'settings' => {
  'move_speed' => 5.0, 'invert_y' => true, 'gravity' => 'tanta', 'language' => 'de',
  'panel_level' => 3, 'sconosciuta' => 1, 'keys' => { 'jump' => 74 }, 'materials' => []
})
ok(n == 4, "importate solo le chiavi valide (#{n} di 8)")
ok(cfg['move_speed'] == 5.0 && cfg['invert_y'] == true, 'valori numerici e booleani importati')
ok(cfg['gravity'] == before['gravity'], 'valore del tipo sbagliato ignorato')
ok(cfg['language'] == before['language'] && cfg['panel_level'] == before['panel_level'],
   'lingua e livello del pannello non vengono importati')
ok(!cfg.key?('sconosciuta'), 'chiave sconosciuta ignorata')
ok(F.import_values([1, 2]).zero? && F.import_values(nil).zero?, 'file senza impostazioni → 0')
cfg.replace(before)

# ── Home riservato (Ctrl+Home apre il pannello) ──────────────────
ok(F.sanitize_keys(dk.merge('jump' => F::VK_HOME))['jump'] == dk['jump'], 'Home è riservato → torna al predefinito')

# ── Aspetto: colori e scelte ─────────────────────────────────────
before = cfg.dup
cfg.merge!('ui_theme' => 'neon', 'ui_font' => 'georgia', 'ui_accent' => '#FF8800',
           'ui_bg' => 'rosso', 'hud_cross_color' => 12, 'hud_cross_style' => 'circle')
F.sanitize_look
ok(cfg['ui_theme'] == 'dark' && cfg['ui_font'] == 'georgia', 'scelta sconosciuta → predefinita, scelta valida tenuta')
ok(cfg['ui_accent'] == '#ff8800', 'colore valido tenuto (in minuscolo)')
ok(cfg['ui_bg'] == F::DEFAULT['ui_bg'] && cfg['hud_cross_color'] == F::DEFAULT['hud_cross_color'],
   'colori non validi → predefiniti')
ok(cfg['hud_cross_style'] == 'circle', 'forma del mirino valida tenuta')
ok(F.rgba('ui_accent', 0.5) == [255, 136, 0, 128], "rgba: '#ff8800' al 50 % → [255, 136, 0, 128]")
ok(F::LOOK_CHOICES.all? { |k, v| v.include?(F::DEFAULT[k]) }, 'ogni predefinito a scelta è fra le scelte ammesse')
n = F.import_values('settings' => { 'ui_theme' => 'light', 'ui_accent' => '#123456', 'ui_font_size' => 17 })
ok(n == 3 && cfg['ui_theme'] == 'light' && cfg['ui_font_size'] == 17, 'l\'aspetto si importa (testi e numeri)')
cfg.replace(before)

# ── Respawn dopo una caduta nel vuoto ────────────────────────────
iv = ->(k, v) { F.instance_variable_set(k, v) }
gv = ->(k) { F.instance_variable_get(k) }
iv[:@on_ground, true]; iv[:@safe_trail, []]; iv[:@fall_time, 0.0]; iv[:@left_ground_at, nil]
iv[:@cur_h_m, 1.7]; iv[:@vv, 0.0]; iv[:@respawn_streak, 0]; iv[:@ground_time, 0.0]
# a terra per 2 s camminando lungo x, poi il bordo a x = 200"
(0..20).each do |i|
  iv[:@eye_x, i * 10.0]; iv[:@eye_y, 0.0]; iv[:@floor_z_in, 0.0]
  F.track_fall(100.0 + i * 0.1, 0.1, false)
end
trail = gv[:@safe_trail]
ok(trail.size == 21 && trail.last[1] == 200.0, "scia a terra: una posizione ogni 0,1 s (#{trail.size})")
iv[:@on_ground, false]; iv[:@vv, 2.0]
F.track_fall(102.1, 0.1, false)                # ancora in salita: non conta
ok(gv[:@fall_time].zero? && gv[:@left_ground_at] == 102.1, 'la salita di un salto non conta come caduta')
iv[:@vv, -5.0]
50.times { |i| F.track_fall(102.2 + i * 0.1, 0.1, false) }
ok((gv[:@fall_time] - 5.0).abs < 1e-6, "caduta libera contata (#{gv[:@fall_time].round(2)} s)")
iv[:@eye_x, 999.0]; iv[:@eye_z, -5000.0]; iv[:@vh_x, 3.0]
F.fall_respawn(107.2)
ok(gv[:@eye_x].between?(150.0, 160.0), "respawn mezzo secondo prima di lasciare il suolo (x = #{gv[:@eye_x]}, bordo a 200)")
ok(gv[:@eye_z] == 1.7 * F::M_TO_IN && gv[:@vv].zero? && gv[:@vh_x].zero? && gv[:@on_ground],
   'dopo il respawn: in piedi sul pavimento, fermo')
ok(gv[:@fall_time].zero? && gv[:@left_ground_at].nil?, 'contatore della caduta azzerato')
iv[:@safe_trail, []]; iv[:@spawn_point, [1.0, 2.0, 3.0]]
F.fall_respawn(200.0)
ok(gv[:@eye_x] == 1.0 && gv[:@eye_y] == 2.0, 'mai toccato terra: si torna al punto di partenza')
ok(gv[:@respawn_streak] == 2, "due respawn senza fermarsi a terra: serie a 2 (#{gv[:@respawn_streak]})")
ok(F.respawn_exit?, 'al secondo respawn di seguito si esce dalla modalità (predefinito)')
cfg['respawn_exit_count'] = 3
ok(!F.respawn_exit?, 'con 3 respawn impostati, al secondo si resta')
cfg['respawn_exit_count'] = 0
ok(!F.respawn_exit?, 'con 0 la sicurezza è spenta')
cfg['respawn_exit_count'] = 2
iv[:@on_ground, true]
F.track_fall(201.0, 1.0, false)
ok(gv[:@respawn_streak] == 2, 'un attimo a terra non azzera la serie')
iv[:@on_ground, false]; F.track_fall(201.1, 0.1, false)
iv[:@on_ground, true]
3.times { |i| F.track_fall(202.0 + i, 1.0, false) }
ok(gv[:@respawn_streak].zero?, 'qualche secondo fermi a terra azzera la serie')

# ── Registro errori ──────────────────────────────────────────────
require 'tmpdir'
log = File.join(Dir.tmpdir, 'dagawasd_test_settings.log')
File.delete(log) if File.exist?(log)
F.instance_variable_set(:@log_file, log)
F.instance_variable_set(:@log_quiet, true)
begin
  raise ArgumentError, 'prova registro'
rescue => e
  F.log_error(:test_settings, e)
  F.log_error(:test_settings, e)    # stesso errore: una volta sola
end
txt = File.exist?(log) ? File.read(log, encoding: 'UTF-8') : ''
ok(txt.include?('[test_settings] ArgumentError: prova registro'), 'errore scritto nel registro')
ok(txt.scan('prova registro').size == 1, 'lo stesso errore viene scritto una volta sola')
ok((F.log_error(:x, Object.new) rescue :raised).nil?, 'log_error non solleva mai eccezioni')
w32 = F.instance_variable_get(:@w32)
F.instance_variable_set(:@w32, nil)
F.find_main_window   # @w32 assente: il rescue interno passa dal registro invece di tacere
F.instance_variable_set(:@w32, w32)
ok(File.read(log, encoding: 'UTF-8').include?('[find_main_window]'), 'un rescue interno finisce nel registro')
r = F.read_log
ok(r['path'] == log && r['text'].include?('prova registro'), 'read_log: percorso e contenuto per il pannello')
ok(F.log_count == 2, "log_count conta le voci (#{F.log_count})")
File.open(log, 'ab') { |f| f.write("byte strano: ".b + [0xFF].pack('C') + "\n".b) }   # 0xFF: non è UTF-8
ok(F.read_log['text'].valid_encoding?, 'read_log restituisce sempre UTF-8 valido')
F.clear_log
ok(!File.exist?(log) && F.read_log['text'] == '' && F.log_count.zero?, 'clear_log svuota il registro')
begin; raise ArgumentError, 'prova registro'; rescue => e; F.log_error(:test_settings, e); end
ok(F.log_count == 1, 'dopo lo svuotamento lo stesso errore viene registrato di nuovo')
File.delete(log)

# ── settings.json in %APPDATA%\DagaWASD, recuperato dalla cartella dell'estensione ──
ok(F::SETTINGS_FILE.start_with?(ENV['APPDATA']) && !F::SETTINGS_FILE.start_with?(F::PLUGIN_DIR),
   'settings.json sta fuori dalla cartella dell\'estensione (un .rbz non lo riscrive)')
old_const = F::OLD_SETTINGS_FILE
old_file  = File.join(Dir.mktmpdir('dagawasd_vecchio'), 'settings.json')
File.write(old_file, JSON.generate('move_speed' => 5.5))
F.send(:remove_const, :OLD_SETTINGS_FILE); F.const_set(:OLD_SETTINGS_FILE, old_file)
saved_sf = F.instance_variable_get(:@settings_file)
F.instance_variable_set(:@settings_file, nil)
File.delete(F::SETTINGS_FILE) if File.exist?(F::SETTINGS_FILE)
ok(F.load_cfg['move_speed'] == 5.5 && File.exist?(F::SETTINGS_FILE),
   'primo avvio dopo l\'aggiornamento: le impostazioni vecchie vengono recuperate')
ok(File.exist?(old_file), 'il settings.json vecchio resta al suo posto')
File.write(F::SETTINGS_FILE, JSON.generate('move_speed' => 4.0))
ok(F.load_cfg['move_speed'] == 4.0, 'avvii successivi: vale quello nuovo, il vecchio non lo ricopre')
F.instance_variable_get(:@cfg)['move_speed'] = 3.3
F.save_cfg
ok(JSON.parse(File.read(F::SETTINGS_FILE))['move_speed'] == 3.3 && JSON.parse(File.read(old_file))['move_speed'] == 5.5,
   'il salvataggio va nel file nuovo')
File.delete(F::SETTINGS_FILE)
File.delete(old_file)
ok(F.load_cfg['move_speed'] == F::DEFAULT['move_speed'] && !File.exist?(F::SETTINGS_FILE),
   'nessun settings.json, né nuovo né vecchio: valori predefiniti')
F.send(:remove_const, :OLD_SETTINGS_FILE); F.const_set(:OLD_SETTINGS_FILE, old_const)
F.instance_variable_set(:@settings_file, saved_sf)

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
