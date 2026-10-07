# Test delle parti di calcolo puro di main.rb (fuori da SketchUp).
# Carica il vero main.rb con la finta API di tests/support/sketchup.rb.
#   Esecuzione:  ruby -E UTF-8 tests/test_physics.rb   (oppure tests\run_tests.bat)
# Ciò che usa davvero SketchUp (raggi, spostamenti, camera) va provato nel
# programma: qui si verificano matematica, fisica e riconoscimento materiali.
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
F = DagaWASD::FPSWalk
# La finta API non ha tutti i metodi: gli errori che main.rb intercetta
# finiscono in un registro temporaneo, non in dagawasd.log del progetto.
require 'tmpdir'
F.instance_variable_set(:@log_file, File.join(Dir.tmpdir, 'dagawasd_test_physics.log'))
F.instance_variable_set(:@log_quiet, true)
F.load_cfg
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
def near(a, b, tol = 1e-3); (a - b).abs <= tol; end
P = Geom::Point3d

# ── Algebra ───────────────────────────────────────────────────────
x = F.solve_lin([[2.0, 1.0], [1.0, 3.0]], [3.0, 5.0])
ok(near(x[0], 0.8) && near(x[1], 1.4), "solve_lin risolve un sistema 2×2 (#{x.map { |v| v.round(3) }})")

# ── Inviluppo 2D ──────────────────────────────────────────────────
h = F.hull2d([[0,0],[10,0],[10,10],[0,10],[5,5],[3,7]])
ok(h.size == 4 && !h.include?([5,5]), "hull2d: quadrato con punti interni → 4 vertici")
area2 = h.each_index.sum { |i| a = h[i]; b = h[(i + 1) % h.size]; a[0] * b[1] - b[0] * a[1] }
ok(area2 > 0, "hull2d: vertici in senso antiorario")
ok(F.hull2d([[0,0],[5,5],[10,10]]).size == 2, "hull2d: punti allineati → segmento")

# ── Riconoscimento cerchi / sfere ────────────────────────────────
circ = (0...24).map { |i| a = i * 2 * Math::PI / 24; [2 + 5 * Math.cos(a), 3 + 5 * Math.sin(a)] }
c, r, res = F.fit_round(circ)
ok(near(c[0], 2) && near(c[1], 3) && near(r, 5) && res < 1e-6, "fit_round: cerchio a 24 lati, centro (2,3) r=5")
sph = []
(1..7).each { |i| th = i * Math::PI / 8; (0...12).each { |j| ph = j * Math::PI / 6
  sph << [1 + 4 * Math.sin(th) * Math.cos(ph), -2 + 4 * Math.sin(th) * Math.sin(ph), 5 + 4 * Math.cos(th)] } }
c, r, res = F.fit_round(sph)
ok(near(c[0], 1) && near(c[1], -2) && near(c[2], 5) && near(r, 4) && res < 1e-6, "fit_round: sfera centro (1,-2,5) r=4")
hemi = sph.select { |p| p[2] <= 5.0001 }
c, r, res = F.fit_round(hemi)
ok(near(c[2], 5) && near(r, 4) && res < 1e-6, "fit_round: semisfera → trova il centro della sfera (non del bounding box)")
sq = [[0,0],[10,0],[10,2],[0,2],[5,0],[5,2],[0,1],[10,1],[2.5,0],[7.5,2]]   # rettangolo 10×2
c, r, res = F.fit_round(sq)
ok(res > r * 0.01 + 0.02, "fit_round: punti non su un cerchio → scarto alto, rifiutato")

# ── Campionamento sonde ───────────────────────────────────────────
cube = [0, 10].product([0, 10], [0, 10]).map { |a, b, cc| P.new(a, b, cc) }
centers = [[5,5,0],[5,5,10],[5,0,5],[5,10,5],[0,5,5],[10,5,5]].map { |v| P.new(*v) }
s = F.fps_sample(cube + centers, 12)
ok(s.size == 12 && (cube - s).empty?, "fps_sample: prende prima gli 8 spigoli del cubo, poi i centri delle facce")

