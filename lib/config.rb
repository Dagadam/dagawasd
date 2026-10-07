# DagaWASD — Costanti, valori predefiniti (DEFAULT, tasti, materiali) e stato runtime.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    PLUGIN_DIR    = File.expand_path('..', __dir__).freeze   # lib/ sta dentro la cartella dell'estensione
    SETTINGS_FILE = File.join(PLUGIN_DIR, 'settings.json').freeze
    PANEL_FILE    = File.join(PLUGIN_DIR, 'panel.html').freeze
    LANG_DIR      = File.join(PLUGIN_DIR, 'lang').freeze
    LOG_FILE      = File.join(PLUGIN_DIR, 'dagawasd.log').freeze
    LOG_MAX       = 256 * 1024
    M_TO_IN       = 39.3701
    IN_TO_M       = 1.0 / M_TO_IN
    PITCH_LIMIT   = (Math::PI / 2.0) * 0.97
    PI2           = Math::PI * 2.0
    DEG           = Math::PI / 180.0
    MAX_OMEGA     = 25.0   # rad/s — cap sulla velocità angolare dei corpi
    THROW_SPIN_ZONE = 0.9  # frazione di carica oltre la quale il lancio ha topspin
    CONTACT_EPS   = 0.25   # pollici: spigoli entro questa quota sono "a contatto"

    VK_SHIFT  = 0x10   # Shift generico (per i tasti personalizzati)
    VK_W      = 0x57
    VK_A      = 0x41
    VK_S      = 0x53
    VK_D      = 0x44
    VK_SPACE  = 0x20
    VK_C      = 0x43
    VK_ESC    = 0x1B
    VK_LSHIFT = 0xA0
    VK_RSHIFT = 0xA1
    VK_F      = 0x46
    VK_ALT    = 0x12   # VK_MENU
    VK_LALT   = 0xA4   # VK_LMENU
    VK_RALT   = 0xA5   # VK_RMENU
    VK_K      = 0x4B   # Calcia
    VK_G      = 0x47   # Afferra / Lancia
    VK_R      = 0x52   # Registra un percorso
    VK_LEFT   = 0x25   # Frecce = alias di WASD
    VK_UP     = 0x26
    VK_RIGHT  = 0x27
    VK_DOWN   = 0x28
    VK_PRIOR  = 0x21   # PagSu  — Ctrl+PagSu entra in modalità FPS
    VK_NEXT   = 0x22   # PagGiù — Ctrl+PagGiù esce
    VK_HOME   = 0x24   # Home   — Ctrl+Home apre il pannello impostazioni
    VK_CONTROL = 0x11
    VK_TAB    = 0x09
    # Firma dei tasti che FPS inietta da sé (Alt+Tab), nel dwExtraInfo di
    # keybd_event: l'hook ignora solo quelli. Gli altri tasti iniettati
    # (RustDesk, AnyDesk, TeamViewer, tastiera a schermo, macro) valgono come
    # tasti veri: da remoto la tastiera arriva tutta iniettata.
    INJECT_TAG = 0x4441_4741   # "DAGA"

    # ── Tasti personalizzabili ─────────────────────────────────────
    # azione → codice virtual-key di Windows. Il pannello li legge da
    # event.keyCode, che su Windows coincide con il codice VK.
    # Frecce (alias del movimento), ESC, Tab (Alt+Tab), PagSu/PagGiù
    # (Ctrl+PagSu/PagGiù), Home (Ctrl+Home) e i tasti Windows restano riservati.
    DEFAULT_KEYS = {
      'forward' => VK_W,     'back'   => VK_S,     'left' => VK_A, 'right' => VK_D,
      'jump'    => VK_SPACE, 'crouch' => VK_C,     'run'  => VK_SHIFT,
      'use'     => VK_ALT,   'kick'   => VK_K,     'grab' => VK_G, 'cursor' => VK_F,
      'record'  => VK_R
    }.freeze
    RESERVED_KEYS = [VK_ESC, VK_TAB, VK_PRIOR, VK_NEXT, VK_HOME,
                     VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN, 0x5B, 0x5C, 0x5D,
                     0x62, 0x64, 0x66, 0x68].freeze   # tastierino 2 4 6 8: sguardo
    # Sguardo col tastierino: codice di scansione → direzione. Con BlocNum
    # spento i tasti arrivano come frecce, acceso come VK_NUMPADx; il codice
    # di scansione è lo stesso, e le frecce vere hanno in più il flag
    # "esteso": così il tastierino si riconosce in entrambi i casi.
    PAD_LOOK_SCAN = { 0x48 => :pad_up, 0x4B => :pad_left, 0x4D => :pad_right, 0x50 => :pad_down }.freeze
    KEY_NAMES = {
      0x08 => 'Backspace', 0x0D => 'Enter', 0x10 => 'Shift', 0x11 => 'Ctrl', 0x12 => 'Alt',
      0x14 => 'CapsLock', 0x20 => 'Space', 0x23 => 'End', 0x24 => 'Home',
      0x2D => 'Ins', 0x2E => 'Del'
    }.freeze
    # Tasti sinistro/destro dell'hook → codice generico
    GENERIC_VK = { VK_LSHIFT => VK_SHIFT, VK_RSHIFT => VK_SHIFT, 0xA2 => VK_CONTROL,
                   0xA3 => VK_CONTROL, VK_LALT => VK_ALT, VK_RALT => VK_ALT }.freeze
    # Ordine dei segmenti di rt.hud ("… WASD … · Space … · C … · …"): nil = fisso
    HUD_ACTS = [nil, 'jump', 'crouch', 'run', 'use', 'kick', 'grab', 'cursor', nil].freeze

    # ══════════════════════════════════════════════════════════════
    # Catalogo materiali — densità (kg/m³), restituzione, attrito (μ)
    # Il materiale di un'entità viene dedotto dal nome del materiale
    # SketchUp applicato (o dal nome della definizione/gruppo).
    # ══════════════════════════════════════════════════════════════
    MATERIALS = {
      'legno'   => { density:  600.0, restitution: 0.30, friction: 0.50 },
      'pietra'  => { density: 2500.0, restitution: 0.10, friction: 0.70 },
      'metallo' => { density: 7800.0, restitution: 0.40, friction: 0.25 },
      'vetro'   => { density: 2500.0, restitution: 0.20, friction: 0.15 },
      'gomma'   => { density: 1200.0, restitution: 0.85, friction: 0.90 },
      'pallone' => { density:   90.0, restitution: 0.78, friction: 0.55 },
      'cartone' => { density:  180.0, restitution: 0.10, friction: 0.60 },
      'plastica'=> { density:  950.0, restitution: 0.45, friction: 0.35 }
    }.freeze

    # Parole chiave (it/en) → chiave materiale
    MAT_ALIASES = {
      'legno'    => %w[legno legn wood timber oak pine plywood compensato],
      'pietra'   => %w[pietra sasso stone rock marmo marble granite cemento concrete brick mattone muro],
      'metallo'  => %w[metallo metal steel acciaio iron ferro alluminium alluminio chrome cromo],
      'vetro'    => %w[vetro glass finestra window mirror specchio],
      'gomma'    => %w[gomma rubber pneumatico tire tyre],
      'pallone'  => %w[pallone palla ball sphere sfera balloon],
      'cartone'  => %w[cartone carton cardboard scatola box paper carta],
      'plastica' => %w[plastica plastic pvc nylon resina resin]
    }.freeze

    DEFAULT = {
      # ── Movimento ────────────────────────────────────────────────
      'move_speed'          => 3.2,
      'sprint_multiplier'   => 1.8,
      'crouch_speed_mul'    => 0.45,
      'back_speed_mul'      => 0.75,
      'strafe_speed_mul'    => 0.90,
      'accel_time'          => 0.12,
      'decel_time'          => 0.10,
      'air_control'         => 0.35,
      # ── Salto & gravità ──────────────────────────────────────────
      'gravity'             => 9.8,
      'jump_force'          => 4.6,
      'max_jumps'           => 1,
      'jump_cut_factor'     => 0.45,
      'coyote_time'         => 0.12,
      'jump_buffer'         => 0.15,
      'max_fall_speed'      => 25.0,
      'respawn_enabled'     => true,   # caduta libera troppo lunga → torna dove eri prima di cadere
      'respawn_fall_time'   => 5.0,    # secondi di caduta libera prima del respawn
      'respawn_exit_count'  => 2,      # respawn di seguito che fanno uscire dalla modalità (0 = mai)
      'respawn_calm_time'   => 2.0,    # secondi fermi a terra che azzerano la serie di respawn
      # ── Corpo & collisioni ───────────────────────────────────────
      'eye_height'          => 1.7,
      'crouch_height'       => 0.9,
      'crouch_transition'   => 8.0,
      'body_radius'         => 0.25,
      'step_height'         => 0.45,
      'max_slope_deg'       => 50.0,
      'slide_accel'         => 6.0,
      'floor_snap_distance' => 0.18,
      'collision_quality'   => 3,
      # ── Camera ───────────────────────────────────────────────────
      'mouse_sensitivity'   => 0.0015,
      'invert_y'            => false,
      'pad_look'            => true,   # tastierino 4 6 8 2 = sguardo (per quando manca il mouse)
      'pad_look_speed'      => 120.0,  # rotazione orizzontale a piena velocità (°/s)
      'pad_look_speed_v'    => 80.0,   # rotazione verticale a piena velocità (°/s)
      'pad_look_accel'      => 0.3,    # secondi per arrivare a piena velocità (0 = subito)
      'gamepad_enabled'     => true,   # gamepad XInput (Xbox e compatibili), se collegato
      'gamepad_look_speed'  => 160.0,  # leva destra a fondo corsa (°/s)
      'gamepad_deadzone'    => 0.15,   # leve: frazione di corsa ignorata (deriva)
      'gamepad_curve'       => 1.8,    # leva destra: >1 = più precisa vicino al centro
      'gamepad_rumble'      => true,   # vibrazione negli atterraggi pesanti
      'fov'                => 70.0,
      'crosshair'           => true,
      'charge_bar'          => true,   # barra di carica lancio/calcio sotto il mirino
      'wheel_zoom'          => true,   # rotella = zoom (FOV), tasto centrale = reset
      'zoom_min_fov'        => 20.0,   # FOV minimo raggiungibile zoomando (°)
      'cam_roll'            => 1.2,
      'head_bob_enabled'    => true,
      'head_bob_freq'       => 2.0,
      'head_bob_amp'        => 0.035,
      'head_bob_side'       => 0.022,
      'land_dip'            => 0.10,
      'steps_enabled'       => true,   # suono dei passi secondo il pavimento (lib/sound.rb)
      'steps_volume'        => 70,     # %
      # ── Percorsi registrati (lib/path.rb) ─────────────────────────
      'path_smooth'         => 0.6,    # s di media mobile: toglie dondolio e scatti (0 = com'è)
      'path_speed'          => 1.0,    # × velocità di riproduzione, scene e video
      'path_scene_step'     => 1.0,    # s di registrazione fra una scena e l'altra
      'path_video_fps'      => 30,     # immagini al secondo di video
      'path_video_size'     => 'fhd',  # view (come la vista), hd, fhd, uhd
      'path_video_format'   => 'avi',  # avi (video Motion JPEG, lib/avi.rb) o png (immagini)
      # ── Oggetti: corpo rigido ────────────────────────────────────
      'obj_use_materials'   => true,
      'obj_density'         => 400.0,
      'obj_fill_ratio'      => 0.55,
      'obj_friction'        => 0.55,
      'obj_bounce'          => 0.25,
      'obj_lin_damping'     => 0.12,
      'obj_ang_damping'     => 0.35,
      'obj_air_drag'        => 0.02,
      'obj_sleep_lin'       => 0.12,
      'obj_sleep_ang'       => 0.25,
      'obj_sleep_time'      => 0.35,
      'obj_walls'           => true,
      'obj_tipping'         => true,
      'max_phys_entities'   => 24,
      # ── Player ↔ oggetti ─────────────────────────────────────────
      'player_mass'         => 75.0,
      'push_enabled'        => true,
      'push_max_mass'       => 120.0,
      'knockback_enabled'   => true,
      # ── Interazioni ──────────────────────────────────────────────
      'use_range'           => 2.5,
      'kick_range'          => 2.2,
      'kick_force_min'      => 3.0,    # calcio a tocco breve
      'kick_force'          => 8.0,    # calcio a carica piena
      'kick_charge_time'    => 0.8,    # 0 = calcio istantaneo a piena forza
      'impulse_ref_mass'    => 20.0,
      'grab_range'          => 3.0,
      'grab_distance'       => 1.6,
      'grab_max_mass'       => 60.0,
      'grab_spring'         => 14.0,
      'throw_force_min'     => 3.0,
      'throw_force_max'     => 15.0,
      'throw_charge_time'   => 1.5,
      'grab_pull_time'      => 0.18,   # strappo verso il player alla presa (collisioni spente)
      'grab_out_time'       => 0.22,   # poi fino alla distanza di presa (ancora spente); 0+0 = niente strappo
      # ── Sistema ──────────────────────────────────────────────────
      'tick_rate'           => 60,
      # Ponte per Claude (lib/bridge.rb): esegue Ruby ricevuto da 127.0.0.1
      'bridge_enabled'      => false,
      'bridge_live'         => false,  # costruzione passo passo, visibile nella vista
      'bridge_step_delay'   => 0.3,    # secondi di pausa fra un passo e l'altro
      'bridge_detail'       => 'solids', # solids = solidi finiti, ops = operazioni, anim = animata
      'bridge_orbit'        => false,  # dolly rotante: la camera gira attorno a ciò che si costruisce
      'bridge_orbit_speed'  => 8.0,    # gradi al secondo (negativo = senso orario)
      # ── Meteo: cielo (lib/sky.rb) ────────────────────────────────
      'sky_enabled'         => false,  # sole, luna, stelle e colori del cielo secondo data e ora
      'sky_now'             => false,  # data e ora attuali invece di quelle qui sotto
      'sky_place_custom'    => false,  # luogo scelto qui invece di quello del modello
      'sky_lat'             => 41.9,   # gradi, nord positivo
      'sky_lon'             => 12.5,   # gradi, est positivo
      'sky_tz'              => 1.0,    # fuso orario: ore rispetto a UTC
      'sky_hour'            => 17.0,   # ora locale del modello (17.5 = 17:30)
      'sky_day'             => 21,
      'sky_month'           => 6,
      'sky_flow'            => true,   # il tempo scorre
      'sky_day_minutes'     => 4.0,    # minuti reali per un giorno intero
      'sky_sun'             => true,
      'sky_moon'            => true,
      'sky_stars'           => true,
      'sky_colors'          => true,   # cielo, sfondo e luce secondo l'altezza del sole
      'sky_shadows'         => true,   # accende le ombre del modello
      'sky_body_size'       => 4.0,    # × la grandezza vera di sole e luna
      'sky_star_count'      => 800,    # stelle di fondo, oltre alle più luminose
      'sky_fps'             => 30,     # aggiornamenti al secondo mentre il tempo scorre
      'sky_shadow_fps'      => 4,      # ricalcoli delle ombre al secondo mentre il tempo scorre (costosi)
      # ── Meteo: pioggia e neve (lib/precip.rb) ─────────────────────
      'precip_kind'         => 'none', # none, rain, snow, mix
      'precip_intensity'    => 60,     # %
      'precip_wind'         => 2.0,    # m/s
      'precip_wind_dir'     => 270,    # gradi da cui soffia (0 = da nord, 270 = da ovest)
      'precip_fog'          => true,   # nebbia più fitta con l'intensità
      'precip_roofs'        => true,   # niente pioggia sotto tetti e alberi
      'precip_radius'       => 12.0,   # m attorno alla camera
      'precip_max'          => 3000,   # particelle all'intensità massima
      'precip_fps'          => 30,     # aggiornamenti al secondo
      # ── Meteo: nuvole (lib/clouds.rb) ──────────────────────────────
      'cloud_enabled'       => false,
      'cloud_cover'         => 45,     # % di cielo coperto
      'cloud_shade'         => true,   # le nuvole davanti al sole velano la luce
      'cloud_wind'          => 8.0,    # m/s in quota
      'cloud_wind_dir'      => 270,    # gradi da cui soffia
      'cloud_height'        => 1500,   # m sul livello del mare (z = 0)
      'cloud_size'          => 900,    # m, larghezza media
      'cloud_fps'           => 15,     # aggiornamenti al secondo
      'cloud_timelapse'     => true,   # col tempo accelerato corrono di più (fino a 30×)
      # Temporale e neve al suolo (lib/precip.rb, lib/snowcover.rb)
      'storm'               => false,  # lampi e tuoni, con pioggia o neve
      'storm_rate'          => 6,      # lampi al minuto
      'storm_thunder'       => true,   # tuono, in ritardo secondo la distanza
      'snow_cover'          => true,   # la neve si posa su tetti e terreno
      'snow_cover_time'     => 3.0,    # minuti per una copertura piena
      # 'auto' = segui la lingua dell'interfaccia di SketchUp
      'language'            => 'auto',
      # Tasti: azione → codice VK; key_labels = nome mostrato per i tasti
      # la cui etichetta dipende dal layout (es. "Ò" su tastiera italiana)
      'keys'                => DEFAULT_KEYS,
      'key_labels'          => {},
      # Pannello: 1 = impostazioni base, 2 = avanzate, 3 = molto avanzate
      'panel_level'         => 1,
      # ── Aspetto: pannello ────────────────────────────────────────
      # Colori '#rrggbb'; le scelte possibili sono in LOOK_CHOICES.
      'ui_theme'            => 'dark',
      'ui_accent'           => '#00c9a7',
      'ui_highlight'        => '#ffd166',
      'ui_danger'           => '#c04747',
      'ui_custom_colors'    => false,  # sfondo e testo propri al posto di quelli del tema
      'ui_bg'               => '#151515',
      'ui_text'             => '#dcdcdc',
      'ui_font'             => 'segoe',
      'ui_font_size'        => 15.0,   # px
      'ui_line_height'      => 1.55,
      'ui_radius'           => 6,      # px
      'ui_spacing'          => 1.0,    # × spaziature di righe e gruppi
      'ui_label_width'      => 230,    # px
      'ui_hints'            => true,   # descrizione breve sotto il nome
      'ui_animations'       => true,
      'ui_scrollbar'        => 9,      # px
      'ui_tab_icons'        => 'text',
      'ui_logo'             => 'bolt',
      # ── Aspetto: mirino e barra di carica nella vista di SketchUp ─
      'hud_cross_color'     => '#ffffff',
      'hud_cross_style'     => 'cross',
      'hud_cross_size'      => 9,      # px, dal centro alla punta
      'hud_cross_opacity'   => 0.8,
      'hud_cross_gap'       => 3,      # px
      'hud_cross_width'     => 1,      # px
      'hud_cross_outline'   => false,  # bordo scuro, per vederlo su superfici chiare
      'hud_bar_color'       => '#ffffff',
      'hud_bar_zone_color'  => '#ffb428',
      'hud_bar_width'       => 120,    # px
      'hud_bar_height'      => 6       # px
    }.freeze

    # Coppie [minimo, massimo]: il minimo non supera mai il massimo. Il
    # pannello sposta l'altro valore quando se ne muove uno (PAIRS in
    # panel.html, stesse coppie); qui si rimettono in ordine settings.json
    # scritti a mano e i file importati.
    MIN_MAX_PAIRS = [%w[kick_force_min kick_force], %w[throw_force_min throw_force_max],
                     %w[crouch_height eye_height]].freeze

    # Valori ammessi per le impostazioni a scelta (le etichette sono nel
    # pannello), non solo dell'aspetto: anche il dettaglio del ponte. Le altre impostazioni di testo che iniziano con '#' sono colori.
    LOOK_CHOICES = {
      'ui_theme'        => %w[auto dark light midnight warm contrast],
      'ui_font'         => %w[segoe tahoma verdana trebuchet georgia calibri consolas comic system],
      'ui_tab_icons'    => %w[text both icons],
      'ui_logo'         => %w[bolt game target boot cube none],
      'hud_cross_style' => %w[cross dot circle crossdot],
      'bridge_detail'   => %w[solids ops anim],
      'precip_kind'     => %w[none rain snow mix],
      'path_video_size' => %w[view hd fhd uhd],
      'path_video_format' => %w[avi png]
    }.freeze

    # ── Stato runtime ──────────────────────────────────────────────
    @active        = false
    @timer_id      = nil
    @last_tick     = nil
    @keys          = {}
    @yaw           = 0.0
    @pitch         = 0.0
    @eye_x         = 0.0
    @eye_y         = 0.0
    @eye_z         = 0.0
    @vh_x          = 0.0    # velocità orizzontale X (m/s)
    @vh_y          = 0.0    # velocità orizzontale Y (m/s)
    @vv            = 0.0    # velocità verticale     (m/s)
    @on_ground     = false
    @floor_z_in    = nil
    @floor_n       = nil    # normale del pavimento sotto i piedi
    @cur_h_m       = 1.7
    @bob_phase     = 0.0
    @land_off      = 0.0    # offset camera da atterraggio (m)
    @land_vel      = 0.0
    @step_smooth   = 0.0    # residuo camera dopo un gradino (pollici)
    @roll          = 0.0
    @coyote        = 0.0
    @jump_buf      = 0.0
    @jumps_used    = 0
    @jump_cut      = false
    @prev_space    = false
    @fall_time     = 0.0    # secondi di caduta libera in corso
    @fall_in       = 0.0    # pollici scesi nell'ultimo passo di caduta
    @left_ground_at = nil   # istante in cui i piedi hanno lasciato il suolo
    @safe_trail    = []     # ultime posizioni a terra [t, x, y, z_piedi] (pollici)
    @respawn_streak = 0     # respawn di seguito, senza essersi fermati a terra in mezzo
    @ground_time   = 0.0    # secondi a terra ininterrotti (azzerano la serie di respawn)
    @mouse_freeze  = false
    @cursor_hidden = false
    @hhook         = nil
    @hook_cb       = nil
    @cfg           = {}
    @dialog        = nil
    # Interazioni / corpi rigidi
    @phys_entities  = {}     # entity => stato corpo rigido
    @body_cache     = {}     # entity => {m, ix, iy, iz, rest, fric, mat}
    @grabbed_entity = nil
    @grab_state     = :idle  # :idle | :holding | :charging
    @charge_start   = nil
    @prev_g         = false
    @prev_alt       = false
    @prev_k         = false
    @kick_start     = nil    # istante di inizio carica del calcio
    @dyn_entities   = Set.new # entità mosse dalla fisica (per la fase larga della presa)
    @obst           = nil    # griglia degli ingombri, costruita a ogni presa
    @base_fov       = 70.0   # FOV di riferimento (senza zoom)
    @zoom_fov       = 70.0   # FOV corrente (smussato)
    @zoom_target    = 70.0   # FOV verso cui tende lo zoom

    @w32       = nil
    @w32_error = nil

  end
end
