# Posizioni dei percorsi (lib/pathkeys.rb): sfere con freccia nel modello,
# curva a velocità costante, schematizzazione della registrazione, comandi
# del pannello, tag spento durante la riproduzione, Overlay (SketchUp finto).
#   Esecuzione:  ruby -E UTF-8 tests/test_pathkeys.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
MB_YESNO = 4 unless defined?(MB_YESNO)
IDYES = 6 unless defined?(IDYES)
IDNO = 7 unless defined?(IDNO)

tmp = Dir.mktmpdir('dagawasd_posizioni')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.instance_variable_set(:@settings_file, File.join(tmp, 'settings.json'))
F.load_cfg
cfg = F.instance_variable_get(:@cfg)
cfg['language'] = 'it'
F.load_lang
M = F::M_TO_IN

# ── SketchUp finto: quanto usano le posizioni ────────────────────────
module Geom
  class PolygonMesh
    AUTO_SOFTEN = 4; SMOOTH_SOFT_EDGES = 8
    attr_reader :polys
    def initialize(*); @polys = []; end
    def add_polygon(*pts); @polys << pts.flatten; end
  end
end
module Sketchup
  class Color
    attr_reader :rgb
    def initialize(*rgb); @rgb = rgb; end
  end
end
module Attrs
  def attrs; @attrs ||= {}; end
  def get_attribute(d, k, default = nil); attrs.fetch(d, {}).fetch(k, default); end
  def set_attribute(d, k, v); (attrs[d] ||= {})[k] = v; end
end
class Layer
  attr_accessor :name, :visible
  def initialize(n); @name = n; @visible = true; end
  def visible?; @visible; end
end
class Layers < Hash
  def add(n); self[n] = Layer.new(n); end
end
class Mat
  attr_accessor :name, :color
  def initialize(n); @name = n; end
end
class Mats < Hash
  def add(n); self[n] = Mat.new(n); end
end
class DefEnts
  attr_reader :meshes, :lines
  def initialize; @meshes = []; @lines = []; end
  def add_faces_from_mesh(mesh, flags, mat = nil, back = nil); @meshes << [mesh, flags, mat, back]; end
  def add_line(a, b); @lines << [a, b]; end
  def clear!; @meshes.clear; @lines.clear; end
end
class FakeDefn < Sketchup::ComponentDefinition
  include Attrs
  attr_accessor :name, :description, :model
  attr_reader :entities, :instances
  def initialize(n, m); @name = n; @model = m; @entities = DefEnts.new; @instances = []; @ok = true; end
  def valid?; @ok; end
  def kill!; @ok = false; end
end
class Defs < Array
  attr_accessor :model
  def add(n); d = FakeDefn.new(n, model); self << d; d; end
  def remove(d); d.kill!; delete(d); true; end
end
$next_id = 100
class Inst < Sketchup::ComponentInstance
  include Attrs
  attr_accessor :transformation, :material, :layer, :name, :parent
  attr_reader :definition, :entityID
  def initialize(d, tr, parent); @definition = d; @transformation = tr; @parent = parent; @hidden = false; @ok = true
                                  @entityID = ($next_id += 1); end
  def definition=(d); @definition.instances.delete(self); @definition = d; d.instances << self; end
  def hidden?; @hidden; end
  def hidden=(v); @hidden = v; end
  def valid?; @ok; end
  def erase!; @ok = false; @definition.instances.delete(self); end
  # Ctrl+Sposta: stessa definizione e attributi, altra trasformazione
  def copy_to(tr)
    c = Inst.new(@definition, tr, @parent)
    attrs.each { |d, h| h.each { |k, v| c.set_attribute(d, k, v) } }
    @definition.instances << c
    c
  end
end
class ModelEnts < Array
  def add_instance(d, tr); e = Inst.new(d, tr, $pm); d.instances << e; self << e; e; end
  def erase_entities(list); list.each { |e| e.erase!; delete(e) }; end
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
  attr_accessor :camera, :model
  attr_reader :anim, :drawn, :texts
  attr_writer :line_width, :line_stipple, :drawing_color
  def animation=(a); old = @anim; @anim = a; old.stop if old.respond_to?(:stop) && !old.equal?(a); end
  def initialize; @camera = Cam.new; @drawn = []; @texts = []; end
  def invalidate; end
  def draw(kind, pts); @drawn << [kind, pts]; end
  def screen_coords(p); Geom::Point3d.new(p.x, p.y, 0); end
  def draw_text(p, s, o = {}); @texts << [p, s, o]; end
end
class Dict < Hash
  def delete_key(k); delete(k); end
end
class FakeModel
  attr_accessor :active_path
  attr_reader :view, :dicts, :ops, :tools_sel, :layers, :materials, :definitions, :entities
  def initialize
    @view = FakeView.new; @view.model = self; @dicts = {}; @ops = []; @tools_sel = []
    @layers = Layers.new; @materials = Mats.new; @definitions = Defs.new; @definitions.model = self; @entities = ModelEnts.new
  end
  def active_view; @view; end
  def attribute_dictionary(n, create = false); @dicts[n] ||= Dict.new if create; @dicts[n]; end
  def set_attribute(d, k, v); attribute_dictionary(d, true)[k] = v; end
  def attribute_dictionaries; dd = @dicts; o = Object.new; o.define_singleton_method(:delete) { |d| dd.delete(dd.key(d)) }; o; end
  def start_operation(name, *a); @ops << [:start, name, *a]; true; end
  def commit_operation; @ops << [:commit]; true; end
  def abort_operation; @ops << [:abort]; true; end
  def select_tool(t); @tools_sel << t; end
  def add_observer(_o); true; end
  def valid?; true; end
  def path; ''; end
