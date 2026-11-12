# DagaWASD — Esporta video: la finestra (videoexport.html) che viene prima
# dell'esportazione di un percorso (lib/path.rb), e il registro accanto al video.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # «Video» di un percorso apre questa finestra invece di partire subito:
    # formato, misure, fps, velocità e meteo (le stesse impostazioni del
    # pannello), dove salvare (con Sfoglia…), quali fotogrammi (dal x al y)
    # e, se il video o la cartella hanno già dei fotogrammi, da dove
    # riprendere. Un AVI di DagaWASD si allunga in coda (lib/avi.rb): un
    # video lungo si fa a pezzi e resta un file solo, senza montaggio.
    #
    # Registro: accanto al video, stesso nome e .log (per le immagini nella
    # loro cartella, col nome del percorso). Una riga per ogni inizio e
    # ogni fine, con data e ora, i fotogrammi e i loro istanti nel video;
    # mentre si esporta l'ultima riga dice l'ultimo fotogramma scritto, così
    # anche se SketchUp si chiude si sa dove si era. In fondo a ogni riga,
    # fra quadre, gli stessi numeri per la finestra: [ev=… from=… …].
    # Il primo fotogramma di un AVI (first) lo sa solo il registro: un video
    # cominciato dal fotogramma 2001 ha 2001 come primo.
    # ══════════════════════════════════════════════════════════════
    VX_FILE   = File.join(PLUGIN_DIR, 'videoexport.html').freeze
    VX_CFG    = %w[path_video_format path_video_size path_video_fps path_video_weather path_speed].freeze
    VX_EVERY  = 5.0          # s fra una riscrittura e l'altra del registro durante l'esportazione
    VX_PANEL  = (%w[f.path_video_format f.path_video_size f.path_video_fps f.path_video_weather f.path_speed] +
                 %w[avi png].map { |v| "o.path_video_format.#{v}" } +
                 %w[view hd fhd uhd].map { |v| "o.path_video_size.#{v}" }).freeze

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
        width: 520, height: 720, min_width: 420, min_height: 520,
        resizable: true
      )
      d.set_file(VX_FILE)
      d.add_action_callback('ready')  { |_c, _| vx_ready }
      d.add_action_callback('set')    { |_c, json| vx_set(json) }
      d.add_action_callback('browse') { |_c, _| vx_browse }
      d.add_action_callback('target') { |_c, s| vx_target_set(s) }
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
      strings = @lang.select { |k, _| k.start_with?('ve.') || VX_PANEL.include?(k) }
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
      fmt = vx_format
      target = vx_target(name, fmt)
      log = fmt == 'avi' ? vx_log_file(target) : File.join(target, "#{path_safe(name)}.log")
      st = { 'name' => name, 'dur' => tr[:dur].to_f, 'total' => total, 'fps' => fps, 'w' => w, 'h' => h,
             'format' => fmt, 'size' => cf('path_video_size').to_s, 'speed' => cf('path_speed').to_f,
             'weather' => cf('path_video_weather') ? true : false, 'target' => vx_win(target),
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

    # {chiave: valore} dalla finestra: le stesse impostazioni del pannello,
    # salvate e mostrate anche lì.
    def self.vx_set(json)
      c = JSON.parse(json.to_s)
      return unless c.is_a?(Hash)
      c.each do |k, v|
        next unless VX_CFG.include?(k)
        v = case k
            when 'path_video_format' then %w[avi png].include?(v) ? v : nil
            when 'path_video_size' then (PATH_VIDEO_SIZES.keys + ['view']).include?(v) ? v : nil
            when 'path_video_fps' then v.to_i.clamp(10, 60)
            when 'path_video_weather' then v ? true : false
            when 'path_speed' then (v.to_f.clamp(0.25, 4.0) * 20).round / 20.0
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

    # Esporta: {from, to, append}. Partita, la finestra si chiude (resta
    # quella dell'attesa); se no dice perché e resta aperta.
    def self.vx_go(d, json)
      c = JSON.parse(json.to_s)
      return unless c.is_a?(Hash)
      name = @vx[:name]
      target = vx_target(name, vx_format)
      parent = vx_format == 'avi' ? File.dirname(target) : File.dirname(File.expand_path(target))
      return UI.messagebox(format(t('ve.no_dir'), dir: vx_win(parent))) unless File.directory?(parent)
      err = path_export_frames(name, target: target, from: c['from'].to_i, to: c['to'].to_i,
                                     append: vx_format == 'avi' && c['append'] ? true : false)
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
      target = vx_target(name, vx_format)
      log = vx_format == 'avi' ? vx_log_file(target) : File.join(target, "#{path_safe(name)}.log")
      UI.openURL("file:///#{log.tr('\\', '/')}") if File.file?(log)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # ── Registro ──────────────────────────────────────────────────
    def self.vx_log_file(avi); avi.to_s.sub(/\.avi\z/i, '') + '.log'; end

    def self.vx_job_log(job)
      job[:avi] ? vx_log_file(job[:avi].path) : File.join(job[:dir], "#{path_safe(job[:name])}.log")
    end

    # Le righe del registro come [testo, {chiave => valore}]
    def self.vx_log_lines(file)
      return [] unless File.file?(file)
      File.read(file, encoding: 'UTF-8').scrub.lines.map(&:chomp).reject(&:empty?).map do |l|
        kv = l[/\[([^\[\]]*)\]\s*\z/, 1].to_s.scan(/(\w+)=(\S+)/).to_h
        [l.sub(/\s*\[[^\[\]]*\]\s*\z/, ''), kv]
      end
    rescue SystemCallError, IOError
      []
    end

    # Il primo fotogramma del video: quello dell'ultimo inizio
    def self.vx_file_first(file)
      ev = vx_log_lines(file).reverse.find { |_, kv| kv['ev'] == 'start' } or return nil
      n = ev[1]['first'].to_i
      n.positive? ? n : nil
    end

    def self.vx_log_last(file)
      l = vx_log_lines(file).last
      l && l[1]['ev'] ? l[0] : nil
    end

    # Istante nel video del fotogramma n (da 1): 4:38.80
    def self.vx_clock(n, fps)
      s = [n - 1, 0].max / fps.to_f
      format('%d:%05.2f', (s / 60).floor, s % 60)
    end

    def self.vx_line(text, kv)
      "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}  #{text}  [#{kv.map { |k, v| "#{k}=#{v}" }.join(' ')}]\r\n"
    end

    # Inizio: fresh = video nuovo o immagini da capo, il registro riparte;
    # se no (in coda, un altro pezzo di immagini) le righe di prima restano.
    def self.vx_log_begin(job, fresh)
      file = vx_job_log(job)
      old = !fresh && File.file?(file) ? File.read(file, encoding: 'UTF-8').scrub : ''
      old += "\r\n" unless old.empty? || old.end_with?("\n")
      head = old.empty? ? "#{format(t('ve.log.head'), name: job[:name])}\r\n" : ''
      fps = job[:fps]
      from = job[:k0].to_i + 1
      to = job[:stop] || job[:total]
      text = format(t('ve.log.start'), from: from, to: to, total: job[:total], t1: vx_clock(from, fps), t2: vx_clock(to, fps),
                                       w: job[:w], h: job[:h], fps: fps)
      before = job[:avi]&.before.to_i
      text += " #{format(t('ve.log.append'), n: before)}" if before.positive?
      kv = { 'ev' => 'start', 'from' => from, 'to' => to, 'total' => job[:total], 'fps' => fps, 'w' => job[:w], 'h' => job[:h] }
      kv['first'] = job[:first] if job[:avi]
      base = old + head + vx_line(text, kv)
      job[:log] = { file: file, base: base, at: nil }
      vx_log_write(job, base)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Durante: ogni VX_EVERY s l'ultima riga dice l'ultimo fotogramma scritto
    def self.vx_log_progress(job)
      lg = job[:log] or return
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if lg[:at] && now - lg[:at] < VX_EVERY
      lg[:at] = now
      return if job[:k] == job[:k0].to_i
      vx_log_write(job, lg[:base] + vx_line(format(t('ve.log.run'), last: job[:k], t: vx_clock(job[:k], job[:fps])),
                                            'ev' => 'run', 'last' => job[:k]))
    end

    # Fine, per qualunque motivo (why: :fine, :interrotto, :pieno, :errore)
    def self.vx_log_end(job, why)
      vx_refresh
      lg = job[:log] or return
      last = job[:k]
      nxt = last + 1
      tt = vx_clock(last, job[:fps])
      key, ev =
        if why == :fine then ['ve.log.end', 'end']
        elsif last == job[:k0].to_i then ['ve.log.stop0', 'stop']
        elsif why == :pieno then ['ve.log.full', 'full']
        elsif why == :errore then ['ve.log.error', 'error']
        else ['ve.log.stop', 'stop']
        end
      kv = { 'ev' => ev, 'last' => last }
      kv['next'] = nxt unless ev == 'end'
      vx_log_write(job, lg[:base] + vx_line(format(t(key), last: last, t: tt, next: nxt), kv))
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Il registro non deve mai fermare l'esportazione
    def self.vx_log_write(job, text)
      File.binwrite(job[:log][:file], text)
    rescue SystemCallError, IOError => fps_err
      log_error(__method__, fps_err)
    end

  end
end
