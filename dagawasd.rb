require 'sketchup.rb'
require 'extensions.rb'

# ══════════════════════════════════════════════════════════════════
# DagaWASD — loader dell'estensione
# Va nella radice della cartella Plugins, accanto alla cartella
# "dagawasd" che contiene main.rb, panel.html, lib, lang e icons.
#
# VERSION è l'unico posto dove sta il numero di versione: tools/crea_rbz.rb
# lo legge da qui e pretende la sezione corrispondente in CHANGELOG.md.
# ══════════════════════════════════════════════════════════════════
module DagaWASD
  module FPSWalkLoader

    VERSION = '2.1.0' unless defined?(VERSION)

    unless defined?(EXTENSION)

      EXTENSION = SketchupExtension.new(
        'DagaWASD',
        File.join(File.dirname(__FILE__), 'dagawasd', 'main')
      )
      EXTENSION.description =
        'Cammina nel modello in prima persona con WASD e mouse (o gamepad): ' \
        'inerzia, salto, scale e pendenze, fisica degli oggetti secondo il ' \
        'materiale (calcia, afferra, lancia, spingi). Cielo con sole, luna e ' \
        'stelle, pioggia, neve, nuvole e temporali, suoni dei passi, percorsi ' \
        'registrati ed esportati in video. Ponte facoltativo per Claude Code.'
      EXTENSION.version   = VERSION
      EXTENSION.creator   = 'Dagadam'
      EXTENSION.copyright = '2026'

      Sketchup.register_extension(EXTENSION, true)

    end

  end
end
