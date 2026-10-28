# Pilota autonomo (tools/pilota_ia.rb), con il ponte finto. Motore claude-code:
# un «claude -p» finto. Motore api: la gemma vera dell'API di Claude contro
# un'API finta in locale. Niente rete, niente spesa.
#   Esecuzione:  ruby -E UTF-8 tests/test_pilota_ia.rb   (oppure tests\run_tests.bat)
#   Senza la gemma (gem install anthropic) la parte api si salta.
require 'json'
require 'socket'
require 'tmpdir'
require 'stringio'
require 'fileutils'
$fail = 0
def ok(cond, msg); puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"; $fail += 1 unless cond; end
def fine
  puts
  puts $fail.zero? ? 'TUTTI I TEST PASSATI' : "#{$fail} TEST FALLITI"
  exit($fail.zero? ? 0 : 1)
end

gemma = begin
  require 'anthropic'
  true
rescue LoadError
  false
end
load File.expand_path('../tools/pilota_ia.rb', __dir__)

# ── API finta: risponde con le risposte in coda, ricorda le richieste ──
class ApiFinta
  attr_reader :port, :richieste, :risposte

  def initialize
    @srv = TCPServer.new('127.0.0.1', 0)
    @port = @srv.addr[1]
    @richieste = []
    @risposte = []
    @th = Thread.new { loop { servi(@srv.accept) } }
  end

  def servi(c)
    loop do
      line = c.gets or break
      head = {}
      while (l = c.gets) && l != "\r\n"
        k, v = l.split(':', 2)
        head[k.downcase] = v.strip
      end
      body = c.read(head['content-length'].to_i)
      @richieste << { path: line.split[1], head: head, body: JSON.parse(body) }
      r = JSON.generate(@risposte.shift || messaggio([{ type: 'text', text: 'basta' }], 'end_turn'))
      c.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{r.bytesize}\r\n\r\n#{r}")
    end
  rescue IOError, Errno::ECONNRESET
    nil
  ensure
    c.close rescue nil
  end

  def messaggio(content, stop)
    { id: "msg_#{@richieste.size}", type: 'message', role: 'assistant', model: 'claude-opus-5-5', content: content,
      stop_reason: stop, stop_sequence: nil,
      usage: { input_tokens: 100, output_tokens: 20, cache_read_input_tokens: 1000, cache_creation_input_tokens: 50 } }
  end
end

# ── Ponte finto: percezioni in coda, steer ricordati ──
class PonteFinto
  attr_reader :steers, :attese

  def initialize(prima, dopo)
    @prima = prima
    @dopo = dopo
    @steers = []
    @attese = []
  end

  def percept(_since, _n) = @prima

  def wait(since, run, secs, _n)
    @attese << [since, run, secs]
    @dopo.shift || { 'on' => false }
  end

  def steer(opts)
    @steers << opts
    rej = Array(opts['agenda']).select { |v| v['go'] == 'o999' }.map { |v| { 'item' => v, 'why' => 'cosa sconosciuta: o999' } }
    { 'ok' => true, 'agenda' => Array(opts['agenda']).map { |v| { 'act' => 'go', 'id' => v['go'], 'state' => 'waiting' } },
      'likes' => {}, 'rejected' => rej, 'photo_pending' => false, 'ev_n' => 9 }
  end
end

tmp = Dir.mktmpdir('dagawasd_pilota_ia')
png = File.join(tmp, 'foto_1.png')
File.binwrite(png, "\x89PNG\r\n\x1A\nfinto".b)
cosa = { 'id' => 'o1', 'label' => 'Gruppo12', 'kind' => 'object', 'in_view' => true, 'bearing_deg' => 10, 'dist_m' => 5.0 }
base = { 'ok' => true, 'on' => true, 'run' => 'r1', 'ev_n' => 2, 'wake' => true, 'seconds' => 3.0, 'things' => [cosa],
         'events' => [{ 'n' => 2, 'type' => 'agenda_empty' }], 'log' => [{ 'n' => 1 }], 'agenda' => [] }
