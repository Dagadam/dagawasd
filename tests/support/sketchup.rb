# Finta API di SketchUp: solo quanto serve a caricare main.rb e a provare
# le funzioni di calcolo puro fuori da SketchUp. Si chiama sketchup.rb perché
# main.rb fa `require 'sketchup'`: i test mettono questa cartella in testa al
# $LOAD_PATH, così viene caricata questa al posto di quella vera.

# main.rb all'avvio accende ponte, cielo, meteo e neve: gli errori che
# questa finta API provoca lì vanno in un registro temporaneo, non nel
# dagawasd.log del progetto. Ogni test può poi sceglierne uno suo.
require 'tmpdir'
# Impostazioni e file del ponte stanno in %APPDATA%\DagaWASD: i test usano
# una cartella temporanea vuota, mai quella vera dell'utente.
ENV['APPDATA'] = Dir.mktmpdir('dagawasd_test_appdata')
module DagaWASD
  module FPSWalk
    @log_file  = File.join(Dir.tmpdir, 'dagawasd_test_load.log')
    @log_quiet = true
  end
end

module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0.0, y = 0.0, z = 0.0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def transform(t); t.apply(self); end
    def -(o); o.is_a?(Point3d) ? Vector3d.new(x - o.x, y - o.y, z - o.z) : Point3d.new(x - o.x, y - o.y, z - o.z); end
    def +(v); Point3d.new(x + v.x, y + v.y, z + v.z); end
    def offset(v, l); k = l / Math.sqrt(v.x**2 + v.y**2 + v.z**2); Point3d.new(x + v.x * k, y + v.y * k, z + v.z * k); end
    def distance(o); Math.sqrt((x - o.x)**2 + (y - o.y)**2 + (z - o.z)**2); end
    def to_a; [x, y, z]; end
  end
  class Vector3d < Point3d
    def length; Math.sqrt(x * x + y * y + z * z); end
    def normalize!; l = length; @x /= l; @y /= l; @z /= l; self; end
    def transform(t); t.apply_vec(self); end
  end
  class Transformation
    attr_reader :m   # 16 valori, per colonne come in SketchUp
    def initialize(m = nil); @m = m || [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1].map(&:to_f); end
    def self.translation(v); new([1,0,0,0, 0,1,0,0, 0,0,1,0, v.x,v.y,v.z,1].map(&:to_f)); end
    def to_a; @m.dup; end
    # Prodotto di trasformazioni (matrici 4×4 per colonne)
    def *(o)
      a = @m; b = o.m
      Transformation.new((0..15).map { |i| c = i / 4; r = i % 4; (0..3).sum { |k| a[k * 4 + r] * b[c * 4 + k] } })
    end
    def apply(p)
      Point3d.new(@m[0]*p.x + @m[4]*p.y + @m[8]*p.z + @m[12],
                  @m[1]*p.x + @m[5]*p.y + @m[9]*p.z + @m[13],
                  @m[2]*p.x + @m[6]*p.y + @m[10]*p.z + @m[14])
    end
    def apply_vec(v)
      Vector3d.new(@m[0]*v.x + @m[4]*v.y + @m[8]*v.z,
                   @m[1]*v.x + @m[5]*v.y + @m[9]*v.z,
                   @m[2]*v.x + @m[6]*v.y + @m[10]*v.z)
    end
  end
end
module Geom
  class BoundingBox
    attr_reader :min, :max
    def initialize(min = nil, max = nil); @min = min; @max = max; end
    def empty?; @min.nil?; end
    def corner(i); Geom::Point3d.new(i & 1 == 0 ? @min.x : @max.x, i & 2 == 0 ? @min.y : @max.y, i & 4 == 0 ? @min.z : @max.z); end
    def add(p)
      @min = @min ? Geom::Point3d.new([@min.x, p.x].min, [@min.y, p.y].min, [@min.z, p.z].min) : Geom::Point3d.new(p.x, p.y, p.z)
      @max = @max ? Geom::Point3d.new([@max.x, p.x].max, [@max.y, p.y].max, [@max.z, p.z].max) : Geom::Point3d.new(p.x, p.y, p.z)
      self
    end
  end
end
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Y_AXIS = Geom::Vector3d.new(0, 1, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)
module Sketchup
  class Face; end; class Edge; end; class Group; end; class ComponentInstance; end
  def self.status_text=(s); end
  def self.get_locale; 'it'; end
  # Come in SketchUp: percorso senza estensione, carica .rb (o .rbe cifrato)
  def self.require(path); Kernel.require(path); end
  # Modello finto: $stub_entities è l'elenco delle entità di primo livello
  Model = Struct.new(:entities)
  def self.active_model; Model.new($stub_entities || []); end
end

