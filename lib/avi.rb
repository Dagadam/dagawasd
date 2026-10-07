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
    #     LIST 'hdrl'  avih · LIST 'strl' (strh, strf)    ← intestazione fissa, 224 byte
    #     LIST 'movi'  '00dc' JPEG, '00dc' JPEG, …
    #     idx1         16 byte per fotogramma
    # Numero di fotogrammi e lunghezze si riscrivono alla chiusura: anche un
    # video interrotto a metà resta valido. RIFF ha dimensioni a 32 bit:
    # oltre AVI_MAX si rifiutano altri fotogrammi (full? = vero).
    # ══════════════════════════════════════════════════════════════
    class MjpegAvi
      HEADER  = 224
      AVI_MAX = 3_900_000_000

      attr_reader :frames, :path

      def initialize(path, width, height, fps)
        @path = path; @w = width.to_i; @h = height.to_i; @fps = fps.to_i
        @io = File.open(path, 'wb')
        @io.write(header(0, 0, 0))
        @index = []
        @frames = 0
        @biggest = 0
        @pos = 4                       # scostamenti dell'indice: dal 'movi' del LIST
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
        @io.write(header(@frames, @biggest, movi, riff))
        @io.close
        @io = nil
      end

      private

      def header(frames, biggest, movi, riff = 0)
        buf = biggest + 8
        avih = [1_000_000 / [@fps, 1].max, buf * @fps, 0, 0x10, frames, 0, 1, buf, @w, @h, 0, 0, 0, 0].pack('V14')
        strh = ['vids', 'MJPG', 0, 0, 0, 0, 1, @fps, 0, frames, buf, 0xFFFF_FFFF, 0, 0, 0, @w, @h]
               .pack('a4a4VvvVVVVVVVVs<s<s<s<')
        strf = [40, @w, @h, 1, 24, 'MJPG', @w * @h * 3, 0, 0, 0, 0].pack('Vl<l<vva4VVVVV')
        strl = ['strh', strh.bytesize].pack('a4V') + strh + ['strf', strf.bytesize].pack('a4V') + strf
        hdrl = ['avih', avih.bytesize].pack('a4V') + avih + ['LIST', strl.bytesize + 4, 'strl'].pack('a4Va4') + strl
        ['RIFF', riff, 'AVI ', 'LIST', hdrl.bytesize + 4, 'hdrl'].pack('a4Va4a4Va4') + hdrl +
          ['LIST', movi, 'movi'].pack('a4Va4')
      end
    end

  end
end
