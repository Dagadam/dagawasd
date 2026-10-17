# DagaWASD — Schermate per la scheda dell'Extension Warehouse, dal modello
# aperto: per ogni inquadratura una scena del modello (solo la camera), una
# preimpostazione del meteo (weather_preset, come i pulsanti del pannello) e
# la cattura della vista 3D con cielo, nuvole e pioggia (tools/finestre.ps1:
# write_image salta le Overlay). In più il pannello.
#
#   ruby -E UTF-8 tools/schermate.rb [cartella] [larghezza altezza] [scena ...]
#
# Default: pubblicazione/schermate, 1920x1080. La vista arriva al massimo
# alla misura dello schermo (Windows non allarga una finestra oltre): per
# 1920x1080 serve un monitor almeno così. Le inquadrature sono le scene
# nominate, una per immagine nell'ordine di SHOTS; senza nomi, le prime
# scene del modello; senza scene, la camera attuale.
#
# Alla fine impostazioni, camera, stile e ombre tornano com'erano (le
# impostazioni passano da settings.json: per qualche secondo lì ci sono
# quelle della preimpostazione). Serve il ponte acceso e FPS spento.
$stdout.sync = true   # i risultati si vedono subito anche in una pipe
require 'json'
require 'net/http'
require 'open3'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
FIN  = File.join(ROOT, 'tools', 'finestre.ps1')
INFO = File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'bridge.json')
DIR  = File.expand_path(ARGV[0] || File.join(ROOT, 'pubblicazione', 'schermate'))
W, H = (ARGV[1] || 1920).to_i, (ARGV[2] || 1080).to_i

SCELTE = ARGV[3..] || []

# file, preimpostazione del meteo, attesa (s) perché il meteo si assesti.
# Il tramonto è arancio solo vicino all'orizzonte: va bene solo con
# un'inquadratura aperta, per questo qui non c'è.
SHOTS = [
  ['01_giorno_nuvole',  'clear',  4],
  ['02_notte_stellata', 'starry', 3],
  ['03_alba',           'dawn',   4],
  ['04_temporale',      'storm',  5],
  ['05_giorno',         'clear',  3]
].freeze

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
# Le catture passano da tools/finestre.ps1: serve il permesso del pannello
IMP = (JSON.parse(File.read(File.join(ENV['APPDATA'] || Dir.home, 'DagaWASD', 'settings.json'), encoding: 'UTF-8')) rescue {})
abort 'Finestre e tasti spenti: accendili in DagaWASD (Sistema › Ponte Claude › Finestre e tasti)' unless IMP['bridge_windows']
FileUtils.mkdir_p(DIR)

# Stato da rimettere: impostazioni (copia profonda), camera. Stile e ombre
# li rimette DagaWASD quando il cielo si spegne (sky_restore).
abort 'Modalità FPS attiva: esci prima (Esc)' if su('DagaWASD::FPSWalk.instance_variable_get(:@active)')
su(<<~'RUBY')
  m = DagaWASD::FPSWalk
  cfg = m.instance_variable_get(:@cfg)
  c = Sketchup.active_model.active_view.camera
  ro = Sketchup.active_model.rendering_options
  $dagawasd_schermate = { cfg: Marshal.load(Marshal.dump(cfg)), assi: ro['DisplaySketchAxes'],
                          cam: [c.eye, c.target, c.up, c.perspective?, c.fov, (c.height rescue nil)] }
  cfg['bridge_orbit'] = false          # la camera non deve inseguire nulla fra un invio e l'altro
  ro['DisplaySketchAxes'] = false      # niente assi rosso, verde e blu nelle immagini
  nil
RUBY

