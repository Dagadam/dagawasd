# Pioggia e neve (lib/precip.rb) con SketchUp finto: vento, caduta, tetti, spruzzi, nebbia, disegno.
#   Esecuzione:  ruby -E UTF-8 tests/test_precip.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
M = F::M_TO_IN
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end

tmp = Dir.mktmpdir('dagawasd_precip')
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
end
class PBox
  attr_reader :min, :max
  def initialize(a, b); @min = Geom::Point3d.new(*a); @max = Geom::Point3d.new(*b); end
  def empty?; false; end
  def diagonal; Math.sqrt((max.x - min.x)**2 + (max.y - min.y)**2 + (max.z - min.z)**2); end
end
class PCam
  attr_accessor :eye
  def initialize; @eye = Geom::Point3d.new(0, 0, 1.7 * M); end
  def xaxis; Geom::Vector3d.new(1, 0, 0); end
  def yaxis; Geom::Vector3d.new(0, 0, 1); end
end
class PView
  attr_reader :calls, :cam
  attr_accessor :drawing_color, :line_width
  def initialize; @calls = []; @cam = PCam.new; end
  def camera; @cam; end
  def invalidate; end
  def draw(mode, pts); @calls << [mode, pts.size, @drawing_color]; end
end
# Un tetto a 3 m sopra il quadrato x, y in 4–8 m; il resto è suolo (nessun colpo)
class PModel
  attr_reader :rendering_options, :shadow_info, :observers, :view, :rays
  def initialize
    @rendering_options = { 'DisplayFog' => false, 'FogStartDist' => -1.0, 'FogEndDist' => -1.0, 'FogUseBkColor' => false }
    @shadow_info = { 'NorthAngle' => 0.0 }
    @observers = []; @view = PView.new; @rays = 0
  end
  def add_observer(o); @observers << o; end
  def remove_observer(o); @observers.delete(o); end
  def active_view; @view; end
  def bounds; PBox.new([-50 * M, -50 * M, 0], [50 * M, 50 * M, 3 * M]); end
  def raytest(ray, _wysiwyg = true)
    @rays += 1
    p = ray[0]
    inside = p.x.between?(4 * M, 8 * M) && p.y.between?(4 * M, 8 * M)
    inside ? [Geom::Point3d.new(p.x, p.y, 3 * M), []] : nil
  end
end
pm = PModel.new
Sketchup.define_singleton_method(:active_model) { pm }

# ── Vento ───────────────────────────────────────────────────────
cfg.merge!('precip_wind' => 2.0, 'precip_wind_dir' => 270)
wx, wy = F.precip_wind_v(0.0)
ok((wx - 2 * M).abs < 1e-6 && wy.abs < 1e-6, 'vento da ovest: spinge verso est (+X)')
wx, wy = F.precip_wind_v(90.0)
ok(wx.abs < 1e-6 && (wy + 2 * M).abs < 1e-6, 'nord del modello ruotato di 90°: lo stesso vento va verso −Y')
cfg['precip_wind_dir'] = 0
wx, wy = F.precip_wind_v(0.0)
ok(wx.abs < 1e-6 && wy < 0, 'vento da nord: va verso sud')

# ── Accensione ──────────────────────────────────────────────────
cfg.merge!('precip_kind' => 'none')
F.precip_sync
ok(F.instance_variable_get(:@precip_model).nil? && pm.rendering_options['DisplayFog'] == false, 'spenta: modello non toccato')
cfg.merge!('precip_kind' => 'rain', 'precip_intensity' => 50, 'precip_max' => 2000, 'precip_radius' => 20.0,
           'precip_wind' => 0.0, 'precip_fog' => true, 'precip_roofs' => true, 'precip_fps' => 30)
