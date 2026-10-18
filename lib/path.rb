# DagaWASD — Percorsi: registra la camera mentre si cammina, la riproduce,
# ne fa scene di SketchUp o immagini per un video. Le posizioni da ritoccare
# nel modello (sfere con freccia) stanno in lib/pathkeys.rb.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Dove stanno: nel modello (dizionario PATH_DICT, una chiave per
    # percorso), così viaggiano col file .skp. Ogni percorso è un JSON
    #   { "date": "2026-10-04 18:30", "s": [[t, ex, ey, ez, dx, dy, dz, ux, uy, uz, fov], …] }
    # t in secondi dall'inizio, occhio in pollici, direzione e alto
    # versori, fov in gradi: la camera vera, dondolio e inclinazione compresi.
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
          'shown' => list.any? { |e| !e.hidden? }, 'rec' => rec, 'pts' => pts }
      end.sort_by { |p| [p['date'], p['name']] }
    end

    # Fotogrammi e durata: dalle posizioni nel modello se ce ne sono almeno
    # due, se no dalla registrazione levigata; nil se nessuna delle due.
    def self.path_track(name, model = Sketchup.active_model)
      data = path_data(name, model) or return nil
      keys = key_read(name, model)
      if keys.size >= 2
        fr = key_frames(keys, key_speed(data))
        return { frames: fr, dur: (fr.size - 1) / PATH_HZ, keys: keys.size }
      end
      s = data['s']
      s.size >= 2 ? { frames: path_frames(s), dur: s.last[0].to_f, keys: 0 } : nil
    end

    def self.path_track_err(name)
      path_data(name) ? format(t('path.no_keys'), name: name) : t('path.missing')
    end

    def self.path_push
      @dialog&.execute_script("setPaths(#{js_json(path_list)})")
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
        Sketchup.status_text = t('rt.rec_short')
        return nil
      end
      name = path_new_name
      json = JSON.generate('date' => Time.now.strftime('%Y-%m-%d %H:%M:%S'), 's' => s)
      path_write(t('path.op_save')) { |m| m.set_attribute(PATH_DICT, name, json) }
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

    def self.path_set_camera(view, fr)
      cam = view.camera
      eye = Geom::Point3d.new(fr[0], fr[1], fr[2])
      cam.set(eye, Geom::Point3d.new(fr[0] + fr[3] * 100, fr[1] + fr[4] * 100, fr[2] + fr[5] * 100),
              Geom::Vector3d.new(fr[6], fr[7], fr[8]))
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
      model = Sketchup.active_model
      view = model.active_view
      speed = cf('path_speed').to_f.clamp(0.1, 10.0)
      @path_job = { kind: kind, name: name, frames: tr[:frames], speed: speed,
                    dur: tr[:dur], t0: nil, k: 0, view: view, done: false }.merge(extra)
      @path_job[:keys_hidden] = key_hide(model)   # le sfere non devono finire nella vista
      @path_job[:back] = path_cam_save(view.camera) if kind == :play
      model.select_tool(PathTool.new)
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
      if job[:kind] == :frames
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
      err = path_start(:frames, name, extra.merge(bytes: 0), tr)
      attesa_open(@path_job) unless err      # lib/attesa.rb: personaggio, avanzamento, battute
      err
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
      if (avi = job[:avi])
        ok = view.write_image(filename: job[:jpg], width: job[:w], height: job[:h], antialias: true, compression: 0.9)
        raise IOError, job[:jpg] unless ok
        jpeg = File.binread(job[:jpg])
        avi.add(jpeg)
        job[:bytes] = job[:bytes].to_i + jpeg.bytesize + 8
      else
        png = File.join(job[:dir], format('frame_%05d.png', k + 1))
        ok = view.write_image(filename: png, width: job[:w], height: job[:h], antialias: true)
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

    def self.path_frames_done(job, why)
      return path_video_done(job, why) if job[:avi]
      n = job[:k]
      Sketchup.status_text = ''
      unless n.zero?
        bat = File.join(job[:dir], 'crea_video.bat')
        File.write(bat, "@echo off\r\ncd /d \"%~dp0\"\r\n" \
                        "ffmpeg -y -framerate #{job[:fps]} -i frame_%%05d.png -c:v libx264 -pix_fmt yuv420p -crf 18 " \
                        "\"#{path_safe(job[:name])}.mp4\"\r\npause\r\n")
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
      model = Sketchup.active_model
      view = model.active_view
      frames = tr[:frames]
      dur = tr[:dur]
      step = cf('path_scene_step').to_f.clamp(0.2, 30.0)
      speed = cf('path_speed').to_f.clamp(0.1, 10.0)
      times = (0..(dur / step).floor).map { |i| i * step }
      times << dur if dur - times.last > step * 0.25
      cam = view.camera
      saved = [cam.eye, cam.target, cam.up, cam.perspective?, cam.fov]
      flags = defined?(PAGE_USE_CAMERA) ? PAGE_USE_CAMERA : 1
      re = /\A#{Regexp.escape(name)} \d{3,}\z/
      made = 0
      path_write(t('path.op_scenes'), model) do |m|
        m.pages.to_a.select { |pg| pg.name =~ re }.each { |pg| m.pages.erase(pg) }
        times.each_with_index do |tt, i|
          path_set_camera(view, path_frame_at(frames, tt))
          pg = m.pages.add(format('%s %03d', name, i + 1), flags)
          pg.transition_time = i.zero? ? 1.0 : (tt - times[i - 1]) / speed
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

    # ── Comandi dal pannello ──────────────────────────────────────
    def self.path_command(cmd, name, i = nil)
      err = case cmd
            when 'play'   then path_start(:play, name)
            when 'scenes' then path_make_scenes(name)
            when 'frames' then path_export_frames(name)
            when 'stop'   then path_abort
            when 'rename' then path_rename(name)
            when 'delete' then path_delete(name)
            when 'edit'   then key_edit(name)       # lib/pathkeys.rb: posizioni nel modello
            when 'revert' then key_revert(name)
            when 'new'    then key_new
            when 'key'    then key_open_nth(name, i.to_i)
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
