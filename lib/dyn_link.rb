# DagaWASD — Collegamento con DagaDyn (oggetti animati), se è installata.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
#
# DagaDyn anima le proprietà degli oggetti (posizione, rotazione, colore…).
# Da sola usa view.animation, che è unica: mentre DagaWASD cammina,
# esplora, riproduce un percorso o registra un video il tempo lo batte
# DagaWASD, con DagaDyn.ext_tick. Così gli oggetti si muovono anche qui:
#
# - camminando ed esplorando, in tempo reale;
# - nei video, al tempo del video (fotogramma k → k / fps secondi): un
#   video lento da registrare resta comunque fluido;
# - le piattaforme animate portano il giocatore (dyn_carry), ruotandolo
#   con loro;
# - gli oggetti animati non si prendono e non si calciano (dyn_kinematic?);
# - il tasto Aziona fa partire quelli che partono «quando li si aziona».
#
# Ogni metodo non fa nulla se DagaDyn non c'è (o è di una versione senza
# questi metodi) e non solleva mai: un errore di DagaDyn non ferma la
# camminata.
module DagaWASD
  module FPSWalk

    def self.dyn?
      defined?(::DagaDyn) && ::DagaDyn.respond_to?(:api_version) && ::DagaDyn.api_version >= 1
    rescue StandardError
      false
    end

    # owner: :walk, :explore, :path, :video. Ritorna true se DagaDyn anima qualcosa.
    def self.dyn_begin(owner)
      return false unless dyn?
      @dyn_owner = owner
      @dyn_t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ::DagaDyn.ext_begin(owner)
    rescue => fps_err
      log_error(__method__, fps_err)
      false
    end

    # elapsed: secondi dall'inizio nell'orologio di chi chiama (nil: tempo reale)
    def self.dyn_tick(elapsed = nil)
      return unless @dyn_owner && dyn?
      elapsed ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) - @dyn_t0
      ::DagaDyn.ext_tick(elapsed)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.dyn_end(owner)
      return unless @dyn_owner == owner
      @dyn_owner = nil
      ::DagaDyn.ext_end(owner) if dyn?
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # La cosa sotto i piedi si è mossa in questo passo: il giocatore la segue
    # (posizione, quota del pavimento e direzione dello sguardo).
    def self.dyn_carry
      return unless @dyn_owner && @on_ground && @floor_hit && dyn?
      d = ::DagaDyn.carry(@floor_hit[1]) or return
      feet = Geom::Point3d.new(@eye_x, @eye_y, @floor_z_in.to_f)
      moved = feet.transform(d)
      @eye_x = moved.x.to_f
      @eye_y = moved.y.to_f
      dz = moved.z.to_f - @floor_z_in.to_f
      @floor_z_in = moved.z.to_f
      @eye_z += dz
      dir = Geom::Vector3d.new(Math.cos(@yaw), Math.sin(@yaw), 0).transform(d)
      @yaw = Math.atan2(dir.y, dir.x) if dir.x.abs + dir.y.abs > 1e-9
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Animato da DagaDyn: si muove da solo, la fisica non lo sposta.
    def self.dyn_kinematic?(path)
      @dyn_owner && dyn? ? ::DagaDyn.kinematic?(path) : false
    rescue => fps_err
      log_error(__method__, fps_err)
      false
    end

    # Tasto Aziona: true se DagaDyn ha fatto partire qualcosa (la barra di
    # stato la scrive DagaDyn).
    def self.dyn_use(path)
      return false unless @dyn_owner && dyn?
      name = ::DagaDyn.use(path)
      Sketchup.status_text = "[#{t('rt.use')}] #{name}" if name
      !name.nil?
    rescue => fps_err
      log_error(__method__, fps_err)
      false
    end

  end
end
