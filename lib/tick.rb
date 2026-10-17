# DagaWASD — Ciclo principale: mouse, movimento, salto, interazioni, camera.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Tick principale
    # ══════════════════════════════════════════════════════════════
    def self.tick
      return unless @active
      view = Sketchup.active_model&.active_view
      return unless view

      now  = Time.now.to_f
      dt   = (now - @last_tick).clamp(0.001, 0.1)
      @last_tick = now

      # ── Mouse look ──────────────────────────────────────────────
      # Solo con la finestra principale in primo piano: altrimenti il mouse
      # verrebbe riportato di continuo al centro di SketchUp mentre usi
      # un'altra applicazione. Al ritorno si ricentra senza scatto.
      focused = main_focused?
      if focused && !@was_focused && !@mouse_freeze
        c0x, c0y = viewport_center
        @w32.SetCursorPos(c0x, c0y)
      end
      @was_focused = focused
      if !@mouse_freeze && focused
        cx, cy = viewport_center
        mx, my = cursor_pos
        dx = mx - cx; dy = my - cy
        @w32.SetCursorPos(cx, cy) unless dx == 0 && dy == 0
        # Zoomando la mira rallenta in proporzione: stesso movimento del
        # mouse = stesso spostamento sullo schermo a qualsiasi zoom.
        sens    = cf('mouse_sensitivity').to_f * (@zoom_fov / [@base_fov, 1.0].max).clamp(0.05, 2.0)
        @yaw   -= dx * sens
        @yaw    = @yaw % PI2
        ysign   = cf('invert_y') ? 1.0 : -1.0
        @pitch += dy * sens * ysign
        @pitch  = @pitch.clamp(-PITCH_LIMIT, PITCH_LIMIT)
      end
      pad_look(dt) if focused

      # ── Gamepad: letto solo in primo piano, come il mouse ───────
      if focused
        pad_poll(now)
        pad_stick_look(dt)
        if pad_buttons(dt) == :stop
          stop
          return
        end
      else
        @pad = nil
      end
      pad_rumble_tick(dt)

      # ── Accovacciamento (prima del movimento: influenza la velocità) ──
      forced_crouch = !pressed?('crouch') && !can_uncrouch?
      crouching     = pressed?('crouch') || forced_crouch
      # Accovacciati mai più alti che in piedi (anche con valori scambiati a mano)
      target_h      = crouching ? [cf('crouch_height').to_f, cf('eye_height').to_f].min : cf('eye_height').to_f
      alpha         = (cf('crouch_transition').to_f * dt).clamp(0.0, 1.0)
      @cur_h_m     += (target_h - @cur_h_m) * alpha

      # ── Velocità desiderata (normalizzata: niente boost in diagonale) ──
      f = ((pressed?('forward') || key?(VK_UP))    ? 1 : 0) - ((pressed?('back') || key?(VK_DOWN)) ? 1 : 0)
      r = ((pressed?('right')   || key?(VK_RIGHT)) ? 1 : 0) - ((pressed?('left') || key?(VK_LEFT)) ? 1 : 0)
      # Tastiera ferma: leva sinistra del gamepad, analogica (poco = piano)
      mag = 1.0
      if f == 0 && r == 0 && (pm = pad_move)
        r, f = pm
        mag = Math.sqrt(f * f + r * r).clamp(0.0, 1.0)
      end
      fx, fy = fwd_flat; rx, ry = right_flat

      speed = cf('move_speed').to_f * mag
      speed *= cf('sprint_multiplier').to_f if pressed?('run') && !crouching
      speed *= cf('crouch_speed_mul').to_f  if crouching
      # Andatura: indietro e strafe puro più lenti dell'avanti (con la leva:
      # "puro" = quasi di lato)
      speed *= if    f < -0.2 then cf('back_speed_mul').to_f
               elsif f.abs <= 0.2 && r != 0 then cf('strafe_speed_mul').to_f
               else 1.0
               end

      tgt_x = 0.0; tgt_y = 0.0
      if f != 0 || r != 0
        wx = fx * f + rx * r
        wy = fy * f + ry * r
        wl = Math.sqrt(wx * wx + wy * wy)
        if wl > 1e-6
          tgt_x = wx / wl * speed
          tgt_y = wy / wl * speed
        end
      end

      # ── Accelerazione / inerzia ─────────────────────────────────
      # A terra si accelera e si frena ai ratei configurati; in aria il
      # controllo è ridotto (air_control) → il salto conserva lo slancio.
      base       = cf('move_speed').to_f * cf('sprint_multiplier').to_f
      accel_rate = base / [cf('accel_time').to_f, 0.01].max
      decel_rate = base / [cf('decel_time').to_f, 0.01].max
      unless @on_ground
        ac = cf('air_control').to_f.clamp(0.0, 1.0)
        accel_rate *= ac
        decel_rate *= ac
      end
      ax = (tgt_x.abs >= @vh_x.abs && tgt_x * @vh_x >= 0) ? accel_rate : decel_rate
      ay = (tgt_y.abs >= @vh_y.abs && tgt_y * @vh_y >= 0) ? accel_rate : decel_rate
      @vh_x = approach(@vh_x, tgt_x, ax, dt)
      @vh_y = approach(@vh_y, tgt_y, ay, dt)

      # ── Scivolamento su pendenze troppo ripide ──────────────────
      steep = false
      if @on_ground && @floor_n
        cos_max = Math.cos(cf('max_slope_deg').to_f * DEG)
        nz = @floor_n[2]
        if nz > 0.05 && nz < cos_max
          steep = true
          gx = @floor_n[0]; gy = @floor_n[1]
          gl = Math.sqrt(gx * gx + gy * gy)
          if gl > 1e-4
            acc = cf('slide_accel').to_f * dt
            @vh_x += gx / gl * acc
            @vh_y += gy / gl * acc
          end
        end
      end

      mdx = @vh_x * dt * M_TO_IN
      mdy = @vh_y * dt * M_TO_IN
      # Salvato prima dello spostamento: move_with_slide può scavalcare un
      # gradino e aggiornare @floor_z_in da sé (serve allo stair smoothing).
      prev_floor = @floor_z_in
      move_with_slide(mdx, mdy, dt)

      # ── Rilevamento pavimento ────────────────────────────────────
      snap_in   = cf('floor_snap_distance').to_f * M_TO_IN
      step_in   = cf('step_height').to_f * M_TO_IN
      # Salendo una rampa i piedi finiscono sotto la nuova quota: la tolleranza
      # verso l'alto cresce con la distanza percorsa e la pendenza ammessa.
      # A terra vale almeno step_height, altrimenti un gradino più basso della
      # soglia-muro verrebbe attraversato invece che salito.
      travel_in = Math.sqrt(mdx * mdx + mdy * mdy)
      up_allow  = snap_in + travel_in * Math.tan(cf('max_slope_deg').to_f * DEG) + 1.0
      up_allow  = [up_allow, step_in + 1.0].max if @on_ground || @coyote > 0
      # In caduta, con la vista lenta un passo vale fino a 0,1 s: i piedi
      # possono aver superato il pavimento di più della tolleranza (a 15 fps
      # già cadendo da 1,75 m). Conta anche il tratto sceso nell'ultimo passo,
      # altrimenti il pavimento sembrerebbe un gradino troppo alto e lo si
      # attraverserebbe.
      up_allow += @fall_in if !@on_ground && @vv < 0
      feet_z    = @eye_z - @cur_h_m * M_TO_IN
      fl        = detect_floor(feet_z, up_allow)
      was_grounded = @on_ground

      if fl
        floor_z = fl[0]
        dist    = feet_z - floor_z
        if dist <= snap_in && dist >= -up_allow && @vv <= 0
          @on_ground  = true
          @floor_z_in = floor_z
          @floor_n    = fl[1]
        else
          @on_ground = false
        end
      else
        @on_ground = false
      end

      # Stair smoothing: salendo (o scendendo) un gradino la quota dell'occhio
      # cambierebbe di scatto. La camera resta indietro dello stesso salto e
      # recupera in ~0.1 s, così le scale scorrono fluide.
      if @on_ground && was_grounded && prev_floor
        rise = @floor_z_in - prev_floor
        if rise.abs > 1.0 && rise.abs <= step_in + 2.0
          @step_smooth = (@step_smooth - rise).clamp(-step_in - 2.0, step_in + 2.0)
        end
      end
      @step_smooth = approach(@step_smooth, 0.0, (step_in + 4.0) * 9.0, dt)

      # Atterraggio: dip della camera proporzionale all'impatto
      if @on_ground && !was_grounded
        impact = @vv.abs
        # Impulso alla molla della camera: una caduta da ~3 m (≈8 m/s) con
        # land_dip 0.10 produce un abbassamento di picco di ~8 cm.
        @land_vel -= [impact * cf('land_dip').to_f, 1.5].min if impact > 1.5
        pad_rumble((impact - 3.0) / 9.0) if impact > 3.5
        @jumps_used = 0
      end

      @coyote = cf('coyote_time').to_f if was_grounded && !@on_ground && @vv <= 0
      @coyote = (@coyote - dt).clamp(0.0, 1.0) unless @on_ground
      # Camminare giù da un bordo consuma il primo salto una volta scaduto il coyote
      @jumps_used = 1 if !@on_ground && @jumps_used == 0 && @coyote <= 0

      # ── Soffitto ────────────────────────────────────────────────
      if @vv > 0
        ceil_z = detect_ceiling
        @vv = 0.0 if ceil_z && ceil_z <= @eye_z + @vv * dt * M_TO_IN + 0.05 * M_TO_IN
      end

      # ── Salto (buffer + coyote + multi-salto) ───────────────────
      space_now = pressed?('jump')
      @jump_buf = cf('jump_buffer').to_f if space_now && !@prev_space
      @jump_buf = (@jump_buf - dt).clamp(0.0, 1.0) if @jump_buf > 0

      if @jump_buf > 0 && !steep
        max_jumps = [cf('max_jumps').to_i, 1].max
        if @jumps_used == 0 && (@on_ground || @coyote > 0)
          @vv = cf('jump_force').to_f
          @jumps_used = 1; @on_ground = false; @coyote = 0.0; @jump_buf = 0.0
          @jump_cut = true
        elsif @jumps_used >= 1 && @jumps_used < max_jumps
          @vv = cf('jump_force').to_f
          @jumps_used += 1; @jump_buf = 0.0; @jump_cut = true
        end
      end

      # Variable jump: rilasciando Space durante la salita il salto si accorcia
      if @jump_cut && @vv > 0 && !space_now
        @vv *= cf('jump_cut_factor').to_f.clamp(0.1, 1.0)
        @jump_cut = false
      elsif @vv <= 0 || @on_ground
        @jump_cut = false
      end
      @prev_space = space_now

      # ── Fisica verticale ─────────────────────────────────────────
      if @on_ground
        @vv      = 0.0
        @fall_in = 0.0
        @eye_z   = @floor_z_in + @cur_h_m * M_TO_IN
      else
        @vv   -= cf('gravity').to_f * dt
        @vv    = @vv.clamp(-cf('max_fall_speed').to_f, cf('jump_force').to_f * 1.6)
        dz_in  = (@vv * dt * M_TO_IN).clamp(-3.0 * M_TO_IN, 3.0 * M_TO_IN)
        @eye_z += dz_in
        @fall_in = dz_in < 0 ? -dz_in : 0.0   # pollici scesi in questo passo (vedi up_allow)
      end
      track_fall(now, dt, steep)
      if cf('respawn_enabled') && @fall_time >= cf('respawn_fall_time').to_f
        fall_respawn(now)
        # Sicurezza: se si ricade subito dopo il rientro, il punto di rientro
        # non regge; si esce dalla modalità invece di cadere all'infinito.
        if respawn_exit?
          apply_camera(view, 0.0, 0.0)
          stop
          Sketchup.status_text = t('rt.respawn_exit')
          return
        end
      end

      # ── Head bob + dip d'atterraggio + roll ──────────────────────
      bob_z, bob_side = head_bob(dt, Math.sqrt(@vh_x**2 + @vh_y**2))   # camera.rb

      # Molla smorzata per il dip d'atterraggio (m)
      if @land_off.abs > 1e-5 || @land_vel.abs > 1e-5
        acc = -110.0 * @land_off - 15.0 * @land_vel
        @land_vel += acc * dt
        @land_off += @land_vel * dt
        bob_z += @land_off * M_TO_IN
      end

      # Residuo dello stair smoothing (già in pollici)
      bob_z += @step_smooth

      # Roll: inclinazione laterale proporzionale allo strafe
      roll_max = cf('cam_roll').to_f * DEG
      lat      = @vh_x * rx + @vh_y * ry          # componente laterale (m/s)
      ref_spd  = [cf('move_speed').to_f, 0.1].max
      roll_tgt = (-lat / ref_spd).clamp(-1.0, 1.0) * roll_max
      @roll   += (roll_tgt - @roll) * (8.0 * dt).clamp(0.0, 1.0)

      # ── Interazioni (Alt / K / G) ────────────────────────────────
      alt_now = pressed?('use')
      k_now   = pressed?('kick')
      g_now   = pressed?('grab')

      do_use  if alt_now && !@prev_alt

      # Calcio: tenere premuto K carica, rilasciare calcia. Con carica 0 s
      # il calcio parte subito alla pressione, a piena forza.
      if k_now && !@prev_k
        if cf('kick_charge_time').to_f <= 0
          do_kick(1.0)
        else
          @kick_start = Time.now.to_f
          Sketchup.status_text = "[#{t('rt.kick')}] #{t('rt.kick_charge')}"
        end
      end
      if !k_now && @prev_k && @kick_start
        do_kick(charge_ratio(@kick_start, cf('kick_charge_time')))
        @kick_start = nil
      end

      if g_now && !@prev_g
        case @grab_state
        when :idle
          do_grab(shift? && kb('grab') != VK_SHIFT)   # Shift+G = pezzo interno al gruppo
        when :holding
          @grab_state   = :charging
          @charge_start = Time.now.to_f
          Sketchup.status_text = "[#{t('rt.grab')}] #{t('rt.grab_charge')}"
        end
      end
      do_throw if !g_now && @prev_g && @grab_state == :charging

      @prev_alt = alt_now; @prev_k = k_now; @prev_g = g_now
      rec_now = pressed?('record')
      path_rec_toggle(now) if rec_now && !@prev_rec
      @prev_rec = rec_now

      # ── Fisica oggetti ───────────────────────────────────────────
      step_physics(dt)

      # ── Camera ───────────────────────────────────────────────────
      @zoom_fov += (@zoom_target - @zoom_fov) * (12.0 * dt).clamp(0.0, 1.0)
      apply_camera(view, bob_z, bob_side)
      path_rec_tick(now, view) if @path_rec
      view.invalidate

    rescue => e
      log_error(__method__, e)
      Sketchup.status_text = "#{t('rt.err_tick')}: #{e.message[0, 120]}"
    end

    # ══════════════════════════════════════════════════════════════
    # Sguardo col tastierino (4 6 8 2), per quando manca il mouse
    # Anche due tasti insieme (in diagonale) e anche col mouse sbloccato
    # da F. Si parte a un quarto della velocità e si arriva al massimo in
    # pad_look_accel s, così un tocco breve basta per mirare fine. Come col
    # mouse, zoomando la rotazione rallenta e invert_y vale anche qui.
    # ══════════════════════════════════════════════════════════════
    def self.pad_look(dt)
      h = (key?(:pad_left) ? 1 : 0) - (key?(:pad_right) ? 1 : 0)
      v = (key?(:pad_up)   ? 1 : 0) - (key?(:pad_down)  ? 1 : 0)
      if h == 0 && v == 0
        @pad_held = 0.0
        return
      end
      @pad_held = (@pad_held || 0.0) + dt
      acc  = cf('pad_look_accel').to_f
      ramp = acc > 0 ? (@pad_held / acc).clamp(0.0, 1.0) : 1.0
      k    = (0.25 + 0.75 * ramp) * DEG * dt * (@zoom_fov / [@base_fov, 1.0].max).clamp(0.05, 2.0)
      @yaw   = (@yaw + h * cf('pad_look_speed').to_f * k) % PI2
      ysign  = cf('invert_y') ? -1.0 : 1.0
      @pitch = (@pitch + v * cf('pad_look_speed_v').to_f * k * ysign).clamp(-PITCH_LIMIT, PITCH_LIMIT)
    end

    # ══════════════════════════════════════════════════════════════
    # Caduta nel vuoto → respawn
    # A terra si tiene una scia delle ultime posizioni (una ogni 0,1 s, per
    # SAFE_TRAIL s); in aria la scia si ferma e si conta solo la caduta vera
    # (velocità verticale negativa), così un salto lungo non la accumula.
    # Si rientra dal punto di SAFE_BACK s prima di lasciare il suolo: il
    # bordo da cui si è caduti sarebbe troppo vicino al vuoto.
    # ══════════════════════════════════════════════════════════════
    SAFE_TRAIL = 3.0
    SAFE_BACK  = 0.5
    # respawn_exit_count respawn di seguito escono dalla modalità (0 = mai);
    # la serie si azzera dopo respawn_calm_time s a terra senza interruzioni.
    def self.respawn_exit?
      n = cf('respawn_exit_count').to_i
      n > 0 && @respawn_streak >= n
    end

    def self.track_fall(now, dt, steep)
      if @on_ground
        @fall_time = 0.0
        @left_ground_at = nil
        @ground_time += dt
        @respawn_streak = 0 if @ground_time >= cf('respawn_calm_time').to_f
        return if steep       # un pendio da cui si scivola non è un buon punto di rientro
        last = @safe_trail.last
        @safe_trail << [now, @eye_x, @eye_y, @floor_z_in] if last.nil? || now - last[0] >= 0.09
        @safe_trail.shift while @safe_trail.size > 1 && now - @safe_trail.first[0] > SAFE_TRAIL
      else
        @ground_time = 0.0
        @left_ground_at ||= now
        @fall_time += dt if @vv < 0
      end
    end

    def self.fall_respawn(now)
      cutoff = (@left_ground_at || now) - SAFE_BACK
      spot   = @safe_trail.reverse.find { |e| e[0] <= cutoff } || @safe_trail.first
      x, y, z = spot ? spot[1, 3] : @spawn_point
      return unless x
      @eye_x = x; @eye_y = y
      @eye_z = z + @cur_h_m * M_TO_IN
      @floor_z_in = z; @on_ground = true
      @vh_x = @vh_y = @vv = 0.0
      @jumps_used = 0; @coyote = 0.0; @jump_buf = 0.0; @jump_cut = false
      @land_off = @land_vel = 0.0; @step_smooth = 0.0
      @fall_time = 0.0; @left_ground_at = nil; @fall_in = 0.0
      @ground_time = 0.0; @respawn_streak += 1
      Sketchup.status_text = t('rt.respawn')
    end

  end
end
