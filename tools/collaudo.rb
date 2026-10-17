# DagaWASD — Collaudo dal vivo, nel SketchUp aperto: i passaggi che i test
# (tests/) non raggiungono perché passano dalle finestre. Il Ruby lo fa il
# ponte (lib/bridge.rb), pulsanti, menu e finestre tools/finestre.ps1.
#
#   ruby -E UTF-8 tools/collaudo.rb [pannello] [conferma] [video]   (nessuno = tutti)
#
#   pannello  il pulsante della barra e il menu aprono il pannello, sullo
#             schermo; ricordato fuori dallo schermo, si riapre visibile
#   conferma  «Elimina percorso»: con «No» resta, con «Sì» sparisce
#   video     esportazione di un percorso breve, scegliendo il file (AVI) o la
#             cartella (PNG) nella finestra di Windows, fino alla finestra finale
#
# Serve il ponte acceso (Sistema › Ponte Claude) e FPS spento. Il modello
# resta com'era: i percorsi di prova («Collaudo Claude …») si tolgono alla
# fine, il pannello torna dov'era, i file del video stanno in una cartella
# temporanea e si cancellano. Le operazioni restano nella cronologia di
# annullamento. Mentre gira, non usare SketchUp.
$stdout.sync = true   # i risultati si vedono subito anche in una pipe
require 'json'
require 'net/http'
require 'open3'
require 'tmpdir'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
FIN  = File.join(ROOT, 'tools', 'finestre.ps1')
INFO = File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'bridge.json')

$falliti = 0
def ok(cond, msg)
  puts "#{cond ? 'PASS' : 'FAIL'} #{msg}"
  $falliti += 1 unless cond
  cond
end

def nota(msg); puts "     #{msg}"; end

# Ruby nel modello aperto; ritorna il valore dell'ultima espressione, passato in JSON
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

# tools/finestre.ps1; ritorna [riuscito, testo]
def fin(*args)
  out, st = Open3.capture2e('powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', FIN, *args.map(&:to_s))
  [st.success?, out.force_encoding('UTF-8').strip]
end

# Aspetta la finestra; se invece compare un avviso (un errore) lo dice,
# lo chiude e ritorna false.
def aspetta_finestra(titolo, secondi)
  esito = nil
  aspetta(secondi) do
    if fin('aspetta', titolo, 0.2)[0]
      esito = true
    elsif fin('aspetta', 'avviso', 0.2)[0]
      _, testo = fin('controlli', 'avviso')
      nota "avviso inatteso: #{testo[/«([^»]*)»\s+id=qt_msgbox_label/m, 1] || testo}"
      fin('premi', 'avviso', 'OK')
      esito = false
    end
    !esito.nil?
  end
  esito == true
end

def aspetta(secondi)
  t0 = Time.now
  loop do
    return true if yield
    return false if Time.now - t0 > secondi
    sleep 0.5
  end
end

abort "Il ponte è spento: accendilo in DagaWASD (Sistema › Ponte Claude)" unless File.exist?(INFO)
# Pulsanti, menu, catture e tasti passano da tools/finestre.ps1: serve il permesso del pannello
IMP = (JSON.parse(File.read(File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'settings.json'), encoding: 'UTF-8')) rescue {})
abort 'Finestre e tasti spenti: accendili in DagaWASD (Sistema › Ponte Claude › Finestre e tasti)' unless IMP['bridge_windows']
parti = ARGV.empty? ? %w[pannello conferma video] : ARGV
STATO = su(<<~'RUBY')
  m = DagaWASD::FPSWalk
  d = m.instance_variable_get(:@dialog)
  aperto = !!(d && d.visible?)
  { 'fps' => !!m.instance_variable_get(:@active), 'job' => !m.instance_variable_get(:@path_job).nil?,
    'titolo' => "DagaWASD — #{m.t('menu.settings').sub(/…\z/, '')}", 'menu' => m.t('menu.settings'),
    'aperto' => aperto, 'dove' => (aperto && d.respond_to?(:get_position) ? d.get_position + d.get_size : nil),
    'fix' => m.respond_to?(:dialog_on_screen), 'formato' => m.cf('path_video_format'),
    'attesa' => "DagaWASD — #{m.t('att.title')}", 'salva' => m.t('path.save_video'), 'cartella' => m.t('path.choose_dir'),
    'versione' => (DagaWASD::FPSWalkLoader::VERSION rescue '?') }
