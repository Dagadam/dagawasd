# DagaWASD — Profili dell'esploratore autonomo (lib/explore.rb): insiemi di
# coefficienti che ne fanno il carattere (curioso, corridore, lento,
# fotografo, spensierato…) e la finestra per sceglierli e cambiarli
# (exprofiles.html). Si apre da Estensioni › DagaWASD o dal tasto destro
# mentre esplora.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # In settings.json:
    #   "explore_profile":  id del profilo in uso ('balanced', 'curious', … o 'u1', 'u2'…)
    #   "explore_profiles": { id => { "name": "…" (solo i tuoi), "v": { chiave => valore } } }
    # Per un profilo già pronto (EX_PROFILES) "v" tiene solo ciò che hai
    # cambiato: «Ripristina» lo toglie. Un profilo tuo nasce copia di un
    # altro, con tutti i valori. Le chiavi sono EX_PROFILE_KEYS, ripulite
    # come le opzioni di ogni giro (explore_clean).
    # ══════════════════════════════════════════════════════════════
    XP_FILE     = File.join(PLUGIN_DIR, 'exprofiles.html').freeze
    XP_DEFAULT  = 'balanced'
    XP_NAME_MAX = 40

    # ── Archivio ──────────────────────────────────────────────────
    def self.explore_profiles_store
      @cfg ||= {}
      @cfg['explore_profiles'] = {} unless @cfg['explore_profiles'].is_a?(Hash)
      @cfg['explore_profiles']
    end

    def self.explore_custom?(id)
      e = explore_profiles_store[id.to_s]
      !EX_PROFILES.key?(id.to_s) && e.is_a?(Hash) && e['name'].is_a?(String)
    end

    def self.explore_profile?(id); EX_PROFILES.key?(id.to_s) || explore_custom?(id); end

    def self.explore_profile_id
      id = (@cfg || {})['explore_profile'].to_s
      explore_profile?(id) ? id : XP_DEFAULT
    end

    # Per id o per nome (maiuscole ignorate, anche il nome tradotto dei
    # profili già pronti); nil se non c'è.
    def self.explore_profile_find(x)
      x = x.to_s.strip
      return nil if x.empty?
      return x if explore_profile?(x)
      p = explore_profile_list.find { |q| q['name'].casecmp?(x) }
      p && p['id']
    end

    def self.explore_profile_name(id)
      id = id.to_s
      return t(EX_PROFILE_TEXT[id][0]) if EX_PROFILE_TEXT.key?(id)
      explore_custom?(id) ? explore_profiles_store[id]['name'] : id
    end

    # Ciò che il profilo cambia rispetto ai predefiniti (per explore_opts)
    def self.explore_profile_values(id)
      id = id.to_s
      e = explore_profiles_store[id]
      v = e.is_a?(Hash) && e['v'].is_a?(Hash) ? e['v'].select { |k, _| EX_PROFILE_KEYS.include?(k) } : {}
      return EX_PROFILES[id].merge(v) if EX_PROFILES.key?(id)
      explore_custom?(id) ? v : {}
    end

    # Tutti i valori del profilo, come li userebbe l'esploratore
    def self.explore_profile_full(id)
      explore_opts(nil, id).slice(*EX_PROFILE_KEYS)
    end

    # I valori originali di un profilo già pronto (nil per i tuoi)
    def self.explore_profile_base(id)
      return nil unless EX_PROFILES.key?(id.to_s)
      o = EX_DEFAULTS.dup
      [(@cfg || {})['explore'], EX_PROFILES[id.to_s]].each do |src|
        next unless src.is_a?(Hash)
        src.each { |k, v| c = explore_clean(k.to_s, v); o[k.to_s] = c unless c.nil? }
      end
      o.slice(*EX_PROFILE_KEYS)
    end

    def self.explore_profile_modified?(id)
      base = explore_profile_base(id) or return false
      explore_profile_full(id) != base
    end

    # Per l'editor, il menu e il ponte: prima i già pronti, poi i tuoi
    def self.explore_profile_list
      mine = explore_profiles_store.keys.select { |id| explore_custom?(id) }
                                   .sort_by { |id| [id[/\d+/].to_i, id] }
      EX_PROFILES.keys.map do |id|
        { 'id' => id, 'name' => t(EX_PROFILE_TEXT[id][0]), 'desc' => t(EX_PROFILE_TEXT[id][1]),
          'builtin' => true, 'modified' => explore_profile_modified?(id) }
      end + mine.map { |id| { 'id' => id, 'name' => explore_profile_name(id), 'desc' => '', 'builtin' => false, 'modified' => false } }
    end

    # ── Modifiche ─────────────────────────────────────────────────
    # Ogni modifica si salva (save = false: solo dal vivo, mentre si trascina
    # un cursore; il salvataggio arriva al rilascio) e, se l'esploratore sta
    # usando quel profilo, vale subito.
    def self.explore_profile_set(id, k, v, save = true)
      id = id.to_s
      return false unless explore_profile?(id) && EX_PROFILE_KEYS.include?(k.to_s)
      c = explore_clean(k.to_s, v)
      return false if c.nil?
      st = explore_profiles_store
      e = (st[id] = st[id].is_a?(Hash) ? st[id] : {})
      vals = (e['v'] = e['v'].is_a?(Hash) ? e['v'] : {})
      base = explore_profile_base(id)
      if base && base[k.to_s] == c
        vals.delete(k.to_s)                      # tornato all'originale: niente da ricordare
        st.delete(id) if vals.empty? && EX_PROFILES.key?(id)
      else
        vals[k.to_s] = c
      end
      save_cfg if save
      explore_reprofile(id) if @ex && @ex[:o]['profile'] == id
      true
    end

    def self.explore_profile_use(id)
      id = id.to_s
      return false unless explore_profile?(id)
      @cfg['explore_profile'] = id
      save_cfg
      explore_reprofile(id) if @ex
      xp_refresh
      true
    end

    # Un nome libero: «Curioso (copia)», poi «Curioso (copia) 2»…
    def self.explore_profile_free_name(name, except = nil)
      used = explore_profile_list.reject { |p| p['id'] == except }.map { |p| p['name'].downcase }
      n = 1
      out = name
      out = "#{name} #{n += 1}" while used.include?(out.downcase)
      out
    end

    # Copia di un profilo (con tutti i suoi valori), subito in uso
    def self.explore_profile_new(from = explore_profile_id)
      st = explore_profiles_store
      n = 1
      n += 1 while st.key?("u#{n}")
      id = "u#{n}"
      name = explore_profile_free_name(format(t('xp.copy_of'), name: explore_profile_name(from))[0, XP_NAME_MAX])
      st[id] = { 'name' => name, 'v' => explore_profile_full(from) }
      explore_profile_use(id)
      id
    end

    def self.explore_profile_rename(id, name)
      return false unless explore_custom?(id)
      name = name.to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, XP_NAME_MAX]
      return false if name.empty?
      explore_profiles_store[id.to_s]['name'] = explore_profile_free_name(name, id.to_s)
      save_cfg
      xp_refresh
      true
    end

    def self.explore_profile_delete(id)
      return false unless explore_custom?(id)
      explore_profiles_store.delete(id.to_s)
      return explore_profile_use(XP_DEFAULT) if @cfg['explore_profile'] == id.to_s
      save_cfg
      xp_refresh
      true
    end

    # Un profilo già pronto torna com'era
    def self.explore_profile_reset(id)
      return false unless EX_PROFILES.key?(id.to_s)
      explore_profiles_store.delete(id.to_s)
      save_cfg
      explore_reprofile(id.to_s) if @ex && @ex[:o]['profile'] == id.to_s
      xp_refresh
      true
    end

    # ══════════════════════════════════════════════════════════════
    # Finestra
    # ══════════════════════════════════════════════════════════════
    def self.xp_open
      @xp ||= {}
      d = @xp[:dialog]
      return d.bring_to_front if d&.visible?
      d = UI::HtmlDialog.new(
        dialog_title:    "DagaWASD — #{t('xp.title')}",
        preferences_key: 'DagaWASDProfili',
        width: 640, height: 760, min_width: 420, min_height: 480,
        resizable: true
      )
      d.set_file(XP_FILE)
      d.add_action_callback('ready') { |_c, _| xp_ready }
      d.add_action_callback('use')   { |_c, id| explore_profile_use(id.to_s) }
      d.add_action_callback('set')   { |_c, json| xp_set_json(json) }
      d.add_action_callback('act')   { |_c, what| xp_act(what.to_s) }
      d.set_on_closed do
        # la notizia della chiusura può arrivare dopo una riapertura immediata
        @xp[:dialog] = nil if @xp[:dialog].equal?(d) && !d.visible?
      end
      @xp[:dialog] = d
      d.show
      dialog_on_screen(d)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.xp_ready
      d = @xp && @xp[:dialog] or return
      load_lang
      look = { 'theme' => cf('ui_theme'), 'accent' => cf('ui_accent'), 'highlight' => cf('ui_highlight'),
               'danger' => cf('ui_danger') }
      look.merge!('bg' => cf('ui_bg'), 'text' => cf('ui_text')) if cf('ui_custom_colors')
      d.execute_script("init(#{js_json('strings' => @lang.select { |k, _| k.start_with?('xp.') },
                                        'lang' => @lang_code, 'rtl' => @lang_rtl, 'look' => look)})")
      xp_push
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.xp_state
      id = explore_profile_id
      { 'profiles' => explore_profile_list, 'active' => id,
        'values' => explore_profile_full(id), 'base' => explore_profile_base(id),
        'running' => explore_on?, 'running_profile' => @ex && @ex[:o]['profile'],
        'busy' => !!(@active || @path_job || bridge_building?) }
    end

    def self.xp_push
      d = @xp && @xp[:dialog] or return
      d.execute_script("show(#{js_json(xp_state)})")
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # Dopo ogni cambiamento (anche dal menu o dal ponte), se le finestre sono aperte
    def self.xp_refresh
      xp_push if @xp && @xp[:dialog]&.visible?
      xs_push if @xs && @xs[:dialog]&.visible?
    end

    # {k, v, save}: un valore del profilo in uso
    def self.xp_set_json(json)
      d = JSON.parse(json.to_s)
      return unless d.is_a?(Hash)
      save = d['save'] != false
      ok = explore_profile_set(explore_profile_id, d['k'].to_s, d['v'], save)
      xp_push if save || !ok                      # rimette il valore vero (ripulito, nei limiti)
    rescue JSON::ParserError
      nil
    end

    def self.xp_act(what)
      id = explore_profile_id
      case what
      when 'new'    then explore_profile_new(id)
      when 'rename'
        return unless explore_custom?(id)
        r = UI.inputbox([t('xp.ask_name')], [explore_profile_name(id)], t('xp.title'))
        explore_profile_rename(id, r[0]) if r
      when 'delete'
        return unless explore_custom?(id)
        ask = format(t('xp.ask_delete'), name: explore_profile_name(id))
        explore_profile_delete(id) if UI.messagebox(ask, MB_YESNO) == IDYES
      when 'reset'  then explore_profile_reset(id)
      when 'start'
        err = explore_start('record' => explore_record?)
        UI.messagebox("DagaWASD — #{err}") if err
      when 'stop'   then explore_stop
      end
      xp_push
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # ══════════════════════════════════════════════════════════════
    # Finestra di avvio (exstart.html): dal pulsante e dal menu, quando
    # l'esploratore è fermo. Si sceglie il profilo e se il giro diventa un
    # percorso; le due scelte restano per la volta dopo ("explore_profile",
    # "explore_record"). Il ponte non passa di qui: le sue opzioni le manda lui.
    # ══════════════════════════════════════════════════════════════
    XS_FILE = File.join(PLUGIN_DIR, 'exstart.html').freeze

    def self.explore_record?; (@cfg || {})['explore_record'] != false; end

    # Le scelte della finestra: salvate, e si parte (nil, o il perché no)
    def self.explore_launch(id, record)
      @cfg['explore_record'] = record ? true : false
      explore_profile_use(id) if explore_profile?(id)
      save_cfg
      explore_start('record' => explore_record?)
    end

    def self.xs_open
      @xs ||= {}
      d = @xs[:dialog]
      return d.bring_to_front if d&.visible?
      d = UI::HtmlDialog.new(
        dialog_title:    "DagaWASD — #{t('xs.title')}",
        preferences_key: 'DagaWASDAvvio',
        width: 440, height: 650, min_width: 340, min_height: 400,
        resizable: true
      )
      d.set_file(XS_FILE)
      d.add_action_callback('ready')  { |_c, _| xs_ready }
      d.add_action_callback('go')     { |_c, json| xs_go(d, json) }
      d.add_action_callback('edit')   { |_c, _| xp_open }
      d.add_action_callback('cancel') { |_c, _| d.close }
      d.set_on_closed do
        @xs[:dialog] = nil if @xs[:dialog].equal?(d) && !d.visible?
      end
      @xs[:dialog] = d
      d.show
      dialog_on_screen(d)
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.xs_ready
      d = @xs && @xs[:dialog] or return
      load_lang
      look = { 'theme' => cf('ui_theme'), 'accent' => cf('ui_accent'), 'danger' => cf('ui_danger') }
      look.merge!('bg' => cf('ui_bg'), 'text' => cf('ui_text')) if cf('ui_custom_colors')
      d.execute_script("init(#{js_json('strings' => @lang.select { |k, _| k.start_with?('xs.') },
                                        'lang' => @lang_code, 'rtl' => @lang_rtl, 'look' => look)})")
      xs_push
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.xs_push
      d = @xs && @xs[:dialog] or return
      d.execute_script("show(#{js_json('profiles' => explore_profile_list, 'active' => explore_profile_id,
                                       'record' => explore_record?, 'busy' => !!explore_busy)})")
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # {profile, record}: si parte e la finestra si chiude; se non si può, lo dice
    def self.xs_go(d, json)
      c = JSON.parse(json.to_s)
      return unless c.is_a?(Hash)
      err = explore_launch(c['profile'].to_s, c['record'] != false)
      return UI.messagebox("DagaWASD — #{err}") if err
      d.close
    rescue JSON::ParserError
      nil
    rescue => fps_err
      log_error(__method__, fps_err)
    end

  end
end
