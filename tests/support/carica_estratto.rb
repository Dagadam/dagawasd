# Carica un'estensione estratta da un .rbz come farebbe SketchUp (loader →
# main.rb → lib/) con la finta API, e stampa in JSON quello che serve a
# tests/test_rbz.rb. Gira in un processo a sé: ogni pacchetto parte da zero.
#   ruby -E UTF-8 tests/support/carica_estratto.rb CARTELLA_ESTRATTA
require 'json'
require 'tmpdir'
x = ARGV[0]
$LOAD_PATH.unshift(__dir__)
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
class Raccoglitore
  attr_reader :script
  def initialize; @script = []; end
  def execute_script(s); @script << s; end
  def visible?; true; end
end

load File.join(x, 'dagawasd.rb')
ext = $registrata
F = DagaWASD::FPSWalk
F.load_cfg
F.instance_variable_get(:@cfg)['language'] = 'ar'
F.load_lang
d = Raccoglitore.new
F.instance_variable_set(:@dialog, d)
F.push_panel_state
lang_payload = JSON.parse(d.script.first[/\AapplyLang\((.*)\)\z/m, 1])
puts JSON.generate(
  'name' => ext&.name, 'version' => ext&.version, 'creator' => ext&.creator,
  'copyright' => ext&.copyright, 'description' => ext&.description,
  'plugin_dir' => File.expand_path(F::PLUGIN_DIR),
  'menu' => UI.menu('Plugins').items.any? { |n, _| n == 'DagaWASD' },
  'panel' => File.exist?(F::PANEL_FILE),
  'log_file' => File.expand_path(F::LOG_FILE),
  'settings_file' => File.expand_path(F::SETTINGS_FILE),
  'bridge' => F.bridge?, 'bridge_server' => F.respond_to?(:bridge_start),
  'panel_bridge' => lang_payload['bridge'],
  'set_bridge_sent' => d.script.any? { |s| s.start_with?('setBridge(') },
  'arabic' => F.t('rt.err_logged') != 'rt.err_logged' && F.instance_variable_get(:@lang_rtl)
)
