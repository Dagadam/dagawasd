# DagaWASD — Pilota dell'esploratore: l'IA collegata al ponte guarda e guida.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Pilota dell'esploratore autonomo (lib/explore.rb)
    #
    # Due velocità. L'IA ragiona in secondi, l'esploratore decide due volte
    # al secondo e disegna a 30 fotogrammi: l'IA non entra mai nel passo.
    # Dà intenzioni; sguardo, passi, giri attorno ai muri, determinazione e
    # continuità restano dell'esploratore, che non aspetta mai l'IA.
    #
    #   cose viste  ogni oggetto (e le facce più salienti) che passa nella
    #               retina entra in un elenco con un nome corto e stabile
    #               (o12 oggetto, s7 faccia, F3 zona inesplorata): l'IA
    #               indica quelli, non coordinate
    #   agenda      coda di intenzioni: vai a, guarda, vai a un punto; la
    #               prima diventa l'obiettivo, con la stessa scelta di sempre
    #               (explore_aim), e non la si cambia finché non è fatta.
    #               Agenda vuota: l'esploratore sceglie da solo, come prima
    #   gusti       pesi morbidi su cose, nomi, frontiere, spazio aperto:
    #               orientano le scelte proprie senza dare ordini
    #   avvisi      ciò che l'IA deve sapere (arrivato, fatto, agenda quasi
    #               vuota, una cosa notevole mai vista), numerati: il client
    #               chiede quelli dopo l'ultimo che ha letto (una cosa notevole
    #               al più ogni EX_NOTABLE_GAP s); una meta che non
    #               si raggiunge lo dice ogni tanto (slow), poi si lascia
    #   a piedi     per ogni cosa, se ci si arriva camminando e con quanti
    #               metri di strada (sulla pianta di adesso): l'IA non sceglie
    #               mete che l'esploratore non può raggiungere
    #   commenti    ciò che l'IA dice entra nel diario
    #   foto        nelle soste, un'immagine della vista con il nome corto
    #               scritto accanto a ogni cosa visibile (avviso photo)
    #   galleria    le foto belle, senza segni, con che cosa e perché
    #               (lib/gallery.rb): "snap" in una voce o subito (avviso snap)
    #
    # Il ponte: GET /explore/percept?since=N[&n=20][&brief=1] (descrizione
    # e avvisi), GET /explore/wait?since=N[&timeout=25][&run=…] (la stessa
    # descrizione, ma solo quando c'è un avviso che sveglia: il ponte tiene
    # la richiesta in sospeso), POST /explore {"cmd": "steer", "opts": {…}}
    # (guida). Il client per Claude Code è tools/esplora.rb (pilota, guida).
    # Direzioni: bearing_deg rispetto allo sguardo, + a sinistra, − a destra.
    # ══════════════════════════════════════════════════════════════
    EX_KNOWN_MAX   = 400     # cose ricordate al più (poi via le viste da più tempo)
    EX_FKNOWN_MAX  = 150     # zone inesplorate ricordate al più
    EX_KNOWN_SURF  = 5       # facce sciolte registrate per analisi: le più salienti
    EX_KNOWN_SURF_MIN = 0.12 # e solo se spiccano almeno così (pareti e pavimenti no)
    EX_NOTABLE     = 0.6     # salienza di una cosa mai vista (e di un tipo mai visto) che merita un avviso
    EX_NOTABLE_GAP = 8.0     # s: al più un avviso notable ogni tanto (il più saliente)
    EX_EVENTS_MAX  = 150
    EX_AGENDA_MAX  = 8
    EX_LIKE_RANGE  = [0.0, 5.0].freeze
    EX_AVOID       = 0.15    # «evita»: il fascino si riduce a tanto
    EX_PILOT_PATIENCE = 1.5  # una meta dell'IA si insegue per attention × tanto
    EX_PILOT_SLOW  = 12.0    # s: ogni tanto, se non ci si arriva, l'IA lo sa (avviso slow)
    EX_PILOT_LOOK  = 2.5     # s: «guarda» senza durata
    EX_PERCEPT_N   = [20, 80].freeze   # cose descritte: quante di solito, al più
    EX_REACH_WALK  = 40.0 * M_TO_IN    # a piedi: strade cercate fin qui (di cammino)
    EX_REACH_NODES = 4000    # celle esaminate al più; oltre, ciò che non si è trovato è «non so»
    EX_REACH_FRESH = 3.0     # s: la ricerca di prima vale ancora (spostati di poche celle; su Stromboli 0,2 s)
    # avvisi che svegliano il pilota (gli altri sono solo cronaca)
    EX_PILOT_WAKE  = %w[agenda_low agenda_empty arrived done rejected notable slow photo].freeze
    EX_PHOTOS      = %w[ai all off].freeze
    EX_PHOTO_W     = 800     # px di larghezza delle foto (l'altezza segue la vista)
    EX_PHOTO_AIM   = 4.0 * DEG   # si scatta con lo sguardo entro tanto dalla meta…
    EX_PHOTO_SETTLE = 1.5    # …o dopo tanti secondi di sosta comunque
    EX_PHOTO_FAR   = 80.0 * M_TO_IN  # più lontano non si segna
    EX_PHOTO_MARKS = 18      # segni al più
    EX_PHOTO_KEEP  = 40      # foto tenute nella cartella (di tutti i giri)
    EX_PHOTO_FONT  = 2       # lato in px di un punto del carattere 5×7
    # [sfondo, testo] dei cartellini
    EX_PHOTO_COLORS = { target: [[255, 209, 102], [0, 0, 0]], obj: [[25, 45, 110], [255, 255, 255]],
                        surf: [[70, 70, 70], [255, 255, 255]], front: [[120, 60, 170], [255, 255, 255]],
                        far: [[205, 205, 205], [95, 95, 95]] }.freeze   # far: a piedi non ci si arriva
    # carattere 5×7, solo ciò che serve ai nomi corti
    EX_GLYPHS = {
      '0' => %w[.###. #...# #..## #.#.# ##..# #...# .###.], '1' => %w[..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.],
      '2' => %w[.###. #...# ....# ...#. ..#.. .#... #####], '3' => %w[##### ...#. ..#.. ...#. ....# #...# .###.],
      '4' => %w[...#. ..##. .#.#. #..#. ##### ...#. ...#.], '5' => %w[##### #.... ####. ....# ....# #...# .###.],
      '6' => %w[..##. .#... #.... ####. #...# #...# .###.], '7' => %w[##### ....# ...#. ..#.. .#... .#... .#...],
      '8' => %w[.###. #...# #...# .###. #...# #...# .###.], '9' => %w[.###. #...# #...# .#### ....# ...#. .##..],
      'o' => %w[..... ..... .###. #...# #...# #...# .###.], 's' => %w[..... ..... .#### #.... .###. ....# ####.],
      'F' => %w[##### #.... #.... ####. #.... #.... #....]
    }.freeze

    def self.pilot_init(ex)
      ex.merge!(known: {}, ksid: {}, fknown: {}, kid: {}, kseq: Hash.new(0), agenda: [], ag_seq: 0,
                kinds: {}, notable_t: -1e9, likes: {}, events: [], ev_seq: 0, says: [], run: format('%08x', rand(2**32)),
                photos: 'ai', photo_ask: false, photo_want: nil, photo: nil, photo_n: 0, steering: false, steered: false)
    end

    # Il nome corto di una cosa (o di una zona) dal suo nome lungo; lo stesso per sempre.
    def self.pilot_sid(ex, ident, prefix)
      ex[:kid][ident] ||= "#{prefix}#{ex[:kseq][prefix] += 1}"
    end

    # Gli avvisi nati da uno steer (una meta lasciata perché l'IA ha cambiato
    # agenda, saltata) hanno from_steer: l'IA li ha causati, non la svegliano.
    def self.pilot_event(ex, type, data = {})
      ev = ex[:events]
      data = data.merge('from_steer' => true) if ex[:steering]
      ev << { 'n' => (ex[:ev_seq] += 1), 't' => ex[:t].round(1), 'type' => type }.merge(data)
      ev.shift while ev.size > EX_EVENTS_MAX
    end

    # ── Cose viste: dai candidati di un'analisi, prima dei pesi della scelta
    # (la salienza è quanto spiccano, non quanto attirano adesso) ──
    def self.pilot_seen(ex, cands, now)
      step = ex[:steps]
      surf = 0
      best = nil
      cands.each do |c|
        if c[:front]
          sid = pilot_sid(ex, c[:id], 'F')
          ex[:fknown][sid] = { f: c[:front], t: now }
          c[:sid] = sid
          next
        end
        next if c[:open]
        next if !c[:obj] && (c[:score] < EX_KNOWN_SURF_MIN || (surf += 1) > EX_KNOWN_SURF)   # già in ordine di salienza
        k = ex[:known][c[:id]]
        unless k
          sid = pilot_sid(ex, c[:id], c[:obj] ? 'o' : 's')
          k = ex[:known][c[:id]] = { sid: sid, id: c[:id], label: c[:label], kind: c[:kind], obj: c[:obj],
                                     opath: c[:opath], first: now, seen: 0, sal_max: 0.0, size: pilot_size(c) }
          ex[:ksid][sid] = c[:id]
          # la prima di un tipo (stessa definizione); all'avvio tutto è nuovo: dalla terza analisi
          first = c[:obj] && !ex[:kinds].key?(c[:kind])
          best = c if first && step > 2 && c[:score] >= EX_NOTABLE && (best.nil? || c[:score] > best[:score])
        end
        ex[:kinds][c[:kind]] = true if c[:obj]
        k[:pt] = c[:pt].dup
        k[:last] = now
        k[:step] = step
        k[:sal] = c[:score]
        k[:sal_max] = c[:score] if c[:score] > k[:sal_max]
        k[:seen] += 1
        c[:sid] = k[:sid]
      end
      if best && now - ex[:notable_t] >= EX_NOTABLE_GAP
        ex[:notable_t] = now
        pilot_event(ex, 'notable', 'id' => best[:sid], 'label' => best[:label], 'salience' => best[:score].round(2))
      end
      pilot_prune(ex)
    end

    def self.pilot_size(c)
      return nil unless c[:obj] && c[:opath]
      bb = explore_world_box(c[:opath])
      ([bb.max.z - bb.min.z, Math.hypot(bb.max.x - bb.min.x, bb.max.y - bb.min.y)].max * IN_TO_M).round(2)
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    def self.pilot_prune(ex)
      kn = ex[:known]
      if kn.size > EX_KNOWN_MAX
        busy = ex[:agenda].map { |i| ex[:ksid][i[:id]] }
        kn.values.sort_by { |k| k[:last] }.first(kn.size - EX_KNOWN_MAX * 9 / 10).each do |k|
          next if busy.include?(k[:id])
          kn.delete(k[:id])
          ex[:ksid].delete(k[:sid])
        end
      end
      fk = ex[:fknown]
      return if fk.size <= EX_FKNOWN_MAX
      busy = ex[:agenda].map { |i| i[:id] }
      fk.keys.sort_by { |s| fk[s][:t] }.first(fk.size - EX_FKNOWN_MAX * 9 / 10).each { |s| fk.delete(s) unless busy.include?(s) }
      ex[:kid].delete_if { |_, s| s.start_with?('F') && !fk.key?(s) }
    end

    # ── Gusti: un fattore sul fascino di un candidato ──
    def self.pilot_like_f(ex, c)
      lk = ex[:likes]
      return 1.0 if lk.empty?
      f = 1.0
      sid = c[:sid] || ex[:kid][c[:id]]
      f *= lk[sid] if sid && lk[sid]
      f *= lk['frontier'] if c[:front] && lk['frontier']
      f *= lk['open'] if c[:open] && !c[:front] && lk['open']
      lab = c[:label].to_s.downcase
      lk.each { |k, v| f *= v if k.start_with?('label:') && lab.include?(k[6..]) }
      f
    end

    # ── Agenda ──
    # Una voce dal JSON dell'IA: [voce, nil] o [nil, perché no].
    #   {"go": "o12"}  {"look": "o12", "for": 3}  {"go": "F3"}  {"to": [x, y, z]} (m)
    #   e per tutte: "dwell" (s di sosta), "orbit" (° di giro attorno), "say" (commento all'arrivo),
    #   "snap" (all'arrivo una foto per la galleria: il testo è il perché; say è il che cosa)
    def self.pilot_item(ex, h)
      return [nil, 'atteso un oggetto, es. {"go": "o12"}'] unless h.is_a?(Hash)
      it = { n: (ex[:ag_seq] += 1) }
      if (id = h['look'] || h['go'])
        id = id.to_s
        it[:act] = h['look'] ? :look : :go
        if id.start_with?('F')
          return [nil, "zona inesplorata sconosciuta: #{id}"] unless ex[:fknown][id]
          it[:act] = :go
        else
          k = ex[:known][ex[:ksid][id]] or return [nil, "cosa sconosciuta: #{id}"]
          return [nil, "#{id} non c'è più nel modello"] if k[:obj] && !k[:obj].valid?
        end
        if it[:act] == :go && pilot_reach_of(ex, id)&.first == 'no'
          return [nil, "a piedi non ci si arriva: nessuna strada fino a #{id} sulla pianta di adesso (entro " \
                       "#{(EX_REACH_WALK * IN_TO_M).round} m di cammino); scegli altro, o guardalo da qui con look"]
        end
        it[:id] = id
      elsif (p = h['to'])
        v = p.is_a?(Array) && p.size == 3 ? p.map { |x| explore_num(x) } : []
        return [nil, "to: attesi tre numeri in metri, non #{p.inspect}"] unless v.size == 3 && v.all?
        it[:act] = :to
        it[:id] = "p#{it[:n]}"
        it[:pt] = v.map { |x| x * M_TO_IN }
      else
        return [nil, "manca go, look o to: #{JSON.generate(h)[0, 80]}"]
      end
      d = explore_num(h['dwell'] || h['for'])
      it[:dwell] = d.clamp(0.0, 60.0) if d
      o = explore_num(h['orbit'])
      it[:orbit] = o.clamp(0.0, 360.0) if o
      it[:say] = h['say'].to_s.strip[0, 500] if h['say'] && !h['say'].to_s.strip.empty?
      it[:snap] = h['snap'].to_s.strip[0, 500] if h['snap'] && !h['snap'].to_s.strip.empty?
      [it, nil]
    end

    def self.pilot_item_json(ex, it)
      j = { 'act' => it[:act].to_s, 'id' => it[:id] }
      if (k = ex[:known][ex[:ksid][it[:id]]])
        j['label'] = k[:label]
      elsif it[:pt]
        j['to_m'] = it[:pt].map { |v| (v * IN_TO_M).round(2) }
      end
      j['dwell'] = it[:dwell] if it[:dwell]
      j['orbit'] = it[:orbit] if it[:orbit]
      j['say'] = it[:say] if it[:say]
      j['snap'] = it[:snap] if it[:snap]
      j['state'] = ex[:target] && ex[:target][:ai].equal?(it) ? (ex[:target][:arrived] ? 'arrived' : 'going') : 'waiting'
      j
    end

    # Il candidato di una voce, come se l'avesse scelto l'esploratore; nil se non si può più.
    def self.pilot_cand(ex, it)
      if it[:act] == :to
        return { id: it[:id], kind: nil, pt: it[:pt].dup, score: 0.5, area: 0.0, cell: nil,
                 label: "→ #{it[:pt].map { |v| format('%.1f', v * IN_TO_M) }.join(', ')}",
                 obj: nil, opath: nil, open: true, ai: it }
      end
      if it[:id].start_with?('F')
        fk = ex[:fknown][it[:id]] or return nil
        return nil unless ex[:mode] == :walk
        return explore_front_cand(ex, fk[:f]).merge(ai: it)
      end
      k = ex[:known][ex[:ksid][it[:id]]] or return nil
      return nil if k[:obj] && !k[:obj].valid?
      { id: k[:id], kind: k[:kind], pt: k[:pt].dup, score: k[:sal] || 0.5, area: 0.0, cell: nil, label: k[:label],
        obj: k[:obj], opath: k[:opath], open: false, ai: it }
    end

    # A ogni analisi, prima della scelta: se c'è una voce in attesa e
    # l'obiettivo di adesso non è dell'IA, la prima voce diventa l'obiettivo.
    # La sosta davanti a un obiettivo proprio (e lo zoom) finisce prima.
    def self.pilot_next(ex, now)
      ag = ex[:agenda]
      cur = ex[:target]
      return if ag.empty? || (cur && (cur[:ai] || cur[:arrived] || explore_zooming?(ex)))
      until ag.empty?
        it = ag.first
        c = pilot_cand(ex, it)
        if c
          explore_aim(ex, c, now)
          tgt = ex[:target]
          tgt[:dwell] = it[:dwell] if it[:dwell]
          tgt[:orbit_deg] = it[:orbit] if it[:orbit]
          pilot_event(ex, 'started', 'id' => it[:id], 'act' => it[:act].to_s, 'label' => tgt[:label],
                                     'dist_m' => (explore_dist_eye(ex, tgt[:pt]) * IN_TO_M).round(2))
          # quasi finita, ma non se è l'IA ad averla appena data così
          pilot_event(ex, 'agenda_low', 'left' => ag.size) if ag.size <= 1 && !ex[:steered]
          ex[:steered] = false
          if it[:act] == :look                   # guardare: si resta dove si è
            tgt[:dwell] = it[:dwell] || EX_PILOT_LOOK
            tgt[:zoom] = nil
            tgt[:arrived] = now
            explore_route_drop(ex)
            pilot_arrived(ex, tgt, now)
          end
          return
        end
        ag.shift
        pilot_event(ex, 'rejected', 'id' => it[:id], 'why' => 'non più raggiungibile da qui')
        pilot_event(ex, 'agenda_empty') if ag.empty?
      end
    end

    # Una meta dell'IA che non si raggiunge: ogni EX_PILOT_SLOW s un avviso,
    # con la distanza e quante volte il percorso si è dovuto rifare.
    def self.pilot_watch(ex, tgt, now)
      it = tgt[:ai] or return
      t = (tgt[:slow_t] ||= tgt[:since] + EX_PILOT_SLOW)
      return if now < t || tgt[:arrived]
      tgt[:slow_t] = now + EX_PILOT_SLOW
      pilot_event(ex, 'slow', 'id' => it[:id], 'label' => tgt[:label], 'seconds' => (now - tgt[:since]).round,
                              'dist_m' => (explore_dist_eye(ex, tgt[:pt]) * IN_TO_M).round(2), 'replans' => ex[:replans])
    end

    # Arrivati (alle mete proprie e a quelle dell'IA): forse una foto, che
    # trattiene la sosta finché non è fatta; per le mete dell'IA l'avviso e
    # il commento. Con la foto in arrivo, l'avviso arrived non sveglia: sveglia photo.
    def self.pilot_arrived(ex, tgt, now)
      it = tgt[:ai]
      gal_consider(ex, tgt, now)                 # lib/gallery.rb: una foto per la galleria?
      photo = pilot_photo_want?(ex, tgt)
      if photo
        ex[:photo_ask] = false
        ex[:photo_want] = { tgt: tgt, id: it ? it[:id] : ex[:kid][tgt[:id]], t: now }
        tgt[:photo_hold] = true
      end
      return unless it
      pilot_event(ex, 'arrived', { 'id' => it[:id], 'label' => tgt[:label],
                                   'dist_m' => (explore_dist_eye(ex, tgt[:pt]) * IN_TO_M).round(2),
                                   'photo' => photo || nil }.compact)
      pilot_say(ex, it[:say], it[:id]) if it[:say]
    end

    # Una voce finita (raggiunta e guardata, o lasciata): fuori dall'agenda.
    def self.pilot_done(ex, tgt, why, _now)
      it = tgt[:ai] or return
      ag = ex[:agenda]
      ag.delete_if { |i| i.equal?(it) }
      pilot_event(ex, 'done', 'id' => it[:id], 'label' => tgt[:label], 'why' => why)
      pilot_event(ex, 'agenda_empty') if ag.empty?
    end

    # Il commento resta anche nel percorso registrato (explore_save_path):
    # descrizione delle scene e sottotitoli del video (lib/path.rb).
    # Lo stesso commento due volte nello stesso giro no (l'IA a volte lo
    # rimette in una voce nuova).
    def self.pilot_say(ex, text, id = nil)
      text = text.to_s[0, 500]
      return if ex[:says].any? { |_, s| s.strip.casecmp?(text.strip) }
      ex[:says] << [ex[:t].round(2), text]
      explore_log(ex, nil, 'commento')
      e = ex[:log].last
      e['label'] = text
      e['id'] = id if id
      pilot_event(ex, 'said', 'text' => text)
    end

    # ── Comando «steer» (POST /explore) ──
    #   agenda: [voci]  sostituisce l'agenda (la voce in corso resta se è la prima)
    #   add: [voci]     in coda
    #   clear: true     agenda vuota, si torna a scegliere da soli
    #   skip: true      lascia l'obiettivo di adesso
    #   like: {"o12": 2, "label:altare": 1.5, "frontier": 2, "open": 0.5, "o3": null}
    #   avoid: ["o3"]   like = 0,15
    #   likes_clear: true
    #   say: "testo"    un commento nel diario
    #   photo: true     una foto alla sosta di adesso, o alla prossima
    #   snap: "perché"  una foto per la galleria, adesso (say, se c'è, dice che cosa)
    #   photos: "ai" | "all" | "off"   quando si fanno da sole
    def self.pilot_steer(ex, o, now)
      ex[:steering] = true
      pilot_steer_do(ex, o, now)
    ensure
      ex[:steering] = false
    end

    def self.pilot_steer_do(ex, o, now)
      o = {} unless o.is_a?(Hash)
      ex[:steered] = true if o['clear'] || o.key?('agenda') || o.key?('add')
      rej = []
      parse = lambda do |list|
        Array(list).filter_map do |h|
          it, err = pilot_item(ex, h)
          rej << { 'item' => h, 'why' => err } if err
          it
        end
      end
      cur = ex[:target]
      running = cur && cur[:ai]
      if o['clear'] || o.key?('agenda')
        items = parse.(o['agenda'])
        if running && items.first && items.first[:id] == running[:id] && items.first[:act] == running[:act]
          items[0] = running                     # la stessa: si continua, senza ricominciare
        elsif running
          pilot_abort(ex, now)
        end
        ex[:agenda] = items
      end
      if o.key?('add')
        ex[:agenda].concat(parse.(o['add']))
      end
      if ex[:agenda].size > EX_AGENDA_MAX
        ex[:agenda].pop(ex[:agenda].size - EX_AGENDA_MAX).each { |it| rej << { 'item' => it[:id], 'why' => "agenda piena (#{EX_AGENDA_MAX})" } }
      end
      explore_satiate(ex, now, 'saltato') if o['skip'] && ex[:target]
      ex[:likes].clear if o['likes_clear']
      if o['like'].is_a?(Hash)
        o['like'].each do |k, v|
          k = k.to_s.strip
          k = "label:#{k[6..].strip.downcase}" if k.start_with?('label:')
          next rej << { 'item' => k, 'why' => 'gusto senza nome' } if k.empty? || k == 'label:'
          next ex[:likes].delete(k) if v.nil?
          n = explore_num(v) or next rej << { 'item' => k, 'why' => "peso non numerico: #{v.inspect}" }
          ex[:likes][k] = n.clamp(*EX_LIKE_RANGE)
        end
      end
      Array(o['avoid']).each { |k| ex[:likes][k.to_s.strip] = EX_AVOID }
      pilot_say(ex, o['say'].to_s.strip[0, 500]) if o['say'] && !o['say'].to_s.strip.empty?
      if o.key?('photos')
        v = o['photos'].to_s
        EX_PHOTOS.include?(v) ? ex[:photos] = v : rej << { 'item' => "photos=#{v}", 'why' => "atteso #{EX_PHOTOS.join(', ')}" }
      end
      if o['snap'] && !o['snap'].to_s.strip.empty?         # una foto per la galleria, adesso
        if !ex[:snaps]
          rej << { 'item' => 'snap', 'why' => 'foto della galleria spente: il giro non diventa un percorso' }
        elsif ex[:snap_want]
          rej << { 'item' => 'snap', 'why' => 'una foto per la galleria aspetta già' }
        else
          ex[:snap_want] = { tgt: nil, by: 'ai', why: o['snap'].to_s.strip[0, 500],
                             what: o['say'] && !o['say'].to_s.strip.empty? ? o['say'].to_s.strip[0, 500] : nil, t: now }
        end
      end
      if o['photo']
        tgt = ex[:target]
        if tgt && tgt[:arrived] && !ex[:photo_want]          # già fermi: subito (appena lo sguardo c'è)
          ex[:photo_want] = { tgt: tgt, id: tgt[:ai] ? tgt[:ai][:id] : ex[:kid][tgt[:id]], t: now }
          tgt[:photo_hold] = true
        else
          ex[:photo_ask] = true                  # alla prossima sosta
        end
      end
      ex[:next_scan] = now if ex[:next_scan] > now && !ex[:agenda].empty? && !(ex[:target] && ex[:target][:ai])
      { 'ok' => true, 'agenda' => ex[:agenda].map { |it| pilot_item_json(ex, it) }, 'likes' => ex[:likes],
        'photos' => ex[:photos], 'photo_pending' => !!(ex[:photo_want] || ex[:photo_ask]), 'rejected' => rej, 'ev_n' => ex[:ev_seq] }
    end

    # L'IA ha cambiato idea: la meta in corso si lascia senza segnarla come vista.
    def self.pilot_abort(ex, _now)
      tgt = ex[:target] or return
      it = tgt[:ai] or return
      ex[:target] = nil
      explore_route_drop(ex)
      explore_log(ex, tgt, 'cambiato')
      pilot_event(ex, 'done', 'id' => it[:id], 'label' => tgt[:label], 'why' => 'cambiato')
    end

    # ── A piedi: dove si arriva ──
    # Dalla cella dove si è, sulla pianta del suo piano, ogni cella che si
    # raggiunge entro EX_REACH_WALK di cammino: Dijkstra con gli stessi costi
    # e gli stessi gradini di explore_route_find, ma una volta per tutte le
    # cose e senza raggi. Per ogni cella i metri (della strada più comoda) e
    # se passa da celle mai viste. Solo se qualcuno lo chiede; quella di
    # prima vale finché è dello stesso piano, ha meno di EX_REACH_FRESH s e
    # ci si è spostati di poche celle.
    def self.pilot_flood(ex)
      return nil unless ex[:mode] == :walk && ex[:plan]
      cs = EX_PLAN_CELL
      feet = explore_feet(ex)
      lv = explore_plan_lv(feet)
      sx = (ex[:x] / cs).floor
      sy = (ex[:y] / cs).floor
      key = [ex[:plan_seq], sx, sy, lv]
      t = ex[:t].to_f
      if (fl = ex[:flood]) && fl[:lv] == lv &&
         (fl[:key] == key || (t - fl[:t] < EX_REACH_FRESH && [(fl[:key][1] - sx).abs, (fl[:key][2] - sy).abs].max <= 4))
        return fl
      end
      plan = ex[:plan]
      zmap = ex[:plan_z] || {}
      kx = 1 << 40
      ky = 1 << 20
      cost = {}
      cost_of = ->(k) { cost.key?(k) ? cost[k] : (cost[k] = explore_cell_cost(plan, k)) }
      k0 = explore_vpack(sx, sy, lv)
      g = { k0 => 0.0 }
      d = { k0 => 0.0 }
      unk = { k0 => false }
      zc = { k0 => [feet, sx, sy] }
      done = {}
      heap = [[0.0, k0, sx, sy]]
      n = 0
      cut = false
      until heap.empty?
        gk, k, ix, iy = explore_heap_pop(heap)
        next if done[k]
        done[k] = true
        if (n += 1) > EX_REACH_NODES
          cut = true
          break
        end
        EX_N8.each do |a, b, len|
          nk = k + a * kx + b * ky
          c = cost_of.(nk) or next
          next if a != 0 && b != 0 && !(cost_of.(k + a * kx) && cost_of.(k + b * ky))
          nd = d[k] + len * cs
          next if nd > EX_REACH_WALK
          nx = ix + a
          ny = iy + b
          za, zx, zy = zc[k]
          zb = zmap[nk]
          next unless explore_step_ok?(ex, za, zb, [Math.hypot(nx - zx, ny - zy) - 1.0, 0.0].max * cs)
          ng = gk + len * c
          old = g[nk]
          next if old && old <= ng
          g[nk] = ng
          d[nk] = nd
          unk[nk] = unk[k] || plan[nk].nil?
          zc[nk] = zb ? [zb, nx, ny] : zc[k]
          explore_heap_push(heap, [ng, nk, nx, ny])
        end
      end
      ex[:flood] = { key: key, lv: lv, t: t, d: d, unk: unk, cut: cut, nodes: n }
    end

    # Si arriva a piedi a meno di reach dal punto? [stato, metri di strada]:
    #   yes      sì, per celle già viste
    #   unknown  forse: la strada passa da celle mai viste, o la ricerca si
    #            è fermata prima (EX_REACH_NODES)
    #   no       nessuna strada entro EX_REACH_WALK di cammino, con ciò che si sa
    #   far      più lontano di così in linea d'aria: non si sa
    # nil in volo (si arriva dappertutto). L'ultimo tratto, dalla cella al
    # punto, non deve passare per celle piene, tranne gli ultimi short
    # (la cosa stessa occupa la sua cella).
    def self.pilot_reach(ex, pt, reach, short)
      fl = pilot_flood(ex) or return nil
      return ['far', nil] if Math.hypot(pt[0] - ex[:x], pt[1] - ex[:y]) > EX_REACH_WALK
      cs = EX_PLAN_CELL
      tx = (pt[0] / cs).floor
      ty = (pt[1] / cs).floor
      r = reach / cs
      ri = r.ceil
      cells = []
      (-ri..ri).each do |a|
        (-ri..ri).each do |b|
          next if a * a + b * b > r * r
          k = explore_vpack(tx + a, ty + b, fl[:lv])
          dd = fl[:d][k] or next
          cells << [dd, k, tx + a, ty + b]
        end
      end
      cells.sort_by!(&:first).each do |dd, k, ix, iy|
        next unless explore_grid_clear?(ex, fl[:lv], (ix + 0.5) * cs, (iy + 0.5) * cs, pt[0], pt[1], false, short)
        return [fl[:unk][k] ? 'unknown' : 'yes', (dd * IN_TO_M).round(1)]
      end
      [fl[:cut] ? 'unknown' : 'no', nil]
    end

    # Per un nome corto (cosa o zona): fin dove basta arrivare come per
    # explore_aim (la distanza di sosta, di più per le cose grandi; una zona
    # mai vista: il suo bordo). nil in volo o se non la si conosce.
    def self.pilot_reach_of(ex, sid)
      return nil unless ex[:mode] == :walk
      if sid.start_with?('F')
        fk = ex[:fknown][sid] or return nil
        return pilot_reach(ex, explore_front_cand(ex, fk[:f])[:pt], 1.5 * M_TO_IN, 0.0)
      end
      k = ex[:known][ex[:ksid][sid]] or return nil
      size = (k[:size] || 1.5) * M_TO_IN
      reach = [ex[:o]['standoff'] * M_TO_IN, [0.8 * size, 6.0 * M_TO_IN].min].max + 0.5 * M_TO_IN
      pilot_reach(ex, k[:pt], reach, [[0.8 * M_TO_IN, 0.4 * size].max, reach - 0.25 * M_TO_IN].min)
    end

    # ── Foto con i segni, solo nelle soste ──
    # Una write_image su un modello pesante blocca SketchUp per più di un
    # secondo (1,8 s su Stromboli): si scatta solo da fermi, davanti a una
    # meta raggiunta, con lo sguardo già sopra. Non contiene ciò che disegna
    # lo strumento, così i segni (il nome corto di ogni cosa visibile) si
    # scrivono sui pixel: BMP → righe RGB → etichette → PNG (Zlib).
    #   photos  ai   alle mete dell'IA (predefinito)
    #           all  a ogni sosta, anche davanti alle mete scelte da solo
    #           off  mai
    # Con steer "photo": true la prossima sosta ne fa una comunque.
    def self.pilot_photo_w; EX_PHOTO_W; end

    def self.pilot_photo_want?(ex, tgt)
      return true if ex[:photo_ask]
      case ex[:photos]
      when 'off' then false
      when 'all' then !tgt[:open] || !tgt[:ai].nil?
      else !tgt[:ai].nil?
      end
    end

    # A ogni fotogramma, dopo la camera: se una foto aspetta la sosta della
    # meta di adesso e lo sguardo ci è arrivato (o è passato abbastanza), si scatta.
    def self.pilot_photo_tick(view, ex, now)
      w = ex[:photo_want] or return
      tgt = ex[:target]
      unless tgt && w[:tgt].equal?(tgt)
        ex[:photo_want] = nil                    # la meta è cambiata prima della foto
        return
      end
      return if !tgt[:arrived] || explore_orbiting?(tgt) || explore_zooming?(ex)
      return if explore_aim_err(ex, tgt[:pt]) > EX_PHOTO_AIM && now - tgt[:arrived] < EX_PHOTO_SETTLE
      ex[:photo_want] = nil
      tgt[:photo_hold] = nil unless ex[:snap_want]   # e la foto della galleria, se aspetta anche lei
      pilot_photo(view, ex, w[:id])
    end

    def self.pilot_photo(view, ex, id)
      require 'tmpdir'
      require 'fileutils'
      vw = [view.vpwidth.to_f, 1.0].max
      vh = [view.vpheight.to_f, 1.0].max
      w = pilot_photo_w
      h = (w * vh / vw).round.clamp(48, 2000)
      bmp = File.join(Dir.tmpdir, "dagawasd_pilota_#{Process.pid}.bmp")
      t0 = explore_cpu
      ok = view.write_image(filename: bmp, width: w, height: h, antialias: true, transparent: false)
      t1 = explore_cpu
      rows = ok && File.exist?(bmp) ? pilot_rows(File.binread(bmp)) : nil
      return pilot_event(ex, 'photo', 'id' => id, 'error' => 'write_image non ha scritto l\'immagine') unless rows
      h = rows.size
      w = rows[0].bytesize / 3
      marks = pilot_marks(view, ex, w / vw, h / vh, w, h)
      pilot_draw_marks(rows, w, h, marks)
      dir = @pilot_dir || File.join(USER_DIR, 'pilota')   # i test ne danno un'altra
      FileUtils.mkdir_p(dir)
      ex[:photo_n] += 1
      file = File.join(dir, format('foto_%s_%03d.png', ex[:run], ex[:photo_n]))
      File.binwrite(file, pilot_png(w, h, rows))
      pilot_photo_prune(dir)
      info = { 'path' => file, 'id' => id, 'id_visible' => marks.any? { |m| m[:id] == id }, 'w' => w, 'h' => h,
               'render_ms' => ((t1 - t0) * 1000.0).round,
               'ms' => ((explore_cpu - t0) * 1000.0).round }
      ex[:photo] = info.merge('t' => ex[:t].round(1),
                              'marks' => marks.map { |m| { 'id' => m[:id], 'x' => m[:x].round, 'y' => m[:y].round } })
      pilot_event(ex, 'photo', info.merge('marks' => marks.size))
    rescue => fps_err
      log_error(__method__, fps_err)
      pilot_event(ex, 'photo', 'id' => id, 'error' => "#{fps_err.class}: #{fps_err.message}")
    ensure
      begin
        File.delete(bmp) if bmp && File.exist?(bmp)
      rescue SystemCallError
        nil
      end
    end

    # Le foto più vecchie se ne vanno (di tutti i giri)
    def self.pilot_photo_prune(dir)
      fs = Dir.glob(File.join(dir, 'foto_*.png')).sort_by { |f| File.mtime(f) }
      fs.first([fs.size - EX_PHOTO_KEEP, 0].max).each { |f| File.delete(f) rescue nil }
    end

    # BMP a 24 o 32 bit → righe RGB dall'alto, stringhe binarie (una per riga)
    def self.pilot_rows(data)
      return nil unless data.bytesize > 54 && data.byteslice(0, 2) == 'BM'
      off = data.byteslice(10, 4).unpack1('V')
      w, h = data.byteslice(18, 8).unpack('l<l<')
      bpp, comp = data.byteslice(28, 6).unpack('vV')
      return nil unless w.positive? && h != 0 && [24, 32].include?(bpp) && [0, 3].include?(comp)
      top_down = h.negative?
      h = h.abs
      step = bpp / 8
      stride = ((bpp * w + 31) / 32) * 4
      return nil if data.bytesize < off + stride * h
      perm = Array.new(w * 3) { |i| (i / 3) * step + 2 - (i % 3) }   # BGR(A) → RGB, in C
      Array.new(h) do |y|
        r = top_down ? y : h - 1 - y
        data.byteslice(off + r * stride, w * step).unpack('C*').values_at(*perm).pack('C*')
      end
    end

    def self.pilot_png(w, h, rows)
      require 'zlib'
      raw = String.new(capacity: (w * 3 + 1) * h, encoding: Encoding::BINARY)
      rows.each { |r| raw << 0 << r }
      chunk = lambda do |type, data|
        body = type.b + data.b
        [data.bytesize].pack('N') + body + [Zlib.crc32(body)].pack('N')
      end
      "\x89PNG\r\n\x1A\n".b + chunk.('IHDR', [w, h, 8, 2, 0, 0, 0].pack('NNC5')) +
        chunk.('IDAT', Zlib::Deflate.deflate(raw, 6)) + chunk.('IEND', '')
    end

    # Le cose da segnare: davanti, nell'inquadratura, non troppo lontane, e
    # visibili da qui (un raggio: ciò che sta dietro un muro non si segna).
    # L'obiettivo per primo, poi per salienza; le zone inesplorate anche.
    def self.pilot_marks(view, ex, sx, sy, w, h)
      eye = view.camera.eye
      cp = Math.cos(ex[:pitch])
      fx = cp * Math.cos(ex[:yaw]); fy = cp * Math.sin(ex[:yaw]); fz = Math.sin(ex[:pitch])
      tgt = ex[:target]
      tid = tgt && (tgt[:ai] ? tgt[:ai][:id] : ex[:kid][tgt[:id]])
      list = []
      add = lambda do |sid, pt, kind, pri, obj|
        dx = pt[0] - eye.x; dy = pt[1] - eye.y; dz = pt[2] - eye.z
        l = Math.sqrt(dx * dx + dy * dy + dz * dz)
        return if l < 0.3 * M_TO_IN || l > EX_PHOTO_FAR || (dx * fx + dy * fy + dz * fz) / l < 0.2
        s = view.screen_coords(Geom::Point3d.new(*pt))
        x = s.x * sx
        y = s.y * sy
        return unless x.between?(3.0, w - 3.0) && y.between?(3.0, h - 3.0)
        list << { id: sid, x: x, y: y, kind: sid == tid ? :target : kind, pri: sid == tid ? 1e9 : pri, pt: pt, obj: obj }
      end
      ex[:known].each_value do |k|
        next if k[:obj] && !k[:obj].valid?
        add.(k[:sid], k[:pt], k[:obj] ? :obj : :surf, k[:sal] || 0.0, k[:obj])
      end
      ex[:fronts].each do |f|
        c = explore_front_cand(ex, f)
        sid = ex[:kid][c[:id]] or next
        add.(sid, c[:pt], :front, 0.3, nil)
      end
      out = []
      list.sort_by { |m| -m[:pri] }.first(EX_PHOTO_MARKS * 2).each do |m|
        break if out.size >= EX_PHOTO_MARKS
        out << m if explore_sees?(eye.x, eye.y, eye.z, m[:pt], m[:obj])
      end
      out.each { |m| m[:kind] = :far if m[:kind] == :obj && pilot_reach_of(ex, m[:id])&.first == 'no' }
      out
    end

    # Un punto dove sta la cosa e accanto un cartellino col nome. Prima si
    # trovano i posti: un cartellino non copre gli altri né i punti delle
    # altre cose (quattro posti provati, poi la cosa si salta); poi si
    # disegnano tutti i punti, e sopra i cartellini.
    def self.pilot_draw_marks(rows, w, h, marks)
      s = EX_PHOTO_FONT
      pad = 3
      black = [0, 0, 0].pack('C3')
      hit = ->(a, b, g = 2) { a[0] < b[0] + b[2] + g && b[0] < a[0] + a[2] + g && a[1] < b[1] + b[3] + g && b[1] < a[1] + a[3] + g }
      dots = marks.map { |m| [m[:x].round - 4, m[:y].round - 4, 9, 9] }
      boxes = []
      marks.each_with_index do |m, j|
        bw = m[:id].to_s.size * 6 * s - s + 2 * pad
        bh = 7 * s + 2 * pad
        x = m[:x].round
        y = m[:y].round
        m[:box] = [[x + 6, y - 6 - bh], [x - 6 - bw, y - 6 - bh], [x + 6, y + 6], [x - 6 - bw, y + 6]].map do |bx, by|
          [bx.clamp(1, [w - bw - 1, 1].max), by.clamp(1, [h - bh - 1, 1].max), bw, bh]
        end.find do |b|
          boxes.none? { |a| hit.(a, b) } && dots.each_with_index.none? { |d, k| k != j && hit.(d, b, 0) }
        end
        boxes << m[:box] if m[:box]
      end
      marks.select! { |m| m[:box] }
      marks.each do |m|
        x = m[:x].round
        y = m[:y].round
        pilot_rect(rows, w, h, x - 4, y - 4, 9, 9, black)
        pilot_rect(rows, w, h, x - 3, y - 3, 7, 7, EX_PHOTO_COLORS[m[:kind]][0].pack('C3'))
      end
      marks.each do |m|
        bg, fg = EX_PHOTO_COLORS[m[:kind]].map { |c| c.pack('C3') }
        bx, by, bw, bh = m.delete(:box)
        pilot_rect(rows, w, h, bx - 1, by - 1, bw + 2, bh + 2, black)
        pilot_rect(rows, w, h, bx, by, bw, bh, bg)
        m[:id].to_s.each_char.with_index do |ch, i|
          g = EX_GLYPHS[ch] or next
          gx = bx + pad + i * 6 * s
          g.each_with_index do |line, gy|
            line.each_char.with_index { |b, k| pilot_rect(rows, w, h, gx + k * s, by + pad + gy * s, s, s, fg) if b == '#' }
          end
        end
      end
    end

    def self.pilot_rect(rows, w, h, x, y, rw, rh, col)
      x0 = [x, 0].max
      x1 = [x + rw, w].min
      return if x1 <= x0
      seg = col * (x1 - x0)
      ([y, 0].max...[y + rh, h].min).each { |yy| rows[yy][x0 * 3, seg.bytesize] = seg }
    end

    # Avvisi che svegliano il pilota; una cosa notevole solo se l'agenda è
    # quasi finita (con un piano in corso, la vedrà alla prossima occasione).
    def self.pilot_wake?(ex, evs)
      evs.any? do |e|
        EX_PILOT_WAKE.include?(e['type']) && !e['from_steer'] && (e['type'] != 'notable' || ex[:agenda].size <= 1) &&
          !(e['type'] == 'arrived' && e['photo'])
      end
    end

    def self.pilot_reach_json(r)
      r ? { 'reach' => r[0], 'walk_m' => r[1] } : {}
    end

    # ── Descrizione per l'IA (GET /explore/percept) ──
    # since: gli avvisi dopo questo numero; brief: solo gli avvisi (per
    # aspettare senza costruire tutto); n: quante cose (in vista prima).
    def self.explore_percept(since = 0, n = nil, brief = false)
      ex = @ex
      return { 'ok' => true, 'on' => false, 'last' => @ex_last } unless ex
      evs = ex[:events].select { |e| e['n'] > since.to_i }
      out = { 'ok' => true, 'on' => true, 'run' => ex[:run], 'paused' => !!ex[:paused], 'seconds' => ex[:t].round(1),
              'ev_n' => ex[:ev_seq], 'events' => evs, 'wake' => pilot_wake?(ex, evs) }
      return out if brief
      now = explore_clock
      n = (n || EX_PERCEPT_N[0]).to_i.clamp(1, EX_PERCEPT_N[1])
      m = ->(v) { (v * IN_TO_M).round(2) }
      rel = lambda do |pt|
        dx = pt[0] - ex[:x]
        dy = pt[1] - ex[:y]
        h = Math.hypot(dx, dy)
        { 'bearing_deg' => (explore_wrap(Math.atan2(dy, dx) - ex[:yaw]) / DEG).round,
          'elev_deg' => (Math.atan2(pt[2] - ex[:z], h) / DEG).round, 'dist_m' => m.(Math.sqrt(h * h + (pt[2] - ex[:z])**2)) }
      end
      step = ex[:steps]
      things = ex[:known].values.reject { |k| k[:obj] && !k[:obj].valid? }
      things = things.sort_by { |k| k[:step] == step ? [0, -k[:sal]] : [1, -k[:last]] }.first(n).map do |k|
        { 'id' => k[:sid], 'label' => k[:label], 'kind' => k[:obj] ? 'object' : 'surface', 'in_view' => k[:step] == step }
          .merge(rel.(k[:pt]))
          .merge('size_m' => k[:size], 'salience' => k[:sal].round(2), 'seen_s_ago' => (now - k[:last]).round(1),
                 'reached' => ex[:visited].key?(k[:id]), 'liked' => ex[:likes][k[:sid]])
          .merge(pilot_reach_json(k[:obj] && pilot_reach_of(ex, k[:sid])))
          .compact
      end
      fronts = ex[:fronts].filter_map do |f|
        c = explore_front_cand(ex, f)
        sid = ex[:kid][c[:id]] or next
        { 'id' => sid }.merge(rel.(c[:pt])).merge('width_m' => (f[:size] * EX_PLAN_CELL * IN_TO_M).round(1),
                                                    'unknown' => f[:unk].round(2))
                       .merge(pilot_reach_json(pilot_reach_of(ex, sid))).compact
      end
      tgt = ex[:target]
      out.merge(
        'mode' => ex[:mode].to_s, 'pos_m' => [m.(ex[:x]), m.(ex[:y]), m.(ex[:z])],
        'yaw_deg' => (ex[:yaw] / DEG).round(1), 'pitch_deg' => (ex[:pitch] / DEG).round(1),
        'target' => tgt && { 'id' => tgt[:ai] ? tgt[:ai][:id] : ex[:kid][tgt[:id]], 'label' => tgt[:label],
                             'by' => tgt[:ai] ? 'ai' : 'auto', 'arrived' => !tgt[:arrived].nil?, 'visible' => tgt[:vis] }
                                .merge(rel.(tgt[:pt])).compact,
        'looking_around' => !ex[:look].nil?,
        'agenda' => ex[:agenda].map { |it| pilot_item_json(ex, it) }, 'likes' => ex[:likes],
        'photos' => ex[:photos], 'photo_pending' => !!(ex[:photo_want] || ex[:photo_ask]), 'photo' => ex[:photo],
        'things' => things, 'frontiers' => fronts,
        'counts' => { 'known' => ex[:known].size, 'reached' => ex[:visited].size, 'steps' => step, 'notes' => ex[:says].size },
        'log' => ex[:log].last(8)
      )
    end
  end
end
