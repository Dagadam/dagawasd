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

    VERSION = '1.1.0' unless defined?(VERSION)

    unless defined?(EXTENSION)

      # __FILE__ può arrivare con la codifica sbagliata se il percorso ha
      # lettere accentate (nome utente di Windows): si dichiara UTF-8.
      dir = File.dirname(__FILE__.dup.force_encoding('UTF-8'))
      EXTENSION = SketchupExtension.new('DagaWASD', File.join(dir, 'dagawasd', 'main'))
      EXTENSION.description =
        'Cammina nel modello in prima persona con WASD e mouse (o gamepad): ' \
        'inerzia, salto, scale e pendenze, fisica degli oggetti secondo il ' \
        'materiale (calcia, afferra, lancia, spingi). Cielo con sole, luna e ' \
        'stelle, pioggia, neve, nuvole e temporali, percorsi registrati ed ' \
        'esportati in video. Solo per SketchUp su Windows.'
      # il pacchetto per l'Extension Warehouse non ha il ponte (lib/bridge.rb)
      ponte = File.join(dir, 'dagawasd', 'lib', 'bridge')
      if File.exist?("#{ponte}.rb") || File.exist?("#{ponte}.rbe")
        EXTENSION.description += ' Ponte facoltativo per Claude Code.'
      end
      EXTENSION.version   = VERSION
      EXTENSION.creator   = 'Dagadam'
      EXTENSION.copyright = '© 2026 Dagadam'

      Sketchup.register_extension(EXTENSION, true)

    end

  end
end
