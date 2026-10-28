# DagaWASD — foto e galleria
# Fotografie mentre si gira: per chi cammina (tasto 'photo') e per
# l'esploratore (lib/explore.rb), che fotografa da sé le mete più
# interessanti del giro e scrive che cosa sono e perché le ha scelte; l'IA
# che lo guida (lib/expilot.rb) le chiede con "snap" e il suo perché.
# Ogni serie sta in una cartella accanto al modello (<modello>_foto/<data
# e ora>/, per un modello mai salvato in %APPDATA%/DagaWASD/foto): le foto
# JPG, galleria.json (per ogni foto chi, quando, dove, che cosa, perché; il
# giro in pianta) e galleria.html, la galleria da sfogliare nel browser,
# rifatta dallo stampo galleria.html a ogni apertura (nella lingua di
# adesso, col nome di adesso del percorso e i commenti dell'IA). Il percorso
# salvato tiene la sua cartella ('gallery': relativa alla cartella del
# modello quando ci sta dentro, così la si ritrova se il modello viaggia
# con le sue foto) e quante foto ('photos'); le serie senza percorso (foto
# fuori da una registrazione, giri non salvati, percorsi cancellati)
# compaiono a parte sotto l'elenco dei percorsi.
require 'fileutils'

module DagaWASD
  module FPSWalk
    GAL_W        = 1600   # px di larghezza della foto
    GAL_JPG      = 0.9    # qualità del JPG (0..1)
    GAL_MAX      = 30     # foto dell'esploratore in un giro, al più
    GAL_GAP      = 8.0    # s fra due sue foto, almeno
    GAL_OPEN_GAP = 45.0   # s fra due colpi d'occhio (spazi che si aprono)
    GAL_RANK     = 0.6    # solo mete più interessanti di questa parte di quelle viste
    GAL_FILL     = 0.22   # da lontano solo se la meta occupa almeno tanto del campo visivo
    GAL_SAME     = [1.5 * M_TO_IN, 30.0 * DEG].freeze   # da qui, guardando di qui, c'è già una foto
    GAL_TRACK    = 800    # punti del giro nella galleria, al più
    GAL_FLASH    = 0.3    # s del lampo dello scatto
    GAL_JSON     = 'galleria.json'
    GAL_HTML     = 'galleria.html'
    # nomi che SketchUp dà da sé: non dicono niente, meglio il materiale
    GAL_GENERIC  = /\A(?:gruppo|group|gruppe|groupe|grupo|groep|grupa|skupina|ryhmä|componente|component|komponente|composant|komponent)\s*#?\s*\d*(?:#\d+)?\z/i

    # ── Cartelle ──
    def self.gal_root(model = Sketchup.active_model)
      return @gal_root if @gal_root                # i test (e le prove dal vivo) ne danno un'altra
      p = model&.path.to_s.dup.force_encoding('UTF-8')
      p.empty? ? File.join(USER_DIR, 'foto') : File.join(File.dirname(p), "#{File.basename(p, '.*')}_foto")
    end

    # Una serie nuova (la cartella c'è da subito: la prima foto ci va dentro).
    # Accanto al modello non si può scrivere (cartella in sola lettura,
    # disco pieno): in %APPDATA%/DagaWASD/foto.
    def self.gal_new(model)
      base = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
      dir = nil
      [gal_root(model), gal_spare_root].uniq.each do |root|
        dir = File.join(root, base)
        n = 1
        dir = File.join(root, "#{base}_#{n += 1}") while File.exist?(dir)
        FileUtils.mkdir_p(dir)
        break
      rescue SystemCallError => fps_err
        log_error(__method__, fps_err)
        dir = nil
      end
      return nil unless dir
      { dir: dir, data: { 'v' => 1, 'model' => (model.title.to_s rescue ''), 'date' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
                          'path' => nil, 'photos' => [], 'track' => [] } }
    end

    def self.gal_spare_root; File.join(USER_DIR, 'foto'); end   # i test ne danno un'altra

    # La cartella della serie per il JSON del percorso: relativa alla
    # cartella del modello se ci sta dentro, se no com'è.
    def self.gal_ref(dir, model = Sketchup.active_model)
      md = gal_model_dir(model) or return dir
      d = File.expand_path(dir)
      pre = "#{md}/"
      d.downcase.start_with?(pre.downcase) ? d[pre.size..] : d
    end

    # E al contrario: la cartella di una serie dal JSON del percorso. Un
    # percorso assoluto che non c'è più (il modello spostato con le sue
    # foto) si cerca accanto al modello, con le ultime due parti.
    def self.gal_dir(ref, model = Sketchup.active_model)
      ref = ref.to_s
      return nil if ref.empty?
      md = gal_model_dir(model)
      abs = File.absolute_path?(ref) || ref.match?(%r{\A[A-Za-z]:[\\/]})
      cands = []
      cands << File.expand_path(ref) if abs
      if md
        cands << File.expand_path(ref, md) unless abs
        cands << File.join(md, *ref.tr('\\', '/').split('/').last(2))
      end
      cands.find { |c| File.file?(File.join(c, GAL_JSON)) } || cands.first
    end

    def self.gal_model_dir(model)
      p = model&.path.to_s.dup.force_encoding('UTF-8')
      p.empty? ? nil : File.expand_path(File.dirname(p))
    end

    def self.gal_save(gal)
      File.write(File.join(gal[:dir], GAL_JSON), JSON.generate(gal[:data]), mode: 'wb')
    end

    def self.gal_read(dir)
      JSON.parse(File.read(File.join(dir, GAL_JSON), encoding: 'UTF-8'))
    rescue SystemCallError, JSON::ParserError
      nil
    end

    # La vista di adesso in JPG, nella serie; info: chi, quando, che cosa,
    # perché. Ritorna la voce della foto, o nil se SketchUp non l'ha scritta.
    def self.gal_photo_w; GAL_W; end              # i test la vogliono piccola

    def self.gal_shoot(view, gal, info)
      vw = [view.vpwidth.to_f, 1.0].max
      vh = [view.vpheight.to_f, 1.0].max
      w = gal_photo_w
      h = (w * vh / vw).round.clamp(32, 2400)
      n = gal[:data]['photos'].size + 1
      name = format('foto_%03d.jpg', n)
      file = File.join(gal[:dir], name)
      ok = view.write_image(filename: file, width: w, height: h, antialias: true, compression: GAL_JPG,
                            transparent: false)
      return nil unless ok && File.exist?(file)
      c = view.camera
      e = c.eye
      d = c.direction
      ph = { 'n' => n, 'file' => name, 'w' => w, 'h' => h, 'clock' => Time.now.strftime('%H:%M:%S'),
             'pos' => [e.x, e.y, e.z].map { |v| (v * IN_TO_M).round(2) },
             'yaw' => (Math.atan2(d.y, d.x) / DEG).round(1) }.merge(info.compact)
      gal[:data]['photos'] << ph
      gal_save(gal)
      @gal_flash = Time.now.to_f
      ph
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    # Fine della serie: il percorso a cui appartiene (o nil) e il giro in
    # pianta, dai campioni del percorso [t, x, y, z, …] in pollici.
    def self.gal_finish(gal, name, samples)
      return unless gal
      s = samples.to_a
      step = [(s.size / GAL_TRACK.to_f).ceil, 1].max
      tr = (0...s.size).step(step).map { |i| s[i] }
      tr << s.last if s.size > 1 && !tr.last.equal?(s.last)
      gal[:data]['path'] = name
      gal[:data]['track'] = tr.map { |q| [(q[1] * IN_TO_M).round(2), (q[2] * IN_TO_M).round(2), q[0].to_f.round(1)] }
      gal_save(gal)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Per il JSON del percorso
    def self.gal_fields(gal, model = Sketchup.active_model)
      n = gal ? gal[:data]['photos'].size : 0
      n.positive? ? { 'gallery' => gal_ref(gal[:dir], model), 'photos' => n } : {}
    end

    # Il percorso ha cambiato nome: la serie lo sa (per quando resterà senza)
    def self.gal_renamed(data, name, model = Sketchup.active_model)
      dir = gal_dir(data && data['gallery'], model) or return
      d = gal_read(dir) or return
      d['path'] = name
      gal_save(dir: dir, data: d)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # ── Nomi e descrizioni ──
    def self.gal_name(label, obj = nil, mat = nil)
      l = label.to_s.strip
      return l unless l.empty? || l.match?(GAL_GENERIC)
      m = mat || (obj.respond_to?(:material) && obj.material) || gal_inner_material(obj)
      m ? m.display_name.to_s : l
    end

    # Il materiale più usato dalle facce di un gruppo o componente (le prime 200)
    def self.gal_inner_material(obj)
      return nil unless obj.respond_to?(:definition)
      ms = obj.definition.entities.grep(Sketchup::Face).first(200).filter_map(&:material)
      ms.empty? ? nil : ms.tally.max_by(&:last)[0]
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    def self.gal_num(v)
      v = v.to_f
      v >= 10 ? v.round.to_s : v.round(1).to_s
    end

    # Che cosa c'è al centro della vista (le foto di chi cammina)
    def self.gal_what_center(view)
      c = view.camera
      hit = Sketchup.active_model.raytest([c.eye, c.direction], true)
      return t('gal.what.view') unless hit
      path = hit[1].to_a
      lo = EX_OBJ[0] * M_TO_IN
      hi = EX_OBJ[1] * M_TO_IN
      obj = path.reverse.find do |e|
        (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.bounds.diagonal.to_f.between?(lo, hi)
      end
      # il materiale della faccia, o quello che le dà il gruppo che la contiene
      mat = path.reverse.map { |e| e.respond_to?(:material) ? e.material : nil }.compact.first
      dist = gal_num(c.eye.distance(hit[0]).to_f * IN_TO_M)
      if obj
        format(t('gal.what.obj'), label: gal_name(entity_label(obj), obj, mat), size: gal_num(obj.bounds.diagonal.to_f * IN_TO_M),
                                  dist: dist)
      else
        format(t('gal.what.face'), label: mat ? mat.display_name.to_s : t('explore.surface'), dist: dist)
      end
    rescue => fps_err
      log_error(__method__, fps_err)
      t('gal.what.view')
    end

    # Che cosa ha fotografato l'esploratore: la meta, e le cose più salienti
    # viste intorno (lib/expilot.rb le tiene in ex[:known]).
    def self.gal_what_target(ex, tgt, now)
      dist = gal_num(explore_dist_eye(ex, tgt[:pt]) * IN_TO_M)
      s = if tgt[:open] then t('gal.what.open')
          elsif tgt[:obj] then format(t('gal.what.obj'), label: gal_name(tgt[:label], tgt[:obj]),
                                                         size: gal_num(tgt[:size].to_f * IN_TO_M), dist: dist)
          else format(t('gal.what.face'), label: tgt[:label], dist: dist)
          end
      near = ex[:known].to_h.values.select { |k| k[:obj] && k[:last] && now - k[:last] < 1.5 && k[:id] != tgt[:id] }
      names = near.sort_by { |k| -k[:sal].to_f }.map { |k| gal_name(k[:label], k[:obj]) }
      names = (names.uniq - [gal_name(tgt[:label], tgt[:obj])]).first(3)
      names.empty? ? s : "#{s} #{format(t('gal.what.around'), list: names.join(', '))}"
    end

    # Perché: la meta era la più interessante del giro o fra le più
    # interessanti, e che cosa la faceva spiccare (le parti più forti della
    # salienza della sua cella migliore: explore_saliency, :why).
    def self.gal_why_target(tgt, best)
      out = [best ? t('gal.why.best') : t('gal.why.top')]
      p = tgt[:why]
      if p
        txt = [t('gal.why.shape'), t('gal.why.shape'), t('gal.why.detail'), t('gal.why.color'), t('gal.why.rare'),
               t('gal.why.complex')]
        top = p.max.to_f
        (0...p.size).sort_by { |i| -p[i] }.first(2).each do |i|
          out << txt[i] if p[i].positive? && p[i] >= 0.7 * top && !out.include?(txt[i])
        end
      end
      out.join(' ')
    end

    # ── Chi cammina: il tasto 'photo' (lib/tick.rb) ──
    # Durante una registrazione la foto va col percorso; se no in una serie
    # tutta sua, una per ogni volta che si entra nella modalità.
    def self.gal_human(view, now)
      r = @path_rec
      model = Sketchup.active_model
      gal = r ? (r[:gal] ||= gal_new(model)) : (@gal_loose ||= gal_new(model))
      info = { 'by' => 'you', 'what' => gal_what_center(view) }
      info['t'] = (now - r[:t0]).round(2) if r
      ph = gal && gal_shoot(view, gal, info)
      Sketchup.status_text = ph ? format(t('rt.photo'), n: ph['n']) : t('rt.photo_err')
      ph
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    # Lampo dello scatto (lib/tool.rb, sopra la vista): bianco che svanisce
    def self.gal_flash
      return nil unless @gal_flash
      a = 1.0 - (Time.now.to_f - @gal_flash) / GAL_FLASH
      return (@gal_flash = nil) if a <= 0.0
      a
    end

    # ── L'esploratore ──
    def self.gal_ex_init(ex)
      ex.merge!(gal: nil, snap_want: nil, snaps: ex[:o]['record'] || @gal_always ? true : false,
                gal_st: { n: 0, t: -1e9, open_t: -1e9, scores: [], ids: [], poses: [] })
    end

    # Una meta si fotografa quando lo sguardo ci si posa e la vista ne è
    # piena abbastanza (anche da lontano, o durante lo zoom), o all'arrivo
    # (pilot_arrived): molte mete si guardano e si lasciano senza arrivarci.
    # Le mete dell'IA solo se le ha dato un perché ("snap"); le altre se sono
    # fra le più interessanti viste finora, non troppo presto dopo l'ultima
    # foto e non da dove si è già fotografato; gli spazi aperti ogni tanto.
    def self.gal_sight(ex, now)
      tgt = ex[:target]
      return unless ex[:snaps] && tgt && !tgt[:ai] && !tgt[:open] && !tgt[:arrived] && !tgt[:gal_sight] && tgt[:vis]
      return if explore_aim_err(ex, tgt[:pt]) > EX_PHOTO_AIM
      d = [explore_dist_eye(ex, tgt[:pt]), 1.0].max
      return if 2.0 * Math.atan(tgt[:size].to_f / 2.0 / d) / DEG < GAL_FILL * ex[:fov].to_f
      tgt[:gal_sight] = true
      gal_consider(ex, tgt, now)
    end

    def self.gal_consider(ex, tgt, now)
      return unless ex[:snaps] && !ex[:snap_want]
      g = ex[:gal_st]
      what = nil
      if (it = tgt[:ai])
        return unless it[:snap]
        by = 'ai'
        why = it[:snap]
        what = it[:say]
      else
        return if g[:n] >= GAL_MAX || now - g[:t] < GAL_GAP || tgt[:front]
        if tgt[:open]
          return if now - g[:open_t] < GAL_OPEN_GAP
          why = t('gal.why.open')
        else
          return if g[:ids].include?(tgt[:id])
          sc = tgt[:score].to_f
          hist = g[:scores]
          if (old = tgt[:gal_rank])                  # vista prima, ora raggiunta: conta una volta
            k = hist.rindex(old)
            hist.delete_at(k) if k
          end
          best = hist.empty? || sc > hist.max
          rank = hist.count { |v| v < sc }.to_f / [hist.size, 1].max
          hist << sc
          tgt[:gal_rank] = sc
          return unless best || rank >= GAL_RANK
          why = gal_why_target(tgt, best && hist.size > 1)
        end
        by = 'explorer'
      end
      return if by != 'ai' && gal_seen_here?(ex)    # l'IA l'ha chiesta: si scatta comunque
      ex[:snap_want] = { tgt: tgt, by: by, why: why, what: what, t: now, sight: !tgt[:arrived] }
      tgt[:photo_hold] = true if tgt[:arrived]
    end

    def self.gal_seen_here?(ex)
      ex[:gal_st][:poses].any? do |x, y, yaw|
        Math.hypot(ex[:x] - x, ex[:y] - y) < GAL_SAME[0] && explore_wrap(ex[:yaw] - yaw).abs < GAL_SAME[1]
      end
    end

    # A ogni fotogramma, dopo la camera: lo scatto aspetta che la meta sia
    # nella vista, come la foto per l'IA (pilot_photo_tick). Senza meta
    # (l'IA: "snap" adesso) si scatta subito.
    def self.gal_tick(view, ex, now)
      gal_sight(ex, now) unless ex[:snap_want]
      w = ex[:snap_want] or return
      tgt = w[:tgt]
      if tgt
        unless ex[:target].equal?(tgt)
          ex[:snap_want] = nil                     # la meta è cambiata prima della foto
          return
        end
        unless w[:sight]                           # da lontano: subito, lo sguardo c'è già
          return if !tgt[:arrived] || explore_orbiting?(tgt) || explore_zooming?(ex)
          return if explore_aim_err(ex, tgt[:pt]) > EX_PHOTO_AIM && now - tgt[:arrived] < EX_PHOTO_SETTLE
        end
      end
      ex[:snap_want] = nil
      tgt[:photo_hold] = nil if tgt && !ex[:photo_want]
      gal_snap(view, ex, w, now)
    end

    def self.gal_snap(view, ex, w, now)
      ex[:gal] ||= gal_new(ex[:model])
      return pilot_event(ex, 'snap', 'error' => 'nessuna cartella dove scrivere le foto') unless ex[:gal]
      tgt = w[:tgt]
      what = w[:what] || (tgt ? gal_what_target(ex, tgt, now) : gal_what_center(view))
      info = { 'by' => w[:by], 't' => ex[:t].round(2), 'what' => what, 'why' => w[:why].to_s,
               'title' => tgt && !tgt[:open] ? gal_name(tgt[:label], tgt[:obj]) : nil }
      ph = gal_shoot(view, ex[:gal], info)
      return pilot_event(ex, 'snap', 'error' => 'write_image non ha scritto la foto') unless ph
      g = ex[:gal_st]
      g[:n] += 1 if w[:by] == 'explorer'
      g[:t] = now
      g[:open_t] = now if tgt && tgt[:open]
      g[:ids] << tgt[:id] if tgt
      g[:poses] << [ex[:x], ex[:y], ex[:yaw]]
      pilot_event(ex, 'snap', { 'n' => ph['n'], 'by' => w[:by], 'id' => tgt && (tgt[:ai] ? tgt[:ai][:id] : ex[:kid][tgt[:id]]),
                                'file' => File.join(ex[:gal][:dir], ph['file']) }.compact)
    rescue => fps_err                                # una foto che non riesce non ferma il giro
      log_error(__method__, fps_err)
      nil
    end

    # ── Galleria ──
    # Testi della pagina (galleria.html li prende da qui, nella lingua di adesso)
    GAL_TXT = { 'what' => 'gal.what', 'why' => 'gal.why', 'hint' => 'gal.hint', 'hint_table' => 'gal.hint.table',
                'count' => 'gal.count', 'route' => 'gal.route', 'you' => 'gal.by_you', 'explorer' => 'gal.by_explorer',
                'ai' => 'gal.by_ai', 'strip' => 'gal.view.strip', 'table' => 'gal.view.table', 'tidy' => 'gal.tidy',
                'play' => 'gal.play', 'all' => 'gal.all', 'said' => 'gal.said', 'end' => 'gal.end', 'dur' => 'gal.dur',
                'dist' => 'gal.dist' }.freeze

    # La pagina dallo stampo, con i dati dentro; ritorna il suo file. notes:
    # i commenti dell'IA lungo il percorso ([[t, testo]], lib/path.rb).
    def self.gal_report(dir, title, notes = [])
      data = gal_read(dir) or return nil
      tpl = File.read(File.join(PLUGIN_DIR, GAL_HTML), encoding: 'UTF-8')
      page = { 'id' => File.basename(dir), 'title' => title.to_s, 'model' => data['model'].to_s, 'date' => data['date'].to_s,
               'photos' => data['photos'].to_a, 'track' => data['track'].to_a, 'notes' => notes.to_a,
               'lang' => @lang_code.to_s, 'rtl' => !!@lang_rtl, 'txt' => GAL_TXT.transform_values { |k| t(k) } }
      json = JSON.generate(page).gsub('</', '<\/')
      file = File.join(dir, GAL_HTML)
      File.write(file, tpl.sub('/*DATI*/null') { json }, mode: 'wb')
      file
    end

    def self.gal_open(dir, title, notes = [])
      return format(t('gal.missing'), dir: dir) unless dir && File.file?(File.join(dir, GAL_JSON))
      file = gal_report(dir, title, notes) or return format(t('gal.missing'), dir: dir)
      UI.openURL(gal_url(file))
      nil
    end

    # file:/// con i caratteri che non vanno in un indirizzo in %XX (spazi, accenti)
    def self.gal_url(file)
      path = File.expand_path(file).tr('\\', '/')
      enc = path.b.gsub(%r{[^A-Za-z0-9/:._~-]}n) { |c| format('%%%02X', c.ord) }
      "file:///#{enc.sub(%r{\A/+}, '')}"
    end

    # Le serie della cartella del modello che nessun percorso tiene: le più
    # recenti prima, al più 30 (per il pannello: id = nome della cartella).
    def self.gal_loose(model = Sketchup.active_model)
      root = gal_root(model)
      return [] unless File.directory?(root)
      used = (path_dict(model)&.keys || []).filter_map { |k| (d = path_data(k, model)) && gal_dir(d['gallery'], model) }
                                         .map { |d| File.expand_path(d).downcase }
      Dir.children(root).sort.reverse.lazy.filter_map do |c|
        dir = File.join(root, c)
        next if used.include?(File.expand_path(dir).downcase)
        d = File.file?(File.join(dir, GAL_JSON)) && gal_read(dir) or next
        n = d['photos'].to_a.size
        { 'id' => c, 'n' => n, 'date' => d['date'].to_s, 'was' => d['path'] } if n.positive?
      end.first(30)
    rescue => fps_err
      log_error(__method__, fps_err)
      []
    end

    # La galleria di un percorso; senza foto, come farne.
    def self.gal_open_path(name)
      d = path_data(name) or return t('path.missing')
      return format(t('gal.none'), key: key_label('photo')) if d['gallery'].to_s.empty? || d['photos'].to_i.zero?
      gal_open(gal_dir(d['gallery']), name, path_notes(d))
    end

    def self.gal_open_loose(id)
      return nil if id.to_s.empty? || id.include?('/') || id.include?('\\') || id.start_with?('.')
      dir = File.join(gal_root, id)
      d = gal_read(dir)
      gal_open(dir, d && d['path'] ? d['path'] : "#{t('path.loose')} — #{d ? d['date'] : id}")
    end

  end
end
