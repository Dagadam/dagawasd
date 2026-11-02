# DagaWASD — Esploratore autonomo: guarda la scena, sceglie la cosa più
# significativa, le fa un passo incontro guardandola, e ricomincia.
# Parte di DagaWASD::FPSWalk, caricata da main.rb (che elenca tutti i file e il loro ordine).
module DagaWASD
  module FPSWalk

    # ══════════════════════════════════════════════════════════════
    # Esploratore autonomo
    #
    #   ANALIZZA → SCEGLIE IL PUNTO → UN PASSO VERSO IL PUNTO, GUARDANDOLO → ANALIZZA …
    #
    # L'occhio è una retina di raggi lanciati dalla camera attraverso la
    # griglia dello schermo (view.pickray + model.raytest): ogni raggio
    # riporta quello che si vede in quel punto della vista — distanza,
    # normale, faccia, oggetto, colore. Da questo piccolo G-buffer escono,
    # cella per cella, sette misure di salienza:
    #   bordi       salti di profondità: sagome contro lo sfondo, aperture
    #   spigoli     cambi di normale fra celle alla stessa distanza
    #   dettaglio   quante facce diverse nell'intorno 3×3
    #   colore      contrasto con l'intorno e con il colore medio della vista
    #   rarità      un oggetto che occupa poco della vista spicca, il muro no
    #   oggetto     componenti e gruppi a misura d'uomo (non l'edificio
    #               intero), di più se hanno molte facce
    #   pixel       facoltativo («occhio a colori»): salienza dell'immagine
    #               vera, da una piccola write_image in BMP
    # pesate poi per distanza (né addosso né all'orizzonte), centro della
    # vista e novità: una memoria 3D a voxel ricorda dove lo sguardo è già
    # stato e se ne stanca (inibizione del ritorno), una mappa dei posti già
    # calpestati spinge verso stanze nuove. Le celle si raggruppano per
    # oggetto (o per faccia): il gruppo col punteggio più alto è
    # l'obiettivo, e il suo punto è il baricentro delle celle più salienti.
    # Se niente spicca si va verso lo spazio aperto (porte, corridoi) o ci si
    # guarda intorno.
    #
    # Il passo: si cammina verso l'obiettivo con lo sguardo che lo insegue,
    # girando attorno agli ostacoli (sonde a tre altezze come il corpo della
    # camminata, più un anello di raggi attorno al corpo per gli spigoli),
    # salendo gradini e rifiutando i precipizi (un profilo del pavimento
    # davanti); ci si ferma a distanza di osservazione, lo si guarda per un
    # po' e la memoria lo segna come visto. Senza pavimento sotto (vista
    # aerea, modello senza terreno) si vola, e arrivati vicino a terra si
    # atterra; senza niente da vedere, in volo si sale a guardare dall'alto.
    #
    # Come il ponte per Claude (lib/bridge.rb) tutto gira nel solo thread di
    # SketchUp senza mai bloccarlo: la scansione è una Fiber che a ogni
    # fotogramma lancia raggi per al più frame_ms e poi cede (come `step`
    # della costruzione dal vivo), e la retina si allarga o si stringe per
    # restare in scan_ms; la camera la muove view.animation (come la
    # riproduzione dei percorsi) con lo stesso inseguimento esponenziale del
    # dolly rotante. Il ponte lo comanda e lo osserva (GET/POST /explore,
    # client tools/esplora.rb). Alla fine il giro diventa un percorso
    # (lib/path.rb): si riguarda, si fa in scene o in video.
    # ══════════════════════════════════════════════════════════════

    # Valori predefiniti. Si cambiano per una volta da explore_start(opzioni)
    # (anche dal ponte) o per sempre in settings.json: "explore": { "speed": 1.4 }
    EX_DEFAULTS = {
      'speed'      => 1.1,    # m/s camminando (in volo di più, secondo la distanza)
      'step_time'  => 0.45,   # s: un passo = un'analisi
      'standoff'   => 1.2,    # m: distanza minima da ciò che si guarda
      'dwell'      => 1.8,    # s di sosta davanti a ciò che si è raggiunto
      'attention'  => 25.0,   # s massimi dietro allo stesso obiettivo
      'grid'       => 32,     # celle della retina in orizzontale (poi si adatta)
      'scan_ms'    => 40.0,   # ms di calcolo per analisi a cui la retina si adatta
      'frame_ms'   => 6.0,    # ms di raggi per fotogramma: oltre, la scansione cede
      'adaptive'   => true,   # scan_ms e frame_ms seguono i fotogrammi (sono solo la partenza)
      'fovea'      => 1.5,    # quanto la retina è più fitta attorno a ciò che si guarda (0: uniforme)
      'turn_speed' => 110.0,  # °/s massimi di rotazione dello sguardo
      'pitch_max'  => 50.0,   # ° di sguardo in su o in giù
      'max_drop'   => 0.8,    # m: un salto più alto è un precipizio
      'mode'       => 'auto', # auto, walk (a piedi), fly (in volo)
      'heatmap'    => true,   # mappa dell'attenzione disegnata nella vista
      'pixels'     => false,  # occhio a colori: anche i pixel della vista (più lento)
      'record'     => true,   # alla fine il giro diventa un percorso
      'bob'        => true,   # leggero dondolio camminando
      'duration'   => 0.0,    # s: si ferma da solo dopo (0 = mai)
      'seed'       => 7,      # spareggi: stesso seme e stesso modello, stesso giro
      # ── carattere (i profili, lib/exprofiles.rb) ──
      'commit'     => 2.5,    # s fedele a un obiettivo appena scelto, prima di cambiare idea
      'sticky'     => 1.4,    # quanto deve valere di più un altro obiettivo per cambiare
      'curiosity'  => 1.0,    # peso della memoria di ciò che ha già visto (0 = ci torna volentieri)
      'boredom'    => 20.0,   # s di sguardo che spengono il fascino di un obiettivo (a 1/e)
      'roam'       => 1.0,    # voglia di andare: spazio aperto e posti non ancora calpestati
      'whim'       => 0.04,   # capriccio: quanto le scelte sono a caso (±)
      'continuity' => 1.0,    # sguardo che passa a ciò che sta accanto e non torna dove ha già guardato (0 = no)
      'w_object'   => 1.0,    # pesi di ciò che lo attira: oggetti a misura d'uomo,
      'w_shape'    => 1.0,    #   sagome e spigoli,
      'w_detail'   => 1.0,    #   dettaglio,
      'w_color'    => 1.0,    #   contrasto di colore,
      'w_rare'     => 1.0,    #   rarità
      'zoom'       => false,  # prima di avvicinarsi ingrandisce l'obiettivo
      'zoom_fill'  => 0.5,    # parte dell'altezza della vista che l'obiettivo ingrandito riempie
      'zoom_max'   => 6.0,    # ingrandimento al più
      'zoom_hold'  => 1.5,    # s fermo sull'ingrandimento
      'jump'       => true,   # salta un ostacolo basso che sbarra la strada (forza e gravità del giocatore)
      'orbit'      => 0.0     # ° di giro attorno a un oggetto raggiunto, per vederlo da più lati (0 = no)
    }.freeze
    EX_RANGES = {
      'speed' => [0.2, 4.0], 'step_time' => [0.15, 3.0], 'standoff' => [0.4, 8.0], 'dwell' => [0.0, 15.0],
      'attention' => [3.0, 120.0], 'grid' => [12, 64], 'scan_ms' => [5.0, 400.0], 'frame_ms' => [1.0, 40.0],
      'fovea' => [0.0, 4.0],
      'turn_speed' => [20.0, 360.0], 'pitch_max' => [10.0, 80.0], 'max_drop' => [0.1, 5.0],
      'duration' => [0.0, 86_400.0], 'seed' => [0, 2_147_483_647],
      'commit' => [0.0, 20.0], 'sticky' => [1.0, 4.0], 'curiosity' => [0.0, 3.0], 'boredom' => [3.0, 120.0],
      'roam' => [0.0, 3.0], 'whim' => [0.0, 1.0], 'continuity' => [0.0, 3.0], 'w_object' => [0.0, 3.0], 'w_shape' => [0.0, 3.0],
      'w_detail' => [0.0, 3.0], 'w_color' => [0.0, 3.0], 'w_rare' => [0.0, 3.0],
      'zoom_fill' => [0.1, 0.9], 'zoom_max' => [1.0, 12.0], 'zoom_hold' => [0.0, 10.0], 'orbit' => [0.0, 360.0]
    }.freeze
    EX_MODES = %w[auto walk fly].freeze

    # Profili: insiemi di coefficienti che fanno il carattere dell'esploratore.
    # Solo queste chiavi; quelle tecniche (retina, durata, registrazione…)
    # restano delle opzioni di ogni giro. L'editor è lib/exprofiles.rb.
    EX_PROFILE_KEYS = %w[speed standoff max_drop mode bob jump turn_speed pitch_max step_time
                         dwell orbit attention commit sticky curiosity boredom roam whim continuity
                         w_object w_shape w_detail w_color w_rare pixels
                         zoom zoom_fill zoom_max zoom_hold].freeze
    # Profili già pronti: solo ciò che cambia rispetto ai predefiniti.
    # [nome, descrizione] sono chiavi di traduzione.
    EX_PROFILES = {
      'balanced'     => {},
      'curious'      => { 'curiosity' => 2.2, 'boredom' => 8.0, 'attention' => 15.0, 'dwell' => 1.2, 'roam' => 1.6,
                          'commit' => 2.0, 'w_detail' => 1.5, 'w_rare' => 1.6, 'speed' => 1.3, 'orbit' => 90.0 },
      'runner'       => { 'speed' => 3.2, 'step_time' => 0.3, 'turn_speed' => 220.0, 'dwell' => 0.4, 'standoff' => 2.0,
                          'attention' => 12.0, 'roam' => 1.8, 'commit' => 3.0, 'boredom' => 12.0 },
      'slow'         => { 'speed' => 0.5, 'turn_speed' => 45.0, 'dwell' => 5.0, 'attention' => 45.0, 'boredom' => 45.0,
                          'standoff' => 1.6, 'commit' => 5.0, 'sticky' => 2.0, 'step_time' => 0.8, 'jump' => false },
      'photographer' => { 'zoom' => true, 'zoom_hold' => 2.5, 'zoom_fill' => 0.6, 'dwell' => 2.5, 'speed' => 0.9,
                          'turn_speed' => 80.0, 'w_color' => 1.5, 'w_shape' => 1.3, 'commit' => 4.0, 'orbit' => 180.0 },
      'carefree'     => { 'whim' => 0.5, 'sticky' => 1.1, 'commit' => 1.5, 'roam' => 2.2, 'curiosity' => 0.6,
                          'continuity' => 0.5, 'boredom' => 10.0, 'dwell' => 0.8, 'w_object' => 0.6, 'w_color' => 1.3 },
      # ricognizione: corre, dà un'occhiata da lontano e passa oltre, finché
      # non resta niente di mai visto (le frontiere pesano più degli oggetti);
      # sempre a piedi, anche partendo da una camera alta
      'soldier'      => { 'mode' => 'walk', 'speed' => 3.6, 'step_time' => 0.3, 'turn_speed' => 260.0, 'max_drop' => 1.5,
                          'standoff' => 3.5, 'dwell' => 0.3, 'attention' => 8.0, 'boredom' => 6.0,
                          'commit' => 3.0, 'sticky' => 1.6, 'curiosity' => 2.5, 'roam' => 2.8, 'whim' => 0.02,
                          'continuity' => 1.6,
                          'w_object' => 1.3, 'w_shape' => 1.2, 'w_detail' => 0.7, 'w_color' => 0.5 }
    }.freeze
    EX_PROFILE_TEXT = {
      'balanced'     => ['xp.p.balanced', 'xp.d.balanced'],
      'curious'      => ['xp.p.curious', 'xp.d.curious'],
      'runner'       => ['xp.p.runner', 'xp.d.runner'],
      'slow'         => ['xp.p.slow', 'xp.d.slow'],
      'photographer' => ['xp.p.photographer', 'xp.d.photographer'],
      'carefree'     => ['xp.p.carefree', 'xp.d.carefree'],
      'soldier'      => ['xp.p.soldier', 'xp.d.soldier']
    }.freeze

    # ── Retina dinamica ─────────────────────────────────────────────
    EX_FOVEA_W    = 0.15     # larghezza della fovea (parte dello schermo, per asse)
    EX_FOVEA_EDGE = 0.12     # la fovea non va più vicina di così al bordo dello schermo
    EX_FPS_GOAL   = 30.0     # fotogrammi al secondo da difendere scansionando
    EX_SLICE_SHARE = 0.15    # su un modello pesante la scansione allunga un fotogramma al più di tanto
    EX_SLICE      = [2.0, 30.0].freeze   # ms di scansione per fotogramma, al meno e al più
    EX_SCAN_FILL  = 0.7      # parte di un passo (step_time) che la scansione può occupare
    EX_FRAME_K    = 0.2      # media dei tempi dei fotogrammi (esponenziale)
    EX_HZ_RANGE   = [0.5, 15.0].freeze   # analisi al secondo della cadenza adattiva (pannello › Sistema › Prestazioni)
    EX_CELL_K     = 0.3      # media del costo di una cella della retina (esponenziale)

    # ── Salienza ────────────────────────────────────────────────────
    # Pesi delle misure (senza occhio a colori il peso dei pixel si ridistribuisce)
    EX_W = { d: 0.17, n: 0.10, f: 0.15, c: 0.15, r: 0.15, o: 0.18, p: 0.10 }.freeze
    EX_DEPTH_EDGE = 0.4      # salto di log-distanza che vale un bordo pieno (≈ ×1,5)
    EX_VOID_EDGE  = 0.7      # sagoma contro il cielo: conta, ma meno (stanze senza soffitto)
    EX_REGION_W   = 0.65     # una faccia sciolta rispetto a un oggetto (le grandi ancora meno)
    EX_COL_LOCAL  = 25.0     # ΔE (Lab) dall'intorno che vale un contrasto pieno
    EX_COL_GLOBAL = 45.0     # ΔE dal colore medio della vista che vale pieno
    EX_NEAR       = [0.45, 1.3].freeze                              # m: più vicino è "addosso"
    EX_FAR        = { walk: [18.0, 60.0], fly: [80.0, 300.0] }.freeze # m: oltre conta meno
    EX_OBJ        = [0.08, 5.0].freeze   # m: diagonale di un oggetto a misura d'uomo
    EX_CPLX_REF   = 600.0    # facce per una complessità piena (scala logaritmica)
    EX_CPLX_CAP   = 4000     # oltre non si contano
    EX_MIN_PEAK   = 0.04     # gruppi più spenti non sono candidati
    EX_MIN_SCORE  = 0.08     # sotto, meglio guardarsi intorno
    EX_OPEN_W     = 0.33     # peso dello spazio aperto (porte, corridoi, orizzonte)
    EX_OPEN_PITCH = 14.0 * DEG
    EX_N4 = [[-1, 0], [1, 0], [0, -1], [0, 1]].freeze
    EX_N6 = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]].freeze

    # ── Memoria ─────────────────────────────────────────────────────
    EX_VOXEL      = 0.75 * M_TO_IN   # lato dei voxel della memoria dello sguardo
    EX_MEM_TAU    = 120.0    # s: la memoria si scolora
    EX_SEEN       = 0.05     # a ogni analisi, per ogni voxel visibile (una volta sola)
    EX_ATTEND     = 0.04     # al secondo, sul voxel dell'obiettivo che si sta guardando
    EX_SATIATE    = 3.0      # obiettivo raggiunto e osservato
    EX_WALK_CELL  = 1.5 * M_TO_IN    # celle della mappa del calpestio
    EX_WALK_DZ    = 0.5 * M_TO_IN    # e sua quota (dei piedi): un piano sopra l'altro non si confonde
    EX_WALK_TAU   = 300.0
    EX_WALK_K     = 0.06     # per secondo passato in una cella
    EX_BORE_FADE  = 90.0     # s in cui la noia passa
    EX_VISIT_TAU  = 180.0    # s in cui un obiettivo visto torna interessante
    EX_KIND_OBJ   = 0.35     # visto un oggetto, quanto meno incuriosiscono gli altri uguali
    EX_KIND_REGION = 0.6     # vista una faccia, quanto meno le altre dello stesso materiale
    # Continuità dello sguardo (continuity): lo sguardo passa volentieri a ciò
    # che sta accanto a dove guarda, e non torna su ciò che aveva già nella
    # retina e da cui si è girato. Una scia delle pose delle analisi ricorda
    # da dove si è guardato e in che direzione.
    EX_SACCADE    = 45.0 * DEG       # salto dello sguardo che, a continuity 1, dimezza il fascino
    EX_SACCADE_CAP = 120.0 * DEG     # oltre, girarsi costa uguale (dietro le spalle è dietro)
    EX_SACCADE_GO = 0.35     # per le mete del cammino (frontiere, spazio aperto) conta meno
    EX_RETURN     = 2.0      # tornare a ciò da cui lo sguardo si è girato: fascino / (1 + 2 a continuity 1)
    EX_RETURN_DEG = [15.0 * DEG, 45.0 * DEG].freeze   # quanto più vicino era lo sguardo, prima: niente → pieno
    EX_SWEEP_TAU  = 25.0     # s: la scia si scolora
    EX_SWEEP_NEAR = 4.0 * M_TO_IN    # pose più lontane di così non contano (camminando, la vista è nuova)
    EX_SWEEP_N    = 40       # pose ricordate

    # ── Corpo e sguardo ─────────────────────────────────────────────
    EX_GAZE_K     = 3.2      # 1/s: rapidità con cui lo sguardo insegue (come ORBIT_FOLLOW)
    EX_ACCEL      = 1.6      # m/s²
    EX_STEP_MAX   = 0.25     # m: gradini (scale sì, tavolini no)
    EX_STEER      = [0, 25, -25, 50, -50, 80, -80, 115, -115].freeze   # gradi di deviazione provati
    EX_STUCK_T    = 1.6      # s fra due controlli di avanzamento
    EX_STUCK_D    = 0.12 * M_TO_IN
    EX_LOOK_TURN  = 100.0 * DEG
    EX_LOOK_TIME  = 1.6
    EX_BLIND_MAX  = 10       # analisi di fila senza vedere nulla: ci si ferma
    EX_STALL_T    = 10.0     # s: ogni tanto si controlla di essersi mossi davvero
    EX_STALL_D    = 0.75 * M_TO_IN   # meno di così in EX_STALL_T, senza sosta né zoom: bloccato
    EX_ESCAPE_T   = 5.0      # s di cammino nella via di fuga, senza guardare nient'altro
    EX_ZOOM_K     = 2.2      # 1/s: rapidità dello zoom (sul logaritmo del campo visivo)
    EX_JUMP_DETOUR = 50.0 * DEG      # un giro più largo di così attorno all'ostacolo: meglio saltare
    EX_JUMP_RETRY  = 0.6     # s fra due tentativi (e dopo un atterraggio)
    EX_JUMP_NEAR   = 0.9 * M_TO_IN   # l'ostacolo da saltare è a portata di passo
    EX_JUMP_FAR    = 2.2 * M_TO_IN   # dove atterrare: al più così avanti
    EX_JUMP_STEP   = 0.15 * M_TO_IN  # passo della ricerca
    EX_JUMP_SAFE   = 0.85    # parte della quota massima dei piedi che si usa davvero
    EX_JUMP_PAD    = 0.6 * M_TO_IN   # attorno al punto d'arrivo, piano per almeno così
    EX_JUMP_VH     = 4.5     # m/s: in orizzontale non si vola più svelti di così
    EX_ORBIT_MAX   = 6.0 * M_TO_IN   # attorno a oggetti più grandi non si gira
    EX_ORBIT_SPEED = 0.7     # parte della velocità del passo girando attorno
    EX_ORBIT_AHEAD = 0.6 * M_TO_IN   # girando, l'oggetto deve vedersi anche da così più avanti

    # ── Pianta di ciò che si è visto: frontiere e giri attorno ai muri ──
    EX_PLAN_CELL   = 0.5 * M_TO_IN   # lato delle celle
    EX_PLAN_LV     = 2.0 * M_TO_IN   # piedi più in alto o in basso di così: un'altra pianta (un altro piano)
    EX_PLAN_REACH  = 15.0 * M_TO_IN  # un raggio segna la pianta fin qui
    EX_PLAN_MAX    = 400_000         # celle al più, poi si ricomincia
    EX_PLAN_BODY   = [-1.0 * M_TO_IN, 2.2 * M_TO_IN].freeze   # quote attorno ai piedi che contano
    PL_FREE = 1; PL_SOLID = 2; PL_DONE = 4; PL_BUMP = 8         # libera, piena, frontiera chiusa, urtata
    EX_FRONT_R     = 30      # celle: frontiere cercate entro 15 m
    EX_FRONT_UNK   = 8       # celle mai viste nel 5×5 attorno; meno è un buco fra due raggi
    EX_FRONT_MIN   = 3       # celle di frontiera vicine: più stretto non è un passaggio
    EX_FRONT_W     = 0.3     # peso di una zona mai vista (come lo spazio aperto, per roam)
    EX_SIGHT_T     = 0.3     # s fra due controlli che l'obiettivo sia ancora in vista
    EX_ROUTE_NODES = 2500    # A*: celle esaminate al più (un obiettivo irraggiungibile le esamina tutte)
    EX_ROUTE_SPAN  = 160     # celle (80 m): obiettivi più lontani non si aggirano
    EX_ROUTE_LOS   = 40      # arrivi provati con un raggio verso l'obiettivo; poi va bene il primo
    EX_ROUTE_AGAIN = 0.5     # s fra due ricerche
    EX_ROUTE_RENEW = 3.0     # s: un percorso si rifà comunque (la pianta cresce, magari c'è una scorciatoia)
    EX_ROUTE_NEAR  = 1.0 * M_TO_IN   # oltre la distanza di sosta più di così: si pianifica
    EX_ROUTE_GREED = 1.4     # A*: euristica gonfiata (percorsi di poco più lunghi, trovati prima)
    EX_ROUTE_LOOK  = 70.0 * DEG      # il percorso gira lontano dall'obiettivo: si guarda avanti
    EX_ROUTE_TRIES = 8       # percorsi rifatti dopo un urto, poi irraggiungibile
    EX_N8 = [[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0],
             [1, 1, 1.4142], [1, -1, 1.4142], [-1, 1, 1.4142], [-1, -1, 1.4142]].freeze
    EX_FLY_MUL    = 2.5
    EX_LAND       = 1.5 * M_TO_IN    # all'avvio, occhio entro altezza + questo dal pavimento: a piedi
    EX_VANTAGE    = 3.0 * M_TO_IN    # in volo, senza niente da guardare: si sale di tanto per giro
    EX_PX_MAX_MS  = 220.0    # occhio a colori più lento di così: si spegne da solo
    EX_LOG_MAX    = 60
    # Mappa dell'attenzione: [soglia, colore, lato del punto in px]
    EX_HEAT = [[0.12, [70, 140, 255], 4], [0.3, [0, 201, 167], 5],
               [0.5, [255, 209, 102], 6], [0.7, [255, 80, 60], 8]].freeze

    # Una cella della retina: punto colpito, distanza (pollici), normale verso
    # chi guarda, colore Lab, chiavi di faccia e oggetto per questa analisi,
    # oggetto e suo percorso, complessità, identità stabile, nome, area vera
    # della faccia (m²) e categoria (stessa definizione o stesso materiale).
    ExCell = Struct.new(:p, :d, :nx, :ny, :nz, :col, :fkey, :okey, :obj, :opath, :cplx, :ident, :label, :farea, :kind)

    @ex = nil

    # ══════════════════════════════════════════════════════════════
    # Avvio, arresto, pausa
    # ══════════════════════════════════════════════════════════════
    def self.explore_on?; !@ex.nil?; end

    # Tempo della simulazione (i test lo sostituiscono) e tempo vero di
    # calcolo, che decide quando la scansione cede e quanto è grande la retina.
    def self.explore_clock; @ex_clock ? @ex_clock.call : Process.clock_gettime(Process::CLOCK_MONOTONIC); end
    def self.explore_cpu; Process.clock_gettime(Process::CLOCK_MONOTONIC); end

    def self.explore_num(v)
      f = (Float(v) rescue nil)
      f&.finite? ? f : nil
    end

    # Predefiniti ← settings.json ("explore") ← profilo ← opzioni della
    # chiamata; tipi e intervalli ripuliti come fa il pannello con i suoi
    # valori. Il profilo è quello in uso, o opzioni['profile'] (id o nome);
    # pid lo impone (l'editor mostra un profilo che non è in uso).
    def self.explore_opts(user = nil, pid = nil)
      o = EX_DEFAULTS.dup
      want = user.is_a?(Hash) ? (user['profile'] || user[:profile]) : nil
      pid ||= explore_profile_find(want) || explore_profile_id
      [(@cfg || {})['explore'], explore_profile_values(pid), user].each do |src|
        next unless src.is_a?(Hash)
        src.each do |k, v|
          c = explore_clean(k.to_s, v)
          o[k.to_s] = c unless c.nil?
        end
      end
      o['profile'] = pid
      o
    end

    # Un valore ripulito, o nil se la chiave non esiste o il valore non vale
    # (resta quello dello strato di sotto).
    def self.explore_clean(k, v)
      d = EX_DEFAULTS[k]
      case d
      when nil         then nil
      when true, false then [true, 'true', 1, '1'].include?(v)
      when String      then EX_MODES.include?(v.to_s) ? v.to_s : nil
      else
        f = explore_num(v) or return nil
        lo, hi = EX_RANGES[k]
        d.is_a?(Integer) ? f.round.clamp(lo, hi) : f.clamp(lo, hi)
      end
    end

    # Ritorna nil se parte, altrimenti il motivo per cui non parte.
    def self.explore_start(opts = nil)
      err = explore_busy and return err
      model = Sketchup.active_model
      explore_stop if @ex
      load_cfg if @cfg.nil? || @cfg.empty?
      o = explore_opts(opts)
      view = model.active_view
      ke_dolly_end(view)                 # lib/keyedit.rb: un dolly a metà finisce, sfere com'erano
      cam = view.camera
      unless cam.perspective?
        cam.perspective = true
        cam.fov = 60.0 unless cam.fov.to_f.between?(10.0, 120.0)
      end
      eye = cam.eye
      d = cam.target - eye
      now = explore_clock
      @ex_cplx = {}                      # il modello può essere cambiato da un giro all'altro
      ex = {
        model: model, view: view, o: o, t: 0.0, last: now,
        x: eye.x, y: eye.y, z: eye.z, vx: 0.0, vy: 0.0, vz: 0.0,
        yaw: Math.atan2(d.y, d.x), pitch: Math.atan2(d.z, Math.hypot(d.x, d.y) + 1e-10),
        drop_in: o['max_drop'] * M_TO_IN,
        speed: o['speed'], heatmap: o['heatmap'], pixels: o['pixels'],
        gw_f: o['grid'].to_f, gw: o['grid'], geo: nil,
        scan_goal: o['scan_ms'], slice: o['frame_ms'],  # budget di un'analisi e di un fotogramma (ms)
        fr_at: nil, fr_slice: 0.0, fr_other: nil,       # tempi veri dei fotogrammi
        hz: nil, hz_lim: nil, cell_ms: nil, scan_w: 1.0, aspect: nil,   # cadenza delle analisi (explore_hz)
        target: nil, res: nil, scan: nil, next_scan: now, look: nil, blind: 0,
        mem: {}, walked: {}, bored: {}, visited: {}, kbored: {}, kvisited: {}, sweep: [],
        ctx: { memo: {}, omemo: {}, size: {}, fseq: 0, oseq: 0, t: now },
        rng: Random.new(o['seed']), log: [], seq: 0, steps: 0, trying: false,
        rec: [], rec_last: nil, bob: 0.0, hud_t: 0.0, scan_ms: 0.0, scan_n: 0, scan_hits: 0,
        call: opts.is_a?(Hash) ? opts : nil,           # per rifare le opzioni se cambia il profilo
        fov0: cam.fov.to_f, fov: cam.fov.to_f,          # campo visivo di partenza e attuale (zoom)
        anchor: [now, eye.x, eye.y, eye.z], escape: nil, # controllo di essersi mossi; via di fuga
        jump: nil, jumps: 0, jump_next: now,             # salto in corso, quanti, prossimo tentativo
        plan: {}, plan_z: {}, fronts: [], route: nil, route_job: nil, route_next: now,       # pianta, frontiere, giri
        routes: 0, replans: 0, plan_seq: 0, orbits: 0, route_why: Hash.new(0)   # perché si è (ri)pianificato
      }
      explore_body(ex)
      pilot_init(ex)                     # lib/expilot.rb: cose viste, agenda e avvisi per l'IA
      gal_ex_init(ex)                    # lib/gallery.rb: le foto del giro
      # posizioni dei percorsi (lib/pathkeys.rb): né viste, né ostacoli, né cose da guardare
      ex[:keys_hidden] = key_hide(model)
      explore_calibrate(view, ex)
      explore_pick_mode(ex)
      # prima si lascia lo strumento di adesso: se è un ExploreTool rimasto da
      # un giro di prima, il suo deactivate fermerebbe questo appena partito
      model.select_tool(nil)
      @ex = ex
      model.select_tool(ExploreTool.new)
      explore_attach(ex)
      Sketchup.status_text = explore_status_line(ex)
      xp_refresh                         # lib/exprofiles.rb: Esplora diventa Ferma
      nil
    rescue => fps_err
      log_error(__method__, fps_err)
      key_unhide(model, ex[:keys_hidden]) if ex
      @ex = nil
      fps_err.message
    end

    # Il corpo è quello del giocatore (pannello › Giocatore): altezza degli
    # occhi, raggio, gradino (al più EX_STEP_MAX: scale sì, tavolini no),
    # forza del salto e gravità. Riletto a ogni fotogramma, così una modifica
    # del pannello vale anche mentre esplora.
    def self.explore_body(ex)
      ex[:eye_h] = cf('eye_height').to_f.clamp(0.5, 3.0) * M_TO_IN
      ex[:radius_in] = cf('body_radius').to_f.clamp(0.05, 1.0) * M_TO_IN
      ex[:step_in] = cf('step_height').to_f.clamp(0.0, EX_STEP_MAX) * M_TO_IN
      ex[:slope] = Math.tan(cf('max_slope_deg').to_f.clamp(0.0, 60.0) * DEG)   # la salita più ripida a piedi
      ex[:jump_v] = cf('jump_force').to_f.clamp(0.0, 20.0)       # m/s
      ex[:grav] = cf('gravity').to_f.clamp(0.5, 50.0)            # m/s²
    end

    # A piedi se sotto gli occhi c'è un pavimento a portata, altrimenti in volo.
    def self.explore_pick_mode(ex)
      res = ray(ex[:x], ex[:y], ex[:z], 0, 0, -1)
      want = ex[:o]['mode']
      ex[:floor] = res ? res[0].z : nil
      walk = want != 'fly' && res && (want == 'walk' || ex[:z] - res[0].z <= ex[:eye_h] + EX_LAND)
      ex[:mode] = walk ? :walk : :fly
    end

    # Ferma l'esploratore; salva il giro come percorso. Ritorna il nome del
    # percorso salvato o nil. tool_gone: lo strumento se n'è già andato da sé.
    def self.explore_stop(tool_gone = false)
      ex = @ex or return nil
      @ex = nil
      explore_detach(ex)
      ex[:model].select_tool(nil) unless tool_gone
      key_unhide(ex[:model], ex[:keys_hidden])
      explore_unzoom(ex)
      name = ex[:o]['record'] ? explore_save_path(ex) : nil
      gal_finish(ex[:gal], name, ex[:rec])       # lib/gallery.rb: la serie sa di che percorso è
      @ex_last = { 'steps' => ex[:steps], 'seconds' => ex[:t].round(1), 'visited' => ex[:visited].size, 'path' => name }
      Sketchup.status_text = name ? format(t('rt.rec_saved'), name: name, time: path_clock(ex[:rec].last[0])) : t('rt.explore_off')
      xp_refresh
      name
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    # Pulsante e menu: fermo → la finestra di avvio (profilo, registrare o
    # no il percorso; lib/exprofiles.rb), attivo → si ferma.
    def self.explore_toggle
      return explore_stop if @ex
      err = explore_busy
      return Sketchup.status_text = err if err
      xs_open
      nil
    end

    # Perché ora non può partire (nil se può)
    def self.explore_busy
      t('rt.explore_busy') if @active || bridge_building? || @path_job || !Sketchup.active_model
    end

    # Fermarsi da dentro l'animazione: fuori, con un timer (come lo strumento
    # della camminata quando viene sostituito).
    def self.explore_stop_later(ex)
      ex[:anim] = nil
      UI.start_timer(0, false) { explore_stop if @ex.equal?(ex) }
    end

    # on: true pausa, false riprende, nil scambia. Ritorna lo stato di pausa.
    def self.explore_pause(on)
      ex = @ex or return nil
      on = !ex[:paused] if on.nil?
      if on && !ex[:paused]
        ex[:paused] = true
        explore_detach(ex)
      elsif !on && ex[:paused]
        ex[:paused] = false
        explore_sync(ex)
        explore_attach(ex) unless ex[:suspended]
      end
      Sketchup.status_text = explore_status_line(ex)
      ex[:view].invalidate
      ex[:paused]
    end

    # Uno strumento di vista (orbita col tasto centrale, panoramica) prende la
    # camera per un momento: l'esploratore aspetta e riparte da dove lo lasci.
    def self.explore_suspend(on)
      ex = @ex or return
      if on
        return if ex[:suspended]
        ex[:suspended] = true
        explore_detach(ex)
      elsif ex[:suspended]
        ex[:suspended] = false
        explore_sync(ex)
        explore_attach(ex) unless ex[:paused]
      end
    end

    # Riprende posizione e sguardo dalla camera (qualcuno può averla spostata).
    def self.explore_sync(ex)
      cam = ex[:view].camera
      e = cam.eye
      d = cam.target - e
      ex[:x] = e.x; ex[:y] = e.y; ex[:z] = e.z
      ex[:vx] = ex[:vy] = ex[:vz] = 0.0
      ex[:yaw] = Math.atan2(d.y, d.x)
      ex[:pitch] = Math.atan2(d.z, Math.hypot(d.x, d.y) + 1e-10)
      ex[:scan] = nil
      ex[:next_scan] = explore_clock
      ex[:steer] = nil
      ex[:escape] = nil
      ex[:jump] = nil                    # un salto a metà non riprende: si riparte da dove si è
      explore_route_drop(ex)
      ex[:fov] = cam.fov.to_f if cam.perspective?
      ex[:anchor] = [ex[:next_scan], e.x, e.y, e.z]
      explore_pick_mode(ex)
    end

    # Profilo cambiato (menu, editor, ponte) mentre esplora: le opzioni si
    # rifanno, con quelle della chiamata sopra; memoria e giro restano.
    def self.explore_reprofile(pid = nil)
      ex = @ex or return
      call = ex[:call] ? ex[:call].reject { |k, _| k.to_s == 'profile' } : nil
      o = explore_opts(call, pid)
      ex[:o] = o
      ex[:speed] = o['speed']
      ex[:drop_in] = o['max_drop'] * M_TO_IN
      ex[:pixels] = o['pixels']
      ex[:steer] = nil
      explore_pick_mode(ex) if o['mode'] != 'auto'
      Sketchup.status_text = explore_status_line(ex)
    end

    # ══════════════════════════════════════════════════════════════
    # Animazione (view.animation) e strumento (Esc, clic, menu, mappa)
    # ══════════════════════════════════════════════════════════════
    class ExploreAnimation
      def initialize(ex); @ex = ex; end
      def nextFrame(view); DagaWASD::FPSWalk.explore_frame(view, @ex); end
      # SketchUp l'ha tolta da sé (scena, altra animazione): ci si ferma
      def stop; DagaWASD::FPSWalk.explore_anim_gone(@ex); end
    end

    def self.explore_attach(ex)
      ex[:last] = explore_clock
      ex[:anim] = ExploreAnimation.new(ex)
      ex[:view].animation = ex[:anim]
    end

    def self.explore_detach(ex)
      return unless ex[:anim]
      ex[:anim] = nil                    # prima: lo stop che SketchUp chiama non deve fermare tutto
      ex[:view].animation = nil
    end

    def self.explore_anim_gone(ex)
      return unless @ex.equal?(ex) && ex[:anim]
      explore_stop_later(ex)
    end

    class ExploreTool
      def activate; Sketchup.active_model.active_view.invalidate; end
      # Un altro strumento ha preso il posto di questo: ci si ferma (e si salva)
      def deactivate(view)
        view.invalidate
        DagaWASD::FPSWalk.explore_stop(true)
      end
      def suspend(view); DagaWASD::FPSWalk.explore_suspend(true); view.invalidate; end
      def resume(view); DagaWASD::FPSWalk.explore_suspend(false); view.invalidate; end
      def onCancel(_reason, _view); DagaWASD::FPSWalk.explore_stop; end
      def onLButtonDown(_flags, _x, _y, _view); DagaWASD::FPSWalk.explore_stop; end
      # Rotella: velocità del passo (e niente zoom, che sposterebbe l'occhio)
      def onMouseWheel(_flags, delta, _x, _y, _view); DagaWASD::FPSWalk.explore_wheel(delta); true; end
      # I: righe d'informazione in alto a sinistra sì/no (tenendo premuto, una volta sola)
      def onKeyDown(key, repeat, _flags, _view)
        return false unless [73, 105].include?(key)
        DagaWASD::FPSWalk.explore_command('info') if repeat.to_i <= 1
        true
      end
      def getMenu(menu, _flags = nil, _x = nil, _y = nil, _view = nil); DagaWASD::FPSWalk.explore_menu(menu); end
      def getExtents; DagaWASD::FPSWalk.explore_extents; end
      def draw(view); DagaWASD::FPSWalk.explore_draw(view); end
      def getInstructorContentDirectory; nil; end
    end

    # ══════════════════════════════════════════════════════════════
    # Un fotogramma: analisi a fette, decisione, passo, sguardo, camera
    # ══════════════════════════════════════════════════════════════
    def self.explore_frame(view, ex)
      return false unless @ex.equal?(ex) && ex[:anim]
      now = explore_clock
      dt = (now - ex[:last]).clamp(0.0, 0.1)
      ex[:last] = now
      ex[:t] += dt
      explore_frame_time(ex)
      explore_scan_tick(view, ex, now)
      return false unless ex[:anim]                  # l'analisi può averlo fermato (niente da vedere)
      explore_body(ex)
      explore_think(ex, now, dt)
      explore_zoom_tick(ex, now, dt)
      if ex[:jump] then explore_jump_tick(ex, now)
      elsif ex[:mode] == :fly then explore_fly(ex, now, dt)
      else explore_walk(ex, now, dt)
      end
      explore_stall(ex, now)
      explore_gaze(ex, dt)
      explore_camera(view, ex, dt)
      pilot_photo_tick(view, ex, now)            # lib/expilot.rb: la foto della sosta, se si aspetta
      gal_tick(view, ex, now)                    # lib/gallery.rb: la foto per la galleria, se si aspetta
      explore_rec_tick(ex, view)
      explore_hud(ex, now)
      dur = ex[:o]['duration']
      return true unless dur > 0 && ex[:t] >= dur
      explore_stop_later(ex)
      false
    rescue => fps_err
      log_error(__method__, fps_err)
      explore_stop_later(ex)
      false
    end

    # Quanto costa un fotogramma senza le fette di calcolo (scansione e
    # percorsi): il disegno di SketchUp e il resto dell'esploratore. Dal
    # tempo vero fra due fotogrammi, tolte le fette di quello prima; le
    # attese lunghe (pausa, finestre aperte) non contano.
    def self.explore_frame_time(ex)
      t = explore_cpu
      if (a = ex[:fr_at]) && t - a < 0.5
        other = [(t - a) * 1000.0 - ex[:fr_slice], 0.0].max
        ex[:fr_other] = ex[:fr_other] ? ex[:fr_other] + EX_FRAME_K * (other - ex[:fr_other]) : other
      end
      ex[:fr_at] = t
      ex[:fr_slice] = 0.0
    end

    # ══════════════════════════════════════════════════════════════
    # Retina: raggi attraverso lo schermo, a fette dentro una Fiber
    # ══════════════════════════════════════════════════════════════
    def self.explore_scan_tick(view, ex, now)
      unless ex[:scan]
        return if now < ex[:next_scan]
        explore_scan_begin(view, ex, now)
      end
      t0 = explore_cpu
      res = ex[:scan].resume
      ex[:scan_cpu] += explore_cpu - t0
      ex[:fr_slice] += (explore_cpu - t0) * 1000.0
      return if ex[:scan].alive?
      ex[:scan] = nil
      ex[:plan_seq] += 1                 # la pianta può essere cambiata: i percorsi si ricontrollano
      explore_adapt(ex)
      ex[:next_scan] = ex[:scan_t0] + 1.0 / explore_hz(ex)
      explore_decide(ex, res, now)
    rescue => fps_err
      log_error(__method__, fps_err)
      ex[:scan] = nil
      ex[:next_scan] = now + 0.5
    end

    # I raggi partono tutti dalla posa di adesso (la camera poi si muove, ma
    # la retina descrive quello che si vedeva qui), e l'immagine dell'occhio
    # a colori viene scattata nello stesso istante.
    def self.explore_scan_begin(view, ex, now)
      vw = view.vpwidth.to_f
      vh = view.vpheight.to_f
      gw = ex[:gw]
      gh = (gw * vh / [vw, 1.0].max).round.clamp(6, 48)
      ex[:aspect] = vh / [vw, 1.0].max
      geo = ex[:geo] = explore_geo(view, ex, gw, gh)
      rays = explore_rays(view, gw, gh, geo)
      img = ex[:pixels] ? explore_grab(view, ex) : nil
      budget = ex[:slice] / 1000.0
      model = ex[:model]
      walk = ex[:mode] == :walk
      ctx = explore_ctx(ex, now)
      nov = ->(p) { explore_novelty(ex, p, now) }
      # con la cadenza adattiva un'analisi vale per il tempo dall'ultima, in
      # passi: memoria, scia e cecità vanno come con una per passo, a ogni cadenza
      lim = ex[:hz_lim] = explore_hz_limits
      prev = ex[:scan_t0]
      ex[:scan_w] = lim && prev ? ((now - prev) / ex[:o]['step_time']).clamp(0.1, 3.0) : 1.0
      ex[:scan_t0] = now
      ex[:scan_pose] = [ex[:x], ex[:y], ex[:yaw], explore_half_hfov(view)]
      ex[:scan_cpu] = 0.0
      ex[:scan_n] = rays.size
      # a piedi, la pianta: piedi e posizione di adesso
      feet = walk && ex[:floor]
      step_in = ex[:step_in]
      x0 = ex[:x]
      y0 = ex[:y]
      fronts = ex[:o]['roam'] > 0.0
      ex[:scan] = Fiber.new do
        pmap = img && explore_pixel_map(img, gw, gh, budget, geo)
        cells = explore_cast(model, rays, ctx, budget)
        res = explore_saliency(cells, gw, gh, rays: rays, px: pmap, nov: nov, walk: walk, budget: budget, geo: geo,
                               w: explore_weights(ex[:o]), objw: ex[:o]['w_object'], open: ex[:o]['roam'])
        if feet
          explore_plan_mark(ex[:plan], ex[:plan_z], cells, rays, gw, feet, step_in, budget)
          res[:fronts] = explore_frontiers(ex[:plan], ex[:plan_z], x0, y0, feet, budget, model: model) if fronts
        end
        res
      end
    end

    # Retina dinamica: la fovea, cioè dove le celle sono più fitte, sta su
    # ciò che si guarda (l'obiettivo, se è nella vista) o al centro. Le
    # celle restano una griglia gw×gh, righe e colonne intere (la pianta
    # legge le colonne); cambia solo dove cadono sullo schermo, asse per
    # asse. Per asse: centri e bordi delle celle (0..1) e il loro peso, la
    # parte di schermo che coprono rispetto a una retina uniforme.
    def self.explore_geo(view, ex, gw, gh)
      a = ex[:o]['fovea'].to_f
      fx = fy = 0.5
      tgt = ex[:target]
      if a > 0.0 && tgt && !ex[:look]
        p = Geom::Point3d.new(*tgt[:pt])
        cam = view.camera
        e = cam.eye
        d = cam.direction
        if (p.x - e.x) * d.x + (p.y - e.y) * d.y + (p.z - e.z) * d.z > 0.0
          s = view.screen_coords(p)
          fx = (s.x / [view.vpwidth, 1].max).clamp(EX_FOVEA_EDGE, 1.0 - EX_FOVEA_EDGE)
          fy = (s.y / [view.vpheight, 1].max).clamp(EX_FOVEA_EDGE, 1.0 - EX_FOVEA_EDGE)
        end
      end
      ux, wx, bx = explore_fovea_axis(gw, fx, a)
      vy, wy, by = explore_fovea_axis(gh, fy, a)
      { ux: ux, vy: vy, wx: wx, wy: wy, bx: bx, by: by, fx: fx, fy: fy }
    end

    # Un asse: densità delle celle 1 + a·e^(-((s - f)/EX_FOVEA_W)²), fino a
    # 1 + a volte più fitte attorno al fuoco f e più rade lontano (sono
    # sempre n). → [centri, pesi, bordi]; con a = 0 la retina uniforme.
    def self.explore_fovea_axis(n, f, a)
      if a <= 0.0 || n < 2
        return [Array.new(n) { |k| (k + 0.5) / n }, Array.new(n, 1.0), Array.new(n + 1) { |k| k.to_f / n }]
      end
      m = 256
      cdf = Array.new(m + 1, 0.0)
      m.times do |j|
        s = (j + 0.5) / m
        cdf[j + 1] = cdf[j] + (1.0 + a * Math.exp(-((s - f) / EX_FOVEA_W)**2)) / m
      end
      tot = cdf[m]
      inv = lambda do |u|                        # s dove la densità cumulata vale u
        q = u * tot
        j = (cdf.bsearch_index { |c| c >= q } || m).clamp(1, m)
        (j - 1 + ((q - cdf[j - 1]) / (cdf[j] - cdf[j - 1])).clamp(0.0, 1.0)) / m
      end
      edges = Array.new(n + 1) { |k| inv.(k.to_f / n) }
      [Array.new(n) { |k| inv.((k + 0.5) / n) }, Array.new(n) { |k| (edges[k + 1] - edges[k]) * n }, edges]
    end

    # Raggi al centro di ogni cella. Solo tre pickray (gli angoli): per una
    # camera prospettica la direzione riportata sul piano a distanza 1 è
    # affine nelle coordinate dello schermo, per una parallela lo è
    # l'origine; interpolare è quindi esatto in entrambi i casi. geo: dove
    # cadono le celle (explore_geo), senza la retina uniforme.
    def self.explore_rays(view, gw, gh, geo = nil)
      vw = view.vpwidth
      vh = view.vpheight
      fwd = view.camera.direction
      corner = lambda do |x, y|
        o, d = view.pickray(x, y)
        k = d.x * fwd.x + d.y * fwd.y + d.z * fwd.z
        k = 1.0 if k.abs < 1e-9
        [o.x, o.y, o.z, d.x / k, d.y / k, d.z / k]
      end
      a = corner.call(0, 0)
      b = corner.call(vw, 0)
      c = corner.call(0, vh)
      Array.new(gw * gh) do |i|
        u = geo ? geo[:ux][i % gw] : ((i % gw) + 0.5) / gw
        v = geo ? geo[:vy][i / gw] : ((i / gw) + 0.5) / gh
        q = Array.new(6) { |k| a[k] + (b[k] - a[k]) * u + (c[k] - a[k]) * v }
        l = Math.sqrt(q[3] * q[3] + q[4] * q[4] + q[5] * q[5])
        [Geom::Point3d.new(q[0], q[1], q[2]), Geom::Vector3d.new(q[3] / l, q[4] / l, q[5] / l)]
      end
    end

    # Lancia i raggi; con budget (s) cede il controllo quando lo supera.
    def self.explore_cast(model, rays, ctx, budget = nil)
      cells = Array.new(rays.size)
      deadline = budget && explore_cpu + budget
      rays.each_with_index do |r, i|
        cells[i] = explore_sample(model, r, ctx)
        next unless deadline && explore_cpu >= deadline
        Fiber.yield
        deadline = explore_cpu + budget
      end
      cells
    end

    # Memorie per percorso colpito: normale, colori, oggetto, nome. Si
    # svuotano ogni tanto, perché il modello può cambiare (il ponte disegna).
    def self.explore_ctx(ex, now)
      c = ex[:ctx]
      if now - c[:t] > 30.0 || c[:memo].size > 20_000
        c[:memo].clear; c[:omemo].clear; c[:size].clear
        c[:t] = now
      end
      c[:dflt] = explore_default_colors(ex[:model])
      c
    end

    # Colori delle facce senza materiale, secondo lo stile del modello.
    def self.explore_default_colors(model)
      ro = model.rendering_options
      f = ro['FaceFrontColor']
      b = ro['FaceBackColor']
      [f ? explore_lab_color(f) : [100.0, 0.0, 0.0], b ? explore_lab_color(b) : [60.0, 0.0, -20.0]]
    rescue => fps_err
      log_error(__method__, fps_err)
      [[100.0, 0.0, 0.0], [60.0, 0.0, -20.0]]
    end

    # Un raggio: nil se va nel vuoto, altrimenti una cella della retina.
    def self.explore_sample(model, ray, ctx)
      res = model.raytest(ray, true)            # true: solo ciò che si vede (niente nascosti)
      return nil unless res
      path = res[1]
      return nil unless path.is_a?(Array) && !path.empty?
      info = (ctx[:memo][path.map(&:entityID)] ||= explore_path_info(path, ctx))
      o = ray[0]
      dir = ray[1]
      pt = res[0]
      if (n = info[:n])
        nx, ny, nz = n
        front = nx * dir.x + ny * dir.y + nz * dir.z <= 0.0
        unless front
          nx = -nx; ny = -ny; nz = -nz
        end
      else
        front = true
        nx = -dir.x; ny = -dir.y; nz = -dir.z
      end
      d = Math.sqrt((pt.x - o.x)**2 + (pt.y - o.y)**2 + (pt.z - o.z)**2)
      ExCell.new(pt, d, nx, ny, nz, front ? info[:cf] : info[:cb], info[:fkey], info[:okey], info[:obj],
                 info[:opath], info[:cplx], info[:ident], info[:label], info[:farea], info[:kind])
    end

    # L'oggetto di un percorso è il gruppo o componente più esterno a misura
    # d'uomo: dentro un edificio fatto gruppo la sedia, non l'edificio; dentro
    # la sedia la sedia, non la gamba. Senza, l'unità è la faccia.
    def self.explore_path_info(path, ctx)
      leaf = path.last
      tr = nil; inh = nil; obj = nil; opath = nil
      lo = EX_OBJ[0] * M_TO_IN
      hi = EX_OBJ[1] * M_TO_IN
      path[0...-1].each_with_index do |e, k|
        next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
        tr = tr ? tr * e.transformation : e.transformation
        m = e.material
        inh = m if m                             # vince il più interno con un materiale
        next if obj
        s = (ctx[:size][e] ||= e.bounds.diagonal.to_f)
        next unless s >= lo && s <= hi
        obj = e
        opath = path[0..k]
      end
      n = nil
      fm = bm = inh
      farea = 1.0
      if leaf.is_a?(Sketchup::Face)
        v = leaf.normal
        x, y, z = tr ? normal_xform(tr.to_a, v.x, v.y, v.z) : [v.x, v.y, v.z]
        l = Math.sqrt(x * x + y * y + z * z)
        n = [x / l, y / l, z / l] if l > 1e-12
        fm = leaf.material || inh
        bm = leaf.back_material || inh
        # area vera (m²): una parete o un pavimento sono grandi, un pannello no
        farea = (tr ? leaf.area(tr) : leaf.area).to_f * IN_TO_M * IN_TO_M
      end
      dflt = ctx[:dflt] || [[100.0, 0.0, 0.0], [60.0, 0.0, -20.0]]
      okey = obj ? (ctx[:omemo][opath.map(&:entityID)] ||= (ctx[:oseq] += 1)) : nil
      { n: n, cf: fm ? explore_lab_color(fm.color) : dflt[0], cb: bm ? explore_lab_color(bm.color) : dflt[1],
        fkey: (ctx[:fseq] += 1), okey: okey, obj: obj, opath: opath,
        ident: obj ? "o#{opath.map(&:entityID).join('/')}" : "f#{path.map(&:entityID).join('/')}",
        label: obj ? entity_label(obj) : (fm ? fm.display_name.to_s : t('explore.surface')),
        cplx: obj ? explore_complexity(obj) : 0.0, farea: farea,
        # categoria: visto un divano, gli altri uguali incuriosiscono meno; vista una parete d'intonaco, tutte
        kind: obj ? "d:#{obj.definition.name}" : "m:#{fm ? fm.display_name : '-'}" }
    rescue => fps_err
      log_error(__method__, fps_err)
      { n: nil, cf: [50.0, 0.0, 0.0], cb: [50.0, 0.0, 0.0], fkey: (ctx[:fseq] += 1), okey: nil, obj: nil,
        opath: nil, ident: 'x', label: '?', cplx: 0.0, farea: 1.0, kind: '-' }
    end

    # Quante facce ha un oggetto (gruppi annidati compresi), in scala 0–1.
    def self.explore_complexity(obj)
      d = obj.definition
      @ex_cplx ||= {}
      return @ex_cplx[d] if @ex_cplx.key?(d)
      n = 0
      walk = lambda do |ents, depth|
        ents.each do |e|
          break if n > EX_CPLX_CAP
          if e.is_a?(Sketchup::Face)
            n += 1
          elsif depth < 4 && (e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group))
            walk.call(e.definition.entities, depth + 1)
          end
        end
      end
      walk.call(d.entities, 0)
      @ex_cplx[d] = (Math.log10(1.0 + n) / Math.log10(1.0 + EX_CPLX_REF)).clamp(0.0, 1.0)
    rescue => fps_err
      log_error(__method__, fps_err)
      0.5
    end

    # ── Colore: sRGB → CIELab (D65), dove le distanze sono percettive ──
    EX_SRGB = Array.new(256) { |i| c = i / 255.0; c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }.freeze

    def self.explore_lab_color(c); explore_lab(c.red.to_i, c.green.to_i, c.blue.to_i); end

    def self.explore_lab(r, g, b)
      r = EX_SRGB[r.clamp(0, 255)]
      g = EX_SRGB[g.clamp(0, 255)]
      b = EX_SRGB[b.clamp(0, 255)]
      fx = explore_lab_f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
      fy = explore_lab_f(0.2126 * r + 0.7152 * g + 0.0722 * b)
      fz = explore_lab_f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
      [116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)]
    end

    def self.explore_lab_f(v); v > 0.008856 ? Math.cbrt(v) : 7.787 * v + 16.0 / 116.0; end

    # Pesi delle misure di salienza secondo il profilo (si normalizzano: conta il rapporto)
    def self.explore_weights(o)
      { d: EX_W[:d] * o['w_shape'], n: EX_W[:n] * o['w_shape'], f: EX_W[:f] * o['w_detail'],
        c: EX_W[:c] * o['w_color'], r: EX_W[:r] * o['w_rare'], o: EX_W[:o] * o['w_object'], p: EX_W[:p] }
    end

    # Quanto è piccola una faccia: 1 sotto 0,3 m², 0 da 4 m² in su (pareti, pavimenti)
    def self.explore_small(area_m2); 1.0 - explore_ss(0.3, 4.0, area_m2.to_f); end

    def self.explore_ss(e0, e1, x)
      return x >= e1 ? 1.0 : 0.0 if e1 <= e0
      t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0)
      t * t * (3.0 - 2.0 * t)
    end

    # ══════════════════════════════════════════════════════════════
    # Salienza: dalle celle ai candidati
    # Funzione pura delle celle (più novità, da fuori): i test la provano
    # da sola. Ritorna { cells, gw, gh, f (salienza per cella), cands, hits }.
    # Con budget (s), dentro la Fiber della scansione cede anche lei ogni
    # tanto: con una retina fine il calcolo non pesa su un fotogramma solo.
    # ══════════════════════════════════════════════════════════════
    # w: pesi delle misure (explore_weights, dal profilo); objw: quanto un
    # oggetto vale più di una faccia sciolta; open: peso dello spazio aperto.
    # geo: la retina dinamica (explore_geo). Ogni cella pesa per la parte di
    # vista che copre, così rarità, grandezza e colore medio sono quelli
    # della vista e non della griglia (nella fovea le celle sono piccole).
    def self.explore_saliency(cells, gw, gh, rays: nil, px: nil, nov: nil, walk: true, budget: nil,
                              w: EX_W, objw: 1.0, open: 1.0, geo: nil)
      n = gw * gh
      f = Array.new(n, 0.0)
      cw = geo ? Array.new(n) { |i| geo[:wx][i % gw] * geo[:wy][i / gw] } : Array.new(n, 1.0)
      deadline = budget && explore_cpu + budget
      pause = lambda do |i|
        next unless deadline && (i & 127).zero? && explore_cpu >= deadline
        Fiber.yield
        deadline = explore_cpu + budget
      end
      hit = 0
      hw = 0.0                                   # le celle colpite, pesate
      cnt_o = Hash.new(0.0)
      cnt_f = Hash.new(0.0)
      g0 = g1 = g2 = 0.0
      cells.each_with_index do |c, i|
        next unless c
        q = cw[i]
        hit += 1
        hw += q
        cnt_o[c.okey] += q if c.okey
        cnt_f[c.fkey] += q
        g0 += c.col[0] * q; g1 += c.col[1] * q; g2 += c.col[2] * q
      end
      return { cells: cells, gw: gw, gh: gh, f: f, cands: [], hits: 0, geo: geo } if hit.zero?
      g0 /= hw; g1 /= hw; g2 /= hw
      lg = cells.map { |c| c && Math.log(c.d * IN_TO_M + 0.3) }
      wsum = w[:d] + w[:n] + w[:f] + w[:c] + w[:r] + w[:o] + (px ? w[:p] : 0.0)
      wsum = 1.0 if wsum < 1e-6

      # ── misure grezze per cella ──
      raw = Array.new(n, 0.0)
      parts = Array.new(n)                       # le parti della salienza: perché spicca (lib/gallery.rb)
      n.times do |i|
        pause.call(i)
        c = cells[i] or next
        x = i % gw
        y = i / gw
        ed = 0.0
        en = 0.0
        EX_N4.each do |ox, oy|
          xx = x + ox
          yy = y + oy
          next if xx < 0 || yy < 0 || xx >= gw || yy >= gh
          j = yy * gw + xx
          o = cells[j]
          if o.nil?
            ed = EX_VOID_EDGE if ed < EX_VOID_EDGE   # sagoma contro il vuoto
            next
          end
          dl = lg[j] - lg[i]
          if dl > 0.0                            # il bordo è del lato vicino, non dello sfondo
            e = dl / EX_DEPTH_EDGE
            ed = e > 1.0 ? 1.0 : e if e > ed
          end
          next unless dl.abs < 0.15
          e = (1.0 - (c.nx * o.nx + c.ny * o.ny + c.nz * o.nz)) * 1.5
          en = e > 1.0 ? 1.0 : e if e > en
        end
        # dettaglio (facce diverse nel 3×3) e media del colore nel 5×5
        s0 = s1 = s2 = 0.0
        m = 0
        uniq = []
        (-2..2).each do |oy|
          yy = y + oy
          next if yy < 0 || yy >= gh
          (-2..2).each do |ox|
            xx = x + ox
            next if xx < 0 || xx >= gw
            o = cells[yy * gw + xx] or next
            s0 += o.col[0]; s1 += o.col[1]; s2 += o.col[2]
            m += 1
            uniq << o.fkey if ox.abs <= 1 && oy.abs <= 1 && !uniq.include?(o.fkey)
          end
        end
        # facce diverse in un 3×3: in una cella piccola (fovea) se ne vedono
        # meno, più o meno in proporzione al lato
        det = ((uniq.size - 1) / (4.0 * Math.sqrt(cw[i]))).clamp(0.0, 1.0)
        cc = c.col
        loc = Math.sqrt((cc[0] - s0 / m)**2 + (cc[1] - s1 / m)**2 + (cc[2] - s2 / m)**2) / EX_COL_LOCAL
        glo = Math.sqrt((cc[0] - g0)**2 + (cc[1] - g1)**2 + (cc[2] - g2)**2) / EX_COL_GLOBAL
        con = 0.55 * loc.clamp(0.0, 1.0) + 0.45 * glo.clamp(0.0, 1.0)
        rar = if c.okey then 1.0 - Math.sqrt(cnt_o[c.okey] / hw)
              else 0.6 * (1.0 - Math.sqrt(cnt_f[c.fkey] / hw)) * (0.4 + 0.6 * explore_small(c.farea))
              end
        obj = c.obj ? 0.55 + 0.45 * c.cplx : 0.0
        parts[i] = [w[:d] * ed, w[:n] * en, w[:f] * det, w[:c] * con, w[:r] * rar, w[:o] * obj]
        s = w[:d] * ed + w[:n] * en + w[:f] * det + w[:c] * con + w[:r] * rar + w[:o] * obj   # non sum: arrotonda diverso
        s += w[:p] * px[i] if px
        s /= wsum
        s *= 0.45 if c.okey.nil? && c.nz.abs > 0.85    # pavimenti e soffitti: poco interessanti
        raw[i] = s
      end

      # ── levigatura 3×3, distanza, centro, novità ──
      far = EX_FAR[walk ? :walk : :fly]
      n.times do |i|
        pause.call(i)
        c = cells[i] or next
        x = i % gw
        y = i / gw
        sw = 0.0
        sv = 0.0
        (-1..1).each do |oy|
          yy = y + oy
          next if yy < 0 || yy >= gh
          (-1..1).each do |ox|
            xx = x + ox
            next if xx < 0 || xx >= gw
            j = yy * gw + xx
            next unless cells[j]
            wt = ox.zero? && oy.zero? ? 4.0 : (ox.zero? || oy.zero? ? 2.0 : 1.0)
            sw += wt
            sv += wt * raw[j]
          end
        end
        s = 0.5 * raw[i] + 0.5 * sv / sw
        dm = c.d * IN_TO_M
        s *= explore_ss(EX_NEAR[0], EX_NEAR[1], dm) * (1.0 - 0.75 * explore_ss(far[0], far[1], dm))
        cx = (geo ? geo[:ux][x] : (x + 0.5) / gw) - 0.5
        cy = (geo ? geo[:vy][y] : (y + 0.5) / gh) - 0.5
        s *= 0.8 + 0.2 * Math.exp(-(cx * cx + cy * cy) / 0.18)
        s *= nov.call(c.p) if nov
        f[i] = s
      end

      # ── gruppi: un candidato per oggetto, o per faccia ──
      groups = {}
      n.times do |i|
        c = cells[i] or next
        key = c.okey ? c.okey * 2 : c.fkey * 2 + 1
        g = (groups[key] ||= { pi: i, peak: -1.0, sum: 0.0, cnt: 0.0, sx: 0.0, sy: 0.0, sz: 0.0, sw: 0.0 })
        v = f[i]
        g[:cnt] += cw[i]
        g[:sum] += v * cw[i]
        if v > g[:peak]
          g[:peak] = v
          g[:pi] = i
        end
        wv = v * v * cw[i]                       # baricentro tirato verso le celle più salienti
        g[:sx] += c.p.x * wv; g[:sy] += c.p.y * wv; g[:sz] += c.p.z * wv
        g[:sw] += wv
      end
      cands = []
      groups.each_value do |g|
        next if g[:peak] < EX_MIN_PEAK
        c0 = cells[g[:pi]]
        pt = g[:sw] > 0.0 ? [g[:sx] / g[:sw], g[:sy] / g[:sw], g[:sz] / g[:sw]] : [c0.p.x, c0.p.y, c0.p.z]
        area = g[:cnt] / hw
        mass = (g[:sum] / Math.sqrt(g[:cnt])).clamp(0.0, 1.0)
        base = 0.6 * g[:peak] + 0.4 * mass
        size_f = (0.55 + 0.45 * explore_ss(0.0, 0.012, area)) * (1.0 - 0.6 * explore_ss(0.25, 0.65, area))
        # un oggetto vale di più se è complesso; una faccia sciolta poco, e
        # pochissimo se è grande (pareti, pavimenti: struttura, non cose)
        obj_f = c0.obj ? (1.0 + 0.35 * c0.cplx) * (0.4 + 0.6 * objw) : EX_REGION_W * (0.45 + 0.55 * explore_small(c0.farea))
        cands << { id: c0.ident, kind: c0.kind, pt: pt, score: base * size_f * obj_f, area: area, cell: g[:pi],
                   label: c0.label, obj: c0.obj, opath: c0.opath, open: false, why: parts[g[:pi]] }
      end

      # ── spazio aperto davanti, all'altezza degli occhi o poco sotto: porte,
      # corridoi, l'altro capo della stanza. Solo raggi che colpiscono: il
      # cielo sopra un muro o il vuoto oltre un bordo non sono strade.
      if walk && rays
        ds = cells.compact.map(&:d).sort
        med = [ds[ds.size / 2] * IN_TO_M, 0.3].max
        lo = -Math.sin(EX_OPEN_PITCH)
        hi = Math.sin(3.0 * DEG)
        best = nil
        n.times do |i|
          c = cells[i] or next
          dz = rays[i][1].z
          next if dz < lo || dz > hi
          o = explore_ss(1.6, 4.0, c.d * IN_TO_M / med)
          next if o <= 0.0
          s = o * (nov ? nov.call(c.p) : 1.0)
          best = [s, i, c.p] if best.nil? || s > best[0]
        end
        if best
          pt = best[2]
          cell = 3.0 * M_TO_IN
          cands << { id: "a#{(pt.x / cell).floor},#{(pt.y / cell).floor}", pt: [pt.x, pt.y, pt.z],
                     score: EX_OPEN_W * open * best[0], area: 0.0, cell: best[1], label: t('explore.open'),
                     obj: nil, opath: nil, open: true }
        end
      end
      cands.sort_by! { |c| -c[:score] }
      { cells: cells, gw: gw, gh: gh, f: f, cands: cands, hits: hit, geo: geo }
    end

    # ══════════════════════════════════════════════════════════════
    # Decisione: quale punto, con memoria e un po' di ostinazione
    # ══════════════════════════════════════════════════════════════
    def self.explore_decide(ex, res, now)
      ex[:res] = res
      ex[:steps] += 1
      ex[:scan_hits] = res[:hits]
      if res[:hits].zero?
        ex[:blind] += [ex[:scan_w] || 1.0, 1.0].min
        return explore_stop_later(ex) if ex[:blind] >= EX_BLIND_MAX   # niente da vedere da nessuna parte
      else
        ex[:blind] = 0
        explore_seen(ex, res, now)
      end
      explore_sweep_note(ex, now)
      ex[:fronts] = res[:fronts] || []
      return if ex[:escape]                      # sulla via di fuga non si guarda altro
      o = ex[:o]
      whim = o['whim']
      cands = res[:cands]
      walk = ex[:mode] == :walk
      ex[:fronts].each { |f| cands << explore_front_cand(ex, f) } if walk
      pilot_seen(ex, cands, now)                 # lib/expilot.rb: l'elenco delle cose viste, per l'IA
      cur = ex[:target]
      cands.each do |c|
        k = explore_bored_f(ex, c, now) * explore_walk_f(ex, c[:pt], now) * (1.0 - whim + 2.0 * whim * ex[:rng].rand)
        k *= pilot_like_f(ex, c)                 # i gusti dati dall'IA
        # l'obiettivo di adesso no: lo si sta già guardando, o aggirando
        k *= explore_shift_f(ex, c, now) unless cur && (c[:id] == cur[:id] || (cur[:front] && c[:front] && explore_front_same?(c, cur)))
        if walk
          # a piedi, ciò che sta su un altro piano si guarda ma non si insegue
          k *= 1.0 - 0.5 * explore_ss(1.5, 4.0, (c[:pt][2] - ex[:z]).abs * IN_TO_M)
        elsif !c[:obj]
          k *= 0.5                               # dall'alto muri e tetti sono struttura: si cercano le cose
        end
        c[:score] *= k
      end
      cands.sort_by! { |c| -c[:score] }
      pilot_next(ex, now)                        # una meta dell'IA in agenda diventa l'obiettivo
      cur = ex[:target]
      keep = 0.0
      # una zona mai vista che non è più al bordo di niente: vista, fatto
      if cur && cur[:front] && !cur[:arrived] && cands.none? { |c| c[:front] && explore_front_same?(c, cur) }
        explore_satiate(ex, now, 'scoperto')
        cur = nil
      end
      if cur
        m = cands.find { |c| c[:id] == cur[:id] } ||
            (cur[:front] && cands.find { |c| c[:front] && explore_front_same?(c, cur) }) ||
            cands.find { |c| !c[:open] && !cur[:open] && explore_d3(c[:pt], cur[:pt]) < 0.6 * M_TO_IN } ||
            (cur[:open] && !cur[:front] && cands.find { |c| c[:open] && !c[:front] && explore_same_way?(ex, c[:pt], cur[:pt]) })
        if m
          cur[:seen] = now
          cur[:score] = m[:score]
          cur[:front] = m[:front] if cur[:front]
          # avvicinandosi il punto si affina, senza scatti (lo spazio aperto si sposta con lo sguardo)
          # (un punto dato dall'IA resta quello)
          a = 1.0 - 0.65**(ex[:scan_w] || 1.0)   # 0,35 per analisi, a ogni cadenza
          cur[:pt] = Array.new(3) { |k| cur[:pt][k] + (m[:pt][k] - cur[:pt][k]) * a } unless cur[:arrived] || (cur[:ai] && cur[:ai][:act] == :to)
          keep = m[:score] * o['sticky']
        elsif now - cur[:seen] < 2.5 || explore_routing?(ex, cur)
          # appena uscito di vista (una retina rada lo perde e lo ritrova), o
          # nascosto dietro ciò che si sta aggirando: lo si tiene ancora
          keep = cur[:score] * o['sticky'] * 0.85
        end
        # davanti all'obiettivo lo si guarda fino in fondo; appena scelto (o mentre lo
        # si ingrandisce) non si cambia idea: senza, gli obiettivi si alternano a ogni
        # analisi, lo sguardo li insegue e non si fa mai un passo
        # una meta dell'IA si tiene finché non è fatta
        keep = Float::INFINITY if cur[:arrived] || cur[:ai] || now - cur[:since] < o['commit'] || explore_zooming?(ex)
      end
      best = cands.find { |c| cur.nil? || c[:id] != cur[:id] }
      # a forza di guardarsi intorno senza trovare nulla ci si accontenta:
      # la soglia si dimezza a ogni giro, così non si resta a girare sul posto
      min = EX_MIN_SCORE * 0.5**ex[:looks].to_i
      if cur && keep > 0.0 && (best.nil? || best[:score] <= keep)
        ex[:look] = nil
      elsif best && best[:score] >= min
        explore_aim(ex, best, now)
      elsif cur && keep > 0.0
        ex[:look] = nil
      else
        ex[:target] = nil
        explore_look_around(ex, res, now) unless ex[:look]
      end
    end

    # Nuovo obiettivo. La distanza a cui fermarsi dipende da quanto è grande:
    # abbastanza lontano da vederlo intero, mai meno di standoff.
    def self.explore_aim(ex, c, now)
      standoff = ex[:o]['standoff'] * M_TO_IN
      dwell = ex[:o]['dwell']
      size = 1.5 * M_TO_IN                       # una faccia sciolta: un pezzo da un metro e mezzo
      center = nil
      if c[:front]
        # una zona mai vista: ci si ferma sul bordo, guardandoci dentro
        standoff = 1.0 * M_TO_IN
        dwell = 0.6
      elsif c[:open]
        standoff = 0.6 * M_TO_IN
        dwell = 0.0
      elsif c[:opath] && c[:obj].valid?
        bb = explore_world_box(c[:opath])
        size = [bb.max.z - bb.min.z, Math.hypot(bb.max.x - bb.min.x, bb.max.y - bb.min.y), 0.1 * M_TO_IN].max
        center = [(bb.min.x + bb.max.x) / 2.0, (bb.min.y + bb.max.y) / 2.0]
        half = (ex[:view].camera.fov.to_f.clamp(10.0, 120.0) / 2.0) * DEG
        standoff = (0.55 * size / Math.tan(half)).clamp(standoff, [standoff, 6.0 * M_TO_IN].max)
      else
        # una faccia sciolta: la si guarda da più lontano e per meno tempo
        standoff = [standoff, (ex[:mode] == :fly ? 3.0 : 2.0) * M_TO_IN].max
        dwell = [dwell, 0.7].min
      end
      ex[:target] = { id: c[:id], kind: c[:kind], pt: c[:pt].dup, label: c[:label], score: c[:score], open: c[:open],
                      front: c[:front], obj: c[:obj], center: center, size: size, vis: true, vis_t: now,
                      standoff: standoff, dwell: dwell, since: now, seen: now, arrived: nil, dist: nil,
                      prog: nil, stuck: 0, orbit: nil, ai: c[:ai], why: c[:why],
                      zoom: ex[:o]['zoom'] && !c[:open] ? { phase: :aim, t: now, size: size } : nil }
      explore_route_drop(ex)
      ex[:look] = nil
      ex[:looks] = 0
      ex[:rise_to] = nil
      explore_log(ex, ex[:target], 'nuovo')
    end

    # Ingombro nel modello di un oggetto annidato (gli angoli trasformati).
    def self.explore_world_box(opath)
      obj = opath.last
      tr = nil
      opath[0...-1].each { |e| tr = tr ? tr * e.transformation : e.transformation }
      bb = obj.bounds
      out = Geom::BoundingBox.new
      8.times do |i|
        c = bb.corner(i)
        out.add(tr ? c.transform(tr) : c)
      end
      out
    end

    def self.explore_look_around(ex, res, now)
      gw = res[:gw]
      geo = res[:geo]
      l = r = 0.0
      nl = nr = 0.0
      res[:cells].each_with_index do |c, i|
        d = c ? c.d : 1e6
        x = i % gw
        q = geo ? geo[:wx][x] * geo[:wy][i / gw] : 1.0   # metà dello schermo, non della griglia
        if geo ? geo[:ux][x] < 0.5 : x < gw / 2
          l += d * q; nl += q
        else
          r += d * q; nr += q
        end
      end
      # gira verso il lato più profondo (la sinistra dello schermo è +yaw);
      # con la continuità, non dalla parte appena guardata e, guardandosi
      # intorno di nuovo, dalla stessa parte di prima: un giro, non un andirivieni
      dl = nl.zero? ? 0.0 : l / nl
      dr = nr.zero? ? 0.0 : r / nr
      q = ex[:o]['continuity']
      if q > 0.0
        reach = 10.0 * M_TO_IN
        side_f = lambda do |s|
          a = ex[:yaw] + s * EX_LOOK_TURN
          c = { pt: [ex[:x] + Math.cos(a) * reach, ex[:y] + Math.sin(a) * reach, ex[:z]], open: true }
          f = 1.0 / (1.0 + EX_RETURN * q * explore_return_w(ex, c, now))
          lk = ex[:look_last]
          f *= 1.0 + q if lk && lk[1] == s && now - lk[0] < EX_SWEEP_TAU && Math.hypot(ex[:x] - lk[2], ex[:y] - lk[3]) < EX_SWEEP_NEAR
          f
        end
        dl *= side_f.(1.0)
        dr *= side_f.(-1.0)
      end
      side = dl >= dr ? 1.0 : -1.0
      ex[:look_last] = [now, side, ex[:x], ex[:y]]
      ex[:look] = { goal: explore_wrap(ex[:yaw] + side * EX_LOOK_TURN), until: now + EX_LOOK_TIME }
      ex[:looks] = ex[:looks].to_i + 1
      # in volo, guardandosi intorno si sale (fino a poco sopra il modello)
      # e si guarda in basso: da più in alto si vede dentro, e più lontano
      if ex[:mode] == :fly
        top = explore_model_top(ex) + EX_VANTAGE
        ex[:rise_to] = [[ex[:rise_to] || ex[:z], ex[:z]].max + EX_VANTAGE, top].min
      end
      explore_log(ex, nil, 'intorno')
    end

    def self.explore_model_top(ex)
      bb = ex[:model].respond_to?(:bounds) ? ex[:model].bounds : nil
      bb && !bb.empty? ? bb.max.z : ex[:z]
    rescue => fps_err
      log_error(__method__, fps_err)
      ex[:z]
    end

    # Mentre c'è un obiettivo: attenzione che stanca, sosta, pazienza finita,
    # avanzamento (se non si avvicina, è irraggiungibile o è già lì).
    def self.explore_think(ex, now, dt)
      ex[:look] = nil if ex[:look] && now >= ex[:look][:until]
      tgt = ex[:target] or return
      unless tgt[:open]
        explore_bored_add(ex, tgt, dt, now)
        explore_mem_add(ex[:mem], explore_vkey(*tgt[:pt]), EX_ATTEND * dt, now, EX_MEM_TAU)
      end
      if tgt[:arrived]
        return if explore_orbiting?(tgt)        # la sosta comincia finito il giro attorno
        explore_satiate(ex, now, 'raggiunto') if now - tgt[:arrived] >= tgt[:dwell] && !tgt[:photo_hold]
        return
      end
      limit = tgt[:open] ? [ex[:o]['attention'] * 0.5, 8.0].max : ex[:o]['attention']
      if tgt[:ai]
        limit *= EX_PILOT_PATIENCE
        pilot_watch(ex, tgt, now)                # lib/expilot.rb: l'IA sa che non ci si arriva
      end
      return explore_satiate(ex, now, 'stancato') if now - tgt[:since] > limit
      d = tgt[:dist] or return
      pr = (tgt[:prog] ||= [now, d])
      return if now - pr[0] < EX_STUCK_T
      if ex[:trying] && pr[1] - d < EX_STUCK_D
        tgt[:stuck] += 1
        if tgt[:stuck] >= 2
          return explore_arrive(ex, tgt, now) if !tgt[:open] && d < tgt[:standoff] + 1.5 * M_TO_IN
          return explore_satiate(ex, now, 'irraggiungibile')
        end
      else
        tgt[:stuck] = 0
      end
      tgt[:prog] = [now, d]
    end

    def self.explore_arrive(ex, tgt, now)
      return if tgt[:arrived]
      tgt[:arrived] = now
      explore_route_drop(ex)
      explore_orbit_begin(ex, tgt, now)
      pilot_arrived(ex, tgt, now)                # lib/expilot.rb: avviso, commento, foto
    end

    # Fatto (o rinunciato): la memoria lo segna e si cerca subito altro.
    def self.explore_satiate(ex, now, why)
      tgt = ex[:target] or return
      ex[:target] = nil
      explore_route_drop(ex)
      ex[:visited][tgt[:id]] = now
      ex[:kvisited][tgt[:kind]] = now if tgt[:kind]
      explore_front_done(ex, tgt[:front]) if tgt[:front]
      unless tgt[:open]
        amount = { 'raggiunto' => EX_SATIATE, 'irraggiungibile' => EX_SATIATE * 1.5,
                   'bloccato' => EX_SATIATE * 1.5 }[why] || EX_SATIATE * 0.6
        ix, iy, iz = tgt[:pt].map { |v| (v / EX_VOXEL).floor }
        explore_mem_add(ex[:mem], explore_vpack(ix, iy, iz), amount, now, EX_MEM_TAU)
        EX_N6.each { |a, b, c| explore_mem_add(ex[:mem], explore_vpack(ix + a, iy + b, iz + c), amount * 0.5, now, EX_MEM_TAU) }
      end
      ex[:next_scan] = now if ex[:next_scan] > now
      explore_log(ex, tgt, why)
      pilot_done(ex, tgt, why, now) if tgt[:ai]
    end

    def self.explore_skip(ex)
      now = explore_clock
      explore_satiate(ex, now, 'saltato') if ex[:target]
      ex[:next_scan] = now
    end

    # ── Zoom prima di avvicinarsi (zoom nel profilo) ──
    # Fasi: :aim finché lo sguardo non è dritto sull'obiettivo; :in il campo
    # visivo si stringe finché l'obiettivo riempie zoom_fill dell'altezza
    # della vista; :hold fermo zoom_hold s; :out torna com'era; :done si
    # cammina. Intanto non si cambia obiettivo e non si fa un passo.
    def self.explore_zooming?(ex)
      z = ex[:target] && ex[:target][:zoom]
      !z.nil? && z[:phase] != :done
    end

    def self.explore_zoom_tick(ex, now, dt)
      fov0 = ex[:fov0]
      goal = fov0
      tgt = ex[:target]
      z = tgt && tgt[:zoom]
      if z && !ex[:look] && !ex[:escape]
        o = ex[:o]
        case z[:phase]
        when :aim
          if explore_aim_err(ex, tgt[:pt]) < 4.0 * DEG || now - z[:t] > 3.0
            d = [explore_dist_eye(ex, tgt[:pt]), 1.0].max
            seen = 2.0 * Math.atan(z[:size] / 2.0 / d) / DEG      # gradi che occupa adesso
            f = (seen / o['zoom_fill']).clamp(fov0 / o['zoom_max'], fov0)
            if f > fov0 * 0.85
              z[:phase] = :done                    # già grande nella vista: niente zoom
            else
              z[:fov] = f
              z[:phase] = :in
            end
          end
        when :in
          goal = z[:fov]
          if (ex[:fov] - goal).abs < 0.05 * goal
            z[:phase] = :hold
            z[:t] = now
          end
        when :hold
          goal = z[:fov]
          z[:phase] = :out if now - z[:t] >= o['zoom_hold']
        when :out
          z[:phase] = :done if (ex[:fov] - fov0).abs < 0.02 * fov0
        end
      end
      # esponenziale sul logaritmo: da ×1 a ×2 dura quanto da ×2 a ×4
      k = 1.0 - Math.exp(-dt * EX_ZOOM_K)
      ex[:fov] = Math.exp(Math.log(ex[:fov]) + (Math.log(goal) - Math.log(ex[:fov])) * k)
    end

    # Angolo fra lo sguardo e il punto
    def self.explore_aim_err(ex, pt)
      dx = pt[0] - ex[:x]
      dy = pt[1] - ex[:y]
      dz = pt[2] - ex[:z]
      l = Math.sqrt(dx * dx + dy * dy + dz * dz)
      return 0.0 if l < 1e-6
      cp = Math.cos(ex[:pitch])
      dot = (dx * cp * Math.cos(ex[:yaw]) + dy * cp * Math.sin(ex[:yaw]) + dz * Math.sin(ex[:pitch])) / l
      Math.acos(dot.clamp(-1.0, 1.0))
    end

    # Fermato a metà di uno zoom: la camera torna al campo visivo di partenza
    def self.explore_unzoom(ex)
      cam = ex[:view].camera
      cam.fov = ex[:fov0] if ex[:fov0] && cam.perspective? && cam.fov != ex[:fov0]
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    # ── Bloccato ──
    # Ogni EX_STALL_T s: se non si è spostato (e non stava sostando davanti
    # a qualcosa né ingrandendo) è bloccato. Succede dove nessun obiettivo
    # è raggiungibile (un terrazzo, un tetto) o se gli obiettivi si
    # alternano senza che uno vinca: lo sguardo li insegue e i piedi non
    # partono mai. Si cammina per qualche secondo nella direzione libera più
    # lunga; se non ce n'è nessuna e il modo è auto, si vola.
    def self.explore_stall(ex, now)
      tgt = ex[:target]
      if (tgt && tgt[:arrived]) || explore_zooming?(ex) || ex[:escape]
        ex[:anchor] = [now, ex[:x], ex[:y], ex[:z]]
        return
      end
      a = ex[:anchor]
      return if now - a[0] < EX_STALL_T
      moved = Math.sqrt((ex[:x] - a[1])**2 + (ex[:y] - a[2])**2 + (ex[:z] - a[3])**2)
      ex[:anchor] = [now, ex[:x], ex[:y], ex[:z]]
      explore_unstick(ex, now) if moved < EX_STALL_D
    end

    def self.explore_unstick(ex, now)
      ex[:stalls] = ex[:stalls].to_i + 1
      explore_satiate(ex, now, 'bloccato') if ex[:target]
      ex[:look] = nil
      # questo posto stanca: lo spazio aperto qui attorno conta meno
      explore_walked_add(ex, now, 0.0, 40.0)
      if ex[:mode] == :fly
        ex[:rise_to] = [ex[:rise_to] || ex[:z], ex[:z]].max + EX_VANTAGE
        return explore_log(ex, nil, 'bloccato')
      end
      ang = explore_escape_dir(ex, now)
      if ang
        ex[:escape] = { ang: ang, until: now + EX_ESCAPE_T }
        ex[:steer] = nil
        explore_log(ex, nil, 'via di fuga')
      elsif ex[:o]['mode'] == 'auto'
        ex[:mode] = :fly                           # a piedi da qui non si va da nessuna parte
        ex[:vz] = 0.0
        ex[:rise_to] = ex[:z] + EX_VANTAGE
        ex[:no_land] = now + EX_ESCAPE_T           # senza, riatterrerebbe subito dov'è
        explore_log(ex, nil, 'in volo')
      else
        explore_log(ex, nil, 'bloccato')
      end
    end

    # La direzione libera più lunga, a piedi (muri e precipizi), meglio se
    # verso posti non ancora calpestati; nil se non ce n'è.
    def self.explore_escape_dir(ex, now)
      r = ex[:radius_in]
      reach = 4.0 * M_TO_IN
      best = nil
      12.times do |i|
        a = ex[:yaw] + i * PI2 / 12
        ux = Math.cos(a)
        uy = Math.sin(a)
        hit = explore_probe(ex, ux, uy, reach + r, false)
        free = hit ? hit[0] - r : reach
        next if free < 1.0 * M_TO_IN
        next unless explore_floor_ok?(ex, ux, uy, [free, 2.0 * M_TO_IN].min)
        s = free * explore_walk_f(ex, [ex[:x] + ux * free, ex[:y] + uy * free], now, ex[:floor]) * (0.8 + 0.4 * ex[:rng].rand)
        best = [s, a] if best.nil? || s > best[0]
      end
      best && explore_wrap(best[1])
    end

    def self.explore_escape_end(ex, now)
      ex[:escape] = nil
      ex[:steer] = nil
      ex[:next_scan] = now
      ex[:anchor] = [now, ex[:x], ex[:y], ex[:z]]
    end

    # ── Memoria: voxel 3D dello sguardo, celle 2D del calpestio, noia ──
    # Chiave intera di tre indici (20 bit ciascuno, ±390 km a 0,75 m).
    def self.explore_vpack(ix, iy, iz)
      ((ix + 524_288) << 40) | ((iy + 524_288) << 20) | (iz + 524_288)
    end

    def self.explore_vkey(x, y, z)
      explore_vpack((x / EX_VOXEL).floor, (y / EX_VOXEL).floor, (z / EX_VOXEL).floor)
    end

    def self.explore_mem_get(mem, k, now, tau)
      v = mem[k] or return 0.0
      v[0] * Math.exp(-(now - v[1]) / tau)
    end

    def self.explore_mem_add(mem, k, amount, now, tau)
      mem[k] = [explore_mem_get(mem, k, now, tau) + amount, now]
    end

    # Ogni voxel visibile si scolora un poco a ogni analisi: una volta sola,
    # comunque grande sia nella vista (avvicinarsi non deve stancare di più).
    def self.explore_seen(ex, res, now)
      keys = {}
      res[:cells].each { |c| keys[explore_vkey(c.p.x, c.p.y, c.p.z)] = true if c }
      amount = EX_SEEN * (ex[:scan_w] || 1.0)
      keys.each_key { |k| explore_mem_add(ex[:mem], k, amount, now, EX_MEM_TAU) }
    end

    def self.explore_novelty(ex, p, now)
      mem = ex[:mem]
      return 1.0 if mem.empty?
      ix = (p.x / EX_VOXEL).floor
      iy = (p.y / EX_VOXEL).floor
      iz = (p.z / EX_VOXEL).floor
      v = explore_mem_get(mem, explore_vpack(ix, iy, iz), now, EX_MEM_TAU)
      nb = 0.0
      EX_N6.each { |a, b, c| nb += explore_mem_get(mem, explore_vpack(ix + a, iy + b, iz + c), now, EX_MEM_TAU) }
      1.0 / (1.0 + ex[:o]['curiosity'] * (v + 0.35 * nb / 6.0))
    end

    # Il calpestio si ricorda in pianta e in quota (la quota dei piedi a
    # EX_WALK_DZ): il piano di sopra, sulla stessa verticale, è ancora nuovo.
    def self.explore_wkey(x, y, feet)
      explore_vpack((x / EX_WALK_CELL).floor, (y / EX_WALK_CELL).floor, (feet / EX_WALK_DZ).round)
    end

    def self.explore_feet(ex); ex[:floor] || ex[:z] - ex[:eye_h]; end

    def self.explore_walked_add(ex, now, dt, amount = dt)
      explore_mem_add(ex[:walked], explore_wkey(ex[:x], ex[:y], explore_feet(ex)), amount, now, EX_WALK_TAU)
    end

    # pt: un punto visto, che si guarda coi piedi fra 2,2 m sotto e poco
    # sopra di lui; con feet: dove si mettono i piedi, a quella quota.
    def self.explore_walk_f(ex, pt, now, feet = nil)
      lo, hi = feet ? [feet - EX_WALK_DZ, feet + EX_WALK_DZ] : [pt[2] - 2.2 * M_TO_IN, pt[2] + 0.3 * M_TO_IN]
      ix = (pt[0] / EX_WALK_CELL).floor
      iy = (pt[1] / EX_WALK_CELL).floor
      m = 0.0
      ((lo / EX_WALK_DZ).round..(hi / EX_WALK_DZ).round).each do |iz|
        v = explore_mem_get(ex[:walked], explore_vpack(ix, iy, iz), now, EX_WALK_TAU)
        m = v if v > m
      end
      1.0 / (1.0 + EX_WALK_K * ex[:o]['roam'] * m)
    end

    # Noia per obiettivo e, più blanda, per categoria (c = candidato o obiettivo).
    def self.explore_bored_add(ex, c, dt, now)
      explore_mem_add(ex[:bored], c[:id], dt, now, EX_BORE_FADE)
      explore_mem_add(ex[:kbored], c[:kind], dt, now, EX_BORE_FADE) if c[:kind]
    end

    def self.explore_bored_f(ex, c, now)
      id = c[:id]
      tau = ex[:o]['boredom']
      cur = [ex[:o]['curiosity'], 1.0].min       # oltre 1 la curiosità pesa sulla novità, non qui
      k = Math.exp(-explore_mem_get(ex[:bored], id, now, EX_BORE_FADE) / tau)
      v = ex[:visited][id]
      k *= 1.0 - 0.9 * cur * Math.exp(-(now - v) / EX_VISIT_TAU) if v
      kind = c[:kind] or return k
      k *= Math.exp(-explore_mem_get(ex[:kbored], kind, now, EX_BORE_FADE) / (tau * 3.0))
      v = ex[:kvisited][kind]
      k *= 1.0 - (c[:obj] ? EX_KIND_OBJ : EX_KIND_REGION) * cur * Math.exp(-(now - v) / EX_VISIT_TAU) if v
      k
    end

    # ── Continuità dello sguardo ──
    # Metà del campo visivo in orizzontale (fov di SketchUp è di solito l'altezza).
    def self.explore_half_hfov(view)
      cam = view.camera
      t = Math.tan(cam.fov.to_f.clamp(10.0, 120.0) * DEG / 2.0)
      height = cam.respond_to?(:fov_is_height?) ? cam.fov_is_height? : true
      Math.atan(height ? t * view.vpwidth.to_f / [view.vpheight.to_f, 1.0].max : t)
    end

    # La posa dell'analisi appena finita (da dove, verso dove, quanto largo)
    # entra nella scia; le più vecchie escono.
    def self.explore_sweep_note(ex, now)
      pose = ex[:scan_pose] or return
      sw = ex[:sweep]
      # analisi fitte: una posa per passo, se no la scia ricorderebbe pochi secondi
      return if ex[:hz_lim] && sw.any? && now - sw[-1][4] < 0.9 * ex[:o]['step_time']
      sw << [pose[0], pose[1], pose[2], pose[3], now]
      sw.shift while sw.size > EX_SWEEP_N || (sw.any? && now - sw[0][4] > 3.0 * EX_SWEEP_TAU)
    end

    # Quanto costa spostare lo sguardo fin lì: poco accanto a dove si guarda,
    # di più girandosi, e di più ancora tornando su ciò che era già nella
    # retina e da cui ci si è girati. 1 senza continuità.
    def self.explore_shift_f(ex, c, now)
      q = ex[:o]['continuity']
      return 1.0 if q <= 0.0
      q *= EX_SACCADE_GO if c[:open]
      dx = c[:pt][0] - ex[:x]
      dy = c[:pt][1] - ex[:y]
      yc = Math.atan2(dy, dx)
      pc = Math.atan2(c[:pt][2] - ex[:z], Math.hypot(dx, dy))
      cs = Math.cos(ex[:pitch]) * Math.cos(pc) * Math.cos(yc - ex[:yaw]) + Math.sin(ex[:pitch]) * Math.sin(pc)
      a = [Math.acos(cs.clamp(-1.0, 1.0)), EX_SACCADE_CAP].min / EX_SACCADE
      1.0 / (1.0 + q * a * a) / (1.0 + EX_RETURN * q * explore_return_w(ex, c, now))
    end

    # Ci si torna? Fuori dalla metà centrale della vista di adesso (l'ultima
    # posa della scia), e una posa vicina a qui lo aveva nella retina
    # guardandolo da più vicino di adesso: lo sguardo c'era passato accanto
    # e se n'è andato. 0–1, scolorito con l'età della posa.
    def self.explore_return_w(ex, c, now)
      sw = ex[:sweep]
      return 0.0 if sw.size < 2
      px, py = c[:pt]
      last = sw[-1]
      d_now = explore_wrap(Math.atan2(py - last[1], px - last[0]) - last[2]).abs
      return 0.0 if d_now < [EX_RETURN_DEG[0], 0.5 * last[3]].max   # ancora in mezzo alla vista
      w = 0.0
      sw[0...-1].each do |x, y, yaw, half, t|
        next if Math.hypot(x - ex[:x], y - ex[:y]) > EX_SWEEP_NEAR
        d = explore_wrap(Math.atan2(py - y, px - x) - yaw).abs
        next if d > half
        v = explore_ss(EX_RETURN_DEG[0], EX_RETURN_DEG[1], d_now - d) * Math.exp(-(now - t) / EX_SWEEP_TAU)
        w = v if v > w
      end
      w
    end

    # ══════════════════════════════════════════════════════════════
    # Pianta: dove lo sguardo è passato, piano per piano
    #
    # Celle di EX_PLAN_CELL, una pianta per ogni quota dei piedi (EX_PLAN_LV).
    # Ogni raggio della retina, finché passa all'altezza del corpo, segna
    # libere le celle che attraversa fino a poco prima di ciò che colpisce; ciò
    # che colpisce, se rivolto in su, dà la quota della cella (pavimento,
    # gradino, tavolo), se verticale e più alto di un gradino è pieno. Mai
    # viste restano le celle senza segni. Serve a due cose:
    #   frontiere  celle libere al bordo di una zona mai vista (oltre una
    #              porta, dietro un angolo): ci si va apposta, a guardarci dentro
    #   percorsi   per ogni obiettivo un A* sulla pianta prefigura la strada
    #              fino a un punto da cui lo si vede: attorno a muri e mobili,
    #              su per le scale, mai su un tavolo. Dove non si sa si prova
    #              (ottimisti); a ogni analisi il resto del percorso si
    #              ricontrolla sulla pianta nuova, ogni tanto si rifà comunque
    #              (una scorciatoia appena vista), e dove si urta la cella si
    #              segna e si ripianifica
    # ══════════════════════════════════════════════════════════════
    def self.explore_plan_lv(feet); (feet / EX_PLAN_LV).round; end

    # Le piante su cui si segna: quella dei piedi e, vicino al confine, anche
    # la vicina (una rampa o una scala non spezzano la pianta).
    def self.explore_plan_lvs(feet)
      f = feet / EX_PLAN_LV
      lv = f.round
      fr = f - lv
      if fr > 0.25 then [lv, lv + 1]
      elsif fr < -0.25 then [lv, lv - 1]
      else [lv]
      end
    end

    # Cede il controllo alla Fiber della scansione ogni budget s (nil: mai)
    def self.explore_pauser(budget)
      return nil unless budget
      deadline = explore_cpu + budget
      lambda do
        next unless explore_cpu >= deadline
        Fiber.yield
        deadline = explore_cpu + budget
      end
    end

    def self.explore_plan_set(plan, ix, iy, lvs, flag)
      lvs.each do |lv|
        k = explore_vpack(ix, iy, lv)
        plan[k] = (plan[k] || 0) | flag
      end
    end

    # Una colonna della retina guarda quasi sempre nella stessa direzione in
    # pianta: le celle libere le segna il suo raggio che resta più a lungo
    # all'altezza del corpo (gli altri passano dalle stesse); le celle di ciò
    # che si colpisce, ogni raggio. Una faccia rivolta in su (pavimento,
    # gradino, piano di un tavolo, sedile) è libera e dà la quota della cella
    # (la più alta vista): fra due celle si passa solo se la quota sale al
    # più di un gradino (vedi explore_step_ok?). Una faccia verticale è piena
    # se sale più di un gradino sopra la quota della sua cella: un muro sì,
    # l'alzata di un gradino o un cordolo no. Pieni la sua cella (che il
    # raggio non segna libera) e quella appena dietro, che da qui non si
    # vede ma non si attraversa.
    def self.explore_plan_mark(plan, zmap, cells, rays, gw, feet, step_in, budget = nil)
      if plan.size > EX_PLAN_MAX
        plan.clear
        zmap.clear
      end
      pause = explore_pauser(budget)
      lvs = explore_plan_lvs(feet)
      lo = feet + EX_PLAN_BODY[0]
      hi = feet + EX_PLAN_BODY[1]
      cs = EX_PLAN_CELL
      best = Array.new(gw)                       # per colonna: [portata, i, cella colpita]
      walls = []                                 # facce verticali: dopo, quando le quote ci sono
      rays.each_with_index do |(o, _d), i|
        pause&.call if (i & 63).zero?
        c = cells[i] or next
        p = c.p
        hd = Math.hypot(p.x - o.x, p.y - o.y)
        next if hd < 1.0                         # dritto in giù o in su
        hx = (p.x / cs).floor
        hy = (p.y / cs).floor
        sz = (p.z - o.z) / hd
        out = if sz > 1e-9 then (hi - o.z) / sz
              elsif sz < -1e-9 then (lo - o.z) / sz
              else hd
              end
        reach = [hd, out, EX_PLAN_REACH].min
        col = i % gw
        best[col] = [reach, i, hx, hy] if best[col].nil? || reach > best[col][0]
        next if hd > EX_PLAN_REACH || p.z < lo || p.z > hi
        if c.nz > 0.7
          explore_plan_set(plan, hx, hy, lvs, PL_FREE)
          lvs.each do |lv|
            k = explore_vpack(hx, hy, lv)
            zmap[k] = p.z if (z = zmap[k]).nil? || p.z > z
          end
        else
          walls << [p, (p.x - o.x) / hd, (p.y - o.y) / hd, hx, hy]
        end
      end
      lv0 = lvs[0]
      walls.each do |p, ux, uy, hx, hy|
        next unless p.z - (zmap[explore_vpack(hx, hy, lv0)] || feet) > step_in
        explore_plan_set(plan, hx, hy, lvs, PL_SOLID)
        bx = ((p.x + ux * 0.3 * M_TO_IN) / cs).floor
        by = ((p.y + uy * 0.3 * M_TO_IN) / cs).floor
        explore_plan_set(plan, bx, by, lvs, PL_SOLID) unless bx == hx && by == hy
      end
      step = cs * 0.7
      best.each do |b|
        next unless b
        reach, i, hx, hy = b
        o = rays[i][0]
        p = cells[i].p
        hd = Math.hypot(p.x - o.x, p.y - o.y)
        ux = (p.x - o.x) / hd
        uy = (p.y - o.y) / hd
        lx = ly = nil
        s = 0.0
        while s <= reach
          ix = ((o.x + ux * s) / cs).floor
          iy = ((o.y + uy * s) / cs).floor
          unless (ix == lx && iy == ly) || (ix == hx && iy == hy)
            explore_plan_set(plan, ix, iy, lvs, PL_FREE)
            lx = ix
            ly = iy
          end
          s += step
        end
      end
    end

    # Frontiere attorno a (x, y), sulla pianta dei piedi: celle libere con
    # una vicina mai vista e abbastanza mai visto attorno, a gruppi di celle
    # vicine. Per gruppo: la cella centrale, quante, quanto mai visto c'è
    # attorno (0..1), la direzione verso il mai visto, tutte le celle e la
    # quota del pavimento sotto ciascuna (con model; nil se non si trova).
    def self.explore_frontiers(plan, zmap, x, y, feet, budget = nil, model: nil)
      pause = explore_pauser(budget)
      lv = explore_plan_lv(feet)
      cs = EX_PLAN_CELL
      cx = (x / cs).floor
      cy = (y / cs).floor
      r = EX_FRONT_R
      # chiavi di explore_vpack: una cella più in là in x è +KX, in y +KY
      kx = 1 << 40
      ky = 1 << 20
      found = {}
      (-r..r).each do |dy|
        pause&.call
        w = Math.sqrt(r * r - dy * dy).floor
        iy = cy + dy
        k = explore_vpack(cx - w - 1, iy, lv)
        (-w..w).each do |dx|
          k += kx
          f = plan[k] or next
          next if (f & PL_FREE).zero? || (f & (PL_DONE | PL_BUMP)).nonzero?
          next if (z = zmap[k]) && (z > feet + 0.6 * M_TO_IN || z < feet - 1.0 * M_TO_IN)   # sopra un mobile, giù da un bordo
          next if plan.key?(k + kx) && plan.key?(k - kx) && plan.key?(k + ky) && plan.key?(k - ky)
          n = 0; sx = 0; sy = 0
          (-2..2).each do |b|
            (-2..2).each do |a|
              next if plan.key?(k + a * kx + b * ky)
              n += 1; sx += a; sy += b
            end
          end
          found[[cx + dx, iy]] = [n, sx, sy] if n >= EX_FRONT_UNK
        end
      end
      out = []
      seen = {}
      found.each_key do |k0|
        next if seen[k0]
        seen[k0] = true
        stack = [k0]
        group = []
        until stack.empty?
          k = stack.pop
          group << k
          EX_N8.each do |a, b, _|
            q = [k[0] + a, k[1] + b]
            next if seen[q] || !found.key?(q)
            seen[q] = true
            stack << q
          end
        end
        next if group.size < EX_FRONT_MIN
        mx = group.sum { |k| k[0] } / group.size.to_f
        my = group.sum { |k| k[1] } / group.size.to_f
        rep = group.min_by { |k| (k[0] - mx)**2 + (k[1] - my)**2 }
        n = 0; sx = 0.0; sy = 0.0
        group.each do |k|
          v = found[k]
          n += v[0]; sx += v[1]; sy += v[2]
        end
        l = Math.hypot(sx, sy)
        pause&.call
        zs = group.map { |ix, iy| explore_front_ground(model, zmap, ix, iy, lv, feet) }
        out << { ix: rep[0], iy: rep[1], lv: lv, size: group.size, unk: n / (25.0 * group.size),
                 ux: l > 1e-6 ? sx / l : 0.0, uy: l > 1e-6 ? sy / l : 0.0, cells: group, zs: zs,
                 z: zs[group.index(rep)] }
      end
      out
    end

    # Quota del pavimento sotto una cella di frontiera. Di solito la pianta
    # non la sa: la cella l'ha segnata libera un raggio che ci è passato
    # sopra senza toccare terra (ed è questo a farne il bordo del visto). La
    # si cerca con un raggio in giù da sopra la fascia del corpo, saltando
    # ciò che sta più in alto (un solaio); più giù di un precipizio, nil.
    def self.explore_front_ground(model, zmap, ix, iy, lv, feet)
      z = zmap[explore_vpack(ix, iy, lv)]
      return z if z || model.nil?
      hi = feet + EX_PLAN_BODY[1]
      explore_ground(model, (ix + 0.5) * EX_PLAN_CELL, (iy + 0.5) * EX_PLAN_CELL, hi + 0.5 * EX_PLAN_LV, hi,
                     feet + EX_PLAN_BODY[0] - 0.5 * EX_PLAN_LV)
    end

    # Il primo pavimento sotto (x, y) fra lo e hi: un raggio in giù da top
    # che salta ciò che sta sopra hi (un solaio, un architrave); nil se non c'è.
    def self.explore_ground(model, x, y, top, hi, lo)
      o = Geom::Point3d.new(x, y, top)
      down = Geom::Vector3d.new(0, 0, -1)
      4.times do
        res = model.raytest([o, down], true) or return nil
        z = res[0].z
        return z >= lo ? z : nil if z <= hi
        o = Geom::Point3d.new(x, y, z - 0.01 * M_TO_IN)
      end
      nil
    end

    # Una frontiera come candidato: il punto è appena oltre il bordo, all'altezza
    # degli occhi sul suo pavimento; vale di più se è larga, molto mai vista e
    # non troppo lontana.
    def self.explore_front_cand(ex, f)
      cs = EX_PLAN_CELL
      x = (f[:ix] + 0.5) * cs
      y = (f[:iy] + 0.5) * cs
      d = Math.hypot(x - ex[:x], y - ex[:y])
      near = (0.3 + 0.7 * explore_ss(0.5 * M_TO_IN, 2.0 * M_TO_IN, d)) / (1.0 + d / (10.0 * M_TO_IN))
      wide = 0.6 + 0.4 * [f[:size] / 8.0, 1.0].min
      { id: "f#{f[:ix]},#{f[:iy]},#{f[:lv]}", kind: nil,
        pt: [x + f[:ux] * cs, y + f[:uy] * cs, (f[:z] || explore_feet(ex)) + ex[:eye_h]],
        score: EX_FRONT_W * ex[:o]['roam'] * (0.5 + 0.5 * f[:unk]) * wide * near,
        area: 0.0, cell: nil, label: t('explore.frontier'), obj: nil, opath: nil, open: true, front: f }
    end

    # La stessa frontiera di un'analisi fa (si sposta man mano che si scopre)
    def self.explore_front_same?(c, cur)
      return true if c[:id] == cur[:id]
      a = c[:front]
      b = cur[:front]
      a[:lv] == b[:lv] && (a[:ix] - b[:ix])**2 + (a[:iy] - b[:iy])**2 <= 16
    end

    # Fatta (raggiunta, vista o abbandonata): le sue celle e quelle accanto
    # non sono più frontiera (oltre un precipizio o nel vuoto resterebbe per sempre).
    def self.explore_front_done(ex, f)
      plan = ex[:plan]
      f[:cells].each do |ix, iy|
        (-2..2).each do |b|
          (-2..2).each do |a|
            k = explore_vpack(ix + a, iy + b, f[:lv])
            plan[k] |= PL_DONE if plan[k]
          end
        end
      end
    end

    # ── Obiettivo in vista? ──
    # Un raggio da (x, y, z) al punto: si vede se arriva fin lì o se colpisce
    # l'oggetto stesso.
    def self.explore_sees?(x, y, z, pt, obj)
      dx = pt[0] - x
      dy = pt[1] - y
      dz = pt[2] - z
      l = Math.sqrt(dx * dx + dy * dy + dz * dz)
      return true if l < 0.5 * M_TO_IN
      res = ray(x, y, z, dx / l, dy / l, dz / l) or return true
      h = res[0]
      return true if Math.sqrt((h.x - x)**2 + (h.y - y)**2 + (h.z - z)**2) >= l - 0.4 * M_TO_IN
      !obj.nil? && res[1].is_a?(Array) && res[1].include?(obj)
    end

    # Ogni EX_SIGHT_T: si vede ancora da qui?
    def self.explore_sight(ex, tgt, now, _dist)
      return if now < tgt[:vis_t]
      tgt[:vis_t] = now + EX_SIGHT_T
      tgt[:vis] = explore_sees?(ex[:x], ex[:y], ex[:z], tgt[:pt], tgt[:obj])
    end

    # ── Giri: A* sulla pianta ──
    def self.explore_routing?(ex, tgt)
      r = ex[:route] || ex[:route_job]
      !r.nil? && r[:id] == tgt[:id]
    end

    def self.explore_heap_push(h, item)
      h << item
      i = h.size - 1
      while i.positive?
        p = (i - 1) >> 1
        break if h[p][0] <= item[0]
        h[i] = h[p]
        i = p
      end
      h[i] = item
    end

    def self.explore_heap_pop(h)
      top = h[0]
      last = h.pop
      return top if h.empty?
      i = 0
      n = h.size
      loop do
        c = 2 * i + 1
        break if c >= n
        c += 1 if c + 1 < n && h[c + 1][0] < h[c][0]
        break if h[c][0] >= last[0]
        h[i] = h[c]
        i = c
      end
      h[i] = last
      top
    end

    # Da una cella a quota za alla vicina a quota zb (nil: non si sa, si
    # prova): in su al più un gradino (con un po' di margine: in mezzo metro
    # di scala ci stanno due alzate), in giù al più max_drop. Fra due quote
    # note non vicine (gap: quanto c'è in mezzo senza quota) si aggiunge la
    # salita più ripida che il giocatore fa (max_slope_deg): 1,4 m più su a
    # 5 m può essere un pendio, a un passo è un muretto.
    def self.explore_step_ok?(ex, za, zb, gap = 0.0)
      return true unless za && zb
      d = zb - za
      more = gap * (ex[:slope] || 1.0)
      d <= (ex[:step_in] || EX_STEP_MAX * M_TO_IN) + 0.12 * M_TO_IN + more && -d <= (ex[:drop_in] || 0.8 * M_TO_IN) + more
    end

    # Un segmento sulla pianta, a mezze celle, senza la cella di partenza:
    # strict, niente celle con qualcosa di pieno (per accorciare i percorsi);
    # se no solo niente celle piene del tutto o urtate (per vedere se un
    # percorso è ancora buono). Le celle mai viste vanno bene. short: ci si
    # ferma prima della fine (l'obiettivo stesso è pieno). Lungo il segmento
    # le quote note salgono e scendono come fra celle vicine, o come un
    # pendio se sono lontane (z0: la quota da cui si parte, nil se non si sa).
    def self.explore_grid_clear?(ex, lv, x0, y0, x1, y1, strict, short = 0.0, z0 = nil)
      plan = ex[:plan]
      zmap = ex[:plan_z] || {}
      cs = EX_PLAN_CELL
      l = Math.hypot(x1 - x0, y1 - y0)
      n = ((l - short) / (cs * 0.5)).floor
      return true if n <= 0
      dx = (x1 - x0) / l * cs * 0.5
      dy = (y1 - y0) / l * cs * 0.5
      sx = (x0 / cs).floor
      sy = (y0 / cs).floor
      x = x0
      y = y0
      zx = x0                                    # dov'era l'ultima quota nota
      zy = y0
      n.times do
        x += dx
        y += dy
        ix = (x / cs).floor
        iy = (y / cs).floor
        next if ix == sx && iy == sy
        k = explore_vpack(ix, iy, lv)
        f = plan[k] or next
        return false if (f & PL_BUMP).nonzero?
        return false if strict ? (f & PL_SOLID).nonzero? : (f & PL_FREE).zero?
        next unless (z = zmap[k])
        return false unless explore_step_ok?(ex, z0, z, [Math.hypot(x - zx, y - zy) - cs, 0.0].max)
        z0 = z
        zx = x
        zy = y
      end
      true
    end

    def self.explore_cell_z(ex, lv, x, y)
      (ex[:plan_z] || {})[explore_vpack((x / EX_PLAN_CELL).floor, (y / EX_PLAN_CELL).floor, lv)]
    end

    # Dai centri delle celle a pochi punti: da ogni punto si va dritti al più
    # lontano dei successivi (fino a 40 avanti) che si raggiunge senza celle
    # con qualcosa di pieno; dove non si può (una porta, uno spigolo) restano
    # i punti di A*.
    def self.explore_route_smooth(ex, lv, x, y, z, pts)
      out = []
      i = 0
      while i < pts.size
        j = i
        k = i + 1
        lim = [i + 40, pts.size - 1].min
        while k <= lim && explore_grid_clear?(ex, lv, x, y, pts[k][0], pts[k][1], true, 0.0, z)
          j = k
          k += 1
        end
        out << pts[j]
        x, y = pts[j]
        z = explore_cell_z(ex, lv, x, y) || z
        i = j + 1
      end
      out
    end

    # Il percorso fino a una cella entro reach dal punto, sulla pianta del
    # piano dove si è. Libere costano 1; accanto a qualcosa di pieno 2 (si
    # passa un po' discosti da muri e mobili); mai viste 2 (ottimisti: forse
    # si passa); libere ma con qualcosa dentro (le porte, gli spigoli) 4;
    # piene e urtate non si passano, e in diagonale non si tagliano gli
    # spigoli. Una cella d'arrivo va bene se fra lei e il punto la pianta non
    # ha niente di pieno e un raggio lo conferma; dopo EX_ROUTE_LOS celle va
    # bene la prima. Euristica gonfiata di EX_ROUTE_GREED: un percorso di
    # poco più lungo, trovato molto prima. Ritorna i punti già accorciati
    # (explore_route_smooth) o nil.
    def self.explore_route_find(ex, tgt, reach, budget = nil)
      pause = explore_pauser(budget)
      plan = ex[:plan]
      feet = explore_feet(ex)
      lv = explore_plan_lv(feet)
      cs = EX_PLAN_CELL
      sx = (ex[:x] / cs).floor
      sy = (ex[:y] / cs).floor
      gx = tgt[:pt][0]
      gy = tgt[:pt][1]
      tx = (gx / cs).floor
      ty = (gy / cs).floor
      span = [(tx - sx).abs, (ty - sy).abs].max + 20
      return nil if span > EX_ROUTE_SPAN
      rg = reach / cs
      eye = feet + ex[:eye_h]
      kx = 1 << 40                               # chiavi di explore_vpack, come in explore_frontiers
      ky = 1 << 20
      off = 524_288
      zmap = ex[:plan_z] || {}
      cost = {}                                  # costo di una cella (nil: non si passa), una volta sola
      cost_of = ->(k) { cost.key?(k) ? cost[k] : (cost[k] = explore_cell_cost(plan, k)) }
      hk = EX_ROUTE_GREED
      k0 = explore_vpack(sx, sy, lv)
      g = { k0 => 0.0 }
      zc = { k0 => [feet, sx, sy] }              # per nodo: l'ultima quota nota e la sua cella
      came = {}
      shut = {}
      ax = (sx - tx).abs
      ay = (sy - ty).abs
      heap = [[[[ax, ay].max + 0.4142 * [ax, ay].min - rg, 0.0].max * hk, k0, sx, sy]]
      n = 0
      los = 0
      until heap.empty?
        _, k, ix, iy = explore_heap_pop(heap)
        next if shut[k]
        shut[k] = true
        pause&.call if (n & 31).zero?
        if k != k0 && (ix - tx)**2 + (iy - ty)**2 <= rg * rg
          los += 1
          cx = (ix + 0.5) * cs
          cy = (iy + 0.5) * cs
          ok = los > EX_ROUTE_LOS
          if !ok && explore_grid_clear?(ex, lv, cx, cy, gx, gy, false, 0.8 * M_TO_IN)
            pause&.call
            ok = explore_sees?(cx, cy, eye, tgt[:pt], tgt[:obj])
          end
          if ok
            pts = []
            while k
              pts << [((k >> 40) - off + 0.5) * cs, (((k >> 20) & 0xFFFFF) - off + 0.5) * cs]
              k = came[k]
            end
            pts.reverse!
            pts.shift
            return explore_route_smooth(ex, lv, ex[:x], ex[:y], feet, pts)
          end
        end
        return nil if (n += 1) > EX_ROUTE_NODES
        gk = g[k]
        EX_N8.each do |a, b, len|
          nx = ix + a
          ny = iy + b
          next if (nx - sx).abs > span || (ny - sy).abs > span
          nk = k + a * kx + b * ky
          c = cost_of.(nk) or next
          next if a != 0 && b != 0 && !(cost_of.(k + a * kx) && cost_of.(k + b * ky))
          za, zx, zy = zc[k]
          zb = zmap[nk]
          # un gradino sì, un tavolo no; fra quote lontane un pendio (in linea
          # d'aria: girare fra celle senza quota non fa salire di più)
          next unless explore_step_ok?(ex, za, zb, [Math.hypot(nx - zx, ny - zy) - 1.0, 0.0].max * cs)
          ng = gk + len * c
          old = g[nk]
          next if old && old <= ng
          g[nk] = ng
          came[nk] = k
          zc[nk] = zb ? [zb, nx, ny] : zc[k]
          ax = (nx - tx).abs
          ay = (ny - ty).abs
          h = (ax > ay ? ax + 0.4142 * ay : ay + 0.4142 * ax) - rg
          explore_heap_push(heap, [ng + (h > 0.0 ? h * hk : 0.0), nk, nx, ny])
        end
      end
      nil
    end

    # Quanto costa passare da una cella (nil: non si passa); vedi explore_route_find.
    def self.explore_cell_cost(plan, k)
      f = plan[k]
      return 2.0 if f.nil?
      return nil if (f & PL_BUMP).nonzero? || (f & PL_FREE).zero?
      return 4.0 if (f & PL_SOLID).nonzero?
      [1 << 40, -(1 << 40), 1 << 20, -(1 << 20)].any? { |d| (q = plan[k + d]) && (q & PL_SOLID).nonzero? } ? 2.0 : 1.0
    end

    # Quando (ri)pianificare: per un obiettivo nuovo che non è a due passi;
    # se un'analisi ha cambiato la pianta e il percorso ora è sbarrato; se
    # l'obiettivo si è spostato; ogni EX_ROUTE_RENEW s comunque (la pianta
    # cresce: magari c'è una scorciatoia). Nascosto o con la strada sbarrata,
    # il percorso è necessario (need): se non c'è, alla lunga si rinuncia.
    def self.explore_route_want(ex, tgt, now, dist)
      return if ex[:route_job] || now < ex[:route_next] || ex[:mode] != :walk
      rt = ex[:route]
      rt = nil if rt && rt[:id] != tgt[:id]
      if rt
        moved = Math.hypot(rt[:goal][0] - tgt[:pt][0], rt[:goal][1] - tgt[:pt][1]) > 1.0 * M_TO_IN
        why = moved ? 'moved' : (now >= rt[:renew] ? 'renew' : nil)
        unless why
          return if rt[:seq] == ex[:plan_seq]
          rt[:seq] = ex[:plan_seq]
          return if explore_route_clear?(ex, rt)
          ex[:route] = nil                         # sbarrato: senza percorso finché non c'è il nuovo
          why = 'blocked'
        end
      else
        return unless !tgt[:vis] || dist > tgt[:standoff] + EX_ROUTE_NEAR
        why = 'none'
      end
      (ex[:route_why] ||= Hash.new(0))[why] += 1
      explore_route_begin(ex, tgt, now, rt ? rt[:tries] : 0, !tgt[:vis])
    end

    # Il resto del percorso, da dove si è, passa ancora sulla pianta?
    def self.explore_route_clear?(ex, rt)
      lv = explore_plan_lv(explore_feet(ex))
      x = ex[:x]
      y = ex[:y]
      z = explore_feet(ex)
      rt[:pts][rt[:i]..].all? do |px, py|
        ok = explore_grid_clear?(ex, lv, x, y, px, py, false, 0.0, z)
        x = px
        y = py
        z = explore_cell_z(ex, lv, x, y) || z
        ok
      end
    end

    # Comincia a cercare un percorso verso l'obiettivo. La ricerca va a
    # fette come l'analisi (explore_route_tick): un obiettivo irraggiungibile
    # la fa lunga, e su un modello pesante ogni raggio verso l'obiettivo
    # costa. Intanto si segue il percorso di prima, se c'è.
    def self.explore_route_begin(ex, tgt, now, tries = 0, need = false)
      ex[:route_next] = now + EX_ROUTE_AGAIN
      return false unless ex[:mode] == :walk
      reach = tgt[:front] ? 1.0 * M_TO_IN : tgt[:standoff] + 0.5 * M_TO_IN
      budget = ex[:slice] / 1000.0
      job = { id: tgt[:id], tries: tries, need: need }
      x = ex[:x]
      y = ex[:y]
      z = explore_feet(ex)
      job[:fiber] = Fiber.new do
        pts = explore_route_find(ex, tgt, reach, budget)
        job[:prof] = explore_route_profile(ex, x, y, z, pts, budget) if pts && !pts.empty? && ex[:model]
        pts
      end
      ex[:route_job] = job
      true
    end

    # Il percorso sul terreno, per disegnarlo: ogni tratto (da dove si parte,
    # o dal punto prima, a pts[j]) a passi di un quarto di metro, con la quota
    # del pavimento sotto. Dove a metà passo la quota non sta in mezzo è un
    # gradino o un bordo: se ne cerca lo spigolo e lo si scavalca (in su si
    # sale prima, in giù si scende dopo), così la linea non taglia i solidi.
    # Per tratto: [t lungo il tratto (0..1), x, y, z].
    def self.explore_route_profile(ex, x, y, z, pts, budget = nil)
      pause = explore_pauser(budget)
      model = ex[:model]
      ground = lambda do |px, py, zp|
        explore_ground(model, px, py, zp + EX_PLAN_BODY[1], zp + 1.0 * M_TO_IN, zp - 0.5 * EX_PLAN_LV) || zp
      end
      ax = x
      ay = y
      za = z
      segs = pts.map do |bx, by|
        at = ->(t) { [ax + (bx - ax) * t, ay + (by - ay) * t] }
        n = [(Math.hypot(bx - ax, by - ay) / (0.5 * EX_PLAN_CELL)).ceil, 1].max
        seg = []
        n.times do |k|
          pause&.call
          t0 = k.to_f / n
          t1 = (k + 1).to_f / n
          z1 = ground.(*at.(t1), za)
          if (z1 - za).abs > 0.04 * M_TO_IN && ((zm = ground.(*at.((t0 + t1) / 2), za)) - (za + z1) / 2).abs > 0.02 * M_TO_IN
            lo = t0
            hi = t1
            if (zm - za).abs < (zm - z1).abs then lo = (t0 + t1) / 2 else hi = (t0 + t1) / 2 end
            3.times do
              tm = (lo + hi) / 2
              zm = ground.(*at.(tm), za)
              if (zm - za).abs < (zm - z1).abs then lo = tm else hi = tm end
            end
            te = z1 > za ? lo : hi
            seg << [te, *at.(te), za] << [te, *at.(te), z1]
          end
          seg << [t1, *at.(t1), z1]
          za = z1
        end
        ax = bx
        ay = by
        seg
      end
      { start: [x, y], segs: segs }
    end

    # Un fotogramma di ricerca; trovato, il percorso nuovo prende il posto
    # del vecchio. Non trovato: si tiene il vecchio, o si va dritti; se era
    # necessario si riprova più tardi, e alla seconda volta (o dopo un urto)
    # si rinuncia.
    def self.explore_route_tick(ex, tgt, now)
      job = ex[:route_job]
      t0 = explore_cpu
      pts = job[:fiber].resume
      ex[:fr_slice] += (explore_cpu - t0) * 1000.0
      return if job[:fiber].alive?
      ex[:route_job] = nil
      if pts.nil? || pts.empty?
        ex[:route_next] = now + 3.0
        return unless job[:need]
        tgt[:nofind] = tgt[:nofind].to_i + 1
        explore_satiate(ex, now, 'irraggiungibile') if tgt[:nofind] >= 2 || job[:tries].positive?
        return
      end
      old = ex[:route]
      rest = Array.new(pts.size, 0.0)
      (pts.size - 2).downto(0) { |i| rest[i] = rest[i + 1] + Math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) }
      ex[:route] = { id: tgt[:id], pts: pts, rest: rest, i: 0, tries: job[:tries], goal: tgt[:pt][0, 2],
                     seq: ex[:plan_seq], renew: now + EX_ROUTE_RENEW, prof: job[:prof] }
      ex[:steer] = nil
      if tgt[:plans].to_i.positive?
        ex[:replans] += 1                        # un altro percorso per lo stesso obiettivo
      else
        ex[:routes] += 1
      end
      tgt[:plans] = tgt[:plans].to_i + 1
      unless old && old[:id] == tgt[:id]
        tgt[:prog] = nil
        tgt[:stuck] = 0
      end
      why = job[:need] ? 'aggira' : 'percorso'
      logged = (tgt[:logged] ||= {})
      explore_log(ex, tgt, why) unless logged[why]
      logged[why] = true
    rescue => fps_err
      log_error(__method__, fps_err)
      ex[:route_job] = nil
      ex[:route_next] = now + 3.0
    end

    def self.explore_route_drop(ex)
      ex[:route] = nil
      ex[:route_job] = nil
    end

    # Un passo lungo il percorso: [direzione, velocità]. Se un punto è
    # sbarrato la cella si segna urtata e si ripianifica (l'ostacolo è
    # l'obiettivo stesso: arrivati). Se il percorso gira largo attorno a un
    # ostacolo basso, oltre il quale c'è dove atterrare, si salta.
    def self.explore_route_walk(ex, tgt, rt, now, dist)
      pts = rt[:pts]
      i = rt[:i]
      i += 1 while i < pts.size - 1 && Math.hypot(pts[i][0] - ex[:x], pts[i][1] - ex[:y]) < 0.6 * M_TO_IN
      rt[:i] = i
      p = pts[i]
      d = Math.hypot(p[0] - ex[:x], p[1] - ex[:y])
      tgt[:dist] = d + rt[:rest][i]              # l'avanzamento si misura lungo il percorso
      if i == pts.size - 1 && d < 0.5 * M_TO_IN
        # in fondo: di qui l'obiettivo si vede, l'ultimo tratto è dritto
        ex[:route] = nil
        ex[:route_next] = now + 2.0
        tgt[:prog] = nil
        return [nil, 0.0]
      end
      head = Math.atan2(p[1] - ex[:y], p[0] - ex[:x])
      ang = explore_steer(ex, head, now)
      direct = Math.atan2(tgt[:pt][1] - ex[:y], tgt[:pt][0] - ex[:x])
      if ex[:o]['jump'] && now >= ex[:jump_next] && dist > tgt[:standoff] + 1.0 * M_TO_IN &&
         explore_wrap((ang || head) - direct).abs >= EX_JUMP_DETOUR && explore_wrap(direct - ex[:yaw]).abs < 60.0 * DEG
        j = explore_jump_plan(ex, direct, dist, now)
        if j
          explore_route_drop(ex)
          explore_jump_begin(ex, j, now)
          return [nil, 0.0]
        end
        ex[:jump_next] = now + EX_JUMP_RETRY
      end
      if ang.nil? || explore_wrap(ang - head).abs > 80.0 * DEG
        if (!tgt[:open] || tgt[:front]) && dist < tgt[:standoff] + 1.0 * M_TO_IN
          explore_arrive(ex, tgt, now)           # l'ostacolo è lui: più vicino di così non si va
          return [nil, 0.0]
        end
        return [nil, 0.0] if now < ex[:route_next]
        explore_plan_bump(ex, head)
        ex[:route] = nil
        (ex[:route_why] ||= Hash.new(0))['bump'] += 1
        if rt[:tries] < EX_ROUTE_TRIES
          explore_route_begin(ex, tgt, now, rt[:tries] + 1, true)
        else
          explore_satiate(ex, now, 'irraggiungibile')
        end
        return [nil, 0.0]
      end
      ex[:trying] = true
      # lo sguardo può stare sull'obiettivo mentre il percorso gira: di lato si va più piano
      e = explore_wrap(ang - ex[:yaw]).abs
      face = e < 45.0 * DEG ? 1.0 : (e < 100.0 * DEG ? 0.75 : 0.5)
      slow = 0.35 + 0.65 * explore_ss(tgt[:standoff], tgt[:standoff] + 1.5 * M_TO_IN, dist)
      [ang, ex[:speed] * face * slow]
    end

    # Dove guardare camminando sul percorso: avanti, se l'obiettivo è
    # nascosto o il percorso gira lontano da lui (nil: l'obiettivo).
    def self.explore_route_look(ex, tgt)
      rt = ex[:route]
      return nil unless rt && rt[:id] == tgt[:id]
      p = rt[:pts][rt[:i]]
      return p unless tgt[:vis]
      a = Math.atan2(p[1] - ex[:y], p[0] - ex[:x])
      b = Math.atan2(tgt[:pt][1] - ex[:y], tgt[:pt][0] - ex[:x])
      explore_wrap(a - b).abs > EX_ROUTE_LOOK ? p : nil
    end

    # Urtato andando verso head: le celle di ciò che si è urtato, un metro
    # per parte lungo la sua faccia (o la cella davanti, se è il pavimento a
    # mancare), non si passano più.
    def self.explore_plan_bump(ex, head)
      ux = Math.cos(head)
      uy = Math.sin(head)
      cs = EX_PLAN_CELL
      hit = explore_probe(ex, ux, uy, ex[:radius_in] + 1.0 * M_TO_IN)
      pts = if hit
              q = hit[1][0]
              n = hit_normal(hit[1], ux, uy, 0)
              tx, ty = n && Math.hypot(n[0], n[1]) > 0.3 ? [-n[1], n[0]] : [-uy, ux]
              tl = Math.hypot(tx, ty)
              (-2..2).map { |k| [q.x + ux * 0.05 * M_TO_IN + tx / tl * k * cs, q.y + uy * 0.05 * M_TO_IN + ty / tl * k * cs] }
            else
              [[ex[:x] + ux * 0.6 * M_TO_IN, ex[:y] + uy * 0.6 * M_TO_IN]]
            end
      lv = [explore_plan_lv(explore_feet(ex))]
      me = [(ex[:x] / cs).floor, (ex[:y] / cs).floor]
      pts.each do |x, y|
        c = [(x / cs).floor, (y / cs).floor]
        explore_plan_set(ex[:plan], c[0], c[1], lv, PL_BUMP) unless c == me   # mai la cella dove si è
      end
    end

    # ── Giro attorno a un oggetto raggiunto (orbit nel profilo, in gradi) ──
    # Sul cerchio attorno al centro dell'oggetto, alla distanza a cui ci si è
    # fermati, guardandolo; dal lato più libero. Se la strada si chiude si
    # torna indietro (una volta); finito il giro comincia la sosta.
    def self.explore_orbiting?(tgt); !tgt.nil? && !tgt[:orbit].nil? && !tgt[:orbit][:end]; end

    def self.explore_orbit_begin(ex, tgt, now)
      deg = (tgt[:orbit_deg] || ex[:o]['orbit']).to_f   # una meta dell'IA può dire di quanto
      c = tgt[:center]
      return unless deg > 0.0 && c && ex[:mode] == :walk && !tgt[:open] && tgt[:size] <= EX_ORBIT_MAX
      r = Math.hypot(ex[:x] - c[0], ex[:y] - c[1])
      return if r < 0.3 * M_TO_IN
      a = Math.atan2(ex[:y] - c[1], ex[:x] - c[0])
      dir = [1.0, -1.0].max_by do |s|
        h = a + s * Math::PI / 2.0
        hit = explore_probe(ex, Math.cos(h), Math.sin(h), 2.0 * M_TO_IN + ex[:radius_in])
        (hit ? hit[0] : 3.0 * M_TO_IN) + ex[:rng].rand
      end
      goal = deg * DEG
      time = goal * r * IN_TO_M / (ex[:speed] * EX_ORBIT_SPEED)
      tgt[:orbit] = { cx: c[0], cy: c[1], r: r, a: a, dir: dir, done: 0.0, goal: goal, flips: 0,
                      until: now + time * 2.0 + 4.0, end: false }
      ex[:orbits] += 1
      ex[:steer] = nil
      explore_log(ex, tgt, 'gira attorno')
    end

    # Direzione del passo sul cerchio, o nil (fermo questo fotogramma). Si
    # gira solo finché lo si vede: ogni EX_SIGHT_T si guarda dal punto del
    # cerchio un po' più avanti; se di lì lo nasconde una parete (o altro),
    # come per un ostacolo sul cerchio si torna indietro, la seconda volta
    # si smette.
    def self.explore_orbit_step(ex, tgt, now)
      ob = tgt[:orbit]
      a = Math.atan2(ex[:y] - ob[:cy], ex[:x] - ob[:cx])
      ob[:done] += explore_wrap(a - ob[:a]) * ob[:dir]
      ob[:a] = a
      return explore_orbit_end(ex, tgt, now) if ob[:done] >= ob[:goal] || now > ob[:until]
      if now >= ob[:sight_t].to_f
        ob[:sight_t] = now + EX_SIGHT_T
        la = a + ob[:dir] * EX_ORBIT_AHEAD / ob[:r]
        unless explore_sees?(ob[:cx] + Math.cos(la) * ob[:r], ob[:cy] + Math.sin(la) * ob[:r], ex[:z], tgt[:pt], tgt[:obj])
          ob[:hidden] = ob[:hidden].to_i + 1
          return explore_orbit_flip(ex, tgt, now)
        end
      end
      na = a + ob[:dir] * 0.8 * M_TO_IN / ob[:r]
      px = ob[:cx] + Math.cos(na) * ob[:r]
      py = ob[:cy] + Math.sin(na) * ob[:r]
      head = Math.atan2(py - ex[:y], px - ex[:x])
      ang = explore_steer(ex, head, now)
      return ang if ang && explore_wrap(ang - head).abs <= 60.0 * DEG
      explore_orbit_flip(ex, tgt, now)
    end

    # Di qui non si va (ostacolo, o l'oggetto sparirebbe): indietro, o basta
    def self.explore_orbit_flip(ex, tgt, now)
      ob = tgt[:orbit]
      ob[:flips] += 1
      return explore_orbit_end(ex, tgt, now) if ob[:flips] > 1
      ob[:dir] = -ob[:dir]
      ob[:sight_t] = 0.0                         # l'altra parte si controlla subito
      ex[:steer] = nil
      nil
    end

    def self.explore_orbit_end(ex, tgt, now)
      tgt[:orbit][:end] = true
      tgt[:arrived] = now                        # ora la sosta
      ex[:steer] = nil
      nil
    end

    # ══════════════════════════════════════════════════════════════
    # Il passo: a piedi
    # ══════════════════════════════════════════════════════════════
    def self.explore_walk(ex, now, dt)
      tgt = ex[:target]
      ang = nil
      want = 0.0
      ex[:trying] = false
      if (esc = ex[:escape])
        ang = explore_steer(ex, esc[:ang], now)
        e = ang ? explore_wrap(ang - ex[:yaw]).abs : Math::PI
        want = ex[:speed] * (e < 45.0 * DEG ? 1.0 : (e > 110.0 * DEG ? 0.0 : (110.0 * DEG - e) / (65.0 * DEG)))
        explore_escape_end(ex, now) if ang.nil? || now >= esc[:until]
      elsif tgt && !ex[:look] && explore_orbiting?(tgt)
        ang = explore_orbit_step(ex, tgt, now)
        want = ex[:speed] * EX_ORBIT_SPEED if ang
      elsif tgt && !ex[:look] && !tgt[:arrived] && !explore_zooming?(ex)
        dx = tgt[:pt][0] - ex[:x]
        dy = tgt[:pt][1] - ex[:y]
        dist = Math.hypot(dx, dy)
        tgt[:dist] = dist
        if dist <= tgt[:standoff]
          explore_arrive(ex, tgt, now)
        else
          head = Math.atan2(dy, dx)
          explore_sight(ex, tgt, now, dist)
          explore_route_tick(ex, tgt, now) if ex[:route_job]
          explore_route_want(ex, tgt, now, dist) if ex[:target]
          rt = ex[:route]
          if !ex[:target]
            ang = nil                              # si è rinunciato
          elsif rt && rt[:id] == tgt[:id]
            # il percorso sulla pianta di ciò che si è visto
            ang, want = explore_route_walk(ex, tgt, rt, now, dist)
            return if ex[:jump]
          else
            # senza percorso (a due passi, o lo si sta cercando, o non c'è): dritti
            ex[:trying] = explore_wrap(head - ex[:yaw]).abs < 60.0 * DEG
            ang = explore_steer(ex, head, now)
            blocked = ang.nil? || explore_wrap(ang - head).abs >= EX_JUMP_DETOUR
            # strada sbarrata e nessun giro corto attorno: un salto, se c'è dove atterrare
            if ex[:o]['jump'] && blocked && ex[:trying] && now >= ex[:jump_next] && dist > tgt[:standoff] + 1.0 * M_TO_IN
              j = explore_jump_plan(ex, head, dist, now)
              return explore_jump_begin(ex, j, now) if j
              ex[:jump_next] = now + EX_JUMP_RETRY
            end
            if ang.nil? && (!tgt[:open] || tgt[:front]) && dist < tgt[:standoff] + 1.0 * M_TO_IN
              explore_arrive(ex, tgt, now)         # l'ostacolo è lui: più vicino di così non si va
            elsif blocked && !ex[:route_job] && now >= ex[:route_next] && explore_route_begin(ex, tgt, now, 0, true)
              ang = nil                            # sbarrato: si cerca il giro
            elsif ang
              # si cammina verso dove si guarda: prima ci si gira, poi si va
              e = explore_wrap(ang - ex[:yaw]).abs
              face = if e < 45.0 * DEG then 1.0
                     elsif e > 110.0 * DEG then 0.0
                     else (110.0 * DEG - e) / (65.0 * DEG)
                     end
              slow = 0.35 + 0.65 * explore_ss(tgt[:standoff], tgt[:standoff] + 1.5 * M_TO_IN, dist)
              want = ex[:speed] * face * slow
            end
          end
        end
      end
      ex[:vx] = approach(ex[:vx], ang ? Math.cos(ang) * want : 0.0, EX_ACCEL, dt)
      ex[:vy] = approach(ex[:vy], ang ? Math.sin(ang) * want : 0.0, EX_ACCEL, dt)
      mdx = ex[:vx] * dt * M_TO_IN
      mdy = ex[:vy] * dt * M_TO_IN
      if mdx.abs + mdy.abs > 1e-4
        explore_slide(ex, mdx, mdy)
        explore_separate(ex)
      end
      # l'occhio insegue il pavimento: gradini e rampe senza scatti
      ex[:z] += (ex[:floor] + ex[:eye_h] - ex[:z]) * (1.0 - Math.exp(-dt * 10.0))
      explore_walked_add(ex, now, dt)
    end

    # ── Salto ─────────────────────────────────────────────────────
    # Con la forza del salto e la gravità del giocatore i piedi salgono al
    # più v²/2g (4,6 m/s e 9,8 m/s²: 1,08 m); si salta solo ciò che resta
    # sotto EX_JUMP_SAFE di quella quota. Si cerca dove atterrare oltre
    # l'ostacolo, sulla linea verso l'obiettivo: un piano quasi orizzontale
    # più vicino all'obiettivo, al più max_drop sotto i piedi, con lo spazio
    # per la testa; sopra, niente soffitto; lungo l'arco, niente da urtare.
    def self.explore_jump_plan(ex, head, dist, now)
      v0 = ex[:jump_v]
      g = ex[:grav]
      return nil unless v0 > 0.5 && ex[:floor]
      rise = v0 * v0 / (2.0 * g) * M_TO_IN
      ux = Math.cos(head)
      uy = Math.sin(head)
      hit = explore_probe(ex, ux, uy, ex[:radius_in] + EX_JUMP_NEAR) or return nil
      feet = ex[:floor]
      top = feet + rise * EX_JUMP_SAFE
      up = ray(ex[:x], ex[:y], ex[:z], 0, 0, 1)
      return nil if up && up[0].z - ex[:z] < rise + 0.1 * M_TO_IN        # un soffitto
      peak = feet
      d = hit[0]
      reach = [EX_JUMP_FAR, dist - 0.3 * M_TO_IN].min
      while (d += EX_JUMP_STEP) <= reach
        x = ex[:x] + ux * d
        y = ex[:y] + uy * d
        res = ray(x, y, feet + rise + 0.05 * M_TO_IN, 0, 0, -1)
        z = res && res[0].z
        peak = z if z && z > peak
        return nil if peak > top                                         # troppo alto
        next unless z && d >= hit[0] + ex[:radius_in] && feet - z <= ex[:drop_in] && z - feet <= rise * EX_JUMP_SAFE
        n = hit_normal(res, 0, 0, -1)
        next if n && n[2].abs < 0.8                                      # in pendenza: non ci si ferma
        next unless explore_jump_flat?(ex, x, y, z)                      # un sedile, un tavolo: no
        # l'arco: libero sopra il punto più alto, e la testa all'arrivo
        over = peak + 0.1 * M_TO_IN
        blk = ray(ex[:x], ex[:y], over, ux, uy, 0)
        next if blk && Math.hypot(blk[0].x - ex[:x], blk[0].y - ex[:y]) < d + ex[:radius_in]
        blk = ray(x - ux * ex[:radius_in], y - uy * ex[:radius_in], z + ex[:eye_h] - 0.1 * M_TO_IN, ux, uy, 0)
        next if blk && Math.hypot(blk[0].x - x, blk[0].y - y) < ex[:radius_in] * 0.5
        dz = (z - feet) * IN_TO_M
        disc = v0 * v0 - 2.0 * g * dz
        next if disc <= 0
        dur = (v0 + Math.sqrt(disc)) / g
        next if d * IN_TO_M / dur > EX_JUMP_VH
        return { t0: now, dur: dur, x0: ex[:x], y0: ex[:y], z0: feet, x1: x, y1: y, z1: z, v0: v0, g: g }
      end
      nil
    end

    # Dove si atterra c'è un piano vero: tutt'intorno, a EX_JUMP_PAD, lo
    # stesso livello entro un gradino (non il sedile di un divano, non un
    # tavolo); e il corpo ci sta, lontano dal muretto appena scavalcato
    # (raggi orizzontali tutt'attorno, alle altezze di explore_separate).
    def self.explore_jump_flat?(ex, x, y, z)
      EX_RING.all? do |cx, cy|
        res = ray(x + cx * EX_JUMP_PAD, y + cy * EX_JUMP_PAD, z + 1.2 * M_TO_IN, 0, 0, -1)
        next false unless res && (res[0].z - z).abs <= ex[:step_in] + 1.0
        [ex[:step_in] + 2.0, 0.72 * M_TO_IN].none? do |h|
          blk = ray(x, y, z + h, cx, cy, 0)
          blk && Math.hypot(blk[0].x - x, blk[0].y - y) < ex[:radius_in] * 1.2
        end
      end
    end

    def self.explore_jump_begin(ex, j, now)
      ex[:jump] = j
      ex[:jumps] += 1
      ex[:steer] = nil
      ex[:vx] = ex[:vy] = 0.0
      explore_log(ex, ex[:target], 'salto')
      explore_jump_tick(ex, now)
    end

    # Lungo l'arco: in orizzontale a velocità costante, in verticale la parabola
    def self.explore_jump_tick(ex, now)
      j = ex[:jump]
      t = (now - j[:t0]).clamp(0.0, j[:dur])
      s = t / j[:dur]
      ex[:x] = j[:x0] + (j[:x1] - j[:x0]) * s
      ex[:y] = j[:y0] + (j[:y1] - j[:y0]) * s
      feet = j[:z0] + (j[:v0] * t - 0.5 * j[:g] * t * t) * M_TO_IN
      ex[:z] = feet + ex[:eye_h]
      return if s < 1.0
      ex[:jump] = nil
      ex[:floor] = j[:z1]
      ex[:z] = j[:z1] + ex[:eye_h]
      ex[:jump_next] = now + EX_JUMP_RETRY
      ex[:anchor] = [now, ex[:x], ex[:y], ex[:z]]
    end

    # Sonde orizzontali a tre altezze dai piedi: appena sopra i gradini,
    # torso, testa. Ritorna [distanza, risultato] dell'ostacolo più vicino
    # entro reach (pollici), nil se libero.
    # low: false salta la sonda bassa (la direzione di marcia controlla i
    # gradini col profilo del pavimento, vedi explore_steer).
    def self.explore_probe(ex, ux, uy, reach, low = true)
      feet = ex[:floor] || ex[:z] - ex[:eye_h]
      best = nil
      hs = [0.72 * M_TO_IN, ex[:eye_h] - 0.15 * M_TO_IN]    # piano dei tavoli, testa
      hs.unshift(ex[:step_in] + 2.0) if low
      hs.each do |h|
        res = ray(ex[:x], ex[:y], feet + h, ux, uy, 0)
        next unless res
        d = Math.hypot(res[0].x - ex[:x], res[0].y - ex[:y])
        next if d >= reach
        best = [d, res] if best.nil? || d < best[0]
      end
      best
    end

    # Il corpo è un cerchio, non un raggio: passando accanto a uno spigolo
    # la sonda in avanti non lo vede. Otto raggi attorno, un fotogramma
    # all'altezza di sedili e divani, quello dopo all'altezza dei tavoli: se
    # qualcosa è più vicino del raggio del corpo, ci si scosta.
    EX_RING = Array.new(8) { |k| [Math.cos(k * Math::PI / 4), Math.sin(k * Math::PI / 4)] }.freeze

    def self.explore_separate(ex)
      r = ex[:radius_in]
      ex[:ring] = !ex[:ring]
      z = ex[:floor] + (ex[:ring] ? ex[:step_in] + 2.0 : 0.72 * M_TO_IN)
      worst = nil
      EX_RING.each do |cx, cy|
        res = ray(ex[:x], ex[:y], z, cx, cy, 0) or next
        d = Math.hypot(res[0].x - ex[:x], res[0].y - ex[:y])
        worst = [r - d, cx, cy] if d < r && (worst.nil? || r - d > worst[0])
      end
      return unless worst
      push, cx, cy = worst
      nx = ex[:x] - cx * push
      ny = ex[:y] - cy * push
      res = ray(nx, ny, ex[:floor] + ex[:step_in] + 2.0, 0, 0, -1)
      return unless res && (res[0].z - ex[:floor]).abs <= ex[:step_in] + 2.0
      ex[:x] = nx
      ex[:y] = ny
    end

    # Il pavimento davanti, in quattro punti fino a dist: ogni salita al più
    # un gradino, ogni discesa al più max_drop. I raggi scendono da 1,2 m
    # sopra i piedi, così vedono anche il piano di un tavolo basso.
    def self.explore_floor_ok?(ex, ux, uy, dist)
      prev = ex[:floor]
      start = ex[:floor] + 1.2 * M_TO_IN
      (1..4).all? do |k|
        f = dist * k / 4.0
        res = ray(ex[:x] + ux * f, ex[:y] + uy * f, start, 0, 0, -1)
        next false unless res
        z = res[0].z
        good = z - prev <= ex[:step_in] + 1.0 && prev - z <= ex[:drop_in]
        prev = z
        good
      end
    end

    # Spostamento con scivolamento lungo i muri (come move_with_slide, senza
    # spinte): la componente che entra nel muro si toglie.
    def self.explore_slide(ex, dx, dy)
      r = ex[:radius_in]
      3.times do
        len = Math.hypot(dx, dy)
        return if len < 1e-4
        ux = dx / len
        uy = dy / len
        hit = explore_probe(ex, ux, uy, r + len)
        return explore_floor_move(ex, ex[:x] + dx, ex[:y] + dy) unless hit
        n = hit_normal(hit[1], ux, uy, 0)
        nx, ny = n ? [n[0], n[1]] : [-ux, -uy]
        nl = Math.hypot(nx, ny)
        if nl < 1e-6
          nx = -ux; ny = -uy
        else
          nx /= nl; ny /= nl
        end
        dot = dx * nx + dy * ny
        return if dot >= 0
        dx -= nx * dot
        dy -= ny * dot
        vdot = ex[:vx] * nx + ex[:vy] * ny
        if vdot < 0
          ex[:vx] -= nx * vdot
          ex[:vy] -= ny * vdot
        end
      end
    end

    # Pavimento nel punto d'arrivo: si sale fino a un gradino, si scende fino
    # a max_drop; oltre (o nel vuoto) non si va.
    def self.explore_floor_move(ex, nx, ny)
      feet = ex[:floor]
      res = ray(nx, ny, feet + ex[:step_in] + 2.0, 0, 0, -1)
      if res && res[0].z >= feet - ex[:drop_in]
        ex[:x] = nx
        ex[:y] = ny
        ex[:floor] = res[0].z
        return true
      end
      ex[:vx] = ex[:vy] = 0.0
      false
    end

    # Direzione di marcia: verso l'obiettivo se libera, altrimenti la
    # deviazione più piccola che lo è (muri e precipizi), tenendo il lato
    # scelto l'ultima volta per non oscillare. Ricalcolata ogni 0,12 s.
    def self.explore_steer(ex, head, now)
      st = ex[:steer]
      return st[1] if st && now < st[0] && explore_wrap(st[2] - head).abs < 10.0 * DEG
      look = [0.75, ex[:speed] * 0.7].max * M_TO_IN
      pref = ex[:steer_side] || 1.0
      EX_STEER.each do |a|
        ang = head + a * DEG * pref
        ux = Math.cos(ang)
        uy = Math.sin(ang)
        next if explore_probe(ex, ux, uy, look + ex[:radius_in], false)
        next unless explore_floor_ok?(ex, ux, uy, look)
        ex[:steer_side] = a.negative? ? -pref : pref unless a.zero?
        ex[:steer] = [now + 0.12, ang, head]
        return ang
      end
      ex[:steer] = [now + 0.12, nil, head]
      nil
    end

    # ══════════════════════════════════════════════════════════════
    # Il passo: in volo
    # ══════════════════════════════════════════════════════════════
    def self.explore_fly(ex, now, dt)
      tgt = ex[:target]
      ux = uy = uz = 0.0
      want = 0.0
      ex[:trying] = false
      if tgt && !ex[:look] && !tgt[:arrived] && !explore_zooming?(ex)
        dx = tgt[:pt][0] - ex[:x]
        dy = tgt[:pt][1] - ex[:y]
        dz = tgt[:pt][2] - ex[:z]
        dist = Math.sqrt(dx * dx + dy * dy + dz * dz)
        tgt[:dist] = dist
        if dist <= tgt[:standoff]
          explore_arrive(ex, tgt, now)
        else
          ux = dx / dist; uy = dy / dist; uz = dz / dist
          cp = Math.cos(ex[:pitch])
          dot = ux * cp * Math.cos(ex[:yaw]) + uy * cp * Math.sin(ex[:yaw]) + uz * Math.sin(ex[:pitch])
          ex[:trying] = dot > 0.5
          face = dot > 0.7 ? 1.0 : (dot < 0.0 ? 0.0 : dot / 0.7)
          far = (dist * IN_TO_M / 10.0).clamp(0.5, 4.0)       # lontano si vola più svelti
          slow = 0.3 + 0.7 * explore_ss(tgt[:standoff], tgt[:standoff] + 3.0 * M_TO_IN, dist)
          want = ex[:speed] * EX_FLY_MUL * far * face * slow
        end
      end
      # senza obiettivo si sale a guardare dall'alto (vedi explore_look_around)
      if want.zero? && (rise = ex[:rise_to]) && ex[:z] < rise
        uz = 1.0
        want = [1.2, (rise - ex[:z]) * IN_TO_M].min
      end
      acc = EX_ACCEL * 2.0
      ex[:vx] = approach(ex[:vx], ux * want, acc, dt)
      ex[:vy] = approach(ex[:vy], uy * want, acc, dt)
      ex[:vz] = approach(ex[:vz], uz * want, acc, dt)
      sx = ex[:vx] * dt * M_TO_IN
      sy = ex[:vy] * dt * M_TO_IN
      sz = ex[:vz] * dt * M_TO_IN
      len = Math.sqrt(sx * sx + sy * sy + sz * sz)
      if len > 1e-4
        res = ray(ex[:x], ex[:y], ex[:z], sx / len, sy / len, sz / len)
        hit_d = res && Math.sqrt((res[0].x - ex[:x])**2 + (res[0].y - ex[:y])**2 + (res[0].z - ex[:z])**2)
        if hit_d && hit_d < len + ex[:radius_in]
          ex[:vx] = ex[:vy] = ex[:vz] = 0.0      # davanti c'è qualcosa: fermo (l'avanzamento deciderà)
        else
          ex[:x] += sx; ex[:y] += sy; ex[:z] += sz
        end
      end
      # mai sotto l'altezza degli occhi sul terreno; vicino a terra si atterra,
      # ma solo arrivati (non sul tetto che si sorvola per andare oltre)
      g = ray(ex[:x], ex[:y], ex[:z], 0, 0, -1)
      return unless g
      gap = ex[:z] - g[0].z
      ex[:z] = g[0].z + ex[:eye_h] if gap < ex[:eye_h]
      return unless ex[:o]['mode'] == 'auto' && gap <= ex[:eye_h] + 0.3 * M_TO_IN
      return if (t = ex[:target]) && !t[:arrived]
      return if ex[:no_land] && now < ex[:no_land]   # appena decollato da dove era bloccato
      ex[:mode] = :walk
      ex[:floor] = g[0].z
      ex[:vz] = 0.0
    end

    # ══════════════════════════════════════════════════════════════
    # Sguardo e camera
    # ══════════════════════════════════════════════════════════════
    def self.explore_wrap(a); ((a + Math::PI) % PI2) - Math::PI; end

    def self.explore_d3(a, b); Math.sqrt((a[0] - b[0])**2 + (a[1] - b[1])**2 + (a[2] - b[2])**2); end

    def self.explore_dist_eye(ex, pt); explore_d3(pt, [ex[:x], ex[:y], ex[:z]]); end

    # Due punti nella stessa direzione, vista da dove si è (entro 25°)?
    def self.explore_same_way?(ex, a, b)
      ya = Math.atan2(a[1] - ex[:y], a[0] - ex[:x])
      yb = Math.atan2(b[1] - ex[:y], b[0] - ex[:x])
      explore_wrap(ya - yb).abs < 25.0 * DEG
    end

    # Lo sguardo insegue il punto: esponenziale, con una velocità massima.
    def self.explore_gaze(ex, dt)
      if (esc = ex[:escape])
        yaw_goal = esc[:ang]
        pitch_goal = -4.0 * DEG
      elsif (lk = ex[:look])
        yaw_goal = lk[:goal]
        pitch_goal = (ex[:mode] == :fly ? -25.0 : -4.0) * DEG
      elsif (tgt = ex[:target]) && !tgt[:arrived] && (p = explore_route_look(ex, tgt))
        # l'obiettivo è nascosto, o il percorso gira lontano da lui: si guarda dove si va
        yaw_goal = Math.atan2(p[1] - ex[:y], p[0] - ex[:x])
        pitch_goal = -4.0 * DEG
      elsif tgt
        hx = tgt[:pt][0] - ex[:x]
        hy = tgt[:pt][1] - ex[:y]
        yaw_goal = Math.atan2(hy, hx)
        pitch_goal = Math.atan2(tgt[:pt][2] - ex[:z], Math.hypot(hx, hy))
      else
        return
      end
      pm = ex[:o]['pitch_max'] * DEG
      pitch_goal = pitch_goal.clamp(-pm, pm)
      k = 1.0 - Math.exp(-dt * EX_GAZE_K)
      ry = ex[:o]['turn_speed'] * DEG * dt
      ex[:yaw] = explore_wrap(ex[:yaw] + (explore_wrap(yaw_goal - ex[:yaw]) * k).clamp(-ry, ry))
      ex[:pitch] += ((pitch_goal - ex[:pitch]) * k).clamp(-ry * 0.6, ry * 0.6)
    end

    def self.explore_camera(view, ex, dt)
      bob = 0.0
      if ex[:o]['bob'] && ex[:mode] == :walk
        sp = Math.hypot(ex[:vx], ex[:vy])
        ratio = (sp / 1.2).clamp(0.0, 1.6)
        ex[:bob] = (ex[:bob] + dt * PI2 * 1.7 * (0.5 + 0.5 * ratio)) % PI2 if sp > 0.05
        bob = Math.sin(ex[:bob] * 2.0) * 0.012 * M_TO_IN * ratio
      end
      cp = Math.cos(ex[:pitch])
      fx = cp * Math.cos(ex[:yaw])
      fy = cp * Math.sin(ex[:yaw])
      fz = Math.sin(ex[:pitch])
      eye = Geom::Point3d.new(ex[:x], ex[:y], ex[:z] + bob)
      ux = -fx * fz; uy = -fy * fz; uz = 1.0 - fz * fz
      ul = Math.sqrt(ux * ux + uy * uy + uz * uz)
      up = ul > 1e-6 ? Geom::Vector3d.new(ux / ul, uy / ul, uz / ul) : Geom::Vector3d.new(0, 0, 1)
      cam = view.camera
      cam.set(eye, Geom::Point3d.new(eye.x + fx * 100.0, eye.y + fy * 100.0, eye.z + fz * 100.0), up)
      cam.fov = ex[:fov] if cam.perspective? && (cam.fov - ex[:fov]).abs > 1e-3
    end

    # ══════════════════════════════════════════════════════════════
    # Registrazione: il giro diventa un percorso di lib/path.rb
    # Stessi campioni della registrazione a mano, tempo senza le pause.
    # ══════════════════════════════════════════════════════════════
    def self.explore_rec_tick(ex, view)
      return unless ex[:o]['record']
      t = ex[:t]
      return if ex[:rec_last] && t - ex[:rec_last] < 1.0 / PATH_HZ - 0.002
      ex[:rec_last] = t
      c = view.camera
      e = c.eye; d = c.direction; u = c.up
      ex[:rec] << [t.round(3), e.x.round(2), e.y.round(2), e.z.round(2), d.x.round(5), d.y.round(5), d.z.round(5),
                   u.x.round(5), u.y.round(5), u.z.round(5), c.fov.round(2)]
    end

    def self.explore_save_path(ex)
      s = ex[:rec]
      return nil if s.size < 2 || s.last[0] < PATH_MIN
      base = t('explore.path')
      used = path_dict(ex[:model])&.keys || []
      n = 1
      n += 1 while used.include?("#{base} #{n}")
      name = "#{base} #{n}"
      data = { 'date' => Time.now.strftime('%Y-%m-%d %H:%M:%S'), 's' => s }
      data['notes'] = ex[:says] unless ex[:says].to_a.empty?     # i commenti dell'IA (lib/expilot.rb)
      data.merge!(gal_fields(ex[:gal], ex[:model]))              # le foto (lib/gallery.rb)
      path_write(t('path.op_save'), ex[:model]) { |m| m.set_attribute(PATH_DICT, name, JSON.generate(data)) }
      name
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    # ══════════════════════════════════════════════════════════════
    # Retina adattiva, riga di stato, disegno nella vista, menu
    # ══════════════════════════════════════════════════════════════
    # La griglia si allarga se l'analisi costa meno del suo budget, si
    # stringe se costa di più: su un modello pesante meno raggi, su uno
    # leggero più fini. Si stringe in fretta (fino a metà per analisi:
    # un'analisi da secondi blocca il passo), si allarga piano.
    def self.explore_adapt(ex)
      ms = ex[:scan_cpu] * 1000.0
      ex[:scan_ms] = ms
      if ms > 0.0 && ex[:scan_n].to_i > 0
        c = ms / ex[:scan_n]
        ex[:cell_ms] = ex[:cell_ms] ? ex[:cell_ms] + EX_CELL_K * (c - ex[:cell_ms]) : c
      end
      explore_budget(ex)
      return if ms <= 0.0
      lo, hi = EX_RANGES['grid']
      ex[:gw_f] = (ex[:gw_f] * ((ex[:scan_goal] / ms)**0.5).clamp(0.5, 1.25)).clamp(lo.to_f, hi.to_f)
      ex[:gw] = ex[:gw_f].round
    end

    # Il budget segue i fotogrammi (se adaptive; se no restano scan_ms e
    # frame_ms). Per fotogramma: quanto manca a EX_FPS_GOAL, cioè molto su
    # un modello leggero, ma almeno EX_SLICE_SHARE di un fotogramma su uno
    # pesante (se no la scansione non finirebbe mai). Per analisi: quante
    # fette stanno in una parte dell'intervallo fra due analisi (explore_hz:
    # un passo, se la cadenza adattiva è spenta), perché la decisione non
    # tardi. Dove SketchUp ha fiato la retina si fa fitta, dove i fotogrammi
    # rallentano si fa rada.
    def self.explore_budget(ex)
      return unless ex[:o]['adaptive'] && (other = ex[:fr_other])
      ex[:slice] = sl = [1000.0 / EX_FPS_GOAL - other, EX_SLICE_SHARE * other].max.clamp(*EX_SLICE)
      ex[:scan_goal] = (EX_SCAN_FILL * 1000.0 * sl / (other + sl) / explore_hz(ex)).clamp(*EX_RANGES['scan_ms'])
    end

    # Cadenza adattiva (pannello › Sistema › Prestazioni): [minimo, massimo]
    # di analisi al secondo, o nil se è spenta.
    def self.explore_hz_limits
      c = @cfg or return nil
      return nil unless c['explore_scan_adaptive']
      a, b = [c['explore_scan_hz_min'], c['explore_scan_hz_max']].map { |v| (explore_num(v) || 1.0).clamp(*EX_HZ_RANGE) }
      a <= b ? [a, b] : [b, a]
    end

    # Analisi al secondo. Spenta la cadenza adattiva, una per passo
    # (step_time del profilo). Accesa, quante ne stanno nel calcolo che i
    # fotogrammi lasciano alle fette (1000·slice/(other + slice) ms al
    # secondo, di cui EX_SCAN_FILL per le analisi) con la retina di partenza
    # (grid) al costo per cella misurato: su un modello leggero si sale verso
    # il massimo (e il calcolo che avanza fa più fitta la retina), su uno
    # pesante si scende fino al minimo, e solo sotto la retina si dirada
    # (explore_adapt). Le fette per fotogramma restano quelle, quindi i
    # fotogrammi e il cammino non rallentano: fra un'analisi e l'altra si va
    # verso l'obiettivo di prima.
    def self.explore_hz(ex)
      lim = explore_hz_limits
      step = 1.0 / ex[:o]['step_time']
      ex[:hz] = if lim.nil? then step
                elsif (c = ex[:cell_ms]) && (other = ex[:fr_other]) && ex[:aspect]
                  q = ex[:o]['grid']
                  cells = q * (q * ex[:aspect]).round.clamp(6, 48)
                  sl = ex[:slice]
                  (EX_SCAN_FILL * 1000.0 * sl / (other + sl) / (c * cells)).clamp(*lim)
                else (ex[:hz] || step).clamp(*lim)
                end
    end

    # La prima retina a misura del modello: quanto costa qui un raggio (nove,
    # attraverso la vista) e quante celle stanno in scan_ms. Solo per
    # stringerla: in certi modelli un raggio che colpisce il terreno costa
    # decine di ms, e la prima analisi con la retina piena durerebbe secondi.
    def self.explore_calibrate(view, ex)
      rays = explore_rays(view, 3, 3)
      t0 = explore_cpu
      rays.each { |r| ex[:model].raytest(r, true) }
      per = (explore_cpu - t0) / rays.size
      return if per <= 0.0
      aspect = view.vpwidth.to_f / [view.vpheight.to_f, 1.0].max
      lo, hi = EX_RANGES['grid']
      fit = Math.sqrt(ex[:scan_goal] / 1000.0 / per * aspect)
      ex[:gw_f] = [ex[:gw_f], fit].min.clamp(lo.to_f, hi.to_f)
      ex[:gw] = ex[:gw_f].round
    rescue => fps_err
      log_error(__method__, fps_err)
    end

    def self.explore_hud(ex, now)
      return if now < ex[:hud_t]
      ex[:hud_t] = now + 0.25
      Sketchup.status_text = explore_status_line(ex)
    end

    def self.explore_status_line(ex)
      return t('rt.explore_pause') if ex[:paused]
      tgt = ex[:target]
      return t('rt.explore_look') if tgt.nil? || ex[:look]
      format(t('rt.explore_hud'), what: tgt[:label], dist: format('%.1f', explore_dist_eye(ex, tgt[:pt]) * IN_TO_M),
                                  speed: format('%.1f', ex[:speed]), ms: ex[:scan_ms].round)
    rescue ArgumentError, KeyError
      t('rt.explore_off')
    end

    # Riga in alto a sinistra: analisi fatte, costo sul budget, retina,
    # velocità (cifre e simboli, niente da tradurre)
    def self.explore_hud_text(ex)
      res = ex[:res]
      hz = ex[:hz_lim] && ex[:hz] ? " · #{format('%.1f', ex[:hz])}/s" : ''
      g = res ? "#{res[:gw]}×#{res[:gh]}" : '…'
      "#{ex[:mode] == :fly ? '≈' : '»'} #{ex[:steps]} · #{ex[:scan_ms].round}/#{ex[:scan_goal].round} ms#{hz} · #{g} · " \
        "#{format('%.1f', ex[:speed])} m/s"
    end

    # Seconda riga: da dove vengono i colori che pesa la salienza
    def self.explore_hud_colors(ex)
      if ex[:pixels]
        ms = ex[:px_ms] ? " #{ex[:px_ms].round} ms" : ''
        "#{t('explore.colors_view')}#{ms}"
      elsif ex[:px_off]
        "#{t('explore.colors_model')} · #{format(t('explore.colors_slow'), ms: ex[:px_off].round)}"
      else
        t('explore.colors_model')
      end
    end

    def self.explore_color(rgb)
      (@ex_colors ||= {})[rgb] ||= Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
    end

    # Mappa dell'attenzione (le celle colpite, colorate per salienza), i
    # prossimi candidati, l'obiettivo col suo nome e la riga dei numeri.
    def self.explore_draw(view)
      ex = @ex or return
      res = ex[:res]
      tgt = ex[:target]
      if ex[:heatmap] && res
        bins = Array.new(EX_HEAT.size) { [] }
        f = res[:f]
        res[:cells].each_with_index do |c, i|
          next unless c
          b = EX_HEAT.rindex { |th, _, _| f[i] >= th }
          bins[b] << c.p if b
        end
        bins.each_with_index do |pts, b|
          view.draw_points(pts, EX_HEAT[b][2], 2, explore_color(EX_HEAT[b][1])) unless pts.empty?
        end
        pts = res[:cands].first(6).reject { |c| tgt && c[:id] == tgt[:id] }.map { |c| Geom::Point3d.new(*c[:pt]) }
        view.draw_points(pts, 12, 1, explore_color([255, 255, 255])) unless pts.empty?
        explore_draw_plan(view, ex)
      end
      if tgt
        p = Geom::Point3d.new(*tgt[:pt])
        acc = explore_color(rgba('ui_accent')[0, 3])
        view.draw_points([p], 24, 1, acc)
        view.draw_points([p], 7, 2, acc)
        cam = view.camera
        e = cam.eye
        d = cam.direction
        if (p.x - e.x) * d.x + (p.y - e.y) * d.y + (p.z - e.z) * d.z > 0.0
          s = view.screen_coords(p)
          explore_text(view, s.x + 16, s.y - 24, "#{tgt[:label]}  #{(tgt[:score] * 100).round}", acc)
        end
      end
      return if @ex_info_off
      [explore_hud_text(ex), explore_hud_colors(ex)].each_with_index do |txt, k|
        y = 6 + k * 24
        view.drawing_color = [0, 0, 0, 120]
        view.draw2d(GL_QUADS, [Geom::Point3d.new(6, y, 0), Geom::Point3d.new(14 + txt.size * 7, y, 0),
                               Geom::Point3d.new(14 + txt.size * 7, y + 22, 0), Geom::Point3d.new(6, y + 22, 0)])
        explore_text(view, 12, y + 4, txt, explore_color([255, 255, 255]))
      end
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    # Frontiere (quadratini viola, sul pavimento) e giro in corso (tratteggio)
    def self.explore_draw_plan(view, ex)
      cs = EX_PLAN_CELL
      feet = explore_feet(ex)
      lv = explore_plan_lv(feet)
      up = 0.05 * M_TO_IN
      on = ->(x, y) { Geom::Point3d.new(x, y, (explore_cell_z(ex, lv, x, y) || feet) + up) }   # sul pavimento visto
      pts = ex[:fronts].flat_map do |f|
        f[:cells].each_with_index.map do |(ix, iy), i|
          x = (ix + 0.5) * cs
          y = (iy + 0.5) * cs
          (z = f[:zs] && f[:zs][i]) ? Geom::Point3d.new(x, y, z + up) : on.(x, y)
        end
      end
      view.draw_points(pts, 6, 1, explore_color([190, 120, 255])) unless pts.empty?
      rt = ex[:route] or return
      line = [Geom::Point3d.new(ex[:x], ex[:y], feet + up)]
      i = rt[:i]
      if (pf = rt[:prof])
        # del tratto in corso, solo ciò che sta ancora davanti
        ax, ay = i.zero? ? pf[:start] : rt[:pts][i - 1]
        bx, by = rt[:pts][i]
        l2 = (bx - ax)**2 + (by - ay)**2
        tc = l2 > 1e-9 ? ((ex[:x] - ax) * (bx - ax) + (ex[:y] - ay) * (by - ay)) / l2 : 1.0
        pf[:segs][i..].each_with_index do |seg, j|
          seg.each { |t, x, y, z| line << Geom::Point3d.new(x, y, z + up) if j.positive? || t > tc }
        end
      else
        line.concat(rt[:pts][i..].map { |x, y| on.(x, y) })
      end
      view.line_width = 2
      view.line_stipple = '-'
      view.drawing_color = explore_color(rgba('ui_accent')[0, 3])
      view.draw(GL_LINE_STRIP, line)
      view.line_stipple = ''
    end

    def self.explore_text(view, x, y, txt, color)
      view.draw_text(Geom::Point3d.new(x, y, 0), txt, size: 12, bold: true, color: color)
    rescue ArgumentError, TypeError
      view.draw_text(Geom::Point3d.new(x, y, 0), txt)
    end

    # Ingombro di ciò che lo strumento disegna in 3D (per i piani di taglio).
    def self.explore_extents
      bb = Geom::BoundingBox.new
      ex = @ex or return bb
      if (res = ex[:res])
        res[:bb] ||= begin
          b = Geom::BoundingBox.new
          res[:cells].each { |c| b.add(c.p) if c }
          res[:cands].each { |c| b.add(Geom::Point3d.new(*c[:pt])) }
          b
        end
        unless res[:bb].empty?
          bb.add(res[:bb].min)
          bb.add(res[:bb].max)
        end
      end
      bb.add(Geom::Point3d.new(*ex[:target][:pt])) if ex[:target]
      bb
    end

    # Tasto destro durante l'esplorazione
    def self.explore_menu(menu)
      ex = @ex or return
      menu.add_item(t(ex[:paused] ? 'explore.resume' : 'explore.pause')) { explore_pause(nil) }
      menu.add_item(t('explore.next')) { explore_command('next') }
      menu.add_separator
      i = menu.add_item(t('explore.map')) { explore_command('heatmap') }
      menu.set_validation_proc(i) { @ex && @ex[:heatmap] ? MF_CHECKED : MF_UNCHECKED }
      px = ex[:px_off] ? format(t('explore.pixels_slow'), ms: ex[:px_off].round) : t('explore.pixels')
      i = menu.add_item(px) { explore_command('pixels') }
      menu.set_validation_proc(i) { @ex && @ex[:pixels] ? MF_CHECKED : MF_UNCHECKED }
      menu.add_separator
      menu.add_item(t('explore.stop')) { explore_stop }
      # carattere: un altro profilo vale subito (lib/exprofiles.rb)
      menu.add_separator
      sub = menu.add_submenu(t('explore.profile'))
      explore_profile_list.each do |p|
        i = sub.add_item(p['name']) { explore_profile_use(p['id']) }
        sub.set_validation_proc(i) { @ex && @ex[:o]['profile'] == p['id'] ? MF_CHECKED : MF_UNCHECKED }
      end
      menu.add_item(t('explore.profiles')) { xp_open }
    rescue => fps_err
      log_error(__method__, fps_err)
      nil
    end

    def self.explore_wheel(delta)
      ex = @ex or return
      ex[:speed] = (ex[:speed] * (delta > 0 ? 1.15 : 1.0 / 1.15)).clamp(*EX_RANGES['speed'])
      Sketchup.status_text = explore_status_line(ex)
    end

    def self.explore_log(ex, tgt, why)
      ex[:seq] += 1
      e = { 'n' => ex[:seq], 't' => ex[:t].round(1), 'why' => why }
      if tgt
        e['label'] = tgt[:label]
        e['score'] = tgt[:score].round(3)
        e['dist_m'] = (explore_dist_eye(ex, tgt[:pt]) * IN_TO_M).round(2)
        e['ai'] = true if tgt[:ai]
      end
      ex[:log] << e
      ex[:log].shift while ex[:log].size > EX_LOG_MAX
    end

    # ══════════════════════════════════════════════════════════════
    # Comandi e stato (menu, barra, ponte per Claude: GET/POST /explore)
    # ══════════════════════════════════════════════════════════════
    def self.explore_status
      ex = @ex
      return { 'ok' => true, 'on' => false, 'last' => @ex_last } unless ex
      tgt = ex[:target]
      res = ex[:res]
      m = ->(v) { (v * IN_TO_M).round(2) }
      {
        'ok' => true, 'on' => true, 'paused' => !!ex[:paused], 'mode' => ex[:mode].to_s,
        'profile' => { 'id' => ex[:o]['profile'], 'name' => explore_profile_name(ex[:o]['profile']) },
        'zoom' => (ex[:fov0] / ex[:fov]).round(2), 'escape' => !ex[:escape].nil?, 'stalls' => ex[:stalls].to_i,
        'jumps' => ex[:jumps].to_i, 'eye_m' => (ex[:eye_h] * IN_TO_M).round(2),
        'routes' => ex[:routes], 'replans' => ex[:replans], 'route_why' => ex[:route_why], 'route_left' => ex[:route] ? ex[:route][:pts].size - ex[:route][:i] : nil,
        'orbits' => ex[:orbits], 'orbiting' => explore_orbiting?(tgt),
        'frontiers' => ex[:fronts].size, 'plan_cells' => ex[:plan].size,
        'seconds' => ex[:t].round(1), 'steps' => ex[:steps], 'speed' => ex[:speed].round(2),
        'heatmap' => ex[:heatmap], 'pixels' => ex[:pixels], 'pixels_off_ms' => ex[:px_off]&.round, 'info' => !@ex_info_off,
        'pos_m' => [m.(ex[:x]), m.(ex[:y]), m.(ex[:z])],
        'yaw_deg' => (ex[:yaw] / DEG).round(1), 'pitch_deg' => (ex[:pitch] / DEG).round(1),
        'target' => tgt && { 'label' => tgt[:label], 'score' => tgt[:score].round(3), 'open' => !!tgt[:open],
                             'dist_m' => m.(explore_dist_eye(ex, tgt[:pt])), 'pt_m' => tgt[:pt].map { |v| m.(v) },
                             'arrived' => !tgt[:arrived].nil?, 'frontier' => !tgt[:front].nil?, 'visible' => tgt[:vis] },
        'scan' => { 'grid' => res ? [res[:gw], res[:gh]] : nil, 'rays' => ex[:scan_n], 'hits' => ex[:scan_hits],
                    'ms' => ex[:scan_ms].round(1), 'pixel_ms' => ex[:px_ms]&.round(1),
                    'goal_ms' => ex[:scan_goal].round(1), 'slice_ms' => ex[:slice].round(1),
                    'frame_ms' => ex[:fr_other]&.round(1),
                    'hz' => ex[:hz]&.round(2), 'hz_limits' => ex[:hz_lim],
                    'fovea' => ex[:geo] && ex[:o]['fovea'] > 0.0 ? [ex[:geo][:fx].round(2), ex[:geo][:fy].round(2)] : nil },
        'candidates' => res ? res[:cands].first(5).map { |c| { 'label' => c[:label], 'score' => c[:score].round(3), 'dist_m' => m.(explore_dist_eye(ex, c[:pt])) } } : [],
        'visited' => ex[:visited].size, 'agenda' => ex[:agenda].size, 'ev_n' => ex[:ev_seq], 'log' => ex[:log]
      }
    end

    # cmd: start (opts = opzioni, anche 'profile'), stop, status, pause, resume,
    # toggle, next, heatmap / pixels / info (opts true/false, o niente per scambiare),
    # speed (opts m/s), profiles (elenco), profile (opts = id o nome: in uso),
    # percept (opts = {"since": N, "n": 20, "brief": true}) e steer (lib/expilot.rb).
    def self.explore_command(cmd, opts = nil)
      cmd = cmd.to_s
      case cmd
      when 'start'
        err = explore_start(opts.is_a?(Hash) ? opts : nil)
        return err ? { 'ok' => false, 'error' => err } : explore_status
      when 'stop'
        name = explore_stop
        return { 'ok' => true, 'on' => false, 'path' => name, 'last' => @ex_last }
      when '', 'status'
        return explore_status
      when 'percept'
        q = opts.is_a?(Hash) ? opts : {}
        return explore_percept(q['since'].to_i, q['n'], q['brief'] == true)
      when 'profiles'
        return { 'ok' => true, 'active' => explore_profile_id, 'profiles' => explore_profile_list }
      when 'profile'
        id = explore_profile_find(opts) or return { 'ok' => false, 'error' => "profilo sconosciuto: #{opts}" }
        explore_profile_use(id)
        return explore_status.merge('active' => id)
      end
      ex = @ex
      return { 'ok' => false, 'error' => 'esploratore fermo: prima «start»' } unless ex
      flag = ->(cur) { opts == true || opts == false ? opts : !cur }
      case cmd
      when 'pause'   then explore_pause(true)
      when 'resume'  then explore_pause(false)
      when 'toggle'  then explore_pause(nil)
      when 'next'    then explore_skip(ex)
      when 'steer'   then return pilot_steer(ex, opts, explore_clock)
      when 'heatmap'
        ex[:heatmap] = flag.(ex[:heatmap])
        ex[:view].invalidate
      when 'pixels'
        ex[:pixels] = flag.(ex[:pixels])
        ex[:px_off] = nil if ex[:pixels]
        ex[:view].invalidate
      when 'info'   # resta scelto anche per le esplorazioni dopo
        @ex_info_off = !flag.(!@ex_info_off)
        ex[:view].invalidate
      when 'speed'
        v = explore_num(opts)
        ex[:speed] = v.clamp(*EX_RANGES['speed']) if v
      else
        return { 'ok' => false, 'error' => "comando sconosciuto: #{cmd}" }
      end
      explore_status
    end

    # ══════════════════════════════════════════════════════════════
    # Occhio a colori: una piccola immagine vera della vista (BMP, niente da
    # decomprimere) e la sua salienza a contrasto di colore, alla Achanta:
    # distanza dal colore medio + contrasto con l'intorno + densità di
    # dettaglio. Costa una write_image a ogni analisi: per questo è
    # facoltativo, e si spegne da solo se il modello la rende troppo lenta.
    # ══════════════════════════════════════════════════════════════
    def self.explore_grab(view, ex)
      require 'tmpdir'
      w = (ex[:gw] * 3).clamp(48, 192)
      h = (w * view.vpheight.to_f / [view.vpwidth, 1].max).round.clamp(27, 144)
      file = File.join(Dir.tmpdir, "dagawasd_esplora_#{Process.pid}.bmp")
      t0 = explore_cpu
      ok = view.write_image(filename: file, width: w, height: h, antialias: false, transparent: false)
      data = ok && File.exist?(file) ? File.binread(file) : nil
      ex[:px_ms] = (explore_cpu - t0) * 1000.0
      if ex[:px_ms] > EX_PX_MAX_MS
        ex[:pixels] = false
        ex[:px_off] = ex[:px_ms]   # il perché resta scritto nel menu e nel riquadro
      end
      data && explore_bmp(data)
    rescue => fps_err
      log_error(__method__, fps_err)
      ex[:pixels] = false
      nil
    ensure
      begin
        File.delete(file) if file && File.exist?(file)
      rescue SystemCallError
        nil
      end
    end

    # BMP a 24 o 32 bit, dal basso o dall'alto → { w:, h:, rgb: [r, g, b, …] }
    def self.explore_bmp(data)
      return nil unless data.bytesize > 54 && data.byteslice(0, 2) == 'BM'
      off = data.byteslice(10, 4).unpack1('V')
      w, h = data.byteslice(18, 8).unpack('l<l<')
      bpp, comp = data.byteslice(28, 6).unpack('vV')
      return nil unless w.positive? && h != 0 && [24, 32].include?(bpp) && [0, 3].include?(comp)
      top_down = h.negative?
      h = h.abs
      stride = ((bpp * w + 31) / 32) * 4
      return nil if data.bytesize < off + stride * h
      step = bpp / 8
      rgb = Array.new(w * h * 3)
      h.times do |row|
        y = top_down ? row : h - 1 - row
        line = data.byteslice(off + row * stride, w * step).bytes
        base = y * w * 3
        w.times do |x|
          k = x * step
          q = base + x * 3
          rgb[q] = line[k + 2]
          rgb[q + 1] = line[k + 1]
          rgb[q + 2] = line[k]
        end
      end
      { w: w, h: h, rgb: rgb }
    end

    def self.explore_pixel_saliency(img, budget = nil)
      w = img[:w]
      h = img[:h]
      n = w * h
      rgb = img[:rgb]
      deadline = budget && explore_cpu + budget
      pause = lambda do
        next unless deadline && explore_cpu >= deadline
        Fiber.yield
        deadline = explore_cpu + budget
      end
      memo = {}
      lab = [Array.new(n), Array.new(n), Array.new(n)]
      n.times do |i|
        r = rgb[3 * i]; g = rgb[3 * i + 1]; b = rgb[3 * i + 2]
        v = (memo[(r << 16) | (g << 8) | b] ||= explore_lab(r, g, b))
        lab[0][i] = v[0]; lab[1][i] = v[1]; lab[2][i] = v[2]
      end
      pause.call
      bl = lab.map { |ch| explore_box(ch, w, h, 1) }       # sfocatura leggera: gli spigoli disegnati non contano
      pause.call
      mean = bl.map { |ch| ch.sum / n }
      rad = [w / 16, 2].max
      loc = bl.map { |ch| explore_box(ch, w, h, rad) }
      pause.call
      ft = Array.new(n)
      lc = Array.new(n)
      n.times do |i|
        a0 = bl[0][i]; a1 = bl[1][i]; a2 = bl[2][i]
        ft[i] = Math.sqrt((a0 - mean[0])**2 + (a1 - mean[1])**2 + (a2 - mean[2])**2)
        lc[i] = Math.sqrt((a0 - loc[0][i])**2 + (a1 - loc[1][i])**2 + (a2 - loc[2][i])**2)
      end
      l = lab[0]
      gr = Array.new(n, 0.0)
      (1...h - 1).each do |y|
        (1...w - 1).each do |x|
          i = y * w + x
          gr[i] = (l[i + 1] - l[i - 1]).abs + (l[i + w] - l[i - w]).abs
        end
      end
      ed = explore_box(gr, w, h, rad)
      pause.call
      nf = explore_norm(ft)
      nl = explore_norm(lc)
      ne = explore_norm(ed)
      Array.new(n) { |i| 0.4 * nf[i] + 0.35 * nl[i] + 0.25 * ne[i] }
    end

    # Media su un quadrato di lato 2r+1 (immagine integrale), bordi compresi.
    def self.explore_box(a, w, h, r)
      w1 = w + 1
      ii = Array.new(w1 * (h + 1), 0.0)
      h.times do |y|
        row = 0.0
        w.times do |x|
          row += a[y * w + x]
          ii[(y + 1) * w1 + x + 1] = ii[y * w1 + x + 1] + row
        end
      end
      out = Array.new(w * h)
      h.times do |y|
        y0 = y - r < 0 ? 0 : y - r
        y1 = y + r + 1 > h ? h : y + r + 1
        w.times do |x|
          x0 = x - r < 0 ? 0 : x - r
          x1 = x + r + 1 > w ? w : x + r + 1
          s = ii[y1 * w1 + x1] - ii[y0 * w1 + x1] - ii[y1 * w1 + x0] + ii[y0 * w1 + x0]
          out[y * w + x] = s / ((y1 - y0) * (x1 - x0))
        end
      end
      out
    end

    def self.explore_norm(a)
      m = a.max.to_f
      m > 1e-9 ? a.map { |v| v / m } : Array.new(a.size, 0.0)
    end

    # Salienza dei pixel → una media per cella della retina, 0–1 (geo: dove
    # cadono le celle, explore_geo).
    def self.explore_pixel_map(img, gw, gh, budget = nil, geo = nil)
      sal = explore_pixel_saliency(img, budget)
      w = img[:w]
      h = img[:h]
      xs = geo ? geo[:bx].map { |b| (b * w).round.clamp(0, w) } : Array.new(gw + 1) { |k| k * w / gw }
      ys = geo ? geo[:by].map { |b| (b * h).round.clamp(0, h) } : Array.new(gh + 1) { |k| k * h / gh }
      out = Array.new(gw * gh, 0.0)
      gh.times do |cy|
        y0 = [ys[cy], h - 1].min
        y1 = [ys[cy + 1], y0 + 1].max
        gw.times do |cx|
          x0 = [xs[cx], w - 1].min
          x1 = [xs[cx + 1], x0 + 1].max
          s = 0.0
          (y0...y1).each { |y| (x0...x1).each { |x| s += sal[y * w + x] } }
          out[cy * gw + cx] = s / ((y1 - y0) * (x1 - x0))
        end
      end
      explore_norm(out)
    end

  end
end
