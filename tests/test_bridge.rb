# Ponte per Claude (lib/bridge.rb): server vero su 127.0.0.1, SketchUp finto.
#   Esecuzione:  ruby -E UTF-8 tests/test_bridge.rb   (oppure tests\run_tests.bat)
# Il timer di SketchUp qui non esiste: il test chiama bridge_poll a mano
# mentre un thread fa da client, come farebbe tools/su.rb.
$LOAD_PATH.unshift(File.join(__dir__, 'support'))
load File.expand_path('../main.rb', __dir__)
require 'net/http'
require 'tmpdir'
F = DagaWASD::FPSWalk
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end

tmp = Dir.mktmpdir('dagawasd_bridge')
info_file = File.join(tmp, 'sub', 'bridge.json')
F.instance_variable_set(:@bridge_file, info_file)
F.instance_variable_set(:@log_file, File.join(tmp, 'test.log'))
F.instance_variable_set(:@log_quiet, true)
F.load_cfg
cfg = F.instance_variable_get(:@cfg)

ok(F::DEFAULT['bridge_enabled'] == false, 'il ponte è spento di default')
F.bridge_sync
ok(!F.bridge_status['on'] && !File.exist?(info_file), 'spento: nessun server e nessun file di connessione')

cfg['bridge_enabled'] = true
F.bridge_sync
st = F.bridge_status
ok(st['on'] && F::BRIDGE_PORTS.cover?(st['port']), "acceso sulla porta #{st['port']}")
info = File.exist?(info_file) ? JSON.parse(File.read(info_file)) : {}
ok(info['port'] == st['port'] && info['token'].to_s.size == 48, 'file di connessione con porta e token')

# Una richiesta HTTP servita da bridge_poll: il client gira in un thread.
def call(info, req, token: info['token'], origin: nil)
  req['X-Token'] = token if token
  req['Origin'] = origin if origin
  res = nil
  th = Thread.new do
    res = Net::HTTP.start('127.0.0.1', info['port'], read_timeout: 10) { |h| h.request(req) }
  end
  deadline = Time.now + 10
  while th.alive? && Time.now < deadline
    F.bridge_poll
    sleep 0.01
  end
  th.join(1)
  res
end
def post(code, op = nil)
  r = Net::HTTP::Post.new('/eval' + (op ? "?op=#{op}" : ''))
  r.body = code
  r
end
body = ->(r) { JSON.parse(r.body.force_encoding('UTF-8')) }

r = call(info, Net::HTTP::Get.new('/ping'))
ok(r && r.code == '200' && body[r]['ok'] && body[r]['sketchup'] == '26.0.0', 'ping con il token giusto')
r = call(info, Net::HTTP::Get.new('/ping'), token: 'x' * 48)
ok(r && r.code == '403', 'token sbagliato: rifiutato (403)')
r = call(info, Net::HTTP::Get.new('/ping'), token: nil)
ok(r && r.code == '403', 'senza token: rifiutato (403)')
r = call(info, Net::HTTP::Get.new('/ping'), origin: 'https://example.com')
ok(r && r.code == '403' && body[r]['error'].include?('browser'), 'richiesta da una pagina web (Origin): rifiutata')
r = call(info, Net::HTTP::Get.new('/nulla'))
ok(r && r.code == '404', 'percorso sconosciuto: 404')

$stub_ops = []
r = call(info, post("puts 'ciao'\n@n = 20 + 1\n[model.class.name, @n]", 'Tavolo'))
b = body[r]
ok(b['ok'] && b['result'] == '["Sketchup::Model", 21]' && b['output'] == "ciao\n", "eval: risultato e output (#{b['result']})")
ok($stub_ops == %i[start commit], 'eval riuscito: una sola operazione, confermata')
r = call(info, post('@n * 2'))
ok(body[r]['result'] == '42', 'le variabili @ restano fra una chiamata e l\'altra')

$stub_ops = []
r = call(info, post("puts 'prima'\nraise ArgumentError, 'rotto'"))
b = body[r]
ok(!b['ok'] && b['error'] == 'ArgumentError: rotto' && b['undone'] && b['output'] == "prima\n",
   'errore: messaggio, output fino all\'errore, operazione annullata')
