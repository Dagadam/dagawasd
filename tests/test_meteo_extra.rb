# Meteo, aggiunte: nuvole in time-lapse, temporale, neve al suolo, situazioni pronte (SketchUp finto).
#   Esecuzione:  ruby -E UTF-8 tests/test_meteo_extra.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
M = F::M_TO_IN
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end

tmp = Dir.mktmpdir('dagawasd_meteo')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.instance_variable_set(:@settings_file, File.join(tmp, 'settings.json'))
F.load_cfg
cfg = F.instance_variable_get(:@cfg)

$sounds = []
module UI
  def self.play_sound(path); $sounds << path; end
end
module Sketchup
  class Color
    attr_reader :rgba
    def initialize(*v); @rgba = v.size == 3 ? v + [255] : v; end
    def to_a; @rgba; end
  end
  class Layer; def visible?; true; end; end
end
class XCam
  def eye; Geom::Point3d.new(0, 0, 1.7 * M); end
  def direction; Geom::Vector3d.new(0, 1, 0); end
  def perspective?; true; end
end
class XView
  attr_reader :calls
  attr_accessor :drawing_color, :line_width
  def initialize; @calls = []; end
  def camera; @cam ||= XCam.new; end
  def vpwidth; 800; end
  def vpheight; 500; end
  def invalidate; end
  def draw(mode, pts, **_o); @calls << [:draw, mode, pts.size, @drawing_color&.to_a]; end
  def draw2d(mode, pts); @calls << [:draw2d, mode, pts.size, @drawing_color&.to_a]; end
end
# Facce finte: un tetto piano, una falda a 45°, un muro; dentro un gruppo spostato in alto
class XMesh
  def initialize(pts); @pts = pts; end
  def count_points; @pts.size; end
  def point_at(i); @pts[i - 1]; end
  def polygons; [[1, 2, 3], [1, -3, 4]]; end
end
class XFace < Sketchup::Face
  attr_accessor :back_material, :parent
  def initialize(n, pts); @n = n; @pts = pts.map { |p| Geom::Point3d.new(*p) }; end
  def normal; Geom::Vector3d.new(*@n); end
  def mesh(_f); XMesh.new(@pts); end
  def hidden?; false; end
  def layer; Sketchup::Layer.new; end
end
class XGroup < Sketchup::Group
  attr_reader :entities, :transformation
  def initialize(ents, tr); @entities = ents; @transformation = tr; end
  def hidden?; false; end
  def layer; Sketchup::Layer.new; end
end
class XModel
  attr_reader :entities, :shadow_info, :view, :observers
  def initialize(ents)
    @entities = ents; @shadow_info = { 'NorthAngle' => 0.0, 'Latitude' => 41.9, 'Longitude' => 12.5, 'TZOffset' => 1.0,
                                       'DaylightSavings' => false }
    @view = XView.new; @observers = []
  end
  def active_view; @view; end
  def add_observer(o); @observers << o; end
  def remove_observer(o); @observers.delete(o); end
  def bounds; b = Geom::BoundingBox.new; b.add(Geom::Point3d.new(-50 * M, -50 * M, 0)); b.add(Geom::Point3d.new(50 * M, 50 * M, 20 * M)); b; end
end
sq = ->(z) { [[0, 0, z], [100, 0, z], [100, 100, z], [0, 100, z]] }
tetto = XFace.new([0, 0, 1], sq.(0))
falda = XFace.new([0, 0.707, 0.707], sq.(0))
muro  = XFace.new([1, 0, 0], sq.(0))
gruppo = XGroup.new([tetto, falda, muro], Geom::Transformation.translation(Geom::Vector3d.new(0, 0, 300)))
lontano = XGroup.new([XFace.new([0, 0, 1], sq.(0))], Geom::Transformation.translation(Geom::Vector3d.new(400 * M, 0, 0)))
xm = XModel.new([gruppo, lontano])
Sketchup.define_singleton_method(:active_model) { xm }

