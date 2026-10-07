# DagaWASD — Gamepad XInput (Xbox e compatibili): leve, grilletti, pulsanti, vibrazione.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Comandi (fissi, come nei giochi in prima persona):
    #   leva sinistra  muoversi (analogica: poco inclinata = piano)
    #   leva destra    guardarsi intorno
    #   A salto · B accovacciarsi · X aziona (Alt) · Y afferra/lancia (G)
    #   grilletto destro  calcio (tenere = caricare, come K)
    #   grilletto sinistro o leva sinistra premuta  correre
    #   croce su/giù   zoom · View (Back)  sblocca il mouse (F) · Menu (Start)  esce
    # Il gamepad conta solo con SketchUp in primo piano, come il mouse.
    # ══════════════════════════════════════════════════════════════
    XI_DLLS   = %w[xinput1_4 xinput1_3 xinput9_1_0].freeze
    XI_UP     = 0x0001
    XI_DOWN   = 0x0002
    XI_START  = 0x0010
    XI_BACK   = 0x0020
    XI_LTHUMB = 0x0040
    XI_A      = 0x1000
    XI_B      = 0x2000
    XI_X      = 0x4000
    XI_Y      = 0x8000
    PAD_BUTTON_ACTS = { 'jump' => XI_A, 'crouch' => XI_B, 'use' => XI_X, 'grab' => XI_Y }.freeze
    PAD_SCAN_EVERY  = 2.0     # s fra una ricerca e l'altra quando non ce n'è uno collegato

    def self.ensure_xinput
      return @xi if @xi
      return nil if @xi_error
      require 'fiddle'
      require 'fiddle/import'
      XI_DLLS.each do |dll|
        m = Module.new
        m.extend(Fiddle::Importer)
        begin
          m.dlload(dll)
          m.module_eval do
            extern 'int XInputGetState(int, void*)'
            extern 'int XInputSetState(int, void*)'
          end
        rescue Fiddle::DLError
          next
        end
        return @xi = m
      end
      @xi_error = 'XInput'
      nil
    rescue => e
      @xi_error = e.message
      log_error(__method__, e)
      nil
    end

    # Leva: zona morta radiale (non a croce: le diagonali restano dolci),
    # poi curva sulla sola intensità, direzione intatta.
    def self.pad_stick(x, y, dead, curve)
      x /= 32_767.0; y /= 32_767.0
      m = Math.sqrt(x * x + y * y)
      return [0.0, 0.0] if m <= dead
      k = ((m - dead) / (1.0 - dead)).clamp(0.0, 1.0)**curve / m
      [x * k, y * k]
    end

    # Legge lo stato. Uno scollegato costa (XInput lo cerca): si guarda solo
    # quello trovato, e se non c'è si ricerca ogni PAD_SCAN_EVERY s.
    def self.pad_poll(now)
      return @pad = nil unless cf('gamepad_enabled') && ensure_xinput
      buf = "\0".b * 16
      if @pad_slot
        if @xi.XInputGetState(@pad_slot, buf).zero?
          _pkt, btn, lt, rt, lx, ly, rx, ry = buf.unpack('L<S<CCs<s<s<s<')
          dead = cf('gamepad_deadzone').to_f.clamp(0.0, 0.6); curve = cf('gamepad_curve').to_f.clamp(1.0, 3.0)
          @pad = { btn: btn, lt: lt / 255.0, rt: rt / 255.0,
                   move: pad_stick(lx, ly, dead, 1.0), look: pad_stick(rx, ry, dead, curve) }
          return @pad
        end
        @pad_slot = @pad = nil
        Sketchup.status_text = t('rt.pad_off')
      end
      return nil if @pad_scan_at && now - @pad_scan_at < PAD_SCAN_EVERY
      @pad_scan_at = now
      4.times do |i|
        next unless @xi.XInputGetState(i, buf).zero?
        @pad_slot = i
        Sketchup.status_text = t('rt.pad_on')
        return pad_poll(now)
      end
      nil
    rescue => fps_err
      log_error(__method__, fps_err)
      @pad = nil
    end

    def self.pad_pressed?(act)
      p = @pad or return false
      case act
      when 'run'  then (p[:btn] & XI_LTHUMB) != 0 || p[:lt] > 0.5
      when 'kick' then p[:rt] > 0.5
      else (b = PAD_BUTTON_ACTS[act]) ? (p[:btn] & b) != 0 : false
      end
    end

    # Spostamento della leva sinistra: [destra, avanti], nil se a riposo.
    def self.pad_move
      p = @pad or return nil
      x, y = p[:move]
      x == 0.0 && y == 0.0 ? nil : [x, y]
    end

    # Leva destra: gradi al secondo a fondo corsa, rallenta zoomando come il mouse.
    def self.pad_stick_look(dt)
      p = @pad or return
      x, y = p[:look]
      return if x == 0.0 && y == 0.0
      k = cf('gamepad_look_speed').to_f * DEG * dt * (@zoom_fov / [@base_fov, 1.0].max).clamp(0.05, 2.0)
      @yaw   = (@yaw - x * k) % PI2
      ysign  = cf('invert_y') ? -1.0 : 1.0
      @pitch = (@pitch + y * k * 0.75 * ysign).clamp(-PITCH_LIMIT, PITCH_LIMIT)
    end

    # Pulsanti a scatto (solo alla pressione). Ritorna :stop per uscire.
    # La croce su/giù fa da rotella (zoom, o distanza dell'oggetto in mano):
    # uno scatto alla pressione, poi uno ogni 0,1 s tenendo premuto.
    def self.pad_buttons(dt)
      btn = @pad ? @pad[:btn] : 0
      down = btn & ~(@pad_prev_btn || 0xFFFF)     # nil = appena entrati: niente scatti
      @pad_prev_btn = btn
      return :stop if (down & XI_START) != 0
      toggle_mouse_freeze if (down & XI_BACK) != 0
      dir = (btn & XI_UP) != 0 ? 1 : (btn & XI_DOWN) != 0 ? -1 : 0
      if dir == 0
        @pad_wheel_wait = nil
      elsif (down & (XI_UP | XI_DOWN)) != 0
        on_wheel(dir)
        @pad_wheel_wait = 0.35
      elsif @pad_wheel_wait && (@pad_wheel_wait -= dt) <= 0
        on_wheel(dir)
        @pad_wheel_wait += 0.1
      end
      nil
    end

    # Vibrazione breve, proporzionale (0–1); si spegne da sola in pad_rumble_tick.
    def self.pad_rumble(strength, secs = 0.12)
      return unless @pad && @pad_slot && cf('gamepad_rumble') && ensure_xinput
      v = (strength.clamp(0.0, 1.0) * 65_535).round
      @xi.XInputSetState(@pad_slot, [v, (v * 0.6).round].pack('S<S<'))
      @pad_rumble_left = secs
    rescue => fps_err; log_error(__method__, fps_err); end

    # dt = nil: spegnere subito (uscita dalla modalità)
    def self.pad_rumble_tick(dt = nil)
      return unless @pad_rumble_left
      return if dt && (@pad_rumble_left -= dt) > 0
      @xi.XInputSetState(@pad_slot, [0, 0].pack('S<S<')) if @xi && @pad_slot
      @pad_rumble_left = nil
    rescue => fps_err; log_error(__method__, fps_err); end

  end
end
