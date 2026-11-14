# DagaWASD — Registro dell'esportazione video: un file di testo accanto al
# video (lib/path.rb, lib/videoexport.rb), in caratteri ASCII con le
# etichette nella lingua scelta.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Accanto al video, stesso nome e .log (per le immagini nella loro
    # cartella, col nome del percorso). Si riscrive tutto a ogni cambio:
    #
    #   +==========================+   DagaWASD, versione, percorso
    #    MODELLO                       file, salvato?, SketchUp, contenuto
    #    PERCORSO                      sfere, durata, velocità
    #    VIDEO                         file, formato, misure, fps, audio, …
    #    METEO NEL VIDEO               dipinto, cielo, nuvole, pioggia, …
    #    PEZZI ESPORTATI   tabella     uno per riga: modo, inizio, fine,
    #                                  fotogrammi, durata, s a fotogramma, esito
    #    RIEPILOGO                     fatti, quanto manca, ritmo, più lenti,
    #                                  dimensione e disco, da dove riprendere
    #    AVVISI                        modello non salvato, impostazioni
    #                                  cambiate fra un pezzo e l'altro, buchi…
    #    -- dati --                    una riga «#D {json}» per pezzo
    #
    # Le righe #D sono quello che DagaWASD rilegge (la finestra: primo
    # fotogramma del video, ultima riga); il resto si rifà da loro. Ogni
    # pezzo tiene le impostazioni con cui è stato fatto: le sezioni in alto
    # sono quelle dell'ultimo. Mentre si esporta il pezzo in corso si
    # aggiorna ogni VX_EVERY s, così anche se SketchUp si chiude si sa
    # dov'era arrivato. I registri di prima (righe con [ev=… …]) si leggono
    # ancora e alla prima riscrittura passano al formato nuovo.
    # Il registro non deve mai fermare l'esportazione.
    # ══════════════════════════════════════════════════════════════
    VX_EVERY = 5.0           # s fra una riscrittura e l'altra del registro durante l'esportazione
    VX_LOG_W = 78            # larghezza del riquadro in alto
    VX_LOG_CMP = { 'w' => 'f.path_video_size', 'h' => 'f.path_video_size', 'fps' => 'f.path_video_fps' }.freeze
    VX_LOG_CMP_CFG = { 'speed' => 'f.path_speed', 'weather' => 'f.path_video_weather', 'quality' => 've.quality',
                       'sky' => 've.lg.sky', 'clouds' => 've.lg.clouds', 'precip' => 've.lg.precip',
                       'mtime' => 've.lg.model', 'model' => 've.lg.model', 'audio' => 've.lg.audio' }.freeze

    def self.vx_log_file(avi); avi.to_s.sub(/\.avi\z/i, '') + '.log'; end

    def self.vx_job_log(job)
      return vx_log_file(job[:patch][:file]) if job[:patch]
      job[:avi] ? vx_log_file(job[:avi].path) : File.join(job[:dir], "#{path_safe(job[:name])}.log")
    end

    # ── Lettura ───────────────────────────────────────────────────
    # I pezzi del registro, dal primo all'ultimo: le righe «#D {…}», o
    # quelle con [ev=…] dei registri di prima
    def self.vx_log_sessions(file)
      return [] unless File.file?(file)
      list = []
      File.read(file, encoding: 'UTF-8').scrub.each_line do |l|
        l = l.chomp
        if l.start_with?('#D {')
          s = begin
            JSON.parse(l[3..])
          rescue JSON::ParserError
            nil
          end
          list << s if s.is_a?(Hash)
        elsif (kv = l[/\[([^\[\]]*)\]\s*\z/, 1])
          vx_log_legacy(list, kv.scan(/(\w+)=(\S+)/).to_h, l[/\A\d{4}-\d\d-\d\d \d\d:\d\d:\d\d/])
        end
      end
      list
    rescue SystemCallError, IOError
      []
    end

    def self.vx_log_legacy(list, h, at)
      if h['ev'] == 'start'
        from = h['from'].to_i
        first = h['first']&.to_i
        list << { 'at0' => at, 'state' => 'lost', 'mode' => first && first != from ? 'append' : 'new',
                  'from' => from, 'to' => h['to'].to_i, 'total' => h['total'].to_i, 'fps' => h['fps'].to_i,
                  'w' => h['w'].to_i, 'h' => h['h'].to_i, 'first' => first, 'last' => from - 1, 'n' => 0 }
      elsif (s = list.last) && %w[run end stop full error].include?(h['ev'])
        s['last'] = h['last'].to_i
        s['n'] = [s['last'] - s['from'] + 1, 0].max
        s['state'] = h['ev'] == 'run' ? 'lost' : h['ev']
        s['at1'] = at
      end
    end

    # Il primo fotogramma del video: quello dell'ultimo pezzo che lo sa
    def self.vx_file_first(file)
      s = vx_log_sessions(file).reverse.find { |x| x['first'] } or return nil
      n = s['first'].to_i
      n.positive? ? n : nil
    end

    # Per la finestra: com'è finito l'ultimo pezzo
    def self.vx_log_last(file)
      s = vx_log_sessions(file).last or return nil
      vx_f(t('ve.lg.last_line'), at: s['at1'] || s['at0'], state: vx_st(s['state']), last: s['last'])
    end

    # Istante nel video del fotogramma n (da 1): 4:38.80
    def self.vx_clock(n, fps)
      s = [n - 1, 0].max / fps.to_f
      format('%d:%05.2f', (s / 60).floor, s % 60)
    end

    def self.vx_hms(sec)
      sec = sec.to_f.round
      format('%d:%02d:%02d', sec / 3600, sec / 60 % 60, sec % 60)
    end

    # Un testo tradotto con i suoi %{nomi}: come format, ma un «%» da solo
    # (50%, 4 GB al 90%) resta com'è invece di far fallire tutto il registro
    def self.vx_f(str, **v)
      str.to_s.gsub(/%\{(\w+)\}/) { v.key?($1.to_sym) ? v[$1.to_sym].to_s : $& }
    end

    # Esiti e tipi dei pezzi: le chiavi per intero (test_i18n le cerca così)
    VX_LG_ST = { 'run' => 've.lg.st_run', 'ff' => 've.lg.st_ff', 'end' => 've.lg.st_end', 'stop' => 've.lg.st_stop',
                 'full' => 've.lg.st_full', 'error' => 've.lg.st_error', 'lost' => 've.lg.st_lost' }.freeze
    VX_LG_MODE = { 'new' => 've.lg.m_new', 'append' => 've.lg.m_append', 'patch' => 've.lg.m_patch', 'draft' => 've.lg.m_draft' }.freeze
    def self.vx_st(state); t(VX_LG_ST[state.to_s] || 've.lg.st_lost'); end

    def self.vx_now; Time.now.strftime('%Y-%m-%d %H:%M:%S'); end
    def self.vx_time(str); Time.new(*str.to_s.scan(/\d+/).first(6).map(&:to_i)); end

    # ── Scrittura ─────────────────────────────────────────────────
    # Inizio: fresh = video nuovo o immagini da capo, il registro riparte;
    # se no (in coda, un altro pezzo, un tratto rifatto) i pezzi di prima restano.
    def self.vx_log_begin(job, fresh)
      file = vx_job_log(job)
      list = fresh ? [] : vx_log_sessions(file)
      from = job[:k0].to_i + 1
      s = { 'v' => 2, 'name' => job[:name], 'at0' => vx_now, 'at1' => nil, 'state' => job[:ff] ? 'ff' : 'run',
            'mode' => job[:draft] ? 'draft' : job[:mode] || 'new', 'from' => from, 'to' => job[:stop] || job[:total],
            'total' => job[:total], 'fps' => job[:fps], 'w' => job[:w], 'h' => job[:h], 'first' => job[:first],
            'last' => from - 1, 'n' => 0, 'cfg' => vx_log_snapshot(job, file) }
      s['before'] = job[:avi].before if job[:avi] && job[:mode] == 'append'
      job[:log] = { file: file, list: list + [s], cur: s, at: nil, t0: Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      vx_log_write(job)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Le impostazioni con cui si fa questo pezzo
    def self.vx_log_snapshot(job, file)
      m = Sketchup.active_model
      mp = m.path.to_s
      ms = attesa_model_stats(m)
      ver = defined?(DagaWASD::FPSWalkLoader::VERSION) ? DagaWASD::FPSWalkLoader::VERSION : ''
      target = job[:patch] ? job[:patch][:file] : job[:avi] ? job[:avi].path : job[:dir]
      c = { 'model' => mp.empty? ? nil : mp.tr('/', '\\'), 'saved' => !(m.respond_to?(:modified?) && m.modified?),
            'mtime' => !mp.empty? && File.exist?(mp) ? File.mtime(mp).strftime('%Y-%m-%d %H:%M:%S') : nil,
            'su' => (Sketchup.version.to_s rescue ''), 'ver' => ver,
            'faces' => ms['faces'], 'comps' => ms['comps'], 'mats' => ms['mats'],
            'keys' => job[:keys].to_i, 'dur' => job[:dur].to_f.round(2), 'speed' => job[:speed].to_f,
            'file' => target.to_s.tr('/', '\\'), 'log' => file.tr('/', '\\'), 'format' => job[:avi] ? 'avi' : 'png',
            'quality' => job[:avi] ? job[:quality] : nil,
            'weather' => job[:vm] && job[:vm][:paint] ? true : false,
            'vary' => cf('weather_vary') ? true : false, 'dyn' => @dyn_owner == :video ? true : false,
            'after' => job[:after] }
      if (a = job[:audio])
        c['audio'] = a[:path].tr('/', '\\')
        c['audio_s'] = (a[:bytes].to_f / a[:avg]).round(2)
        c['audio_from'] = ((job[:first] || job[:k0].to_i + 1) - 1).to_f / job[:fps]
      end
      if @sky_model && job[:vm] && job[:vm][:utc0]
        tz = (sky_place(m)[2] rescue 0.0)
        c['sky'] = Time.at(job[:vm][:utc0] + tz * 3600).utc.strftime('%Y-%m-%d %H:%M')
        c['sky_x'] = (vm_sky_rate rescue nil)&.round(1)
      end
      c['clouds'] = cf('cloud_cover').to_i if @cloud_model
      c['precip'] = "#{cf('precip_kind')} #{cf('precip_intensity').to_i}" if @precip_model
      c
    rescue => fps_err
      log_error(__method__, fps_err)
      {}
    end

    # Il pezzo in corso: fotogrammi, tempi, stima della fine
    def self.vx_log_update(job)
      lg = job[:log] or return
      s = lg[:cur]
      s['last'] = job[:k]
      s['n'] = job[:k] - job[:k0].to_i
      s['el'] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - lg[:t0]).round(1)
      s['ff_s'] = job[:ff_s].round(1) if job[:ff_s]
      s['ff_at'] = job[:ff] if job[:ff]
      if (st = job[:st]) && st[:n].positive?
        s['spf'] = (st[:sum] / st[:n]).round(3)
        s['spf_min'] = st[:min].round(3)
        s['spf_max'] = st[:max].round(3)
        s['slow'] = st[:slow].map { |f, d| [f, d.round(2)] }
        s['eta'] = (((job[:stop] || job[:total]) - job[:k]) * st[:ema]).round
      end
      s['bytes'] = job[:bytes].to_i
      dir = job[:avi] ? File.dirname(job[:avi].path) : job[:dir]
      free = vx_free(dir)
      s['free'] = free if free
    end

    # Durante: ogni VX_EVERY s
    def self.vx_log_progress(job)
      lg = job[:log] or return
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if lg[:at] && now - lg[:at] < VX_EVERY
      lg[:at] = now
      vx_log_update(job)
      lg[:cur]['state'] = job[:ff] ? 'ff' : 'run'
      vx_log_write(job)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Fine, per qualunque motivo (why: :fine, :interrotto, :pieno, :errore)
    def self.vx_log_end(job, why)
      vx_refresh
      lg = job[:log] or return
      vx_log_update(job)
      s = lg[:cur]
      s.delete('eta')
      s.delete('ff_at')
      s['at1'] = vx_now
      s['state'] = { fine: 'end', pieno: 'full', errore: 'error' }[why] || 'stop'
      s['err'] = job[:err] if job[:err]
      res = job[:res] || {}
      s['res'] = res.transform_keys(&:to_s).reject { |_, v| v.nil? }
      vx_log_write(job)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.vx_log_write(job)
      lg = job[:log]
      File.binwrite(lg[:file], vx_log_text(lg[:list], lg[:cur]))
    rescue SystemCallError, IOError => fps_err
      log_error(__method__, fps_err)
    end

    # ── Il testo ──────────────────────────────────────────────────
    # Colonne occupate sullo schermo: i caratteri cinesi, giapponesi e
    # coreani ne prendono due, gli accenti combinati nessuna
    def self.vx_cw(str)
      str.to_s.each_char.sum do |ch|
        if ch.match?(/\p{Mn}|\p{Me}|\p{Cf}/) then 0
        elsif ch.match?(/[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}\uFF01-\uFF60\uFFE0-\uFFE6]/) || ch.match?(/[\u3000-\u303F]/) then 2
        else 1
        end
      end
    end

    def self.vx_pad(str, w); str.to_s + ' ' * [w - vx_cw(str), 0].max; end

    # cur: il pezzo di adesso (gli altri «in corso» sono rimasti a metà)
    def self.vx_log_text(list, cur = nil)
      s = list.last or return ''
      c = s['cfg'] || {}
      yes = t('ve.lg.yes')
      no = t('ve.lg.no')
      yn = ->(v) { v ? yes : no }
      out = []
      bar = "+#{'=' * (VX_LOG_W - 2)}+"
      out << bar
      ["#{"DagaWASD #{c['ver']}".strip} - #{t('ve.lg.title')}", "#{t('ve.lg.path')}: #{s['name']}"].each do |l|
        out << "| #{vx_pad(l, VX_LOG_W - 4)} |"
      end
      out << bar
      sec = lambda do |title, rows|
        rows = rows.reject { |_, v| v.nil? }
        out << ''
        out << " #{title.upcase}"
        lw = rows.map { |l, _| vx_cw(l) }.max.to_i
        rows.each { |l, v| out << "   #{l} #{'.' * (lw - vx_cw(l) + 3)} #{v}" }
      end
      fps = s['fps'].to_i.positive? ? s['fps'] : 30
      unless c.empty?
        sec.(t('ve.lg.model'), [
          [t('ve.lg.file'), c['model'] || t('ve.lg.never_saved')],
          [t('ve.lg.saved'), c['saved'] ? "#{yes}#{c['mtime'] ? " (#{c['mtime']})" : ''}" : "! #{t('ve.lg.unsaved')}"],
          [t('ve.lg.app'), "SketchUp #{c['su']}, #{"DagaWASD #{c['ver']}".strip}"],
          [t('ve.lg.content'), c['faces'] ? vx_f(t('ve.lg.content_v'), f: c['faces'], c: c['comps'], m: c['mats']) : nil]
        ])
        sec.(t('ve.lg.path'), [
          [t('ve.lg.keys'), c['keys'].to_i.positive? ? c['keys'] : t('ve.lg.recorded')],
          [t('ve.lg.dur'), c['dur'] && vx_clock(c['dur'] * fps + 1, fps)],
          [t('f.path_speed'), c['speed'] && format('%.2fx', c['speed'])]
        ])
        res = s['res'] || {}
        audio = c['audio'] && "#{c['audio']} (#{vx_clock(c['audio_s'] * fps + 1, fps)}), " \
                              "#{vx_f(t('ve.lg.audio_from'), t: vx_clock(c['audio_from'] * fps + 1, fps))}"
        audio += " - ! #{t('ve.lg.w_audio')}" if audio && res['audio'] == false
        sec.(t('ve.lg.video'), [
          [t(c['format'] == 'png' ? 've.lg.folder' : 've.lg.file'), c['file']],
          [t('f.path_video_format'), c['format'] == 'png' ? 'PNG' : "AVI Motion JPEG, #{vx_f(t('ve.lg.jpeg'), q: c['quality'])}"],
          [t('f.path_video_size'), "#{s['w']}x#{s['h']}#{s['mode'] == 'draft' ? " (#{t('ve.lg.m_draft')})" : ''}"],
          [t('f.path_video_fps'), s['fps']],
          [t('ve.lg.frames'), "#{s['total']} = #{vx_clock(s['total'].to_i + 1, fps)}"],
          [t('ve.lg.audio'), audio || '-'],
          [t('ve.lg.srt'), res['srt'] || '-'],
          [t('ve.lg.sheet'), res['sheet'] || '-']
        ])
        sec.(t('f.path_video_weather'), [
          [t('ve.lg.painted'), yn.(c['weather'])],
          [t('ve.lg.sky'), c['sky'] ? "#{c['sky']}#{c['sky_x'] ? "  (x#{c['sky_x']})" : ''}" : '-'],
          [t('ve.lg.clouds'), c['clouds'] ? "#{c['clouds']}%" : '-'],
          [t('ve.lg.precip'), c['precip'] ? "#{t("o.precip_kind.#{c['precip'].split.first}")} #{c['precip'].split.last}%" : '-'],
          [t('f.weather_vary'), yn.(c['vary'])],
          [t('ve.lg.dyn'), yn.(c['dyn'])]
        ])
      end
      vx_log_table(out, list)
      vx_log_summary(sec, list, s, cur)
      warn = vx_log_warnings(list, cur)
      out << ''
      out << " #{t('ve.lg.warn').upcase}"
      (warn.empty? ? [t('ve.lg.w_none')] : warn.map { |w| "! #{w}" }).each { |w| out << "   #{w}" }
      out << ''
      out << "-- #{t('ve.lg.data')} --"
      list.each { |x| out << "#D #{JSON.generate(x, ascii_only: true)}" }
      out.join("\r\n") + "\r\n"
    end

    def self.vx_log_table(out, list)
      head = ['#', t('ve.lg.c_mode'), t('ve.lg.c_start'), t('ve.lg.c_end'), t('ve.lg.c_frames'),
              t('ve.lg.c_time'), t('ve.lg.c_spf'), t('ve.lg.c_result')]
      rows = list.each_with_index.map do |x, i|
        el = x['el'] || (x['at0'] && x['at1'] && (vx_time(x['at1']) - vx_time(x['at0']) rescue nil))
        [(i + 1).to_s, t(VX_LG_MODE[x['mode']] || 've.lg.m_new'), x['at0'].to_s[0, 16], x['at1'] ? x['at1'][0, 16] : '...',
         x['n'].to_i.positive? ? "#{x['from']}-#{x['last']} (#{x['n']})" : '-',
         el ? vx_hms(el) : '-', x['spf'] ? format('%.2f', x['spf']) : '-', vx_st(x['state'])]
      end
      ws = head.each_index.map { |j| ([head] + rows).map { |r| vx_cw(r[j]) }.max }
      line = "+#{ws.map { |w| '-' * (w + 2) }.join('+')}+"
      cells = ->(r) { "|#{r.each_with_index.map { |v, j| " #{vx_pad(v, ws[j])} " }.join('|')}|" }
      out << ''
      out << " #{t('ve.lg.runs').upcase}"
      out << line
      out << cells.(head)
      out << line
      rows.each { |r| out << cells.(r) }
      out << line
    end

    # Fotogrammi fatti: l'unione dei pezzi (un tratto rifatto non ne aggiunge)
    def self.vx_log_cover(list)
      list.select { |x| x['n'].to_i.positive? }.map { |x| [x['from'].to_i, x['last'].to_i] }.sort
          .each_with_object([]) do |(a, b), acc|
            if acc.empty? || a > acc.last[1] + 1 then acc << [a, b]
            else acc.last[1] = [acc.last[1], b].max
            end
          end
    end

    def self.vx_log_summary(sec, list, s, cur)
      cov = vx_log_cover(list)
      done = cov.sum { |a, b| b - a + 1 }
      total = s['total'].to_i
      rows = [[t('ve.lg.done'), vx_f(t('ve.lg.done_v'), n: done, total: total, p: total.positive? ? format('%.1f', 100.0 * done / total) : '0')]]
      if s.equal?(cur) && s['eta'] && !s['at1']
        at = Time.now + s['eta']
        rows << [t('ve.lg.left'), vx_f(t('ve.lg.left_v'), t: vx_hms(s['eta']),
                                                           at: at.strftime(at.strftime('%F') == Time.now.strftime('%F') ? '%H:%M' : '%Y-%m-%d %H:%M'))]
      end
      if s['ff_at']
        rows << [t('ve.lg.ff'), vx_f(t('ve.lg.ff_run'), n: s['ff_at'], to: s['from'])]
      elsif s['ff_s']
        rows << [t('ve.lg.ff'), vx_f(t('ve.lg.ff_v'), n: s['from'], t: vx_hms(s['ff_s']))]
      end
      rows << [t('ve.lg.rate'), vx_f(t('ve.lg.rate_v'), avg: format('%.2f', s['spf']), min: format('%.2f', s['spf_min']), max: format('%.2f', s['spf_max']))] if s['spf']
      rows << [t('ve.lg.slow'), s['slow'].map { |f, d| "#{f} (#{format('%.1f', d)} s)" }.join(', ')] if s['slow'] && !s['slow'].empty?
      mb = s['res'] && s['res']['mb'] ? s['res']['mb'].to_f : s['bytes'].to_i / 1_048_576.0
      kb = s['n'].to_i.positive? ? (s['bytes'].to_i / 1024.0 / s['n']).round : nil
      if mb.positive?
        v = vx_f(t('ve.lg.size_v'), mb: format('%.1f', mb), kb: kb || '-')
        v += ", #{vx_f(t('ve.lg.free_v'), gb: format('%.1f', s['free'] / 1_073_741_824.0))}" if s['free']
        rows << [t('ve.lg.size'), v]
      end
      nxt = cov.empty? ? s['from'].to_i : cov.first[1] + 1           # il primo buco
      rows << [t('ve.lg.resume'), vx_f(t('ve.lg.resume_v'), n: nxt)] if done < total && nxt <= total && !%w[run ff].include?(s['state'])
      sec.(t('ve.lg.sum'), rows)
    end

    def self.vx_log_warnings(list, cur)
      w = []
      s = list.last
      c = s['cfg'] || {}
      w << t('ve.lg.w_unsaved') if c.key?('saved') && !c['saved']
      list.each_with_index do |x, i|
        w << vx_f(t('ve.lg.w_lost'), n: i + 1, last: x['last']) if %w[run ff lost].include?(x['state']) && !x.equal?(cur)
        if x['mode'] == 'append' && x['before'] && x['first'] && x['from'] != x['first'] + x['before']
          w << vx_f(t('ve.lg.w_gap'), a: x['first'] + x['before'] - 1, b: x['from'])  # in coda, ma non dal seguente
        end
        next if i.zero?
        p = list[i - 1]
        what = VX_LOG_CMP.select { |k, _| p.key?(k) && x.key?(k) && p[k] != x[k] }.values
        pc = p['cfg'] || {}
        xc = x['cfg'] || {}
        what += VX_LOG_CMP_CFG.select { |k, _| !pc.empty? && !xc.empty? && pc[k] != xc[k] }.values
        what = what.uniq.map { |k| t(k) }.uniq
        w << vx_f(t('ve.lg.w_changed'), n: i + 1, m: i, what: what.join(', ')) unless what.empty? || x['mode'] == 'draft'
      end
      cov = vx_log_cover(list)
      cov.each_cons(2).first(5).each { |(_, b), (a, _)| w << vx_f(t('ve.lg.w_gap'), a: b, b: a) }
      res = s['res'] || {}
      w << t('ve.lg.w_audio') if res['audio'] == false
      w << t('ve.lg.w_patch') if res['patch_err']
      w << vx_f(t('ve.lg.w_error'), msg: s['err']) if s['state'] == 'error'
      w << vx_f(t('ve.lg.w_full'), n: s['last'].to_i + 1) if s['state'] == 'full'
      w
    end

  end
end
