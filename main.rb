require 'sketchup'
require 'json'
require 'set'

# ══════════════════════════════════════════════════════════════════
# DagaWASD — caricatore
# Il codice sta in lib/, un file per argomento; tutti riaprono lo stesso
# modulo DagaWASD::FPSWalk. L'ordine conta solo per config (costanti usate al
# caricamento dagli altri file); i metodi si risolvono quando vengono
# chiamati, quindi un file può usare metodi definiti in uno successivo.
#
#   config     costanti, DEFAULT, stato       i18n       lingue
#   settings   settings.json, tasti, log      input      Win32, hook tastiera
#   camera     camera e zoom                  raycast    raggi
#   player     pavimento, muri, gradini       materials  materiali, massa
#   geometry   forma reale degli oggetti      support    appoggio, ribaltamento
#   bodies     registrazione corpi, impulsi   collisions urti fra oggetti
#   held       oggetto in mano                physics    passo di simulazione
#   actions    aziona, calcia, afferra        lifecycle  avvio e arresto
#   tick       ciclo principale               tool       strumento e mirino
#   panel      pannello impostazioni          bridge     ponte per Claude
#   sky        sole, luna, stelle, cielo      precip     pioggia e neve
#   clouds     nuvole                         snowcover  neve al suolo
#   sound      passi, canale del tuono        gamepad    controller XInput
#   avi        video AVI Motion JPEG          path       percorsi registrati
#   ui         menu e barra
# ══════════════════════════════════════════════════════════════════

# Già caricato (es. `load` ripetuto dalla console): non registrare di
# nuovo menu, barra e timer.
unless defined?(DagaWASD::FPSWalk::PLUGIN_DIR)
  %w[
    config i18n settings input camera raycast player materials geometry support
    bodies collisions held physics actions lifecycle tick tool panel bridge sky precip clouds snowcover sound avi path
    gamepad ui
  ].each do |f|
    path = File.join(__dir__.dup.force_encoding('UTF-8'), 'lib', f)   # percorsi con lettere accentate
    # Il ponte è facoltativo: il pacchetto per l'Extension Warehouse non lo ha.
    next if f == 'bridge' && !File.exist?("#{path}.rb") && !File.exist?("#{path}.rbe")
    # Sketchup.require e non require: con la firma i file possono diventare .rbe cifrati
    Sketchup.require(path)
  end

  begin
    DagaWASD::FPSWalk.register_ui
    DagaWASD::FPSWalk.start_hotkey_poller
    DagaWASD::FPSWalk.bridge_sync if DagaWASD::FPSWalk.bridge?   # ponte per Claude, se c'è ed è acceso
    DagaWASD::FPSWalk.sky_sync          # cielo animato, se acceso
    DagaWASD::FPSWalk.precip_sync       # pioggia e neve, se accese
    DagaWASD::FPSWalk.cloud_sync        # nuvole, se accese
    DagaWASD::FPSWalk.snow_sync         # neve al suolo
    DagaWASD::FPSWalk.step_warm_start   # suoni dei passi pronti in sottofondo
    DagaWASD::FPSWalk.path_observe      # elenco dei percorsi nel pannello: segue il modello
  rescue => e
    DagaWASD::FPSWalk.log_error(:register_ui, e)
    Sketchup.status_text = "DagaWASD — register_ui error: #{e.message}"
  end
end
