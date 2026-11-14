# Percorsi registrati: registrazione, levigatura, riproduzione, scene, immagini (SketchUp finto).
#   Esecuzione:  ruby -E UTF-8 tests/test_path.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
MB_YESNO = 4 unless defined?(MB_YESNO)
IDYES = 6 unless defined?(IDYES)
IDNO = 7 unless defined?(IDNO)

tmp = Dir.mktmpdir('dagawasd_percorsi')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.instance_variable_set(:@settings_file, File.join(tmp, 'settings.json'))
F.load_cfg
cfg = F.instance_variable_get(:@cfg)
cfg['language'] = 'it'
F.load_lang
cfg['path_video_sheet'] = false     # il foglio di controllo (GDI+) ha il suo test più sotto
cfg['path_video_notify'] = false    # niente suoni durante i test

# ── SketchUp finto ────────────────────────────────────────────────────
class Dict < Hash
  def delete_key(k); delete(k); end
end
class Cam
  attr_reader :eye, :target, :up
  attr_accessor :fov, :perspective
  def initialize; set(Geom::Point3d.new(0, 0, 66), Geom::Point3d.new(100, 0, 66), Geom::Vector3d.new(0, 0, 1)); @fov = 60.0; @perspective = true; end
  def set(e, t, u); @eye = e; @target = t; @up = u; end
  def perspective?; @perspective; end
  def direction
    d = Geom::Vector3d.new(target.x - eye.x, target.y - eye.y, target.z - eye.z)
    d.normalize!
  end
end
class FakeView
  attr_accessor :camera
  attr_reader :anim                    # solo per il test: la View vera ha animation= ma non animation
  def animation=(a); old = @anim; @anim = a; old.stop if old.respond_to?(:stop) && !old.equal?(a); end
  attr_reader :images
  def initialize; @camera = Cam.new; @images = []; end
  def vpwidth; 800; end
  def vpheight; 500; end
  def invalidate; end
  def write_image(o)
    data = o[:filename].end_with?('.jpg') ? "\xFF\xD8".b + ('x' * (500 + @images.size * 7)) + "\xFF\xD9".b : 'PNG'
    File.binwrite(o[:filename], data)
    @images << [o[:filename], o[:width], o[:height], @camera.eye.x]
    true
  end
end
Page = Struct.new(:name, :flags, :eye_x, :transition_time, :delay_time, :description) do
  def attrs; @attrs ||= {}; end
  def get_attribute(d, k, dflt = nil); attrs.fetch([d, k], dflt); end
  def set_attribute(d, k, v); attrs[[d, k]] = v; end
  # flag delle scene di SketchUp: 2 stile e resa, 4 ombre, 32 tag
  def use_rendering_options?; flags.to_i & 2 != 0; end
  def use_style?; flags.to_i & 2 != 0; end
  def use_shadow_info?; flags.to_i & 4 != 0; end
  def use_hidden_layers?; flags.to_i & 32 != 0; end
end
class FakePages
  include Enumerable
  def initialize(view); @view = view; @list = []; end
  def each(&b); @list.each(&b); end
  def to_a; @list.dup; end
  def add(name, flags); p = Page.new(name, flags, @view.camera.eye.x); @list << p; p; end
  def erase(p); @list.delete(p); end
  def size; @list.size; end
end
class FakeModel
  attr_reader :view, :pages, :dicts, :ops, :tools_sel, :opts
  def initialize
    @view = FakeView.new; @pages = FakePages.new(@view); @dicts = {}; @ops = []; @tools_sel = []
    @opts = { 'PageOptions' => { 'ShowTransition' => false } }
  end
  def active_view; @view; end
  def attribute_dictionary(n, create = false); @dicts[n] ||= Dict.new if create; @dicts[n]; end
  def set_attribute(d, k, v); attribute_dictionary(d, true)[k] = v; end
  def attribute_dictionaries; dd = @dicts; o = Object.new; o.define_singleton_method(:delete) { |d| dd.delete(dd.key(d)) }; o; end
  def start_operation(name, *_); @ops << [:start, name]; true; end
  def commit_operation; @ops << [:commit]; true; end
  def abort_operation; @ops << [:abort]; true; end
  def select_tool(t); @tools_sel << t; end
  def options; @opts; end
  def path; ''; end
  def layers; {}; end            # niente posizioni nel modello: quelle le prova tests/test_pathkeys.rb
  def definitions; []; end
end
pm = FakeModel.new
Sketchup.define_singleton_method(:active_model) { pm }
view = pm.view
boxes = []
UI.define_singleton_method(:messagebox) { |msg, *_a| boxes << msg; $answer || IDYES }

# ── Registrazione: 3 s a 60 Hz, 1 m/s in avanti, testa che dondola ────
M = F::M_TO_IN
rec = lambda do |secs, t0 = 100.0|
  F.path_rec_start(t0)
  (0..(secs * 60).round).each do |i|
    t = i / 60.0
    x = t * M
    z = 66 + 2.0 * Math.sin(t * 2 * Math::PI * 4.4)                  # dondolio: ±2"
    view.camera.set(Geom::Point3d.new(x, 0, z), Geom::Point3d.new(x + 100, 0, z), Geom::Vector3d.new(0, 0, 1))
    F.path_rec_tick(t0 + t, view)
  end
  F.path_rec_stop
end
n1 = rec.(3.0)
d = pm.attribute_dictionary(F::PATH_DICT)
data = d && JSON.parse(d['Percorso 1'])
ok(n1 == 'Percorso 1' && data, 'registrazione salvata nel modello come «Percorso 1»')
s = data['s']
ok((s.size - 91).abs <= 2, "#{s.size} campioni in 3 s (30 al secondo, non 60)")
ok(s.first[0] == 0.0 && (s.last[0] - 3.0).abs < 0.04 && s.first.size == 11, 'campioni [t, occhio, direzione, alto, fov] dall\'inizio')
ok(pm.ops.include?([:start, F.t('path.op_save')]) && pm.ops.last == [:commit], 'un\'operazione annullabile «Registra percorso»')
ok(rec.(0.2).nil? && d.keys == ['Percorso 1'], 'troppo corta (0,2 s): non salvata')
ok(rec.(2.0, 200.0) == 'Percorso 2', 'la seconda prende il numero successivo')
F.instance_variable_set(:@path_rec, nil)
ok(F.path_rec_stop.nil?, 'fermare senza registrazione: niente')
lst = F.path_list
ok(lst.map { |p| p['name'] } == ['Percorso 1', 'Percorso 2'] && (lst[0]['dur'] - 3.0).abs < 0.05, 'elenco per il pannello, in ordine, con la durata')

# ── Fotogrammi levigati ──────────────────────────────────────────────
raw = F.path_frames(s, 0.0)
lev = F.path_frames(s, 0.6)
amp = ->(fr) { zs = fr[15...-15].map { |f| f[2] }; zs.max - zs.min }
ok(raw.size == 91 && amp.(raw) > 3.5, "senza levigatura il dondolio resta (#{amp.(raw).round(2)}\")")
ok(amp.(lev) < 0.6, "levigati 0,6 s: dondolio quasi sparito (#{amp.(lev).round(2)}\")")
ok(lev.first[0].abs < 1e-6 && (lev.last[0] - s.last[1]).abs < 1e-6, 'partenza e arrivo esattamente dove erano')
ok(lev.all? { |f| (Math.sqrt(f[3]**2 + f[4]**2 + f[5]**2) - 1).abs < 1e-9 && (f[3] * f[6] + f[4] * f[7] + f[5] * f[8]).abs < 1e-9 },
   'direzione unitaria e alto perpendicolare')
mid = F.path_frame_at(lev, 1.5)
ok((mid[0] - 1.5 * M).abs < 1.0, "a metà tempo a metà strada (#{(mid[0] / M).round(3)} m)")
ok(F.path_frame_at(lev, 99.0) == lev.last, 'oltre la fine: l\'ultimo fotogramma')

# ── Riproduzione ─────────────────────────────────────────────────────
cfg['path_speed'] = 2.0
F.instance_variable_set(:@active, false)
view.camera.set(Geom::Point3d.new(-7 * M, 2 * M, 80), Geom::Point3d.new(-7 * M, 3 * M, 80), Geom::Vector3d.new(0, 0, 1))
view.camera.fov = 45.0
ok(F.path_start(:play, 'Percorso 1').nil? && view.anim && pm.tools_sel.last.is_a?(F::PathTool),
   'riproduzione: animazione nella vista e strumento che la ferma')
job = F.instance_variable_get(:@path_job)
ok(F.path_start(:play, 'Percorso 2') == F.t('path.busy'), 'una alla volta')
job[:t0] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.5          # 0,5 s a velocità 2 = 1 s di cammino
ok(view.anim.nextFrame(view) == true && (view.camera.eye.x / M - 1.0).abs < 0.05,
   "velocità 2: dopo 0,5 s la camera è a #{(view.camera.eye.x / M).round(2)} m")
