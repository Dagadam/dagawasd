# Nuvole (lib/clouds.rb) con SketchUp finto: copertura, campo, ordine, sole coperto, colori, atlante, disegno.
#   Esecuzione:  ruby -E UTF-8 tests/test_clouds.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
M = F::M_TO_IN
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end

tmp = Dir.mktmpdir('dagawasd_clouds')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.load_cfg
cfg = F.instance_variable_get(:@cfg)

module Sketchup
  class Color
    attr_reader :rgba
    def initialize(*v); @rgba = v.size == 3 ? v + [255] : v; end
    def to_a; @rgba; end
  end
  class ImageRep
    attr_reader :args
    def set_data(*a); @args = a; end
  end
end
class CCam
  attr_accessor :eye
  def initialize; @eye = Geom::Point3d.new(0, 0, 1.7 * M); end
  def perspective?; true; end
  def direction; Geom::Vector3d.new(0, 1, 0); end
  def fov; 60.0; end
end
class CView
  attr_reader :calls, :cam, :loaded, :released
  attr_accessor :drawing_color
  def initialize; @calls = []; @cam = CCam.new; @loaded = []; @released = []; end
  def camera; @cam; end
  def vpwidth; 1000; end
  def vpheight; 600; end
  def invalidate; end
  def load_texture(rep); @loaded << rep; 40 + @loaded.size; end
  def release_texture(id); @released << id; end
  def draw(mode, pts, **opt); @calls << [mode, pts, opt]; end
end
class CModel
  attr_reader :view, :shadow_info
  def initialize; @view = CView.new; @shadow_info = { 'NorthAngle' => 0.0 }; end
  def active_view; @view; end
  def bounds; b = Geom::BoundingBox.new; b.add(Geom::Point3d.new(-50 * M, -50 * M, 0)); b.add(Geom::Point3d.new(50 * M, 50 * M, 20 * M)); b; end
end
cm = CModel.new
Sketchup.define_singleton_method(:active_model) { cm }

# ── Copertura ───────────────────────────────────────────────────
cfg.merge!('cloud_enabled' => false, 'precip_kind' => 'none')
ok(F.cloud_cover == 0.0, 'nuvole spente: copertura 0')
cfg.merge!('cloud_enabled' => true, 'cloud_cover' => 45)
ok((F.cloud_cover - 0.45).abs < 1e-9, 'copertura 45 %')
cfg.merge!('precip_kind' => 'rain', 'precip_intensity' => 50)
ok((F.cloud_cover - 0.8).abs < 1e-9, 'con pioggia al 50 % il cielo si chiude (80 %)')
ok(F.cloud_overcast > 0.3, 'cielo molto coperto: ingrigisce')
cfg['precip_kind'] = 'none'

# ── Campo e posizioni ───────────────────────────────────────────
cfg.merge!('cloud_size' => 900, 'cloud_height' => 1500, 'cloud_wind' => 10, 'cloud_wind_dir' => 270, 'cloud_shade' => true, 'cloud_fps' => 15)
F.cloud_seed
cl = F.instance_variable_get(:@clouds)
atteso = (0.45 * F::CLOUD_TILE**2 / ((900 * M)**2 * 0.55)).round
ok(cl.size == atteso, "campo: #{cl.size} nuvole per il 45 % (attese #{atteso})")
F.cloud_place(0.0, 0.0, 1.7 * M)
list = F.instance_variable_get(:@cloud_list)
ok(list.all? { |v, *| Math.asin(v[2]) >= F::CLOUD_MIN_ELEV - 1e-9 }, 'nessuna nuvola sotto i 2,5° sull\'orizzonte')
ok(list.each_cons(2).all? { |a, b| a[1] >= b[1] }, 'dalla più lontana alla più vicina')
ok(list.all? { |_, d, *| d <= Math.sqrt(2 * (F::CLOUD_TILE / 2)**2 + (1500 * M)**2) + 1 }, 'tutte nel quadrato attorno alla camera')
lontana = F.cloud_place(5_000_000.0 * M, 0.0, 1.7 * M).size
ok((lontana - list.size).abs < list.size * 0.4, 'camera spostata di 5000 km: il campo la segue (nessun buco)')
alta = list.select { |v, *| v[2] > 0.6 }
ok(alta.all? { |*, lev| lev == 0 } && list.any? { |*, lev| lev == 3 }, 'in alto nitide, verso l\'orizzonte sfumate nella foschia')

# ── Vento ───────────────────────────────────────────────────────
wx, wy = F.cloud_wind_v(0.0)
ok((wx - 10 * M).abs < 1e-6 && wy.abs < 1e-6, 'vento da ovest: verso est')

