# DagaWASD — Materiali fisici: tabella, riconoscimento dal nome, massa e inerzia.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Proprietà fisiche dei corpi (massa, inerzia, materiale)
    # ══════════════════════════════════════════════════════════════

    def self.entity_label(entity)
      case entity
      when Sketchup::ComponentInstance
        n = entity.name.to_s
        n.empty? ? entity.definition.name.to_s : n
      when Sketchup::Group
        n = entity.name.to_s
        n.empty? ? (entity.definition.name.to_s rescue 'Group') : n
      else entity.class.name.to_s.split('::').last.to_s   # come typename, senza la sua lentezza
      end
    rescue => fps_err; log_error(__method__, fps_err); 'Oggetto'; end

    # ══════════════════════════════════════════════════════════════
    # Tabella materiali (modificabile dal pannello)
    # Ogni riga: id, name (solo righe utente), density, restitution,
    # friction, keywords ("a, b, c"), icon. Le righe predefinite hanno come
    # id la chiave del catalogo (legno, pietra…) e il nome tradotto mat.<id>.
    # ══════════════════════════════════════════════════════════════
    MAT_ICONS = %w[wood stone metal glass rubber ball box plastic cork ice foam generic].freeze
    MAT_DEFAULT_ICON = {
      'legno' => 'wood', 'pietra' => 'stone', 'metallo' => 'metal', 'vetro' => 'glass',
      'gomma' => 'rubber', 'pallone' => 'ball', 'cartone' => 'box', 'plastica' => 'plastic'
    }.freeze

    def self.default_materials
      MATERIALS.map do |id, m|
        { 'id' => id, 'name' => '', 'density' => m[:density], 'restitution' => m[:restitution],
          'friction' => m[:friction], 'keywords' => MAT_ALIASES[id].join(', '),
          'icon' => MAT_DEFAULT_ICON[id] || 'generic' }
      end
    end

    # Ripulisce una tabella arrivata dal pannello (o da settings.json).
    def self.sanitize_materials(rows)
      return nil unless rows.is_a?(Array)
      rows.first(64).filter_map do |r|
        next unless r.is_a?(Hash)
        id = r['id'].to_s.gsub(/[^\w\-]/, '')[0, 40]
        next if id.empty?
        { 'id'          => id,
          'name'        => r['name'].to_s.strip[0, 40],
          'density'     => r['density'].to_f.clamp(10.0, 20_000.0),
          'restitution' => r['restitution'].to_f.clamp(0.0, 0.98),
          'friction'    => r['friction'].to_f.clamp(0.0, 1.5),
          'keywords'    => r['keywords'].to_s[0, 400],
          'icon'        => MAT_ICONS.include?(r['icon'].to_s) ? r['icon'].to_s : 'generic' }
      end
    end

    def self.mat_table
      rows = sanitize_materials(@cfg['materials'])
      rows && !rows.empty? ? rows : default_materials
    end

    def self.mat_row(id)
      mat_table.find { |r| r['id'] == id }
    end

    # Nome da mostrare: tradotto per le righe predefinite, quello scritto
    # dall'utente per le sue.
    def self.mat_label(id)
      r = mat_row(id)
      return id.to_s unless r
      r['name'].to_s.empty? ? t("mat.#{id}") : r['name']
    end

    # Nomi dei materiali predefiniti in TUTTE le lingue (mat.<id> di ogni
    # file lang): un tedesco che chiama il materiale "Holz" o un giapponese
    # "木材" ottiene il legno senza toccare la tabella.
    # Ritorna id → [[nome, codice lingua], …].
    def self.all_lang_mat_names
      @all_mat_names ||= begin
        h = Hash.new { |x, k| x[k] = [] }
        lang_codes.each do |c|
          read_json(File.join(LANG_DIR, "#{c}.json")).each do |k, v|
            h[k[4..-1]] << [v.to_s.strip.downcase, c] if k.start_with?('mat.') && !v.to_s.strip.empty?
          end
        end
        h
      end
    end

    # Scritture senza spazi fra le parole (cinese, giapponese, thai): lì si
    # cerca la sottostringa; altrove la parola intera, così il turco "cam"
    # (vetro) non scatta dentro "camera". Il coreano usa gli spazi.
    NO_SPACE_SCRIPT = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}]/

    # Un nome tradotto vale in ogni lingua, tranne quelli brevi (< 4 lettere)
    # di lingue diverse da quella dell'interfaccia: il norvegese "tre"
    # (legno) o il turco "top" (pallone) sono parole comuni altrove.
    def self.mat_name_usable?(name, code)
      code == @lang_code || name.length >= 4 || name =~ NO_SPACE_SCRIPT
    end

    def self.word_in?(name, w)
      return name.include?(w) if w =~ NO_SPACE_SCRIPT
      name.match?(/(?<![[:alnum:]])#{Regexp.escape(w)}(?![[:alnum:]])/)
    end

    # Regole di riconoscimento compilate: [[id, parola, :sub|:word], …].
    # Parole chiave scritte nella tabella: sottostringa (come sempre);
    # nomi tradotti e nome delle righe utente: parola intera.
    def self.mat_matchers
      load_lang if @lang_code.nil?
      @mat_matchers ||= mat_table.flat_map do |r|
        list = r['keywords'].to_s.split(',').map { |w| [r['id'], w.strip.downcase, :sub] }
        extra = if r['name'].to_s.empty?
                  all_lang_mat_names[r['id']].select { |n, c| mat_name_usable?(n, c) }.map(&:first)
                else
                  [r['name'].strip.downcase]
                end
        list + extra.uniq.map { |w| [r['id'], w, :word] }
      end.reject { |_, w, _| w.empty? }
    end

    def self.invalidate_materials
      @mat_matchers = nil
      @facemat_cache = {}
    end

    # Materiale che copre la superficie maggiore delle facce di una
    # definizione (gruppi annidati compresi; una faccia senza materiale
    # eredita quello del gruppo che la contiene). Memorizzato per definizione.
    def self.dominant_face_material(defn)
      @facemat_cache ||= {}
      return @facemat_cache[defn] if @facemat_cache.key?(defn)
      area = Hash.new(0.0); count = 0
      walk = lambda do |ents, inherited, depth|
        return if depth > 6
        ents.each do |e|
          break if count > 5000
          case e
          when Sketchup::Face
            count += 1
            m = e.material || e.back_material || inherited
            area[m] += e.area if m
          when Sketchup::Group, Sketchup::ComponentInstance
            walk.call(e.definition.entities, e.material || inherited, depth + 1)
          end
        end
      end
      walk.call(defn.entities, nil, 0)
      @facemat_cache[defn] = area.max_by { |_, a| a }&.first
    rescue => fps_err
      log_error(__method__, fps_err)
      @facemat_cache[defn] = nil
    end

    # Deduce il materiale fisico. Nomi esaminati, in ordine:
    #   1. materiale applicato al gruppo/componente (dall'esterno)
    #   2. materiale che copre più superficie delle sue facce interne
    #   3. nome dell'istanza   4. nome della definizione
    # Il primo nome che contiene una parola nota decide; se ne contiene più
    # d'una vince la più lunga (più specifica), a parità l'ordine in tabella.
    def self.material_key(entity)
      names = []
      begin
        m = entity.material
        names << m.display_name.to_s if m
      rescue => fps_err; log_error(__method__, fps_err); end
      begin
        if entity.respond_to?(:definition)
          fm = dominant_face_material(entity.definition)
          names << fm.display_name.to_s if fm
        end
      rescue => fps_err; log_error(__method__, fps_err); end
      names << entity_label(entity).to_s
      begin
        names << entity.definition.name.to_s if entity.respond_to?(:definition)
      rescue => fps_err; log_error(__method__, fps_err); end
      rules = mat_matchers
      names.each do |nm|
        nm = nm.downcase
        next if nm.empty?
        best = nil
        rules.each do |id, w, mode|
          next unless mode == :sub ? nm.include?(w) : word_in?(nm, w)
          best = [id, w.length] if best.nil? || w.length > best[1]
        end
        return best[0] if best
      end
      nil
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Massa (kg), inerzia principale (kg·m²), restituzione, attrito e forma.
    # Il risultato è memorizzato per entità: la geometria non cambia.
    def self.body_props(entity)
      cached = @body_cache[entity]
      return cached if cached

      geo = geometry(entity)
      # Dimensioni proprie dell'oggetto (box orientato), non dell'AABB mondo:
      # un cubo afferrato mentre è ruotato non deve risultare più grande.
      ob = obb(entity)
      if ob
        sx = ob[:len][0] * IN_TO_M; sy = ob[:len][1] * IN_TO_M; sz = ob[:len][2] * IN_TO_M
      else
        b  = entity.bounds
        sx = (b.max.x - b.min.x) * IN_TO_M
        sy = (b.max.y - b.min.y) * IN_TO_M
        sz = (b.max.z - b.min.z) * IN_TO_M
      end
      sx = 0.02 if sx < 0.02; sy = 0.02 if sy < 0.02; sz = 0.02 if sz < 0.02

      key = cf('obj_use_materials') ? material_key(entity) : nil
      mat = key ? mat_row(key) : nil
      dens = mat ? mat['density'] : cf('obj_density').to_f
      # Solido chiuso: volume reale della mesh. Altrimenti l'ingombro,
      # che sovrastima il volume, corretto dal fattore di riempimento.
      mass = if geo && geo[:vol]
               geo[:vol] * (IN_TO_M**3) * dens
             else
               sx * sy * sz * dens * cf('obj_fill_ratio').to_f
             end
      mass = mass.clamp(0.2, 200_000.0)

      props = {
        m:    mass,
        im:   1.0 / mass,
        ix:   mass / 12.0 * (sy * sy + sz * sz),
        iy:   mass / 12.0 * (sx * sx + sz * sz),
        iz:   mass / 12.0 * (sx * sx + sy * sy),
        rest: (mat ? mat['restitution'] : cf('obj_bounce').to_f).clamp(0.0, 0.98),
        fric: (mat ? mat['friction']    : cf('obj_friction').to_f).clamp(0.0, 1.5),
        mat:  key,
        geo:  geo
      }
      @body_cache[entity] = props
      props
    rescue => fps_err
      log_error(__method__, fps_err)
      # In cache anche il ripiego: senza, l'errore si ripeterebbe a ogni tick
      @body_cache[entity] = { m: 10.0, im: 0.1, ix: 1.0, iy: 1.0, iz: 1.0,
        rest: cf('obj_bounce').to_f, fric: cf('obj_friction').to_f, mat: nil, geo: nil }
    end

    # Baricentro nel mondo (volume reale se disponibile, altrimenti centro).
    def self.com_world(entity)
      g = body_props(entity)[:geo]
      return g[:com].transform(entity.transformation) if g
      b = entity.bounds
      Geom::Point3d.new((b.min.x + b.max.x) * 0.5, (b.min.y + b.max.y) * 0.5, (b.min.z + b.max.z) * 0.5)
    rescue => fps_err
      log_error(__method__, fps_err)
      entity.bounds.center
    end

  end
end