job[:t0] -= 10
ok(view.anim.nextFrame(view) == false, 'finito: l\'animazione si ferma')
ok(view.anim.nil? && pm.tools_sel.last.nil? && !F.path_busy?, 'e lascia il campo: niente animazione, strumento di selezione')
ok((view.camera.eye.x + 7 * M).abs < 1e-6 && (view.camera.target.y - 3 * M).abs < 1e-6 && view.camera.fov == 45.0,
   'arrivata in fondo: la camera torna dov\'era alla partenza, con lo stesso zoom')
F.path_start(:play, 'Percorso 1')
job = F.instance_variable_get(:@path_job)
job[:t0] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.5
view.anim.nextFrame(view)
F::PathTool.new.onCancel(0, view)
ok(!F.path_busy? && view.anim.nil?, 'Esc ferma la riproduzione')
ok((view.camera.eye.x / M - 1.0).abs < 0.05, 'fermata con Esc: la camera resta dov\'è arrivata')
F.path_start(:play, 'Percorso 1', from: 1.0)
job = F.instance_variable_get(:@path_job)
job[:t0] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.25          # più 0,25 s a velocità 2 = 0,5 s
ok(view.anim.nextFrame(view) == true && (view.camera.eye.x / M - 1.5).abs < 0.05,
   "da 1 s del percorso: dopo 0,25 s la camera è a #{(view.camera.eye.x / M).round(2)} m")
F::PathTool.new.onCancel(0, view)
F.path_start(:play, 'Percorso 1')
altra = Object.new
view.animation = altra                                      # es. le scene di SketchUp
ok(!F.path_busy? && view.anim.equal?(altra), 'un\'altra animazione prende il posto: si ferma senza toglierla')
view.animation = nil
F.path_start(:play, 'Percorso 1')
sel = pm.tools_sel.size
F::PathTool.new.deactivate(view)
ok(!F.path_busy? && pm.tools_sel.size == sel, 'scelto un altro strumento: si ferma senza toglierlo')
ok(F.path_start(:play, 'Nessuno') == F.t('path.missing'), 'percorso inesistente: messaggio')

# ── Commenti dell'IA (lib/expilot.rb): descrizioni delle scene, sottotitoli ──
con_note = lambda do |name, notes|
  p = JSON.parse(d[name])
  p['notes'] = notes
  d[name] = JSON.generate(p)
end
con_note.('Percorso 1', [[2.9, 'Fine'], [1.2, 'Una statua'], [1.3, 'Bella'], [2.0, '  '], 'rotto'])
ok(F.path_track('Percorso 1')[:notes] == [[1.2, 'Una statua'], [1.3, 'Bella'], [2.9, 'Fine']],
   'commenti del percorso: in ordine, senza quelli vuoti o rotti')
srt = F.path_srt([[0.5, 'Primo'], [1.0, 'Secondo'], [9.0, 'oltre la fine']], 1.0, 2.0)
ok(srt == "\uFEFF1\r\n00:00:00,500 --> 00:00:00,950\r\nPrimo\r\n\r\n2\r\n00:00:01,000 --> 00:00:02,000\r\nSecondo\r\n",
   'SRT: ognuno finché arriva il successivo, l\'ultimo fino alla fine del video, niente oltre')
ok(F.path_srt([[2.0, 'Uno']], 2.0, 60.0).include?('00:00:01,000 --> 00:00:05,120') && F.path_srt([[3.0, 'x']], 1.0, 2.0).nil?,
   'SRT a velocità 2: tempi dimezzati; 4 s più un po\' per testo; nessun commento nel tratto: nil')
con_note.('Percorso 2', [[0.5, 'Primo'], [1.0, 'Secondo']])

# ── Scene ────────────────────────────────────────────────────────────
cfg['path_scene_step'] = 1.0
cfg['path_speed'] = 1.0
pm.pages.add('Ingresso', 1)
cam0 = view.camera.eye.x
F.path_make_scenes('Percorso 1')
sc = pm.pages.select { |p| p.name.start_with?('Percorso 1 ') }
ok(sc.map(&:name) == ['Percorso 1 001', 'Percorso 1 002', 'Percorso 1 003', 'Percorso 1 004'], "una scena al secondo: #{sc.size} scene")
ok(sc.all? { |p| p.flags == 1 && p.delay_time == 0.0 } && sc[1..].all? { |p| (p.transition_time - 1.0).abs < 1e-9 },
   'solo la camera, nessuna pausa, transizione di 1 s')
ok((sc.last.eye_x - s.last[1]).abs < 1.0 && (sc[1].eye_x / M - 1.0).abs < 0.05, 'ogni scena dove si era in quell\'istante')
ok(pm.opts['PageOptions']['ShowTransition'] == true, 'transizioni delle scene accese')
ok(sc.map(&:description) == [nil, 'Una statua · Bella', nil, 'Fine'], 'i commenti dell\'IA nella descrizione della scena più vicina')
ok(view.camera.eye.x == cam0, 'la vista torna com\'era')
cfg['path_speed'] = 2.0
F.path_make_scenes('Percorso 1')
sc2 = pm.pages.select { |p| p.name.start_with?('Percorso 1 ') }
ok(sc2.size == 4 && pm.pages.size == 5 && pm.pages.first.name == 'Ingresso', 'rifatte: sostituite, le altre scene restano')
ok((sc2[1].transition_time - 0.5).abs < 1e-9, 'a velocità 2 le transizioni durano metà')
ok(boxes.last.include?('4'), 'messaggio con il numero di scene')
# Prima: rifacendole si toglieva ogni scena chiamata «Percorso 1 NNN», anche
# una fatta a mano dall'utente. Ora solo le nostre (attributo), e quelle di
# prima dell'attributo se salvano solo la camera.
ok(sc2.all? { |p| p.get_attribute(F::PATH_DICT, 'percorso') == 'Percorso 1' }, 'le scene fatte sanno di che percorso sono')
mano = pm.pages.add('Percorso 1 007', 4095)            # dell'utente: salva tutto
vecchia = pm.pages.add('Percorso 1 009', 1)            # di una versione di prima: solo camera, senza attributo
altro = pm.pages.add('Percorso 10 001', 1)
altro.set_attribute(F::PATH_DICT, 'percorso', 'Percorso 10')
F.path_make_scenes('Percorso 1')
ok(pm.pages.to_a.include?(mano) && pm.pages.to_a.include?(altro) && !pm.pages.to_a.include?(vecchia),
   'rifatte: resta la scena dell\'utente con lo stesso nome e quella di un altro percorso; via quella di prima')
ok(pm.pages.count { |p| p.get_attribute(F::PATH_DICT, 'percorso') == 'Percorso 1' } == 4, 'e le nostre sono di nuovo 4')
[mano, altro].each { |p| pm.pages.erase(p) }

# ── Immagini per il video ────────────────────────────────────────────
cfg.merge!('path_speed' => 1.0, 'path_video_fps' => 10, 'path_video_size' => 'hd', 'path_video_format' => 'png')
batch = F::PATH_BATCH
F.send(:remove_const, :PATH_BATCH); F.const_set(:PATH_BATCH, 0.0)    # qui un fotogramma per giro
UI.define_singleton_method(:select_directory) { |**_o| tmp }
F.path_export_frames('Percorso 2')
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
out = File.join(tmp, 'Percorso 2')
pngs = Dir.glob(File.join(out, 'frame_*.png'))
ok(pngs.size == 21 && view.images.size == 21, "2 s a 10 al secondo: #{pngs.size} immagini")
ok(view.images.all? { |_f, w, h, _x| w == 1280 && h == 720 }, 'alla dimensione scelta (HD)')
xs = view.images.map(&:last)
ok(xs.each_cons(2).all? { |a, b| b > a }, 'ogni immagine un passo più avanti')
bat = File.join(out, 'crea_video.bat')
ok(File.exist?(bat) && File.read(bat).include?('-framerate 10') && File.read(bat).include?('frame_%%05d.png'),
   'accanto, crea_video.bat per ffmpeg')
srt_png = File.join(out, 'Percorso 2.srt')
ok(File.exist?(srt_png) && File.binread(srt_png).force_encoding('UTF-8').include?('Secondo') &&
   File.read(bat).include?('-i "Percorso 2.srt" -c:s mov_text'),
   'i commenti in Percorso 2.srt, e crea_video.bat li mette nel video come sottotitoli')
ok(boxes.last.include?('21') && !F.path_busy? && view.anim.nil?, 'alla fine: messaggio con quante immagini e dove')
view.images.clear
F.path_export_frames('Percorso 2')
3.times { view.anim.nextFrame(view) }
F::PathTool.new.onCancel(0, view)
ok(Dir.glob(File.join(out, 'frame_*.png')).size == 3 && boxes.last.include?('3'),
   'interrotta con Esc: restano le immagini fatte (le vecchie tolte) e lo dice')
UI.define_singleton_method(:select_directory) { |**_o| nil }
ok(F.path_export_frames('Percorso 2').nil? && !F.path_busy?, 'nessuna cartella scelta: non parte')

# ── Video AVI (Motion JPEG) ──────────────────────────────────────────
# Smonta il file: [fourcc, dimensione, inizio dei dati] di ogni pezzo RIFF.
chunks = lambda do |b, from, to|
  out = []
  while from + 8 <= to
    id, n = b.byteslice(from, 8).unpack('a4V')
    out << [id, n, from + 8]
    from += 8 + n + (n & 1)
  end
  out
