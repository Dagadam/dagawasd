# Esploratore autonomo (lib/explore.rb) in una scena finta di scatole.
#   Esecuzione:  ruby -E UTF-8 tests/test_explore.rb   (oppure tests\run_tests.bat)
# La scena (tests/support/scena.rb): due stanze con una porta, un tavolo, una
# statua, un divano e una pianta; model.raytest vero sulle scatole. Il tempo
# della simulazione è finto (30 fotogrammi al secondo), i timer di SketchUp
# si eseguono a mano, la retina ha una griglia fissa: ogni giro è uguale.
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'scena'
require 'tmpdir'
require 'net/http'
require 'zlib'
F = DagaWASD::FPSWalk
M = Scena::M
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
MF_CHECKED = 8 unless defined?(MF_CHECKED)
MF_UNCHECKED = 0 unless defined?(MF_UNCHECKED)

tmp = Dir.mktmpdir('dagawasd_esplora')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.instance_variable_set(:@settings_file, File.join(tmp, 'settings.json'))
F.load_cfg
cfg = F.instance_variable_get(:@cfg)
cfg['language'] = 'it'
F.load_lang

$timers = []
UI.define_singleton_method(:start_timer) { |*_a, &b| $timers << b if b; 1 }
def run_timers; $timers.shift.call while $timers.any?; end
$status = ''
Sketchup.define_singleton_method(:status_text=) { |s| $status = s.to_s }
$now = 1000.0
F.instance_variable_set(:@ex_clock, -> { $now })
# griglia fissa: niente adattamento al tempo vero di calcolo (che cambia da un PC all'altro)
ADATTA = F.method(:explore_adapt)
CALIBRA = F.method(:explore_calibrate)
F.define_singleton_method(:explore_adapt) { |ex| ex[:scan_ms] = ex[:scan_cpu] * 1000.0 }
F.define_singleton_method(:explore_calibrate) { |_view, _ex| nil }
# foto del pilota: in una cartella dei test, e piccole (il finto write_image traccia un raggio per pixel)
F.instance_variable_set(:@pilot_dir, File.join(tmp, 'pilota'))
F.define_singleton_method(:pilot_photo_w) { 192 }
# foto della galleria (lib/gallery.rb): anche i giri col percorso le fanno; piccole e fra i file dei test
F.instance_variable_set(:@gal_root, File.join(tmp, 'foto'))
F.define_singleton_method(:gal_photo_w) { 96 }

def ex; F.instance_variable_get(:@ex); end

# Fotogrammi a 30 al secondo finché l'animazione va; il diario completo in $diario
def run(view, secs, &blk)
  (secs * 30).round.times do
    $now += 1.0 / 30
    a = view.anim or break
    go = a.nextFrame(view)
    run_timers
    e = ex
    break unless e && go
    e[:log].each { |l| ($diario << l; $ultimo = l['n']) if l['n'] > $ultimo }
    blk&.call(e)
  end
end

def fresh(world, eye, tgt, opts = {})
  F.explore_stop if ex
  run_timers
  $diario = []; $ultimo = 0
  model, view, cam = Scena.setup(world, eye, tgt)
  err = F.explore_start({ 'frame_ms' => 40 }.merge(opts))
  # le fette si misurano a tempo vero: col computer carico un'analisi
  # scivolerebbe sul fotogramma dopo e il giro cambierebbe. Qui ogni analisi
  # (e ogni ricerca di percorso) sta in un fotogramma; le fette si provano a parte
  ex[:slice] = 1e9 if ex
  [model, view, cam, err]
end

# ── Opzioni ──────────────────────────────────────────────────────────
o = F.explore_opts('speed' => '9', 'mode' => 'salta', 'heatmap' => 'false', 'grid' => 20.7, 'boh' => 1, 'record' => true)
ok(o['speed'] == 4.0 && o['mode'] == 'auto' && o['heatmap'] == false && o['grid'] == 21 && !o.key?('boh') && o['record'],
   'opzioni ripulite: intervalli, scelte, interi, sconosciute scartate')
cfg['explore'] = { 'speed' => 1.6, 'dwell' => 'x' }
o = F.explore_opts('dwell' => 0.5)
ok(o['speed'] == 1.6 && o['dwell'] == 0.5, 'settings.json ("explore") e poi le opzioni della chiamata')
cfg.delete('explore')
o = F.explore_opts(nil)
ok(o.reject { |k, _| k == 'profile' } == F::EX_DEFAULTS && o['profile'] == 'balanced', 'senza nulla: i predefiniti (profilo Equilibrato)')

# ── Colore e geometria della retina ──────────────────────────────────
w = F.explore_lab(255, 255, 255); r = F.explore_lab(255, 0, 0)
ok((w[0] - 100).abs < 0.1 && w[1].abs < 0.1 && (r[0] - 53.2).abs < 0.3 && (r[1] - 80.1).abs < 0.5, "Lab: bianco #{w.map { |v| v.round(1) }}, rosso #{r.map { |v| v.round(1) }}")

world, objs = Scena.due_stanze
model, view, cam = Scena.setup(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7])
rays = F.explore_rays(view, 32, 18)
err = rays.each_with_index.map do |(o2, d), i|
  _, q = view.pickray((i % 32 + 0.5) * 640 / 32.0, (i / 32 + 0.5) * 360 / 18.0)
  Math.acos([[d.x * q.x + d.y * q.y + d.z * q.z, 1.0].min, -1.0].max) + (o2.distance(cam.eye))
end.max
ok(rays.size == 576 && err < 1e-6, "576 raggi da 3 pickray: esatti come pickray cella per cella (scarto #{err.round(9)})")

ctx = { memo: {}, omemo: {}, size: {}, fseq: 0, oseq: 0, t: 0.0, dflt: F.explore_default_colors(model) }
tutte = F.explore_cast(model, rays, ctx)
ctx2 = { memo: {}, omemo: {}, size: {}, fseq: 0, oseq: 0, t: 0.0, dflt: F.explore_default_colors(model) }
fib = Fiber.new { F.explore_cast(model, rays, ctx2, 0.0) }
giri = 0
res = nil
while fib.alive?
  res = fib.resume
  giri += 1
end
ok(giri >= 500 && res.size == 576 && res.each_with_index.all? { |c, i| (c.nil? && tutte[i].nil?) || (c && c.p.distance(tutte[i].p) < 1e-9) },
   "a fette nella Fiber (#{giri} riprese con budget 0): stesse celle di un colpo solo")
ok(tutte.compact.size == 576 && tutte.count { |c| c.obj == objs[:tavolo] } > 5, 'ogni raggio colpisce; il tavolo occupa più celle')

sal = F.explore_saliency(tutte, 32, 18, rays: rays, walk: true)
best = sal[:cands].first
ok(best && best[:obj] == objs[:tavolo] && best[:label] == 'Tavolo', "il punto più significativo è il tavolo (#{best && best[:label]} #{best && best[:score].round(2)})")
pt = best[:pt].map { |v| v / M }
ok(pt[0].between?(-4.7, -3.3) && pt[1].between?(1.5, 2.5) && pt[2].between?(0.0, 0.8), "il punto sta sul tavolo #{pt.map { |v| v.round(2) }}")
muri = sal[:cands].reject { |c| c[:obj] || c[:open] }
ok(muri.all? { |c| c[:score] < best[:score] * 0.5 }, 'pareti e pavimento valgono meno della metà del tavolo')
ok(F.explore_small(0.1) == 1.0 && F.explore_small(12.0) == 0.0, 'facce piccole contano, pareti grandi no')
ok(sal[:f].each_with_index.all? { |v, i| tutte[i] || v.zero? }, 'il vuoto non ha salienza')

# ── Retina dinamica: la fovea ───────────────────────────────────────
u, wu, bu = F.explore_fovea_axis(32, 0.3, 0.0)
ok(u.each_with_index.all? { |v, k| (v - (k + 0.5) / 32).abs < 1e-12 } && wu.all? { |v| v == 1.0 } && bu.size == 33,
   'fovea spenta: la retina uniforme di sempre')
u, wu, bu = F.explore_fovea_axis(32, 0.3, 1.5)
fine = wu.each_with_index.min_by { |v, _| v }[1]
ok(u.each_cons(2).all? { |a, b| b > a } && bu.first.abs < 1e-9 && (bu.last - 1.0).abs < 1e-9 && (wu.sum - 32).abs < 1e-6 &&
   (u[fine] - 0.3).abs < 0.04 && (wu.max / wu.min).between?(2.3, 2.5),
   "fovea a 0,3: celle più fitte lì (#{(u[fine]).round(2)}), #{(wu.max / wu.min).round(1)} volte più strette che ai margini")
tav_pt = best[:pt]
fx = view.screen_coords(Geom::Point3d.new(*tav_pt)).x / 640.0
geo = F.explore_geo(view, { o: { 'fovea' => 1.5 }, target: { pt: tav_pt }, look: nil }, 32, 18)
ok((geo[:fx] - fx.clamp(F::EX_FOVEA_EDGE, 1 - F::EX_FOVEA_EDGE)).abs < 1e-9 &&
   F.explore_geo(view, { o: { 'fovea' => 1.5 }, target: nil }, 32, 18)[:fx] == 0.5,
   "la fovea sta sull'obiettivo (x #{geo[:fx].round(2)} dello schermo), senza obiettivo al centro")
rf = F.explore_rays(view, 32, 18, geo)
err = rf.each_with_index.map do |(o2, d), i|
  _, q = view.pickray(geo[:ux][i % 32] * 640, geo[:vy][i / 32] * 360)
  Math.acos([[d.x * q.x + d.y * q.y + d.z * q.z, 1.0].min, -1.0].max) + o2.distance(cam.eye)
end.max
ok(err < 1e-6, "raggi della fovea esatti come pickray nei punti spostati (scarto #{err.round(9)})")
tf = F.explore_cast(model, rf, ctx)
sf = F.explore_saliency(tf, 32, 18, rays: rf, walk: true, geo: geo)
bf = sf[:cands].first
celle = ->(cs) { cs.count { |c| c && c.obj == objs[:tavolo] } }
ok(bf && bf[:label] == 'Tavolo' && celle.(tf) > celle.(tutte) * 1.5 && (bf[:area] / best[:area]).between?(0.7, 1.4),
   "con la fovea sul tavolo: #{celle.(tf)} celle invece di #{celle.(tutte)}, ma la sua parte di vista resta quella " \
   "(#{(bf[:area] * 100).round(1)}% contro #{(best[:area] * 100).round(1)}%) e resta il più significativo")

# ── Retina dinamica: il budget segue i fotogrammi ───────────────────
bud = ->(other, opts = {}) { e = { o: F.explore_opts(opts), fr_other: other, slice: 6.0, scan_goal: 40.0 }; F.explore_budget(e); e }
leggero = bud.(5.0)
pesante = bud.(110.0)
fisso = bud.(5.0, 'adaptive' => false)
ok(leggero[:slice] > 25.0 && leggero[:scan_goal] > 200.0 && pesante[:slice].between?(15.0, 18.0) &&
   pesante[:scan_goal].between?(30.0, 60.0) && fisso[:slice] == 6.0 && fisso[:scan_goal] == 40.0,
   "budget: fotogrammi da 5 ms → #{leggero[:slice].round(1)} ms per fotogramma, #{leggero[:scan_goal].round} per analisi; " \
   "da 110 ms → #{pesante[:slice].round(1)} e #{pesante[:scan_goal].round}; adaptive spento: fisso")

# ── Cadenza adattiva (pannello › Sistema › Prestazioni) ─────────────
# Accesa: analisi al secondo secondo il calcolo che le fette lasciano, fra il
# minimo e il massimo; spenta: una per passo, e il budget com'era.
cad = ->(other, cell_ms) do
  e = { o: F.explore_opts, fr_other: other, slice: 6.0, scan_goal: 40.0, cell_ms: cell_ms, aspect: 0.5625 }
  F.explore_budget(e)
  e
end
cfg.merge!('explore_scan_adaptive' => true, 'explore_scan_hz_min' => 1.0, 'explore_scan_hz_max' => 6.0)
leggera = cad.(5.0, 0.02)       # 32×18 celle da 0,02 ms: c'è calcolo per molte più analisi
pesa = cad.(110.0, 2.0)         # celle da 2 ms su fotogrammi da 110 ms: nemmeno una al secondo
media = cad.(20.0, 0.15)
ok(leggera[:hz] == 6.0 && pesa[:hz] == 1.0 && media[:hz].between?(1.0, 6.0) && media[:hz] > 1.5 && media[:hz] < 5.5,
   "cadenza adattiva: modello leggero #{leggera[:hz]}/s (il massimo), pesante #{pesa[:hz]}/s (il minimo), " \
   "medio #{media[:hz].round(2)}/s")
ok((leggera[:scan_goal] - 0.7 * 1000.0 * leggera[:slice] / (5.0 + leggera[:slice]) / 6.0).abs < 1e-6 &&
   pesa[:scan_goal] > pesante[:scan_goal],
   "…la retina sta nell'intervallo: #{leggera[:scan_goal].round} ms a 6/s; al minimo più larga del passo " \
   "(#{pesa[:scan_goal].round} contro #{pesante[:scan_goal].round} ms), quindi si dirada solo sotto il minimo")
cfg['explore_scan_hz_min'] = 8.0
ok(cad.(5.0, 0.02)[:hz] == 8.0 && F.explore_hz_limits == [6.0, 8.0], '…minimo oltre il massimo: si scambiano')
cfg['explore_scan_adaptive'] = false
spenta = cad.(5.0, 0.02)
ok((spenta[:hz] - 1.0 / F.explore_opts['step_time']).abs < 1e-9 && (spenta[:scan_goal] - leggero[:scan_goal]).abs < 1e-6,
   "…spenta: una analisi per passo (#{spenta[:hz].round(2)}/s) e lo stesso budget di prima")
cfg.merge!('explore_scan_hz_min' => 1.0)
fr = { fr_at: F.explore_cpu - 0.02, fr_slice: 5.0, fr_other: nil }
F.explore_frame_time(fr)
lungo = { fr_at: F.explore_cpu - 2.0, fr_slice: 0.0, fr_other: 12.0 }
F.explore_frame_time(lungo)
ok(fr[:fr_other].between?(14.0, 40.0) && fr[:fr_slice].zero? && lungo[:fr_other] == 12.0,
   "fotogramma da 20 ms con 5 di calcolo: #{fr[:fr_other].round(1)} ms di resto; un'attesa lunga non conta")

