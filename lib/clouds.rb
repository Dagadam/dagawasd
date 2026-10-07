# DagaWASD — Nuvole: cumuli portati dal vento, colorati dalla luce del cielo, che velano il sole.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Nuvole (Meteo › Nuvole)
    # Un campo di nuvole su un piano a quota cloud_height, in un quadrato di
    # CLOUD_TILE attorno alla camera: il vento lo trascina e chi esce da un
    # lato rientra dall'altro. Ogni nuvola si disegna come il sole e le
    # stelle: nella sua direzione, appena oltre l'ingombro del modello
    # (sky_dist), quindi gli oggetti del modello la coprono; la grandezza è
    # quella apparente vera (larghezza / distanza).
    #
    # Aspetto: un'immagine con trasparenza (load_texture, SketchUp 2020+).
    # La tinta di drawing_color non colora le texture: il colore va dentro
    # l'immagine. L'atlante ha 4 forme × 4 livelli di foschia (verso
    # l'orizzonte le nuvole sfumano), si ricostruisce quando cambia la luce
    # (alba, tramonto, notte, pioggia). Pixel in ordine BGRA, prima riga in
    # alto (v = 1), margine trasparente: la texture si ripete ai bordi.
    #
    # Tutte in una chiamata, dalla più lontana alla più vicina e ognuna un
    # filo più vicina in profondità: i bordi trasparenti delle vicine non
    # bucano le lontane. Col cielo animato le disegna sky_draw dopo sole,
    # luna e stelle (che restano dietro); senza, la loro Overlay.
    #
    # Col cielo animato: una nuvola davanti al sole abbassa la luce diretta
    # (ombre che vanno e vengono), molte nuvole ingrigiscono il cielo. Con
    # pioggia o neve il cielo si chiude da solo.
    # ══════════════════════════════════════════════════════════════
    CLOUD_TILE      = 24_000.0 * M_TO_IN
    CLOUD_MAX       = 900
    CLOUD_TEX       = 64                    # pixel per nuvola nell'atlante
    CLOUD_SHAPES    = 4
    CLOUD_LEVELS    = [[0.0, 1.0], [0.3, 0.8], [0.55, 0.55], [0.8, 0.3]].freeze   # [foschia, opacità]
    CLOUD_MIN_ELEV  = 2.5 * DEG
    CLOUD_FADE_ELEV = 14.0 * DEG
    # [altezza del sole°, parte illuminata, parte in ombra]
    CLOUD_KEYS = [
      [12.0, [255, 255, 255], [196, 202, 214]],
      [3.0, [255, 228, 205], [170, 160, 170]],
      [-1.0, [252, 168, 128], [120, 100, 116]],
      [-6.0, [118, 96, 128], [62, 56, 82]],
      [-14.0, [34, 38, 52], [22, 25, 36]]
    ].freeze

    def self.cloud_on?; cf('cloud_enabled') ? true : false; end

    # Copertura 0–1; con pioggia o neve il cielo si chiude.
    def self.cloud_cover
      return 0.0 unless cloud_on?
      c = (cf('cloud_cover').to_f / 100.0).clamp(0.0, 1.0)
      p = precip_cover
      p > 0 ? [c, 0.6 + 0.4 * p].max : c
    end

    # Col tempo del cielo accelerato le nuvole corrono come in un time-lapse;
    # al massimo 30 volte, se no attraversano il cielo in pochi secondi.
    def self.cloud_timelapse
      return 1.0 unless cf('cloud_timelapse') && cf('sky_enabled') && cf('sky_flow') && !cf('sky_now')
      (86_400.0 / (cf('sky_day_minutes').to_f.clamp(0.5, 120.0) * 60.0)).clamp(1.0, 30.0)
    end

    # Quanto le nuvole ingrigiscono il cielo (oltre metà copertura)
    def self.cloud_overcast; ((cloud_cover - 0.5) * 1.2).clamp(0.0, 0.6); end

    # Quanto una nuvola copre ora il sole (0–1)
    def self.cloud_sun_shade
      cloud_on? && cf('cloud_shade') ? @cloud_occ.to_f : 0.0
    end

    # ── Campo di nuvole ───────────────────────────────────────────
    # Nuvola = [x, y nel quadrato, larghezza, forma, opacità] (pollici)
    def self.cloud_seed
      rnd = Random.new(4242)
      size = cf('cloud_size').to_f.clamp(200.0, 3000.0) * M_TO_IN
      n = (cloud_cover * CLOUD_TILE**2 / (size * size * 0.55)).round.clamp(0, CLOUD_MAX)
      @clouds = Array.new(n) do
        [rnd.rand * CLOUD_TILE, rnd.rand * CLOUD_TILE, size * (0.6 + 0.8 * rnd.rand), rnd.rand(CLOUD_SHAPES), 0.75 + 0.25 * rnd.rand]
      end
      @cloud_off ||= [0.0, 0.0]
      @cloud_set = [cf('cloud_size'), (cloud_cover * 100).round]
    end

    def self.cloud_wind_v(north_deg)
      sp = cf('cloud_wind').to_f.clamp(0.0, 80.0) * M_TO_IN
      b = (cf('cloud_wind_dir').to_f + 180.0 + north_deg) * DEG
      [Math.sin(b) * sp, Math.cos(b) * sp]
    end

    # Direzioni viste dall'occhio, dalla più lontana alla più vicina:
    # [versore, distanza, mezza larghezza apparente (radianti), forma, livello]
    def self.cloud_place(ex, ey, ez)
      h = cf('cloud_height').to_f.clamp(100.0, 10_000.0) * M_TO_IN
      t = CLOUD_TILE; half = t / 2.0
      ox, oy = @cloud_off
      list = []
      @clouds.each do |x0, y0, w, shape, op|
        dx = (x0 + ox - ex + half) % t - half
        dy = (y0 + oy - ey + half) % t - half
        dz = h - ez
        d = Math.sqrt(dx * dx + dy * dy + dz * dz)
        next if d < 1.0
        v = [dx / d, dy / d, dz / d]
        el = Math.asin(v[2].clamp(-1.0, 1.0))
        next if el < CLOUD_MIN_ELEV
        f = ((el - CLOUD_MIN_ELEV) / (CLOUD_FADE_ELEV - CLOUD_MIN_ELEV)).clamp(0.0, 1.0) * op
        level = f > 0.8 ? 0 : f > 0.55 ? 1 : f > 0.3 ? 2 : 3
        list << [v, d, Math.atan(w / 2.0 / d), shape, level]
      end
      @cloud_list = list.sort_by! { |c| -c[1] }
    end

    # Quanto le nuvole davanti al sole lo coprono (0–1)
    def self.cloud_occlusion(sun)
      return 0.0 unless sun && @cloud_list
      occ = 0.0
      @cloud_list.each do |v, _, hw, _, level|
        c = v[0] * sun[0] + v[1] * sun[1] + v[2] * sun[2]
        next if c < 0.5
        ang = Math.acos(c.clamp(-1.0, 1.0))
        k = (1.0 - ang / (hw * 0.75)) * CLOUD_LEVELS[level][1]
        occ = k if k > occ
      end
      occ.clamp(0.0, 1.0)
    end

    # ── Colori e atlante ──────────────────────────────────────────
    # [illuminata, in ombra, foschia] per la luce di adesso
    def self.cloud_colors
      alt = @sky ? @sky[:sun_alt] : 45.0
      lo = CLOUD_KEYS.find { |k| alt >= k[0] } || CLOUD_KEYS.last
      hi = CLOUD_KEYS.reverse.find { |k| alt <= k[0] } || CLOUD_KEYS.first
      t = lo.equal?(hi) ? 0.0 : (alt - lo[0]) / (hi[0] - lo[0])
      lit = sky_mix(lo[1], hi[1], t); dark = sky_mix(lo[2], hi[2], t)
      p = precip_cover                          # nuvole da pioggia: grigie e cupe
      st = storm_on? ? 1.0 : 0.0                # da temporale: ancora più scure
      if p > 0 || st > 0
        grey = ->(c, k) { g = ((0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]) * k).round; [g, g, g + 3] }
        lit = sky_mix(lit, grey.(lit, 0.62 - 0.2 * st), 0.85 * [p, st].max)
        dark = sky_mix(dark, grey.(dark, 0.45 - 0.17 * st), 0.85 * [p, st].max)
      end
      look = @sky_applied && @sky_applied[:look]
      haze = look ? look[4] : [200, 216, 232]
      [lit, dark, haze]
    end

    # Forme: [opacità, luce] per pixel (riga 0 in alto). Cumuli fatti di
    # bolle sovrapposte, bordi sfrangiati da un rumore, base piatta, più
    # chiari in alto e ai bordi.
    def self.cloud_shapes
      @cloud_shapes ||= Array.new(CLOUD_SHAPES) do |s|
        rnd = Random.new(1000 + s)
        n = CLOUD_TEX
        base = Array.new(4 + rnd.rand(3)) { [0.2 + rnd.rand * 0.6, 0.36 + rnd.rand * 0.1, 0.11 + rnd.rand * 0.08] }
        tops = Array.new(6 + rnd.rand(6)) do
          x = 0.3 + rnd.rand * 0.4
          [x, 0.48 + rnd.rand * 0.22 - (x - 0.5).abs * 0.3, 0.06 + rnd.rand * 0.08]   # più alte al centro
        end
        blobs = base + tops
        grid = Array.new(13) { Array.new(13) { rnd.rand } }
        noise = lambda do |x, y|
          gx = x * 12; gy = y * 12; i = gx.floor.clamp(0, 11); j = gy.floor.clamp(0, 11); fx = gx - i; fy = gy - j
          a = grid[j][i] + (grid[j][i + 1] - grid[j][i]) * fx
          b = grid[j + 1][i] + (grid[j + 1][i + 1] - grid[j + 1][i]) * fx
          a + (b - a) * fy
        end
        alpha = []; light = []
        n.times do |row|
          y = 1.0 - (row + 0.5) / n                 # 0 in basso
          n.times do |col|
            x = (col + 0.5) / n
            v = blobs.sum { |cx, cy, r| Math.exp(-((x - cx)**2 + (y - cy)**2) / (r * r)) }
            v *= 0.7 + 0.6 * noise.(x, y)
            v *= ((y - 0.2) / 0.12).clamp(0.0, 1.0)
            v *= ([x, 1 - x, y, 1 - y].min / 0.08).clamp(0.0, 1.0)
            alpha << ((v - 0.35) * 1.8).clamp(0.0, 1.0)
            light << (y * 1.25 - 0.15 + 0.35 * (1.0 - v.clamp(0.0, 1.5) / 1.5)).clamp(0.0, 1.0)
          end
        end
        [alpha, light]
      end
    end

    # Pixel dell'atlante (4 forme in colonna × 4 livelli in riga), BGRA.
    # Anche i pixel trasparenti hanno il colore della nuvola: col filtro
    # lineare un nero trasparente farebbe un alone scuro.
    def self.cloud_pixels(lit, dark, haze)
      n = CLOUD_TEX; side = n * CLOUD_SHAPES
      data = Array.new(side * CLOUD_LEVELS.size * n * 4, 0)
      shapes = cloud_shapes
      CLOUD_LEVELS.each_with_index do |(hz, am), lev|
        l = sky_mix(lit, haze, hz); k = sky_mix(dark, haze, hz)
        db = l[2] - k[2]; dg = l[1] - k[1]; dr = l[0] - k[0]
        a255 = 255.0 * am
        shapes.each_with_index do |(alpha, light), s|
          n.times do |row|
            i = ((lev * n + row) * side + s * n) * 4
            off = row * n
            n.times do |col|
              t = light[off + col]
              data[i] = (k[2] + db * t).round
              data[i + 1] = (k[1] + dg * t).round
              data[i + 2] = (k[0] + dr * t).round
              data[i + 3] = (alpha[off + col] * a255).round
              i += 4
            end
          end
        end
      end
      data.pack('C*')
    end

    # Ricostruisce l'atlante se la luce è cambiata abbastanza da vedersi.
    def self.cloud_refresh_colors
      cols = cloud_colors
      key = cols.flatten.map { |c| (c / 5).round }
      return if key == @cloud_key
      @cloud_key = key
      @cloud_pix = cloud_pixels(*cols)
    end

    # ── Accensione e fotogrammi ───────────────────────────────────
    def self.cloud_sync
      model = Sketchup.active_model
      return cloud_stop unless cloud_on? && model
      cloud_attach(model)
      cloud_seed if @cloud_set != [cf('cloud_size'), (cloud_cover * 100).round]
      @cloud_wind = cloud_wind_v(model.shadow_info['NorthAngle'].to_f)
      @cloud_key = nil                          # colori da rifare (pioggia, ora…)
      cloud_frame
      rate = cf('cloud_fps').to_i.clamp(5, 30)
      return if rate == @cloud_rate
      UI.stop_timer(@cloud_timer) if @cloud_timer
      @cloud_timer = UI.start_timer(1.0 / rate, true) { cloud_frame }
      @cloud_rate = rate
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.cloud_stop
      UI.stop_timer(@cloud_timer) if @cloud_timer
      @cloud_timer = @cloud_rate = nil
      if (m = @cloud_model)
        begin
          m.overlays.remove(@cloud_ov) if @cloud_ov
          m.active_view.release_texture(@cloud_tex) if @cloud_tex
          m.active_view.invalidate
        rescue StandardError
          nil                       # modello già chiuso
        end
      end
      had_occ = @cloud_occ.to_f > 0
      @cloud_model = @cloud_ov = @clouds = @cloud_list = @cloud_set = @cloud_tex = @cloud_tex_key = nil
      @cloud_key = @cloud_pix = @cloud_tick = nil
      @cloud_occ = 0.0
      sky_frame(true) if had_occ && @sky_model  # il sole torna pieno
    end

    def self.cloud_attach(model)
      return if @cloud_model.equal?(model)
      cloud_stop if @cloud_model
      @cloud_model = model
      @cloud_occ = 0.0
      if SKY_OVERLAY
        @cloud_ov = CloudOverlay.new
        model.overlays.add(@cloud_ov)
        @cloud_ov.enabled = true
      end
      return if @sky_app_obs
      @sky_app_obs = SkyAppObserver.new
      Sketchup.add_observer(@sky_app_obs)
    end

    def self.cloud_frame
      model = @cloud_model
      return unless model
      return cloud_sync unless Sketchup.active_model.equal?(model)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      dt = @cloud_tick ? (now - @cloud_tick).clamp(0.0, 0.5) : 0.0
      @cloud_tick = now
      k = cloud_timelapse
      @cloud_off[0] += @cloud_wind[0] * dt * k
      @cloud_off[1] += @cloud_wind[1] * dt * k
      eye = model.active_view.camera.eye
      cloud_place(eye.x.to_f, eye.y.to_f, eye.z.to_f)
      cloud_refresh_colors
      occ = @sky && cf('cloud_shade') ? cloud_occlusion(@sky[:sun]) : 0.0
      if (occ - @cloud_occ.to_f).abs > 0.04
        @cloud_occ = occ
        sky_frame(true) if @sky_model           # luce del sole velata o di nuovo piena
      end
      model.active_view.invalidate
    rescue => fps_err
      log_error(__method__, fps_err)
      cloud_stop
    end

    # ── Disegno ───────────────────────────────────────────────────
    # g = geometria del fotogramma di sky_draw (se le disegna lui)
    def self.cloud_draw(view, g = nil)
      list = @cloud_list
      return unless list && @cloud_pix && cloud_on? && !list.empty?
      return unless view.respond_to?(:load_texture)
      cam = view.camera
      return unless cam.perspective?
      if @cloud_tex_key != @cloud_key || @cloud_tex.nil?
        rep = Sketchup::ImageRep.new
        side = CLOUD_TEX * CLOUD_SHAPES
        rep.set_data(side, CLOUD_TEX * CLOUD_LEVELS.size, 32, 0, @cloud_pix)
        # prima la nuova, poi via la vecchia: liberandola prima SketchUp
        # riusa lo stesso numero e a volte mostra ancora l'immagine vecchia
        # (nuvole nere: i colori della notte con il giorno di neve)
        old = @cloud_tex
        @cloud_tex = view.load_texture(rep)
        view.release_texture(old) if old
        @cloud_tex_key = @cloud_key
      end
      g ||= sky_geo(cam)
      cw = 1.0 / CLOUD_SHAPES; ch = 1.0 / CLOUD_LEVELS.size
      pad = 0.5 / (CLOUD_TEX * CLOUD_SHAPES)
      # Solo quelle nell'inquadratura (mezza diagonale del campo visivo).
      # Ordine = distanza a cui si disegnano, dalla maggiore: quella cambia
      # a scatti dove il raggio smette di incontrare il modello, e una
      # nuvola disegnata dopo ma più lontana verrebbe tagliata dal bordo
      # trasparente di quella prima (vicino all'orizzonte: bordi dritti).
      dir = g[:dir]
      half = Math.atan(Math.tan(cam.fov * DEG / 2.0) * Math.hypot(1.0, view.vpwidth.to_f / [view.vpheight, 1].max))
      seen = []
      list.each do |c|
        v, _, hw = c
        cosa = v[0] * dir[0] + v[1] * dir[1] + v[2] * dir[2]
        next if Math.acos(cosa.clamp(-1.0, 1.0)) > half + hw * 1.3
        seen << [sky_dist(g, v), c]
      end
      seen.sort_by! { |d, _| -d }
      pts = []; uvs = []
      n = [seen.size, 1].max
      seen.each_with_index do |(dist, (v, _, hw, shape, level)), i|
        d = dist * (0.985 - 0.02 * i / n)          # le successive un filo davanti
        pts.concat(cloud_quad(g, v, hw, d))
        u0 = shape * cw + pad; u1 = (shape + 1) * cw - pad
        vt = 1.0 - level * ch - pad; vb = 1.0 - (level + 1) * ch + pad
        uvs << [u0, vb, 0] << [u1, vb, 0] << [u1, vt, 0] << [u0, vt, 0]
      end
      return if pts.empty?
      view.drawing_color = Sketchup::Color.new(255, 255, 255)
      view.draw(GL_QUADS, pts, texture: @cloud_tex, uvs: uvs)
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # I quattro angoli di una nuvola (direzione v, mezza larghezza hw) a distanza d
    def self.cloud_quad(g, v, hw, d)
      c = sky_at(g, v, d)
      u, w = sky_basis(v)                          # u orizzontale, w verso il basso
      hx = d * Math.tan(hw)
      hy = hx * (0.42 + 0.25 * v[2])               # viste di lato sono più basse
      b = [c[0] + w[0] * hy, c[1] + w[1] * hy, c[2] + w[2] * hy]
      t = [c[0] - w[0] * hy, c[1] - w[1] * hy, c[2] - w[2] * hy]
      [[b[0] - u[0] * hx, b[1] - u[1] * hx, b[2] - u[2] * hx], [b[0] + u[0] * hx, b[1] + u[1] * hx, b[2] + u[2] * hx],
       [t[0] + u[0] * hx, t[1] + u[1] * hx, t[2] + u[2] * hx], [t[0] - u[0] * hx, t[1] - u[1] * hx, t[2] - u[2] * hx]]
    end

    # Profondità lungo lo sguardo del punto più lontano delle nuvole che
    # possono stare davanti al cerchio di raggio ang attorno a w (0 se
    # nessuna): il sole va dietro di loro, se no le taglierebbe (sky_draw_sun).
    def self.cloud_depth_near(g, w, ang)
      list = @cloud_list
      return 0.0 unless list && @cloud_pix && cloud_on?
      e = g[:eye]; dir = g[:dir]
      list.map do |v, _, hw|
        cosa = v[0] * w[0] + v[1] * w[1] + v[2] * w[2]
        next 0.0 if Math.acos(cosa.clamp(-1.0, 1.0)) > ang + hw * 1.3
        cloud_quad(g, v, hw, sky_dist(g, v) * 0.985).map { |p| (p[0] - e[0]) * dir[0] + (p[1] - e[1]) * dir[1] + (p[2] - e[2]) * dir[2] }.max
      end.max || 0.0
    end

    # Le nuvole le disegna il cielo, se c'è (dopo sole e stelle)
    def self.cloud_by_sky?; @sky && @sky_ov && cf('sky_enabled') ? true : false; end

    if SKY_OVERLAY
      class CloudOverlay < Sketchup::Overlay
        def initialize
          super('dagawasd.clouds', "DagaWASD — #{DagaWASD::FPSWalk.t('sub.clouds')}")
        end
        def draw(view)
          DagaWASD::FPSWalk.cloud_draw(view) unless DagaWASD::FPSWalk.cloud_by_sky?
        end
      end
    end

  end
end
