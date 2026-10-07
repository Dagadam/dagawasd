# DagaWASD — Ponte per Claude: server HTTP locale che esegue Ruby nel modello aperto.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Ponte per Claude
    # Un server HTTP minimo su 127.0.0.1 (mai raggiungibile dalla rete)
    # che riceve codice Ruby e lo esegue nel modello aperto, come un'unica
    # operazione annullabile con Ctrl+Z. Serve a Claude Code per disegnare
    # e interrogare il modello; il client è tools/su.rb.
    #
    # Sicurezza: spento finché l'utente non lo accende dal pannello. Il
    # token cambia a ogni avvio ed è scritto solo nel file di connessione
    # (%APPDATA%\DagaWASD\bridge.json). Le richieste con intestazione Origin
    # arrivano da una pagina web e vengono rifiutate: un sito aperto nel
    # browser non può usare il ponte. Nessuna intestazione CORS viene inviata.
    #
    # SketchUp esegue Ruby su un solo thread: il server non blocca, un timer
    # controlla le connessioni in arrivo e ne serve una alla volta.
    #
    #   GET  /ping              stato: versione di SketchUp, modello aperto
    #   POST /eval[?op=Nome]    corpo = codice Ruby → risultato, output, errore
    #   GET  /image[?w=&h=]     PNG della vista attuale
    #
    # Costruzione dal vivo (bridge_live): il codice gira in una Fiber e a
    # ogni `step "descrizione"` cede il controllo a SketchUp, che ridisegna
    # la vista e resta reattivo; un timer lo riprende dopo bridge_step_delay
    # secondi. La risposta HTTP parte solo alla fine. Resta una sola
    # operazione: Ctrl+Z toglie tutto, un errore a metà la annulla per intero.
    # Senza bridge_live, step non fa nulla.
    # ══════════════════════════════════════════════════════════════
    BRIDGE_PORTS   = (47810..47819).freeze
    BRIDGE_MAX     = 8 * 1024 * 1024      # corpo massimo di una richiesta
    BRIDGE_TIMEOUT = 3.0                  # secondi per ricevere le intestazioni
    BRIDGE_OUT_MAX = 200_000              # caratteri massimi di risultato e output

    # Oggetto in cui gira il codice ricevuto: le variabili d'istanza (@x)
    # restano da una chiamata all'altra, le locali no.
    class BridgeContext
      def model; Sketchup.active_model; end
      def ents;  model.active_entities; end
      def sel;   model.selection; end
      def view;  model.active_view; end
      # Fine di un passo: dal vivo mostra il modello fin qui e aspetta;
      # altrimenti non fa nulla. level = dettaglio minimo a cui il passo si
      # vede (1 solidi finiti, 2 operazioni, 3 costruzione animata).
      def step(label = nil, level = 1); DagaWASD::FPSWalk.bridge_step(label, level); end
      # Dettaglio scelto nel pannello (1–3); 1 se la costruzione dal vivo è
      # spenta, così lo script non spezza le operazioni per niente.
      def detail; DagaWASD::FPSWalk.bridge_detail; end
    end

    # SketchUp si chiude: il file di connessione non deve restare a indicare un server morto
    class BridgeQuitObserver < Sketchup::AppObserver
      def onQuit; DagaWASD::FPSWalk.bridge_stop; end
    end

    def self.bridge_info_path
      @bridge_file || File.join(USER_DIR, 'bridge.json')
    end

    def self.bridge_status
      @bridge_srv ? { 'on' => true, 'port' => @bridge_port } : { 'on' => false, 'fail' => !!@bridge_fail }
    end

    # Accende o spegne il ponte secondo l'impostazione; il pannello mostra lo stato.
    def self.bridge_sync
      cf('bridge_enabled') ? bridge_start : bridge_stop
      @dialog.execute_script("setBridge(#{js_json(bridge_status)})") if @dialog && @dialog.visible?
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.bridge_start
      return true if @bridge_srv
      require 'socket'
      require 'securerandom'
      require 'stringio'
      require 'fileutils'
      @bridge_fail = false
      BRIDGE_PORTS.each do |p|
        begin
          @bridge_srv  = TCPServer.new('127.0.0.1', p)
          @bridge_port = p
          break
        rescue Errno::EADDRINUSE, Errno::EACCES
          next
        end
      end
      unless @bridge_srv
        @bridge_fail = true
        return false
      end
      @bridge_token = SecureRandom.hex(24)
      @bridge_ctx   = BridgeContext.new
      path = bridge_info_path
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(
        'port' => @bridge_port, 'token' => @bridge_token, 'pid' => Process.pid,
        'sketchup' => Sketchup.version, 'started' => Time.now.strftime('%Y-%m-%d %H:%M:%S')
      ))
      unless @bridge_quit_obs
        @bridge_quit_obs = BridgeQuitObserver.new
        Sketchup.add_observer(@bridge_quit_obs)
      end
      @bridge_timer = UI.start_timer(0.05, true) { bridge_poll }
      true
    rescue => fps_err
      log_error(__method__, fps_err)
      bridge_stop
      false
    end

    def self.bridge_stop
      UI.stop_timer(@bridge_timer) if @bridge_timer
      @bridge_timer = nil
      bridge_job_finish('ok' => false, 'error' => 'ponte spento durante la costruzione') if @bridge_job
      if @bridge_srv
        begin; @bridge_srv.close; rescue IOError, SystemCallError; end
        # il file è nostro solo se contiene ancora il nostro token (un'altra
        # copia di SketchUp potrebbe averlo riscritto)
        begin
          path = bridge_info_path
          File.delete(path) if File.exist?(path) && JSON.parse(File.read(path))['token'] == @bridge_token
        rescue JSON::ParserError, SystemCallError
          nil
        end
      end
      @bridge_srv = nil; @bridge_port = nil; @bridge_token = nil
    end

    def self.bridge_poll
      return unless @bridge_srv
      4.times do                                   # poche richieste per tick: SketchUp resta reattivo
        c = @bridge_srv.accept_nonblock(exception: false)
        break if c == :wait_readable || c.nil?
        async = false
        begin
          async = bridge_serve(c) == :async      # costruzione dal vivo: risponde alla fine
        ensure
          c.close unless async rescue nil
        end
      end
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # ── HTTP ────────────────────────────────────────────────────────
    # Legge una richiesta intera (intestazioni + corpo) o restituisce nil.
    def self.bridge_read(sock)
      deadline = Time.now + BRIDGE_TIMEOUT
      buf = String.new(encoding: 'BINARY')
      read_some = lambda do
        return false unless IO.select([sock], nil, nil, 0.2)
        chunk = sock.read_nonblock(65_536, exception: false)
        return nil if chunk.nil?                   # connessione chiusa
        buf << chunk if chunk.is_a?(String)
        true
      end
      until (i = buf.index("\r\n\r\n"))
        return nil if Time.now > deadline || buf.bytesize > 64 * 1024
        return nil if read_some.call.nil?
      end
      head = buf[0...i].dup.force_encoding('UTF-8').scrub
      line, *hl = head.split("\r\n")
      meth, target = line.to_s.split(' ')
      hdr = {}
      hl.each { |h| k, v = h.split(':', 2); hdr[k.to_s.strip.downcase] = v.to_s.strip }
      len = hdr['content-length'].to_i
      return nil if len.negative? || len > BRIDGE_MAX
      body_start = i + 4
      while buf.bytesize - body_start < len
        return nil if Time.now > deadline + 30     # corpo grande: più tempo, non infinito
        return nil if read_some.call.nil?
      end
      path, query = target.to_s.split('?', 2)
      q = {}
      query.to_s.split('&').each { |kv| k, v = kv.split('=', 2); q[k] = URI.decode_www_form_component(v.to_s) }
      body = buf.byteslice(body_start, len).force_encoding('UTF-8')
      { meth: meth, path: path, q: q, hdr: hdr, body: body }
    end

    def self.bridge_reply(sock, code, body, type = 'application/json; charset=utf-8')
      body = JSON.generate(body) if body.is_a?(Hash)
      body = body.b
      msg  = { 200 => 'OK', 400 => 'Bad Request', 403 => 'Forbidden', 404 => 'Not Found', 409 => 'Conflict',
               500 => 'Error' }[code] || 'OK'
      sock.write("HTTP/1.1 #{code} #{msg}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\n" \
                 "Connection: close\r\n\r\n")
      sock.write(body)
    rescue IOError, SystemCallError
      nil
    end

    # Confronto a tempo costante: non rivela quanti caratteri del token sono giusti.
    def self.bridge_token_ok?(tok)
      tok = tok.to_s
      @bridge_token && tok.bytesize == @bridge_token.bytesize &&
        tok.bytes.zip(@bridge_token.bytes).reduce(0) { |a, (x, y)| a | (x ^ y) }.zero?
    end

    def self.bridge_serve(sock)
      require 'uri'
      req = bridge_read(sock)
      return bridge_reply(sock, 400, 'error' => 'richiesta non valida o incompleta') unless req
      return bridge_reply(sock, 403, 'error' => 'le richieste dal browser non sono ammesse') if req[:hdr].key?('origin')
      return bridge_reply(sock, 403, 'error' => 'token mancante o errato (vedi bridge.json)') unless bridge_token_ok?(req[:hdr]['x-token'])
      case [req[:meth], req[:path]]
      when ['GET', '/ping']  then bridge_reply(sock, 200, bridge_ping)
      when ['POST', '/eval']
        if @bridge_job
          bridge_reply(sock, 409, 'ok' => false, 'error' => 'sto ancora costruendo l\'invio precedente')
        elsif cf('bridge_live') && !@active && Sketchup.active_model
          bridge_eval_live(sock, req[:body], req[:q]['op'])
        else
          bridge_reply(sock, 200, bridge_eval(req[:body], req[:q]['op']))
        end
      when ['GET', '/image']
        png = bridge_image(req[:q]['w'].to_i, req[:q]['h'].to_i)
        png ? bridge_reply(sock, 200, png, 'image/png') : bridge_reply(sock, 500, 'error' => 'nessuna vista da fotografare')
      else bridge_reply(sock, 404, 'error' => "sconosciuto: #{req[:meth]} #{req[:path]}")
      end
    rescue => fps_err
      log_error(__method__, fps_err)
      bridge_reply(sock, 500, 'error' => "#{fps_err.class}: #{fps_err.message}")
    end

    # ── Comandi ─────────────────────────────────────────────────────
    def self.bridge_ping
      m = Sketchup.active_model
      { 'ok' => true, 'sketchup' => Sketchup.version,
        'model' => m && (m.title.empty? ? '(senza titolo)' : m.title), 'path' => m && m.path,
        'entities' => m && m.entities.size, 'units' => m && m.options['UnitsOptions']['LengthUnit'],
        'fps_active' => !!@active }
    end

    # Esegue il codice come una sola operazione: un errore la annulla per
    # intero, quindi il modello non resta mai a metà. puts/p finiscono in
    # 'output', il valore dell'ultima espressione in 'result'.
    def self.bridge_eval(code, op)
      model = Sketchup.active_model
      return { 'ok' => false, 'error' => 'nessun modello aperto' } unless model
      return { 'ok' => false, 'error' => 'modalità FPS attiva: esci prima (ESC)' } if @active
      out = StringIO.new
      old_out = $stdout
      op = op.to_s.strip.empty? ? 'Claude' : "Claude: #{op.to_s[0, 60]}"
      model.start_operation(op, true)
      t0 = Time.now
      begin
        $stdout = out
        res = @bridge_ctx.instance_eval(code, 'claude', 1)
        $stdout = old_out
        model.commit_operation
        model.active_view.invalidate
        { 'ok' => true, 'result' => bridge_clip(res.inspect), 'output' => bridge_clip(out.string),
          'seconds' => (Time.now - t0).round(3) }
      rescue ScriptError, StandardError => e
        $stdout = old_out
        model.abort_operation
        trace = (e.backtrace || []).select { |l| l.start_with?('claude:') }.first(8)
        { 'ok' => false, 'error' => "#{e.class}: #{e.message}", 'backtrace' => trace,
          'output' => bridge_clip(out.string), 'undone' => true }
      ensure
        $stdout = old_out
      end
    end

    # ── Costruzione dal vivo ────────────────────────────────────────
    # step chiamato dal codice ricevuto: cede il controllo solo se sta
    # girando dentro la Fiber di un lavoro dal vivo.
    def self.bridge_step(label, level = 1)
      job = @bridge_job
      return nil unless job && Fiber.current.equal?(job[:fiber])
      return nil if level.to_i > bridge_detail
      Fiber.yield(label.to_s)
      nil
    end

    BRIDGE_DETAIL = { 'solids' => 1, 'ops' => 2, 'anim' => 3 }.freeze
    def self.bridge_detail
      return 1 unless @bridge_job
      BRIDGE_DETAIL[cf('bridge_detail')] || 1
    end

    def self.bridge_eval_live(sock, code, op)
      model = Sketchup.active_model
      ctx   = @bridge_ctx
      op = op.to_s.strip.empty? ? 'Claude' : "Claude: #{op.to_s[0, 60]}"
      # disable_ui = true anche dal vivo: con false SketchUp aggiorna i suoi
      # pannelli a ogni singola modifica e la costruzione diventa ~50 volte
      # più lenta. La vista si ridisegna comunque fra un passo e l'altro.
      model.start_operation(op, true)
      fiber = Fiber.new do
        begin
          { 'ok' => true, 'result' => bridge_clip(ctx.instance_eval(code, 'claude', 1).inspect) }
        rescue ScriptError, StandardError => e
          { 'ok' => false, 'error' => "#{e.class}: #{e.message}",
            'backtrace' => (e.backtrace || []).select { |l| l.start_with?('claude:') }.first(8) }
        end
      end
      @bridge_job = { fiber: fiber, sock: sock, model: model, out: StringIO.new, t0: Time.now, steps: 0 }
      orbit_start(model)
      bridge_job_resume
      :async
    end

    # Esegue fino al prossimo step (o alla fine) e programma il passo dopo.
    def self.bridge_job_resume
      job = @bridge_job
      return unless job
      old_out = $stdout
      begin
        $stdout = job[:out]
        val = orbit_trace { job[:fiber].resume }
      ensure
        $stdout = old_out
      end
      return bridge_job_finish(val) unless job[:fiber].alive?
      job[:steps] += 1
      orbit_retarget
      Sketchup.status_text = "Claude › #{val.empty? ? "#{job[:steps]}" : val}"
      job[:model].active_view.invalidate
      delay = cf('bridge_step_delay').to_f.clamp(0.05, 2.0)
      UI.start_timer(delay, false) { bridge_job_resume }
    rescue => fps_err
      log_error(__method__, fps_err)
      bridge_job_finish('ok' => false, 'error' => "#{fps_err.class}: #{fps_err.message}")
    end

    # Chiude l'operazione (conferma o annulla) e manda la risposta attesa dal client.
    def self.bridge_job_finish(res)
      job = @bridge_job
      return unless job
      @bridge_job = nil
      orbit_stop
      res = res.is_a?(Hash) ? res : { 'ok' => false, 'error' => 'costruzione interrotta' }
      if res['ok']
        job[:model].commit_operation
      else
        job[:model].abort_operation
        res['undone'] = true
      end
      job[:model].active_view.invalidate
      Sketchup.status_text = ''
      res['output']  = bridge_clip(job[:out].string)
      res['steps']   = job[:steps]
      res['seconds'] = (Time.now - job[:t0]).round(3)
      bridge_reply(job[:sock], 200, res)
      job[:sock].close rescue nil
    end

    # ── Dolly rotante ───────────────────────────────────────────────
    # Con bridge_orbit, durante la costruzione dal vivo la camera gira
    # lentamente attorno a ciò che si sta costruendo. A ogni passo si
    # ricalcola l'ingombro delle entità nate nel lavoro (quelle che
    # c'erano già all'inizio non contano) e la camera ci scivola sopra
    # senza scatti: centro, distanza e altezza inseguono l'obiettivo.
    # Prima che nasca qualcosa gira attorno al punto guardato. A fine
    # lavoro si ferma dove si trova.
    #
    # Nelle pause fra i passi la muove un timer. Mentre il codice ricevuto
    # lavora, invece, SketchUp non ridisegna e i timer non scattano: la
    # muove orbit_frame, chiamata da un TracePoint acceso solo durante la
    # Fiber (vedi orbit_trace). Resta ferma solo dentro una singola
    # chiamata lunga all'API (un booleano su un solido grande): lì Ruby
    # non riprende la parola finché SketchUp non ha finito.
    ORBIT_FPS       = 30.0
    ORBIT_ELEV      = 25.0 * DEG   # inclinazione dello sguardo verso l'oggetto
    ORBIT_MARGIN    = 1.3          # aria attorno all'oggetto nell'inquadratura
    ORBIT_MIN_DIST  = 40.0         # pollici (~1 m): mai dentro un oggetto minuscolo
    ORBIT_FOLLOW    = 1.5          # rapidità con cui la camera insegue l'obiettivo (1/s)
    ORBIT_REAIM     = 0.5          # secondi fra due ricalcoli dell'ingombro mentre il codice lavora

    def self.orbit_start(model)
      orbit_stop
      return unless cf('bridge_orbit')
      cam = model.active_view.camera
      off = cam.eye - cam.target
      @orbit = {
        model: model, known: {}, last: orbit_clock, due: 0.0, reaim: 0.0,
        center: cam.target, radius: [Math.hypot(off.x, off.y), 1.0].max, height: off.z,
        angle: Math.atan2(off.y, off.x), ortho: cam.perspective? ? nil : cam.height
      }
      model.active_entities.each { |e| @orbit[:known][e.entityID] = true }
      @orbit.merge!(goal_center: @orbit[:center], goal_radius: @orbit[:radius],
                    goal_height: @orbit[:height], goal_ortho: @orbit[:ortho])
      @orbit_timer = UI.start_timer(1.0 / ORBIT_FPS, true) { orbit_tick }
    rescue => fps_err
      log_error(__method__, fps_err)
      orbit_stop
    end

    def self.orbit_stop
      UI.stop_timer(@orbit_timer) if @orbit_timer
      @orbit_timer = nil
      @orbit = nil
    end

    def self.orbit_clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end

    # Esegue il blocco (un tratto della Fiber) dando fotogrammi alla camera.
    # Un TracePoint sempre acceso rallenterebbe il codice Ruby di 2-3 volte;
    # così invece un thread fa da metronomo e lo accende ORBIT_FPS volte al
    # secondo: scatta alla prima riga o al primo ritorno dall'API del thread
    # principale, si spegne e disegna un fotogramma. Il metronomo non tocca
    # mai SketchUp (l'API va usata solo dal thread principale); quando il
    # codice tiene occupato Ruby i thread si alternano più di rado e i
    # fotogrammi scendono a ~20 al secondo. Senza dolly, o in un SketchUp
    # senza View#refresh, il blocco gira e basta.
    def self.orbit_trace
      o = @orbit
      return yield unless o && o[:model].active_view.respond_to?(:refresh)
      main = Thread.current
      tp = TracePoint.new(:line, :c_return) do |t|
        next unless Thread.current.equal?(main)
        t.disable
        orbit_frame
      end
      metronome = Thread.new { loop { sleep(1.0 / ORBIT_FPS); tp.enable } }
      begin
        yield
      ensure
        metronome.kill
        tp.disable
      end
    end

    # Un fotogramma mentre il codice lavora: gira la camera e ridisegna
    # subito, senza aspettare il ciclo di SketchUp. Il tempo del disegno è
    # misurato e il codice ne riceve almeno altrettanto prima del prossimo:
    # su un modello pesante i fotogrammi si diradano, ma la costruzione non
    # rallenta più del doppio.
    def self.orbit_frame
      o = @orbit
      return unless o
      t = orbit_clock
      return if t < o[:due]
      if t >= o[:reaim]
        orbit_retarget
        o[:reaim] = t + ORBIT_REAIM
      end
      orbit_tick(false)
      o[:model].active_view.refresh
      done = orbit_clock
      o[:due] = done + [1.0 / ORBIT_FPS - (done - t), done - t].max
    rescue => fps_err
      log_error(__method__, fps_err)
      orbit_stop
    end

    # Posizione da cui inquadrare un ingombro: [centro, raggio, altezza, altezza
    # della vista in parallela]. fov in gradi, verticale come in SketchUp.
    def self.orbit_goal(bb, fov)
      half = bb.diagonal / 2.0
      dist = [half / Math.sin((fov.to_f.clamp(10.0, 120.0) / 2.0) * DEG) * ORBIT_MARGIN, ORBIT_MIN_DIST].max
      c = Geom::Point3d.new((bb.min.x + bb.max.x) / 2.0, (bb.min.y + bb.max.y) / 2.0, (bb.min.z + bb.max.z) / 2.0)
      [c, dist * Math.cos(ORBIT_ELEV), dist * Math.sin(ORBIT_ELEV), [bb.diagonal * ORBIT_MARGIN, ORBIT_MIN_DIST].max]
    end

    def self.orbit_eye(center, radius, height, angle)
      Geom::Point3d.new(center.x + Math.cos(angle) * radius, center.y + Math.sin(angle) * radius, center.z + height)
    end

    # Dopo ogni passo: nuovo obiettivo dall'ingombro delle entità nate nel lavoro.
    def self.orbit_retarget
      o = @orbit
      return unless o
      bb = Geom::BoundingBox.new
      o[:model].active_entities.each do |e|
        bb.add(e.bounds) if e.valid? && !o[:known][e.entityID] && e.respond_to?(:bounds)
      end
      return if bb.empty?
      cam = o[:model].active_view.camera
      o[:goal_center], o[:goal_radius], o[:goal_height], ortho = orbit_goal(bb, cam.perspective? ? cam.fov : 35.0)
      o[:goal_ortho] = ortho if o[:ortho]
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Un passo della camera; redraw = false quando chi chiama ridisegna da sé.
    def self.orbit_tick(redraw = true)
      o = @orbit
      return orbit_stop unless o && @bridge_job
      now = orbit_clock
      el  = [now - o[:last], 0.0].max
      dt  = el.clamp(0.001, 0.1)
      o[:last] = now
      k = (ORBIT_FOLLOW * dt).clamp(0.0, 1.0)
      # L'angolo segue l'orologio, non i fotogrammi né i passi: se un passo
      # lungo tiene occupato SketchUp, al fotogramma dopo la camera è dove
      # sarebbe stata comunque. La rotazione resta costante nel tempo.
      o[:angle]  += cf('bridge_orbit_speed').to_f * DEG * el
      o[:center]  = Geom.linear_combination(1.0 - k, o[:center], k, o[:goal_center])
      o[:radius] += (o[:goal_radius] - o[:radius]) * k
      o[:height] += (o[:goal_height] - o[:height]) * k
      view = o[:model].active_view
      cam  = view.camera
      cam.set(orbit_eye(o[:center], o[:radius], o[:height], o[:angle]), o[:center], Z_AXIS)
      if o[:ortho]
        o[:ortho] += (o[:goal_ortho] - o[:ortho]) * k
        cam.height = o[:ortho]
      end
      view.invalidate if redraw
    rescue => fps_err
      log_error(__method__, fps_err)
      orbit_stop
    end

    def self.bridge_clip(s)
      s = s.to_s.dup.force_encoding('UTF-8').scrub('?')
      s.size > BRIDGE_OUT_MAX ? s[0, BRIDGE_OUT_MAX] + "\n…[tagliato: #{s.size} caratteri]" : s
    end

    def self.bridge_image(w, h)
      require 'tmpdir'
      view = Sketchup.active_model&.active_view
      return nil unless view
      w = w.positive? ? w.clamp(64, 4096) : view.vpwidth
      h = h.positive? ? h.clamp(64, 4096) : view.vpheight
      path = File.join(Dir.tmpdir, "dagawasd_view_#{Process.pid}.png")
      view.write_image(filename: path, width: w, height: h, antialias: true, transparent: false)
      data = File.binread(path)
      File.delete(path) rescue nil
      data
    end

  end
end