F.precip_sync
list = F.instance_variable_get(:@precip)
ok(list.size == 1000 && list.none? { |p| p[3] }, 'pioggia al 50 % di 2000: 1000 gocce')
ro = pm.rendering_options
ok(ro['DisplayFog'] == true && ro['FogUseBkColor'] == true && ro['FogEndDist'] > ro['FogStartDist'], 'nebbia accesa, del colore dello sfondo')
far_rain = ro['FogEndDist']
ok(pm.observers.size == 1 && F.instance_variable_get(:@precip_rate) == 30, 'osservatore e timer')
eye = pm.view.camera.eye
r = 20 * M
ok(list.all? { |p| (p[0] - eye.x).abs <= r && (p[1] - eye.y).abs <= r && p[2] <= eye.z + F::PRECIP_ABOVE + 1 },
   'tutte dentro la scatola attorno alla camera')

# ── Caduta, rientro, suolo ──────────────────────────────────────
F.instance_variable_set(:@precip_rnd, Random.new(1))
p = [0.0, 0.0, 5 * M, false, 0.0, 0.5, -9.0 * M]
F.instance_variable_set(:@precip, [p])
F.instance_variable_set(:@precip_splash, [])
F.instance_variable_set(:@precip_wind, [0.0, 0.0])
F.precip_step(0.1, eye.x, eye.y, eye.z, 100.0)
ok((p[2] - (5 - 0.9) * M).abs < 1e-6, "una goccia cade a 9 m/s (#{(p[2] / M).round(2)} m)")
F.precip_step(0.1, eye.x + 25 * M, eye.y, eye.z, 100.1)       # la camera si è spostata di 25 m
ok((p[0] - (eye.x + 25 * M)).abs <= r, 'camera spostata: la goccia rientra dal lato opposto, attorno alla camera')
p[0] = 0.0; p[1] = 0.0; p[2] = 0.05 * M
F.precip_step(0.1, eye.x, eye.y, eye.z, 100.2)
spl = F.instance_variable_get(:@precip_splash)
ok(spl.size == 1 && spl[0][2] == 0.0 && p[2] > eye.z, 'tocca terra: spruzzo al suolo e riparte dall\'alto')
F.precip_step(0.05, eye.x, eye.y, eye.z, 100.2 + F::PRECIP_SPLASH + 0.01)
ok(F.instance_variable_get(:@precip_splash).empty?, 'lo spruzzo dura poco')

# ── Tetti ───────────────────────────────────────────────────────
F.precip_measure(pm, eye)
tops = F.instance_variable_get(:@precip_tops)
ok(pm.rays > 50 && tops.size == pm.rays, "mappa dei tetti: #{pm.rays} celle misurate in un fotogramma")
ok(F.precip_top(6 * M, 6 * M) == 3 * M && F.precip_top(0.5 * M, 0.5 * M) == 0.0, 'tetto a 3 m sopra il portico, suolo altrove')
p[0] = 6 * M; p[1] = 6 * M; p[2] = 3.05 * M
F.precip_step(0.1, eye.x, eye.y, eye.z, 200.0)
spl = F.instance_variable_get(:@precip_splash)
ok(spl.last && (spl.last[2] - 3 * M).abs < 1e-6, 'sul tetto: spruzzo a 3 m, non passa sotto')
F.instance_variable_set(:@precip_rnd, Random.new(2))
q = F.precip_spawn([0.0, 0.0, 0.0, false, 0, 0, -9.0 * M], 6 * M, 6 * M, 1.7 * M, true)
ok(q[2] >= F.precip_top(q[0], q[1]) - 1e-6, 'una goccia nuova non nasce sotto un tetto')
F.instance_variable_set(:@in_phys_op, true)
F.precip_model_changed
ok(!tops.empty?, 'le mosse della fisica non azzerano la mappa dei tetti')
F.instance_variable_set(:@in_phys_op, false)
F.precip_model_changed
ok(tops.empty?, 'una modifica dell\'utente la azzera')

