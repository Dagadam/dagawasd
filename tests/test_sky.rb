# Cielo (lib/sky.rb): astronomia, colori, orologio, modello e disegno con SketchUp finto.
#   Esecuzione:  ruby -E UTF-8 tests/test_sky.rb   (oppure tests\run_tests.bat)
# I valori di riferimento del sole vengono da SketchUp 2024 (SunDirection
# con lo stesso luogo, data e ora), le fasi della luna dalle effemeridi.
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
def near(a, b, tol); a.zip(b).all? { |x, y| (x - y).abs <= tol }; end

tmp = Dir.mktmpdir('dagawasd_sky')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.load_cfg
cfg = F.instance_variable_get(:@cfg)

# ── Astronomia ──────────────────────────────────────────────────
roma = Time.utc(2026, 11, 8, 12, 30).to_f        # 13:30 a Roma (UTC+1)
s = F.sky_state(roma, 41.883, 12.5, 0.0)
ok(near(s[:sun], [-0.390458, -0.797508, 0.459917], 0.002), "sole come SketchUp (#{s[:sun].map { |x| x.round(4) }})")
s30 = F.sky_state(roma, 41.883, 12.5, 30.0)
ok(near(s30[:sun], [-0.736900, -0.495433, 0.459917], 0.002), 'nord del modello ruotato di 30°: sole come SketchUp')
piena = F.sky_state(Time.utc(2024, 1, 25, 17, 54).to_f, 0, 0, 0)
nuova = F.sky_state(Time.utc(2024, 1, 11, 11, 57).to_f, 0, 0, 0)
quarto = F.sky_state(Time.utc(2024, 1, 18, 3, 52).to_f, 0, 0, 0)
ok(piena[:moon_lit] > 0.99 && piena[:phase] == 4, 'luna piena il 25/1/2024')
ok(nuova[:moon_lit] < 0.01 && nuova[:phase] == 0, 'luna nuova l\'11/1/2024')
ok((quarto[:moon_lit] - 0.5).abs < 0.03 && quarto[:phase] == 2 && quarto[:waxing], 'primo quarto il 18/1/2024, crescente')
m = F.sky_matrix(41.883 * F::DEG, 1.0, 0.0)
polare = F.sky_apply_m(m, F.sky_eq_vec(2.530 * 15 * F::DEG, 89.26 * F::DEG))
ok((Math.asin(polare[2]) / F::DEG - 41.883).abs < 1.0, 'la Polare sta all\'altezza della latitudine')
ok(polare[1] > 0.7, 'la Polare è a nord (asse verde)')
mezzanotte = F.sky_state(Time.utc(2026, 6, 21, 22, 0).to_f, 41.883, 12.5, 0.0)
ok(mezzanotte[:sun_alt] < -20, "a mezzanotte d'estate il sole è sotto l'orizzonte (#{mezzanotte[:sun_alt].round}°)")

# ── Colori e luce ───────────────────────────────────────────────
orig = { sky: [0, 154, 217], bg: [191, 191, 198], light: 80, dark: 45 }
giorno = F.sky_look(40, orig)
notte  = F.sky_look(-30, orig)
ok(giorno[0, 4] == [orig[:sky], orig[:bg], 80, 45], 'di giorno restano cielo, sfondo e luce del modello')
ok(near(giorno[4], [191, 229, 245], 2), "orizzonte di giorno come lo fa SketchUp (#{giorno[4].inspect})")
ok(notte[4].sum < 100, "di notte niente fascia chiara all'orizzonte (#{notte[4].inspect})")
ok(notte[0].sum < 60 && notte[2] == 0 && notte[3] < 10, "di notte cielo scuro e niente sole (#{notte.inspect})")
tram = F.sky_look(-1, orig)
ok(tram[4][0] > tram[4][2] && tram[0][2] > tram[0][0], "al tramonto orizzonte arancio (#{tram[4].inspect}) sotto un cielo blu (#{tram[0].inspect})")
ok(F.sky_look(-30, orig, 8.0)[3] > notte[3], 'la luna alta schiarisce un po\' la notte')
ok(F.sky_night(10).zero? && F.sky_night(-20) == 1.0, 'stelle: invisibili di giorno, piene a notte fonda')

