# Pacchetto .rbz: si crea, contiene solo l'estensione, e l'estensione
# estratta si carica da sola come in SketchUp (loader → main.rb → lib/).
#   Esecuzione:  ruby -E UTF-8 tests/test_rbz.rb   (oppure tests\run_tests.bat)
require 'tmpdir'
require 'open3'
require 'rbconfig'
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
def fine; puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"; exit($fail.zero? ? 0 : 1); end

ROOT = File.expand_path('..', __dir__)
ver  = File.read(File.join(ROOT, 'dagawasd.rb'), encoding: 'UTF-8')[/VERSION = '(\d+\.\d+\.\d+)'/, 1]
ok(ver, "versione in dagawasd.rb: #{ver}")

out_dir = Dir.mktmpdir('dagawasd_rbz')
out, st = Open3.capture2e(RbConfig.ruby, '-E', 'UTF-8', File.join(ROOT, 'tools', 'crea_rbz.rb'), out_dir)
rbz = File.join(out_dir, "dagawasd-#{ver}.rbz")
ok(st.success? && File.exist?(rbz), "crea_rbz crea dagawasd-#{ver}.rbz#{st.success? ? '' : "\n#{out}"}")
fine unless File.exist?(rbz)

# Estrazione con uno strumento che non è il nostro: il tar di Windows legge gli zip
tar = File.join(ENV['SystemRoot'] || 'C:/Windows', 'System32', 'tar.exe')
unless File.exist?(tar)
  puts '  [salto] estrazione: tar.exe di Windows non trovato'
  fine
end
x = Dir.mktmpdir('dagawasd_rbz_x')
out, st = Open3.capture2e(tar, '-xf', rbz, '-C', x)
ok(st.success?, "il tar di Windows lo estrae#{st.success? ? '' : ": #{out}"}")

nomi = Dir.glob('**/*', base: x).select { |f| File.file?(File.join(x, f)) }.sort
attesi = (%w[dagawasd.rb dagawasd/main.rb dagawasd/panel.html] +
          Dir.glob('{lib/*.rb,lang/*.json,icons/*.png}', base: ROOT).map { |f| "dagawasd/#{f}" }).sort
ok(nomi == attesi, "contiene esattamente loader, main.rb, panel.html, lib, lang e icons (#{nomi.size} file)")
ok(nomi.none? { |n| n =~ /settings\.json|\.log\z|\.txt\z/ }, 'niente settings.json: un aggiornamento non tocca le impostazioni')
sorgente = ->(n) { n == 'dagawasd.rb' ? File.join(ROOT, n) : File.join(ROOT, n.delete_prefix('dagawasd/')) }
diversi = nomi.reject { |n| File.binread(File.join(x, n)) == File.binread(sorgente.(n)) }
ok(diversi.empty?, "file estratti identici ai sorgenti#{diversi.empty? ? '' : ": #{diversi.join(', ')}"}")

# ── L'estensione estratta si carica da sola ──────────────────────
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
require 'sketchup'
stub = Dir.mktmpdir('dagawasd_rbz_stub')
File.write(File.join(stub, 'extensions.rb'), '')
$LOAD_PATH.unshift(stub)
class SketchupExtension
  attr_accessor :name, :path, :description, :version, :creator, :copyright
  def initialize(name, path); @name = name; @path = path; end
end
module Sketchup
  def self.register_extension(ext, carica)
    $registrata = ext
    load "#{ext.path}.rb" if carica
    true
  end
end
load File.join(x, 'dagawasd.rb')
ext = $registrata
ok(ext && ext.name == 'DagaWASD' && ext.version == ver, "il loader registra DagaWASD #{ver}")
ok(ext && !ext.description.to_s.empty?, 'descrizione per il Gestore estensioni')
F = DagaWASD::FPSWalk
ok(defined?(F::PLUGIN_DIR) && File.expand_path(F::PLUGIN_DIR) == File.expand_path(File.join(x, 'dagawasd')),
   'main.rb e lib/ caricati dalla cartella estratta')
ok(UI.menu('Plugins').items.any? { |n, _| n == 'DagaWASD' }, 'menu Plugins › DagaWASD registrato')
ok(File.exist?(F::PANEL_FILE), 'panel.html al suo posto')
F.load_cfg
F.instance_variable_get(:@cfg)['language'] = 'ar'
F.load_lang
ok(F.t('rt.err_logged') != 'rt.err_logged' && F.instance_variable_get(:@lang_rtl), 'lingue presenti: arabo caricato, da destra a sinistra')

fine
