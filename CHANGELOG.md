# Registro delle modifiche

Tutte le modifiche di DagaWASD che contano per chi lo usa. Numeri di versione
[semantici](https://semver.org/lang/it/): la terza cifra per le correzioni,
la seconda per le novità che non rompono nulla, la prima per i cambiamenti
che chiedono qualcosa a chi aggiorna.

Il numero sta in un posto solo, `VERSION` in `dagawasd.rb`;
`tools/crea_rbz.rb` rifiuta di fare il pacchetto se qui manca la sua sezione.

## [Non ancora uscito]

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