# ── Orologio dal pannello ───────────────────────────────────────
cfg.merge!('sky_hour' => 17.5, 'sky_day' => 31, 'sky_month' => 2)
t = Time.at(F.sky_utc_from_cfg(1.0) + 3600).utc
ok(t.month == 2 && t.day == (Time.utc(Time.now.year, 3, 1) - 86_400).day && t.hour == 17 && t.min == 30,
   "31 febbraio diventa l'ultimo giorno del mese, alle 17:30 locali (#{t})")

# ── Modello finto: ombre, stile, salvataggio ────────────────────
module Sketchup
  class Color
    attr_reader :rgba
    def initialize(*v); @rgba = v.size == 3 ? v + [255] : v; end
    def to_a; @rgba; end
    def ==(o); o.is_a?(Color) && o.rgba == rgba; end
  end
end
class FakeBB
  def initialize(a, b); @a = a; @b = b; end
  def empty?; false; end
  def min; @a; end
  def max; @b; end
  def corner(i); Geom::Point3d.new(i & 1 == 0 ? @a.x : @b.x, i & 2 == 0 ? @a.y : @b.y, i & 4 == 0 ? @a.z : @b.z); end
end
class FakeCam
  attr_accessor :eye
  def initialize; @eye = Geom::Point3d.new(0, 0, 60); end
  def perspective?; true; end
  def direction; Geom::Vector3d.new(0, 1, 0); end
  def xaxis; Geom::Vector3d.new(1, 0, 0); end
  def yaxis; Geom::Vector3d.new(0, 0, 1); end
end
class FakeView
  attr_reader :calls
  attr_accessor :drawing_color
  def initialize; @calls = []; @cam = FakeCam.new; end
  def camera; @cam; end
  def invalidate; end
  def draw(mode, pts); @calls << [:draw, mode, pts.size, @drawing_color, pts.map(&:z).min]; end
  def pixels_to_model(px, _pt); px * 2.0; end
end
class FakeModel
  attr_reader :shadow_info, :rendering_options, :observers, :view
  def initialize
    @shadow_info = { 'ShadowTime' => Time.at(1_794_144_600), 'Light' => 80, 'Dark' => 45, 'UseSunForAllShading' => false,
                     'DisplayShadows' => false, 'Latitude' => 41.883, 'Longitude' => 12.5, 'TZOffset' => 1.0,
                     'DaylightSavings' => false, 'NorthAngle' => 0.0, 'City' => 'Roma', 'Country' => 'Italia' }
    @rendering_options = { 'SkyColor' => Sketchup::Color.new(0, 154, 217), 'BackgroundColor' => Sketchup::Color.new(191, 191, 198),
                           'HorizonColor' => Sketchup::Color.new(0, 0, 0, 0), 'DrawHorizon' => true }
    @observers = []
    @view = FakeView.new
  end
  def add_observer(o); @observers << o; end
  def remove_observer(o); @observers.delete(o); end
  def active_view; @view; end
  def bounds; FakeBB.new(Geom::Point3d.new(-500, -500, 0), Geom::Point3d.new(500, 500, 300)); end
end
fm = FakeModel.new
Sketchup.define_singleton_method(:active_model) { fm }
si = fm.shadow_info; ro = fm.rendering_options
orig_time = si['ShadowTime']

cfg.merge!('sky_enabled' => false)
F.sky_sync
ok(F.instance_variable_get(:@sky_model).nil? && si['ShadowTime'] == orig_time, 'cielo spento: il modello non viene toccato')

