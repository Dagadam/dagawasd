# DagaWASD — Pannello impostazioni (HtmlDialog): callback, esporta/importa.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Pannello di controllo
    # ══════════════════════════════════════════════════════════════
    # Il ponte per Claude è facoltativo: il pacchetto per l'Extension
    # Warehouse non ha lib/bridge.rb (main.rb lo salta, vedi OPTIONAL).
    def self.bridge?; respond_to?(:bridge_start); end

    # Invia al pannello dizionario, elenco lingue, impostazioni e stato.
    # L'ordine conta: applyLang ricostruisce il DOM, quindi i valori
    # vanno ricaricati subito dopo.
    def self.push_panel_state
      return unless @dialog
      load_lang
      payload = {
        'strings'   => @lang,
        'languages' => lang_index,
        'current'   => (@cfg['language'] || 'auto'),
        'resolved'  => @lang_code,
        'rtl'       => @lang_rtl,
        'bridge'    => bridge?      # senza lib/bridge.rb il pannello nasconde la sezione
      }
      @dialog.execute_script("applyLang(#{js_json(payload)})")
      # I valori predefiniti esistono solo qui (DEFAULT): il pannello li
      # riceve per "Ripristina", per i segni di modifica e per la guida.
      @dialog.execute_script("setDefaults(#{js_json(DEFAULT)})")
      # Il pannello riceve sempre la tabella effettiva (predefinita se
      # l'utente non l'ha mai modificata)
      @dialog.execute_script("loadSettings(#{js_json(@cfg.merge('materials' => mat_table))})")
      @dialog.execute_script("setRunning(#{@active})")
      @dialog.execute_script("setLogCount(#{log_count})")
      @dialog.execute_script("setBridge(#{js_json(bridge_status)})") if bridge?
      @dialog.execute_script("setSky(#{js_json(sky_status)})")
      @dialog.execute_script("setPaths(#{js_json(path_list)})")
    rescue => fps_err; log_error(__method__, fps_err); nil; end

    # Dopo ogni modifica di @cfg (pannello o importazione): ripulisce,
    # salva e applica a caldo ciò che richiede un riavvio del timer o
    # l'invalidazione delle proprietà dei corpi.
    def self.apply_cfg_change(old_rate)
      @cfg['materials'] = sanitize_materials(@cfg['materials']) if @cfg.key?('materials')
      # Tabella identica alla predefinita: non salvarla, così i futuri
      # aggiornamenti del catalogo arrivano anche a chi non l'ha toccata.
      m = @cfg['materials']
      @cfg.delete('materials') if m.nil? || m.empty? || m == default_materials
      refresh_keys
      sanitize_look
      sanitize_pairs
      save_cfg
      restart_timer if @active && @cfg['tick_rate'] != old_rate
      invalidate_materials
      @body_cache.clear
      @phys_entities.each_value { |st| st[:props] = nil }
      Sketchup.status_text = hud_text if @active
      bridge_sync if bridge?
      sky_sync
      precip_sync
      cloud_sync
      snow_sync
    end

    # ── Esporta / importa ──────────────────────────────────────────
    # Il file contiene solo il comportamento (valori, tabella materiali,
    # tasti): lingua e livello del pannello restano quelli di chi importa.
    # Il ponte per Claude esegue codice: un file ricevuto da altri non deve
    # poterlo accendere.
    PANEL_ONLY = %w[language panel_level bridge_enabled bridge_live bridge_step_delay bridge_detail
                    bridge_windows bridge_windows_mouse bridge_mouse_time].freeze

    def self.export_settings
      path = UI.savepanel(t('bk.export'), '', 'DagaWASD.json')
      return unless path
      path += '.json' unless path =~ /\.json\z/i
      data = @cfg.reject { |k, _| PANEL_ONLY.include?(k) }.merge('materials' => mat_table)
      File.write(path, JSON.pretty_generate('dagawasd_settings' => 1, 'settings' => data))
      @dialog.execute_script("flashStatus(#{js_json(t('bk.exported'))})") if @dialog
    rescue => fps_err
      log_error(__method__, fps_err)
      UI.messagebox("DagaWASD — #{fps_err.message}")
    end

    # Accetta solo chiavi note, del tipo giusto; gli intervalli li
    # ricontrolla il pannello, che dopo l'importazione risalva i valori
    # passati dal suo clamp.
    def self.import_values(src)
      src = src['settings'] if src.is_a?(Hash) && src['settings'].is_a?(Hash)
      return 0 unless src.is_a?(Hash)
      n = 0
      src.each do |k, v|
        next if PANEL_ONLY.include?(k)
        d = DEFAULT[k]
        ok = case d
             when true, false then v == true || v == false
             when Numeric     then v.is_a?(Numeric) && v.to_f.finite?
             when Hash        then v.is_a?(Hash)
             when String      then v.is_a?(String)   # colori e scelte: li ripulisce sanitize_look
             else k == 'materials' && v.is_a?(Array)
             end
        next unless ok
        @cfg[k] = v
        n += 1
      end
      n
    end

    def self.import_settings
      path = UI.openpanel(t('bk.import'), '', 'JSON|*.json||')
      return unless path
      data = begin
        JSON.parse(File.read(path, encoding: 'UTF-8'))
      rescue JSON::ParserError, EncodingError
        nil
      end
      old_rate = @cfg['tick_rate']
      if import_values(data).zero?
        UI.messagebox(t('bk.bad'))
        return
      end
      apply_cfg_change(old_rate)
      push_panel_state
      @dialog.execute_script("saveNow(); flashStatus(#{js_json(t('bk.imported'))})") if @dialog
    rescue => fps_err
      log_error(__method__, fps_err)
      UI.messagebox("DagaWASD — #{fps_err.message}")
    end

    def self.show_panel
      load_cfg
      load_lang
      if @dialog && @dialog.visible?
        dialog_on_screen(@dialog)    # "aperto" ma fuori dallo schermo: il menu non farebbe nulla
        @dialog.bring_to_front; return
      end
      @dialog = UI::HtmlDialog.new(
        dialog_title:    "DagaWASD — #{t('menu.settings').sub(/…\z/, '')}",
        preferences_key: 'DagaWASDPanel',
        width:  620, height:  880,
        min_width: 520, min_height: 520,
        resizable: true
      )
      @dialog.set_file(PANEL_FILE)
      @dialog.add_action_callback('save_settings') do |_ctx, json|
        begin
          old_rate = @cfg['tick_rate']
          @cfg.merge!(JSON.parse(json))
          apply_cfg_change(old_rate)
        rescue => fps_err; log_error(__method__, fps_err); end
      end
      @dialog.add_action_callback('export_settings') { |_ctx, _| export_settings }
      @dialog.add_action_callback('read_log') do |_ctx, _|
        @dialog.execute_script("showLog(#{js_json(read_log)})")
      end
      @dialog.add_action_callback('clear_log') do |_ctx, _|
        clear_log
        @dialog.execute_script("showLog(#{js_json(read_log)})")
      end
      @dialog.add_action_callback('import_settings') { |_ctx, _| import_settings }
      # «Incolla» del menu del destro: la pagina non può leggere gli appunti (lib/keyedit.rb)
      @dialog.add_action_callback('panel_paste') do |_ctx, _|
        @dialog.execute_script("incolla(#{js_json(ke_clipboard)})")
      end
      @dialog.add_action_callback('weather_preset') { |_ctx, id| weather_preset(id) }
      # Percorsi: {cmd, name} (play, stop, scenes, frames, rename, delete…);
      # 'key' ha anche i, la posizione da aprire nell'elenco espanso
      @dialog.add_action_callback('path_cmd') do |_ctx, json|
        d = JSON.parse(json.to_s) rescue {}
        path_command(d['cmd'].to_s, d['name'].to_s, d['i'])
      end
      # "Ripristina tabella": torna al catalogo predefinito
      @dialog.add_action_callback('reset_materials') do |_ctx, _|
        begin
          @cfg.delete('materials')
          save_cfg
          invalidate_materials
          @body_cache.clear
          @phys_entities.each_value { |st| st[:props] = nil }
          push_panel_state
        rescue => fps_err; log_error(__method__, fps_err); end
      end
      @dialog.add_action_callback('toggle') do |_ctx, _|
        toggle
        @dialog.execute_script("setRunning(#{@active})")
      end
      @dialog.add_action_callback('request_settings') do |_ctx, _|
        push_panel_state
      end
      @dialog.add_action_callback('set_language') do |_ctx, code|
        begin
          code = code.to_s
          @cfg['language'] = (code == 'auto' || lang_codes.include?(code)) ? code : 'auto'
          save_cfg
          push_panel_state          # ricarica la lingua (load_lang)
          # i nomi brevi validi dipendono dalla lingua dell'interfaccia
          invalidate_materials
          @body_cache.clear
          @phys_entities.each_value { |st| st[:props] = nil }
          Sketchup.status_text = @active ? hud_text : t('rt.off')
        rescue => fps_err; log_error(__method__, fps_err); end
      end
      @dialog.show
      dialog_on_screen(@dialog)
    end

  end
end