end
$pm = pm = FakeModel.new
Sketchup.define_singleton_method(:active_model) { pm }
view = pm.view
boxes = []
UI.define_singleton_method(:messagebox) { |msg, *_a| boxes << msg; $answer || IDYES }
F.key_attach(pm)

# Una posizione: occhio (m), direzione e alto
key = ->(x, y, z, d = [1, 0, 0], u = [0, 0, 1]) { [x * M, y * M, z * M, *d.map(&:to_f), *u.map(&:to_f), 60.0] }
near = ->(a, b, tol = 1e-6) { a.zip(b).all? { |p, q| (p - q).abs < tol } }

# ── Curva e tempi ────────────────────────────────────────────────────
dritta = [key.(0, 0, 1.7), key.(4, 0, 1.7), key.(10, 0, 1.7)]
fr = F.key_frames(dritta, 2.0)
dur = (fr.size - 1) / F::PATH_HZ
ok((dur - 5.0).abs < 0.05, "10 m a 2 m/s: #{dur.round(2)} s")
passi = fr.each_cons(2).map { |a, b| F.key_dist3(a, b) / M * F::PATH_HZ }
ok(passi[1..-2].all? { |v| (v - 2.0).abs < 0.05 }, "velocità costante anche a cavallo delle posizioni (#{passi.min.round(3)}–#{passi.max.round(3)} m/s)")
ok(near.(fr.first[0, 3], dritta.first[0, 3]) && near.(fr.last[0, 3], dritta.last[0, 3]), 'parte e arriva esattamente sulle sfere')

giro = [key.(0, 0, 1.7, [1, 0, 0]), key.(0, 0, 1.7, [0, 1, 0])]
fr = F.key_frames(giro, 2.0)
ok(((fr.size - 1) / F::PATH_HZ - 2.0).abs < 0.05, "girarsi di 90° sul posto: #{((fr.size - 1) / F::PATH_HZ).round(2)} s a 45°/s")
ok(fr.all? { |f| near.(f[0, 3], giro.first[0, 3]) }, 'sul posto la camera non si sposta')
ang = fr.map { |f| Math.atan2(f[4], f[3]) * 180 / Math::PI }
ok(ang.each_cons(2).all? { |a, b| b >= a - 1e-9 } && (ang[fr.size / 2] - 45).abs < 3, 'lo sguardo gira con continuità, a metà tempo a metà giro')

elle = [key.(0, 0, 1.7), key.(6, 0, 1.7), key.(6, 6, 1.7, [0, 1, 0])]
fr = F.key_frames(elle, 1.4)
ok(fr.map { |f| F.key_dist3(f, elle[1]) }.min < 0.02 * M, 'la curva passa per la sfera di mezzo')
fuori = fr.map { |f| [-f[1], f[0] - 6 * M].max }.max / M
ok(fuori < 0.3, "spigolo a 90°: la curva lo gira uscendo di #{(fuori * 100).round} cm su tratti di 6 m")
ok(fr.all? { |f| (Math.sqrt(f[3]**2 + f[4]**2 + f[5]**2) - 1).abs < 1e-9 && (f[3] * f[6] + f[4] * f[7] + f[5] * f[8]).abs < 1e-9 },
   'direzione unitaria, alto perpendicolare')
ok((F.key_duration(elle, 1.4) - (fr.size - 1) / F::PATH_HZ).abs < 1.0 / F::PATH_HZ + 1e-9, 'durata per il pannello = durata dei fotogrammi')
corto = [key.(0, 0, 1.7), key.(0.5, 0, 1.7), key.(0.5, 10, 1.7)]
fr = F.key_frames(corto, 1.4)
fuori = fr.map { |f| [-f[1], f[0] - 0.5 * M].max }.max / M
ok(fuori < 0.04, "tratto corto accanto a uno lungo: nessuna ansa (#{(fuori * 100).round(1)} cm fuori; tangenti pesate sulle distanze)")
curva = (0..8).map { |i| a = i / 8.0 * Math::PI / 2; key.(10 * Math.sin(a), 10 - 10 * Math.cos(a), 1.7) }
fr = F.key_frames(curva, 1.4)
r = fr.map { |f| Math.sqrt((f[0] / M)**2 + (f[1] / M - 10)**2) }
dentro = r[r.size / 8, r.size * 6 / 8].map { |x| (x - 10).abs }.max
ok(dentro < 0.005 && r.all? { |x| (x - 10).abs < 0.04 },
   "posizioni lungo un arco di 10 m: la curva resta sull'arco (#{(dentro * 1000).round(1)} mm; ai capi la corda, qualche cm)")

# ── Dalla registrazione alle posizioni ───────────────────────────────
# 6 m dritti, sosta di 2 s guardandosi a sinistra, 6 m a sinistra; 30 Hz
rec = []
180.times { |i| rec << key.(i / 30.0, 0, 1.7) }
60.times { |i| a = i / 59.0 * Math::PI / 2; rec << key.(6, 0, 1.7, [Math.cos(a), Math.sin(a), 0]) }
181.times { |i| rec << key.(6, i / 30.0, 1.7, [0, 1, 0]) }
ks = F.key_from_frames(rec)
ok(ks.size.between?(4, 9) && near.(ks.first, rec.first) && near.(ks.last, rec.last), "#{rec.size} fotogrammi → #{ks.size} posizioni, i capi compresi")
fr = F.key_frames(ks, 1.0)
err = rec.map { |r| fr.map { |f| F.key_dist3(f, r) }.min }.max
ok(err < F::KEY_TOL * 1.5, "la curva delle posizioni resta vicina al percorso registrato (scarto massimo #{(err / M * 100).round(1)} cm)")
v = F.key_rec_speed(rec)
ok((v - 1.0).abs < 0.05, "velocità media senza contare la sosta: #{v.round(3)} m/s")