# ── Avvio ────────────────────────────────────────────────────────────
F.instance_variable_set(:@active, true)
ok(F.explore_start == F.t('rt.explore_busy') && ex.nil?, 'con la camminata FPS attiva non parte')
F.instance_variable_set(:@active, false)
F.instance_variable_set(:@bridge_job, {})
ok(F.explore_start == F.t('rt.explore_busy') && ex.nil?, 'mentre il ponte costruisce dal vivo non parte')
F.instance_variable_set(:@bridge_job, nil)

model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7])
ok(err.nil? && ex && ex[:mode] == :walk && model.tool.is_a?(F::ExploreTool) && view.anim.is_a?(F::ExploreAnimation),
   'parte: a piedi (pavimento sotto gli occhi), strumento e animazione')
run(view, 1.0) { |e| break if e[:target] }      # la prima analisi può chiedere qualche fotogramma in più
ok(ex[:target] && ex[:target][:label] == 'Tavolo' && $diario.first['why'] == 'nuovo', 'prima analisi, primo obiettivo: il tavolo')
yaw0 = ex[:yaw]
run(view, 1.0)
gy = Math.atan2(ex[:target][:pt][1] - ex[:y], ex[:target][:pt][0] - ex[:x])
ok(F.explore_wrap(gy - ex[:yaw]).abs < F.explore_wrap(gy - yaw0).abs, 'lo sguardo si gira verso il tavolo')

# fino al tavolo: si ferma a distanza di osservazione e lo guarda
tav = objs[:tavolo].bounds
fuori = true
run(view, 8.0) do |e|
  x = e[:x]; y = e[:y]
  fuori &&= !(x > tav.min.x - 5 && x < tav.max.x + 5 && y > tav.min.y - 5 && y < tav.max.y + 5)
end
arr = $diario.find { |l| l['why'] == 'raggiunto' && l['label'] == 'Tavolo' }
ok(arr && arr['dist_m'].between?(1.1, 2.6), "raggiunge il tavolo e si ferma a #{arr && arr['dist_m']} m")
ok(fuori, 'mai dentro il tavolo')
ok((ex[:z] / M - 1.7).abs < 0.02, "occhi a #{(ex[:z] / M).round(3)} m dal pavimento (impostazione eye_height)")
dopo = $diario.find { |l| l['why'] == 'nuovo' && l['n'] > arr['n'] }
ok(dopo && dopo['label'] != 'Tavolo', "poi cerca altro (#{dopo && dopo['label']}): inibizione del ritorno")

# ── Un giro lungo: tutte e due le stanze, mai dentro un muro ─────────
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7])
dentro = []
porta = []
prev_x = nil
run(view, 75.0) do |e|
  x = e[:x] / M; y = e[:y] / M
  world.boxes.each do |b|
    next if b.max[2] / M < 0.3 || b.min[2] / M > 1.6         # pavimento, soffitto
    pad = 0.08
    dentro << [x.round(2), y.round(2)] if x > b.min[0] / M - pad && x < b.max[0] / M + pad && y > b.min[1] / M - pad && y < b.max[1] / M + pad
  end
  porta << y.round(2) if prev_x && (prev_x <=> 0) != (x <=> 0)
  prev_x = x
end
visti = $diario.select { |l| l['why'] == 'raggiunto' }.map { |l| l['label'] }.uniq & %w[Tavolo Statua Divano Pianta]
ok(visti.size >= 3, "in 75 s raggiunge #{visti.size} oggetti su 4: #{visti.join(', ')}")
ok(dentro.empty?, "mai dentro un muro o un oggetto#{dentro.empty? ? '' : ": #{dentro.first(3).inspect}"}")
ok(!porta.empty? && porta.all? { |y| y.abs < 0.7 }, "passa dall'altra stanza, sempre dalla porta (y = #{porta.first(4).inspect})")
ok($diario.count { |l| l['why'] == 'intorno' } < 20, 'non resta a girare su se stesso')

# ── Registrazione: il giro diventa un percorso ──────────────────────
nome = F.explore_stop
run_timers
d = model.attribute_dictionary(F::PATH_DICT)
dati = d && JSON.parse(d[nome])
ok(nome == 'Esplorazione 1' && dati && dati['s'].size > 75 * 29 && dati['s'].all? { |s| s.size == 11 },
   "salvato come «#{nome}», #{dati && dati['s'].size} campioni [t, occhio, direzione, alto, fov]")
ok(model.ops.include?([:start, F.t('path.op_save')]) && model.ops.last == [:commit], 'un\'operazione annullabile, come la registrazione a mano')
fr = F.path_frames(dati['s'])
ok(fr.size > 2000 && (dati['s'].last[0] - 75.0).abs < 0.1, 'i percorsi lo riproducono (fotogrammi levigati)')
ok(ex.nil? && view.anim.nil? && model.tool.nil? && $status.include?(nome), 'fermo: niente animazione né strumento, la riga di stato dice il percorso')

# ── A piedi: precipizio e scale ─────────────────────────────────────
alto = Scena::World.new
pav = Scena::Mat.new('Pavimento', [190, 186, 178])
alto.box([-6, -6, -0.1], [6, 6, 0], pav)
alto.box([-6, -3, 0], [0, 3, 1.5], Scena::Mat.new('Terrazza', [210, 200, 180]))     # terrazza alta 1,5 m, bordo a x = 0
vaso = Scena::Inst.new('Vaso')
alto.box([2.5, -0.3, 0], [3.1, 0.3, 0.9], Scena::Mat.new('Rosso', [200, 40, 40]), vaso)
model, view, cam, err = fresh(alto, [-3, 0, 3.2], [3, 0, 0.5], 'attention' => 12)
zmin = 99.0
xmax = -99.0
run(view, 20.0) { |e| zmin = [zmin, e[:z] / M].min; xmax = [xmax, e[:x] / M].max }
ok(xmax < 0.0 && zmin > 3.0, "dal bordo della terrazza non si butta (x max #{xmax.round(2)}, occhi mai sotto #{zmin.round(2)} m)")
ok($diario.any? { |l| l['label'] == 'Vaso' }, 'il vaso di sotto lo guarda lo stesso')

scala = Scena::World.new
scala.box([-6, -6, -0.1], [8, 6, 0], pav)
5.times { |k| scala.box([0 + k * 0.3, -2, 0], [8, 2, 0.18 * (k + 1)], Scena::Mat.new('Gradino', [170, 170, 175])) }
busto = Scena::Inst.new('Busto')
scala.box([4.6, -0.2, 0.9], [5.0, 0.2, 1.6], Scena::Mat.new('Bronzo', [150, 90, 40]), busto)
model, view, cam, err = fresh(scala, [-4, 0, 1.7], [4.8, 0, 1.2])
fmax = 0.0
run(view, 15.0) { |e| fmax = [fmax, e[:floor] / M].max }
ok(fmax > 0.85, "sale le scale fino al busto (pavimento a #{fmax.round(2)} m)")

# ── In volo: da una vista aerea si atterra dove c'è qualcosa da vedere ──
model, view, cam, err = fresh(world, [-14, -12, 9], [2, 0, 0])
ok(ex[:mode] == :fly, 'niente pavimento sotto la vista aerea: in volo')
zfly = []
run(view, 40.0) { |e| zfly << e[:z] / M if e[:mode] == :fly }
ok(ex[:mode] == :walk && (ex[:z] / M - 1.7).abs < 0.05, "atterra e prosegue a piedi (occhi a #{(ex[:z] / M).round(2)} m)")
ok($diario.any? { |l| l['why'] == 'raggiunto' && %w[Tavolo Statua Divano Pianta].include?(l['label']) }, 'e raggiunge un oggetto')

# ── Comandi, stato, fine ────────────────────────────────────────────
st = F.explore_status
ok(st['on'] && JSON.parse(JSON.generate(st))['mode'] == 'walk' && st['scan']['rays'] == 576, 'stato in JSON per il ponte')
ok(F.explore_command('pause')['paused'] && view.anim.nil?, 'pausa: l\'animazione si stacca')
cam.set(Geom::Point3d.new(-6 * M, -4 * M, 1.7 * M), Geom::Point3d.new(0, -4 * M, 1.7 * M), Geom::Vector3d.new(0, 0, 1))
r = F.explore_command('resume')
ok(!r['paused'] && view.anim && (ex[:x] / M + 6).abs < 1e-6, 'riprende da dove hai messo la camera')
run(view, 0.5)
lbl = ex[:target] && ex[:target][:label]
F.explore_command('next')
ok(ex[:target].nil? && ex[:log].last['why'] == 'saltato' && ex[:log].last['label'] == lbl, "«Cerca altro» lascia #{lbl}")
ok(F.explore_command('heatmap', false)['heatmap'] == false && F.explore_command('heatmap')['heatmap'] == true, 'mappa dell\'attenzione: spegni, accendi')
ok(F.explore_command('speed', 9)['speed'] == 4.0, 'velocità limitata a 4 m/s')
ok(F.explore_command('vola')['ok'] == false, 'comando sconosciuto: errore')

run(view, 1.0)
view.drawn.clear
F.explore_draw(view)
pts = view.drawn.select { |x| x[0] == :points }
ok(pts.size >= 3 && view.drawn.any? { |x| x[0] == :text }, "disegno: mappa, obiettivo, scritte (#{pts.size} gruppi di punti)")
info = ->(v) { v.drawn.select { |x| x[0] == :text && x[3] < 60 && x[2] < 20 }.map { |x| x[1] } }
righe = info.(view)
tool = F::ExploreTool.new
eaten = tool.onKeyDown(73, 1, 0, view)
tool.onKeyDown(73, 2, 0, view)       # tasto tenuto: non scambia di nuovo
view.drawn.clear
F.explore_draw(view)
spente = info.(view)
ok(righe == [F.explore_hud_text(ex), F.explore_hud_colors(ex)] && eaten && spente.empty? && F.explore_status['info'] == false &&
   view.drawn.any? { |x| x[0] == :text }, "I: righe in alto a sinistra via (#{righe.size} → #{spente.size}), il resto resta")
tool.onKeyDown(105, 1, 0, view)
view.drawn.clear
F.explore_draw(view)
ok(info.(view).size == 2 && F.explore_status['info'] == true && tool.onKeyDown(74, 1, 0, view) == false, 'I di nuovo: tornano; altri tasti non presi')
bb = F.explore_extents
ok(!bb.empty? && bb.max.x > bb.min.x, 'getExtents: l\'ingombro di ciò che si disegna')

class Menu
  attr_reader :items, :procs
  def initialize; @items = []; @procs = {}; end
  def add_item(n, &b); @items << [n, b]; @items.size; end
  def add_separator; @items << ['—', nil]; end
  def set_validation_proc(i, &b); @procs[i] = b; end
  def add_submenu(n); m = Menu.new; @items << [n, m]; m; end
end
mn = Menu.new
F.explore_menu(mn)
ok(mn.items.map(&:first) == [F.t('explore.pause'), F.t('explore.next'), '—', F.t('explore.map'), F.t('explore.pixels'), '—', F.t('explore.stop'),
                             '—', F.t('explore.profile'), F.t('explore.profiles')] &&
   mn.procs[4].call == MF_CHECKED && mn.procs[5].call == MF_UNCHECKED, 'tasto destro: pausa, cerca altro, mappa (spuntata), occhio a colori, ferma, profilo')
pm = mn.items[8][1]
ok(pm.items.map(&:first) == F.explore_profile_list.map { |p| p['name'] } && pm.procs[1].call == MF_CHECKED && pm.procs[2].call == MF_UNCHECKED,
   "sottomenu Profilo: #{pm.items.size} profili, spuntato quello in uso")

F.explore_wheel(1)
ok((ex[:speed] - 4.0).abs < 1e-9, 'rotella: velocità (già al massimo)')
model.tool.onCancel(0, view)
run_timers
ok(ex.nil?, 'Esc ferma')

model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'duration' => 2, 'record' => false)
run(view, 5.0)
ok(ex.nil? && model.dicts.empty?, 'duration: si ferma da solo; record spento: nessun percorso')

# Retina a misura del modello: raggi cari (come il terreno di certi modelli
# vero, decine di ms) → la prima retina è già piccola; raggi a buon mercato → resta
model, view, cam = Scena.setup(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7])
lento = { model: model, o: F.explore_opts, gw_f: 32.0, gw: 32, scan_goal: 40.0 }
model.define_singleton_method(:raytest) { |r, w = true| sleep 0.004; super(r, w) }
CALIBRA.call(view, lento)
veloce = { model: Scena.setup(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7])[0], o: F.explore_opts, gw_f: 32.0, gw: 32, scan_goal: 40.0 }
CALIBRA.call(view, veloce)
# (tempo vero: col computer carico anche i raggi veloci costano un po', la retina resta comunque grande)
ok(lento[:gw] == 12 && veloce[:gw] >= 24, "taratura: raggi da 4 ms → retina #{lento[:gw]}, raggi veloci → #{veloce[:gw]}")
a = { o: F.explore_opts, gw_f: 32.0, gw: 32, scan_cpu: 6.0, scan_goal: 40.0 }
ADATTA.call(a)
b = { o: F.explore_opts, gw_f: 20.0, gw: 20, scan_cpu: 0.001, scan_goal: 40.0 }
ADATTA.call(b)
ok(a[:gw] == 16 && b[:gw] == 25, "analisi da 6 s: la retina si dimezza (#{a[:gw]}); a buon mercato si allarga piano (#{b[:gw]})")