# ── Neve: fiocchi lenti, niente spruzzi, nebbia più fitta ───────
cfg['precip_kind'] = 'snow'
F.precip_sync
list = F.instance_variable_get(:@precip)
ok(list.size == 1000 && list.all? { |x| x[3] }, 'neve: 1000 fiocchi')
ok(ro['FogEndDist'] < far_rain, "nebbia più fitta con la neve (#{(ro['FogEndDist'] / M).round} m contro #{(far_rain / M).round} m)")
f = [0.0, 0.0, 0.05 * M, true, 0.0, 0.5, -0.95 * M]
F.instance_variable_set(:@precip, [f]); F.instance_variable_set(:@precip_splash, [])
z0 = f[2]
F.precip_step(0.1, eye.x, eye.y, eye.z, 300.0)
ok(F.instance_variable_get(:@precip_splash).empty?, 'un fiocco a terra non schizza')
f[2] = 5 * M
F.precip_step(0.1, eye.x, eye.y, eye.z, 300.1)
ok(((5 * M - f[2]) / M - 0.095).abs < 1e-6, 'un fiocco cade lento (0,95 m/s)')
cfg['precip_kind'] = 'mix'
F.precip_sync
list = F.instance_variable_get(:@precip)
ok(list.count { |x| x[3] } == 500, 'nevischio: metà gocce e metà fiocchi')

# ── Disegno ─────────────────────────────────────────────────────
pm.view.calls.clear
F.precip_draw(pm.view)
c = pm.view.calls
ok(c.any? { |m, n, _| m == GL_LINES && n == 1000 } && c.any? { |m, n, _| m == GL_QUADS && n == 2000 },
   'disegno: un segmento per goccia, un quadratino per fiocco')

# ── Ingombro per il piano di taglio vicino ──────────────────────
# (segnalato sopra il mare di Stromboli: senza geometria vicina SketchUp
# tagliava via tutti i fiocchi entro 20 m)
ext = F.precip_extents
ok(!ext.empty? && ext.min.x <= eye.x - 19 * M && ext.max.z >= eye.z + 9 * M,
   'camera dentro il modello: l\'Overlay dichiara la scatola delle particelle')
pm.view.cam.eye = Geom::Point3d.new(75 * M, 0, 7 * M)            # 25 m oltre il bordo, sul mare
ok(!F.precip_extents.empty?, 'camera appena fuori dal modello (25 m): le particelle restano dichiarate')
pm.view.cam.eye = Geom::Point3d.new(500 * M, 0, 30 * M)          # 450 m oltre il bordo del modello
ok(F.precip_extents.empty?, 'camera lontana dal modello: nessun ingombro, Zoom estensioni non cambia')
pm.view.cam.eye = Geom::Point3d.new(0, 0, 1.7 * M)

# ── Cielo coperto ───────────────────────────────────────────────
look = [[0, 154, 217], [191, 191, 198], 80, 45, [191, 229, 245]]
ok(F.sky_overcast(look, 0.0) == look, 'senza pioggia il cielo non cambia')
cop = F.sky_overcast(look, 1.0)
ok((cop[0].max - cop[0].min) < 30 && cop[2] < 20 && cop[3] > 45, "pioggia forte: cielo grigio #{cop[0].inspect}, sole velato (luce #{cop[2]})")
ok(F.precip_cover == 0.5, 'copertura = intensità')

# ── Salvataggio e spegnimento ───────────────────────────────────
F.precip_saving(pm, true)
ok(ro['DisplayFog'] == false && ro['FogStartDist'] == -1.0, 'prima del salvataggio la nebbia del modello torna com\'era')
F.precip_saving(pm, false)
ok(ro['DisplayFog'] == true, 'dopo il salvataggio la nebbia riprende')
cfg['precip_fog'] = false
F.precip_sync
ok(ro['DisplayFog'] == false && ro['FogUseBkColor'] == false, 'nebbia spenta nel pannello: torna quella del modello')
cfg['precip_fog'] = true
F.precip_sync
cfg['precip_kind'] = 'none'
F.precip_sync
ok(ro['DisplayFog'] == false && ro['FogEndDist'] == -1.0 && pm.observers.empty? && F.instance_variable_get(:@precip_timer).nil?,
   'spenta: nebbia originale, niente osservatore né timer')
pm.view.calls.clear
F.precip_draw(pm.view)
ok(pm.view.calls.empty?, 'spenta: non si disegna nulla')

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
