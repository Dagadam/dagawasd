# DagaWASD — Geometria reale degli oggetti: involucro, volume, baricentro, forma.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Box orientato (OBB) — dimensioni proprie dell'oggetto
    # ══════════════════════════════════════════════════════════════
    def self.obb(entity)
      return nil unless entity.respond_to?(:definition)
      lb = entity.definition.bounds
      return nil if lb.empty?
      tr = entity.transformation
      cs = (0..7).map { |i| lb.corner(i).transform(tr) }
      # corner(0) = min; 1 = +x; 2 = +y; 4 = +z (convenzione di BoundingBox)
      lens = [1, 2, 4].map { |i| (cs[i] - cs[0]).length.to_f }
      { corners: cs, center: lb.center.transform(tr), len: lens }
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # ══════════════════════════════════════════════════════════════
    # Geometria reale dei corpi
    # Alla prima interazione si leggono i vertici e le facce dell'oggetto
    # (gruppi annidati compresi) e se ne ricava, una volta sola:
    #   hull   — i punti estremi (involucro convesso approssimato): sono loro
    #            a toccare il pavimento, non gli spigoli della scatola
    #   com    — baricentro del volume (solidi chiusi), es. una semisfera ha
    #            il baricentro a 3/8 del raggio dalla faccia piana
    #   vol    — volume reale (pollici³ mondo)
    #   shape  — :sphere (anche calotte/semisfere) o :cylinder se tutti i
    #            vertici stanno su una sfera o attorno a un asse locale
    # Tutto è in coordinate della definizione; il mondo si ottiene con la
    # trasformazione dell'istanza (che può anche scalare).
    # ══════════════════════════════════════════════════════════════
    GEO_MAX_DIAG  = 6.0 * 39.3701  # oltre 6 m di diagonale: niente geometria reale
    GEO_MAX_PTS   = 40_000   # vertici letti, duplicati compresi (~10 000 distinti): oltre, oggetto troppo complesso
    GEO_MAX_TRIS  = 15_000   # oltre, niente volume reale
    GEO_FIT_MAX   = 6_000    # oltre, niente riconoscimento cilindro/sfera
    HULL_MAX      = 96       # punti d'involucro usati per il contatto
    ROLL_RESIST   = 0.02     # coefficiente di resistenza al rotolamento
    HELD_PROBES   = 32       # punti di superficie da cui partono i raggi dell'oggetto in mano
    HELD_INSET    = 0.3      # pollici: le sonde partono appena dentro l'oggetto
    HELD_SKIN     = 0.05     # pollici: distanza minima lasciata dagli ostacoli
    HELD_DROP_GAP = 39.37    # pollici (1 m): oltre, l'oggetto è "incastrato"…
    HELD_DROP_T   = 0.4      # …e se resta incastrato così a lungo (s) si molla
    GRAB_TAP      = 0.18     # s: un tocco di G più breve di così posa l'oggetto invece di lanciarlo
    GRAB_GHOST_MAX = 1.0     # s: al massimo così resta "fantasma" se è ancora dentro qualcosa
    GRAB_MIN_FRAMES = 8      # lo strappo iniziale dura almeno tanti fotogrammi

    def self.collect_geometry(ents, tr, pts, tris, st, depth, sp = nil)
      return if depth > 8
      ents.each do |e|
        break if pts.size > GEO_MAX_PTS
        case e
        when Sketchup::Face
          e.vertices.each { |v| pts << v.position.transform(tr) }
          sp << e.bounds.center.transform(tr) if sp && sp.size < GEO_MAX_PTS
          if st[:normals] && st[:normals].size < 5000
            n = e.normal
            st[:normals] << (normal_xform(tr.to_a, n.x, n.y, n.z) << e.area)
          end
          next unless st[:tris_ok]
          m = e.mesh(0)
          m.polygons.each do |poly|
            a, b, c = poly.map { |i| m.point_at(i.abs).transform(tr) }
            tris << [a, b, c] if c
          end
          st[:tris_ok] = false if tris.size > GEO_MAX_TRIS
        when Sketchup::Edge
          a = e.start.position.transform(tr); b = e.end.position.transform(tr)
          pts << a << b
          sp << Geom::Point3d.new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5) if sp && sp.size < GEO_MAX_PTS
        when Sketchup::Group, Sketchup::ComponentInstance
          collect_geometry(e.definition.entities, tr * e.transformation, pts, tris, st, depth + 1, sp)
        end
      end
    end

    # Direzioni delle facce che coprono più superficie (al massimo 16), con
    # n e −n considerate la stessa direzione: sono gli assi candidati del
    # test di separazione negli urti fra oggetti. Normali quasi uguali
    # (entro ~1°) si sommano.
    def self.main_normals(list)
      acc = []
      list.each do |x, y, z, a|
        l = Math.sqrt(x * x + y * y + z * z)
        next if l < 1e-9 || a.nil? || a <= 0
        x /= l; y /= l; z /= l
        hit = acc.find { |q| (q[0] * x + q[1] * y + q[2] * z).abs > 0.9998 }
        if hit then hit[3] += a else acc << [x, y, z, a] end
      end
      acc.sort_by { |q| -q[3] }.first(16).map { |q| q[0, 3] }
    end

    # Campionamento "farthest point": k punti ben distribuiti sulla superficie
    # (prima gli spigoli più lontani, poi via via i punti che riempiono i
    # vuoti: centri delle facce, metà degli spigoli…).
    def self.fps_sample(pts, k)
      pts = pts.uniq { |p| [(p.x * 10).round, (p.y * 10).round, (p.z * 10).round] }
      pts = pts.each_slice((pts.size / 2000.0).ceil).map(&:first) if pts.size > 2000
      return pts if pts.size <= k
      n  = pts.size
      cx = pts.sum(&:x) / n; cy = pts.sum(&:y) / n; cz = pts.sum(&:z) / n
      d2 = ->(a, b) { (a.x - b.x)**2 + (a.y - b.y)**2 + (a.z - b.z)**2 }
      c  = Geom::Point3d.new(cx, cy, cz)
      first = pts.max_by { |p| d2.(p, c) }
      chosen = [first]
      dist = pts.map { |p| d2.(p, first) }
      while chosen.size < k
        i = dist.each_with_index.max[1]
        q = pts[i]
        chosen << q
        pts.each_with_index { |p, j| dd = d2.(p, q); dist[j] = dd if dd < dist[j] }
      end
      chosen
    end

    # Direzioni quasi uniformi sulla sfera (spirale di Fibonacci).
    def self.fib_dirs(n)
      ga = Math::PI * (3.0 - Math.sqrt(5.0))
      (0...n).map do |i|
        z = 1.0 - 2.0 * (i + 0.5) / n
        r = Math.sqrt([1.0 - z * z, 0.0].max)
        [Math.cos(ga * i) * r, Math.sin(ga * i) * r, z]
      end
    end

    # Eliminazione di Gauss con pivot parziale. nil se singolare.
    def self.solve_lin(a, b)
      n = b.size
      m = a.each_with_index.map { |row, i| row.dup << b[i] }
      n.times do |c|
        pr = (c...n).max_by { |r| m[r][c].abs }
        return nil if m[pr][c].abs < 1e-12
        m[c], m[pr] = m[pr], m[c]
        (c + 1...n).each do |r|
          f = m[r][c] / m[c][c]
          (c..n).each { |k| m[r][k] -= f * m[c][k] }
        end
      end
      x = Array.new(n, 0.0)
      (n - 1).downto(0) do |r|
        s = m[r][n]
        (r + 1...n).each { |k| s -= m[r][k] * x[k] }
        x[r] = s / m[r][r]
      end
      x
    end

    # Cerchio (2D) o sfera (3D) ai minimi quadrati algebrici.
    # Ritorna [centro, raggio, scarto massimo] oppure nil.
    def self.fit_round(pts)
      d = pts[0].size
      mean = (0...d).map { |k| pts.sum { |p| p[k] } / pts.size }
      q = pts.map { |p| (0...d).map { |k| p[k] - mean[k] } }
      n = d + 1
      mm = Array.new(n) { Array.new(n, 0.0) }; rhs = Array.new(n, 0.0)
      q.each do |p|
        row = p + [1.0]
        s = p.sum { |v| v * v }
        n.times do |i|
          rhs[i] += row[i] * s
          n.times { |j| mm[i][j] += row[i] * row[j] }
        end
      end
      sol = solve_lin(mm, rhs)
      return nil unless sol
      c  = (0...d).map { |k| sol[k] / 2.0 }
      r2 = sol[d] + c.sum { |v| v * v }
      return nil if r2 <= 0
      r = Math.sqrt(r2)
      res = q.map { |p| (Math.sqrt((0...d).sum { |k| (p[k] - c[k])**2 }) - r).abs }.max
      [(0...d).map { |k| c[k] + mean[k] }, r, res]
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.geometry(entity)
      return nil unless entity.respond_to?(:definition)
      d  = entity.definition
      lb = d.bounds
      return nil if lb.empty?
      # Muri, pavimenti, edifici modellati come gruppo: non sono corpi da
      # far rotolare, e leggerne la geometria bloccherebbe SketchUp al primo
      # contatto. Restano sulla stima dall'ingombro.
      return nil if entity.bounds.diagonal > GEO_MAX_DIAG
      pts = []; tris = []; st = { tris_ok: true, normals: [] }
      sp = []   # centri delle facce e punti medi degli spigoli (per le sonde di presa)
      collect_geometry(d.entities, Geom::Transformation.new, pts, tris, st, 0, sp)
      return nil if pts.size > GEO_MAX_PTS   # lettura interrotta: involucro incompleto
      pts = pts.uniq { |p| [(p.x * 100).round, (p.y * 100).round, (p.z * 100).round] }
      return nil if pts.size < 4

      # Scala per asse dell'istanza: le verifiche di forma vanno fatte sulle
      # misure reali (un cilindro scalato su un asse diventa ellittico).
      tr = entity.transformation
      sc = [X_AXIS, Y_AXIS, Z_AXIS].map { |ax| [ax.transform(tr).length.to_f, 1e-6].max }
      sl = pts.map { |p| [p.x * sc[0], p.y * sc[1], p.z * sc[2]] }

      # ── Involucro: punti estremi lungo HULL_MAX direzioni ──────────
      hull_pts = if pts.size <= HULL_MAX
                   pts
                 else
                   cand = (0...sl.size).to_a
                   if cand.size > 3000
                     # Prefiltro a griglia: per ogni cella tiene solo i punti
                     # estremi sul terzo asse (quelli interni non toccano mai).
                     keep = {}
                     [[0, 1, 2], [0, 2, 1], [1, 2, 0]].each do |i, j, k|
                       lo = sl.map { |s| s[i] }.minmax; lo2 = sl.map { |s| s[j] }.minmax
                       ci = (lo[1] - lo[0]) / 16.0 + 1e-9; cj = (lo2[1] - lo2[0]) / 16.0 + 1e-9
                       cells = {}
                       sl.each_with_index do |s, idx|
                         key = [((s[i] - lo[0]) / ci).floor, ((s[j] - lo2[0]) / cj).floor]
                         mn, mx = cells[key] || [idx, idx]
                         mn = idx if s[k] < sl[mn][k]
                         mx = idx if s[k] > sl[mx][k]
                         cells[key] = [mn, mx]
                       end
                       cells.each_value { |a, b| keep[a] = true; keep[b] = true }
                     end
                     cand = keep.keys
                   end
                   fib_dirs(HULL_MAX).map do |dx, dy, dz|
                     cand.max_by { |i| s = sl[i]; s[0] * dx + s[1] * dy + s[2] * dz }
                   end.uniq.map { |i| pts[i] }
                 end
      hull = hull_pts.map { |p| [p.x, p.y, p.z] }

      # ── Volume e baricentro (teorema della divergenza sui triangoli) ─
      vol = 0.0; cx = cy = cz = 0.0
      if st[:tris_ok]
        tris.each do |a, b, c|
          v = (a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x) +
               a.z * (b.x * c.y - b.y * c.x)) / 6.0
          vol += v
          cx += v * (a.x + b.x + c.x) * 0.25
          cy += v * (a.y + b.y + c.y) * 0.25
          cz += v * (a.z + b.z + c.z) * 0.25
        end
      end
      bvol = (lb.max.x - lb.min.x) * (lb.max.y - lb.min.y) * (lb.max.z - lb.min.z)
      com = nil; vol_w = nil
      # Solo se il risultato è plausibile: una mesh aperta o con facce
      # incoerenti dà volumi senza senso, e allora si ripiega sul centro.
      if vol.abs > 1e-9 && bvol > 1e-9 && (vol.abs / bvol).between?(0.01, 1.05)
        c = Geom::Point3d.new(cx / vol, cy / vol, cz / vol)
        if lb.contains?(c)
          com = c
          vol_w = vol.abs * sc[0] * sc[1] * sc[2]
        end
      end
      com ||= lb.center

      geo = { hull: hull, com: com, vol: vol_w, shape: nil,
              probe: fps_sample(pts + sp, HELD_PROBES).map { |p| [p.x, p.y, p.z] },
              normals: main_normals(st[:normals]) }

      # ── Riconoscimento cilindro / sfera ─────────────────────────────
      if sl.size <= GEO_FIT_MAX
        # Cilindro: proiettati sul piano ⊥ a un asse locale, tutti i vertici
        # stanno su un cerchio (servono ≥10 posizioni: un prisma a pochi
        # lati resta un poliedro).
        3.times do |ai|
          j, k = [0, 1, 2] - [ai]
          p2 = sl.map { |s| [s[j], s[k]] }.uniq { |p| [(p[0] * 50).round, (p[1] * 50).round] }
          next if p2.size < 10
          f = fit_round(p2)
          next unless f
          cc, r, res = f
          next if r < 0.1 || res > r * 0.01 + 0.02
          along = sl.map { |s| s[ai] }.minmax
          cen = [0.0, 0.0, 0.0]
          cen[j] = cc[0] / sc[j]; cen[k] = cc[1] / sc[k]
          cen[ai] = (along[0] + along[1]) * 0.5 / sc[ai]
          axv = [X_AXIS, Y_AXIS, Z_AXIS][ai]
          geo.merge!(shape: :cylinder, c: Geom::Point3d.new(*cen), r: r,
                     half: (along[1] - along[0]) * 0.5, axis_v: axv)
          break
        end
        # Sfera o calotta (semisfera…): tutti i vertici su una sfera.
        if geo[:shape].nil?
          u = sl.uniq { |p| [(p[0] * 50).round, (p[1] * 50).round, (p[2] * 50).round] }
          if u.size >= 20
            f = fit_round(u)
            if f && f[1] > 0.1 && f[2] <= f[1] * 0.01 + 0.02
              cc = f[0]
              # Piena solo se occupa tutta la sfera: estensione ≈ 2r su ogni asse
              # (una semisfera no). Per gli urti una calotta resta un poliedro.
              full = 3.times.all? { |k| mm = sl.map { |q| q[k] }.minmax; (mm[1] - mm[0]) > f[1] * 1.9 }
              geo.merge!(shape: :sphere, r: f[1], full: full,
                         c: Geom::Point3d.new(cc[0] / sc[0], cc[1] / sc[1], cc[2] / sc[2]))
            end
          end
        end
      end
      geo
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Trasforma punti [x,y,z] con la matrice di una Transformation (to_a).
    def self.xform_all(pts, m)
      pts.map do |x, y, z|
        [m[0] * x + m[4] * y + m[8]  * z + m[12],
         m[1] * x + m[5] * y + m[9]  * z + m[13],
         m[2] * x + m[6] * y + m[10] * z + m[14]]
      end
    end

    # Inviluppo convesso 2D (monotone chain). Punti [x, y].
    def self.hull2d(pts)
      ps = pts.uniq { |p| [(p[0] * 20).round, (p[1] * 20).round] }.sort
      return ps if ps.size < 3
      cross = ->(o, a, b) { (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]) }
      lo = []; ps.each { |p| lo.pop while lo.size >= 2 && cross.(lo[-2], lo[-1], p) <= 1e-9; lo << p }
      up = []; ps.reverse_each { |p| up.pop while up.size >= 2 && cross.(up[-2], up[-1], p) <= 1e-9; up << p }
      h = lo[0...-1] + up[0...-1]
      h.size < 3 ? [ps.first, ps.last] : h
    end

    # Punto più vicino a c sul segmento a-b (2D).
    def self.closest_on_seg(c, a, b)
      ex = b[0] - a[0]; ey = b[1] - a[1]
      l2 = ex * ex + ey * ey
      return a if l2 < 1e-12
      t = (((c[0] - a[0]) * ex + (c[1] - a[1]) * ey) / l2).clamp(0.0, 1.0)
      [a[0] + ex * t, a[1] + ey * t]
    end

  end
end