# Le sfere delle posizioni dei percorsi (lib/pathkeys.rb) non si vedono e non
# si guardano mentre esplora; poi tornano come erano
model, view, cam = Scena.setup(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7])
tag = model.layers[F::KEY_TAG] = Scena::Layer.new(F::KEY_TAG, true)
F.explore_start('record' => false)
spento = !tag.visible?
F.explore_stop
ok(spento && tag.visible?, 'sfere dei percorsi spente durante l\'esplorazione, riaccese alla fine')
tag.visible = false
F.explore_start('record' => false)
F.explore_stop
ok(!tag.visible?, 'tag già spento da te: resta spento')
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false)
run(view, 0.5)
model.select_tool(nil)
ok(ex.nil?, 'un altro strumento: si ferma')
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false)
view.animation = Object.new
run_timers
ok(ex.nil?, 'un\'altra animazione (una scena): si ferma')
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false)
F.start
ok(ex.nil?, 'la camminata FPS lo ferma')
F.stop if F.instance_variable_get(:@active)   # la camminata non resta accesa per le prove dopo
run_timers

# ── Occhio a colori: BMP e salienza dei pixel ───────────────────────
f24 = File.join(tmp, 'a.bmp')
px = (0...24).map { |y| (0...32).map { |x| x.between?(20, 25) && y.between?(4, 9) ? [30, 30, 220].pack('C3') : [128, 128, 128].pack('C3') }.join }
Scena.bmp24(f24, 32, 24, px.reverse.join)
img = F.explore_bmp(File.binread(f24))
ok(img && img[:w] == 32 && img[:h] == 24 && img[:rgb][(5 * 32 + 21) * 3, 3] == [220, 30, 30] && img[:rgb][0, 3] == [128, 128, 128],
   'BMP a 24 bit dal basso: righe e canali al loro posto')
f32 = File.join(tmp, 'b.bmp')
Scena.bmp24(f32, 2, 2, [[1, 2, 3, 255], [4, 5, 6, 255], [7, 8, 9, 255], [10, 11, 12, 255]].map { |c| c.pack('C4') }.join, top_down: true, bpp: 32)
img2 = F.explore_bmp(File.binread(f32))
ok(img2 && img2[:rgb] == [3, 2, 1, 6, 5, 4, 9, 8, 7, 12, 11, 10], 'BMP a 32 bit dall\'alto')
ok(F.explore_bmp('PNG...') .nil?, 'non BMP: nil')
pm = F.explore_pixel_map(img, 8, 6)
top = pm.each_with_index.max_by { |v, _| v }[1]
ok([top % 8, top / 8].then { |cx, cy| cx.between?(5, 6) && cy.between?(1, 2) }, "il quadrato rosso è la cella più saliente (#{top % 8}, #{top / 8})")

model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'pixels' => true, 'record' => false)
run(view, 1.0)
ok(view.images >= 1 && ex[:px_ms] && ex[:res] && ex[:res][:hits] > 0 && ex[:target], "con l'occhio a colori: #{view.images} immagini, analisi e obiettivo")
ex[:pixels] = true    # l'immagine finta può passare EX_PX_MAX_MS sotto carico
ex[:px_off] = nil
ex[:px_ms] = 50.4
ok(F.explore_hud_colors(ex) == "#{F.t('explore.colors_view')} 50 ms", "riquadro: #{F.explore_hud_colors(ex)}")
# immagine troppo lenta: si spegne da solo, ma il perché resta nel menu e nel riquadro
cpu = F.method(:explore_cpu)
tick = 0.0
F.define_singleton_method(:explore_cpu) { tick += 0.3 }
F.explore_grab(view, ex)
F.define_singleton_method(:explore_cpu, cpu)
mn = Menu.new
F.explore_menu(mn)
ok(!ex[:pixels] && ex[:px_off].round == 300 && mn.items[4][0] == format(F.t('explore.pixels_slow'), ms: 300) && mn.procs[5].call == MF_UNCHECKED &&
   F.explore_hud_colors(ex) == "#{F.t('explore.colors_model')} · #{format(F.t('explore.colors_slow'), ms: 300)}" &&
   F.explore_status['pixels_off_ms'] == 300, "occhio a colori spento da solo: «#{mn.items[4][0]}», «#{F.explore_hud_colors(ex)}»")
F.explore_command('pixels')
mn = Menu.new
F.explore_menu(mn)
ok(ex[:pixels] && ex[:px_off].nil? && mn.items[4][0] == F.t('explore.pixels') && mn.procs[5].call == MF_CHECKED,
   'riacceso dal menu: spuntato, il motivo sparisce')
F.explore_command('pixels', false)
ok(F.explore_hud_colors(ex) == F.t('explore.colors_model'), "spento a mano: #{F.explore_hud_colors(ex)}")
F.explore_stop

# ── Ponte per Claude: GET/POST /explore ─────────────────────────────
F.instance_variable_set(:@bridge_file, File.join(tmp, 'bridge.json'))
cfg = F.instance_variable_get(:@cfg)      # F.start ha ricaricato le impostazioni
cfg['bridge_enabled'] = true
F.bridge_sync
info = JSON.parse(File.read(File.join(tmp, 'bridge.json')))
def call(info, req)
  req['X-Token'] = info['token']
  res = nil
  th = Thread.new { res = Net::HTTP.start('127.0.0.1', info['port'], read_timeout: 10) { |h| h.request(req) } }
  deadline = Time.now + 10
  while th.alive? && Time.now < deadline
    F.bridge_poll
    sleep 0.01
  end
  th.join(1)
  res
end
post = lambda do |h|
  r = Net::HTTP::Post.new('/explore')
  r.body = JSON.generate(h)
  r
end
body = ->(r) { JSON.parse(r.body.force_encoding('UTF-8')) }
model, view, cam = Scena.setup(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7])
$diario = []; $ultimo = 0
r = call(info, Net::HTTP::Get.new('/explore'))
ok(r.code == '200' && body[r]['on'] == false, 'GET /explore: fermo')
r = call(info, post.(cmd: 'start', opts: { speed: 1.4, record: false }))
ok(r.code == '200' && body[r]['on'] && body[r]['speed'] == 1.4, 'POST start con opzioni: parte')
run(view, 1.0)
r = call(info, Net::HTTP::Get.new('/explore'))
b = body[r]
ok(b['target'] && b['target']['label'] == 'Tavolo' && b['candidates'].any? && b['log'].any?, "GET: obiettivo #{b['target'] && b['target']['label']}, candidati, diario")
r = call(info, Net::HTTP::Get.new('/explore/percept?since=0&n=3'))
pc = body[r]
tav = pc['things'] && pc['things'].find { |t| t['label'] == 'Tavolo' }
ok(r.code == '200' && tav && pc['things'].size <= 3 && pc['agenda'] == [], "GET /explore/percept: il tavolo è #{tav && tav['id']}")
r = call(info, post.(cmd: 'steer', opts: { agenda: [{ look: tav['id'], for: 0.5 }] }))
ok(r.code == '200' && body[r]['agenda'].size == 1 && body[r]['rejected'].empty?, 'POST steer: in agenda')
run(view, 2.0)
r = call(info, Net::HTTP::Get.new("/explore/percept?since=#{pc['ev_n']}&brief=1"))
ok((%w[arrived photo] - body[r]['events'].map { |e| e['type'] }).empty? && body[r]['wake'] && !body[r].key?('things'),
   'GET /explore/percept?brief=1: solo gli avvisi (arrivato, foto), e svegliano il pilota')
# attesa lunga: il ponte risponde quando c'è un avviso che sveglia, intanto l'esploratore va
attesa = lambda do |path|
  req = Net::HTTP::Get.new(path)
  req['X-Token'] = info['token']
  res = nil
  th = Thread.new { res = Net::HTTP.start('127.0.0.1', info['port'], read_timeout: 30) { |h| h.request(req) } }
  giri = 0
  while th.alive? && giri < 600
    F.bridge_poll
    run(view, 1.0 / 30) if ex
    giri += 1
    sleep 0.005
  end
  th.join(2)
  [res, giri]
end
n0 = F.explore_percept(0, nil, true)['ev_n']
r, = attesa.("/explore/wait?since=#{n0}&timeout=0")
ok(r && body[r]['timeout'] && body[r]['things'], 'GET /explore/wait con timeout 0: risponde subito, senza avvisi')
r, = attesa.("/explore/wait?since=#{n0}&timeout=20&run=altro")
ok(r && body[r]['new_run'] && body[r]['run'] == ex[:run], 'un giro diverso da quello del pilota: subito, da capo')
call(info, post.(cmd: 'steer', opts: { agenda: [{ look: tav['id'], for: 0.3 }] }))
r, giri = attesa.("/explore/wait?since=#{n0}&timeout=20&run=#{ex[:run]}")
tipi = r ? body[r]['events'].map { |e| e['type'] } : []
# una sola voce data adesso dall'IA: niente «agenda quasi vuota», la sveglia è la foto della sosta
ok(r && !body[r]['timeout'] && tipi.include?('photo') && !tipi.include?('agenda_low') && giri > 5,
   "GET /explore/wait: aspetta (#{giri} giri del timer) e risponde con la foto (#{tipi.join(', ')})")
# chi aspettava e se ne va libera il posto
via = Array.new(F::BRIDGE_WAITS) do
  so = TCPSocket.new('127.0.0.1', info['port'])
  so.write("GET /explore/wait?since=#{ex[:ev_seq]}&timeout=200 HTTP/1.1\r\nX-Token: #{info['token']}\r\nHost: x\r\n\r\n")
  so
end
20.times { F.bridge_poll; sleep 0.01 }
pieni = F.instance_variable_get(:@bridge_waits).size
via.each(&:close)
5.times { F.bridge_poll; sleep 0.01 }
ok(pieni == F::BRIDGE_WAITS && F.instance_variable_get(:@bridge_waits).empty?,
   "attese di client andati via: tolte (#{pieni} in sospeso, poi #{F.instance_variable_get(:@bridge_waits).size})")
r = call(info, post.(cmd: 'stop'))
ok(body[r]['on'] == false && ex.nil?, 'POST stop: fermo')
bad = Net::HTTP::Post.new('/explore'); bad.body = 'non json'
r = call(info, bad)
ok(r.code == '400', 'corpo non JSON: 400')
cfg['bridge_enabled'] = false
F.bridge_sync

# ── Salto: un muretto che sbarra tutta la stanza ────────────────────
# Il giocatore salta di v²/2g = 4,6²/19,6 = 1,08 m: un muretto di 60 cm si
# scavalca, uno di 1,3 m no. Oltre il muretto, una statua da vedere.
muretto = lambda do |h|
  w = Scena::World.new
  w.box([-8, -4, -0.1], [8, 4, 0], pav)
  w.box([-0.1, -4, 0], [0.1, 4, h], Scena::Mat.new('Pietra', [150, 150, 150]))
  s = Scena::Inst.new('Statua')
  w.box([4.7, -0.3, 0], [5.3, 0.3, 0.9], Scena::Mat.new('Marmo', [228, 228, 222]), s)
  w.box([4.85, -0.15, 0.9], [5.15, 0.15, 1.9], Scena::Mat.new('Bronzo rosso', [178, 40, 34]), s)
  w
end
salta = lambda do |h, opts = {}|
  model, view, cam, err = fresh(muretto.(h), [-3, 0, 1.7], [5, 0, 1.4], { 'record' => false }.merge(opts))
  xmax = -99.0
  dentro = false
  occhi = []
  run(view, 25.0) do |e|
    xmax = [xmax, e[:x] / M].max
    dentro ||= (e[:x] / M).abs < 0.1 + 0.25 && e[:z] / M - 1.7 < h - 0.05 && !e[:jump]
    occhi << (e[:z] - e[:floor]) / M if e[:mode] == :walk && !e[:jump] && e[:floor]
  end
  r = { xmax: xmax, salti: ex[:jumps], diario: $diario.count { |l| l['why'] == 'salto' }, dentro: dentro, occhi: occhi.last(30) }
  F.explore_stop
  r
end
r = salta.(0.6)
ok(r[:salti] >= 1 && r[:diario] >= 1 && r[:xmax] > 1.0 && !r[:dentro],
   "muretto di 60 cm sulla strada: lo salta (#{r[:salti]} salti, fino a x #{r[:xmax].round(2)} m), mai dentro")
ok(r[:occhi].all? { |o| (o - 1.7).abs < 0.03 }, "dopo il salto, a piedi, occhi a 1,7 m dal pavimento come il giocatore")
r = salta.(1.3)
ok(r[:salti].zero? && r[:xmax] < 0.0, "muretto di 1,3 m: troppo alto per il salto del giocatore, resta di qua (x max #{r[:xmax].round(2)})")
r = salta.(0.6, 'jump' => false)
ok(r[:salti].zero? && r[:xmax] < 0.0, 'salto spento (profilo Lento): resta di qua')
c = F.instance_variable_get(:@cfg)
c['jump_force'] = 2.5                       # 2,5²/19,6 = 0,32 m: il muretto è troppo alto
r = salta.(0.6)
ok(r[:salti].zero?, 'con il salto del giocatore più debole (2,5 m/s) il muretto non si salta più')
c['jump_force'] = F::DEFAULT['jump_force']        # non delete: una chiave tolta il giocatore la legge nil

# ── Occhi all'altezza del giocatore, anche cambiata mentre esplora ──
c['eye_height'] = 1.2
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false)
run(view, 3.0)
h1 = (ex[:z] - ex[:floor]) / M
c['eye_height'] = 1.55
run(view, 3.0)
h2 = (ex[:z] - ex[:floor]) / M
st = F.explore_status
F.explore_stop
c['eye_height'] = F::DEFAULT['eye_height']
ok((h1 - 1.2).abs < 0.03 && (h2 - 1.55).abs < 0.03 && st['eye_m'] == 1.55,
   "occhi all'altezza del giocatore: #{h1.round(2)} m, poi cambiata nel pannello #{h2.round(2)} m")

# ── Calpestio in pianta e in quota ───────────────────────────────────
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false)
e = ex
F.explore_walked_add(e, $now, 0.0, 60.0)
qui = F.explore_walk_f(e, [e[:x], e[:y], e[:floor] + 1.0 * M], $now)
sopra = F.explore_walk_f(e, [e[:x], e[:y], e[:floor] + 4.0 * M], $now)
piedi = F.explore_walk_f(e, [e[:x], e[:y], 0.0], $now, e[:floor])
piedi_su = F.explore_walk_f(e, [e[:x], e[:y], 0.0], $now, e[:floor] + 3.0 * M)
F.explore_stop
ok(qui < 0.5 && piedi < 0.5 && sopra == 1.0 && piedi_su == 1.0,
   "il calpestio ha la quota: qui stanca (#{qui.round(2)}), lo stesso punto un piano più su no (#{sopra.round(2)})")

