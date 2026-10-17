# Bug trovati nella revisione del codice: ogni test fallisce col codice di
# prima e passa con la correzione.
#   Esecuzione:  ruby -E UTF-8 tests/test_regressions.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end

tmp = Dir.mktmpdir('dagawasd_test')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
settings = File.join(tmp, 'settings.json')
F.instance_variable_set(:@settings_file, settings)

# ── settings.json valido come JSON ma non un oggetto ────────────────
# Prima: DEFAULT.merge(nil) → TypeError, e register_ui non creava menu e barra.
File.write(settings, 'null')
cfg = (F.load_cfg rescue :raised)
ok(cfg.is_a?(Hash) && cfg['move_speed'] == F::DEFAULT['move_speed'], 'settings.json = null: si parte dai default invece di fallire')
ok(File.exist?(File.join(tmp, 'settings.bad.json')) && !File.exist?(settings),
   'il file illeggibile viene messo da parte come settings.bad.json')
File.write(settings, '{"move_speed": 5.0')          # troncato a metà
cfg = (F.load_cfg rescue :raised)
ok(cfg.is_a?(Hash) && cfg['move_speed'] == F::DEFAULT['move_speed'], 'settings.json troncato: default, nessun errore')

# ── Salvataggio atomico ─────────────────────────────────────────────
F.load_cfg
F.instance_variable_get(:@cfg)['move_speed'] = 4.2
F.save_cfg
ok(JSON.parse(File.read(settings))['move_speed'] == 4.2, 'save_cfg scrive il file')
F.instance_variable_get(:@cfg)['move_speed'] = 4.4
F.save_cfg                                           # sostituisce un file esistente
ok(JSON.parse(File.read(settings))['move_speed'] == 4.4 && !File.exist?("#{settings}.tmp"),
   'save_cfg sostituisce il file esistente e non lascia il temporaneo')

# ── Corpo precipitato nel vuoto ─────────────────────────────────────
# Prima: finiva in to_rest ma il filtro "non addormentare chi si muove" lo
# teneva (cade, quindi si muove): restava simulato per sempre.
model = Object.new
def model.raytest(*); nil; end
def model.start_operation(*); end
def model.commit_operation; end
def model.entities; []; end
Sketchup.define_singleton_method(:active_model) { model }
F.load_cfg
phys = F.instance_variable_get(:@phys_entities)
phys.clear
st = ->(vz) { { vx: 0.0, vy: 0.0, vz: vz, ox: 0.0, oy: 0.0, oz: 0.0, fz: nil, still: 0.0, props: nil } }
deep = StubGroup.new([0, 0, -9000], [10, 10, -8990])   # sotto −200 m
air  = StubGroup.new([50, 0, 100], [60, 10, 110])       # in aria, niente sotto
phys[deep] = st.(-900.0)
phys[air]  = st.(0.0)
F.step_physics(1.0 / 60)
ok(!phys.key?(deep), 'un corpo precipitato sotto −200 m esce dalla simulazione')
ok(phys.key?(air), 'un corpo che sta cadendo (non ancora nel vuoto) resta simulato')
gone = StubGroup.new([0, 0, 0], [10, 10, 10])
def gone.valid?; false; end
phys[gone] = st.(-50.0)
F.step_physics(1.0 / 60)
ok(!phys.key?(gone), 'un corpo cancellato dal modello esce dalla simulazione')
phys.clear

# ── FPSTool#draw: errore durante il disegno ─────────────────────────
# Prima: il rescue chiamava log_error, che nella classe FPSTool non esiste →
# NoMethodError dentro il rescue stesso, a ogni fotogramma.
view = Object.new
def view.vpwidth; raise 'vista non pronta'; end
F.instance_variable_set(:@active, true)
r = begin; F::FPSTool.new.draw(view); :ok; rescue Exception => e; e.class; end
F.instance_variable_set(:@active, false)
ok(r == :ok, "draw non solleva eccezioni se la vista dà errore (#{r})")
ok(File.read(File.join(tmp, 'test.log')).include?('[draw] RuntimeError: vista non pronta'), "l'errore di draw finisce nel registro")

