# Meteo nel video: View finta, proiezione, cielo di fondo, profondità, orologio, GDI+ (SketchUp finto).
#   Esecuzione:  ruby -E UTF-8 tests/test_videometeo.rb   (oppure tests\run_tests.bat)
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'tmpdir'
F = DagaWASD::FPSWalk
M = F::M_TO_IN
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
def near(a, b, eps = 1e-6); (a - b).abs < eps; end

tmp = Dir.mktmpdir('dagawasd_videometeo')
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.instance_variable_set(:@settings_file, File.join(tmp, 'settings.json'))
F.load_cfg
cfg = F.instance_variable_get(:@cfg)

module Sketchup
  class Color
    def initialize(*v); @v = v.size == 3 ? v + [255] : v; end
    def to_a; @v; end
  end
end
# Camera che guarda lungo +y dall'altezza di 2 m; x a destra, z in alto
class VCam
  attr_accessor :fov
  def initialize; @fov = 60.0; end
  def eye; Geom::Point3d.new(0, 0, 2 * M); end
  def direction; Geom::Vector3d.new(0, 1, 0); end
  def xaxis; Geom::Vector3d.new(1, 0, 0); end
  def yaxis; Geom::Vector3d.new(0, 0, 1); end
  def perspective?; true; end
  def fov_is_height?; true; end
end
cam = VCam.new
W = 800; H = 450

puts '── Impostazione'
ok(cfg['path_video_weather'] == true, 'Meteo nel video acceso di serie')

puts '── View finta: registra'
texs = {}
v = F::VmView.new(cam, W, H, texs)
v.drawing_color = Sketchup::Color.new(10, 20, 30, 128)
v.line_width = 3
v.draw(GL_LINES, [Geom::Point3d.new(0, 10, 0), Geom::Point3d.new(1, 10, 0)])
v.draw(GL_LINE_STRIP, [0, 5, 1], [1, 5, 1], [2, 5, 1])          # punti uno per argomento
v.draw2d(GL_QUADS, [[0, 0, 0], [W, 0, 0], [W, H, 0], [0, H, 0]])
rep = Struct.new(:width, :height, :data).new(2, 1, "\x01\x02\x03\x04\x05\x06\x07\x08".b)
id = v.load_texture(rep)
v.draw(GL_QUADS, [[0, 9, 0], [1, 9, 0], [1, 9, 1], [0, 9, 1]], texture: id, uvs: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]])
ok(v.ops.size == 4, "quattro chiamate registrate (#{v.ops.size})")
ok(v.ops[0][0] == :d3 && v.ops[0][2] == [[0.0, 10.0, 0.0], [1.0, 10.0, 0.0]], 'Point3d diventano [x, y, z]')
ok(v.ops[0][3] == ((128 << 24) | (10 << 16) | (20 << 8) | 30), 'colore con trasparenza in ARGB')
ok(v.ops[0][4] == 3, 'larghezza della linea')
ok(v.ops[1][2].size == 3, 'punti passati uno per argomento')
ok(v.ops[2][0] == :d2, 'draw2d resta 2D')
ok(texs[id] && texs[id][:w] == 2 && texs[id][:data].bytesize == 8, 'texture tenuta dalla View finta')
ok(v.ops[3][5] == id && v.ops[3][6].size == 4, 'texture e uvs registrate')
v.release_texture(id)
ok(texs.empty?, 'texture liberata')
px = v.pixels_to_model(1, Geom::Point3d.new(0, 100, 2 * M))
ok(near(px, 2.0 * 100 * Math.tan(30 * F::DEG) / H, 1e-9), 'pixels_to_model alla profondità del punto')

