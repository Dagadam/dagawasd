# DagaWASD — Corpi rigidi: mira, estrazione da un gruppo, registrazione, impulsi.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Interazioni — raycast / registrazione corpi
    # ══════════════════════════════════════════════════════════════

    # Raggio lungo la direzione della camera, senza limite di distanza.
    # Ritorna [risultato raytest, distanza in m] oppure nil.
    def self.aim_ray
      cp = Math.cos(@pitch); sp = Math.sin(@pitch)
      res = pray(@eye_x, @eye_y, @eye_z, cp * Math.cos(@yaw), cp * Math.sin(@yaw), sp)
      return nil unless res
      [res, Geom::Point3d.new(@eye_x, @eye_y, @eye_z).distance(res[0]) / M_TO_IN]
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Raycast nella direzione della camera fino a range_m metri
    def self.raycast_forward(range_m)
      hit = aim_ray
      hit && hit[1] <= range_m ? hit[0] : nil
    end

    # Primo livello del percorso colpito (dal più esterno al più interno)
    # abbastanza leggero da sollevare; nil se nessuno lo è.
    def self.grab_level(insts, max_kg)
      (0...insts.size).find { |i| body_props(insts[i])[:m] <= max_kg }
    end

    # Porta al livello principale il gruppo/componente colpito dal raggio al
    # livello lvl del percorso (0 = il più esterno; nil = il PIÙ INTERNO),
    # mantenendone la posizione nel mondo. La fisica lavora in coordinate
    # mondo sulle entità del modello: un pezzo annidato va tirato fuori dal
    # suo contenitore per poterlo muovere da solo.
    # Ritorna la nuova istanza, o nil se il colpo non è dentro un annidato.
    # Va chiamata dentro un'operazione (annullabile con abort_operation).
    def self.extract_inner(res, lvl = nil)
      grp = ->(e) { e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      insts = res[1].select(&grp)
      return nil if insts.size < 2
      lvl ||= insts.size - 1
      return nil unless lvl.between?(1, insts.size - 1)

      # Contenitori condivisi (copie dello stesso gruppo/componente): prima
      # vanno resi unici, altrimenti il pezzo sparirebbe da tutte le copie.
      # make_unique duplica il contenuto, quindi dopo ogni passo il percorso
      # si ricalcola con un nuovo raggio.
      a = 0
      while a < lvl
        anc = insts[a]
        if anc.definition.instances.size > 1 && anc.respond_to?(:make_unique)
          anc.make_unique
          hit = aim_ray
          return nil unless hit
          insts = hit[0][1].select(&grp)
          return nil if insts.size <= lvl
        end
        a += 1
      end

      inner = insts[lvl]
      tr = Geom::Transformation.new
      insts[0..lvl].each { |e| tr *= e.transformation }
      # L'oggetto estratto va nel modello, non nel contesto aperto: la fisica lavora lì
      ni = Sketchup.active_model.entities.add_instance(inner.definition, tr) # rubocop:disable SketchupSuggestions/ModelEntities
      # Le facce senza materiale prendevano quello del contenitore: fuori
      # dal gruppo devono restare dello stesso colore.
      mat = inner.material || insts[0...lvl].reverse.map(&:material).compact.first
      ni.material = mat if mat
      ni.layer    = inner.layer
      ni.name     = inner.name unless inner.name.to_s.empty?
      # Attributi dell'istanza (es. i dati dei componenti dinamici)
      (inner.attribute_dictionaries || []).each do |dict|
        dict.each_pair { |k, v| ni.set_attribute(dict.name, k, v) }
      end
      inner.erase!
      ni
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Ritorna il ComponentInstance/Group colpito (primo livello), o nil
    def self.phys_target(result)
      return nil unless result
      e = result[1]&.first
      return nil unless e&.valid?
      return e if e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
      nil
    end

    def self.add_physics_entity(entity, vx, vy, vz, ox = 0.0, oy = 0.0, oz = 0.0)
      # Tetto al numero di corpi simultanei: esce quello più fermo (non il
      # più vecchio, che potrebbe essere in volo e resterebbe sospeso in aria).
      cap = cf('max_phys_entities').to_i
      cap = 4 if cap < 4
      while @phys_entities.size >= cap
        calm = @phys_entities.min_by { |_, st| st[:vx]**2 + st[:vy]**2 + st[:vz]**2 - (st[:fz] ? 1e6 : 0) }
        break unless calm
        @phys_entities.delete(calm[0])
      end
      p = body_props(entity)
      @phys_entities[entity] = {
        vx: vx.to_f, vy: vy.to_f, vz: vz.to_f,
        ox: ox.to_f, oy: oy.to_f, oz: oz.to_f,
        fz: nil, still: 0.0, props: p
      }
    end

    # Applica un impulso (kg·m/s) a un'entità, con braccio r (pollici, dal CM).
    # Se l'entità non è ancora simulata viene aggiunta.
    def self.apply_impulse(entity, jx, jy, jz, rx_in = 0.0, ry_in = 0.0, rz_in = 0.0)
      p  = body_props(entity)
      st = @phys_entities[entity]
      unless st
        add_physics_entity(entity, 0, 0, 0)
        st = @phys_entities[entity]
      end
      return unless st

      # Δv lineare (m/s → pollici/s)
      st[:vx] += jx * p[:im] * M_TO_IN
      st[:vy] += jy * p[:im] * M_TO_IN
      st[:vz] += jz * p[:im] * M_TO_IN

      # Δω = (r × J) / I   —  r convertito in metri
      rx = rx_in * IN_TO_M; ry = ry_in * IN_TO_M; rz = rz_in * IN_TO_M
      st[:ox] = (st[:ox] + (ry * jz - rz * jy) / p[:ix]).clamp(-MAX_OMEGA, MAX_OMEGA)
      st[:oy] = (st[:oy] + (rz * jx - rx * jz) / p[:iy]).clamp(-MAX_OMEGA, MAX_OMEGA)
      st[:oz] = (st[:oz] + (rx * jy - ry * jx) / p[:iz]).clamp(-MAX_OMEGA, MAX_OMEGA)
      st[:still] = 0.0
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Il player cammina contro un oggetto leggero: gli cede quantità di moto in
    # proporzione al rapporto di massa (un armadio non si muove, una scatola sì).
    def self.try_push_entity(entity, dx, dy, dt)
      return unless cf('push_enabled')
      return unless entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
      return unless entity.valid?
      return if entity == @grabbed_entity
      return if dt <= 0
      p = body_props(entity)
      return if p[:m] > cf('push_max_mass').to_f

      pm    = cf('player_mass').to_f
      ratio = pm / (pm + p[:m])
      # Velocità del player sull'asse di spinta (m/s)
      vx_m = dx * IN_TO_M / dt
      vy_m = dy * IN_TO_M / dt
      jx = vx_m * p[:m] * ratio * 0.65
      jy = vy_m * p[:m] * ratio * 0.65

      b = entity.bounds
      # Braccio applicato all'altezza del bacino: la spinta fa anche ruotare
      rz = (@eye_z - @cur_h_m * M_TO_IN * 0.45) - (b.min.z + b.max.z) * 0.5
      apply_impulse(entity, jx, jy, 0.0, 0.0, 0.0, rz)
    rescue => fps_err; log_error(__method__, fps_err); nil; end

  end
end
