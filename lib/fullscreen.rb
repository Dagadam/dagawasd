# DagaWASD — Schermo intero mentre si cammina: la vista 3D copre il monitor.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # SketchUp per Windows non ha uno schermo intero. Menu, barra di stato e
    # pannelli sono disegnati da Qt dentro la finestra principale, quindi da
    # fuori non si nascondono: la finestra perde bordo e titolo e si allarga
    # finché la vista 3D (la finestra figlia più piccola che occupa almeno
    # metà di ogni lato) coincide col monitor; il resto finisce oltre i
    # bordi dello schermo. Qt rimette a posto le barre dopo ogni cambio di
    # misura, quindi si misura e si corregge a più riprese. All'uscita stile
    # e posizione tornano quelli di prima (anche ingrandita).
    # ══════════════════════════════════════════════════════════════
    FS_STEP  = 0.2        # s fra una correzione e l'altra
    FS_TRIES = 12
    FS_DROP  = 0x00C00000 | 0x00040000 | 0x01000000   # WS_CAPTION | WS_THICKFRAME | WS_MAXIMIZE
    FS_DROP_EX = 0x00000001 | 0x00000100 | 0x00000200 | 0x00020000   # DLGMODALFRAME, WINDOWEDGE, CLIENTEDGE, STATICEDGE
    GWL_STYLE   = -16
    GWL_EXSTYLE = -20

    def self.fs_active?; @fs ? true : false; end

    # Finestra da dare: x, y, larghezza, altezza perché la vista copra il
    # monitor. Rettangoli [sinistra, alto, destra, basso] in pixel di schermo.
    # status: quello che sta sotto la vista (barra di stato, con la casella
    # delle misure) resta in fondo al monitor, e la vista finisce sopra.
    def self.fs_target(mon, win, view, status = false)
      below = status ? 0 : win[3] - view[3]
      [mon[0] - (view[0] - win[0]),
       mon[1] - (view[1] - win[1]),
       (mon[2] - mon[0]) + (win[2] - win[0]) - (view[2] - view[0]),
       (mon[3] - mon[1]) + (view[1] - win[1]) + below]
    end

    def self.fs_win32
      return false unless ensure_win32
      return true if @w32.respond_to?(:SetWindowPos)
      @w32.module_eval do
        extern 'long  GetWindowLongW(void*, int)'
        extern 'long  SetWindowLongW(void*, int, long)'
        extern 'int   GetWindowPlacement(void*, void*)'
        extern 'int   SetWindowPlacement(void*, void*)'
        extern 'int   SetWindowPos(void*, void*, int, int, int, int, unsigned int)'
        extern 'void* MonitorFromWindow(void*, int)'
        extern 'int   GetMonitorInfoW(void*, void*)'
        extern 'int   EnumChildWindows(void*, void*, void*)'
        extern 'void* SendMessageW(void*, unsigned int, void*, void*)'
      end
      true
    rescue => fps_err
      log_error(__method__, fps_err)
      false
    end

    def self.fs_rect(h)
      r = "\0" * 16
      @w32.GetWindowRect(h, r)
      r.unpack('l<4')
    end

    # La vista 3D: fra le finestre figlie visibili quella più piccola che
    # occupa almeno metà della principale in larghezza e in altezza.
    def self.fs_view_rect(h)
      require 'fiddle/closure'
      m = fs_rect(h)
      mw = m[2] - m[0]; mh = m[3] - m[1]
      best = nil; area = nil
      cb = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]) do |c, _|
        if @w32.IsWindowVisible(c) != 0
          r = fs_rect(c)
          w = r[2] - r[0]; hh = r[3] - r[1]
          (best = r; area = w * hh) if w * 2 >= mw && hh * 2 >= mh && (area.nil? || w * hh < area)
        end
        1
      end
      @w32.EnumChildWindows(h, cb.to_i, nil)
      best
    end

    def self.fs_monitor(h)
      mon = @w32.MonitorFromWindow(h, 2)                   # MONITOR_DEFAULTTONEAREST
      info = [40].pack('L') + "\0" * 36
      return nil if @w32.GetMonitorInfoW(mon, info).zero?
      info[4, 16].unpack('l<4')
    end

    def self.fs_enter
      return if @fs
      return unless cf('fullscreen') && @main_hwnd && fs_win32
      h = @main_hwnd
      place = [44].pack('L') + "\0" * 40
      return if @w32.GetWindowPlacement(h, place).zero?
      style = @w32.GetWindowLongW(h, GWL_STYLE) & 0xFFFF_FFFF
      ex = @w32.GetWindowLongW(h, GWL_EXSTYLE) & 0xFFFF_FFFF
      mon = fs_monitor(h) or return
      @fs = { hwnd: h, place: place, style: style, ex: ex, mon: mon, tries: 0, status: cf('fullscreen_status') == true }
      fs_quit_observer
      @w32.SendMessageW(h, 0x0112, 0xF120, nil) if (style & 0x01000000) != 0   # WM_SYSCOMMAND SC_RESTORE
      @w32.SetWindowLongW(h, GWL_STYLE, fs_signed(style & ~FS_DROP))
      @w32.SetWindowLongW(h, GWL_EXSTYLE, fs_signed(ex & ~FS_DROP_EX))
      fs_fit(@fs)
    rescue => fps_err
      log_error(__method__, fps_err)
      fs_leave
    end

    # Una correzione: la vista misurata ora, la finestra dove deve andare;
    # finché non è già lì, un'altra fra FS_STEP secondi (timer di un colpo
    # solo: quelli ripetuti a volte si fermano da soli).
    def self.fs_fit(fs)
      return unless @fs.equal?(fs)                         # uscito, o rientrato con un altro
      h = fs[:hwnd]
      view = fs_view_rect(h)
      fs[:view] = view
      fs[:tries] += 1
      return if view.nil?
      win = fs_rect(h)
      x, y, w, hh = fs_target(fs[:mon], win, view, fs[:status])
      return if win == [x, y, x + w, y + hh]
      @w32.SetWindowPos(h, nil, x, y, w, hh, 0x0234)       # NOZORDER | NOACTIVATE | FRAMECHANGED | NOOWNERZORDER
      UI.start_timer(FS_STEP, false) { fs_fit(fs) } if fs[:tries] < FS_TRIES
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.fs_leave
      fs = @fs or return
      @fs = nil
      h = fs[:hwnd]
      @w32.SetWindowLongW(h, GWL_STYLE, fs_signed(fs[:style] & ~0x01000000))
      @w32.SetWindowLongW(h, GWL_EXSTYLE, fs_signed(fs[:ex]))
      @w32.SetWindowPos(h, nil, 0, 0, 0, 0, 0x0237)        # NOSIZE | NOMOVE | NOZORDER | NOACTIVATE | FRAMECHANGED
      @w32.SetWindowPlacement(h, fs[:place])               # posizione e stato di prima (anche ingrandita)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Il centro della vista per il cursore, finché si è a schermo intero
    def self.fs_view_center
      v = @fs && @fs[:view] or return nil
      [(v[0] + v[2]) / 2, (v[1] + v[3]) / 2]
    end

    def self.fs_signed(v); [v & 0xFFFF_FFFF].pack('L').unpack1('l'); end

    # SketchUp chiuso a schermo intero: prima la finestra torna com'era,
    # così Qt non ricorda quella senza bordi e più grande dello schermo.
    class FullscreenQuitObserver < Sketchup::AppObserver
      def onQuit; DagaWASD::FPSWalk.fs_leave; end
    end

    def self.fs_quit_observer
      return if @fs_observer
      @fs_observer = FullscreenQuitObserver.new
      Sketchup.add_observer(@fs_observer)
    end

  end
end
