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

# ── Overlay: curva e numeri ──────────────────────────────────────────
view.camera.set(Geom::Point3d.new(-5 * M, 0, 66), Geom::Point3d.new(0, 0, 66), Geom::Vector3d.new(0, 0, 1))   # tutte davanti
F.key_draw(view)
ok(view.drawn.size == 1 && view.drawn[0][0] == GL_LINE_STRIP && view.drawn[0][1].size == (ord.size - 1) * F::KEY_SUB + 1,
   'Overlay: la curva fra le sfere')
ok(view.texts.map { |x| x[1] } == (1..ord.size).map(&:to_s), 'e il numero d\'ordine accanto a ognuna')
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

puts
puts($fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI")
exit($fail.zero? ? 0 : 1)
