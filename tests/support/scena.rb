# Scena finta per l'esploratore autonomo (tests/test_explore.rb): scatole con
# facce vere per model.raytest, una camera prospettica con pickray, una vista
# che registra cosa si disegna e sa fare write_image in BMP (ray tracing
# delle stesse scatole). Misure in pollici, come in SketchUp.
module Sketchup
  class Color
    attr_reader :red, :green, :blue, :alpha
    def initialize(r = 0, g = 0, b = 0, a = 255)
      r, g, b = r if r.is_a?(Array)
      @red = r.to_i; @green = g.to_i; @blue = b.to_i; @alpha = a.to_i
    end
  end
end

module Scena
  M = 39.3701
  @eid = 0
  def self.eid; @eid += 1; end

  class Mat
    attr_reader :color, :display_name
    def initialize(name, rgb); @display_name = name; @color = Sketchup::Color.new(*rgb); end
  end

  class Face < Sketchup::Face
    attr_reader :normal, :entityID
    attr_accessor :material, :back_material
    attr_writer :area
    def initialize(n, mat); @normal = Geom::Vector3d.new(*n); @material = mat; @back_material = nil; @entityID = Scena.eid; @area = 1.0; end
    def area(_tr = nil); @area; end            # pollici quadrati, come Face#area
    def valid?; true; end
  end

  class Defn
    attr_reader :entities, :name
    def initialize(name); @name = name; @entities = []; end
  end

  class Inst < Sketchup::ComponentInstance
    attr_reader :entityID, :definition, :transformation
    attr_accessor :name, :material, :bounds
    def initialize(name); @definition = Defn.new(name); @name = ''; @material = nil; @entityID = Scena.eid
                          @transformation = Geom::Transformation.new; @bounds = Geom::BoundingBox.new; end
    def valid?; true; end
  end

  # Una scatola: 6 facce con normale uscente; prefix = istanze che la contengono
  Box = Struct.new(:min, :max, :faces, :prefix)

  class World
    attr_reader :boxes
    def initialize; @boxes = []; end

    # a, b in metri; mat = Mat; inst = istanza a cui appartiene (o nil)
    def box(a, b, mat, inst = nil)
      mn = a.map { |v| v * M }
      mx = b.map { |v| v * M }
      faces = [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]].map { |n| Face.new(n, mat) }
      dim = (0..2).map { |k| mx[k] - mn[k] }
      faces.each_with_index { |f, i| ax = i / 2; f.area = dim.each_with_index.reject { |_, k| k == ax }.map(&:first).reduce(:*) }
      if inst
        inst.definition.entities.concat(faces)
        inst.bounds.add(Geom::Point3d.new(*mn))
        inst.bounds.add(Geom::Point3d.new(*mx))
      end
      @boxes << Box.new(mn, mx, faces, inst ? [inst] : [])
      self
    end

    # Il raytest di SketchUp: il primo colpo davanti all'origine → [punto, percorso]
    def raytest(o, d)
      best = nil
      @boxes.each do |bx|
        t0 = -Float::INFINITY; t1 = Float::INFINITY; f0 = nil; f1 = nil
        hit = true
        [[o.x, d.x, 0], [o.y, d.y, 1], [o.z, d.z, 2]].each do |oo, dd, ax|
          lo = bx.min[ax]; hi = bx.max[ax]
          if dd.abs < 1e-12
            if oo < lo || oo > hi then hit = false; break end
            next
          end
          a = (lo - oo) / dd; b = (hi - oo) / dd
          fa = ax * 2; fb = ax * 2 + 1                  # faccia del lato "lo" e del lato "hi"
          if a > b then a, b = b, a; fa, fb = fb, fa end
          if a > t0 then t0 = a; f0 = fa end
          if b < t1 then t1 = b; f1 = fb end
          if t0 > t1 then hit = false; break end
        end
        next unless hit
        t, fi = t0 > 1e-6 ? [t0, f0] : (t1 > 1e-6 ? [t1, f1] : nil)
        next unless t
        best = [t, bx, fi] if best.nil? || t < best[0]
      end
      return nil unless best
      t, bx, fi = best
      [Geom::Point3d.new(o.x + d.x * t, o.y + d.y * t, o.z + d.z * t), bx.prefix + [bx.faces[fi]]]
    end

    # Colore di un punto colpito (per il "rendering" di write_image)
    def shade(o, d, sky)
      r = raytest(o, d)
      return sky unless r
      f = r[1].last
      c = f.material ? f.material.color : Sketchup::Color.new(240, 240, 240)
      n = f.normal
      k = 0.55 + 0.45 * [n.x * 0.3 + n.y * 0.5 + n.z * 0.8, 0.0].max
      [c.red * k, c.green * k, c.blue * k].map { |v| v.round.clamp(0, 255) }
    end
  end

  class Cam
    attr_reader :eye, :target, :up
    attr_accessor :fov, :perspective
    def initialize(eye, target, fov = 60.0)
      @fov = fov; @perspective = true
      set(eye, target, Geom::Vector3d.new(0, 0, 1))
    end
    def perspective?; @perspective; end
    def set(e, t, u); @eye = e; @target = t; @up = u; end
    def direction
      d = Geom::Vector3d.new(@target.x - @eye.x, @target.y - @eye.y, @target.z - @eye.z)
      d.normalize!
    end
    # base ortonormale: avanti, destra, alto
    def basis
      f = direction
      u = @up
      r = Geom::Vector3d.new(f.y * u.z - f.z * u.y, f.z * u.x - f.x * u.z, f.x * u.y - f.y * u.x)
      r = Geom::Vector3d.new(f.y, -f.x, 0.0) if r.length < 1e-9
      r.normalize!
      up = Geom::Vector3d.new(r.y * f.z - r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y - r.y * f.x)
      [f, r, up]
    end
  end

  class View
    attr_accessor :camera, :world
    attr_reader :anim, :drawn, :images
    def initialize(world, cam, w = 640, h = 360)
      @world = world; @camera = cam; @w = w; @h = h; @drawn = []; @images = 0
    end
    def vpwidth; @w; end
    def vpheight; @h; end
    def animation=(a)
      old = @anim
      @anim = a
      old.stop if old && !old.equal?(a) && old.respond_to?(:stop)
    end
    def invalidate; end
    def refresh; end
    def pickray(x, y)
      f, r, u = @camera.basis
      th = Math.tan(@camera.fov * Math::PI / 360.0)
      a = (2.0 * x / @w - 1.0) * th * @w / @h
      b = (1.0 - 2.0 * y / @h) * th
      d = Geom::Vector3d.new(f.x + r.x * a + u.x * b, f.y + r.y * a + u.y * b, f.z + r.z * a + u.z * b)
      e = @camera.eye
      [Geom::Point3d.new(e.x, e.y, e.z), d.normalize!]
    end
    def screen_coords(p)
      f, r, u = @camera.basis
      e = @camera.eye
      v = [p.x - e.x, p.y - e.y, p.z - e.z]
      z = v[0] * f.x + v[1] * f.y + v[2] * f.z
      th = Math.tan(@camera.fov * Math::PI / 360.0)
      a = (v[0] * r.x + v[1] * r.y + v[2] * r.z) / z / (th * @w / @h)
      b = (v[0] * u.x + v[1] * u.y + v[2] * u.z) / z / th
      Geom::Point3d.new((a + 1.0) * @w / 2.0, (1.0 - b) * @h / 2.0, 0)
    end
    def draw_points(pts, size, style, color); @drawn << [:points, pts.size, size, style, color]; end
    def draw_text(pt, txt, opts = nil); @drawn << [:text, txt, pt.x, pt.y, opts]; end
    def draw2d(*a); @drawn << [:draw2d, a.first]; end
    def drawing_color=(c); end
    def line_width=(w); end
    def line_stipple=(s); end
    def draw(*a); @drawn << [:draw, a.first, a[1].size]; end
    # BMP a 24 bit dal basso, come quelli di SketchUp: le stesse scatole, ombreggiate
    def write_image(o)
      w = o[:width]; h = o[:height]
      @images += 1
      rows = (0...h).map do |y|
        row = (0...w).map do |x|
          org, dir = pickray((x + 0.5) * @w / w, (y + 0.5) * @h / h)
          r, g, b = @world.shade(org, dir, [200, 220, 245])
          [b, g, r].pack('C3')
        end.join
        row + ("\x00".b * ((4 - (w * 3) % 4) % 4))
      end
      Scena.bmp24(o[:filename], w, h, rows.reverse.join)
      true
    end
  end

  def self.bmp24(file, w, h, pixels, top_down: false, bpp: 24)
    off = 54
    hdr = ['BM', off + pixels.bytesize, 0, 0, off].pack('a2VvvV')
    dib = [40, w, top_down ? -h : h, 1, bpp, 0, pixels.bytesize, 2835, 2835, 0, 0].pack('Vl<l<vvVVl<l<VV')
    File.binwrite(file, hdr + dib + pixels)
  end

  Layer = Struct.new(:name, :visible) do
    def visible?; visible; end
  end

  class Model
    attr_reader :view, :ops, :dicts, :tool, :world
    attr_accessor :ro
    def initialize(world, view)
      @world = world; @view = view; @ops = []; @dicts = {}; @tool = nil
      @ro = { 'FaceFrontColor' => Sketchup::Color.new(255, 255, 255), 'FaceBackColor' => Sketchup::Color.new(160, 170, 200) }
    end
    def active_view; @view; end
    def raytest(ray, _wysiwyg = true); @world.raytest(ray[0], ray[1]); end
    def bounds
      bb = Geom::BoundingBox.new
      @world.boxes.each { |b| bb.add(Geom::Point3d.new(*b.min)); bb.add(Geom::Point3d.new(*b.max)) }
      bb
    end
    def rendering_options; @ro; end
    def select_tool(t)
      old = @tool
      @tool = t
      old.deactivate(@view) if old && !old.equal?(t) && old.respond_to?(:deactivate)
      t.activate if t.respond_to?(:activate) && !old.equal?(t)
    end
    def attribute_dictionary(n, create = false); @dicts[n] ||= {} if create; @dicts[n]; end
    def set_attribute(d, k, v); attribute_dictionary(d, true)[k] = v; end
    def start_operation(name, *_); @ops << [:start, name]; true; end
    def commit_operation; @ops << [:commit]; true; end
    def abort_operation; @ops << [:abort]; true; end
    def entities; []; end
    def active_entities; []; end
    # tag per nome: c'è solo quello delle posizioni dei percorsi, se un test lo mette
    def layers; @layers ||= {}; end
    def active_path; nil; end
    def title; 'scena'; end
    def path; ''; end
    def options; { 'UnitsOptions' => { 'LengthUnit' => 4 } }; end
  end

  # ── Le due stanze ──────────────────────────────────────────────
  # Stanza A (x da -8 a 0) e stanza B (x da 0 a 8), larghe 12 m, alte 3 m,
  # separate da un muro con una porta di 1,4 m al centro. La stanza A ha il
  # soffitto, la B no (il cielo, come in tanti modelli). Quattro oggetti.
  def self.due_stanze
    w = World.new
    pav = Mat.new('Pavimento', [190, 186, 178])
    mur = Mat.new('Intonaco', [236, 233, 226])
    w.box([-8, -6, -0.1], [8, 6, 0], pav)                       # pavimento
    w.box([-8.2, -6.2, 0], [-8, 6.2, 3], mur)                   # muri esterni
    w.box([8, -6.2, 0], [8.2, 6.2, 3], mur)
    w.box([-8, -6.2, 0], [8, -6, 3], mur)
    w.box([-8, 6, 0], [8, 6.2, 3], mur)
    w.box([-0.1, -6, 0], [0.1, -0.7, 3], mur)                   # muro divisorio con la porta
    w.box([-0.1, 0.7, 0], [0.1, 6, 3], mur)
    w.box([-0.1, -0.7, 2.1], [0.1, 0.7, 3], mur)                # architrave
    w.box([-8, -6, 3], [-0.1, 6, 3.1], mur)                     # soffitto della stanza A
    objs = {}
    legno = Mat.new('Rovere', [139, 94, 60])
    t = objs[:tavolo] = Inst.new('Tavolo')
    w.box([-4.6, 1.6, 0.7], [-3.4, 2.4, 0.76], legno, t)
    [[-4.55, 1.65], [-3.5, 1.65], [-4.55, 2.3], [-3.5, 2.3]].each { |x, y| w.box([x, y, 0], [x + 0.05, y + 0.05, 0.7], legno, t) }
    s = objs[:statua] = Inst.new('Statua')
    w.box([-5.3, -3.3, 0], [-4.7, -2.7, 0.9], Mat.new('Marmo', [228, 228, 222]), s)
    w.box([-5.15, -3.15, 0.9], [-4.85, -2.85, 1.9], Mat.new('Bronzo rosso', [178, 40, 34]), s)
    d = objs[:divano] = Inst.new('Divano')
    blu = Mat.new('Velluto blu', [40, 70, 160])
    w.box([3, 3, 0], [5, 3.9, 0.45], blu, d)
    w.box([3, 3.7, 0.45], [5, 3.9, 0.95], blu, d)
    w.box([3, 3, 0.45], [3.2, 3.9, 0.7], blu, d)
    w.box([4.8, 3, 0.45], [5, 3.9, 0.7], blu, d)
    pi = objs[:pianta] = Inst.new('Pianta')
    w.box([4.8, -3.2, 0], [5.2, -2.8, 0.4], Mat.new('Terracotta', [190, 95, 60]), pi)
    verde = Mat.new('Foglie', [60, 150, 60])
    8.times do |k|
      a = k * Math::PI / 4
      x = 5.0 + Math.cos(a) * 0.25
      y = -3.0 + Math.sin(a) * 0.25
      w.box([x - 0.12, y - 0.12, 0.4 + k * 0.08], [x + 0.12, y + 0.12, 0.6 + k * 0.08], verde, pi)
    end
    [w, objs]
  end

  def self.setup(world, eye_m, target_m, fov = 60.0)
    cam = Cam.new(Geom::Point3d.new(*eye_m.map { |v| v * M }), Geom::Point3d.new(*target_m.map { |v| v * M }), fov)
    view = View.new(world, cam)
    model = Model.new(world, view)
    Sketchup.define_singleton_method(:active_model) { model }
    [model, view, cam]
  end
end