foto = base.merge('ev_n' => 5, 'photo' => { 'path' => png, 'id' => 'o1', 'marks' => [{ 'id' => 'o1' }] },
                  'events' => [{ 'n' => 5, 'type' => 'photo', 'id' => 'o1' }, { 'n' => 3, 'type' => 'said', 'text' => 'Una fontana di pietra' },
                               { 'n' => 4, 'type' => 'done', 'id' => 'o1',
                                                                                'label' => 'Gruppo12', 'why' => 'raggiunto' }])
# ── Motore claude-code: un «claude -p» finto ──
chiamate = []
uscite = []
finto = lambda do |args, testo|
  chiamate << [args, testo]
  [uscite.shift || '', '', true]
end
cc = lambda do |so, sid, extra = {}|
  JSON.generate({ 'type' => 'result', 'subtype' => 'success', 'is_error' => false, 'session_id' => sid, 'num_turns' => 2,
                  'terminal_reason' => 'completed', 'result' => JSON.generate(so), 'structured_output' => so,
                  'usage' => { 'input_tokens' => 3, 'output_tokens' => 40, 'cache_read_input_tokens' => 900,
                               'cache_creation_input_tokens' => 100 } }.merge(extra))
end
uscite << cc.({ 'agenda' => [{ 'go' => 'o1', 'say' => 'Una fontana di pietra' }], 'nota' => 'Vado alla fontana' }, 's1')
uscite << cc.({}, 's1')
uscite << cc.({ 'like' => { 'frontier' => 2 } }, 's2')
pc = PonteFinto.new(base, [foto, base.merge('ev_n' => 6), { 'on' => false }])
mcc = PilotaIA::MotoreClaudeCode.new(esegui: finto)
pcc = PilotaIA::Pilota.new(motore: mcc, ponte: pc, rinnova: 2, out: (occ = StringIO.new))
pcc.guida(turni: 5, secondi: 60, attesa: 20)
a0, t0 = chiamate[0]
sc = a0 && JSON.parse(a0[a0.index('--json-schema') + 1])
ok(a0 && a0[0, 2] == %w[claude -p] && a0.each_cons(2).to_a.include?(%w[--output-format json]) &&
   a0.each_cons(2).to_a.include?(%w[--tools Read]) && a0.include?('--strict-mcp-config') && !a0.include?('--resume') &&
   a0[a0.index('--system-prompt') + 1] == PilotaIA::SISTEMA_CC && a0.each_cons(2).to_a.include?(%w[--effort low]) &&
   sc['properties'].key?('agenda') && sc['properties'].key?('nota'),
   'claude -p: risposta in JSON con lo schema dello steer (più «nota»), solo Read, niente MCP, sforzo basso')
ok(t0.start_with?('Commenti in italiano.') && JSON.parse(t0.lines[1..].join)['things'] == [cosa],
   'la descrizione va sull\'ingresso di claude -p')
ok(pc.steers[0] == { 'agenda' => [{ 'go' => 'o1', 'say' => 'Una fontana di pietra' }] } && occ.string.include?('claude: Vado alla fontana'),
   'lo steer al ponte senza la nota; la nota stampata')
a1, t1 = chiamate[1]
ok(a1 && a1.each_cons(2).to_a.include?(%w[--resume s1]) && t1.start_with?('Esito del tuo ultimo steer: {') &&
   t1.include?("Foto della sosta (guardala con Read): #{png}"),
   'secondo turno: la stessa conversazione (--resume), l\'esito dello steer di prima e il percorso della foto')
a2, t2 = chiamate[2]
ok(pc.steers.size == 2 && a2 && !a2.include?('--resume') && t2.include?('Riprendi la stessa esplorazione') &&
   t2.include?('Una fontana di pietra') && pcc.uso[:cache_read] == 2700 && occ.string.include?('fine: 3 turni'),
   'risposta {}: nessuno steer; dopo --rinnova una conversazione nuova con il riassunto; i token contati')
uscite << cc.({}, 's3', 'is_error' => true, 'result' => 'Not logged in')
err = begin
  PilotaIA::Pilota.new(motore: PilotaIA::MotoreClaudeCode.new(esegui: finto), ponte: PonteFinto.new(base, []), out: StringIO.new).guida
  nil
rescue RuntimeError => e
  e.message
