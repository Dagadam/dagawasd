# DagaWASD

[English](README.md) · [Italiano](README.it.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Nederlands](README.nl.md) · **Svenska** · [Polski](README.pl.md) · [Čeština](README.cs.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [中文](README.zh.md)

Tillägg för SketchUp (Windows): gå genom din modell i förstapersonsvy med
WASD och musen, eller med en handkontroll.

▶ Officiell presentation: https://youtu.be/8eBvtl7DiKU

⬇ **Ladda ner**: [senaste versionen](https://github.com/Dagadam/dagawasd/releases/latest) (alla versioner: [Releases](https://github.com/Dagadam/dagawasd/releases))

## Vad det gör

- **Gå**: tröghet, springa, huka sig, hoppa, trappor och sluttningar, och
  en säker återkomst till marken om du faller ut i tomma intet.
- **Objektfysik**: grupper och komponenter faller, studsar och välter
  efter sitt material; du kan sparka, greppa och kasta dem.
- **Himmel och väder**: sol, måne och stjärnor efter datum, tid och plats;
  regn, snö, moln, åska, snö som blir liggande på marken. Färdiga
  situationer och växlande väder som ändras av sig självt med himlens tid.
  Vädret syns även i exporterade videor.
- **Rutter**: spela in kameran medan du går, spela upp den, exportera den
  som scener eller som AVI-video. Finjustera den i modellen genom att flytta
  och vrida dess positioner (klot med en pil lika lång som zoomen, och
  bildens ram), eller bygg en från början. I panelen öppnas varje rutt med
  listan över dess positioner; ett klick på en position, eller ett
  dubbelklick på dess klot (eller Enter), öppnar dess inställningar med en
  förhandsvisning av vad den ser, och ett klick mellan två positioner lägger
  till en från den aktuella vyn. Under uppspelning tänder listan den
  aktuella positionen. «Gallra kameror» slår ihop klot som ligger staplade
  på varandra till ett, deras medelvärde (position, blick, zoom), så länge
  de inte tittar mer än 45° isär.
- **Autonom utforskare**: kameran tittar på scenen, väljer det mest
  betydelsefulla, tar ett steg mot det medan den tittar på det, och börjar
  om; till slut är promenaden en rutt. Se nedan.
- **Foton och galleri**: P tar ett foto av det du ser; utforskaren
  fotograferar själv det intressantaste under sin promenad. Varje rutt
  öppnar sitt galleri i webbläsaren: polaroidbilder på ett bord, med
  anteckningar. Se nedan.
- XInput-**handkontroll**, och att se sig omkring med numeriska
  tangentbordet.
- Inställningspanel på 36 språk.
- **Tillgänglighet**: *Tillgänglighet › Inga blixtar* stänger av alla
  blixtar, från foton och från åska (se
  [ACCESSIBILITY.md](.github/ACCESSIBILITY.md)).

Krav: SketchUp 2023 eller senare, på Windows. På Mac installeras tillägget
men startar inte, och säger det.

## Installation

- Från SketchUps **Extension Warehouse** (signerad version), eller
- ladda ner **`dagawasd-<version>-warehouse.rbz`** från den
  [senaste versionen](https://github.com/Dagadam/dagawasd/releases/latest) (under *Assets*) och installera
  den från *Tillägg › Extension Manager › Installera tillägg*. Den andra
  filen, `dagawasd-<version>.rbz`, innehåller även bryggan för Claude Code
  (se *Två paket*).

Inställningarna sparas i `%APPDATA%\DagaWASD\settings.json`: en
uppdatering raderar dem inte.

## Autonom utforskare

Ögonknappen i verktygsfältet (eller *Tillägg › DagaWASD › Autonom
utforskare*): ett litet fönster låter dig välja profil (dess karaktär, se
nedan) och om promenaden ska spelas in som rutt, och kommer ihåg dina val
till nästa gång; piltangenter och Enter, eller dubbelklick på en profil, för
att starta direkt. Samma knapp stoppar den medan den utforskar. Cykeln:
**analysera → välja punkt → ett steg mot punkten, medan den tittar på den →
analysera**.

- **Analys**: en näthinna av strålar genom skärmens rutnät (`view.pickray`
  + `model.raytest`) ger för varje cell avstånd, normal, yta, objekt och
  färg. Därifrån framträdandet: djupkanter, kanter, detaljer, färgkontrast
  (Lab), sällsynthet, komponenter och grupper i mänsklig storlek; stora
  väggar och golv väger lite. Viktat efter avstånd, bildens mitt och
  nyhet.
- **Minne**: voxlar av det blicken redan sett, platser den redan gått på (i
  plan och höjd: våningen ovanför förblir ny), tristess per mål och per
  kategori (har den sett en soffa lockar likadana mindre): så återvänder den
  inte hela tiden till samma saker.
- **Karta över det den sett**: till fots markerar strålarna i kroppshöjd på
  en karta med 50 cm-celler (en per våning) det sedda golvet med dess höjd
  (golv, trappsteg, möbelskivor) och de träffade väggarna. Den används till
  två saker:
  - **gränser**: kanten mellan det den sett och det den aldrig sett (bakom
    en dörr, runt ett hörn) blir ett mål, ett «outforskat område»: den går
    dit och tittar in. Det väger som öppen yta, enligt profilens lust att
    röra sig; i uppmärksamhetskartan är det de lila rutorna på golvet;
  - **planerade vägar**: för varje mål planerar den vägen på kartan (A*) till
    en punkt varifrån målet syns: runt väggar och möbler med lite avstånd,
    uppför trappor (ett steg i taget ja, ett bord eller en soffa nej) och
    sluttningar upp till spelarens maximala lutning, rakt fram där det går.
    Där den ännu inte tittat är den optimistisk och försöker. Vid varje
    analys kontrollerar den resten av vägen på den nya kartan och letar, om
    den nu är blockerad, efter en annan; var 3:e sekund planerar den om
    ändå (kanske har den sett en genväg); där den krockar markerar den det
    och räknar om. Försvinner målet bakom något, eller svänger vägen bort
    från det, tittar den dit den går. Den aktuella vägen är den streckade
    linjen på golvet. Sökningen arbetar i skivor, precis som analysen.
- **Steg**: mot punkten, runt hinder, uppför trappor, aldrig ner från en
  kant; den stannar på ett avstånd där objektet syns helt, och tittar på
  det. Från en flygvy flyger den och landar där det finns något att se.
- **Gå runt föremål**: framme vid ett föremål går den, om profilen begär
  det (*Går runt föremål*, i grader: Fotograf 180°, Nyfiken 90°), runt det
  medan den tittar på det, på den friaste sidan, för att se det från flera
  håll; stängs vägen vänder den. Sedan pausen.
- **Hopp**: ett lågt hinder som spärrar vägen (en låg mur, ett staket, ett
  stort trappsteg) utan kort omväg hoppar den över, om det finns en yta att
  landa på bakom. Den använder spelarens hoppkraft och gravitation (med
  standardvärdena lyfter fötterna 1,08 m; den hoppar över det som är lägre än
  85 % av den höjden); den hoppar aldrig upp på stolar och bord. Kan stängas
  av i profilen (Långsam hoppar inte).
- **Kropp**: ögonhöjd, radie, trappsteg (högst 25 cm), hopp och gravitation
  är spelarens (panelen › Spelare), även om de ändras medan den utforskar.
- **Smidigt**: precis som bryggans livebygge är analysen en Fiber som
  arbetar i skivor mellan en bildruta och nästa; näthinnan blir tätare
  eller glesare beroende på vad en stråle kostar i den modellen. Med
  *System › Prestanda › Adaptiv analys* följer även analysernas frekvens den
  lediga beräkningskraften, mellan ett minimum och ett maximum per sekund,
  utan att sakta ner gången.
- **Styrning**: Esc eller ett klick för att stoppa den, högerklick för paus,
  «Leta efter något annat», uppmärksamhetskarta, färgöga; mushjulet för
  hastigheten; I döljer eller visar informationsraderna uppe till vänster.
  Ett annat verktyg stoppar den; att kretsa med mittenknappen pausar den,
  och den fortsätter därifrån du satte kameran.
- **Fast?** Om den inte rör sig 75 cm på 10 sekunder (obeslutsam mellan
  närliggande mål, instängd i ett hörn), letar den efter en flyktväg bland
  12 riktningar och följer den några sekunder; finns ingen väg till fots och
  läget är automatiskt, lyfter den.
- **Till slut**, om du lät «Spela in rutten» vara ikryssad vid starten, blir
  promenaden en rutt («Utforskning 1», …): från panelen tittar du på den
  igen, eller gör scener eller en video av den.

### Profiler

Utforskarens karaktär är en **profil**, en uppsättning koefficienter:
*Tillägg › DagaWASD › Utforskarens profiler…*, eller högerklick medan den
utforskar › *Profil* (byte i farten) och *Redigera profiler…*.

| Profil | Karaktär |
|---|---|
| Balanserad | den vanliga |
| Nyfiken | blir snabbt uttråkad, söker detaljer och sällsynta saker, utforskar mer, går 90° runt föremål |
| Löpare | 3,2 m/s, snabba reflexer, korta pauser |
| Långsam | 0,5 m/s, långa pauser, en blick som vänder sig långsamt |
| Fotograf | zoomar in målet innan den närmar sig, går sedan dit och 180° runt det |
| Sorglös | nyckfulla val, ändrar sig lätt, älskar öppna ytor |
| Soldat | spaning, alltid till fots: 3,6 m/s, tittar på avstånd och kort, går först dit den ännu inte tittat |

I fönstret har varje koefficient ett skjutreglage (medan du drar ändras
utforskaren live, om den använder den profilen) och en ↺ som återställer
originalvärdet. Grupper: rörelse (hastighet, stoppavstånd, trappsteg, till
fots/flygande), blick (vridning, reflexer, **kontinuitet** — hur gärna den
går vidare till det som ligger bredvid det den tittar på, utan att
återvända till det den redan vänt sig från), uppmärksamhet (paus, gå runt
föremål, varaktighet, **beslutsamhet** — hur många sekunder den inte ändrar
sig om ett nyss valt mål — och **trohet**), nyfikenhet (minne, tristess,
lust att röra sig, nyck), vad som lockar den (vikter för objekt,
silhuetter, detaljer, färg, sällsynthet) och zoom. «Ny» kopierar profilen
som används; de färdiga profilerna kan ändras och sedan återställas.

I `settings.json`: `"explore_profile"` (den som används),
`"explore_profiles"` (dina egna, och ändringar av de färdiga) och
`"explore_record"` (ruttrutan i startfönstret). Värdena läggs ihop i lager:
standardvärden (`EX_DEFAULTS`, `lib/explore.rb`) ← `"explore": { … }` ←
profil ← alternativ från den som startar den (bryggan).

Med bryggan på styr och följer Claude Code den (kommandona i
utvecklarverktygen är på italienska):

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # start: 120 s, 1,3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # en profil bara för den här promenaden
ruby tools/esplora.rb profili                      # lista; «profilo NAMN» tar den i bruk
ruby tools/esplora.rb segui --foto esplorazione    # en rad och ett foto per val
ruby tools/esplora.rb ferma                        # stoppar och sparar rutten
```

### AI vid ratten

Med `pilota` och `guida` är det Claude Code som bestämmer vart den ska,
medan utforskaren själv fortsätter att gå och titta (`lib/expilot.rb`).
Varje sedd sak har ett kort, stabilt namn (`o12` ett objekt, `s7` en yta,
`F3` ett outforskat område); AI:n sätter mål på en agenda, och utforskaren
når dem ett efter ett med sina egna steg, sina egna omvägar runt väggar och
sin egen blick. Med tom agenda väljer den själv igen: den stannar aldrig
för att vänta på AI:n.

```
ruby tools/esplora.rb pilota                       # väntar på en händelse och beskriver vad den ser
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "Högaltaret" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # vänder sig för att titta, utan att röra sig
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # ny agenda: en punkt i meter
ruby tools/esplora.rb guida --svuota               # ingen agenda: väljer själv igen
ruby tools/esplora.rb guida --foto                 # ett foto vid nuvarande paus (eller nästa)
ruby tools/esplora.rb guida --foto-sempre          # ett foto vid varje paus (--foto-mete: bara vid AI:ns mål, --senza-foto)
```

Händelserna som väcker `pilota`: mål nått, mål klart (eller övergivet, och
varför), agendan nästan tom eller tom, ett mål som inte går att nå, något
anmärkningsvärt som aldrig setts, ett foto.

**Till fots: vart man kommer.** Under gång säger beskrivningen för varje
sak och outforskat område om man når dit (`reach`: ja, kanske via aldrig
sedda områden, nej) och med hur många meters väg (`walk_m`), utifrån
kartan som utforskaren gjort genom att titta. Ett «gå» till något man inte
når till fots avvisas direkt, med orsak; på fotona har de sakerna en
ljusgrå etikett. På Stromboli gick den autonoma piloten från ungefär ett
nått mål per minut till tre.

**Foton med etiketter.** Vid pauserna framför AI:ns mål tar utforskaren,
stillastående och med blicken på målet, en bild av vyn (800 px) och skriver
bredvid varje synlig sak dess korta namn: målet i gult, objekt i blått,
ytor i grått, outforskade områden i lila. Så ser AI:n vad «Grupp2577#2» och
liknande är, och pekar ut dem med namn. Fotona ligger i
`%APPDATA%\DagaWASD\pilota` (de senaste 40). Ett foto blockerar SketchUp
under en bild av vyn (en halv sekund i en stor modell): därför bara när den
står still.

På bryggan: `GET /explore/percept?since=N` (beskrivning och händelser),
`GET /explore/wait?since=N&timeout=60` (samma beskrivning, men bryggan
svarar först när en väckande händelse finns: `pilota` frågar inte hela
tiden) och `POST /explore` med `{"cmd": "steer", …}`.

**Kommentarerna i videon.** Det AI:n säger (`--commento`, `--di`, eller
`say` i steer) stannar i den inspelade rutten, i det ögonblick den sade
det: det blir beskrivningen av den närmaste scenen när man gör scener, och
en undertextfil `.srt` bredvid videon (AVI: samma namn, spelarna öppnar den
själva; PNG-bilder: `crea_video.bat` lägger in den i MP4:an).

**Autonom pilot.** `tools/pilota_ia.rb` styr själv, utan ett kommando i
taget: den väntar på bryggans händelser, skickar beskrivningen och fotot
från pausen till Claude, och ger bryggan det Claude bestämmer.
Standardmotorn är Claude Code själv (`claude -p`, med den här datorns
konto: ingen nyckel); med `ANTHROPIC_API_KEY` satt använder den Claude-API:t
(gem `anthropic`). På Stromboli tar en tur 4–5 s. Varje tur kostar:
`--turni` (20) och `--secondi` (300) sätter gränsen, och till sist skriver
den ut använda tokens.

```
ruby tools/esplora.rb avvia --a-piedi                   # start, till fots
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # låg ansträngning: svar på några sekunder
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # API:t, med nyckeln
```

## Foton och galleri

Under gång tar **P** (ändras under *System › Styrning*; på handkontrollen
höger axelknapp, RB) ett foto av vyn, utan sikte eller text, med en blixt.
Spelar du in en rutt hör fotot till den; annars hamnar det i en egen serie,
en för varje gång du går in i läget.

Utforskaren fotograferar själv när promenaden blir en rutt: de
intressantaste målen av det den sett hittills, när blicken vilar på dem och
ser dem tillräckligt stora (många mål tittas på utan att den går dit) eller
vid ankomsten; ytor som öppnar sig då och då; aldrig från en plats där den
redan fotograferat, aldrig mer än ett foto var 8:e sekund (högst 30 per
promenad). Till varje foto skriver den **vad** som syns (saken, hur stor,
hur långt bort, vad som finns runt omkring) och **varför** den valde det:
det intressantaste hittills, färgen som sticker ut, inget liknande i sikte,
många detaljer, silhuetten som lossnar från bakgrunden, ett objekt av många
delar, en utsikt. AI:n som styr den ber om sina egna foton med `snap`
(varför) och `say` (vad).

Fotona sparas bredvid modellen, i `<modell>_foto/<datum och tid>/`, som JPG
på 1600 px, med `galleria.json`; rutten sparar mappen relativt modellen, så
den hittar den igen om modellen flyttas med sina foton. För en modell som
aldrig sparats, eller om det inte går att skriva bredvid modellen, hamnar
de i `%APPDATA%/DagaWASD/foto`.

Under *Kamera › Rutter* har varje rutt sin egen **📷**-knapp, bredvid
Video: med antalet foton öppnar den galleriet i webbläsaren; grå om rutten
saknar foton, och ett klick förklarar hur man tar några. Under listan finns
serierna som ingen rutt äger (foton utanför en inspelning, raderade
rutter).

Galleriet är en enda sida, `galleria.html` i fotomappen, som byggs om vid
varje öppning på SketchUps språk. Fotona är polaroidbilder på ett träbord,
som framkallas när de kommer in i bild, var och en med sitt
anteckningsblad: vad, varför, vem som tog det, en kompass med blickens
riktning, och tiden. Man tittar på dem på två sätt:

- **på rad**: de rullar i sidled med mushjulet, piltangenterna, genom att
  dra, eller från filmremsan längst ner (miniatyrerna). Överst syns
  promenaden ritad med blyerts: de numrerade fotona med konen av det de såg,
  skalan, norr, riktningen. En liten karta i ett hörn följer det aktuella
  fotot. AI:ns kommentarer sitter på post-it-lappar på sin plats i
  promenaden, och sist finns kortet med tid, sträcka och foton;
- **utspridda på bordet**: man tar fotona och flyttar dem med musen (eller
  fingret, eller piltangenterna), och placeringen sparas till nästa gång.
  *Lägg dem i ordning* lägger dem i rader igen.

Ett klick öppnar fotot stort, med *Bildspel* (ett i taget; mellanslag
pausar). Med foton från flera upphovspersoner (du, utforskaren, AI:n)
filtrerar stämplarna överst dem. `#3` i adressen går till foto 3, `#3z`
öppnar det stort. Sidan skrivs ut rent (fotona med sina anteckningar),
fungerar utan nät och kan skickas till någon tillsammans med sin mapp.

**Redigera** ändrar texterna där de står, med samma handstil: galleriets och
varje fotos titel, *Vad*, *Varför*, stämpeln och AI:ns anteckningar; ✕ tar
ut ett foto ur galleriet (filen finns kvar) och ↺ lägger tillbaka det.
SketchUps egna texter försvinner aldrig: var och en kan gå tillbaka till
originalet. Ändringar sparas direkt i webbläsaren; *Spara i mappen* (Edge,
Chrome) skriver dem till `galleria_modifiche.json` bredvid fotona och in i
själva sidan, så att de följer med mappen.

## Två paket

`tools\crea_rbz.bat` skapar i `dist\`:

- `dagawasd-<version>.rbz`: komplett, med **bryggan för Claude Code**
  (`lib/bridge.rb`), en enbart lokal server, avstängd tills du slår på den i
  panelen, genom vilken Claude Code ritar i den öppna modellen;
- `dagawasd-<version>-warehouse.rbz`: utan bryggan, för Extension
  Warehouse. Utan `lib/bridge.rb` fungerar tillägget ändå.

## Utveckling

Koden, kommentarerna och ändringsloggen är på italienska.

- `installa.bat` kopierar källkoden till Plugins-mappen i varje SketchUp
  som hittas.
- `tests\run_tests.bat` kör testerna (Ruby, med ett simulerat SketchUp;
  panelen i en simulerad webbläsare med Node).
- `tools\controlla_warehouse.bat` kontrollerar paketet mot Trimbles regler
  (rubocop-sketchup).
- Versionsnumret finns bara i `dagawasd.rb` (`VERSION`); varje version har
  sitt avsnitt i `CHANGELOG.md`.
- Ikonerna skapas från SVG-filerna i `pubblicazione/`:
  `tools\rendi_icone.bat` gör om verktygsfältets (`icons/`) och
  Warehouse-sidans (`pubblicazione/icona_512.png`).
- Sidan för Extension Warehouse (texter på engelska och anteckningar för
  granskarna) finns i `pubblicazione/extension_warehouse.md`.
- Den här README:n finns på flera språk (`README.md` på engelska,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.nl`, `.sv`, `.pl`, `.cs`, `.ru`, `.ja`, `.ko`, `.zh`):
  en ändring ska in i alla.
- I det öppna SketchUp, med bryggan på och «Fönster och tangenter» på i
  panelen (verktyg för Claude Code, installeras inte):
  - `tools\finestre.ps1` når dit Ruby inte når: inbyggda fönster,
    meddelanden, menyer, fångst av vyn med himmel och moln, simulerade
    tangenter och riktiga klick i 3D-vyn (till exempel dubbelklick på ett
    klot);
  - `tools\collaudo.rb` testar live panelens knapp och meny, bekräftelsen av
    «Ta bort» och en video fram till slutfönstret;
  - `tools\schermate.rb` gör sidans bilder i `pubblicazione/schermate/`
    (1920×1080, med en skärm minst så stor);
  - `tools\prova_fps.rb` går och springer i FPS-läge och mäter huvudets
    gungning.

## Kontakt

Skriv till [DagaWASD@icloud.com](mailto:DagaWASD@icloud.com). Buggar och idéer är bättre som
[issue](https://github.com/Dagadam/dagawasd/issues), där andra kan se och följa dem;
säkerhetsproblem rapporteras enligt [säkerhetspolicyn](.github/SECURITY.md).

Har du nytta av DagaWASD kan du stödja utvecklingen på [Ko-fi](https://ko-fi.com/dagadam).

## Licens

[MIT](LICENSE) © 2026 Dagadam. Du får använda, ändra och sprida koden
fritt, även kommersiellt, så länge varje kopia behåller upphovsrättsnotisen
och licenstexten.