RUBY
abort 'Modalità FPS attiva: esci prima (Esc)' if STATO['fps']
abort 'Un percorso è in riproduzione o in esportazione: aspetta che finisca' if STATO['job']
puts "Collaudo dal vivo — DagaWASD #{STATO['versione']}: #{parti.join(', ')}"

TITOLO = STATO['titolo']
def chiudi_pannello
  su("d = DagaWASD::FPSWalk.instance_variable_get(:@dialog); d.close if d&.visible?; nil")
  fin('sparita', TITOLO, 5)
end

def sullo_schermo?
  r, out = fin('posizione', TITOLO)
  nota "pannello: #{out}"
  r && !out.include?('NESSUNO')
end

# ── Pannello ─────────────────────────────────────────────────────────
if parti.include?('pannello')
  chiudi_pannello
  r, out = fin('premi', 'principale', 'FPS Settings')
  ok(r, "barra: pulsante delle impostazioni premuto (#{out})")
  ok(fin('aspetta', TITOLO, 10)[0], 'barra: il pannello si apre')
  ok(sullo_schermo?, 'barra: il pannello è su un monitor')

  chiudi_pannello
  r, out = fin('menu', "Estensioni>DagaWASD>#{STATO['menu']}")
  ok(r, "menu: #{out}")
  ok(fin('aspetta', TITOLO, 10)[0], 'menu: il pannello si apre')

  if STATO['fix']
    su('DagaWASD::FPSWalk.instance_variable_get(:@dialog).set_position(-30_000, 200); nil')
    fin('menu', "Estensioni>DagaWASD>#{STATO['menu']}")   # già aperto: lo riporta davanti
    sleep 0.5
    ok(sullo_schermo?, 'fuori dallo schermo e richiamato dal menu: torna su un monitor')
    chiudi_pannello
    su('DagaWASD::FPSWalk.show_panel; nil')               # riaperto: SketchUp ricordava la posizione
    sleep 0.5
    ok(sullo_schermo?, 'riaperto dopo la chiusura: su un monitor')
  else
    nota 'SALTATO pannello fuori dallo schermo: la versione installata non ha dialog_on_screen (installa.bat e riavvia)'
  end

  # com'era prima
  if STATO['aperto']
    su('DagaWASD::FPSWalk.show_panel; nil')
    x, y, w, h = STATO['dove']
    su("d = DagaWASD::FPSWalk.instance_variable_get(:@dialog); d.set_size(#{w}, #{h}); d.set_position(#{x}, #{y}); nil") if x
  else
    chiudi_pannello
  end
end

