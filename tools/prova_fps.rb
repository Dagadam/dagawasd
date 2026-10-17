# DagaWASD — Prova di gioco in modalità FPS con tasti simulati
# (tools/finestre.ps1 tasti): entra con Ctrl+PagSu, registra un percorso (R)
# mentre cammina e poi corre, esce con Esc. Dalla registrazione (la camera
# vera, 30 campioni al secondo, dondolio compreso) misura l'oscillazione
# della testa camminando e correndo.
#
#   ruby -E UTF-8 tools/prova_fps.rb [scena] [secondi_camminata] [secondi_corsa]
#
# Default: la camera attuale (meglio davanti a un tratto lungo, dritto e
# libero), 3 s di camminata, 4 s di corsa. Mentre gira tastiera e mouse
# vanno a SketchUp: non toccare nulla (se il primo piano passa ad altro i
# tasti si rilasciano e la prova si ferma). Alla fine la camera torna dov'era
# e il percorso registrato si toglie; le mosse della fisica, se ha urtato
# qualcosa, restano nella cronologia di annullamento.
$stdout.sync = true   # i risultati si vedono subito anche in una pipe
require 'json'
require 'net/http'
require 'open3'

ROOT  = File.expand_path('..', __dir__)
FIN   = File.join(ROOT, 'tools', 'finestre.ps1')
INFO  = File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'bridge.json')
SCENA = ARGV[0].to_s
CAMM  = (ARGV[1] || 3).to_f
CORSA = (ARGV[2] || 4).to_f

def su(code)
  info = JSON.parse(File.read(INFO, encoding: 'UTF-8'))
  req = Net::HTTP::Post.new('/eval')
  req['X-Token'] = info['token']
  req['Content-Type'] = 'text/plain; charset=utf-8'
  req.body = "require 'json'\n__r = begin\n#{code}\nend\nprint JSON.generate([__r])"
  res = Net::HTTP.start('127.0.0.1', info['port'], open_timeout: 3, read_timeout: 600) { |h| h.request(req) }
  d = JSON.parse(res.body.force_encoding('UTF-8'))
  raise "ponte: #{d['error']}" unless d['ok']
  JSON.parse(d['output'])[0]
end

def fin(*args)
  out, st = Open3.capture2e('powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', FIN, *args.map(&:to_s))
  [st.success?, out.force_encoding('UTF-8').strip]
end

abort 'Il ponte è spento: accendilo in DagaWASD (Sistema › Ponte Claude)' unless File.exist?(INFO)
# I tasti passano da tools/finestre.ps1: serve il permesso del pannello
IMP = (JSON.parse(File.read(File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'settings.json'), encoding: 'UTF-8')) rescue {})
abort 'Finestre e tasti spenti: accendili in DagaWASD (Sistema › Ponte Claude › Finestre e tasti)' unless IMP['bridge_windows']
stato = su(<<~'RUBY')
  m = DagaWASD::FPSWalk
  c = Sketchup.active_model.active_view.camera
  $dagawasd_prova = [c.eye, c.target, c.up, c.perspective?, c.fov]
  { 'fps' => !!m.instance_variable_get(:@active), 'job' => m.path_busy?,
    'percorsi' => m.path_list.map { |p| p['name'] }, 'scene' => Sketchup.active_model.pages.map(&:name),
    'bob' => (m::BOB_Z_MAX rescue nil), 'amp' => m.cf('head_bob_amp'), 'v' => m.cf('move_speed'), 'corsa' => m.cf('sprint_multiplier') }
RUBY
abort 'Modalità FPS già attiva: esci prima (Esc)' if stato['fps']
abort 'Un percorso è in riproduzione o in esportazione' if stato['job']
if stato['scene'].include?(SCENA)
  su("Sketchup.active_model.active_view.camera = Sketchup.active_model.pages[#{SCENA.inspect}].camera; nil")
  puts "Partenza: scena «#{SCENA}»"
else
  puts 'Partenza: camera attuale'
end
puts "Head bob del pannello #{stato['amp']} m, velocità #{stato['v']} m/s, corsa ×#{stato['corsa']}; " \
     "tetto installato: #{stato['bob'] ? "#{stato['bob']} m" : 'nessuno (versione senza il tetto)'}"

