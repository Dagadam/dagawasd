# DagaWASD — Esporta video: la finestra (videoexport.html) che viene prima
# dell'esportazione di un percorso (lib/path.rb), il foglio di controllo, e
# quello che serve da Windows (PC sveglio, suono, sospendi o spegni alla fine).
# Il registro accanto al video sta in lib/videolog.rb.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # «Video» di un percorso apre questa finestra invece di partire subito.
    # Due livelli (path_video_level): base e avanzate. Dall'alto:
    #   Fotogrammi   dal x al y (numeri o tempi 3:43), se il video o la
    #                cartella hanno già fotogrammi cosa farne (nuovo, in
    #                coda, rifai questi), Riprendi, la bozza;
    #   Video        formato, misure, meteo; fps, velocità, qualità JPEG;
    #   Audio        un .wav da mettere nel video;
    #   Dove salvare il file o la cartella, con Sfoglia…;
    #   Alla fine    sospendi o spegni il PC; suono, foglio di controllo,
    #                PC sveglio;
    #   Registro     dove sta, l'ultima riga, Apri.
    # Formato, misure, fps, velocità e meteo sono le stesse impostazioni del
    # pannello; le altre stanno solo qui.
    # ══════════════════════════════════════════════════════════════
    VX_FILE   = File.join(PLUGIN_DIR, 'videoexport.html').freeze
    VX_CFG    = %w[path_video_format path_video_size path_video_fps path_video_weather path_speed
                   path_video_quality path_video_sheet path_video_awake path_video_notify path_video_level].freeze
    VX_PANEL  = (%w[f.path_video_format f.path_video_size f.path_video_fps f.path_video_weather f.path_speed lvl.1 lvl.2] +
                 %w[avi png].map { |v| "o.path_video_format.#{v}" } +
                 %w[view hd fhd uhd].map { |v| "o.path_video_size.#{v}" }).freeze
    VX_DRAFT_FPS = 5         # bozza: fotogrammi al secondo (e metà misure)
    VX_AFTER_S   = 120       # s prima di sospendere o spegnere il PC: si può annullare

    # ── Finestra ──────────────────────────────────────────────────
    def self.vx_open(name)
      return t('path.busy') if @path_job
      path_track(name) or return path_track_err(name)
      @vx ||= { targets: {} }
      @vx[:name] = name
      d = @vx[:dialog]
      if d&.visible?
        vx_push
        d.bring_to_front
        return nil
      end
      d = UI::HtmlDialog.new(
        dialog_title:    "DagaWASD — #{t('ve.title')}",
        preferences_key: 'DagaWASDEsporta',
        width: 540, height: 760, min_width: 440, min_height: 520,
        resizable: true
      )
      d.set_file(VX_FILE)
      d.add_action_callback('ready')  { |_c, _| vx_ready }
      d.add_action_callback('set')    { |_c, json| vx_set(json) }
      d.add_action_callback('browse') { |_c, _| vx_browse }
      d.add_action_callback('target') { |_c, s| vx_target_set(s) }
      d.add_action_callback('audio')  { |_c, what| vx_audio(what.to_s) }
      d.add_action_callback('go')     { |_c, json| vx_go(d, json) }
      d.add_action_callback('log')    { |_c, _| vx_open_log }
      d.add_action_callback('cancel') { |_c, _| d.close }
      d.set_on_closed do
        @vx[:dialog] = nil if @vx[:dialog].equal?(d) && !d.visible?
      end
      @vx[:dialog] = d
      d.show
      dialog_on_screen(d)
      nil
    end

    def self.vx_ready
      d = @vx && @vx[:dialog] or return
      load_lang
      look = { 'theme' => cf('ui_theme'), 'accent' => cf('ui_accent'), 'danger' => cf('ui_danger') }
      look.merge!('bg' => cf('ui_bg'), 'text' => cf('ui_text')) if cf('ui_custom_colors')
      strings = @lang.select { |k, _| (k.start_with?('ve.') && k !~ /\Ave\.lg\./) || VX_PANEL.include?(k) }
      d.execute_script("init(#{js_json('strings' => strings, 'lang' => @lang_code, 'rtl' => @lang_rtl, 'look' => look)})")
      vx_push
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.vx_push
      d = @vx && @vx[:dialog] or return
      d.execute_script("show(#{js_json(vx_state)})")
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Finita un'esportazione la finestra (se è aperta) torna libera e
    # rilegge video, cartella e registro
    def self.vx_refresh
      return unless @vx && @vx[:dialog]&.visible?
      UI.start_timer(0, false) { vx_push }
    end

    # Quello che la finestra mostra: numeri del video con le impostazioni di
    # adesso, il file o la cartella, cosa c'è già e da dove si riprenderebbe.
    def self.vx_state
      name = @vx[:name]
      tr = path_track(name)
      return { 'name' => name, 'missing' => true, 'busy' => !@path_job.nil? } unless tr
      fps, total, w, h = path_video_numbers(tr)
      dfps, dtotal, dw, dh = path_video_numbers(tr, true)
      fmt = vx_format
      target = vx_target(name, fmt)
      log = vx_log_of(name, fmt, target)
      model = Sketchup.active_model
      st = { 'name' => name, 'dur' => tr[:dur].to_f, 'total' => total, 'fps' => fps, 'w' => w, 'h' => h,
             'format' => fmt, 'size' => cf('path_video_size').to_s, 'speed' => cf('path_speed').to_f,
             'weather' => cf('path_video_weather') ? true : false, 'target' => vx_win(target),
             'quality' => cf('path_video_quality').to_i, 'sheet' => cf('path_video_sheet') ? true : false,
             'awake' => cf('path_video_awake') ? true : false, 'notify' => cf('path_video_notify') ? true : false,
             'level' => cf('path_video_level').to_i == 2 ? 2 : 1, 'modified' => model.respond_to?(:modified?) && model.modified? ? true : false,
             'draft' => { 'fps' => dfps, 'total' => dtotal, 'w' => dw, 'h' => dh, 'target' => vx_win(vx_draft_target(target, fmt)) },
             'audio' => vx_audio_state,
             'log' => vx_win(log), 'log_exists' => File.file?(log), 'log_last' => vx_log_last(log),
             'busy' => !@path_job.nil? }
      if fmt == 'avi'
        if File.file?(target)
          st['exists'] = true
          info = MjpegAvi.probe(target)
          if info && info[:w] == w && info[:h] == h && info[:fps] == fps
            n = info[:index].size
            first = vx_file_first(log) || 1
            st['avi'] = { 'n' => n, 'a' => first, 'b' => first + n - 1 }
            st['next'] = first + n if n.positive? && first + n <= total
          else
            st['avi_other'] = true
          end
        end
      else
        nums = vx_png_frames(target)
        unless nums.empty?
          st['png'] = { 'n' => nums.size, 'a' => nums.min, 'b' => nums.max }
          st['next'] = nums.max + 1 if nums.max < total
        end
      end
      st
    end

    def self.vx_format; cf('path_video_format') == 'png' ? 'png' : 'avi'; end
    def self.vx_win(path); path.to_s.tr('/', '\\'); end

    # Il registro di un video (accanto, stesso nome) o di una cartella (dentro, col nome del percorso)
    def self.vx_log_of(name, fmt, target)
      fmt == 'avi' ? vx_log_file(target) : File.join(target, "#{path_safe(name)}.log")
    end

    # La bozza: accanto al video, «Video DagaWASD - bozza.avi» (il nome tradotto)
    def self.vx_draft_target(target, fmt)
      base = fmt == 'avi' ? target.to_s.sub(/\.avi\z/i, '') : target.to_s.sub(%r{[\\/]+\z}, '')
      named = format(t('ve.draft_name'), name: File.basename(base))
      File.join(File.dirname(base), path_safe(named)) + (fmt == 'avi' ? '.avi' : '')
    end

    # I numeri delle immagini frame_NNNNN.png già nella cartella
    def self.vx_png_frames(dir)
      return [] unless File.directory?(dir)
      Dir.children(dir).filter_map { |f| f[/\Aframe_(\d+)\.png\z/i, 1]&.to_i }
    rescue SystemCallError
      []
    end

    # Il file o la cartella scelti per quel percorso e formato (finché
    # SketchUp è aperto); se no accanto al modello, col nome del percorso.
    def self.vx_target(name, fmt)
      @vx[:targets][[name, fmt]] ||
        (fmt == 'avi' ? File.join(path_default_dir, "#{path_safe(name)}.avi") : File.join(path_default_dir, path_safe(name)))
    end

    # {chiave: valore} dalla finestra: salvate; quelle del pannello mostrate anche lì.
    def self.vx_set(json)
      c = JSON.parse(json.to_s)
      return unless c.is_a?(Hash)
      c.each do |k, v|
        next unless VX_CFG.include?(k)
        v = case k
            when 'path_video_format' then %w[avi png].include?(v) ? v : nil
            when 'path_video_size' then (PATH_VIDEO_SIZES.keys + ['view']).include?(v) ? v : nil
            when 'path_video_fps' then v.to_i.clamp(10, 60)
            when 'path_speed' then (v.to_f.clamp(0.25, 4.0) * 20).round / 20.0
            when 'path_video_quality' then v.to_i.clamp(50, 100)
            when 'path_video_level' then v.to_i == 2 ? 2 : 1
            else v ? true : false
            end
        @cfg[k] = v unless v.nil?
      end
      save_cfg
      @dialog.execute_script("loadSettings(#{js_json(@cfg.merge('materials' => mat_table))})") if @dialog&.visible?
      vx_push
    rescue JSON::ParserError
      nil
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Sfoglia…: il file del video, o la cartella che conterrà quella delle
    # immagini (col nome del percorso; scelta direttamente se è già lei).
    def self.vx_browse
      name = @vx[:name]
      fmt = vx_format
      cur = vx_target(name, fmt)
      if fmt == 'avi'
        dir = File.dirname(cur)
        file = UI.savepanel(t('path.save_video'), File.directory?(dir) ? dir : path_default_dir, File.basename(cur))
        return unless file
        file = "#{file}.avi" unless file.downcase.end_with?('.avi')
        @vx[:targets][[name, fmt]] = file.tr('\\', '/')
      else
        start = File.directory?(cur) ? File.dirname(cur) : path_default_dir
        dir = UI.select_directory(title: t('path.choose_dir'), directory: start)
        return unless dir
        dir = dir.tr('\\', '/')
        own = File.basename(dir) == path_safe(name) || !vx_png_frames(dir).empty?
        @vx[:targets][[name, fmt]] = own ? dir : File.join(dir, path_safe(name))
      end
      vx_push
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Il percorso scritto a mano nella casella
    def self.vx_target_set(s)
      s = s.to_s.strip.delete('"')
      return vx_push if s.empty?
      s = "#{s}.avi" if vx_format == 'avi' && !s.downcase.end_with?('.avi')
      @vx[:targets][[@vx[:name], vx_format]] = s.tr('\\', '/')
      vx_push
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # ── Audio ─────────────────────────────────────────────────────
    # 'pick': sceglie un .wav (uno illeggibile non si tiene: lo si dice);
    # 'clear': niente audio.
    def self.vx_audio(what)
      if what == 'clear'
        @cfg['path_video_audio'] = ''
      else
        cur = cf('path_video_audio').to_s
        dir = !cur.empty? && File.directory?(File.dirname(cur)) ? File.dirname(cur) : path_default_dir
        file = UI.openpanel(t('ve.audio_choose'), dir, 'WAV|*.wav||') or return
        file = file.tr('\\', '/')
        return UI.messagebox(format(t('ve.audio_bad'), file: vx_win(file))) unless MjpegAvi.wav(file)
        @cfg['path_video_audio'] = file
      end
      save_cfg
      vx_push
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Per la finestra: file, se si legge, durata, frequenza, canali
    def self.vx_audio_state
      f = cf('path_video_audio').to_s
      return nil if f.empty?
      w = MjpegAvi.wav(f)
      st = { 'file' => vx_win(f), 'ok' => !w.nil? }
      st.merge!('s' => (w[:bytes].to_f / w[:avg]).round(2), 'rate' => w[:rate], 'ch' => w[:ch], 'bits' => w[:bits]) if w
      st
    end

    # Esporta: {from, to, mode, draft, after}. Partita, la finestra si
    # chiude (resta quella dell'attesa); se no dice perché e resta aperta.
    def self.vx_go(d, json)
      c = JSON.parse(json.to_s)
      return unless c.is_a?(Hash)
      name = @vx[:name]
      fmt = vx_format
      target = vx_target(name, fmt)
      draft = c['draft'] ? true : false
      if draft
        tr = path_track(name) or return UI.messagebox(path_track_err(name))
        fps, total, = path_video_numbers(tr)
        dfps, dtotal, = path_video_numbers(tr, true)
        conv = ->(n) { (((n.to_i - 1).to_f / fps * dfps).floor + 1).clamp(1, dtotal) }
        c['from'] = conv.(c['from'])
        c['to'] = c['to'].to_i >= total ? dtotal : conv.(c['to'])
        target = vx_draft_target(target, fmt)
      end
      parent = fmt == 'avi' ? File.dirname(target) : File.dirname(File.expand_path(target))
      return UI.messagebox(format(t('ve.no_dir'), dir: vx_win(parent))) unless File.directory?(parent)
      mode = c['mode'] || (c['append'] ? 'append' : nil)
      err = path_export_frames(name, target: target, from: c['from'].to_i, to: c['to'].to_i,
                                     mode: %w[new append patch].include?(mode) ? mode : nil,
                                     draft: draft, after: c['after'])
      return UI.messagebox(err) if err.is_a?(String)
      d.close if @path_job
    rescue JSON::ParserError
      nil
    rescue => fps_err
      log_error(__method__, fps_err)
      UI.messagebox("DagaWASD — #{fps_err.message}")
    end

    def self.vx_open_log
      name = @vx && @vx[:name] or return
      log = vx_log_of(name, vx_format, vx_target(name, vx_format))
      UI.openURL("file:///#{log.tr('\\', '/')}") if File.file?(log)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # ── Tempi di ogni fotogramma (per il registro) ────────────────
    # n, somma, minimo, massimo, i 5 più lenti, e una media mobile per la stima della fine
    def self.vx_stat(job, f, dt)
      st = (job[:st] ||= { n: 0, sum: 0.0, min: nil, max: 0.0, slow: [], ema: nil })
      st[:n] += 1
      st[:sum] += dt
      st[:min] = dt if st[:min].nil? || dt < st[:min]
      st[:max] = dt if dt > st[:max]
      st[:ema] = st[:ema] ? st[:ema] + (dt - st[:ema]) * 0.02 : dt
      if st[:slow].size < 5 || dt > st[:slow].last[1]
        st[:slow] << [f, dt]
        st[:slow] = st[:slow].sort_by { |_, s| -s }.first(5)
      end
    end

    # ══════════════════════════════════════════════════════════════
    # Foglio di controllo: un PNG accanto al video (o nella cartella) con
    # un fotogramma ogni VX_SHEET_STEPS secondi (il primo che ci sta in
    # VX_SHEET_MAX miniature), ognuno col suo istante. Le miniature si
    # fanno mentre si esporta, dai JPEG e PNG già scritti (GDI+, VmGdi in
    # lib/videometeo.rb); il foglio si salva alla fine, anche interrotto.
    # Non deve mai fermare l'esportazione: al primo errore si smette.
    # ══════════════════════════════════════════════════════════════
    VX_SHEET_STEPS = [5, 10, 15, 20, 30, 60, 120, 300, 600].freeze
    VX_SHEET_MAX   = 120
    VX_SHEET_COLS  = 6
    VX_SHEET_TW    = 320     # px: larghezza di una miniatura
    VX_SHEET_PAD   = 6
    VX_SHEET_HEAD  = 44

    # Ogni quanti secondi, quante miniature e il loro posto
    def self.vx_sheet_plan(frames, fps, w, h)
      secs = frames.to_f / fps
      step = VX_SHEET_STEPS.find { |s| secs / s < VX_SHEET_MAX } || VX_SHEET_STEPS.last
      every = step * fps
      slots = (frames - 1) / every + 1
      cols = [slots, VX_SHEET_COLS].min
      tw = VX_SHEET_TW
      th = (tw * h.to_f / w).round
      rows = (slots + cols - 1) / cols
      { step: step, every: every, slots: slots, cols: cols, tw: tw, th: th,
        width: VX_SHEET_PAD + cols * (tw + VX_SHEET_PAD), height: VX_SHEET_HEAD + VX_SHEET_PAD + rows * (th + VX_SHEET_PAD) }
    end

    def self.vx_sheet_begin(job)
      return unless cf('path_video_sheet') && Sketchup.platform == :platform_win
      first = job[:k0].to_i + 1
      last = job[:stop] || job[:total]
      pl = vx_sheet_plan(last - first + 1, job[:fps], job[:w], job[:h])
      VmGdi.start
      bmp = VmGdi.bitmap(pl[:width], pl[:height])
      g = VmGdi.graphics(bmp)
      VmGdi.clear(g, 0xFF141414)
      title = "#{job[:name]}   #{job[:w]}x#{job[:h]}  #{job[:fps]} fps   #{first}-#{last}   #{vx_clock(first, job[:fps])} - #{vx_clock(last, job[:fps])}   / #{pl[:step]} s"
      VmGdi.text(g, title, VX_SHEET_PAD + 2, 10, 18, 0xFFE6E6E6, true)
      job[:sheet] = pl.merge(bmp: bmp, g: g, first: first, n: 0)
    rescue StandardError => fps_err
      log_error(__method__, fps_err)
      vx_sheet_drop(job)
    end

    # Dopo ogni fotogramma scritto (f da 1, file: il suo JPEG o PNG)
    def self.vx_sheet_add(job, f, file)
      sh = job[:sheet] or return
      return unless ((f - sh[:first]) % sh[:every]).zero? && sh[:n] < sh[:slots]
      i = sh[:n]
      x = VX_SHEET_PAD + (i % sh[:cols]) * (sh[:tw] + VX_SHEET_PAD)
      y = VX_SHEET_HEAD + VX_SHEET_PAD + (i / sh[:cols]) * (sh[:th] + VX_SHEET_PAD)
      VmGdi.draw_scaled(sh[:g], file, x, y, sh[:tw], sh[:th])
      VmGdi.rect(sh[:g], 0xB0000000, x, y + sh[:th] - 22, 118, 22)
      VmGdi.text(sh[:g], "#{vx_clock(f, job[:fps]).sub(/\.\d+\z/, '')}  ##{f}", x + 5, y + sh[:th] - 21, 14, 0xFFFFFFFF)
      sh[:n] += 1
    rescue StandardError => fps_err
      log_error(__method__, fps_err)
      vx_sheet_drop(job)
    end

    # Alla fine: solo le righe con miniature
    def self.vx_sheet_save(job)
      sh = job[:sheet] or return
      if sh[:n].positive?
        rows = (sh[:n] + sh[:cols] - 1) / sh[:cols]
        file = vx_sheet_file(job)
        VmGdi.save_crop(sh[:bmp], sh[:width], VX_SHEET_HEAD + VX_SHEET_PAD + rows * (sh[:th] + VX_SHEET_PAD), file)
        (job[:res] ||= {})[:sheet] = file.tr('/', '\\')
      end
    rescue StandardError => fps_err
      log_error(__method__, fps_err)
    ensure
      vx_sheet_drop(job)
    end

    def self.vx_sheet_drop(job)
      sh = job.delete(:sheet) or return
      VmGdi.delete_graphics(sh[:g]) if sh[:g]
      VmGdi.dispose_image(sh[:bmp]) if sh[:bmp]
    rescue StandardError
      nil
    end

    # «Video DagaWASD - controllo.png» accanto al video; un pezzo che non
    # parte dal primo fotogramma ha i suoi numeri nel nome
    def self.vx_sheet_file(job)
      first = job[:k0].to_i + 1
      last = job[:stop] || job[:total]
      part = first == 1 && last == job[:total] ? '' : " #{first}-#{last}"
      if job[:avi]
        video = job[:patch] ? job[:patch][:file] : job[:avi].path
        base = File.basename(video.sub(/\.avi\z/i, ''))
        File.join(File.dirname(video), path_safe(format(t('ve.sheet_name'), name: base)) + "#{part}.png")
      else
        File.join(job[:dir], path_safe(format(t('ve.sheet_name'), name: path_safe(job[:name]))) + "#{part}.png")
      end
    end

    # ══════════════════════════════════════════════════════════════
    # Windows: PC sveglio, spazio libero, suono, sospendi o spegni.
    # Fiddle al primo uso; fuori da Windows o se manca qualcosa non fa nulla.
    # ══════════════════════════════════════════════════════════════
    module VxWin
      module_function

      def api
        return @api if defined?(@api)
        @api = begin
          require 'fiddle'
          require 'fiddle/import'
          m = Module.new
          m.extend(Fiddle::Importer)
          m.dlload('kernel32', 'user32')
          m.extern 'unsigned int SetThreadExecutionState(unsigned int)'
          m.extern 'int GetDiskFreeSpaceExW(void*, void*, void*, void*)'
          m.extern 'int MessageBeep(unsigned int)'
          m
        rescue StandardError, LoadError
          nil
        end
      end

      # ES_CONTINUOUS | ES_SYSTEM_REQUIRED: niente sospensione (lo schermo può spegnersi)
      def awake(on); api&.SetThreadExecutionState(on ? 0x8000_0001 : 0x8000_0000); end

      def beep; api&.MessageBeep(0x40); end   # MB_ICONASTERISK: il suono «Informazione» di Windows

      # Byte liberi sul disco della cartella
      def free(dir)
        a = api or return nil
        buf = "\0" * 8
        w = (dir.to_s.tr('/', '\\').encode('UTF-16LE') + "\0".encode('UTF-16LE')).b
        a.GetDiskFreeSpaceExW(w, buf, nil, nil).zero? ? nil : buf.unpack1('Q')
      rescue StandardError
        nil
      end

      def suspend
        require 'fiddle'
        require 'fiddle/import'
        m = Module.new
        m.extend(Fiddle::Importer)
        m.dlload('powrprof')
        m.extern 'unsigned char SetSuspendState(unsigned char, unsigned char, unsigned char)'
        m.SetSuspendState(0, 0, 0)
      end

      # Un comando senza finestra (shutdown)
      def run(cmd)
        require 'win32ole'
        WIN32OLE.new('WScript.Shell').Run(cmd, 0, false)
      end
    end

    def self.vx_win?; Sketchup.platform == :platform_win; end

    def self.vx_awake(on)
      return unless vx_win?
      return if on && !cf('path_video_awake')
      VxWin.awake(on)
    rescue StandardError => fps_err
      log_error(__method__, fps_err)
    end

    def self.vx_free(dir)
      vx_win? ? VxWin.free(dir) : nil
    end

    def self.vx_notify(_job, _why)
      VxWin.beep if vx_win? && cf('path_video_notify')
    rescue StandardError => fps_err
      log_error(__method__, fps_err)
    end

    # Alla fine (non se l'ha interrotto chi è davanti al PC): sospendi o
    # spegni fra VX_AFTER_S secondi. Spegnere: shutdown /s di Windows, che
    # avvisa da sé e si annulla con shutdown /a; sospendere: un timer.
    # Ritorna { what, s } per la finestra d'attesa, o nil.
    def self.vx_after_start(job, why)
      what = job[:after] or return nil
      return nil if why == :interrotto || !vx_win?
      @vx_after = { what: what, at: Process.clock_gettime(Process::CLOCK_MONOTONIC) + VX_AFTER_S }
      if what == 'shutdown'
        vx_run("shutdown /s /t #{VX_AFTER_S} /c \"DagaWASD: #{t('ve.after_why').delete('"')}\"")
      else
        aft = @vx_after
        UI.start_timer(VX_AFTER_S, false) { vx_suspend if @vx_after.equal?(aft) }
      end
      { 'what' => what, 's' => VX_AFTER_S }
    rescue StandardError => fps_err
      log_error(__method__, fps_err)
      nil
    end

    def self.vx_after_cancel
      a = @vx_after or return
      @vx_after = nil
      vx_run('shutdown /a') if a[:what] == 'shutdown'
    rescue StandardError => fps_err
      log_error(__method__, fps_err)
    end

    def self.vx_suspend
      @vx_after = nil
      VxWin.suspend
    rescue StandardError => fps_err
      log_error(__method__, fps_err)
    end

    def self.vx_run(cmd); VxWin.run(cmd); end

  end
end
