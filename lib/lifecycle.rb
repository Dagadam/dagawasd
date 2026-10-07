# DagaWASD — Avvio e arresto della modalità FPS; assestamento dopo l'uscita.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Start / Stop / Toggle
    # ══════════════════════════════════════════════════════════════
    def self.start
      return if @active
      return if @bridge_job     # il ponte sta costruendo: la fisica non deve entrare nella sua operazione
      stop_settle
      load_cfg

      unless ensure_win32
        UI.messagebox("DagaWASD — #{t('rt.err_win32')}:\n#{@w32_error}", MB_OK)
        return
      end

      view = Sketchup.active_model&.active_view
      return unless view
      watch_ops(Sketchup.active_model)   # voce d'annullamento della fisica (physics.rb)

      cam = view.camera
      init_angles(cam)
      @eye_x = cam.eye.x; @eye_y = cam.eye.y; @eye_z = cam.eye.z

      @vh_x = 0.0; @vh_y = 0.0; @vv = 0.0
      @on_ground      = false
      @floor_n        = nil
      @cur_h_m        = cf('eye_height').to_f
      @bob_phase      = 0.0
      @land_off       = 0.0
      @land_vel       = 0.0
      @step_smooth    = 0.0
      @roll           = 0.0
      @coyote         = 0.0
      @jump_buf       = 0.0
      @jumps_used     = 0
      @jump_cut       = false
      @prev_space     = false
      @fall_time      = 0.0
      @fall_in        = 0.0
      @left_ground_at = nil
      @safe_trail     = []
      @respawn_streak = 0
      @ground_time    = 0.0
      @mouse_freeze   = false
      @phys_entities.clear
      @body_cache.clear
      @dyn_entities.clear
      @obst = nil
      @phys_op_named = false
      invalidate_materials      # il modello può essere cambiato da un avvio all'altro
      @grabbed_entity = nil
      @grab_state     = :idle
      @charge_start   = nil
      @prev_g         = false
      @prev_alt       = false
      @prev_k         = false
      @prev_rec       = false
      @path_rec       = nil
      @kick_start     = nil
      # FOV di riferimento: quello impostato, o quello del modello se fov = 0
      @base_fov = cf('fov').to_f > 0 ? cf('fov').to_f : (cam.fov.to_f rescue 60.0)
      @base_fov = 60.0 unless @base_fov > 1.0
      @zoom_fov = @zoom_target = @base_fov

      fl = detect_floor(@eye_z - @cur_h_m * M_TO_IN, 1e9)
      if fl
        @floor_z_in = fl[0]; @floor_n = fl[1]; @on_ground = true
        @eye_z      = fl[0] + @cur_h_m * M_TO_IN
        apply_camera(view, 0.0, 0.0)
      end
      # Punto di rientro di riserva, se si cade prima di aver mai toccato terra
      @spawn_point = [@eye_x, @eye_y, @eye_z - @cur_h_m * M_TO_IN]

      unless install_hook
        UI.messagebox("DagaWASD — #{t('rt.err_hook')}:\n#{@w32_error}", MB_OK)
        return
      end

      @keys.clear
      @main_hwnd    = find_main_window
      focus_main_window
      @was_focused  = true
      @alt_injected = false
      cx, cy = viewport_center
      @w32.SetCursorPos(cx, cy)
      hide_cursor
      Sketchup.active_model.select_tool(FPSTool.new)

      @active    = true
      @last_tick = Time.now.to_f
      restart_timer

      Sketchup.status_text = hud_text
    end

    def self.restart_timer
      UI.stop_timer(@timer_id) if @timer_id
      rate      = cf('tick_rate').to_f.clamp(10, 144)
      @timer_id = UI.start_timer(1.0 / rate, true) { tick }
    end

    def self.stop
      return unless @active
      @active = false
      UI.stop_timer(@timer_id) if @timer_id
      @timer_id = nil
      remove_hook
      show_cursor
      @keys.clear
      @main_hwnd = nil
      pad_rumble_tick
      @pad = @pad_prev_btn = nil       # al rientro i pulsanti già premuti non scattano
      @step_kind_cache = nil           # materiali cambiati nel frattempo: si rileggono
      # L'oggetto in mano viene mollato e, insieme a quelli ancora in volo,
      # finisce di cadere: senza, resterebbero sospesi a mezz'aria nel modello.
      if @grabbed_entity&.valid?
        add_physics_entity(@grabbed_entity, 0.0, 0.0, 0.0)
      end
      @grabbed_entity = nil
      @grab_state     = :idle
      @kick_start     = nil
      start_settle
      # Non lasciare il modello zoomato all'uscita
      if (@zoom_fov - @base_fov).abs > 0.01
        begin; Sketchup.active_model.active_view.camera.fov = @base_fov; rescue => fps_err; log_error(__method__, fps_err); end
      end
      @zoom_fov = @zoom_target = @base_fov
      Sketchup.active_model&.select_tool(nil)
      Sketchup.status_text = t('rt.off')
      path_rec_stop                    # registrazione in corso: salvata (e lo dice)
      @dialog&.execute_script('setRunning(false)') rescue nil
    end

    # Dopo l'uscita la fisica continua da sola (senza player) finché i corpi
    # non si fermano, al massimo SETTLE_MAX secondi di simulazione.
    # Mentre il ponte costruisce dal vivo aspetta: la sua operazione resta
    # aperta fra un passo e l'altro, e una mossa della fisica lì in mezzo la
    # spezzerebbe (un errore a metà non annullerebbe più tutto). Finito il
    # lavoro riprende da dove era.
    SETTLE_MAX = 4.0

    def self.start_settle
      stop_settle
      return finish_settle if @phys_entities.empty?
      @last_settle = Time.now.to_f
      @settle_t    = 0.0
      @settle_timer = UI.start_timer(1.0 / 60, true) { settle_tick }
    end

    def self.settle_tick
      now = Time.now.to_f
      dt  = (now - @last_settle).clamp(0.001, 0.1)
      @last_settle = now
      return if @bridge_job
      @settle_t += dt
      step_physics(dt)
      finish_settle if @phys_entities.empty? || @settle_t > SETTLE_MAX
    end

    def self.stop_settle
      UI.stop_timer(@settle_timer) if @settle_timer
      @settle_timer = nil
    end

    def self.finish_settle
      stop_settle
      @phys_entities.clear
      @body_cache.clear
    end

    def self.toggle; @active ? stop : start; end

  end
end
