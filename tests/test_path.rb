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
Page = Struct.new(:name, :flags, :eye_x, :transition_time, :delay_time)
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
ok((view.camera.eye.x - s.last[1]).abs < 1e-6, 'la camera resta all\'arrivo')
F.path_start(:play, 'Percorso 1')
F::PathTool.new.onCancel(0, view)
ok(!F.path_busy? && view.anim.nil?, 'Esc ferma la riproduzione')
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
ok(view.camera.eye.x == cam0, 'la vista torna com\'era')
cfg['path_speed'] = 2.0
F.path_make_scenes('Percorso 1')
sc2 = pm.pages.select { |p| p.name.start_with?('Percorso 1 ') }
ok(sc2.size == 4 && pm.pages.size == 5 && pm.pages.first.name == 'Ingresso', 'rifatte: sostituite, le altre scene restano')
ok((sc2[1].transition_time - 0.5).abs < 1e-9, 'a velocità 2 le transizioni durano metà')
ok(boxes.last.include?('4'), 'messaggio con il numero di scene')

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
F.path_export_frames('Percorso 2')
5.times { view.anim.nextFrame(view) }
F::PathTool.new.onCancel(0, view)
b = File.binread(avi_file)
ok(b.byteslice(4, 4).unpack1('V') == b.bytesize - 8 && b.byteslice(48, 4).unpack1('V') == 5 && boxes.last.include?('giro.avi'),
   'interrotto con Esc: video di 5 fotogrammi, comunque valido')
UI.define_singleton_method(:savepanel) { |*_a| nil }
ok(F.path_export_frames('Percorso 2').nil? && !F.path_busy?, 'nessun file scelto: non parte')
small = F::MjpegAvi.new(File.join(tmp, 'vuoto.avi'), 64, 48, 25)
begin
  small.add('non un jpeg')
  ok(false, 'dati che non sono JPEG rifiutati')
rescue ArgumentError
  ok(true, 'dati che non sono JPEG rifiutati')
end
small.close
ok(File.size(File.join(tmp, 'vuoto.avi')) == 224 + 8, 'video senza fotogrammi: solo intestazione e indice vuoto')

# Più fotogrammi per giro: un write_image da 0,1 s, giro da 0,35 s → 4 per giro
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
ok(per_giro == 4, "un giro dell'animazione scrive più fotogrammi (#{per_giro}): il ridisegno fra un giro e l'altro pesa meno")
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
ok(ini && ini['strings'].keys.all? { |k| k.start_with?('att.', 'fun.') } && ini['strings']['att.stop'] == F.t('att.stop') && ini['lang'] == 'it',
   'init: solo i testi att./fun., nella lingua scelta')
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
st = F.attesa_stats(frames: ramp, name: 'rampa', dur: 10.0, speed: 1.0, fps: 30, total: 300, w: 1920, h: 1080)
ok((st['up'] - 6.0).abs < 0.3 && st['down'] < 0.3 && (st['turn'] - 720).abs < 5 && (st['kmh'] - 30.6 / 10 * 3.6).abs < 0.3,
   "rampa: #{st['up']} m in salita, #{st['down']} in discesa, sguardo girato di #{st['turn']}°, #{st['kmh']} km/h")
F.send(:remove_const, :PATH_BATCH); F.const_set(:PATH_BATCH, batch)

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
F.refresh_keys
ok(F.instance_variable_get(:@swallow).include?(0x52), 'in modalità FPS R non arriva a SketchUp')

puts
puts($fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI")
exit($fail.zero? ? 0 : 1)
