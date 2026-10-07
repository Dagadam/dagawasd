require 'sketchup.rb'
require 'extensions.rb'

# ══════════════════════════════════════════════════════════════════
# DagaWASD — loader dell'estensione
# Va nella radice della cartella Plugins, accanto alla cartella
# "dagawasd" che contiene main.rb, panel.html, settings.json e icons.
# ══════════════════════════════════════════════════════════════════
module DagaWASD
  module FPSWalkLoader

    unless defined?(EXTENSION)

      EXTENSION = SketchupExtension.new(
        'DagaWASD',
        File.join(File.dirname(__FILE__), 'dagawasd', 'main')
      )
      EXTENSION.description =
        'Navigazione in prima persona con WASD + mouse look: movimento con ' \
        'inerzia, salto variabile, scavalcamento gradini, pendenze, e fisica ' \
        'a corpo rigido degli oggetti (massa dai materiali, urti mass-based, ' \
        'ribaltamento, calcia/afferra/lancia).'
      EXTENSION.version   = '2.0.0'
      EXTENSION.creator   = 'Dagadam'
      EXTENSION.copyright = '2026'

      Sketchup.register_extension(EXTENSION, true)

    end

  end
end