ok($stub_ops == %i[start abort], 'errore: l\'operazione viene annullata per intero')
ok(b['backtrace'].any? { |l| l.start_with?('claude:2') }, 'errore: riga del codice inviato nel backtrace')
r = call(info, post('def x('))
ok(!body[r]['ok'] && body[r]['error'].start_with?('SyntaxError'), 'errore di sintassi segnalato, SketchUp non si ferma')
ok($stdout == STDOUT, '$stdout ripristinato dopo gli errori')

big = "s = <<~T\n#{'x' * 300_000}\nT\ns.size"
r = call(info, post(big))
ok(body[r]['result'] == '300001', 'corpo grande (300 kB) ricevuto per intero')

F.instance_variable_set(:@active, true)
r = call(info, post('1'))
ok(!body[r]['ok'] && body[r]['error'].include?('FPS'), 'con la modalità FPS attiva il codice non viene eseguito')
F.instance_variable_set(:@active, false)

# ── Costruzione dal vivo ─────────────────────────────────────────
# I timer di SketchUp qui sono finti: si raccolgono i blocchi e il test li
# esegue (con timers: true) mentre aspetta la risposta.
module UI
  def self.start_timer(_d = 0, _r = false, &b); ($timers ||= []) << b if b; 1; end
end
def call_live(info, req, timers: true)
  req['X-Token'] = info['token']
  res = nil
  th = Thread.new { res = Net::HTTP.start('127.0.0.1', info['port'], read_timeout: 10) { |h| h.request(req) } }
  deadline = Time.now + 10
  while th.alive? && Time.now < deadline
    F.bridge_poll
    ($timers ||= []).shift&.call if timers
    sleep 0.01
  end
  th.join(1)
  res
end

r = call(info, post("step 'non fa nulla'\n5"))
ok(body[r]['result'] == '5' && !body[r].key?('steps'), 'senza costruzione dal vivo step non fa nulla')

cfg['bridge_live'] = true
$stub_ops = []; $timers = []
code = "puts 'via'\n@pezzi = []\n3.times { |i| @pezzi << i; step \"pezzo \#{i}\" }\n@pezzi.size"
r = call_live(info, post(code, 'Dal vivo'))
b = body[r]
ok(b['ok'] && b['result'] == '3' && b['steps'] == 3 && b['output'] == "via\n", "dal vivo: 3 passi, risultato e output (#{b['steps']} passi)")
ok($stub_ops == %i[start commit], 'dal vivo: una sola operazione, confermata alla fine')
ok(F.instance_variable_get(:@bridge_job).nil?, 'lavoro concluso: nessuna costruzione in sospeso')

# livelli di dettaglio: step "x", n si vede solo dal livello n in su
lv_code = "step 'spigolo', 3\nstep 'faccia', 2\nstep 'solido'\ndetail"
{ 'solids' => [1, '1'], 'ops' => [2, '2'], 'anim' => [3, '3'] }.each do |d, (steps, res)|
  cfg['bridge_detail'] = d; $timers = []
  b = body[call_live(info, post(lv_code))]
  ok(b['steps'] == steps && b['result'] == res, "dettaglio #{d}: #{b['steps']} passi, detail = #{b['result']}")
end
cfg['bridge_detail'] = 'solids'
r = call(info, Net::HTTP::Get.new('/ping'))
ok(F.bridge_detail == 1, 'fuori da una costruzione dal vivo detail vale 1')

# Dolly rotante: spento di default, geometria dell'inquadratura
ok(F::DEFAULT['bridge_orbit'] == false, 'dolly rotante spento di default')
bb = Geom::BoundingBox.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 200, 50))
c, rad, hgt, = F.orbit_goal(bb, 35.0)
dist = Math.hypot(rad, hgt)
ok([c.x, c.y, c.z] == [50.0, 100.0, 25.0], 'orbita centrata sull\'ingombro di ciò che si costruisce')
ok(dist > bb.diagonal / 2 && (Math.atan2(hgt, rad) / F::DEG - 25.0).abs < 1e-9,
   "camera fuori dall'oggetto (#{dist.round} > #{(bb.diagonal / 2).round}), 25° sopra l'orizzonte")
tiny = Geom::BoundingBox.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 1, 1))
ok((Math.hypot(*F.orbit_goal(tiny, 35.0)[1, 2]) - F::ORBIT_MIN_DIST).abs < 1e-9, 'oggetto minuscolo: distanza minima')
e = F.orbit_eye(c, rad, hgt, Math::PI / 2)
ok((e.x - 50.0).abs < 1e-9 && (e.y - (100.0 + rad)).abs < 1e-9 && e.z == 25.0 + hgt, 'punto dell\'orbita a 90°')
ok(F.orbit_start(nil).nil? && F.instance_variable_get(:@orbit).nil?, 'con il dolly spento non parte nessuna orbita')

