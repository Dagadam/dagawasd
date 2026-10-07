# DagaWASD — Urti fra oggetti: forme nel mondo, asse separatore, impulsi.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Risoluzione collisioni fra corpi (impulsi mass-based)
    # ══════════════════════════════════════════════════════════════
    # ── Forma reale per gli urti fra oggetti ──────────────────────────
    # Rappresentazione nel mondo di un corpo, per il test di contatto:
    #   kind  :poly (punti dell'involucro), :sphere (sfera piena) o :cyl
    #   pts   punti dell'involucro nel mondo      com  baricentro
    #   axes  direzioni candidate: normali principali delle facce
    #   c, r, a, half   per sfera e cilindro (proiezione esatta)
    # nil se l'oggetto non ha geometria letta (enorme o troppo complesso).
    def self.shape_world(entity)
      geo = body_props(entity)[:geo]
      return nil unless geo
      tr = entity.transformation
      m  = tr.to_a
      sw = { kind: :poly, pts: xform_all(geo[:hull], m), com: geo[:com].transform(tr) }
      sw[:axes] = (geo[:normals] || []).map do |x, y, z|
        nx, ny, nz = normal_xform(m, x, y, z)
        l = Math.sqrt(nx * nx + ny * ny + nz * nz)
        l > 1e-9 ? [nx / l, ny / l, nz / l] : nil
      end.compact
      if geo[:shape] == :cylinder
        a = geo[:axis_v].transform(tr); a.normalize!
        sw.merge!(kind: :cyl, c: geo[:c].transform(tr), r: geo[:r], a: [a.x, a.y, a.z], half: geo[:half])
      elsif geo[:shape] == :sphere && geo[:full]
        sw.merge!(kind: :sphere, c: geo[:c].transform(tr), r: geo[:r])
      end
      sw
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Intervallo [min, max] della proiezione di una forma sull'asse unitario n.
    def self.shape_proj(sw, n)
      case sw[:kind]
      when :sphere
        d = sw[:c].x * n[0] + sw[:c].y * n[1] + sw[:c].z * n[2]
        [d - sw[:r], d + sw[:r]]
      when :cyl
        c = sw[:c]; a = sw[:a]
        an = a[0] * n[0] + a[1] * n[1] + a[2] * n[2]
        d  = c.x * n[0] + c.y * n[1] + c.z * n[2]
        e  = sw[:half] * an.abs + sw[:r] * Math.sqrt([1.0 - an * an, 0.0].max)
        [d - e, d + e]
      else
        lo = hi = nil
        sw[:pts].each do |x, y, z|
          d = x * n[0] + y * n[1] + z * n[2]
          lo = d if lo.nil? || d < lo
          hi = d if hi.nil? || d > hi
        end
        [lo, hi]
      end
    end

    # Punto della forma più lontano lungo n (per il punto di contatto): per
    # i poliedri la media dei punti dell'involucro entro `tol` dal massimo.
    def self.shape_support(sw, n, tol)
      if sw[:kind] == :sphere
        c = sw[:c]; r = sw[:r]
        return [c.x + n[0] * r, c.y + n[1] * r, c.z + n[2] * r]
      end
      ds  = sw[:pts].map { |x, y, z| x * n[0] + y * n[1] + z * n[2] }
      top = ds.max
      sel = sw[:pts].each_index.select { |i| ds[i] >= top - tol }
      [sel.sum { |i| sw[:pts][i][0] } / sel.size,
       sel.sum { |i| sw[:pts][i][1] } / sel.size,
       sel.sum { |i| sw[:pts][i][2] } / sel.size]
    end

    def self.vcross(a, b)
      [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    end

    # Punti più vicini fra i segmenti p1–q1 e p2–q2 (assi di due cilindri).
    def self.closest_segments(p1, q1, p2, q2)
      d1 = [q1[0] - p1[0], q1[1] - p1[1], q1[2] - p1[2]]
      d2 = [q2[0] - p2[0], q2[1] - p2[1], q2[2] - p2[2]]
      r  = [p1[0] - p2[0], p1[1] - p2[1], p1[2] - p2[2]]
      dot = ->(u, v) { u[0] * v[0] + u[1] * v[1] + u[2] * v[2] }
      a = dot.(d1, d1); e = dot.(d2, d2); f = dot.(d2, r)
      c = dot.(d1, r);  b = dot.(d1, d2); den = a * e - b * b
      s = den.abs > 1e-12 ? ((b * f - c * e) / den).clamp(0.0, 1.0) : 0.0
      t = e > 1e-12 ? ((b * s + f) / e) : 0.0
      if t < 0 then t = 0.0; s = a > 1e-12 ? (-c / a).clamp(0.0, 1.0) : 0.0
      elsif t > 1 then t = 1.0; s = a > 1e-12 ? ((b - c) / a).clamp(0.0, 1.0) : 0.0
      end
      [[p1[0] + d1[0] * s, p1[1] + d1[1] * s, p1[2] + d1[2] * s],
       [p2[0] + d2[0] * t, p2[1] + d2[1] * t, p2[2] + d2[2] * t]]
    end

    # Contatto fra due forme col teorema dell'asse separatore: se esiste un
    # asse su cui le proiezioni non si sovrappongono, non si toccano. Assi
    # provati: normali principali delle facce di entrambi, i loro prodotti
    # vettoriali (spigolo contro spigolo), la congiungente dei baricentri e,
    # per sfere e cilindri, le direzioni fra i loro punti più vicini.
    # Per due box orientati è il test esatto; per poliedri generici e forme
    # curve un'ottima approssimazione. Due cubi ruotati di 45° vicini hanno
    # ingombri sovrapposti ma forme separate: ora non si urtano più "a vuoto".
    # Ritorna nil (separati) oppure { n: normale da B verso A, depth:, point: }.
    def self.shape_contact(sa, sb)
      axes = sa[:axes].first(8) + sb[:axes].first(8)
      sa[:axes].first(3).each { |u| sb[:axes].first(3).each { |v| axes << vcross(u, v) } }
      ca = sa[:com]; cb = sb[:com]
      axes << [ca.x - cb.x, ca.y - cb.y, ca.z - cb.z]
      [sa, sb].each { |s| axes << s[:a] if s[:kind] == :cyl }
      if sa[:kind] == :cyl && sb[:kind] == :cyl
        ends = ->(s) { c = s[:c]; a = s[:a]; h = s[:half]
                       [[c.x - a[0] * h, c.y - a[1] * h, c.z - a[2] * h], [c.x + a[0] * h, c.y + a[1] * h, c.z + a[2] * h]] }
        pa, pb = closest_segments(*ends.(sa), *ends.(sb))
        axes << [pa[0] - pb[0], pa[1] - pb[1], pa[2] - pb[2]]
        axes << vcross(sa[:a], sb[:a])
      end
      [[sa, sb], [sb, sa]].each do |s, o|
        next unless s[:kind] == :sphere
        # dalla sfera verso il punto più vicino dell'altra forma (fra i suoi punti)
        c = s[:c]
        q = o[:pts].min_by { |x, y, z| (x - c.x)**2 + (y - c.y)**2 + (z - c.z)**2 }
        axes << [q[0] - c.x, q[1] - c.y, q[2] - c.z] if q
      end

      best = nil
      axes.each do |ax|
        l = Math.sqrt(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2])
        next if l < 1e-9
        n = [ax[0] / l, ax[1] / l, ax[2] / l]
        a0, a1 = shape_proj(sa, n)
        b0, b1 = shape_proj(sb, n)
        d_pos = b1 - a0   # A dalla parte +n di B
        d_neg = a1 - b0   # A dalla parte −n di B
        return nil if d_pos <= 0 || d_neg <= 0      # asse separatore trovato
        o, nn = d_pos < d_neg ? [d_pos, n] : [d_neg, [-n[0], -n[1], -n[2]]]
        best = [o, nn] if best.nil? || o < best[0]
      end
      return nil unless best

      depth, n = best
      tol = [depth * 1.5, 0.3].max
      pa = shape_support(sa, [-n[0], -n[1], -n[2]], tol)   # punto di A più dentro B
      pb = shape_support(sb, n, tol)                        # punto di B più dentro A
      { n: n, depth: depth,
        point: [(pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5, (pa[2] + pb[2]) * 0.5] }
    end

    # Contatto fra due entità: con la forma reale se entrambe hanno la
    # geometria letta, altrimenti con gli ingombri (come prima). memo evita
    # di ricalcolare la forma nel mondo della stessa entità nello stesso tick.
    # Ritorna nil o { n: [x,y,z] da B verso A, depth:, point: [x,y,z],
    #                 ca: baricentro A, cb: baricentro B } (pollici).
    def self.body_contact(ea, eb, memo, min_depth = 0.0)
      memo[ea] = shape_world(ea) unless memo.key?(ea)
      memo[eb] = shape_world(eb) unless memo.key?(eb)
      sa = memo[ea]; sb = memo[eb]
      if sa && sb
        c = shape_contact(sa, sb)
        return nil unless c && c[:depth] > min_depth
        return c.merge(ca: sa[:com], cb: sb[:com])
      end
      ba = ea.bounds; bb = eb.bounds
      ov = [[ba.max.x, bb.max.x].min - [ba.min.x, bb.min.x].max,
            [ba.max.y, bb.max.y].min - [ba.min.y, bb.min.y].max,
            [ba.max.z, bb.max.z].min - [ba.min.z, bb.min.z].max]
      return nil unless ov.all? { |o| o > min_depth }
      k = ov.index(ov.min)
      n = [0.0, 0.0, 0.0]; n[k] = 1.0
      ca = Geom::Point3d.new((ba.min.x + ba.max.x) * 0.5, (ba.min.y + ba.max.y) * 0.5, (ba.min.z + ba.max.z) * 0.5)
      cb = Geom::Point3d.new((bb.min.x + bb.max.x) * 0.5, (bb.min.y + bb.max.y) * 0.5, (bb.min.z + bb.max.z) * 0.5)
      n = n.map { |v| -v } if [ca.x - cb.x, ca.y - cb.y, ca.z - cb.z][k] < 0
      pt = [([ba.min.x, bb.min.x].max + [ba.max.x, bb.max.x].min) * 0.5,
            ([ba.min.y, bb.min.y].max + [ba.max.y, bb.max.y].min) * 0.5,
            ([ba.min.z, bb.min.z].max + [ba.max.z, bb.max.z].min) * 0.5]
      { n: n, depth: ov[k], point: pt, ca: ca, cb: cb }
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.resolve_entity_collisions(model)
      active = @phys_entities.keys.select { |e| e.valid? }
      memo   = {}   # forme nel mondo calcolate in questo tick

      # ── Risveglia corpi fermi colpiti da uno in moto ───────────────
      to_add = {}
      active.each do |ea|
        sa  = @phys_entities[ea]
        spd = Math.sqrt(sa[:vx]**2 + sa[:vy]**2 + sa[:vz]**2)
        next if spd < 2.0
        ba   = ea.bounds
        # Candidati dalla griglia degli ingombri (non da tutto il modello)
        q = [ba.min.x, ba.min.y, ba.min.z, ba.max.x, ba.max.y, ba.max.z]
        nearby_entities(q, ea).each do |eb|
          next unless eb.is_a?(Sketchup::ComponentInstance) || eb.is_a?(Sketchup::Group)
          next if eb == ea || @phys_entities.key?(eb) || to_add.key?(eb) || eb == @grabbed_entity
          bb   = eb.bounds
          # Mai svegliare l'ambiente: gli oggetti enormi (muri, pavimenti,
          # un'intera stanza modellata come gruppo) e i contenitori, il cui
          # ingombro racchiude quello del corpo che si muove al loro interno.
          # Una casa-gruppo diventata "fisica" cadrebbe nel vuoto.
          next if bb.diagonal > GEO_MAX_DIAG
          next if bb.min.x <= ba.min.x && bb.min.y <= ba.min.y && bb.min.z <= ba.min.z &&
                  bb.max.x >= ba.max.x && bb.max.y >= ba.max.y && bb.max.z >= ba.max.z
          # Si toccano davvero? (forma reale; ingombri solo se manca la geometria)
          ct = body_contact(ea, eb, memo, 0.1)
          next unless ct
          nx, ny, nz = ct[:n]
          v_in = (sa[:vx] * (-nx) + sa[:vy] * (-ny) + sa[:vz] * (-nz)) * IN_TO_M
          next if v_in <= 0
          pa = (sa[:props] ||= body_props(ea)); pb = body_props(eb)
          e  = [pa[:rest], pb[:rest]].min
          j  = (1.0 + e) * v_in / (pa[:im] + pb[:im])   # kg·m/s
          # Troppo pesante per smuoversi (< 0.1 m/s): resta dov'è. Lo scontro
          # con la sua superficie lo gestiscono già i raggi dei muri.
          next if j * pb[:im] < 0.1
          to_add[eb] = { vx: -nx * j * pb[:im] * M_TO_IN,
                         vy: -ny * j * pb[:im] * M_TO_IN,
                         vz: -nz * j * pb[:im] * M_TO_IN,
                         ox: 0.0, oy: 0.0, oz: 0.0,
                         fz: nil, still: 0.0, props: pb }
          sa[:vx] += nx * j * pa[:im] * M_TO_IN
          sa[:vy] += ny * j * pa[:im] * M_TO_IN
          sa[:vz] += nz * j * pa[:im] * M_TO_IN
          sa[:still] = 0.0
        end
      end
      to_add.each { |e, st| @phys_entities[e] = st unless @phys_entities.size >= cf('max_phys_entities').to_i }

      # ── Impulsi bidirezionali fra corpi attivi ────────────────────
      active = @phys_entities.keys.select { |e| e.valid? }
      n = active.size
      return if n < 2

      n.times do |i|
        (i + 1...n).each do |j_i|
          ea = active[i]; eb = active[j_i]
          sa = @phys_entities[ea]; sb = @phys_entities[eb]
          next unless sa && sb
          pa = (sa[:props] ||= body_props(ea))
          pb = (sb[:props] ||= body_props(eb))
          # Fase larga: gli ingombri devono almeno toccarsi
          ba = ea.bounds;  bb = eb.bounds
          next if ba.max.x < bb.min.x || bb.max.x < ba.min.x ||
                  ba.max.y < bb.min.y || bb.max.y < ba.min.y ||
                  ba.max.z < bb.min.z || bb.max.z < ba.min.z
          # Fase stretta: contatto fra le forme reali
          ct = body_contact(ea, eb, memo)
          next unless ct
          nx, ny, nz = ct[:n]
          depth = ct[:depth]
          ca = ct[:ca]; cb = ct[:cb]

          # Velocità relativa lungo la normale (m/s)
          rvx = (sa[:vx] - sb[:vx]) * IN_TO_M
          rvy = (sa[:vy] - sb[:vy]) * IN_TO_M
          rvz = (sa[:vz] - sb[:vz]) * IN_TO_M
          rel_vn = rvx * nx + rvy * ny + rvz * nz
          inv_sum = pa[:im] + pb[:im]
          next if inv_sum <= 0

          if rel_vn < 0
            e  = [pa[:rest], pb[:rest]].min
            jn = -(1.0 + e) * rel_vn / inv_sum        # kg·m/s
            jx = jn * nx; jy = jn * ny; jz = jn * nz

            # Punto di contatto fra le due forme (per la rotazione impressa)
            cx, cy, cz = ct[:point]

            # Attrito di Coulomb sulla componente tangenziale
            tvx = rvx - rel_vn * nx
            tvy = rvy - rel_vn * ny
            tvz = rvz - rel_vn * nz
            tlen = Math.sqrt(tvx * tvx + tvy * tvy + tvz * tvz)
            if tlen > 1e-4
              mu = Math.sqrt(pa[:fric] * pb[:fric])
              jt = -tlen / inv_sum
              jt = -mu * jn if jt < -mu * jn
              tx = tvx / tlen; ty = tvy / tlen; tz = tvz / tlen
              jx += jt * tx; jy += jt * ty; jz += jt * tz
            end

            apply_pair_impulse(sa, pa, ea,  jx,  jy,  jz, cx - ca.x, cy - ca.y, cz - ca.z)
            apply_pair_impulse(sb, pb, eb, -jx, -jy, -jz, cx - cb.x, cy - cb.y, cz - cb.z)
          end

          # Correzione posizionale proporzionale alla massa inversa (slop 0.1")
          push = [(depth - 0.1) * 0.6, 0.0].max
          if push > 0
            fa = pa[:im] / inv_sum
            fb = pb[:im] / inv_sum
            ea.transformation = Geom::Transformation.translation(
              Geom::Vector3d.new(nx * push * fa, ny * push * fa, nz * push * fa)
            ) * ea.transformation
            eb.transformation = Geom::Transformation.translation(
              Geom::Vector3d.new(-nx * push * fb, -ny * push * fb, -nz * push * fb)
            ) * eb.transformation
            memo.delete(ea); memo.delete(eb)   # si sono spostati: forme da ricalcolare
          end
        end
      end
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Applica un impulso J (kg·m/s) allo stato `st` con braccio r (pollici).
    def self.apply_pair_impulse(st, p, _entity, jx, jy, jz, rx_in, ry_in, rz_in)
      st[:vx] += jx * p[:im] * M_TO_IN
      st[:vy] += jy * p[:im] * M_TO_IN
      st[:vz] += jz * p[:im] * M_TO_IN
      rx = rx_in * IN_TO_M; ry = ry_in * IN_TO_M; rz = rz_in * IN_TO_M
      st[:ox] = (st[:ox] + (ry * jz - rz * jy) / p[:ix]).clamp(-MAX_OMEGA, MAX_OMEGA)
      st[:oy] = (st[:oy] + (rz * jx - rx * jz) / p[:iy]).clamp(-MAX_OMEGA, MAX_OMEGA)
      st[:oz] = (st[:oz] + (rx * jy - ry * jx) / p[:iz]).clamp(-MAX_OMEGA, MAX_OMEGA)
      st[:still] = 0.0
    end

  end
end
