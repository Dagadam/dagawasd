# DagaWASD — Pannello della sfera: le impostazioni di una posizione di un
# percorso (lib/pathkeys.rb) in una finestra (keyedit.html), con l'anteprima
# dalla sfera. Si apre col doppio clic su una sfera o, selezionata, con Invio.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Ogni modifica è un'operazione annullabile e la sfera cambia subito
    # (componente dello zoom, attributi 'sosta' e 'v'). Con «Anteprima
    # dalla sfera» la camera entra in dolly nella vista della sfera e la
    # segue; tolta, torna in dolly alla vista di prima. Ogni passaggio fra
    # una sfera e l'altra è un dolly: con l'anteprima lungo il percorso
    # vero (accelerato), senza la camera trasla quanto la sfera.
    # Angoli come li vede chi usa SketchUp: direzione a bussola (0° verso
    # l'asse verde, 90° verso il rosso), inclinazione positiva verso
    # l'alto, rollio positivo con la testa piegata a destra.
    # ══════════════════════════════════════════════════════════════
    KE_FILE   = File.join(PLUGIN_DIR, 'keyedit.html').freeze
    KE_DOLLY  = 1.0          # s: entrare e uscire dall'anteprima, spostarsi senza anteprima
    KE_PATH   = 1.5          # s al più da sfera a sfera lungo il percorso (un tratto più breve, meno)
    KE_SELECT = 21022        # active_tool_id dello strumento Seleziona
    VK_RETURN = 0x0D

    def self.key_editable?(e)
      e.is_a?(Sketchup::ComponentInstance) && e.valid? &&
        !e.definition.get_attribute(KEY_DICT, 'def').nil? && !e.get_attribute(KEY_DICT, 'path').nil?
    end

    # ── Angoli ↔ direzione e alto ────────────────────────────────
    # [direzione, inclinazione, rollio] in gradi
    def self.ke_angles(k)
      dx, dy, dz = k[3], k[4], k[5]
      az = (Math.atan2(dx, dy) * 180 / Math::PI) % 360
      pitch = Math.asin(dz.clamp(-1.0, 1.0)) * 180 / Math::PI
      u0, r = ke_level(dx, dy, dz)
      roll = u0 ? Math.atan2(k[6] * r[0] + k[7] * r[1] + k[8] * r[2], k[6] * u0[0] + k[7] * u0[1] + k[8] * u0[2]) * 180 / Math::PI : 0.0
      [az, pitch, roll]
    end

    # Alto «in bolla» per quella direzione e la destra; nil guardando dritto in su o in giù
    def self.ke_level(dx, dy, dz)
      ux = -dz * dx; uy = -dz * dy; uz = 1.0 - dz * dz
      l = Math.sqrt(ux * ux + uy * uy + uz * uz)
      return [nil, nil] if l < 1e-6
      u = [ux / l, uy / l, uz / l]
      [u, [dy * u[2] - dz * u[1], dz * u[0] - dx * u[2], dx * u[1] - dy * u[0]]]   # destra = sguardo × alto
    end

    def self.ke_from_angles(k, az, pitch, roll)
      a = az * Math::PI / 180; p = pitch.clamp(-89.9, 89.9) * Math::PI / 180; q = roll * Math::PI / 180
      d = [Math.sin(a) * Math.cos(p), Math.cos(a) * Math.cos(p), Math.sin(p)]
      u0, r = ke_level(*d)
      k[3], k[4], k[5] = d
      k[6], k[7], k[8] = (0..2).map { |c| u0[c] * Math.cos(q) + r[c] * Math.sin(q) }
      k
    end

    # Fotogramma della camera attuale (come una posizione)
    def self.ke_cam_frame(cam)
      e = cam.eye; d = cam.direction; u = cam.up
      path_orthonormal!([e.x, e.y, e.z, d.x, d.y, d.z, u.x, u.y, u.z, cam.perspective? ? cam.fov.to_f : 60.0])
    end

    # Quota degli occhi sopra ciò che c'è sotto (pollici); nil se sotto non c'è nulla.
    # Le sfere e i loro pezzi non contano.
    def self.ke_ground(model, k)
      from = Geom::Point3d.new(k[0], k[1], k[2])
      down = Geom::Vector3d.new(0, 0, -1)
      6.times do
        hit = model.raytest([from, down], true) or return nil
        return k[2] - hit[0].z unless hit[1].any? { |e| e.respond_to?(:definition) && e.definition.get_attribute(KEY_DICT, 'def') }
        from = hit[0].offset(down, 0.01)
      end
      nil
    rescue StandardError
      nil
    end

    # ── Valori per la pagina ──────────────────────────────────────
    def self.ke_values(e)
      model = e.model
      name = e.get_attribute(KEY_DICT, 'path').to_s
      list = key_instances(model)[name] || [e]
      i = list.index(e) || 0
      keys = list.map { |x| key_of(x) }
      v_auto = key_speed(path_data(name, model))
      sch = key_schedule(keys, v_auto)
      k = keys[i]
      az, pitch, roll = ke_angles(k)
      g = ke_ground(model, k)
      { 'path' => name, 'i' => i + 1, 'n' => list.size,
        'x' => k[0] * IN_TO_M, 'y' => k[1] * IN_TO_M, 'z' => k[2] * IN_TO_M, 'ground' => g && g * IN_TO_M,
        'az' => az, 'pitch' => pitch, 'roll' => roll, 'fov' => k[9], 'zoom' => key_zoom(k[9]),
        'pause' => k[10].to_f, 'v' => k[11].to_f, 'v_auto' => v_auto,
        'seg' => sch[i][:seg], 'arrive' => sch[i][:arrive],
        'preview' => !!(@ke && @ke[:preview]), 'busy' => !@path_job.nil? }
    end

    # ── Finestra ──────────────────────────────────────────────────
    def self.ke_open(e)
      return unless key_editable?(e)
      return UI.messagebox(t('path.busy')) if @path_job || @active
      @ke ||= { preview: false }
      old = @ke[:inst]
      d = ke_dialog
      ke_select(e)
      if d.visible?
        ke_goto(e) unless old.equal?(e)
        ke_push
        d.bring_to_front
      else
        @ke[:inst] = e
        d.show
        dialog_on_screen(d)
      end
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Dall'elenco espanso del pannello: la i-esima posizione (da 0) del percorso
    def self.key_open_nth(name, i)
      list = key_instances[name] or return t('path.missing')
      e = list[i] or return nil
      ke_open(e)
      nil
    end

    def self.ke_dialog
      return @ke[:dialog] if @ke[:dialog]
      d = UI::HtmlDialog.new(
        dialog_title:    "DagaWASD — #{t('ke.title')}",
        preferences_key: 'DagaWASDSfera',
        width: 380, height: 640, min_width: 330, min_height: 480,
        resizable: true
      )
      d.set_file(KE_FILE)
      d.add_action_callback('ready')   { |_c, _| ke_ready }
      d.add_action_callback('set')     { |_c, json| ke_set_json(json) }
      d.add_action_callback('nav')     { |_c, dir| ke_nav(dir.to_i) }
      d.add_action_callback('preview') { |_c, on| ke_preview([true, 'true', 1, '1'].include?(on)) }
      d.add_action_callback('act')     { |_c, what| ke_act(what.to_s) }
      d.add_action_callback('paste')   { |_c, _| d.execute_script("incolla(#{js_json(ke_clipboard)})") }
      d.set_on_closed do
        ke_preview(false) if @ke[:preview]       # chiusa con l'anteprima accesa: si torna alla vista di prima
        # la notizia della chiusura può arrivare dopo una riapertura immediata:
        # si dimentica solo una finestra ancora chiusa
        @ke[:dialog] = nil if @ke[:dialog].equal?(d) && !d.visible?
      end
      @ke[:dialog] = d
    end

    def self.ke_ready
      d = @ke && @ke[:dialog] or return
      load_lang
      look = { 'theme' => cf('ui_theme'), 'accent' => cf('ui_accent'), 'highlight' => cf('ui_highlight'),
               'danger' => cf('ui_danger') }
      look.merge!('bg' => cf('ui_bg'), 'text' => cf('ui_text')) if cf('ui_custom_colors')
      d.execute_script("init(#{js_json('strings' => @lang.select { |k, _| k.start_with?('ke.') },
                                        'lang' => @lang_code, 'rtl' => @lang_rtl, 'look' => look)})")
      ke_push
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.ke_push
      d = @ke && @ke[:dialog] or return
      e = @ke[:inst]
      return d.close unless key_editable?(e)
      d.execute_script("show(#{js_json(ke_values(e))})")
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Dopo ogni operazione (lib/pathkeys.rb, key_changed): la sfera spostata
    # con Sposta, ruotata, cancellata, Ctrl+Z…
    def self.ke_refresh
      return unless @ke && @ke[:dialog]&.visible?
      e = @ke[:inst]
      return ke_push if key_editable?(e)
      @ke[:dialog].close                         # la sfera non c'è più
    end

    # ── Modifiche ─────────────────────────────────────────────────
    def self.ke_set_json(json)
      d = JSON.parse(json.to_s)
      ke_set(d['f'].to_s, d['v'], d['run'])
    rescue JSON::ParserError
      nil
    end

    def self.ke_set(f, v, run = nil)
      e = @ke && @ke[:inst]
      return unless key_editable?(e) && !@path_job
      k = key_of(e)
      x = v.is_a?(Numeric) ? v.to_f : (Float(v.to_s.tr(',', '.')) rescue nil)
      return ke_push if x.nil? && f != 'vauto'          # non è un numero: resta il valore di prima
      az, pitch, roll = ke_angles(k)
      case f
      when 'x' then k[0] = x * M_TO_IN
      when 'y' then k[1] = x * M_TO_IN
      when 'z' then k[2] = x * M_TO_IN
      when 'ground'
        g = ke_ground(e.model, k) or return ke_push
        k[2] += x * M_TO_IN - g
      when 'az'    then ke_from_angles(k, x, pitch, roll)
      when 'pitch' then ke_from_angles(k, az, x, roll)
      when 'roll'  then ke_from_angles(k, az, pitch, x)
      when 'fov'   then k[9] = x.clamp(1.0, 170.0)
      when 'zoom'  then k[9] = (2 * Math.atan(Math.tan(KEY_FOV0 * Math::PI / 360) / x.clamp(0.05, 50.0)) * 180 / Math::PI).clamp(1.0, 170.0)
      when 'pause' then k[10] = x.clamp(0.0, 600.0)
      when 'v'     then k[11] = x.clamp(0.05, 50.0)
      when 'vauto' then k[11] = v == true || v.to_s == 'true' ? 0.0 : key_speed(path_data(e.get_attribute(KEY_DICT, 'path'), e.model))
      else return
      end
      ke_apply(e, k, t('ke.op'), run)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Posizione, zoom (il componente della sua freccia), sosta e velocità
    # run: gli invii di una variazione continua (destro su − o +, ~10 al
    # secondo) si fondono nella prima operazione (trasparenti): un Ctrl+Z.
    def self.ke_apply(e, k, op, run = nil)
      model = e.model
      unisci = !run.nil? && run == @ke[:run]
      @ke[:run] = run
      model.start_operation(op, true, false, unisci)
      e.transformation = key_transform(k)
      e.definition = key_def(model, k[9]) unless e.definition.get_attribute(KEY_DICT, 'fov') == k[9].round.clamp(1, 179)
      e.set_attribute(KEY_DICT, 'fov', k[9].to_f.round(2))
      { 'sosta' => k[10], 'v' => k[11] }.each do |a, val|
        val.to_f > 0 ? e.set_attribute(KEY_DICT, a, val.to_f.round(2)) : e.delete_attribute(KEY_DICT, a)
      end
      key_purge(model)
      model.commit_operation
      path_set_camera(model.active_view, k) if @ke[:preview]   # agganciata: la vista segue la sfera
      ke_push
    end

    # Selezionata la sfera del pannello; non con l'anteprima: SketchUp
    # disegna il contorno di ciò che è selezionato anche col tag spento, e
    # riquadro e cono comparirebbero in blu davanti alla camera.
    def self.ke_select(e)
      sel = e.model.selection
      sel.clear
      sel.add(e) unless @ke && @ke[:preview]
    end

    # Testo negli appunti di Windows, per «Incolla» del menu del pannello: la
    # pagina non può leggerli da sola. '' se non c'è testo.
    CF_UNICODETEXT = 13
    def self.ke_clipboard
      return '' unless ensure_win32 && @w32.IsClipboardFormatAvailable(CF_UNICODETEXT) != 0
      return '' if @w32.OpenClipboard(nil).zero?
      begin
        h = @w32.GetClipboardData(CF_UNICODETEXT)
        return '' if h.to_i.zero?
        p = @w32.GlobalLock(h)
        return '' if p.to_i.zero?
        begin
          n = [@w32.GlobalSize(h).to_i, 1 << 16].min & ~1              # al più 32 000 caratteri
          raw = Fiddle::Pointer.new(p.to_i)[0, n]
          raw = raw[0, raw.unpack('v*').index(0).to_i * 2] if raw.unpack('v*').include?(0)
          raw.force_encoding('UTF-16LE').encode('UTF-8', invalid: :replace, undef: :replace)
        ensure
          @w32.GlobalUnlock(h)
        end
      ensure
        @w32.CloseClipboard
      end
    rescue => fps_err
      log_error(__method__, fps_err)
      ''
    end

    # ── Navigazione e anteprima ───────────────────────────────────
    def self.ke_nav(dir)
      e = @ke && @ke[:inst]
      return unless key_editable?(e)
      list = key_instances(e.model)[e.get_attribute(KEY_DICT, 'path').to_s] or return
      j = list.index(e).to_i + (dir.negative? ? -1 : 1)
      return unless j.between?(0, list.size - 1)
      ke_select(list[j])
      ke_goto(list[j])
    end

    # Alla sfera n, in dolly: con l'anteprima lungo il percorso, senza
    # traslando la camera quanto si sposta la sfera.
    def self.ke_goto(n)
      e = @ke[:inst]
      @ke[:inst] = n
      view = n.model.active_view
      if key_editable?(e) && !e.equal?(n)
        a = key_of(e); b = key_of(n)
        if @ke[:preview]
          ke_dolly(view, ke_path_frames(e, n) || ->(s) { ke_mix(a, b, s) }, nil)
        else
          c = ke_cam_frame(view.camera)
          c2 = c.dup
          3.times { |i| c2[i] += b[i] - a[i] }
          ke_dolly(view, ->(s) { ke_mix(c, c2, s) }, KE_DOLLY)
        end
      end
      ke_push
    end

    def self.ke_preview(on)
      e = @ke && @ke[:inst]
      return unless key_editable?(e) && on != @ke[:preview]
      view = e.model.active_view
      @ke[:preview] = on
      ke_select(e)                                # con l'anteprima niente contorno blu
      if on
        c = view.camera
        @ke[:back] = [c.eye, c.target, c.up, c.perspective?, c.perspective? ? c.fov : nil, c.perspective? ? nil : c.height]
        from = ke_cam_frame(c); to = key_of(e)
        # le sfere si spengono, come durante la riproduzione: se no la camera
        # finisce dentro la sua e vede solo arancione
        @ke[:keys_hidden] = key_hide(e.model)
        ke_dolly(view, ->(s) { ke_mix(from, to, s) }, KE_DOLLY)
      elsif (bk = @ke[:back])
        from = ke_cam_frame(view.camera)
        eye, target, up, persp, fov, height = bk
        dir = eye.vector_to(target)
        to = path_orthonormal!([eye.x, eye.y, eye.z, dir.x, dir.y, dir.z, up.x, up.y, up.z, fov || from[9]])
        hidden = @ke[:keys_hidden]
        ke_dolly(view, ->(s) { ke_mix(from, to, s) }, KE_DOLLY) do
          cam = Sketchup::Camera.new(eye, target, up, persp, fov || 35)
          cam.height = height if height
          view.camera = cam                       # esatta com'era, anche parallela
          key_unhide(e.model, hidden)             # fuori dalla sfera si rivedono
        end
        @ke[:back] = nil
        @ke[:keys_hidden] = false
      end
      ke_push
    end

    # Fotogrammi del percorso da una sfera all'altra (anche all'indietro),
    # come funzione della frazione 0–1; nil se non sono dello stesso percorso.
    def self.ke_path_frames(e, n)
      name = e.get_attribute(KEY_DICT, 'path')
      return nil unless name == n.get_attribute(KEY_DICT, 'path')
      list = key_instances(e.model)[name.to_s] or return nil
      i = list.index(e); j = list.index(n)
      return nil unless i && j && list.size >= 2
      keys = list.map { |x| key_of(x) }
      v = key_speed(path_data(name, e.model))
      sch = key_schedule(keys, v)
      fr = key_frames(keys, v)
      t0 = i < j ? sch[i][:leave] : sch[i][:arrive]
      t1 = i < j ? sch[j][:arrive] : sch[j][:leave]
      span = (t1 - t0).abs
      dur = span.clamp(0.4, KE_PATH)
      fine = key_of(n)
      f = lambda do |s|
        next fine if s >= 1.0                        # i fotogrammi cadono a passi: si arriva esatti sulla sfera
        x = (t0 + (t1 - t0) * s) * PATH_HZ
        a = x.floor.clamp(0, fr.size - 1); b = (a + 1).clamp(0, fr.size - 1)
        ke_mix(fr[a], fr[b], x - x.floor)
      end
      [f, dur]
    end

    def self.ke_mix(a, b, s)
      path_orthonormal!((0..9).map { |i| a[i] + (b[i] - a[i]) * s })
    end

    # Dolly: la camera segue f(s), s da 0 a 1 rallentando ai capi, in dur
    # secondi (f può essere [funzione, durata]); poi il blocco, se c'è.
    def self.ke_dolly(view, f, dur, &done)
      f, dur = f if f.is_a?(Array)
      view.animation = KeDolly.new(f, dur || KE_DOLLY, done)
    end

    class KeDolly
      def initialize(f, dur, done)
        @f = f; @dur = dur; @done = done
        @t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def nextFrame(view)
        s = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @t0) / @dur).clamp(0.0, 1.0)
        e = s < 0.5 ? 2 * s * s : 1 - (-2 * s + 2)**2 / 2
        DagaWASD::FPSWalk.path_set_camera(view, @f.call(e))
        view.show_frame
        return true if s < 1.0
        @done&.call
        false
      rescue => fps_err
        DagaWASD::FPSWalk.log_error(:ke_dolly, fps_err)
        false
      end
    end

    # ── Pulsanti ──────────────────────────────────────────────────
    def self.ke_act(what)
      e = @ke && @ke[:inst]
      return unless key_editable?(e) && !@path_job
      model = e.model
      name = e.get_attribute(KEY_DICT, 'path').to_s
      list = key_instances(model)[name] || [e]
      i = list.index(e) || 0
      case what
      when 'from_view'
        k = key_of(e)
        f = ke_cam_frame(model.active_view.camera)
        ke_apply(e, f + [k[10], k[11]], t('ke.op'))
      when 'insert' then ke_insert(e, list, i)
      when 'delete' then ke_delete(e, list, i)
      end
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Dopo questa: a metà della curva verso la prossima, o due metri avanti se è l'ultima
    def self.ke_insert(e, list, i)
      model = e.model
      keys = list.map { |x| key_of(x) }
      if i < list.size - 1
        nk = key_eval(key_spline(keys), i, 0.5) + [0.0, 0.0]
      else
        nk = keys[i].dup
        3.times { |c| nk[c] += nk[c + 3] * 2.0 * M_TO_IN }
        nk[10] = 0.0; nk[11] = 0.0
      end
      model.start_operation(t('ke.op'), true)
      list.each_with_index { |x, j| x.set_attribute(KEY_DICT, 'i', j <= i ? j : j + 1) }
      n = model.entities.add_instance(key_def(model, nk[9]), key_transform(nk)) # rubocop:disable SketchupSuggestions/ModelEntities
      n.material = e.material
      n.layer = e.layer
      n.name = e.name
      n.set_attribute(KEY_DICT, 'path', e.get_attribute(KEY_DICT, 'path'))
      n.set_attribute(KEY_DICT, 'i', i + 1)
      n.set_attribute(KEY_DICT, 'fov', nk[9].to_f.round(2))
      model.commit_operation
      ke_select(n)
      ke_goto(n)
    end

    def self.ke_delete(e, list, i)
      return UI.messagebox(t('ke.min2')) if list.size <= 2
      model = e.model
      rest = list.reject { |x| x.equal?(e) }
      nxt = rest[[i, rest.size - 1].min]
      model.start_operation(t('ke.op'), true)
      e.erase!
      rest.each_with_index { |x, j| x.set_attribute(KEY_DICT, 'i', j) }
      key_purge(model)
      model.commit_operation
      ke_select(nxt)
      @ke[:inst] = nxt
      ke_push
    end

    # ── Aperture: doppio clic e Invio ─────────────────────────────
    # Doppio clic su una sfera: SketchUp entra nel componente per
    # modificarlo; se ne esce subito e si apre il pannello.
    class KeyModelObserver
      def onActivePathChanged(model); DagaWASD::FPSWalk.ke_active_path(model); end
    end

    def self.ke_active_path(model)
      e = model.active_path&.last
      return unless key_editable?(e)
      UI.start_timer(0, false) do
        model.close_active if model.active_path&.last.equal?(e)
        ke_open(e)
      end
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Invio con una sola sfera selezionata, lo strumento Seleziona attivo
    # (con gli altri Invio conferma una misura) e in primo piano la finestra
    # principale (non un dialogo: Invio nei campi del pannello non conta).
    # Dal timer dei tasti rapidi (lib/input.rb, poll_hotkey).
    def self.ke_poll_enter
      down = async_down?(VK_RETURN)
      fire = down && !@ke_enter
      @ke_enter = down
      return unless fire && !@active && !@path_job && su_main_foreground?
      model = Sketchup.active_model or return
      return unless model.tools.active_tool_id == KE_SELECT
      sel = model.selection
      ke_open(sel.first) if sel.size == 1 && key_editable?(sel.first)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # In primo piano la finestra principale di SketchUp: del processo e senza
    # proprietaria (i dialoghi ce l'hanno)
    def self.su_main_foreground?
      return false unless sketchup_foreground?
      @w32.GetWindow(@w32.GetForegroundWindow, 4).to_i.zero?   # GW_OWNER
    end

  end
end
