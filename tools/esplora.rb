# DagaWASD — client dell'esploratore autonomo (lib/explore.rb) attraverso il
# ponte per Claude (lib/bridge.rb, GET/POST /explore). Non viene installato in
# SketchUp: lo usa Claude Code dalla riga di comando, come tools/su.rb.
#
#   ruby tools/esplora.rb avvia [--secondi 60] [--velocita 1.4] [--volo | --a-piedi]
#                               [--occhio] [--senza-mappa] [--senza-percorso] [--seme 7]
#                               [--profilo NOME]   (solo per questo giro)
#   ruby tools/esplora.rb ferma
#   ruby tools/esplora.rb pausa | riprendi | altro
#   ruby tools/esplora.rb stato
#   ruby tools/esplora.rb profili
#   ruby tools/esplora.rb profilo NOME   (id o nome: diventa quello in uso, anche dal vivo)
#   ruby tools/esplora.rb segui [--foto CARTELLA] [--secondi N]
#   ruby tools/esplora.rb pilota [--attesa 60] [--subito] [--cose 20] [--json]
#   ruby tools/esplora.rb guida … [--foto] [--foto-sempre | --foto-mete | --senza-foto]
#   ruby tools/esplora.rb guida [--vai ID] [--guarda ID [--per S]] [--punto X,Y,Z]
#                               [--sosta S] [--giro GRADI] [--commento TESTO]
#                               [--sostituisci] [--svuota] [--salta]
#                               [--piace ID=PESO] [--evita ID] [--senza-gusti] [--di TESTO]
#   ruby tools/esplora.rb guida '{"agenda": [{"go": "o12"}], …}'   (il JSON di steer, tale e quale)
#
# segui stampa una riga per ogni scelta dell'esploratore (che cosa guarda,
# quanto spicca, a che distanza) finché si ferma; con --foto salva anche
# un'immagine della vista a ogni nuovo obiettivo (GET /image), così Claude
# può guardare quello che l'esploratore ha scelto di guardare.
#
# pilota e guida servono all'IA che guida l'esploratore (lib/expilot.rb).
# pilota aspetta un avviso (arrivato, fatto, agenda quasi vuota, una cosa
# notevole mai vista; al più --attesa s) e stampa che cosa vede e sa:
# le cose con un nome corto (o12 oggetto, s7 faccia, F3 zona inesplorata),
# il lato rispetto allo sguardo (+ sinistra, − destra), la distanza; e il
# percorso dell'ultima foto (fatta in una sosta, coi nomi corti scritti
# accanto alle cose visibili). L'attesa la fa il ponte (GET /explore/wait).
# Ricorda l'ultimo avviso letto in %APPDATA%\DagaWASD\pilota.json.
# guida mette in agenda (in coda; --sostituisci la rifà): --vai, --guarda e
# --punto (in metri) sono voci, nell'ordine; --sosta, --giro, --commento,
# --per valgono per la voce prima. --piace o12=2 (anche label:testo=2,
# frontier=2, open=0.5), --evita o3, --di "testo" (un commento ora).
#
# Legge porta e token da %APPDATA%\DagaWASD\bridge.json, scritto da
# SketchUp quando il ponte è acceso (Sistema › Ponte Claude).
# Esce con 0 se tutto è andato bene, 1 per un errore, 2 per un uso sbagliato.
require 'json'
require 'net/http'
require 'fileutils'

def die(msg, code = 1)
  warn "esplora.rb: #{msg}"
  exit code
end

info_path = File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'bridge.json')
die("#{info_path} non esiste: accendi il ponte in DagaWASD (Sistema › Ponte Claude)") unless File.exist?(info_path)
INFO = (JSON.parse(File.read(info_path, encoding: 'UTF-8')) rescue die("#{info_path} illeggibile"))

