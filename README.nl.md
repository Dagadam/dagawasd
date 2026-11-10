# DagaWASD

[English](README.md) · [Italiano](README.it.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · **Nederlands** · [Svenska](README.sv.md) · [Polski](README.pl.md) · [Čeština](README.cs.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [中文](README.zh.md)

Extensie voor SketchUp (Windows): loop in de eerste persoon door je model
met WASD en de muis, of met een gamepad.

▶ Demovideo: https://youtu.be/w6xE86y7iEw?is=7Gh12tF7atE_N9_K

⬇ **Downloaden**: [nieuwste versie](https://github.com/Dagadam/dagawasd/releases/latest) (alle versies: [Releases](https://github.com/Dagadam/dagawasd/releases))

## Wat het doet

- **Lopen**: traagheid, rennen, hurken, springen, trappen en hellingen, en
  een veilige terugkeer naar de grond als je in het niets valt.
- **Objectfysica**: groepen en componenten vallen, stuiteren en kantelen
  volgens hun materiaal; je kunt ze schoppen, pakken en gooien.
- **Lucht en weer**: zon, maan en sterren volgens datum, tijd en plaats;
  regen, sneeuw, wolken, onweer, sneeuw die op de grond blijft liggen.
  Kant-en-klare situaties, en wisselvallig weer dat vanzelf verandert met de
  hemeltijd. Het weer komt ook in geëxporteerde video's.
- **Routes**: neem de camera op terwijl je loopt, speel hem af, exporteer
  hem als scènes of als AVI-video. Stel hem in het model bij door de
  posities te verplaatsen en te draaien (bollen met een pijl zo lang als de
  zoom, en het kader van de opname), of bouw er een vanaf nul. In het paneel
  opent elke route de lijst van zijn posities; een klik op een positie, of
  een dubbelklik op de bol (of Enter), opent de instellingen met een
  voorbeeld van wat hij ziet, en een klik tussen twee posities voegt er een
  toe vanuit de huidige weergave. Tijdens het afspelen licht de lijst de
  huidige positie op. «Camera's uitdunnen» voegt bollen die op elkaar
  gestapeld liggen samen tot één, hun gemiddelde (positie, blik, zoom),
  zolang ze niet meer dan 45° van elkaar af kijken.
- **Autonome verkenner**: de camera bekijkt de scène, kiest het meest
  betekenisvolle, zet er een stap naartoe terwijl hij ernaar kijkt, en
  begint opnieuw; aan het eind is de wandeling een route. Zie hieronder.
- **Foto's en galerij**: P maakt een foto van wat je ziet; de verkenner
  fotografeert zelf de interessantste dingen van zijn wandeling. Elke route
  opent zijn galerij in de browser: polaroids op een tafel, met notities.
  Zie hieronder.
- XInput-**gamepad**, en rondkijken met het numerieke toetsenblok.
- Instellingenpaneel in 36 talen.
- **Toegankelijkheid**: *Toegankelijkheid › Geen flitsen* zet elke flits
  uit, van foto's en van bliksem (zie
  [ACCESSIBILITY.md](.github/ACCESSIBILITY.md)).

Vereisten: SketchUp 2023 of later, op Windows. Op een Mac installeert de
extensie wel, maar start niet, en meldt dat.

## Installatie

- Via het **Extension Warehouse** van SketchUp (ondertekende versie), of
- download **`dagawasd-<versie>-warehouse.rbz`** uit de
  [nieuwste versie](https://github.com/Dagadam/dagawasd/releases/latest) (onder *Assets*) en installeer
  het via *Extensies › Extension Manager › Extensie installeren*. Het
  andere bestand, `dagawasd-<versie>.rbz`, bevat ook de brug voor Claude
  Code (zie *Twee pakketten*).

De instellingen staan in `%APPDATA%\DagaWASD\settings.json`: een update
wist ze niet.

## Autonome verkenner

Oogknop in de werkbalk (of *Extensies › DagaWASD › Autonome verkenner*):
een klein venster laat je het profiel kiezen (zijn karakter, zie
hieronder) en of de wandeling als route wordt opgenomen, en onthoudt je
keuzes voor de volgende keer; pijltjes en Enter, of een dubbelklik op een
profiel, om meteen te vertrekken. Dezelfde knop stopt hem tijdens het
verkennen. De cyclus: **analyseren → punt kiezen → een stap naar het punt,
terwijl hij ernaar kijkt → analyseren**.

- **Analyse**: een netvlies van stralen door het raster van het scherm
  (`view.pickray` + `model.raytest`) geeft voor elke cel afstand, normaal,
  vlak, object en kleur. Daaruit de opvallendheid: diepteranden, randen,
  detail, kleurcontrast (Lab), zeldzaamheid, componenten en groepen op
  menselijke maat; grote muren en vloeren tellen weinig. Gewogen naar
  afstand, midden van het beeld en nieuwheid.
- **Geheugen**: voxels van wat de blik al heeft gezien, plekken waar hij al
  heeft gelopen (in plattegrond en hoogte: de verdieping erboven blijft
  nieuw), verveling per doel en per categorie (één bank gezien, dan zijn
  gelijke banken minder boeiend): zo keert hij niet steeds naar dezelfde
  dingen terug.
- **Kaart van wat hij heeft gezien**: te voet markeren de stralen op
  lichaamshoogte op een kaart met cellen van 50 cm (één per verdieping) de
  geziene vloer met zijn hoogte (vloer, treden, bladen van meubels) en de
  geraakte muren. Dat dient twee doelen:
  - **grenzen**: de rand tussen wat hij heeft gezien en wat hij nooit heeft
    gezien (achter een deur, om een hoek) wordt een doel, een «onverkend
    gebied»: hij gaat erheen en kijkt naar binnen. Het weegt als open ruimte,
    volgens de zin om te gaan van het profiel; op de aandachtskaart zijn het
    de paarse vierkantjes op de vloer;
  - **geplande routes**: voor elk doel plant hij de weg op de kaart (A*) naar
    een punt van waaruit het te zien is: om muren en meubels heen, met wat
    afstand, trappen op (één trede tegelijk wel, een tafel of bank niet) en
    hellingen tot de maximale helling van de speler, rechtdoor waar het kan.
    Waar hij nog niet heeft gekeken is hij optimistisch en probeert hij het.
    Bij elke analyse controleert hij de rest van de route op de nieuwe kaart
    en zoekt, als die nu versperd is, een andere; elke 3 s plant hij
    sowieso opnieuw (misschien heeft hij een kortere weg gezien); waar hij
    botst, markeert hij dat en rekent hij opnieuw. Verdwijnt het doel achter
    iets, of buigt de route ervan af, dan kijkt hij waar hij heen gaat. De
    huidige route is de stippellijn op de vloer. Het zoeken werkt in plakjes,
    net als de analyse.
- **Stap**: naar het punt, om obstakels heen, trappen op, nooit van een
  rand af; hij stopt op een afstand waarop het object helemaal te zien is,
  en kijkt ernaar. Vanuit een luchtbeeld vliegt hij en landt hij waar iets te
  zien is.
- **Om objecten heen lopen**: bij een object aangekomen loopt hij er, als
  het profiel dat vraagt (*Loopt om objecten heen*, in graden: Fotograaf
  180°, Nieuwsgierig 90°), omheen terwijl hij ernaar kijkt, langs de vrijste
  kant, om het van meerdere kanten te zien; als de weg dichtgaat keert hij
  om. Daarna de pauze.
- **Springen**: een laag obstakel dat de weg verspert (een muurtje, een hek,
  een grote trede) zonder korte omweg springt hij over, als er erachter een
  vlak is om op te landen. Hij gebruikt de sprongkracht en zwaartekracht
  van de speler (met de standaardwaarden gaan de voeten 1,08 m omhoog; hij
  springt over wat lager is dan 85 % daarvan); hij springt nooit op stoelen
  en tafels. Uit te zetten in het profiel (Traag springt niet).
- **Lichaam**: ooghoogte, straal, trede (hooguit 25 cm), sprong en
  zwaartekracht zijn die van de speler (paneel › Speler), ook als ze tijdens
  het verkennen worden gewijzigd.
- **Vloeiend**: net als de live-opbouw van de brug is de analyse een Fiber
  die in plakjes werkt tussen het ene beeld en het volgende; het netvlies
  wordt dichter of ijler naargelang wat een straal in dat model kost. Met
  *Systeem › Prestaties › Adaptieve analyse* volgt ook de frequentie van de
  analyses de vrije rekenkracht, tussen een minimum en een maximum per
  seconde, zonder het lopen te vertragen.
- **Besturing**: Esc of een klik om hem te stoppen, rechtermuisknop voor
  pauze, «Iets anders zoeken», aandachtskaart, kleurenoog; scrollwiel voor
  de snelheid; I verbergt of toont de informatieregels linksboven. Een ander
  gereedschap stopt hem; orbiten met de middelste knop pauzeert hem, en hij
  gaat verder vanaf waar je de camera hebt neergezet.
- **Vast?** Als hij in 10 seconden geen 75 cm verplaatst (twijfelend tussen
  nabije doelen, opgesloten in een hoek), zoekt hij een uitweg in 12
  richtingen en volgt die een paar seconden; is er te voet geen weg en staat
  de modus op automatisch, dan stijgt hij op.
- **Aan het eind**, als je bij de start «Route opnemen» aangevinkt liet,
  wordt de wandeling een route («Verkenning 1», …): vanuit het paneel bekijk
  je hem opnieuw, of maak je er scènes of een video van.

### Profielen

Het karakter van de verkenner is een **profiel**, een set coëfficiënten:
*Extensies › DagaWASD › Profielen van de verkenner…*, of rechtsklik tijdens
het verkennen › *Profiel* (direct wisselen) en *Profielen bewerken…*.

| Profiel | Karakter |
|---|---|
| Evenwichtig | de vertrouwde |
| Nieuwsgierig | verveelt zich snel, zoekt details en zeldzame dingen, verkent meer, loopt 90° om objecten heen |
| Renner | 3,2 m/s, snelle reflexen, korte pauzes |
| Traag | 0,5 m/s, lange pauzes, een blik die langzaam draait |
| Fotograaf | zoomt in op het doel voordat hij nadert, gaat er dan heen en loopt er 180° omheen |
| Zorgeloos | grillige keuzes, verandert makkelijk van gedachten, houdt van open ruimte |
| Soldaat | verkenning, altijd te voet: 3,6 m/s, kijkt van ver en kort, gaat eerst waar hij nog niet heeft gekeken |

In het venster heeft elke coëfficiënt een schuifregelaar (terwijl je
sleept verandert de verkenner live, als hij dat profiel gebruikt) en een ↺
die de oorspronkelijke waarde terugzet. Groepen: beweging (snelheid,
stopafstand, trede, te voet/vliegend), blik (draaien, reflexen,
**continuïteit** — hoe graag hij overgaat naar wat naast het bekekene ligt,
zonder terug te keren naar waar hij zich al van heeft afgewend), aandacht
(pauze, om objecten heen lopen, duur, **vastberadenheid** — hoeveel
seconden hij niet van gedachten verandert over een net gekozen doel — en
**trouw**), nieuwsgierigheid (geheugen, verveling, zin om te gaan, gril),
wat hem aantrekt (gewichten van objecten, silhouetten, detail, kleur,
zeldzaamheid) en zoom. «Nieuw» kopieert het profiel in gebruik; de
kant-en-klare profielen kun je wijzigen en daarna herstellen.

In `settings.json`: `"explore_profile"` (het profiel in gebruik),
`"explore_profiles"` (je eigen, en wijzigingen aan de kant-en-klare) en
`"explore_record"` (het routevakje van het startvenster). De waarden worden
in lagen opgeteld: standaardwaarden (`EX_DEFAULTS`, `lib/explore.rb`) ←
`"explore": { … }` ← profiel ← opties van wie hem start (de brug).

Met de brug aan bestuurt en volgt Claude Code hem (de commando's van de
ontwikkelaarstools zijn in het Italiaans):

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # start: 120 s, 1,3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # een profiel alleen voor deze wandeling
ruby tools/esplora.rb profili                      # lijst; «profilo NAAM» zet het in gebruik
ruby tools/esplora.rb segui --foto esplorazione    # één regel en één foto per keuze
ruby tools/esplora.rb ferma                        # stopt en bewaart de route
```

### De AI aan het stuur

Met `pilota` en `guida` beslist Claude Code waarheen, terwijl de verkenner
zelf blijft lopen en kijken (`lib/expilot.rb`). Elk gezien ding heeft een
korte, vaste naam (`o12` een object, `s7` een vlak, `F3` een onverkend
gebied); de AI zet bestemmingen op een agenda, en de verkenner bereikt ze
een voor een met zijn eigen stappen, zijn eigen omwegen om muren en zijn
eigen blik. Met een lege agenda kiest hij weer zelf: hij stopt nooit om op
de AI te wachten.

```
ruby tools/esplora.rb pilota                       # wacht op een melding en beschrijft wat hij ziet
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "Het hoofdaltaar" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # draait zich om te kijken, zonder te bewegen
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # nieuwe agenda: een punt in meters
ruby tools/esplora.rb guida --svuota               # geen agenda: kiest weer zelf
ruby tools/esplora.rb guida --foto                 # een foto bij de huidige pauze (of de volgende)
ruby tools/esplora.rb guida --foto-sempre          # een foto bij elke pauze (--foto-mete: alleen bij de bestemmingen van de AI, --senza-foto)
```

De meldingen die `pilota` wekken: bestemming bereikt, bestemming afgerond
(of opgegeven, en waarom), agenda bijna leeg of leeg, een onbereikbare
bestemming, iets opvallends dat nooit eerder is gezien, een foto.

**Te voet: waar je kunt komen.** Al lopend zegt de beschrijving voor elk
ding en onverkend gebied of je er kunt komen (`reach`: ja, misschien via
nooit geziene gebieden, nee) en met hoeveel meter lopen (`walk_m`), volgens
de kaart die de verkenner al kijkend heeft gemaakt. Een «ga» naar iets waar
je te voet niet komt wordt meteen geweigerd, met de reden; op de foto's
hebben die dingen een lichtgrijs label. Op Stromboli ging de autonome
piloot van ongeveer één bereikte bestemming per minuut naar drie.

**Foto's met labels.** Bij de pauzes voor de bestemmingen van de AI maakt
de verkenner, stilstaand en met de blik op de bestemming, een beeld van de
weergave (800 px) en schrijft naast elk zichtbaar ding zijn korte naam: de
bestemming in geel, objecten in blauw, vlakken in grijs, onverkende
gebieden in paars. Zo ziet de AI wat «Groep2577#2» en dergelijke zijn, en
noemt ze bij naam. De foto's staan in `%APPDATA%\DagaWASD\pilota` (de
laatste 40). Een foto blokkeert SketchUp gedurende één beeld van de
weergave (een halve seconde bij een groot model): daarom alleen bij
stilstand.

Op de brug: `GET /explore/percept?since=N` (beschrijving en meldingen),
`GET /explore/wait?since=N&timeout=60` (dezelfde beschrijving, maar de brug
antwoordt pas als er een wekkende melding is: `pilota` vraagt niet
voortdurend) en `POST /explore` met `{"cmd": "steer", …}`.

**Opmerkingen in de video.** Wat de AI zegt (`--commento`, `--di`, of
`say` in de steer) blijft in de opgenomen route, op het moment dat hij het
zei: het wordt de beschrijving van de dichtstbijzijnde scène als je scènes
maakt, en een ondertitelbestand `.srt` naast de video (AVI: dezelfde naam,
spelers openen het zelf; PNG-beelden: `crea_video.bat` zet het in de MP4).

**Autonome piloot.** `tools/pilota_ia.rb` stuurt zelf, zonder één commando
per keer: hij wacht op de meldingen van de brug, stuurt Claude de
beschrijving en de foto van de pauze, en geeft aan de brug door wat Claude
beslist. De standaardmotor is Claude Code zelf (`claude -p`, met het account
van deze computer: geen sleutel); met `ANTHROPIC_API_KEY` ingesteld gebruikt
hij de Claude-API (gem `anthropic`). Op Stromboli duurt een beurt 4–5 s.
Elke beurt kost iets: `--turni` (20) en `--secondi` (300) stellen de grens,
en aan het eind toont hij de gebruikte tokens.

```
ruby tools/esplora.rb avvia --a-piedi                   # start, te voet
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # weinig moeite: antwoorden in een paar seconden
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # de API, met de sleutel
```

## Foto's en galerij

Al lopend maakt **P** (te wijzigen in *Systeem › Besturing*; op de gamepad
de rechter schouderknop, RB) een foto van de weergave, zonder vizier of
tekst, met een flits. Neem je een route op, dan hoort de foto bij die
route; anders bij een aparte serie, één voor elke keer dat je de modus
binnengaat.

De verkenner fotografeert zelf, als de wandeling een route wordt: de
interessantste bestemmingen van wat hij tot dan toe zag, wanneer zijn blik
erop rust en ze groot genoeg ziet (veel bestemmingen worden bekeken zonder
dat hij erheen gaat) of bij aankomst; ruimtes die zich af en toe openen;
nooit vanaf een plek waar hij al een foto maakte, nooit meer dan één foto
per 8 seconden (hooguit 30 per wandeling). Bij elke foto schrijft hij
**wat** erop staat (het ding, hoe groot, hoe ver, wat eromheen staat) en
**waarom** hij die koos: de interessantste tot dan toe, de kleur die
opvalt, niets vergelijkbaars in zicht, veel details, het silhouet dat
loskomt van de achtergrond, een object uit veel onderdelen, een uitzicht.
De AI die hem stuurt vraagt zijn eigen foto's met `snap` (het waarom) en
`say` (het wat).

De foto's staan naast het model, in `<model>_foto/<datum en tijd>/`, als
JPG van 1600 px, met `galleria.json`; de route bewaart de map relatief aan
het model, dus vindt hij die terug als het model met zijn foto's verhuist.
Voor een nooit opgeslagen model, of als er naast het model niet geschreven
kan worden, gaan ze naar `%APPDATA%/DagaWASD/foto`.

In *Camera › Routes* heeft elke route zijn eigen knop **📷**, naast Video:
met het aantal foto's opent hij de galerij in de browser; grijs als de
route er geen heeft, en een klik legt uit hoe je ze maakt. Onder de lijst
staan de series die bij geen route horen (foto's buiten een opname,
verwijderde routes).

De galerij is één pagina, `galleria.html` in de fotomap, telkens opnieuw
gemaakt in de taal van SketchUp. De foto's zijn polaroids op een houten
tafel, die zich ontwikkelen als ze in beeld komen, elk met een notitieblad:
wat, waarom, wie hem maakte, een kompas met de kijkrichting, en de tijd. Je
bekijkt ze op twee manieren:

- **op een rij**: ze schuiven opzij met het scrollwiel, de pijltjes, door
  te slepen, of via de filmstrook onderaan (de miniaturen). Bovenaan staat
  de wandeling met potlood getekend: de genummerde foto's met de kegel van
  wat ze bekeken, de schaal, het noorden, de richting. Een kleine kaart in
  een hoek volgt de huidige foto. De opmerkingen van de AI staan op
  plakbriefjes op hun plek in de wandeling, en aan het eind staat de kaart
  met duur, afgelegde weg en foto's;
- **verspreid over de tafel**: je pakt de foto's en verschuift ze met de
  muis (of de vinger, of de pijltjes), en de indeling blijft voor de
  volgende keer. *Netjes leggen* zet ze weer in rijen.

Een klik opent de foto groot, met *Diavoorstelling* (een voor een; de
spatiebalk pauzeert). Met foto's van meerdere makers (jij, de verkenner, de
AI) filteren de stempels bovenaan ze. `#3` in het adres gaat naar foto 3,
`#3z` opent die groot. De pagina print netjes (de foto's met hun
notities), werkt offline en kan met zijn map naar iemand worden gestuurd.

**Bewerken** wijzigt de teksten waar ze staan, in hetzelfde handschrift: de
titel van de galerij en van elke foto, *Wat*, *Waarom*, het stempel en de
notities van de AI; ✕ haalt een foto uit de galerij (het bestand blijft) en
↺ zet hem terug. De teksten van SketchUp gaan nooit verloren: elke tekst kan
terug naar het origineel. Wijzigingen worden meteen in de browser bewaard;
*Opslaan in de map* (Edge, Chrome) schrijft ze naar
`galleria_modifiche.json` naast de foto's en in de pagina zelf, zodat ze met
de map meereizen.

## Twee pakketten

`tools\crea_rbz.bat` maakt in `dist\`:

- `dagawasd-<versie>.rbz`: compleet, met de **brug voor Claude Code**
  (`lib/bridge.rb`), een server die alleen lokaal werkt, uit totdat je hem
  in het paneel aanzet, waarmee Claude Code in het geopende model tekent;
- `dagawasd-<versie>-warehouse.rbz`: zonder de brug, voor het Extension
  Warehouse. Zonder `lib/bridge.rb` werkt de extensie net zo goed.

## Ontwikkeling

De code, het commentaar en het wijzigingslogboek zijn in het Italiaans.

- `installa.bat` kopieert de broncode naar de Plugins-map van elke
  gevonden SketchUp.
- `tests\run_tests.bat` draait de tests (Ruby, met een gesimuleerde
  SketchUp; het paneel in een gesimuleerde browser met Node).
- `tools\controlla_warehouse.bat` controleert het pakket met de regels van
  Trimble (rubocop-sketchup).
- Het versienummer staat alleen in `dagawasd.rb` (`VERSION`); elke versie
  heeft een eigen sectie in `CHANGELOG.md`.
- De pictogrammen komen uit de SVG's in `pubblicazione/`:
  `tools\rendi_icone.bat` maakt die van de werkbalk (`icons/`) en die van de
  Warehouse-pagina (`pubblicazione/icona_512.png`) opnieuw.
- De pagina voor het Extension Warehouse (teksten in het Engels en notities
  voor de beoordelaars) staat in `pubblicazione/extension_warehouse.md`.
- Deze README bestaat in meerdere talen (`README.md` in het Engels,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.nl`, `.sv`, `.pl`, `.cs`, `.ru`, `.ja`, `.ko`, `.zh`):
  een wijziging hoort in allemaal.
- In de geopende SketchUp, met de brug aan en «Vensters en toetsen» aan in
  het paneel (gereedschap voor Claude Code, niet geïnstalleerd):
  - `tools\finestre.ps1` komt waar Ruby niet komt: native vensters,
    meldingen, menu's, opname van de weergave met lucht en wolken,
    gesimuleerde toetsen en echte klikken in de 3D-weergave (bijvoorbeeld de
    dubbelklik op een bol);
  - `tools\collaudo.rb` test live de knop en het menu van het paneel, de
    bevestiging van «Verwijderen» en een video tot aan het eindvenster;
  - `tools\schermate.rb` maakt de afbeeldingen van de pagina in
    `pubblicazione/schermate/` (1920×1080, met een scherm van minstens die
    grootte);
  - `tools\prova_fps.rb` loopt en rent in FPS-modus en meet het deinen van
    het hoofd.

## Licentie

[MIT](LICENSE) © 2026 Dagadam. Je mag de code vrij gebruiken, wijzigen en
verspreiden, ook commercieel, zolang elke kopie de copyrightvermelding en de
licentietekst behoudt.
