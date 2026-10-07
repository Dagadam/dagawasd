# DagaWASD — Raggi: normali delle facce colpite, raggi che ignorano un'entità.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Raycasting — helper comuni
    # ══════════════════════════════════════════════════════════════

    # Normale mondo della faccia colpita da un raytest, orientata verso -dir.
    # `result` = valore di ritorno di Model#raytest.
    def self.hit_normal(result, dx, dy, dz)
      path = result[1]
      return nil unless path.is_a?(Array) && !path.empty?
      face = path.last
      return nil unless face.is_a?(Sketchup::Face)
      n = face.normal
      nx = n.x; ny = n.y; nz = n.z
      # Compone le trasformazioni delle istanze/gruppi padre
      if path.size > 1
        tr = nil
        path[0...-1].each do |e|
          next unless e.respond_to?(:transformation)
          tr = tr ? tr * e.transformation : e.transformation
        end
        nx, ny, nz = normal_xform(tr.to_a, nx, ny, nz) if tr
      end
      len = Math.sqrt(nx * nx + ny * ny + nz * nz)
      return nil if len < 1e-9
      nx /= len; ny /= len; nz /= len
      # Orienta la normale contro la direzione del raggio
      if nx * dx + ny * dy + nz * dz > 0
        nx = -nx; ny = -ny; nz = -nz
      end
      [nx, ny, nz]
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Trasforma una normale con l'inversa trasposta della parte lineare di
    # una trasformazione (matrice per colonne, come Transformation#to_a).
    # Con la matrice diretta, un gruppo stirato su un asse inclinerebbe le
    # normali: rimbalzi e scivolamenti prenderebbero direzioni sbagliate.
    def self.normal_xform(m, x, y, z)
      a, b, c = m[0], m[4], m[8]    # riga 0: L = [[a b c] [d e f] [g h i]]
      d, e, f = m[1], m[5], m[9]
      g, h, i = m[2], m[6], m[10]
      # (L⁻¹)ᵀ ∝ matrice dei cofattori: il fattore 1/det non serve, si normalizza dopo
      c00 = e * i - f * h; c01 = f * g - d * i; c02 = d * h - e * g
      c10 = c * h - b * i; c11 = a * i - c * g; c12 = b * g - a * h
      c20 = b * f - c * e; c21 = c * d - a * f; c22 = a * e - b * d
      det = a * c00 + b * c01 + c * c02
      s = det < 0 ? -1.0 : 1.0     # cofattori × segno(det) = (L⁻¹)ᵀ a meno di un fattore positivo
      [s * (c00 * x + c10 * y + c20 * z),
       s * (c01 * x + c11 * y + c21 * z),
       s * (c02 * x + c12 * y + c22 * z)]
    end

    def self.ray(ox, oy, oz, dx, dy, dz)
      Sketchup.active_model.raytest(
        [Geom::Point3d.new(ox, oy, oz), Geom::Vector3d.new(dx, dy, dz)], true
      )
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Raycast che ignora l'entità `skip`. Serve per i corpi rigidi: i raggi
    # partono dall'interno dell'oggetto (centro / base) e senza questo filtro
    # colpirebbero le facce dell'oggetto stesso invece del pavimento o del muro.
    # Avanza oltre ogni colpo appartenente a `skip`, fino a max_hits tentativi.
    def self.ray_ignoring(ox, oy, oz, dx, dy, dz, skip, max_hits = 4)
      len = Math.sqrt(dx * dx + dy * dy + dz * dz)
      return nil if len < 1e-9
      ux = dx / len; uy = dy / len; uz = dz / len
      t  = 0.0
      max_hits.times do
        res = ray(ox + ux * t, oy + uy * t, oz + uz * t, ux, uy, uz)
        return nil unless res
        hit = res[0]
        ent = res[1].is_a?(Array) ? res[1].first : nil
        return res unless ent && ent == skip
        # Avanza appena oltre la faccia colpita e riprova
        d = Math.sqrt((hit.x - ox)**2 + (hit.y - oy)**2 + (hit.z - oz)**2)
        nt = d + 0.02
        return nil if nt <= t + 1e-6      # nessun progresso: esci
        t = nt
      end
      nil
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Raycast del player: attraversa l'oggetto tenuto in mano. Senza questo,
    # guardando in basso con un oggetto afferrato il pavimento sonda la sua
    # faccia superiore, il player ci sale sopra, l'oggetto sale con la camera
    # e si vola all'infinito; e il calcio colpirebbe l'oggetto in mano.
    def self.pray(ox, oy, oz, dx, dy, dz)
      g = @grabbed_entity
      if g && g.valid?
        ray_ignoring(ox, oy, oz, dx, dy, dz, g)
      else
        ray(ox, oy, oz, dx, dy, dz)
      end
    end

  end
end
