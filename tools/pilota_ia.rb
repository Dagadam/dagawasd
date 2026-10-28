# DagaWASD — pilota autonomo: Claude guida l'esploratore (lib/explore.rb,
# lib/expilot.rb) da solo, senza che nessuno lanci un comando alla volta. Il
# ponte (lib/bridge.rb) sveglia il pilota quando c'è da decidere (GET
# /explore/wait); il pilota manda a Claude che cosa l'esploratore vede e sa,
# con la foto della sosta se ce n'è una nuova, e passa al ponte (POST
# /explore, steer) quello che Claude decide: agenda, gusti, commenti.
# Intanto l'esploratore va da solo: l'IA decide fra un avviso e l'altro.
# Non viene installato in SketchUp, come tools/esplora.rb.
#
#   ruby tools/pilota_ia.rb [--turni 20] [--secondi 300] [--attesa 60]
#                           [--motore claude-code | api]
#                           [--modello claude-opus-5-5] [--sforzo low]
#                           [--lingua italiano] [--cose 20] [--rinnova 10]
#                           [--senza-foto] [--json]
#
# Due motori:
#   claude-code (se non c'è ANTHROPIC_API_KEY): ogni turno è un «claude -p»
#     con l'account di Claude Code di questo computer; la risposta è il JSON
#     dello steer, la foto Claude la guarda con Read, la conversazione
#     continua con --resume. Gira in una cartella sua, senza MCP né progetto.
#   api (se c'è la chiave): l'API di Claude con la gemma ufficiale
#     (gem install anthropic) e lo strumento «steer».
# --turni: quante volte al più chiede a Claude (ogni volta consuma: è il
#   tetto); --secondi: per quanto guida; --attesa: quanto aspetta un avviso
#   prima di lasciar fare all'esploratore e aspettare ancora.
# --sforzo: low risponde in pochi secondi e tiene l'esplorazione fluida;
#   medium o high pensano di più e lasciano più tempo l'esploratore da solo.
# --rinnova: dopo tanti turni si ricomincia una conversazione nuova (con un
#   riassunto di quello che ha detto e visto), così non cresce senza fine.
# I commenti di Claude finiscono nel percorso registrato: descrizioni delle
# scene e sottotitoli del video (lib/path.rb).
# Esce con 0 se tutto è andato bene, 1 per un errore, 2 per un uso sbagliato.
require 'json'
require 'net/http'
require 'base64'
require 'open3'
require 'tmpdir'

