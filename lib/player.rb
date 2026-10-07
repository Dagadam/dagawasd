# DagaWASD — Movimento del player: pavimento, soffitto, muri, gradini.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Utility matematiche
    # ══════════════════════════════════════════════════════════════

    # Avvicina uno scalare a `target` a `rate` unità/s², senza overshoot.
    def self.approach(cur, target, rate, dt)
      d = target - cur
      m = rate * dt
      return target if m <= 0.0 || d.abs <= m
      cur + (d > 0 ? m : -m)
    end

    # ══════════════════════════════════════════════════════════════
    # Pavimento / soffitto / muri
    # ══════════════════════════════════════════════════════════════

    # Cerca il pavimento sotto i piedi. In qualità alta sonda anche 4 punti sul
    # bordo del corpo: così il player resta appoggiato sui bordi e sugli scalini
    # invece di cadere appena il raggio centrale manca la superficie.
    # Ritorna [z_pollici, normale] oppure nil.
    def self.detect_floor(feet_z, max_up_in)
      r_in    = cf('body_radius').to_f * M_TO_IN
      quality = cf('collision_quality').to_i
      origin_z = @eye_z
      best_z = nil; best_n = nil

      probes = [[0.0, 0.0]]
      if quality >= 3
        o = r_in * 0.72
        probes += [[o, 0.0], [-o, 0.0], [0.0, o], [0.0, -o]]
      elsif quality == 2
        o = r_in * 0.72
        probes += [[o, 0.0], [0.0, o]]
      end

      probes.each do |px, py|
        res = pray(@eye_x + px, @eye_y + py, origin_z, 0, 0, -1)
        next unless res
        z = res[0].z
        next if (origin_z - z) > 12.0 * M_TO_IN     # troppo lontano: ignora
        next if z > feet_z + max_up_in              # è un gradino troppo alto
        if best_z.nil? || z > best_z
          best_z = z
          best_n = hit_normal(res, 0, 0, -1)
          @floor_hit = res                          # faccia e percorso: di che cosa è il pavimento (servirà ai suoni)
        end
      end
      best_z ? [best_z, best_n] : nil
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.detect_ceiling
      res = pray(@eye_x, @eye_y, @eye_z, 0, 0, 1)
      res ? res[0].z : nil
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Sonda un muro nella direzione (dx,dy) alle quote di controllo del corpo.
    # Ritorna nil se libero, altrimenti {n: [nx,ny], ent: entità colpita}.
    def self.wall_probe(dx, dy, radius_in)
      len_sq = dx * dx + dy * dy
      return nil if len_sq < 1e-8
      len = Math.sqrt(len_sq)
      ux  = dx / len; uy = dy / len
      reach = radius_in + len

      h_in    = @cur_h_m * M_TO_IN
      quality = cf('collision_quality').to_i
      # Quote di sonda relative all'occhio: testa, torso, caviglie.
      # Le caviglie partono sopra step_height così i gradini non risultano muri.
      ankle = -h_in + cf('step_height').to_f * M_TO_IN + 1.0
      zs = case quality
           when 1 then [-h_in * 0.45]
           when 2 then [-h_in * 0.10, -h_in * 0.55]
           else        [-h_in * 0.08, -h_in * 0.50, ankle]
           end

      best = nil; best_d = nil
      zs.each do |z|
        res = pray(@eye_x, @eye_y, @eye_z + z, ux, uy, 0)
        next unless res
        hit = res[0]
        d   = Math.sqrt((hit.x - @eye_x)**2 + (hit.y - @eye_y)**2)
        next if d >= reach
        next if best_d && d >= best_d
        best_d = d
        n = hit_normal(res, ux, uy, 0)
        nx, ny = n ? [n[0], n[1]] : [-ux, -uy]
        nl = Math.sqrt(nx * nx + ny * ny)
        if nl < 1e-6 then nx = -ux; ny = -uy else nx /= nl; ny /= nl end
        best = { n: [nx, ny], ent: (res[1].is_a?(Array) ? res[1].first : nil), d: d }
      end
      best
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Spostamento orizzontale con scivolamento sul piano del muro (invece della
    # vecchia separazione per assi), scavalcamento gradini e spinta degli oggetti.
    # dx,dy in pollici; la velocità (@vh_*) viene proiettata sul muro.
    def self.move_with_slide(dx, dy, dt)
      return if dx.abs < 0.0001 && dy.abs < 0.0001
      r = cf('body_radius').to_f * M_TO_IN
      pushed = nil   # un solo impulso per oggetto per tick

      3.times do
        hit = wall_probe(dx, dy, r)
        unless hit
          @eye_x += dx; @eye_y += dy
          return
        end

        # 1) L'ostacolo è un oggetto spingibile? → trasferisci quantità di moto
        if hit[:ent] && hit[:ent] != pushed
          pushed = hit[:ent]
          try_push_entity(hit[:ent], dx, dy, dt)
        end

        # 2) È un gradino scavalcabile? → sali e prosegui
        return if try_step_up(dx, dy, r)

        # 3) Scivola lungo il muro: rimuovi la componente entrante
        nx, ny = hit[:n]
        dot = dx * nx + dy * ny
        break if dot >= 0                     # normale già uscente: niente da fare
        dx -= nx * dot; dy -= ny * dot
        vdot = @vh_x * nx + @vh_y * ny
        if vdot < 0
          @vh_x -= nx * vdot; @vh_y -= ny * vdot
        end
        break if dx.abs < 0.0001 && dy.abs < 0.0001
      end
    end

    # Tenta di scavalcare un gradino alto fino a step_height: cerca il piano di
    # appoggio alla posizione di destinazione e verifica che ci sia spazio libero.
    def self.try_step_up(dx, dy, radius_in)
      return false unless @on_ground || @coyote > 0
      step_in = cf('step_height').to_f * M_TO_IN
      return false if step_in <= 0.5

      feet_z = @eye_z - @cur_h_m * M_TO_IN
      tx = @eye_x + dx; ty = @eye_y + dy
      # Pavimento alla destinazione, sondato dall'alto del gradino
      res = pray(tx, ty, feet_z + step_in + 1.0, 0, 0, -1)
      return false unless res
      nz = res[0].z
      rise = nz - feet_z
      return false if rise <= 0.6 || rise > step_in

      # Pendenza del gradino: se è quasi verticale non è calpestabile
      n = hit_normal(res, 0, 0, -1)
      return false if n && n[2] < Math.cos(cf('max_slope_deg').to_f * DEG)

      # Spazio sopra la testa alla nuova quota
      new_eye = nz + @cur_h_m * M_TO_IN
      up = pray(tx, ty, nz + 1.0, 0, 0, 1)
      return false if up && up[0].z < new_eye - 1.0

      @eye_x = tx; @eye_y = ty; @eye_z = new_eye
      @floor_z_in = nz; @floor_n = n
      @on_ground = true; @vv = 0.0
      true
    rescue => fps_err; log_error(__method__, fps_err); false; end

    def self.can_uncrouch?
      needed_in = (cf('eye_height').to_f - @cur_h_m) * M_TO_IN
      return true if needed_in < 1.0
      ceil_z = detect_ceiling
      return true unless ceil_z
      (ceil_z - @eye_z) > needed_in
    end

  end
end