# ── Pianta, giri dietro i muri, frontiere, giro attorno agli oggetti ──
into = Scena::Mat.new('Intonaco', [235, 232, 225])
stanza = lambda do |w, x0, x1, y0, y1|
  w.box([x0, y0, -0.1], [x1, y1, 0], pav)
  w.box([x0 - 0.2, y0, 0], [x0, y1, 3], into); w.box([x1, y0, 0], [x1 + 0.2, y1, 3], into)
  w.box([x0, y0 - 0.2, 0], [x1, y0, 3], into); w.box([x0, y1, 0], [x1, y1 + 0.2, 3], into)
end
statua = lambda do |w, x, y|
  s = Scena::Inst.new('Statua')
  w.box([x - 0.3, y - 0.3, 0], [x + 0.3, y + 0.3, 0.9], Scena::Mat.new('Marmo', [228, 228, 222]), s)
  w.box([x - 0.15, y - 0.15, 0.9], [x + 0.15, y + 0.15, 1.9], Scena::Mat.new('Bronzo rosso', [178, 40, 34]), s)
  s
end
# l'obiettivo imposto: la statua, che vale più di tutto il resto
mira = lambda do |s, x, y|
  F.explore_aim(ex, { id: 'statua', kind: nil, pt: [x * M, y * M, 1.2 * M], label: 'Statua', score: 5.0,
                      obj: s, opath: [s], open: false }, $now)
end
cella = ->(plan, x, y) { plan[F.explore_vpack((x * M / F::EX_PLAN_CELL).floor, (y * M / F::EX_PLAN_CELL).floor, 0)] }

# La statua dietro un muro di 2,5 m (troppo alto da saltare), che lascia un
# passaggio solo in fondo: prima si camminava contro il muro, o la si perdeva
w = Scena::World.new
stanza.(w, -6, 8, -5, 5)
w.box([0.9, -5, 0], [1.1, 2.5, 2.5], into)
s = statua.(w, 4.5, -2)
model, view, cam, err = fresh(w, [-3, -2, 1.7], [4.5, -2, 1.2], 'record' => false, 'attention' => 60.0)
ok(!F.explore_sees?(ex[:x], ex[:y], ex[:z], [4.5 * M, -2 * M, 1.2 * M], s), 'da qui la statua non si vede: c\'è il muro')
mira.(s, 4.5, -2)
dentro = false
linea = false
raggiunta = nil
plan = nil
run(view, 25.0) do |e|
  # il centro del corpo mai a meno di 8 cm dal muro (x 0,9..1,1 m fino a y 2,5 m), come nel giro lungo
  dentro ||= Math.hypot([0.9 - e[:x] / M, 0.0, e[:x] / M - 1.1].max, [e[:y] / M - 2.5, 0.0].max) < 0.08
  plan ||= e[:plan].dup if e[:t] >= 1.0               # la pianta di appena partiti
  if e[:route] && !linea
    view.drawn.clear
    F.explore_draw(view)
    linea = view.drawn.any? { |d| d[0] == :draw && d[1] == GL_LINE_STRIP && d[2] >= 2 }
  end
  raggiunta ||= e[:t] if e[:target] && e[:target][:label] == 'Statua' && e[:target][:arrived]
end
st = F.explore_status
F.explore_stop
ok(raggiunta && raggiunta < 18.0 && $diario.any? { |l| l['why'] == 'aggira' && l['label'] == 'Statua' } && !dentro,
   "statua dietro il muro: la aggira dal passaggio e la raggiunge (#{raggiunta&.round(1)} s, #{st['routes']} giri), mai dentro il muro")
ok(linea, 'il giro in corso si disegna (tratteggio sul pavimento)')
ok((cella.(plan, -2, -2).to_i & F::PL_FREE).nonzero? && (cella.(plan, 0.95, -2).to_i & F::PL_SOLID).nonzero? && cella.(plan, 1.6, -4.5).nil?,
   'sulla pianta: libero il pavimento visto, pieno il muro, mai visto un angolo dietro il muro')

# Ricerca del giro a fette: con budget 0 cede a ogni passo, stesso risultato
e = { plan: { F.explore_vpack(0, 0, 0) => F::PL_FREE }, x: 0.1 * M, y: 0.1 * M, z: 1.7 * M, floor: 0.0, eye_h: 1.7 * M }
(0..8).each { |k| e[:plan][F.explore_vpack(4, k - 4, 0)] = F::PL_SOLID }   # un muro a x = 2 m, da y = -2 a 2,5 m
tg = { pt: [4.0 * M, 0.1 * M, 1.2 * M], obj: nil }
tutto = F.explore_route_find(e, tg, 0.5 * M)
fib = Fiber.new { F.explore_route_find(e, tg, 0.5 * M, 0.0) }
fette = 0
pezzi = nil
while fib.alive?
  pezzi = fib.resume
  fette += 1
end
nel_muro = tutto && tutto.any? { |x, y| (x / M).between?(2.0, 2.5) && (y / M).between?(-2.0, 2.5) }
ok(tutto && tutto == pezzi && fette > 3 && !nel_muro && tutto.any? { |_, y| y / M > 2.5 || y / M < -2.0 },
   "A* a fette (#{fette} riprese): stesso giro (#{tutto&.size} punti), attorno al muro e non attraverso")

# Quote sulla pianta: una scala (alzate di 18 cm ogni 25 cm) si sale, un
# tavolo (75 cm) no; un percorso accorciato non ci passa sopra
e = { plan: {}, plan_z: {}, x: 0.25 * M, y: 0.25 * M, z: 1.7 * M, floor: 0.0, eye_h: 1.7 * M,
      step_in: 0.25 * M, drop_in: 0.8 * M }
(-10..20).each { |i| (-10..10).each { |j| e[:plan][F.explore_vpack(i, j, 0)] = F::PL_FREE; e[:plan_z][F.explore_vpack(i, j, 0)] = 0.0 } }
(4..5).each { |i| (-3..3).each { |j| e[:plan_z][F.explore_vpack(i, j, 0)] = 0.75 * M } }   # un tavolo a x = 2..3 m
tg = { pt: [5.25 * M, 0.25 * M, 1.2 * M], obj: nil }
via = F.explore_route_find(e, tg, 0.5 * M)
sopra = via && [[0.25 * M, 0.25 * M], *via].each_cons(2).any? do |(x0, y0), (x1, y1)|
  (0..20).any? { |q| x = x0 + (x1 - x0) * q / 20.0; y = y0 + (y1 - y0) * q / 20.0; (x / M).between?(2.0, 3.0) && (y / M).between?(-1.5, 2.0) }
end
(4..9).each { |i| (-3..3).each { |j| e[:plan_z][F.explore_vpack(i, j, 0)] = (i - 3) * 0.18 * M } }   # ora una scala
su = F.explore_route_find(e, { pt: [4.75 * M, 0.25 * M, 2.0 * M], obj: nil }, 0.3 * M)
ok(via && !sopra && su && su.size <= 2, "quote: attorno al tavolo (#{via&.size} tratti), su per la scala dritti (#{su&.size} tratti)")

# Quote lontane fra loro: 1,4 m più su a 5 m può essere un pendio (si
# prova), a un passo è un muretto (no); così la retta e così A*
e = { plan: {}, plan_z: {}, x: 0.25 * M, y: 0.25 * M, z: 1.7 * M, floor: 0.0, eye_h: 1.7 * M,
      step_in: 0.25 * M, drop_in: 0.8 * M, slope: Math.tan(50 * F::DEG) }
(-10..20).each { |i| (-10..10).each { |j| e[:plan][F.explore_vpack(i, j, 0)] = F::PL_FREE } }
e[:plan_z][F.explore_vpack(0, 0, 0)] = 0.0
e[:plan_z][F.explore_vpack(10, 0, 0)] = 1.4 * M
pendio = F.explore_grid_clear?(e, 0, 0.25 * M, 0.25 * M, 5.25 * M, 0.25 * M, false, 0.0, 0.0)
a_pendio = F.explore_route_find(e, { pt: [5.25 * M, 0.25 * M, 2.6 * M], obj: nil }, 0.3 * M)
(-10..1).each { |i| (-10..10).each { |j| e[:plan_z][F.explore_vpack(i, j, 0)] = 0.0 } }   # il pavimento davanti, visto
(2..3).each { |i| (-10..10).each { |j| e[:plan_z][F.explore_vpack(i, j, 0)] = 1.4 * M } }   # un muretto a x = 1..2 m, fino a y = 5,5 m
muretto = F.explore_grid_clear?(e, 0, 0.25 * M, 0.25 * M, 5.25 * M, 0.25 * M, false, 0.0, 0.0)
oltre = F.explore_route_find(e, { pt: [5.25 * M, 0.25 * M, 2.6 * M], obj: nil }, 0.3 * M)
scavalca = oltre && [[0.25 * M, 0.25 * M], *oltre].each_cons(2).any? do |(x0, y0), (x1, y1)|
  (0..40).any? { |q| x = x0 + (x1 - x0) * q / 40.0; y = y0 + (y1 - y0) * q / 40.0; (x / M).between?(1.05, 1.95) && y / M < 5.45 }   # dentro, non sullo spigolo
end
ok(pendio && a_pendio && !muretto && oltre && !scavalca,
   "quote lontane: 1,4 m più su a 5 m si prova (un pendio), un muretto di 1,4 m a un passo no: lo si gira in fondo (#{oltre&.size} tratti)")

# Ripianificare: un'analisi segna pieno un tratto del percorso → se ne cerca un altro
e = { plan: {}, plan_z: {}, x: 0.25 * M, y: 0.25 * M, z: 1.7 * M, floor: 0.0, eye_h: 1.7 * M, step_in: 0.25 * M,
      drop_in: 0.8 * M, mode: :walk, o: { 'frame_ms' => 40.0 }, slice: 40.0, route_job: nil, route_next: 0.0, plan_seq: 1 }
(-10..20).each { |i| (-10..10).each { |j| e[:plan][F.explore_vpack(i, j, 0)] = F::PL_FREE } }
tg = { id: 'x', pt: [6.25 * M, 0.25 * M, 1.2 * M], obj: nil, vis: true, standoff: 0.5 * M }
pts = F.explore_route_find(e, tg, 1.0 * M)
e[:route] = { id: 'x', pts: pts, rest: [], i: 0, tries: 0, goal: tg[:pt][0, 2], seq: 1, renew: 99.0 }
F.explore_route_want(e, tg, 0.0, 6.0 * M)
tiene = e[:route_job].nil?
(-1..1).each { |j| e[:plan][F.explore_vpack(6, j, 0)] = F::PL_FREE | F::PL_SOLID | F::PL_BUMP }   # qualcosa a x = 3 m
e[:plan_seq] = 2
F.explore_route_want(e, tg, 0.0, 6.0 * M)
ok(tiene && e[:route].nil? && e[:route_job], 'un percorso ancora libero si tiene; sbarrato da ciò che si è visto, se ne cerca un altro')

# Si pianifica sempre, non solo quando la strada è sbarrata: la statua si
# vede oltre una barriera di 1 m (troppo alta per saltarla) che ha un
# passaggio solo in fondo. Prima andava dritto fino alla barriera e solo lì
# cercava il giro; ora va subito verso il passaggio, per la strada corta.
w = Scena::World.new
stanza.(w, -6, 8, -5, 5)
w.box([0.9, -5, 0], [1.3, 2.5, 1.0], Scena::Mat.new('Siepe', [60, 120, 60]))
s = statua.(w, 4.5, -2)
model, view, cam, err = fresh(w, [-3, -2, 1.7], [4.5, -2, 1.2], 'record' => false, 'attention' => 60.0)
ok(F.explore_sees?(ex[:x], ex[:y], ex[:z], [4.5 * M, -2 * M, 1.2 * M], s), 'la statua si vede, oltre la barriera')
mira.(s, 4.5, -2)
cammino = 0.0
raggiunta = nil
prec = nil
a3 = nil
run(view, 30.0) do |e|
  prec ||= [e[:x], e[:y]]
  cammino += Math.hypot(e[:x] - prec[0], e[:y] - prec[1]) / M unless raggiunta   # fino all'arrivo
  prec = [e[:x], e[:y]]
  a3 ||= [e[:x] / M, e[:y] / M] if e[:t] >= 3.0
  raggiunta ||= e[:t] if e[:target] && e[:target][:label] == 'Statua' && e[:target][:arrived]
end
F.explore_stop
# la strada corta: fino all'angolo del passaggio (1,1; 2,9), poi alla statua (fermandosi a ~1,2 m)
corta = Math.hypot(1.1 + 3, 2.9 + 2) + Math.hypot(4.5 - 1.1, -2 - 2.9) - 1.2
ok($diario.any? { |l| l['why'] == 'percorso' && l['label'] == 'Statua' } && a3[1] > -1.2,
   "si prefigura il percorso: dopo 3 s è già in diagonale verso il passaggio (#{a3.map { |v| v.round(1) }}), " \
   'non dritto contro la barriera (y = -2)')
ok(raggiunta && cammino < corta * 1.3,
   "e raggiunge la statua in #{raggiunta&.round(1)} s camminando #{cammino.round(1)} m (la strada corta ne fa #{corta.round(1)})")

# Due stanze vuote con una porta, partendo voltati verso un muro: le
# frontiere (il bordo di ciò che non si è mai visto) portano di là
w = Scena::World.new
stanza.(w, -6, 6, -4, 4)
w.box([-0.1, -4, 0], [0.1, -0.5, 3], into)
w.box([-0.1, 0.5, 0], [0.1, 4, 3], into)
model, view, cam, err = fresh(w, [-4, 2, 1.7], [-4, -4, 1.2], 'record' => false)
di_la = nil
viola = false
run(view, 40.0) do |e|
  di_la ||= e[:t] if e[:x] / M > 1.0
  next if viola || e[:fronts].empty?
  view.drawn.clear
  F.explore_draw(view)
  viola = view.drawn.any? { |d| d[0] == :points && d[4].red == 190 && d[4].blue == 255 }