def request(req, timeout = 120)
  req['X-Token'] = INFO['token']
  Net::HTTP.start('127.0.0.1', INFO['port'], open_timeout: 3, read_timeout: timeout) { |h| h.request(req) }
rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout
  die("SketchUp non risponde sulla porta #{INFO['port']}: è aperto, col ponte acceso?")
end

def json_of(res)
  body = JSON.parse(res.body.force_encoding('UTF-8')) rescue nil
  die("risposta inattesa (#{res.code}): #{res.body.to_s[0, 200]}") unless body.is_a?(Hash)
  die(body['error']) if res.code != '200' || body['ok'] == false
  body
end

def stato; json_of(request(Net::HTTP::Get.new('/explore'))); end

def comando(cmd, opts = nil)
  req = Net::HTTP::Post.new('/explore')
  req['Content-Type'] = 'application/json'
  req.body = JSON.generate(opts.nil? ? { 'cmd' => cmd } : { 'cmd' => cmd, 'opts' => opts })
  json_of(request(req))
end

# --nome → true se c'è (e lo toglie da ARGV); valore(--nome) → il valore che segue
def flag(nome); !ARGV.delete(nome).nil?; end

PILOTA = File.join(File.dirname(info_path), 'pilota.json')

def pilota_stato
  JSON.parse(File.read(PILOTA, encoding: 'UTF-8'))
rescue StandardError
  {}
end