# ── Nuvole in time-lapse ────────────────────────────────────────
cfg.merge!('cloud_timelapse' => true, 'sky_enabled' => true, 'sky_flow' => false, 'sky_now' => false, 'sky_day_minutes' => 4.0)
ok(F.cloud_timelapse == 1.0, 'tempo fermo: nuvole alla velocità del vento')
cfg['sky_flow'] = true
ok(F.cloud_timelapse == 30.0, 'giorno in 4 minuti (360×): nuvole al massimo 30×')
cfg['sky_day_minutes'] = 120.0
ok(F.cloud_timelapse == 12.0, 'giorno in 2 ore (12×): nuvole 12×')
cfg['cloud_timelapse'] = false
ok(F.cloud_timelapse == 1.0, 'opzione spenta: velocità del vento')
cfg.merge!('sky_flow' => false, 'sky_enabled' => false)

# ── Temporale ───────────────────────────────────────────────────
F.instance_variable_set(:@precip_rnd, Random.new(3))
F.instance_variable_set(:@precip_model, xm)
cfg.merge!('precip_kind' => 'none', 'storm' => true, 'storm_rate' => 6, 'storm_thunder' => true, 'cloud_height' => 1500)
ok(!F.storm_on?, 'senza pioggia niente temporale')
cfg['precip_kind'] = 'rain'
ok(F.storm_on?, 'pioggia e temporale: acceso')
attese = Array.new(400) { F.storm_wait }
media = attese.sum / attese.size
ok(attese.min >= 1.5 && (media - 10).abs < 2.5, "attesa fra i lampi: in media #{media.round(1)} s per 6 al minuto")
F.instance_variable_set(:@storm_next, 100.0)
F.storm_step(100.0)
s = F.instance_variable_get(:@storm)
ok(s && s[:pulses].size >= 2, 'è l\'ora: un lampo con due o tre guizzi')
ok(F.storm_glow(100.0) == 1.0 && F.storm_glow(100.0 + F::STORM_FLASH + 0.01) == 0.0, 'il lampo si accende subito e dura meno di mezzo secondo')
b = s[:bolt]
top = Math.atan2(1500.0, s[:dist])
ok((Math.asin(b.first[2]) - top).abs < 1e-6 && b.last[2].abs < 1e-9, 'fulmine dalla base delle nuvole all\'orizzonte')
th = F.instance_variable_get(:@storm_thunder).first
ok(th && (th[0] - (100.0 + s[:dist] / 343.0)).abs < 1e-6, "tuono dopo #{(s[:dist] / 343.0).round(1)} s (#{s[:dist].round} m)")
F.instance_variable_set(:@storm_next, th[0] - 1.0)       # un altro lampo prima del tuono
F.storm_step(th[0] - 1.0)
snd = F.instance_variable_get(:@snd)
plays = -> { snd.mci.grep(/\Aplay dagawasd_tuono/) }
ok(F.instance_variable_get(:@storm_thunder).size == 2 && plays.().empty?, 'un lampo nuovo prima del tuono: due tuoni in coda, nessuno perso')
F.storm_step(th[0] + 0.01)
opened = snd.mci.map { |c| c[/\Aopen "(.+)" type waveaudio alias dagawasd_tuono_[vl]\z/, 1] }.compact
ok(plays.().size == 1 && opened.size == 1 && File.binread(opened[0], 4) == 'RIFF' && $sounds.empty?,
   'tuono: un WAV suonato quando arriva, sul suo canale MCI (i passi non lo zittiscono)')
snd.mci_rc = 263                                          # MCI non disponibile
F.instance_variable_set(:@snd_open, {})
F.snd_play_file(opened[0], 'dagawasd_tuono_v')
snd.mci_rc = 0
ok($sounds == [opened[0]], 'senza MCI il tuono passa da UI.play_sound')
wav = F.storm_wav_data(true)
size, = wav.byteslice(4, 4).unpack('V'); rate, = wav.byteslice(24, 4).unpack('V'); n, = wav.byteslice(40, 4).unpack('V')
ok(size == wav.bytesize - 8 && rate == 22_050 && n == wav.bytesize - 44, 'WAV valido: 22050 Hz, 16 bit, intestazione coerente')
pcm = wav.byteslice(44, n).unpack('s<*')
ok(pcm.map(&:abs).max > 3000 && pcm.first(2205).map(&:abs).max > pcm.last(2205).map(&:abs).max * 3, 'tuono vicino: forte all\'inizio, poi si spegne')
F.instance_variable_set(:@storm_glow, 0.8)
v = XView.new
F.storm_draw(v)
ok(v.calls.count { |c| c[1] == GL_LINE_STRIP } == 2 && v.calls.any? { |c| c[0] == :draw2d }, 'lampo: fulmine (alone e linea) e vista schiarita')
lit, = F.cloud_colors
cfg['storm'] = false
lit2, = F.cloud_colors
ok(lit.sum < lit2.sum, 'col temporale le nuvole sono più scure')
cfg.merge!('precip_kind' => 'none', 'storm' => false)
F.instance_variable_set(:@storm_glow, 0.0)
F.instance_variable_set(:@precip_model, nil)