end
st = F.explore_status
F.explore_stop
ok(di_la && di_la < 15.0 && $diario.any? { |l| l['label'] == F.t('explore.frontier') } && st['plan_cells'] > 200,
   "frontiere: dalla stanza vuota all'altra in #{di_la&.round(1)} s, passando per le zone mai viste (#{st['plan_cells']} celle viste)")
ok(viola, 'le frontiere si disegnano (quadratini viola sul pavimento)')

# Frontiere su un terreno che sale: ognuna sul suo pavimento, non alla quota
# dei piedi (sotto un solaio, che il raggio in giù salta)
w = Scena::World.new
w.box([-6, -6, -0.2], [2, 6, 0], into)
w.box([2, -6, 0], [6, 6, 1.2], into)                  # un terrazzo alto 1,2 m da x = 2 m
w.box([-6, -6, 2.5], [6, 6, 2.7], into)               # un solaio sopra tutto
model = Scena::Model.new(w, nil)
plan = {}
zmap = {}
(-10..9).each { |i| (-10..10).each { |j| plan[F.explore_vpack(i, j, 0)] = F::PL_FREE } }
(-2..2).each { |i| (-2..2).each { |j| zmap[F.explore_vpack(i, j, 0)] = 0.0 } }   # il pavimento visto davvero
fr = F.explore_frontiers(plan, zmap, 0.25 * M, 0.25 * M, 0.0, model: model)
quota = {}
fr.each { |f| f[:cells].each_with_index { |c, i| quota[c] = f[:zs][i] } }
alto = (-4..4).map { |j| quota[[9, j]] }
basso = (-4..4).map { |j| quota[[-10, j]] }
ok(alto.all? { |z| z && (z - 1.2 * M).abs < 0.01 * M } && basso.all? { |z| z && z.abs < 0.01 * M },
   "frontiere sul terreno: sul terrazzo a #{alto.compact.map { |z| (z / M).round(2) }.uniq} m, " \
   "davanti a #{basso.compact.map { |z| (z / M).round(2) }.uniq} m")
f9 = fr.find { |f| f[:cells].include?([9, 0]) }
c9 = F.explore_front_cand({ x: 0.25 * M, y: 0.25 * M, z: 1.7 * M, floor: 0.0, eye_h: 1.7 * M, o: { 'roam' => 1.0 } },
                          f9.merge(ix: 9, iy: 0, z: quota[[9, 0]]))
ok((c9[:pt][2] - 2.9 * M).abs < 0.01 * M, "e la frontiera da guardare è all'altezza degli occhi sul terrazzo (#{(c9[:pt][2] / M).round(2)} m)")

# Il tratteggio del percorso sul terreno: su per quattro gradini, lungo un
# pianerottolo, giù da un bordo; sempre sul pavimento, mai dentro un solido
w = Scena::World.new
w.box([-2, -3, -0.2], [9, 3, 0], into)
4.times { |k| w.box([2.0 + 0.3 * k, -3, 0], [5, 3, 0.17 * (k + 1)], into) }
w.box([-2, -3, 2.6], [9, 3, 2.8], into)               # un solaio
model = Scena::Model.new(w, nil)
pf = F.explore_route_profile({ model: model }, 0.0, 0.0, 0.0, [[3.5 * M, 0.1 * M], [7 * M, 0.4 * M]])
linea = [[0.0, 0.0, 0.0]] + pf[:segs].flatten(1).map { |_, x, y, z| [x, y, z] }
dentro = lambda do |x, y, z|
  w.boxes.any? { |b| (0..2).all? { |k| [x, y, z][k] > b.min[k] + 0.001 * M && [x, y, z][k] < b.max[k] - 0.001 * M } }
end
taglia = linea.each_cons(2).count { |a, b| (1..49).any? { |s| dentro.(*(0..2).map { |k| a[k] + (b[k] - a[k]) * s / 50.0 }) } }
quota = lambda do |x|
  x /= M
  x < 2.0 || x >= 5.0 ? 0.0 : 0.17 * ([((x - 2.0) / 0.3).floor, 3].min + 1)
end
sul = linea.all? { |x, _, z| (z - quota.(x) * M).abs < 0.002 * M || (z - quota.(x + 0.03 * M) * M).abs < 0.002 * M ||
                             (z - quota.(x - 0.03 * M) * M).abs < 0.002 * M }
ok(taglia.zero? && sul && linea.map { |p| p[2] }.max.between?(0.67 * M, 0.69 * M),
   "il percorso disegnato poggia sul terreno (#{linea.size} punti, fino a #{(linea.map { |p| p[2] }.max / M).round(2)} m) " \
   "e non taglia i gradini (#{taglia} tratti dentro un solido)")

# Giro attorno a un oggetto raggiunto (orbit, in gradi; il Fotografo 180°)
giro = lambda do |gradi, muro = false|
  w = Scena::World.new
  stanza.(w, -6, 6, -5, 5)
  s = statua.(w, 2, 0)
  w.box([1.3, 0.55, 0], [2.7, 0.65, 2.5], into) if muro   # un muretto a nord della statua: da lì non si vede
  model, view, cam, err = fresh(w, [-3, 0, 1.7], [2, 0, 1.2], 'record' => false, 'orbit' => gradi)
  mira.(s, 2, 0)
  angs = []
  guarda = []
  nascosta = 0
  fine = nil
  run(view, 30.0) do |e|
    t = e[:target]
    if t && t[:id] == 'statua' && t[:orbit] && !t[:orbit][:end]
      angs << Math.atan2(e[:y] / M, e[:x] / M - 2)
      guarda << F.explore_aim_err(e, t[:pt]) / F::DEG if angs.size > 30
      nascosta += 1 unless F.explore_sees?(e[:x], e[:y], e[:z], t[:pt], t[:obj])
    end
    fine ||= e[:t] if $diario.any? { |l| l['why'] == 'raggiunto' && l['label'] == 'Statua' }
  end
  F.explore_stop
  span = angs.each_cons(2).sum { |a, b| ((b - a + Math::PI) % (2 * Math::PI) - Math::PI).abs } / F::DEG
  { span: span, guarda: guarda.max || 0.0, fine: fine, giri: $diario.count { |l| l['why'] == 'gira attorno' },
    nascosta: nascosta, passi: angs.size }
end
r = giro.(180.0)
ok(r[:giri] >= 1 && r[:span].between?(165, 200) && r[:fine] && r[:guarda] < 25.0,
   "orbit 180°: raggiunta la statua ci gira attorno (#{r[:span].round}°) guardandola (scarto al più #{r[:guarda].round}°), poi la sosta")
r = giro.(360.0, true)
ok(r[:giri] >= 1 && r[:fine] && r[:passi] > 60 && r[:nascosta].zero? && r[:span] > 150,
   "orbit 360° con un muretto accanto alla statua: gira (#{r[:span].round}°) solo dove la vede " \
   "(#{r[:nascosta]} fotogrammi su #{r[:passi]} senza vederla), poi la sosta")
r = giro.(0.0)
ok(r[:giri].zero? && r[:fine], 'orbit 0: niente giro, solo la sosta')
ok(F::EX_PROFILES['photographer']['orbit'] == 180.0 && F::EX_PROFILES['curious']['orbit'] == 90.0 &&
   F::EX_DEFAULTS['orbit'].zero?, 'giro attorno: Fotografo 180°, Curioso 90°, gli altri no')

# ── Determinazione: un obiettivo appena scelto non si cambia ────────
# Su Stromboli (retina rada, tante piante piccole) un obiettivo entrava e
# usciva dalle celle a ogni analisi: l'esploratore cambiava idea ogni mezzo
# secondo, lo sguardo inseguiva e i piedi non partivano mai.
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false)
F.explore_pause(true)                       # decisioni a mano, senza animazione
e = ex
cand = lambda do |id, score, pt|
  { id: id, kind: "d:#{id}", pt: pt.map { |v| v * M }, score: score, area: 0.01, cell: 0, label: id,
    obj: nil, opath: nil, open: false }
end
analisi = ->(*cs) { { cells: [], gw: 1, gh: 1, f: [], cands: cs, hits: 10 } }
t0 = $now
F.explore_decide(e, analisi.(cand.('A', 0.5, [-4, 2, 0.7])), t0)
F.explore_decide(e, analisi.(cand.('B', 0.6, [4, 3, 0.5])), t0 + 0.5)
F.explore_decide(e, analisi.(cand.('B', 0.7, [4, 3, 0.5])), t0 + 1.5)
tenuto = e[:target][:id] == 'A'
F.explore_decide(e, analisi.(cand.('B', 0.9, [4, 3, 0.5])), t0 + 5.0)
ok(tenuto && e[:target][:id] == 'B', 'appena scelto non cambia idea (determinazione 2,5 s); sparito da un pezzo, sì')

# ── Continuità dello sguardo: accanto sì, indietro no ───────────────
# Il soldato guardava a destra, poi a sinistra, poi di nuovo a destra una
# cosa che aveva già nella retina la prima volta.
deg = F::DEG
dir = ->(a, d = 4.0) { [e[:x] / M + Math.cos(a * deg) * d, e[:y] / M + Math.sin(a * deg) * d, e[:z] / M] }
posa = ->(yaw, t) { [e[:x], e[:y], yaw * deg, F.explore_half_hfov(view), t] }
e[:target] = nil
e[:yaw] = -30.0 * deg; e[:pitch] = 0.0
e[:sweep] = [posa.(-30.0, $now)]
vicino = F.explore_shift_f(e, cand.('C', 0.5, dir.(-40.0)), $now)
lontano = F.explore_shift_f(e, cand.('B', 0.5, dir.(30.0)), $now)
e[:o] = e[:o].merge('continuity' => 0.0)
spento = [F.explore_shift_f(e, cand.('C', 0.5, dir.(-40.0)), $now), F.explore_shift_f(e, cand.('B', 0.5, dir.(30.0)), $now)]
ok(vicino > 0.9 && lontano < 0.4 && spento == [1.0, 1.0],
   "saltare accanto costa poco (10°: #{vicino.round(2)}), girarsi di più (60°: #{lontano.round(2)}); continuity 0: niente")
scelta = lambda do |q|
  e[:o] = e[:o].merge('continuity' => q, 'whim' => 0.0)
  e[:target] = nil; e[:bored] = {}; e[:visited] = {}; e[:kbored] = {}; e[:kvisited] = {}
  e[:scan_pose] = nil
  F.explore_decide(e, analisi.(cand.('B', 0.6, dir.(30.0)), cand.('C', 0.5, dir.(-40.0))), $now)
  e[:target] && e[:target][:id]
end
ok(scelta.(1.0) == 'C' && scelta.(0.0) == 'B', 'finito a destra, prima la cosa accanto (C) che quella più bella a sinistra (B); senza continuità B')
e[:o] = e[:o].merge('continuity' => 1.0)
# guardava a 60°, ora a -30°: ciò che stava a 60° l'aveva nella retina e se n'è girato
e[:yaw] = -30.0 * deg
e[:sweep] = [posa.(60.0, $now - 6.0), posa.(-30.0, $now)]
torna = F.explore_shift_f(e, cand.('R', 0.5, dir.(60.0)), $now)
nuovo = F.explore_shift_f(e, cand.('N', 0.5, dir.(-120.0)), $now)
ok(F.explore_return_w(e, cand.('R', 0.5, dir.(60.0)), $now) > 0.7 && F.explore_return_w(e, cand.('N', 0.5, dir.(-120.0)), $now).zero? &&
   torna < nuovo * 0.45, "stessa girata (90°): tornare su ciò che aveva già visto #{torna.round(3)}, guardare dove non ha mai guardato #{nuovo.round(3)}")
e[:sweep] = [posa.(60.0, $now - 6.0), posa.(40.0, $now)]
ok(F.explore_return_w(e, cand.('R', 0.5, dir.(60.0)), $now).zero?, 'ancora lì accanto: non è un ritorno')
e[:sweep] = [[e[:x] + 20 * M, e[:y], 60.0 * deg, 0.8, $now - 6.0], posa.(-30.0, $now)]
ok(F.explore_return_w(e, cand.('R', 0.5, dir.(60.0)), $now).zero?, 'guardato da 20 m più in là: non conta')
# guardandosi intorno: un giro, non un andirivieni
cella = ->(d) { F::ExCell.new(nil, d * M) }
giro_lato = lambda do |q|
  e[:o] = e[:o].merge('continuity' => q)
  e[:look] = nil; e[:look_last] = nil; e[:looks] = 0
  e[:yaw] = 0.0
  e[:sweep] = [posa.(0.0, $now - 2.0)]
  F.explore_look_around(e, { cells: [cella.(10.0), cella.(30.0)], gw: 2, gh: 1, geo: nil }, $now - 2.0)   # più profondo a destra
  primo = F.explore_wrap(e[:look][:goal]) < 0 ? :destra : :sinistra
  e[:yaw] = e[:look][:goal]
  e[:sweep] << posa.(e[:yaw] / deg, $now)
  e[:look] = nil
  F.explore_look_around(e, { cells: [cella.(30.0), cella.(10.0)], gw: 2, gh: 1, geo: nil }, $now)          # ora a sinistra
  [primo, F.explore_wrap(e[:look][:goal] - e[:yaw]) < 0 ? :destra : :sinistra]
end
ok(giro_lato.(1.0) == %i[destra destra] && giro_lato.(0.0) == %i[destra sinistra],
   'guardandosi intorno due volte continua a girare dalla stessa parte (senza continuità torna indietro)')
ok(F::EX_PROFILES['soldier']['continuity'] > 1.0 && F::EX_PROFILES['carefree']['continuity'] < 1.0 && F::EX_DEFAULTS['continuity'] == 1.0,
   'continuità: Soldato di più, Spensierato di meno')
F.explore_stop

# ── Pilota: l'IA collegata al ponte guarda e guida (lib/expilot.rb) ──
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, -3, 1.7], 'record' => false)
run(view, 1.5)
p0 = JSON.parse(JSON.generate(F.explore_percept(0)))
cosa = ->(lbl) { p0['things'].find { |t| t['label'] == lbl } }
statua = cosa.('Statua')
ok(p0['on'] && p0['run'].is_a?(String) && statua && statua['id'] =~ /\Ao\d+\z/ && statua['kind'] == 'object' &&
   statua['size_m'].between?(1.8, 2.0) && statua['in_view'] && statua['bearing_deg'].abs <= 60 && p0['things'].first == statua &&
   p0['things'].none? { |t| t['kind'] == 'surface' && t['salience'] < F::EX_KNOWN_SURF_MIN },
   "descrizione per l'IA in JSON: prima la statua, #{statua && statua['id']} (#{statua && statua['size_m']} m, lato #{statua && statua['bearing_deg']}°); facce spente no")
