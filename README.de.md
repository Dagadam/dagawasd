# DagaWASD

[English](README.md) · [Italiano](README.it.md) · [Español](README.es.md) · [Français](README.fr.md) · **Deutsch** · [Português](README.pt.md) · [Nederlands](README.nl.md) · [Svenska](README.sv.md) · [Polski](README.pl.md) · [Čeština](README.cs.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [中文](README.zh.md)

Erweiterung für SketchUp (Windows): Gehe in der Ich-Perspektive durch dein
Modell, mit WASD und Maus oder mit einem Gamepad.

▶ Offizielle Präsentation: https://youtu.be/8eBvtl7DiKU

⬇ **Download**: [neueste Version](https://github.com/Dagadam/dagawasd/releases/latest) (alle Versionen: [Releases](https://github.com/Dagadam/dagawasd/releases))

## Was sie kann

- **Gehen**: Trägheit, Rennen, Ducken, Springen, Treppen und Rampen, und
  sichere Rückkehr auf den Boden, wenn du ins Leere fällst.
- **Objektphysik**: Gruppen und Komponenten fallen, prallen ab und kippen um,
  je nach Material; man kann sie treten, greifen und werfen.
- **Himmel und Wetter**: Sonne, Mond und Sterne nach Datum, Uhrzeit und Ort;
  Regen, Schnee, Wolken, Gewitter, Schnee, der am Boden liegen bleibt.
  Fertige Wetterlagen und wechselhaftes Wetter, das sich mit der Himmelszeit
  von selbst ändert. Das Wetter erscheint auch in exportierten Videos.
- **Pfade**: Zeichne die Kamera beim Gehen auf, spiele sie ab, exportiere sie
  als Szenen oder als AVI-Video. Verfeinere sie im Modell, indem du ihre
  Positionen verschiebst und drehst (Kugeln mit einem Pfeil so lang wie der
  Zoom, und der Bildrahmen), oder baue einen von Grund auf. Im Panel öffnet
  sich jeder Pfad mit der Liste seiner Positionen; ein Klick auf eine
  Position, oder ein Doppelklick auf ihre Kugel (oder Enter), öffnet ihre
  Einstellungen mit einer Vorschau dessen, was sie sieht, und ein Klick
  zwischen zwei Positionen fügt eine aus der aktuellen Ansicht hinzu. Beim
  Abspielen hebt die Liste die aktuelle Position hervor. „Kameras
  ausdünnen“ fasst übereinander gehäufte Kugeln zu einer zusammen, ihrem
  Mittel (Position, Blick, Zoom), sofern sie nicht mehr als 45°
  auseinanderblicken.
- **Autonomer Erkunder**: Die Kamera betrachtet die Szene, wählt das
  Bedeutsamste aus, macht einen Schritt darauf zu, während sie es ansieht,
  und beginnt von vorn; am Ende ist der Rundgang ein Pfad. Siehe unten.
- **Fotos und Galerie**: P macht ein Foto von dem, was du siehst; der
  Erkunder fotografiert selbst die interessantesten Dinge seines Rundgangs.
  Jeder Pfad öffnet seine Galerie im Browser: Sofortbilder auf einem Tisch,
  mit Notizen. Siehe unten.
- XInput-**Gamepad**, und Umschauen mit dem Ziffernblock.
- Einstellungs-Panel in 36 Sprachen.
- **Barrierefreiheit**: *Barrierefreiheit › Keine Blitze* schaltet jeden
  Blitz ab, von Fotos und von Gewittern (siehe
  [ACCESSIBILITY.md](.github/ACCESSIBILITY.md)).

Voraussetzungen: SketchUp 2023 oder neuer, unter Windows. Auf dem Mac lässt
sich die Erweiterung installieren, startet aber nicht, und sagt das auch.

## Installation

- Über das **Extension Warehouse** von SketchUp (signierte Version), oder
- lade **`dagawasd-<Version>-warehouse.rbz`** aus der
  [neuesten Version](https://github.com/Dagadam/dagawasd/releases/latest) herunter (unter *Assets*) und installiere
  sie über *Erweiterungen › Extension Manager › Erweiterung installieren*.
  Die andere Datei, `dagawasd-<Version>.rbz`, enthält zusätzlich die Brücke
  für Claude Code (siehe *Zwei Pakete*).

Die Einstellungen liegen in `%APPDATA%\DagaWASD\settings.json`: Ein Update
löscht sie nicht.

## Autonomer Erkunder

Augen-Knopf in der Leiste (oder *Erweiterungen › DagaWASD › Autonomer
Erkunder*): Ein kleines Fenster lässt dich das Profil wählen (seinen
Charakter, siehe unten) und ob der Rundgang als Pfad aufgezeichnet wird, und
merkt sich deine Wahl für das nächste Mal; Pfeile und Enter, oder ein
Doppelklick auf ein Profil, um sofort loszulegen. Derselbe Knopf hält ihn
an, während er erkundet. Der Ablauf: **analysieren → Punkt wählen → einen
Schritt auf den Punkt zu, ihn dabei ansehen → analysieren**.

- **Analyse**: Eine Netzhaut aus Strahlen durch das Raster des Bildschirms
  (`view.pickray` + `model.raytest`) liefert für jede Zelle Entfernung,
  Normale, Fläche, Objekt und Farbe. Daraus die Auffälligkeit:
  Tiefenkanten, Kanten, Detail, Farbkontrast (Lab), Seltenheit, Komponenten
  und Gruppen in Menschengröße; große Wände und Böden zählen wenig. Gewichtet
  nach Entfernung, Bildmitte und Neuheit.
- **Gedächtnis**: Voxel dessen, was der Blick schon gesehen hat, schon
  betretene Orte (im Grundriss und in der Höhe: das Stockwerk darüber bleibt
  neu), Langeweile pro Ziel und pro Kategorie (hat er ein Sofa gesehen,
  reizen ihn gleiche weniger): So kehrt er nicht immer zu denselben Dingen
  zurück.
- **Karte des Gesehenen**: Zu Fuß markieren die Strahlen, die auf
  Körperhöhe verlaufen, auf einer Karte mit 50-cm-Zellen (eine pro Stockwerk)
  den gesehenen Boden mit seiner Höhe (Boden, Stufen, Möbelflächen) und die
  getroffenen Wände. Sie dient zwei Dingen:
  - **Grenzen**: Der Rand zwischen dem, was er gesehen hat, und dem, was er
    nie gesehen hat (hinter einer Tür, um eine Ecke), wird zu einem Ziel,
    einem „unerkundeten Bereich“: Er geht hin und schaut hinein. Er wiegt wie
    offener Raum, je nach Bewegungsdrang des Profils; in der
    Aufmerksamkeitskarte sind es die violetten Quadrate auf dem Boden;
  - **geplante Wege**: Für jedes Ziel plant er den Weg auf der Karte (A*) bis
    zu einem Punkt, von dem aus es zu sehen ist: um Wände und Möbel herum,
    mit etwas Abstand, Treppen hinauf (eine Stufe nach der anderen ja, ein
    Tisch oder ein Sofa nein) und Rampen bis zur maximalen Steigung des
    Spielers, geradeaus, wo es geht. Wo er noch nicht hingeschaut hat, ist
    er optimistisch und versucht es. Bei jeder Analyse prüft er den Rest des
    Weges auf der neuen Karte und sucht, falls er jetzt versperrt ist, einen
    anderen; alle 3 s plant er ohnehin neu (vielleicht hat er eine Abkürzung
    gesehen); wo er anstößt, markiert er es und rechnet neu. Verschwindet
    das Ziel hinter etwas, oder führt der Weg von ihm weg, schaut er, wohin
    er geht. Der aktuelle Weg ist die gestrichelte Linie auf dem Boden. Die
    Suche arbeitet in Scheiben, wie die Analyse.
- **Schritt**: auf den Punkt zu, um Hindernisse herum, Treppen hinauf, nie
  über eine Kante hinab; er hält in einer Entfernung an, aus der das Objekt
  ganz zu sehen ist, und sieht es an. Aus einer Luftansicht fliegt er und
  landet dort, wo es etwas zu sehen gibt.
- **Um Objekte herumgehen**: Hat er ein Objekt erreicht und verlangt das
  Profil es (*Geht um Objekte herum*, in Grad: Fotograf 180°, Neugierig
  90°), geht er darum herum und sieht es an, auf der freieren Seite, um es
  von mehreren Seiten zu sehen; schließt sich der Weg, kehrt er um. Dann die
  Pause.
- **Springen**: Ein niedriges Hindernis, das den Weg versperrt (ein
  Mäuerchen, ein Zaun, eine große Stufe) und um das es keinen kurzen Umweg
  gibt, überspringt er, wenn dahinter eine Fläche zum Landen ist. Er nutzt
  Sprungkraft und Schwerkraft des Spielers (mit den Standardwerten heben
  sich die Füße um 1,08 m; er überspringt, was unter 85 % dieser Höhe
  liegt); auf Sitze und Tische springt er nie. Im Profil abschaltbar
  (Langsam springt nicht).
- **Körper**: Augenhöhe, Radius, Stufe (höchstens 25 cm), Sprung und
  Schwerkraft sind die des Spielers (Panel › Spieler), auch wenn sie während
  der Erkundung geändert werden.
- **Flüssig**: Wie der Live-Aufbau der Brücke ist die Analyse eine Fiber,
  die in Scheiben zwischen zwei Bildern arbeitet; die Netzhaut wird dichter
  oder lichter, je nachdem, was ein Strahl in diesem Modell kostet. Mit
  *System › Leistung › Adaptive Analyse* folgt auch die Häufigkeit der
  Analysen der freien Rechenleistung, zwischen einem Minimum und einem
  Maximum pro Sekunde, ohne das Gehen zu bremsen.
- **Steuerung**: Esc oder Klick zum Anhalten, Rechtsklick für Pause, „Etwas
  anderes suchen“, Aufmerksamkeitskarte, Farbauge; Mausrad für die
  Geschwindigkeit; I blendet die Infozeilen oben links aus oder ein. Ein
  anderes Werkzeug hält ihn an; Orbit mit der mittleren Maustaste setzt ihn
  aus, und er macht dort weiter, wo du die Kamera hingesetzt hast.
- **Festgefahren?** Bewegt er sich in 10 Sekunden nicht um 75 cm (unschlüssig
  zwischen nahen Zielen, in einer Ecke gefangen), sucht er unter 12
  Richtungen einen Fluchtweg und folgt ihm einige Sekunden; gibt es zu Fuß
  keinen Weg und ist der Modus automatisch, hebt er ab.
- **Am Ende**, wenn du beim Start „Weg aufzeichnen“ angehakt gelassen hast,
  wird der Rundgang zu einem Pfad („Erkundung 1“, …): Im Panel siehst du ihn
  dir wieder an oder machst Szenen oder ein Video daraus.

### Profile

Der Charakter des Erkunders ist ein **Profil**, ein Satz von Koeffizienten:
*Erweiterungen › DagaWASD › Profile des Erkunders…*, oder Rechtsklick
während der Erkundung › *Profil* (Wechsel im Flug) und *Profile
bearbeiten…*.

| Profil | Charakter |
|---|---|
| Ausgewogen | der gewohnte |
| Neugierig | langweilt sich schnell, sucht Details und Seltenes, erkundet mehr, geht 90° um Objekte herum |
| Läufer | 3,2 m/s, schnelle Reflexe, kurze Pausen |
| Langsam | 0,5 m/s, lange Pausen, ein Blick, der sich langsam dreht |
| Fotograf | zoomt vor dem Näherkommen auf das Ziel, geht dann hin und 180° darum herum |
| Unbeschwert | launische Entscheidungen, ändert leicht seine Meinung, liebt offenen Raum |
| Soldat | Aufklärung, immer zu Fuß: 3,6 m/s, schaut aus der Ferne und kurz, geht zuerst dorthin, wo er noch nicht hingesehen hat |

Im Fenster hat jeder Koeffizient einen Schieberegler (während du ihn ziehst,
ändert sich der Erkunder live, wenn er dieses Profil nutzt) und ein ↺, das
den ursprünglichen Wert wiederherstellt. Gruppen: Bewegung
(Geschwindigkeit, Haltedistanz, Stufe, zu Fuß/fliegend), Blick (Drehung,
Reflexe, **Fluss** — wie sehr er lieber zu dem wechselt, was neben dem
Angesehenen liegt, statt zu dem zurückzukehren, von dem er sich schon
abgewandt hat), Aufmerksamkeit (Pause, um Objekte herumgehen, Dauer,
**Entschlossenheit** — wie viele Sekunden er seine Meinung über ein gerade
gewähltes Ziel nicht ändert — und **Treue**), Neugier (Gedächtnis,
Langeweile, Bewegungsdrang, Laune), was ihn anzieht (Gewichte von Objekten,
Silhouetten, Detail, Farbe, Seltenheit) und Zoom. „Neu“ kopiert das
aktuelle Profil; die fertigen Profile lassen sich ändern und dann
wiederherstellen.

In `settings.json`: `"explore_profile"` (das aktive),
`"explore_profiles"` (deine eigenen und Änderungen an den fertigen) und
`"explore_record"` (das Pfad-Kästchen im Startfenster). Die Werte werden in
Schichten zusammengesetzt: Standardwerte (`EX_DEFAULTS`,
`lib/explore.rb`) ← `"explore": { … }` ← Profil ← Optionen dessen, der ihn
startet (die Brücke).

Bei eingeschalteter Brücke steuert und beobachtet ihn Claude Code (die
Befehle der Entwicklerwerkzeuge sind auf Italienisch):

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # starten: 120 s, 1,3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # ein Profil nur für diesen Rundgang
ruby tools/esplora.rb profili                      # Liste; „profilo NAME“ macht es aktiv
ruby tools/esplora.rb segui --foto esplorazione    # eine Zeile und ein Foto pro Entscheidung
ruby tools/esplora.rb ferma                        # anhalten und den Pfad speichern
```

### Die KI am Steuer

Mit `pilota` und `guida` entscheidet Claude Code, wohin es geht, während der
Erkunder selbst weitergeht und schaut (`lib/expilot.rb`). Jedes gesehene
Ding hat einen kurzen, festen Namen (`o12` ein Objekt, `s7` eine Fläche,
`F3` ein unerkundeter Bereich); die KI setzt Ziele auf eine Agenda, und der
Erkunder erreicht sie eines nach dem anderen mit seinen eigenen Schritten,
seinen Umwegen um Wände und seinem Blick. Bei leerer Agenda wählt er wieder
selbst: Er bleibt nie stehen, um auf die KI zu warten.

```
ruby tools/esplora.rb pilota                       # wartet auf ein Ereignis und beschreibt, was er sieht
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "Der Hochaltar" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # dreht sich zum Schauen, ohne sich zu bewegen
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # neue Agenda: ein Punkt in Metern
ruby tools/esplora.rb guida --svuota               # keine Agenda: wählt wieder selbst
ruby tools/esplora.rb guida --foto                 # ein Foto bei der aktuellen Pause (oder der nächsten)
ruby tools/esplora.rb guida --foto-sempre          # ein Foto bei jeder Pause (--foto-mete: nur bei den Zielen der KI, --senza-foto)
```

Die Ereignisse, die `pilota` wecken: Ziel erreicht, Ziel erledigt (oder
aufgegeben, und warum), Agenda fast leer oder leer, ein unerreichbares Ziel,
etwas Bemerkenswertes, nie Gesehenes, ein Foto.

**Zu Fuß: wohin man kommt.** Beim Gehen sagt die Beschreibung für jedes Ding
und jeden unerkundeten Bereich, ob man hinkommt (`reach`: ja, vielleicht
über nie gesehene Bereiche, nein) und mit wie vielen Metern Weg (`walk_m`),
nach der Karte, die sich der Erkunder beim Schauen gemacht hat. Ein „geh“ zu
etwas, das zu Fuß nicht erreichbar ist, wird sofort abgelehnt, mit Grund;
auf den Fotos tragen diese Dinge ein hellgraues Schild. Auf Stromboli stieg
der autonome Pilot von etwa einem erreichten Ziel pro Minute auf drei.

**Beschriftete Fotos.** Bei den Pausen vor den Zielen der KI macht der
Erkunder, stillstehend und mit dem Blick auf dem Ziel, ein Bild der Ansicht
(800 px) und schreibt neben jedes sichtbare Ding seinen kurzen Namen: das
Ziel in Gelb, Objekte in Blau, Flächen in Grau, unerkundete Bereiche in
Violett. So sieht die KI, was „Gruppe2577#2“ und dergleichen sind, und nennt
sie beim Namen. Die Fotos liegen in `%APPDATA%\DagaWASD\pilota` (die letzten
40). Ein Foto blockiert SketchUp für die Dauer eines Ansichtsbildes (eine
halbe Sekunde bei einem großen Modell): deshalb nur im Stillstand.

Auf der Brücke: `GET /explore/percept?since=N` (Beschreibung und
Ereignisse), `GET /explore/wait?since=N&timeout=60` (dieselbe Beschreibung,
aber die Brücke antwortet erst, wenn ein weckendes Ereignis vorliegt:
`pilota` fragt nicht ständig nach) und `POST /explore` mit `{"cmd":
"steer", …}`.

**Die Kommentare im Video.** Was die KI sagt (`--commento`, `--di` oder
`say` im Steer), bleibt im aufgezeichneten Pfad, zu dem Zeitpunkt, an dem
sie es gesagt hat: Es wird zur Beschreibung der nächstgelegenen Szene, wenn
man Szenen erstellt, und zu einer Untertiteldatei `.srt` neben dem Video
(AVI: gleicher Name, Player öffnen sie von selbst; PNG-Bilder:
`crea_video.bat` bettet sie ins MP4 ein).

**Autonomer Pilot.** `tools/pilota_ia.rb` steuert selbstständig, ohne
Einzelbefehle: Er wartet auf die Ereignisse der Brücke, schickt Claude die
Beschreibung und das Foto der Pause und gibt an die Brücke weiter, was
Claude entscheidet. Der Standard-Motor ist Claude Code selbst (`claude -p`,
mit dem Konto dieses Computers: kein Schlüssel); ist `ANTHROPIC_API_KEY`
gesetzt, nutzt er die Claude-API (Gem `anthropic`). Auf Stromboli dauert ein
Zug 4–5 s. Jeder Zug kostet: `--turni` (20) und `--secondi` (300) setzen die
Grenze, und am Ende gibt er die verbrauchten Tokens aus.

```
ruby tools/esplora.rb avvia --a-piedi                   # starten, zu Fuß
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # geringer Aufwand: Antworten in wenigen Sekunden
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # die API, mit dem Schlüssel
```

## Fotos und Galerie

Beim Gehen macht **P** (änderbar unter *System › Steuerung*; am Gamepad die
rechte Schultertaste, RB) ein Foto der Ansicht, ohne Fadenkreuz oder Text,
mit einem Blitz. Zeichnest du gerade einen Pfad auf, gehört das Foto zu ihm;
sonst kommt es in eine eigene Serie, eine für jedes Mal, wenn du den Modus
betrittst.

Der Erkunder fotografiert selbst, wenn der Rundgang zu einem Pfad wird: die
interessantesten Ziele unter den bis dahin gesehenen, wenn sein Blick darauf
ruht und sie groß genug sieht (viele Ziele werden angesehen, ohne dass er
hingeht) oder bei der Ankunft; Räume, die sich ab und zu öffnen; nie von
dort, wo er schon fotografiert hat, nie mehr als ein Foto alle 8 Sekunden
(höchstens 30 pro Rundgang). Zu jedem Foto schreibt er, **was** darauf ist
(das Ding, wie groß, wie weit entfernt, was darum herum ist) und **warum**
er es gewählt hat: das bisher interessanteste, die Farbe, die heraussticht,
nichts Ähnliches in Sicht, viele Details, die Silhouette, die sich vom
Hintergrund abhebt, ein Objekt aus vielen Teilen, ein Ausblick. Die KI, die
ihn steuert, verlangt ihre eigenen Fotos mit `snap` (ihr Warum) und `say`
(das Was).

Die Fotos liegen neben dem Modell, in `<Modell>_foto/<Datum und Uhrzeit>/`,
als JPG mit 1600 px, mit `galleria.json`; der Pfad speichert den Ordner
relativ zum Modell und findet ihn so wieder, wenn das Modell mit seinen
Fotos umzieht. Bei einem nie gespeicherten Modell, oder wenn neben dem
Modell nicht geschrieben werden kann, landen sie in
`%APPDATA%/DagaWASD/foto`.

Unter *Kamera › Pfade* hat jeder Pfad seinen **📷**-Knopf neben Video: Mit
der Anzahl der Fotos öffnet er die Galerie im Browser; ausgegraut, wenn der
Pfad keine hat, und ein Klick erklärt, wie man welche macht. Unter der Liste
stehen die Serien, die zu keinem Pfad gehören (Fotos außerhalb einer
Aufzeichnung, gelöschte Pfade).

Die Galerie ist eine einzige Seite, `galleria.html` im Fotoordner, bei jedem
Öffnen neu erstellt, in der Sprache von SketchUp. Die Fotos sind
Sofortbilder auf einem Holztisch, die sich entwickeln, wenn sie ins Bild
kommen, jedes mit seinem Notizzettel: was, warum, wer es aufgenommen hat,
ein Kompass mit der Blickrichtung und die Uhrzeit. Man sieht sie auf zwei
Arten:

- **in einer Reihe**: Sie scrollen seitwärts mit dem Mausrad, den Pfeilen,
  durch Ziehen oder über den Filmstreifen unten (die Miniaturen). Oben ist
  der Rundgang mit Bleistift gezeichnet: die nummerierten Fotos mit dem
  Kegel dessen, was sie ansahen, der Maßstab, Norden, die Richtung. Eine
  kleine Karte in einer Ecke folgt dem aktuellen Foto. Die Kommentare der KI
  stehen auf Haftnotizen an ihrer Stelle im Rundgang, und am Ende gibt es die
  Karte mit Dauer, zurückgelegtem Weg und Fotos;
- **auf dem Tisch verstreut**: Man nimmt die Fotos und verschiebt sie mit der
  Maus (oder dem Finger, oder den Pfeilen), und die Anordnung bleibt für das
  nächste Mal erhalten. *Wieder ordnen* legt sie zurück in Reihen.

Ein Klick öffnet das Foto groß, mit *Diashow* (eines nach dem anderen; die
Leertaste hält sie an). Bei Fotos mehrerer Urheber (du, der Erkunder, die
KI) filtern die Stempel oben. `#3` in der Adresse führt zu Foto 3, `#3z`
öffnet es groß. Sie lässt sich sauber drucken (die Fotos mit ihren
Notizen), funktioniert offline und lässt sich mitsamt ihrem Ordner
weitergeben.

**Bearbeiten** ändert die Texte direkt dort, wo sie stehen, in derselben
Handschrift: den Titel der Galerie und jedes Fotos, *Was*, *Warum*, den
Stempel und die Notizen der KI; ✕ nimmt ein Foto aus der Galerie (die Datei
bleibt) und ↺ legt es zurück. Die Texte von SketchUp gehen nie verloren:
Jeder kann zum Original zurück. Änderungen bleiben sofort im Browser; *Im
Ordner speichern* (Edge, Chrome) schreibt sie in `galleria_modifiche.json`
neben den Fotos und in die Seite selbst, so reisen sie mit dem Ordner.

## Zwei Pakete

`tools\crea_rbz.bat` erstellt in `dist\`:

- `dagawasd-<Version>.rbz`: vollständig, mit der **Brücke für Claude Code**
  (`lib/bridge.rb`), einem rein lokalen Server, ausgeschaltet, bis du ihn im
  Panel einschaltest, über den Claude Code im geöffneten Modell zeichnet;
- `dagawasd-<Version>-warehouse.rbz`: ohne die Brücke, für das Extension
  Warehouse. Ohne `lib/bridge.rb` funktioniert die Erweiterung genauso.

## Entwicklung

Der Code, seine Kommentare und das Änderungsprotokoll sind auf Italienisch.

- `installa.bat` kopiert den Quellcode in den Plugins-Ordner jedes
  gefundenen SketchUp.
- `tests\run_tests.bat` startet die Tests (Ruby, mit simuliertem SketchUp;
  das Panel in einem simulierten Browser mit Node).
- `tools\controlla_warehouse.bat` prüft das Paket nach den Regeln von
  Trimble (rubocop-sketchup).
- Die Versionsnummer steht nur in `dagawasd.rb` (`VERSION`); jede Version hat
  ihren Abschnitt in `CHANGELOG.md`.
- Die Icons entstehen aus den SVGs in `pubblicazione/`:
  `tools\rendi_icone.bat` erstellt die der Leiste (`icons/`) und das der
  Warehouse-Seite (`pubblicazione/icona_512.png`) neu.
- Die Seite für das Extension Warehouse (Texte auf Englisch und Hinweise für
  die Prüfer) liegt in `pubblicazione/extension_warehouse.md`.
- Dieses README gibt es in mehreren Sprachen (`README.md` auf Englisch,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.nl`, `.sv`, `.pl`, `.cs`, `.ru`, `.ja`, `.ko`, `.zh`): Eine Änderung gehört in alle.
- Im laufenden SketchUp, mit eingeschalteter Brücke und „Fenster und
  Tasten“ im Panel aktiviert (Werkzeuge für Claude Code, nicht installiert):
  - `tools\finestre.ps1` reicht dorthin, wo Ruby nicht hinkommt: native
    Fenster, Meldungen, Menüs, Aufnahme der Ansicht mit Himmel und Wolken,
    simulierte Tasten und echte Klicks in der 3D-Ansicht (zum Beispiel der
    Doppelklick auf eine Kugel);
  - `tools\collaudo.rb` testet live Knopf und Menü des Panels, die
    Bestätigung von „Löschen“ und ein Video bis zum Abschlussfenster;
  - `tools\schermate.rb` erstellt die Bilder der Seite in
    `pubblicazione/schermate/` (1920×1080, mit einem mindestens so großen
    Bildschirm);
  - `tools\prova_fps.rb` geht und rennt im FPS-Modus und misst das Wippen
    des Kopfes.

## Kontakt

Schreib an [DagaWASD@icloud.com](mailto:DagaWASD@icloud.com). Fehler und Ideen besser als
[Issue](https://github.com/Dagadam/dagawasd/issues) melden, wo andere sie sehen und verfolgen können;
Sicherheitsprobleme bitte über die [Sicherheitsrichtlinie](.github/SECURITY.md).

Wenn dir DagaWASD nützt, kannst du seine Entwicklung auf [Ko-fi](https://ko-fi.com/dagadam) unterstützen.

## Lizenz

[MIT](LICENSE) © 2026 Dagadam. Du darfst den Code frei verwenden, ändern und
weitergeben, auch kommerziell, solange jede Kopie den Copyright-Hinweis und
den Lizenztext enthält.
