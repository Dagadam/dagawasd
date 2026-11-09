# Registro delle modifiche

Tutte le modifiche di DagaWASD che contano per chi lo usa. Numeri di versione
[semantici](https://semver.org/lang/it/): la terza cifra per le correzioni,
la seconda per le novità che non rompono nulla, la prima per i cambiamenti
che chiedono qualcosa a chi aggiorna.

Il numero sta in un posto solo, `VERSION` in `dagawasd.rb`;
`tools/crea_rbz.rb` rifiuta di fare il pacchetto se qui manca la sua sezione.

## [Non ancora uscito]

### Aggiunto
- Pannello: nuova scheda **Accessibilità** con **Niente lampi**, per chi è
  sensibile alle luci lampeggianti: niente lampo bianco quando si scatta una
  foto (propria o dell'esploratore) e niente fulmini né cielo che si
  schiarisce nei temporali, che restano pioggia o neve. La barra di stato
  conferma comunque ogni foto. La scheda dice dove stanno le altre
  regolazioni di comfort (head bob, campo visivo, tasti, contrasto elevato).
- Galleria: **Modifica**. I testi si cambiano lì dove sono, nella stessa
  calligrafia: titolo della galleria e delle foto, «Che cosa», «Perché», il
  timbro dell'autore, i commenti dell'IA. ✕ toglie una foto dalla galleria
  (il JPG resta) e ↺ la rimette; «↺ Torna all'originale» rimette il testo di
  SketchUp. Invio conferma, Esc annulla, Maiuscolo+Invio va a capo.
  Le modifiche si tengono subito nel browser; «Salva nella cartella» (Edge,
  Chrome) le scrive in `galleria_modifiche.json` accanto alle foto e nella
  pagina stessa, così restano anche mandando la cartella a qualcuno, e da lì
  in poi si salvano da sole. Negli altri browser «Scarica le modifiche».
  SketchUp non tocca mai quel file e lo rimette nella pagina ogni volta che
  la apre.
- `.github/ACCESSIBILITY.md`: la dichiarazione di accessibilità.

### Corretto
- Ponte per Claude: mentre Claude costruisce dal vivo, i comandi che
  cambierebbero il modello (scene, video, rinomina, elimina, posizioni dei
  percorsi, pannello della sfera, modalità FPS) non partono più e dicono di
  aspettare che finisca. Prima chiudevano a metà l'operazione della
  costruzione: il resto finiva fuori, e un errore non annullava più tutto.
  Fermare una riproduzione e guardare le foto si può sempre.
- Ponte per Claude: un invio il cui codice apre un messaggio di SketchUp non
  lascia più partire un secondo invio dentro il primo.
- Galleria: un nome nel modello che contiene `<!--<script>` non svuota più la
  pagina.
- Video come immagini: `crea_video.bat` funziona anche con un `%` nel nome
  del percorso e con lettere non ASCII (accenti, cirillico, giapponese…).
- Scene di un percorso: rifacendole si tolgono solo quelle fatte da DagaWASD,
  non più anche una scena dell'utente con lo stesso nome («Percorso 1 003»).
- Pannello della sfera: un errore a metà di una modifica la annulla per
  intero, invece di lasciare l'operazione aperta.
- Video: se l'avvio dell'esportazione fallisce, il file `.avi` appena creato
  non resta aperto e vuoto.
- Modalità FPS: se l'aggancio della tastiera fallisce, le sfere dei percorsi
  tornano visibili.
- `installa.bat` funziona anche con un `!` nel percorso (nome utente,
  cartella).
- Test: il conteggio dei fotogrammi per giro dell'esportazione video non
  fallisce più quando `sleep` di Windows sfora di qualche millisecondo.
- Esploratore: chi corre si ferma alla sua distanza di sosta. Prima la
  frenata cominciava sempre un metro e mezzo prima, qualunque fosse la
  velocità: il Soldato, che dovrebbe guardare da 3,5 m, scivolava fino a
  0,9 m, il Corridore finiva addosso agli oggetti e in volo passava oltre
  di una ventina di metri. Ora la velocità d'arrivo tiene conto dello spazio
  per frenare (anche lungo un percorso che aggira un muro); i profili lenti
  non cambiano.
- Esploratore: lo Spensierato cambia idea facilmente, ma non più a ogni
  analisi. Il capriccio di ogni candidato dura qualche secondo invece di
  essere ripescato ogni mezzo secondo: prima l'obiettivo cambiava in media
  ogni 2 s e non arrivava quasi mai a niente oltre i 3 m.
- Esploratore: un profilo sempre a piedi (Soldato) partito con il vuoto
  sotto la camera volava per sempre, senza atterrare. Ora lo dice nella riga
  di stato, vola come in automatico e atterra appena può.

## [1.2.1] — 2026-11-02

### Corretto
- Portoghese: «Dirada camere», la spiegazione dell'analisi adattiva e il
  suggerimento del tastierino usavano forme brasiliane («câmeras», «tela»,
  «grade», «mouse»…) in un'interfaccia in portoghese europeo: ora «Rarear
  câmaras», «ecrã», «grelha», «rato».

## [1.2.0] — 2026-11-02

### Aggiunto
- *Sistema › Prestazioni › Esploratore: analisi della vista* (livello
  avanzato): con **Analisi adattiva** accesa l'esploratore autonomo guarda la
  scena tanto più spesso quanto più calcolo lasciano liberi i fotogrammi, fra
  il minimo e il massimo di analisi al secondo scelti con un cursore a due
  maniglie. Le fette di calcolo per fotogramma restano quelle, quindi la
  camminata non rallenta; su un modello pesante prima si scende verso il
  minimo, e solo sotto la retina si dirada. Memoria, scia dello sguardo e
  «niente da vedere» contano il tempo, non il numero di analisi: il carattere
  dei profili resta lo stesso a ogni cadenza. Spenta (com'è all'inizio), una
  analisi per passo come prima.
- In *Camera › Percorsi*, sui percorsi con più di due posizioni nel modello,
  **Dirada camere**: dopo una conferma le sfere ammassate una sull'altra
  (tipiche di quando ci si gira sul posto registrando) diventano una sola,
  con la media di posizione, sguardo e zoom; le soste si sommano. Si uniscono
  solo sfere di fila nel percorso, mai due passaggi dallo stesso punto, e
  solo se guardano a non più di 45° l'una dall'altra: un giro sul posto
  resta fatto di più sguardi. Si annulla con Ctrl+Z.
- In *Camera › Percorsi* il triangolo accanto al nome apre, rientrato sotto
  al percorso, l'elenco delle sue posizioni: numero (lo stesso accanto alla
  sfera), quando la camera ci arriva e, se ci sono, sosta, velocità propria e
  zoom. Un clic su una posizione ne apre il pannello, come il doppio clic
  sulla sfera. L'elenco resta aperto mentre si spostano, aggiungono o tolgono
  sfere.
- Nello stesso elenco, passando col mouse fra due posizioni (o prima della
  prima, dopo l'ultima) compare una lineetta: un clic aggiunge lì una
  posizione presa dalla vista attuale, e la vista arretra di un metro per
  non restare dentro la sfera nuova (meno, se dietro c'è un muro). La sfera
  nuova prende colore e tag delle vicine; con l'anteprima del pannello della
  sfera accesa conta la vista di prima, e l'anteprima si spegne. Gli spazi si
  raggiungono anche col tasto Tab.
- Durante la riproduzione (e il video) di un percorso, nel suo elenco si
  accende una dopo l'altra la posizione in corso.
- Il pulsante «+ Nuovo dalla vista» si chiama ora «+ Nuovo percorso dalla
  vista», e la nota del pannello spiega l'elenco delle posizioni.
- **Esploratore autonomo** (`lib/explore.rb`, pulsante con l'occhio nella
  barra e voce nel menu): la camera esplora il modello da sola. Analizza la
  vista con una retina di raggi lanciati attraverso lo schermo (distanza,
  normale, faccia, oggetto e colore di ogni punto), sceglie il punto più
  significativo — sagome, spigoli, dettaglio, contrasto di colore, rarità,
  componenti e gruppi a misura d'uomo più delle pareti — gli fa un passo
  incontro guardandolo, e ricomincia. Gira attorno agli ostacoli, sale le
  scale, non scende dai precipizi; da una vista aerea vola e atterra dove c'è
  qualcosa da vedere. Una memoria di ciò che ha già guardato (e dei posti
  già calpestati) lo stanca delle stesse cose e lo porta in stanze nuove.
  L'analisi è divisa fra i fotogrammi e la retina si adatta al modello, così
  la vista resta fluida. Mappa dell'attenzione nella vista; Esc o un clic per
  fermarlo, tasto destro per pausa, «Cerca altro», mappa e «occhio a
  colori» (anche i pixel veri della vista, più lento); rotella per la
  velocità. Alla fine il giro diventa un percorso, da riguardare o da
  esportare in scene e video.
- **Profili dell'esploratore** (*Estensioni › DagaWASD › Profili
  dell'esploratore…*, `exprofiles.html`): il suo carattere è un insieme di
  coefficienti — velocità, riflessi, soste, determinazione, fedeltà,
  curiosità, noia, voglia di andare, capriccio, che cosa lo attira e quanto,
  zoom. Sette profili pronti: Equilibrato, Curioso, Corridore, Lento,
  Fotografo (ingrandisce ogni obiettivo prima di avvicinarsi), Spensierato
  e Soldato (ricognizione, sempre a piedi: corre, guarda da lontano e per poco, va prima
  dove non ha ancora visto); «Nuovo» ne copia uno da cambiare a piacere. Le modifiche
  valgono subito, anche mentre esplora; dal tasto destro si cambia profilo
  al volo.
- L'esploratore salta un ostacolo basso che gli sbarra la strada (muretti,
  staccionate), con la forza del salto e la gravità del giocatore, se oltre
  c'è un piano dove atterrare; il profilo Lento non salta. Altezza degli
  occhi, raggio, gradino e salto seguono le impostazioni del giocatore anche
  se cambiate mentre esplora.
- L'esploratore tiene una pianta di ciò che ha visto (a celle di 50 cm, una
  per piano, con la quota di pavimenti, gradini e mobili) e su di essa
  pianifica la strada per ogni obiettivo, invece di andare dritto schivando:
  attorno a muri e mobili, su per scale e pendii, mai sopra un tavolo. A ogni
  analisi ricontrolla il resto del percorso e, se ciò che ha appena visto lo
  sbarra, ne cerca un altro; dove urta, ricalcola. Se l'obiettivo sparisce
  dietro un muro trova il giro fino a un punto da cui lo rivede, invece di
  camminare contro il muro o lasciar perdere, e intanto guarda dove va. Il
  percorso in corso si vede tratteggiato sul pavimento: segue pendii e
  gradini e scavalca gli spigoli, senza attraversare i solidi.
- Frontiere: il bordo fra ciò che l'esploratore ha visto e ciò che non ha
  mai visto (oltre una porta, dietro un angolo) diventa un obiettivo, «zona
  inesplorata»: ci va a guardare. Quadratini viola nella mappa
  dell'attenzione, posati sul terreno anche in salita e in discesa.
- Retina dinamica: è più fitta attorno a ciò che l'esploratore guarda (una
  fovea sull'obiettivo, o al centro) e più rada ai margini, a parità di
  raggi; rarità e grandezza degli oggetti contano comunque per la parte di
  vista che occupano. Il tempo di calcolo segue i fotogrammi: dove SketchUp
  ha fiato la retina si fa fitta, dove la vista rallenta si fa rada. In
  alto a sinistra il costo dell'ultima analisi sul suo budget (es.
  «48/120 ms»). Opzioni `fovea` (0 = uniforme) e `adaptive` (false = budget
  fisso `scan_ms`/`frame_ms`).