# ── Sole coperto ────────────────────────────────────────────────
list = F.cloud_place(0.0, 0.0, 1.7 * M)
sun = list.last[0]                          # il sole proprio dietro la nuvola più vicina
ok(F.cloud_occlusion(sun) > 0.5, "sole dietro una nuvola: coperto (#{F.cloud_occlusion(sun).round(2)})")
ok(F.cloud_occlusion([0.0, 0.0, -1.0]) == 0.0, 'sole sotto l\'orizzonte: nessuna nuvola davanti')
F.instance_variable_set(:@cloud_occ, 0.7)
ok(F.cloud_sun_shade == 0.7, 'la luce si vela quanto la nuvola copre il sole')
cfg['cloud_shade'] = false
ok(F.cloud_sun_shade == 0.0, '"Coprono il sole" spento: luce piena')
cfg['cloud_shade'] = true

# ── Colori e atlante ────────────────────────────────────────────
F.instance_variable_set(:@sky, { sun_alt: 40.0 })
lit, dark, = F.cloud_colors
ok(lit == [255, 255, 255] && dark[2] > dark[0], 'giorno: bianche, ombra azzurrina')
F.instance_variable_set(:@sky, { sun_alt: -1.0 })
ok(F.cloud_colors[0][0] > F.cloud_colors[0][2] + 60, 'tramonto: rosate')
F.instance_variable_set(:@sky, { sun_alt: -30.0 })
ok(F.cloud_colors[0].sum < 150, 'notte: scure')
F.instance_variable_set(:@sky, { sun_alt: 40.0 })
cfg.merge!('precip_kind' => 'rain', 'precip_intensity' => 100)
ok(F.cloud_colors[0].max < 190 && (F.cloud_colors[0].max - F.cloud_colors[0].min) < 10, 'con la pioggia: grigie')
cfg['precip_kind'] = 'none'
alpha, light = F.cloud_shapes[0]
n = F::CLOUD_TEX
bordo = (0...n).flat_map { |i| [alpha[i], alpha[(n - 1) * n + i], alpha[i * n], alpha[i * n + n - 1]] }
ok(bordo.all?(&:zero?) && alpha.count { |a| a > 0.5 } > n * n / 10, 'forme: margine trasparente, corpo pieno')
ok(light[(n / 8) * n + n / 2] > light[(n * 5 / 8) * n + n / 2], 'più chiare in alto che in basso')
px = F.cloud_pixels([250, 10, 20], [100, 5, 10], [200, 200, 200])
ok(px.bytesize == n * 4 * n * 4 * 4, 'atlante 4 × 4 nuvole, 4 byte per pixel')
b = px.bytes
i = b.each_slice(4).find_index { |p| p[3] > 200 } * 4
ok(b[i + 2] > 200 && b[i] < 40, 'byte in ordine BGRA (rosso nel terzo byte)')
ok(b[0, 4][0..2].sum > 0, 'anche i pixel trasparenti hanno il colore della nuvola (niente alone scuro)')

# ── Accensione, fotogrammi, disegno ─────────────────────────────
F.instance_variable_set(:@sky, nil)
F.cloud_sync
ok(F.instance_variable_get(:@cloud_rate) == 15 && F.instance_variable_get(:@cloud_pix), 'accese: timer e atlante pronti')
off0 = F.instance_variable_get(:@cloud_off).dup
F.instance_variable_set(:@cloud_tick, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.5)
F.cloud_frame
off1 = F.instance_variable_get(:@cloud_off)
ok(((off1[0] - off0[0]) / M - 5.0).abs < 0.2, "il vento le sposta: #{((off1[0] - off0[0]) / M).round(1)} m in 0,5 s")
v = cm.view
F.cloud_draw(v)
q = v.calls.last
nl = F.instance_variable_get(:@cloud_list).size
visti = q ? q[1].size / 4 : 0
ok(v.calls.size == 1 && visti > 20 && visti < nl && q[2][:uvs].size == q[1].size && q[2][:texture] == 41,
   "una sola chiamata con texture, solo le nuvole inquadrate (#{visti} di #{nl})")
ok(q[2][:uvs].all? { |u, w, _| u.between?(0, 1) && w.between?(0, 1) }, 'coordinate texture dentro l\'atlante')
F.cloud_draw(v)
ok(v.loaded.size == 1, 'l\'atlante si carica una volta sola finché la luce non cambia')
F.instance_variable_set(:@sky, { sun_alt: -1.0 })
F.cloud_frame
F.cloud_draw(v)
ok(v.loaded.size == 2 && v.released == [41], 'cambia la luce: nuovo atlante, il vecchio rilasciato')
cfg['cloud_enabled'] = false
F.cloud_sync
v.calls.clear
F.cloud_draw(v)
ok(F.instance_variable_get(:@cloud_timer).nil? && v.calls.empty? && v.released.size == 2, 'spente: niente timer, niente disegno, texture rilasciata')

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
