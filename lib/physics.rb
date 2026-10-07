# DagaWASD — Passo della simulazione dei corpi rigidi e spinta sul player.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Simulazione corpi rigidi — un passo dt
    # ══════════════════════════════════════════════════════════════
    def self.step_physics(dt)
      return if @phys_entities.empty? && @grabbed_entity.nil?
      # Chi viene simulato si sposta: la griglia statica della presa non lo
      # sa, quindi da qui in poi lo si controlla sulla posizione attuale.
      @dyn_entities.merge(@phys_entities.keys)

      model      = Sketchup.active_model
      gravity_in = cf('gravity').to_f * M_TO_IN
      max_fall   = cf('max_fall_speed').to_f * M_TO_IN
      lin_damp   = cf('obj_lin_damping').to_f
      ang_damp   = cf('obj_ang_damping').to_f
      air_drag   = cf('obj_air_drag').to_f
      sleep_lin  = cf('obj_sleep_lin').to_f * M_TO_IN
      sleep_ang  = cf('obj_sleep_ang').to_f
      sleep_time = cf('obj_sleep_time').to_f
      do_walls   = cf('obj_walls')
      do_tip     = cf('obj_tipping')
      cos_slope  = Math.cos(cf('max_slope_deg').to_f * DEG)
      to_rest    = []   # fermi abbastanza a lungo: si addormentano
      to_drop    = []   # non più validi, caduti nel vuoto o in errore: escono comunque

      # ── Pre-scan pavimenti (fuori dall'operation per coerenza) ────
      floor_data = {}
      @phys_entities.each_key do |entity|
        next unless entity.valid?
        b  = entity.bounds
        cx = (b.min.x + b.max.x) * 0.5
        cy = (b.min.y + b.max.y) * 0.5
        r  = ray_ignoring(cx, cy, b.min.z + 1.0, 0, 0, -1, entity)
        # Nessun colpo dalla base: forse è affondata un po' nel pavimento.
        # Si riprova dall'alto; se anche così sotto non c'è niente, è nel
        # vuoto (:void) e deve cadere, non restare alla quota di prima.
        r ||= ray_ignoring(cx, cy, b.max.z + 1.0, 0, 0, -1, entity)
        floor_data[entity] = r ? [r[0].z, hit_normal(r, 0, 0, -1)] : :void
      rescue => fps_err
        log_error(:floor_scan, fps_err)
        floor_data[entity] = nil
      end

      # Annullamento: la prima mossa della fisica apre una voce propria
      # ("DagaWASD"), le successive vi si accodano (transparent). Se
      # anche la prima fosse accodata finirebbe nell'ultima operazione
      # dell'utente, e un Ctrl+Z dopo l'uscita cancellerebbe anche quella.
      # Accodarsi vale solo se in cima alla cronologia c'è ancora la voce della
      # fisica: OpObserver rimette @phys_op_named a false a ogni operazione
      # altrui e a ogni annulla/ripeti (vedi sotto).
      @in_phys_op = true
      if @phys_op_named
        model.start_operation('', true, false, true)
      else
        model.start_operation('DagaWASD', true)
        @phys_op_named = true
      end
      begin   # …e l'operazione va chiusa comunque, anche se qualcosa fallisce

      # Oggetto tenuto: nessuna gravità, segue la camera
      if @grabbed_entity
        if @grabbed_entity.valid?
          update_grabbed_position(dt)
        else
          @grabbed_entity = nil; @grab_state = :idle
        end
      end

      @phys_entities.each do |entity, state|
        begin
          unless entity.valid?
            to_drop << entity; next
          end

          p        = state[:props] ||= body_props(entity)
          bounds   = entity.bounds
          bottom_z = bounds.min.z

          if bottom_z < -200 * M_TO_IN    # precipitato nel vuoto
            to_drop << entity; next
          end

          fd           = floor_data[entity]
          void         = fd == :void
          fd           = nil if void
          fz           = fd && fd[0]
          fn           = fd && fd[1]
          effective_fz = void ? nil : (fz || state[:fz])

          # ── Pre-correzione clip: la rotazione del tick precedente può aver
          #    spinto uno spigolo sotto il piano d'appoggio.
          if effective_fz && bottom_z < effective_fz - 0.05
            push = effective_fz - bottom_z
            entity.transformation = Geom::Transformation.translation(
              Geom::Vector3d.new(0, 0, push)
            ) * entity.transformation
            bottom_z   = effective_fz
            state[:vz] = [state[:vz], 0.0].max
          end

          # ── Gravità ──────────────────────────────────────────────
          state[:vz] -= gravity_in * dt
          state[:vz]  = state[:vz].clamp(-max_fall, max_fall)

          # ── Smorzamento lineare e resistenza dell'aria ───────────
          # La resistenza cresce col quadrato della velocità: gli oggetti
          # lanciati forte rallentano in volo in modo credibile.
          spd = Math.sqrt(state[:vx]**2 + state[:vy]**2 + state[:vz]**2)
          if spd > 0.01
            drag = (lin_damp + air_drag * spd * IN_TO_M) * dt
            f = [1.0 - drag, 0.0].max
            state[:vx] *= f; state[:vy] *= f; state[:vz] *= f
          end

          dx = state[:vx] * dt
          dy = state[:vy] * dt
          dz = state[:vz] * dt

          on_floor = false

          # ── Collisione con muri / superfici verticali ────────────
          if do_walls && (dx.abs > 0.2 || dy.abs > 0.2)
            hl = Math.sqrt(dx * dx + dy * dy)
            ux = dx / hl; uy = dy / hl
            cx = (bounds.min.x + bounds.max.x) * 0.5
            cy = (bounds.min.y + bounds.max.y) * 0.5
            cz = (bounds.min.z + bounds.max.z) * 0.5
            half = [(bounds.max.x - bounds.min.x), (bounds.max.y - bounds.min.y)].max * 0.5
            res = ray_ignoring(cx, cy, cz, ux, uy, 0, entity)
            if res
              d = Math.sqrt((res[0].x - cx)**2 + (res[0].y - cy)**2)
              if d < half + hl
                n = hit_normal(res, ux, uy, 0)
                if n
                  vn = (state[:vx] * n[0] + state[:vy] * n[1] + state[:vz] * n[2])
                  if vn < 0
                    e = p[:rest]
                    # Riflessione con restituzione + attrito tangenziale
                    state[:vx] -= (1.0 + e) * vn * n[0]
                    state[:vy] -= (1.0 + e) * vn * n[1]
                    state[:vz] -= (1.0 + e) * vn * n[2]
                    tf = [1.0 - p[:fric] * 0.5, 0.0].max
                    state[:vx] *= tf; state[:vy] *= tf
                    # L'urto contro il muro fa ruotare l'oggetto
                    spin = vn.abs * IN_TO_M * 0.35
                    state[:ox] = (state[:ox] + n[1] * spin).clamp(-MAX_OMEGA, MAX_OMEGA)
                    state[:oy] = (state[:oy] - n[0] * spin).clamp(-MAX_OMEGA, MAX_OMEGA)
                    dx = state[:vx] * dt; dy = state[:vy] * dt; dz = state[:vz] * dt
                  end
                end
              end
            end
          end

          # ── Collisione pavimento / rimbalzo ──────────────────────
          if effective_fz && bottom_z + dz <= effective_fz + 0.5
            on_floor = true
            dz       = effective_fz - bottom_z
            if state[:vz] < 0
              impact = state[:vz].abs
              e = p[:rest]
              if e > 0 && impact > 2.0
                # L'urto obliquo genera rotazione (spin da impatto)
                state[:ox] = (state[:ox] + state[:vy] * IN_TO_M * e * 0.30).clamp(-MAX_OMEGA, MAX_OMEGA)
                state[:oy] = (state[:oy] - state[:vx] * IN_TO_M * e * 0.30).clamp(-MAX_OMEGA, MAX_OMEGA)
              end
              reb = e > 0 ? (-state[:vz] * e) : 0.0
              state[:vz] = reb.abs < 2.0 ? 0.0 : reb
            end
          end

          state[:fz] = effective_fz if on_floor && effective_fz

          stable = true
          sup    = nil    # analisi d'appoggio (body_support)
          sup_n  = nil    # normale del piano d'appoggio
          pivot  = nil    # perno di ribaltamento (Point3d) se sta basculando
          curved = false  # poggia su una superficie curva (rotola / dondola)

          if on_floor
            mu    = p[:fric]
            sup_n = fn && fn[2] > 0.05 ? fn : [0.0, 0.0, 1.0]
            sup   = p[:geo] ? body_support(entity, p[:geo], sup_n) : nil
            curved = sup && sup[:kind] == :curved

            if curved
              # ── Rotolamento / dondolio ─────────────────────────────
              # Sulla superficie curva niente attrito radente pieno: il corpo
              # rotola, frenato solo dalla resistenza al rotolamento.
              stable = roll_step(state, p, sup, dt, cf('gravity').to_f)
            else
              # ── Attrito di Coulomb col terreno ─────────────────────
              # a_attrito = μ·g  →  decelerazione indipendente dalla massa.
              vh = Math.sqrt(state[:vx]**2 + state[:vy]**2)
              if vh > 0.01
                dec = mu * gravity_in * dt
                if dec >= vh
                  state[:vx] = 0.0; state[:vy] = 0.0
                else
                  k = (vh - dec) / vh
                  state[:vx] *= k; state[:vy] *= k
                end
              end

              # ── Scivolamento su pendenza ───────────────────────────
              # (i corpi curvi rotolano a valle da soli: la coppia della
              # gravità rispetto al contatto li porta giù)
              if fn && fn[2] < cos_slope && fn[2] > 0.05
                # Gravità proiettata sul piano: la parte orizzontale della
                # normale punta a valle → è la direzione di scivolamento.
                gx = fn[0] * fn[2]; gy = fn[1] * fn[2]
                gl = Math.sqrt(gx * gx + gy * gy)
                if gl > 1e-4
                  slope_a = gravity_in * Math.sqrt([1.0 - fn[2] * fn[2], 0.0].max) * dt
                  state[:vx] += gx / gl * slope_a
                  state[:vy] += gy / gl * slope_a
                end
              end
            end
            state[:oz] *= [1.0 - (ang_damp + mu) * dt * 2.0, 0.0].max

            # ── Ribaltamento: appoggio reale sui vertici ─────────────
            if do_tip && sup && sup[:kind] == :poly
              if sup[:free]
                stable = false
              elsif sup[:face] && sup[:inside]
                # Poggia su una faccia col CM dentro: il contatto annulla la
                # rotazione attorno agli assi orizzontali (urto anelastico).
                stable = true
                state[:ox] = 0.0; state[:oy] = 0.0
              else
                stable = false
                pivot  = sup[:pivot]
                c      = sup[:com]
                if sup[:lever] > 0.05
                  # Coppia della gravità attorno al perno: τ = r × (0,0,−m·g)
                  # α = τ / (I_cm + m·d²)   (teorema degli assi paralleli)
                  rx = (c.x - pivot.x) * IN_TO_M
                  ry = (c.y - pivot.y) * IN_TO_M
                  rz = (c.z - pivot.z) * IN_TO_M
                  i_over_m = [p[:ix], p[:iy], p[:iz]].max / p[:m]
                  k = i_over_m + rx * rx + ry * ry + rz * rz
                  g = cf('gravity').to_f
                  state[:ox] = (state[:ox] - g * ry / k * dt).clamp(-MAX_OMEGA, MAX_OMEGA)
                  state[:oy] = (state[:oy] + g * rx / k * dt).clamp(-MAX_OMEGA, MAX_OMEGA)
                else
                  # CM esattamente sopra uno spigolo: equilibrio instabile, che
                  # in natura non dura. Una spinta minima decide il lato.
                  a = rand * PI2
                  state[:ox] += -Math.sin(a) * 0.4
                  state[:oy] +=  Math.cos(a) * 0.4
                end
              end
            end
          else
            # In aria: solo smorzamento angolare
            f = [1.0 - ang_damp * 0.3 * dt, 0.0].max
            state[:ox] *= f; state[:oy] *= f; state[:oz] *= f
          end

          # ── Traslazione ─────────────────────────────────────────
          if dx.abs > 0.02 || dy.abs > 0.02 || dz.abs > 0.02
            entity.transformation =
              Geom::Transformation.translation(Geom::Vector3d.new(dx, dy, dz)) *
              entity.transformation
          end

          # ── Rotazione (tumbling / rolling / ribaltamento) ────────
          ox = state[:ox]; oy = state[:oy]; oz = state[:oz]
          omega_sq = ox * ox + oy * oy + oz * oz
          if omega_sq > 0.0001
            # Si ruota attorno al baricentro reale (per una semisfera non è
            # il centro della scatola).
            center = com_world(entity)
            if pivot
              # Basculando su uno spigolo il perno resta fermo a terra: la
              # parte orizzontale della rotazione va fatta attorno a lui (il
              # perno è stato misurato prima della traslazione di questo tick).
              rc = Geom::Point3d.new(pivot.x + dx, pivot.y + dy, pivot.z + dz)
              hm = Math.sqrt(ox * ox + oy * oy)
              if hm * dt > 0.0005
                u   = [ox / hm, oy / hm, 0.0]
                ang = hm * dt
                # Se in questo tick un altro punto tocca il piano, ci si ferma
                # esattamente lì: il corpo atterra sulla faccia (o sul fianco
                # del cilindro) invece di attraversarla, e l'urto anelastico
                # azzera la rotazione.
                hit = tipping_toi(sup[:hw], sup[:pivot], u, sup_n, ang)
                if hit
                  ang = hit
                  state[:ox] = 0.0; state[:oy] = 0.0
                end
                entity.transformation = Geom::Transformation.rotation(
                  rc, Geom::Vector3d.new(*u), ang
                ) * entity.transformation
              end
              if oz.abs * dt > 0.0005
                entity.transformation = Geom::Transformation.rotation(
                  center, Geom::Vector3d.new(0, 0, oz > 0 ? 1 : -1), oz.abs * dt
                ) * entity.transformation
              end
            else
              omega_mag = Math.sqrt(omega_sq)
              angle     = omega_mag * dt
              if angle > 0.0005
                axis = Geom::Vector3d.new(ox / omega_mag, oy / omega_mag, oz / omega_mag)
                entity.transformation =
                  Geom::Transformation.rotation(center, axis, angle) * entity.transformation
              end
            end
            omega_sq = state[:ox]**2 + state[:oy]**2 + state[:oz]**2
          end

          # ── Post-rotazione: recupera il clip indotto dalla rotazione ─
          post_fz = void ? nil : (fz || state[:fz])
          if post_fz
            b3         = entity.bounds
            clip_depth = post_fz - b3.min.z
            if clip_depth > 0.05
              entity.transformation = Geom::Transformation.translation(
                Geom::Vector3d.new(0, 0, clip_depth)
              ) * entity.transformation
              if clip_depth > 1.0
                damp = 0.7
                state[:ox] *= damp; state[:oy] *= damp; state[:oz] *= damp
              end
              state[:vz] = [state[:vz], 0.0].max
            end
          end

          # ── Sonno: serve quiete SOSTENUTA, non un singolo frame ──
          v_lin = Math.sqrt(state[:vx]**2 + state[:vy]**2 + state[:vz]**2)
          if on_floor && stable && v_lin < sleep_lin && Math.sqrt(omega_sq) < sleep_ang
            state[:still] += dt
            to_rest << entity if state[:still] >= sleep_time
          else
            state[:still] = 0.0
          end
        rescue => fps_err
          log_error(:step_body, fps_err)
          to_drop << entity
        end
      end

      resolve_entity_collisions(model)
      push_player_from_entities(dt)

      # Non addormentare corpi che hanno appena ricevuto un impulso da collisione
      # (quelli in to_drop escono comunque: uno che precipita è sempre "in moto").
      to_rest.reject! do |e|
        next false unless e.valid?
        st = @phys_entities[e]
        st && st[:still] < sleep_time &&
          (st[:vx].abs > 1.0 || st[:vy].abs > 1.0 || st[:vz].abs > 1.0)
      end

      ensure
        model.commit_operation rescue nil
        @in_phys_op = false
      end
      (to_rest + to_drop).each { |e| @phys_entities.delete(e) }
    rescue => fps_err
      @in_phys_op = false
      log_error(__method__, fps_err)
      nil
    end

    # ── Voce d'annullamento della fisica ─────────────────────────────
    # Le mosse della fisica si accodano alla voce "DagaWASD". Se però in cima
    # alla cronologia finisce altro (Ctrl+Z in modalità FPS, un disegno durante
    # l'assestamento dopo l'uscita, un invio del ponte), accodarsi metterebbe
    # la fisica dentro l'operazione di qualcun altro: un Ctrl+Z annullerebbe
    # insieme le due cose. Ogni operazione altrui, annulla e ripeti fanno
    # quindi aprire alla fisica una voce nuova.
    class OpObserver < Sketchup::ModelObserver
      def onTransactionCommit(_model); DagaWASD::FPSWalk.foreign_op; end
      def onTransactionUndo(_model);   DagaWASD::FPSWalk.foreign_op; end
      def onTransactionRedo(_model);   DagaWASD::FPSWalk.foreign_op; end
    end

    def self.foreign_op
      @phys_op_named = false unless @in_phys_op
    end

    # Osserva le operazioni del modello (uno alla volta: aperto un altro
    # file, l'osservatore passa al nuovo modello).
    def self.watch_ops(model)
      return if model.nil? || @op_model.equal?(model)
      @op_obs ||= OpObserver.new
      (@op_model.remove_observer(@op_obs) rescue nil) if @op_model
      model.add_observer(@op_obs)
      @op_model = model
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Un corpo in moto che investe il player lo spinge: la spinta è tanto più
    # forte quanto più l'oggetto è pesante rispetto al player.
    def self.push_player_from_entities(dt)
      return unless @active && cf('knockback_enabled')
      return if @phys_entities.empty?
      r_in = cf('body_radius').to_f * M_TO_IN
      h_in = @cur_h_m * M_TO_IN
      pmin_z = @eye_z - h_in
      pm = cf('player_mass').to_f

      @phys_entities.each do |entity, st|
        next unless entity.valid?
        speed = Math.sqrt(st[:vx]**2 + st[:vy]**2 + st[:vz]**2) * IN_TO_M
        next if speed < 1.0
        b = entity.bounds
        next if b.max.z < pmin_z || b.min.z > @eye_z + 4.0
        next if b.max.x < @eye_x - r_in || b.min.x > @eye_x + r_in
        next if b.max.y < @eye_y - r_in || b.min.y > @eye_y + r_in

        p = st[:props] || body_props(entity)
        ratio = (p[:m] / (p[:m] + pm)).clamp(0.0, 0.95)
        # Il player riceve una frazione della velocità dell'oggetto (m/s)
        @vh_x += st[:vx] * IN_TO_M * ratio * 0.6
        @vh_y += st[:vy] * IN_TO_M * ratio * 0.6
        if st[:vz] > 0.5
          # Un oggetto che sale sotto i piedi solleva il player
          @vv = [@vv, st[:vz] * IN_TO_M * ratio * 0.5].max
          @on_ground = false if @vv > 0.5
        end
        # Reazione: l'oggetto perde parte della sua velocità
        st[:vx] *= (1.0 - ratio * 0.5)
        st[:vy] *= (1.0 - ratio * 0.5)
      end
    rescue => fps_err; log_error(__method__, fps_err); nil; end

  end
end