fatte = []
begin
  scene = su('Sketchup.active_model.pages.map(&:name)')
  (SCELTE - scene).each { |n| puts "  (scena «#{n}» assente: saltata)" }
  usate = SCELTE.empty? ? scene : SCELTE & scene
  SHOTS.each_with_index do |(file, preset, attesa), i|
    if (scena = usate[i])
      su("p = Sketchup.active_model.pages[#{scena.inspect}]; Sketchup.active_model.active_view.camera = p.camera; nil")
      puts "  #{file}: scena «#{scena}»"
    else
      puts "  #{file}: camera attuale (nessuna scena per questa immagine)"
    end
    su("DagaWASD::FPSWalk.weather_preset(#{preset.inspect}); DagaWASD::FPSWalk.instance_variable_get(:@cfg)['bridge_orbit'] = false; nil")
    sleep attesa
    out = File.join(DIR, "#{file}.png").tr('/', '\\')
    ok, msg = fin('schermo', out, 'vista', W, H)
    puts "#{ok ? 'OK  ' : 'ERR '} #{file}: #{msg}"
    fatte << out if ok
  end

  # Il pannello in inglese (la scheda è in inglese), sulla scheda Meteo, senza
  # il segnale degli errori del registro, per un momento nell'angolo in alto
  # a sinistra: la pagina web si dipinge solo dove la finestra sta sullo
  # schermo. Riaperto da capo, perché il titolo prende la lingua all'apertura.
  # show_panel rilegge settings.json: la lingua va salvata.
  su(<<~'RUBY')
    m = DagaWASD::FPSWalk
    d = m.instance_variable_get(:@dialog)
    $dagawasd_schermate[:pannello] = d&.visible? ? d.get_position : nil
    d.close if d&.visible?
    m.instance_variable_get(:@cfg)['language'] = 'en'
    m.save_cfg
    m.show_panel
    m.instance_variable_get(:@dialog).set_position(0, 0)
    nil
  RUBY
  sleep 3
  su(<<~'RUBY')
    DagaWASD::FPSWalk.instance_variable_get(:@dialog).execute_script("window.__schedaPrima = curTab; window.__sottoPrima = curSub['weather']; selTab('weather'); selSub('presets'); setLogCount(0)")
    nil
  RUBY
  sleep 1
  titolo = su("\"DagaWASD — \#{DagaWASD::FPSWalk.t('menu.settings').sub(/…\\z/, '')}\"")
  out = File.join(DIR, '06_pannello.png').tr('/', '\\')
  ok, msg = fin('schermo', out, titolo)
  puts "#{ok ? 'OK  ' : 'ERR '} 06_pannello: #{msg}"
  fatte << out if ok
  su(<<~'RUBY')   # la scheda di prima: il pannello la ricorda per la prossima apertura
    d = DagaWASD::FPSWalk.instance_variable_get(:@dialog)
    d.execute_script("if (window.__sottoPrima) selSub(window.__sottoPrima); if (window.__schedaPrima) selTab(window.__schedaPrima)")
    nil
  RUBY
  sleep 0.5
ensure
  su(<<~'RUBY')
    m = DagaWASD::FPSWalk
    s = $dagawasd_schermate
    cfg = m.instance_variable_get(:@cfg)
    rate = cfg['tick_rate']
    cfg.replace(s[:cfg])
    m.apply_cfg_change(rate)             # salva e rimette cielo, nuvole, pioggia (e stile e ombre)
    m.push_panel_state
    eye, target, up, persp, fov, height = s[:cam]
    cam = Sketchup::Camera.new(eye, target, up, persp, fov)
    cam.height = height if !persp && height
    Sketchup.active_model.active_view.camera = cam
    Sketchup.active_model.rendering_options['DisplaySketchAxes'] = s[:assi]
    if s.key?(:pannello)                 # riaperto nella lingua di prima, dov'era; o chiuso
      d = m.instance_variable_get(:@dialog)
      d.close if d&.visible?
      if (xy = s[:pannello])
        m.show_panel
        m.instance_variable_get(:@dialog).set_position(*xy)
      end
    end
    $dagawasd_schermate = nil
    nil
  RUBY
  puts 'Impostazioni, camera, stile e ombre rimessi com\'erano.'
end

piccole = fatte.reject { |f| f.include?('pannello') }.select do |f|
  w, h = File.binread(f, 24)[16, 8].unpack('N2')   # intestazione PNG: larghezza e altezza
  w != W || h != H
end
puts "Attenzione: #{piccole.size} immagini non sono #{W}x#{H} (schermo più piccolo): rifalle col monitor grande." unless piccole.empty?