puts '── Proiezione'
pr = F.vm_projector(cam, W, H)
c = F.vm_proj(pr, [0, 100, 2 * M])
ok(near(c[0], W / 2.0) && near(c[1], H / 2.0) && near(c[2], 100), 'davanti al centro: centro dell\'immagine')
r = F.vm_proj(pr, [10, 100, 2 * M])
u = F.vm_proj(pr, [0, 100, 2 * M + 10])
ok(r[0] > W / 2.0 && near(r[1], H / 2.0), 'a destra: x maggiore')
ok(u[1] < H / 2.0, 'in alto: y minore (righe dall\'alto)')
top = F.vm_proj(pr, [0, 100, 2 * M + 100 * Math.tan(30 * F::DEG)])
ok(near(top[1], 0.0, 1e-6), 'campo verticale: il bordo in alto è a fov/2')
d = F.vm_ray(pr, W / 2.0, 0.0)
ok(near(Math.atan2(d[2], d[1]) / F::DEG, 30.0, 1e-9), 'raggio del pixel in alto a 30°')
ok(F.vm_proj(pr, [0, -5, 0])[2] < 0, 'dietro la camera: profondità negativa')

puts '── Orlo del suolo'
hz = F.vm_horizon(pr)
ok(hz && near(hz[1], H / 2.0, 1e-3) && near(hz[3], H / 2.0, 1e-3) && near(hz[4], 0.0) && near(hz[5], 1.0),
   "sguardo orizzontale: orizzonte a metà altezza, suolo in basso (#{hz&.map { |x| x.round(3) }.inspect})")
rolled = { eye: [0.0, 0.0, 2 * M], dir: [0.0, 1.0, 0.0], xa: [0.0, 0.0, 1.0], ya: [-1.0, 0.0, 0.0], f: pr[:f], cx: W / 2.0, cy: H / 2.0 }
hr = F.vm_horizon(rolled)
ok(hr && near(hr[0], W / 2.0, 1e-3) && near(hr[2], W / 2.0, 1e-3) && near(hr[4], -1.0),
   'camera girata di 90° (in alto a destra): orizzonte verticale, suolo a sinistra')
ok(F.vm_horizon(pr.merge(dir: [0.0, 0.001, -1.0])).nil?, 'sguardo dritto in basso: nessun orizzonte')
# Immagine finta: suolo pieno sotto la riga 225, la riga 225 semitrasparente e scura, cielo trasparente sopra
EW = 40; EH = 450; stride = EW * 4
img = String.new(encoding: Encoding::BINARY)
EH.times do |y|
  px = if y > 225 then [200, 150, 100, 255]
       elsif y == 225 then [40, 30, 20, 96]
       elsif y == 100 then [10, 10, 10, 50]                     # lontano dall'orizzonte: non si tocca
       else [0, 0, 0, 0]
       end
  img << (px.pack('C4') * EW)
end
ch = F.vm_ground_edge(img, stride, EW, EH, [0.0, 225.5, EW.to_f, 225.5, 0.0, 1.0])
ok(ch.size == EW && ch.all? { |o, s| o / stride == 225 && s.unpack('C4') == [200, 150, 100, 96] },
   "orlo: i #{ch.size} pixel della riga prendono il colore del suolo e tengono l'opacità")
ok(ch.none? { |o, _| o / stride == 100 }, 'un pixel semitrasparente lontano dall\'orizzonte resta com\'è')
img2 = img.dup; img2[225 * stride, stride] = [0, 0, 0, 0].pack('C4') * EW
ok(F.vm_ground_edge(img2, stride, EW, EH, [0.0, 225.5, EW.to_f, 225.5, 0.0, 1.0]).empty?, 'orlo già pulito: niente da riscrivere')

puts '── Orli sul cielo'
# 6×5 con 2 byte di riempimento a riga: una nuvola piena (2×2, grigio
# nebbia) con il contorno semitrasparente e scuro, un pixel isolato senza
# vicini pieni, e un pixel che l'orlo del suolo ha già corretto
CW = 6; CH = 5; cst = CW * 4 + 2
cimg = String.new("\0" * (cst * CH), encoding: Encoding::BINARY)
put = ->(x, y, px) { cimg[y * cst + x * 4, 4] = px.pack('C4') }
put.(2, 2, [198, 191, 191, 255]); put.(3, 2, [198, 191, 191, 255])
put.(2, 3, [198, 191, 191, 255]); put.(3, 3, [198, 191, 191, 255])
put.(1, 2, [99, 96, 96, 64]); put.(4, 3, [50, 48, 48, 16]); put.(2, 1, [149, 144, 144, 128])
put.(1, 3, [10, 10, 10, 200])                               # già corretto dall'orlo del suolo
cimg[0 * cst + CW * 4, 2] = "\x80\x80".b                    # riempimento: non è un pixel
done = { 3 * cst + 1 * 4 => true }
cc = F.vm_edge_clean(cimg, cst, CW, CH, done).to_h
ok(cc.size == 3 && [[1, 2, 64], [4, 3, 16], [2, 1, 128]].all? { |x, y, a| cc[y * cst + x * 4]&.unpack('C4') == [198, 191, 191, a] },
   "contorno: i #{cc.size} pixel semitrasparenti prendono il colore della nuvola e tengono l'opacità")