end
ok(err == 'claude -p: Not logged in', "claude -p con un errore: si ferma e lo dice (#{err})")
uscite << 'non json'
err = begin
  PilotaIA::Pilota.new(motore: PilotaIA::MotoreClaudeCode.new(esegui: finto), ponte: PonteFinto.new(base, []), out: StringIO.new).guida
  nil
rescue RuntimeError => e
  e.message
end
ok(err.to_s.start_with?('claude -p non ha risposto in JSON'), 'uscita che non è JSON: si ferma e lo dice')
err = begin
  PilotaIA::MotoreClaudeCode.new(comando: 'claude_che_non_esiste_davvero').chiedi('x', nil)
rescue RuntimeError => e
  e.message
end
ok(err.to_s.include?('non si trova'), 'Claude Code assente: messaggio chiaro')

# ── Motore api ──
unless gemma
  puts 'SALTATO: la parte api, manca la gemma anthropic (gem install anthropic)'
  FileUtils.rm_rf(tmp) rescue nil
  fine
end
api = ApiFinta.new
api.risposte << api.messaggio([{ type: 'thinking', thinking: '', signature: 'firma1' },
                               { type: 'text', text: 'Vado a vederla.' },
                               { type: 'tool_use', id: 'toolu_1', name: 'steer',
                                 input: { agenda: [{ go: 'o1', dwell: 2, say: 'Una fontana di pietra' }, { go: 'o999' }] } }], 'tool_use')
api.risposte << api.messaggio([{ type: 'tool_use', id: 'toolu_2', name: 'steer', input: { like: { frontier: 2 } } }], 'tool_use')
api.risposte << api.messaggio([{ type: 'text', text: 'Proseguo.' }], 'end_turn')
ponte = PonteFinto.new(base, [base.merge('wake' => false, 'timeout' => true, 'events' => []), foto,
                              base.merge('ev_n' => 6), base.merge('ev_n' => 7, 'run' => 'r2', 'new_run' => true)])
out = StringIO.new
client = Anthropic::Client.new(api_key: 'chiave-finta', base_url: "http://127.0.0.1:#{api.port}", max_retries: 0)
pil = PilotaIA::Pilota.new(motore: PilotaIA::MotoreAPI.new(client: client), ponte: ponte, rinnova: 2, out: out)
pil.guida(turni: 4, secondi: 60, attesa: 20)
rq = api.richieste.map { |r| r[:body] }
testo = out.string

r0 = api.richieste[0]
b0 = rq[0]
ok(r0 && r0[:path] == '/v1/messages' && r0[:head]['authorization'].to_s.include?('chiave-finta') &&
   r0[:head]['anthropic-beta'].to_s.include?('server-side-fallback-2026-07-01'),
   "richiesta all'API con la chiave e il ripiego sul server (#{r0 && r0[:path]})")
ok(b0 && b0['model'] == 'claude-opus-5-5' && b0['output_config'] == { 'effort' => 'low' } && b0['fallbacks'] == 'default' &&
   b0['cache_control'] == { 'type' => 'ephemeral' } && b0['system'] == PilotaIA::SISTEMA && b0['max_tokens'] == 16_000,
   'modello, sforzo basso per la fluidità, ripieghi, cache, istruzioni fisse')
ok(b0 && b0['tools'].map { |t| t['name'] } == ['steer'] && b0['tools'][0]['input_schema']['properties'].key?('agenda'),
   'uno strumento, steer, con lo schema delle voci')
m0 = b0 && b0['messages']
ok(m0 && m0.size == 1 && m0[0]['role'] == 'user' && m0[0]['content'][0]['text'].start_with?('Commenti in italiano.') &&
   (d0 = JSON.parse(m0[0]['content'][0]['text'].lines[1..].join)) && d0['things'] == [cosa] && !d0.key?('log') && !d0.key?('wake'),
   'primo turno: la lingua dei commenti e la descrizione in JSON, senza diario né campi del ponte')
ok(ponte.steers[0] && ponte.steers[0]['agenda'][0] == { 'go' => 'o1', 'dwell' => 2, 'say' => 'Una fontana di pietra' } &&
   testo.include?('claude: Vado a vederla.') && testo.include?('rifiutate: cosa sconosciuta: o999'),
   'lo steer di Claude va al ponte tale e quale; testo e voci rifiutate stampati')