# ── Neve al suolo ───────────────────────────────────────────────
cfg.merge!('snow_cover' => true, 'snow_cover_time' => 1.0)
ok(F.snow_falling == 0.0, 'non nevica: niente da posare')
cfg.merge!('precip_kind' => 'snow', 'precip_intensity' => 100)
ok(F.snow_falling == 1.0, 'neve al 100 %')
cfg['precip_kind'] = 'mix'
ok(F.snow_falling == 0.5, 'nevischio: metà')
l = F.snow_advance(0.0, 60.0, 1.0, false)
ok((l - 1.0).abs < 1e-9, 'neve piena in snow_cover_time minuti alla massima intensità')
ok((F.snow_advance(0.0, 30.0, 0.5, false) - 0.35).abs < 1e-9, 'a metà intensità più lenta')
ok((F.snow_advance(1.0, 45.0, 0.0, false) - 0.5).abs < 1e-9 && F.snow_advance(1.0, 30.0, 0.0, true) == 0.0,
   'smette: si scioglie, con la pioggia tre volte più in fretta')
cfg['precip_kind'] = 'snow'
F.snow_sync
ok(F.instance_variable_get(:@snow_model).equal?(xm) && F.instance_variable_get(:@snow_timer), 'nevica: neve al suolo agganciata, timer acceso')
F.snow_collect_step(1.0)
tris = F.instance_variable_get(:@snow_tris)
ok(tris.size == 6 && tris.count { |t| t[4] > 0.99 } == 4 && tris.count { |t| (t[4] - 0.707).abs < 0.01 } == 2,
   'raccolte le facce verso l\'alto (tetti e falda), non il muro')
z = tris.find { |t| t[4] > 0.99 }[5][2]
ok((z - (300 + F::SNOW_LIFT)).abs < 1e-6, 'dentro il gruppo: posizione trasformata, appena sopra la superficie')
# Facce verso il basso: neve solo sui fogli sottili colorati sui due lati
class XEdge < Sketchup::Edge
  attr_reader :faces
  def initialize(faces); @faces = faces; end
end
XRaccolta = Struct.new(:entities)
raccolte = F.instance_variable_get(:@snow_tris)
aperta = XRaccolta.new([XEdge.new([1]), XEdge.new([1, 2])])        # foglia: spigolo con una faccia sola
chiusa = XRaccolta.new([XEdge.new([1, 2]), XEdge.new([1, 2])])     # solido chiuso
giu = lambda do |back, par|
  f = XFace.new([0, -0.6, -0.8], sq.(0)); f.back_material = back; f.parent = par; f
end
F.instance_variable_set(:@snow_tris, []); F.instance_variable_set(:@snow_open, {})
ok(F.snow_add_face(giu.('verde', aperta), Geom::Transformation.new), 'foglia rovesciata (retro colorato, geometria aperta): neve sulla pagina di sopra')
t = F.instance_variable_get(:@snow_tris).first
ok(t && (t[4] - 0.8).abs < 1e-9 && (t[3] - 0.6).abs < 1e-9 && (t[5][2] - F::SNOW_LIFT).abs < 1e-9, 'foglia rovesciata: normale capovolta verso l\'alto per la luce, neve sopra')
ok(!F.snow_add_face(giu.('verde', chiusa), Geom::Transformation.new), 'fondo di un solido chiuso colorato anche dentro: niente neve')
ok(!F.snow_add_face(giu.(nil, aperta), Geom::Transformation.new), 'faccia verso il basso senza retro colorato: niente neve')
ok(!F.snow_add_face(XFace.new([0, -0.95, -0.3], sq.(0)).tap { |f| f.back_material = 'verde'; f.parent = aperta }, Geom::Transformation.new),
   'foglio quasi verticale: troppo ripido anche dal retro')