ok(!cc.key?(3 * cst + 1 * 4), 'un pixel già corretto dall\'orlo del suolo non si tocca di nuovo')
cimg2 = String.new("\0" * (cst * CH), encoding: Encoding::BINARY)
cimg2[2 * cst + 2 * 4, 4] = [20, 20, 20, 90].pack('C4')
ok(F.vm_edge_clean(cimg2, cst, CW, CH).empty?, 'un filo isolato senza vicini pieni resta com\'è')
ok(F.vm_edge_clean(String.new("\0" * (cst * CH), encoding: Encoding::BINARY), cst, CW, CH).empty?, 'cielo vuoto: niente da riscrivere')

puts '── Affine (texture → schermo)'
m = F.vm_affine([0, 0], [64, 0], [0, 32], [10, 20], [74, 30], [5, 52])
a = F.vm_aff(m, 64, 32)
ok(near(a[0], 69) && near(a[1], 62), 'quarto vertice del parallelogramma')
ok(F.vm_affine([0, 0], [1, 1], [2, 2], [0, 0], [1, 1], [2, 2]).nil?, 'punti allineati: nessuna trasformazione')
ok(F.vm_same_affine?(m, m.map { |x| x + 1e-4 }, 64, 32) && !F.vm_same_affine?(m, m.map { |x| x + 1 }, 64, 32), 'stessa trasformazione a meno di mezzo pixel')

puts '── Cielo di fondo (come SketchUp)'
ro = { 'BackgroundColor' => Sketchup::Color.new(0, 255, 0), 'SkyColor' => Sketchup::Color.new(0, 0, 255),
       'HorizonColor' => Sketchup::Color.new(255, 0, 0), 'DisplayFog' => false, 'FogUseBkColor' => true,
       'FogColor' => Sketchup::Color.new(255, 255, 0) }
px_at = ->(data, bw, i, j) { data[(j * bw + i) * 4, 4].unpack('C4') }   # B G R A
data, bw, bh = F.vm_sky_pixels(pr, W, H, ro, true)
ok(bw == F::VM_SKY_W && bh == (bw * H / W.to_f).round && data.bytesize == bw * bh * 4, "#{bw}×#{bh} pixel")
ok(px_at.(data, bw, bw / 2, 0) == [255, 0, 0, 255], 'in alto (30°): colore del cielo')
ok(px_at.(data, bw, bw / 2, bh - 1) == [0, 255, 0, 255], 'sotto l\'orizzonte: sfondo')
row = (0...bh).find { |j| F.vm_ray(pr, W / 2.0, (j + 0.5) * H / bh)[2] >= 0 && F.vm_ray(pr, W / 2.0, (j + 1.5) * H / bh)[2] < 0 }
b, _g, rr, = px_at.(data, bw, bw / 2, row)
ok(rr > 240 && b < 15, "appena sopra l'orizzonte: colore dell'orizzonte (#{rr}, #{b})")
mid = (0...bh).min_by { |j| d = F.vm_ray(pr, W / 2.0, (j + 0.5) * H / bh); (Math.atan2(d[2], d[1]) - F::VM_SKY_FADE / 2).abs }
b, _g, rr, = px_at.(data, bw, bw / 2, mid)
ok((rr - 128).abs < 20 && (b - 128).abs < 20, "a metà sfumatura: metà e metà (#{rr}, #{b})")
data, = F.vm_sky_pixels(pr, W, H, ro.merge('DisplayFog' => true), true)
ok(data.unpack('C4').uniq == [0, 255, 0, 255] || data.bytes.each_slice(4).to_a.uniq == [[0, 255, 0, 255]], 'nebbia: tutto del colore dello sfondo')
data, = F.vm_sky_pixels(pr, W, H, ro.merge('DisplayFog' => true, 'FogUseBkColor' => false), true)
ok(data.bytes.each_slice(4).to_a.uniq == [[0, 255, 255, 255]], 'nebbia col suo colore')
data, = F.vm_sky_pixels(pr, W, H, ro, false)
ok(data.bytes.each_slice(4).to_a.uniq == [[0, 255, 0, 255]], 'senza cielo: tutto sfondo')

