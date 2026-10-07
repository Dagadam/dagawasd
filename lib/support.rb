# DagaWASD — Appoggio di un corpo: contatto, ribaltamento, rotolamento.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Appoggio di un corpo sul piano di normale n
    # Ritorna nil se non valutabile, altrimenti un hash con kind:
    #   :curved — poggia sulla superficie curva di sfera/calotta/cilindro
    #             coricato: pc = punto di contatto, roll = :sphere|:cylinder,
    #             axis = asse del cilindro (mondo), lever = distanza
    #             orizzontale fra baricentro e contatto
    #   :poly   — poggia su vertici dell'involucro: face (≥3 punti non
    #             allineati), inside (CM dentro il poligono), pivot (punto del
    #             poligono più vicino al CM), lever, hw (involucro mondo)
    #             free = nessun punto ha davvero qualcosa sotto
    # ══════════════════════════════════════════════════════════════
    def self.body_support(entity, geo, n)
      tr  = entity.transformation
      m   = tr.to_a
      hw  = xform_all(geo[:hull], m)
      com = geo[:com].transform(tr)
      nx, ny, nz = n
      ds   = hw.map { |x, y, z| x * nx + y * ny + z * nz }
      dmin = ds.min

      # ── Contatto curvo ────────────────────────────────────────────
      # Il punto più basso della superficie analitica coincide (a meno della
      # sfaccettatura) col vertice più basso solo se è la parte curva a
      # toccare. Una semisfera appoggiata sulla faccia piana ha il punto più
      # basso della sfera ideale un raggio sotto il pavimento: resta :poly.
      if geo[:shape]
        c  = geo[:c].transform(tr); r = geo[:r]
        cd = c.x * nx + c.y * ny + c.z * nz
        tol = r * 0.03 + 0.05
        if geo[:shape] == :sphere
          if dmin - (cd - r) < tol
            pc = Geom::Point3d.new(c.x - nx * r, c.y - ny * r, c.z - nz * r)
            return { kind: :curved, roll: :sphere, pc: pc, com: com, c: c, r: r, hw: hw,
                     lever: Math.sqrt((com.x - pc.x)**2 + (com.y - pc.y)**2) }
          end
        else
          a  = geo[:axis_v].transform(tr); a.normalize!
          an = a.x * nx + a.y * ny + a.z * nz
          if an.abs < 0.07   # asse entro ~4° dall'orizzontale: è coricato
            low = cd - r * Math.sqrt([1.0 - an * an, 0.0].max) - geo[:half] * an.abs
            if dmin - low < tol
              px = nx - an * a.x; py = ny - an * a.y; pz = nz - an * a.z
              pl = Math.sqrt(px * px + py * py + pz * pz)
              px /= pl; py /= pl; pz /= pl
              t  = ((com.x - c.x) * a.x + (com.y - c.y) * a.y + (com.z - c.z) * a.z)
                   .clamp(-geo[:half], geo[:half])
              pc = Geom::Point3d.new(c.x + a.x * t - px * r, c.y + a.y * t - py * r,
                                     c.z + a.z * t - pz * r)
              return { kind: :curved, roll: :cylinder, pc: pc, com: com, c: c, r: r, hw: hw,
                       axis: [a.x, a.y, a.z],
                       lever: Math.sqrt((com.x - pc.x)**2 + (com.y - pc.y)**2) }
            end
          end
        end
      end

      # ── Appoggio poliedrico ────────────────────────────────────────
      # Base (u, v) del piano d'appoggio
      ax, ay, az = nz.abs < 0.9 ? [0.0, 0.0, 1.0] : [1.0, 0.0, 0.0]
      ux = ay * nz - az * ny; uy = az * nx - ax * nz; uz = ax * ny - ay * nx
      ul = Math.sqrt(ux * ux + uy * uy + uz * uz)
      ux /= ul; uy /= ul; uz /= ul
      vx = ny * uz - nz * uy; vy = nz * ux - nx * uz; vz = nx * uy - ny * ux
      to2d = ->(x, y, z) { [x * ux + y * uy + z * uz, x * vx + y * vy + z * vz] }

      cands = []
      hw.each_with_index { |p, i| cands << p if ds[i] <= dmin + CONTACT_EPS }
      # Solo i punti sul contorno del gruppo di contatto contano per il
      # poligono; se sono tanti (la base di un cilindro) ne basta un campione.
      c2d  = cands.map { |x, y, z| to2d.(x, y, z) }
      h2   = hull2d(c2d)
      ring = h2.map { |q| cands[c2d.index(q)] || cands[0] }
      ring = ring.each_slice((ring.size / 12.0).ceil).map(&:first) if ring.size > 12

      # Un punto conta solo se sotto c'è davvero qualcosa: un oggetto che
      # sporge oltre il bordo di un tavolo non si appoggia sul vuoto.
      contacts = ring.select do |x, y, z|
        res = ray_ignoring(x, y, z + 2.0, 0, 0, -1, entity)
        res && res[0].z >= z - 1.2
      end
      return { kind: :poly, face: false, inside: false, pivot: nil, lever: 0.0,
               com: com, hw: hw, free: true } if contacts.empty?

      # CM proiettato in verticale sul piano d'appoggio
      t  = nz.abs > 0.05 ? (dmin - (com.x * nx + com.y * ny + com.z * nz)) / nz : 0.0
      c2 = to2d.(com.x, com.y, com.z + t)

      hull = hull2d(contacts.map { |x, y, z| to2d.(x, y, z) })
      inside = false
      near = hull[0]
      if hull.size >= 3
        # Poligono convesso in senso antiorario: dentro se a sinistra di ogni lato
        inside = hull.each_index.all? do |i|
          a = hull[i]; b = hull[(i + 1) % hull.size]
          (b[0] - a[0]) * (c2[1] - a[1]) - (b[1] - a[1]) * (c2[0] - a[0]) >= -1e-6
        end
        unless inside
          best_d = nil
          hull.each_index do |i|
            q = closest_on_seg(c2, hull[i], hull[(i + 1) % hull.size])
            d = (q[0] - c2[0])**2 + (q[1] - c2[1])**2
            if best_d.nil? || d < best_d then best_d = d; near = q end
          end
        end
      elsif hull.size == 2
        near = closest_on_seg(c2, hull[0], hull[1])
      end
      near = c2 if inside
      lever = Math.sqrt((near[0] - c2[0])**2 + (near[1] - c2[1])**2)
      pivot = Geom::Point3d.new(
        near[0] * ux + near[1] * vx + dmin * nx,
        near[0] * uy + near[1] * vy + dmin * ny,
        near[0] * uz + near[1] * vz + dmin * nz
      )
      { kind: :poly, face: hull.size >= 3, inside: inside, pivot: pivot, lever: lever,
        com: com, hw: hw, free: false }
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Primo angolo (≤ step) a cui, ruotando attorno a `pivot` sull'asse
    # orizzontale u, un altro punto dell'involucro tocca il piano. Serve a
    # fermare il ribaltamento esattamente sulla faccia d'arrivo invece di
    # attraversarla. Altezza di un punto dopo una rotazione θ (Rodrigues):
    #   h(θ) = h0·cosθ + (r·(n×u))·sinθ
    def self.tipping_toi(pts, pivot, u, n, step)
      wx = n[1] * u[2] - n[2] * u[1]
      wy = n[2] * u[0] - n[0] * u[2]
      wz = n[0] * u[1] - n[1] * u[0]
      best = nil
      pts.each do |x, y, z|
        rx = x - pivot.x; ry = y - pivot.y; rz = z - pivot.z
        h0 = rx * n[0] + ry * n[1] + rz * n[2]
        next if h0 < CONTACT_EPS          # già a contatto (o sul perno)
        bw = rx * wx + ry * wy + rz * wz
        next if bw >= 0                   # questo punto si sta alzando
        th = Math.atan2(h0, -bw)
        best = th if th <= step && (best.nil? || th < best)
      end
      best
    end

    # Rotolamento su un contatto curvo (sfera, calotta, cilindro coricato).
    # Il momento angolare attorno al punto di contatto si conserva nel
    # passaggio strisciamento → rotolamento (così un calcio a una palla ne
    # fa prima strisciare e poi rotolare la palla, come nella realtà); la
    # coppia della gravità rispetto al contatto fa dondolare le calotte, il
    # cui baricentro non sta sulla verticale del contatto. L'attrito regola
    # quanto in fretta il corpo aggancia il rotolamento.
    # Aggiorna state (ω e v orizzontale). Ritorna true se è in equilibrio.
    def self.roll_step(state, p, sup, dt, g)
      r_m = sup[:r] * IN_TO_M
      com = sup[:com]; pc = sup[:pc]
      dx = (com.x - pc.x) * IN_TO_M; dy = (com.y - pc.y) * IN_TO_M; dz = (com.z - pc.z) * IN_TO_M
      d2 = dx * dx + dy * dy + dz * dz

      # I_cm / m: cilindro pieno attorno all'asse; sfera piena, corretta per
      # le calotte col teorema degli assi paralleli (baricentro ≠ centro).
      icm = if sup[:roll] == :cylinder
              0.5 * r_m * r_m
            else
              off = ((com.x - sup[:c].x)**2 + (com.y - sup[:c].y)**2 + (com.z - sup[:c].z)**2) * IN_TO_M * IN_TO_M
              [0.4 * r_m * r_m - off, 0.05 * r_m * r_m].max
            end
      k = icm + d2

      vx = state[:vx] * IN_TO_M; vy = state[:vy] * IN_TO_M; vz = state[:vz] * IN_TO_M
      ox = state[:ox]; oy = state[:oy]; oz = state[:oz]
      # Momento angolare (per unità di massa) attorno al contatto: I·ω + d × v
      lx = icm * ox + (dy * vz - dz * vy)
      ly = icm * oy + (dz * vx - dx * vz)
      lz = icm * oz + (dx * vy - dy * vx)
      # Coppia della gravità (per unità di massa): d × (0, 0, −g)
      tx = -g * dy; ty = g * dx

      mu   = p[:fric]
      beta = (mu * 15.0 * dt).clamp(0.0, 1.0)
      decel = ROLL_RESIST * g / [r_m, 0.01].max * dt

      if sup[:roll] == :cylinder
        a = sup[:axis]
        w = (lx * a[0] + ly * a[1] + lz * a[2]) / k + (tx * a[0] + ty * a[1]) / k * dt
        w = w > 0 ? [w - decel, 0.0].max : [w + decel, 0.0].min
        tox = w * a[0]; toy = w * a[1]
        # Un cilindro coricato ruota solo sul proprio asse
        nox = ox + (tox - ox) * beta
        noy = oy + (toy - oy) * beta
        wa  = nox * a[0] + noy * a[1]
        nox = wa * a[0]; noy = wa * a[1]
      else
        wx = lx / k + tx / k * dt
        wy = ly / k + ty / k * dt
        mag = Math.sqrt(wx * wx + wy * wy)
        if mag > 1e-9
          s = [mag - decel, 0.0].max / mag
          wx *= s; wy *= s
        end
        nox = ox + (wx - ox) * beta
        noy = oy + (wy - oy) * beta
      end

      # Velocità di rotolamento del baricentro: v = ω × d
      rvx =  noy * dz
      rvy = -nox * dz
      if sup[:roll] == :cylinder
        a = sup[:axis]
        # Lungo l'asse il cilindro striscia (attrito di Coulomb pieno)
        va  = vx * a[0] + vy * a[1]
        pvx = vx - va * a[0]; pvy = vy - va * a[1]
        dec = mu * g * dt
        va  = va.abs <= dec ? 0.0 : va - (va > 0 ? dec : -dec)
        pvx += (rvx - pvx) * beta; pvy += (rvy - pvy) * beta
        vx = pvx + va * a[0]; vy = pvy + va * a[1]
      else
        vx += (rvx - vx) * beta; vy += (rvy - vy) * beta
      end

      state[:ox] = nox.clamp(-MAX_OMEGA, MAX_OMEGA)
      state[:oy] = noy.clamp(-MAX_OMEGA, MAX_OMEGA)
      state[:vx] = vx * M_TO_IN; state[:vy] = vy * M_TO_IN
      sup[:lever] < 0.05
    end

  end
end
