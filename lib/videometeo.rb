# DagaWASD — Meteo nel video: cielo, nuvole, pioggia e lampi anche nei fotogrammi esportati.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk
    # ══════════════════════════════════════════════════════════════
    # Meteo nel video (Percorsi › Video › Meteo nel video)
    # write_image non disegna le Overlay: senza questo file nel video
    # mancano sole, luna, stelle, nuvole, pioggia, neve e fulmini.
    #
    # Orologio (sempre, a ogni esportazione di fotogrammi). Cielo, nuvole,
    # pioggia, temporale e neve al suolo non seguono più i loro timer: vanno
    # avanti di 1/fps secondi di video a fotogramma (vm_step). Il cielo parte
    # dall'ora del pannello, le nuvole dal loro posto iniziale, la pioggia da
    # un seme fisso: due esportazioni uguali danno lo stesso video. Così
    # anche luce, ombre e colori che il cielo scrive nel modello seguono il
    # video: prima seguivano l'orologio vero e, a qualche secondo per
    # fotogramma, un secondo di video poteva saltare un giorno intero.
    # Finita l'esportazione il meteo riprende da dov'era.
    #
    # Fotogramma (opzione accesa, solo Windows: GDI+ via Fiddle):
    #   1. il modello con write_image, cielo di SketchUp spento (DrawHorizon)
    #      e sfondo trasparente: suolo (il mare), nebbia, ombre restano suoi;
    #   2. sotto, il cielo rifatto come lo disegna SketchUp (vm_sky_pixels);
    #   3. sempre sotto il modello sole, luna, stelle, nuvole e la saetta del
    #      fulmine: stanno tutti oltre l'ingombro del modello (sky_dist);
    #   4. sopra, gocce, fiocchi, spruzzi e il lampo che schiarisce la vista;
    #      quelli dietro un muro li toglie una mappa di profondità (raggi
    #      dalla camera su una griglia, vm_depth).
    # Il disegno è quello della vista: sky_draw, cloud_draw e precip_draw
    # ricevono una View finta (VmView) che registra le chiamate; qui si
    # proiettano con la camera del fotogramma e si dipingono. Nessun secondo
    # disegno da tenere allineato al primo.
    # La neve al suolo non c'è ancora (DA_FARE.md).
    # ══════════════════════════════════════════════════════════════
    VM_SEED     = 20_261_110
    VM_SKY_FADE = 17.5 * DEG          # SketchUp: dal colore dell'orizzonte a quello del cielo (misurato)
    VM_SKY_W    = 160                 # pixel di larghezza del cielo, poi ingrandito (è una sfumatura)
    VM_GRID_W   = 64                  # colonne della mappa di profondità
    VM_NEAR     = 0.05 * M_TO_IN      # più vicino di così non si disegna (piano di taglio)

    def self.vm_export?; @vm_export ? true : false; end

    # ── Orologio del video ────────────────────────────────────────
    # Inizio dell'esportazione: il meteo passa all'orologio del video.
    def self.vm_begin(job)
      model = Sketchup.active_model
      return nil unless model && (@sky_model || @cloud_model || @precip_model || @snow_model)
      vm = { live: { sky_utc: @sky_utc, cloud_off: @cloud_off&.dup }, tex: [nil, nil, nil, nil], texs: {} }
      if @sky_model
        sky_sync_place(model)
        vm[:utc0] = cf('sky_now') ? Time.now.to_f : sky_utc_from_cfg(sky_place(model)[2])
      end
      @cloud_off = [0.0, 0.0] if @clouds
      @precip_rnd = Random.new(VM_SEED)           # anche se la pioggia comincia a metà (meteo variabile)
      @storm = @storm_next = nil
      @storm_glow = 0.0
      @vm_export = true
      job[:vm] = vm
      vm[:paint] = cf('path_video_weather') && (@sky_model || @cloud_model || @precip_model) ? vm_paint_start(job, vm) : false
      vm
    rescue => fps_err
      log_error(__method__, fps_err)
      @vm_export = false
      job[:vm] = nil
    end

    # Secondi di video per secondo di cielo
    def self.vm_sky_rate
      return 1.0 if cf('sky_now')
      return 0.0 unless cf('sky_flow')
      86_400.0 / (cf('sky_day_minutes').to_f.clamp(0.5, 120.0) * 60.0)
    end

    # Il meteo all'istante tv (s di video), dt dopo il fotogramma prima,
    # con la camera già al suo posto.
    def self.vm_step(job, view, tv, dt)
      vm = job[:vm] or return
      model = Sketchup.active_model
      e = view.camera.eye
      ex = e.x.to_f; ey = e.y.to_f; ez = e.z.to_f
      if @sky_model
        sky_sync_place(model)
        lat, lon, tz, north = sky_place(model)
        @sky_utc = vm[:utc0] + tv * vm_sky_rate
        weather_vary_step(model, @sky_utc, tz)   # il meteo variabile (lib/sky.rb) all'ora del fotogramma
        @sky = sky_state(@sky_utc, lat, lon, north).merge(tz: tz, lat: lat, lon: lon, place: [lat, lon, tz, north])
        @sky[:stars] = sky_star_dirs(@sky[:matrix]) if cf('sky_stars')
      end
      if @cloud_model && @clouds && @cloud_wind
        k = cloud_timelapse
        @cloud_off[0] += @cloud_wind[0] * dt * k
        @cloud_off[1] += @cloud_wind[1] * dt * k
        cloud_place(ex, ey, ez)
        cloud_refresh_colors
        @cloud_occ = @sky && cf('cloud_shade') ? cloud_occlusion(@sky[:sun]) : 0.0
      end
      if @precip_model && @precip_wind
        unless vm[:seeded]                       # particelle attorno alla prima camera, dal seme fisso
          @precip_rnd = Random.new(VM_SEED)
          precip_seed(ex, ey, ez)
          vm[:seeded] = true
        end
        precip_measure(model, e, nil)            # tutti i tetti attorno, senza limite di tempo
        precip_step(dt, ex, ey, ez, tv)
        storm_step(tv)
      end
      @snow_level = snow_advance(snow_level, dt, snow_falling, precip_kind == 'rain') if @snow_model
      return unless @sky_model && @sky
      (@sky_applied ||= {})[:time_at] = nil      # ombre all'ora esatta di ogni fotogramma
      sky_apply_model(model)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Fine dell'esportazione (o interruzione): il meteo riprende da dov'era.
    def self.vm_end(job)
      vm = job[:vm] or return
      job[:vm] = nil
      @vm_export = false
      vm_paint_end(vm)
      live = vm[:live]
      @sky_utc = live[:sky_utc]
      @cloud_off = live[:cloud_off] if live[:cloud_off] && @clouds
      @sky_tick = @cloud_tick = @precip_tick = @snow_tick = nil
      @precip_rnd = Random.new if @precip_model
      @storm = @storm_next = nil
      @storm_glow = 0.0
      if @sky_model
        @sky_applied = {}                        # luce, ombre e colori di adesso
        sky_frame(true)
      end
      Sketchup.active_model&.active_view&.invalidate
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # ── Fotogramma col meteo dipinto ──────────────────────────────
    def self.vm_paint_start(job, vm)
      return false unless Sketchup.platform == :platform_win
      VmGdi.start
      w = job[:w]; h = job[:h]
      vm[:canvas] = VmGdi.bitmap(w, h)
      vm[:gr] = VmGdi.graphics(vm[:canvas])
      vm[:ia] = VmGdi.attributes
      require 'tmpdir'
      vm[:png] = File.join(Dir.tmpdir, "dagawasd_meteo_#{Process.pid}.png")
      # linee larghe quanto nella vista, in proporzione all'altezza dell'immagine
      vm[:scale] = (h.to_f / [Sketchup.active_model.active_view.vpheight.to_i, 1].max).clamp(0.5, 4.0)
      true
    rescue => fps_err
      log_error(__method__, fps_err)
      vm_paint_end(vm)
      UI.messagebox(t('path.weather_fail'))
      false
    end

    def self.vm_paint_end(vm)
      vm[:texs].each_value { |x| VmGdi.dispose_image(x[:bmp]) if x[:bmp] }
      vm[:texs].clear
      VmGdi.delete_graphics(vm.delete(:gr)) if vm[:gr]
      VmGdi.dispose_image(vm.delete(:canvas)) if vm[:canvas]
      VmGdi.dispose_attributes(vm.delete(:ia)) if vm[:ia]
      File.delete(vm[:png]) if vm[:png] && File.exist?(vm[:png])
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Il fotogramma in file (fmt :jpg o :png). Se GDI+ si inceppa, da lì in
    # poi i fotogrammi escono senza meteo dipinto, ma escono.
    def self.vm_shot(view, job, file, fmt)
      vm = job[:vm]
      w = job[:w]; h = job[:h]
      ro = Sketchup.active_model.rendering_options
      horizon = ro['DrawHorizon']
      ro['DrawHorizon'] = false
      begin
        ok = view.write_image(filename: vm[:png], width: w, height: h, antialias: true, transparent: true)
      ensure
        ro['DrawHorizon'] = horizon
      end
      return false unless ok
      cam = view.camera
      pr = vm_projector(cam, w, h)
      back = VmView.new(cam, w, h, vm[:texs])
      front = VmView.new(cam, w, h, vm[:texs])
      vm_with_textures(vm) do
        sky_draw(back)
        cloud_draw(back) unless cloud_by_sky?
        precip_draw(front) if @precip
      end
      g = vm[:gr]
      VmGdi.clear(g, 0xFF000000)
      VmGdi.draw_pixels(g, vm[:ia], *vm_sky_pixels(pr, w, h, ro, horizon), w, h)
      vm_paint(vm, back.ops, pr, nil)
      VmGdi.draw_file(g, vm[:png], w, h)
      dg = front.ops.any? { |o| o[0] == :d3 } ? vm_depth(pr, w, h) : nil
      vm_paint(vm, front.ops, pr, dg)
      VmGdi.save(vm[:canvas], file, fmt)
      true
    rescue => fps_err
      log_error(__method__, fps_err)
      vm[:paint] = false
      path_plain_shot(view, job, file, fmt)
    end

    # Sole e nuvole tengono la loro texture in @sun_tex e @cloud_tex: durante
    # il disegno nel video quelle sono della View finta (i numeri della vista
    # vera non valgono lì, e viceversa).
    def self.vm_with_textures(vm)
      live = [@sun_tex, @sun_tex_key, @cloud_tex, @cloud_tex_key]
      @sun_tex, @sun_tex_key, @cloud_tex, @cloud_tex_key = vm[:tex]
      begin
        yield
      ensure
        vm[:tex] = [@sun_tex, @sun_tex_key, @cloud_tex, @cloud_tex_key]
        @sun_tex, @sun_tex_key, @cloud_tex, @cloud_tex_key = live
      end
    end

    # ── Proiezione ────────────────────────────────────────────────
    def self.vm_projector(cam, w, h)
      tv = Math.tan(cam.fov.to_f * DEG / 2.0)
      height = !cam.respond_to?(:fov_is_height?) || cam.fov_is_height?
      f = (height ? h : w) / 2.0 / tv
      { eye: cam.eye.to_a.map(&:to_f), dir: cam.direction.to_a.map(&:to_f),
        xa: cam.xaxis.to_a.map(&:to_f), ya: cam.yaxis.to_a.map(&:to_f), f: f, cx: w / 2.0, cy: h / 2.0 }
    end

    # [x, y, profondità lungo lo sguardo]; pixel dall'angolo in alto a sinistra
    def self.vm_proj(pr, p)
      e = pr[:eye]; d = pr[:dir]; xa = pr[:xa]; ya = pr[:ya]
      dx = p[0] - e[0]; dy = p[1] - e[1]; dz = p[2] - e[2]
      z = dx * d[0] + dy * d[1] + dz * d[2]
      return [0.0, 0.0, z] if z <= 1e-9
      k = pr[:f] / z
      [pr[:cx] + k * (dx * xa[0] + dy * xa[1] + dz * xa[2]), pr[:cy] - k * (dx * ya[0] + dy * ya[1] + dz * ya[2]), z]
    end

    # Direzione (non unitaria) del raggio del pixel (sx, sy)
    def self.vm_ray(pr, sx, sy)
      a = (sx - pr[:cx]) / pr[:f]; b = (pr[:cy] - sy) / pr[:f]
      d = pr[:dir]; xa = pr[:xa]; ya = pr[:ya]
      [d[0] + xa[0] * a + ya[0] * b, d[1] + xa[1] * a + ya[1] * b, d[2] + xa[2] * a + ya[2] * b]
    end

    # ── Cielo di fondo ────────────────────────────────────────────
    # Come SketchUp con DrawHorizon (misurato): sotto l'orizzonte lo sfondo,
    # sopra dal colore dell'orizzonte a quello del cielo, smoothstep
    # sull'altezza fino a VM_SKY_FADE; con la nebbia tutto del suo colore;
    # senza cielo tutto sfondo. Pochi pixel, poi GDI+ li ingrandisce.
    # Ritorna [pixel BGRA, larghezza, altezza].
    def self.vm_sky_pixels(pr, w, h, ro, horizon)
      bw = VM_SKY_W; bh = [(bw * h / w.to_f).round, 2].max
      rgb = ->(c) { c.to_a[0, 3].map(&:to_i) }
      bg = rgb.(ro['BackgroundColor'])
      flat =
        if !horizon then bg
        elsif ro['DisplayFog'] then ro['FogUseBkColor'] ? bg : rgb.(ro['FogColor'])
        end
      return [([flat[2], flat[1], flat[0], 255].pack('C4') * (bw * bh)), bw, bh] if flat
      sky = rgb.(ro['SkyColor'])
      hz = ro['HorizonColor'] ? rgb.(ro['HorizonColor']) : sky
      out = String.new(capacity: bw * bh * 4, encoding: Encoding::BINARY)
      bh.times do |j|
        sy = (j + 0.5) * h / bh
        bw.times do |i|
          d = vm_ray(pr, (i + 0.5) * w / bw, sy)
          el = Math.asin((d[2] / Math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])).clamp(-1.0, 1.0))
          c = if el < 0 then bg
              else
                x = (el / VM_SKY_FADE).clamp(0.0, 1.0); s = x * x * (3 - 2 * x)
                [0, 1, 2].map { |q| (hz[q] + (sky[q] - hz[q]) * s).round }
              end
          out << [c[2], c[1], c[0], 255].pack('C4')
        end
      end
      [out, bw, bh]
    end

    # ── Profondità ────────────────────────────────────────────────
    # Per ogni cella della griglia la profondità della prima superficie
    # (infinita se il raggio va nel cielo o sul suolo di SketchUp).
    def self.vm_depth(pr, w, h)
      gw = VM_GRID_W; gh = [(gw * h / w.to_f).round, 1].max
      e = pr[:eye]; dir = pr[:dir]
      grid = Array.new(gw * gh) do |n|
        d = vm_ray(pr, (n % gw + 0.5) * w / gw, (n / gw + 0.5) * h / gh)
        hit = ray(e[0], e[1], e[2], d[0], d[1], d[2])
        next Float::INFINITY unless hit
        p = hit[0]
        (p.x.to_f - e[0]) * dir[0] + (p.y.to_f - e[1]) * dir[1] + (p.z.to_f - e[2]) * dir[2]
      end
      { w: gw, h: gh, kx: gw / w.to_f, ky: gh / h.to_f, d: grid }
    end

    # Visibile se più vicino della superficie dietro: delle quattro celle
    # attorno conta la più lontana (ai bordi meglio una goccia di troppo che
    # un buco nella pioggia).
    def self.vm_visible?(dg, x, y, z)
      return true unless dg
      gx = x * dg[:kx] - 0.5; gy = y * dg[:ky] - 0.5
      i0 = gx.floor; j0 = gy.floor
      i1 = (i0 + 1).clamp(0, dg[:w] - 1); j1 = (j0 + 1).clamp(0, dg[:h] - 1)
      i0 = i0.clamp(0, dg[:w] - 1); j0 = j0.clamp(0, dg[:h] - 1)
      d = dg[:d]; w = dg[:w]
      z < [d[j0 * w + i0], d[j0 * w + i1], d[j1 * w + i0], d[j1 * w + i1]].max
    end

    # ── Pittura ───────────────────────────────────────────────────
    # Le chiamate registrate, nell'ordine: 3D proiettate (e, con la mappa,
    # solo se visibili), 2D come sono.
    def self.vm_paint(vm, ops, pr, dg)
      g = vm[:gr]
      ops.each do |kind, mode, pts, argb, width, tex, uvs|
        sp = kind == :d2 ? pts.map { |p| [p[0].to_f, p[1].to_f, nil] } : pts.map { |p| vm_proj(pr, p) }
        case mode
        when GL_LINES, GL_LINE_STRIP
          pen = VmGdi.pen(argb, width.to_f * vm[:scale])
          step = mode == GL_LINES ? 2 : 1
          (0...sp.size - 1).step(step) do |i|
            a, b = vm_clip_line(sp[i], sp[i + 1], pts[i], pts[i + 1], pr, kind)
            next unless a && (kind == :d2 || vm_visible?(dg, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2))
            VmGdi.line(g, pen, a[0], a[1], b[0], b[1])
          end
        when GL_QUADS, GL_TRIANGLES, GL_POLYGON
          n = { GL_QUADS => 4, GL_TRIANGLES => 3 }[mode] || sp.size
          t = tex && vm[:texs][tex]
          next vm_paint_textured(vm, t, sp, uvs, n) if t && uvs
          brush = VmGdi.brush(argb)
          (0..sp.size - n).step(n) do |i|
            poly = sp[i, n]
            next if kind == :d3 && poly.any? { |q| q[2] < VM_NEAR }
            cx = poly.sum { |q| q[0] } / n; cy = poly.sum { |q| q[1] } / n
            next unless kind == :d2 || vm_visible?(dg, cx, cy, poly.sum { |q| q[2] } / n)
            VmGdi.fill(g, brush, poly)
          end
        end
      end
    end

    # Segmento tagliato al piano vicino (3D); nil se tutto dietro.
    def self.vm_clip_line(a, b, pa, pb, pr, kind)
      return [a, b] if kind == :d2 || (a[2] >= VM_NEAR && b[2] >= VM_NEAR)
      return nil if a[2] < VM_NEAR && b[2] < VM_NEAR
      f = (VM_NEAR - a[2]) / (b[2] - a[2])
      cut = vm_proj(pr, [0, 1, 2].map { |q| pa.to_a[q].to_f + (pb.to_a[q].to_f - pa.to_a[q].to_f) * f })
      a[2] < VM_NEAR ? [cut, b] : [a, cut]
    end

    # Quadrati e triangoli con texture: ogni gruppo di vertici con la stessa
    # trasformazione (texture → schermo) è un'immagine sola, ritagliata sui
    # triangoli (il sole, tagliato all'orizzonte); i quadrati (nuvole) sono
    # un pezzo dell'atlante ciascuno.
    def self.vm_paint_textured(vm, t, sp, uvs, n)
      g = vm[:gr]
      t[:bmp] ||= VmGdi.bitmap_from(t[:w], t[:h], t[:data])
      tw = t[:w].to_f; th = t[:h].to_f
      st = uvs.map { |u| [u[0].to_f * tw, (1.0 - u[1].to_f) * th] }   # prima riga in alto = v 1
      if n == 4
        (0..sp.size - 4).step(4) do |i|
          next if sp[i, 4].any? { |q| q[2] < VM_NEAR }
          m = vm_affine(st[i], st[i + 1], st[i + 3], sp[i], sp[i + 1], sp[i + 3]) or next
          xs = st[i, 4].map(&:first); ys = st[i, 4].map(&:last)
          s0, s1 = xs.minmax; t0, t1 = ys.minmax
          VmGdi.image_points(g, t[:bmp], vm[:ia], [vm_aff(m, s0, t0), vm_aff(m, s1, t0), vm_aff(m, s0, t1)], s0, t0, s1 - s0, t1 - t0)
        end
        return
      end
      groups = []
      (0..sp.size - 3).step(3) do |i|
        tri = sp[i, 3]
        next if tri.any? { |q| q[2] < VM_NEAR }
        m = vm_affine(st[i], st[i + 1], st[i + 2], *tri) or next
        last = groups.last
        if last && vm_same_affine?(last[:m], m, tw, th) then last[:tris] << tri
        else groups << { m: m, tris: [tri] }
        end
      end
      groups.each do |gr|
        m = gr[:m]
        VmGdi.clip_polys(g, gr[:tris])
        VmGdi.image_points(g, t[:bmp], vm[:ia], [vm_aff(m, 0, 0), vm_aff(m, tw, 0), vm_aff(m, 0, th)], 0, 0, tw, th)
        VmGdi.reset_clip(g)
      end
    end

    # Trasformazione affine (s, t) → (x, y) da tre coppie; nil se degenere
    def self.vm_affine(s0, s1, s2, p0, p1, p2)
      ds1 = s1[0] - s0[0]; dt1 = s1[1] - s0[1]; ds2 = s2[0] - s0[0]; dt2 = s2[1] - s0[1]
      det = (ds1 * dt2 - ds2 * dt1).to_f
      return nil if det.abs < 1e-9
      x1 = p1[0] - p0[0]; y1 = p1[1] - p0[1]; x2 = p2[0] - p0[0]; y2 = p2[1] - p0[1]
      a = (x1 * dt2 - x2 * dt1) / det; b = (x2 * ds1 - x1 * ds2) / det
      d = (y1 * dt2 - y2 * dt1) / det; e = (y2 * ds1 - y1 * ds2) / det
      [a, b, p0[0] - a * s0[0] - b * s0[1], d, e, p0[1] - d * s0[0] - e * s0[1]]
    end

    def self.vm_aff(m, s, t); [m[0] * s + m[1] * t + m[2], m[3] * s + m[4] * t + m[5]]; end

    def self.vm_same_affine?(a, b, tw, th)
      [[0, 0], [tw, 0], [0, th], [tw, th]].all? do |s, t|
        p = vm_aff(a, s, t); q = vm_aff(b, s, t)
        (p[0] - q[0]).abs < 0.5 && (p[1] - q[1]).abs < 0.5
      end
    end

    # ══════════════════════════════════════════════════════════════
    # View finta: quello che sky_draw, cloud_draw e precip_draw chiedono a
    # una View, con la camera e la dimensione del fotogramma. Registra.
    # ops: [:d3 | :d2, modo, punti, colore ARGB, larghezza, texture, uvs]
    # ══════════════════════════════════════════════════════════════
    class VmView
      attr_reader :camera, :ops, :vpwidth, :vpheight
      attr_accessor :line_width

      def initialize(cam, w, h, texs)
        @camera = cam; @vpwidth = w; @vpheight = h; @texs = texs
        @ops = []; @argb = 0xFFFFFFFF; @line_width = 1
      end

      def drawing_color=(c)
        r, g, b, a = c.to_a
        @argb = ((a || 255).to_i << 24) | (r.to_i << 16) | (g.to_i << 8) | b.to_i
      end

      def draw(mode, *pts, texture: nil, uvs: nil)
        pts = pts.first if pts.size == 1 && pts.first.is_a?(Array) && !pts.first.first.is_a?(Numeric)
        @ops << [:d3, mode, pts.map { |p| p.to_a.map(&:to_f) }, @argb, @line_width, texture, uvs]
      end

      def draw2d(mode, *pts)
        pts = pts.first if pts.size == 1 && pts.first.is_a?(Array) && !pts.first.first.is_a?(Numeric)
        @ops << [:d2, mode, pts.map { |p| p.to_a.map(&:to_f) }, @argb, @line_width, nil, nil]
      end

      # Lunghezza nel modello di px pixel alla profondità di pt
      def pixels_to_model(px, pt)
        e = @camera.eye; d = @camera.direction
        z = (pt.x - e.x) * d.x + (pt.y - e.y) * d.y + (pt.z - e.z) * d.z
        height = !@camera.respond_to?(:fov_is_height?) || @camera.fov_is_height?
        px * 2.0 * z.to_f * Math.tan(@camera.fov.to_f * DEG / 2.0) / (height ? @vpheight : @vpwidth)
      end

      def load_texture(rep)
        id = (@texs.keys.max || 0) + 1
        @texs[id] = { w: rep.width, h: rep.height, data: rep.data.to_s.b }
        id
      end

      def release_texture(id)
        x = @texs.delete(id)
        VmGdi.dispose_image(x[:bmp]) if x && x[:bmp]
        true
      end

      def invalidate; end
    end

    # ══════════════════════════════════════════════════════════════
    # GDI+ (gdiplus.dll di Windows) via Fiddle, come XInput in gamepad.rb.
    # Caricato al primo uso: fuori da Windows e nei test non si tocca.
    # ══════════════════════════════════════════════════════════════
    module VmGdi
      SIGS = [
        'int GdiplusStartup(void*, void*, void*)',
        'int GdipCreateBitmapFromScan0(int, int, int, int, void*, void*)',
        'int GdipGetImageGraphicsContext(void*, void*)',
        'int GdipDeleteGraphics(void*)',
        'int GdipDisposeImage(void*)',
        'int GdipGraphicsClear(void*, unsigned int)',
        'int GdipSetSmoothingMode(void*, int)',
        'int GdipSetInterpolationMode(void*, int)',
        'int GdipSetPixelOffsetMode(void*, int)',
        'int GdipCreateSolidFill(unsigned int, void*)',
        'int GdipSetSolidFillColor(void*, unsigned int)',
        'int GdipCreatePen1(unsigned int, float, int, void*)',
        'int GdipSetPenColor(void*, unsigned int)',
        'int GdipSetPenWidth(void*, float)',
        'int GdipSetPenStartCap(void*, int)',
        'int GdipSetPenEndCap(void*, int)',
        'int GdipFillPolygon(void*, void*, void*, int, int)',
        'int GdipDrawLine(void*, void*, float, float, float, float)',
        'int GdipLoadImageFromFile(void*, void*)',
        'int GdipDrawImageRectI(void*, void*, int, int, int, int)',
        'int GdipDrawImageRectRect(void*, void*, float, float, float, float, float, float, float, float, int, void*, void*, void*)',
        'int GdipDrawImagePointsRect(void*, void*, void*, int, float, float, float, float, int, void*, void*, void*)',
        'int GdipCreateImageAttributes(void*)',
        'int GdipSetImageAttributesWrapMode(void*, int, unsigned int, int)',
        'int GdipDisposeImageAttributes(void*)',
        'int GdipCreatePath(int, void*)',
        'int GdipAddPathPolygon(void*, void*, int)',
        'int GdipSetClipPath(void*, void*, int)',
        'int GdipResetClip(void*)',
        'int GdipDeletePath(void*)',
        'int GdipSaveImageToFile(void*, void*, void*, void*)'
      ].freeze
      ARGB32       = 0x26200A     # PixelFormat32bppARGB: byte B, G, R, A
      ANTIALIAS    = 4            # SmoothingModeAntiAlias
      BILINEAR     = 6            # InterpolationModeHighQualityBilinear
      NEAREST      = 5            # InterpolationModeNearestNeighbor
      OFFSET_HALF  = 4            # PixelOffsetModeHalf
      UNIT_PIXEL   = 2
      TILE_FLIP_XY = 3            # ai bordi l'immagine si specchia: niente orli trasparenti
      CAP_ROUND    = 2
      JPEG = ['557CF401', '1A04', '11D3', '9A73', '0000F81EF32E'].freeze
      PNG  = ['557CF406', '1A04', '11D3', '9A73', '0000F81EF32E'].freeze
      QUALITY = ['1D5BE4B5', 'FA4A', '452D', '9CDD', '5DB35105E7EB'].freeze

      module_function

      def api
        @api ||= begin
          require 'fiddle'
          require 'fiddle/import'
          m = Module.new
          m.extend(Fiddle::Importer)
          m.dlload('gdiplus.dll')
          SIGS.each { |s| m.extern(s) }
          m
        end
      end

      def ok!(name, st)
        raise IOError, "GDI+ #{name}: #{st}" unless st.zero?
      end

      # Puntatore restituito da una funzione in *out
      def out
        @out ||= Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
      end

      def got; out[0, Fiddle::SIZEOF_VOIDP].unpack1('J'); end

      def start
        return if @token
        input = [1].pack('L') + "\0" * 4 + [0].pack('J') + [0, 0].pack('LL')   # GdiplusStartupInput, versione 1
        tok = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
        ok!('startup', api.GdiplusStartup(tok, input, nil))
        @token = tok[0, Fiddle::SIZEOF_VOIDP].unpack1('J')   # resta acceso finché SketchUp è aperto
      end

      def bitmap(w, h)
        ok!('bitmap', api.GdipCreateBitmapFromScan0(w, h, 0, ARGB32, nil, out))
        got
      end

      # Bitmap dai pixel BGRA (righe dall'alto); i pixel restano tenuti da qui
      def bitmap_from(w, h, data)
        @keep ||= {}
        buf = Fiddle::Pointer.malloc(data.bytesize, Fiddle::RUBY_FREE)
        buf[0, data.bytesize] = data
        ok!('bitmap', api.GdipCreateBitmapFromScan0(w, h, w * 4, ARGB32, buf, out))
        b = got
        @keep[b] = buf
        b
      end

      def graphics(bmp)
        ok!('graphics', api.GdipGetImageGraphicsContext(bmp, out))
        g = got
        api.GdipSetSmoothingMode(g, ANTIALIAS)
        api.GdipSetInterpolationMode(g, BILINEAR)
        api.GdipSetPixelOffsetMode(g, OFFSET_HALF)
        g
      end

      def attributes
        ok!('attributes', api.GdipCreateImageAttributes(out))
        ia = got
        api.GdipSetImageAttributesWrapMode(ia, TILE_FLIP_XY, 0, 0)
        ia
      end

      def dispose_image(b)
        api.GdipDisposeImage(b)
        @keep&.delete(b)
      end

      def delete_graphics(g); api.GdipDeleteGraphics(g); end
      def dispose_attributes(ia); api.GdipDisposeImageAttributes(ia); end
      def clear(g, argb); ok!('clear', api.GdipGraphicsClear(g, argb)); end

      # Un pennello e una penna sola, ricolorati a ogni uso
      def brush(argb)
        if @brush then api.GdipSetSolidFillColor(@brush, argb)
        else
          ok!('brush', api.GdipCreateSolidFill(argb, out))
          @brush = got
        end
        @brush
      end

      def pen(argb, width)
        if @pen
          api.GdipSetPenColor(@pen, argb)
          api.GdipSetPenWidth(@pen, width)
        else
          ok!('pen', api.GdipCreatePen1(argb, width, UNIT_PIXEL, out))
          @pen = got
          api.GdipSetPenStartCap(@pen, CAP_ROUND)
          api.GdipSetPenEndCap(@pen, CAP_ROUND)
        end
        @pen
      end

      def points(pts); pts.flat_map { |p| [p[0], p[1]] }.pack('e*'); end

      def fill(g, brush, poly); api.GdipFillPolygon(g, brush, points(poly), poly.size, 0); end
      def line(g, pen, x1, y1, x2, y2); api.GdipDrawLine(g, pen, x1, y1, x2, y2); end

      # Pixel piccoli stirati su tutta l'immagine (il cielo)
      def draw_pixels(g, ia, data, bw, bh, w, h)
        b = bitmap_from(bw, bh, data)
        begin
          ok!('cielo', api.GdipDrawImageRectRect(g, b, 0.0, 0.0, w.to_f, h.to_f, 0.0, 0.0, bw.to_f, bh.to_f, UNIT_PIXEL, ia, nil, nil))
        ensure
          dispose_image(b)
        end
      end

      # Il PNG del modello, pixel per pixel (senza la scala dei DPI del file)
      def draw_file(g, file, w, h)
        ok!('carica', api.GdipLoadImageFromFile(wstr(file), out))
        img = got
        begin
          api.GdipSetInterpolationMode(g, NEAREST)
          ok!('modello', api.GdipDrawImageRectI(g, img, 0, 0, w, h))
        ensure
          api.GdipSetInterpolationMode(g, BILINEAR)
          api.GdipDisposeImage(img)                  # il file torna libero per il prossimo write_image
        end
      end

      # Il rettangolo (sx, sy, sw, sh) dell'immagine sul parallelogramma dei
      # tre punti: in alto a sinistra, in alto a destra, in basso a sinistra.
      def image_points(g, img, ia, dst, sx, sy, sw, sh)
        api.GdipDrawImagePointsRect(g, img, points(dst), 3, sx.to_f, sy.to_f, sw.to_f, sh.to_f, UNIT_PIXEL, ia, nil, nil)
      end

      def clip_polys(g, polys)
        ok!('path', api.GdipCreatePath(1, out))     # FillModeWinding: unione dei triangoli
        path = got
        begin
          polys.each { |p| api.GdipAddPathPolygon(path, points(p), p.size) }
          api.GdipSetClipPath(g, path, 0)
        ensure
          api.GdipDeletePath(path)
        end
      end

      def reset_clip(g); api.GdipResetClip(g); end

      def wstr(s); (s.to_s.encode('UTF-16LE') + "\0".encode('UTF-16LE')).b; end

      def guid(p); [p[0].hex, p[1].hex, p[2].hex].pack('LSS') + [p[3] + p[4]].pack('H*'); end

      # JPEG (qualità 90) per l'AVI, PNG per la cartella di immagini
      def save(bmp, file, fmt)
        if fmt == :png
          ok!('salva', api.GdipSaveImageToFile(bmp, wstr(file), guid(PNG), nil))
          return
        end
        q = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
        q[0, 4] = [90].pack('L')
        # EncoderParameters: Count, poi un EncoderParameter (GUID, NumberOfValues, Type = Long, Value*)
        params = [1].pack('L') + "\0" * 4 + guid(QUALITY) + [1, 4].pack('LL') + [q.to_i].pack('J')
        ok!('salva', api.GdipSaveImageToFile(bmp, wstr(file), guid(JPEG), params))
      end
    end
  end
end