module PilotaIA
  MODELLO = 'claude-opus-5-5'
  # Modelli che accettano i ripieghi automatici sul server quando rifiutano
  FALLBACK = %w[claude-opus-5-5 claude-opus-5 claude-fable-5-1 claude-sonnet-5-5].freeze
  FALLBACK_BETA = 'server-side-fallback-2026-07-01'

  SISTEMA = <<~TXT
    Guidi un esploratore che cammina dentro un modello 3D di SketchUp (un
    edificio, un paese, un paesaggio) e ne registra il percorso, che diventerà
    un video. L'esploratore si muove e guarda da solo; tu decidi dove andare e
    che cosa guardare, come farebbe un visitatore curioso, e commenti quello
    che c'è di notevole.

    Ogni volta ricevi in JSON che cosa vede e sa, quando c'è qualcosa da
    decidere (gli avvisi in "events"):
    - things: le cose viste, con un nome corto stabile (o12 un oggetto, s7 una
      faccia o superficie), il nome nel modello (label: a volte dice poco, come
      "Gruppo2577#2"), bearing_deg (il lato rispetto allo sguardo: + a
      sinistra, − a destra), elev_deg, dist_m, size_m, salience (quanto
      spicca), in_view (adesso nella vista), reached (già raggiunta);
      a piedi anche reach: yes (ci si arriva, walk_m metri di strada),
      unknown (forse: la strada passa da zone mai viste), no (non ci si
      arriva: niente go, al più look), far (troppo lontano per saperlo);
    - frontiers: zone ancora inesplorate (F3), con larghezza, quanto è
      ignoto e reach come sopra;
    - target: dove sta andando ora (by "ai" se l'hai deciso tu), agenda: le tue
      mete in coda, likes: i tuoi gusti;
    - pos_m, yaw_deg, pitch_deg: dove sta e dove guarda; mode: walk a piedi, fly in volo.
    Alle soste davanti alle tue mete arriva anche una foto della vista, con i
    nomi corti scritti accanto alle cose visibili: la meta in giallo, gli
    oggetti in blu (in grigio chiaro quelli dove a piedi non si arriva), le
    superfici in grigio scuro, le zone inesplorate in viola. È il
    modo per sapere che cosa sono davvero le cose dal nome muto.

    Per agire usa lo strumento steer; puoi anche non usarlo, se va bene così.
    - Tieni in agenda una o due mete alla volta, vicine fra loro e a dove si
      trova: un giro sensato, senza andare avanti e indietro. Quando l'agenda è
      quasi vuota, aggiungi la prossima con add. Se la meta in corso va
      ancora bene non rifare l'agenda: agenda la sostituisce, e la meta in
      corso si lascia (resta solo se la rimetti per prima).
    - go va da una cosa e la guarda; look la guarda da dove si trova; to va a
      un punto in metri. dwell sono i secondi di sosta, orbit i gradi del giro
      intorno alla cosa (0 per nessuno).
    - say nella voce è il commento detto all'arrivo (se rifai l'agenda prima
      dell'arrivo non è detto); say da solo è detto subito. Quello che è stato
      detto davvero arriva negli avvisi said. Commenta solo ciò che vale la
      pena: una frase breve, concreta, da sottotitolo, su quello che si vede
      (nella foto) e non sui nomi corti. Mai lo stesso commento due volte.
    - snap fa una foto per la galleria del giro: una bella foto senza segni,
      che chi guarda il giro sfoglierà con i tuoi appunti. In una voce si
      scatta all'arrivo; da solo, subito, la vista di adesso. Il testo di
      snap è il perché l'hai voluta (una frase tua, viva), il say della voce
      (o quello accanto a snap) dice che cosa c'è. Solo per le vedute e le
      cose che lo meritano davvero: una ogni tanto, non a ogni meta.
    - like dà un peso alle cose (0–5, 1 neutro; "frontier" per le zone nuove,
      "label:testo" per un tipo di cosa), avoid le evita.
    - In volo si raggiunge tutto. A piedi preferisci reach yes, con pochi
      walk_m; se una meta non si raggiunge lo stesso (avviso slow o done con
      why diverso da raggiunto), scegline un'altra.
    Risposte brevi: l'esploratore intanto continua a camminare.
  TXT

  VOCE = {
    type: 'object',
    properties: {
      go: { type: 'string', description: 'nome corto di una cosa o zona (o12, s7, F3): ci va e la guarda' },
      look: { type: 'string', description: 'nome corto di una cosa: la guarda da dove si trova' },
      to: { type: 'array', items: { type: 'number' }, minItems: 3, maxItems: 3, description: 'un punto [x, y, z] in metri' },
      dwell: { type: 'number', description: 'secondi di sosta all\'arrivo (0–60)' },
      orbit: { type: 'number', description: 'gradi di giro intorno alla cosa (0–360)' },
      say: { type: 'string', description: 'commento detto all\'arrivo (sottotitolo del video)' },
      snap: { type: 'string', description: 'all\'arrivo una foto per la galleria: perché la vuoi' }
    }
  }.freeze

  STRUMENTO = {
    name: 'steer',
    description: 'Guida l\'esploratore: le mete (agenda sostituisce, add aggiunge in coda), i gusti, i commenti, ' \
                 'le foto. Risponde con l\'agenda com\'è adesso e le voci rifiutate, con il motivo.',
    input_schema: {
      type: 'object',
      properties: {
        agenda: { type: 'array', items: VOCE, description: 'sostituisce le mete in coda (al più 8)' },
        add: { type: 'array', items: VOCE, description: 'mete aggiunte in coda' },
        clear: { type: 'boolean', description: 'nessuna meta: l\'esploratore torna a scegliere da solo' },
        skip: { type: 'boolean', description: 'lascia la meta di adesso' },
        like: { type: 'object', additionalProperties: { type: %w[number null] },
                description: 'pesi 0–5 per nomi corti, "frontier", "open", "label:testo"; null toglie' },
        avoid: { type: 'array', items: { type: 'string' }, description: 'nomi corti da evitare' },
        say: { type: 'string', description: 'un commento detto subito' },
        photo: { type: 'boolean', description: 'una foto alla sosta di adesso, o alla prossima' },
        snap: { type: 'string', description: 'una foto per la galleria, adesso: perché la vuoi (say: che cosa c\'è)' }
      }
    }
  }.freeze

  # Con claude -p lo strumento non c'è: la risposta è lo steer stesso.
  SISTEMA_CC = SISTEMA + <<~TXT

    Qui lo strumento steer non c'è: la tua risposta è sempre un oggetto JSON
    con i suoi stessi campi ({} se va bene così), più "nota" per un pensiero
    breve tuo, che non viene detto. Quando arriva una foto ti è dato il
    percorso del file PNG: guardala con Read. Non usare altri strumenti.
  TXT
  SCHEMA_CC = STRUMENTO[:input_schema].merge(
    properties: STRUMENTO[:input_schema][:properties].merge(nota: { type: 'string', description: 'un pensiero breve, non detto' })
  ).freeze

  # ── Motore api: l'API di Claude con lo strumento steer ──
  # La conversazione cresce solo in coda: i risultati degli steer tornano al
  # turno dopo, davanti alla descrizione nuova.
  class MotoreAPI
    def initialize(client:, modello: MODELLO, sforzo: 'low')
      @client = client
      @modello = modello
      @sforzo = sforzo
      nuova
    end

    def nuova
      @messaggi = []
      @esiti = []
    end

    # → { azioni: [[:testo, s] | [:steer, id, opts]], stop:, uso: {…}, rinnova: }
    def chiedi(testo, foto)
      contenuto = @esiti + [{ type: 'text', text: testo }]
      if foto
        contenuto << { type: 'image', source: { type: 'base64', media_type: 'image/png', data: Base64.strict_encode64(File.binread(foto)) } }
      end
      @esiti = []
      @messaggi << { role: 'user', content: contenuto }
      par = { model: @modello, max_tokens: 16_000, system_: SISTEMA, tools: [STRUMENTO], messages: @messaggi,
              output_config: { effort: @sforzo.to_sym }, cache_control: { type: 'ephemeral' } }
      par.merge!(betas: [FALLBACK_BETA], fallbacks: :default) if FALLBACK.include?(@modello)
      r = @client.beta.messages.create(**par)
      @messaggi << { role: 'assistant', content: r.content }
      u = r.usage
      uso = { in: u.input_tokens.to_i, out: u.output_tokens.to_i, cache_read: u.cache_read_input_tokens.to_i,
              cache_new: u.cache_creation_input_tokens.to_i }
      stop = r.stop_reason.to_s
      if r.stop_reason == :refusal                 # anche i ripieghi hanno rifiutato: si ricomincia
        stop += " #{r.stop_details&.category} #{r.stop_details&.explanation}"
        return { azioni: [], stop: stop, uso: uso, rinnova: true }
      end
      return { azioni: [], stop: stop, uso: uso, rinnova: true } if r.stop_reason == :max_tokens   # uno steer a metà no
      azioni = r.content.filter_map do |b|
        case b.type
        when :text then [:testo, b.text.strip] unless b.text.strip.empty?
        when :tool_use
          opts = JSON.parse(JSON.generate(b.input))
          next [:steer, b.id, opts] if b.name == 'steer' && opts.is_a?(Hash)
          esito(b.id, "strumento sconosciuto: #{b.name}", true)
          nil
        end
      end
      { azioni: azioni, stop: stop, uso: uso, rinnova: false }
    end

    def esito(id, testo, errore)
      @esiti << { type: 'tool_result', tool_use_id: id, content: testo, is_error: errore }
    end
  end

  # ── Motore claude-code: «claude -p» con l'account di questo computer ──
  # Ogni turno un processo; la conversazione continua con --resume. La
  # risposta è il JSON dello steer (--json-schema); l'unico strumento è Read,
  # per la foto. Gira in una cartella sua: niente CLAUDE.md né memoria del
  # progetto, niente MCP.
  class MotoreClaudeCode
    attr_reader :sessione

    def initialize(modello: MODELLO, sforzo: 'low', comando: 'claude', cartella: File.join(Dir.tmpdir, 'dagawasd_pilota'), esegui: nil)
      @modello = modello
      @sforzo = sforzo
      @comando = comando
      @cartella = cartella
      @esegui = esegui || method(:lancia)
      nuova
    end

    def nuova
      @sessione = nil
      @esiti = []
    end

    def chiedi(testo, foto)
      testo = "#{@esiti.join("\n")}\n#{testo}" unless @esiti.empty?
      testo += "\nFoto della sosta (guardala con Read): #{foto}" if foto
      @esiti = []
      args = [@comando, '-p', '--output-format', 'json', '--json-schema', JSON.generate(SCHEMA_CC),
              '--system-prompt', SISTEMA_CC, '--tools', 'Read', '--allowedTools', 'Read', '--strict-mcp-config',
              '--model', @modello, '--effort', @sforzo]
      args += ['--resume', @sessione] if @sessione
      out, err, ok = @esegui.call(args, testo)
      j = (JSON.parse(out.to_s) rescue nil)
      raise "claude -p non ha risposto in JSON#{ok ? '' : ' (uscito con errore)'}: #{(err.to_s + out.to_s).strip[0, 300]}" unless j.is_a?(Hash)
      raise "claude -p: #{j['result'].to_s[0, 300]}" if j['is_error']
      @sessione = j['session_id']
      u = j['usage'] || {}
      uso = { in: u['input_tokens'].to_i, out: u['output_tokens'].to_i, cache_read: u['cache_read_input_tokens'].to_i,
              cache_new: u['cache_creation_input_tokens'].to_i }
      so = j['structured_output']
      so = (JSON.parse(j['result'].to_s) rescue nil) unless so.is_a?(Hash)
      azioni = []
      if so.is_a?(Hash)
        nota = so.delete('nota')
        azioni << [:testo, nota.strip] if nota.is_a?(String) && !nota.strip.empty?
        azioni << [:steer, "cc#{j['num_turns']}", so] unless so.empty?
      end
      { azioni: azioni, stop: j['terminal_reason'] || j['subtype'], uso: uso, rinnova: false }
    end

    def esito(_id, testo, errore)
      @esiti << "#{errore ? 'Errore del' : 'Esito del'} tuo ultimo steer: #{testo}"
    end

    private

    def lancia(args, testo)
      Dir.mkdir(@cartella) unless Dir.exist?(@cartella)
      Open3.capture3(*args, stdin_data: testo, chdir: @cartella)
    rescue Errno::ENOENT
      raise "«#{@comando}» non si trova: serve Claude Code installato (o --motore api con una chiave)"
    end
  end

  # ── Il ponte di SketchUp ──
  class Ponte
    def initialize(info)
      @port = info['port']
      @token = info['token']
    end

    def percept(since, n) = get("/explore/percept?since=#{since.to_i}&n=#{n}")
    def wait(since, run, secs, n) = get("/explore/wait?since=#{since.to_i}&timeout=#{secs.round}&run=#{run}&n=#{n}", secs + 30)

    def steer(opts)
      req = Net::HTTP::Post.new('/explore')
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate('cmd' => 'steer', 'opts' => opts)
      call(req)
    end

    private

    def get(path, timeout = 30) = call(Net::HTTP::Get.new(path), timeout)

    def call(req, timeout = 30)
      req['X-Token'] = @token
      res = Net::HTTP.start('127.0.0.1', @port, open_timeout: 3, read_timeout: timeout) { |h| h.request(req) }
      body = JSON.parse(res.body.force_encoding('UTF-8')) rescue nil
      raise "risposta inattesa dal ponte (#{res.code}): #{res.body.to_s[0, 200]}" unless body.is_a?(Hash)
      raise "ponte: #{body['error']}" if res.code != '200'
      body
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout
      raise "SketchUp non risponde sulla porta #{@port}: è aperto, col ponte acceso?"
    end
  end

  # ── Il pilota ──
  class Pilota
    attr_reader :turni, :uso, :detti

    def initialize(motore:, ponte:, lingua: 'italiano', cose: 20, rinnova: 10, foto: true, json: false, out: $stdout)
      @motore = motore
      @ponte = ponte
      @lingua = lingua
      @cose = cose
      @rinnova = rinnova
      @foto = foto
      @json = json
      @out = out
      @turni = 0
      @uso = Hash.new(0)
      @detti = []            # i commenti detti davvero (avvisi said), per il riassunto quando si rinnova
      @mete = []             # le mete fatte
      nuova_conversazione
    end

    # Guida finché l'esploratore va, per al più turni volte e secondi s.
    def guida(turni: 20, secondi: 300, attesa: 60)
      fine = Time.now + secondi
      p = @ponte.percept(0, @cose)
      return riga('esploratore fermo: avvialo prima (tools/esplora.rb avvia)') unless p['on']
      @run = p['run']
      while @turni < turni && Time.now < fine
        break riga('esploratore fermo') unless p['on']
        if p['new_run']
          riga('un giro nuovo: si ricomincia')
          @run = p['run']
          nuova_conversazione
        end
        turno(p) if @turni.zero? || p['wake'] || p['new_run']
        p = @ponte.wait(p['ev_n'], @run, [attesa, fine - Time.now].min.clamp(0, 300), @cose)
      end
      riga(format('fine: %d turni, token %d in (%d dalla cache) e %d out', @turni, @uso[:in] + @uso[:cache_read] + @uso[:cache_new],
                  @uso[:cache_read], @uso[:out]))
    end

    # Un giro di domanda e risposta: la descrizione (e la foto) a Claude, i
    # suoi steer al ponte; gli esiti il motore li ridà a Claude al turno dopo.
    def turno(p)
      nuova_conversazione(riassunto) if @in_conv >= @rinnova      # gli steer in sospeso sono già applicati
      @turni += 1
      @in_conv += 1
      p['events'].each do |e|
        @mete << "#{e['id']} #{e['label']}".strip if e['type'] == 'done' && e['why'] == 'raggiunto'
        @detti << e['text'] if e['type'] == 'said'
      end
      foto = nil
      if @foto && (f = p['photo']) && f['path'] != @ultima_foto && File.exist?(f['path'].to_s)
        foto = @ultima_foto = f['path']
      end
      t0 = Time.now
      r = @motore.chiedi(descrizione(p), foto)
      r[:uso].each { |k, v| @uso[k] += v }
      riga(format('turno %d (%.1f s, %s)', @turni, Time.now - t0, r[:stop]))
      r[:azioni].each do |a|
        case a[0]
        when :testo then riga("  claude: #{a[1]}")
        when :steer then esegui(a[1], a[2])
        end
      end
      nuova_conversazione(riassunto) if r[:rinnova]
    end

    private

    def nuova_conversazione(primo = nil)
      @motore.nuova
      @in_conv = 0
      @primo = primo
    end

    def riassunto
      return nil if @detti.empty? && @mete.empty?
      "Riprendi la stessa esplorazione. Mete già fatte: #{@mete.last(30).join(', ')}. " \
        "Commenti già detti (non ripeterli): #{@detti.last(20).map { |s| "«#{s}»" }.join(' ')}."
    end

    def descrizione(p)
      d = p.reject { |k, _| %w[ok wake log ev_n].include?(k) }
      d['photo'] = d['photo'].reject { |k, _| k == 'path' } if d['photo']
      testo = JSON.generate(d)
      testo = "Commenti in #{@lingua}.\n#{@primo ? "#{@primo}\n" : ''}#{testo}" if @in_conv == 1
      testo
    end

    # Lo steer di Claude al ponte; l'esito, ridotto, torna a Claude.
    def esegui(id, opts)
      riga("  steer #{JSON.generate(opts)}")
      r = @ponte.steer(opts)
      riga("  rifiutate: #{r['rejected'].map { |x| x['why'] }.join(' | ')}") unless r['rejected'].to_a.empty?
      @motore.esito(id, JSON.generate(r.slice('agenda', 'likes', 'rejected', 'photo_pending')), !r['ok'])
    rescue => e
      @motore.esito(id, "errore: #{e.message}", true)
    end

    def riga(s)
      @out.puts(@json ? JSON.generate('t' => Time.now.strftime('%H:%M:%S'), 'msg' => s) : s)
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  def die(msg, code = 1)
    warn "pilota_ia.rb: #{msg}"
    exit code
  end

  def valore(nome)
    i = ARGV.index(nome) or return nil
    v = ARGV[i + 1] or die("#{nome} vuole un valore", 2)
    ARGV.slice!(i, 2)
    v
  end

  def numero(nome)
    v = valore(nome) or return nil
    Float(v)
  rescue ArgumentError
    die("#{nome}: atteso un numero, non #{v}", 2)
  end

  turni = (numero('--turni') || 20).to_i
  secondi = numero('--secondi') || 300
  attesa = numero('--attesa') || 60
  motore = valore('--motore') || (ENV['ANTHROPIC_API_KEY'].to_s.empty? ? 'claude-code' : 'api')
  modello = valore('--modello') || PilotaIA::MODELLO
  sforzo = valore('--sforzo') || 'low'
  lingua = valore('--lingua') || 'italiano'
  cose = (numero('--cose') || 20).to_i.clamp(5, 80)
  rinnova = (numero('--rinnova') || 10).to_i.clamp(2, 100)
  foto = !ARGV.delete('--senza-foto')
  json = !ARGV.delete('--json').nil?
  die("opzione sconosciuta: #{ARGV.first}", 2) unless ARGV.empty?
  die("--sforzo: low, medium, high, xhigh o max, non #{sforzo}", 2) unless %w[low medium high xhigh max].include?(sforzo)
  die("--motore: claude-code o api, non #{motore}", 2) unless %w[claude-code api].include?(motore)

  if motore == 'api'
    begin
      require 'anthropic'
    rescue LoadError
      die('manca la gemma dell\'API di Claude: gem install anthropic (o --motore claude-code)')
    end
  end
  info_path = File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'bridge.json')
  die("#{info_path} non esiste: accendi il ponte in DagaWASD (Sistema › Ponte Claude)") unless File.exist?(info_path)
  info = (JSON.parse(File.read(info_path, encoding: 'UTF-8')) rescue die("#{info_path} illeggibile"))
  $stdout.sync = true
  m = if motore == 'api'
        PilotaIA::MotoreAPI.new(client: Anthropic::Client.new, modello: modello, sforzo: sforzo)
      else
        PilotaIA::MotoreClaudeCode.new(modello: modello, sforzo: sforzo)
      end
  puts "motore #{motore}, #{modello}, sforzo #{sforzo}"
  pilota = PilotaIA::Pilota.new(motore: m, ponte: PilotaIA::Ponte.new(info), lingua: lingua, cose: cose, rinnova: rinnova,
                                foto: foto, json: json)
  begin
    pilota.guida(turni: turni, secondi: secondi, attesa: attesa)
  rescue Interrupt
    puts "interrotto dopo #{pilota.turni} turni"
  rescue RuntimeError => e
    die(e.message)
  rescue StandardError => e
    raise unless defined?(Anthropic::Errors::APIError) && e.is_a?(Anthropic::Errors::APIError)
    case e
    when Anthropic::Errors::AuthenticationError
      die('chiave dell\'API rifiutata o assente: imposta ANTHROPIC_API_KEY (o --motore claude-code)')
    when Anthropic::Errors::RateLimitError then die("troppe richieste all'API, riprova più tardi (#{e.message})")
    when Anthropic::Errors::APIStatusError then die("l'API ha risposto con un errore (#{e.status}): #{e.message}")
    else die("l'API non risponde: #{e.message}")
    end
  end
end