end
cfg.merge!('path_video_format' => 'avi', 'path_video_fps' => 10, 'path_video_size' => 'hd')
avi_file = File.join(tmp, 'giro.avi')
UI.define_singleton_method(:savepanel) { |*_a| avi_file.sub(/\.avi\z/, '') }    # senza estensione: la aggiunge
view.images.clear
F.path_export_frames('Percorso 2')
k += 1 while view.anim&.nextFrame(view) && k < 5000
b = File.binread(avi_file)
riff, rsize, kind = b.unpack('a4Va4')
ok(riff == 'RIFF' && kind == 'AVI ' && rsize == b.bytesize - 8, 'AVI: RIFF valido, dimensione giusta')
top = chunks.(b, 12, b.bytesize)
ok(top.map(&:first) == %w[LIST LIST idx1] && b.byteslice(top[0][2], 4) == 'hdrl' && b.byteslice(top[1][2], 4) == 'movi',
   'intestazione, fotogrammi e indice in quest\'ordine')
avih = b.byteslice(top[0][2] + 12, 56).unpack('V14')
strh_at = top[0][2] + 4 + 8 + 56 + 12
strh = b.byteslice(strh_at + 8, 56).unpack('a4a4VvvVVVVV')
strf = b.byteslice(strh_at + 8 + 56 + 8, 40).unpack('Vl<l<vva4')
ok(avih[0] == 100_000 && avih[4] == 21 && avih[8] == 1280 && avih[9] == 720, 'avih: 10 al secondo, 21 fotogrammi, 1280×720')
ok(strh[0] == 'vids' && strh[1] == 'MJPG' && strh[7] == 10 && strh[6] == 1 && strh[9] == 21 && strf[5] == 'MJPG' && strf[1] == 1280,
   'flusso video MJPG con la stessa durata')
frames = chunks.(b, top[1][2] + 4, top[1][2] + top[1][1])
ok(frames.size == 21 && frames.all? { |id, n, at| id == '00dc' && b.byteslice(at, 2) == "\xFF\xD8".b && b.byteslice(at + n - 2, 2) == "\xFF\xD9".b },
   '21 JPEG interi nel blocco dei fotogrammi (anche quelli di lunghezza dispari)')
idx = b.byteslice(top[2][2], top[2][1]).unpack('a4VVV' * 21).each_slice(4).to_a
movi = top[1][2]
ok(idx.size == 21 && idx.each_with_index.all? { |(id, fl, off, n), i| id == '00dc' && fl == 0x10 && movi + off == frames[i][2] - 8 && n == frames[i][1] },
   'indice: ogni fotogramma chiave, posizione e lunghezza giuste')
ok(avih[7] >= frames.map { |_id, n, _at| n }.max, 'buffer suggerito grande quanto il fotogramma più grosso')
ok(boxes.last.include?('giro.avi') && boxes.last.include?('0:02') && !File.exist?(File.join(Dir.tmpdir, "dagawasd_fotogramma_#{Process.pid}.jpg")),
   'alla fine: messaggio con file e durata, JPEG temporaneo tolto')
srt_avi = File.join(tmp, 'giro.srt')
ok(File.exist?(srt_avi) && File.binread(srt_avi).include?('Primo'), 'accanto al video giro.srt con i commenti')
F.path_export_frames('Percorso 2')
5.times { view.anim.nextFrame(view) }
F::PathTool.new.onCancel(0, view)
b = File.binread(avi_file)
ok(b.byteslice(4, 4).unpack1('V') == b.bytesize - 8 && b.byteslice(48, 4).unpack1('V') == 5 && boxes.last.include?('giro.avi'),
   'interrotto con Esc: video di 5 fotogrammi, comunque valido')
ok(!File.exist?(srt_avi), 'mezzo secondo di video, nessun commento: il .srt di prima tolto')
UI.define_singleton_method(:savepanel) { |*_a| nil }
ok(F.path_export_frames('Percorso 2').nil? && !F.path_busy?, 'nessun file scelto: non parte')
# Prima: se l'avvio falliva dopo aver aperto il video, il file restava aperto
# (bloccato finché SketchUp non si chiudeva) e vuoto.
rotto = File.join(tmp, 'rotto.avi')
UI.define_singleton_method(:savepanel) { |*_a| rotto }
orig_ps = F.method(:path_start)
F.define_singleton_method(:path_start) { |*_a| raise IOError, 'avvio fallito' }
alzato = (F.path_export_frames('Percorso 2') rescue :raised)
F.define_singleton_method(:path_start, orig_ps)
ok(alzato == :raised && !File.exist?(rotto) && !F.path_busy?, 'avvio del video fallito: il file aperto viene chiuso e tolto')
UI.define_singleton_method(:savepanel) { |*_a| nil }
small = F::MjpegAvi.new(File.join(tmp, 'vuoto.avi'), 64, 48, 25)
begin
  small.add('non un jpeg')
  ok(false, 'dati che non sono JPEG rifiutati')
rescue ArgumentError
  ok(true, 'dati che non sono JPEG rifiutati')
end
small.close
ok(File.size(File.join(tmp, 'vuoto.avi')) == 224 + 8, 'video senza fotogrammi: solo intestazione e indice vuoto')

# ── Esporta video: dal fotogramma x al y, in coda, registro ──────────
# (lib/videoexport.rb; qui senza la finestra: le scelte arrivano dirette)
corri = -> { n = 0; n += 1 while view.anim&.nextFrame(view) && n < 5000 }
# dove stava la camera in ogni fotogramma scritto (il finto write_image non la mette nel JPEG)
camere = -> { view.images.map(&:last) }
cfg.merge!('path_video_format' => 'avi', 'path_video_fps' => 10, 'path_video_size' => 'hd', 'path_speed' => 1.0)
intero = File.join(tmp, 'intero.avi')
view.images.clear
F.path_export_frames('Percorso 2', target: intero)
corri.()
cam_intero = camere.()
view.images.clear
pezzi = File.join(tmp, 'pezzi.avi')
ok(F.path_export_frames('Percorso 2', target: pezzi, from: 1, to: 8).nil?, 'dal fotogramma 1 all\'8: parte')
corri.()
info = F::MjpegAvi.probe(pezzi)
ok(info && info[:index].size == 8 && info[:w] == 1280 && info[:h] == 720 && info[:fps] == 10, 'primo pezzo: 8 fotogrammi, 1280×720 a 10 al secondo')
reg = File.join(tmp, 'pezzi.log')
ss = F.vx_log_sessions(reg)
txt = File.binread(reg).force_encoding('UTF-8')
ok(ss.size == 1 && ss[0].values_at('mode', 'from', 'to', 'first', 'total', 'last', 'n', 'state') == ['new', 1, 8, 1, 21, 8, 8, 'end'],
   'registro accanto al video: un pezzo nuovo, dal 1 all\'8 di 21, finito all\'8')
ok(ss[0]['at0'] =~ /\A\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\z/ && ss[0]['at1'] && ss[0]['spf'] && ss[0]['cfg']['format'] == 'avi' && ss[0]['cfg']['quality'] == 90,
   'il pezzo sa data e ora d\'inizio e fine, secondi a fotogramma, formato e qualità')
righe = txt.split("\r\n")
ok(righe[0] =~ /\A\+=+\+\z/ && righe[0].size == F::VX_LOG_W && righe[1].start_with?('| DagaWASD') && righe[2].include?('Percorso 2') &&
   righe[1].size == F::VX_LOG_W, 'in cima un riquadro ASCII largo VX_LOG_W con DagaWASD e il percorso')
[F.t('ve.lg.model'), F.t('ve.lg.path'), F.t('ve.lg.video'), F.t('f.path_video_weather'), F.t('ve.lg.runs'), F.t('ve.lg.sum'), F.t('ve.lg.warn')].each do |s|
  ok(righe.include?(" #{s.upcase}"), "sezione «#{s.upcase}»")
end
ok(txt.include?("#{F.t('f.path_video_size')} ") && txt.include?('1280x720') && txt =~ /^\| 1 +\| #{F.t('ve.lg.m_new')} +\|.*\| 1-8 \(8\) +\|/ &&
   txt.include?(F.vx_f(F.t('ve.lg.done_v'), n: 8, total: 21, p: '38.1')) && txt.include?(F.vx_f(F.t('ve.lg.resume_v'), n: 9)),
   'misure, una riga della tabella per pezzo (1-8), fatti 8 di 21 e da dove riprendere')
