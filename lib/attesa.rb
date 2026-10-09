# DagaWASD — Attesa del video: mentre path.rb scrive i fotogrammi, una
# finestra (attesa.html) con un personaggio e un fumetto: avanzamento,
# statistiche del percorso, del video e del modello, e battute che ne derivano.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # La pagina chiede i dati con ready() quando è caricata: fino ad
    # allora avanzamento e finale restano nel lavoro e partono con lei.
    # Ruby è fermo dentro write_image per ~0,8 s alla volta (PATH_BATCH):
    # l'avanzamento arriva fra un blocco e l'altro, l'orologio e le
    # animazioni della pagina girano da soli nel processo del browser.
    # Il personaggio: attesa/personaggio.(webp|gif|png), se c'è; se no
    # la pagina ne disegna uno suo.
    # ══════════════════════════════════════════════════════════════
    ATTESA_FILE = File.join(PLUGIN_DIR, 'attesa.html').freeze
    ATTESA_DIR  = File.join(PLUGIN_DIR, 'attesa').freeze
    ATTESA_IMGS = %w[personaggio.webp personaggio.gif personaggio.png].freeze
    ATTESA_STEP = 0.75     # m per passo, per contare i passi
    ATTESA_HYST = 0.15     # m: salite e discese più piccole sono il dondolio della testa

    def self.attesa_open(job)
      attesa_close
      # Senza la pagina una finestra bianca: meglio il messagebox finale di prima
      return log_error(__method__, IOError.new("manca #{ATTESA_FILE}")) unless File.exist?(ATTESA_FILE)
      job[:att] = { stats: attesa_stats(job), t0: Process.clock_gettime(Process::CLOCK_MONOTONIC), ready: false }
      d = UI::HtmlDialog.new(
        dialog_title:    "DagaWASD — #{t('att.title')}",
        preferences_key: 'DagaWASDAttesa',
        width:  700, height: 520,
        min_width: 520, min_height: 440,
        resizable: true
      )
      d.set_file(ATTESA_FILE)
      d.add_action_callback('ready') { |_ctx, _| attesa_ready(job) }
      d.add_action_callback('stop')  { |_ctx, _| path_abort if @path_job.equal?(job) }
      d.add_action_callback('open')  { |_ctx, what| attesa_open_result(job, what.to_s) }
      d.add_action_callback('close') { |_ctx, _| UI.start_timer(0, false) { attesa_close } }
      # Chiusa con la X durante l'esportazione: si ferma anche lei
      d.set_on_closed do
        @attesa = nil if @attesa.equal?(d)
        path_abort if @path_job.equal?(job)
      end
      @attesa = d
      job[:att][:dialog] = d
      d.show
    rescue => fps_err
      log_error(__method__, fps_err)
      @attesa = nil
    end

    def self.attesa_close
      d = @attesa or return
      @attesa = nil
      d.close if d.visible?
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.attesa_dialog(job)
      a = job[:att] or return nil
      d = a[:dialog]
      d && @attesa.equal?(d) ? d : nil
    end

    def self.attesa_ready(job)
      d = attesa_dialog(job) or return
      a = job[:att]
      a[:ready] = true
      load_lang
      look = { 'theme' => cf('ui_theme'), 'accent' => cf('ui_accent'), 'highlight' => cf('ui_highlight'),
               'danger' => cf('ui_danger') }
      look.merge!('bg' => cf('ui_bg'), 'text' => cf('ui_text')) if cf('ui_custom_colors')
      payload = {
        'strings' => @lang.select { |k, _| k.start_with?('att.', 'fun.') },
        'lang'    => @lang_code,
        'rtl'     => @lang_rtl,
        'look'    => look,
        'image'   => ATTESA_IMGS.find { |f| File.exist?(File.join(ATTESA_DIR, f)) },
        'stats'   => a[:stats]
      }
      d.execute_script("init(#{js_json(payload)})")
      d.execute_script("progress(#{js_json(attesa_progress_data(job))})")
      d.execute_script("finish(#{js_json(a[:fin])})") if a[:fin]
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Dopo ogni blocco di fotogrammi
    def self.attesa_progress(job)
      d = attesa_dialog(job) or return
      return unless job[:att][:ready]
      d.execute_script("progress(#{js_json(attesa_progress_data(job))})")
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.attesa_progress_data(job)
      { 'k' => job[:k], 'total' => job[:total], 'bytes' => job[:bytes].to_i,
        'el' => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - job[:att][:t0]).round(2) }
    end

    # Fine dell'esportazione. Ritorna true se il finale lo mostra la
    # finestra (allora niente messagebox), false se è stata chiusa.
    # info: n (fotogrammi), time, mb, file o dir.
    def self.attesa_finish(job, why, info)
      d = attesa_dialog(job) or return false
      a = job[:att]
      a[:fin] = info.merge('why' => why.to_s, 'el' => attesa_progress_data(job)['el'])
      if a[:ready]
        d.execute_script("progress(#{js_json(attesa_progress_data(job))})")
        d.execute_script("finish(#{js_json(a[:fin])})")
      end
      d.bring_to_front
      true
    rescue => fps_err
      log_error(__method__, fps_err)
      false
    end

    # "Guarda il video" / "Apri la cartella": con il programma predefinito di Windows
    def self.attesa_open_result(job, what)
      fin = job[:att] && job[:att][:fin] or return
      target = what == 'file' ? fin['file'] : (fin['dir'] || (fin['file'] && File.dirname(fin['file'])))
      return unless target && File.exist?(target)
      UI.openURL("file:///#{target.tr('\\', '/')}")
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # ── Statistiche: una volta, all'inizio ────────────────────────
    # Percorso dai fotogrammi già levigati (niente dondolio): distanza,
    # salite e discese oltre ATTESA_HYST, quanto ha girato lo sguardo.
    def self.attesa_stats(job)
      fr = job[:frames]
      dist = 0.0; up = 0.0; down = 0.0; turn = 0.0
      hyst = ATTESA_HYST * M_TO_IN
      anchor = fr.first[2]
      yaw = Math.atan2(fr.first[4], fr.first[3])
      fr.each_cons(2) do |a, b|
        dx = b[0] - a[0]; dy = b[1] - a[1]; dz = b[2] - a[2]
        dist += Math.sqrt(dx * dx + dy * dy + dz * dz)
        if b[2] - anchor > hyst
          up += b[2] - anchor; anchor = b[2]
        elsif anchor - b[2] > hyst
          down += anchor - b[2]; anchor = b[2]
        end
        next if b[3].abs + b[4].abs < 1e-3             # sguardo dritto in alto o in basso: niente imbardata
        y = Math.atan2(b[4], b[3])
        turn += ((y - yaw + Math::PI) % PI2 - Math::PI).abs
        yaw = y
      end
      m = dist * IN_TO_M
      dur = job[:dur].to_f
      attesa_model_stats.merge(
        'name'    => job[:name].to_s,
        'm'       => m.round(1),
        'up'      => (up * IN_TO_M).round(1),
        'down'    => (down * IN_TO_M).round(1),
        'turn'    => (turn / DEG).round,
        'rec'     => dur.round(1),
        'kmh'     => dur > 0 ? (m / dur * 3.6).round(1) : 0,
        'speed'   => job[:speed].to_f,
        'fps'     => job[:fps],
        'total'   => job[:total],
        'vid'     => (job[:total].to_f / job[:fps]).round(1),
        'w'       => job[:w], 'h' => job[:h],
        'format'  => job[:avi] ? 'avi' : 'png'
      )
    end

    # Facce: quelle del modello più quelle di ogni definizione una volta
    # sola (un componente ripetuto conta come uno). Tutto il modello, anche
    # se c'è un gruppo aperto: da qui model.entities e non active_entities.
    def self.attesa_model_stats(model = Sketchup.active_model)
      faces = model.entities.grep(Sketchup::Face).size # rubocop:disable SketchupSuggestions/ModelEntities
      comps = 0
      model.definitions.each do |df|
        next if df.image?
        faces += df.entities.grep(Sketchup::Face).size
        comps += 1 unless df.group?
      end
      title = model.title.to_s
      { 'model'   => title,
        'faces'   => faces,
        'mats'    => model.materials.size,
        'comps'   => comps,
        'scenes'  => model.pages.size,
        'weather' => cf('precip_kind').to_s != 'none' || cf('cloud_enabled') == true }
    rescue => fps_err
      log_error(__method__, fps_err)
      {}
    end

  end
end