# Mezzanotte del 21 giugno, tempo fermo
cfg.merge!('sky_enabled' => true, 'sky_now' => false, 'sky_flow' => false, 'sky_hour' => 0.0, 'sky_day' => 21, 'sky_month' => 6,
           'sky_colors' => true, 'sky_shadows' => true, 'sky_stars' => true, 'sky_sun' => true, 'sky_moon' => true)
$timers = []
F.sky_sync
st = F.instance_variable_get(:@sky)
ok(si['ShadowTime'].getutc.hour == 0 && si['ShadowTime'].getutc.month == 6 && si['ShadowTime'].getutc.day == 21,
   "ora del modello = ora del pannello nei campi UTC (#{si['ShadowTime'].getutc})")
ok(si['DisplayShadows'] == true && si['UseSunForAllShading'] == true, 'ombre e luce del sole accese')
ok(ro['SkyColor'].to_a[0, 3].sum < 60 && si['Light'] == 0 && ro['HorizonColor'].to_a[3] == 255,
   "notte: cielo scuro (#{ro['SkyColor'].to_a.inspect}), orizzonte scuro, luce diretta 0")
ok(fm.observers.size == 1, 'osservatore dei salvataggi aggiunto')
ok(F.instance_variable_get(:@sky_timer).nil?, 'tempo fermo: nessun timer')
ok(st[:stars] && st[:stars].sum(&:size) > 100, "stelle sopra l'orizzonte: #{st[:stars].sum(&:size)}")

# Disegno: di notte stelle, la luna se è alta, niente sole
fm.view.calls.clear
F.sky_draw(fm.view)
c = fm.view.calls
stelle = c.select { |x| x[1] == GL_QUADS }
davanti = st[:stars].sum { |b| b.count { |w| w[1] > 0 } }    # la camera finta guarda verso +Y
ok(stelle.sum { |x| x[2] } == davanti * 4 && c.none? { |x| x[3].to_a[0, 3] == [255, 250, 232] },
   "di notte si disegnano le stelle davanti alla camera (#{davanti}, un quadratino 3D ciascuna) e non il sole")

# Dove si disegna: appena oltre l'uscita dall'ingombro, mai oltre lo spigolo più lontano
g = F.sky_geo(fm.view.camera)          # occhio (0, 0, 60) dentro l'ingombro ±500 × ±500 × 0–300
ok((F.sky_dist(g, [0.0, 1.0, 0.0]) - 499.0).abs < 0.01,
   "sguardo verso +Y: la faccia a 500\" è anche il piano di taglio, si resta appena prima (#{F.sky_dist(g, [0.0, 1.0, 0.0]).round(1)})")
lato = F.sky_dist(g, [1.0, 0.0, 0.0])
ok(lato > 500 && lato < 502, "di lato (+X, profondità 0 sullo sguardo): appena oltre la faccia a 500\" (#{lato.round(1)})")
alto = F.sky_dist(g, [0.0, 0.0, 1.0])
ok(alto > 240 && alto < 300, "verso lo zenit: appena oltre il tetto dell'ingombro a 240\" sopra l'occhio (#{alto.round(1)})")
fuori = { eye: [0.0, -2000.0, 60.0], dir: [0.0, 1.0, 0.0], box: g[:box], fmax: 2500.0 }
w = [Math.sin(0.5), Math.cos(0.5), 0.0]       # 29° a lato: non incontra l'ingombro
ok(F.sky_dist(fuori, w) * w[1] < 2500.0, 'da fuori, in una direzione libera: resta prima del piano di taglio lontano')
ok((F.sky_dist(fuori, [0.0, 1.0, 0.0]) - 2500 * 0.998).abs < 1e-6,
   'da fuori, attraverso il modello: la faccia lontana coincide col piano di taglio, si resta appena prima')

