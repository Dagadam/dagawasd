# Completezza delle traduzioni (lang/*.json).
#   Esecuzione:  ruby -E UTF-8 tests/test_i18n.rb   (oppure tests\run_tests.bat)
# Controlla che:
#   - ogni file di lingua sia JSON valido e che index.json elenchi solo lingue esistenti;
#   - ogni testo usato dal codice (t('…') in main.rb e lib/*.rb, T('…') e chiavi composte
#     f./grp./sub./tab./keys. nel pannello) esista in en.json;
#   - ogni chiave di en.json esista in tutte le altre lingue e non sia vuota.
require 'json'

ROOT = File.expand_path('..', __dir__)
LANG = File.join(ROOT, 'lang')
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
def read(path); File.read(path, encoding: 'UTF-8'); end

files = Dir[File.join(LANG, '*.json')].map { |f| File.basename(f, '.json') } - ['index']
parsed = {}
bad = files.reject do |c|
  parsed[c] = JSON.parse(read(File.join(LANG, "#{c}.json")))
  true
rescue JSON::ParserError
  false
end
ok(bad.empty?, "tutti i #{files.size} file di lingua sono JSON validi#{bad.empty? ? '' : ": errori in #{bad.join(', ')}"}")

index = JSON.parse(read(File.join(LANG, 'index.json')))['languages'].map { |l| l['code'] }
ok((index - files).empty?, "index.json elenca solo lingue che hanno un file (#{index.size} lingue)")
ok((files - index).empty?, "ogni file di lingua è elencato in index.json#{(files - index).empty? ? '' : ": manca #{(files - index).join(', ')}"}")

en = parsed['en']
rb = ([File.join(ROOT, 'main.rb')] + Dir[File.join(ROOT, 'lib', '*.rb')]).map { |f| read(f) }.join("\n")
ph = read(File.join(ROOT, 'panel.html'))
used  = rb.scan(/\bt\(['"]([\w.]+)['"]\)/).flatten
used += ph.scan(/\bT\(['"]([\w.]+)['"]\)/).flatten
used += ph.scan(/\{k:'(\w+)'/).flatten.map { |k| "f.#{k}" }
used += ph.scan(/\{ id:'(\w+)',[^{\[]*?\bfields:/).flatten.map { |g| "grp.#{g}" }
used += ph.scan(/\{ id:'(\w+)',[^{\[]*?\b(?:groups|special):/).flatten.map { |s| "sub.#{s}" }
used += ph.scan(/\bnote:'([\w.]+)'/).flatten
# scelte tradotte (o.<chiave>.<valore>); quelle in lit: hanno un nome fisso
ph.scan(/\{k:'(\w+)', type:'choice',[^}]*?opts:\[([^\]]*)\]/).each do |k, opts|
  used += opts.scan(/'(\w+)'/).flatten.map { |v| "o.#{k}.#{v}" }
end
used += (1..ph[/HELP_ITEMS = (\d+)/, 1].to_i).map { |i| "help.#{i}" }
used += ph.scan(/^\{ id:'(\w+)', subs/).flatten.map { |t| "tab.#{t}" }
used += ph.scan(/'(keys\.\w+)'/).flatten
used += rb.scan(/'rt\.\w+'/).map { |k| k.delete("'") }            # chiavi passate come argomento (es. drop_grabbed)
used += %w[legno pietra metallo vetro gomma pallone cartone plastica].map { |m| "mat.#{m}" }
# Finestra durante il video (attesa.html): ogni 'att.…' e 'fun.…' fra apici
# (T('att.stop'), battute { k:'fun.…' }, righe delle statistiche, finali)
ah = read(File.join(ROOT, 'attesa.html'))
att = ah.scan(/'((?:att|fun)\.\w+)'/).flatten.uniq
used += att
# Pannello della sfera (keyedit.html, lib/keyedit.rb): ogni 'ke.…' fra apici
kh = read(File.join(ROOT, 'keyedit.html'))
ke = (kh.scan(/'(ke\.[\w.]+)'/).flatten + read(File.join(ROOT, 'lib', 'keyedit.rb')).scan(/t\('(ke\.[\w.]+)'\)/).flatten).uniq
used += ke
used.uniq!
missing_en = used.reject { |k| en.key?(k) }
ok(missing_en.empty?, "i #{used.size} testi usati da codice e pannello esistono in en.json#{missing_en.empty? ? '' : ": mancano #{missing_en.join(', ')}"}")
# attesa.rb manda alla pagina solo att.* e fun.*: in en.json nessuno inutilizzato
morti = en.keys.select { |k| k.start_with?('att.', 'fun.') } - att
ok(morti.empty?, "ogni testo att./fun. di en.json è usato da attesa.html (#{att.size})#{morti.empty? ? '' : ": inutili #{morti.join(', ')}"}")
morti = en.keys.select { |k| k.start_with?('ke.') } - ke
ok(morti.empty?, "ogni testo ke. di en.json è usato dal pannello della sfera (#{ke.size})#{morti.empty? ? '' : ": inutili #{morti.join(', ')}"}")

(files - ['en']).sort.each do |c|
  d = parsed[c] || {}
  miss  = en.keys.reject { |k| d.key?(k) }
  empty = en.keys.select { |k| d.key?(k) && d[k].to_s.strip.empty? }
  next if miss.empty? && empty.empty?
  ok(false, "#{c}: #{miss.size} chiavi mancanti #{miss.first(5).inspect}, #{empty.size} vuote")
end
ok(true, "tutte le #{files.size - 1} lingue hanno le #{en.size} chiavi di en.json") if $fail.zero?

# Lingue da destra a sinistra: un testo tecnico che comincia con un simbolo
# neutro (%APPDATA%\…, #ffd166) viene riordinato e diventa «APPDATA%\…%».
# Va chiuso fra U+2066 (LRI) e U+2069 (PDI), che lo tengono da sinistra a destra.
rtl = JSON.parse(read(File.join(LANG, 'index.json')))['languages'].select { |l| l['rtl'] }.map { |l| l['code'] }
ok(rtl.sort == %w[ar he], "lingue da destra a sinistra: #{rtl.join(', ')}")
rtl.each do |c|
  storti = (parsed[c] || {}).select do |_, v|
    v.is_a?(String) && v.gsub(/%\{\w+\}/, '').gsub(/⁦[^⁩]*⁩/, '') =~ /[%#][A-Za-z]/
  end
  ok(storti.empty?, "#{c}: percorsi e codici isolati da sinistra a destra#{storti.empty? ? '' : ": #{storti.keys.join(', ')}"}")
end

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