# ── Ribaltamento: istante d'impatto della faccia ─────────────────
# Cubo di lato 10 su uno spigolo lungo Y nell'origine, inclinato di 30°.
a30 = 30 * Math::PI / 180
pts = [[0, 0, 0], [10 * Math.cos(a30), 0, 10 * Math.sin(a30)],
       [-10 * Math.sin(a30), 0, 10 * Math.cos(a30)],
       [10 * Math.cos(a30) - 10 * Math.sin(a30), 0, 10 * Math.sin(a30) + 10 * Math.cos(a30)]]
pts += pts.map { |px, _, pz| [px, 10, pz] }
th = F.tipping_toi(pts, P.new(0, 0, 0), [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], 1.0)
ok(th && near(th, a30, 1e-6), "tipping_toi: la faccia a 30° tocca terra dopo 30° di rotazione (#{th && (th * 180 / Math::PI).round(3)}°)")
ok(F.tipping_toi(pts, P.new(0, 0, 0), [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], 0.2).nil?, "tipping_toi: passo più piccolo dell'angolo → nessun impatto")
th2 = F.tipping_toi(pts, P.new(0, 0, 0), [0.0, -1.0, 0.0], [0.0, 0.0, 1.0], 1.5)
ok(th2 && near(th2, Math::PI / 2 - a30, 1e-6), "tipping_toi: ruotando dall'altra parte atterra sulla faccia a 60°")

# ── Rotolamento ──────────────────────────────────────────────────
# Palla piena r = 10": lanciata strisciando a 100"/s senza rotazione.
# Conservazione del momento angolare attorno al contatto: v_finale = 5/7 v0.
st = { vx: 100.0, vy: 0.0, vz: 0.0, ox: 0.0, oy: 0.0, oz: 0.0 }
sup = { roll: :sphere, r: 10.0, com: P.new(0, 0, 10), c: P.new(0, 0, 10), pc: P.new(0, 0, 0), lever: 0.0 }
F.roll_step(st, { fric: 1.0 }, sup, 1.0 / 15, 9.8)
rr = 0.02 * 9.8 * (1.0 / 15) * F::M_TO_IN   # resistenza al rotolamento in un passo ("/s)
ok(near(st[:vx], 100.0 * 5 / 7 - rr, 0.02), "roll_step: palla strisciante → rotola a 5/7 della velocità meno la resistenza (#{st[:vx].round(2)} vs #{(500.0 / 7 - rr).round(2)})")
ok(near(st[:oy], st[:vx] * F::IN_TO_M / (10 * F::IN_TO_M), 1e-6), "roll_step: rotolamento puro (ω = v / r)")
st2 = { vx: 100.0, vy: 0.0, vz: 0.0, ox: 0.0, oy: 0.0, oz: 0.0 }
F.roll_step(st2, { fric: 0.0 }, sup, 1.0 / 60, 9.8)
ok(near(st2[:vx], 100.0) && st2[:oy].abs < 1e-9, "roll_step: attrito zero → striscia senza rotolare (ghiaccio)")
# Cilindro coricato lungo X: una spinta lungo il proprio asse non lo fa rotolare.
cyl = { roll: :cylinder, r: 10.0, com: P.new(0, 0, 10), c: P.new(0, 0, 10), pc: P.new(0, 0, 0), axis: [1.0, 0.0, 0.0], lever: 0.0 }
st3 = { vx: 100.0, vy: 0.0, vz: 0.0, ox: 0.0, oy: 0.0, oz: 0.0 }
F.roll_step(st3, { fric: 0.5 }, cyl, 1.0 / 60, 9.8)
ok(st3[:ox].abs < 1e-9 && st3[:oy].abs < 1e-9 && st3[:vx] < 100.0, "roll_step: cilindro spinto lungo l'asse striscia (frena) senza rotolare")
st4 = { vx: 0.0, vy: 100.0, vz: 0.0, ox: 0.0, oy: 0.0, oz: 0.0 }
F.roll_step(st4, { fric: 1.0 }, cyl, 1.0 / 15, 9.8)
ok(st4[:ox].abs > 0.1 && st4[:oy].abs < 1e-9 && near(st4[:vy], 100.0 * 2 / 3 - rr, 0.02),
   "roll_step: cilindro spinto di traverso rotola sul proprio asse (v = 2/3 v0 meno la resistenza: #{st4[:vy].round(2)})")