# Sole all'orizzonte (segnalato alle 6:00 del 26/9 a Roma, sole a −1,1°):
# sotto l'orizzonte non si disegna nulla, a metà solo la parte sopra.
taglio = F.sky_clip([[0, 0, -1.0], [2, 0, -1.0], [2, 0, 1.0], [0, 0, 1.0]], 0.0)
ok(taglio.size == 4 && taglio.all? { |p| p[2] >= 0.0 } && taglio.count { |p| p[2].zero? } == 2, 'un quadrato tagliato a metà dall\'orizzonte')
ok(F.sky_clip([[0, 0, -1.0], [1, 0, -2.0], [0, 1, -1.5]], 0.0).empty?, 'un poligono tutto sotto l\'orizzonte sparisce')
alba = F.sky_state(Time.utc(2026, 9, 26, 5).to_f, 41.883, 12.5, 0.0)
ok(alba[:sun_alt].between?(-1.5, -0.5), "alle 6:00 locali del 26/9 a Roma il sole è appena sotto l'orizzonte (#{alba[:sun_alt].round(2)}°)")
salvo = F.instance_variable_get(:@sky)
sole_a = lambda do |alt_deg|
  a = alt_deg * F::DEG
  F.instance_variable_set(:@sky, salvo.merge(sun: [0.0, Math.cos(a), Math.sin(a)], sun_alt: alt_deg, stars: nil, moon_alt: -90.0))
  fm.view.calls.clear
  F.sky_draw(fm.view)
  fm.view.calls.select { |x| x[1] == GL_POLYGON }
end
prima = sole_a.(-1.1)
occhio = fm.view.camera.eye.z
ok(prima.size == 1 && prima[0][3].to_a[3] == 40 && prima[0][4] >= occhio - 1e-6,
   'sole a −1,1°: disco nascosto, sopra l\'orizzonte solo il chiarore tenue')
ok(sole_a.(-4).empty?, 'sole a −4°: non si vede nulla')
meta = sole_a.(0.5)
ok(meta.size == 3 && meta.all? { |x| x[4] >= occhio - 1e-6 }, "sole a +0,5°: si vede solo la parte sopra l'orizzonte (#{meta.size} dischi)")
ok(sole_a.(30).all? { |x| x[2] == 32 }, 'sole alto: dischi interi')
F.instance_variable_set(:@sky, salvo)

# Salvataggio: originali nel file, poi il cielo riprende
F.sky_saving(fm, true)
ok(si['ShadowTime'] == orig_time && si['Light'] == 80 && si['DisplayShadows'] == false && ro['SkyColor'].to_a[0, 3] == [0, 154, 217],
   'prima del salvataggio il modello ritrova i suoi valori')
F.sky_saving(fm, false)
ok(si['ShadowTime'].getutc.hour == 0 && si['Light'] == 0, 'dopo il salvataggio il cielo riprende')

# Mezzogiorno: sole disegnato, niente stelle, colori del modello
cfg['sky_hour'] = 12.0
F.sky_sync
fm.view.calls.clear
F.sky_draw(fm.view)
c = fm.view.calls
ok(c.none? { |x| x[1] == GL_QUADS } && c.count { |x| x[0] == :draw && x[1] == GL_POLYGON } >= 3, 'a mezzogiorno il sole sì, le stelle no')
ok(ro['SkyColor'].to_a[0, 3] == [0, 154, 217] && si['Light'] == 80, 'a mezzogiorno colori e luce del modello')

# Il tempo scorre: un giorno in 2 minuti → 12 minuti di cielo per secondo
cfg.merge!('sky_flow' => true, 'sky_day_minutes' => 2.0)
F.sky_sync
ok(F.instance_variable_get(:@sky_rate) == cfg['sky_fps'], 'tempo che scorre: timer acceso')
u0 = F.instance_variable_get(:@sky_utc)
F.instance_variable_set(:@sky_tick, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.25)
F.sky_frame
du = F.instance_variable_get(:@sky_utc) - u0
ok((du - 0.25 * 720).abs < 5, "0,25 s reali = #{du.round} s di cielo (atteso 180)")