- Occhio a colori: una seconda riga in alto a sinistra dice da dove vengono
  i colori che l'esploratore pesa («colori: dei materiali» o «colori: come
  si vedono», col costo dell'immagine). Se un'immagine della vista costa
  troppo si spegne da solo, e ora lo dice: nel riquadro e nella voce del
  tasto destro, coi millisecondi; un clic la riprova.
- Esploratore: il tasto I nasconde o mostra le righe d'informazione in alto
  a sinistra (comando `info` del ponte; la scelta resta per i giri dopo).
- Profili: *Giro attorno agli oggetti* (in gradi). Raggiunto un oggetto, ci
  gira attorno guardandolo per vederlo da più lati; il Fotografo di 180°, il
  Curioso di 90°, gli altri no. Gira solo finché lo vede: dove una parete lo
  nasconderebbe torna indietro e, se anche dall'altra parte sparisce, si
  ferma lì.
- La memoria dei posti già calpestati ricorda anche la quota: il piano di
  sopra, sulla stessa verticale, resta nuovo.
- Il pulsante dell'esploratore apre prima una finestra di avvio: si sceglie
  il profilo e se registrare il giro come percorso (`exstart.html`). Le due
  scelte restano per la volta dopo.
- Se in 10 secondi non si sposta, l'esploratore cerca una via di fuga e la
  percorre; senza via a piedi si alza in volo.