puts '── Suolo dipinto (il mare senza la trama del suolo di SketchUp)'
ro_g = ro.merge('GroundColor' => Sketchup::Color.new(34, 92, 128), 'HorizonColor' => Sketchup::Color.new(191, 230, 246),
                'FogStartDist' => 8 * M, 'FogEndDist' => 150 * M, 'BackgroundColor' => Sketchup::Color.new(191, 191, 198))
gm = F.vm_ground_model(ro_g, [191, 230, 246], 5 * M)
ok(F.vm_ground_rgb(gm, 1.0) == [34, 92, 128].each_with_index.map { |c, q| (c + ([191, 230, 246][q] - c) * 0.4 * (1 - Math.exp(-5 / 255.0))).round },
   'sotto i piedi: quasi il colore del suolo')
c_far = F.vm_ground_rgb(gm, 1e6)
ok(c_far == [97, 147, 175], "lontanissimo: 0,4 verso l'orizzonte, come SketchUp (#{c_far.inspect})")
# misurati su SketchUp 2024 (Stromboli, 4–43 m d'altezza): 80–150 m → 57 112 145, 400–1500 m → 91 142 171
c_mid = F.vm_ground_rgb(F.vm_ground_model(ro_g, [191, 230, 246], 1 * M), 110.0)
ok(c_mid.zip([57, 112, 145]).all? { |a, b| (a - b).abs <= 3 }, "a 110 m come SketchUp (#{c_mid.inspect})")
gmf = F.vm_ground_model(ro_g.merge('DisplayFog' => true), [191, 230, 246], 1 * M)
ok(F.vm_ground_rgb(gmf, 5.0) == F.vm_ground_rgb(F.vm_ground_model(ro_g, [191, 230, 246], 1 * M), 5.0), 'prima dell\'inizio della nebbia: niente nebbia')
ok(F.vm_ground_rgb(gmf, 200.0) == [191, 191, 198], 'oltre la fine della nebbia: il suo colore')
half = F.vm_ground_rgb(gmf, 79.0)
ok(half[0] > 100 && half[0] < 130, "a metà nebbia: a metà strada (#{half.inspect})")
data, bw, bh = F.vm_sky_pixels(pr, W, H, ro_g, true, true)
ok(bw == F::VM_GROUND_W && bh == H && data.bytesize == bw * bh * 4, "col suolo: #{bw}×#{bh}, righe quante l'immagine")
hrow = (0...H).find { |j| F.vm_ray(pr, W / 2.0, j + 0.5)[2] < 0 }
ok(px_at.(data, bw, bw / 2, hrow - 1)[0, 3] == [246, 230, 191], 'sopra l\'orizzonte: il colore dell\'orizzonte')
ok(px_at.(data, bw, bw / 2, hrow) == [175, 147, 97, 255] || px_at.(data, bw, bw / 2, hrow)[0] > 160, 'appena sotto: il suolo lontano')
ok(px_at.(data, bw, bw / 2, H - 1)[0] < 140, "in basso: il suolo vicino, più scuro (#{px_at.(data, bw, bw / 2, H - 1).inspect})")
data, = F.vm_sky_pixels(pr, W, H, ro_g.merge('DisplayFog' => true), true, true)
ok(px_at.(data, bw, bw / 2, 0) == [198, 191, 191, 255] && px_at.(data, bw, bw / 2, hrow) == [198, 191, 191, 255],
   'nebbia: cielo e suolo lontano del suo colore')
