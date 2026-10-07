# DagaWASD — Pioggia e neve: gocce e fiocchi attorno alla camera, vento, nebbia, riparo sotto i tetti.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Pioggia e neve (Meteo › Pioggia e neve)
    # Le particelle vivono in una scatola attorno alla camera: lato 2 ×
    # raggio, da PRECIP_BELOW sotto l'occhio a PRECIP_ABOVE sopra. Chi esce
    # di lato rientra dal lato opposto (la camera si muove e la pioggia la
    # segue senza vuoti); chi tocca terra o un tetto riparte dall'alto, e la
    # goccia lascia uno spruzzo.
    #
    # Tetti: una mappa a celle di 1 m dice a che quota sta la prima
    # superficie vista dall'alto (un raggio verso il basso per cella). Le
    # celle si misurano a poco a poco, dalle più vicine alla camera, pochi
    # millisecondi per fotogramma; finché una cella non è misurata vale il
    # suolo (z = 0). La mappa si azzera quando l'utente modifica il modello
    # (non per le mosse della fisica, che aprono un'operazione a ogni
    # fotogramma).
    #
    # Nebbia: più fitta con l'intensità e con la neve, del colore dello
    # sfondo (che il cielo animato scurisce di notte). Come per il cielo, i
    # valori originali si rimettono spegnendo e prima di ogni salvataggio.
    # Con il cielo animato acceso le precipitazioni coprono anche il cielo:
    # grigio, sole e stelle velati, ombre deboli (precip_cover, lib/sky.rb).
    #
    # Disegno: un'Overlay come il cielo; le gocce sono segmenti (la scia di
    # PRECIP_STREAK secondi di caduta), i fiocchi quadratini rivolti alla
    # camera: tutto in 3D, quindi coperto da muri e tetti.
    # ══════════════════════════════════════════════════════════════
    PRECIP_KINDS   = %w[none rain snow mix].freeze
    PRECIP_ABOVE   = 10.0 * M_TO_IN   # quota sopra l'occhio da cui cadono
    PRECIP_BELOW   = 6.0 * M_TO_IN    # sotto l'occhio spariscono anche senza toccare nulla
    PRECIP_CELL    = 1.0 * M_TO_IN    # lato delle celle della mappa dei tetti
    PRECIP_RAY_SEC = 0.003            # tempo massimo di raggi per fotogramma
    PRECIP_STREAK  = 0.035            # secondi di caduta che una goccia mostra come scia
    PRECIP_SPLASH  = 0.18             # durata di uno spruzzo (s)
    PRECIP_SPLASHES = 200             # spruzzi al massimo nello stesso istante

    def self.precip_kind
      k = cf('precip_kind').to_s
      PRECIP_KINDS.include?(k) ? k : 'none'
    end

    def self.precip_on?; precip_kind != 'none'; end
    def self.precip_level; (cf('precip_intensity').to_f / 100.0).clamp(0.0, 1.0); end
    def self.precip_count; (cf('precip_max').to_i.clamp(0, 20_000) * precip_level).round; end
    def self.precip_radius; cf('precip_radius').to_f.clamp(5.0, 60.0) * M_TO_IN; end

    # Quanto le precipitazioni coprono il cielo (0–1): lo usa il cielo animato.
    def self.precip_cover; precip_on? ? precip_level : 0.0; end

    # Quota della prima superficie vista dall'alto in (x, y); suolo se la
    # cella non è ancora misurata o se il riparo sotto i tetti è spento.
    def self.precip_top(x, y)
      return 0.0 unless @precip_tops
      @precip_tops[(x / PRECIP_CELL).floor * 1_000_003 + (y / PRECIP_CELL).floor] || 0.0
    end

    # ── Fisica delle particelle ───────────────────────────────────
    # Particella = [x, y, z, neve?, fase, 0–1 a caso, velocità di caduta]
    # (pollici, pollici/s). In SketchUp il Ruby è lento: il ciclo è scritto
    # per fare poco per particella (vedi precip_step).
    def self.precip_spawn(p, ex, ey, ez, anywhere)
      rnd = @precip_rnd; r = precip_radius
      p[0] = ex + (rnd.rand * 2 - 1) * r
      p[1] = ey + (rnd.rand * 2 - 1) * r
      top = ez + PRECIP_ABOVE
      p[2] = anywhere ? ez - PRECIP_BELOW + rnd.rand * (PRECIP_ABOVE + PRECIP_BELOW) : top - rnd.rand * PRECIP_CELL
      p[2] = top if p[2] < precip_top(p[0], p[1])      # nato sotto un tetto: in cima
      p
    end

    def self.precip_seed(ex, ey, ez)
      @precip_rnd ||= Random.new
      kind = precip_kind
      @precip = Array.new(precip_count) do |i|
        snow = kind == 'snow' || (kind == 'mix' && i.odd?)
        f = @precip_rnd.rand
        vz = snow ? -(0.7 + 0.5 * f) * M_TO_IN : -(8.0 + 2.0 * f) * M_TO_IN
        precip_spawn([0.0, 0.0, 0.0, snow, @precip_rnd.rand * 2 * Math::PI, f, vz], ex, ey, ez, true)
      end
      @precip_splash = []
      @precip_set = [kind, @precip.size, cf('precip_radius')]
    end

    # Vento: [vx, vy] in pollici/s verso cui soffia. precip_wind_dir è da
    # dove viene (0 = da nord, 90 = da est), riferito al nord del modello.
    def self.precip_wind_v(north_deg)
      sp = cf('precip_wind').to_f.clamp(0.0, 40.0) * M_TO_IN
      b = (cf('precip_wind_dir').to_f + 180.0 + north_deg) * DEG
      [Math.sin(b) * sp, Math.cos(b) * sp]
    end


    # Avanza di dt secondi con la camera in (ex, ey, ez); t = orologio, per
    # l'ondeggiare dei fiocchi.
    def self.precip_step(dt, ex, ey, ez, t)
      r = precip_radius; span = 2.0 * r
      wx, wy = @precip_wind
      rx = wx * dt; ry = wy * dt
      low = ez - PRECIP_BELOW; high = ez + PRECIP_ABOVE
      sway = 0.35 * M_TO_IN * dt
      splash = @precip_splash
      splash.reject! { |s| s[3] < t }
      # la mappa si guarda solo sotto il tetto più alto misurato: sopra non
      # c'è nulla da toccare (è la gran parte delle particelle)
      tops = @precip_tops; roof = @precip_roof_max || 0.0; cell = PRECIP_CELL
      @precip.each do |p|
        vz = p[6]
        if p[3]
          x = p[0] + rx * 0.8 + Math.sin(t * 1.7 + p[4]) * sway
          y = p[1] + ry * 0.8 + Math.cos(t * 1.3 + p[4] * 1.7) * sway
        else
          x = p[0] + rx
          y = p[1] + ry
        end
        z = p[2] + vz * dt
        dx = x - ex; x = ex + (dx + r) % span - r if dx > r || dx < -r
        dy = y - ey; y = ey + (dy + r) % span - r if dy > r || dy < -r
        p[0] = x; p[1] = y; p[2] = z
        top = tops && z < roof ? (tops[(x / cell).floor * 1_000_003 + (y / cell).floor] || 0.0) : 0.0
        if z < top || z < low
          # spruzzo solo se la goccia ha appena toccato una superficie visibile
          if !p[3] && top >= low && p[2] >= top + vz * dt * 1.5 && splash.size < PRECIP_SPLASHES
            splash << [p[0], p[1], top, t + PRECIP_SPLASH]
          end
          precip_spawn(p, ex, ey, ez, false)
        elsif p[2] > high
          p[2] -= PRECIP_ABOVE + PRECIP_BELOW         # la camera è scesa
        end
      end
    end

    # ── Mappa dei tetti ───────────────────────────────────────────
    # Celle attorno alla camera, dalla più vicina: si misurano quelle che
    # mancano finché resta tempo in questo fotogramma.
    def self.precip_measure(model, eye)
      return unless @precip_tops
      n = (precip_radius / PRECIP_CELL).ceil + 1
      if @precip_ring_n != n
        @precip_ring = (-n..n).to_a.product((-n..n).to_a).sort_by { |i, j| i * i + j * j }
        @precip_ring_n = n
      end
      bb = model.bounds
      return if bb.empty?
      z0 = bb.max.z.to_f + M_TO_IN
      if @precip_tops.size > 250_000
        @precip_tops.clear
        @precip_roof_max = 0.0
      end
      ci = (eye.x / PRECIP_CELL).floor; cj = (eye.y / PRECIP_CELL).floor
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @precip_ring.each do |di, dj|
        k = (ci + di) * 1_000_003 + (cj + dj)
        next if @precip_tops.key?(k)
        hit = ray((ci + di + 0.5) * PRECIP_CELL, (cj + dj + 0.5) * PRECIP_CELL, z0, 0.0, 0.0, -1.0)
        h = hit ? hit[0].z.to_f : 0.0
        @precip_tops[k] = h
        @precip_roof_max = h if h > (@precip_roof_max || 0.0)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 > PRECIP_RAY_SEC
      end
    end

    # L'utente ha cambiato il modello: tetti da rimisurare.
    def self.precip_model_changed
      return if @in_phys_op || !@precip_tops
      @precip_tops.clear
      @precip_roof_max = 0.0
    end

    # ── Accensione e fotogrammi ───────────────────────────────────
    def self.precip_sync
      model = Sketchup.active_model
      return precip_stop unless precip_on? && model
      precip_attach(model)
      @precip_tops = cf('precip_roofs') ? (@precip_tops || {}) : nil
      @precip_wind = precip_wind_v(model.shadow_info['NorthAngle'].to_f)
      eye = model.active_view.camera.eye
      precip_seed(eye.x.to_f, eye.y.to_f, eye.z.to_f) if @precip_set != [precip_kind, precip_count, cf('precip_radius')]
      precip_apply_fog(model) unless @precip_paused
      model.active_view.invalidate
      rate = cf('precip_fps').to_i.clamp(10, 60)
      return if rate == @precip_rate
      UI.stop_timer(@precip_timer) if @precip_timer
      @precip_timer = UI.start_timer(1.0 / rate, true) { precip_frame }
      @precip_rate = rate
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.precip_stop
      UI.stop_timer(@precip_timer) if @precip_timer
      @precip_timer = @precip_rate = nil
      if (m = @precip_model)
        begin
          m.overlays.remove(@precip_ov) if @precip_ov
          precip_restore_fog(m)
          m.remove_observer(@precip_mobs) if @precip_mobs
          m.active_view.invalidate
        rescue StandardError
          nil                       # modello già chiuso
        end
      end
      @precip_model = @precip_ov = @precip = @precip_set = @precip_tops = @precip_tick = @precip_fog_orig = @precip_roof_max = nil
      @storm = @storm_next = nil
      @storm_glow = 0.0
      @precip_paused = false
    end

    def self.precip_attach(model)
      return if @precip_model.equal?(model)
      precip_stop if @precip_model
      @precip_model = model
      @precip_tops = {}
      @precip_roof_max = 0.0
      @precip_mobs ||= PrecipModelObserver.new
      model.add_observer(@precip_mobs)
      if SKY_OVERLAY
        @precip_ov = PrecipOverlay.new
        model.overlays.add(@precip_ov)
        @precip_ov.enabled = true
      end
      return if @sky_app_obs                     # lo stesso osservatore del cielo
      @sky_app_obs = SkyAppObserver.new
      Sketchup.add_observer(@sky_app_obs)
    end

    def self.precip_frame
      model = @precip_model
      return unless model && !@precip_paused
      return precip_sync unless Sketchup.active_model.equal?(model)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      dt = @precip_tick ? (now - @precip_tick).clamp(0.0, 0.1) : 0.0
      @precip_tick = now
      eye = model.active_view.camera.eye
      precip_measure(model, eye)
      precip_step(dt, eye.x.to_f, eye.y.to_f, eye.z.to_f, now)
      storm_step(now)
      model.active_view.invalidate
    rescue => fps_err
      log_error(__method__, fps_err)
      precip_stop
    end

    # ── Nebbia ────────────────────────────────────────────────────
    # [inizio, fine] in metri per intensità 0 e 1: pioggia, poi neve.
    PRECIP_FOG = { rain: [[80.0, 1500.0], [6.0, 140.0]], snow: [[40.0, 800.0], [2.0, 45.0]] }.freeze

    def self.precip_fog_range
      i = precip_level
      snow = { 'rain' => 0.0, 'snow' => 1.0, 'mix' => 0.5 }[precip_kind] || 0.0
      at = ->(k) { a, b = PRECIP_FOG[k]; [a[0] + (b[0] - a[0]) * i, a[1] + (b[1] - a[1]) * i] }
      r = at.(:rain); s = at.(:snow)
      [r[0] + (s[0] - r[0]) * snow, r[1] + (s[1] - r[1]) * snow]
    end

    def self.precip_apply_fog(model)
      ro = model.rendering_options
      if cf('precip_fog')
        @precip_fog_orig ||= { on: ro['DisplayFog'], start: ro['FogStartDist'], stop: ro['FogEndDist'], bk: ro['FogUseBkColor'] }
        near, far = precip_fog_range
        ro['DisplayFog'] = true
        ro['FogUseBkColor'] = true          # colore dello sfondo: di notte il cielo lo scurisce
        ro['FogStartDist'] = near * M_TO_IN
        ro['FogEndDist'] = far * M_TO_IN
      else
        precip_restore_fog(model)
      end
    end

    def self.precip_restore_fog(model)
      o = @precip_fog_orig
      return unless o
      ro = model.rendering_options
      ro['DisplayFog'] = o[:on]; ro['FogStartDist'] = o[:start]; ro['FogEndDist'] = o[:stop]; ro['FogUseBkColor'] = o[:bk]
      @precip_fog_orig = nil
    end

    def self.precip_saving(model, before)
      return unless model.equal?(@precip_model)
      if before
        precip_restore_fog(model)
        @precip_paused = true
      else
        @precip_paused = false
        precip_apply_fog(model)
      end
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # ── Temporale ─────────────────────────────────────────────────
    # Lampi a caso (storm_rate al minuto in media): due o tre guizzi in
    # STORM_FLASH secondi, un fulmine frastagliato dalla base delle nuvole
    # all'orizzonte, la vista che si schiarisce (un velo 2D su tutto) e, col
    # cielo animato, anche la luce del modello.
    STORM_FLASH = 0.45

    def self.storm_on?; precip_on? && cf('storm') ? true : false; end

    # Attesa fino al prossimo lampo: casuale, in media 60 / storm_rate s
    def self.storm_wait
      mean = 60.0 / cf('storm_rate').to_f.clamp(1.0, 30.0)
      [-Math.log(1.0 - @precip_rnd.rand) * mean, 1.5].max
    end

    # Intensità del lampo all'istante t (0–1)
    def self.storm_glow(t)
      s = @storm
      return 0.0 unless s && t >= s[:t0] && t <= s[:t0] + STORM_FLASH
      x = t - s[:t0]
      s[:pulses].map { |at, w| (1.0 - (x - at).abs / w).clamp(0.0, 1.0) * (at.zero? ? 1.0 : 0.85) }.max
    end

    # Fulmine: versori dalla base delle nuvole al suolo, a distanza dist (m)
    # e azimut az (dal nord del modello), con zig-zag di qualche decina di metri.
    def self.storm_bolt(az, dist, north_deg)
      rnd = @precip_rnd
      top = Math.atan2(cf('cloud_height').to_f.clamp(300.0, 5000.0), dist)
      n = 14; side = 0.0
      (0..n).map do |i|
        el = top * (1.0 - i.to_f / n)
        side += (rnd.rand * 2 - 1) * 45.0 / dist
        a = az + side + north_deg * DEG
        [Math.sin(a) * Math.cos(el), Math.cos(a) * Math.cos(el), Math.sin(el)]
      end
    end

    def self.storm_step(t)
      return @storm = nil unless storm_on?
      @storm_next ||= t + storm_wait
      if t >= @storm_next
        rnd = @precip_rnd
        dist = 400.0 + rnd.rand * 4000.0
        pulses = [[0.0, 0.07], [0.11 + rnd.rand * 0.08, 0.08]]
        pulses << [0.3 + rnd.rand * 0.08, 0.09] if rnd.rand < 0.5
        @storm = { t0: t, pulses: pulses, dist: dist,
                   bolt: storm_bolt(rnd.rand * 2 * Math::PI, dist, @precip_model.shadow_info['NorthAngle'].to_f) }
        @storm_next = t + storm_wait
      end
      g = storm_glow(t)
      if g > 0.0 || @storm_glow.to_f > 0.0
        @storm_glow = g
        sky_frame(true) if @sky_model              # la scena si illumina col lampo
      end
    end

    def self.storm_draw(view)
      g = @storm_glow.to_f
      s = @storm
      return unless g > 0.0 && s
      w = view.vpwidth; h = view.vpheight          # prima il velo: la vista si schiarisce tutta
      view.drawing_color = Sketchup::Color.new(225, 232, 255, (80 * g).round)
      view.draw2d(GL_QUADS, [[0, 0, 0], [w, 0, 0], [w, h, 0], [0, h, 0]])
      geo = sky_geo(view.camera)
      # davanti alle nuvole (che stanno fra 0,965 e 0,985 della distanza): il
      # fulmine scende dalla loro base, non deve finirci dietro
      dists = s[:bolt].map { |w| sky_dist(geo, w) }
      pts = s[:bolt].zip(dists).map { |w, d| sky_at(geo, w, d * 0.94) }
      core = s[:bolt].zip(dists).map { |w, d| sky_at(geo, w, d * 0.93) }   # un filo davanti all'alone
      view.line_width = 8
      view.drawing_color = Sketchup::Color.new(150, 170, 255, (120 * g).round)   # alone azzurro
      view.draw(GL_LINE_STRIP, pts)
      view.line_width = 3
      view.drawing_color = Sketchup::Color.new(248, 250, 255, (255 * g).round)
      view.draw(GL_LINE_STRIP, core)
      view.line_width = 1
    end

    # ── Disegno ───────────────────────────────────────────────────
    # Piano di taglio vicino: SketchUp lo allontana quando la geometria più
    # vicina nell'inquadratura è lontana (sopra il mare di Stromboli, a 21 m
    # di quota, stava oltre 20 m) e taglierebbe via tutte le particelle.
    # L'Overlay dichiara come suo ingombro la scatola delle particelle, ma
    # solo la parte dentro l'ingombro del modello allargato di un quarto
    # della sua diagonale (almeno il raggio): con la camera appena fuori
    # (sul mare, a 36 m dalla costa) la pioggia si vede, con la camera
    # lontana Zoom estensioni resta quello di sempre.
    def self.precip_extents
      bb = Geom::BoundingBox.new
      return bb unless @precip && precip_on?
      model = Sketchup.active_model
      mb = model.bounds
      return bb if mb.empty?
      e = model.active_view.camera.eye
      r = precip_radius
      margin = [r, mb.diagonal.to_f * 0.25].max
      lo = [e.x - r, e.y - r, e.z - PRECIP_BELOW].map(&:to_f)
      hi = [e.x + r, e.y + r, e.z + PRECIP_ABOVE].map(&:to_f)
      a = lo.zip(mb.min.to_a).map { |v, m| [v, m.to_f - margin].max }
      b = hi.zip(mb.max.to_a).map { |v, m| [v, m.to_f + margin].min }
      return bb if a.zip(b).any? { |x, y| x > y }
      bb.add(Geom::Point3d.new(*a))
      bb.add(Geom::Point3d.new(*b))
      bb
    end

    def self.precip_draw(view)
      list = @precip
      return unless list && @precip_model && precip_on?
      storm_draw(view)
      # di notte (col cielo animato) gocce e fiocchi sono più scuri
      night = @sky ? sky_night(@sky[:sun_alt]) : 0.0
      wx, wy = @precip_wind
      rain = []; snow = []
      cam = view.camera
      xa = cam.xaxis.to_a; ya = cam.yaxis.to_a
      # punti come array [x, y, z]: in SketchUp costano un terzo dei Point3d
      s = PRECIP_STREAK; sx = wx * s; sy = wy * s
      ax = xa[0] + ya[0]; ay = xa[1] + ya[1]; az = xa[2] + ya[2]   # diagonali del quadratino
      bx = xa[0] - ya[0]; by = xa[1] - ya[1]; bz = xa[2] - ya[2]
      list.each do |p|
        x = p[0]; y = p[1]; z = p[2]
        if p[3]
          h = (0.015 + 0.010 * p[5]) * M_TO_IN
          snow << [x - ax * h, y - ay * h, z - az * h] << [x + bx * h, y + by * h, z + bz * h] <<
            [x + ax * h, y + ay * h, z + az * h] << [x - bx * h, y - by * h, z - bz * h]
        else
          rain << [x, y, z] << [x - sx, y - sy, z - p[6] * s]
        end
      end
      view.line_width = 1
      unless rain.empty?
        g = (200 - 90 * night).round
        view.drawing_color = Sketchup::Color.new(g - 10, g, g + 15, 125)
        view.draw(GL_LINES, rain)
      end
      unless snow.empty?
        g = (252 - 80 * night).round
        view.drawing_color = Sketchup::Color.new(g, g, [g + 3, 255].min, 235)
        view.draw(GL_QUADS, snow)
      end
      return if @precip_splash.nil? || @precip_splash.empty?
      d = 0.03 * M_TO_IN
      crowns = @precip_splash.flat_map do |x, y, z, _|
        o = [x, y, z + 0.2]
        [o, [x + d, y, z + d], o, [x - d, y, z + d]]     # una V di schizzi
      end
      g = (210 - 120 * night).round
      view.drawing_color = Sketchup::Color.new(g, g, g + 10, 150)
      view.draw(GL_LINES, crowns)
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # ── Osservatore e Overlay ─────────────────────────────────────
    class PrecipModelObserver < Sketchup::ModelObserver
      def onPreSaveModel(model);    DagaWASD::FPSWalk.precip_saving(model, true);  end
      def onPostSaveModel(model);   DagaWASD::FPSWalk.precip_saving(model, false); end
      def onTransactionCommit(_m);  DagaWASD::FPSWalk.precip_model_changed; end
      def onTransactionUndo(_m);    DagaWASD::FPSWalk.precip_model_changed; end
      def onTransactionRedo(_m);    DagaWASD::FPSWalk.precip_model_changed; end
    end

    # Senza Overlay le particelle le disegna lo strumento FPS (lib/tool.rb)
    unless SKY_OVERLAY
      class FPSTool
        def getExtents; DagaWASD::FPSWalk.precip_extents; end
      end
    end

    if SKY_OVERLAY
      class PrecipOverlay < Sketchup::Overlay
        def initialize
          super('dagawasd.precip', "DagaWASD — #{DagaWASD::FPSWalk.t('sub.precip')}")
        end
        def getExtents; DagaWASD::FPSWalk.precip_extents; end
        def draw(view); DagaWASD::FPSWalk.precip_draw(view); end
      end
    end

  end
end