# Semisfera inclinata: baricentro spostato verso −X rispetto al contatto
# → la coppia la fa rotolare verso −X, riducendo l'inclinazione (dondolio).
dome = { roll: :sphere, r: 10.0, com: P.new(-1.5, 0, 6.25), c: P.new(0, 0, 10), pc: P.new(0, 0, 0), lever: 1.5 }
st5 = { vx: 0.0, vy: 0.0, vz: 0.0, ox: 0.0, oy: 0.0, oz: 0.0 }
stable = F.roll_step(st5, { fric: 1.0 }, dome, 1.0 / 15, 9.8)
ok(st5[:oy] < 0 && st5[:vx] < 0 && !stable, "roll_step: semisfera inclinata riceve una coppia di richiamo (dondolio)")
ball_rest = F.roll_step({ vx: 0.0, vy: 0.0, vz: 0.0, ox: 0.0, oy: 0.0, oz: 0.0 }, { fric: 1.0 }, sup, 1.0 / 60, 9.8)
ok(ball_rest, "roll_step: palla ferma su un piano è in equilibrio")

# ── Materiali in tutte le lingue ──────────────────────────────────
F.load_lang
F.invalidate_materials
Ent = Struct.new(:material, :name, :definition) do
  def respond_to?(m, *a); m == :definition ? !definition.nil? : super; end
  def is_a?(k); false; end
  def typename; 'Group'; end
end
Mat = Struct.new(:display_name)
def mk(label); Ent.new(Mat.new(label), '', nil); end
cases = { 'Holz Eiche' => 'legno', 'Madera roble' => 'legno', 'Стекло' => 'vetro', '木材_橡木' => 'legno',
          'Metallo satinato' => 'metallo', 'Camera' => nil, 'Sedia tre gambe' => nil, 'Table top' => nil,
          'Scatola di metallo' => 'metallo', 'Wood_Cherry_Original' => 'legno', 'Gomma nera' => 'gomma' }
