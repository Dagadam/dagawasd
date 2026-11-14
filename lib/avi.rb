# DagaWASD — Video AVI Motion JPEG scritto in Ruby (per i percorsi, lib/path.rb).
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Un AVI "MJPG" è una fila di JPEG interi in un contenitore RIFF con un
    # indice in fondo: niente codifica video, quindi niente programmi
    # esterni (SketchUp scrive i JPEG). Pesa 5–10 volte un MP4, ma lo
    # aprono il lettore di Windows, VLC e i programmi di montaggio.
    #
    #   RIFF 'AVI '
    #     LIST 'hdrl'  avih · LIST 'strl' (strh, strf) [· LIST 'strl' audio]
    #     LIST 'movi'  '00dc' JPEG, '00dc' JPEG, … [ogni secondo '01wb' audio]
    #     idx1         16 byte per pezzo
    # Numero di fotogrammi e lunghezze si riscrivono alla chiusura: anche un
    # video interrotto a metà resta valido. RIFF ha dimensioni a 32 bit:
    # oltre AVI_MAX si rifiutano altri fotogrammi (full? = vero).
    #
    # Mentre si esporta il video è solo immagini, con l'intestazione fissa
    # di HEADER byte. Audio e tratti rifatti arrivano alla fine, rifacendo
    # il file da capo (MjpegAvi.rebuild): i fotogrammi si copiano com'erano.
    #
    # In coda (MjpegAvi.append): un video già scritto da qui si riapre e i
    # fotogrammi nuovi vanno dopo i suoi. L'indice si rifà leggendo i
    # '00dc' di fila, quindi va bene anche un video rimasto senza chiusura
    # (SketchUp chiuso a metà: niente idx1, intestazione a zero); un
    # fotogramma scritto a metà si scarta. Uno con l'audio prima lo perde
    # (rebuild senza audio): alla fine, se c'è, si rimette su tutto il video.
    # ══════════════════════════════════════════════════════════════
    class MjpegAvi
      HEADER   = 224
      AVI_MAX  = 3_900_000_000
      RIFF_MAX = 4_290_000_000           # oltre, le dimensioni a 32 bit non bastano

      attr_reader :frames, :path, :before

      # Un video di questa classe con le stesse misure e gli stessi fps,
      # riaperto per aggiungere in coda; nil se non lo è.
      def self.append(path, width, height, fps)
        info = probe(path) or return nil
        return nil unless info[:w] == width.to_i && info[:h] == height.to_i && info[:fps] == fps.to_i
        if info[:audio] || info[:movi] != HEADER - 4
          rebuild(path, info) or return nil          # solo immagini, con l'intestazione fissa
          info = probe(path) or return nil
        end
        new(path, width, height, fps, info)
      end

      # Misure, fps e fotogrammi di un AVI scritto da questa classe (anche
      # mai chiuso, anche con l'audio); nil se non lo è o non si legge.
      # index: [posizione dal 'movi', lunghezza] di ogni fotogramma.
      def self.probe(path)
        File.open(path, 'rb') do |io|
          size = io.size
          head = io.read(12)
          return nil unless head && head.bytesize == 12 && head[0, 4] == 'RIFF' && head[8, 4] == 'AVI '
          pos = 12
          hdrl = movi = nil
          while pos + 12 <= size
            io.seek(pos)
            id, n, kind = io.read(12).unpack('a4Va4')
            if id == 'LIST' && kind == 'hdrl'
              hdrl = io.read([n - 4, 4096].min)
            elsif id == 'LIST' && kind == 'movi'
              movi = pos + 8
              break
            end
            break unless id.match?(/\A[ -~]{4}\z/)
            pos += 8 + n + (n & 1)
          end
          return nil unless hdrl && movi
          st = streams(hdrl) or return nil
          v = st[:video]
          return nil unless v && v[:handler] == 'MJPG' && v[:scale] == 1
          pos = movi + 4
          index = []
          biggest = 0
          sound = 0
          while pos + 8 <= size
            io.seek(pos)
            id, n = io.read(8).unpack('a4V')
            break unless %w[00dc 01wb JUNK].include?(id) && pos + 8 + n <= size
            if id == '00dc'
              index << [pos - movi, n]
              biggest = n if n > biggest
            elsif id == '01wb'
              sound += n
            end
            pos += 8 + n + (n & 1)
          end
          { w: st[:w], h: st[:h], fps: v[:rate], index: index, biggest: biggest, end: pos, movi: movi,
            audio: st[:audio], audio_bytes: sound }
        end
      rescue SystemCallError, IOError
        nil
      end

      # avih e i flussi di LIST 'hdrl' (senza le 4 lettere 'hdrl')
      def self.streams(buf)
        out = { audio: false }
        walk = lambda do |from, to|
          while from + 8 <= to
            id, n = buf.byteslice(from, 8).unpack('a4V')
            break unless n && from + 8 + n <= buf.bytesize
            if id == 'avih' && n >= 40
              out[:w], out[:h] = buf.byteslice(from + 8 + 32, 8).unpack('VV')
            elsif id == 'LIST' && buf.byteslice(from + 8, 4) == 'strl'
              walk.(from + 12, from + 8 + n)
            elsif id == 'strh' && n >= 32
              type, handler = buf.byteslice(from + 8, 8).unpack('a4a4')
              scale, rate = buf.byteslice(from + 8 + 20, 8).unpack('VV')
              if type == 'vids' then out[:video] ||= { handler: handler, scale: scale, rate: rate }
              elsif type == 'auds' then out[:audio] = true
              end
            end
            from += 8 + n + (n & 1)
          end
        end
        walk.(0, buf.bytesize)
        out[:w] ? out : nil
      end

      # ── WAV ─────────────────────────────────────────────────────
      # Un .wav PCM (8, 16, 24 o 32 bit): formato e dove stanno i suoni;
      # nil se non lo è.
      def self.wav(path)
        File.open(path, 'rb') do |io|
          size = io.size
          head = io.read(12)
          return nil unless head && head.bytesize == 12 && head[0, 4] == 'RIFF' && head[8, 4] == 'WAVE'
          fmt = data = nil
          pos = 12
          while pos + 8 <= size && !(fmt && data)
            io.seek(pos)
            id, n = io.read(8).unpack('a4V')
            if id == 'fmt ' then fmt = io.read([n, 40].min)
            elsif id == 'data' then data = [pos + 8, [n, size - pos - 8].min]
            end
            pos += 8 + n + (n & 1)
          end
          return nil unless fmt && data && fmt.bytesize >= 16
          tag, ch, rate, _avg, align, bits = fmt.unpack('vvVVvv')
          tag = fmt.byteslice(24, 2).unpack1('v') if tag == 0xFFFE && fmt.bytesize >= 26   # WAVE_FORMAT_EXTENSIBLE: il sottoformato
          return nil unless tag == 1 && ch.between?(1, 8) && rate.positive? && [8, 16, 24, 32].include?(bits) && align == ch * bits / 8
          { path: path, ch: ch, rate: rate, bits: bits, align: align, avg: rate * align, at: data[0],
            bytes: data[1] - data[1] % align }
        end
      rescue SystemCallError, IOError
        nil
      end

      # ── Rifare il file ──────────────────────────────────────────
      # Riscrive path (descritto da info = probe) da capo, in un file
      # accanto che poi prende il suo posto:
      #   seg, at: i fotogrammi del video seg (un probe, tutti) al posto di
      #            quelli di path dall'indice at (da 0), tanti quanti sono;
      #   audio:   un wav (MjpegAvi.wav), dal byte skip dei suoni: un secondo
      #            di audio prima di ogni secondo di fotogrammi. Mai oltre
      #            la fine del video; un wav più corto finisce prima.
      # Ritorna { frames:, no_audio: } o nil se non si è potuto (path resta
      # com'era). Se il file verrebbe troppo grande l'audio resta fuori
      # (no_audio vero).
      def self.rebuild(path, info, seg: nil, at: 0, audio: nil, skip: 0)
        tmp = "#{path}.tmp"
        src = File.open(path, 'rb')
        sio = seg && File.open(seg[:path], 'rb')
        begin
          fps = info[:fps]
          list = info[:index].map { |off, n| [src, info[:movi] + off + 8, n] }
          if seg
            mine = seg[:index].map { |off, n| [sio, seg[:movi] + off + 8, n] }
            list[at, mine.size] = mine
          end
          vbytes = list.sum { |_, _, n| 8 + n + (n & 1) }
          abytes = 0
          if audio
            have = [audio[:bytes] - skip, 0].max
            want = (list.size.to_f / fps * audio[:rate]).floor * audio[:align]
            abytes = [have, want].min
            per = audio[:avg]
            chunks = (abytes.to_f / per).ceil
            abytes = 0 if HEADER + 200 + vbytes + abytes + chunks * 9 + (list.size + chunks) * 16 > RIFF_MAX
          end
          aud = abytes.positive? ? audio : nil
          frames = write(tmp, info[:w], info[:h], fps, list, aud, skip, abytes)
          [src, sio].compact.each(&:close)
          File.rename(tmp, path)
          { frames: frames, no_audio: audio && !aud ? true : false }
        ensure
          [src, sio].compact.each { |f| f.close unless f.closed? }
          File.delete(tmp) if File.exist?(tmp)
        end
      rescue SystemCallError, IOError
        nil
      end

      def self.write(file, w, h, fps, list, audio, skip, abytes)
        File.open(file, 'wb') do |o|
          o.write(header(w, h, fps, 0, 0, 0, 0, audio))
          movi = o.pos - 4                       # il 'movi' del LIST: da lì le posizioni dell'indice
          idx = []
          vbig = abig = 0
          left = abytes
          per = audio ? audio[:avg] : 0
          wio = audio && File.open(audio[:path], 'rb')
          begin
            wio&.seek(audio[:at] + skip)
            list.each_with_index do |(io, at, n), i|
              if wio && left.positive? && (i % fps).zero?
                len = [per, left].min
                pcm = wio.read(len).to_s
                pcm += "\0".b * (len - pcm.bytesize) if pcm.bytesize < len
                idx << ['01wb', o.pos - movi, len]
                o.write(['01wb', len].pack('a4V'), pcm)
                o.write("\0") if len.odd?
                left -= len
                abig = len if len > abig
              end
              io.seek(at)
              jpeg = io.read(n)
              raise IOError, 'fotogramma illeggibile' unless jpeg && jpeg.bytesize == n
              idx << ['00dc', o.pos - movi, n]
              o.write(['00dc', n].pack('a4V'), jpeg)
              o.write("\0") if n.odd?
              vbig = n if n > vbig
            end
          ensure
            wio&.close
          end
          size = o.pos - movi
          o.write(['idx1', 16 * idx.size].pack('a4V'))
          o.write(idx.map { |id, off, n| [id, 0x10, off, n].pack('a4VVV') }.join)
          riff = o.pos - 8
          o.seek(0)
          o.write(header(w, h, fps, list.size, vbig, size, riff, audio, abytes, abig))
        end
        list.size
      end

      # L'intestazione: HEADER byte senza audio, più lunga con
      def self.header(w, h, fps, frames, biggest, movi, riff = 0, audio = nil, abytes = 0, abig = 0)
        buf = biggest + 8
        rate = buf * fps + (audio ? audio[:avg] : 0)
        sug = audio ? [buf, abig + 8].max : buf
        avih = [1_000_000 / [fps, 1].max, rate, 0, audio ? 0x110 : 0x10, frames, 0, audio ? 2 : 1, sug, w, h, 0, 0, 0, 0].pack('V14')
        strh = ['vids', 'MJPG', 0, 0, 0, 0, 1, fps, 0, frames, buf, 0xFFFF_FFFF, 0, 0, 0, w, h]
               .pack('a4a4VvvVVVVVVVVs<s<s<s<')
        strf = [40, w, h, 1, 24, 'MJPG', w * h * 3, 0, 0, 0, 0].pack('Vl<l<vva4VVVVV')
        lists = [strl(strh, strf)]
        if audio
          al = audio[:align]
          ah = ['auds', "\0\0\0\0", 0, 0, 0, 0, al, audio[:avg], 0, abytes / al, abig, 0xFFFF_FFFF, al, 0, 0, 0, 0]
               .pack('a4a4VvvVVVVVVVVs<s<s<s<')
          af = [1, audio[:ch], audio[:rate], audio[:avg], al, audio[:bits], 0].pack('vvVVvvv')   # WAVEFORMATEX, PCM
          lists << strl(ah, af)
        end
        hdrl = ['avih', avih.bytesize].pack('a4V') + avih + lists.join
        ['RIFF', riff, 'AVI ', 'LIST', hdrl.bytesize + 4, 'hdrl'].pack('a4Va4a4Va4') + hdrl +
          ['LIST', movi, 'movi'].pack('a4Va4')
      end

      def self.strl(strh, strf)
        body = ['strh', strh.bytesize].pack('a4V') + strh + ['strf', strf.bytesize].pack('a4V') + strf
        ['LIST', body.bytesize + 4, 'strl'].pack('a4Va4') + body
      end

      def initialize(path, width, height, fps, resume = nil)
        @path = path; @w = width.to_i; @h = height.to_i; @fps = fps.to_i
        if resume
          @io = File.open(path, 'r+b')
          @io.truncate(resume[:end])     # via idx1 e un fotogramma a metà
          @io.seek(resume[:end])
          @index = resume[:index].dup
          @biggest = resume[:biggest]
          @pos = resume[:end] - (HEADER - 4)
        else
          @io = File.open(path, 'wb')
          @io.write(self.class.header(@w, @h, @fps, 0, 0, 0))
          @index = []
          @biggest = 0
          @pos = 4                       # scostamenti dell'indice: dal 'movi' del LIST
        end
        @frames = @index.size
        @before = @frames                # quelli che c'erano già
      end

      def full?; @io.nil? || @io.pos > AVI_MAX; end

      def add(jpeg)
        raise IOError, 'AVI chiuso' unless @io
        raise ArgumentError, 'non è un JPEG' unless jpeg.byteslice(0, 2) == "\xFF\xD8".b
        n = jpeg.bytesize
        @io.write(['00dc', n].pack('a4V'), jpeg)
        @io.write("\0") if n.odd?
        @index << [@pos, n]
        @pos += 8 + n + (n & 1)
        @biggest = n if n > @biggest
        @frames += 1
      end

      def close
        return unless @io
        movi = @io.pos - (HEADER - 4)  # dimensione del LIST 'movi': da 'movi' in poi
        @io.write(['idx1', 16 * @index.size].pack('a4V'))
        @io.write(@index.map { |off, n| ['00dc', 0x10, off, n].pack('a4VVV') }.join)   # 0x10 = fotogramma chiave
        riff = @io.pos - 8
        @io.seek(0)
        @io.write(self.class.header(@w, @h, @fps, @frames, @biggest, movi, riff))
        @io.close
        @io = nil
      end
    end

  end
end
