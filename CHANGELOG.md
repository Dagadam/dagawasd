# Registro delle modifiche

Tutte le modifiche di DagaWASD che contano per chi lo usa. Numeri di versione
[semantici](https://semver.org/lang/it/): la terza cifra per le correzioni,
la seconda per le novità che non rompono nulla, la prima per i cambiamenti
che chiedono qualcosa a chi aggiorna.

Il numero sta in un posto solo, `VERSION` in `dagawasd.rb`;
`tools/crea_rbz.rb` rifiuta di fare il pacchetto se qui manca la sua sezione.

Il progetto è sotto git dal 7 ottobre 2026: le voci fino alla 2.1.0 sono
ricostruite a posteriori dalle date dei file e dalle sessioni di lavoro.

## [Non ancora uscito]

## [2.1.0] — 2026-10-07

### Aggiunto
- **Cielo**: sole, luna con le sue fasi e stelle secondo data, ora e luogo
  del modello, oppure di un luogo pronto o di coordinate scelte a mano.
- **Meteo**: pioggia e neve attorno alla camera, con vento, nebbia e riparo
  sotto i tetti; nuvole portate dal vento che velano il sole; temporali con
  lampi e tuono; neve al suolo che imbianca tetti, terreno e chiome e poi si
  scioglie. Sette situazioni pronte (per esempio «Temporale estivo» e «Notte
  di neve»).
- **Suoni**: passi diversi secondo il pavimento, atterraggi.
- **Gamepad** XInput (Xbox e compatibili): leve analogiche, grilletti,
  pulsanti, vibrazione.
- **Visuale con il tastierino numerico**, in alternativa al mouse.
- **Percorsi**: registra la camera mentre cammini, riproducila, esportala in
  video AVI (Motion JPEG, si apre con il lettore di Windows e con VLC).
- **Ponte per Claude Code**, spento finché non lo accendi dal pannello: un
  server solo locale, con un token che cambia a ogni avvio, attraverso cui
  Claude disegna nel modello aperto; costruzione dal vivo passo per passo, con
  la camera che gira attorno al lavoro. Tutto si annulla con un solo Ctrl+Z.
- **Pacchetto .rbz** per installare dal Gestore estensioni di SketchUp
  (`tools/crea_rbz.bat`).

### Modificato
- Le impostazioni stanno in `%APPDATA%\DagaWASD\settings.json`, fuori dalla
  cartella dell'estensione: aggiornare con un .rbz non le cancella più. Al
  primo avvio quelle vecchie vengono recuperate da sole.
- Da remoto (per esempio con RustDesk) i tasti arrivano: si scartano solo
  quelli che DagaWASD inietta da sé.
- Descrizione nel Gestore estensioni aggiornata a tutto quello che fa.

### Corretto
- Arabo ed ebraico: i codici colore non perdono più il `#` in fondo
  («ffd166#»), le parole chiave dei materiali si leggono dall'inizio, le
  unità come °/s non diventano s/°, il percorso del file del ponte resta
  intero.

### Rimosso
- `settings.json` dai file distribuiti: i valori predefiniti stanno nel
  codice (`lib/config.rb`).
- L'Officina (generatori di pezzi da stampare in 3D) è diventata un progetto
  a sé in `G:\Officina`; usa ancora il ponte di DagaWASD per costruire in
  SketchUp.

## [2.0.0] — 2026-09-27

### Modificato
- Nuovo nome: **DagaWASD**.
- Il codice è diviso per argomento in `lib/` invece che in un file solo.

## Prima del nome DagaWASD — settembre 2026

Le versioni prima del nuovo nome.

- Camminata in prima persona con WASD e mouse: inerzia, corsa, accovacciarsi,
  salto variabile, gradini e pendenze, ritorno a terra se cadi nel vuoto.
- Fisica degli oggetti: gruppi e componenti cadono, rimbalzano, scivolano e
  si ribaltano; massa, attrito e rimbalzo secondo il materiale. Calcia,
  afferra, lancia, spingi.
- Pannello delle impostazioni con tasti personalizzati, temi, mirino,
  esportazione e importazione; interfaccia in 36 lingue.
