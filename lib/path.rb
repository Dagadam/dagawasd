# DagaWASD — Percorsi: registra la camera mentre si cammina, la riproduce,
# ne fa scene di SketchUp o immagini per un video. Le posizioni da ritoccare
# nel modello (sfere con freccia) stanno in lib/pathkeys.rb.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Dove stanno: nel modello (dizionario PATH_DICT, una chiave per
    # percorso), così viaggiano col file .skp. Ogni percorso è un JSON
    #   { "date": "2026-10-04 18:30", "s": [[t, ex, ey, ez, dx, dy, dz, ux, uy, uz, fov], …],
    #     "notes": [[t, "testo"], …] }
    # t in secondi dall'inizio, occhio in pollici, direzione e alto
    # versori, fov in gradi: la camera vera, dondolio e inclinazione compresi.
    # notes (facoltative): i commenti dell'IA che guidava l'esploratore
    # (lib/expilot.rb), che diventano descrizioni delle scene e sottotitoli.
    # ══════════════════════════════════════════════════════════════
    PATH_DICT = 'DagaWASD_percorsi'
    PATH_HZ   = 30.0         # campioni al secondo registrati (e fotogrammi interni)
    PATH_MIN  = 0.5          # s: più corto non si salva (tasto premuto due volte)
    PATH_VIDEO_SIZES = { 'hd' => [1280, 720], 'fhd' => [1920, 1080], 'uhd' => [3840, 2160] }.freeze

    # ── Archivio ──────────────────────────────────────────────────
    def self.path_dict(model = Sketchup.active_model)
      model&.attribute_dictionary(PATH_DICT)
    end

    # 's' può essere vuoto: percorso fatto solo di posizioni (lib/pathkeys.rb).
    # Letto una volta per testo: il pannello rifà l'elenco a ogni operazione.
    def self.path_data(name, model = Sketchup.active_model)
      raw = path_dict(model)&.[](name)
      return nil unless raw.is_a?(String)
      c = (@path_parsed ||= {})[name]
      return c[1] if c && c[0] == raw
      d = JSON.parse(raw)
      d = nil unless d.is_a?(Hash) && d['s'].is_a?(Array)
      @path_parsed[name] = [raw, d]
      d
    rescue JSON::ParserError
      nil
    end

    # Per il pannello: nome, durata (s), data, posizioni nel modello (quante,
    # se si vedono, e per ognuna arrivo e sosta in s, velocità propria in m/s
    # o 0, ingrandimento), se c'è la registrazione; i più vecchi prima.
    def self.path_list(model = Sketchup.active_model)
      d = path_dict(model) or return []
      by = key_instances(model)
      d.keys.filter_map do |k|
        p = path_data(k, model) or next
        list = by[k] || []
        keys = list.map { |e| key_of(e) }
        sch = key_schedule(keys, key_speed(p))
        rec = p['s'].size >= 2
        dur = if list.size >= 2 then sch.last[:leave]
              elsif rec then p['s'].last[0].to_f
              else 0.0
              end
        pts = keys.each_with_index.map do |q, i|
          { 't' => sch[i][:arrive].round(1), 'p' => q[10].round(1), 'v' => q[11].round(2), 'z' => key_zoom(q[9]).round(1) }
        end
        { 'name' => k, 'dur' => dur.round(1), 'date' => p['date'].to_s, 'keys' => list.size,
          'shown' => list.any? { |e| !e.hidden? }, 'rec' => rec, 'pts' => pts, 'photos' => p['photos'].to_i }
      end.sort_by { |p| [p['date'], p['name']] }
    end

    # Fotogrammi e durata: dalle posizioni nel modello se ce ne sono almeno
    # due, se no dalla registrazione levigata; nil se nessuna delle due.
    # Con le posizioni anche mark: da che secondo è «in corso» ciascuna
    # (a metà del tratto che porta a lei; la prima da 0).
    def self.path_track(name, model = Sketchup.active_model)
      data = path_data(name, model) or return nil
      keys = key_read(name, model)
      if keys.size >= 2
        v = key_speed(data)
        tm = key_timing(key_spline(keys), v)
        fr = key_frames(keys, v, tm)
        mark = [0.0] + key_schedule(keys, v, tm).each_cons(2).map { |a, b| (a[:leave] + b[:arrive]) / 2 }
        return { frames: fr, dur: (fr.size - 1) / PATH_HZ, keys: keys.size, mark: mark }
      end
      s = data['s']
      s.size >= 2 ? { frames: path_frames(s), dur: s.last[0].to_f, keys: 0, notes: path_notes(data) } : nil
    end

    # I commenti sul tempo della registrazione: con le posizioni nel modello
    # il tempo è un altro, e path_track non li dà.
    def self.path_notes(data)
      n = data['notes']
      return [] unless n.is_a?(Array)
      n.select { |a| a.is_a?(Array) && a[0].is_a?(Numeric) && a[1].is_a?(String) && !a[1].strip.empty? }
       .map { |a| [a[0].to_f, a[1].strip] }.sort_by(&:first)
    end

    # Sottotitoli SRT: ogni commento dal suo istante (diviso per la velocità)
    # finché non arriva il successivo, al più 4 s più un po' per i lunghi;
    # nil se non ce ne sono nel tratto girato (end in s di video).
    def self.path_srt(notes, speed, end_s)
      tc = ->(s) { ms = (s * 1000).round; format('%02d:%02d:%02d,%03d', ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000) }
      list = notes.map { |t, txt| [t / speed, txt] }.select { |a, _| a < end_s }
      return nil if list.empty?
      body = list.each_with_index.map do |(a, txt), i|
        b = [a + 4.0 + txt.size * 0.04, a + 8.0, end_s].min
        b = [b, a + 0.5].max
        b = [b, list[i + 1][0] - 0.05].min if list[i + 1]      # mai sopra il successivo
        "#{i + 1}\r\n#{tc.(a)} --> #{tc.(b)}\r\n#{txt}\r\n"
      end
      "\uFEFF" + body.join("\r\n")
    end

    # Senza commenti nel tratto girato si toglie quello di una volta.
    def self.path_srt_write(job, file)
      srt = path_srt(job[:notes].to_a, job[:speed], job[:k].to_f / job[:fps])
      return (File.delete(file) if File.exist?(file)) && nil unless srt
      File.write(file, srt, mode: 'wb')
      file
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    def self.path_track_err(name)
      path_data(name) ? format(t('path.no_keys'), name: name) : t('path.missing')
    end

    # I percorsi e le serie di foto che nessun percorso tiene (lib/gallery.rb)
    def self.path_push
      @dialog&.execute_script("setPaths(#{js_json(path_list)}, #{js_json(gal_loose)})")
    rescue => fps_err; log_error(__method__, fps_err); end

    def self.path_write(op, model = Sketchup.active_model)
      model.start_operation(op, true)
      begin
        yield model
        model.commit_operation
      rescue
        model.abort_operation
        raise
      end
      path_push
    end

    def self.path_new_name(model = Sketchup.active_model)
      base = t('path.default')
      used = path_dict(model)&.keys || []
      n = 1
      n += 1 while used.include?("#{base} #{n}")
      "#{base} #{n}"
    end

    # ══════════════════════════════════════════════════════════════
    # Registrazione (dentro la modalità FPS, tasto 'record')
    # ══════════════════════════════════════════════════════════════
    def self.path_rec_toggle(now)
      @path_rec ? path_rec_stop : path_rec_start(now)
    end

    def self.path_rec_start(now)
      @path_rec = { t0: now, last: nil, shown: -1, s: [] }
      Sketchup.status_text = format(t('rt.rec_on'), time: '0:00', key: key_label('record'))
    end

    # Dopo apply_camera: la camera che si vede, al più PATH_HZ volte al secondo.
    def self.path_rec_tick(now, view)
      r = @path_rec or return
      return if r[:last] && now - r[:last] < 1.0 / PATH_HZ - 0.002
      r[:last] = now
      c = view.camera
      e = c.eye; d = c.direction; u = c.up
      r[:s] << [(now - r[:t0]).round(3), e.x.round(2), e.y.round(2), e.z.round(2),
                d.x.round(5), d.y.round(5), d.z.round(5), u.x.round(5), u.y.round(5), u.z.round(5), c.fov.round(2)]
      sec = (now - r[:t0]).floor
      return if sec == r[:shown]
      r[:shown] = sec
      Sketchup.status_text = format(t('rt.rec_on'), time: path_clock(sec), key: key_label('record'))
    rescue => fps_err
      log_error(__method__, fps_err)
      @path_rec = nil
    end

    # Ferma e salva (anche all'uscita dalla modalità). Ritorna il nome o nil.
    def self.path_rec_stop
      r = @path_rec or return nil
      @path_rec = nil
      s = r[:s]
      if s.size < 2 || s.last[0] < PATH_MIN
        gal_finish(r[:gal], nil, s)              # le foto restano, senza percorso
        Sketchup.status_text = t('rt.rec_short')
        return nil
      end
      name = path_new_name
      json = JSON.generate({ 'date' => Time.now.strftime('%Y-%m-%d %H:%M:%S'), 's' => s }.merge(gal_fields(r[:gal])))
      path_write(t('path.op_save')) { |m| m.set_attribute(PATH_DICT, name, json) }
      gal_finish(r[:gal], name, s)               # lib/gallery.rb: le foto scattate registrando
      Sketchup.status_text = format(t('rt.rec_saved'), name: name, time: path_clock(s.last[0]))
      name
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    def self.path_clock(sec)
      sec = sec.round
      format('%d:%02d', sec / 60, sec % 60)
    end

    # ══════════════════════════════════════════════════════════════
    # Fotogrammi: ricampionati a PATH_HZ e levigati
    # Media mobile centrata di path_smooth secondi su posizione,
    # direzione, alto e fov: toglie il dondolio della testa e gli scatti
    # del mouse. La finestra si stringe verso i due capi, che restano
    # esattamente dove si è partiti e arrivati.
    # Ogni fotogramma: [ex, ey, ez, dx, dy, dz, ux, uy, uz, fov].
    # ══════════════════════════════════════════════════════════════
    def self.path_frames(samples, smooth = cf('path_smooth').to_f)
      t_end = samples.last[0].to_f
      n = (t_end * PATH_HZ).floor + 1
      j = 0
      raw = Array.new(n) do |i|
        t = i / PATH_HZ
        j += 1 while j < samples.size - 2 && samples[j + 1][0] < t
        a = samples[j]; b = samples[j + 1]
        f = b[0] > a[0] ? ((t - a[0]) / (b[0] - a[0])).clamp(0.0, 1.0) : 0.0
        (1..10).map { |k| a[k] + (b[k] - a[k]) * f }
      end
      h = (smooth.clamp(0.0, 10.0) * PATH_HZ / 2).round
      if h > 0
        pre = Array.new(n + 1) { Array.new(10, 0.0) }
        n.times { |i| 10.times { |k| pre[i + 1][k] = pre[i][k] + raw[i][k] } }
        raw = Array.new(n) do |i|
          w = [h, i, n - 1 - i].min
          c = 2 * w + 1
          (0...10).map { |k| (pre[i + w + 1][k] - pre[i - w][k]) / c }
        end
      end
      raw.each { |fr| path_orthonormal!(fr) }
    end

    # Direzione unitaria, alto perpendicolare e unitario (la media li accorcia).
    def self.path_orthonormal!(fr)
      dl = Math.sqrt(fr[3]**2 + fr[4]**2 + fr[5]**2)
      dl = 1.0 if dl < 1e-9
      fr[3] /= dl; fr[4] /= dl; fr[5] /= dl
      dot = fr[6] * fr[3] + fr[7] * fr[4] + fr[8] * fr[5]
      ux = fr[6] - dot * fr[3]; uy = fr[7] - dot * fr[4]; uz = fr[8] - dot * fr[5]
      ul = Math.sqrt(ux * ux + uy * uy + uz * uz)
      if ul < 1e-9
        ux = 0.0; uy = 0.0; uz = 1.0; ul = 1.0
      end
      fr[6] = ux / ul; fr[7] = uy / ul; fr[8] = uz / ul
      fr
    end

    # Fotogramma al tempo t (s di registrazione), interpolato fra i due vicini.
    def self.path_frame_at(frames, t)
      x = (t * PATH_HZ).clamp(0.0, frames.size - 1.0)
      i = x.floor
      return frames[i] if i >= frames.size - 1
      f = x - i
      a = frames[i]; b = frames[i + 1]
      path_orthonormal!(Array.new(10) { |k| a[k] + (b[k] - a[k]) * f })
    end

    # persp false: solo occhio, sguardo e alto (una camera parallela resta tale)
    def self.path_set_camera(view, fr, persp = true)
      cam = view.camera
      eye = Geom::Point3d.new(fr[0], fr[1], fr[2])
      cam.set(eye, Geom::Point3d.new(fr[0] + fr[3] * 100, fr[1] + fr[4] * 100, fr[2] + fr[5] * 100),
              Geom::Vector3d.new(fr[6], fr[7], fr[8]))
      return unless persp
      cam.perspective = true
      cam.fov = fr[9]
    end

    # ══════════════════════════════════════════════════════════════
    # Riproduzione e immagini: un'animazione di SketchUp (view.animation)
    # più uno strumento che la ferma con Esc o con un clic.
    # ══════════════════════════════════════════════════════════════
    class PathAnimation
      def initialize(job); @job = job; end
      def nextFrame(view); DagaWASD::FPSWalk.path_next(view, @job); end
      # SketchUp l'ha già tolta (altra animazione, scena…): non toccare la vista
      def stop; DagaWASD::FPSWalk.path_finish(@job, :interrotto, true) unless @job[:done]; end
    end

    class PathTool
      def activate; end
      # Scelto un altro strumento: si ferma, senza togliere quello nuovo
      def deactivate(_view); DagaWASD::FPSWalk.path_abort(true); end
      def onCancel(_reason, _view); DagaWASD::FPSWalk.path_abort; end
      def onLButtonDown(_flags, _x, _y, _view); DagaWASD::FPSWalk.path_abort; end
    end

    def self.path_busy?; !@path_job.nil?; end

    # kind :play o :frames. Ritorna un messaggio d'errore o nil.
    def self.path_start(kind, name, extra = {}, tr = nil)
      return t('path.busy') if @path_job
      tr ||= path_track(name) or return path_track_err(name)
      stop if @active                 # la camera la guida il percorso, non il giocatore
      explore_stop if @ex             # né l'esploratore autonomo
      model = Sketchup.active_model
      view = model.active_view
      ke_dolly_end(view)              # lib/keyedit.rb: un dolly a metà finisce, sfere com'erano
      speed = cf('path_speed').to_f.clamp(0.1, 10.0)
      @path_job = { kind: kind, name: name, frames: tr[:frames], speed: speed, notes: tr[:notes],
                    dur: tr[:dur], t0: nil, k: 0, view: view, done: false, mark: tr[:mark], on: nil }.merge(extra)
      @path_job[:keys_hidden] = key_hide(model)   # le sfere non devono finire nella vista
      @path_job[:back] = path_cam_save(view.camera) if kind == :play
      model.select_tool(PathTool.new)
      # prima dell'animazione: SketchUp chiede il primo fotogramma già qui
      vm_begin(@path_job) if kind == :frames  # lib/videometeo.rb: il meteo col tempo del video (e dipinto)
      view.animation = PathAnimation.new(@path_job)
      nil
    end

    def self.path_next(view, job)
      return false if job[:done]
      if job[:kind] == :play
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        job[:t0] ||= now
        t = (now - job[:t0]) * job[:speed]
        path_set_camera(view, path_frame_at(job[:frames], [t, job[:dur]].min))
        path_mark(job, t)
        if job[:k] == 0
          Sketchup.status_text = format(t('rt.path_play'), name: job[:name])
          job[:k] = 1
        end
        return true if t < job[:dur]
        path_finish(job, :fine)
        false
      else
        path_frames_step(view, job)
      end
    rescue => fps_err
      log_error(__method__, fps_err)
      path_finish(job, :errore)
      false
    end

    # Nel pannello si accende la posizione in corso, una dopo l'altra
    # (pathMark); t nil la spegne. Solo quando cambia.
    def self.path_mark(job, t)
      mark = job[:mark] or return
      i = t && (mark.rindex { |s| s <= t } || 0)
      return if i == job[:on]
      job[:on] = i
      @dialog.execute_script("pathMark(#{js_json(job[:name])}, #{js_json(i)})") if @dialog&.visible?
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.path_abort(tool_gone = false)
      job = @path_job or return
      job[:tool_gone] = true if tool_gone
      path_finish(job, :interrotto)
    end

    # View ha animation= ma non animation: la nostra si toglie se è ancora lei.
    def self.path_finish(job, why, anim_gone = false)
      return if job[:done]
      job[:done] = true
      @path_job = nil if @path_job.equal?(job)
      view = job[:view]
      view.animation = nil if view && !anim_gone
      Sketchup.active_model&.select_tool(nil) unless job[:tool_gone]
      key_unhide(Sketchup.active_model, job[:keys_hidden])
      path_mark(job, nil) unless job[:on].nil?
      if job[:kind] == :frames
        vm_end(job) if job[:vm]                # il meteo riprende il suo orologio
        path_frames_done(job, why)
      else
        # arrivata in fondo si torna alla vista di partenza (se no resterebbe
        # dentro l'ultima sfera); fermata con Esc o un clic resta dov'è
        path_cam_restore(view, job[:back]) if why == :fine && view && job[:back]
        Sketchup.status_text = why == :fine ? t('rt.path_end') : ''
      end
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # La camera com'è, anche parallela, e di nuovo com'era
    def self.path_cam_save(c)
      [c.eye, c.target, c.up, c.perspective?, c.perspective? ? c.fov : nil, c.perspective? ? nil : c.height]
    end

    def self.path_cam_restore(view, saved)
      eye, target, up, persp, fov, height = saved
      cam = view.camera
      cam.set(eye, target, up)
      cam.perspective = persp
      persp ? cam.fov = fov : cam.height = height
      view.invalidate
    end

    # ── Video (AVI) o immagini (PNG) ──────────────────────────────
    # Un fotogramma per chiamata: posa la camera e la scrive (write_image
    # disegna da sé). Il video dura quanto la registrazione / path_speed.
    # AVI: ogni fotogramma JPEG in un file temporaneo e da lì nel video
    # (lib/avi.rb); PNG: una cartella di immagini più crea_video.bat.
    def self.path_export_frames(name)
      return t('path.busy') if @path_job
      tr = path_track(name) or return path_track_err(name)
      fps = cf('path_video_fps').to_i.clamp(10, 60)
      speed = cf('path_speed').to_f.clamp(0.1, 10.0)
      total = (tr[:dur] / speed * fps).floor + 1
      view = Sketchup.active_model.active_view
      w, h = PATH_VIDEO_SIZES[cf('path_video_size')] || [view.vpwidth, view.vpheight]
      extra = { fps: fps, total: total, w: w, h: h }
      if cf('path_video_format') == 'png'
        base = UI.select_directory(title: t('path.choose_dir'), directory: path_default_dir)
        return nil unless base
        dir = File.join(base.tr('\\', '/'), path_safe(name))
        Dir.mkdir(dir) unless Dir.exist?(dir)
        Dir.glob(File.join(dir, 'frame_*.png')).each { |f| File.delete(f) rescue nil }   # niente avanzi di prima
        extra[:dir] = dir
      else
        file = UI.savepanel(t('path.save_video'), path_default_dir, "#{path_safe(name)}.avi")
        return nil unless file
        file = "#{file}.avi" unless file.downcase.end_with?('.avi')
        require 'tmpdir'
        extra[:avi] = MjpegAvi.new(file, w, h, fps)
        extra[:jpg] = File.join(Dir.tmpdir, "dagawasd_fotogramma_#{Process.pid}.jpg")
      end
      err = begin
        path_start(:frames, name, extra.merge(bytes: 0), tr)
      rescue StandardError
        # il lavoro era già nato: lo si chiude (e con lui il video); se no il
        # video aperto qui resterebbe un file vuoto e bloccato
        @path_job && @path_job[:avi].equal?(extra[:avi]) ? path_finish(@path_job, :errore) : path_avi_discard(extra)
        raise
      end
      return path_avi_discard(extra) && err if err
      attesa_open(@path_job)                 # lib/attesa.rb: personaggio, avanzamento, battute
      nil
    end

    # Il video appena aperto da path_export_frames, mai partito: chiuso e tolto.
    def self.path_avi_discard(extra)
      avi = extra[:avi] or return true
      avi.close
      File.delete(avi.path) if File.exist?(avi.path)
      true
    rescue SystemCallError, IOError => fps_err
      log_error(__method__, fps_err)
      true
    end

    # Più fotogrammi per giro dell'animazione, per ~PATH_BATCH s: fra un giro
    # e l'altro SketchUp ridisegna la vista e fa girare i timer del cielo, che
    # da soli raddoppiavano il tempo (write_image 0,57 s, un giro 1,15 s).
    # Esc e i clic arrivano fra un giro e l'altro.
    PATH_BATCH = 0.8

    def self.path_frames_step(view, job)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        go = path_frame_write(view, job)
        return go unless go
        next if Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 < PATH_BATCH
        attesa_progress(job)
        return true
      end
    end

    def self.path_frame_write(view, job)
      k = job[:k]
      if k >= job[:total]
        path_finish(job, :fine)
        return false
      end
      t = k * job[:speed] / job[:fps].to_f
      path_set_camera(view, path_frame_at(job[:frames], [t, job[:dur]].min))
      vm_step(job, view, k / job[:fps].to_f, k.zero? ? 0.0 : 1.0 / job[:fps]) if job[:vm]   # meteo all'istante del video
      path_mark(job, t)
      if (avi = job[:avi])
        ok = path_shot(view, job, job[:jpg], :jpg)
        raise IOError, job[:jpg] unless ok
        jpeg = File.binread(job[:jpg])
        avi.add(jpeg)
        job[:bytes] = job[:bytes].to_i + jpeg.bytesize + 8
      else
        png = File.join(job[:dir], format('frame_%05d.png', k + 1))
        ok = path_shot(view, job, png, :png)
        raise IOError, job[:dir] unless ok
        job[:bytes] = job[:bytes].to_i + File.size(png)
      end
      job[:k] = k + 1
      if avi&.full?                              # al limite dei 4 GB di un AVI: si chiude qui
        path_finish(job, :pieno)
        return false
      end
      Sketchup.status_text = format(t('rt.path_frames'), n: k + 1, total: job[:total])
      true
    end

    # Un fotogramma in file (fmt :jpg o :png): col meteo dipinto se l'opzione
    # è accesa (lib/videometeo.rb), se no com'è nella vista senza le Overlay.
    def self.path_shot(view, job, file, fmt)
      return vm_shot(view, job, file, fmt) if job[:vm] && job[:vm][:paint]
      path_plain_shot(view, job, file, fmt)
    end

    def self.path_plain_shot(view, job, file, fmt)
      opts = { filename: file, width: job[:w], height: job[:h], antialias: true }
      opts[:compression] = 0.9 if fmt == :jpg
      view.write_image(opts)
    end

    def self.path_frames_done(job, why)
      return path_video_done(job, why) if job[:avi]
      n = job[:k]
      Sketchup.status_text = ''
      unless n.zero?
        base = path_safe(job[:name])
        srt = path_srt_write(job, File.join(job[:dir], "#{base}.srt"))   # i commenti dell'IA, nel video come sottotitoli
        bat = File.join(job[:dir], 'crea_video.bat')
        # in un .bat un % del nome aprirebbe una variabile: «Sconto 50%» perdeva mezza riga.
        # Il file è UTF-8 e cmd lo leggerebbe nella codepage OEM (850…): un nome
        # con lettere non ASCII («Маршрут 1», «è») non si troverebbe. chcp 65001.
        b = base.gsub('%', '%%')
        File.write(bat, "@echo off\r\nchcp 65001 >nul\r\ncd /d \"%~dp0\"\r\n" \
                        "ffmpeg -y -framerate #{job[:fps]} -i frame_%%05d.png #{srt ? "-i \"#{b}.srt\" -c:s mov_text " : ''}" \
                        "-c:v libx264 -pix_fmt yuv420p -crf 18 \"#{b}.mp4\"\r\npause\r\n", mode: 'wb')   # wb: \r\n e non \r\r\n
      end
      info = { 'n' => n, 'time' => path_clock(n.to_f / job[:fps]), 'mb' => (job[:bytes].to_i / 1_048_576.0).round(1),
               'dir' => job[:dir].tr('/', '\\') }
      return if attesa_finish(job, why, info) || n.zero?
      key = why == :fine ? 'path.frames_done' : 'path.frames_stopped'
      UI.messagebox(format(t(key), n: n, dir: job[:dir]))
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.path_video_done(job, why)
      avi = job[:avi]
      avi.close
      File.delete(job[:jpg]) if File.exist?(job[:jpg])
      Sketchup.status_text = ''
      n = avi.frames
      File.delete(avi.path) if n.zero? && File.exist?(avi.path)
      path_srt_write(job, avi.path.sub(/\.avi\z/i, '') + '.srt') unless n.zero?   # accanto: i lettori lo aprono da soli
      file = avi.path.tr('/', '\\')
      time = path_clock(n.to_f / job[:fps])
      mb = n.zero? ? 0.0 : (File.size(avi.path) / 1_048_576.0).round(1)
      return if attesa_finish(job, why, 'n' => n, 'time' => time, 'mb' => mb, 'file' => n.zero? ? nil : file) || n.zero?
      key = why == :fine ? 'path.video_done' : 'path.video_stopped'
      UI.messagebox(format(t(key), file: file, time: time, mb: mb))
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.path_default_dir
      p = Sketchup.active_model.path.to_s
      return File.dirname(p) unless p.empty?
      File.join(ENV['USERPROFILE'].to_s, 'Videos')
    end

    def self.path_safe(name)
      s = name.to_s.gsub(/[\\\/:*?"<>|]/, '_').strip
      s.empty? ? 'percorso' : s
    end

    # ── Scene di SketchUp ─────────────────────────────────────────
    # Una scena ogni path_scene_step secondi di registrazione, solo con
    # la camera, transizione = passo / path_speed e nessuna pausa: la
    # riproduzione delle scene (o File › Esporta › Animazione) rifà il
    # percorso. Rifarle sostituisce quelle dello stesso percorso.
    def self.path_make_scenes(name)
      return t('path.busy') if @path_job
      tr = path_track(name) or return path_track_err(name)
      stop if @active
      explore_stop if @ex
      model = Sketchup.active_model
      view = model.active_view
      frames = tr[:frames]
      dur = tr[:dur]
      step = cf('path_scene_step').to_f.clamp(0.2, 30.0)
      speed = cf('path_speed').to_f.clamp(0.1, 10.0)
      times = (0..(dur / step).floor).map { |i| i * step }
      times << dur if dur - times.last > step * 0.25
      # ogni commento dell'IA nella descrizione della scena più vicina
      said = Hash.new { |h, k| h[k] = [] }
      tr[:notes].to_a.each { |nt, txt| said[times.each_index.min_by { |i| (times[i] - nt).abs }] << txt }
      cam = view.camera
      saved = [cam.eye, cam.target, cam.up, cam.perspective?, cam.fov]
      flags = defined?(PAGE_USE_CAMERA) ? PAGE_USE_CAMERA : 1
      made = 0
      path_write(t('path.op_scenes'), model) do |m|
        m.pages.to_a.select { |pg| path_scene_ours?(pg, name) }.each { |pg| m.pages.erase(pg) }
        times.each_with_index do |tt, i|
          path_set_camera(view, path_frame_at(frames, tt))
          pg = m.pages.add(format('%s %03d', name, i + 1), flags)
          pg.set_attribute(PATH_DICT, 'percorso', name)    # nostra: rifacendole si toglie solo questa
          pg.transition_time = i.zero? ? 1.0 : (tt - times[i - 1]) / speed
          pg.description = said[i].join(' · ') if said.key?(i)
          pg.delay_time = 0.0
          made += 1
        end
        m.options['PageOptions']['ShowTransition'] = true
      end
      cam.set(saved[0], saved[1], saved[2])
      cam.perspective = saved[3]
      cam.fov = saved[4] if saved[3]
      UI.messagebox(format(t('path.scenes_done'), n: made, name: name))
      nil
    end

    # Una scena fatta da path_make_scenes per questo percorso? Quelle nuove
    # lo dicono in un attributo. Quelle di prima (senza) si riconoscono dal
    # nome «<percorso> 001» e dal fatto che salvano solo la camera: una scena
    # dell'utente con lo stesso nome salva anche stile e tag, e resta.
    def self.path_scene_ours?(pg, name)
      mine = pg.get_attribute(PATH_DICT, 'percorso')
      return mine == name unless mine.nil?
      return false unless pg.name.match?(/\A#{Regexp.escape(name)} \d{3,}\z/)
      %i[use_style? use_rendering_options? use_hidden_layers? use_shadow_info?]
        .none? { |q| pg.respond_to?(q) && pg.public_send(q) }
    end

    # ── Comandi dal pannello ──────────────────────────────────────
    # Mentre un ponte costruisce dal vivo (lib/lifecycle.rb, bridge_refuse)
    # si possono solo fermare la riproduzione e guardare le foto.
    PATH_CMD_ANYTIME = %w[stop photos gallery].freeze

    def self.path_command(cmd, name, i = nil)
      return if !PATH_CMD_ANYTIME.include?(cmd) && bridge_refuse
      err = case cmd
            when 'play'   then path_start(:play, name)
            when 'scenes' then path_make_scenes(name)
            when 'frames' then path_export_frames(name)
            when 'stop'   then path_abort
            when 'rename' then path_rename(name)
            when 'delete' then path_delete(name)
            when 'edit'   then key_edit(name)       # lib/pathkeys.rb: posizioni nel modello
            when 'revert' then key_revert(name)
            when 'thin'   then key_thin(name)       # sfere ammassate → una, la loro media
            when 'new'    then key_new
            when 'key'    then key_open_nth(name, i.to_i)
            when 'add'    then key_add_at(name, i)
            when 'photos' then gal_open_path(name)  # lib/gallery.rb: la galleria nel browser
            when 'gallery' then gal_open_loose(name)  # una serie senza percorso (name = la sua cartella)
            end
      UI.messagebox(err) if err.is_a?(String)
    rescue => fps_err
      log_error(__method__, fps_err)
      UI.messagebox("DagaWASD — #{fps_err.message}")
    end

    def self.path_rename(name)
      raw = path_dict&.[](name) or return t('path.missing')
      res = UI.inputbox([t('path.ask_name')], [name], t('path.rename')) or return nil
      nuovo = res[0].to_s.strip[0, 60]
      return nil if nuovo.empty? || nuovo == name
      return t('path.exists') if path_dict.keys.include?(nuovo)
      list = key_instances[name] || []
      path_write(t('path.op_edit')) do |m|
        m.set_attribute(PATH_DICT, nuovo, raw)
        m.attribute_dictionary(PATH_DICT).delete_key(name)
        list.each do |e|
          e.set_attribute(KEY_DICT, 'path', nuovo)
          e.name = nuovo
        end
      end
      gal_renamed(path_data(nuovo), nuovo)   # lib/gallery.rb: le sue foto lo sanno
      nil
    end

    def self.path_delete(name)
      return t('path.missing') unless path_dict&.[](name)
      return nil unless UI.messagebox(format(t('path.ask_delete'), name: name), MB_YESNO) == IDYES
      list = key_instances[name] || []
      path_write(t('path.op_edit')) do |m|
        unless list.empty?
          m.entities.erase_entities(list) # rubocop:disable SketchupSuggestions/ModelEntities
          key_purge(m)                    # lib/pathkeys.rb: componenti rimasti senza sfere
        end
        d = m.attribute_dictionary(PATH_DICT)
        d.delete_key(name)
        m.attribute_dictionaries.delete(d) if d.keys.empty?
      end
      nil
    end

    # Il pannello aperto e le posizioni (osservatore, Overlay) seguono il modello attivo.
    class PathAppObserver < Sketchup::AppObserver
      def onNewModel(model);  UI.start_timer(0, false) { DagaWASD::FPSWalk.path_follow(model) }; end
      def onOpenModel(model); UI.start_timer(0, false) { DagaWASD::FPSWalk.path_follow(model) }; end
    end

    def self.path_follow(model)
      key_attach(model)
      path_push
    end

    def self.path_observe
      key_attach(Sketchup.active_model)
      return if @path_observer
      @path_observer = PathAppObserver.new
      Sketchup.add_observer(@path_observer)
    end

  end
end