# Ombre: ricalcolarle costa, quindi al più sky_shadow_fps volte al secondo
st0 = si['ShadowTime']
F.instance_variable_set(:@sky_tick, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.03)
F.sky_frame
ok(si['ShadowTime'] == st0, 'fotogramma subito dopo: il cielo avanza, l\'ora delle ombre aspetta')
F.instance_variable_get(:@sky_applied)[:time_at] -= 1.0 / cfg['sky_shadow_fps'] + 0.01
F.instance_variable_set(:@sky_tick, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.03)
F.sky_frame
ok(si['ShadowTime'] != st0, 'passato 1/sky_shadow_fps s: l\'ora delle ombre si aggiorna')

# Cambio di ora nel pannello: l'orologio riparte da lì
cfg['sky_hour'] = 6.0
F.sky_sync
ok(si['ShadowTime'].getutc.hour == 6, 'nuova ora dal pannello: l\'orologio riparte da lì')

# Luogo personalizzato: scritto nelle ombre (se no SketchUp illuminerebbe
# col sole di Roma), sole di mezzanotte e notte polare a Tromsø
cfg.merge!('sky_flow' => false, 'sky_place_custom' => true, 'sky_lat' => 69.65, 'sky_lon' => 18.96, 'sky_tz' => 1.0,
           'sky_hour' => 0.0, 'sky_day' => 21, 'sky_month' => 6)
F.sky_sync
ok(si['Latitude'] == 69.65 && si['Longitude'] == 18.96 && si['TZOffset'] == 1.0 && si['DaylightSavings'] == false,
   'luogo personalizzato scritto nelle ombre del modello')
ok(F.instance_variable_get(:@sky)[:sun_alt] > 0 && F.sky_status['custom'],
   "Tromsø, 21 giugno a mezzanotte: sole sopra l'orizzonte (#{F.instance_variable_get(:@sky)[:sun_alt].round(1)}°)")
cfg.merge!('sky_hour' => 12.0, 'sky_month' => 12)
F.sky_sync
ok(F.instance_variable_get(:@sky)[:sun_alt] < 0, "Tromsø, 21 dicembre a mezzogiorno: notte polare (#{F.instance_variable_get(:@sky)[:sun_alt].round(1)}°)")
F.sky_saving(fm, true)
ok(si['Latitude'] == 41.883 && si['Longitude'] == 12.5, 'prima del salvataggio torna il luogo del modello')
F.sky_saving(fm, false)
ok(si['Latitude'] == 69.65, 'dopo il salvataggio torna il luogo scelto')
cfg['sky_place_custom'] = false
F.sky_sync
ok(si['Latitude'] == 41.883 && si['TZOffset'] == 1.0 && F.instance_variable_get(:@sky)[:lat] == 41.883,
   'luogo personalizzato spento: di nuovo quello del modello')
cfg['sky_place_custom'] = true
F.sky_sync

# Spento: tutto torna com'era
cfg['sky_enabled'] = false
F.sky_sync
ok(si['Latitude'] == 41.883 && si['Longitude'] == 12.5, 'spento: il modello ritrova il suo luogo')
ok(si['ShadowTime'] == orig_time && si['Light'] == 80 && si['Dark'] == 45 && si['DisplayShadows'] == false &&
   si['UseSunForAllShading'] == false && ro['SkyColor'].to_a[0, 3] == [0, 154, 217] && ro['BackgroundColor'].to_a[0, 3] == [191, 191, 198] &&
   ro['HorizonColor'].to_a == [0, 0, 0, 0],
   'spento: ombre, luce e colori del modello tornano com\'erano')
ok(fm.observers.empty? && F.instance_variable_get(:@sky_timer).nil?, 'spento: niente osservatore né timer')
fm.view.calls.clear
F.sky_draw(fm.view)
ok(fm.view.calls.empty?, 'spento: non si disegna nulla')

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