# ── Percorsi di prova ────────────────────────────────────────────────
# Due campioni a mezzo secondo l'uno dall'altro, dalla camera attuale
# mezzo metro avanti: un video di pochi fotogrammi.
def crea_percorso(nome)
  su(<<~RUBY)
    m = DagaWASD::FPSWalk
    c = Sketchup.active_model.active_view.camera
    e = c.eye.to_a.map(&:to_f); d = c.direction.to_a; u = c.up.to_a   # Length in JSON diventerebbe testo
    a = [0.0, *e, *d, *u, c.fov]
    b = [0.5, *e.zip(d).map { |p, v| p + v * 20 }, *d, *u, c.fov]
    Sketchup.active_model.set_attribute(m::PATH_DICT, #{nome.inspect}, JSON.generate('date' => Time.now.strftime('%Y-%m-%d %H:%M'), 's' => [a, b]))
    m.path_push
    !m.path_data(#{nome.inspect}).nil?
  RUBY
end

def esiste?(nome); su("!DagaWASD::FPSWalk.path_data(#{nome.inspect}).nil?"); end

def togli_percorso(nome)
  su(<<~RUBY)
    m = DagaWASD::FPSWalk
    d = m.path_dict
    if d&.[](#{nome.inspect})
      d.delete_key(#{nome.inspect})
      Sketchup.active_model.attribute_dictionaries.delete(d) if d.keys.empty?
      m.path_push
    end
    nil
  RUBY
end

# Fuori dall'operazione del ponte e senza bloccarlo: le finestre modali
# le apre SketchUp mentre il collaudo aspetta.
def comando_percorso(cmd, nome)
  su("UI.start_timer(0, false) { DagaWASD::FPSWalk.path_command(#{cmd.inspect}, #{nome.inspect}) }; nil")
end

# ── Conferma ─────────────────────────────────────────────────────────
if parti.include?('conferma')
  nome = "Collaudo Claude #{Time.now.strftime('%H%M%S')}"
  ok(crea_percorso(nome), "percorso di prova «#{nome}» creato")
  begin
    comando_percorso('delete', nome)
    ok(fin('aspetta', 'avviso', 10)[0], 'Elimina: compare la richiesta di conferma')
    _, testo = fin('controlli', 'avviso')
    ok(testo.include?(nome), 'la richiesta nomina il percorso')
    ok(fin('premi', 'avviso', 'No')[0] && fin('sparita', 'avviso', 5)[0], 'risposto «No»')
    ok(esiste?(nome), 'con «No» il percorso resta')

    comando_percorso('delete', nome)
    fin('aspetta', 'avviso', 10)
    ok(fin('premi', 'avviso', 'Sì')[0] && fin('sparita', 'avviso', 5)[0], 'risposto «Sì»')
    ok(!esiste?(nome), 'con «Sì» il percorso sparisce')
  ensure
    togli_percorso(nome)
  end
end

# ── Video ────────────────────────────────────────────────────────────
if parti.include?('video')
  nome = "Collaudo Claude video #{Time.now.strftime('%H%M%S')}"
  dir = File.join(Dir.tmpdir, "dagawasd_collaudo_#{Process.pid}")
  FileUtils.mkdir_p(dir)
  win = dir.tr('/', '\\')
  ok(crea_percorso(nome), "percorso di prova «#{nome}» creato")
  # Con SketchUp a icona la vista non si ridisegna e il video resta fermo
  # al primo fotogramma: per il tempo dell'esportazione la si rimostra.
  a_icona = fin('mostra', 'principale')[1].include?('era a icona')
  nota 'SketchUp era a icona: rimostrato senza fuoco per il video' if a_icona
  begin
    comando_percorso('frames', nome)
    if STATO['formato'] == 'png'
      raise StopIteration unless ok(aspetta_finestra(STATO['cartella'], 10), 'PNG: compare la scelta della cartella')
      fin('scrivi', STATO['cartella'], '=1152', win)          # casella «Cartella:»
      ok(fin('premi', STATO['cartella'], '=1')[0], "PNG: scelta #{win}")
    else
      raise StopIteration unless ok(aspetta_finestra(STATO['salva'], 10), 'AVI: compare la finestra Salva')
      ok(fin('scrivi', STATO['salva'], '=1001', "#{win}\\collaudo.avi")[0], 'AVI: nome del file scritto')   # solo \: con / Windows lo rifiuta
      ok(fin('premi', STATO['salva'], '=1')[0], 'AVI: premuto Salva')
    end
    raise StopIteration unless ok(aspetta_finestra(STATO['attesa'], 15), 'si apre la finestra del video')
    t0 = Time.now
    fatto = aspetta(600) { su('DagaWASD::FPSWalk.instance_variable_get(:@path_job).nil?') }
    ok(fatto, "esportazione finita (#{(Time.now - t0).round} s)")
    file = Dir.glob(File.join(dir, '**', '*.{avi,png}'))
    peso = file.sum { |f| File.size(f) }
    ok(!file.empty? && peso > 10_000, "file scritti: #{file.size}, #{(peso / 1024.0).round} KB")
    ok(fin('chiudi', STATO['attesa'])[0] && fin('sparita', STATO['attesa'], 5)[0], 'finestra del video chiusa')
  rescue StopIteration
    nota 'video: il resto è saltato'
  ensure
    # interrotto a metà: DagaWASD lo dice con un avviso, che non deve restare aperto
    if (su('DagaWASD::FPSWalk.path_busy?') rescue false)
      su('DagaWASD::FPSWalk.path_abort; nil')
      fin('premi', 'avviso', 'OK') if fin('aspetta', 'avviso', 3)[0]
    end
    togli_percorso(nome)
    FileUtils.rm_rf(dir)
    fin('icona', 'principale') if a_icona
  end
end

puts
puts $falliti.zero? ? 'COLLAUDO RIUSCITO' : "#{$falliti} CONTROLLI FALLITI"
exit($falliti.zero? ? 0 : 1)
