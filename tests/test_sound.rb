# Passi secondo il pavimento e gamepad XInput (SketchUp, winmm e XInput finti).
#   Esecuzione:  ruby -E UTF-8 tests/test_sound.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end

tmp = Dir.mktmpdir('dagawasd_suoni')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.instance_variable_set(:@step_cache_dir, tmp)        # i suoni dei test non vanno nella cartella vera
F.instance_variable_set(:@settings_file, File.join(tmp, 'settings.json'))
F.load_cfg
cfg = F.instance_variable_get(:@cfg)
snd = F.instance_variable_get(:@snd)
xi  = F.instance_variable_get(:@xi)

# ── Nomi dei materiali ────────────────────────────────────────────────
{ 'Wood_Floor_Parquet' => 'legno', 'Vegetation_Grass_Light' => 'erba', 'Groundcover_Gravel' => 'ghiaia',
  'Stone_Masonry' => 'duro', 'Metal_Steel_Textured' => 'metallo', 'Water_Pool_Light' => 'acqua',
  'Carpet_Loop' => 'moquette', 'PratoInglese' => 'erba', 'Legno di rovere' => 'legno', 'Piastrelle bagno' => 'duro',
  'Neve fresca' => 'neve', 'Sabbia' => 'terra', '[Ciottoli]' => 'ghiaia',
  'Terrazza' => nil, 'Seat cushion' => nil, 'Office' => nil, 'Material12' => nil }.each do |name, want|
  got = F.step_kind_of_name(name)
  ok(got == want, "«#{name}» → #{got.inspect}#{got == want ? '' : " (atteso #{want.inspect})"}")
end

# ── Dal raggio alla superficie ────────────────────────────────────────
Mat   = Struct.new(:display_name)
Layer = Struct.new(:name)
class FaceF < Sketchup::Face
  attr_accessor :material, :back_material, :layer
end
Inst = Struct.new(:material, :name, :definition, :layer)
Defn = Struct.new(:name)
untagged = Layer.new('Untagged')
face = lambda do |front = nil, back = nil|
  f = FaceF.new; f.material = front && Mat.new(front); f.back_material = back && Mat.new(back); f.layer = untagged; f
end
inst = ->(mat: nil, name: '', defn: 'Gruppo#1', layer: untagged) { Inst.new(mat && Mat.new(mat), name, Defn.new(defn), layer) }
ok(F.step_surface([face.('Marmo bianco')]) == 'duro', 'materiale della faccia: marmo → duro')
ok(F.step_surface([face.(nil, 'Assi di legno')]) == 'legno', 'faccia senza materiale davanti: si guarda il retro')
ok(F.step_surface([inst.(name: 'Prato'), face.()]) == 'erba', 'faccia senza materiale: decide il nome del gruppo')
ok(F.step_surface([inst.(mat: 'Ghiaia'), inst.(name: 'Viale'), face.()]) == 'ghiaia', 'gruppo esterno colorato a ghiaia')
ok(F.step_surface([inst.(name: 'Prato'), face.('Metal_Grate')]) == 'metallo', 'la faccia vince sul gruppo che la contiene')
ok(F.step_surface([inst.(layer: Layer.new('Pavimento in legno')), face.()]) == 'legno', 'ultimo tentativo: il tag')
ok(F.step_surface([inst.(mat: 'Holz'), face.()]) == 'legno', 'parole dei materiali fisici, anche tradotte (Holz)')
ok(F.step_surface([face.('Material12')]) == 'duro' && F.step_surface(nil) == 'duro', 'sconosciuto o niente: duro')

# ── All'aperto: neve al suolo e pioggia ───────────────────────────────
roof = nil
orig_pray = F.method(:pray)
F.define_singleton_method(:pray) { |*_| roof }
F.instance_variable_set(:@snow_level, 0.6)
ok(F.step_weather('legno') == 'neve', 'neve al suolo, all\'aperto: tutto scricchiola di neve')
roof = [Geom::Point3d.new(0, 0, 100), []]
ok(F.step_weather('legno') == 'legno', '…ma sotto un tetto resta il pavimento')
roof = nil
F.instance_variable_set(:@snow_level, 0.0)
cfg.merge!('precip_kind' => 'rain', 'precip_intensity' => 60)
ok(F.step_weather('duro') == 'bagnato' && F.step_weather('erba') == 'erba', 'pioggia: il duro si bagna, l\'erba no')
ok(F.step_weather('acqua') == 'acqua', 'nell\'acqua resta acqua')
cfg['precip_kind'] = 'none'
ok(F.step_weather('duro') == 'duro', 'senza pioggia niente bagnato')
F.define_singleton_method(:pray, orig_pray)

# ── Suoni generati ────────────────────────────────────────────────────
kinds = F::STEP_GAIN.keys
peak = ->(w) { w.byteslice(44, w.bytesize - 44).unpack('s<*').map(&:abs).max }
wavs = kinds.map { |k| F.step_wav(k, 0, 1.0) }
ok(wavs.all? { |w| w.start_with?('RIFF') && w.byteslice(8, 4) == 'WAVE' && w.byteslice(4, 4).unpack1('V') == w.bytesize - 8 },
   "WAV validi per tutte le #{kinds.size} superfici")
ok(wavs.each_with_index.all? { |w, i| (peak.(w) - 32_000 * F::STEP_GAIN[kinds[i]]).abs < 2 }, 'ognuno al suo volume pieno')
w1 = F.step_wav('legno', 1, 1.0); w5 = F.step_wav('legno', 1, 0.5)
ok((peak.(w5) - peak.(w1) / 2.0).abs < 2, 'metà volume = metà ampiezza')
ok(F.step_wav('legno', 1, 1.0).equal?(w1) && w1.frozen?, 'generato una volta e tenuto (PlaySound lo legge mentre suona)')
ok(F.step_wav('legno', 0, 0.02).nil?, 'volume quasi zero: niente suono')
ok(F.step_wav('legno', 0, 1.0) != F.step_wav('legno', 2, 1.0), 'varianti diverse fra loro')
pcm = File.join(F.step_cache_dir, 'metallo_3.pcm')
F.step_wav('metallo', 3, 0.5)
salvata = File.exist?(pcm) && File.size(pcm) == F.step_base('metallo', 3).size * 2
F.instance_variable_set(:@step_base, {}); F.instance_variable_set(:@step_wavs, {})
File.binwrite(pcm, ([1000] * 3000).pack('s<*'))                 # riconoscibile: viene dal disco
ok(salvata && F.step_base('metallo', 3) == [1000] * 3000, 'forma d\'onda salvata su disco e riletta (calcolata una volta per computer)')
File.binwrite(pcm, 'rotto')
F.instance_variable_set(:@step_base, {})
ok(F.step_base('metallo', 3).size > 3000 && File.size(pcm) > 2000, 'file rovinato: ricalcolata e riscritta')
timers = []
UI.define_singleton_method(:start_timer) { |*_a, &b| timers << b; timers.size }
UI.define_singleton_method(:stop_timer) { |id| timers[id - 1] = nil }
F.instance_variable_set(:@step_base, {})
F.instance_variable_set(:@active, false)
F.instance_variable_set(:@step_warm_timer, nil)     # quello di main.rb al caricamento
F.step_warm_start
200.times { timers[0]&.call }
tutte = F::STEP_GAIN.size * F::STEP_VARIANTS
ok(F.instance_variable_get(:@step_base).size == tutte && timers[0].nil?, "in sottofondo: pronte tutte le #{tutte} e il timer si ferma")
UI.define_singleton_method(:start_timer) { |*_a| 1 }
UI.define_singleton_method(:stop_timer) { |*_a| }

# ── Cadenza col vero tick, su un pavimento di legno a z = 0 ───────────
floor = face.('Parquet')
class Sketchup::Face; def normal; Geom::Vector3d.new(0, 0, 1); end; end
view = Object.new
def view.invalidate; end
model = Object.new
model.define_singleton_method(:active_view) { view }
Sketchup.define_singleton_method(:active_model) { model }
held = []
focused = false
stopped = 0; frozen = 0
stubs = { main_focused?: -> { focused }, key?: ->(_v) { false }, shift?: -> { false }, alt?: -> { false },
          async_down?: ->(_v) { false }, can_uncrouch?: -> { true }, step_physics: ->(_dt) {}, apply_camera: ->(*_a) {},
          detect_ceiling: -> { nil }, viewport_center: -> { [500, 400] }, cursor_pos: -> { [500, 400] },
          stop: -> { stopped += 1 }, toggle_mouse_freeze: -> { frozen += 1 },
          ray: ->(ox, oy, oz, _dx, _dy, dz) { dz < 0 && oz > 0 ? [Geom::Point3d.new(ox, oy, 0.0), [floor]] : nil } }
stubs.each { |n, l| F.define_singleton_method(n, &l) }
orig_pressed = F.method(:pressed?)
F.define_singleton_method(:pressed?) { |a| held.include?(a) || F.pad_pressed?(a) }
eye_in = F.cf('eye_height').to_f * F::M_TO_IN
reset = lambda do |h_m = 0.0|
  { :@active => true, :@cur_h_m => F.cf('eye_height').to_f, :@eye_x => 0.0, :@eye_y => 0.0,
    :@eye_z => h_m * F::M_TO_IN + eye_in, :@on_ground => h_m == 0.0, :@floor_z_in => 0.0, :@jumps_used => 0,
    :@safe_trail => [], :@zoom_fov => 70.0, :@zoom_target => 70.0, :@base_fov => 70.0, :@yaw => 0.0, :@pitch => 0.0,
    :@was_focused => true, :@mouse_freeze => false, :@pad => nil, :@pad_slot => nil, :@pad_scan_at => nil,
    :@pad_prev_btn => nil, :@floor_hit => nil, :@step_kind_cache => nil }.each { |k, v| F.instance_variable_set(k, v) }
  %i[@vh_x @vh_y @vv @coyote @jump_buf @fall_time @fall_in @step_smooth @land_off @land_vel @roll @bob_phase @step_phase]
    .each { |v| F.instance_variable_set(v, 0.0) }
end
run = lambda do |secs, dt = (1.0 / 60)|
  (secs / dt).round.times do
    F.instance_variable_set(:@last_tick, Time.now.to_f - dt)
    F.tick
  end
end

reset.()
snd.played.clear
run.(3.0)
ok(snd.played.empty?, 'fermi: nessun passo')
held = ['forward']
run.(3.0)
n = snd.played.size
rate = 2 * F.cf('head_bob_freq') * 1.1
ok((n - rate * 3).abs <= 2, "camminando 3 s: #{n} passi (attesi ~#{(rate * 3).round}, uno per oscillazione della testa)")
ok(F.instance_variable_get(:@step_last_kind) == 'legno', 'sul parquet suonano di legno')
ok(snd.played.each_cons(2).all? { |a, b| !a.equal?(b) }, 'mai due volte di fila la stessa variante')
cfg['head_bob_enabled'] = false
snd.played.clear
run.(3.0)
ok((snd.played.size - n).abs <= 1, "dondolio spento: stessa cadenza (#{snd.played.size})")
cfg['head_bob_enabled'] = true
held = %w[forward run]
snd.played.clear
run.(3.0)
corsa = snd.played.size
ok(corsa > n && peak.(snd.played.last) > peak.(F.step_wav('legno', 0, 0.7 * 0.7)) * 0.9,
   "correndo più passi (#{corsa}) e più forti")
held = %w[forward]
cfg['steps_enabled'] = false
snd.played.clear
run.(2.0)
ok(snd.played.empty?, 'passi spenti nel pannello: silenzio')
cfg['steps_enabled'] = true

# Atterraggio
held = []
reset.(2.0)
snd.played.clear
run.(1.5)
ok(snd.played.size == 1 && F.instance_variable_get(:@on_ground), 'caduta da 2 m: un tonfo all\'atterraggio')

# ── Gamepad ───────────────────────────────────────────────────────────
focused = true
reset.()
xi.pads.clear
c0 = xi.calls
run.(1.0)
ok(F.instance_variable_get(:@pad).nil? && xi.calls - c0 == 4, 'nessun gamepad: cercato una volta sola (4 posti) in 1 s')
F.instance_variable_set(:@pad_scan_at, nil)
xi.pads[2] = [0, 0, 0, 0, 0, 0, 0]
run.(0.1)
ok(F.instance_variable_get(:@pad_slot) == 2, 'collegato al posto 3: trovato')
c0 = xi.calls
run.(0.5)
ok(xi.calls - c0 == 30, 'poi si legge solo quello (una lettura per fotogramma)')
xi.pads[2] = [0, 0, 0, 3000, -2500, 0, 0]
run.(0.5)
ok(F.pad_move.nil? && F.instance_variable_get(:@vh_x).abs + F.instance_variable_get(:@vh_y).abs < 1e-9,
   'leve appena fuori centro (deriva): ignorate')
xi.pads[2] = [0, 0, 0, 0, 16_384, 0, 0]
run.(1.0)
v = Math.hypot(F.instance_variable_get(:@vh_x), F.instance_variable_get(:@vh_y))
atteso = (0.5 - 0.15) / 0.85 * F.cf('move_speed')
ok((v - atteso).abs < 0.05, "leva sinistra a metà: #{v.round(2)} m/s (attesi #{atteso.round(2)}, analogica)")
xi.pads[2] = [0, 0, 0, 0, 0, 32_767, 0]
y0 = F.instance_variable_get(:@yaw)
run.(0.5)
dy = ((y0 - F.instance_variable_get(:@yaw)) % F::PI2) / F::DEG
ok((dy - F.cf('gamepad_look_speed') * 0.5).abs < 3, "leva destra a fondo per 0,5 s: girati di #{dy.round} °")
xi.pads[2] = [F::XI_A, 0, 0, 0, 0, 0, 0]
ok(F.pressed?('jump') || (run.(1.0 / 60); F.pressed?('jump')), 'A = salto')
xi.pads[2] = [0, 0, 255, 0, 0, 0, 0]
run.(1.0 / 60)
ok(F.pad_pressed?('kick') && !F.pad_pressed?('run'), 'grilletto destro = calcio')
xi.pads[2] = [F::XI_LTHUMB, 0, 0, 0, 0, 0, 0]
run.(1.0 / 60)
ok(F.pad_pressed?('run'), 'leva sinistra premuta = corsa')
xi.pads[2] = [F::XI_BACK, 0, 0, 0, 0, 0, 0]
run.(0.3)
ok(frozen == 1, 'View: sblocca il mouse una volta sola anche tenendo premuto')
xi.pads[2] = [F::XI_UP, 0, 0, 0, 0, 0, 0]
z0 = F.instance_variable_get(:@zoom_target)
run.(1.0)
z1 = F.instance_variable_get(:@zoom_target)
ok(z1 < z0 / 1.15**5, "croce su tenuta 1 s: zoom continuo (#{z0.round} → #{z1.round} °)")
xi.pads[2] = [F::XI_START, 0, 0, 0, 0, 0, 0]
run.(1.0 / 60)
ok(stopped == 1, 'Menu: esce')
F.instance_variable_set(:@pad_prev_btn, nil)
F.instance_variable_set(:@active, true)
stopped = 0
run.(0.2)
ok(stopped == 0, 'rientrando con Menu ancora premuto non si riesce subito')
xi.pads[2] = [0, 0, 0, 0, 0, 0, 0]
reset.(4.0)
F.instance_variable_set(:@pad_slot, 2)
xi.rumble.clear
run.(1.5)
ok(xi.rumble.size == 2 && xi.rumble.first[0] > 0 && xi.rumble.last == [0, 0], 'atterraggio pesante: vibra e poi si ferma')
cfg['gamepad_enabled'] = false
run.(0.1)
ok(F.instance_variable_get(:@pad).nil?, 'gamepad spento nel pannello: ignorato')
cfg['gamepad_enabled'] = true
focused = false
run.(0.1)
ok(F.instance_variable_get(:@pad).nil? && !F.pad_pressed?('jump'), 'SketchUp non in primo piano: il gamepad non comanda')
xi.pads.clear
focused = true
run.(0.1)
ok(F.instance_variable_get(:@pad_slot).nil?, 'scollegato: dimenticato, si torna a cercarlo')

F.define_singleton_method(:pressed?, orig_pressed)
F.instance_variable_set(:@active, false)
puts
puts($fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI")
exit($fail.zero? ? 0 : 1)
