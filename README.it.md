# DagaWASD

[English](README.md) · **Italiano** · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Nederlands](README.nl.md) · [Svenska](README.sv.md) · [Polski](README.pl.md) · [Čeština](README.cs.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [中文](README.zh.md)

Estensione per SketchUp (Windows): cammini nel modello in prima persona con
WASD e mouse, o con un gamepad.

▶ Video dimostrativo: https://youtu.be/w6xE86y7iEw?is=7Gh12tF7atE_N9_K

⬇ **Scarica**: [ultima versione](https://github.com/Dagadam/dagawasd/releases/latest) (tutte le versioni: [Releases](https://github.com/Dagadam/dagawasd/releases))

## Che cosa fa

- **Camminata**: inerzia, corsa, accovacciarsi, salto, gradini e pendenze,
  ritorno a terra se cadi nel vuoto.
- **Fisica degli oggetti**: gruppi e componenti cadono, rimbalzano e si
  ribaltano secondo il materiale; si possono calciare, afferrare e lanciare.
- **Cielo e meteo**: sole, luna e stelle secondo data, ora e luogo; pioggia,
  neve, nuvole, temporali, neve al suolo. Situazioni pronte, e un meteo
  variabile che cambia da solo col tempo del cielo. Il meteo compare anche
  nei video esportati.
- **Percorsi**: registra la camera mentre cammini, riproducila, esportala in
  scene o in video AVI. Ritoccala nel modello spostando e ruotando le sue
  posizioni (sfere con una freccia lunga quanto lo zoom e il riquadro
  dell'inquadratura), o costruiscine una da zero. Nel pannello ogni percorso
  si apre sull'elenco delle sue posizioni; un clic su una posizione, o un
  doppio clic sulla sua sfera (o Invio), apre le sue impostazioni, con
  l'anteprima di ciò che vede, e un clic fra due posizioni ne aggiunge una
  dalla vista attuale. Durante la riproduzione l'elenco accende la posizione
  in corso. «Dirada camere» unisce le sfere ammassate una sull'altra in una
  sola, la loro media (posizione, sguardo, zoom), se non guardano a più di
  45° l'una dall'altra.
- **Esploratore autonomo**: la camera guarda la scena, sceglie la cosa più
  significativa, le fa un passo incontro guardandola e ricomincia; alla fine
  il giro è un percorso. Vedi sotto.
- **Foto e galleria**: P scatta una foto di quello che vedi; l'esploratore
  fotografa da sé le cose più interessanti del giro. Ogni percorso apre la
  sua galleria nel browser, Polaroid su un tavolo con gli appunti. Vedi sotto.
- **Gamepad** XInput e visuale con il tastierino numerico.
- Pannello delle impostazioni in 36 lingue.
- **Accessibilità**: *Accessibilità › Niente lampi* spegne ogni lampo, delle
  foto e dei fulmini (vedi [ACCESSIBILITY.md](.github/ACCESSIBILITY.md)).

Requisiti: SketchUp 2023 o successivo, su Windows. Su Mac l'estensione si
installa ma non parte, e lo dice.

## Installazione

- Dall'**Extension Warehouse** di SketchUp (versione firmata), oppure
- scarica **`dagawasd-<versione>-warehouse.rbz`** dall'
  [ultima versione](https://github.com/Dagadam/dagawasd/releases/latest) (sotto *Assets*) e installalo da
  *Estensioni › Gestore estensioni › Installa estensione*. L'altro file,
  `dagawasd-<versione>.rbz`, contiene anche il ponte per Claude Code (vedi
  *Due pacchetti*).

Le impostazioni stanno in `%APPDATA%\DagaWASD\settings.json`: un
aggiornamento non le cancella.

## Esploratore autonomo

Pulsante con l'occhio nella barra (o *Estensioni › DagaWASD › Esploratore
autonomo*): una piccola finestra fa scegliere il profilo (il carattere, vedi
sotto) e se registrare il giro come percorso, e ricorda le scelte per la
volta dopo; frecce e Invio, o doppio clic su un profilo, per partire subito.
Lo stesso pulsante, mentre esplora, lo ferma. Ciclo: **analizza → sceglie il punto → un passo verso il punto,
guardandolo → analizza**.

- **Analisi**: una retina di raggi attraverso la griglia dello schermo
  (`view.pickray` + `model.raytest`) dà, per ogni cella, distanza, normale,
  faccia, oggetto e colore. Da lì la salienza: bordi di profondità, spigoli,
  dettaglio, contrasto di colore (Lab), rarità, componenti e gruppi a misura
  d'uomo; le pareti e i pavimenti grandi contano poco. Pesata per distanza,
  centro della vista e novità.
- **Memoria**: voxel di ciò che lo sguardo ha già visto, posti già
  calpestati (in pianta e in quota: il piano di sopra resta nuovo), noia per
  obiettivo e per categoria (visto un divano, gli altri uguali incuriosiscono
  meno): così non torna sempre sulle stesse cose.
- **Pianta di ciò che ha visto**: a piedi, i raggi che passano all'altezza
  del corpo segnano su una pianta a celle di 50 cm (una per piano) il
  pavimento visto con la sua quota (pavimento, gradini, piani dei mobili) e i
  muri colpiti. Serve a due cose:
  - **frontiere**: il bordo fra ciò che ha visto e ciò che non ha mai visto
    (oltre una porta, dietro un angolo) diventa un obiettivo, «zona
    inesplorata»: ci va e ci guarda dentro. Pesa come lo spazio aperto,
    secondo la voglia di andare del profilo; nella mappa dell'attenzione
    sono i quadratini viola sul pavimento;
  - **percorsi pianificati**: per ogni obiettivo si prefigura la strada sulla
    pianta (A*) fino a un punto da cui lo si vede: attorno a muri e mobili
    tenendosene un po' discosto, su per le scale (un gradino per volta sì,
    un tavolo o un divano no) e per i pendii fino alla pendenza massima
    del giocatore, dritta dove si può. Dove non ha ancora visto
    è ottimista e prova. A ogni analisi ricontrolla il resto del percorso
    sulla pianta nuova e, se ora è sbarrato, ne cerca un altro; ogni 3 s lo
    rifà comunque (magari ha visto una scorciatoia); dove urta, segna e
    ricalcola. Se l'obiettivo sparisce dietro qualcosa, o il percorso gira
    lontano da lui, guarda dove va. Il percorso in corso è il tratteggio sul
    pavimento. La ricerca lavora a fette come l'analisi.
- **Passo**: verso il punto, girando attorno agli ostacoli, salendo le scale,
  mai giù da un bordo; si ferma a una distanza da cui l'oggetto si vede
  intero e lo guarda. Da una vista aerea vola e atterra dove c'è qualcosa.
- **Giro attorno agli oggetti**: raggiunto un oggetto, se il profilo lo
  chiede (*Giro attorno agli oggetti*, in gradi: Fotografo 180°, Curioso 90°)
  ci gira attorno guardandolo, dal lato più libero, per vederlo da più lati;
  se la strada si chiude torna indietro. Poi la sosta.
- **Salto**: un ostacolo basso che sbarra la strada (un muretto, una
  staccionata, un gradone) e attorno a cui non c'è un giro corto lo salta,
  se oltre c'è un piano dove atterrare. Usa la forza del salto e la gravità
  del giocatore (con quelle predefinite i piedi salgono di 1,08 m; salta ciò
  che sta sotto l'85 % di quella quota); non salta sopra sedili e tavoli.
  Si spegne nel profilo (il Lento non salta).
- **Corpo**: altezza degli occhi, raggio, gradino (al più 25 cm), salto e
  gravità sono quelli del giocatore (pannello › Giocatore), anche cambiati
  mentre esplora.
- **Fluido**: come la costruzione dal vivo del ponte, l'analisi è una Fiber
  che lavora a fette fra un fotogramma e l'altro; la retina si allarga o si
  stringe secondo quanto costa un raggio in quel modello. Con *Sistema ›
  Prestazioni › Analisi adattiva* anche la frequenza delle analisi segue il
  calcolo libero, fra un minimo e un massimo al secondo, senza rallentare il
  cammino.
- **Comandi**: Esc o clic per fermarlo, tasto destro per pausa, «Cerca
  altro», mappa dell'attenzione, occhio a colori; rotella per la velocità; I
  nasconde o mostra le righe d'informazione in alto a sinistra. Un
  altro strumento lo ferma; l'orbita col tasto centrale lo sospende e lui
  riparte da dove hai messo la camera.
- **Bloccato?** Se in 10 secondi non si sposta di 75 cm (indeciso fra
  obiettivi vicini, chiuso in un angolo), cerca una via di fuga fra 12
  direzioni e la percorre per qualche secondo; se a piedi non c'è via e il
  modo è automatico, si alza in volo.
- **Alla fine**, se all'avvio hai lasciato «Registra il percorso», il giro
  diventa un percorso («Esplorazione 1», …): dal pannello lo riguardi, lo
  fai in scene o in video.

### Profili

Il carattere dell'esploratore è un **profilo**, un insieme di coefficienti:
*Estensioni › DagaWASD › Profili dell'esploratore…*, o tasto destro mentre
esplora › *Profilo* (cambio al volo) e *Modifica i profili…*.

| Profilo | Carattere |
|---|---|
| Equilibrato | quello di sempre |
| Curioso | si annoia presto, cerca dettagli e cose rare, esplora di più, gira di 90° attorno agli oggetti |
| Corridore | 3,2 m/s, riflessi pronti, soste brevi |
| Lento | 0,5 m/s, soste lunghe, sguardo che gira piano |
| Fotografo | prima di avvicinarsi ingrandisce l'obiettivo (zoom), poi ci va e ci gira attorno di 180° |
| Spensierato | scelte a capriccio, cambia idea facilmente, ama lo spazio aperto |
| Soldato | ricognizione, sempre a piedi: 3,6 m/s, guarda da lontano e per poco, va prima dove non ha ancora visto |

Nella finestra ogni coefficiente ha un cursore (mentre lo trascini
l'esploratore, se usa quel profilo, cambia dal vivo) e un ↺ che lo riporta
al valore originale. Gruppi: movimento (velocità, distanza di sosta,
gradino, a piedi/in volo), sguardo (rotazione, riflessi, **continuità** —
quanto preferisce passare a ciò che sta accanto a quello che guarda e non
tornare su ciò da cui si è già girato), attenzione
(sosta, giro attorno agli oggetti, durata, **determinazione** — per quanti secondi non cambia idea su
un obiettivo appena scelto — e **fedeltà**), curiosità (memoria, noia,
voglia di andare, capriccio), che cosa lo attira (pesi di oggetti, sagome,
dettaglio, colore, rarità) e zoom. «Nuovo» copia il profilo in uso; i
profili già pronti si possono cambiare e poi ripristinare.

In `settings.json`: `"explore_profile"` (quello in uso),
`"explore_profiles"` (i tuoi, e le modifiche a quelli già pronti) ed
`"explore_record"` (la casella del percorso della finestra di avvio). I valori
si sommano a strati: predefiniti (`EX_DEFAULTS`, `lib/explore.rb`) ←
`"explore": { … }` ← profilo ← opzioni di chi lo avvia (il ponte).

Con il ponte acceso Claude Code lo comanda e lo osserva:

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3
ruby tools/esplora.rb avvia --profilo Fotografo    # un profilo solo per questo giro
ruby tools/esplora.rb profili                      # elenco; «profilo NOME» lo mette in uso
ruby tools/esplora.rb segui --foto esplorazione    # una riga e una foto per ogni scelta
ruby tools/esplora.rb ferma                        # salva il percorso
```

### L'IA alla guida

Con `pilota` e `guida` è Claude Code a decidere dove andare, mentre
l'esploratore continua a camminare e guardare da solo (`lib/expilot.rb`).
Ogni cosa vista ha un nome corto e stabile (`o12` un oggetto, `s7` una
faccia, `F3` una zona inesplorata); l'IA mette in agenda delle mete, e
l'esploratore le raggiunge una dopo l'altra con i suoi passi, i suoi giri
attorno ai muri e il suo sguardo. Ad agenda vuota torna a scegliere da solo:
non si ferma mai ad aspettare l'IA.

```
ruby tools/esplora.rb pilota                       # aspetta un avviso e descrive ciò che vede
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "L'altare maggiore" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # si gira a guardare, senza muoversi
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # rifà l'agenda: un punto in metri
ruby tools/esplora.rb guida --svuota               # niente agenda: torna a scegliere da solo
ruby tools/esplora.rb guida --foto                 # una foto alla sosta di adesso (o alla prossima)
ruby tools/esplora.rb guida --foto-sempre          # una foto a ogni sosta (--foto-mete: solo alle mete dell'IA, --senza-foto)
```

Gli avvisi che svegliano `pilota`: arrivato a una meta, meta fatta (o
lasciata, e perché), agenda quasi vuota o vuota, una meta che non si
raggiunge, una cosa notevole mai vista, una foto.

**A piedi: dove si arriva.** Camminando, la descrizione dice per ogni cosa
e zona inesplorata se ci si arriva (`reach`: sì, forse passando da zone
mai viste, no) e con quanti metri di strada (`walk_m`), dalla pianta che
l'esploratore si è fatto guardando. Un «vai» verso una cosa dove a piedi
non si arriva è rifiutato subito, col motivo; nelle foto quelle cose hanno
il cartellino grigio chiaro. Su Stromboli il pilota autonomo è passato da
circa una meta raggiunta al minuto a tre.

**Foto con i segni.** Alle soste davanti alle mete dell'IA l'esploratore,
fermo e con lo sguardo sulla meta, scatta un'immagine della vista (800 px)
e scrive accanto a ogni cosa visibile il suo nome corto: la meta in giallo,
gli oggetti in blu, le facce in grigio, le zone inesplorate in viola. Così
l'IA vede che cosa sono «Gruppo2577#2» e simili e li indica per nome. Le
foto stanno in `%APPDATA%\DagaWASD\pilota` (le ultime 40). Una foto blocca
SketchUp per il tempo di un'immagine della vista (mezzo secondo su un
modello grande): per questo solo da fermi.

Sul ponte: `GET /explore/percept?since=N` (descrizione e avvisi), `GET
/explore/wait?since=N&timeout=60` (la stessa descrizione, ma il ponte
risponde solo quando c'è un avviso che sveglia: `pilota` non interroga di
continuo) e `POST /explore` con `{"cmd": "steer", …}`.

**I commenti nel video.** Ciò che l'IA dice (`--commento`, `--di`, o `say`
nello steer) resta nel percorso registrato, all'istante in cui l'ha detto:
diventa la descrizione della scena più vicina quando si fanno le scene, e un
file di sottotitoli `.srt` accanto al video (AVI: lo stesso nome, i lettori
lo aprono da soli; immagini PNG: `crea_video.bat` lo mette nell'MP4).

**Pilota autonomo.** `tools/pilota_ia.rb` guida da solo, senza un comando
alla volta: aspetta gli avvisi del ponte, manda a Claude la descrizione e la
foto della sosta, e passa al ponte quello che Claude decide. Il motore
predefinito è Claude Code stesso (`claude -p`, con l'account di questo
computer: nessuna chiave); con `ANTHROPIC_API_KEY` impostata usa l'API di
Claude (gemma `anthropic`). Su Stromboli un turno dura 4–5 s. Ogni turno
consuma: `--turni` (20) e `--secondi` (300) mettono il tetto, e alla fine
stampa i token usati.

```
ruby tools/esplora.rb avvia --a-piedi
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # sforzo basso: risposte in pochi secondi
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # l'API, con la chiave
```

## Foto e galleria

Camminando, **P** (si cambia in *Sistema › Comandi*; col gamepad il dorsale destro, RB)
scatta una foto della vista, senza mirino né scritte, con un lampo. Se stai
registrando un percorso la foto va con lui; se no in una serie a parte, una
per ogni volta che entri nella modalità.

L'esploratore fotografa da sé, quando il giro diventa un percorso: le mete
più interessanti fra quelle viste fino a lì, quando lo sguardo ci si posa e
le vede abbastanza grandi (molte mete si guardano senza arrivarci) o
all'arrivo; gli spazi che si aprono ogni tanto; mai da dove ha già
fotografato, mai più di una foto ogni 8 secondi (al più 30 per giro). Di ogni
foto scrive **che cosa** c'è (la cosa, quanto è grande, quanto è lontana, che
cosa c'è intorno) e **perché** l'ha scelta: la più interessante fin lì, il
colore che spicca, niente di simile in vista, tanti dettagli, la sagoma che
si stacca dallo sfondo, un oggetto fatto di molte parti, una veduta. L'IA
che lo guida chiede le sue foto con `snap` (il suo perché) e `say` (il che
cosa).

Le foto stanno accanto al modello, in `<modello>_foto/<data e ora>/`, in JPG
da 1600 px, con `galleria.json`; il percorso tiene la cartella relativa al
modello, così la ritrova se il modello si sposta con le sue foto. Per un
modello mai salvato, o se accanto al modello non si può scrivere, vanno in
`%APPDATA%/DagaWASD/foto`.

In *Camera › Percorsi* ogni percorso ha il suo pulsante **📷**, accanto a
Video: col numero delle foto apre la galleria nel browser; spento, se il
percorso non ne ha, e un clic spiega come farne. Sotto l'elenco ci sono le
serie che nessun percorso tiene (foto fuori da una registrazione, percorsi
cancellati).

La galleria è una pagina sola, `galleria.html` nella cartella delle foto,
rifatta a ogni apertura nella lingua di SketchUp. Le foto sono Polaroid su un
tavolo di legno, che si sviluppano quando arrivano nella vista, ognuna col
foglietto degli appunti: che cosa, perché, chi l'ha scattata, una bussola
con la direzione dello sguardo e l'ora. Si guardano in due modi:

- **in fila**: scorrono di lato con la rotella, le frecce, trascinando o dal
  rullino in basso (le miniature su pellicola). In testa c'è il giro
  disegnato a matita: le foto numerate col cono di quello che guardavano, la
  scala, il nord, il verso. Una mappa piccola in un angolo segue la foto in
  corso. I commenti dell'IA stanno sui post-it al loro posto nel giro, e in
  fondo c'è la scheda con durata, strada fatta e foto;
- **sparse sul tavolo**: le foto si prendono e si spostano col mouse (o col
  dito, o con le frecce), e la disposizione resta per la volta dopo.
  *Rimettile in ordine* le rimette a righe.

Un clic apre la foto in grande, con *Presentazione* (una dopo l'altra; lo
spazio la ferma). Con foto di più autori (tu, l'esploratore, l'IA) i timbri
in testa le filtrano. `#3` nell'indirizzo porta alla foto 3, `#3z` la apre
in grande. Si stampa pulita (le foto con i loro appunti), funziona senza
rete e si può mandare a qualcuno con la sua cartella.

**Modifica** cambia i testi lì dove sono, nella stessa calligrafia: il
titolo della galleria e delle foto, *Che cosa*, *Perché*, il timbro e i
commenti dell'IA; ✕ toglie una foto dalla galleria (il file resta) e ↺ la
rimette. I testi di SketchUp non si perdono mai: ognuno può tornare
all'originale. Le modifiche si tengono subito nel browser; *Salva nella
cartella* (Edge, Chrome) le scrive in `galleria_modifiche.json` accanto alle
foto e nella pagina stessa, così viaggiano con la cartella.

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
- Le icone nascono dagli SVG in `pubblicazione/`: `tools\rendi_icone.bat`
  rifà quelle della barra (`icons/`) e quella della scheda del Warehouse
  (`pubblicazione/icona_512.png`).
- La scheda per l'Extension Warehouse (testi in inglese e note per i
  revisori) sta in `pubblicazione/extension_warehouse.md`.
- Questo README è in più lingue (`README.md` in inglese, `README.it.md`,
  `.es`, `.fr`, `.de`, `.pt`, `.nl`, `.sv`, `.pl`, `.cs`, `.ru`, `.ja`, `.ko`, `.zh`): una modifica va in tutte.
- Nel SketchUp aperto, col ponte acceso e con «Finestre e tasti» acceso nel
  pannello (strumenti per Claude Code, non installati):
  - `tools\finestre.ps1` arriva dove il Ruby non arriva: finestre native,
    avvisi, menu, cattura della vista con cielo e nuvole, tasti simulati e
    clic veri nella vista 3D (per esempio il doppio clic su una sfera);
  - `tools\collaudo.rb` prova dal vivo pulsante e menu del pannello, la
    conferma di «Elimina» e un video fino alla finestra finale;
  - `tools\schermate.rb` fa le immagini della scheda in
    `pubblicazione/schermate/` (1920×1080 con uno schermo almeno così);
  - `tools\prova_fps.rb` cammina e corre in modalità FPS e misura
    l'oscillazione della testa.

## Licenza

[MIT](LICENSE) © 2026 Dagadam. Puoi usare, modificare e ridistribuire il codice
liberamente, anche a fini commerciali, purché ogni copia mantenga la nota di
copyright e il testo della licenza.