# ── Riga di stato: nome del tasto con la barra rovesciata ───────────
F.load_lang
cfg = F.instance_variable_get(:@cfg)
cfg['keys'] = F::DEFAULT_KEYS.merge('jump' => 0xDC); cfg['key_labels'] = { 'jump' => '\\0' }
F.refresh_keys
ok(F.hud_text.include?('\\0 '), 'un nome di tasto con "\\" compare così com\'è nella riga di stato')

# ── G su un oggetto annidato troppo pesante ──────────────────────────
# Prima: G si fermava al gruppo più esterno ("troppo pesante") anche se il
# mirino era su un libro dentro la libreria. Ora scende di livello.
cfg['obj_use_materials'] = false; cfg['obj_density'] = 400.0; cfg['obj_fill_ratio'] = 0.55
F.instance_variable_get(:@body_cache).clear
m2i = 39.3701
box = ->(sx, sy, sz) { StubGroup.new([0, 0, 0], [sx * m2i, sy * m2i, sz * m2i]) }
libreria = box.(2.4, 0.35, 2.6); mensola = box.(0.6, 0.3, 0.4); libro = box.(0.03, 0.2, 0.25)
ok(F.body_props(libreria)[:m] > 60 && F.body_props(libro)[:m] < 60, 'libreria oltre 60 kg, libro sotto')
ok(F.grab_level([libreria, mensola, libro], 60) == 1, 'G sceglie il primo livello sollevabile (la mensola, non il libro)')
ok(F.grab_level([libreria, libro], 60) == 1, 'libreria troppo pesante → il libro colpito')
ok(F.grab_level([libro], 60) == 0, 'oggetto leggero al primo livello: preso com\'è')
ok(F.grab_level([libreria, box.(1.5, 0.35, 1.5)], 60).nil?, 'nessun livello sollevabile → nil (messaggio "troppo pesante")')

# ── Strappo iniziale con la vista lenta ──────────────────────────────
# Prima: con passi da 0,1 s (vista pesante da ridisegnare) lo strappo di
# 0,4 s finiva in 4 fotogrammi e sembrava un salto.
libro = box.(0.03, 0.2, 0.25)
{ :@grabbed_entity => libro, :@grab_t => 0.0, :@grab_from => libro.center, :@eye_x => 100.0, :@eye_y => 0.0,
  :@eye_z => 60.0, :@yaw => 0.0, :@pitch => 0.0, :@held_block => 0.0 }.each { |k, v| F.instance_variable_set(k, v) }
frames = 0
while F.instance_variable_get(:@grab_t) < F.cf('grab_pull_time') + F.cf('grab_out_time')
  F.update_grabbed_position(0.1)
  frames += 1
end
ok(frames >= F::GRAB_MIN_FRAMES, "con passi da 0,1 s lo strappo dura #{frames} fotogrammi (almeno #{F::GRAB_MIN_FRAMES})")
F.instance_variable_set(:@grabbed_entity, nil)

# ── Allontanamento dopo lo strappo: niente attraversamenti ───────────
# Prima: tornando alla distanza di presa l'oggetto attraversava la libreria
# davanti al player e finiva dietro. Ora, se è libero, rispetta le collisioni.
sweeps = []
overlap = false
orig = { held_overlapping?: F.method(:held_overlapping?), held_sweep: F.method(:held_sweep) }
F.define_singleton_method(:held_overlapping?) { |_e| overlap }
F.define_singleton_method(:held_sweep) { |_e, dx, dy, dz, _dt = nil| sweeps << [dx, dy, dz]; [0.0, 0.0, 0.0] }   # muro subito davanti
run_grab = lambda do
  sweeps.clear
  libro = box.(0.03, 0.2, 0.25)
  { :@grabbed_entity => libro, :@grab_t => 0.0, :@grab_from => libro.center, :@grab_out_free => nil }.each { |k, v| F.instance_variable_set(k, v) }
  20.times { F.update_grabbed_position(0.05) }
  F.instance_variable_set(:@grabbed_entity, nil)
