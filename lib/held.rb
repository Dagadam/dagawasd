# DagaWASD — Oggetto tenuto in mano: inseguimento, ostacoli, spinta, rilascio.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Oggetto tenuto in mano — inseguimento elastico
    # ══════════════════════════════════════════════════════════════
    def self.update_grabbed_position(dt)
      return unless @grabbed_entity&.valid?
      b = @grabbed_entity.bounds
      entity_r = Math.sqrt(
        (b.max.x - b.min.x)**2 + (b.max.y - b.min.y)**2 + (b.max.z - b.min.z)**2
      ) * 0.5
      min_dist = cf('body_radius').to_f * M_TO_IN + entity_r
      dist_in  = [(@hold_dist || cf('grab_distance').to_f) * M_TO_IN + entity_r, min_dist].max   # rotella: vedi on_wheel
      cp = Math.cos(@pitch)
      tx = @eye_x + Math.cos(@yaw) * cp * dist_in
      ty = @eye_y + Math.sin(@yaw) * cp * dist_in
      tz = @eye_z + Math.sin(@pitch) * dist_in
      cx = (b.min.x + b.max.x) * 0.5
      cy = (b.min.y + b.max.y) * 0.5
      cz = (b.min.z + b.max.z) * 0.5

      # ── Strappo iniziale: l'ambiente non conta ─────────────────────
      # Un oggetto accostato a un muro o infilato sotto un tavolo partirebbe
      # già incastrato. Nei primi istanti viene quindi portato di forza
      # verso il player (a un passo dagli occhi) e poi alla distanza di
      # presa, attraversando qualsiasi cosa. Solo dopo le collisioni tornano.
      pull_t = cf('grab_pull_time').to_f.clamp(0.0, 2.0)   # durate dal pannello (0 = fase saltata)
      out_t  = cf('grab_out_time').to_f.clamp(0.0, 2.0)
      # Almeno GRAB_MIN_FRAMES fotogrammi: con la vista lenta da ridisegnare
      # (ombre, texture, modelli pesanti) un passo vale fino a 0,1 s e lo
      # strappo, che dura 0,4 s, si ridurrebbe a un salto di 3–4 fotogrammi.
      step = pull_t + out_t > 0 ? [dt, (pull_t + out_t) / GRAB_MIN_FRAMES].min : dt
      @grab_t = (@grab_t || 0.0) + step
      if @grab_t < pull_t + out_t
        near_in = min_dist + 2.0
        nx = @eye_x + Math.cos(@yaw) * cp * near_in
        ny = @eye_y + Math.sin(@yaw) * cp * near_in
        nz = @eye_z + Math.sin(@pitch) * near_in
        if @grab_t < pull_t
          s = smoothstep(@grab_t / pull_t)          # dalla posizione di partenza…
          fx, fy, fz = @grab_from
          gx = fx + (nx - fx) * s; gy = fy + (ny - fy) * s; gz = fz + (nz - fz) * s
          move_held_by(gx - cx, gy - cy, gz - cz)
        else
          s = smoothstep((@grab_t - pull_t) / out_t)   # …poi alla distanza di presa
          gx = nx + (tx - nx) * s; gy = ny + (ty - ny) * s; gz = nz + (tz - nz) * s
          # Allontanandosi l'oggetto non deve attraversare nulla: vicino a una
          # libreria il punto di presa le sta dietro, e l'oggetto ci finirebbe
          # oltre. Se però è ancora dentro qualcosa (naso contro un muro)
          # resta fantasma, altrimenti rimarrebbe incastrato.
          @grab_out_free = !held_overlapping?(@grabbed_entity) if @grab_out_free.nil?
          dx = gx - cx; dy = gy - cy; dz = gz - cz
          dx, dy, dz = held_sweep(@grabbed_entity, dx, dy, dz, dt) if @grab_out_free
          move_held_by(dx, dy, dz)
        end
        @held_block = 0.0
        return
      end

      # Finito lo strappo, se l'oggetto è ancora dentro qualcosa (player col
      # naso contro un muro) resta "fantasma" finché non è libero, così le
      # collisioni non lo inchiodano dentro l'ostacolo. Al massimo GRAB_GHOST_MAX.
      if @grab_ghost
        @grab_ghost = false if @grab_t > pull_t + out_t + GRAB_GHOST_MAX ||
                               !held_overlapping?(@grabbed_entity)
      end

      # Inseguimento elastico: gli oggetti pesanti restano indietro.
      p = body_props(@grabbed_entity)
      k = cf('grab_spring').to_f * (20.0 / (20.0 + p[:m])).clamp(0.15, 1.0)
      a = (k * dt).clamp(0.05, 1.0)
      ddx = (tx - cx) * a; ddy = (ty - cy) * a; ddz = (tz - cz) * a
      if ddx * ddx + ddy * ddy + ddz * ddz >= 0.0025   # ≥ 0.05"
        # Non può attraversare niente: si muove fin dove è libero e scivola
        # lungo l'ostacolo per il resto del tragitto (fantasma: si muove e basta).
        mx, my, mz = @grab_ghost ? [ddx, ddy, ddz] : held_sweep(@grabbed_entity, ddx, ddy, ddz, dt)
        move_held_by(mx, my, mz)
        cx += mx; cy += my; cz += mz
      end

      # Incastrato: il punto davanti alla camera è lontano dall'oggetto, che
      # non riesce a raggiungerlo (dietro un muro, sotto un tavolo…). Dopo un
      # attimo si molla, come quando la presa ti sfugge di mano; la breve
      # attesa evita di mollarlo per il ritardo elastico di una girata veloce.
      gap = Math.sqrt((tx - cx)**2 + (ty - cy)**2 + (tz - cz)**2)
      @held_block = gap > HELD_DROP_GAP ? (@held_block || 0.0) + dt : 0.0
      drop_grabbed if @held_block > HELD_DROP_T
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.smoothstep(t)
      t = t.clamp(0.0, 1.0)
      t * t * (3.0 - 2.0 * t)
    end

    def self.move_held_by(mx, my, mz)
      return if mx * mx + my * my + mz * mz <= 1e-4
      @grabbed_entity.transformation =
        Geom::Transformation.translation(Geom::Vector3d.new(mx, my, mz)) *
        @grabbed_entity.transformation
    end

    # L'oggetto in mano ha dentro di sé geometria altrui? Dal baricentro
    # partono raggi verso i suoi punti di superficie: se uno incontra
    # qualcos'altro prima di arrivarci, c'è compenetrazione. La fase larga
    # evita i raggi quando attorno non c'è l'ingombro di niente.
    def self.held_overlapping?(entity)
      b = entity.bounds
      q = [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z]
      return false unless obstacles_near?(q, entity)
      geo = body_props(entity)[:geo]
      com = com_world(entity)
      pts = if geo && geo[:probe] && !geo[:probe].empty?
              xform_all(geo[:probe].first(16), entity.transformation.to_a)   # i 16 più distribuiti
            else
              ob = obb(entity)
              ob ? ob[:corners].map { |c| [c.x, c.y, c.z] } : []
            end
      pts.any? do |x, y, z|
        vx = x - com.x; vy = y - com.y; vz = z - com.z
        d = Math.sqrt(vx * vx + vy * vy + vz * vz)
        next false if d < 1e-3
        res = ray_ignoring(com.x, com.y, com.z, vx, vy, vz, entity, 6)
        res && com.distance(res[0]) < d - HELD_SKIN
      end
    rescue => fps_err
      log_error(__method__, fps_err)
      false
    end

    # ── Fase larga: griglia degli ingombri della scena ────────────────
    # Costruita una volta a ogni presa: per ogni entità del modello (gruppi,
    # componenti, facce e spigoli sciolti) il suo ingombro va nelle celle di
    # una griglia da ~1 m. Gli ingombri enormi (un pavimento di 50 m) vanno
    # in una lista a parte, controllata sempre. Gli oggetti che la fisica ha
    # mosso (@dyn_entities) si controllano invece sulla posizione attuale.
    GRID_CELL      = 40.0   # pollici
    GRID_MAX_CELLS = 64     # oltre, l'ingombro va nella lista "grandi"

    def self.build_obstacle_grid(skip)
      grid = Hash.new { |h, k| h[k] = [] }; big = []
      # Ostacoli: tutto il modello, anche se si sta modificando un gruppo
      Sketchup.active_model.entities.each do |e| # rubocop:disable SketchupSuggestions/ModelEntities
        next if e == skip || !e.valid?
        b = e.bounds
        next if b.empty?
        box = [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z, e]
        i0, j0, k0 = (box[0] / GRID_CELL).floor, (box[1] / GRID_CELL).floor, (box[2] / GRID_CELL).floor
        i1, j1, k1 = (box[3] / GRID_CELL).floor, (box[4] / GRID_CELL).floor, (box[5] / GRID_CELL).floor
        if (i1 - i0 + 1) * (j1 - j0 + 1) * (k1 - k0 + 1) > GRID_MAX_CELLS
          big << box
        else
          (i0..i1).each { |i| (j0..j1).each { |j| (k0..k1).each { |k| grid[[i, j, k]] << box } } }
        end
      end
      @obst = { grid: grid, big: big }
    rescue => fps_err
      log_error(__method__, fps_err)
      @obst = nil
    end

    # Entità il cui ingombro tocca q: dalla griglia (costruita se manca) più
    # quelle mosse dalla fisica, controllate sulla posizione attuale.
    def self.nearby_entities(q, skip = nil)
      build_obstacle_grid(@grabbed_entity) unless @obst
      out = {}
      @dyn_entities.each do |e|
        next if e == skip || !e.valid?
        b = e.bounds
        out[e] = true if box_overlap?(q, [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z])
      end
      return out.keys unless @obst
      take = ->(b) { out[b[6]] = true if b[6] != skip && !@dyn_entities.include?(b[6]) && b[6].valid? && box_overlap?(q, b) }
      @obst[:big].each(&take)
      i0, j0, k0 = (q[0] / GRID_CELL).floor, (q[1] / GRID_CELL).floor, (q[2] / GRID_CELL).floor
      i1, j1, k1 = (q[3] / GRID_CELL).floor, (q[4] / GRID_CELL).floor, (q[5] / GRID_CELL).floor
      (i0..i1).each do |i|
        (j0..j1).each do |j|
          (k0..k1).each { |k| (@obst[:grid].fetch([i, j, k], nil) || []).each(&take) }
        end
      end
      out.keys
    end

    def self.box_overlap?(q, b)
      q[0] <= b[3] && q[3] >= b[0] && q[1] <= b[4] && q[4] >= b[1] && q[2] <= b[5] && q[5] >= b[2]
    end

    # C'è qualcosa (oltre a `skip`) il cui ingombro tocca la scatola q
    # [x0, y0, z0, x1, y1, z1]? Se non si può dire, risponde sì (prudente).
    def self.obstacles_near?(q, skip)
      @dyn_entities.each do |e|
        next if e == skip || !e.valid?
        b = e.bounds
        return true if box_overlap?(q, [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z])
      end
      build_obstacle_grid(skip) unless @obst
      return true unless @obst
      test = ->(b) { b[6] != skip && !@dyn_entities.include?(b[6]) && box_overlap?(q, b) }
      return true if @obst[:big].any?(&test)
      i0, j0, k0 = (q[0] / GRID_CELL).floor, (q[1] / GRID_CELL).floor, (q[2] / GRID_CELL).floor
      i1, j1, k1 = (q[3] / GRID_CELL).floor, (q[4] / GRID_CELL).floor, (q[5] / GRID_CELL).floor
      (i0..i1).each do |i|
        (j0..j1).each do |j|
          (k0..k1).each do |k|
            cell = @obst[:grid].fetch([i, j, k], nil)
            return true if cell && cell.any?(&test)
          end
        end
      end
      false
    end

    # Spostamento dell'oggetto in mano senza compenetrazioni.
    # 1. Fase larga: se nella zona attraversata non c'è l'ingombro di niente
    #    (il caso comune: oggetto sollevato in aria) si muove libero, senza
    #    lanciare nemmeno un raggio.
    # 2. Altrimenti, dai punti di superficie sul lato che avanza (al massimo
    #    HELD_LEAD, appena rientrati verso il baricentro così che un oggetto
    #    appoggiato non "strisci" sul pavimento) parte un raggio nella
    #    direzione del moto: il più corto stabilisce fin dove si può andare.
    #    Il moto che resta viene proiettato sul piano dell'ostacolo
    #    (scivolamento) e si riprova una volta.
    # Ritorna lo spostamento consentito [x, y, z] in pollici.
    HELD_LEAD = 12

    def self.held_sweep(entity, dx, dy, dz, dt = nil)
      b   = entity.bounds
      pad = HELD_SKIN + 0.5
      q = [[b.min.x, b.min.x + dx].min - pad, [b.min.y, b.min.y + dy].min - pad,
           [b.min.z, b.min.z + dz].min - pad, [b.max.x, b.max.x + dx].max + pad,
           [b.max.y, b.max.y + dy].max + pad, [b.max.z, b.max.z + dz].max + pad]
      return [dx, dy, dz] unless obstacles_near?(q, entity)

      geo = body_props(entity)[:geo]
      com = com_world(entity)
      raw = if geo && geo[:probe] && !geo[:probe].empty?
              xform_all(geo[:probe], entity.transformation.to_a)
            else
              ob = obb(entity)
              ob ? ob[:corners].map { |c| [c.x, c.y, c.z] } : []
            end
      return [dx, dy, dz] if raw.empty?
      # [punto rientrato, direzione dal baricentro (per scegliere il lato che avanza)]
      probes = raw.map do |x, y, z|
        vx = com.x - x; vy = com.y - y; vz = com.z - z
        l = Math.sqrt(vx * vx + vy * vy + vz * vz)
        s = l > 1e-6 ? [HELD_INSET, l * 0.5].min / l : 0.0
        [[x + vx * s, y + vy * s, z + vz * s], l > 1e-6 ? [-vx / l, -vy / l, -vz / l] : [0.0, 0.0, 0.0]]
      end

      mx = my = mz = 0.0
      rx = dx; ry = dy; rz = dz
      pushed = false
      2.times do
        len = Math.sqrt(rx * rx + ry * ry + rz * rz)
        break if len < 0.02
        ux = rx / len; uy = ry / len; uz = rz / len
        # Solo il lato che avanza può urtare qualcosa: i punti più "davanti"
        # rispetto alla direzione del moto (con un po' di fianchi, per gli spigoli).
        lead = probes.map { |pt, n| [pt, n[0] * ux + n[1] * uy + n[2] * uz] }
                     .select { |_, d| d > -0.3 }.max_by(HELD_LEAD) { |_, d| d }.map(&:first)
        best = len; bn = nil; bent = nil
        lead.each do |x, y, z|
          ox = x + mx; oy = y + my; oz = z + mz
          res = ray_ignoring(ox, oy, oz, ux, uy, uz, entity, 6)
          next unless res
          h = res[0]
          d = Math.sqrt((h.x - ox)**2 + (h.y - oy)**2 + (h.z - oz)**2) - HELD_SKIN
          next if d >= best
          best = [d, 0.0].max
          bn   = hit_normal(res, ux, uy, uz)
          bent = res[1].is_a?(Array) ? res[1].first : nil
        end
        mx += ux * best; my += uy * best; mz += uz * best
        break unless bn                       # nessun ostacolo sul tragitto
        # Se l'ostacolo è un oggetto leggero, l'oggetto in mano lo spinge via
        # (una volta per tick): al tick dopo, il passaggio è libero.
        if dt && bent && !pushed
          pushed = true
          held_push(entity, bent, ux, uy, uz, len / dt)
        end
        # Resto del moto proiettato sul piano dell'ostacolo
        rem = len - best
        rx = ux * rem; ry = uy * rem; rz = uz * rem
        dot = rx * bn[0] + ry * bn[1] + rz * bn[2]
        break if dot >= 0
        rx -= bn[0] * dot; ry -= bn[1] * dot; rz -= bn[2] * dot
      end
      [mx, my, mz]
    rescue => fps_err
      log_error(__method__, fps_err)
      [0.0, 0.0, 0.0]
    end

    # L'oggetto in mano urta `other` muovendosi a speed pollici/s lungo u:
    # se `other` è un oggetto spingibile gli cede quantità di moto, in
    # proporzione alle masse. L'ambiente (enorme o contenitore) non si muove.
    def self.held_push(held, other, ux, uy, uz, speed)
      return unless cf('push_enabled')
      return unless other.is_a?(Sketchup::ComponentInstance) || other.is_a?(Sketchup::Group)
      return unless other.valid? && other != held
      bo = other.bounds; bh = held.bounds
      return if bo.diagonal > GEO_MAX_DIAG
      return if bo.min.x <= bh.min.x && bo.min.y <= bh.min.y && bo.min.z <= bh.min.z &&
                bo.max.x >= bh.max.x && bo.max.y >= bh.max.y && bo.max.z >= bh.max.z
      po = body_props(other)
      return if po[:m] > cf('push_max_mass').to_f
      mh = body_props(held)[:m]
      v  = speed * IN_TO_M * mh / (mh + po[:m]) * 0.8   # m/s ceduti all'altro oggetto
      return if v < 0.05
      j  = v * po[:m]
      apply_impulse(other, ux * j, uy * j, uz * j)
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Molla l'oggetto in mano: torna alla fisica, fermo, e cade.
    # msg_key: 'rt.grab_lost' (sfuggito, incastrato) o 'rt.grab_drop' (posato)
    def self.drop_grabbed(msg_key = 'rt.grab_lost')
      e = @grabbed_entity
      @grabbed_entity = nil; @grab_state = :idle; @charge_start = nil; @held_block = 0.0
      return unless e&.valid?
      add_physics_entity(e, 0.0, 0.0, 0.0)
      Sketchup.status_text = "[#{t('rt.grab')}] #{entity_label(e)} — #{t(msg_key)}"
    rescue => fps_err; log_error(__method__, fps_err); nil; end

  end
end
