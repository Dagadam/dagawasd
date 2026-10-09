# Pacchetti .rbz, completo e per l'Extension Warehouse: si creano, contengono
# solo l'estensione, e l'estensione estratta si carica da sola come in
# SketchUp (loader → main.rb → lib/), ognuna in un processo a sé.
#   Esecuzione:  ruby -E UTF-8 tests/test_rbz.rb   (oppure tests\run_tests.bat)
require 'tmpdir'
require 'open3'
require 'rbconfig'
require 'json'
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
def fine; puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"; exit($fail.zero? ? 0 : 1); end

ROOT = File.expand_path('..', __dir__)
ver  = File.read(File.join(ROOT, 'dagawasd.rb'), encoding: 'UTF-8')[/VERSION = '(\d+\.\d+\.\d+)'/, 1]
ok(ver, "versione in dagawasd.rb: #{ver}")

# Estrazione con uno strumento che non è il nostro: il tar di Windows legge gli zip
tar = File.join(ENV['SystemRoot'] || 'C:/Windows', 'System32', 'tar.exe')
unless File.exist?(tar)
  puts '  [salto] estrazione: tar.exe di Windows non trovato'
  fine
end

sorgente = ->(n) { n == 'dagawasd.rb' ? File.join(ROOT, n) : File.join(ROOT, n.delete_prefix('dagawasd/')) }
tutti = (%w[dagawasd.rb dagawasd/main.rb dagawasd/panel.html dagawasd/attesa.html dagawasd/LICENSE] +
         Dir.glob('{lib/*.rb,lang/*.json,icons/*.png,attesa/*.{webp,gif,png}}', base: ROOT).map { |f| "dagawasd/#{f}" }).sort

[[false, "dagawasd-#{ver}.rbz", 'completo'], [true, "dagawasd-#{ver}-warehouse.rbz", 'Extension Warehouse']].each do |wh, nome, quale|
  puts "\n── Pacchetto #{quale} ──"
  out_dir = Dir.mktmpdir('dagawasd_rbz')
  args = [RbConfig.ruby, '-E', 'UTF-8', File.join(ROOT, 'tools', 'crea_rbz.rb')] + (wh ? ['--warehouse'] : []) + [out_dir]
  out, st = Open3.capture2e(*args)
  rbz = File.join(out_dir, nome)
  ok(st.success? && File.exist?(rbz), "crea_rbz crea #{nome}#{st.success? ? '' : "\n#{out}"}")
  next unless File.exist?(rbz)

  x = Dir.mktmpdir('dagawasd_rbz_x')
  out, st = Open3.capture2e(tar, '-xf', rbz, '-C', x)
  ok(st.success?, "il tar di Windows lo estrae#{st.success? ? '' : ": #{out}"}")

  nomi = Dir.glob('**/*', base: x).select { |f| File.file?(File.join(x, f)) }.sort
  attesi = wh ? tutti - ['dagawasd/lib/bridge.rb'] : tutti
  ok(nomi == attesi, "contiene esattamente loader, main.rb, panel.html, attesa.html, LICENSE, lib, lang e icons (#{nomi.size} file)" +
                     (wh ? ', senza lib/bridge.rb' : ''))
  ok(nomi.none? { |n| n =~ /settings\.json|\.log\z|\.txt\z/ }, 'niente settings.json né registri')
  # installa.bat (per lo sviluppo) deve copiare le stesse cose: un file nuovo
  # nel pacchetto ma non lì resta fuori dall'installazione (attesa.html, 2026-10-09)
  unless wh
    bat = File.read(File.join(ROOT, 'installa.bat'), encoding: 'UTF-8')
    voci = nomi.map { |n| n.delete_prefix('dagawasd/').split('/').first }.uniq - ['LICENSE']
    fuori = voci.reject { |v| bat.include?("%SRC%\\#{v}") }
    ok(fuori.empty?, "installa.bat copia tutto quello che ha il pacchetto#{fuori.empty? ? '' : ": manca #{fuori.join(', ')}"}")
  end
  diversi = nomi.reject { |n| File.binread(File.join(x, n)) == File.binread(sorgente.(n)) }
  ok(diversi.empty?, "file estratti identici ai sorgenti#{diversi.empty? ? '' : ": #{diversi.join(', ')}"}")
  if wh
    codice = nomi.select { |n| n.end_with?('.rb') }.map { |n| File.read(File.join(x, n), encoding: 'UTF-8') }.join("\n")
    ok(codice !~ /instance_eval|\beval\(|TCPServer/, 'nessun codice che esegue Ruby ricevuto da fuori (eval, TCPServer)')
  end

  out, st = Open3.capture2e(RbConfig.ruby, '-E', 'UTF-8', File.join(__dir__, 'support', 'carica_estratto.rb'), x)
  r = (JSON.parse(out.lines.last) rescue nil)
  ok(st.success? && r, "l'estensione estratta si carica#{r ? '' : ":\n#{out}"}")
  next unless r
  ok(r['name'] == 'DagaWASD' && r['version'] == ver, "il loader registra DagaWASD #{ver}")
  ok(r['creator'] == 'Dagadam' && r['copyright'].to_s.include?('Dagadam'), "autore: #{r['creator']}, #{r['copyright']}")
  ok(!r['description'].to_s.empty?, 'descrizione per il Gestore estensioni')
  ok(r['plugin_dir'] == File.expand_path(File.join(x, 'dagawasd')), 'main.rb e lib/ caricati dalla cartella estratta')
  ok(r['menu'] && r['panel'], 'menu Plugins › DagaWASD registrato, panel.html al suo posto')
  fuori = [r['log_file'], r['settings_file']].none? { |f| f.start_with?(r['plugin_dir']) }
  ok(fuori, 'registro errori e impostazioni fuori dalla cartella dell\'estensione')
  ok(r['arabic'], 'lingue presenti: arabo caricato, da destra a sinistra')
  if wh
    ok(!r['bridge'] && !r['bridge_server'], 'senza ponte per Claude: nessun server')
    ok(!r['description'].include?('Claude'), 'la descrizione non parla del ponte')
    ok(r['panel_bridge'] == false && !r['set_bridge_sent'], 'il pannello riceve bridge: false e nasconde la sezione')
  else
    ok(r['bridge'] && r['panel_bridge'] == true && r['set_bridge_sent'], 'con il ponte per Claude, sezione nel pannello')
    ok(r['description'].include?('Claude Code'), 'la descrizione cita il ponte')
  end
end

fine