end
run_grab.call
ok(sweeps.any?, 'oggetto libero: l\'allontanamento passa dal controllo delle collisioni')
overlap = true
run_grab.call
ok(sweeps.empty? || F.instance_variable_get(:@grab_out_free) == false,
   'oggetto ancora dentro qualcosa: l\'allontanamento resta fantasma, per non incastrarlo')
orig.each { |n, m| F.define_singleton_method(n, m) }   # rimette i metodi veri

# ── Rotella: distanza dell'oggetto in mano, altrimenti zoom ─────────
F.instance_variable_set(:@active, true)
{ :@zoom_target => 70.0, :@base_fov => 70.0, :@grabbed_entity => box.(0.03, 0.2, 0.25), :@hold_dist => 1.6 }
  .each { |k, v| F.instance_variable_set(k, v) }
F.on_wheel(120); F.on_wheel(120)
ok((F.instance_variable_get(:@hold_dist) - 1.9).abs < 1e-9 && F.instance_variable_get(:@zoom_target) == 70.0,
   'oggetto in mano: la rotella in avanti lo allontana (1,6 → 1,9 m), lo zoom non cambia')
30.times { F.on_wheel(-120) }
ok(F.instance_variable_get(:@hold_dist) == F::HOLD_MIN, "non si avvicina oltre #{F::HOLD_MIN} m")
F.reset_zoom
ok(F.instance_variable_get(:@hold_dist) == F.cf('grab_distance'), 'tasto centrale: torna alla distanza del pannello')
F.instance_variable_set(:@grabbed_entity, nil)
F.on_wheel(120)
ok(F.instance_variable_get(:@zoom_target) < 70.0, 'senza oggetto in mano la rotella torna a fare lo zoom')
F.instance_variable_set(:@active, false)

# ── Caduta con la vista lenta ────────────────────────────────────────
# Prima: con passi da 1/15 s o più i piedi superavano il pavimento di più
# della tolleranza d'atterraggio, il pavimento veniva scartato come gradino
# troppo alto e lo si attraversava (a 15 fps 15 cadute su 40, già da 1,75 m;
# a 10 fps 24 su 40, già da 1,25 m). Qui il vero tick, su un pavimento a z = 0.
class Sketchup::Face; def normal; Geom::Vector3d.new(0, 0, 1); end; end
floor_face = Sketchup::Face.new
land_view  = Object.new
def land_view.invalidate; end
land_model = Object.new
land_model.define_singleton_method(:active_view) { land_view }
Sketchup.define_singleton_method(:active_model) { land_model }
stubs = { main_focused?: -> { false }, pressed?: ->(_a) { false }, key?: ->(_v) { false },
          can_uncrouch?: -> { true }, step_physics: ->(_dt) {}, apply_camera: ->(*_a) {},
          detect_ceiling: -> { nil },
          ray: ->(ox, oy, oz, _dx, _dy, dz) { dz < 0 && oz > 0 ? [Geom::Point3d.new(ox, oy, 0.0), [floor_face]] : nil } }
orig = stubs.keys.to_h { |n| [n, F.method(n)] }
stubs.each { |n, l| F.define_singleton_method(n, &l) }
F.load_cfg
eye_in = ->() { F.cf('eye_height').to_f * F::M_TO_IN }
drop = lambda do |h_m, dt|
  { :@active => true, :@cur_h_m => F.cf('eye_height').to_f, :@eye_z => h_m * F::M_TO_IN + eye_in.(),
    :@on_ground => false, :@jumps_used => 1, :@safe_trail => [], :@zoom_fov => 70.0, :@zoom_target => 70.0,
    :@base_fov => 70.0 }.each { |k, v| F.instance_variable_set(k, v) }
  %i[@vh_x @vh_y @vv @coyote @jump_buf @fall_time @fall_in @step_smooth @land_off @land_vel @roll @bob_phase]
    .each { |v| F.instance_variable_set(v, 0.0) }
  res = :timeout
  200.times do
    F.instance_variable_set(:@last_tick, Time.now.to_f - dt)
    F.tick
    feet = F.instance_variable_get(:@eye_z) - F.instance_variable_get(:@cur_h_m) * F::M_TO_IN
    if F.instance_variable_get(:@on_ground) && feet.abs < 1.0 then res = :ok; break end
    if feet < -eye_in.() then res = :through; break end       # occhi sotto il pavimento
  end
  res