# ── Componente, trasformazione ───────────────────────────────────────
k0 = key.(1, 2, 1.6, [0.6, 0.8, 0], [0, 0, 1])
tr = F.key_transform(k0)
e = Inst.new(nil, tr, pm)
ok(near.(F.key_of(e)[0, 9], k0[0, 9]), 'posizione → trasformazione → posizione: uguale')
scala = Geom::Transformation.new(tr.to_a.each_with_index.map { |x, i| i < 11 && i % 4 != 3 ? x * 3 : x })
ok(near.(F.key_of(Inst.new(nil, scala, pm))[0, 9], k0[0, 9]), 'una sfera ingrandita conta come prima')

# ── «Modifica» su un percorso registrato ─────────────────────────────
s = rec.each_with_index.map { |r, i| [(i / 30.0).round(3), *r] }
pm.set_attribute(F::PATH_DICT, 'Giro', JSON.generate('date' => '2026-10-13 10:00:00', 's' => s))
ok(F.path_list.first['keys'].zero? && F.path_list.first['rec'], 'prima: nessuna posizione, la registrazione sì')
t_rec = F.path_track('Giro')[:dur]
F.path_command('edit', 'Giro')
defn = pm.definitions.first
inst = pm.entities.dup
ok(pm.definitions.size == 1 && defn.get_attribute(F::KEY_DICT, 'def') == F::KEY_DEF_V && defn.get_attribute(F::KEY_DICT, 'fov') == 60 &&
   defn.entities.meshes.size == 3, 'registrazione senza zoom (60°): un componente, sfera, freccia, riquadro (niente perno)')
ok(defn.entities.meshes[0][2].nil? && defn.entities.meshes[1][2].name == 'DagaWASD freccia', 'la sfera prende il colore dell\'istanza, la freccia è rossa')
# Il riquadro: davanti alla sfera, perpendicolare alla freccia, più largo che
# alto (16:9), col triangolo sopra: una rotazione attorno alla freccia si vede
riq = defn.entities.meshes[2]
pts = riq[0].instance_variable_get(:@polys).flatten   # il PolygonMesh finto tiene i punti
ys = pts.map(&:y); zs = pts.map(&:z)
ok(pts.map(&:x).uniq.size == 1 && pts.first.x > F::KEY_R, 'riquadro su un piano davanti alla sfera, perpendicolare alla freccia')
ok((ys.max - ys.min) > (zs.max - zs.min) * 1.2 && zs.max > -zs.min * 1.5, 'più largo che alto, con la punta del triangolo sopra (l\'alto)')
ok(riq[2] && riq[3] && riq[2].name == 'DagaWASD alto', 'riquadro bianco da tutte e due le facce')
ok(defn.entities.lines.size == 4 && defn.entities.lines.all? { |a, _| (a.x**2 + a.y**2 + a.z**2 - F::KEY_R**2).abs < 1e-6 },
   'quattro spigoli dalla superficie della sfera agli angoli: il cono di vista')
ok(inst.size >= 4 && inst.all? { |x| x.layer == pm.layers[F::KEY_TAG] && x.material.name == 'DagaWASD posizione' && x.name == 'Giro' },
   "#{inst.size} sfere nel modello, col tag «#{F::KEY_TAG}»")
ok(inst.map { |x| x.get_attribute(F::KEY_DICT, 'i') } == (0...inst.size).to_a && inst.all? { |x| x.get_attribute(F::KEY_DICT, 'path') == 'Giro' },
   'ognuna sa di che percorso è e in che ordine')
ok(pm.ops.include?([:start, F.t('path.op_keys'), true]) && pm.ops.last == [:commit], 'un\'operazione annullabile')
ok((JSON.parse(pm.attribute_dictionary(F::PATH_DICT)['Giro'])['v'] - 1.0).abs < 0.05, 'la velocità della registrazione resta nel percorso')
pl = F.path_list.first
ok(pl['keys'] == inst.size && pl['shown'] && pl['rec'], 'pannello: quante posizioni, visibili, registrazione c\'è')
ok(pl['pts'].size == inst.size && pl['pts'].first['t'].zero? && pl['pts'].each_cons(2).all? { |a, b| b['t'] > a['t'] } &&
   pl['pts'].last['t'] <= pl['dur'] && pl['pts'].all? { |q| q['p'].zero? && q['v'].zero? && q['z'] > 0 },
   'pannello: per ogni posizione l\'arrivo (crescente), niente sosta né velocità propria, lo zoom')
tk = F.path_track('Giro')
ok(tk[:keys] == inst.size && (tk[:dur] - 14.0).abs < 0.3,
   "riproduzione dalle posizioni: #{tk[:dur].round(1)} s = 12 m a 1 m/s + 90° a 45°/s (registrata #{t_rec.round(1)} s)")

# Spostare una sfera cambia il percorso
mid = inst[inst.size / 2]
m = mid.transformation.to_a
m[14] += 1.0 * M
mid.transformation = Geom::Transformation.new(m)
ok(F.path_track('Giro')[:frames].map { |f| f[2] }.max > 2.5 * M, 'sfera alzata di 1 m: la camera ci passa')