# Entità finte con un ingombro: [x0, y0, z0] – [x1, y1, z1] in pollici.
# StubBox è un'entità qualsiasi (es. geometria sciolta); StubGroup si
# comporta da gruppo di SketchUp (is_a?(Sketchup::Group) è vero).
module StubBoxMethods
  attr_accessor :bounds
  def initialize(a, b); move_to(a, b); end
  def move_to(a, b); @bounds = Geom::BoundingBox.new(Geom::Point3d.new(*a), Geom::Point3d.new(*b)); end
  def valid?; true; end
  # Solo traslazioni: assegnare una trasformazione sposta l'ingombro
  def transformation; Geom::Transformation.new; end
  def transformation=(t)
    m = t.m; d = [m[12], m[13], m[14]]
    move_to([bounds.min.x + d[0], bounds.min.y + d[1], bounds.min.z + d[2]],
            [bounds.max.x + d[0], bounds.max.y + d[1], bounds.max.z + d[2]])
  end
  def center; [(bounds.min.x + bounds.max.x) / 2, (bounds.min.y + bounds.max.y) / 2, (bounds.min.z + bounds.max.z) / 2]; end
end
class StubBox
  include StubBoxMethods
end
class StubGroup < Sketchup::Group
  include StubBoxMethods
  def name; ''; end
  def material; nil; end
  def typename; 'Group'; end
end
module Geom
  class BoundingBox
    def diagonal; Math.sqrt((max.x - min.x)**2 + (max.y - min.y)**2 + (max.z - min.z)**2); end
  end
end

# Interfaccia di SketchUp: quanto basta perché main.rb registri menu e
# barra degli strumenti (così anche register_ui viene eseguito nei test).
module UI
  class Menu
    attr_reader :items
    def initialize; @items = []; end
    def add_submenu(name); m = Menu.new; @items << [name, m]; m; end
    def add_item(name, &blk); @items << [name, blk]; end
  end
  class Toolbar
    attr_reader :name, :items
    def initialize(name); @name = name; @items = []; (UI.toolbars << self); end
    def add_item(cmd); @items << cmd; end
    def restore; end
  end
  class Command
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon
    def initialize(name, &blk); @name = name; @blk = blk; end
  end
  def self.menus; @menus ||= {}; end
  def self.toolbars; @toolbars ||= []; end
  def self.menu(name); menus[name] ||= Menu.new; end
  def self.start_timer(*); 1; end
  def self.stop_timer(*); end
  def self.messagebox(*); end
end
MB_OK = 0 unless defined?(MB_OK)
# Primitive di disegno di View#draw (stessi valori di SketchUp)
GL_POINTS = 0; GL_LINES = 1; GL_LINE_LOOP = 2; GL_LINE_STRIP = 3; GL_TRIANGLES = 4
GL_QUADS = 7; GL_QUAD_STRIP = 8; GL_POLYGON = 9

# Quanto serve al ponte per Claude (lib/bridge.rb): osservatore di chiusura,
# versione, operazioni annullabili. $stub_ops registra start/commit/abort.
module Sketchup
  class AppObserver; end
  class ModelObserver; end
  class View; def invalidate; end; end
  class ImageRep                       # immagini per le texture (sole, nuvole)
    attr_reader :args
    def set_data(*a); @args = a; end
  end
  def self.add_observer(_o); true; end
  def self.version; '26.0.0'; end
  def self.platform; $piattaforma || :platform_win; end
  def self.read_default(_s, k, d = nil); ($defaults ||= {}).fetch(k, d); end
  def self.write_default(_s, k, v); ($defaults ||= {})[k] = v; end
  class Model
    def start_operation(*); ($stub_ops ||= []) << :start; true; end
    def commit_operation; ($stub_ops ||= []) << :commit; true; end
    def abort_operation; ($stub_ops ||= []) << :abort; true; end
    def title; 'stub'; end
    def path; ''; end
    def options; { 'UnitsOptions' => { 'LengthUnit' => 4 } }; end
    def active_view; View.new; end
  end
end

# Niente gamepad veri dai test (girano su Windows, Fiddle c'è):
# lib/gamepad.rb usa @xi se c'è già.
module DagaWASD
  module FPSWalk
    # Un gamepad per slot (0–3) o nessuno: stato = [pulsanti, lt, rt, lx, ly, rx, ry]
    class FakeXInput
      attr_accessor :pads
      attr_reader :rumble, :calls
      def initialize; @pads = {}; @rumble = []; @calls = 0; end
      def XInputGetState(slot, buf)
        @calls += 1
        st = @pads[slot] or return 1167                   # ERROR_DEVICE_NOT_CONNECTED
        buf[0, 16] = ([@calls] + st).pack('L<S<CCs<s<s<s<')
        0
      end
      def XInputSetState(_slot, data); @rumble << data.unpack('S<S<'); 0; end
    end
    @xi  = FakeXInput.new
  end
end