def percezione(since, n = nil)
  json_of(request(Net::HTTP::Get.new("/explore/percept?since=#{since.to_i}#{n ? "&n=#{n.to_i}" : ''}")))
end

# Il ponte risponde quando c'è un avviso che sveglia (o allo scadere)
def attendi(since, run, secs, n = nil)
  q = "since=#{since.to_i}&timeout=#{secs}&run=#{run}#{n ? "&n=#{n.to_i}" : ''}"
  json_of(request(Net::HTTP::Get.new("/explore/wait?#{q}"), secs + 30))
end

def lato(g) = g.zero? ? '0°' : format('%+d°', g)

# reach della descrizione: ci si arriva a piedi?
def a_piedi(c)
  case c['reach']
  when 'yes' then "a piedi #{c['walk_m']} m"
  when 'unknown' then c['walk_m'] ? "a piedi forse #{c['walk_m']} m" : 'a piedi forse'
  when 'no' then 'a piedi non si arriva'
  end
end

def stampa_percezione(p)
  m = p['mode'] == 'fly' ? 'in volo' : 'a piedi'
  puts "esploratore #{p['paused'] ? 'in pausa' : 'attivo'}, #{m}, #{p['seconds']} s — posizione #{p['pos_m'].join(', ')} m, " \
       "sguardo #{p['yaw_deg']}° (in su #{p['pitch_deg']}°)"
  t = p['target']
  if t
    chi = t['by'] == 'ai' ? "dato dall'IA" : 'scelto da solo'
    puts "obiettivo: #{t['id'] || '-'} «#{t['label']}» lato #{lato(t['bearing_deg'])}, #{t['dist_m']} m, #{chi}" \
         "#{t['arrived'] ? ', arrivato' : ''}#{t['visible'] == false ? ', nascosto' : ''}"
  else
    puts "obiettivo: nessuno#{p['looking_around'] ? ' (si guarda intorno)' : ''}"
  end
  if (f = p['photo'])
    puts "foto (#{f['t']} s, di #{f['id'] || '-'}#{f['id_visible'] ? '' : ', che da qui non si vede'}): #{f['path']}"
    puts "  segni: #{f['marks'].map { |m| m['id'] }.join(' ')}" unless f['marks'].empty?
  end
  puts "foto in arrivo alla sosta" if p['photo_pending']
  if p['agenda'].empty?
    puts 'agenda: vuota (sceglie da solo)'
  else
    puts 'agenda:'
    p['agenda'].each_with_index do |a, i|
      extra = [a['dwell'] && "sosta #{a['dwell']} s", a['orbit'] && "giro #{a['orbit']}°", a['say'] && "«#{a['say']}»"].compact
      cosa = a['label'] ? "#{a['id']} «#{a['label']}»" : (a['to_m'] ? "punto #{a['to_m'].join(', ')}" : a['id'])
      puts "  #{i + 1}. #{a['act'] == 'look' ? 'guarda' : 'vai a'} #{cosa} [#{a['state']}]" \
           "#{extra.empty? ? '' : " — #{extra.join(', ')}"}"
    end
  end
  puts "gusti: #{p['likes'].map { |k, v| "#{k} ×#{v}" }.join(', ')}" unless p['likes'].empty?
  unless p['events'].empty?
    puts 'avvisi:'
    p['events'].each do |e|
      dati = e.reject { |k, _| %w[n t type].include?(k) }.map { |k, v| "#{k}=#{v}" }.join(' ')
      puts format('  #%-4d %6.1f s  %-13s %s', e['n'], e['t'], e['type'], dati).rstrip
    end
  end
  puts "cose (#{p['counts']['known']} viste, #{p['counts']['reached']} raggiunte; in vista prima; lato + sinistra, − destra):"
  p['things'].each do |c|
    segni = [c['in_view'] ? 'in vista' : "vista #{c['seen_s_ago']} s fa", c['reached'] ? 'raggiunta' : nil,
             a_piedi(c), c['liked'] ? "gusto ×#{c['liked']}" : nil].compact.join(', ')
    puts format('  %-5s %-24s %-7s lato %5s  in su %4s  %6.1f m  %s  salienza %.2f  %s', c['id'], c['label'].to_s[0, 24],
                c['kind'] == 'object' ? 'oggetto' : 'faccia', lato(c['bearing_deg']), lato(c['elev_deg']), c['dist_m'],
                c['size_m'] ? format('grande %4.1f m', c['size_m']) : ' ' * 13, c['salience'], segni).rstrip
  end
  return if p['frontiers'].empty?
  puts 'zone inesplorate:'
  p['frontiers'].each do |f|
    puts format('  %-5s lato %5s  %6.1f m  larga %.1f m  ignota %d%%  %s', f['id'], lato(f['bearing_deg']), f['dist_m'],
                f['width_m'], (f['unknown'] * 100).round, a_piedi(f)).rstrip
  end
end

# guida: le opzioni nell'ordine in cui sono scritte
def opzioni_guida(args)
  o = {}
  voci = []
  ultima = ->(nome) { voci.last || die("#{nome} vale per la voce prima: metti prima --vai, --guarda o --punto", 2) }
  num = lambda do |nome, v|
    Float(v || die("#{nome} senza valore", 2))
  rescue ArgumentError
    die("#{nome}: #{v.inspect} non è un numero", 2)
  end
  until args.empty?
    a = args.shift
    v = -> { args.shift || die("#{a} senza valore", 2) }
    case a
    when '--vai' then voci << { 'go' => v.() }
    when '--guarda' then voci << { 'look' => v.() }
    when '--punto'
      xyz = v.().split(',').map { |x| num.('--punto', x) }
      die('--punto: attesi tre numeri, X,Y,Z in metri', 2) unless xyz.size == 3
      voci << { 'to' => xyz }
    when '--sosta' then ultima.(a)['dwell'] = num.(a, args.shift)
    when '--per' then ultima.(a)['for'] = num.(a, args.shift)
    when '--giro' then ultima.(a)['orbit'] = num.(a, args.shift)
    when '--commento' then ultima.(a)['say'] = v.()
    when '--sostituisci' then o['agenda'] = []
    when '--svuota' then o['clear'] = true
    when '--salta' then o['skip'] = true
    when '--senza-gusti' then o['likes_clear'] = true
    when '--piace'
      k, peso = v.().split('=', 2)
      (o['like'] ||= {})[k] = num.('--piace', peso)
    when '--evita' then (o['avoid'] ||= []) << v.()
    when '--di' then o['say'] = v.()
    when '--foto' then o['photo'] = true
    when '--foto-sempre' then o['photos'] = 'all'
    when '--foto-mete' then o['photos'] = 'ai'
    when '--senza-foto' then o['photos'] = 'off'
    else die("opzione sconosciuta: #{a}", 2)
    end
  end
  if o.key?('agenda') then o['agenda'] = voci
  elsif !voci.empty? then o['add'] = voci
  end
  o
end

def valore(nome)
  i = ARGV.index(nome) or return nil
  v = ARGV[i + 1] or die("#{nome} senza valore", 2)
  ARGV.slice!(i, 2)
  v
end

def numero(nome)
  v = valore(nome) or return nil
  Float(v)
rescue ArgumentError
  die("#{nome}: #{v.inspect} non è un numero", 2)
end

def riga(e)
  dove = e['dist_m'] ? format('a %5.1f m', e['dist_m']) : ''
  sal = e['score'] ? format('salienza %.2f', e['score']) : ''
  format('%7.1f s  %-16s %-24s %-15s %s', e['t'], e['why'], e['label'].to_s[0, 24], sal, dove).rstrip
end

def riassunto(s)
  return 'esploratore fermo' unless s['on']
  t = s['target']
  cosa = t ? "guarda «#{t['label']}» (#{t['score']}) a #{t['dist_m']} m" : 'si guarda intorno'
  prof = s['profile'] ? "profilo #{s['profile']['name']}, " : ''
  "esploratore #{s['paused'] ? 'in pausa' : 'attivo'} (#{prof}#{s['mode'] == 'fly' ? 'in volo' : 'a piedi'}, #{s['speed']} m/s): " \
    "#{cosa} — #{s['steps']} analisi in #{s['seconds']} s" +
    (s['scan']['grid'] ? ", retina #{s['scan']['grid'].join('×')} in #{s['scan']['ms']} ms su #{s['scan']['goal_ms']}" : '') +
    (s['scan']['frame_ms'] ? " (fotogramma #{s['scan']['frame_ms']} ms + #{s['scan']['slice_ms']} di calcolo)" : '')
end

cmd = ARGV.shift
case cmd
when 'avvia'
  o = {}
  (v = numero('--secondi')) && o['duration'] = v
  (v = numero('--velocita')) && o['speed'] = v
  (v = numero('--seme')) && o['seed'] = v.round
  (v = valore('--profilo')) && o['profile'] = v
  o['mode'] = 'fly' if flag('--volo')
  o['mode'] = 'walk' if flag('--a-piedi')
  o['pixels'] = true if flag('--occhio')
  o['heatmap'] = false if flag('--senza-mappa')
  o['record'] = false if flag('--senza-percorso')
  die("opzioni sconosciute: #{ARGV.join(' ')}", 2) unless ARGV.empty?
  puts riassunto(comando('start', o))

when 'ferma'
  r = comando('stop')
  last = r['last'] || {}
  puts "fermato dopo #{last['seconds']} s e #{last['steps']} analisi (obiettivi visti: #{last['visited']})" +
       (r['path'] ? "; percorso salvato nel modello: «#{r['path']}»" : '')

when 'pausa', 'riprendi', 'altro'
  puts riassunto(comando({ 'pausa' => 'pause', 'riprendi' => 'resume', 'altro' => 'next' }[cmd]))

when 'stato'
  puts JSON.pretty_generate(stato)

when 'profili'
  r = comando('profiles')
  r['profiles'].each do |p|
    segni = [p['id'] == r['active'] ? 'in uso' : nil, p['builtin'] ? nil : 'tuo', p['modified'] ? 'modificato' : nil].compact
    puts format('%s %-14s %-24s %s', p['id'] == r['active'] ? '*' : ' ', p['id'], p['name'], segni.empty? ? '' : "(#{segni.join(', ')})").rstrip
  end

when 'profilo'
  nome = ARGV.join(' ').strip
  die('profilo senza nome: usa «profili» per l\'elenco', 2) if nome.empty?
  r = comando('profile', nome)
  puts "profilo in uso: #{r['active']}" + (r['on'] ? " — #{riassunto(r)}" : '')

when 'segui'
  dir = valore('--foto')
  secs = numero('--secondi')
  die("opzioni sconosciute: #{ARGV.join(' ')}", 2) unless ARGV.empty?
  FileUtils.mkdir_p(dir) if dir
  visto = 0
  t0 = Time.now
  loop do
    s = stato
    unless s['on']
      puts 'esploratore fermo'
      break
    end
    (s['log'] || []).each do |e|
      next if e['n'] <= visto
      visto = e['n']
      puts riga(e)
      next unless dir && e['why'] == 'nuovo'
      nome = e['label'].to_s.gsub(/[^\p{L}\p{N}_-]+/, '_')[0, 40]
      file = File.join(dir, format('%04d_%s.png', e['n'], nome))
      res = request(Net::HTTP::Get.new('/image?w=800&h=450'))
      File.binwrite(file, res.body) if res.code == '200'
    end
    $stdout.flush
    break if secs && Time.now - t0 >= secs
    sleep 0.4
  end

when 'pilota'
  attesa = numero('--attesa') || 60.0
  n = numero('--cose')
  subito = flag('--subito')
  grezzo = flag('--json')
  die("opzioni sconosciute: #{ARGV.join(' ')}", 2) unless ARGV.empty?
  st = pilota_stato
  # un giro nuovo (run diverso) risponde subito, con gli avvisi da 1
  p = subito ? percezione(st['ev_n'].to_i, n) : attendi(st['ev_n'].to_i, st['run'], attesa.round, n)
  unless p['on']
    puts 'esploratore fermo' + (p['last'] ? " (ultimo giro: #{p['last']['seconds']} s, #{p['last']['steps']} analisi)" : '')
    exit 0
  end
  p = percezione(0, n) if subito && p['run'] != st['run']
  File.write(PILOTA, JSON.generate('run' => p['run'], 'ev_n' => p['ev_n']))
  if grezzo
    puts JSON.pretty_generate(p)
  else
    puts "(nessun avviso in #{attesa.round} s)" if p['timeout']
    stampa_percezione(p)
  end

when 'guida'
  o = if ARGV.first.to_s.start_with?('{')
        begin
          JSON.parse(ARGV.join(' '))
        rescue JSON::ParserError => e
          die("JSON non valido: #{e.message[0, 120]}", 2)
        end
      else
        opzioni_guida(ARGV.dup)
      end
  die('niente da fare: usa --vai, --guarda, --punto, --piace, --di…', 2) if o.empty?
  r = comando('steer', o)
  r['rejected'].each { |x| warn "rifiutato: #{x['item'].is_a?(String) ? x['item'] : JSON.generate(x['item'])} — #{x['why']}" }
  if r['agenda'].empty?
    puts 'agenda: vuota (sceglie da solo)'
  else
    puts "agenda: #{r['agenda'].map { |a| "#{a['act']} #{a['label'] || a['id']}#{a['state'] == 'waiting' ? '' : " [#{a['state']}]"}" }.join(' → ')}"
  end
  puts "gusti: #{r['likes'].map { |k, v| "#{k} ×#{v}" }.join(', ')}" unless r['likes'].empty?
  puts "foto: #{r['photos']}#{r['photo_pending'] ? ', una in arrivo alla sosta' : ''}"
  exit(r['rejected'].empty? ? 0 : 1)

else
  die("comando sconosciuto: #{cmd.inspect} — usa avvia, ferma, pausa, riprendi, altro, stato, segui, profili, profilo, pilota o guida", 2)
end
