# DagaWASD — Neve al suolo: tetti, terreno e chiome che sbiancano mentre nevica e poi si sciolgono.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Neve al suolo (Meteo › Pioggia e neve › Neve al suolo)
    # Il modello non cambia: un'Overlay ridisegna le facce rivolte verso
    # l'alto (normale con z > SNOW_MIN_NZ, anche dentro gruppi e
    # componenti; per i fogli sottili come le foglie conta anche il retro,
    # vedi snow_sheet?) come triangoli bianchi semitrasparenti, SNOW_LIFT sopra la
    # superficie. L'opacità è il livello della neve (0–1): sale mentre
    # nevica (pieno in snow_cover_time minuti alla massima intensità), cala
    # quando smette, più in fretta con la pioggia; al massimo SNOW_ALPHA,
    # così sotto si intravede il modello. Ogni triangolo prende un tono
    # dalla luce (snow_shade): col sole basso e libero conta l'angolo col
    # sole, col cielo coperto o di notte la luce è diffusa e conta solo
    # quanto la faccia è in piano. Più scura di notte; i toni sono
    # SNOW_SHADES gruppi, uno per chiamata di disegno.
    #
    # Le facce si raccolgono a poco a poco (SNOW_SLICE secondi per
    # fotogramma) e si disegnano solo quelle entro SNOW_RADIUS dalla camera;
    # la scelta si rifà quando la camera si sposta di SNOW_REBUILD. Una
    # modifica dell'utente (non le mosse della fisica) fa ripartire la
    # raccolta. Dove il modello non ha terreno (sotto l'orizzonte c'è lo
    # sfondo) il cielo animato sbianca anche lo sfondo (sky_apply_model).
    # ══════════════════════════════════════════════════════════════
    SNOW_MIN_NZ   = 0.45            # facce meno ripide di ~63°
    SNOW_SHADES   = 8               # toni di luce
    SNOW_ALPHA    = 190             # opacità con la neve piena
    SNOW_LIFT     = 0.025 * M_TO_IN
    SNOW_RADIUS   = 250.0 * M_TO_IN
    SNOW_REBUILD  = 25.0 * M_TO_IN
    SNOW_MAX_TRIS = 150_000
    SNOW_SLICE    = 0.006

    def self.snow_on?; cf('snow_cover') ? true : false; end
    def self.snow_level; @snow_level.to_f; end

    # Quanta neve cade adesso (0–1); il nevischio ne posa metà.
    def self.snow_falling
      return 0.0 unless snow_on?
      case precip_kind
      when 'snow' then precip_level
      when 'mix'  then precip_level * 0.5
      else 0.0
      end
    end

    # Livello dopo dt secondi: sale nevicando, cala quando smette.
    def self.snow_advance(level, dt, falling, raining)
      full = cf('snow_cover_time').to_f.clamp(0.5, 60.0) * 60.0
      if falling > 0
        level + dt / full * (0.4 + 0.6 * falling)
      else
        level - dt / (full * 1.5) * (raining ? 3.0 : 1.0)
      end.clamp(0.0, 1.0)
    end

    # ── Raccolta delle facce ──────────────────────────────────────
    def self.snow_collect_start(model)
      # La neve cade su tutto il modello, non solo sul contesto aperto
      @snow_queue = [[model.entities, Geom::Transformation.new]] # rubocop:disable SketchupSuggestions/ModelEntities
      @snow_tris = []
      @snow_open = {}
      @snow_count = 0
      @snow_sel_at = nil
    end

    # Avanza la raccolta per al massimo `slice` secondi; true se ha aggiunto qualcosa.
    def self.snow_collect_step(slice = SNOW_SLICE)
      q = @snow_queue
      return false unless q && !q.empty?
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      added = false
      until q.empty?
        ents, tr = q.shift
        ents.each do |e|
          case e
          when Sketchup::Face
            next if e.hidden? || (e.layer && !e.layer.visible?)
            added |= snow_add_face(e, tr)
          when Sketchup::Group, Sketchup::ComponentInstance
            next if e.hidden? || (e.layer && !e.layer.visible?)
            ents2 = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
            q << [ents2, tr * e.transformation]
          end
        end
        break if @snow_count >= SNOW_MAX_TRIS
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 > slice
      end
      q.clear if @snow_count >= SNOW_MAX_TRIS
      added
    end

    def self.snow_add_face(face, tr)
      n = face.normal.transform(tr)
      len = n.length.to_f
      return false if len < 1e-9
      nz = n.z.to_f / len
      s = 1.0
      if nz < SNOW_MIN_NZ
        # Un foglio che guarda in basso: la neve va sulla sua pagina di sopra
        return false unless -nz >= SNOW_MIN_NZ && snow_sheet?(face)
        s = -1.0
      end
      nx = s * n.x.to_f / len; ny = s * n.y.to_f / len; nz *= s
      mesh = face.mesh(0)
      pts = (1..mesh.count_points).map do |i|
        p = mesh.point_at(i).transform(tr)
        [p.x.to_f, p.y.to_f, p.z.to_f + SNOW_LIFT]
      end
      list = @snow_tris
      mesh.polygons.each do |poly|
        next unless poly.size == 3
        a, b, c = poly.map { |i| pts[i.abs - 1] }
        list << [(a[0] + b[0] + c[0]) / 3.0, (a[1] + b[1] + c[1]) / 3.0, nx, ny, nz, a, b, c]
        @snow_count += 1
      end
      true
    end

    # Foglio sottile visibile dai due lati (foglie e petali di Flora, tende,
    # pensiline): materiale anche sul retro e geometria aperta, cioè la sua
    # raccolta di entità ha spigoli con una faccia sola. Un solido chiuso
    # colorato anche dentro (lattina, fungo) non lo è: la sua faccia verso il
    # basso è il fondo. La prova si fa una volta per definizione e raccolta.
    def self.snow_sheet?(face)
      return false unless face.back_material
      par = face.parent
      return false unless par && par.respond_to?(:entities)
      cache = (@snow_open ||= {})
      return cache[par] if cache.key?(par)
      cache[par] = par.entities.grep(Sketchup::Edge).any? { |e| e.faces.size == 1 }
    end

    # Luce sulla neve: [direzione, quanto è diretta 0–1]. Diretta col sole
    # sopra l'orizzonte e il cielo libero; se no diffusa, dall'alto.
    def self.snow_light
      s = @sky
      return [[0.0, 0.0, 1.0], 0.0] unless s && s[:sun_alt] > 2.0
      clear = (1.0 - [precip_cover, cloud_overcast * 1.6, cloud_sun_shade].max).clamp(0.0, 1.0)
      [s[:sun], clear * ((s[:sun_alt] - 2.0) / 8.0).clamp(0.0, 1.0)]
    end

    # Tono di un triangolo (0,3–1) per normale n, luce l e quota diretta d
    def self.snow_shade(nx, ny, nz, l, d)
      diffuse = 0.62 + 0.38 * nz
      sun = 0.35 + 0.65 * [nx * l[0] + ny * l[1] + nz * l[2], 0.0].max
      diffuse + (sun - diffuse) * d
    end

    def self.snow_light_key(light)
      light[0].map { |x| (x * 20).round } << (light[1] * 10).round
    end

    # Triangoli entro SNOW_RADIUS dalla camera, divisi per tono e già pronti
    # per view.draw. Si rifà quando la camera si sposta o la luce cambia.
    def self.snow_select(ex, ey)
      r2 = SNOW_RADIUS**2
      light = snow_light
      l, d = light
      sel = Array.new(SNOW_SHADES) { [] }
      @snow_tris.each do |cx, cy, nx, ny, nz, a, b, c|
        dx = cx - ex; dy = cy - ey
        next unless dx * dx + dy * dy < r2
        i = ((snow_shade(nx, ny, nz, l, d) - 0.3) / 0.7 * SNOW_SHADES).floor.clamp(0, SNOW_SHADES - 1)
        sel[i] << a << b << c
      end
      @snow_sel = sel
      @snow_sel_at = [ex, ey]
      @snow_sel_light = snow_light_key(light)
    end

    # ── Accensione e fotogrammi ───────────────────────────────────
    def self.snow_sync
      model = Sketchup.active_model
      # agganciata solo se nevica o c'è ancora neve da sciogliere
      return snow_stop unless snow_on? && model && (snow_falling > 0 || snow_level > 0)
      snow_attach(model)
      unless @snow_timer
        @snow_tick = nil
        @snow_timer = UI.start_timer(0.1, true) { snow_frame }
      end
      model.active_view.invalidate
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.snow_stop
      UI.stop_timer(@snow_timer) if @snow_timer
      @snow_timer = nil
      had = snow_level > 0
      if (m = @snow_model)
        begin
          m.overlays.remove(@snow_ov) if @snow_ov
          m.remove_observer(@snow_mobs) if @snow_mobs
          m.active_view.invalidate
        rescue StandardError
          nil
        end
      end
      @snow_model = @snow_ov = @snow_queue = @snow_tris = @snow_sel = @snow_sel_at = nil
      @snow_level = 0.0
      sky_frame(true) if had && @sky_model           # lo sfondo torna del suo colore
    end

    def self.snow_attach(model)
      return if @snow_model.equal?(model)
      snow_stop if @snow_model
      @snow_model = model
      @snow_level = 0.0
      snow_collect_start(model)
      @snow_mobs ||= SnowModelObserver.new
      model.add_observer(@snow_mobs)
      if SKY_OVERLAY
        @snow_ov = SnowOverlay.new
        model.overlays.add(@snow_ov)
        @snow_ov.enabled = true
      end
      return if @sky_app_obs
      @sky_app_obs = SkyAppObserver.new
      Sketchup.add_observer(@sky_app_obs)
    end

    def self.snow_frame
      model = @snow_model
      return unless model
      return snow_sync unless Sketchup.active_model.equal?(model)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      dt = @snow_tick ? (now - @snow_tick).clamp(0.0, 0.5) : 0.0
      @snow_tick = now
      falling = snow_falling
      old = snow_level
      @snow_level = snow_advance(old, dt, falling, precip_kind == 'rain')
      eye = model.active_view.camera.eye
      grew = @snow_level > 0 && snow_collect_step
      at = @snow_sel_at
      if grew || at.nil? || Math.hypot(eye.x - at[0], eye.y - at[1]) > SNOW_REBUILD ||
         snow_light_key(snow_light) != @snow_sel_light
        snow_select(eye.x.to_f, eye.y.to_f)
      end
      if @sky_model && (@snow_level - @snow_sky.to_f).abs > 0.03   # sfondo innevato (cielo animato)
        @snow_sky = @snow_level
        sky_frame(true)
      end
      model.active_view.invalidate if @snow_level != old || grew
      return unless falling <= 0 && @snow_level <= 0       # sciolta: il timer si ferma
      UI.stop_timer(@snow_timer) if @snow_timer
      @snow_timer = nil
      sky_frame(true) if @sky_model
    rescue => fps_err
      log_error(__method__, fps_err)
      snow_stop
    end

    # Modifica dell'utente: le facce vanno raccolte di nuovo
    def self.snow_model_changed
      return if @in_phys_op || !@snow_model
      snow_collect_start(@snow_model)
    end

    # ── Disegno ───────────────────────────────────────────────────
    def self.snow_draw(view)
      lvl = snow_level
      sel = @snow_sel
      return unless sel && lvl > 0.01 && snow_on?
      night = @sky ? sky_night(@sky[:sun_alt]) : 0.0
      g = 250.0 - 130.0 * night
      a = (SNOW_ALPHA * lvl).round
      sel.each_with_index do |pts, i|
        next if pts.empty?
        shade = 0.3 + (i + 0.5) * 0.7 / SNOW_SHADES
        v = (g * shade).round
        view.drawing_color = Sketchup::Color.new(v, v, [v + 6 + (20 * (1 - shade)).round, 255].min, a)   # ombra azzurrina
        view.draw(GL_TRIANGLES, pts)
      end
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    class SnowModelObserver < Sketchup::ModelObserver
      def onTransactionCommit(_m); DagaWASD::FPSWalk.snow_model_changed; end
      def onTransactionUndo(_m);   DagaWASD::FPSWalk.snow_model_changed; end
      def onTransactionRedo(_m);   DagaWASD::FPSWalk.snow_model_changed; end
    end

    if SKY_OVERLAY
      class SnowOverlay < Sketchup::Overlay
        def initialize
          super('dagawasd.snowcover', "DagaWASD — #{DagaWASD::FPSWalk.t('grp.snowcover')}")
        end
        def draw(view); DagaWASD::FPSWalk.snow_draw(view); end
      end
    end

  end
end