ok(p0['frontiers'].all? { |f| f['id'] =~ /\AF\d+\z/ && f['dist_m'] > 0 } && p0['target'] && %w[auto ai].include?(p0['target']['by']),
   "zone inesplorate (#{p0['frontiers'].size}) e obiettivo (#{p0['target'] && p0['target']['label']}, scelto da solo)")
r = F.explore_command('steer', 'agenda' => [{ 'go' => 'o999' }, { 'foo' => 1 }, { 'go' => 'F99999' }, { 'to' => [1, 'a', 2] }])
ok(r['ok'] && r['agenda'].empty? && r['rejected'].size == 4, "voci che non si possono fare: rifiutate subito (#{r['rejected'].map { |x| x['why'] }.join(' | ')})")
r = F.explore_command('steer', 'agenda' => [{ 'go' => statua['id'], 'dwell' => 0.6, 'orbit' => 0, 'say' => 'Una statua di bronzo' }])
ok(r['agenda'].size == 1 && r['agenda'][0]['label'] == 'Statua' && r['rejected'].empty?, 'in agenda: vai alla statua')
mezzo = nil
fatto = nil
run(view, 30.0) do |e|
  mezzo ||= F.explore_percept(0) if e[:target] && e[:target][:ai] && !e[:target][:arrived]
  fatto = e[:events].find { |v| v['type'] == 'done' && v['id'] == statua['id'] }
  break if fatto
end
tipi = ex[:events].map { |v| v['type'] }
ok(mezzo && mezzo['target']['by'] == 'ai' && mezzo['target']['id'] == statua['id'] && mezzo['agenda'][0]['state'] == 'going',
   'mentre ci va: obiettivo dell\'IA, voce «going»')
ok(fatto && fatto['why'] == 'raggiunto' && (tipi & %w[started arrived done agenda_empty]).size == 4 && !tipi.include?('agenda_low') &&
   tipi.index('started') < tipi.index('arrived') && tipi.index('arrived') < tipi.index('done'),
   "ci arriva, la guarda, è fatta: avvisi #{tipi.uniq.join(', ')}")
arrivo = ex[:events].find { |v| v['type'] == 'arrived' }
ok(arrivo && arrivo['dist_m'] < 3.5 && ex[:log].any? { |l| l['why'] == 'commento' && l['label'] == 'Una statua di bronzo' } &&
   ex[:log].any? { |l| l['why'] == 'nuovo' && l['ai'] && l['label'] == 'Statua' },
   "arrivata a #{arrivo && arrivo['dist_m']} m; il commento nel diario")
detto = ex[:says].first
salvato = F.explore_save_path(ex.merge(rec: [[0.0] + [0.0] * 10, [ex[:t].round(3) + 1] + [0.0] * 10]))
ok(ex[:says].size == 1 && detto[1] == 'Una statua di bronzo' && (detto[0] - arrivo['t']).abs < 0.2 &&
   F.path_data(salvato, model)['notes'] == ex[:says] && F.path_notes(F.path_data(salvato, model)) == [[detto[0], detto[1]]],
   "il commento resta nel percorso registrato, al secondo #{detto && detto[0]} (scene e sottotitoli)")
ok(ex[:agenda].empty? && F.explore_percept(fatto['n'])['events'].map { |v| v['type'] }.include?('agenda_empty'),
   'agenda vuota: torna a scegliere da solo')
# la foto della sosta: dopo l'arrivo, prima che sia fatta; l'arrivo con la foto in arrivo non sveglia
foto = ex[:events].find { |v| v['type'] == 'photo' }
png = foto && foto['path'] && File.exist?(foto['path']) ? File.binread(foto['path']) : ''
ok(foto && foto['error'].nil? && foto['id_visible'] && png.start_with?("\x89PNG\r\n\x1A\n".b) && png.byteslice(16, 8).unpack('NN') == [foto['w'], foto['h']] &&
   foto['w'] == 192 && File.dirname(foto['path']) == File.join(tmp, 'pilota'),
   "foto della sosta: #{foto && File.basename(foto['path'].to_s)} #{foto && foto['w']}×#{foto && foto['h']} in #{foto && foto['ms']} ms")
ok(arrivo['photo'] && ex[:events].index { |v| v['type'] == 'arrived' } < ex[:events].index(foto) &&
   ex[:events].index(foto) < ex[:events].index(fatto) && !F.pilot_wake?(ex, [arrivo]) && F.pilot_wake?(ex, [foto]),
   'arrivo → foto → fatta: la sosta aspetta la foto; sveglia la foto, non l\'arrivo')
segni = ex[:photo] && ex[:photo]['marks']
ok(segni && segni.first && segni.first['id'] == statua['id'] && segni.all? { |m| m['x'].between?(0, 192) && m['y'].between?(0, 108) } &&
   F.explore_percept(0)['photo']['path'] == foto['path'],
   "segni sulla foto: prima la meta (#{segni && segni.map { |m| m['id'] }.join(' ')}); la descrizione dice l'ultima foto")
# PNG e cartellini, a parte
righe = Array.new(60) { ([200, 200, 200].pack('C3') * 100).b }
cart = [{ id: 'o12', x: 50.0, y: 30.0, kind: :obj }, { id: 's3', x: 51.0, y: 31.0, kind: :surf }, { id: 'F9', x: 50.0, y: 30.0, kind: :front }]
F.pilot_draw_marks(righe, 100, 60, cart)
blu = [25, 45, 110].pack('C3')
ok(cart.size == 3 && righe.count { |r| r.include?(blu) } > 10 && righe[30].byteslice(150, 3) == F::EX_PHOTO_COLORS[:front][0].pack('C3'),
   "cartellini: il punto e il nome, tre segni sullo stesso posto senza coprirsi (#{cart.map { |m| m[:id] }.join(' ')})")
cart = Array.new(12) { |i| { id: "o#{i}", x: 50.0, y: 30.0, kind: :obj } }
F.pilot_draw_marks(Array.new(60) { ('x' * 300).b }, 100, 60, cart)
ok(cart.size.between?(1, 4), "senza posto i segni si saltano (#{cart.size} su 12)")
dati = F.pilot_png(100, 60, righe)
ihdr = dati.byteslice(8, 25)
idat_len = dati.byteslice(33, 4).unpack1('N')
grezzo = Zlib::Inflate.inflate(dati.byteslice(41, idat_len))
ok(ihdr.byteslice(4, 4) == 'IHDR' && Zlib.crc32(ihdr.byteslice(4, 17)) == ihdr.byteslice(21, 4).unpack1('N') &&
   grezzo == righe.map { |r| "\x00".b + r }.join && dati.end_with?([0].pack('N') + 'IEND' + [Zlib.crc32('IEND')].pack('N')),
   'PNG scritto a mano: intestazione, CRC, righe com\'erano')
bmp = ['BM', 54 + 3 * 4 * 2, 0, 54, 40, 3, 2, 1, 24, 0, 0, 0, 0, 0, 0].pack('a2Vl<Vl<l<l<vvVVl<l<VV') +
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0, 10, 11, 12, 13, 14, 15, 16, 17, 18, 0, 0, 0].pack('C*')
ok(F.pilot_rows(bmp) == [[12, 11, 10, 15, 14, 13, 18, 17, 16].pack('C*'), [3, 2, 1, 6, 5, 4, 9, 8, 7].pack('C*')],
   'BMP dal basso, righe con il riempimento: righe RGB dall\'alto')
# guardare senza muoversi
x0 = ex[:x]; y0 = ex[:y]
F.explore_command('steer', 'agenda' => [{ 'look' => statua['id'], 'for' => 1.0 }])
run(view, 0.6)
guarda = ex[:target] && ex[:target][:ai] && ex[:target][:arrived]
mosso = nil
run(view, 2.0) do |e|
  next unless e[:events].any? { |v| v['type'] == 'done' && v['why'] == 'raggiunto' && v['n'] > fatto['n'] }
  mosso = Math.hypot(e[:x] - x0, e[:y] - y0) / M
  break
end
ok(guarda && mosso && mosso < 0.1, "«guarda»: si gira e resta dov'è (#{mosso && mosso.round(2)} m), poi è fatta")
# un punto, poi cambiare idea: la meta in corso si lascia
F.explore_command('steer', 'agenda' => [{ 'to' => [-2.0, 0.0, 1.7] }, { 'go' => statua['id'] }])
run(view, 0.6)
punto = ex[:target] && ex[:target][:ai] && ex[:target][:label].start_with?('→') && ex[:target][:pt].map { |v| (v / M).round(1) } == [-2.0, 0.0, 1.7]
ex[:target][:since] -= F::EX_PILOT_SLOW + 1.0      # da un pezzo, e non ci arriva
ex[:target][:slow_t] = nil
F.explore_think(ex, $now, 0.0)
lento = ex[:events].last
ok(lento['type'] == 'slow' && lento['seconds'].between?(13, 14) && F::EX_PILOT_WAKE.include?('slow') && ex[:target],
   "una meta che non si raggiunge: avviso slow dopo #{lento['seconds']} s, la si insegue ancora")
r = F.explore_command('steer', 'clear' => true)
ok(punto && r['agenda'].empty? && !(ex[:target] && ex[:target][:ai]) &&
   ex[:events].last(3).any? { |v| v['type'] == 'done' && v['why'] == 'cambiato' }, 'un punto in metri; «clear»: lasciato, agenda vuota')
cambio = ex[:events].reverse.find { |v| v['why'] == 'cambiato' }
ok(cambio && cambio['from_steer'] && !F.pilot_wake?(ex, [cambio]) && !ex[:steering],
   'la meta lasciata perché l\'IA ha cambiato agenda: avviso segnato from_steer, che non la sveglia')
# gusti
c_t = { id: 'x', sid: 'o77', label: 'Tavolo da pranzo', front: nil, open: false }
c_f = { id: 'f1,1,0', label: 'zona', front: {}, open: true }
r = F.explore_command('steer', 'like' => { 'o77' => 2, 'label:TAVOLO' => 1.5, 'frontier' => 3, 'open' => 'boh' }, 'avoid' => ['o3'])
lk = [F.pilot_like_f(ex, c_t), F.pilot_like_f(ex, c_f), F.pilot_like_f(ex, c_t.merge(sid: 'o3', label: 'Sedia'))]
ok(lk == [3.0, 3.0, F::EX_AVOID] && r['rejected'].size == 1, "gusti: per nome corto × per nome (#{lk[0]}), frontiere (#{lk[1]}), evita (#{lk[2]})")
F.explore_command('steer', 'like' => { 'o77' => nil }, 'likes_clear' => false)
ok(F.pilot_like_f(ex, c_t) == 1.5 && F.explore_command('steer', 'likes_clear' => true)['likes'].empty?, 'un gusto si toglie con null, tutti con likes_clear')
detti = ex[:says].size
F.explore_command('steer', 'say' => 'Una statua di bronzo ')
ok(ex[:says].size == detti, 'un commento già detto in questo giro non si ripete')
r = F.explore_command('steer', 'like' => { 'label: ' => 2, ' ' => 1 })
ok(r['rejected'].size == 2 && r['likes'].empty? && F.pilot_like_f(ex, c_t) == 1.0, 'gusto senza nome: rifiutato (non varrebbe per tutto)')
voce, = F.pilot_item(ex, 'go' => 'o999', 'look' => statua['id'])
ok(voce && voce[:act] == :look && voce[:id] == statua['id'], 'go e look insieme: vale look, con il suo nome')
# a piedi: la descrizione dice se ci si arriva
st_p = F.explore_percept(0)['things'].find { |t| t['id'] == statua['id'] }
ok(ex[:mode] == :walk && st_p && %w[yes unknown].include?(st_p['reach']) && st_p['walk_m'].is_a?(Numeric) &&
   F.explore_percept(0)['things'].select { |t| t['kind'] == 'surface' }.none? { |t| t.key?('reach') },
   "a piedi: la statua si raggiunge (#{st_p && st_p['reach']}, #{st_p && st_p['walk_m']} m di strada); per le facce non si dice")
# pianta finta: una stanza chiusa di 10×10 celle
cs = F::EX_PLAN_CELL
pl = {}
(0..9).each { |i| (0..9).each { |j| pl[F.explore_vpack(i, j, 0)] = F::PL_FREE } }
(-1..10).each { |i| [-1, 10].each { |j| pl[F.explore_vpack(i, j, 0)] = pl[F.explore_vpack(j, i, 0)] = F::PL_SOLID } }
fx = { mode: :walk, plan: pl, plan_z: {}, plan_seq: 1, x: 2.5 * cs, y: 5.5 * cs, z: 1.7 * M, floor: 0.0, eye_h: 1.7 * M,
       o: { 'standoff' => 1.2 }, ag_seq: 0, fknown: {},
       known: { 'k1' => { sid: 'o1', pt: [15.5 * cs, 5.5 * cs, 0.0], size: 0.5, obj: nil } }, ksid: { 'o1' => 'k1' } }
dentro = F.pilot_reach(fx, [8.5 * cs, 5.5 * cs, 0.0], 0.6 * M, 0.0)
fuori = F.pilot_reach(fx, [15.5 * cs, 5.5 * cs, 0.0], 0.6 * M, 0.0)
ok(dentro && dentro[0] == 'yes' && dentro[1].between?(2.0, 3.0) && fuori == ['no', nil] &&
   F.pilot_reach(fx, [200 * M, 0.0, 0.0], 1.0 * M, 0.0) == ['far', nil] && F.pilot_reach(fx.merge(mode: :fly), [0, 0, 0], M, 0.0).nil?,
   "pianta finta: dentro la stanza sì (#{dentro && dentro[1]} m), fuori no, lontano non si sa, in volo non si dice")
