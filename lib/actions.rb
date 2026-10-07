# DagaWASD — Azioni: Aziona, Calcia, Afferra, Lancia.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Azioni
    # ══════════════════════════════════════════════════════════════

    def self.do_use
      result = raycast_forward(cf('use_range').to_f)
      return unless result
      e = result[1]&.first
      return unless e&.valid?
      name   = entity_label(e)
      dist_m = (Geom::Point3d.new(@eye_x, @eye_y, @eye_z).distance(result[0]) / M_TO_IN).round(2)
      extra  = ''
      if e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
        p = body_props(e)
        extra = "  ·  #{p[:m].round(1)} kg#{p[:mat] ? " · #{mat_label(p[:mat])}" : ''}"
      end
      Sketchup.status_text = "[#{t('rt.use')}] #{name}  (#{dist_m} m)#{extra}"
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Frazione di carica 0..1 trascorsa da `start` su un tempo di carica `ct`.
    def self.charge_ratio(start, ct)
      ct = ct.to_f
      return 1.0 if ct <= 0
      ((Time.now.to_f - start) / ct).clamp(0.0, 1.0)
    end

    # Per la barra di carica: [frazione, soglia zona spin | nil] o nil.
    def self.charge_info
      return nil unless @active && cf('charge_bar')
      if @grab_state == :charging && @charge_start
        [charge_ratio(@charge_start, cf('throw_charge_time')), THROW_SPIN_ZONE]
      elsif @kick_start
        [charge_ratio(@kick_start, cf('kick_charge_time')), nil]
      end
    end

    # ratio = frazione di carica 0..1 (1 = piena potenza)
    def self.do_kick(ratio = 1.0)
      result = raycast_forward(cf('kick_range').to_f)
      entity = phys_target(result)
      return unless entity
      p   = body_props(entity)
      ref = cf('impulse_ref_mass').to_f
      kmin = [cf('kick_force_min').to_f, cf('kick_force').to_f].min
      v_ref = kmin + (cf('kick_force').to_f - kmin) * ratio.clamp(0.0, 1.0)
      # Impulso costante: un oggetto di `ref` kg parte a `v_ref` m/s, uno
      # dieci volte più pesante a un decimo. Il tetto a 1.6× evita che un
      # oggetto quasi senza massa schizzi a velocità assurde: la gamba non può
      # comunque muoversi più veloce di così.
      v_max = v_ref * 1.6
      jmag  = [v_ref * ref, v_max * p[:m]].min
      # Un calcio che non smuove l'oggetto non lo trasforma in corpo rigido:
      # se pavimento o edificio sono un gruppo, simularli li farebbe
      # precipitare nel vuoto (sotto di loro il raggio non trova appoggio).
      if jmag * p[:im] < 0.1
        Sketchup.status_text =
          "[#{t('rt.kick')}] #{entity_label(entity)} — #{t('rt.grab_heavy')} (#{p[:m].round(0)} kg)"
        return
      end
      cp = Math.cos(@pitch); sp = Math.sin(@pitch)
      jx = Math.cos(@yaw) * cp * jmag
      jy = Math.sin(@yaw) * cp * jmag
      jz = sp * jmag

      center = com_world(entity)
      hit = result[0]
      apply_impulse(entity, jx, jy, jz,
                    hit.x - center.x, hit.y - center.y, hit.z - center.z)
      v = (jmag * p[:im]).round(1)
      Sketchup.status_text = "[#{t('rt.kick')}] #{entity_label(entity)} — #{p[:m].round(1)} kg → #{v} m/s"
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # G afferra il gruppo più esterno colpito; se pesa troppo scende di
    # livello fino al primo pezzo sollevabile e lo estrae dal contenitore.
    # inner = true (Shift+G): direttamente il gruppo più interno.
    # Ogni rifiuto lascia un messaggio nella barra di stato: senza, un G
    # a vuoto sembrerebbe un tasto che non risponde.
    def self.do_grab(inner = false)
      tag = "[#{t('rt.grab')}]"
      rng = cf('grab_range').to_f
      hit = aim_ray
      unless hit
        Sketchup.status_text = "#{tag} #{t('rt.grab_nothing')}"
        return
      end
      result, dist = hit
      if dist > rng
        Sketchup.status_text =
          "#{tag} #{t('rt.grab_far')} (#{dist.round(1)} m, #{t('rt.grab_max')} #{rng.round(1)} m)"
        return
      end
      entity = phys_target(result)
      unless entity
        Sketchup.status_text = "#{tag} #{t('rt.grab_loose')}"
        return
      end

      model = Sketchup.active_model
      extracted = false
      max_kg = cf('grab_max_mass').to_f
      # G: il pezzo più esterno che si riesce a sollevare, scendendo un livello
      # alla volta lungo ciò che il mirino attraversa (libreria troppo pesante
      # → il libro colpito). Shift+G: direttamente il più interno.
      lvl = if inner
              nil
            elsif body_props(entity)[:m] > max_kg
              insts = result[1].select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
              grab_level(insts, max_kg).tap do |found|
                # nessuno sollevabile: il messaggio parla del pezzo più leggero
                entity = insts.min_by { |e| body_props(e)[:m] } unless found
              end
            end
      if inner || lvl&.positive?
        model.start_operation(t('rt.grab'), true)
        e2 = extract_inner(result, lvl)
        if e2
          entity = e2; extracted = true
        else
          model.abort_operation   # niente di annidato: presa normale
        end
      end

      p = body_props(entity)
      if p[:m] > max_kg
        model.abort_operation if extracted   # il pezzo torna nel suo gruppo
        Sketchup.status_text =
          "#{tag} #{entity_label(entity)} — #{t('rt.grab_heavy')}: #{p[:m].round(1)} kg " \
          "(#{t('rt.grab_max')} #{cf('grab_max_mass').to_f.round(0)} kg)"
        return
      end
      if extracted
        model.commit_operation
        @phys_op_named = false   # la fisica dopo l'estrazione ha la sua voce
      end

      @grabbed_entity = entity
      @grab_state     = :holding
      @phys_entities.delete(entity)
      @held_block     = 0.0
      build_obstacle_grid(entity)   # fase larga delle collisioni dell'oggetto in mano
      # Strappo iniziale (vedi update_grabbed_position): parte da qui
      bc = entity.bounds
      @grab_from  = [(bc.min.x + bc.max.x) * 0.5, (bc.min.y + bc.max.y) * 0.5, (bc.min.z + bc.max.z) * 0.5]
      @grab_t     = 0.0
      @hold_dist  = cf('grab_distance').to_f   # la rotella la cambia finché lo tieni
      @grab_out_free = nil          # deciso all'inizio dell'allontanamento (vedi held.rb)
      @grab_ghost = true
      Sketchup.status_text =
        "#{tag} #{entity_label(entity)} (#{p[:m].round(1)} kg)" \
        "#{extracted ? " · #{t('rt.grab_extracted')}" : ''} — #{t('rt.grab_hold')}"
    rescue => fps_err
      log_error(__method__, fps_err)
      (model.abort_operation rescue nil) if extracted && !@grabbed_entity
      nil
    end

    def self.do_throw
      return unless @grabbed_entity&.valid?
      # Tocco breve di G = posalo, senza lancio (anche il lancio minimo lo
      # scaglierebbe a throw_force_min m/s).
      if @charge_start && Time.now.to_f - @charge_start < GRAB_TAP
        return drop_grabbed('rt.grab_drop')
      end
      entity = @grabbed_entity
      p   = body_props(entity)
      ref = cf('impulse_ref_mass').to_f
      ratio  = @charge_start ? charge_ratio(@charge_start, cf('throw_charge_time')) : 0.0
      # Come per il calcio: un minimo oltre il massimo non fa lanciare più
      # piano caricando di più (il pannello li tiene in ordine, settings.json no)
      tmax   = cf('throw_force_max').to_f
      tmin   = [cf('throw_force_min').to_f, tmax].min
      v_ref  = tmin + (tmax - tmin) * ratio
      # Come per il calcio: impulso costante, ma velocità limitata a 1.6× il
      # nominale (il braccio non può lanciare più veloce di così).
      jmag   = [v_ref * ref, v_ref * 1.6 * p[:m]].min   # impulso (kg·m/s)
      v_real = jmag * p[:im]                            # velocità effettiva (m/s)

      cp = Math.cos(@pitch); sp = Math.sin(@pitch)
      jx = Math.cos(@yaw) * cp * jmag
      jy = Math.sin(@yaw) * cp * jmag
      jz = sp * jmag

      # Topspin: braccio applicato sopra il centro → rotazione in avanti.
      # Solo per un lancio a piena potenza (ultimo tratto della carica):
      # un lancio leggero è un accompagnamento, e l'oggetto parte senza ruotare.
      b = entity.bounds
      arm = ratio >= THROW_SPIN_ZONE ? (b.max.z - b.min.z) * 0.30 : 0.0
      apply_impulse(entity, jx, jy, jz, 0.0, 0.0, arm)

      Sketchup.status_text = "[#{t('rt.throw')}] #{p[:m].round(1)} kg → #{v_real.round(1)} m/s"
      @grabbed_entity = nil; @grab_state = :idle; @charge_start = nil
    rescue => fps_err; log_error(__method__, fps_err); nil; end

  end
end
