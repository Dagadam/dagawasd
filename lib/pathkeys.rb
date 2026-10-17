# DagaWASD — Percorsi da ritoccare: il percorso come posizioni nel modello
# (sfere con una freccia) da spostare e ruotare con gli strumenti di
# SketchUp; riproduzione, scene e video le seguono a velocità costante.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Ogni posizione è un'istanza di un componente «KEY_DEF <fov>°» al primo
    # livello del modello, con gli attributi KEY_DICT 'path' (nome del
    # percorso), 'i' (ordine) e 'fov' (gradi). Il centro della sfera è
    # l'occhio, la freccia (asse rosso) la direzione dello sguardo, lunga
    # quanto lo zoom; il triangolo sopra il riquadro (asse blu) l'alto.
    # Tutte hanno il tag KEY_TAG, che si spegne in
    # modalità FPS e durante riproduzione e video: la camera non le vede
    # e il giocatore non ci sbatte contro.
    # Una copia (Ctrl+Sposta) ha lo stesso 'i' dell'originale: va prima o
    # dopo secondo la distanza dalla posizione precedente, e alla fine
    # dell'operazione l'ordine si riscrive (key_fix_order).
    # Fra una posizione e l'altra una curva morbida (Hermite, tangenti
    # pesate sulle distanze: niente anse) percorsa a velocità costante, la
    # media della registrazione ('v' nel JSON del percorso) o KEY_V;
    # girarsi sul posto va a KEY_TURN gradi al secondo.
    # ══════════════════════════════════════════════════════════════
    KEY_DICT = 'DagaWASD_posizione'
    KEY_DEF  = 'DagaWASD camera'
    KEY_TAG  = 'DagaWASD percorsi'
    KEY_MAT  = { 'DagaWASD posizione' => [255, 140, 0], 'DagaWASD freccia' => [200, 40, 30],
                 'DagaWASD alto' => [245, 245, 245] }.freeze
    KEY_R    = 0.12 * M_TO_IN        # raggio della sfera (la freccia arriva a 4,4 raggi)
    KEY_TOL  = 0.25 * M_TO_IN        # schematizzazione: scarto massimo di posizione…
    KEY_ANG  = 10.0                  # …e di direzione (°)
    KEY_V    = 1.4                   # m/s: percorso nuovo, passo tranquillo
    KEY_TURN = 45.0                  # °/s: girarsi sul posto
    KEY_SUB  = 24                    # pezzi per tratto: lunghezza e curva disegnata

    # ── I componenti ──────────────────────────────────────────────
    # Uno per campo visivo, in gradi interi: la freccia è lunga quanto lo
    # zoom, e le sfere con lo stesso zoom (anche le copie con Ctrl+Sposta)
    # condividono il componente. Cercati per attributo (il nome si può
    # cambiare); l'elenco è ricordato per 2 s, perché l'Overlay lo chiede a
    # ogni ridisegno.
    # Versione della forma, nell'attributo 'def'. 2: riquadro col triangolo
    # dell'alto (si vede il rollio); 3 (2026-10-17): via il perno bianco,
    # doppione del triangolo; freccia lunga quanto lo zoom.
    KEY_DEF_V  = 3
    KEY_FOV0   = 70.0                # campo visivo di FPS senza zoom: freccia di 4,4 raggi
    KEY_FOV_TOL = 3.0                # schematizzazione: scarto massimo di zoom (°)
    KEY_ZOOM_V = 1.0                 # raddoppi d'ingrandimento al secondo, zoomando sul posto

    def self.key_defs(model)
      c = @key_defs
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return c[1] if c && c[0].equal?(model) && now - c[2] < 2.0 && c[1].all?(&:valid?)
      list = model.definitions.select { |x| x.get_attribute(KEY_DICT, 'def') }
      @key_defs = [model, list, now]
      list
    end

    # Il componente per quel campo visivo, fatto se manca (dentro un'operazione)
    def self.key_def(model, fov)
      g = fov.to_f.round.clamp(1, 179)
      d = key_defs(model).find do |x|
        x.get_attribute(KEY_DICT, 'fov') == g && x.get_attribute(KEY_DICT, 'def').to_i >= KEY_DEF_V
      end
      return d if d
      d = model.definitions.add("#{KEY_DEF} #{g}°")
      d.description = 'DagaWASD'
      d.set_attribute(KEY_DICT, 'fov', g)
      key_shape(model, d, g)
      @key_defs = nil
      d
    end

    # Componenti di una forma vecchia (uno solo per tutte le sfere, col perno):
    # ogni sfera passa a quello del suo zoom e il vecchio, vuoto, si toglie.
    # Dentro un'operazione.
    def self.key_upgrade(model)
      old = key_defs(model).select { |x| x.get_attribute(KEY_DICT, 'def').to_i < KEY_DEF_V }
      return if old.empty?
      old.each do |d|
        d.instances.dup.each { |e| e.definition = key_def(model, (e.get_attribute(KEY_DICT, 'fov') || 60.0).to_f) }
        model.definitions.remove(d) if d.instances.empty?
      end
      @key_defs = nil
    end

    # Via i componenti delle sfere rimasti senza sfere (uno zoom che non c'è
    # più): non restano nel modello fra gli inutilizzati. Dentro un'operazione.
    def self.key_purge(model)
      key_defs(model).each { |d| model.definitions.remove(d) if d.instances.empty? }
      @key_defs = nil
    end

    # Ingrandimento rispetto a KEY_FOV0 (2 = immagine grande il doppio)
    def self.key_zoom(fov)
      Math.tan(KEY_FOV0 * Math::PI / 360) / Math.tan(fov.to_f.clamp(1.0, 179.0) * Math::PI / 360)
    end

    # Lunghezza della freccia: 4,4 raggi senza zoom, proporzionale
    # all'ingrandimento; mai più corta di 3,2 raggi (deve uscire dal riquadro).
    def self.key_arrow(fov)
      (4.4 * KEY_R * key_zoom(fov)).clamp(3.2 * KEY_R, 18.0 * KEY_R)
    end

    # La forma, nel sistema della camera: x lo sguardo, z l'alto. Sfera,
    # freccia rossa lunga quanto lo zoom e, davanti, il riquadro 16:9 di ciò
    # che si vede col triangolo sul lato alto, unito al centro da quattro
    # spigoli: quando la camera ruota attorno alla freccia il riquadro si inclina.
    def self.key_shape(model, d, fov)
      e = d.entities
      e.clear!
      r = KEY_R
      ball = (0..8).map { |k| a = Math::PI * (1 - k / 8.0); [r * Math.cos(a), r * Math.sin(a)] }
      key_lathe(e, ball, :x, nil)        # la sfera prende il colore dell'istanza
      len = key_arrow(fov)
      key_lathe(e, [[0.5 * r, 0.12 * r], [len - 1.2 * r, 0.12 * r], [len - 1.2 * r, 0.35 * r], [len, 0.0]], :x,
                key_material(model, 'DagaWASD freccia'))
      bianco = key_material(model, 'DagaWASD alto')
      x = 2.6 * r                        # il riquadro, dove la freccia è ancora sottile
      w = 1.6 * r; h = 0.9 * r; t = 0.14 * r
      pt = ->(y, z) { Geom::Point3d.new(x, y, z) }
      mesh = Geom::PolygonMesh.new
      [[[-w, h - t], [w, h - t], [w, h], [-w, h]],                       # sopra
       [[-w, -h], [w, -h], [w, -h + t], [-w, -h + t]],                   # sotto
       [[-w, -h + t], [-w + t, -h + t], [-w + t, h - t], [-w, h - t]],   # lati
       [[w - t, -h + t], [w, -h + t], [w, h - t], [w - t, h - t]],
       [[-0.5 * r, h + 0.12 * r], [0.5 * r, h + 0.12 * r], [0.0, h + 0.72 * r]]].each do |poly|   # l'alto
        mesh.add_polygon(poly.map { |y, z| pt.(y, z) })
      end
      # solo AUTO_SOFTEN: spariscono gli spigoli fra pezzi complanari, il contorno resta
      e.add_faces_from_mesh(mesh, Geom::PolygonMesh::AUTO_SOFTEN, bianco, bianco)
      [[-w, -h], [w, -h], [w, h], [-w, h]].each do |y, z|
        c = pt.(y, z)
        v = Geom::Vector3d.new(c.x, c.y, c.z)
        e.add_line(Geom::Point3d.new(v.x * r / v.length, v.y * r / v.length, v.z * r / v.length), c)
      end
      d.set_attribute(KEY_DICT, 'def', KEY_DEF_V)
    end

    # Superficie di rivoluzione: profilo [[lungo l'asse, raggio], …] attorno
    # all'asse x o z, facce rivolte all'esterno.
    def self.key_lathe(ents, prof, axis, mat, segs = 16)
      mesh = Geom::PolygonMesh.new
      ring = prof.map do |x, rad|
        Array.new(segs) do |k|
          a = 2 * Math::PI * k / segs
          c = rad * Math.cos(a); s = rad * Math.sin(a)
          axis == :x ? Geom::Point3d.new(x, c, s) : Geom::Point3d.new(c, s, x)
        end
      end
      prof.each_cons(2).with_index do |((_, r0), (_, r1)), j|
        a = ring[j]; b = ring[j + 1]
        segs.times do |k|
          k1 = (k + 1) % segs
          pts = if r0 < 1e-9 then [a[k], b[k1], b[k]]
                elsif r1 < 1e-9 then [a[k], a[k1], b[k]]
                else [a[k], a[k1], b[k1], b[k]]
                end
          mesh.add_polygon(pts)
        end
      end
      flags = Geom::PolygonMesh::AUTO_SOFTEN | Geom::PolygonMesh::SMOOTH_SOFT_EDGES
      mat ? ents.add_faces_from_mesh(mesh, flags, mat) : ents.add_faces_from_mesh(mesh, flags)
    end

    def self.key_material(model, name)
      model.materials[name] || model.materials.add(name).tap { |m| m.color = Sketchup::Color.new(*KEY_MAT[name]) }
    end

    def self.key_tag(model)
      model.layers[KEY_TAG] || model.layers.add(KEY_TAG)
    end

    # ── Posizione ↔ istanza ───────────────────────────────────────
    # Posizione = [x, y, z, dx, dy, dz, ux, uy, uz, fov], come un fotogramma.
    def self.key_transform(k)
      f = path_orthonormal!(k[0, 10].map(&:to_f))
      yx = f[7] * f[5] - f[8] * f[4]               # asse verde = alto × direzione
      yy = f[8] * f[3] - f[6] * f[5]
      yz = f[6] * f[4] - f[7] * f[3]
      Geom::Transformation.new([f[3], f[4], f[5], 0.0, yx, yy, yz, 0.0, f[6], f[7], f[8], 0.0, f[0], f[1], f[2], 1.0])
    end

    # Scala e specchiature dell'istanza non contano: assi riportati a versori.
    # Posizione dell'istanza: i 10 valori di un fotogramma, più la sosta (s)
    # e la velocità del tratto verso la prossima (m/s; 0 = quella del percorso),
    # che il pannello della sfera (lib/keyedit.rb) può dare a ogni sfera.
    def self.key_of(e)
      m = e.transformation.to_a
      w = m[15].to_f
      w = 1.0 if w.abs < 1e-12
      path_orthonormal!([m[12] / w, m[13] / w, m[14] / w, m[0], m[1], m[2], m[8], m[9], m[10],
                         (e.get_attribute(KEY_DICT, 'fov') || 60.0).to_f,
                         e.get_attribute(KEY_DICT, 'sosta').to_f, e.get_attribute(KEY_DICT, 'v').to_f])
    end

    def self.key_dist3(a, b, o = 0)
      Math.sqrt((b[o] - a[o])**2 + (b[o + 1] - a[o + 1])**2 + (b[o + 2] - a[o + 2])**2)
    end

    # { nome del percorso => [istanze nell'ordine] }, solo quelle al primo livello.
    def self.key_instances(model = Sketchup.active_model)
      return {} unless model
      by = Hash.new { |h, k| h[k] = [] }
      key_defs(model).each do |d|
        d.instances.each do |e|
          next if !e.valid? || e.parent.is_a?(Sketchup::ComponentDefinition)
          n = e.get_attribute(KEY_DICT, 'path') or next
          by[n.to_s] << e
        end
      end
      return {} if by.empty?
      by.transform_values { |list| key_order(list) }
    end

    # Per 'i'; a pari 'i' (copie) la più vicina alla posizione precedente
    # prima, o la più lontana dalla successiva se è la prima.
    def self.key_order(list)
      groups = list.group_by { |e| e.get_attribute(KEY_DICT, 'i').to_f }.sort_by(&:first).map(&:last)
      out = []
      groups.each_with_index do |g, gi|
        if g.size > 1
          if (prev = out.last)
            p = key_of(prev)
            g = g.sort_by { |e| [key_dist3(key_of(e), p), e.entityID] }
          elsif (nx = groups[gi + 1]&.first)
            q = key_of(nx)
            g = g.sort_by { |e| [-key_dist3(key_of(e), q), e.entityID] }
          end
        end
        out.concat(g)
      end
      out
    end

    def self.key_read(name, model = Sketchup.active_model)
      (key_instances(model)[name] || []).map { |e| key_of(e) }
    end

    def self.key_speed(data)
      v = data.is_a?(Hash) ? data['v'].to_f : 0.0
      v > 0 ? v.clamp(0.2, 20.0) : KEY_V
    end

    # ══════════════════════════════════════════════════════════════
    # Curva e tempi
    # ══════════════════════════════════════════════════════════════
    # Tangenti per unità di lunghezza di un canale (posizione, direzione o
    # alto: indici o..o+2): differenza centrata divisa per le due distanze,
    # così un tratto corto accanto a uno lungo non fa anse; ai capi la corda.
    # Negli spigoli si accorciano di (1 + cos θ) / 2, θ = angolo fra le due
    # corde: a 90° la curva esce di 1/27 del tratto invece di 2/27 (contro
    # un muro, in una porta), dritta resta com'è, a 180° torna indietro.
    def self.key_tangents(keys, o, len)
      n = keys.size
      Array.new(n) do |i|
        a = keys[i.zero? ? 0 : i - 1]; b = keys[i == n - 1 ? i : i + 1]; c = keys[i]
        l = (i.zero? ? 0.0 : len[i - 1]) + (i == n - 1 ? 0.0 : len[i])
        next [0.0, 0.0, 0.0] if l < 1e-9
        k = 1.0 / l
        if i.positive? && i < n - 1 && len[i - 1] > 1e-9 && len[i] > 1e-9
          cos = ((c[o] - a[o]) * (b[o] - c[o]) + (c[o + 1] - a[o + 1]) * (b[o + 1] - c[o + 1]) +
                 (c[o + 2] - a[o + 2]) * (b[o + 2] - c[o + 2])) / (len[i - 1] * len[i])
          k *= (1 + cos.clamp(-1.0, 1.0)) / 2
        end
        [(b[o] - a[o]) * k, (b[o + 1] - a[o + 1]) * k, (b[o + 2] - a[o + 2]) * k]
      end
    end

    def self.key_spline(keys)
      ls = [0, 3, 6].map { |o| (0...keys.size - 1).map { |i| key_dist3(keys[i], keys[i + 1], o) } }
      { k: keys, l: ls, t: [0, 3, 6].each_with_index.map { |o, c| key_tangents(keys, o, ls[c]) } }
    end

    # Canale c (0 posizione, 1 direzione, 2 alto) del tratto i al parametro u
    def self.key_herm(sp, c, i, u)
      a = sp[:k][i]; b = sp[:k][i + 1]; o = c * 3
      ta = sp[:t][c][i]; tb = sp[:t][c][i + 1]; l = sp[:l][c][i]
      u2 = u * u; u3 = u2 * u
      h00 = 2 * u3 - 3 * u2 + 1; h10 = (u3 - 2 * u2 + u) * l; h01 = 3 * u2 - 2 * u3; h11 = (u3 - u2) * l
      [h00 * a[o] + h10 * ta[0] + h01 * b[o] + h11 * tb[0],
       h00 * a[o + 1] + h10 * ta[1] + h01 * b[o + 1] + h11 * tb[1],
       h00 * a[o + 2] + h10 * ta[2] + h01 * b[o + 2] + h11 * tb[2]]
    end

    def self.key_eval(sp, i, u)
      a = sp[:k][i]; b = sp[:k][i + 1]
      path_orthonormal!(key_herm(sp, 0, i, u) + key_herm(sp, 1, i, u) + key_herm(sp, 2, i, u) << a[9] + (b[9] - a[9]) * u)
    end

    def self.key_angle(a, b, o)
      Math.acos((a[o] * b[o] + a[o + 1] * b[o + 1] + a[o + 2] * b[o + 2]).clamp(-1.0, 1.0))
    end

    # Per tratto: lunghezze cumulate dei KEY_SUB pezzi e durata (s) =
    # lunghezza alla velocità v (m/s), o il tempo per girarsi se è di più.
    def self.key_timing(sp, v_m)
      w = KEY_TURN * Math::PI / 180
      ks = sp[:k]
      Array.new(ks.size - 1) do |i|
        v = (ks[i][11].to_f > 0 ? ks[i][11].to_f : v_m) * M_TO_IN   # velocità propria del tratto, se c'è
        cum = [0.0]
        prev = ks[i]
        (1..KEY_SUB).each do |j|
          pt = key_herm(sp, 0, i, j.to_f / KEY_SUB)
          cum << cum.last + key_dist3(prev, pt)
          prev = pt
        end
        turn = [key_angle(ks[i], ks[i + 1], 3), key_angle(ks[i], ks[i + 1], 6)].max
        # zoomare sul posto prende il suo tempo: KEY_ZOOM_V raddoppi al secondo
        zoom = Math.log(key_zoom(ks[i + 1][9]) / key_zoom(ks[i][9])).abs / Math.log(2) / KEY_ZOOM_V
        { cum: cum, dur: [cum.last / v, turn / w, zoom, 1.0 / PATH_HZ].max }
      end
    end

    # Parametro u che lascia indietro la frazione f della lunghezza del tratto
    def self.key_u(cum, f)
      tot = cum.last
      return f if tot < 1e-6
      s = f * tot
      j = 0
      j += 1 while j < KEY_SUB - 1 && cum[j + 1] < s
      seg = cum[j + 1] - cum[j]
      ((j + (seg < 1e-12 ? 0.0 : (s - cum[j]) / seg)) / KEY_SUB).clamp(0.0, 1.0)
    end

    def self.key_duration(keys, v_m)
      keys.size < 2 ? 0.0 : key_schedule(keys, v_m).last[:leave]
    end

    # La linea del tempo: su ogni sfera la sua sosta, poi il tratto verso la
    # prossima. Per sfera: arrivo e partenza (s dall'inizio) e durata del
    # tratto che parte da lì (nil per l'ultima).
    def self.key_schedule(keys, v_m, tm = nil)
      tm ||= keys.size < 2 ? [] : key_timing(key_spline(keys), v_m)
      t = 0.0
      keys.each_with_index.map do |k, i|
        arrive = t
        t += k[10].to_f
        leave = t
        seg = tm[i] && tm[i][:dur]
        t += seg.to_f
        { arrive: arrive, leave: leave, seg: seg }
      end
    end

    # Fotogrammi a PATH_HZ (come path_frames), dall'una all'altra posizione,
    # fermi sulle soste.
    def self.key_frames(keys, v_m)
      sp = key_spline(keys)
      tm = key_timing(sp, v_m)
      parts = []
      keys.each_with_index do |k, i|
        parts << [:sosta, k[10].to_f, i] if k[10].to_f > 0
        parts << [:tratto, tm[i][:dur], i] if i < tm.size
      end
      total = parts.sum { |p| p[1] }
      j = 0; t0 = 0.0
      frames = Array.new((total * PATH_HZ).floor + 1) do |n|
        t = n / PATH_HZ
        while j < parts.size - 1 && t > t0 + parts[j][1]
          t0 += parts[j][1]; j += 1
        end
        kind, dur, i = parts[j]
        if kind == :sosta
          path_orthonormal!(keys[i][0, 10].dup)
        else
          key_eval(sp, i, key_u(tm[i][:cum], ((t - t0) / dur).clamp(0.0, 1.0)))
        end
      end
      frames << path_orthonormal!(keys.last[0, 10].dup) if (frames.size - 1) / PATH_HZ < total - 1e-6
      frames
    end

    # Punti della curva da disegnare (KEY_SUB per tratto)
    def self.key_curve(keys)
      return [] if keys.size < 2
      sp = key_spline(keys)
      pts = [keys.first[0, 3]]
      (keys.size - 1).times { |i| (1..KEY_SUB).each { |j| pts << key_herm(sp, 0, i, j.to_f / KEY_SUB) } }
      pts
    end

    # ── Dalla registrazione alle posizioni ────────────────────────
    # Ramer–Douglas–Peucker sui fotogrammi levigati: si tiene il fotogramma
    # che più si scosta dal tratto fra i due già tenuti (posizione fuori
    # della corda oltre KEY_TOL, o sguardo diverso da quello intermedio
    # oltre KEY_ANG), finché nessuno si scosta più.
    def self.key_from_frames(fr)
      keep = [0, fr.size - 1]
      stack = [[0, fr.size - 1]]
      until stack.empty?
        a, b = stack.pop
        next if b - a < 2
        worst = 1.0; at = nil
        (a + 1...b).each do |i|
          e = key_err(fr[a], fr[b], fr[i], (i - a).to_f / (b - a))
          if e > worst
            worst = e; at = i
          end
        end
        next unless at
        keep << at
        stack.push([a, at], [at, b])
      end
      keep.uniq.sort.map { |i| fr[i][0, 10].dup }
    end

    # Scarto del fotogramma p dal tratto a–b, in unità di tolleranza (> 1 = troppo)
    def self.key_err(a, b, p, f)
      dx = b[0] - a[0]; dy = b[1] - a[1]; dz = b[2] - a[2]
      l2 = dx * dx + dy * dy + dz * dz
      s = l2 < 1e-9 ? 0.0 : (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy + (p[2] - a[2]) * dz) / l2).clamp(0.0, 1.0)
      pos = Math.sqrt((a[0] + dx * s - p[0])**2 + (a[1] + dy * s - p[1])**2 + (a[2] + dz * s - p[2])**2) / KEY_TOL
      qx = a[3] + (b[3] - a[3]) * f; qy = a[4] + (b[4] - a[4]) * f; qz = a[5] + (b[5] - a[5]) * f
      ql = Math.sqrt(qx * qx + qy * qy + qz * qz)
      return 99.0 if ql < 1e-6
      ang = Math.acos(((qx * p[3] + qy * p[4] + qz * p[5]) / ql).clamp(-1.0, 1.0)) * 180 / Math::PI / KEY_ANG
      # lo zoom fatto con la rotella: senza, zoomare fermi o andando dritti si perdeva
      zoom = (a[9] + (b[9] - a[9]) * f - p[9]).abs / KEY_FOV_TOL
      [pos, ang, zoom].max
    end

    # Velocità media mentre ci si muoveva (m/s): le soste non la abbassano.
    def self.key_rec_speed(fr)
      lim = 0.2 * M_TO_IN / PATH_HZ
      d = 0.0; n = 0
      fr.each_cons(2) do |a, b|
        s = key_dist3(a, b)
        next if s < lim
        d += s; n += 1
      end
      n.zero? ? KEY_V : (d / M_TO_IN / (n / PATH_HZ)).clamp(0.2, 20.0)
    end

    # Due posizioni: la vista attuale e tre metri più avanti, in piano.
    def self.key_from_view(view)
      c = view.camera
      e = c.eye; d = c.direction; u = c.up
      a = path_orthonormal!([e.x, e.y, e.z, d.x, d.y, d.z, u.x, u.y, u.z, c.perspective? ? c.fov.to_f : 60.0])
      h = Math.sqrt(a[3]**2 + a[4]**2)
      hx, hy = h < 1e-6 ? [1.0, 0.0] : [a[3] / h, a[4] / h]
      b = a.dup
      b[0] += hx * 3.0 * M_TO_IN; b[1] += hy * 3.0 * M_TO_IN
      [a, b]
    end

    def self.key_place(model, name, keys)
      key_upgrade(model)
      mat = key_material(model, 'DagaWASD posizione')
      tag = key_tag(model)
      keys.each_with_index do |k, i|
        d = key_def(model, k[9])                           # la freccia del suo zoom
        e = model.entities.add_instance(d, key_transform(k)) # rubocop:disable SketchupSuggestions/ModelEntities
        e.material = mat
        e.layer = tag
        e.name = name
        e.set_attribute(KEY_DICT, 'path', name)
        e.set_attribute(KEY_DICT, 'i', i)
        e.set_attribute(KEY_DICT, 'fov', k[9].to_f.round(2))
        e.set_attribute(KEY_DICT, 'sosta', k[10].to_f.round(2)) if k[10].to_f > 0
        e.set_attribute(KEY_DICT, 'v', k[11].to_f.round(2)) if k[11].to_f > 0
      end
      key_purge(model)
    end

    # ══════════════════════════════════════════════════════════════
    # Comandi dal pannello
    # ══════════════════════════════════════════════════════════════
    # «Modifica»: crea le posizioni (dalla registrazione, o due davanti alla
    # vista se non c'è), poi le nasconde e le rimostra.
    def self.key_edit(name)
      return t('path.busy') if @path_job
      model = Sketchup.active_model
      data = path_data(name, model) or return t('path.missing')
      list = key_instances(model)[name]
      if list && !list.empty?
        show = list.all?(&:hidden?)
        path_write(t(show ? 'path.op_show' : 'path.op_hide'), model) do |m|
          key_upgrade(m)                 # sfere di una forma vecchia: quella nuova
          key_purge(m)
          list.each { |e| e.hidden = !show }
          key_tag(m).visible = true if show && !@active
        end
        return nil
      end
      s = data['s']
      if s.size >= 2
        fr = path_frames(s)
        keys = key_from_frames(fr)
        v = key_rec_speed(fr)
      else
        keys = key_from_view(model.active_view)
        v = key_speed(data)
      end
      path_write(t('path.op_keys'), model) do |m|
        key_place(m, name, keys)
        m.set_attribute(PATH_DICT, name, JSON.generate(data.merge('v' => v.round(3))))
      end
      Sketchup.status_text = format(t('path.keys_made'), n: keys.size, name: name)
      nil
    end

    # «Nuovo dalla vista»: un percorso senza registrazione, due posizioni.
    def self.key_new
      return t('path.busy') if @path_job
      model = Sketchup.active_model
      name = path_new_name(model)
      keys = key_from_view(model.active_view)
      path_write(t('path.op_keys'), model) do |m|
        m.set_attribute(PATH_DICT, name, JSON.generate('date' => Time.now.strftime('%Y-%m-%d %H:%M:%S'), 's' => [], 'v' => KEY_V))
        key_place(m, name, keys)
        key_tag(m).visible = true unless @active
      end
      Sketchup.status_text = format(t('path.keys_made'), n: keys.size, name: name)
      nil
    end

    # «↺»: via le posizioni, si torna alla registrazione.
    def self.key_revert(name)
      list = key_instances[name]
      return nil if list.nil? || list.empty?
      return nil unless UI.messagebox(format(t('path.ask_revert'), n: list.size, name: name), MB_YESNO) == IDYES
      path_write(t('path.op_keys')) do |m|
        m.entities.erase_entities(list) # rubocop:disable SketchupSuggestions/ModelEntities
        key_purge(m)
      end
      nil
    end

    # ── Tag spento in modalità FPS e durante riproduzione e video ─
    # Ritorna true se l'ha spento lui (e dovrà riaccenderlo).
    def self.key_hide(model)
      l = model&.layers&.[](KEY_TAG)
      return false unless l && l.visible?
      l.visible = false
      true
    rescue => fps_err; log_error(__method__, fps_err); false; end

    def self.key_unhide(model, was)
      return unless was
      l = model&.layers&.[](KEY_TAG)
      l.visible = true if l
    rescue => fps_err; log_error(__method__, fps_err); end

    # ══════════════════════════════════════════════════════════════
    # Osservatore del modello e Overlay della curva
    # ══════════════════════════════════════════════════════════════
    # Dopo ogni operazione (spostata, copiata, cancellata una sfera; Ctrl+Z):
    # al giro dopo l'ordine delle copie si fissa e il pannello si aggiorna.
    def self.key_changed(model, commit)
      @key_defs = nil                 # componenti aggiunti, tolti, rinominati
      @key_fix ||= commit
      return if @key_timer
      @key_timer = UI.start_timer(0.25, false) do
        @key_timer = nil
        fix = @key_fix
        @key_fix = false
        begin
          next if @active || @path_job || !model.valid?
          key_fix_order(model) if fix
          path_push_changed
          ke_refresh                       # lib/keyedit.rb: il pannello della sfera, se è aperto
        rescue => fps_err
          log_error(:key_changed, fps_err)
        end
      end
    end

    # Copie con lo stesso 'i': si rinumera tutto il percorso nell'ordine
    # deciso da key_order. Operazione trasparente: si annulla insieme a
    # quella che ha fatto la copia.
    def self.key_fix_order(model)
      dup = key_instances(model).select { |_, l| l.map { |e| e.get_attribute(KEY_DICT, 'i') }.uniq.size < l.size }
      return if dup.empty?
      model.start_operation(t('path.op_keys'), true, false, true)
      dup.each_value { |l| l.each_with_index { |e, i| e.set_attribute(KEY_DICT, 'i', i) } }
      model.commit_operation
    end

    # Pannello: solo se l'elenco è cambiato (durate comprese).
    def self.path_push_changed
      return unless @dialog && @dialog.visible?
      js = js_json(path_list)
      return if js == @path_pushed
      @path_pushed = js
      @dialog.execute_script("setPaths(#{js})")
    end

    def self.key_draw(view)
      return if @active || @path_job
      model = view.model
      tag = model.layers[KEY_TAG]
      return if tag.nil? || !tag.visible?
      cam = view.camera
      eye = cam.eye; dir = cam.direction
      @key_curves ||= {}
      key_instances(model).each do |name, list|
        next if list.all?(&:hidden?)
        sig = list.map { |e| e.transformation.to_a }.hash
        c = @key_curves[name]
        unless c && c[0] == sig
          keys = list.map { |e| key_of(e) }
          c = @key_curves[name] = [sig, key_curve(keys), keys.map { |k| Geom::Point3d.new(k[0], k[1], k[2]) }]
        end
        if c[1].size >= 2
          view.line_width = 2
          view.line_stipple = ''
          view.drawing_color = Sketchup::Color.new(255, 140, 0)
          view.draw(GL_LINE_STRIP, c[1])
        end
        c[2].each_with_index do |pt, i|
          next if (pt.x - eye.x) * dir.x + (pt.y - eye.y) * dir.y + (pt.z - eye.z) * dir.z <= 0
          next unless key_seen?(model, eye, pt)
          sc = view.screen_coords(pt)
          view.draw_text(Geom::Point3d.new(sc.x + 10, sc.y - 22, 0), (i + 1).to_s,
                         size: 11, bold: true, color: Sketchup::Color.new(255, 140, 0))
        end
      end
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # draw_text sta sopra a tutto: il numero di una sfera dietro la casa
    # finiva sul tetto. Un raggio dall'occhio al centro della sfera: la si
    # vede se non tocca nulla prima della sua superficie. Sfere, frecce e
    # riquadri non coprono (il raggio prosegue oltre), le cose nascoste nemmeno.
    def self.key_seen?(model, eye, pt)
      v = eye.vector_to(pt)
      d = v.length.to_f
      return true if d <= KEY_R
      from = eye
      5.times do
        hit = model.raytest([from, v], true) or return true
        return true if eye.distance(hit[0]).to_f >= d - KEY_R * 1.05
        return false unless hit[1].any? { |e| e.respond_to?(:definition) && e.definition.get_attribute(KEY_DICT, 'def') }
        from = hit[0].offset(v, 0.01)                   # un'altra sfera davanti: oltre
      end
      true
    rescue StandardError
      true                                              # nel dubbio il numero si scrive
    end

    class KeyModelObserver < Sketchup::ModelObserver
      def onTransactionCommit(model); DagaWASD::FPSWalk.key_changed(model, true); end
      def onTransactionUndo(model);   DagaWASD::FPSWalk.key_changed(model, false); end
      def onTransactionRedo(model);   DagaWASD::FPSWalk.key_changed(model, false); end
    end

    # Prende in carico il modello attivo: osservatore e Overlay.
    def self.key_attach(model)
      return if model.nil? || @key_model.equal?(model)
      if (old = @key_model)
        begin
          old.remove_observer(@key_obs)
          old.overlays.remove(@key_ov) if @key_ov
        rescue StandardError
          nil                       # modello già chiuso
        end
      end
      @key_model = model
      @key_defs = @key_ov = nil
      @key_curves = {}
      @key_obs ||= KeyModelObserver.new
      model.add_observer(@key_obs)
      return unless SKY_OVERLAY
      @key_ov = KeyOverlay.new
      model.overlays.add(@key_ov)
      @key_ov.enabled = true
    rescue => fps_err; log_error(__method__, fps_err); end

    if SKY_OVERLAY
      class KeyOverlay < Sketchup::Overlay
        def initialize
          super('dagawasd.paths', "DagaWASD — #{DagaWASD::FPSWalk.t('sub.paths')}")
        end
        def draw(view); DagaWASD::FPSWalk.key_draw(view); end
      end
    end

  end
end
