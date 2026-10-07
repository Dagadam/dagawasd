# DagaWASD

Estensione per SketchUp (Windows): cammini nel modello in prima persona con
WASD e mouse, o con un gamepad.

*A SketchUp extension (Windows only) to walk through your model in first
person with WASD and mouse or a gamepad, with object physics, sky, weather
and recorded camera paths. The interface is available in 36 languages.*

## Che cosa fa

- **Camminata**: inerzia, corsa, accovacciarsi, salto, gradini e pendenze,
  ritorno a terra se cadi nel vuoto.
- **Fisica degli oggetti**: gruppi e componenti cadono, rimbalzano e si
  ribaltano secondo il materiale; si possono calciare, afferrare e lanciare.
- **Cielo e meteo**: sole, luna e stelle secondo data, ora e luogo; pioggia,
  neve, nuvole, temporali, neve al suolo.
- **Percorsi**: registra la camera mentre cammini, riproducila, esportala in
  scene o in video AVI.
- **Gamepad** XInput e visuale con il tastierino numerico.
- Pannello delle impostazioni in 36 lingue.

Requisiti: SketchUp 2023 o successivo, su Windows. Su Mac l'estensione si
installa ma non parte, e lo dice.

## Installazione

- Dall'**Extension Warehouse** di SketchUp (versione firmata), oppure
- scarica il `.rbz` da una Release e installalo da *Estensioni › Gestore
  estensioni › Installa estensione*.

Le impostazioni stanno in `%APPDATA%\DagaWASD\settings.json`: un
aggiornamento non le cancella.

## Due pacchetti

`tools\crea_rbz.bat` crea in `dist\`:

- `dagawasd-<versione>.rbz`: completo, con il **ponte per Claude Code**
  (`lib/bridge.rb`), un server solo locale, spento finché non lo accendi dal
  pannello, attraverso cui Claude Code disegna nel modello aperto;
- `dagawasd-<versione>-warehouse.rbz`: senza il ponte, per l'Extension
  Warehouse. Senza `lib/bridge.rb` l'estensione funziona lo stesso.

## Sviluppo

- `installa.bat` copia il sorgente nella cartella Plugins di ogni SketchUp
  trovato.
- `tests\run_tests.bat` lancia i test (Ruby, con SketchUp simulato; il
  pannello in un browser simulato con Node).
- `tools\controlla_warehouse.bat` controlla il pacchetto con le regole di
  Trimble (rubocop-sketchup).
- Il numero di versione sta solo in `dagawasd.rb` (`VERSION`); ogni versione
  ha la sua sezione in `CHANGELOG.md`.

## Licenza

[MIT](LICENSE) © 2026 Dagadam. Puoi usare, modificare e ridistribuire il codice
liberamente, anche a fini commerciali, purché ogni copia mantenga la nota di
copyright e il testo della licenza.