# Copia (Ctrl+Sposta) fra l'ultima e la penultima
a, b = inst[-2], inst[-1]
pa = F.key_of(a); pb = F.key_of(b)
cm = b.transformation.to_a
cm[12] = (pa[0] + pb[0]) / 2; cm[13] = (pa[1] + pb[1]) / 2
copia = b.copy_to(Geom::Transformation.new(cm))   # copia dell'ultima, messa a metà dell'ultimo tratto
ord = F.key_instances(pm)['Giro']
ok(ord[-2].equal?(copia) && ord[-1].equal?(b), 'la copia dell\'ultima, portata indietro, va prima di lei')
F.key_fix_order(pm)
ok(ord.map { |x| x.get_attribute(F::KEY_DICT, 'i') } == (0...ord.size).to_a, 'e l\'ordine si riscrive')
ok(pm.ops[-2] == [:start, F.t('path.op_keys'), true, false, true], 'in un\'operazione trasparente (si annulla con la copia)')
n_ops = pm.ops.size
F.key_fix_order(pm)
ok(pm.ops.size == n_ops, 'niente da riordinare: nessuna operazione')

# Nascondi e mostra
F.path_command('edit', 'Giro')
ok(F.key_instances(pm)['Giro'].all?(&:hidden?) && !F.path_list.first['shown'], '«Nascondi»: sfere nascoste')
ok(F.path_track('Giro')[:keys] == ord.size, 'nascoste, il percorso le segue lo stesso')
pm.layers[F::KEY_TAG].visible = false
F.path_command('edit', 'Giro')
ok(F.key_instances(pm)['Giro'].none?(&:hidden?) && pm.layers[F::KEY_TAG].visible?, '«Mostra»: di nuovo visibili, tag compreso')

# ── Riproduzione: il tag si spegne e torna ───────────────────────────
F.instance_variable_set(:@active, false)
ok(F.path_start(:play, 'Giro').nil? && !pm.layers[F::KEY_TAG].visible?, 'durante la riproduzione le sfere non si vedono')
F::PathTool.new.onCancel(0, view)
ok(pm.layers[F::KEY_TAG].visible?, 'finita, tornano')
pm.layers[F::KEY_TAG].visible = false
F.path_start(:play, 'Giro')
F::PathTool.new.onCancel(0, view)
ok(!pm.layers[F::KEY_TAG].visible?, 'se il tag era già spento resta spento')
pm.layers[F::KEY_TAG].visible = true
ok(F.key_hide(pm) && !pm.layers[F::KEY_TAG].visible? && (F.key_unhide(pm, true) || true) && pm.layers[F::KEY_TAG].visible?,
   'modalità FPS: stesso spegni e riaccendi')
# FPS avviato con una sfera aperta in modifica: SketchUp darebbe ArgumentError
# («cannot hide layer that is a part of the active path», registro 2026-10-15)
sfera = F.key_instances(pm).values.flatten.first
pm.active_path = [sfera]
ok(!F.key_hide(pm) && pm.layers[F::KEY_TAG].visible?, 'dentro una sfera aperta il tag resta acceso, senza errori')
pm.active_path = nil

# ── Overlay: curva e numeri ──────────────────────────────────────────
view.camera.set(Geom::Point3d.new(-5 * M, 0, 66), Geom::Point3d.new(0, 0, 66), Geom::Vector3d.new(0, 0, 1))   # tutte davanti
F.key_draw(view)
ok(view.drawn.size == 1 && view.drawn[0][0] == GL_LINE_STRIP && view.drawn[0][1].size == (ord.size - 1) * F::KEY_SUB + 1,
   'Overlay: la curva fra le sfere')
ok(view.texts.map { |x| x[1] } == (1..ord.size).map(&:to_s), 'e il numero d\'ordine accanto a ognuna')
# Un muro fra l'occhio e le sfere: draw_text starebbe sopra a tutto (il «9»
# di una sfera dietro casa finiva sul tetto, 2026-10-17); la curva ha la profondità, resta
muro = Object.new
pm.define_singleton_method(:raytest) { |ray, *_| o, v = ray; [o.offset(v, 1 * M), [muro]] }
view.drawn.clear; view.texts.clear
F.key_draw(view)
ok(view.texts.empty? && view.drawn.size == 1, 'un muro davanti: niente numeri, la curva sì')
# davanti c'è solo un'altra sfera: il raggio prosegue oltre, il numero si scrive
altra = F.key_instances(pm).values.flatten.first
occhio = view.camera.eye
pm.define_singleton_method(:raytest) { |ray, *_| o, v = ray; o.distance(occhio) < 1 ? [o.offset(v, 1 * M), [altra]] : nil }
view.drawn.clear; view.texts.clear
F.key_draw(view)
ok(view.texts.size == ord.size, 'davanti solo un\'altra sfera (o la sua freccia): il numero si scrive')
pm.singleton_class.send(:remove_method, :raytest)
view.drawn.clear; view.texts.clear
# screen_coords senza risposta (registro 2026-10-17): quel numero si salta, gli altri no
view.define_singleton_method(:screen_coords) { |p| p.equal?(F.instance_variable_get(:@key_curves).values[0][2][0]) ? nil : Geom::Point3d.new(p.x, p.y, 0) }
F.key_draw(view)
ok(view.texts.size == ord.size - 1, 'un punto senza coordinate sullo schermo: solo il suo numero manca')
view.singleton_class.send(:remove_method, :screen_coords)
view.drawn.clear; view.texts.clear
view.camera.set(Geom::Point3d.new(20 * M, 0, 66), Geom::Point3d.new(30 * M, 0, 66), Geom::Vector3d.new(0, 0, 1))
F.key_draw(view)
ok(view.texts.empty?, 'numeri delle sfere alle spalle della camera: non disegnati')
view.drawn.clear
pm.layers[F::KEY_TAG].visible = false
F.key_draw(view)
F.instance_variable_set(:@path_job, {})
pm.layers[F::KEY_TAG].visible = true
F.key_draw(view)
F.instance_variable_set(:@path_job, nil)
ok(view.drawn.empty?, 'niente curva col tag spento o durante la riproduzione')