voce, perche = F.pilot_item(fx, 'go' => 'o1')
guardo, = F.pilot_item(fx, 'look' => 'o1')
ok(voce.nil? && perche.to_s.include?('a piedi non ci si arriva') && guardo && guardo[:act] == :look,
   'steer: «vai» verso una cosa dove a piedi non si arriva, rifiutato col motivo; «guarda» sì')
pl.delete(F.explore_vpack(10, 5, 0))                         # un varco mai visto nel muro
fx[:plan_seq] = 2
fx[:flood] = nil                                             # (quella di prima varrebbe ancora qualche secondo)
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
forse = F.pilot_reach(fx, [15.5 * cs, 5.5 * cs, 0.0], 0.6 * M, 0.0)
ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
ok(forse && forse[0] == 'unknown' && forse[1].between?(5.0, 7.0) && fx[:flood][:cut] && fx[:flood][:nodes] > F::EX_REACH_NODES,
   "un varco mai visto: forse (#{forse && forse[1]} m), dall'altra parte tutto ignoto: ricerca fermata a #{F::EX_REACH_NODES} celle in #{ms} ms")
again = F.pilot_flood(fx)
fx[:plan_seq] = 3
fx[:x] += 2 * cs
ok(again.equal?(fx[:flood]) && F.pilot_flood(fx).equal?(again), 'la stessa pianta e la stessa cella, o poco dopo e poco più in là: la ricerca non si rifà')
fx[:t] = F::EX_REACH_FRESH + 1.0
ok(!F.pilot_flood(fx).equal?(again), 'dopo qualche secondo con la pianta cambiata: si rifà')
# due voci: la seconda, quando comincia, è l'ultima → agenda quasi vuota (una volta, dopo la prima fatta)
n2 = ex[:ev_seq]
F.explore_command('steer', 'agenda' => [{ 'look' => statua['id'], 'for' => 0.3 }, { 'look' => statua['id'], 'for' => 0.3 }])
run(view, 10.0) { |e| break if e[:events].count { |v| v['n'] > n2 && v['type'] == 'done' } >= 2 }
ev2 = ex[:events].select { |v| v['n'] > n2 }.map { |v| v['type'] }
ok(ev2.count('done') == 2 && ev2.count('agenda_low') == 1 && ev2.index('agenda_low') > ev2.index('done'),
   "agenda quasi vuota quando parte l'ultima voce, non per l'agenda appena data (#{ev2.join(' ')})")
# avvisi a pezzi: brief solo gli avvisi; since li filtra
n0 = ex[:ev_seq]
F.explore_command('steer', 'say' => 'ciao')
b = F.explore_command('percept', 'since' => n0, 'brief' => true)
ok(b['events'].map { |v| v['type'] } == ['said'] && !b['wake'] && !b.key?('things') && b['ev_n'] == n0 + 1,
   'brief: solo gli avvisi dopo since; un commento non sveglia il pilota')
nota = [{ 'type' => 'notable' }]
ok(!F.pilot_wake?({ agenda: [1, 2] }, nota) && F.pilot_wake?({ agenda: [1] }, nota) && F.pilot_wake?({ agenda: [1, 2] }, [{ 'type' => 'slow' }]),
   'una cosa notevole sveglia il pilota solo ad agenda quasi finita')
F.explore_stop
ok(F.explore_percept(0)['on'] == false && F.explore_command('steer', {})['ok'] == false, 'fermo: la descrizione lo dice, steer no')

# ── Bloccato: via di fuga; a piedi nessuna via: in volo ─────────────
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false)
e = ex
e[:anchor] = [$now - 11.0, e[:x], e[:y], e[:z]]           # fermo da 11 s
F.explore_stall(e, $now)
via = !e[:escape].nil?
x0 = e[:x]; y0 = e[:y]
run(view, 3.0)
mosso = Math.hypot(e[:x] - x0, e[:y] - y0) / M
ok(via && $diario.any? { |l| l['why'] == 'via di fuga' } && mosso > 1.0, "fermo da 10 s: via di fuga, e cammina (#{mosso.round(2)} m)")
F.explore_stop

colonna = Scena::World.new
colonna.box([-10, -10, -0.1], [10, 10, 0], pav)
colonna.box([-0.4, -0.4, 0], [0.4, 0.4, 5], Scena::Mat.new('Pietra', [150, 150, 150]))
colonna.box([4, -0.5, 0], [5, 0.5, 1], Scena::Mat.new('Bronzo rosso', [178, 40, 34]), Scena::Inst.new('Cassa'))
model, view, cam, err = fresh(colonna, [0, 0, 6.7], [5, 0, 5.5], 'record' => false)
e = ex
a_piedi = e[:mode] == :walk
e[:anchor] = [$now - 11.0, e[:x], e[:y], e[:z]]
F.explore_stall(e, $now)
volo = e[:mode] == :fly && e[:log].any? { |l| l['why'] == 'in volo' }
run(view, 1.0)
ancora = e[:mode] == :fly                   # non riatterra subito sulla colonna
run(view, 25.0)
giu = Math.hypot(e[:x], e[:y]) > 0.6 * M || e[:z] < 4.0 * M
ok(a_piedi && volo && ancora && giu, "in cima a una colonna, a piedi nessuna via: si alza in volo e scende (#{(e[:z] / M).round(1)} m)")
F.explore_stop

# ── Zoom prima di avvicinarsi (profilo Fotografo) ───────────────────
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => true, 'profile' => 'photographer',
                              'zoom_fill' => 0.9)
fov0 = cam.fov
fmin = fov0
mosso = 0.0
dal = {}
run(view, 12.0) do |q|
  fmin = [fmin, cam.fov].min
  tg = q[:target]
  next unless tg && tg[:zoom] && %i[in hold].include?(tg[:zoom][:phase])
  p0 = (dal[tg[:id]] ||= [q[:x], q[:y]])
  mosso = [mosso, Math.hypot(q[:x] - p0[0], q[:y] - p0[1]) / M].max
end
rec = ex[:rec].map { |s| s[10] }.min
F.explore_stop
ok(fmin < fov0 / 1.5 && mosso < 0.05 && rec < fov0 / 1.5 && (cam.fov - fov0).abs < 1e-6,
   "zoom ×#{(fov0 / fmin).round(1)} fermo sul posto (#{(mosso * 100).round(1)} cm), registrato nel percorso; alla fine la camera torna a #{fov0}°")
model.dicts.clear

# ── Profili (lib/exprofiles.rb) ─────────────────────────────────────
c = F.instance_variable_get(:@cfg)
o = F.explore_opts('profile' => 'runner')
ok(o['speed'] == 3.2 && o['profile'] == 'runner' && F.explore_opts('profile' => F.t('xp.p.runner'))['speed'] == 3.2,
   'profilo per id o per nome: Corridore a 3,2 m/s')
ok(F.explore_profile_list.map { |p| p['id'] } == %w[balanced curious runner slow photographer carefree soldier], 'sette profili già pronti')
F.explore_profile_set('runner', 'speed', 9)
ok(F.explore_profile_full('runner')['speed'] == 4.0 && F.explore_profile_modified?('runner'), 'valore cambiato (nei limiti): profilo modificato')
F.explore_profile_set('runner', 'speed', 3.2)
ok(!F.explore_profile_modified?('runner') && !c['explore_profiles'].key?('runner'), 'tornato al valore originale: niente da ricordare')
F.explore_profile_set('runner', 'dwell', 3)
F.explore_profile_reset('runner')
ok(!F.explore_profile_modified?('runner'), 'Ripristina')
id = F.explore_profile_new('photographer')
ok(F.explore_profile_id == id && F.explore_profile_name(id) == format(F.t('xp.copy_of'), name: F.t('xp.p.photographer')) &&
   F.explore_profile_full(id)['zoom'] == true, "Nuovo: copia del Fotografo, in uso («#{F.explore_profile_name(id)}»)")
F.explore_profile_rename(id, "  Il mio\n ")
id2 = F.explore_profile_new(id)
F.explore_profile_rename(id2, 'il MIO')
ok(F.explore_profile_name(id) == 'Il mio' && F.explore_profile_name(id2) == 'il MIO 2' && F.explore_profile_find('IL MIO') == id,
   'Rinomina: nomi senza doppioni, si trova per nome')
salvato = JSON.parse(File.read(File.join(tmp, 'settings.json'), encoding: 'UTF-8'))
ok(salvato['explore_profile'] == id2 && salvato['explore_profiles'][id]['name'] == 'Il mio', 'nel settings.json')
F.explore_profile_delete(id2)
ok(F.explore_profile_id == 'balanced' && !F.explore_profile?(id2), 'Elimina il profilo in uso: torna Equilibrato')
ok(!F.explore_profile_set('curious', 'grid', 40) && !F.explore_profile_delete('curious') && !F.explore_profile_rename('curious', 'x'),
   'chiavi tecniche e profili già pronti: non si toccano così')
c['explore_profiles']['rotto'] = 'non un oggetto'
c['explore_profile'] = 'rotto'
ok(F.explore_profile_id == 'balanced' && F.explore_profile_list.size == 8, 'settings.json rovinato a mano: si ignora')
c['explore_profiles'].delete('rotto')

model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false)
F.explore_profile_use(id)
ok(ex[:o]['profile'] == id && ex[:o]['zoom'] == true, 'cambiato profilo mentre esplora: vale subito')
F.explore_profile_set(id, 'speed', 2.5)
ok(ex[:speed] == 2.5, 'cambiato un valore del profilo in uso: vale subito')
r = F.explore_command('profile', F.t('xp.p.curious'))
ok(r['profile']['id'] == 'curious' && F.explore_command('profiles')['profiles'].size == 8 &&
   F.explore_command('profile', 'boh')['ok'] == false, 'dal ponte: profilo per nome, elenco, sconosciuto')
F.explore_command('profile', 'balanced')
F.explore_stop

# Soldato: ricognizione, copre le due stanze molto prima del Corridore
copre = lambda do |prof|
  fresh(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7], 'record' => false, 'profile' => prof)
  t0 = $now
  quando = nil
  run(ex[:view], 30.0) { |e| quando ||= $now - t0 if e[:plan].count { |_, v| v & F::PL_FREE != 0 } >= 650 }
  F.explore_stop
  quando || 99.0
end
sol = copre.('soldier')
cor = copre.('runner')
ok(sol < 10.0 && sol < 0.6 * cor, "Soldato: 650 celle viste in #{sol.round(1)} s (Corridore #{cor.round(1)} s)")
# camera a 4,5 m dal pavimento (stanza B, senza soffitto): Equilibrato (auto) vola, il Soldato scende a terra e cammina
fresh(world, [6.5, -1.5, 4.5], [0, 0.5, 3.0], 'record' => false)
vola = ex[:mode]
fresh(world, [6.5, -1.5, 4.5], [0, 0.5, 3.0], 'record' => false, 'profile' => 'soldier')
modi = []
run(ex[:view], 10.0) { |e| modi << e[:mode] }
ok(vola == :fly && modi.uniq == [:walk] && (ex[:z] - ex[:floor] - ex[:eye_h]).abs < 0.05 * M,
   "Soldato da una camera alta: sempre a piedi, occhi a #{((ex[:z] - ex[:floor]) / M).round(2)} m (Equilibrato: #{vola})")
F.explore_stop

# Finestra di avvio: il pulsante la apre (fermo) o ferma; le scelte restano
aperta = 0
xs_vero = F.method(:xs_open)
F.define_singleton_method(:xs_open) { aperta += 1 }
F.explore_toggle
ok(aperta == 1 && !F.explore_on?, 'pulsante, esploratore fermo: si apre la finestra di avvio, non parte ancora')
err = F.explore_launch(id, false)
ok(err.nil? && ex && ex[:o]['profile'] == id && ex[:o]['record'] == false && F.explore_profile_id == id && !F.explore_record?,
   'Esplora: parte col profilo scelto e senza registrare; le due scelte salvate')
salvato = JSON.parse(File.read(File.join(tmp, 'settings.json'), encoding: 'UTF-8'))
ok(salvato['explore_record'] == false && salvato['explore_profile'] == id, 'nel settings.json')
F.explore_toggle
ok(!F.explore_on? && aperta == 1, 'pulsante mentre esplora: si ferma (niente finestra)')
F.explore_launch('balanced', true)
ok(ex[:o]['record'] == true && F.explore_record?, 'di nuovo con la registrazione')
F.explore_stop
model.dicts.clear
F.instance_variable_set(:@active, true)
F.explore_toggle
ok(aperta == 1 && F.explore_launch('balanced', true) == F.t('rt.explore_busy'), 'occupato (camminata): niente finestra, e non parte')
F.instance_variable_set(:@active, nil)
F.define_singleton_method(:xs_open, xs_vero)
F.explore_profile_delete(id)

# Pesi: ciò che lo attira conta in proporzione
w1 = F.explore_weights(F.explore_opts(nil))
ok(w1 == F::EX_W, 'pesi a 1: quelli di sempre')
model, view, cam = Scena.setup(world, [-6.5, 0.5, 1.7], [0, 0.5, 1.7])
rays = F.explore_rays(view, 32, 18)
ctx = { memo: {}, omemo: {}, size: {}, fseq: 0, oseq: 0 }
cells = F.explore_cast(model, rays, ctx)
tav = ->(r) { r[:cands].find { |q| q[:label] == 'Tavolo' }[:score] }
s1 = tav.(F.explore_saliency(cells, 32, 18, rays: rays))
s0 = tav.(F.explore_saliency(cells, 32, 18, rays: rays, w: F.explore_weights(F.explore_opts('w_object' => 0)), objw: 0.0))
ok(s0 < s1 * 0.75, "senza interesse per gli oggetti il tavolo spicca meno (#{s1.round(2)} → #{s0.round(2)})")

# ── Galleria: foto con che cosa e perché (lib/gallery.rb) ──
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, -3, 1.7], 'record' => false)
r = F.explore_command('steer', 'snap' => 'bella vista')
ok(!ex[:snaps] && ex[:gal].nil? && r['rejected'].any? { |x| x['item'] == 'snap' },
   "un giro che non diventa un percorso non fotografa; l'IA lo sa (#{r['rejected'].map { |x| x['why'] }.join(' | ')})")
