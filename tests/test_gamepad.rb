# Gamepad XInput col vero tick (SketchUp e XInput finti).
#   Esecuzione:  ruby -E UTF-8 tests/test_gamepad.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end

tmp = Dir.mktmpdir('dagawasd_gamepad')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.instance_variable_set(:@settings_file, File.join(tmp, 'settings.json'))
F.load_cfg
cfg = F.instance_variable_get(:@cfg)
xi  = F.instance_variable_get(:@xi)

# ── Un pavimento a z = 0 ──────────────────────────────────────────────
floor = Sketchup::Face.new
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
    :@pad_prev_btn => nil, :@floor_hit => nil }.each { |k, v| F.instance_variable_set(k, v) }
  %i[@vh_x @vh_y @vv @coyote @jump_buf @fall_time @fall_in @step_smooth @land_off @land_vel @roll @bob_phase]
    .each { |v| F.instance_variable_set(v, 0.0) }
end
run = lambda do |secs, dt = (1.0 / 60)|
  (secs / dt).round.times do
    F.instance_variable_set(:@last_tick, Time.now.to_f - dt)
    F.tick
  end
end


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