# ── Rinomina, torna alla registrazione, elimina ──────────────────────
UI.define_singleton_method(:inputbox) { |*_a| ['Giro lungo'] }
F.path_command('rename', 'Giro')
ok(F.key_instances(pm).keys == ['Giro lungo'] && F.key_instances(pm)['Giro lungo'].all? { |x| x.name == 'Giro lungo' }, 'rinominato: le sfere lo seguono')
$answer = IDNO
F.path_command('revert', 'Giro lungo')
ok(F.key_instances(pm)['Giro lungo'].size == ord.size, '«↺» non confermato: restano')
$answer = IDYES
F.path_command('revert', 'Giro lungo')
ok(F.key_instances(pm).empty? && F.path_track('Giro lungo')[:keys].zero?, '«↺»: via le sfere, si torna alla registrazione')

# ── Nuovo dalla vista ────────────────────────────────────────────────
view.camera.set(Geom::Point3d.new(0, 0, 66), Geom::Point3d.new(0, 100, 66), Geom::Vector3d.new(0, 0, 1))
F.path_command('new', '')
nuovo = F.path_list.find { |p| !p['rec'] }
ok(nuovo && nuovo['keys'] == 2 && nuovo['name'] == 'Percorso 1', 'nuovo percorso senza registrazione, con due sfere')
two = F.key_read('Percorso 1')
ok(near.(two[0][0, 3], [0, 0, 66], 1e-6) && near.(two[1][0, 3], [0, 3 * M, 66], 1e-6), 'la vista attuale e tre metri più avanti')
ok((F.path_track('Percorso 1')[:dur] - 3.0 / F::KEY_V).abs < 0.05, "si riproduce a #{F::KEY_V} m/s")
F.key_instances(pm)['Percorso 1'].first.erase!
ok(F.path_start(:play, 'Percorso 1') == format(F.t('path.no_keys'), name: 'Percorso 1'), 'con una sola sfera: messaggio invece della riproduzione')
F.path_command('delete', 'Percorso 1')
ok(F.key_instances(pm).empty? && F.path_list.map { |p| p['name'] } == ['Giro lungo'], 'eliminato il percorso: via anche le sue sfere')

# Senza più sfere il componente si toglie; si ritrova anche rinominato; cancellato si rifà
ok(pm.definitions.empty?, 'tolte tutte le sfere: tolto anche il componente (non resta fra gli inutilizzati)')
F.path_command('edit', 'Giro lungo')
defn = pm.definitions.first
defn.name = 'Telecamera'
F.instance_variable_set(:@key_defs, nil)
ok(F.key_defs(pm) == [defn] && F.key_def(pm, 60.4).equal?(defn), 'componente ritrovato per attributo e zoom, non per nome')
defn.kill!
pm.definitions.delete(defn)
F.path_command('edit', 'Giro lungo')
ok(pm.definitions.size == 1 && !pm.definitions.first.equal?(defn) && F.key_instances(pm)['Giro lungo'].size >= 4, 'componente sparito (eliminato dal modello): rifatto')

# ── Lo zoom: freccia lunga quanto l'ingrandimento ────────────────────
r = F::KEY_R
ok((F.key_arrow(F::KEY_FOV0) - 4.4 * r).abs < 1e-9, "senza zoom (#{F::KEY_FOV0.round}°) la freccia è di 4,4 raggi")
z2 = 2 * Math.atan(Math.tan(F::KEY_FOV0 * Math::PI / 360) / 2) * 180 / Math::PI    # ingrandimento 2×
ok((F.key_arrow(z2) - 8.8 * r).abs < 1e-6, "zoom 2× (#{z2.round(1)}°): freccia lunga il doppio")
ok(F.key_arrow(120) == 3.2 * r && F.key_arrow(5) == 18.0 * r, 'grandangolo: la freccia esce comunque dal riquadro; zoom estremo: al più 18 raggi')
punta = ->(d) { d.entities.meshes[1][0].instance_variable_get(:@polys).flatten.map(&:x).max }
d70 = F.key_def(pm, 70); d2 = F.key_def(pm, z2)
ok(!d70.equal?(d2) && (punta.(d70) - F.key_arrow(70)).abs < 1e-6 && (punta.(d2) / punta.(d70) - 2.0).abs < 0.05,
   'un componente per zoom: la punta sta dove dice key_arrow, al doppio per 2×')
ok(F.key_def(pm, 70.3).equal?(d70), 'zoom che arrotondano allo stesso grado condividono il componente')

# Lo zoom fatto con la rotella fa nascere una sfera anche fermi (prima si perdeva)
fermo = (0..30).map { |i| key.(0, 0, 1.6).tap { |k| k[9] = 70.0 - 35.0 * [i, 15].min / 15.0 } }
kz = F.key_from_frames(fermo)
ok(kz.size >= 3 && (kz.first[9] - 70).abs < 1e-6 && kz.any? { |k| (k[9] - 35).abs < 0.5 },
   "zoom da fermo (70° → 35°): #{kz.size} sfere, una dove lo zoom si ferma")
attesa = Math.log(F.key_zoom(35) / F.key_zoom(70)) / Math.log(2) / F::KEY_ZOOM_V
ok((F.key_duration(kz, 1.0) - attesa).abs < 0.1, "zoomare sul posto prende tempo: #{F.key_duration(kz, 1.0).round(2)} s (#{attesa.round(2)} attesi)")