ok(ponte.attese[0] == [2, 'r1', 20] && rq.size == 4, "attesa del prossimo avviso (since, giro, secondi); scaduta senza avvisi: nessun turno (#{rq.size} richieste)")

m1 = rq[1] && rq[1]['messages']
ok(m1 && m1.size == 3 && m1[1]['role'] == 'assistant' && m1[1]['content'].map { |c| c['type'] } == %w[thinking text tool_use] &&
   m1[1]['content'][0]['signature'] == 'firma1' && m1[0] == m0[0],
   'secondo turno: la conversazione cresce solo in coda, la risposta di prima intera (anche il ragionamento firmato)')
c1 = m1 && m1[2]['content']
ok(c1 && c1[0]['type'] == 'tool_result' && c1[0]['tool_use_id'] == 'toolu_1' && JSON.parse(c1[0]['content'])['rejected'].size == 1 &&
   c1[1]['type'] == 'text' && c1[2]['type'] == 'image' && c1[2]['source']['media_type'] == 'image/png' &&
   c1[2]['source']['data'] == [File.binread(png)].pack('m0'),
   'poi: il risultato dello steer (con le voci rifiutate), la descrizione nuova e la foto della sosta')
ok(c1 && !JSON.parse(c1[1]['text'])['photo'].key?('path'), 'la descrizione non dice il percorso della foto sul disco')

m2 = rq[2] && rq[2]['messages']
ok(m2 && m2.size == 1 && m2[0]['content'][0]['type'] == 'text' && m2[0]['content'][0]['text'].include?('Riprendi la stessa esplorazione') &&
   m2[0]['content'][0]['text'].include?('Una fontana di pietra') && m2[0]['content'][0]['text'].include?('o1 Gruppo12'),
   'dopo --rinnova turni: conversazione nuova, con le mete fatte e i commenti già detti')
m3 = rq[3] && rq[3]['messages']
ok(pil.turni == 4 && m3 && m3.size == 1 && !m3[0]['content'][0]['text'].include?('Riprendi') && testo.include?('un giro nuovo') &&
   pil.uso[:cache_read] == 4000 && testo.include?('fine: 4 turni'),
   "giro nuovo: si ricomincia da capo; al tetto dei turni la fine, con i token (#{testo.lines.last.strip})")
pf = PilotaIA::Pilota.new(motore: PilotaIA::MotoreAPI.new(client: client), ponte: PonteFinto.new(base, [base.merge('ev_n' => 3, 'wake' => false, 'timeout' => true), { 'on' => false }]),
                          out: (of = StringIO.new))
pf.guida(turni: 5)
ok(pf.turni == 1 && of.string.include?('esploratore fermo') && of.string.include?('fine: 1 turni'), 'esploratore fermato a metà: il pilota finisce')

# Esploratore spento all'inizio: niente richieste
api2 = ApiFinta.new
p2 = PilotaIA::Pilota.new(motore: PilotaIA::MotoreAPI.new(client: Anthropic::Client.new(api_key: 'x', base_url: "http://127.0.0.1:#{api2.port}", max_retries: 0)),
                          ponte: PonteFinto.new({ 'on' => false }, []), out: (o2 = StringIO.new))
p2.guida
ok(api2.richieste.empty? && o2.string.include?('avvialo prima'), 'esploratore spento: nessuna richiesta all\'API')

# Un modello senza ripieghi sul server: niente beta né fallbacks
api3 = ApiFinta.new
m3 = PilotaIA::MotoreAPI.new(client: Anthropic::Client.new(api_key: 'x', base_url: "http://127.0.0.1:#{api3.port}", max_retries: 0),
                             modello: 'claude-haiku-5-5', sforzo: 'medium')
PilotaIA::Pilota.new(motore: m3, ponte: PonteFinto.new(base, []), out: StringIO.new).guida(turni: 1)
b3 = api3.richieste[0]
ok(b3 && !b3[:body].key?('fallbacks') && !b3[:head]['anthropic-beta'].to_s.include?('fallback') && b3[:body]['output_config']['effort'] == 'medium',
   'altro modello: senza ripieghi, con lo sforzo scelto')

FileUtils.rm_rf(tmp) rescue nil
fine
