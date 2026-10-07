# DagaWASD — Win32: cursore, finestra in primo piano, Ctrl+PagSu, hook della tastiera.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Lazy Win32
    # ══════════════════════════════════════════════════════════════
    def self.ensure_win32
      return true  if @w32
      return false if @w32_error
      begin
        require 'fiddle'
        require 'fiddle/import'
        m = Module.new
        m.extend(Fiddle::Importer)
        m.dlload('user32', 'kernel32')
        m.module_eval do
          extern 'void* SetWindowsHookExA(int, void*, void*, int)'
          extern 'int   UnhookWindowsHookEx(void*)'
          extern 'long  CallNextHookEx(void*, int, void*, void*)'
          extern 'void* GetModuleHandleA(void*)'
          extern 'int   GetCursorPos(void*)'
          extern 'int   SetCursorPos(int, int)'
          extern 'int   ShowCursor(int)'
          extern 'void* GetForegroundWindow()'
          extern 'int   SetForegroundWindow(void*)'
          extern 'int   GetClientRect(void*, void*)'
          extern 'int   ClientToScreen(void*, void*)'
          extern 'int   GetAsyncKeyState(int)'
          extern 'int   GetWindowThreadProcessId(void*, void*)'
          extern 'int   GetCurrentProcessId()'
          extern 'void* GetAncestor(void*, int)'
          extern 'void  keybd_event(int, int, int, void*)'
        end
        m.const_set(:WH_KEYBOARD_LL, 13)
        m.const_set(:WM_KEYDOWN,    0x0100)
        m.const_set(:WM_KEYUP,      0x0101)
        m.const_set(:WM_SYSKEYDOWN, 0x0104)
        m.const_set(:WM_SYSKEYUP,   0x0105)
        @w32 = m
        true
      rescue => e
        @w32_error = e.message
        false
      end
    end

    # ══════════════════════════════════════════════════════════════
    # Win32 helpers
    # ══════════════════════════════════════════════════════════════
    def self.cursor_pos
      buf = String.new("\x00" * 8, encoding: 'BINARY')
      @w32.GetCursorPos(buf)
      buf.unpack('l<2')
    rescue => fps_err; log_error(__method__, fps_err); [0, 0]; end

    def self.viewport_center
      hwnd = @main_hwnd || @w32.GetForegroundWindow
      rect = String.new("\x00" * 16, encoding: 'BINARY')
      @w32.GetClientRect(hwnd, rect)
      _l, _t, w, h = rect.unpack('l<4')
      pt = [w / 2, h / 2].pack('l<2')
      @w32.ClientToScreen(hwnd, pt)
      pt.unpack('l<2')
    rescue => fps_err; log_error(__method__, fps_err); [960, 540]; end

    def self.hide_cursor
      return if @cursor_hidden
      begin
        @hide_calls = 0
        while @w32.ShowCursor(0) >= 0
          @hide_calls += 1
          break if @hide_calls > 20
        end
        @hide_calls += 1
      rescue => fps_err; log_error(__method__, fps_err); end
      @cursor_hidden = true
    end

    def self.show_cursor
      return unless @cursor_hidden
      begin
        (@hide_calls || 1).times { @w32.ShowCursor(1) }
      rescue => fps_err; log_error(__method__, fps_err); end
      @hide_calls = 0
      @cursor_hidden = false
    end

    def self.key?(vk); @keys[vk] == true; end

    # KBDLLHOOKSTRUCT (x64): vkCode, scanCode, flags, time (DWORD) e poi
    # dwExtraInfo (ULONG_PTR) a offset 16. → [vk, scan, flags, extra]
    def self.hook_struct(bytes)
      vk, scan, flags, _time, extra = bytes.unpack('L<L<L<L<Q<')
      [vk, scan, flags, extra]
    end

    # Tasto iniettato da FPS stesso (flag LLKHF_INJECTED e la nostra firma)?
    def self.own_injection?(flags, extra)
      (flags & 0x10) != 0 && extra == INJECT_TAG
    end

    # Direzione del tastierino (:pad_up …) per codice di scansione e flag
    # dell'hook, nil se non è 8 4 6 2 del tastierino (frecce vere: flag 1).
    def self.pad_dir(scan, flags)
      (flags & 0x01).zero? ? PAD_LOOK_SCAN[scan] : nil
    end

    # Finestra principale di SketchUp: quella in primo piano all'avvio o, se
    # FPS parte dal pannello, la sua proprietaria (GA_ROOTOWNER = 3).
    def self.find_main_window
      fg = @w32.GetForegroundWindow
      return nil if fg.nil? || fg.to_i == 0
      root = @w32.GetAncestor(fg, 3)
      root && root.to_i != 0 ? root.to_i : fg.to_i
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Avviato dal pannello, il primo piano resta al dialogo: lo si riporta
    # alla finestra principale, altrimenti mouse e tasti non arriverebbero
    # a FPS finché l'utente non clicca sul modello. SketchUp è già in primo
    # piano, quindi Windows concede il cambio.
    def self.focus_main_window
      return unless @main_hwnd
      fg = @w32.GetForegroundWindow
      return if fg && fg.to_i == @main_hwnd
      @w32.SetForegroundWindow(@main_hwnd)
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # FPS agisce su mouse e tastiera solo con la finestra principale di
    # SketchUp in primo piano: passando a un'altra applicazione (o al pannello)
    # i tasti arrivano normalmente e il mouse non viene più ricentrato.
    def self.main_focused?
      return true unless @main_hwnd
      fg = @w32.GetForegroundWindow
      fg && fg.to_i == @main_hwnd
    rescue => fps_err; log_error(__method__, fps_err); true; end

    def self.alt?
      key?(VK_ALT) || key?(VK_LALT) || key?(VK_RALT)
    end

    def self.shift?
      (@w32.GetAsyncKeyState(VK_LSHIFT) & 0x8000) != 0 ||
      (@w32.GetAsyncKeyState(VK_RSHIFT) & 0x8000) != 0
    end

    def self.async_down?(vk)
      (@w32.GetAsyncKeyState(vk) & 0x8000) != 0
    rescue => fps_err; log_error(__method__, fps_err); false; end

    # La finestra in primo piano appartiene a SketchUp (finestra principale o
    # un suo dialogo)? GetAsyncKeyState legge la tastiera globale: senza questo
    # controllo Ctrl+PagSu premuto in un'altra applicazione avvierebbe FPS.
    def self.sketchup_foreground?
      hwnd = @w32.GetForegroundWindow
      return false if hwnd.nil? || hwnd.to_i == 0
      buf = String.new("\x00" * 4, encoding: 'BINARY')
      @w32.GetWindowThreadProcessId(hwnd, buf)
      @pid ||= @w32.GetCurrentProcessId & 0xFFFFFFFF
      buf.unpack1('L<') == @pid
    rescue => fps_err; log_error(__method__, fps_err); false; end

    # ══════════════════════════════════════════════════════════════
    # Scorciatoie globali Ctrl+PagSu (modalità FPS spenta) e Ctrl+Home
    # L'hook tastiera esiste solo in modalità FPS: da spenti un timer leggero
    # legge lo stato dei tasti. Un polling a 20 Hz costa niente, mentre un hook
    # sempre attivo rallenterebbe la tastiera di tutto il sistema ogni volta
    # che Ruby è occupato. Ctrl+PagGiù è gestito dall'hook (vedi install_hook).
    # ══════════════════════════════════════════════════════════════
    def self.start_hotkey_poller
      return if @hotkey_timer
      return unless ensure_win32
      @prev_hotkey  = false
      @prev_panel_hotkey = false
      @hotkey_timer = UI.start_timer(0.05, true) { poll_hotkey }
    end

    def self.poll_hotkey
      poll_panel_hotkey
      down = async_down?(VK_CONTROL) && async_down?(VK_PRIOR)
      fire = down && !@prev_hotkey
      # Aggiornato anche da attivi: altrimenti, dopo l'uscita, il primo
      # Ctrl+PagSu verrebbe scambiato per il tasto ancora tenuto premuto.
      @prev_hotkey = down
      return if @active || !fire
      start if sketchup_foreground?
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Ctrl+Home apre il pannello (o lo porta davanti se è già aperto), anche
    # in modalità FPS: lì prima sblocca il mouse come F, sennò il cursore
    # resterebbe nascosto sopra il pannello.
    def self.poll_panel_hotkey
      down = async_down?(VK_CONTROL) && async_down?(VK_HOME)
      fire = down && !@prev_panel_hotkey
      @prev_panel_hotkey = down
      return unless fire && sketchup_foreground?
      toggle_mouse_freeze if @active && !@mouse_freeze
      show_panel
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # ══════════════════════════════════════════════════════════════
    # Hook tastiera WH_KEYBOARD_LL
    # ══════════════════════════════════════════════════════════════
    def self.install_hook
      @hook_cb = Fiddle::Closure::BlockCaller.new(
        Fiddle::TYPE_LONG,
        [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]
      ) do |n_code, w_param, l_param|
        begin
          raw   = n_code >= 0 ? hook_struct(Fiddle::Pointer.new(l_param.to_i)[0, 24]) : nil
          # I tasti che iniettiamo noi (Alt+Tab) passano senza toccarli; quelli
          # iniettati da altri (desktop remoto) contano come tasti veri.
          injected = raw && own_injection?(raw[2], raw[3])
          focused  = raw && !injected && main_focused?
          if raw && !focused && !injected
            @keys.clear if @keys.any? { |_, v| v }   # focus perso: niente tasti "incollati"
            @alt_injected = false                   # Alt+Tab ha portato via il focus
          end
          if focused
            vk  = raw[0]
            msg = w_param.to_i
            down = (msg == @w32::WM_KEYDOWN || msg == @w32::WM_SYSKEYDOWN)
            up   = (msg == @w32::WM_KEYUP   || msg == @w32::WM_SYSKEYUP)
            # Tastierino 4 6 8 2 = sguardo: riconosciuto dal codice di
            # scansione senza il flag "esteso" (vedi PAD_LOOK_SCAN), così
            # funziona con BlocNum acceso o spento e non muove come le frecce.
            pad = @active && pad_dir(raw[1], raw[2])
            if pad && cf('pad_look')
              @keys[pad] = true  if down
              @keys[pad] = false if up
              next 1
            end
            repeat = down && @keys[vk]   # autoripetizione di un tasto tenuto premuto
            @keys[vk] = true  if down
            @keys[vk] = false if up
            if @active
              # Alt+Tab: Alt è intercettato (serve per "Usa" e non deve aprire
              # il menu di SketchUp), quindi Windows non lo vede premuto. Alla
              # pressione di Tab con Alt giù si inietta Alt+Tab completo; da lì
              # Windows considera Alt premuto e il rilascio va lasciato passare.
              if down && vk == VK_TAB && alt? && @swallow.include?(VK_LALT) && !@alt_injected
                @alt_injected = true
                @w32.keybd_event(VK_ALT, 0, 0, INJECT_TAG)
                @w32.keybd_event(VK_TAB, 0, 0, INJECT_TAG)
                next 1
              end
              if @alt_injected && [VK_ALT, VK_LALT, VK_RALT].include?(vk) && up
                @alt_injected = false
                @w32.keybd_event(VK_ALT, 0, 2, INJECT_TAG)   # KEYEVENTF_KEYUP
                next 1
              end
              if down && vk == VK_ESC
                UI.start_timer(0) { stop } rescue nil
                next 1
              end
              if down && key_of?(vk, 'cursor')
                # Solo alla prima pressione: tenendo F premuto l'autoripetizione
                # farebbe lampeggiare il cursore. Il lavoro vero va fuori
                # dall'hook, che deve rispondere a Windows in fretta.
                unless repeat
                  UI.start_timer(0) { toggle_mouse_freeze } rescue nil
                end
                next 1
              end
              # Ctrl+PagGiù esce; Ctrl+PagSu (già dentro) non fa nulla. Entrambi
              # inghiottiti: in SketchUp PagSu/PagGiù cambiano scena.
              if (vk == VK_NEXT || vk == VK_PRIOR) && async_down?(VK_CONTROL)
                if down && vk == VK_NEXT
                  UI.start_timer(0) { stop } rescue nil
                end
                next 1
              end
              next 1 if @swallow.include?(vk)
            end
          end
        rescue => fps_err; log_error(__method__, fps_err); end
        @w32.CallNextHookEx(@hhook, n_code, w_param, l_param)
      end
      hmod   = @w32.GetModuleHandleA(nil)
      result = @w32.SetWindowsHookExA(@w32::WH_KEYBOARD_LL, @hook_cb, hmod, 0)
      @hhook = result
      result && result.to_i != 0
    rescue => e
      @w32_error = e.message; false
    end

    # F in modalità FPS: sblocca il mouse e mostra la freccia (per usare il
    # pannello o i menu senza uscire); ripremendo la nasconde e torna la
    # visuale col mouse. Al ritorno il cursore va rimesso al centro, sennò
    # il primo tick leggerebbe tutto lo spostamento fatto nel frattempo e
    # la visuale farebbe uno scatto.
    def self.toggle_mouse_freeze
      return unless @active
      @mouse_freeze = !@mouse_freeze
      if @mouse_freeze
        show_cursor
      else
        cx, cy = viewport_center
        @w32.SetCursorPos(cx, cy)
        hide_cursor
      end
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    def self.remove_hook
      return unless @hhook
      begin; @w32.UnhookWindowsHookEx(@hhook); rescue => fps_err; log_error(__method__, fps_err); end
      @hhook = nil; @hook_cb = nil
    end

  end
end