# Dolly mentre il codice lavora senza step: la camera gira lo stesso,
# perché i fotogrammi li dà il TracePoint e non il timer (qui finto).
module Geom
  def self.linear_combination(a, p, b, q); Point3d.new(a * p.x + b * q.x, a * p.y + b * q.y, a * p.z + b * q.z); end
end
module Sketchup
  class Camera
    attr_reader :eye, :target
    def initialize; @eye = Geom::Point3d.new(-500, -500, 300); @target = Geom::Point3d.new; end
    def perspective?; true; end
    def fov; 35.0; end
    def set(eye, target, _up); @eye = eye; @target = target; end
  end
  class View
    def camera; $cam ||= Camera.new; end
    def refresh; ($refreshes ||= []) << camera.eye.to_a; end
  end
  class Model; def active_entities; []; end; end
end
cfg['bridge_live'] = true; cfg['bridge_orbit'] = true
$timers = []; $refreshes = []
busy = "t = Process.clock_gettime(Process::CLOCK_MONOTONIC)\n" \
       "nil while Process.clock_gettime(Process::CLOCK_MONOTONIC) - t < 0.5\nstep 'fine'\n:ok"
b = body[call_live(info, post(busy))]
ok(b['ok'] && $refreshes.size >= 5 && $refreshes.uniq.size == $refreshes.size,
   "dolly: la camera gira anche mentre il codice lavora (#{$refreshes.size} fotogrammi in 0,5 s)")
ok(F.instance_variable_get(:@orbit).nil?, 'dolly: a fine lavoro l\'orbita si ferma')
n = $refreshes.size
F.bridge_step('fuori', 1)
ok($refreshes.size == n, 'dolly: fuori dal lavoro nessun fotogramma')
cfg['bridge_orbit'] = false   # bridge_live resta acceso per le prove che seguono

$stub_ops = []; $timers = []
r = call_live(info, post("step 'primo'\nraise 'crollato'"))
b = body[r]
ok(!b['ok'] && b['error'] == 'RuntimeError: crollato' && b['undone'] && b['steps'] == 1,
   'dal vivo: errore dopo un passo → operazione annullata per intero')
ok($stub_ops == %i[start abort], 'dal vivo: annullata, non confermata')

# mentre costruisce: un secondo invio viene rifiutato, ping risponde, la camminata non parte
$timers = []
first = nil
th1 = Thread.new do
  rq = post("step 'a'\n1"); rq['X-Token'] = info['token']
  first = Net::HTTP.start('127.0.0.1', info['port'], read_timeout: 10) { |h| h.request(rq) }
end
10.times { F.bridge_poll; sleep 0.02 }
ok(!F.instance_variable_get(:@bridge_job).nil?, 'costruzione in pausa fra due passi')
r = call_live(info, post('2'), timers: false)
ok(r && r.code == '409', 'un secondo invio durante la costruzione viene rifiutato (409)')
r = call_live(info, Net::HTTP::Get.new('/ping'), timers: false)
ok(r && r.code == '200', 'durante la costruzione il ping risponde')
F.start
ok(!F.instance_variable_get(:@active), 'durante la costruzione la camminata FPS non parte')
$timers.shift&.call while $timers.any?
10.times { F.bridge_poll; sleep 0.02 }
th1.join(2)
ok(first && body[first]['result'] == '1', 'la costruzione in pausa poi finisce e risponde')
cfg['bridge_live'] = false

# un file di impostazioni ricevuto da altri non può accendere il ponte
cfg['bridge_enabled'] = false
F.import_values('settings' => { 'bridge_enabled' => true })
ok(cfg['bridge_enabled'] == false, 'bridge_enabled non viene importato')

cfg['bridge_enabled'] = false
F.bridge_sync
ok(!F.bridge_status['on'] && !File.exist?(info_file), 'spento: server chiuso e file di connessione cancellato')
refused = begin
  Net::HTTP.start('127.0.0.1', info['port'], open_timeout: 1) { |h| h.get('/ping') }
  false
rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout
  true
end
ok(refused, 'dopo lo spegnimento la porta non risponde più')

puts "\n#{$fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"}"
exit($fail.zero? ? 0 : 1)