F.instance_variable_set(:@snow_tris, raccolte)
F.snow_select(0.0, 0.0)
sel = F.instance_variable_get(:@snow_sel)
ok(sel.sum(&:size) == 4 * 3, 'si disegnano solo le facce vicine alla camera (non quella a 400 m)')
F.instance_variable_set(:@snow_level, 0.6)
v = XView.new
F.snow_draw(v)
ok(v.calls.size == 2 && v.calls.all? { |c| c[1] == GL_TRIANGLES && c[3][3] == (F::SNOW_ALPHA * 0.6).round }, 'disegno: toni di luce, opaco quanto la neve')
ok(v.calls[0][3][0] < v.calls[1][3][0], 'luce diffusa: la falda è più scura del tetto piano')
sole = [0.0, 0.995, 0.0995]                          # sole basso a nord, cielo libero
verso = F.snow_shade(0.0, 0.707, 0.707, sole, 1.0)
contro = F.snow_shade(0.0, -0.707, 0.707, sole, 1.0)
ok(verso > contro + 0.3, "sole basso: falda verso il sole chiara (#{verso.round(2)}), quella opposta in ombra (#{contro.round(2)})")
F.instance_variable_set(:@in_phys_op, true)
F.snow_model_changed
ok(F.instance_variable_get(:@snow_tris).size == 6, 'le mosse della fisica non fanno ripartire la raccolta')
F.instance_variable_set(:@in_phys_op, false)
F.snow_model_changed
ok(F.instance_variable_get(:@snow_tris).empty?, 'una modifica dell\'utente sì')
cfg['snow_cover'] = false
F.snow_sync
ok(F.instance_variable_get(:@snow_model).nil? && F.snow_level == 0.0 && F.instance_variable_get(:@snow_timer).nil?, 'neve al suolo spenta: tutto via')
cfg.merge!('precip_kind' => 'none', 'snow_cover' => true)

# ── Situazioni pronte ───────────────────────────────────────────
cfg.merge!('sky_month' => 6, 'sky_day' => 21, 'sky_place_custom' => false)
alba = F.sky_sun_hour(:rise, 0.0, 41.9, 12.5, 1.0)
tram = F.sky_sun_hour(:set, 0.0, 41.9, 12.5, 1.0)
ok((alba - 4.6).abs < 0.15 && (tram - 19.8).abs < 0.15, "Roma, 21 giugno (UTC+1): sole all'orizzonte alle #{alba.round(2)} e alle #{tram.round(2)}")
ok(F.sky_sun_hour(:rise, 0.0, 78.2, 15.6, 1.0).nil?, 'Svalbard d\'estate: il sole non sorge né tramonta (nessuna ora)')
mezzanotte = F.sky_sun_hour(:night, 0, 41.9, 12.5, 1.0)
ok((mezzanotte - 0.2).abs < 0.3 || (mezzanotte - 24.2).abs < 0.3, "sole più basso verso la mezzanotte solare (#{mezzanotte.round(2)})")
F.weather_preset('sunset')
ok(cfg['sky_enabled'] && !cfg['sky_now'] && cfg['precip_kind'] == 'none' && cfg['cloud_enabled'] &&
   (cfg['sky_hour'] - 19.5).abs <= 0.25 && (cfg['sky_hour'] * 4) == (cfg['sky_hour'] * 4).round,
   "Tramonto sereno: cielo acceso, ora #{cfg['sky_hour']} (sole a 3°), a quarti d'ora")
F.weather_preset('storm')
ok(cfg['precip_kind'] == 'rain' && cfg['storm'] && cfg['cloud_cover'] == 100 && cfg['sky_hour'] == 16.5, 'Temporale estivo: pioggia, lampi, cielo chiuso')
F.weather_preset('starry')
ok(!cfg['cloud_enabled'] && cfg['precip_kind'] == 'none' && !cfg['storm'], 'Notte stellata: niente nuvole né pioggia')
saved = JSON.parse(File.read(File.join(tmp, 'settings.json')))
ok(saved['cloud_enabled'] == false && saved['sky_enabled'] == true, 'la situazione viene salvata nelle impostazioni')
F.weather_preset('inesistente')
ok(cfg['cloud_enabled'] == false, 'una situazione sconosciuta non cambia nulla')
F.sky_stop; F.precip_stop; F.cloud_stop; F.snow_stop

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