nuovo = nil
begin
  passi = ['tieni:ctrl+pagsu:250', 'aspetta:1500',            # entra in FPS e si assesta
           'tieni:r:150', 'aspetta:300',                      # registra
           "tieni:w:#{(CAMM * 1000).round}",                  # cammina
           "tieni:w+shift:#{(CORSA * 1000).round}",           # corre
           'aspetta:400', 'tieni:r:150', 'aspetta:300',       # ferma la registrazione
           'tieni:esc:150', 'aspetta:500']                    # esce
  ok, out = fin('tasti', *passi)
  puts out
  abort 'Prova interrotta.' unless ok
  sleep 1
  nuovo = (su('DagaWASD::FPSWalk.path_list.map { |p| p["name"] }') - stato['percorsi']).first
  abort 'Nessun percorso registrato: R non è arrivato?' unless nuovo
  s = su("DagaWASD::FPSWalk.path_data(#{nuovo.inspect})['s']")

  require 'tmpdir'
  File.write(File.join(Dir.tmpdir, 'dagawasd_prova_fps.json'), JSON.generate(s))   # per guardarci dentro

  # Un campione per passo di FPS: tanti al secondo quanti i fotogrammi, e su
  # un modello pesante sono pochi. Tutto va fatto sul tempo, non sui campioni.
  pt = s.map { |r| [r[0].to_f, r[1].to_f * 0.0254, r[2].to_f * 0.0254, r[3].to_f * 0.0254] }
  fps = (pt.size - 1) / (pt.last[0] - pt.first[0])
  vicini = ->(i, mezzo) { pt.each_index.select { |j| (pt[j][0] - pt[i][0]).abs <= mezzo } }
  # velocità orizzontale su ±0,15 s
  vel = pt.each_index.map do |i|
    w = vicini.(i, 0.15); a = pt[w.first]; b = pt[w.last]
    b[0] > a[0] ? Math.hypot(b[1] - a[1], b[2] - a[2]) / (b[0] - a[0]) : 0.0
  end
  # Quota meno la retta che meglio la segue nel tratto: resta il dondolio,
  # le pendenze no. Non una media mobile: con pochi campioni per oscillazione
  # la media non sta al centro e gonfia l'ampiezza (±5,6 misurati, ±4,5 veri).
  dondolio = lambda do |idx|
    t = idx.map { |i| pt[i][0] }; z = idx.map { |i| pt[i][3] }
    tm = t.sum / t.size; zm = z.sum / z.size
    den = t.sum { |x| (x - tm)**2 }
    b = den > 0 ? t.zip(z).sum { |x, y| (x - tm) * (y - zm) } / den : 0.0
    t.zip(z).map { |x, y| y - (zm + b * (x - tm)) }
  end
  puts format('FPS a %.1f fotogrammi al secondo (%d campioni in %.1f s)', fps, pt.size, pt.last[0])
  passo = stato['v'].to_f
  [['camminata', ->(v) { v > passo * 0.6 && v < passo * 1.3 }],
   ['corsa',     ->(v) { v > passo * 1.5 }]].each do |nome, sel|
    # solo i tratti a velocità piena, lontani 0,3 s da partenze e cambi di passo
    idx = pt.each_index.select { |i| vicini.(i, 0.3).all? { |j| sel.(vel[j]) } }
    next puts("#{nome}: nessun tratto a velocità costante (ostacolo davanti?)") if idx.size < 4
    d = dondolio.(idx)
    v = idx.sum { |i| vel[i] } / idx.size
    puts format('%-9s %4.1f m/s per %.1f s: la testa va da %+.1f a %+.1f cm (±%.1f)',
                nome, v, pt[idx.last][0] - pt[idx.first][0], d.min * 100, d.max * 100, (d.max - d.min) * 50)
  end
ensure
  su(<<~RUBY) rescue nil
    m = DagaWASD::FPSWalk
    m.stop if m.instance_variable_get(:@active)
    n = #{nuovo.inspect}
    if n && (d = m.path_dict) && d[n]
      d.delete_key(n)
      Sketchup.active_model.attribute_dictionaries.delete(d) if d.keys.empty?
      m.path_push
    end
    eye, target, up, persp, fov = $dagawasd_prova
    Sketchup.active_model.active_view.camera = Sketchup::Camera.new(eye, target, up, persp, fov)
    nil
  RUBY
end
