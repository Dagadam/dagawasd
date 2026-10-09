# Registro delle modifiche

Tutte le modifiche di DagaWASD che contano per chi lo usa. Numeri di versione
[semantici](https://semver.org/lang/it/): la terza cifra per le correzioni,
la seconda per le novità che non rompono nulla, la prima per i cambiamenti
che chiedono qualcosa a chi aggiorna.

Il numero sta in un posto solo, `VERSION` in `dagawasd.rb`;
`tools/crea_rbz.rb` rifiuta di fare il pacchetto se qui manca la sua sezione.

## [Non ancora uscito]

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