F.instance_variable_set(:@gal_always, true)        # come con il percorso, senza salvarlo
model, view, cam, err = fresh(world, [-6.5, 0.5, 1.7], [0, -3, 1.7], 'record' => false)
run(view, 45.0) { |e| break if e[:gal_st][:n] >= 2 }
gal = ex[:gal]
fotos = gal ? gal[:data]['photos'] : []
ok(fotos.size >= 1 && fotos.all? { |p| p['by'] == 'explorer' && File.exist?(File.join(gal[:dir], p['file'])) && p['w'] == 96 } &&
   F.gal_read(gal[:dir])['photos'].size == fotos.size,
   "l'esploratore fotografa da sé le mete migliori: #{fotos.map { |p| "#{p['title']} a #{p['t']} s" }.join(', ')}")
perche = [F.t('gal.why.best'), F.t('gal.why.top')]
ok(fotos.any? && fotos.all? { |p| perche.any? { |w| p['why'].to_s.start_with?(w) } && p['what'].to_s.size > 5 && p['what'] !~ /gal\./ },
   "con che cosa e perché: «#{fotos[0] && fotos[0]['what']}» — «#{fotos[0] && fotos[0]['why']}»")
n0 = fotos.size
r = F.explore_command('steer', 'snap' => 'Mi piace la luce', 'say' => 'La stanza </script> dalla porta')
run(view, 0.2)
ultima = gal[:data]['photos'].last
ok(r['rejected'].empty? && gal[:data]['photos'].size == n0 + 1 && ultima['by'] == 'ai' && ultima['why'] == 'Mi piace la luce' &&
   ultima['what'] == 'La stanza </script> dalla porta' && ultima['title'].nil?,
   "snap dell'IA: subito, col suo perché e il suo che cosa")
ev = ex[:events].reverse.find { |v| v['type'] == 'snap' }
ok(ev && ev['by'] == 'ai' && File.exist?(ev['file'].to_s) && !F.pilot_wake?(ex, [ev]), 'avviso snap col file, che non sveglia il pilota')
ok(F.gal_seen_here?(ex) && ex[:gal_st][:poses].size == gal[:data]['photos'].size, "da qui c'è già una foto: l'esploratore non la rifà")
statua_id = F.explore_percept(0)['things'].find { |t| t['label'] == 'Statua' }&.fetch('id')
r = F.explore_command('steer', 'agenda' => [{ 'look' => statua_id, 'dwell' => 0.5, 'snap' => 'Il bronzo', 'say' => 'La statua' }])
run(view, 20.0) { |e| break if e[:events].any? { |v| v['type'] == 'done' && v['id'] == statua_id } }
bronzo = gal[:data]['photos'].find { |p| p['why'] == 'Il bronzo' }
ok(r['agenda'][0] && r['agenda'][0]['snap'] == 'Il bronzo' && bronzo && bronzo['by'] == 'ai' && bronzo['what'] == 'La statua' &&
   bronzo['title'] == 'Statua',
   "snap in una voce: all'arrivo, col say come che cosa (foto #{bronzo && bronzo['n']})")
gia = F.method(:gal_seen_here?)
F.define_singleton_method(:gal_seen_here?) { |_ex| true }
r = F.explore_command('steer', 'agenda' => [{ 'look' => statua_id, 'dwell' => 0.5, 'snap' => 'Ancora', 'say' => 'Di nuovo' }])
run(view, 20.0) { |e| break if e[:events].count { |v| v['type'] == 'done' && v['id'] == statua_id } >= 2 }
F.define_singleton_method(:gal_seen_here?, gia)
ok(gal[:data]['photos'].any? { |p| p['why'] == 'Ancora' }, "l'IA la chiede da dove ce n'è già una: si scatta lo stesso")
# il percorso tiene la cartella; la serie sa di che percorso è, col giro in pianta
salvato = F.explore_save_path(ex.merge(rec: [[0.0, 0.0, 0.0, 0.0] + [0.0] * 7, [ex[:t].round(3) + 1, 2 * M, M, 0.0] + [0.0] * 7]))
dati = F.path_data(salvato, model)
ok(dati['gallery'] == gal[:dir] && dati['photos'] == gal[:data]['photos'].size, "il percorso salvato tiene le sue foto (#{dati['photos']})")
F.gal_finish(gal, salvato, [[0.0, 0.0, 0.0, 0.0], [5.0, 2 * M, M, 0.0]])
ok(F.gal_read(gal[:dir])['path'] == salvato && F.gal_read(gal[:dir])['track'] == [[0.0, 0.0, 0.0], [2.0, 1.0, 5.0]],
   'la serie sa di che percorso è, col giro in pianta (m)')
pagina = F.instance_variable_get(:@lang_code)
html_file = F.gal_report(gal[:dir], salvato)
html = File.read(html_file, encoding: 'UTF-8')
dati_pagina = JSON.parse(html[/const D = (\{.*?\}) \|\| \{/m, 1].to_s) rescue nil
ok(dati_pagina && dati_pagina['title'] == salvato && dati_pagina['photos'].size == gal[:data]['photos'].size &&
   dati_pagina['txt']['why'] == F.t('gal.why') && dati_pagina['lang'] == pagina && dati_pagina['track'].size == 2 &&
   html.scan('</script>').size == 1 && !html.include?('/*DATI*/'),
   "galleria.html accanto alle foto, coi dati dentro (un </script> nei testi non la rompe)")
ok(html.include?('/*MODIFICHE*/null/*FINE*/'), 'senza modifiche: il loro posto nella pagina, vuoto')
# le modifiche di chi guarda (le scrive la pagina): nella pagina, fra i loro segni, e mai prese per HTML
mod_file = File.join(gal[:dir], F::GAL_EDITS)
File.write(mod_file, JSON.generate('v' => 1, 'title' => 'Sera </script><!-- */', 'photos' => { '1' => { 'what' => 'Il cratere' } }), mode: 'wb')
html = File.read(F.gal_report(gal[:dir], salvato), encoding: 'UTF-8')
mod_js = html[%r{/\*MODIFICHE\*/(.*?)/\*FINE\*/}m, 1].to_s
ok(JSON.parse(mod_js)['photos']['1']['what'] == 'Il cratere' && JSON.parse(mod_js)['title'] == 'Sera </script><!-- */' &&
   html.scan('</script>').size == 1 && !mod_js.include?('<') && !mod_js.include?('*/'),
   'galleria_modifiche.json nella pagina; </script>, <!-- e */ nei testi non la rompono')
File.write(mod_file, '{rotto', mode: 'wb')
ok(File.read(F.gal_report(gal[:dir], salvato), encoding: 'UTF-8').include?('/*MODIFICHE*/null/*FINE*/'), 'un file di modifiche rotto: la galleria si apre senza')
File.delete(mod_file)
ok(F.gal_url('C:\\Foto mie\\è #1.html') == 'file:///C:/Foto%20mie/%C3%A8%20%231.html', 'indirizzo file:/// della galleria, con spazi e accenti')
aperto = nil
UI.define_singleton_method(:openURL) { |u| aperto = u }
F.gal_open(gal[:dir], salvato)
ok(aperto == F.gal_url(html_file) && F.gal_open(File.join(tmp, 'non c è'), 'x').to_s.include?('non c è'),
   'si apre nel browser; una cartella sparita lo dice')
altra = F.gal_new(model)
F.gal_shoot(view, altra, 'by' => 'you', 'what' => 'x')
sciolte = F.gal_loose(model).map { |g| g['id'] }
ok(sciolte.include?(File.basename(altra[:dir])) && !sciolte.include?(File.basename(gal[:dir])),
   'serie senza percorso a parte; quella del percorso no')
ok(F.gal_open_loose('../x').nil? && F.gal_open_loose(File.basename(altra[:dir])).nil? && aperto.include?(File.basename(altra[:dir])),
   'una serie senza percorso si apre per il nome della cartella, niente percorsi fuori')
# 📷 nel pannello: la galleria del percorso, coi commenti dell'IA; un percorso senza foto spiega come farne
ok(F.gal_open_path(salvato).nil? && aperto == F.gal_url(html_file), '📷 di un percorso: la sua galleria')
pg = JSON.parse(File.read(html_file, encoding: 'UTF-8')[/const D = (\{.*?\}) \|\| \{/m, 1].to_s) rescue {}
ok(pg['id'] == File.basename(gal[:dir]) && pg['notes'] == F.path_notes(dati) && pg['notes'].size == dati['notes'].to_a.size &&
   F::GAL_TXT.all? { |k, v| pg['txt'][k] == F.t(v) && pg['txt'][k] != v },
   "nella pagina i commenti dell'IA lungo il giro (#{pg['notes'].to_a.size}) e i #{F::GAL_TXT.size} testi tradotti")
F.path_write('x', model) { |m| m.set_attribute(F::PATH_DICT, 'Senza foto', JSON.generate('date' => '1', 's' => [[0.0] * 11, [1.0] + [0.0] * 10])) }
nessuna = F.gal_open_path('Senza foto')
ok(nessuna == format(F.t('gal.none'), key: F.key_label('photo')) && nessuna.include?('P'), "senza foto: «#{nessuna.to_s.lines.first.strip}…», col tasto")
F.gal_renamed(dati, 'Nome nuovo', model)
ok(F.gal_read(gal[:dir])['path'] == 'Nome nuovo', 'percorso rinominato: la serie lo sa')
F.explore_stop
run_timers
# chi cammina: P fotografa la vista, durante una registrazione la foto va col percorso
F.instance_variable_set(:@gal_loose, nil)
fuori = F.gal_human(view, 5.0)
ok(fuori && fuori['by'] == 'you' && fuori['t'].nil? && fuori['what'].to_s.size > 3 && $status.include?('1') && F.gal_flash.to_f > 0,
   "foto di chi cammina, fuori da una registrazione: «#{fuori && fuori['what']}», col lampo")
F.instance_variable_get(:@cfg)['no_flashes'] = true
ok(F.gal_flash.nil? && F.instance_variable_get(:@gal_flash).nil?, 'Accessibilità › Niente lampi: lo scatto non fa lampo')
F.instance_variable_get(:@cfg)['no_flashes'] = false
F.instance_variable_set(:@path_rec, { t0: 0.0, last: nil, shown: -1,
                                      s: [[0.0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 60], [5.0, 3 * M, 0, 0, 1, 0, 0, 0, 0, 1, 60]] })
dentro = F.gal_human(view, 2.5)
rec = F.instance_variable_get(:@path_rec)
nome = F.path_rec_stop
dd = nome && F.path_data(nome, model)
ok(dentro && dentro['t'] == 2.5 && dd && dd['gallery'] == rec[:gal][:dir] && dd['photos'] == 1 &&
   F.gal_read(rec[:gal][:dir])['path'] == nome && F.gal_read(rec[:gal][:dir])['track'].size == 2,
   "registrando: la foto va col percorso «#{nome}», al secondo #{dentro && dentro['t']}")
F.instance_variable_set(:@gal_always, nil)
# La cartella della serie nel percorso: relativa al modello, ritrovata se il modello si sposta con le sue foto
casa = Struct.new(:path, :title).new(File.join(tmp, 'casa.skp'), 'casa')
serie = File.join(File.expand_path(tmp), 'casa_foto', '2026-01-01_10-00-00')
FileUtils.mkdir_p(serie)
File.write(File.join(serie, F::GAL_JSON), '{"photos":[]}')
ok(F.gal_ref(serie, casa) == 'casa_foto/2026-01-01_10-00-00' && F.gal_ref('D:/altrove/x', casa) == 'D:/altrove/x' &&
   F.gal_ref(serie, model) == serie, 'nel percorso la serie è relativa al modello (se ci sta accanto; un modello mai salvato no)')
ok(F.gal_dir('casa_foto/2026-01-01_10-00-00', casa) == serie && F.gal_dir('Z:/vecchio/posto/casa_foto/2026-01-01_10-00-00', casa) == serie &&
   F.gal_dir('', casa).nil?, 'e si ritrova: relativa, o assoluta di prima che il modello si spostasse')
# Accanto al modello non si può scrivere: in riserva (nei test una cartella dei test, se no %APPDATA%/DagaWASD/foto)
File.write(File.join(tmp, 'un_file'), 'x')
F.instance_variable_set(:@gal_root, File.join(tmp, 'un_file', 'foto'))
F.define_singleton_method(:gal_spare_root) { File.join(tmp, 'riserva') }
ris = F.gal_new(model)
F.instance_variable_set(:@gal_root, File.join(tmp, 'foto'))
ok(ris && File.dirname(ris[:dir]) == File.join(tmp, 'riserva') && File.directory?(ris[:dir]), 'cartella del modello in sola lettura: le foto in riserva')
ok(F.gal_spare?(ris[:dir]) && !F.gal_spare?(File.join(tmp, 'foto', 'x')) && !F.gal_spare?(File.join(tmp, 'riserva_altra', 'x')),
   'una serie in riserva (%APPDATA%) la galleria lo sa: lì il browser non sceglie cartelle, si scaricano le modifiche')
# La graduatoria: una meta vista prima e ora raggiunta conta una volta, col suo punteggio di allora
exg = { snaps: true, snap_want: nil, x: 0.0, y: 0.0, yaw: 0.0, gal_st: { n: 0, t: -1e9, open_t: -1e9, scores: [1.0, 5.0], ids: [], poses: [] } }
F.gal_consider(exg, { id: 'a', score: 6.0, gal_rank: 1.0 }, 100.0)
ok(exg[:gal_st][:scores] == [5.0, 6.0] && exg[:snap_want] && exg[:snap_want][:why].start_with?(F.t('gal.why.best')),
   "rivista: via il suo punteggio di prima (1), non l'ultimo della lista (#{exg[:gal_st][:scores].inspect})")

# (la camminata FPS avviata più su scrive i suoi: la scena finta non ha osservatori)
log = File.exist?(File.join(tmp, 'test.log')) ? File.read(File.join(tmp, 'test.log'), encoding: 'UTF-8') : ''
mie = log.scan(/^\S+ \S+ \[((?:explore|key_|ke_|bridge|path)\w*\??)\] ([^\n]*)/)
ok(mie.empty?, "nessun errore dell'esploratore nel registro#{mie.empty? ? '' : ": #{mie.first(3).inspect[0, 400]}"}")

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