cases.each do |label, want|
  got = F.material_key(mk(label))
  ok(got == want, "material_key(#{label.inspect}) → #{got.inspect}#{got == want ? '' : " (atteso #{want.inspect})"}")
end
# Riga utente aggiunta dal pannello
F.instance_variable_get(:@cfg)['materials'] = F.default_materials + [
  { 'id' => 'c1', 'name' => 'Sughero', 'density' => 240, 'restitution' => 0.5, 'friction' => 0.6, 'keywords' => 'cork', 'icon' => 'cork' }]
F.invalidate_materials
ok(F.material_key(mk('Tappo sughero')) == 'c1', "riga utente: \"Tappo sughero\" → Sughero (dal nome)")
ok(F.material_key(mk('Cork board')) == 'c1', "riga utente: \"Cork board\" → Sughero (dalla parola chiave)")
ok(F.mat_label('c1') == 'Sughero' && F.mat_label('legno') == 'legno', "mat_label: nome utente / nome tradotto")
bad = F.sanitize_materials([{ 'id' => 'x y!', 'density' => -5, 'restitution' => 3, 'friction' => 'abc', 'icon' => 'nope' }, 'junk'])
ok(bad.size == 1 && bad[0]['id'] == 'xy' && bad[0]['density'] == 10.0 && bad[0]['restitution'] == 0.98 &&
   bad[0]['friction'] == 0.0 && bad[0]['icon'] == 'generic', "sanitize_materials ripulisce valori non validi")

# ── Presa: fase larga delle collisioni ────────────────────────────
held  = StubBox.new([0, 0, 50], [10, 10, 60])            # oggetto in mano
floor = StubBox.new([-2000, -2000, -1], [2000, 2000, 0]) # pavimento enorme → lista "grandi"
wall  = StubBox.new([100, -50, 0], [110, 50, 100])       # muro a ~1 m
$stub_entities = [held, floor, wall]
F.instance_variable_set(:@dyn_entities, Set.new)
F.build_obstacle_grid(held)
obst = F.instance_variable_get(:@obst)
ok(obst[:big].map(&:last) == [floor] && obst[:grid].values.flatten(1).map(&:last).uniq == [wall],
   'griglia: pavimento enorme nella lista "grandi", muro nelle celle')
ok(!F.obstacles_near?([0, 0, 50, 10, 10, 60], held), 'fase larga: oggetto in aria lontano da tutto → nessun ostacolo')
ok(F.obstacles_near?([95, 0, 50, 105, 10, 60], held), 'fase larga: tragitto che tocca il muro → ostacolo')
ok(F.obstacles_near?([0, 0, -0.5, 10, 10, 5], held), 'fase larga: oggetto al pavimento → ostacolo')
ok(!F.obstacles_near?([0, 0, 50, 10, 10, 60], wall), "fase larga: l'oggetto stesso non è un ostacolo")
# Un oggetto mosso dalla fisica si controlla dov'è ora, non dov'era
box = StubBox.new([300, 300, 0], [310, 310, 10])
$stub_entities << box
F.build_obstacle_grid(held)
box.move_to([0, 20, 50], [10, 30, 60])
ok(!F.obstacles_near?([0, 15, 50, 10, 25, 60], held), 'fase larga: senza saperlo mosso, la griglia vede solo la vecchia posizione')
F.instance_variable_get(:@dyn_entities) << box
ok(F.obstacles_near?([0, 15, 50, 10, 25, 60], held), 'fase larga: oggetto mosso dalla fisica controllato sulla posizione attuale')
# Tragitto libero: held_sweep restituisce tutto il movimento senza lanciare raggi
F.instance_variable_get(:@dyn_entities).clear
def F.ray(*); raise 'nessun raggio doveva partire'; end
mv = F.held_sweep(held, 3.0, -2.0, 1.0)
ok(mv == [3.0, -2.0, 1.0], 'held_sweep: via libera → movimento intero e zero raggi lanciati')

# ── Presa: strappo iniziale da un oggetto incastrato in un muro ───
# Player in (0,0,60) che guarda verso +X; cubo di 10" infilato per metà in
# un muro spesso a x = 95..105. Durante lo strappo l'ambiente non conta:
# nessun raggio deve partire (F.ray è ancora quello che solleva un errore).
cube = StubBox.new([100, -5, 55], [110, 5, 65])
wall2 = StubBox.new([95, -100, 0], [105, 100, 120])
$stub_entities = [cube, wall2]
F.instance_variable_set(:@dyn_entities, Set.new)
F.build_obstacle_grid(cube)
{ :@grabbed_entity => cube, :@grab_from => cube.center, :@grab_t => 0.0, :@grab_ghost => true,
  :@eye_x => 0.0, :@eye_y => 0.0, :@eye_z => 60.0, :@yaw => 0.0, :@pitch => 0.0, :@held_block => 0.0 }
  .each { |k, v| F.instance_variable_set(k, v) }
entity_r = Math.sqrt(3 * 10.0**2) / 2
target_x = F.cf('grab_distance').to_f * F::M_TO_IN + entity_r
xs = []
begin
  8.times { F.update_grabbed_position(0.05); xs << cube.center[0] }
  raised = false
rescue => e
  raised = e.message
end
ok(!raised, "strappo: nessun raggio lanciato mentre l'oggetto attraversa il muro#{raised ? " (#{raised})" : ''}")
ok(xs[1] < target_x - 5, "strappo: prima viene tirato verso il player (x = #{xs[1].round(1)} < #{target_x.round(1)})")
ok((xs[-1] - target_x).abs < 1.0, "strappo: poi si porta alla distanza di presa (x = #{xs[-1].round(1)} ≈ #{target_x.round(1)})")
ok(F.instance_variable_get(:@grabbed_entity) == cube, 'strappo: l\'oggetto resta in mano (non viene mollato come "incastrato")')
F.update_grabbed_position(0.05)
ok(F.instance_variable_get(:@grab_ghost) == false, 'dopo lo strappo, fuori dal muro: collisioni di nuovo attive')

# ── Normali con scala non uniforme ────────────────────────────────
# Faccia inclinata a 45° (normale (1,0,1)/√2) in un gruppo stirato ×2 su X:
# la faccia diventa più ripida, la normale corretta è (1,0,2) (non (2,0,1)).
stretch = [2,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1].map(&:to_f)
nx, ny, nz = F.normal_xform(stretch, 1 / Math.sqrt(2), 0.0, 1 / Math.sqrt(2))
l = Math.sqrt(nx * nx + ny * ny + nz * nz)
ok(near(nx / l, 1 / Math.sqrt(5)) && near(nz / l, 2 / Math.sqrt(5)) && ny.abs < 1e-12,
   "normal_xform: gruppo stirato ×2 su X → normale (1,0,2)/√5 (#{(nx / l).round(3)}, #{(nz / l).round(3)})")
mirror = [-1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1].map(&:to_f)
mx_, _, mz_ = F.normal_xform(mirror, 1.0, 0.0, 0.0)
ok(near(mx_, -1.0) && mz_.abs < 1e-12, 'normal_xform: specchiatura su X → la normale +X diventa −X')

# ── Tetto corpi simulati: esce il più fermo, non il più vecchio ───
F.instance_variable_get(:@cfg)['max_phys_entities'] = 4
flying = StubGroup.new([0, 0, 100], [10, 10, 110]); resting = StubGroup.new([50, 0, 0], [60, 10, 10])
F.instance_variable_set(:@phys_entities, {})
F.add_physics_entity(flying, 0.0, 0.0, -200.0)                 # il più vecchio, ma in volo
F.add_physics_entity(resting, 0.0, 0.0, 0.0)
F.instance_variable_get(:@phys_entities)[resting][:fz] = 0.0   # appoggiato
2.times { |i| F.add_physics_entity(StubGroup.new([100 + i * 20, 0, 50], [110 + i * 20, 10, 60]), 50.0, 0.0, 0.0) }
F.add_physics_entity(StubGroup.new([200, 0, 50], [210, 10, 60]), 50.0, 0.0, 0.0)   # supera il tetto
pe = F.instance_variable_get(:@phys_entities)
ok(pe.size == 4 && pe.key?(flying) && !pe.key?(resting), 'tetto corpi: esce quello appoggiato e fermo, non quello in volo')
F.instance_variable_get(:@cfg)['max_phys_entities'] = 24

# ── Risveglio: l'ambiente non diventa mai "fisico" ────────────────
mover = StubGroup.new([0, 0, 10], [10, 10, 20])                 # corpo in moto verso +X
light = StubGroup.new([9, 0, 10], [19, 10, 20])                 # scatola leggera accostata
house = StubGroup.new([-100, -100, 0], [150, 150, 100])         # stanza-gruppo che lo contiene
bigwl = StubGroup.new([5, -200, 0], [12, 200, 120])             # muro lunghissimo (> 6 m)
$stub_entities = [mover, light, house, bigwl]
F.instance_variable_set(:@dyn_entities, Set.new)
F.instance_variable_set(:@grabbed_entity, nil)
F.instance_variable_set(:@obst, nil)                            # la griglia si ricostruisce da sola
F.instance_variable_set(:@phys_entities, {})
F.add_physics_entity(mover, 150.0, 0.0, 0.0)
F.resolve_entity_collisions(Sketchup.active_model)
pe = F.instance_variable_get(:@phys_entities)
ok(pe.key?(light), 'risveglio: la scatola leggera urtata entra nella simulazione')
ok(!pe.key?(house), 'risveglio: la stanza-gruppo che contiene il corpo NON diventa fisica')
ok(!pe.key?(bigwl), 'risveglio: un muro enorme NON diventa fisico')

# ── Presa: tocco breve = posare ───────────────────────────────────
F.instance_variable_set(:@phys_entities, {})
tapped = StubGroup.new([0, 0, 50], [10, 10, 60])
F.instance_variable_set(:@grabbed_entity, tapped)
F.instance_variable_set(:@grab_state, :charging)
F.instance_variable_set(:@charge_start, Time.now.to_f - 0.05)
F.do_throw
st = F.instance_variable_get(:@phys_entities)[tapped]
ok(F.instance_variable_get(:@grabbed_entity).nil? && st && st[:vx] == 0.0 && st[:vy] == 0.0 && st[:vz] == 0.0,
   'tocco breve di G: l\'oggetto viene posato (velocità zero), non lanciato')
F.instance_variable_set(:@phys_entities, {})
thrown = StubGroup.new([0, 0, 50], [10, 10, 60])
F.instance_variable_set(:@grabbed_entity, thrown)
F.instance_variable_set(:@grab_state, :charging)
F.instance_variable_set(:@charge_start, Time.now.to_f - 0.6)
F.do_throw
st = F.instance_variable_get(:@phys_entities)[thrown]
ok(st && st[:vx] > 1.0, "pressione lunga di G: l'oggetto viene lanciato (vx = #{st && st[:vx].round(1)}\"/s)")

# ── L'oggetto in mano spinge quelli leggeri, non l'ambiente ───────
F.instance_variable_set(:@phys_entities, {})
held2  = StubGroup.new([0, 0, 50], [10, 10, 60])
box2   = StubGroup.new([11, 0, 50], [21, 10, 60])
heavy2 = StubGroup.new([11, 20, 0], [80, 90, 60])               # ~150 kg: troppo pesante
F.held_push(held2, box2, 1.0, 0.0, 0.0, 60.0)
F.held_push(held2, heavy2, 1.0, 0.0, 0.0, 60.0)
F.held_push(held2, house, 1.0, 0.0, 0.0, 60.0)
pe = F.instance_variable_get(:@phys_entities)
ok(pe.key?(box2) && pe[box2][:vx] > 0, "oggetto in mano: spinge la scatola leggera (vx = #{pe[box2] && pe[box2][:vx].round(1)}\"/s)")
ok(!pe.key?(heavy2) && !pe.key?(house), 'oggetto in mano: non smuove gli oggetti pesanti né la stanza-gruppo')

# ── Urti fra oggetti con la forma reale ───────────────────────────
# Forme costruite a mano nel formato di shape_world.
def box_shape(cx, cy, cz, h, ang_deg = 0.0)
  a = ang_deg * Math::PI / 180; ca = Math.cos(a); sa = Math.sin(a)
  ux = [ca, sa, 0.0]; uy = [-sa, ca, 0.0]; uz = [0.0, 0.0, 1.0]
  pts = [-1, 1].product([-1, 1], [-1, 1]).map do |i, j, k|
    [cx + h * (i * ux[0] + j * uy[0]), cy + h * (i * ux[1] + j * uy[1]), cz + h * k]
  end
  { kind: :poly, pts: pts, com: P.new(cx, cy, cz), axes: [ux, uy, uz] }
end
def cyl_shape(cx, cy, cz, r, half)   # asse lungo X
  pts = [-half, half].product((0...24).to_a).map { |x, i| t = i * Math::PI / 12; [cx + x, cy + r * Math.cos(t), cz + r * Math.sin(t)] }
  { kind: :cyl, pts: pts, com: P.new(cx, cy, cz), axes: [[1.0, 0.0, 0.0]], c: P.new(cx, cy, cz), r: r, a: [1.0, 0.0, 0.0], half: half }
end
def sph_shape(cx, cy, cz, r)
  pts = (0...12).flat_map { |i| (1..5).map { |j| t = i * Math::PI / 6; f = j * Math::PI / 6
    [cx + r * Math.sin(f) * Math.cos(t), cy + r * Math.sin(f) * Math.sin(t), cz + r * Math.cos(f)] } }
  { kind: :sphere, pts: pts, com: P.new(cx, cy, cz), axes: [], c: P.new(cx, cy, cz), r: r }
end

# Due cubi di 10" ruotati di 45°, spostati lungo la diagonale di 11":
# gli ingombri si sovrappongono (7.8" per asse < 14.1") ma le forme no.
d = 11 / Math.sqrt(2)
ok(F.shape_contact(box_shape(d, d, 0, 5, 45), box_shape(0, 0, 0, 5, 45)).nil?,
   'forma reale: cubi ruotati di 45° con ingombri sovrapposti ma forme separate → nessun urto')
d = 9 / Math.sqrt(2)
c = F.shape_contact(box_shape(d, d, 0, 5, 45), box_shape(0, 0, 0, 5, 45))
ok(c && near(c[:depth], 1.0, 1e-6) && near(c[:n][0], 1 / Math.sqrt(2), 1e-6) && near(c[:n][1], 1 / Math.sqrt(2), 1e-6),
   "forma reale: cubi ruotati a contatto → profondità 1\" lungo la diagonale (#{c && c[:depth].round(3)})")
c = F.shape_contact(box_shape(9, 0, 0, 5), box_shape(0, 0, 0, 5))
ok(c && near(c[:depth], 1.0, 1e-6) && near(c[:n][0], 1.0) && near(c[:point][0], 4.5, 1e-6),
   'forma reale: cubi allineati → normale +X, punto di contatto a metà della compenetrazione')

ok(F.shape_contact(sph_shape(11, 0, 0, 5), sph_shape(0, 0, 0, 5)).nil?, 'forma reale: sfere a 11" (r = 5) → separate')
c = F.shape_contact(sph_shape(5.4, 7.2, 0, 5), sph_shape(0, 0, 0, 5))   # distanza 9
ok(c && near(c[:depth], 1.0, 1e-6) && near(c[:n][0], 0.6, 1e-6) && near(c[:n][1], 0.8, 1e-6),
   "forma reale: sfere a 9\" → profondità 1\" lungo la congiungente (#{c && c[:n].map { |v| v.round(3) }})")
c = F.shape_contact(sph_shape(9, 0, 0, 5), box_shape(0, 0, 0, 5))
ok(c && near(c[:depth], 1.0, 1e-6) && near(c[:n][0], 1.0, 1e-6), 'forma reale: sfera contro faccia di cubo → profondità 1"')
ok(F.shape_contact(sph_shape(9, 9, 0, 5), box_shape(0, 0, 0, 5)).nil?,
   'forma reale: sfera vicino allo spigolo del cubo (ingombri sovrapposti) → nessun urto')

# Cilindri paralleli (asse X, r = 5): spostati di (0, 7.5, 7.5) → 10.6" fra
# gli assi, separati anche se gli ingombri si sovrappongono.
ok(F.shape_contact(cyl_shape(0, 7.5, 7.5, 5, 20), cyl_shape(0, 0, 0, 5, 20)).nil?,
   'forma reale: cilindri paralleli con ingombri sovrapposti ma superfici separate → nessun urto')
c = F.shape_contact(cyl_shape(0, 9.5, 0, 5, 20), cyl_shape(0, 0, 0, 5, 20))
ok(c && near(c[:depth], 0.5, 1e-6) && near(c[:n][1], 1.0, 1e-6), 'forma reale: cilindri paralleli a contatto → profondità 0.5" lungo Y')
# Cilindro coricato appoggiato su un cubo (faccia superiore a z = 5)
c = F.shape_contact(cyl_shape(0, 0, 9.8, 5, 4), box_shape(0, 0, 0, 5))
ok(c && near(c[:depth], 0.2, 1e-6) && near(c[:n][2], 1.0, 1e-6) && c[:point][2].between?(4.8, 5.0),
   "forma reale: cilindro coricato su un cubo → normale verso l'alto, contatto dentro la compenetrazione (z = #{c && c[:point][2].round(2)} fra 4.8 e 5)")

# ── Tasti iniettati (desktop remoto) ──────────────────────────────
# Da RustDesk & co. la tastiera arriva tutta iniettata: va accettata. Si
# ignorano solo i tasti che FPS inietta da sé, firmati con INJECT_TAG.
st = [0x57, 0x11, 0x10, 123_456, F::INJECT_TAG].pack('L<L<L<L<Q<')
ok(F.hook_struct(st) == [0x57, 0x11, 0x10, F::INJECT_TAG], 'KBDLLHOOKSTRUCT x64: dwExtraInfo letto a offset 16')
ok(F.own_injection?(0x10, F::INJECT_TAG) && F.own_injection?(0x90, F::INJECT_TAG), 'Alt+Tab iniettato da FPS (con la firma): ignorato')
ok(!F.own_injection?(0x10, 0) && !F.own_injection?(0x10, 0x1234), 'tasto iniettato da un altro programma (RustDesk…): accettato')
ok(!F.own_injection?(0x00, F::INJECT_TAG) && !F.own_injection?(0x00, 0), 'tasto vero: accettato anche se dwExtraInfo somiglia alla firma')

# ── Sguardo col tastierino (4 6 8 2) ──────────────────────────────
# Riconoscimento: stesso codice di scansione con BlocNum acceso o spento,
# le frecce vere hanno il flag "esteso" e restano movimento.
ok(F.pad_dir(0x4B, 0) == :pad_left && F.pad_dir(0x48, 0) == :pad_up &&
   F.pad_dir(0x4D, 0) == :pad_right && F.pad_dir(0x50, 0) == :pad_down, 'tastierino 4 8 6 2 riconosciuti dal codice di scansione')
ok(F.pad_dir(0x4B, 1).nil? && F.pad_dir(0x50, 0x81).nil?, 'frecce vere (flag esteso): non sono il tastierino')
ok(F.pad_dir(0x47, 0).nil? && F.pad_dir(0x4C, 0).nil?, 'tastierino 7 e 5: nessuna direzione')
ok([0x62, 0x64, 0x66, 0x68].all? { |vk| F.sanitize_keys('jump' => vk)['jump'] == F::DEFAULT_KEYS['jump'] },
   'tastierino 2 4 6 8 riservati: non assegnabili a un\'azione')
cfgp = F.instance_variable_get(:@cfg)
cfgp.merge!('pad_look_speed' => 90.0, 'pad_look_speed_v' => 60.0, 'pad_look_accel' => 0.0, 'invert_y' => false)
pad = lambda do |keys, secs, steps = 10|
  F.instance_variable_set(:@keys, keys.to_h { |k| [k, true] })
  F.instance_variable_set(:@yaw, 1.0); F.instance_variable_set(:@pitch, 0.0)
  F.instance_variable_set(:@pad_held, 0.0)
  steps.times { F.pad_look(secs / steps) }
  [(F.instance_variable_get(:@yaw) - 1.0) / F::DEG, F.instance_variable_get(:@pitch) / F::DEG]
end
F.instance_variable_set(:@base_fov, 70.0); F.instance_variable_set(:@zoom_fov, 70.0)
dy, dp = pad.([:pad_left], 1.0)
ok(near(dy, 90.0, 0.01) && near(dp, 0.0), "4 per 1 s a 90°/s: gira a sinistra di 90° (#{dy.round(2)}°)")
dy, = pad.([:pad_right], 0.5)
ok(near(dy, -45.0, 0.01), "6 per 0,5 s: gira a destra di 45° (#{dy.round(2)}°)")
dy, dp = pad.([:pad_left, :pad_up], 0.5)
ok(near(dy, 45.0, 0.01) && near(dp, 30.0, 0.01), "4 e 8 insieme: gira e alza lo sguardo nello stesso momento (#{dy.round(1)}°, #{dp.round(1)}°)")
dy, dp = pad.([:pad_left, :pad_right, :pad_down], 0.5)
ok(near(dy, 0.0) && near(dp, -30.0, 0.01), "4 e 6 insieme si annullano, 2 abbassa lo sguardo (#{dp.round(1)}°)")
_, dp = pad.([:pad_up], 10.0, 100)
ok(near(dp, F::PITCH_LIMIT / F::DEG, 1e-6), 'tenendo 8 lo sguardo si ferma al limite verticale')
cfgp['invert_y'] = true
_, dp = pad.([:pad_up], 0.5)
ok(near(dp, -30.0, 0.01), 'Inverti asse Y vale anche per 8 e 2')
cfgp['invert_y'] = false
F.instance_variable_set(:@zoom_fov, 35.0)
dy, = pad.([:pad_left], 1.0)
ok(near(dy, 45.0, 0.01), "zoomato a metà campo visivo: gira a metà velocità, come col mouse (#{dy.round(2)}°)")
F.instance_variable_set(:@zoom_fov, 70.0)
cfgp['pad_look_accel'] = 0.4
tap, = pad.([:pad_left], 0.05, 5)
full, = pad.([:pad_left], 2.0, 200)
ok(tap < 90.0 * 0.05 * 0.5 && tap > 0, "accelerazione: un tocco di 0,05 s gira poco (#{tap.round(2)}° invece di 4,5°)")
ok(full > 90.0 * 2.0 * 0.85 && full < 180.0, "tenuto 2 s arriva a piena velocità (#{full.round(1)}° su 180°)")
F.instance_variable_set(:@keys, {})
F.pad_look(0.1)
ok(F.instance_variable_get(:@pad_held).zero?, 'rilasciati i tasti l\'accelerazione riparte da capo')
F.load_cfg

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