ok(px_at.(data, bw, bw / 2, H - 1) != [198, 191, 191, 255], 'nebbia: il suolo vicino resta suo')

GModel = Struct.new(:rendering_options, :shadow_info, :active_path, :active_entities)
GEnts = Struct.new(:active_section_plane)
gmod = ->(ro_x = {}, si = {}, path = nil, sec = nil) {
  GModel.new({ 'DrawGround' => true, 'GroundTransparency' => 0 }.merge(ro_x), { 'DisplayShadows' => true, 'DisplayOnGroundPlane' => false }.merge(si), path, GEnts.new(sec))
}
ok(F.vm_own_ground?(gmod.(), true, 10.0), 'suolo opaco, camera sopra: lo dipinge il video')
ok(!F.vm_own_ground?(gmod.(), false, 10.0), 'senza cielo: resta quello di SketchUp')
ok(!F.vm_own_ground?(gmod.(), true, -1.0), 'camera sotto il suolo: resta quello di SketchUp')
ok(!F.vm_own_ground?(gmod.('DrawGround' => false), true, 10.0), 'suolo spento: niente suolo')
ok(!F.vm_own_ground?(gmod.('GroundTransparency' => 40), true, 10.0), 'suolo trasparente: resta quello di SketchUp')
ok(!F.vm_own_ground?(gmod.({}, 'DisplayOnGroundPlane' => true), true, 10.0), 'ombre sul suolo: resta quello di SketchUp')
ok(!F.vm_own_ground?(gmod.({}, {}, [:gruppo]), true, 10.0), 'gruppo aperto: resta quello di SketchUp')
ok(!F.vm_own_ground?(gmod.({}, {}, nil, :sezione), true, 10.0), 'sezione attiva: resta quello di SketchUp')

puts '── Profondità'
dg = { w: 2, h: 1, kx: 2 / 100.0, ky: 1 / 50.0, d: [10.0, Float::INFINITY] }
ok(F.vm_visible?(nil, 0, 0, 1e9), 'senza mappa tutto visibile')
ok(!F.vm_visible?({ w: 1, h: 1, kx: 0.01, ky: 0.02, d: [10.0] }, 50, 25, 20.0), 'dietro il muro: nascosta')
ok(F.vm_visible?({ w: 1, h: 1, kx: 0.01, ky: 0.02, d: [10.0] }, 50, 25, 5.0), 'davanti al muro: visibile')
ok(F.vm_visible?(dg, 49, 25, 20.0), 'al bordo del muro conta la cella più lontana')
ok(!F.vm_visible?(dg, 5, 25, 20.0), 'dentro il muro: nascosta')

puts '── Orologio del video'
F.instance_variable_set(:@vm_export, true)
fake = Object.new                                # se il timer lo usasse, fallirebbe
F.instance_variable_set(:@sky_model, fake)
F.instance_variable_set(:@cloud_model, fake)
F.instance_variable_set(:@precip_model, fake)
F.instance_variable_set(:@snow_model, fake)
ok(F.sky_frame.nil? && F.cloud_frame.nil? && F.precip_frame.nil? && F.snow_frame.nil?, 'durante l\'export i timer del meteo non fanno nulla')
%i[@sky_model @cloud_model @precip_model @snow_model].each { |k| F.instance_variable_set(k, nil) }
F.instance_variable_set(:@vm_export, false)
cfg['sky_now'] = false; cfg['sky_flow'] = true; cfg['sky_day_minutes'] = 1.5
ok(near(F.vm_sky_rate, 960.0), 'giorno di 1,5 minuti: 960 s di cielo per secondo di video')
cfg['sky_flow'] = false
ok(F.vm_sky_rate.zero?, 'tempo fermo: il cielo non si muove')
cfg['sky_now'] = true
ok(F.vm_sky_rate == 1.0, 'ora attuale: un secondo per secondo')
cfg['sky_now'] = false
ok(F.vm_begin({ w: 10, h: 10 }).nil? && !F.vm_export?, 'senza meteo acceso niente orologio del video')