# Sfere della forma vecchia (un componente unico per tutte, versione 2): alla
# prossima «Modifica» ognuna passa al componente del suo zoom, il vecchio si toglie
vecchio = pm.definitions.add('DagaWASD camera')
vecchio.set_attribute(F::KEY_DICT, 'def', 2)
sf = F.key_instances(pm)['Giro lungo']
sf.each { |e| e.definition = vecchio }
sf.first.set_attribute(F::KEY_DICT, 'fov', 35.0)
F.instance_variable_set(:@key_defs, nil)
ok(F.key_instances(pm)['Giro lungo'] == sf, 'le sfere col componente vecchio si ritrovano lo stesso')
F.path_command('edit', 'Giro lungo')     # le nasconde, e intanto le aggiorna
ok(!pm.definitions.include?(vecchio) && sf.all? { |e| e.definition.get_attribute(F::KEY_DICT, 'def') == F::KEY_DEF_V } &&
   sf.first.definition.get_attribute(F::KEY_DICT, 'fov') == 35 && sf.last.definition.get_attribute(F::KEY_DICT, 'fov') == 60,
   'forma vecchia: ogni sfera passa al componente del suo zoom, il vecchio si toglie')
ok(pm.definitions.all? { |d| !d.instances.empty? }, 'nessun componente delle sfere rimasto vuoto (quelli di 70° e 2×, senza sfere, tolti)')
F.path_command('delete', 'Giro lungo')
ok(pm.definitions.empty?, 'eliminato l\'ultimo percorso: via anche i suoi componenti')

# ══ Pannello della sfera (lib/keyedit.rb) ══════════════════════════════
module Attrs; def delete_attribute(d, k); attrs.fetch(d, {}).delete(k); end; end
class Inst; def model; $pm; end; end
class FakeView; def show_frame; end; end
class Sel < Array; def add(e); self << e unless include?(e); end; end
class FakeModel
  attr_accessor :tool_id
  def selection; @sel ||= Sel.new; end
  def tools; id = @tool_id || F::KE_SELECT; o = Object.new; o.define_singleton_method(:active_tool_id) { id }; o; end
  def close_active; @active_path = nil; true; end
end
module Sketchup
  class Camera < ::Cam
    attr_accessor :height
    def initialize(e, t, u, persp = true, fov = 60.0); super(); set(e, t, u); @perspective = persp; @fov = fov; end
  end
end
module UI
  class HtmlDialog
    def initialize(_o); @scripts = []; @cb = {}; @visible = false; end
    def set_file(_f); end
    def add_action_callback(n, &b); @cb[n] = b; end
    def set_on_closed(&b); @closed = b; end
    def show; @visible = true; end
    def visible?; @visible; end
    def close; return unless @visible; @visible = false; @closed&.call; end
    def bring_to_front; end
    def execute_script(s); @scripts << s; end
    def call(n, arg = ''); @cb[n].call(nil, arg); end
    def last(fn); s = @scripts.reverse.find { |x| x.start_with?("#{fn}(") } or return nil; JSON.parse(s[(fn.size + 1)...-1]); end
  end
end
fine_dolly = lambda do
  a = view.anim
  a.instance_variable_set(:@t0, -1e9)        # tempo scaduto: l'ultimo fotogramma
  a.nextFrame(view)
end
near1 = ->(a, b, eps = 1e-6) { (a - b).abs < eps }

# Angoli: bussola dall'asse verde, inclinazione, rollio con la testa a destra
k = F.ke_from_angles(Array.new(12, 0.0), 30.0, 10.0, 15.0)
az, pitch, roll = F.ke_angles(k)
ok(near1.(az, 30) && near1.(pitch, 10) && near1.(roll, 15), "angoli → sguardo e alto → angoli: #{[az, pitch, roll].map { |x| x.round(3) }}")
k = F.ke_from_angles(Array.new(12, 0.0), 90.0, 0.0, 20.0)
ok(near1.(k[3], 1) && near1.(k[4], 0) && near1.(k[7], -Math.sin(20 * Math::PI / 180)) && near1.(k[8], Math.cos(20 * Math::PI / 180)),
   'direzione 90° = verso l\'asse rosso; rollio positivo: l\'alto pende a destra')

# Un percorso nuovo dalla vista: due sfere
view.camera.set(Geom::Point3d.new(0, 0, 66), Geom::Point3d.new(100, 0, 66), Geom::Vector3d.new(0, 0, 1))
view.camera.fov = 60.0
F.path_command('new', '')
nome = F.path_list.last['name']
sf = F.key_instances(pm)[nome]
e1, e2 = sf
F.ke_open(e1)
dlg = F.instance_variable_get(:@ke)[:dialog]
dlg.call('ready')
v = dlg.last('show')
ok(dlg.visible? && dlg.last('init')['strings']['ke.title'] == F.t('ke.title') && v['i'] == 1 && v['n'] == 2,
   'aperto: testi ke.*, posizione 1 di 2')
ok(near1.(v['z'], 66 * F::IN_TO_M) && near1.(v['az'], 90) && near1.(v['fov'], 60) && v['ground'].nil? && v['seg'] && near1.(v['arrive'], 0),
   'valori: quota, direzione 90° (verso il rosso), zoom, niente terreno sotto, tratto e arrivo')
ok(pm.selection == [e1], 'la sfera aperta è selezionata')
F.path_command('key', nome, 1)
ok(F.instance_variable_get(:@ke)[:inst].equal?(e2) && pm.selection == [e2], 'dall\'elenco del pannello (cmd key, i 1): la seconda sfera')
F.path_command('key', nome, 9)
ok(F.instance_variable_get(:@ke)[:inst].equal?(e2), 'posizione che non c\'è più: niente')
F.path_command('key', nome, 0)

# Modifiche: ognuna un'operazione, la sfera cambia subito
n_ops = pm.ops.size
dlg.call('set', '{"f":"z","v":2.0}')
ok(near1.(F.key_of(e1)[2], 2.0 * M) && pm.ops[n_ops][0, 3] == [:start, F.t('ke.op'), true] && pm.ops.last == [:commit],
   'quota a 2 m: la sfera si sposta, in un\'operazione «Modifica posizione»')
