# DagaWASD — Lingue: dizionari lang/*.json, testo localizzato, JSON per il pannello.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Localizzazione
    # I testi stanno in lang/<codice>.json (uno per lingua, chiave→testo)
    # e sono condivisi fra il pannello HTML e i messaggi della barra di
    # stato. lang/index.json elenca le lingue mostrate nel selettore.
    # ══════════════════════════════════════════════════════════════

    def self.read_json(path)
      return {} unless File.exist?(path)
      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      data.is_a?(Hash) ? data : {}
    rescue => fps_err
      log_error(__method__, fps_err)
      {}
    end

    def self.lang_index
      @lang_index ||= (read_json(File.join(LANG_DIR, 'index.json'))['languages'] || [])
    end

    def self.lang_codes
      @lang_codes ||= lang_index.map { |l| l['code'] }
    end

    # 'auto' → lingua dell'interfaccia SketchUp, con ripiego su inglese.
    def self.resolve_lang(code)
      code = code.to_s
      unless code.empty? || code == 'auto'
        return code if lang_codes.include?(code)
      end
      loc  = (Sketchup.get_locale.to_s rescue '')
      base = loc.downcase.split(/[-_]/).first.to_s
      # codici storici usati da alcune piattaforme
      base = 'nb' if base == 'no'
      base = 'he' if base == 'iw'
      base = 'id' if base == 'in'
      lang_codes.include?(base) ? base : 'en'
    rescue
      'en'
    end

    def self.load_lang
      @lang_code = resolve_lang(@cfg['language'])
      base  = read_json(File.join(LANG_DIR, 'en.json'))
      @lang = @lang_code == 'en' ? base : base.merge(read_json(File.join(LANG_DIR, "#{@lang_code}.json")))
      @lang_rtl = !!(lang_index.find { |l| l['code'] == @lang_code } || {})['rtl']
      @lang
    end

    # Testo localizzato. Se la chiave manca ritorna la chiave stessa: un
    # buco nella traduzione si vede subito invece di sparire in silenzio.
    def self.t(key)
      load_lang if @lang.nil?
      @lang[key] || key
    end

    # JSON sicuro per execute_script: tutto in \uXXXX, niente problemi di
    # codifica nel passaggio Ruby → CEF.
    def self.js_json(obj)
      JSON.generate(obj, ascii_only: true)
    rescue
      JSON.generate(obj)
    end

  end
end
