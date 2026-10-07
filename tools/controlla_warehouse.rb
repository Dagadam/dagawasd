# encoding: utf-8
# DagaWASD — controllo del pacchetto per l'Extension Warehouse con le regole
# di Trimble (rubocop-sketchup), sui file esattamente come vengono spediti.
#
#   ruby -E UTF-8 tools/controlla_warehouse.rb      (oppure controlla_warehouse.bat)
#
# Crea il pacchetto --warehouse in una cartella temporanea, lo estrae con il
# tar di Windows e ci fa girare rubocop con tools/rubocop_sketchup.yml.
# Esce con 1 se c'è anche una sola segnalazione. Serve la gemma:
#   gem install rubocop -v 1.68.0 --conservative
#   gem install rubocop-sketchup -v "~> 1.4" --conservative
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

ROOT = File.expand_path('..', __dir__)
tar  = File.join(ENV['SystemRoot'] || 'C:/Windows', 'System32', 'tar.exe')
# il lanciatore di RubyGems (bin/rubocop), che sceglie le versioni giuste delle dipendenze
rubocop = File.join(RbConfig::CONFIG['bindir'], 'rubocop')
abort '  [X] rubocop non installato: vedi le istruzioni in testa a questo file' unless File.exist?(rubocop)

Dir.mktmpdir('dagawasd_ew') do |dir|
  out, st = Open3.capture2e(RbConfig.ruby, '-E', 'UTF-8', File.join(ROOT, 'tools', 'crea_rbz.rb'), '--warehouse', dir)
  abort out unless st.success?
  rbz = Dir.glob(File.join(dir, '*-warehouse.rbz')).first
  FileUtils.mkdir_p(File.join(dir, 'src'))
  _, st = Open3.capture2e(tar, '-xf', rbz, '-C', File.join(dir, 'src'))
  abort '  [X] estrazione non riuscita' unless st.success?
  FileUtils.cp(File.join(ROOT, 'tools', 'rubocop_sketchup.yml'), File.join(dir, '.rubocop.yml'))
  # gli avvisi di Ruby sulla gemma (Cop deprecato) non interessano: si tengono solo le righe di rubocop
  out, st = Open3.capture2e(RbConfig.ruby, '-W0', rubocop, '--format', 'emacs', 'src', chdir: dir)
  righe = out.lines.select { |l| l.include?(': C: ') || l.include?(': W: ') || l.include?(': E: ') || l.include?(': F: ') }
  righe.each { |l| puts "  #{l.sub(%r{\A.*?/src/}, '')}" }
  if st.success? && righe.empty?
    puts "  #{File.basename(rbz)}: nessuna segnalazione delle regole SketchUp"
  else
    puts out if righe.empty?
    puts "  #{righe.size} segnalazioni"
    exit 1
  end
end