ok(righe.count { |l| l.start_with?('#D {') } == 1 && righe.grep(/\A#D /).all?(&:ascii_only?), 'in fondo i dati, una riga per pezzo, in ASCII')
ok(F.path_export_frames('Percorso 2', target: pezzi, from: 9, to: 21, append: true).nil?, 'dal 9 al 21, in coda: parte')
corri.()
b = File.binread(pezzi)
ok(b.byteslice(48, 4).unpack1('V') == 21 && b.byteslice(4, 4).unpack1('V') == b.bytesize - 8, 'in coda: un video solo, di 21 fotogrammi, intestazione giusta')
ok(cam_intero.size == 21 && camere.() == cam_intero, 'i due pezzi uniti sono il video fatto in una volta, fotogramma per fotogramma')
ss = F.vx_log_sessions(reg)
txt = File.binread(reg).force_encoding('UTF-8')
ok(ss.size == 2 && ss[1].values_at('mode', 'from', 'to', 'first', 'before', 'last', 'state') == ['append', 9, 21, 1, 8, 21, 'end'],
   'registro: il pezzo di prima resta, poi dal 9 in coda (col primo fotogramma del video) fino al 21')
ok(txt =~ /^\| 2 +\| #{F.t('ve.lg.m_append')} +\|.*\| 9-21 \(13\) +\|/ && txt.include?(F.vx_f(F.t('ve.lg.done_v'), n: 21, total: 21, p: '100.0')) &&
   !txt.include?(F.t('ve.lg.resume')), 'due righe nella tabella, fatti tutti: niente da riprendere')
ok(File.binread(File.join(tmp, 'pezzi.srt')).include?('Primo'), 'sottotitoli di tutto il video')
F.path_export_frames('Percorso 2', target: File.join(tmp, 'stop.avi'), from: 3, to: 21)
4.times { view.anim.nextFrame(view) }
F::PathTool.new.onCancel(0, view)
ss = F.vx_log_sessions(File.join(tmp, 'stop.log'))
ok(ss.last.values_at('state', 'last') == ['stop', 6] &&
   File.binread(File.join(tmp, 'stop.log')).force_encoding('UTF-8').include?(F.vx_f(F.t('ve.lg.resume_v'), n: 7)),
   'interrotto con Esc: il registro dice l\'ultimo fotogramma scritto (6) e da dove riprendere (7)')
ok(F.vx_log_last(File.join(tmp, 'stop.log')).include?(F.t('ve.lg.st_stop')) && F.vx_log_last(File.join(tmp, 'stop.log')).end_with?('6'),
   'per la finestra: ultima riga con l\'esito e l\'ultimo fotogramma')
# Un registro della 1.2 (righe con [ev=…]): si legge ancora
vecchio = File.join(tmp, 'vecchio.log')
File.binwrite(vecchio, "DagaWASD — registro\r\n2026-11-12 17:10:56  Inizio …  [ev=start from=2001 to=8366 total=8366 fps=30 w=1280 h=720 first=2001]\r\n" \
                       "2026-11-13 01:39:07  Interrotto …  [ev=stop last=5000 next=5001]\r\n")
vs = F.vx_log_sessions(vecchio)
ok(vs.size == 1 && vs[0].values_at('from', 'last', 'n', 'state', 'first', 'at1') == [2001, 5000, 3000, 'stop', 2001, '2026-11-13 01:39:07'] &&
   F.vx_file_first(vecchio) == 2001, 'registro di prima: inizio e fine diventano un pezzo, il primo fotogramma resta')
vt = F.vx_log_text(vs)
ok(vt.include?('2001-5000 (3000)') && vt.include?(F.vx_f(F.t('ve.lg.resume_v'), n: 5001)) && vt.include?(F.t('ve.lg.st_stop')),
   'e si riscrive nel formato nuovo')
# Larghezze: un'etichetta giapponese occupa due colonne a carattere
ok(F.vx_cw('動画') == 4 && F.vx_cw('Vidéo') == 5 && F.vx_cw("e\u0301") == 1, 'colonne: CJK doppie, accenti combinati zero')
ok(F.vx_file_first(File.join(tmp, 'stop.log')) == 3 && F::MjpegAvi.probe(File.join(tmp, 'stop.avi'))[:index].size == 4,
   'il video comincia dal fotogramma 3 e ne ha 4')
# Prima: interrotto a metà da SketchUp chiuso, il video restava senza indice né
# numeri (illeggibile) e un fotogramma a metà. Si riprende in coda e torna buono.
jpeg = "\xFF\xD8".b + ('x' * 101).b + "\xFF\xD9".b
mezzo = File.join(tmp, 'mai_chiuso.avi')
av = F::MjpegAvi.new(mezzo, 64, 48, 10)
3.times { av.add(jpeg) }
io = av.instance_variable_get(:@io)
io.write(['00dc', 500].pack('a4V'), 'y' * 20)        # l'ultimo, scritto a metà
io.close
ok(File.binread(mezzo).byteslice(48, 4).unpack1('V').zero?, 'video mai chiuso: intestazione a zero')
pr = F::MjpegAvi.probe(mezzo)
ok(pr && pr[:index].size == 3 && pr[:w] == 64 && pr[:fps] == 10, 'riletto lo stesso: 3 fotogrammi interi, quello a metà no')
ok(F::MjpegAvi.append(mezzo, 64, 48, 25).nil? && F::MjpegAvi.append(mezzo, 32, 48, 10).nil?, 'altri fps o altre misure: niente coda')
ok(F::MjpegAvi.probe(File.join(tmp, 'pezzi.log')).nil?, 'un file che non è un nostro AVI: nil')
ap = F::MjpegAvi.append(mezzo, 64, 48, 10)
ok(ap.before == 3, 'in coda dopo 3')
ap.add(jpeg)
ap.close
b = File.binread(mezzo)
top = chunks.(b, 12, b.bytesize)
idx = b.byteslice(top[2][2], top[2][1]).unpack('a4VVV' * 4).each_slice(4).to_a
ok(top.map(&:first) == %w[LIST LIST idx1] && b.byteslice(48, 4).unpack1('V') == 4 && idx.size == 4 &&
   idx.all? { |id, _f, off, n| id == '00dc' && n == jpeg.bytesize && b.byteslice(top[1][2] + off + 8, 2) == "\xFF\xD8".b },
   'dopo la coda: 4 fotogrammi, indice giusto, il pezzo a metà sparito')
# Il meteo a metà video è quello di un'esportazione da capo: va avanti
# fotogramma per fotogramma dal primo (senza scrivere), poi si scrive.
passi = []
vmb = F.method(:vm_begin); vms = F.method(:vm_step); vme = F.method(:vm_end)
F.define_singleton_method(:vm_begin) { |job| job[:vm] = { paint: false } }
F.define_singleton_method(:vm_step) { |_job, _v, tv, dt| passi << [(tv * 10).round, dt] }
F.define_singleton_method(:vm_end) { |job| job[:vm] = nil }
view.images.clear
ffile = File.join(tmp, 'ff.avi')
F.path_export_frames('Percorso 2', target: ffile, from: 6, to: 8)
corri.()
F.define_singleton_method(:vm_begin, vmb); F.define_singleton_method(:vm_step, vms); F.define_singleton_method(:vm_end, vme)
ok(passi.map(&:first) == (0..7).to_a && passi[0][1].zero? && passi[1..].all? { |_, dt| (dt - 0.1).abs < 1e-9 },
   'dal fotogramma 6: il meteo passa per ogni fotogramma dal primo, un decimo di secondo l\'uno')
ok(camere.() == cam_intero[5, 3], 'e si scrivono solo 6, 7 e 8, con la camera dove stava nel video intero')
cfg['path_video_format'] = 'png'
pdir = File.join(tmp, 'pezzi_png')
F.path_export_frames('Percorso 2', target: pdir, from: 1, to: 10)
corri.()
F.path_export_frames('Percorso 2', target: pdir, from: 11, to: 21)
corri.()
nomi = Dir.children(pdir).grep(/\Aframe_/).sort
ok(nomi.size == 21 && nomi.first == 'frame_00001.png' && nomi.last == 'frame_00021.png', 'immagini in due pezzi: 21, numerate come da capo')
ok(!File.read(File.join(pdir, 'crea_video.bat')).include?('-start_number') && F.vx_log_sessions(File.join(pdir, 'Percorso 2.log')).size == 2,
   'crea_video.bat da frame_00001; registro nella cartella con i due inizi')
qdir = File.join(tmp, 'coda_png')
F.path_export_frames('Percorso 2', target: qdir, from: 8, to: 21)
corri.()
srt = File.binread(File.join(qdir, 'Percorso 2.srt')).force_encoding('UTF-8')
ok(File.read(File.join(qdir, 'crea_video.bat')).include?('-start_number 8 -i frame_%%05d.png') && Dir.children(qdir).grep(/\Aframe_/).size == 14,
   'solo dall\'8: 14 immagini e crea_video.bat comincia da frame_00008')
ok(!srt.include?('Primo') && srt.include?("00:00:00,300 --> ") && srt.include?('Secondo'),
   'sottotitoli spostati: il commento di 1 s, nel video che parte da 0,7 s, arriva a 0,3 s')
cfg['path_video_format'] = 'avi'

# Più fotogrammi per giro: un write_image da 0,1 s, giro da 0,35 s → 4 per giro
# (3 quando sleep di Windows sfora di qualche millisecondo: conta che siano più d'uno)
F.send(:remove_const, :PATH_BATCH); F.const_set(:PATH_BATCH, 0.35)
slow = view.method(:write_image)
view.define_singleton_method(:write_image) { |o| sleep 0.1; slow.call(o) }
UI.define_singleton_method(:savepanel) { |*_a| avi_file }
view.images.clear
F.path_export_frames('Percorso 2')
view.anim.nextFrame(view)
per_giro = view.images.size
F::PathTool.new.onCancel(0, view)
view.singleton_class.send(:remove_method, :write_image)
ok(per_giro.between?(3, 4), "un giro dell'animazione scrive più fotogrammi (#{per_giro}): il ridisegno fra un giro e l'altro pesa meno")
F.send(:remove_const, :PATH_BATCH); F.const_set(:PATH_BATCH, batch)

# ── Finestra durante il video (lib/attesa.rb) ────────────────────────
# Fin qui senza UI::HtmlDialog: la finestra non si apriva e il finale era
# un messagebox. Da qui una finestra finta che raccoglie gli execute_script.
module UI
  class HtmlDialog
    attr_reader :opts, :file, :scripts
    def self.all; @all ||= []; end
    def initialize(o); @opts = o; @scripts = []; @cb = {}; @visible = false; HtmlDialog.all << self; end
    def set_file(f); @file = f; end
    def add_action_callback(n, &b); @cb[n] = b; end
    def set_on_closed(&b); @closed = b; end
    def show; @visible = true; end
    def visible?; @visible; end
    def close; return unless @visible; @visible = false; @closed&.call; end
    def bring_to_front; end
    def execute_script(s); @scripts << s; end
    def call(n, arg = ''); @cb[n].call(nil, arg); end
    # [[funzione, dati]] dagli script: init({...}), progress({...}), finish({...})
    def sent; @scripts.map { |s| m = s.match(/\A(\w+)\((.*)\)\z/m); [m[1], JSON.parse(m[2])] }; end
    def last(fn); (sent.reverse.find { |f, _| f == fn } || [])[1]; end
  end
end

# Posizione ricordata dove non c'è più un monitor (2026-10-17: il pannello a
# x = -1241 "aperto" ma invisibile, e il menu faceva solo bring_to_front)
if F.ensure_win32
  pos = Class.new(UI::HtmlDialog) do
    attr_reader :centered
    def initialize(xy); super({}); @xy = xy; end
    def get_position; @xy; end
    def get_size; [620, 880]; end
    def center; @centered = true; end
  end
  fuori = pos.new([-30_000, 260])
  F.dialog_on_screen(fuori)
  ok(fuori.centered, 'finestra ricordata fuori da ogni monitor: rimessa al centro')
  dentro = pos.new([100, 100])
  F.dialog_on_screen(dentro)
  ok(!dentro.centered, 'finestra sullo schermo: resta dov\'è')
  UI::HtmlDialog.all.clear
end
class FakeEnts < Array
  def grep(k); select { |e| e.is_a?(k) }; end
end
FakeDef = Struct.new(:entities, :group, :image) do
  def group?; group; end
  def image?; image; end
  def get_attribute(*); nil; end
end
pm.define_singleton_method(:entities) { FakeEnts.new(Array.new(3) { Sketchup::Face.allocate }) }
pm.define_singleton_method(:definitions) do
  [FakeDef.new(FakeEnts.new(Array.new(5) { Sketchup::Face.allocate }), false, false),    # componente
   FakeDef.new(FakeEnts.new(Array.new(2) { Sketchup::Face.allocate }), true, false),     # gruppo
   FakeDef.new(FakeEnts.new([]), false, true)]                                            # immagine
end
pm.define_singleton_method(:materials) { %w[legno vetro] }
pm.define_singleton_method(:title) { 'Faro' }
F.send(:remove_const, :PATH_BATCH); F.const_set(:PATH_BATCH, 0.0)
cfg.merge!('path_video_format' => 'png', 'path_video_fps' => 10, 'path_video_size' => 'hd')
UI.define_singleton_method(:select_directory) { |**_o| tmp }
nbox = boxes.size
F.path_export_frames('Percorso 2')
dlg = UI::HtmlDialog.all.last
ok(dlg && dlg.visible? && dlg.file == F::ATTESA_FILE && File.exist?(dlg.file), 'all\'avvio si apre la finestra con attesa.html')
ok(dlg.scripts.empty?, 'prima di ready la pagina non riceve nulla')
dlg.call('ready')
ini = dlg.last('init')
st = ini && ini['stats']
ok(ini && ini['strings'].keys.all? { |k| k.start_with?('att.', 'fun.') || k == 'f.path_video_weather' } &&
   ini['strings']['f.path_video_weather'] == F.t('f.path_video_weather') && ini['strings']['att.stop'] == F.t('att.stop') && ini['lang'] == 'it',
   'init: solo i testi att./fun. e il nome di «Meteo nel video», nella lingua scelta')
ok(st && (st['m'] - 2.0).abs < 0.1 && st['total'] == 21 && st['w'] == 1280 && st['fps'] == 10 && st['format'] == 'png',
   "statistiche: #{st && st['m']} m percorsi, 21 fotogrammi, 1280×720 a 10 al secondo")
ok(st['faces'] == 10 && st['comps'] == 1 && st['mats'] == 2 && st['model'] == 'Faro',
   'modello: facce di modello e definizioni (una volta), componenti senza gruppi e immagini, materiali, titolo')
ok(st['up'] < 0.2 && st['turn'] < 5, 'dritto e in piano: niente salita, niente giri (il dondolio non conta)')
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
prog = dlg.sent.select { |f, _| f == 'progress' }.map(&:last)
ok(prog.size >= 20 && prog.map { |p| p['k'] }.each_cons(2).all? { |a, b| b >= a } && prog.last['k'] == 21 && prog.last['bytes'] == 21 * 3,
   "avanzamento dopo ogni blocco (#{prog.size}): fotogrammi e byte scritti")
fin = dlg.last('finish')
ok(fin && fin['why'] == 'fine' && fin['n'] == 21 && fin['dir'] == File.join(tmp, 'Percorso 2').tr('/', '\\') && boxes.size == nbox,
   'finale nel fumetto, niente messagebox')
opened = []
UI.define_singleton_method(:openURL) { |u| opened << u }
dlg.call('open', 'dir')
ok(opened.last == "file:///#{File.join(tmp, 'Percorso 2')}", '«Apri la cartella» apre quella delle immagini')
UI.define_singleton_method(:start_timer) { |*_a, &b| b.call; 1 }
dlg.call('close')
ok(!dlg.visible? && F.instance_variable_get(:@attesa).nil?, '«Chiudi» chiude la finestra')

F.path_export_frames('Percorso 2')
dlg = UI::HtmlDialog.all.last
dlg.call('ready')
3.times { view.anim.nextFrame(view) }
dlg.call('stop')
fin = dlg.last('finish')
ok(!F.path_busy? && fin && fin['why'] == 'interrotto' && fin['n'] == 3 && boxes.size == nbox, '«Interrompi» (o Esc nella pagina) ferma: il finale lo dice la finestra')
F.attesa_close

F.path_export_frames('Percorso 2')
dlg = UI::HtmlDialog.all.last
2.times { view.anim.nextFrame(view) }
dlg.close
ok(!F.path_busy? && boxes.size == nbox + 1 && boxes.last.include?('2'), 'finestra chiusa con la X: si ferma, e il finale torna un messagebox')

cfg['path_video_format'] = 'avi'
UI.define_singleton_method(:savepanel) { |*_a| avi_file }
F.path_export_frames('Percorso 2')
dlg = UI::HtmlDialog.all.last
dlg.call('ready')
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
fin = dlg.last('finish')
ok(fin && fin['file'] == avi_file.tr('/', '\\') && fin['time'] == '0:02' && fin['mb'] >= 0, 'AVI: file, durata e MB nel finale')
dlg.call('open', 'file')
ok(opened.last == "file:///#{avi_file}", '«Guarda il video» apre il file')
dlg.call('close')
UI.singleton_class.send(:remove_method, :start_timer)

# Pagina mancante (installazione incompleta): niente finestra bianca, finale col messagebox
vera = F::ATTESA_FILE
F.send(:remove_const, :ATTESA_FILE); F.const_set(:ATTESA_FILE, File.join(tmp, 'non_c_e.html'))
quante = UI::HtmlDialog.all.size
nbox = boxes.size
F.path_export_frames('Percorso 2')
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
ok(UI::HtmlDialog.all.size == quante && boxes.size == nbox + 1 && boxes.last.include?('avi'),
   'attesa.html mancante: nessuna finestra, alla fine il messagebox di sempre')
F.send(:remove_const, :ATTESA_FILE); F.const_set(:ATTESA_FILE, vera)

# Salita, discesa e giri dello sguardo: rampa di 6 m su 30 m girando due volte
ramp = Array.new(301) do |i|
  a = i / 300.0 * 4 * Math::PI
  [i * 0.1 * M, 0.0, 66 + i / 300.0 * 6 * M, Math.cos(a), Math.sin(a), 0.0, 0.0, 0.0, 1.0, 60.0]
end
pd = F.attesa_progress_data(k: 8366, k0: 8366, stop: 8456, ff: 2930, ff_s: 180.0, bytes: 0, att: { t0: Process.clock_gettime(Process::CLOCK_MONOTONIC) })
ok(pd['ff'] == { 'n' => 8367, 'p' => 35 } && pd['ff_s'] == 180.0 && pd['k'].zero? && pd['total'] == 90,
   'attesa: dal 8367 col meteo ancora al 2930, «35%» e il tempo del meteo a parte')
st = F.attesa_stats(frames: ramp, name: 'rampa', dur: 10.0, speed: 1.0, fps: 30, total: 300, w: 1920, h: 1080)
ok((st['up'] - 6.0).abs < 0.3 && st['down'] < 0.3 && (st['turn'] - 720).abs < 5 && (st['kmh'] - 30.6 / 10 * 3.6).abs < 0.3,
   "rampa: #{st['up']} m in salita, #{st['down']} in discesa, sguardo girato di #{st['turn']}°, #{st['kmh']} km/h")
# La battuta sul meteo: nuvole in corso, dipinte nel video o lasciate fuori
vw = F.cf('path_video_weather')
F.instance_variable_set(:@cloud_model, Sketchup.active_model)
w_video = F.attesa_weather(vm: { paint: {} })
F.instance_variable_get(:@cfg)['path_video_weather'] = false
w_out = F.attesa_weather(vm: { paint: false })
F.instance_variable_get(:@cfg)['path_video_weather'] = vw
w_fail = F.attesa_weather(vm: { paint: false })
F.instance_variable_set(:@cloud_model, nil)
ok(st['weather'] == false && w_video == 'video' && w_out == 'out' && w_fail == false && F.attesa_weather(vm: { paint: {} }) == false,
   "meteo: senza #{st['weather'].inspect}, dipinto #{w_video.inspect}, opzione spenta #{w_out.inspect}, dipinto non partito #{w_fail.inspect}")
F.send(:remove_const, :PATH_BATCH); F.const_set(:PATH_BATCH, batch)

# ── Finestra Esporta video (lib/videoexport.rb) ──────────────────────
UI::HtmlDialog.all.clear
cfg.merge!('path_video_format' => 'avi', 'path_video_fps' => 10, 'path_video_size' => 'hd', 'path_speed' => 1.0)
F.path_command('frames', 'Percorso 2')
vd = UI::HtmlDialog.all.last
ok(vd && vd.file == F::VX_FILE && File.exist?(vd.file) && !F.path_busy?, '«Video» apre la finestra Esporta video e non parte')
vd.call('ready')
ini = vd.last('init')
st = vd.last('show')
ok(ini['strings'].keys.all? { |k| k.start_with?('ve.') || F::VX_PANEL.include?(k) } && ini['strings']['ve.go'] == F.t('ve.go') &&
   ini['strings']['o.path_video_size.hd'] == F.t('o.path_video_size.hd'), 'init: i testi ve. e i nomi delle impostazioni del pannello')
ok(st['total'] == 21 && st['fps'] == 10 && st['w'] == 1280 && st['format'] == 'avi' && st['target'].end_with?('\\Percorso 2.avi') && !st['busy'],
   'stato: 21 fotogrammi, un AVI col nome del percorso')
vd.call('target', pezzi.tr('/', '\\'))
st = vd.last('show')
ok(st['avi'] == { 'n' => 21, 'a' => 1, 'b' => 21 } && st['next'].nil? && st['log_exists'] && st['log_last'].include?('21'),
   'un video intero già fatto: lo dice, niente da riprendere, ultima riga del registro')
vd.call('target', ffile)
st = vd.last('show')
ok(st['avi'] == { 'n' => 3, 'a' => 6, 'b' => 8 } && st['next'] == 9, 'un pezzo dal 6 all\'8: si riprende dal 9 (il primo lo sa il registro)')
vd.call('target', File.join(tmp, 'senza_estensione'))
ok(vd.last('show')['target'].end_with?('senza_estensione.avi') && !vd.last('show')['exists'], 'scritto a mano senza .avi: lo aggiunge')
vd.call('target', ffile)
vd.call('set', JSON.generate('path_video_fps' => 20))
st = vd.last('show')
ok(cfg['path_video_fps'] == 20 && st['total'] == 41 && st['avi_other'] && !st['avi'], 'cambiati gli fps: salvati, 41 fotogrammi, quel video non va più in coda')
vd.call('set', JSON.generate('path_video_fps' => 999, 'path_video_size' => 'enorme', 'altro' => 1))
ok(cfg['path_video_fps'] == 60 && cfg['path_video_size'] == 'hd' && !cfg.key?('altro'), 'valori fuori misura: tagliati o ignorati')
vd.call('set', JSON.generate('path_video_fps' => 10, 'path_video_format' => 'png'))
vd.call('target', pdir)
st = vd.last('show')
ok(st['format'] == 'png' && st['png'] == { 'n' => 21, 'a' => 1, 'b' => 21 } && st['next'].nil?, 'immagini: la cartella ne ha 21')
vd.call('target', qdir)
ok(vd.last('show')['png'] == { 'n' => 14, 'a' => 8, 'b' => 21 }, 'una cartella dall\'8 al 21')
UI.define_singleton_method(:select_directory) { |**_o| tmp }
vd.call('browse')
ok(vd.last('show')['target'].end_with?('\\Percorso 2'), 'Sfoglia: dentro la cartella scelta, una col nome del percorso')
UI.define_singleton_method(:select_directory) { |**_o| qdir }
vd.call('browse')
ok(vd.last('show')['target'] == qdir.tr('/', '\\'), 'Sfoglia su una cartella che ha già le immagini: proprio quella')
vd.call('set', JSON.generate('path_video_format' => 'avi'))
UI.define_singleton_method(:savepanel) { |*_a| File.join(tmp, 'scelto') }
vd.call('browse')
ok(vd.last('show')['target'] == File.join(tmp, 'scelto.avi').tr('/', '\\'), 'Sfoglia per il video: il file scelto, con .avi')
UI.define_singleton_method(:savepanel) { |*_a| nil }
vd.call('target', File.join(tmp, 'non_c_e', 'x.avi'))
nb = boxes.size
vd.call('go', JSON.generate('from' => 1, 'to' => 21))
ok(boxes.size == nb + 1 && boxes.last.include?('non_c_e') && !F.path_busy? && vd.visible?, 'cartella che non c\'è: lo dice e la finestra resta')
vd.call('target', File.join(tmp, 'dalla_finestra.avi'))
vd.call('go', JSON.generate('from' => 3, 'to' => 5))
ok(F.path_busy? && !vd.visible?, 'Esporta: parte e la finestra si chiude')
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
ok(F::MjpegAvi.probe(File.join(tmp, 'dalla_finestra.avi'))[:index].size == 3, 'dal 3 al 5: 3 fotogrammi')
F.path_command('frames', 'Percorso 2')
vd = UI::HtmlDialog.all.last
vd.call('target', pezzi)
vd.call('go', JSON.generate('from' => 1, 'to' => 3, 'append' => true))
ok(!F.path_busy? && vd.visible? && F::MjpegAvi.probe(pezzi)[:index].size == 21,
   'in coda dal 1 a un video che ha già 1-21: non parte (rifarebbe il film una seconda volta)')
vd.close if vd.visible?
salto = File.join(tmp, 'salto.avi')
F.path_export_frames('Percorso 2', target: salto, from: 1, to: 5)
corri.()
ok(F.path_export_frames('Percorso 2', target: salto, mode: 'append', from: 8, to: 9).nil?, 'in coda più avanti (un salto): parte')
corri.()
ok(F::MjpegAvi.probe(salto)[:index].size == 7, "in coda dall'8 dopo il 5: 7 fotogrammi")
ok(File.binread(File.join(tmp, 'salto.log')).force_encoding('UTF-8').include?(F.vx_f(F.t('ve.lg.w_gap'), a: 5, b: 8)),
   "registro: in coda dall'8 dopo il 5, avviso del salto")

# ── Rifai un tratto dentro un video (mode patch) ─────────────────────
fotogrammi = lambda do |file|
  info = F::MjpegAvi.probe(file)
  b = File.binread(file)
  info[:index].map { |off, n| b.byteslice(info[:movi] + off + 8, n) }
end
prima = fotogrammi.(intero)
view.images.clear
ok(F.path_export_frames('Percorso 2', target: intero, from: 5, to: 8, mode: 'patch').nil?, 'rifai dal 5 all\'8 dentro il video intero: parte')
corri.()
dopo = fotogrammi.(intero)
ok(camere.() == cam_intero[4, 4] && dopo.size == 21, 'si scrivono solo i 4 fotogrammi, dalla stessa camera; il video ne ha sempre 21')
ok(dopo[0, 4] == prima[0, 4] && dopo[8..] == prima[8..] && dopo[4, 4] != prima[4, 4],
   'gli altri restano identici, byte per byte; quei 4 sono quelli nuovi')
ok(!File.exist?("#{intero}.tratto") && F::MjpegAvi.probe(intero)[:fps] == 10, 'il pezzo di lavoro sparisce, il video resta leggibile')
ss = F.vx_log_sessions(File.join(tmp, 'intero.log'))
ok(ss.last.values_at('mode', 'from', 'to', 'state') == ['patch', 5, 8, 'end'] && ss.last['res']['patched'] == 4, 'registro: un pezzo «rifatto», 4 fotogrammi entrati')
err = F.path_export_frames('Percorso 2', target: File.join(tmp, 'stop.avi'), from: 5, to: 9, mode: 'patch')
ok(err.is_a?(String) && err.include?('3') && err.include?('6') && !F.path_busy?, 'rifai oltre la fine del video (3–6): rifiutato, col tratto che c\'è')
cfg['path_video_fps'] = 20
err = F.path_export_frames('Percorso 2', target: intero, from: 2, to: 3, mode: 'patch')
ok(err.is_a?(String) && !F.path_busy?, 'rifai con altri fps: rifiutato')
cfg['path_video_fps'] = 10
ok(F::MjpegAvi.probe(intero)[:index].size == 21, 'e il video non è stato toccato')

# ── Audio (.wav) nel video ───────────────────────────────────────────
wav = lambda do |file, sec, rate: 8000, ch: 1, fmt: 1|
  data = ([1000, -1000] * (sec * rate * ch / 2.0).ceil).first((sec * rate * ch).round).pack('s<*')
  File.binwrite(file, 'RIFF' + [36 + data.bytesize].pack('V') + 'WAVE' + 'fmt ' + [16, fmt, ch, rate, rate * ch * 2, ch * 2, 16].pack('VvvVVvv') +
                      'data' + [data.bytesize].pack('V') + data)
  file
end
musica = wav.(File.join(tmp, 'musica.wav'), 2.0)
ok(F::MjpegAvi.wav(musica)&.values_at(:ch, :rate, :bits, :bytes) == [1, 8000, 16, 32_000], 'un .wav PCM si legge: 1 canale, 8000 Hz, 16 bit, 2 s')
ok(F::MjpegAvi.wav(wav.(File.join(tmp, 'mp3.wav'), 0.5, fmt: 85)).nil? && F::MjpegAvi.wav(File.join(tmp, 'pezzi.log')).nil?, 'non PCM, o non un .wav: nil')
cfg['path_video_audio'] = musica
con_audio = File.join(tmp, 'con_audio.avi')
ok(F.path_export_frames('Percorso 2', target: con_audio).nil?, 'con l\'audio: parte')
corri.()
info = F::MjpegAvi.probe(con_audio)
b = File.binread(con_audio)
ok(info[:audio] && info[:audio_bytes] == 32_000 && info[:index].size == 21 && b.byteslice(4, 4).unpack1('V') == b.bytesize - 8,
   'nel video: 21 fotogrammi e tutti i 2 s di audio, intestazione giusta')
ok(b.include?('auds') && b.scan('01wb').size >= 2 && b.byteslice(56, 4).unpack1('V') == 2, 'una traccia audio (auds), a pezzi fra i fotogrammi, 2 flussi')
ok(F.vx_log_sessions(File.join(tmp, 'con_audio.log')).last['res']['audio'] == true &&
   F.vx_log_sessions(File.join(tmp, 'con_audio.log')).last['cfg']['audio'] == musica.tr('/', '\\'), 'registro: audio messo, e quale')
ok(F.path_export_frames('Percorso 2', target: con_audio, from: 3, to: 4, mode: 'patch').nil?, 'rifai un tratto in un video con audio')
corri.()
info = F::MjpegAvi.probe(con_audio)
ok(info[:audio] && info[:audio_bytes] == 32_000 && info[:index].size == 21, 'l\'audio resta')
coda_audio = File.join(tmp, 'coda_audio.avi')
F.path_export_frames('Percorso 2', target: coda_audio, from: 11, to: 21)
corri.()
info = F::MjpegAvi.probe(coda_audio)
ok(info[:audio_bytes] == 16_000, 'un video che parte dal fotogramma 11 (1 s): l\'audio parte da 1 s (16000 byte dopo)')
err = F.path_export_frames('Percorso 2', target: coda_audio, mode: 'append', from: 1, to: 2)
ok(err == F.vx_f(F.t('ve.gap'), b: 21, n: 22) && !F.path_busy? && F::MjpegAvi.probe(coda_audio)[:index].size == 11,
   "in coda dal 1 a un video che va dall'11 al 21: non parte, e dice da dove si continua")
cfg['path_video_audio'] = File.join(tmp, 'mp3.wav')
err = F.path_export_frames('Percorso 2', target: File.join(tmp, 'mai.avi'))
ok(err.is_a?(String) && err.include?('mp3.wav') && !File.exist?(File.join(tmp, 'mai.avi')) && !F.path_busy?, 'audio illeggibile: non parte, e dice quale')
cfg['path_video_audio'] = musica
cfg['path_video_format'] = 'png'
adir = File.join(tmp, 'audio_png')
F.path_export_frames('Percorso 2', target: adir, from: 8, to: 21)
corri.()
bat = File.binread(File.join(adir, 'crea_video.bat'))
ok(bat.include?("-ss 0.700 -i \"#{musica.tr('/', '\\')}\"") && bat.include?('-map 0:v -map 1:a') && bat.include?('-map 2:s') &&
   bat.include?('-c:a aac') && bat.include?('-shortest') && bat.include?("\r\n"), 'immagini: crea_video.bat mette l\'audio da 0,7 s, con i sottotitoli')
cfg['path_video_format'] = 'avi'
cfg['path_video_audio'] = ''

# ── Finestra: audio, bozza, rifai, «poi» ─────────────────────────────
F.path_command('frames', 'Percorso 2')
vd = UI::HtmlDialog.all.last
vd.call('ready')
UI.define_singleton_method(:openpanel) { |*_a| musica }
vd.call('audio', 'pick')
st = vd.last('show')
ok(cfg['path_video_audio'] == musica && st['audio']['ok'] && st['audio']['s'] == 2.0 && st['audio']['rate'] == 8000, 'Sfoglia l\'audio: scelto, durata e Hz')
UI.define_singleton_method(:openpanel) { |*_a| File.join(tmp, 'mp3.wav') }
nb = boxes.size
vd.call('audio', 'pick')
ok(boxes.size == nb + 1 && cfg['path_video_audio'] == musica, 'un .wav che non va: lo dice, resta quello di prima')
vd.call('audio', 'clear')
ok(cfg['path_video_audio'] == '' && vd.last('show')['audio'].nil?, 'Togli: niente audio')
UI.singleton_class.send(:remove_method, :openpanel)
st = vd.last('show')
ok(st['draft']['fps'] == F::VX_DRAFT_FPS && st['draft']['total'] == 11 && st['draft']['w'] == 640 && st['draft']['h'] == 360,
   'bozza: 5 al secondo, 11 fotogrammi, a metà misura')
ok(st.values_at('quality', 'sheet', 'notify', 'level') == [90, false, false, 1] && st.key?('modified'), 'stato: qualità, foglio, suono, livello')
vd.call('set', JSON.generate('path_video_quality' => 300, 'path_video_level' => 2))
ok(cfg['path_video_quality'] == 100 && cfg['path_video_level'] == 2, 'qualità tagliata a 100, livello salvato')
vd.call('set', JSON.generate('path_video_quality' => 90, 'path_video_level' => 1))
vd.call('target', File.join(tmp, 'prova.avi'))
ok(vd.last('show')['draft']['target'].end_with?("\\prova - #{F.t('ve.draft_name').sub('%{name} - ', '')}.avi"), 'la bozza accanto, col suo nome')
vd.call('go', JSON.generate('from' => 1, 'to' => 21, 'draft' => true))
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
bozza = File.join(tmp, "prova - #{F.t('ve.draft_name').sub('%{name} - ', '')}.avi")
info = F::MjpegAvi.probe(bozza)
ok(info && info[:fps] == 5 && info[:w] == 640 && info[:index].size == 11 && !File.exist?(File.join(tmp, 'prova.avi')),
   'Esporta la bozza: un file a parte, 11 fotogrammi 640×360 a 5 al secondo; il video vero non c\'è')
ok(F.vx_log_sessions(bozza.sub(/\.avi\z/, '.log')).last['mode'] == 'draft', 'registro della bozza: tipo bozza')
ok(F.path_export_frames('Percorso 2', target: bozza, from: 3, to: 4, mode: 'patch', draft: true).nil?, 'rifai un tratto della bozza')
corri.()
ok(F::MjpegAvi.probe(bozza)[:index].size == 11 && F.vx_log_sessions(bozza.sub(/\.avi\z/, '.log')).size == 2,
   'la bozza resta di 11 fotogrammi, il registro ha due pezzi')
F.path_command('frames', 'Percorso 2')
vd = UI::HtmlDialog.all.last
vd.call('target', intero)
vd.call('go', JSON.generate('from' => 10, 'to' => 12, 'mode' => 'patch'))
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
ok(F.vx_log_sessions(File.join(tmp, 'intero.log')).last.values_at('mode', 'from', 'to') == ['patch', 10, 12] &&
   F::MjpegAvi.probe(intero)[:index].size == 21, 'Rifai dalla finestra: il video ha sempre 21 fotogrammi')
# Alla fine: suono, spegni o sospendi (qui senza toccare davvero il PC)
fatti = []
F::VxWin.singleton_class.send(:alias_method, :vero_run, :run)
F::VxWin.singleton_class.send(:alias_method, :vero_beep, :beep)
F::VxWin.singleton_class.send(:alias_method, :vero_suspend, :suspend)
F::VxWin.singleton_class.send(:alias_method, :vero_awake, :awake)
F::VxWin.define_singleton_method(:run) { |c| fatti << [:run, c] }
F::VxWin.define_singleton_method(:beep) { fatti << [:beep] }
F::VxWin.define_singleton_method(:suspend) { fatti << [:suspend] }
F::VxWin.define_singleton_method(:awake) { |on| fatti << [:awake, on] }
timers = []
UI.define_singleton_method(:start_timer) { |*_a, &bl| timers << bl; timers.size }
cfg['path_video_notify'] = true
F.path_command('frames', 'Percorso 2')
vd = UI::HtmlDialog.all.last
vd.call('target', File.join(tmp, 'spegni.avi'))
vd.call('go', JSON.generate('from' => 1, 'to' => 3, 'after' => 'shutdown'))
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
ok(fatti.first == [:awake, true] && fatti.include?([:awake, false]) && fatti.include?([:beep]), 'durante: PC sveglio; alla fine: torna normale, e un suono')
sp = fatti.find { |f| f[0] == :run }
ok(sp && sp[1].start_with?("shutdown /s /t #{F::VX_AFTER_S} /c") && sp[1].include?(F.t('ve.after_why')), 'poi spegni: shutdown di Windows fra 2 minuti')
F.vx_after_cancel
ok(fatti.last == [:run, 'shutdown /a'], 'Annulla: shutdown /a')
ok(F.vx_log_sessions(File.join(tmp, 'spegni.log')).last['cfg']['after'] == 'shutdown', 'registro: cosa si doveva fare dopo')
fatti.clear
F.path_command('frames', 'Percorso 2')
vd = UI::HtmlDialog.all.last
vd.call('target', File.join(tmp, 'dormi.avi'))
vd.call('go', JSON.generate('from' => 1, 'to' => 3, 'after' => 'sleep'))
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
ok(timers.size == 1 && !fatti.include?([:suspend]), 'poi sospendi: un timer, il PC non si sospende subito')
timers.last.call
ok(fatti.include?([:suspend]), 'allo scadere: sospende')
fatti.clear
F.path_command('frames', 'Percorso 2')
vd = UI::HtmlDialog.all.last
vd.call('target', File.join(tmp, 'dormi2.avi'))
vd.call('go', JSON.generate('from' => 1, 'to' => 3, 'after' => 'sleep'))
k = 0
k += 1 while view.anim&.nextFrame(view) && k < 1000
F.vx_after_cancel
timers.last.call
ok(!fatti.include?([:suspend]) && !fatti.any? { |f| f[0] == :run }, 'sospendi annullato: allo scadere non fa nulla')
fatti.clear
F.send(:remove_const, :PATH_BATCH); F.const_set(:PATH_BATCH, 0.0)    # un fotogramma per giro: si ferma a metà
F.path_export_frames('Percorso 2', target: File.join(tmp, 'fermo.avi'), after: 'shutdown')
2.times { view.anim.nextFrame(view) }
F::PathTool.new.onCancel(0, view)
F.send(:remove_const, :PATH_BATCH); F.const_set(:PATH_BATCH, batch)
ok(!fatti.any? { |f| f[0] == :run } && fatti.include?([:awake, false]), 'interrotto da chi è al PC: non spegne')
cfg['path_video_notify'] = false
cfg['path_video_awake'] = false
fatti.clear
F.path_export_frames('Percorso 2', target: File.join(tmp, 'zitto.avi'), from: 1, to: 2)
corri.()
ok(!fatti.include?([:beep]) && !fatti.include?([:awake, true]), 'suono e PC sveglio spenti nelle impostazioni: niente')
cfg['path_video_awake'] = true
%i[run beep suspend awake].each do |m|
  F::VxWin.singleton_class.send(:alias_method, m, :"vero_#{m}")
  F::VxWin.singleton_class.send(:remove_method, :"vero_#{m}")
end
UI.singleton_class.send(:remove_method, :start_timer)

# ── Foglio di controllo (GDI+, solo Windows) ─────────────────────────
if RUBY_PLATFORM =~ /mingw|mswin/
  F::VmGdi.start
  vera = File.join(tmp, 'vera.jpg')
  bm = F::VmGdi.bitmap(64, 36)
  gg = F::VmGdi.graphics(bm)
  F::VmGdi.clear(gg, 0xFF3080C0)
  F::VmGdi.save(bm, vera, :jpg, 80)
  F::VmGdi.delete_graphics(gg)
  F::VmGdi.dispose_image(bm)
  finta = view.method(:write_image)
  view.define_singleton_method(:write_image) { |o| finta.call(o); FileUtils.cp(vera, o[:filename]) if o[:filename].end_with?('.jpg'); true }
  cfg['path_video_sheet'] = true
  pl = F.vx_sheet_plan(21, 10, 1280, 720)
  ok(pl.values_at(:step, :every, :slots, :cols, :th) == [5, 50, 1, 1, 180], 'piano: 2 s di video → una miniatura (ogni 5 s), alta 180')
  pl = F.vx_sheet_plan(8366, 30, 1280, 720)
  ok(pl[:step] == 5 && pl[:slots] == 56 && pl[:cols] == 6 && pl[:width] == 6 + 6 * 326, '4:39 a 30 fps: ogni 5 s, 56 miniature su 6 colonne')
  F.path_export_frames('Percorso 2', target: File.join(tmp, 'foglio.avi'))
  corri.()
  png = File.join(tmp, "#{F.path_safe(F.t('ve.sheet_name').sub('%{name}', 'foglio'))}.png")
  hd = File.exist?(png) && File.binread(png, 24)
  ok(hd && hd.start_with?("\x89PNG".b) && hd.byteslice(16, 8).unpack('NN') == [332, 236], 'il foglio accanto al video: PNG 332×236 (una miniatura e il titolo)')
  ok(F.vx_log_sessions(File.join(tmp, 'foglio.log')).last['res']['sheet'] == png.tr('/', '\\'), 'registro: dov\'è il foglio')
  F.path_export_frames('Percorso 2', target: File.join(tmp, 'foglio.avi'), from: 11, to: 21, mode: 'new')
  corri.()
  ok(File.exist?(png.sub(/\.png\z/, ' 11-21.png')), 'un pezzo dall\'11: il foglio ha i numeri nel nome')
  # Il SketchUp vero chiede il primo fotogramma appena si dà l'animazione:
  # registro e foglio devono essere già pronti, se no il fotogramma 1 manca
  assegna = view.method(:animation=)
  view.define_singleton_method(:animation=) { |a| assegna.call(a); a&.nextFrame(self) }
  F.path_export_frames('Percorso 2', target: File.join(tmp, 'subito.avi'))
  corri.()
  view.singleton_class.send(:remove_method, :animation=)
  png1 = File.join(tmp, "#{F.path_safe(F.t('ve.sheet_name').sub('%{name}', 'subito'))}.png")
  ss1 = F.vx_log_sessions(File.join(tmp, 'subito.log')).last
  ok(File.exist?(png1) && ss1['n'] == 21 && ss1['last'] == 21,
     'fotogramma 1 chiesto subito: c\'è nel foglio di controllo e nel registro')
  view.singleton_class.send(:remove_method, :write_image)
  cfg['path_video_sheet'] = false
end

# ── Rinomina ed elimina dal pannello ─────────────────────────────────
UI.define_singleton_method(:inputbox) { |*_a| ['Giro del faro'] }
F.path_command('rename', 'Percorso 2')
ok(F.path_list.map { |p| p['name'] }.sort == ['Giro del faro', 'Percorso 1'], 'rinominato')
UI.define_singleton_method(:inputbox) { |*_a| ['Percorso 1'] }
F.path_command('rename', 'Giro del faro')
ok(boxes.last == F.t('path.exists'), 'nome già usato: rifiutato con un messaggio')
$answer = IDNO
F.path_command('delete', 'Percorso 1')
ok(F.path_list.size == 2, 'eliminazione non confermata: resta')
$answer = IDYES
F.path_command('delete', 'Percorso 1')
F.path_command('delete', 'Giro del faro')
ok(F.path_list.empty? && pm.attribute_dictionary(F::PATH_DICT).nil?, 'eliminati tutti: sparisce anche il dizionario')
F.path_command('play', 'Percorso 1')
ok(boxes.last == F.t('path.missing'), 'comando su un percorso che non c\'è più: messaggio')

# ── Tasto ────────────────────────────────────────────────────────────
ok(F::DEFAULT_KEYS['record'] == 0x52, 'R registra (tasto predefinito)')
ok(F::DEFAULT_KEYS['photo'] == 0x50 && F.sanitize_keys({})['photo'] == 0x50, 'P scatta una foto (tasto predefinito)')
vecchi = F::DEFAULT_KEYS.reject { |a, _| a == 'photo' }.merge('use' => 0x50)   # impostazioni di prima, con P già usato
k = F.sanitize_keys(vecchi)
ok(k['use'] == 0x50 && k['photo'] && k['photo'] != 0x50 && k.values.uniq.size == k.size && k['jump'] == F::DEFAULT_KEYS['jump'],
   "un'azione nuova col tasto già preso: ne prende uno libero (#{k['photo'] && k['photo'].chr}), gli altri restano come li si era scelti")
F.refresh_keys
ok(F.instance_variable_get(:@swallow).include?(0x52), 'in modalità FPS R non arriva a SketchUp')

puts
puts($fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI")
exit($fail.zero? ? 0 : 1)
