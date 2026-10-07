# DagaWASD — Cielo: sole, luna e stelle secondo data, ora e luogo del modello.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Cielo (Meteo › Data e ora del giorno)
    # L'orologio del cielo è dell'estensione: parte da data e ora del
    # pannello (o dall'ora attuale) e, se il tempo scorre, avanza a ogni
    # fotogramma. Ogni fotogramma:
    #   - scrive l'ora nelle ombre del modello (ShadowTime), così sole,
    #     luce e ombre di SketchUp lo seguono;
    #   - colora cielo e sfondo e abbassa la luce secondo l'altezza del sole;
    #   - un'Overlay disegna sole, luna con la sua fase e stelle in 3D, appena
    #     oltre l'ingombro del modello nella loro direzione: gli oggetti del
    #     modello li coprono (vedi sky_dist).
    # Il luogo (latitudine, longitudine, fuso, nord) è quello del modello:
    # Finestra › Info modello › Georeferenziazione.
    #
    # Le modifiche a ombre e stile non entrano nella cronologia di Ctrl+Z.
    # I valori originali del modello si rimettono spegnendo il cielo e
    # prima di ogni salvataggio (poi il cielo riprende): il file salvato
    # resta com'era.
    #
    # ShadowTime: SketchUp tiene l'ora locale del modello nei campi UTC
    # (le 13:30 a Roma sono un Time con getutc 13:30). Qui utc è sempre
    # l'istante vero, local = utc + fuso.
    #
    # Senza Sketchup::Overlay (prima del 2023) il cielo si vede solo
    # durante la camminata, disegnato dallo strumento FPS.
    # ══════════════════════════════════════════════════════════════
    SKY_OVERLAY   = defined?(Sketchup::Overlay) ? true : false # rubocop:disable SketchupSuggestions/Compatibility
    SKY_SUN_RAD   = 0.267 * DEG     # raggio apparente vero di sole e luna
    SKY_MOON_RAD  = 0.259 * DEG
    SKY_STAR_SEED = 20_261_002

    # ── Astronomia ────────────────────────────────────────────────
    # Formule a bassa precisione (Astronomical Almanac): ~0,01° il sole,
    # ~0,3° la luna (con la parallasse), più che abbastanza a occhio.
    # Angoli in radianti; d = giorni dal mezzogiorno UTC del 1/1/2000.
    def self.sky_days(utc); utc / 86_400.0 + 2_440_587.5 - 2_451_545.0; end
    def self.sky_eps(d);    (23.439 - 0.000_000_36 * d) * DEG; end

    # Eclittiche → equatoriali [ascensione retta, declinazione]
    def self.sky_ecl_to_eq(lam, bet, d)
      e = sky_eps(d)
      x = Math.cos(bet) * Math.cos(lam)
      y = Math.cos(e) * Math.cos(bet) * Math.sin(lam) - Math.sin(e) * Math.sin(bet)
      z = Math.sin(e) * Math.cos(bet) * Math.sin(lam) + Math.cos(e) * Math.sin(bet)
      [Math.atan2(y, x), Math.asin(z.clamp(-1.0, 1.0))]
    end

    # Sole: [ascensione retta, declinazione, longitudine eclittica]
    def self.sky_sun_eq(d)
      g   = (357.529 + 0.985_600_28 * d) * DEG
      lam = (280.459 + 0.985_647_36 * d + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * DEG
      sky_ecl_to_eq(lam, 0.0, d) + [lam]
    end

    # Luna: [ascensione retta, declinazione, longitudine e latitudine eclittiche]
    def self.sky_moon_eq(d)
      mp = (134.963 + 13.064_993 * d) * DEG   # anomalia media della luna
      f  = (93.272 + 13.229_350 * d) * DEG    # argomento della latitudine
      dd = (297.850 + 12.190_749 * d) * DEG   # elongazione media
      m  = (357.529 + 0.985_600_28 * d) * DEG # anomalia media del sole
      lam = 218.316 + 13.176_396 * d + 6.289 * Math.sin(mp) + 1.274 * Math.sin(2 * dd - mp) +
            0.658 * Math.sin(2 * dd) + 0.214 * Math.sin(2 * mp) - 0.186 * Math.sin(m) - 0.114 * Math.sin(2 * f)
      bet = 5.128 * Math.sin(f) + 0.281 * Math.sin(mp + f) + 0.278 * Math.sin(mp - f) + 0.173 * Math.sin(2 * dd - f)
      lam *= DEG; bet *= DEG
      sky_ecl_to_eq(lam, bet, d) + [lam, bet]
    end

    # Fase: [frazione illuminata 0–1, crescente?, indice 0–7 del nome
    # (0 nuova, 2 primo quarto, 4 piena, 6 ultimo quarto)]
    def self.sky_phase(sun_lam, moon_lam, moon_bet)
      el  = (moon_lam - sun_lam) % (2 * Math::PI)
      cos_psi = Math.cos(moon_bet) * Math.cos(el)
      [(1.0 - cos_psi) / 2.0, el < Math::PI, ((el / (2 * Math::PI)) * 8 + 0.5).floor % 8]
    end

    # Tempo siderale locale (radianti); lon in gradi, est positiva.
    def self.sky_lst(d, lon); ((280.460_618_37 + 360.985_647_366_29 * d + lon) % 360.0) * DEG; end

    # Matrice equatoriali (x verso ascensione retta 0, z polo nord celeste)
    # → modello (X, Y, Z di SketchUp). north = angolo del nord del modello
    # dall'asse Y verde, in senso orario visto dall'alto (NorthAngle).
    def self.sky_matrix(lat, lst, north)
      sl = Math.sin(lst); cl = Math.cos(lst); sp = Math.sin(lat); cp = Math.cos(lat)
      e = [-sl, cl, 0.0]                      # est
      n = [-sp * cl, -sp * sl, cp]            # nord
      u = [cp * cl, cp * sl, sp]              # zenit
      sa = Math.sin(north); ca = Math.cos(north)
      # assi del modello per est e nord ruotati di north
      ex = ca; ey = -sa; nx = sa; ny = ca
      [[e[0] * ex + n[0] * nx, e[1] * ex + n[1] * nx, e[2] * ex + n[2] * nx],
       [e[0] * ey + n[0] * ny, e[1] * ey + n[1] * ny, e[2] * ey + n[2] * ny],
       u]
    end

    def self.sky_eq_vec(ra, dec)
      cd = Math.cos(dec)
      [cd * Math.cos(ra), cd * Math.sin(ra), Math.sin(dec)]
    end

    def self.sky_apply_m(m, v)
      [m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
       m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
       m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2]]
    end

    # Parallasse della luna (~1°): vista da terra sta un po' più in basso.
    def self.sky_parallax(v)
      alt = Math.asin(v[2].clamp(-1.0, 1.0))
      alt2 = alt - 0.9507 * DEG * Math.cos(alt)
      h = Math.hypot(v[0], v[1])
      return v if h < 1e-9
      k = Math.cos(alt2) / h
      [v[0] * k, v[1] * k, Math.sin(alt2)]
    end

    # Stato del cielo in un istante e in un luogo: direzioni nel modello
    # (versori), altezze in gradi, fase della luna.
    def self.sky_state(utc, lat, lon, north)
      d = sky_days(utc)
      m = sky_matrix(lat * DEG, sky_lst(d, lon), north * DEG)
      s_ra, s_dec, s_lam = sky_sun_eq(d)
      m_ra, m_dec, m_lam, m_bet = sky_moon_eq(d)
      sun  = sky_apply_m(m, sky_eq_vec(s_ra, s_dec))
      moon = sky_parallax(sky_apply_m(m, sky_eq_vec(m_ra, m_dec)))
      k, waxing, idx = sky_phase(s_lam, m_lam, m_bet)
      { utc: utc, matrix: m, sun: sun, moon: moon,
        sun_alt: Math.asin(sun[2].clamp(-1.0, 1.0)) / DEG, moon_alt: Math.asin(moon[2].clamp(-1.0, 1.0)) / DEG,
        moon_lit: k, waxing: waxing, phase: idx }
    end

    # ── Stelle ────────────────────────────────────────────────────
    # Le più luminose al loro posto (ascensione retta in ore, declinazione
    # in gradi, magnitudine): Orsa Maggiore, Orione, Cassiopea, Croce del
    # Sud e le altre che si riconoscono. Il resto è un fondo casuale fisso.
    SKY_BRIGHT = [
      [2.530, 89.26, 2.0],  [6.752, -16.72, -1.5], [6.399, -52.70, -0.7], [14.261, 19.18, -0.1],
      [18.616, 38.78, 0.0], [5.278, 46.00, 0.1],   [5.242, -8.20, 0.1],   [7.655, 5.22, 0.4],
      [5.919, 7.41, 0.5],   [1.629, -57.24, 0.5],  [19.846, 8.87, 0.8],   [4.599, 16.51, 0.9],
      [13.420, -11.16, 1.0],[16.490, -26.43, 1.0], [7.755, 28.03, 1.1],   [22.961, -29.62, 1.2],
      [20.690, 45.28, 1.3], [10.140, 11.97, 1.4],  [7.577, 31.89, 1.6],   [5.419, 6.35, 1.6],
      [14.660, -60.83, -0.3],[12.443, -63.10, 0.8],[12.795, -59.69, 1.3], [12.519, -57.11, 1.6],
      [12.252, -58.75, 2.8],
      [11.062, 61.75, 1.8], [11.031, 56.38, 2.4],  [11.897, 53.69, 2.4],  [12.257, 57.03, 3.3],
      [12.900, 55.96, 1.8], [13.399, 54.93, 2.2],  [13.792, 49.31, 1.9],
      [5.679, -1.94, 1.8],  [5.604, -1.20, 1.7],   [5.533, -0.30, 2.2],   [5.796, -9.67, 2.1],
      [0.675, 56.54, 2.2],  [0.153, 59.15, 2.3],   [0.945, 60.72, 2.2],   [1.430, 60.24, 2.7],
      [1.907, 63.67, 3.4],  [3.405, 49.86, 1.8],   [2.120, 23.46, 2.0],   [0.140, 29.09, 2.1],
      [17.582, 12.56, 2.1], [9.460, -8.66, 2.0],   [3.791, 24.11, 2.9],   [21.736, 9.88, 2.4]
    ].freeze

    # Versori equatoriali e magnitudini: brillanti + n casuali (fino a mag 6,
    # più fitte verso le deboli come in cielo).
    def self.sky_stars(n)
      @sky_stars = nil if @sky_stars && @sky_stars[:n] != n
      @sky_stars ||= begin
        rnd = Random.new(SKY_STAR_SEED)
        list = SKY_BRIGHT.map { |ra, dec, mag| [sky_eq_vec(ra * 15 * DEG, dec * DEG), mag] }
        n.times do
          z = rnd.rand * 2 - 1
          a = rnd.rand * 2 * Math::PI
          r = Math.sqrt(1 - z * z)
          list << [[r * Math.cos(a), r * Math.sin(a), z], 6.0 - 3.6 * rnd.rand**2.2]
        end
        { n: n, list: list }
      end
      @sky_stars[:list]
    end

    # Gruppi per luminosità: [magnitudine massima, pixel, opacità 0–1]
    SKY_STAR_BINS = [[0.5, 4, 1.0], [1.5, 3, 1.0], [2.5, 3, 0.75], [3.5, 2, 0.75], [4.7, 2, 0.45], [9.9, 1, 0.55]].freeze

    # ── Colori e luce secondo l'altezza del sole ──────────────────
    # [altezza°, cielo, orizzonte, sfondo, luce ×, ombra ×, peso]; giorno =
    # colori del modello. Peso = quanto il cielo di quell'ora copre quello
    # del modello (al tramonto ne resta una traccia, a notte fonda niente).
    # L'orizzonte di giorno è quello che SketchUp fa da sé quando
    # HorizonColor è trasparente: il cielo schiarito al 75 % verso il bianco
    # (misurato nella vista); qui va dato esplicito, se no di notte resta
    # una fascia chiara.
    # Al tramonto il cielo in alto resta blu e si scurisce, l'arancio sta
    # all'orizzonte: SketchUp sfuma dal primo al secondo (mescolarli dà grigio).
    SKY_KEYS = [
      [15.0, :day, :day, :day, 1.0, 1.0, 0.0],
      [4.0, [70, 120, 185], [255, 190, 130], [160, 140, 128], 0.85, 0.9, 0.75],
      [-1.0, [62, 74, 135], [246, 146, 96], [104, 88, 86], 0.35, 0.6, 0.85],
      [-6.0, [32, 36, 82], [104, 70, 98], [40, 40, 56], 0.0, 0.32, 0.95],
      [-14.0, [7, 11, 28], [16, 20, 38], [9, 10, 16], 0.0, 0.1, 1.0]
    ].freeze
    SKY_HAZE = 0.75

    def self.sky_mix(a, b, t)
      a.zip(b).map { |x, y| (x + (y - x) * t).round }
    end

    # [cielo, sfondo, light, dark, orizzonte] per un'altezza del sole;
    # orig = valori del modello
    def self.sky_look(alt, orig, moon_glow = 0.0)
      day_sky = orig[:sky]; day_bg = orig[:bg]
      day_haze = sky_mix(day_sky, [255, 255, 255], SKY_HAZE)
      keys = SKY_KEYS.map do |a, s, h, b, li, da, w|
        [a, s == :day ? day_sky : sky_mix(day_sky, s, w), b == :day ? day_bg : b, orig[:light] * li, orig[:dark] * da,
         h == :day ? day_haze : sky_mix(day_haze, h, w)]
      end
      lo = keys.find { |k| alt >= k[0] } || keys.last
      hi = keys.reverse.find { |k| alt <= k[0] } || keys.first
      t = lo.equal?(hi) ? 0.0 : (alt - lo[0]) / (hi[0] - lo[0])
      sky  = sky_mix(lo[1], hi[1], t)
      bg   = sky_mix(lo[2], hi[2], t)
      li   = lo[3] + (hi[3] - lo[3]) * t
      da   = lo[4] + (hi[4] - lo[4]) * t
      [sky, bg, li.round.clamp(0, 100), (da + moon_glow).round.clamp(0, 100), sky_mix(lo[5], hi[5], t)]
    end

    # Cielo coperto da pioggia o neve (c = 0–1): colori verso il grigio, sole
    # velato (luce diretta e ombre deboli), un po' più luce diffusa.
    def self.sky_overcast(look, c)
      return look if c <= 0
      grey = lambda do |rgb, k|
        g = ((0.3 * rgb[0] + 0.59 * rgb[1] + 0.11 * rgb[2]) * k).round
        sky_mix(rgb, [g, g, g + 4], 0.95 * c)
      end
      sky, bg, li, da, haze = look
      [grey.(sky, 0.85), grey.(bg, 0.9), (li * (1 - 0.8 * c)).round, (da + li * 0.25 * c).round.clamp(0, 100), grey.(haze, 0.9)]
    end

    # Quanto si vedono le stelle (0 di giorno, 1 a notte fonda)
    def self.sky_night(alt); ((-alt - 2.0) / 10.0).clamp(0.0, 1.0); end

    # ── Orologio ──────────────────────────────────────────────────
    # Luogo del modello: [lat, lon, fuso orario (ore, ora legale compresa), nord]
    def self.sky_place(model)
      si = model.shadow_info
      tz = si['TZOffset'].to_f + (si['DaylightSavings'] ? 1.0 : 0.0)
      [si['Latitude'].to_f, si['Longitude'].to_f, tz, si['NorthAngle'].to_f]
    end

    # Luogo personalizzato (Meteo › Luogo): va scritto anche nelle ombre del
    # modello, se no SketchUp illuminerebbe la scena col sole di un altro
    # posto. Si scrive solo quando cambia; spento, tornano i valori del
    # modello. @sky_place_set = luogo scritto (nil = quello del modello).
    def self.sky_sync_place(model)
      want = cf('sky_place_custom') ? %w[sky_lat sky_lon sky_tz].map { |k| cf(k).to_f } : nil
      return if want == @sky_place_set
      si = model.shadow_info
      if want
        si['Latitude'] = want[0].clamp(-90.0, 90.0)
        si['Longitude'] = want[1].clamp(-180.0, 180.0)
        si['TZOffset'] = want[2].clamp(-12.0, 14.0)
        si['DaylightSavings'] = false
      else
        sky_restore_place(model)
      end
      @sky_place_set = want
    end

    def self.sky_restore_place(model)
      o = @sky_orig
      return unless o && o[:lat]
      si = model.shadow_info
      si['Latitude'] = o[:lat]; si['Longitude'] = o[:lon]
      si['TZOffset'] = o[:tz]; si['DaylightSavings'] = o[:dst]
      @sky_place_set = nil
    end

    # Istante (utc, secondi) di data e ora del pannello nel fuso del modello.
    # L'anno è quello in corso: la luna ha la fase vera di quel giorno.
    def self.sky_utc_from_cfg(tz)
      y  = Time.now.year
      mo = cf('sky_month').to_i.clamp(1, 12)
      dim = (Time.utc(mo == 12 ? y + 1 : y, mo % 12 + 1, 1) - 86_400).day   # giorni del mese
      dd = cf('sky_day').to_i.clamp(1, dim)
      h  = cf('sky_hour').to_f.clamp(0.0, 24.0)
      Time.utc(y, mo, dd).to_f + h * 3600.0 - tz * 3600.0
    end

    # ── Accensione e fotogrammi ───────────────────────────────────
    # All'avvio e a ogni modifica delle impostazioni.
    def self.sky_sync
      model = Sketchup.active_model
      return sky_stop unless cf('sky_enabled') && model
      sky_attach(model)
      sig = %w[sky_now sky_hour sky_day sky_month sky_place_custom sky_tz].map { |k| cf(k) }
      if sig != @sky_sig            # data o ora cambiate nel pannello: l'orologio riparte da lì
        @sky_sig = sig
        @sky_utc = nil
      end
      @sky_applied = {} unless @sky_paused
      sky_frame(true)
      rate = cf('sky_now') || cf('sky_flow') ? cf('sky_fps').to_i.clamp(5, 60) : nil
      return if rate == @sky_rate
      UI.stop_timer(@sky_timer) if @sky_timer
      @sky_timer = rate && UI.start_timer(1.0 / rate, true) { sky_frame }
      @sky_rate  = rate
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.sky_stop
      UI.stop_timer(@sky_timer) if @sky_timer
      @sky_timer = nil; @sky_rate = nil
      if (m = @sky_model)
        begin
          m.overlays.remove(@sky_ov) if @sky_ov
          sky_restore(m)
          m.remove_observer(@sky_mobs) if @sky_mobs
          m.active_view.invalidate
        rescue StandardError
          nil                       # modello già chiuso
        end
      end
      @sky_model = @sky_ov = @sky = @sky_orig = @sky_sig = @sky_utc = @sky_tick = @sky_place_set = nil
      @sky_paused = false
      sky_push_status(true)
    end

    # Prende in carico un modello: ne ricorda i valori originali, gli
    # aggiunge l'Overlay e l'osservatore dei salvataggi.
    def self.sky_attach(model)
      return if @sky_model.equal?(model)
      sky_stop if @sky_model
      @sky_model = model
      @sky_orig  = sky_read_orig(model)
      @sky_place_set = nil
      @sky_applied = {}
      @sky_mobs ||= SkyModelObserver.new
      model.add_observer(@sky_mobs)
      if SKY_OVERLAY
        @sky_ov = SkyOverlay.new
        model.overlays.add(@sky_ov)
        @sky_ov.enabled = true
      end
      return if @sky_app_obs
      @sky_app_obs = SkyAppObserver.new
      Sketchup.add_observer(@sky_app_obs)
    end

    def self.sky_read_orig(model)
      si = model.shadow_info; ro = model.rendering_options
      { time: si['ShadowTime'], light: si['Light'].to_i, dark: si['Dark'].to_i,
        sun_shading: si['UseSunForAllShading'], shadows: si['DisplayShadows'],
        sky: ro['SkyColor'].to_a[0, 3], bg: ro['BackgroundColor'].to_a[0, 3],
        haze: ro['HorizonColor'].to_a, draw_sky: ro['DrawHorizon'],
        lat: si['Latitude'], lon: si['Longitude'], tz: si['TZOffset'], dst: si['DaylightSavings'] }
    end

    def self.sky_restore(model)
      o = @sky_orig
      return unless o
      si = model.shadow_info
      si['ShadowTime'] = o[:time]
      si['DisplayShadows'] = o[:shadows]
      sky_restore_look(model)
      sky_restore_place(model)
      @sky_applied = {}
    end

    # Colori, orizzonte e luce del modello com'erano.
    def self.sky_restore_look(model)
      o = @sky_orig
      si = model.shadow_info; ro = model.rendering_options
      ro['SkyColor'] = Sketchup::Color.new(*o[:sky])
      ro['BackgroundColor'] = Sketchup::Color.new(*o[:bg])
      ro['HorizonColor'] = Sketchup::Color.new(*o[:haze])
      ro['DrawHorizon'] = o[:draw_sky]
      si['Light'] = o[:light]; si['Dark'] = o[:dark]
      si['UseSunForAllShading'] = o[:sun_shading]
    end

    # Salvataggio: il file riceve i valori originali, poi il cielo riprende.
    def self.sky_saving(model, before)
      return unless model.equal?(@sky_model)
      if before
        sky_restore(model)
        @sky_paused = true
      else
        @sky_paused = false
        sky_frame(true)
      end
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Un fotogramma: avanza l'orologio, calcola il cielo, lo applica al
    # modello e ridisegna. force = anche col tempo fermo (cambio impostazioni).
    def self.sky_frame(force = false)
      model = @sky_model
      return unless model && !@sky_paused
      return sky_sync unless Sketchup.active_model.equal?(model)   # un altro modello in primo piano
      sky_sync_place(model)
      lat, lon, tz, north = sky_place(model)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      el  = @sky_tick ? (now - @sky_tick).clamp(0.0, 0.5) : 0.0
      @sky_tick = now
      @sky_utc =
        if cf('sky_now') then Time.now.to_f
        elsif @sky_utc.nil? then sky_utc_from_cfg(tz)
        elsif cf('sky_flow') then @sky_utc + el * 86_400.0 / (cf('sky_day_minutes').to_f.clamp(0.5, 120.0) * 60.0)
        else @sky_utc
        end
      return if !force && @sky && @sky[:utc] == @sky_utc && @sky[:place] == [lat, lon, tz, north]
      @sky = sky_state(@sky_utc, lat, lon, north).merge(tz: tz, lat: lat, lon: lon, place: [lat, lon, tz, north])
      @sky[:stars] = sky_star_dirs(@sky[:matrix]) if cf('sky_stars')
      sky_apply_model(model)
      model.active_view.invalidate
      sky_push_status(force)
    rescue => fps_err
      log_error(__method__, fps_err)
      sky_stop
    end

    # Direzioni delle stelle sopra l'orizzonte, raggruppate per luminosità.
    def self.sky_star_dirs(m)
      bins = SKY_STAR_BINS.map { [] }
      sky_stars(cf('sky_star_count').to_i.clamp(0, 5000)).each do |v, mag|
        w = sky_apply_m(m, v)
        next if w[2] <= 0.0                    # sotto l'orizzonte le copre la terra
        bins[SKY_STAR_BINS.index { |b| mag <= b[0] } || -1] << w
      end
      bins
    end

    # Ombre, colori e luce del modello; scrive solo ciò che è cambiato.
    def self.sky_apply_model(model)
      s = @sky; o = @sky_orig; a = (@sky_applied ||= {})
      si = model.shadow_info; ro = model.rendering_options
      local = (s[:utc] + s[:tz] * 3600.0).floor
      # Cambiare l'ora fa ricalcolare a SketchUp tutte le ombre (sul faro,
      # 21 000 facce: un fotogramma da 24 a 63 ms): mentre il tempo scorre
      # si fa al più sky_shadow_fps volte al secondo, non a ogni fotogramma
      # del cielo. Il primo valore e i salti dal pannello (a azzerato) subito.
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if a[:time] != local &&
         (a[:time].nil? || now - a[:time_at].to_f >= 1.0 / cf('sky_shadow_fps').to_f.clamp(0.5, 60.0))
        si['ShadowTime'] = Time.at(local)
        a[:time] = local
        a[:time_at] = now
      end
      sh = cf('sky_shadows') ? true : o[:shadows]
      if a[:shadows] != sh
        si['DisplayShadows'] = sh
        a[:shadows] = sh
      end
      if cf('sky_colors')
        glow = s[:moon_alt] > 0 ? 8.0 * s[:moon_lit] * sky_night(s[:sun_alt]) : 0.0
        look = sky_overcast(sky_look(s[:sun_alt], o, glow), [precip_cover, cloud_overcast].max)
        shade = cloud_sun_shade                 # una nuvola davanti al sole: luce diretta velata
        look[2] = (look[2] * (1.0 - 0.75 * shade)).round if shade > 0
        sn = snow_level                         # neve al suolo: sbianca lo sfondo (dove non c'è terreno)
        look[1] = sky_mix(look[1], sky_mix([230, 234, 242], [40, 44, 58], sky_night(s[:sun_alt])), 0.7 * sn) if sn > 0
        flash = @storm_glow.to_f                # lampo: cielo chiaro, scena illuminata
        if flash > 0
          look[0] = sky_mix(look[0], [200, 205, 230], 0.6 * flash)
          look[4] = sky_mix(look[4], [210, 215, 235], 0.6 * flash)
          look[1] = sky_mix(look[1], [150, 155, 175], 0.5 * flash)
          look[3] = (look[3] + 60 * flash).round.clamp(0, 100)
        end
        old = a[:look] || []
        ro['SkyColor']        = Sketchup::Color.new(*look[0]) if old[0] != look[0]
        ro['BackgroundColor'] = Sketchup::Color.new(*look[1]) if old[1] != look[1]
        si['Light'] = look[2] if old[2] != look[2]
        si['Dark']  = look[3] if old[3] != look[3]
        ro['HorizonColor'] = Sketchup::Color.new(*look[4], 255) if old[4] != look[4]
        a[:look] = look
        unless a[:fixed]            # luce del sole su tutte le facce, cielo visibile
          si['UseSunForAllShading'] = true
          ro['DrawHorizon'] = true
          a[:fixed] = true
        end
      elsif a[:look]                # colori spenti nel pannello: tornano quelli del modello
        sky_restore_look(model)
        a[:look] = a[:fixed] = nil
      end
    end

    # ── Disegno ───────────────────────────────────────────────────
    # Dove: ogni oggetto del cielo sta appena oltre il punto in cui il suo
    # raggio visivo esce dall'ingombro del modello. Tutta la geometria è
    # dentro l'ingombro, quindi niente gli sta dietro; e nessun punto
    # dell'ingombro è più profondo del suo spigolo più lontano, che il
    # piano di taglio lontano di SketchUp comprende. Così non serve
    # getExtents, che sposterebbe Zoom estensioni e il piano di taglio vicino.
    SKY_EMPTY = 4000.0   # pollici (~100 m): scena vuota

    # Occhio, sguardo, ingombro del modello e profondità del suo spigolo più lontano.
    def self.sky_geo(cam)
      bb = Sketchup.active_model.bounds
      eye = cam.eye.to_a.map(&:to_f); dir = cam.direction.to_a.map(&:to_f)
      return { eye: eye, dir: dir } if bb.empty?
      fmax = (0..7).map { |i| c = bb.corner(i).to_a; (0..2).sum { |j| (c[j].to_f - eye[j]) * dir[j] } }.max
      { eye: eye, dir: dir, box: [bb.min.to_a.map(&:to_f), bb.max.to_a.map(&:to_f)], fmax: fmax }
    end

    # Distanza dall'occhio lungo il versore w (vedi sopra).
    def self.sky_dist(g, w)
      return SKY_EMPTY unless g[:box]
      eye = g[:eye]; lo, hi = g[:box]
      cos = w[0] * g[:dir][0] + w[1] * g[:dir][1] + w[2] * g[:dir][2]
      far = g[:fmax] > 1.0 && cos > 0.01 ? g[:fmax] * 0.998 / cos : Float::INFINITY
      t_in = -Float::INFINITY; t_out = Float::INFINITY
      3.times do |i|
        if w[i].abs < 1e-12
          next if eye[i].between?(lo[i], hi[i])
          t_out = -1.0                 # parallelo a una faccia e fuori: non entra
          break
        end
        a = (lo[i] - eye[i]) / w[i]; b = (hi[i] - eye[i]) / w[i]
        a, b = b, a if a > b
        t_in = a if a > t_in
        t_out = b if b < t_out
      end
      return [t_out * 1.002, far].min if t_out > 0 && t_out >= t_in
      far.finite? ? far * 0.99 : SKY_EMPTY   # il raggio non incontra il modello
    end

    def self.sky_at(g, w, d)
      e = g[:eye]
      [e[0] + w[0] * d, e[1] + w[1] * d, e[2] + w[2] * d]
    end

    def self.sky_cross(a, b)
      [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    end

    def self.sky_unit(a)
      l = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
      l < 1e-12 ? nil : a.map { |x| x / l }
    end

    # Basi del disco perpendicolare alla direzione w: u verso "toward" (se
    # data e non parallela), altrimenti orizzontale.
    def self.sky_basis(w, toward = nil)
      if toward
        d = toward[0] * w[0] + toward[1] * w[1] + toward[2] * w[2]
        u = sky_unit([toward[0] - w[0] * d, toward[1] - w[1] * d, toward[2] - w[2] * d])
      end
      u ||= sky_unit(sky_cross(w, w[2].abs > 0.95 ? [1.0, 0.0, 0.0] : [0.0, 0.0, 1.0]))
      [u, sky_cross(w, u)]
    end

    def self.sky_pt(c, u, v, x, y)
      Geom::Point3d.new(c[0] + u[0] * x + v[0] * y, c[1] + u[1] * x + v[1] * y, c[2] + u[2] * x + v[2] * y)
    end

    def self.sky_xyz(c, u, v, x, y)
      [c[0] + u[0] * x + v[0] * y, c[1] + u[1] * x + v[1] * y, c[2] + u[2] * x + v[2] * y]
    end

    # Taglia un poligono convesso ([x, y, z]) alla parte con z >= zmin.
    # Con zmin = quota dell'occhio è l'orizzonte: sotto, sole e luna li
    # nasconde la terra, anche dove il modello non ha geometria.
    def self.sky_clip(pts, zmin)
      out = []
      pts.each_with_index do |p, i|
        q = pts[i - 1]
        p_in = p[2] >= zmin
        if p_in != (q[2] >= zmin)
          t = (zmin - q[2]) / (p[2] - q[2])
          out << [q[0] + (p[0] - q[0]) * t, q[1] + (p[1] - q[1]) * t, zmin]
        end
        out << p if p_in
      end
      out
    end

    def self.sky_disc(view, c, u, v, rad, color, zmin, n = 32)
      pts = sky_clip((0...n).map { |i| a = 2 * Math::PI * i / n; sky_xyz(c, u, v, rad * Math.cos(a), rad * Math.sin(a)) }, zmin)
      return if pts.size < 3
      view.drawing_color = color
      view.draw(GL_POLYGON, pts.map { |p| Geom::Point3d.new(*p) })
    end

    # Stelle come quadratini 3D rivolti alla camera, grandi px pixel:
    # draw_points ignora la profondità e le mostrerebbe sopra gli edifici,
    # i poligoni no.
    def self.sky_draw_stars(view, cam, g, bins, night)
      xa = cam.xaxis.to_a; ya = cam.yaxis.to_a; dir = g[:dir]
      bins.each_with_index do |dirs, i|
        next if dirs.empty?
        px, op = SKY_STAR_BINS[i][1, 2]
        quads = dirs.flat_map do |w|
          d = sky_dist(g, w)
          depth = d * (w[0] * dir[0] + w[1] * dir[1] + w[2] * dir[2])
          next [] if depth <= 0                  # dietro la camera
          h = px * g[:px] * depth / 2.0
          c = sky_at(g, w, d)
          [sky_pt(c, xa, ya, -h, -h), sky_pt(c, xa, ya, h, -h), sky_pt(c, xa, ya, h, h), sky_pt(c, xa, ya, -h, h)]
        end
        next if quads.empty?
        view.drawing_color = Sketchup::Color.new(255, 250, 235, (255 * op * night).round)
        view.draw(GL_QUADS, quads)
      end
    end

    def self.sky_draw(view)
      s = @sky
      return unless s && cf('sky_enabled')
      cam = view.camera
      return unless cam.perspective?
      g = sky_geo(cam)
      ref = g[:fmax] && g[:fmax] > 1.0 ? g[:fmax] : SKY_EMPTY
      g[:px] = view.pixels_to_model(1, cam.eye.offset(cam.direction, ref)).to_f / ref   # un pixel per unità di profondità
      night = sky_night(s[:sun_alt])
      veil = (1.0 - precip_cover)**1.5         # pioggia e neve velano sole, luna e stelle
      size = cf('sky_body_size').to_f.clamp(1.0, 10.0)
      sky_draw_stars(view, cam, g, s[:stars], night * veil) if s[:stars] && night * veil > 0.02
      # Strati sovrapposti (luna sul suo disco scuro, aloni del sole) un
      # poco più vicini l'uno dell'altro: non si contendono la profondità.
      zh = g[:eye][2]                          # orizzonte: piano all'altezza dell'occhio
      if cf('sky_moon') && s[:moon_alt] > -SKY_MOON_RAD * size / DEG
        w = s[:moon]; d = sky_dist(g, w); rad = d * Math.tan(SKY_MOON_RAD * size)
        u, v = sky_basis(w, s[:sun])
        sky_disc(view, sky_at(g, w, d), u, v, rad, Sketchup::Color.new(28, 32, 46, (210 * night * veil).round), zh) if night > 0.05
        # parte illuminata: fasce fra il bordo verso il sole e il terminatore,
        # ognuna tagliata all'orizzonte e divisa in triangoli
        c = sky_at(g, w, d * 0.997)
        k = 1.0 - 2.0 * s[:moon_lit]          # 1 luna nuova, 0 al quarto, -1 piena
        rows = (0..24).map do |i|
          th = Math::PI * (i / 24.0 - 0.5)
          [sky_xyz(c, u, v, rad * Math.cos(th), rad * Math.sin(th)), sky_xyz(c, u, v, rad * k * Math.cos(th), rad * Math.sin(th))]
        end
        tris = rows.each_cons(2).flat_map do |(a, b), (a2, b2)|
          q = sky_clip([a, a2, b2, b], zh)
          q.size < 3 ? [] : (1...q.size - 1).flat_map { |j| [q[0], q[j], q[j + 1]] }
        end
        if s[:moon_lit] > 0.005 && tris.any?
          view.drawing_color = Sketchup::Color.new(238, 238, 222, ((150 + 105 * night) * veil).round)
          view.draw(GL_TRIANGLES, tris.map { |p| Geom::Point3d.new(*p) })
        end
      end
      if cf('sky_sun') && s[:sun_alt] > -SKY_SUN_RAD * size * 2.6 / DEG
        w = s[:sun]; d = sky_dist(g, w); rad = d * Math.tan(SKY_SUN_RAD * size)
        u, v = sky_basis(w)
        low = ((8.0 - s[:sun_alt]) / 10.0).clamp(0.0, 1.0)       # rosso vicino all'orizzonte
        core = sky_mix([255, 250, 232], [255, 150, 70], low)
        sky_disc(view, sky_at(g, w, d), u, v, rad * 2.6, Sketchup::Color.new(*core, (40 * veil).round), zh)
        # col disco tutto sotto l'orizzonte resta solo il chiarore tenue dell'alba
        if s[:sun_alt] > -SKY_SUN_RAD * size / DEG
          sky_disc(view, sky_at(g, w, d * 0.997), u, v, rad * 1.6, Sketchup::Color.new(*core, (90 * veil).round), zh)
          sky_disc(view, sky_at(g, w, d * 0.994), u, v, rad, Sketchup::Color.new(*core, (255 * veil).round), zh)
        end
      end
      cloud_draw(view, g) if cloud_on?            # per ultime: sole, luna e stelle restano dietro
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # ── Pannello ──────────────────────────────────────────────────
    def self.sky_status
      return { 'on' => false, 'overlay' => SKY_OVERLAY } unless @sky && @sky_model
      t = Time.at(@sky[:utc] + @sky[:tz] * 3600.0).utc
      si = @sky_model.shadow_info
      place = [si['City'], si['Country']].map(&:to_s).reject(&:empty?).join(', ')
      { 'on' => true, 'overlay' => SKY_OVERLAY, 'y' => t.year, 'mo' => t.month, 'd' => t.day, 'h' => t.hour,
        'mi' => t.min, 'place' => place, 'custom' => !!cf('sky_place_custom'), 'lat' => @sky[:lat].round(2), 'lon' => @sky[:lon].round(2),
        'sun' => @sky[:sun_alt].round, 'moon' => (@sky[:moon_lit] * 100).round, 'phase' => @sky[:phase],
        'moon_up' => @sky[:moon_alt] > 0 }
    end

    # Al pannello, se aperto; mentre il tempo scorre al massimo 4 volte al secondo.
    def self.sky_push_status(force = false)
      return unless @dialog && @dialog.visible?
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if !force && @sky_status_t && now - @sky_status_t < 0.25
      @sky_status_t = now
      @dialog.execute_script("setSky(#{js_json(sky_status)})")
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # ── Osservatori e Overlay ─────────────────────────────────────
    class SkyModelObserver < Sketchup::ModelObserver
      def onPreSaveModel(model);  DagaWASD::FPSWalk.sky_saving(model, true);  end
      def onPostSaveModel(model); DagaWASD::FPSWalk.sky_saving(model, false); end
    end

    # ── Situazioni pronte (Meteo › Situazioni) ────────────────────
    # [ora, impostazioni]. L'ora è [:hour, h] fissa, oppure calcolata per la
    # data e il luogo scelti: [:rise | :set, altezza del sole°, ripiego] o
    # [:night, ripiego] (sole più basso). Si parte sempre da cielo animato
    # acceso, data e ora del pannello, tempo fermo.
    WEATHER_BASE = { 'sky_enabled' => true, 'sky_now' => false, 'sky_flow' => false, 'sky_colors' => true,
                     'sky_shadows' => true, 'sky_sun' => true, 'sky_moon' => true, 'sky_stars' => true,
                     'precip_kind' => 'none', 'storm' => false, 'cloud_enabled' => true }.freeze
    WEATHER_PRESETS = {
      'clear'     => [[:hour, 11.5], { 'cloud_cover' => 20, 'cloud_wind' => 6 }],
      'dawn'      => [[:rise, 2.0, 6.5], { 'cloud_cover' => 35, 'cloud_wind' => 5 }],
      'sunset'    => [[:set, 3.0, 19.0], { 'cloud_cover' => 40, 'cloud_wind' => 6 }],
      'starry'    => [[:night, 23.5], { 'cloud_enabled' => false }],
      'snownight' => [[:hour, 22.5], { 'precip_kind' => 'snow', 'precip_intensity' => 70, 'precip_wind' => 2,
                                       'precip_fog' => true, 'snow_cover' => true, 'cloud_cover' => 90 }],
      'storm'     => [[:hour, 16.5], { 'precip_kind' => 'rain', 'precip_intensity' => 90, 'precip_wind' => 9,
                                       'precip_fog' => true, 'storm' => true, 'cloud_cover' => 100, 'cloud_wind' => 14 }],
      'timelapse' => [[:rise, -8.0, 5.0], { 'sky_flow' => true, 'sky_day_minutes' => 1.5, 'cloud_cover' => 45,
                                            'cloud_timelapse' => true }]
    }.freeze

    # Ora locale (h) in cui, nel giorno del pannello, il sole sale (:rise) o
    # scende (:set) oltre alt gradi, o è più basso (:night); nil se non
    # succede (sole di mezzanotte, notte polare).
    def self.sky_sun_hour(kind, alt, lat, lon, tz)
      y = Time.now.year
      mo = cf('sky_month').to_i.clamp(1, 12)
      dim = (Time.utc(mo == 12 ? y + 1 : y, mo % 12 + 1, 1) - 86_400).day
      day0 = Time.utc(y, mo, cf('sky_day').to_i.clamp(1, dim)).to_f - tz * 3600.0
      alts = (0..288).map { |i| sky_state(day0 + i * 300.0, lat, lon, 0.0)[:sun_alt] }
      return alts.each_with_index.min_by { |a, _| a }[1] / 12.0 if kind == :night
      hits = (1..288).select do |i|
        kind == :rise ? alts[i - 1] < alt && alts[i] >= alt : alts[i - 1] > alt && alts[i] <= alt
      end
      i = kind == :rise ? hits.first : hits.last
      i && (i - 1 + (alt - alts[i - 1]) / (alts[i] - alts[i - 1])) / 12.0
    end

    # Applica una situazione: impostazioni, salvataggio, pannello aggiornato.
    def self.weather_preset(id)
      when_, set = WEATHER_PRESETS[id.to_s]
      return unless set
      old_rate = @cfg['tick_rate']
      @cfg.merge!(WEATHER_BASE).merge!(set)
      hour = when_[1] if when_[0] == :hour
      unless hour
        lat, lon, tz =
          if cf('sky_place_custom') then %w[sky_lat sky_lon sky_tz].map { |k| cf(k).to_f }
          elsif (m = Sketchup.active_model) then sky_place(m)
          else [41.9, 12.5, 1.0]
          end
        hour = when_[0] == :night ? sky_sun_hour(:night, 0, lat, lon, tz) : sky_sun_hour(when_[0], when_[1], lat, lon, tz)
        hour ||= when_.last
      end
      @cfg['sky_hour'] = ((hour * 4).round / 4.0) % 24.0     # passo del pannello: un quarto d'ora
      @sky_sig = nil
      apply_cfg_change(old_rate)
      return unless @dialog
      push_panel_state
      @dialog.execute_script("flashStatus(#{js_json(t("wp.#{id}"))})")
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Cielo, pioggia e nuvole insieme (modello nuovo o aperto)
    def self.weather_sync
      sky_sync
      precip_sync
      cloud_sync
      snow_sync
    end

    # Modello nuovo o aperto: il meteo passa a lui (al giro dopo, quando è attivo).
    class SkyAppObserver < Sketchup::AppObserver
      def onNewModel(_model);  UI.start_timer(0, false) { DagaWASD::FPSWalk.weather_sync }; end
      def onOpenModel(_model); UI.start_timer(0, false) { DagaWASD::FPSWalk.weather_sync }; end
    end

    if SKY_OVERLAY
      class SkyOverlay < Sketchup::Overlay
        def initialize
          super('dagawasd.sky', "DagaWASD — #{DagaWASD::FPSWalk.t('tab.weather')}")
        end
        def draw(view); DagaWASD::FPSWalk.sky_draw(view); end
      end
    end

  end
end
