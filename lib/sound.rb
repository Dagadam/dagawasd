# DagaWASD — Suoni: passi secondo il pavimento, atterraggi; canale MCI per il tuono.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Riproduzione
    # I passi vanno con PlaySound dalla memoria (asincrono, ~0,1 ms):
    # uno alla volta, ogni passo taglia la coda del precedente. Il tuono,
    # lungo, va su MCI con un suo nome: suona insieme ai passi (UI.play_sound
    # e PlaySound userebbero lo stesso canale e un passo lo zittirebbe).
    # ══════════════════════════════════════════════════════════════
    SND_ASYNC     = 0x0001
    SND_NODEFAULT = 0x0002
    SND_MEMORY    = 0x0004
    SND_RATE      = 22_050

    def self.ensure_sound
      return @snd if @snd
      return nil if @snd_error
      require 'fiddle'
      require 'fiddle/import'
      m = Module.new
      m.extend(Fiddle::Importer)
      m.dlload('winmm')
      m.module_eval do
        extern 'int PlaySoundW(void*, void*, int)'
        extern 'int mciSendStringW(void*, void*, int, void*)'
      end
      @snd = m
    rescue => e
      @snd_error = e.message
      log_error(__method__, e)
      nil
    end

    # WAV in memoria (stringa congelata e tenuta in cache: PlaySound la legge
    # mentre suona, quindi non deve sparire).
    def self.snd_play_wav(wav)
      return unless ensure_sound
      @snd_now = wav
      @snd.PlaySoundW(wav, nil, SND_ASYNC | SND_MEMORY | SND_NODEFAULT)
    rescue => fps_err; log_error(__method__, fps_err); end

    def self.snd_mci(cmd)
      return -1 unless ensure_sound
      @snd.mciSendStringW((cmd + "\0").encode('UTF-16LE'), nil, 0, nil)
    end

    # File WAV su un canale MCI tutto suo (name); se MCI manca, UI.play_sound.
    def self.snd_play_file(path, name)
      @snd_open ||= {}
      if @snd_open[name] != path
        snd_mci("close #{name}") if @snd_open[name]
        @snd_open.delete(name)
        return UI.play_sound(path) unless snd_mci(%(open "#{path}" type waveaudio alias #{name})).zero?
        @snd_open[name] = path
      end
      snd_mci("play #{name} from 0")
    rescue => fps_err
      log_error(__method__, fps_err)
      UI.play_sound(path) rescue nil
    end

    def self.snd_wav(samples)
      data = samples.pack('s<*')
      (['RIFF', 36 + data.bytesize, 'WAVE', 'fmt ', 16, 1, 1, SND_RATE, SND_RATE * 2, 2, 16, 'data', data.bytesize]
        .pack('a4Va4a4VvvVVvva4V') + data).freeze
    end

    # ══════════════════════════════════════════════════════════════
    # Di che cosa è il pavimento
    # Nomi esaminati, dal più vicino: materiale della faccia (davanti, se no
    # dietro), poi per ogni gruppo/componente che la contiene, dal più
    # interno, materiale, nome e nome della definizione; infine i tag. Il
    # primo nome che contiene una parola nota decide. Parole con * in fondo
    # valgono come inizio di parola (legn* = legno, legname…), le altre intere.
    # Se nessuna è nota: le parole dei materiali fisici (tutte le lingue).
    # ══════════════════════════════════════════════════════════════
    STEP_WORDS = [
      ['acqua',    %w[acqua water mare sea lago lake piscina pool fiume river pozzanghera puddle]],
      ['neve',     %w[neve snow ghiaccio ice]],
      ['moquette', %w[moquette carpet* tappet* rug feltro felt tessut* fabric]],
      ['erba',     %w[erba grass* prato lawn turf vegetation vegetazione foglie leaves muschio moss]],
      ['ghiaia',   %w[ghiaia gravel ciottol* pebble* breccia]],
      ['terra',    %w[terra terren* dirt soil mud fango sabbia sand ground* earth sterrato]],
      ['legno',    %w[legn* wood* timber parquet deck tavolat* plank* rovere oak pino pine compensato plywood laminat*]],
      ['metallo',  %w[metal* steel acciaio ferro iron allumin* alumin* chrome cromo lamiera grata grate]],
      ['duro',     %w[pietr* stone* rock roccia marm* marble granit* cement* concrete brick* mattone mattoni
                      piastrell* tile* ceramic* asfalto asphalt cotto]]
    ].map { |k, ws| [k, ws.map { |w| w.end_with?('*') ? [w.chomp('*'), true] : [w, false] }] }.freeze
    STEP_FROM_PHYSICS = { 'legno' => 'legno', 'pietra' => 'duro', 'metallo' => 'metallo', 'vetro' => 'duro',
                          'gomma' => 'moquette', 'plastica' => 'duro', 'cartone' => 'legno' }.freeze

    def self.step_kind_of_name(name)
      words = name.to_s.gsub(/([[:lower:]])([[:upper:]])/, '\1 \2').downcase.split(/[^[:alpha:]]+/)
      return nil if words.empty?
      STEP_WORDS.each do |kind, list|
        return kind if list.any? { |w, pre| pre ? words.any? { |x| x.start_with?(w) } : words.include?(w) }
      end
      nil
    end

    def self.step_names(path)
      face = path.last
      names = []
      if face.is_a?(Sketchup::Face)
        m = face.material || face.back_material
        names << m.display_name if m
      end
      path[0...-1].reverse_each do |e|
        next unless e.respond_to?(:definition)
        names << e.material.display_name if e.material
        names << e.name
        names << e.definition.name
      end
      path.reverse_each { |e| names << e.layer.name if e.respond_to?(:layer) && e.layer }
      names.reject { |n| n.to_s.empty? }
    end

    def self.step_surface(path)
      return 'duro' unless path.is_a?(Array) && !path.empty?
      @step_kind_cache ||= {}
      @step_kind_cache.clear if @step_kind_cache.size > 2000
      @step_kind_cache[path] ||= begin
        names = step_names(path)
        kind = nil
        names.each { |n| break if (kind = step_kind_of_name(n)) }
        names.each { |n| break if (kind = step_physics_kind(n)) } unless kind
        kind || 'duro'
      end
    rescue => fps_err
      log_error(__method__, fps_err)
      'duro'
    end

    # Le parole della tabella dei materiali fisici (anche tradotte)
    def self.step_physics_kind(name)
      nm = name.downcase
      best = nil
      mat_matchers.each do |id, w, mode|
        next unless mode == :sub ? nm.include?(w) : word_in?(nm, w)
        best = [id, w.length] if best.nil? || w.length > best[1]
      end
      best && STEP_FROM_PHYSICS[best[0]]
    end

    # All'aperto la neve al suolo copre tutto e la pioggia bagna il duro.
    def self.step_weather(kind)
      return kind if kind == 'acqua'
      snowy = snow_level > 0.25
      wet   = precip_on? && %w[rain mix].include?(precip_kind) && precip_level > 0.15
      return kind unless snowy || (wet && kind == 'duro')
      return kind if pray(@eye_x, @eye_y, @eye_z, 0, 0, 1)      # sotto un tetto (o un albero)
      snowy ? 'neve' : 'bagnato'
    rescue => fps_err; log_error(__method__, fps_err); kind; end

    # ══════════════════════════════════════════════════════════════
    # Suoni sintetici, come il tuono: niente file da distribuire.
    # 4 varianti per superficie (tono e forza appena diversi) a 10 livelli
    # di volume, generate quando servono (~3 ms l'una) e tenute in memoria.
    # ══════════════════════════════════════════════════════════════
    STEP_GAIN = { 'duro' => 0.8, 'legno' => 0.85, 'metallo' => 0.7, 'erba' => 0.55, 'ghiaia' => 0.75,
                  'terra' => 0.7, 'neve' => 0.6, 'acqua' => 0.65, 'moquette' => 0.45, 'bagnato' => 0.8 }.freeze

    STEP_VARIANTS  = 4
    STEP_CACHE_VER = 1      # da cambiare se cambia step_samples: i file vecchi non valgono più

    def self.step_wav(kind, variant, level)
      lv = (level.clamp(0.0, 1.0) * 10).round
      return nil if lv <= 0
      @step_wavs ||= {}
      @step_wavs[[kind, variant, lv]] ||= begin
        k = STEP_GAIN[kind] * lv / 10.0
        snd_wav(step_base(kind, variant).map { |x| (x * k).round })
      end
    end

    # Forma d'onda a piena scala. Nel Ruby di SketchUp calcolarla costa
    # 30–140 ms (uno scatto, al primo passo su una superficie nuova): si
    # salva nella cartella temporanea e si calcola una volta per computer.
    def self.step_base(kind, variant)
      @step_base ||= {}
      @step_base[[kind, variant]] ||= begin
        path = File.join(step_cache_dir, "#{kind}_#{variant}.pcm")
        data = File.exist?(path) ? File.binread(path) : ''
        if data.bytesize >= 2000 && data.bytesize.even?
          data.unpack('s<*')
        else
          s = step_samples(kind, Random.new(kind.sum * 31 + variant))
          peak = s.map(&:abs).max.to_f
          k = peak > 0 ? 32_000.0 / peak : 0.0
          ints = s.map { |x| (x * k).round }
          begin                                   # scritto a parte e poi rinominato: mai un file a metà
            File.binwrite("#{path}.tmp", ints.pack('s<*'))
            File.rename("#{path}.tmp", path)
          rescue SystemCallError
            nil
          end
          ints
        end
      end
    end

    def self.step_cache_dir
      @step_cache_dir ||= begin
        require 'tmpdir'
        d = File.join(Dir.tmpdir, "dagawasd_passi_#{STEP_CACHE_VER}")
        Dir.mkdir(d) unless Dir.exist?(d)
        d
      end
    end

    # In sottofondo, fuori dalla modalità: una forma d'onda mancante ogni
    # 1,5 s finché ci sono tutte (la prima volta ~3 s di calcolo in tutto,
    # a pezzi da 0,1 s mentre SketchUp è fermo; poi solo letture dal disco).
    def self.step_warm_start
      return if @step_warm_timer || !cf('steps_enabled')
      todo = STEP_GAIN.keys.product((0...STEP_VARIANTS).to_a)
      @step_warm_timer = UI.start_timer(1.5, true) do
        next if @active
        todo.shift while !todo.empty? && (@step_base ||= {}).key?(todo.first)
        if todo.empty?
          UI.stop_timer(@step_warm_timer)
        else
          step_base(*todo.shift)
        end
      rescue => fps_err
        log_error(:step_warm_start, fps_err)
        UI.stop_timer(@step_warm_timer)
      end
    end

    # Campioni float di un passo (tallone, poi punta un po' più piano).
    def self.step_samples(kind, rnd)
      pitch = 0.92 + rnd.rand * 0.16
      len = kind == 'acqua' || kind == 'neve' ? 0.42 : 0.3
      n = (SND_RATE * len).round
      out = Array.new(n, 0.0)
      hit = lambda do |t0, amp|
        i0 = (t0 * SND_RATE).round
        step_hit(kind, rnd, pitch, n - i0).each_with_index { |v, i| out[i0 + i] += v * amp }
      end
      hit.(0.0, 1.0)
      hit.(0.035 + rnd.rand * 0.02, 0.45 + rnd.rand * 0.2) unless %w[acqua erba].include?(kind)
      out
    end

    def self.step_hit(kind, rnd, pitch, n)
      r = SND_RATE.to_f
      lp = 0.0; hp_prev = 0.0; hp = 0.0
      noise_lp = lambda { |k| lp += ((rnd.rand * 2 - 1) - lp) * k }
      noise_hp = lambda { x = rnd.rand * 2 - 1; hp = 0.85 * (hp + x - hp_prev); hp_prev = x; hp }
      sine = lambda { |t, f, d| Math.sin(2 * Math::PI * f * pitch * t) * Math.exp(-t * d) }
      grains = lambda do |count, span, k|
        g = Array.new(n, 0.0)
        count.times do
          at = (rnd.rand**1.6 * span * r).round
          amp = 0.3 + rnd.rand * 0.7
          gl = (0.002 + rnd.rand * 0.003) * r
          gl.round.times { |j| g[at + j] += (rnd.rand * 2 - 1) * amp * Math.exp(-j / gl * 3) if at + j < n }
        end
        f = 0.0
        g.map! { |v| f += (v - f) * k }
      end
      case kind
      when 'duro'
        Array.new(n) { |i| t = i / r; sine.(t, 95, 45) * 0.5 + noise_hp.() * Math.exp(-t * 95) * 0.8 }
      when 'bagnato'
        Array.new(n) do |i|
          t = i / r
          sine.(t, 95, 45) * 0.4 + noise_hp.() * Math.exp(-t * 85) * 0.7 + noise_lp.(0.35) * Math.exp(-t * 16) * 0.35
        end
      when 'legno'
        Array.new(n) do |i|
          t = i / r
          sine.(t, 190, 32) * 0.55 + sine.(t, 455, 48) * 0.3 + noise_lp.(0.45) * Math.exp(-t * 120) * 0.5
        end
      when 'metallo'
        Array.new(n) do |i|
          t = i / r
          sine.(t, 520, 11) * 0.3 + sine.(t, 1210, 14) * 0.22 + sine.(t, 1980, 19) * 0.15 + sine.(t, 2950, 26) * 0.08 +
            sine.(t, 110, 40) * 0.3 + noise_hp.() * Math.exp(-t * 140) * 0.5
        end
      when 'erba'
        Array.new(n) do |i|
          t = i / r
          env = t < 0.015 ? t / 0.015 : Math.exp(-(t - 0.015) * 13)
          noise_lp.(0.3) * env * (0.6 + 0.4 * Math.sin(t * 90 + rnd.rand * 0.3)**2)
        end
      when 'ghiaia'
        g = grains.(45, 0.15, 0.55)
        Array.new(n) { |i| t = i / r; g[i] + sine.(t, 80, 40) * 0.35 }
      when 'neve'
        g = grains.(90, 0.22, 0.22)
        Array.new(n) { |i| t = i / r; g[i] * (t < 0.03 ? t / 0.03 : 1.0) + sine.(t, 60, 30) * 0.2 }
      when 'terra'
        Array.new(n) { |i| t = i / r; noise_lp.(0.08) * Math.exp(-t * 35) * 2.0 + sine.(t, 70, 32) * 0.6 }
      when 'moquette'
        Array.new(n) { |i| t = i / r; noise_lp.(0.05) * Math.exp(-t * 42) * 2.0 + sine.(t, 60, 45) * 0.5 }
      when 'acqua'
        bubbles = Array.new(6) { [rnd.rand * 0.15, 500 + rnd.rand * 900, 30 + rnd.rand * 40] }
        Array.new(n) do |i|
          t = i / r
          env = t < 0.006 ? t / 0.006 : Math.exp(-(t - 0.006) * 9)
          b = bubbles.sum { |t0, f, d| t > t0 ? sine.(t - t0, f * (1 + (t - t0) * 2), d) * 0.12 : 0.0 }
          noise_lp.(0.5 - [t * 1.0, 0.35].min) * env + b
        end
      else
        Array.new(n, 0.0)
      end
    end

    # ══════════════════════════════════════════════════════════════
    # Quando: un passo per ogni oscillazione verticale della testa, nel
    # punto più basso (sin 2φ = −1: φ = 3π/4 e 7π/4), con la stessa
    # cadenza del dondolio anche se il dondolio è spento.
    # ══════════════════════════════════════════════════════════════
    STEP_FALLS = [0.75 * Math::PI, 1.75 * Math::PI].freeze

    def self.step_tick(dt, h_speed, crouching, bob_prev)
      walking = h_speed > 0.15 && @on_ground
      if cf('head_bob_enabled')
        prev = bob_prev; cur = @bob_phase
      else
        prev = (@step_phase ||= 0.0)
        if walking
          ratio = (h_speed / [cf('move_speed').to_f, 0.1].max).clamp(0.0, 2.2)
          @step_phase = (prev + cf('head_bob_freq').to_f * PI2 * dt * (0.55 + ratio * 0.55)) % PI2
        else
          @step_phase *= 0.85
        end
        cur = @step_phase
      end
      return unless walking && cf('steps_enabled')
      d = (cur - prev) % PI2
      return unless d > 0 && d < Math::PI           # all'indietro: il dondolio si sta spegnendo
      return unless STEP_FALLS.any? { |f| (f - prev) % PI2 < d }
      gait = if crouching then 0.45
             elsif h_speed > cf('move_speed').to_f * 1.15 then 1.0
             else 0.7
             end
      step_play(gait)
    rescue => fps_err; log_error(__method__, fps_err); end

    def self.step_land(impact)
      return unless cf('steps_enabled') && impact > 2.0
      step_play((impact / 7.0).clamp(0.55, 1.0), true)
    end

    def self.step_play(gait, landing = false)
      kind = step_weather(step_surface(@floor_hit && @floor_hit[1]))
      @step_var = ((@step_var || 0) + 1 + (landing ? 0 : rand(2))) % 4
      wav = step_wav(kind, @step_var, cf('steps_volume').to_f / 100.0 * gait)
      snd_play_wav(wav) if wav
      @step_last_kind = kind
    end

  end
end