- Profili: *Continuità dello sguardo*. Lo sguardo dell'esploratore passa
  volentieri a ciò che sta accanto a quello che guarda, invece di saltare
  da una parte all'altra della vista, e non torna su ciò che aveva già nella
  retina e da cui si è girato: niente più destra, sinistra e di nuovo
  destra. Anche guardandosi intorno continua a girare dalla stessa parte.
  Il Soldato ne ha di più, lo Spensierato di meno; a 0 si comporta come
  prima.
- **Ponte per Claude Code**: `GET/POST /explore` comanda e osserva
  l'esploratore (obiettivo, candidati, diario delle scelte); client
  `tools/esplora.rb` con `avvia` (anche `--profilo`), `ferma`, `profili`,
  `profilo`, `segui --foto` (un'immagine della vista a ogni nuovo
  obiettivo).
- **L'IA alla guida dell'esploratore** (`lib/expilot.rb`): attraverso il
  ponte Claude Code vede ciò che l'esploratore ha visto (ogni cosa con un
  nome corto e stabile, la sua direzione, distanza e grandezza, le zone
  inesplorate) e gli dà un'agenda di mete: vai, guarda, vai a un punto, con
  sosta, giro attorno e un commento che finisce nel diario. Può anche dargli
  dei gusti (questo di più, quello mai, più frontiere) senza dare ordini.
  L'esploratore non aspetta mai: cammina e guarda da solo verso le mete
  dell'IA e, ad agenda vuota, sceglie da sé. Sul ponte `GET
  /explore/percept` (con gli avvisi: arrivato, fatto, agenda quasi vuota,
  cosa notevole) e il comando `steer`; client `tools/esplora.rb pilota` e
  `guida`.
- Il pilota vede: alle soste davanti alle sue mete l'esploratore scatta una
  foto della vista con il nome corto scritto accanto a ogni cosa visibile
  (la meta in giallo, oggetti, facce, zone inesplorate), in
  `%APPDATA%\DagaWASD\pilota`. Solo da fermi, perché un'immagine della vista
  blocca SketchUp per un attimo; a richiesta anche a ogni sosta, o mai.
  `GET /explore/wait`: il ponte tiene in sospeso la richiesta del pilota e
  risponde quando c'è qualcosa da decidere, invece di essere interrogato di
  continuo.
- Foto e galleria: P (o il dorsale destro del gamepad) scatta una foto, che
  va col percorso se ne stai registrando uno. L'esploratore fotografa da sé
  le mete più interessanti del giro e scrive che cosa sono e perché le ha
  scelte; l'IA che lo guida le chiede con `snap`. Ogni serie sta accanto al
  modello (`<modello>_foto/`).
- In *Camera › Percorsi* ogni percorso ha il pulsante 📷 accanto a Video:
  apre nel browser la galleria, o spiega come fare foto se non ce ne sono.
  Le serie senza percorso stanno sotto l'elenco.
- La galleria: Polaroid che si sviluppano su un tavolo di legno, ognuna coi
  suoi appunti (che cosa, perché, chi, bussola e ora). Si guardano in fila,
  col rullino delle miniature, o sparse sul tavolo, da spostare a mano. In
  testa il giro a matita con le foto e i loro coni di vista, e in un angolo
  la mappa piccola che segue. Ci sono anche i commenti dell'IA sui post-it,
  il filtro per autore, la presentazione, la scheda finale con durata e
  strada, e la stampa.
- Un'azione arrivata con una versione nuova (come la foto) prende un tasto
  libero se il suo predefinito l'avevi già dato a un'altra: i tuoi tasti
  restano.
- A piedi l'IA sa dove si arriva: `reach` e `walk_m` per cose e zone
  inesplorate (una ricerca sulla pianta per tutte, riusata per qualche
  secondo), «vai» verso cose irraggiungibili rifiutato, cartellini grigi
  nelle foto. Lo stesso commento non si ripete nello stesso giro.
- Il pilota non si risveglia più da solo dopo ogni sua decisione (gli avvisi
  causati dallo steer non svegliano); il ponte libera le attese dei client
  andati via.
- I commenti dell'IA restano nel percorso registrato: descrizioni delle
  scene e sottotitoli `.srt` del video (accanto all'AVI; nell'MP4 di
  `crea_video.bat`).
- Pilota autonomo `tools/pilota_ia.rb`: Claude guida l'esploratore da solo,
  con la descrizione e le foto delle soste, un tetto di turni e di secondi.
  Due motori: Claude Code (`claude -p`, l'account di questo computer, nessuna
  chiave; risposta in JSON con lo schema dello steer, foto lette con Read,
  conversazione con `--resume`) e l'API di Claude (gemma `anthropic`,
  strumento `steer`). Test con un `claude -p` finto e un'API finta
  (`tests/test_pilota_ia.rb`).
- Test dell'esploratore in una scena finta (`tests/test_explore.rb`): due
  stanze con una porta, scale, una terrazza, una vista aerea.

### Corretto
- Entrando in modalità WASD la vista si spostava: gli occhi saltavano
  all'altezza impostata sopra il pavimento e lo zoom passava a quello del
  pannello. Ora si parte esattamente dalla vista in cui si era; altezza degli
  occhi e zoom del pannello arrivano morbidi al primo passo (o salto,
  accovacciamento, presa).
- Finita la riproduzione di un percorso la vista restava all'arrivo, dentro
  l'ultima sfera: ora torna dov'era quando la riproduzione è partita. Fermata
  prima con Esc o con un clic resta dov'è arrivata.
- Avviare la camminata stando dentro una sfera aperta in modifica scriveva
  un errore nel registro (le sfere restavano visibili): ora le sfere restano
  accese senza errori.
- Spegnendo e riaccendendo subito l'anteprima del pannello della sfera, o
  avviando la riproduzione durante il suo dolly, le sfere potevano restare
  spente (tag *DagaWASD percorsi* nascosto).
- Con la vista in proiezione parallela, «successiva» e «precedente» del
  pannello della sfera la facevano passare in prospettiva a 60°: ora resta
  parallela.
- Raramente il disegno dei numeri delle sfere si interrompeva con un errore
  nel registro, e i numeri successivi non comparivano.
- Ponte per Claude, con la costruzione dal vivo spenta: il codice inviato
  vedeva le variabili interne del ponte, e un `out = …` nel codice faceva
  perdere l'output della risposta (o un errore incomprensibile).
- Ponte per Claude ed estensione DagaMCP accesi insieme: mentre DagaMCP
  costruisce dal vivo, il ponte di DagaWASD rifiuta il codice (riprova a
  costruzione finita) e la modalità WASD non parte, così nessuno entra
  nell'operazione aperta dell'altro.

## [1.1.0] — 2026-10-17

### Aggiunto
- **Pannello della sfera**: doppio clic su una sfera di un percorso, o Invio
  con la sfera selezionata, apre una finestra con tutte le sue impostazioni:
  posizione (X, Y, Z, occhi da terra), sguardo (direzione a bussola,
  inclinazione, rollio), zoom (campo visivo o ingrandimento), sosta e
  velocità del tratto fino alla prossima (o quella del percorso), con la
  durata del tratto e il momento d'arrivo. Accanto a ogni campo − e +
  cambiano il valore di un passo (0,1 m, 5° la direzione, 1° gli altri
  angoli…); tenuti premuti lo fanno scorrere. Col destro il valore cambia da
  solo, un centesimo alla volta (un'unità al secondo), con SketchUp che lo
  segue dal vivo, finché un altro clic lo ferma lì. Nel pannello non compare
  il menu del browser (in inglese): nelle caselle il destro apre un menu
  tradotto con Taglia, Copia e Incolla. Lo stesso nel pannello delle
  impostazioni, dove prima il destro mostrava il menu del browser in
  inglese, con le voci per sviluppatori. Ogni modifica si annulla con
  Ctrl+Z (uno scorrimento intero con un solo Ctrl+Z) e la sfera cambia
  subito. «Anteprima dalla sfera» porta la camera
  in dolly dentro ciò che vede la sfera (le sfere si spengono) e la segue a
  ogni modifica; tolta, torna in dolly alla vista di prima. ◀ ▶ passano alla
  sfera precedente o successiva, sempre in dolly: con l'anteprima lungo il
  percorso vero. In più «Prendi dalla vista», «Inserisci dopo», «Elimina».
  Riproduzione, scene e video rispettano soste e velocità di ogni sfera.

### Corretto
- I numeri delle sfere si vedevano attraverso i muri (il «9» di una sfera
  dietro la casa finiva sul tetto): ora si scrivono solo per le sfere in
  vista.

## [1.0.1] — 2026-10-17

### Aggiunto
- **Percorsi da ritoccare**: il pulsante «Modifica» di un percorso lo mette
  nel modello come posizioni, sfere con una freccia (lo sguardo, lunga
  quanto lo zoom: il doppio a ingrandimento 2×) e davanti il riquadro
  dell'inquadratura col triangolo sul lato alto, che si inclina quando la
  sfera ruota attorno alla freccia (rollio), ricavate dalla registrazione
  levigata (una sfera dove la strada, lo sguardo o lo zoom della rotella
  cambiano; zoomare sul posto prende il suo tempo, un raddoppio al secondo).
  Sfere fatte prima si aggiornano alla prossima «Modifica». Si spostano e si
  ruotano con Sposta e Ruota; Ctrl+Sposta su una sfera ne aggiunge una, Canc
  la toglie. Riproduzione,
  scene e video seguono le sfere su una curva morbida a velocità costante
  (quella media della registrazione, soste escluse; girarsi sul posto a
  45°/s). Un'Overlay disegna la curva e il numero d'ordine di ogni sfera.
  Lo stesso pulsante nasconde e rimostra le sfere, «↺» le toglie e torna alla
  registrazione; «Nuovo dalla vista» crea un percorso di due sfere senza
  registrare. Le sfere hanno il tag «DagaWASD percorsi», spento da solo in
  modalità FPS e durante riproduzione e video.

- **Finestre e tasti per Claude** (Sistema › Ponte Claude, solo nel pacchetto
  completo): permesso, spento di default, perché Claude Code prema pulsanti,
  apra menu, risponda agli avvisi, catturi la vista e simuli tasti in
  SketchUp. Con «Mostra il mouse» (acceso di default) il cursore va sul
  pulsante, incorniciato di verde, prima che venga premuto; la durata del
  viaggio si sceglie. Come il ponte, non si importa da un file.
- Una costruzione dal vivo del ponte porta SketchUp in primo piano (e lo
  rimostra se era ridotto a icona): prima la si poteva perdere dietro altre
  finestre.

### Corretto
- Il pannello (e la finestra del video) non si apriva se SketchUp ricordava
  una posizione dove ora non c'è più un monitor, per esempio dopo aver
  staccato uno schermo o usato una sessione remota: la finestra c'era ma
  fuori dallo schermo. Ora in quel caso si riapre al centro.
- Correndo, l'oscillazione della testa (head bob) cresceva con la velocità
  fino a ±7,7 cm, irreale. Ora non supera ±4,5 cm in verticale e ±3 cm di
  lato, qualunque sia la velocità; i cursori del pannello arrivano lì.
- Anche la frequenza aveva lo stesso difetto: la testa andava su e giù al
  doppio del valore del pannello (4,4 volte al secondo camminando a 2 Hz) e
  correndo fino a 7, che con pochi fotogrammi al secondo diventava un
  saltellare a caso. Ora il valore del pannello sono i passi al secondo
  camminando; correndo crescono fino a un massimo di 3, la cadenza di una
  corsa vera. Il cursore arriva a 3 Hz.

## [1.0.0] — 2026-10-09

Prima versione distribuita.

### Aggiunto
- **Camminata in prima persona** con WASD e mouse: inerzia, corsa,
  accovacciarsi, salto variabile, gradini e pendenze, dondolio della testa,
  ritorno a terra se cadi nel vuoto.
- **Fisica degli oggetti**: gruppi e componenti cadono, rimbalzano, scivolano
  e si ribaltano; massa, attrito e rimbalzo secondo il materiale. Calcia,
  afferra, lancia, spingi.
- **Cielo**: sole, luna con le sue fasi e stelle secondo data, ora e luogo
  del modello, oppure di un luogo pronto o di coordinate scelte a mano.
- **Meteo**: pioggia e neve attorno alla camera, con vento, nebbia e riparo
  sotto i tetti; nuvole portate dal vento che velano il sole; temporali con
  lampi; neve al suolo che imbianca tetti, terreno e chiome e poi si scioglie.
  Sette situazioni pronte (per esempio «Temporale estivo» e «Notte di neve»).
- **Gamepad** XInput (Xbox e compatibili): leve analogiche, grilletti,
  pulsanti, vibrazione.
- **Visuale con il tastierino numerico**, in alternativa al mouse.
- **Percorsi**: registra la camera mentre cammini, riproducila, esportala in
  scene o in video AVI (Motion JPEG, si apre con il lettore di Windows e con
  VLC).
- **Finestra durante il video**: mentre un percorso diventa video AVI o
  immagini PNG, un personaggio parla da un fumetto con la barra di
  avanzamento, le statistiche del percorso, del video e del modello
  (fotogrammi, tempo trascorso e mancante, MB scritti e stima finale, metri
  percorsi, facce, materiali, componenti) e battute ricavate da quei numeri,
  in tutte le lingue. Esc o «Interrompi» fermano l'esportazione; alla fine il
  fumetto dice com'è andata, con «Guarda il video» e «Apri la cartella».
  A ogni export il personaggio si veste a caso, mai due volte uguale di
  seguito: cappelli, cuffie o corona, occhiali, sciarpa o papillon, e in
  mano un ciak, una bibita con la cannuccia, i popcorn o un gelato.
- **Pannello delle impostazioni** con tasti personalizzati, temi, mirino,
  esportazione e importazione; interfaccia in 36 lingue, anche da destra a
  sinistra (arabo, ebraico). Le impostazioni stanno in
  `%APPDATA%\DagaWASD\settings.json`, così un aggiornamento non le cancella;
  nella stessa cartella il registro errori, `dagawasd.log`.
- **Ponte per Claude Code**, spento finché non lo accendi dal pannello: un
  server solo locale, con un token che cambia a ogni avvio, attraverso cui
  Claude disegna nel modello aperto, passo per passo e con la camera che gira
  attorno al lavoro. Tutto si annulla con un solo Ctrl+Z. Il pacchetto per
  l'Extension Warehouse non lo contiene.
- Funziona anche da remoto (per esempio con RustDesk) e con lettere accentate
  nel percorso dell'estensione.
- Richiede SketchUp su Windows: su Mac l'estensione si installa ma non parte,
  e lo dice una volta sola.
- Licenza MIT.
