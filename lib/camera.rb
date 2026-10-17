# DagaWASD — Camera in prima persona (bob, roll, FOV) e zoom con la rotella.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Camera math
    # ══════════════════════════════════════════════════════════════
    def self.init_angles(cam)
      d      = cam.target - cam.eye
      @yaw   = Math.atan2(d.y, d.x)
      hor    = Math.sqrt(d.x**2 + d.y**2)
      @pitch = Math.atan2(d.z, hor + 1e-10)
    end

    def self.fwd_flat;   [Math.cos(@yaw),  Math.sin(@yaw)]; end
    def self.right_flat; [Math.sin(@yaw), -Math.cos(@yaw)]; end

    # Head bob (pollici): [verticale, laterale]. Il verticale oscilla al
    # doppio della frequenza del laterale (passo). Frequenza e ampiezza
    # seguono la velocità reale, ma l'ampiezza si ferma a BOB_Z_MAX e
    # BOB_SIDE_MAX: correndo forte la testa andava su e giù di 15 cm.
    def self.head_bob(dt, h_speed)
      return [0.0, 0.0] unless cf('head_bob_enabled')
      amp  = cf('head_bob_amp').to_f
      side = cf('head_bob_side').to_f
      if h_speed > 0.15 && @on_ground
        ref   = [cf('move_speed').to_f, 0.1].max
        ratio = (h_speed / ref).clamp(0.0, 2.2)
        @bob_phase += cf('head_bob_freq').to_f * PI2 * dt * (0.55 + ratio * 0.55)
        @bob_phase %= PI2
        amp *= ratio; side *= ratio
      else
        @bob_phase *= 0.85
        amp *= 0.12; side *= 0.12
      end
      [Math.sin(@bob_phase * 2.0) * amp.clamp(0.0, BOB_Z_MAX) * M_TO_IN,
       Math.sin(@bob_phase) * side.clamp(0.0, BOB_SIDE_MAX) * M_TO_IN]
    end

    # Applica la camera con bob verticale/laterale e inclinazione (roll).
    def self.apply_camera(view, bob_z, bob_side)
      cp = Math.cos(@pitch); sp = Math.sin(@pitch); dist = 200.0
      fx = cp * Math.cos(@yaw); fy = cp * Math.sin(@yaw); fz = sp
      rx, ry = right_flat
      ne = Geom::Point3d.new(
        @eye_x + rx * bob_side,
        @eye_y + ry * bob_side,
        @eye_z + bob_z
      )
      nt = Geom::Point3d.new(ne.x + fx * dist, ne.y + fy * dist, ne.z + fz * dist)

      # Up ortogonale alla direzione, poi ruotato di @roll attorno alla direzione:
      # dà la leggera inclinazione laterale in strafe.
      ux = -fx * fz; uy = -fy * fz; uz = 1.0 - fz * fz
      ul = Math.sqrt(ux * ux + uy * uy + uz * uz)
      if ul > 1e-6
        ux /= ul; uy /= ul; uz /= ul
        if @roll.abs > 1e-4
          # right = fwd × up   (già normalizzato: fwd e up sono ortonormali)
          sx = fy * uz - fz * uy
          sy = fz * ux - fx * uz
          sz = fx * uy - fy * ux
          cr = Math.cos(@roll); sr = Math.sin(@roll)
          ux = ux * cr + sx * sr
          uy = uy * cr + sy * sr
          uz = uz * cr + sz * sr
        end
        view.camera.set(ne, nt, Geom::Vector3d.new(ux, uy, uz))
      else
        view.camera.set(ne, nt, Geom::Vector3d.new(0, 0, 1))
      end

      # Con fov = 0 la camera del modello resta com'è finché non si zooma.
      if cf('fov').to_f > 0 || (@zoom_fov - @base_fov).abs > 0.01
        view.camera.fov = @zoom_fov; view.camera.perspective = true
      end
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # ══════════════════════════════════════════════════════════════
    # Zoom con la rotella (FOV) — chiamato da FPSTool
    # ══════════════════════════════════════════════════════════════
    # Con un oggetto in mano la rotella lo allontana (in avanti) o lo
    # avvicina; senza, fa lo zoom. Vale anche con lo zoom a rotella spento.
    HOLD_STEP = 0.15   # m per scatto
    HOLD_MIN  = 0.4    # m

    def self.on_wheel(delta)
      return false unless @active
      if @grabbed_entity&.valid?
        hi = [cf('grab_range').to_f, cf('grab_distance').to_f].max
        @hold_dist = ((@hold_dist || cf('grab_distance').to_f) + (delta > 0 ? HOLD_STEP : -HOLD_STEP)).clamp(HOLD_MIN, hi)
        Sketchup.status_text = "[#{t('rt.grab')}] ↔ #{@hold_dist.round(2)} m"
        return true
      end
      return false unless cf('wheel_zoom')
      # Rotella in avanti = zoom in. Passi moltiplicativi: ogni scatto ha
      # lo stesso effetto percepito a qualsiasi livello di zoom.
      f = delta > 0 ? 1.0 / 1.15 : 1.15
      lo = cf('zoom_min_fov').to_f.clamp(1.0, 119.0)
      @zoom_target = (@zoom_target * f).clamp(lo, 120.0)
      true
    end

    # Tasto centrale: con un oggetto in mano rimette la distanza di presa del pannello
    def self.reset_zoom
      return unless @active
      if @grabbed_entity&.valid?
        @hold_dist = cf('grab_distance').to_f
        Sketchup.status_text = "[#{t('rt.grab')}] ↔ #{@hold_dist.round(2)} m"
      else
        @zoom_target = @base_fov
      end
    end

  end
end
