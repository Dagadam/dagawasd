# DagaWASD — settings.json, tasti personalizzati, riga di stato e registro errori.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
require 'fileutils'

module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Impostazioni
    # ══════════════════════════════════════════════════════════════
    # I test possono usare un altro file (@settings_file) invece di quello vero.
    def self.settings_path; @settings_file || SETTINGS_FILE; end

    # Un settings.json illeggibile non deve impedire l'avvio (senza, il menu
    # e la barra degli strumenti non comparirebbero): si parte dai default e
    # il file rovinato viene messo da parte come settings.bad.json.
    def self.load_cfg
      adopt_old_settings unless @settings_file
      data = {}
      if File.exist?(settings_path)
        begin
          data = JSON.parse(File.read(settings_path, encoding: 'UTF-8'))
          raise JSON::ParserError, "settings.json: #{data.class} invece di un oggetto" unless data.is_a?(Hash)
        rescue => fps_err
          log_error(__method__, fps_err)
          data = {}
          begin; File.rename(settings_path, settings_path.sub(/\.json\z/, '.bad.json')); rescue SystemCallError; end
        end
      end
      @cfg = DEFAULT.merge(data)
      # Migrazione: l'attrito oggetti era un damping 1/s (0..20), ora è un
      # coefficiente di Coulomb μ (0..1.5). Valori legacy vengono riscalati.
      f = @cfg['obj_friction'].to_f
      @cfg['obj_friction'] = (f / 6.0).clamp(0.05, 1.5) if f > 1.5
      refresh_keys
      sanitize_look
      sanitize_pairs
      @cfg
    end

    # Fino alla 2.0 settings.json stava nella cartella dell'estensione: se in
    # %APPDATA%\DagaWASD non c'è ancora, si parte da una copia di quello.
    # L'originale resta dov'è (tornando a una versione vecchia c'è ancora).
    def self.adopt_old_settings
      return if File.exist?(SETTINGS_FILE) || !File.exist?(OLD_SETTINGS_FILE)
      FileUtils.mkdir_p(USER_DIR)
      FileUtils.cp(OLD_SETTINGS_FILE, SETTINGS_FILE)
    rescue => fps_err; log_error(__method__, fps_err); end

    # Minimo oltre il massimo: il minimo scende al massimo.
    def self.sanitize_pairs
      MIN_MAX_PAIRS.each do |lo, hi|
        a = @cfg[lo]; b = @cfg[hi]
        @cfg[lo] = b if a.is_a?(Numeric) && b.is_a?(Numeric) && a > b
      end
    end

    # ── Aspetto ─────────────────────────────────────────────────────
    # Colori non validi o scelte sconosciute tornano al predefinito:
    # il pannello li trasforma in CSS e il mirino in colori di disegno.
    def self.sanitize_look
      DEFAULT.each do |k, d|
        next unless d.is_a?(String)
        choices = LOOK_CHOICES[k]
        next unless choices || d.start_with?('#')
        v  = @cfg[k]
        ok = choices ? choices.include?(v) : v.is_a?(String) && v.match?(/\A#\h{6}\z/)
        @cfg[k] = ok ? (choices ? v : v.downcase) : d
      end
    end

    # '#rrggbb' → [r, g, b, a] per view.drawing_color (alpha 0–1)
    def self.rgba(k, alpha = 1.0)
      h = cf(k).to_s
      h = DEFAULT[k] unless h.match?(/\A#\h{6}\z/)
      [h[1, 2].hex, h[3, 2].hex, h[5, 2].hex, (alpha.to_f.clamp(0.0, 1.0) * 255).round]
    end

    # ── Tasti personalizzati ────────────────────────────────────────
    # Valori non validi, riservati o doppi tornano al predefinito; se anche
    # così due azioni finiscono sullo stesso tasto, si torna ai predefiniti.
    def self.sanitize_keys(h)
      h = {} unless h.is_a?(Hash)
      out = {}
      DEFAULT_KEYS.each do |act, dflt|
        v = h[act]
        v = v.to_i if v.is_a?(String) && v =~ /\A\d+\z/
        ok = v.is_a?(Integer) && v.between?(1, 254) && !RESERVED_KEYS.include?(v) &&
             !out.value?(v)
        out[act] = ok ? v : dflt
      end
      out.values.uniq.size == out.size ? out : DEFAULT_KEYS.dup
    end

    def self.sanitize_key_labels(h)
      return {} unless h.is_a?(Hash)
      h.select { |a, l| DEFAULT_KEYS.key?(a) && l.is_a?(String) && !l.strip.empty? && l.size <= 12 }
    end

    # Ricalcola la mappa dei tasti e l'insieme di quelli che l'hook
    # inghiotte in modalità FPS. Shift e Ctrl non si inghiottono mai
    # (sono modificatori e SketchUp non reagisce se premuti da soli).
    def self.refresh_keys
      @cfg['keys']       = sanitize_keys(@cfg['keys'])
      @cfg['key_labels'] = sanitize_key_labels(@cfg['key_labels'])
      @kb = @cfg['keys']
      sw = Set.new([VK_ESC, VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN])
      @kb.each_value do |vk|
        next if vk == VK_SHIFT || vk == VK_CONTROL
        vk == VK_ALT ? sw.merge([VK_ALT, VK_LALT, VK_RALT]) : sw << vk
      end
      @swallow = sw
    end

    def self.kb(act)
      refresh_keys unless @kb
      @kb[act]
    end

    # Il tasto dell'azione è premuto? Shift/Ctrl letti dallo stato globale
    # (non passano dall'hook come tasti inghiottiti), Alt in tutte le varianti.
    # Vale anche il pulsante del gamepad della stessa azione (lib/gamepad.rb).
    def self.pressed?(act)
      vk = kb(act)
      down = case vk
             when VK_SHIFT   then shift?
             when VK_CONTROL then async_down?(VK_CONTROL)
             when VK_ALT     then alt?
             else key?(vk)
             end
      down || pad_pressed?(act)
    end

    # vk (dall'hook, quindi con Shift/Ctrl/Alt sinistro o destro) è il tasto di act?
    def self.key_of?(vk, act)
      b = kb(act)
      vk == b || GENERIC_VK[vk] == b
    end

    def self.key_name(vk)
      return KEY_NAMES[vk] if KEY_NAMES[vk]
      return vk.chr if (0x30..0x39).cover?(vk) || (0x41..0x5A).cover?(vk)
      return "F#{vk - 0x6F}" if (0x70..0x87).cover?(vk)
      return "Num#{vk - 0x60}" if (0x60..0x69).cover?(vk)
      format('#%02X', vk)
    end

    def self.key_label(act)
      l = (@cfg['key_labels'] || {})[act]
      l.is_a?(String) && !l.empty? ? l : key_name(kb(act))
    end

    # Riga di stato in modalità FPS: rt.hud con i tasti effettivi. Si
    # sostituisce solo il nome dei tasti cambiati, così i nomi tradotti
    # di quelli predefiniti ("Leertaste", "Mayús"…) restano.
    def self.hud_text
      s = t('rt.hud')
      parts = s.split(' · ')
      return s unless parts.size == HUD_ACTS.size
      mv = %w[forward left back right]   # ordine di "WASD"
      if mv.any? { |a| kb(a) != DEFAULT_KEYS[a] }
        parts[0] = parts[0].sub('WASD') { mv.map { |a| key_label(a) }.join }
      end
      HUD_ACTS.each_with_index do |a, i|
        next unless a && kb(a) != DEFAULT_KEYS[a]
        parts[i] = parts[i].sub(/\A\S+/) { key_label(a) }
      end
      parts.join(' · ')
    end

    # Prima su un file temporaneo, poi lo scambio: se SketchUp si chiude a
    # metà scrittura, settings.json resta quello di prima invece che troncato.
    def self.save_cfg
      tmp = "#{settings_path}.tmp"
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(tmp, JSON.pretty_generate(@cfg), encoding: 'UTF-8')
      File.rename(tmp, settings_path)
    rescue => e
      log_error(__method__, e)
      Sketchup.status_text = "DagaWASD: save error — #{e.message}"
    end

    # ── Registro errori ─────────────────────────────────────────────
    # Gli errori interni non devono interrompere la simulazione, ma
    # nemmeno sparire: ognuno viene scritto una volta per sessione in
    # dagawasd.log (con le prime righe dello stack) e segnalato nella
    # barra di stato. Il registro non supera LOG_MAX: oltre riparte da
    # zero. Questo metodo non deve mai sollevare a sua volta.
    # I test possono deviare il registro (@log_file) e zittire la console
    # (@log_quiet), così non scrivono nella cartella del progetto.
    def self.log_error(where, err)
      @logged ||= {}
      sig = "#{where}|#{err.class}|#{err.message}"
      return if @logged[sig]
      @logged[sig] = true
      trace = (err.backtrace || []).first(4).map { |l| "    #{l}" }.join("\n")
      line  = "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} [#{where}] #{err.class}: #{err.message}\n#{trace}\n"
      path  = log_path
      mode  = File.exist?(path) && File.size(path) > LOG_MAX ? 'w' : 'a'
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, mode) { |f| f.write(line) }
      puts "DagaWASD [#{where}] #{err.class}: #{err.message}" unless @log_quiet
      Sketchup.status_text = "DagaWASD — #{t('rt.err_logged')}"
      # pannello aperto: aggiorna subito il contatore ⚠ nella barra in alto
      @dialog.execute_script("setLogCount(#{log_count})") if @dialog && @dialog.visible?
    rescue Exception
      nil
    end

    def self.log_path; @log_file || LOG_FILE; end

    # Contenuto del registro per il pannello (UTF-8 valido anche se il file
    # contiene byte strani: un messaggio di errore può riportare di tutto).
    def self.read_log
      path = log_path
      txt  = File.exist?(path) ? File.binread(path).force_encoding('UTF-8').scrub('?') : ''
      { 'path' => path, 'text' => txt }
    rescue => fps_err
      { 'path' => log_path, 'text' => "#{fps_err.class}: #{fps_err.message}" }
    end

    # Voci del registro: ogni voce comincia con data e ora.
    def self.log_count
      read_log['text'].scan(/^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \[/).size
    end

    # Svuota il registro; gli errori già visti potranno essere riscritti.
    def self.clear_log
      File.delete(log_path) if File.exist?(log_path)
      @logged = {}
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.cf(k); @cfg[k]; end

  end
end
