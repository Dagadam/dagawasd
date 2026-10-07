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
