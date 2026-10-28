# DagaWASD — Menu Plugins e barra degli strumenti.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Menu + Toolbar
    # ══════════════════════════════════════════════════════════════
    def self.register_ui
      load_cfg
      load_lang
      sub = UI.menu('Plugins').add_submenu('DagaWASD')
      sub.add_item(t('menu.toggle'))   { toggle }
      sub.add_item(t('menu.explore'))  { explore_toggle }
      sub.add_item(t('menu.explore_profiles')) { xp_open }
      sub.add_item(t('menu.settings')) { show_panel }
      tb   = UI::Toolbar.new('DagaWASD')
      idir = File.join(PLUGIN_DIR, 'icons')
      cmd_walk = UI::Command.new('Toggle DagaWASD') { toggle }
      cmd_walk.tooltip = t('tip.walk')
      cmd_walk.status_bar_text = 'DagaWASD'
      si = File.join(idir, 'wasd_24.png'); li = File.join(idir, 'wasd_32.png')
      cmd_walk.small_icon = si if File.exist?(si)
      cmd_walk.large_icon = li if File.exist?(li)
      tb.add_item(cmd_walk)
      # Esploratore autonomo (lib/explore.rb): il pulsante resta premuto mentre esplora
      cmd_exp = UI::Command.new('DagaWASD Explorer') { explore_toggle }
      cmd_exp.tooltip = t('tip.explore')
      cmd_exp.status_bar_text = t('tip.explore')
      si = File.join(idir, 'explore_24.png'); li = File.join(idir, 'explore_32.png')
      cmd_exp.small_icon = si if File.exist?(si)
      cmd_exp.large_icon = li if File.exist?(li)
      if cmd_exp.respond_to?(:set_validation_proc)
        cmd_exp.set_validation_proc { explore_on? ? MF_CHECKED : MF_UNCHECKED }
      end
      tb.add_item(cmd_exp)
      cmd_cfg = UI::Command.new('FPS Settings') { show_panel }
      cmd_cfg.tooltip = t('tip.cfg')
      si2 = File.join(idir, 'gear_24.png'); li2 = File.join(idir, 'gear_32.png')
      cmd_cfg.small_icon = si2 if File.exist?(si2)
      cmd_cfg.large_icon = li2 if File.exist?(li2)
      tb.add_item(cmd_cfg)
      tb.restore
    end

  end
end