puts '── Fotogramma: com\'è o col meteo, e ripiego'
class ShotView
  attr_reader :opts
  def write_image(o); @opts = o; true; end
end
sv = ShotView.new
F.path_shot(sv, { w: 64, h: 36 }, File.join(tmp, 'a.jpg'), :jpg)
ok(sv.opts[:compression] == 0.9 && sv.opts[:width] == 64 && !sv.opts.key?(:transparent), 'JPEG com\'è nella vista')
F.path_shot(sv, { w: 64, h: 36 }, File.join(tmp, 'a.png'), :png)
ok(!sv.opts.key?(:compression), 'PNG senza compressione')
job = { w: 64, h: 36, vm: { paint: true, texs: {}, tex: [nil] * 4, png: File.join(tmp, 'm.png') } }
r = F.path_shot(sv, job, File.join(tmp, 'b.jpg'), :jpg)     # il modello finto non ha rendering_options
ok(r == true && job[:vm][:paint] == false && sv.opts[:filename].end_with?('b.jpg'), 'GDI+ o modello in errore: il fotogramma esce lo stesso, senza meteo')

if RUBY_PLATFORM =~ /mingw|mswin/
  puts '── GDI+ (Windows)'
  begin
    G = F::VmGdi
    G.start
    bmp = G.bitmap(32, 16)
    g = G.graphics(bmp)
    G.clear(g, 0xFF000000)
    G.fill(g, G.brush(0xFFFF0000), [[0, 0], [32, 0], [32, 16], [0, 16]])
    G.line(g, G.pen(0xFF00FF00, 2.0), 0, 8, 32, 8)
    sky = ([0, 0, 255, 255].pack('C4') * 4)
    G.draw_pixels(g, G.attributes, sky, 2, 2, 32, 16)
    G.save(bmp, File.join(tmp, 'g.png'), :png)
    G.save(bmp, File.join(tmp, 'g.jpg'), :jpg)
    ok(File.binread(File.join(tmp, 'g.png'), 4) == "\x89PNG".b, 'GDI+ salva PNG')
    ok(File.binread(File.join(tmp, 'g.jpg'), 2) == "\xFF\xD8".b, 'GDI+ salva JPEG')
    G.delete_graphics(g)
    G.dispose_image(bmp)
    # Un PNG con la riga d'orlo scura e semitrasparente, sul cielo azzurro
    row = ->(px) { px.pack('C4') * 8 }
    src = G.bitmap_from(8, 4, row.([0, 0, 0, 0]) + row.([0, 0, 0, 0]) + row.([20, 20, 20, 100]) + row.([200, 200, 200, 255]))
    edge_png = File.join(tmp, 'orlo.png')
    G.save(src, edge_png, :png)
    G.dispose_image(src)
    paint = lambda do |fix|
      b = G.bitmap(8, 4); gg = G.graphics(b)
      G.clear(gg, 0xFFC0C0C0)
      err = fix ? G.draw_file(gg, edge_png, 8, 4) { |buf, st| F.vm_ground_edge(buf, st, 8, 4, [0.0, 2.5, 8.0, 2.5, 0.0, 1.0]) } : G.draw_file(gg, edge_png, 8, 4)
      G.delete_graphics(gg)
      px = nil
      G.pixels(b, 8, 4) { |buf, st| px = buf.byteslice(2 * st + 4 * 4, 4).unpack('C4'); [] }
      G.dispose_image(b)
      [err, px]
    end
    e0, dark = paint.(false)
    e1, clean = paint.(true)
    ok(e0.nil? && e1.nil? && dark[0] < 150 && clean[0] > 185,
       "GDI+: senza correzione l'orlo esce scuro (#{dark[0]}), con la correzione no (#{clean[0]})")
  rescue StandardError, LoadError => e
    ok(false, "GDI+: #{e.class}: #{e.message}")
  end
end

puts
puts $fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"
exit($fail.zero? ? 0 : 1)