end
[[1.0 / 60, 60], [1.0 / 15, 15], [0.1, 10]].each do |dt, fps|
  bad = (1..40).map { |i| 0.5 + i * 0.25 }.reject { |h| drop.(h, dt) == :ok }
  ok(bad.empty?, "a #{fps} fps nessuna caduta (0,75–10,5 m) attraversa il pavimento#{bad.empty? ? '' : " (#{bad.size} sì: #{bad.first(4).join(', ')} m…)"}")
end
orig.each { |n, m| F.define_singleton_method(n, m) }
F.instance_variable_set(:@active, false)

# ── Head bob con un tetto ────────────────────────────────────────────
# Prima: l'ampiezza cresceva con la velocità fino a 2,2 volte; con la corsa
# a 2,4× la testa andava su e giù di ±7,7 cm (2026-10-17, "inverosimile").
F.instance_variable_set(:@on_ground, true)
F.instance_variable_set(:@bob_phase, 0.0)
cfg = F.instance_variable_get(:@cfg)
bob_cfg = cfg.slice('move_speed', 'head_bob_amp', 'head_bob_side')
cfg.merge!('move_speed' => 4.4, 'head_bob_amp' => 0.15, 'head_bob_side' => 0.12)   # anche coi valori vecchi del pannello
top_z = top_s = 0.0
[4.4, 10.6, 30.0].each do |v|
  600.times do
    z, s = F.head_bob(1.0 / 60, v)
    top_z = [top_z, z.abs].max; top_s = [top_s, s.abs].max
  end
end
ok(top_z <= F::BOB_Z_MAX * F::M_TO_IN + 1e-9 && top_z > 0.9 * F::BOB_Z_MAX * F::M_TO_IN,
   "head bob verticale fermo a #{F::BOB_Z_MAX} m anche correndo (#{(top_z * F::IN_TO_M).round(3)} m)")
ok(top_s <= F::BOB_SIDE_MAX * F::M_TO_IN + 1e-9, "head bob laterale fermo a #{F::BOB_SIDE_MAX} m")
cfg.merge!('head_bob_amp' => 0.02)
top_z = 0.0
600.times { top_z = [top_z, F.head_bob(1.0 / 60, 4.4)[0].abs].max }
ok((top_z * F::IN_TO_M - 0.02).abs < 0.001, 'sotto il tetto, camminando, l\'ampiezza resta quella del pannello')
cfg.merge!(bob_cfg)

# ── Voce d'annullamento della fisica ────────────────────────────────
# Prima: dopo la prima mossa la fisica si accodava sempre all'operazione in
# cima alla cronologia. Un Ctrl+Z in modalità FPS, o un disegno durante
# l'assestamento dopo l'uscita, la faceva finire dentro l'operazione
# dell'utente: un Ctrl+Z successivo annullava le due cose insieme.
ops = []
obs = F::OpObserver.new
op_model = Object.new
def op_model.raytest(*); nil; end
def op_model.entities; []; end
op_model.define_singleton_method(:start_operation) { |name, *a| ops << (a[2] ? :accoda : name) }
op_model.define_singleton_method(:commit_operation) { obs.onTransactionCommit(self) }   # SketchUp avvisa anche per le nostre
Sketchup.define_singleton_method(:active_model) { op_model }
phys.clear
phys[StubGroup.new([0, 0, 100], [10, 10, 110])] = st.(0.0)
F.instance_variable_set(:@phys_op_named, false)
2.times { F.step_physics(1.0 / 60) }
ok(ops == ['DagaWASD', :accoda], "la fisica apre la sua voce e poi vi si accoda (#{ops.inspect})")
obs.onTransactionUndo(op_model)                 # Ctrl+Z in modalità FPS
F.step_physics(1.0 / 60)
ok(ops.last == 'DagaWASD', "dopo un annulla la fisica apre una voce nuova invece di accodarsi a quella dell'utente")
F.step_physics(1.0 / 60)
obs.onTransactionCommit(op_model)               # operazione dell'utente durante l'assestamento
F.step_physics(1.0 / 60)
ok(ops.last(3) == ['DagaWASD', :accoda, 'DagaWASD'],
   "dopo un'operazione altrui la fisica apre una voce nuova (#{ops.last(3).inspect})")

# ── Assestamento mentre il ponte costruisce dal vivo ─────────────────
# Prima: la fisica dopo l'uscita apriva operazioni in mezzo a quella, ancora
# aperta, di una costruzione dal vivo del ponte, spezzandola.
steps = 0
orig_sp = F.method(:step_physics)
F.define_singleton_method(:step_physics) { |_dt| steps += 1 }
timer_blk = nil
UI.define_singleton_method(:start_timer) { |*_a, &b| timer_blk = b; 7 }
F.start_settle
F.instance_variable_set(:@bridge_job, { fiber: nil })
3.times { timer_blk.call }
ok(steps.zero?, "mentre il ponte costruisce l'assestamento dopo l'uscita aspetta")
F.instance_variable_set(:@bridge_job, nil)
timer_blk.call
ok(steps == 1, "finito il lavoro del ponte l'assestamento riprende")
F.finish_settle
F.define_singleton_method(:step_physics, orig_sp)
UI.define_singleton_method(:start_timer) { |*_a| 1 }

# ── Lancio con il minimo oltre il massimo ────────────────────────────
# Prima: con throw_force_min > throw_force_max caricare di più lanciava più piano.
cfg = F.instance_variable_get(:@cfg)
cfg.merge!('throw_force_min' => 10.0, 'throw_force_max' => 4.0, 'throw_charge_time' => 1.0)
imp = []
orig_ai = F.method(:apply_impulse)
F.define_singleton_method(:apply_impulse) { |_e, jx, jy, jz, *_r| imp << Math.sqrt(jx**2 + jy**2 + jz**2) }
throw_after = lambda do |held_s|
  { :@grabbed_entity => box.(0.1, 0.1, 0.1), :@grab_state => :charging,
    :@charge_start => Time.now.to_f - held_s }.each { |k, v| F.instance_variable_set(k, v) }
  F.do_throw
  imp.last
end
weak = throw_after.(0.25); strong = throw_after.(2.0)
ok(weak && strong && strong >= weak - 1e-9, "minimo oltre il massimo: a carica piena non si lancia più piano (#{weak&.round(2)} → #{strong&.round(2)})")
F.define_singleton_method(:apply_impulse, orig_ai)

# ── Coppie minimo/massimo in settings.json ───────────────────────────
File.write(settings, JSON.generate('kick_force_min' => 12.0, 'kick_force' => 8.0,
                                   'crouch_height' => 1.9, 'eye_height' => 1.5))
cfg = F.load_cfg
ok(cfg['kick_force_min'] == 8.0 && cfg['crouch_height'] == 1.5 && cfg['kick_force'] == 8.0,
   'settings.json con minimo oltre il massimo: il minimo scende al massimo')
ok(cfg['throw_force_min'] <= cfg['throw_force_max'], 'le coppie già in ordine restano com\'erano')

# ── Fuori da Windows ─────────────────────────────────────────────────
# Prima: su Mac main.rb caricava lib/input.rb (user32) e si rompeva all'avvio.
# Ora non carica nulla e avvisa una volta sola. In un processo a parte, perché
# qui l'estensione è già caricata.
mac = <<~'RUBY'
  $LOAD_PATH.unshift(ARGV[0])
  require 'sketchup'
  $piattaforma = :platform_osx
  $avvisi = 0
  module UI; def self.start_timer(*, &b); b&.call; 1; end; def self.messagebox(*); $avvisi += 1; end; end
  2.times { load ARGV[1] }                       # due avvii: l'avviso compare una volta
  print [defined?(DagaWASD::FPSWalk::PLUGIN_DIR).nil?, $avvisi].inspect
RUBY
out = IO.popen([RbConfig.ruby, '-E', 'UTF-8', '-e', mac, File.join(__dir__, 'support'), File.expand_path('../main.rb', __dir__)], &:read)
ok(out == '[true, 1]', "fuori da Windows non carica il codice e avvisa una volta sola (#{out})")

FileUtils.remove_entry(tmp)
puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