dlg.call('set', '{"f":"roll","v":"12,5"}')
ok(near1.(F.ke_angles(F.key_of(e1))[2], 12.5) && near1.(F.ke_angles(F.key_of(e1))[0], 90), 'rollio 12,5° (con la virgola): la direzione resta')
dlg.call('set', '{"f":"zoom","v":2}')
fov2 = 2 * Math.atan(Math.tan(F::KEY_FOV0 * Math::PI / 360) / 2) * 180 / Math::PI
ok(near1.(F.key_of(e1)[9], fov2, 0.01) && e1.definition.get_attribute(F::KEY_DICT, 'fov') == fov2.round,
   "ingrandimento 2×: campo visivo #{fov2.round(1)}°, la sfera passa al componente con la freccia lunga")
prima = F.path_track(nome)[:dur]
dlg.call('set', '{"f":"pause","v":2}')
ok(e1.get_attribute(F::KEY_DICT, 'sosta') == 2.0 && near1.(F.path_track(nome)[:dur] - prima, 2.0, 0.05),
   "sosta di 2 s: la riproduzione dura 2 s in più (#{prima.round(2)} → #{F.path_track(nome)[:dur].round(2)} s)")
fr = F.path_track(nome)[:frames]
ok(fr[0, (2.0 * F::PATH_HZ).floor].all? { |f| near1.(f[2], 2.0 * M) && near1.(f[0], 0) }, 'durante la sosta la camera resta sulla sfera')
d0 = F.path_track(nome)[:dur]
dlg.call('set', '{"f":"v","v":0.5}')
ok(e1.get_attribute(F::KEY_DICT, 'v') == 0.5 && F.path_track(nome)[:dur] > d0 + 1, 'velocità propria del tratto (0,5 m/s): il tratto dura di più')
dlg.call('set', '{"f":"vauto","v":true}')
ok(e1.get_attribute(F::KEY_DICT, 'v').nil? && near1.(F.path_track(nome)[:dur], d0, 0.05), '«Automatica»: torna la velocità del percorso')
# Destro su − o +: il valore scorre e arriva ~10 volte al secondo con lo
# stesso 'run'; la prima operazione è normale, le altre vi si fondono
n_ops = pm.ops.size
%w[0.1 0.2 0.3].each { |x| dlg.call('set', %({"f":"x","v":#{x},"run":"r1"})) }
st = pm.ops[n_ops..].select { |o| o[0] == :start }
ok(st.map(&:last) == [false, true, true] && near1.(F.key_of(e1)[0], 0.3 * M),
   'variazione continua: tre invii, un\'operazione sola (le altre trasparenti, un Ctrl+Z)')
dlg.call('set', '{"f":"x","v":0}')
ok(pm.ops.reverse.find { |o| o[0] == :start }.last == false, 'il clic dopo: operazione nuova, normale')
dlg.call('set', '{"f":"x","v":1}')
n_ops = pm.ops.size
dlg.call('set', '{"f":"x","v":"non un numero"}')
ok(near1.(F.key_of(e1)[0], 1.0 * M) && pm.ops.size == n_ops, 'un valore che non è un numero: ignorato, nessuna operazione')
dlg.call('set', '{"f":"x","v":0}')

# Navigazione: dolly, selezione, pannello
dlg.call('nav', '1')
ke = F.instance_variable_get(:@ke)
ok(ke[:inst].equal?(e2) && view.anim.is_a?(F::KeDolly) && pm.selection == [e2] && dlg.last('show')['i'] == 2,
   'successiva: seleziona la seconda, il pannello la mostra, la camera va in dolly')
dlg.call('nav', '1')
ok(ke[:inst].equal?(e2), 'dopo l\'ultima non si va oltre')
dlg.call('nav', '-1')
ok(ke[:inst].equal?(e1), 'precedente: di nuovo la prima')

# Anteprima: dolly dentro la sfera e fuori, alla vista di prima
view.camera = Sketchup::Camera.new(Geom::Point3d.new(-100, -100, 200), Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), true, 40)
dlg.call('preview', true)
fine_dolly.()
c = view.camera
ok(ke[:preview] && near1.(c.eye.z, 2.0 * M, 1e-3) && near1.(c.fov, fov2, 1e-3), 'anteprima: alla fine del dolly la camera è quella della sfera')
ok(!pm.layers[F::KEY_TAG].visible?, 'con l\'anteprima le sfere sono spente: la camera non finisce dentro la sua')
ok(pm.selection.empty?, 'e niente selezionato: il contorno blu della selezione si vedrebbe anche col tag spento')
dlg.call('set', '{"f":"z","v":3.0}')
ok(near1.(view.camera.eye.z, 3.0 * M, 1e-3), 'con l\'anteprima la vista segue ogni modifica')
dlg.call('nav', '1')
ok(view.anim.is_a?(F::KeDolly) && view.anim.instance_variable_get(:@dur) <= F::KE_PATH, 'da sfera a sfera con l\'anteprima: dolly lungo il percorso, al più 1,5 s')
fine_dolly.()
ok(near1.(view.camera.eye.x, F.key_of(e2)[0], 1e-3), 'arrivato nella vista della seconda sfera')
dlg.call('preview', false)
fine_dolly.()
ok(!ke[:preview] && near1.(view.camera.eye.x, -100) && near1.(view.camera.fov, 40), 'anteprima tolta: dolly e camera esattamente com\'era')
ok(pm.layers[F::KEY_TAG].visible?, 'finito il dolly di ritorno le sfere si rivedono')
ok(pm.selection == [e2], 'e la sfera del pannello torna selezionata')

# Inserisci dopo, elimina
dlg.call('nav', '-1')
dlg.call('act', 'insert')
sf = F.key_instances(pm)[nome]
ok(sf.size == 3 && ke[:inst].equal?(sf[1]) && pm.selection == [sf[1]] && sf.map { |x| x.get_attribute(F::KEY_DICT, 'i') } == [0, 1, 2],
   'inserita una sfera dopo la prima, fra le due: diventa la seconda e si apre')
mezzo = F.key_of(sf[1])[0]
ok(mezzo > F.key_of(sf[0])[0] && mezzo < F.key_of(sf[2])[0], 'sta a metà della curva')
dlg.call('act', 'delete')
sf = F.key_instances(pm)[nome]
ok(sf.size == 2 && ke[:inst].equal?(sf[1]) && sf.map { |x| x.get_attribute(F::KEY_DICT, 'i') } == [0, 1], 'eliminata: resta la successiva, numerate di nuovo')
nb = boxes.size
dlg.call('act', 'delete')
ok(F.key_instances(pm)[nome].size == 2 && boxes.size == nb + 1 && boxes.last == F.t('ke.min2'), 'con due sole sfere non si elimina: lo dice')
dlg.call('act', 'from_view')
ok(near1.(F.key_of(ke[:inst])[0], view.camera.eye.x, 1e-3), '«Prendi dalla vista»: la sfera va dov\'è la camera')

# «Incolla» del menu del pannello: la pagina chiede, Ruby legge gli appunti
# di Windows (qui finti: i test non toccano quelli veri) e li rimanda
F.singleton_class.send(:alias_method, :ke_clipboard_vero, :ke_clipboard)
F.define_singleton_method(:ke_clipboard) { "2,5 \"m\"" }
dlg.call('paste')
ok(dlg.instance_variable_get(:@scripts).last == 'incolla("2,5 \\"m\\"")', 'Incolla: il testo degli appunti torna alla pagina (incolla)')
F.show_panel                                         # il pannello generale: stesso Incolla
pd = F.instance_variable_get(:@dialog)
pd.call('panel_paste')
ok(pd.instance_variable_get(:@scripts).last == 'incolla("2,5 \\"m\\"")', 'Incolla anche nel pannello generale (panel_paste)')
pd.close
F.singleton_class.send(:alias_method, :ke_clipboard, :ke_clipboard_vero)
w32 = F.ensure_win32 && F.instance_variable_get(:@w32)
appunti = %i[IsClipboardFormatAvailable OpenClipboard CloseClipboard GetClipboardData GlobalLock GlobalUnlock GlobalSize]
ok(w32 && appunti.all? { |m| w32.respond_to?(m) }, 'Win32 dichiarate per leggere gli appunti')

# Chiuso e riaperto subito: la notizia della chiusura arriva dopo la
# riapertura e non deve far dimenticare la finestra (2026-10-17)
dlg.instance_variable_set(:@visible, false)          # chiusa, notizia non ancora arrivata
dlg.show                                             # riaperta
dlg.instance_variable_get(:@closed).call             # ora arriva la notizia
ok(F.instance_variable_get(:@ke)[:dialog].equal?(dlg), 'chiusura notificata in ritardo, finestra già riaperta: resta')

# La sfera cancellata da fuori (Canc, Ctrl+Z): il pannello si chiude
ke[:inst].erase!
F.ke_refresh
ok(!dlg.visible?, 'sfera sparita: il pannello si chiude')

# Aperture: doppio clic (si entra nel componente: se ne esce e si apre il pannello) e Invio
sf = F.key_instances(pm)[nome]
UI.singleton_class.send(:alias_method, :start_timer_vero, :start_timer)
UI.define_singleton_method(:start_timer) { |*_a, &b| b&.call; 1 }
pm.active_path = [sf[0]]
F.ke_active_path(pm)
ke = F.instance_variable_get(:@ke)
ok(pm.active_path.nil? && ke[:dialog]&.visible? && ke[:inst].equal?(sf[0]), 'doppio clic: fuori dal componente, pannello sulla sfera')
ke[:dialog].close
UI.singleton_class.send(:alias_method, :start_timer, :start_timer_vero)
pm.active_path = [Inst.new(FakeDefn.new('altro', pm), nil, pm)]
F.ke_active_path(pm)
ok(!pm.active_path.nil?, 'doppio clic su un altro componente: SketchUp fa il suo')
pm.active_path = nil
giu = true
F.define_singleton_method(:async_down?) { |_vk| giu }
F.define_singleton_method(:su_main_foreground?) { true }
pm.selection.clear; pm.selection.add(sf[0])
F.instance_variable_set(:@ke_enter, false)
F.ke_poll_enter
ok(ke[:dialog]&.visible? && ke[:inst].equal?(sf[0]), 'Invio con una sfera selezionata: si apre il suo pannello')
ke[:dialog].close
F.ke_poll_enter
ok(!(ke[:dialog]&.visible?), 'Invio tenuto premuto: non si riapre a ripetizione')
giu = false; F.ke_poll_enter; giu = true
pm.tool_id = 21048                                  # Sposta: Invio conferma una misura
F.ke_poll_enter
ok(!(ke[:dialog]&.visible?), 'con un altro strumento attivo Invio non apre nulla')
pm.tool_id = nil
giu = false; F.ke_poll_enter; giu = true
F.define_singleton_method(:su_main_foreground?) { false }
F.ke_poll_enter
ok(!(ke[:dialog]&.visible?), 'Invio dentro un dialogo (anche questo pannello): non conta')

puts
puts($fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI")
exit($fail.zero? ? 0 : 1)
