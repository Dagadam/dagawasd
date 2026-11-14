# DagaWASD

[English](README.md) · [Italiano](README.it.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Nederlands](README.nl.md) · [Svenska](README.sv.md) · [Polski](README.pl.md) · **Čeština** · [Русский](README.ru.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [中文](README.zh.md)

Rozšíření pro SketchUp (Windows): procházejte svůj model z pohledu první
osoby pomocí WASD a myši, nebo s herním ovladačem.

▶ Oficiální představení: https://youtu.be/8eBvtl7DiKU

▶ Ukázkové video: https://youtu.be/w6xE86y7iEw?is=7Gh12tF7atE_N9_K

⬇ **Stáhnout**: [nejnovější verze](https://github.com/Dagadam/dagawasd/releases/latest) (všechny verze: [Releases](https://github.com/Dagadam/dagawasd/releases))

## Co umí

- **Chůze**: setrvačnost, běh, přikrčení, skok, schody a svahy a bezpečný
  návrat na zem, když spadnete do prázdna.
- **Fyzika objektů**: skupiny a komponenty padají, odrážejí se a převracejí
  podle svého materiálu; lze je kopnout, uchopit a hodit.
- **Obloha a počasí**: slunce, měsíc a hvězdy podle data, času a místa;
  déšť, sníh, mraky, bouřky, sníh, který zůstává ležet na zemi. Hotové
  situace a proměnlivé počasí, které se samo mění s časem oblohy. Počasí je
  vidět i v exportovaných videích.
- **Trasy**: nahrávejte kameru při chůzi, přehrajte ji, exportujte jako
  scény nebo video AVI. Dolaďte ji v modelu posouváním a otáčením jejích
  pozic (koule se šipkou dlouhou jako zoom a rámeček záběru), nebo ji
  postavte od začátku. V panelu se každá trasa otevře na seznamu svých
  pozic; kliknutí na pozici, nebo dvojklik na její kouli (či Enter), otevře
  její nastavení s náhledem toho, co vidí, a kliknutí mezi dvěma pozicemi
  přidá novou z aktuálního pohledu. Při přehrávání seznam zvýrazní
  aktuální pozici. «Proředit kamery» sloučí koule nahromaděné jedna na
  druhé do jedné, do jejich průměru (poloha, pohled, zoom), pokud se jejich
  pohledy neliší o víc než 45°.
- **Samostatný průzkumník**: kamera se dívá na scénu, vybere to
  nejvýznamnější, udělá k tomu krok, zatímco se na to dívá, a začne znovu;
  nakonec je procházka trasou. Viz níže.
- **Fotky a galerie**: P vyfotí, co vidíte; průzkumník sám fotí to
  nejzajímavější ze své procházky. Každá trasa otevře svou galerii v
  prohlížeči: polaroidy na stole s poznámkami. Viz níže.
- **Herní ovladač** XInput a rozhlížení numerickou klávesnicí.
- Panel nastavení v 36 jazycích.
- **Přístupnost**: *Přístupnost › Bez záblesků* vypne všechny záblesky,
  fotek i blesků (viz [ACCESSIBILITY.md](.github/ACCESSIBILITY.md)).

Požadavky: SketchUp 2023 nebo novější ve Windows. Na Macu se rozšíření
nainstaluje, ale nespustí se, a oznámí to.

## Instalace

- Z **Extension Warehouse** SketchUpu (podepsaná verze), nebo
- stáhněte **`dagawasd-<verze>-warehouse.rbz`** z
  [nejnovější verze](https://github.com/Dagadam/dagawasd/releases/latest) (v části *Assets*) a nainstalujte
  jej přes *Rozšíření › Extension Manager › Instalovat rozšíření*. Druhý
  soubor, `dagawasd-<verze>.rbz`, obsahuje navíc most pro Claude Code (viz
  *Dva balíčky*).

Nastavení se ukládá do `%APPDATA%\DagaWASD\settings.json`: aktualizace ho
nesmaže.

## Samostatný průzkumník

Tlačítko s okem na liště (nebo *Rozšíření › DagaWASD › Samostatný
průzkumník*): malé okno umožní vybrat profil (jeho povahu, viz níže) a
zda procházku nahrát jako trasu, a zapamatuje si volby na příště; šipky a
Enter, nebo dvojklik na profil, a hned vyrazí. Stejné tlačítko ho při
průzkumu zastaví. Cyklus: **analýza → výběr bodu → krok k bodu s pohledem
na něj → analýza**.

- **Analýza**: sítnice paprsků procházejících mřížkou obrazovky
  (`view.pickray` + `model.raytest`) dává pro každou buňku vzdálenost,
  normálu, plochu, objekt a barvu. Z toho výraznost: hrany hloubky, hrany,
  detail, barevný kontrast (Lab), vzácnost, komponenty a skupiny v lidském
  měřítku; velké stěny a podlahy se počítají málo. Váženo vzdáleností,
  středem pohledu a novostí.
- **Paměť**: voxely toho, co už pohled viděl, místa, kudy už prošel (v
  půdorysu i výšce: patro nad ním zůstává nové), nuda podle cíle a
  kategorie (po jedné pohovce ho stejné zajímají méně): tak se nevrací
  pořád ke stejným věcem.
- **Mapa toho, co viděl**: pěšky paprsky ve výšce těla zaznamenávají na mapu
  s buňkami 50 cm (jedna na patro) viděnou podlahu s její výškou (podlaha,
  schody, desky nábytku) a zasažené stěny. Slouží ke dvěma věcem:
  - **hranice**: okraj mezi tím, co viděl, a tím, co nikdy neviděl (za
    dveřmi, za rohem), se stává cílem, «neprozkoumanou oblastí»: jde tam a
    podívá se dovnitř. Váží jako otevřený prostor, podle chuti chodit v
    profilu; v mapě pozornosti jsou to fialové čtverečky na podlaze;
  - **plánované cesty**: pro každý cíl naplánuje cestu na mapě (A*) k bodu,
    odkud je cíl vidět: kolem stěn a nábytku s odstupem, po schodech nahoru
    (schod po schodu ano, stůl nebo pohovka ne) a po svazích až do
    maximálního sklonu hráče, rovně, kde to jde. Kde se ještě nedíval, je
    optimista a zkouší to. Při každé analýze zkontroluje zbytek cesty na nové
    mapě a pokud je teď zablokovaná, hledá jinou; každé 3 s ji stejně
    přeplánuje (možná uviděl zkratku); kde narazí, označí to a přepočítá.
    Když cíl zmizí za něčím nebo se cesta od něj odkloní, dívá se, kam jde.
    Aktuální cesta je přerušovaná čára na podlaze. Hledání pracuje po
    dávkách, stejně jako analýza.
- **Krok**: k bodu, kolem překážek, po schodech nahoru, nikdy dolů z
  okraje; zastaví se ve vzdálenosti, odkud je objekt vidět celý, a dívá se
  na něj. Z leteckého pohledu letí a přistane tam, kde je co vidět.
- **Obcházení objektů**: když dojde k objektu a profil to žádá (*Obchází
  objekty*, ve stupních: Fotograf 180°, Zvědavý 90°), obejde ho a dívá se
  na něj, z volnější strany, aby ho viděl z více stran; když se cesta
  uzavře, vrátí se. Pak zastávka.
- **Skok**: nízkou překážku, která zatarasí cestu (zídka, plot, velký
  schod) a nedá se krátce obejít, přeskočí, pokud je za ní plocha k
  přistání. Používá sílu skoku a gravitaci hráče (s výchozími hodnotami se
  nohy zvednou o 1,08 m; přeskočí, co je nižší než 85 % této výšky); na
  sedadla a stoly nikdy neskáče. Lze vypnout v profilu (Pomalý neskáče).
- **Tělo**: výška očí, poloměr, schod (nejvýš 25 cm), skok a gravitace jsou
  hráčovy (panel › Hráč), i když se změní během průzkumu.
- **Plynulost**: stejně jako živá stavba přes most je analýza Fiber, který
  pracuje po dávkách mezi jedním snímkem a dalším; sítnice se zahušťuje
  nebo řídne podle toho, kolik v daném modelu stojí jeden paprsek. S
  *Systém › Výkon › Adaptivní analýza* se i frekvence analýz řídí volným
  výpočetním výkonem, mezi minimem a maximem za sekundu, aniž by zpomalila
  chůzi.
- **Ovládání**: Esc nebo kliknutí ho zastaví, pravé tlačítko pozastaví,
  «Hledat něco jiného», mapa pozornosti, barevné oko; kolečko myši pro
  rychlost; I skryje nebo zobrazí informační řádky vlevo nahoře. Jiný
  nástroj ho zastaví; orbitování prostředním tlačítkem ho pozastaví a on
  pokračuje odtud, kam jste dali kameru.
- **Zaseknutý?** Pokud se za 10 sekund neposune o 75 cm (nerozhodný mezi
  blízkými cíli, zavřený v rohu), hledá únikovou cestu mezi 12 směry a
  několik sekund po ní jde; pokud pěšky cesta není a režim je automatický,
  vzlétne.
- **Na konci**, pokud jste při startu nechali zaškrtnuté «Nahrát trasu»,
  se procházka stane trasou («Průzkum 1», …): z panelu si ji znovu
  prohlédnete, nebo z ní uděláte scény či video.

### Profily

Povaha průzkumníka je **profil**, sada koeficientů: *Rozšíření › DagaWASD ›
Profily průzkumníka…*, nebo pravé tlačítko během průzkumu › *Profil*
(změna za běhu) a *Upravit profily…*.

| Profil | Povaha |
|---|---|
| Vyvážený | ten obvyklý |
| Zvědavý | rychle se nudí, hledá detaily a vzácné věci, víc prozkoumává, obchází objekty o 90° |
| Běžec | 3,2 m/s, rychlé reflexy, krátké zastávky |
| Pomalý | 0,5 m/s, dlouhé zastávky, pohled se otáčí pomalu |
| Fotograf | než se přiblíží, přiblíží cíl zoomem, pak k němu jde a obejde ho o 180° |
| Bezstarostný | rozmarné volby, snadno mění názor, miluje otevřený prostor |
| Voják | průzkum, vždy pěšky: 3,6 m/s, dívá se zdálky a krátce, jde nejdřív tam, kam se ještě nedíval |

V okně má každý koeficient posuvník (když ho táhnete, průzkumník s tímto
profilem se mění živě) a ↺, které vrátí původní hodnotu. Skupiny: pohyb
(rychlost, vzdálenost zastavení, schod, pěšky/letem), pohled (otáčení,
reflexy, **plynulost** — jak rád přechází k tomu, co je vedle sledované
věci, místo aby se vracel k tomu, od čeho se už odvrátil), pozornost
(zastávka, obcházení objektů, trvání, **odhodlání** — kolik sekund nemění
názor na právě vybraný cíl — a **věrnost**), zvědavost (paměť, nuda, chuť
chodit, rozmar), co ho přitahuje (váhy objektů, siluet, detailu, barvy,
vzácnosti) a zoom. «Nový» zkopíruje používaný profil; hotové profily lze
měnit a pak obnovit.

V `settings.json`: `"explore_profile"` (používaný), `"explore_profiles"`
(vaše vlastní a změny hotových) a `"explore_record"` (políčko trasy v
úvodním okně). Hodnoty se skládají ve vrstvách: výchozí (`EX_DEFAULTS`,
`lib/explore.rb`) ← `"explore": { … }` ← profil ← volby toho, kdo ho
spouští (most).

Se zapnutým mostem ho Claude Code ovládá a sleduje (příkazy vývojářských
nástrojů jsou v italštině):

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # start: 120 s, 1,3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # profil jen pro tuto procházku
ruby tools/esplora.rb profili                      # seznam; «profilo NÁZEV» ho nastaví jako používaný
ruby tools/esplora.rb segui --foto esplorazione    # jeden řádek a jedna fotka za každou volbu
ruby tools/esplora.rb ferma                        # zastaví a uloží trasu
```

### AI za volantem

S `pilota` a `guida` rozhoduje Claude Code, kam jít, zatímco průzkumník dál
sám chodí a dívá se (`lib/expilot.rb`). Každá viděná věc má krátký, stálý
název (`o12` objekt, `s7` plocha, `F3` neprozkoumaná oblast); AI zapisuje
cíle do plánu a průzkumník je dosahuje jeden po druhém vlastními kroky,
vlastními objížďkami kolem stěn a vlastním pohledem. S prázdným plánem si
znovu vybírá sám: nikdy se nezastaví, aby čekal na AI.

```
ruby tools/esplora.rb pilota                       # čeká na událost a popisuje, co vidí
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "Hlavní oltář" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # otočí se a dívá, bez pohybu
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # nový plán: bod v metrech
ruby tools/esplora.rb guida --svuota               # bez plánu: znovu vybírá sám
ruby tools/esplora.rb guida --foto                 # fotka při aktuální (nebo příští) zastávce
ruby tools/esplora.rb guida --foto-sempre          # fotka při každé zastávce (--foto-mete: jen u cílů AI, --senza-foto)
```

Události, které budí `pilota`: cíl dosažen, cíl splněn (nebo opuštěn, a
proč), plán téměř prázdný nebo prázdný, nedosažitelný cíl, něco
pozoruhodného, co nikdy neviděl, fotka.

**Pěšky: kam se dá dojít.** Při chůzi popis u každé věci a neprozkoumané
oblasti říká, zda se tam dá dojít (`reach`: ano, možná přes nikdy neviděné
oblasti, ne) a kolik metrů cesty to je (`walk_m`), podle mapy, kterou si
průzkumník udělal díváním. «Jdi» k něčemu, kam se pěšky nedá dojít, je
hned odmítnuto i s důvodem; na fotkách mají tyto věci světle šedý štítek.
Na Stromboli se autonomní pilot zlepšil z asi jednoho dosaženého cíle za
minutu na tři.

**Fotky se štítky.** Při zastávkách před cíli AI průzkumník, nehybně a s
pohledem na cíli, pořídí obraz pohledu (800 px) a ke každé viditelné věci
napíše její krátký název: cíl žlutě, objekty modře, plochy šedě,
neprozkoumané oblasti fialově. Tak AI vidí, co jsou «Skupina2577#2» a
podobné, a ukazuje na ně jménem. Fotky jsou v `%APPDATA%\DagaWASD\pilota`
(posledních 40). Fotka zablokuje SketchUp na dobu jednoho obrazu pohledu
(půl sekundy u velkého modelu): proto jen v klidu.

Na mostě: `GET /explore/percept?since=N` (popis a události), `GET
/explore/wait?since=N&timeout=60` (stejný popis, ale most odpoví, až když je
budící událost: `pilota` se neptá pořád dokola) a `POST /explore` s
`{"cmd": "steer", …}`.

**Komentáře ve videu.** Co AI řekne (`--commento`, `--di` nebo `say` ve
steer), zůstane v nahrané trase, v okamžiku, kdy to řekla: stane se popisem
nejbližší scény při tvorbě scén a souborem titulků `.srt` vedle videa (AVI:
stejný název, přehrávače ho otevřou samy; obrázky PNG: `crea_video.bat` ho
vloží do MP4).

**Autonomní pilot.** `tools/pilota_ia.rb` řídí sám, bez jednotlivých
příkazů: čeká na události mostu, pošle Claudovi popis a fotku ze zastávky
a předá mostu, co Claude rozhodne. Výchozím motorem je samotný Claude Code
(`claude -p`, s účtem tohoto počítače: bez klíče); s nastaveným
`ANTHROPIC_API_KEY` používá API Claude (gem `anthropic`). Na Stromboli
trvá jedno kolo 4–5 s. Každé kolo něco stojí: `--turni` (20) a `--secondi`
(300) určí limit a na konci vypíše spotřebované tokeny.

```
ruby tools/esplora.rb avvia --a-piedi                   # start, pěšky
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # nízké úsilí: odpovědi za pár sekund
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # API, s klíčem
```

## Fotky a galerie

Při chůzi **P** (změníte v *Systém › Ovládání*; na ovladači pravé horní
tlačítko, RB) vyfotí pohled, bez zaměřovače a textů, s bleskem. Pokud
nahráváte trasu, fotka patří k ní; jinak do samostatné série, jedné za
každý vstup do režimu.

Průzkumník fotí sám, když se procházka stane trasou: nejzajímavější cíle
z dosud viděných, když na nich spočine pohled a vidí je dost velké (mnoho
cílů si prohlédne, aniž by k nim došel), nebo při příchodu; prostory, které
se občas otevřou; nikdy z místa, kde už fotil, nikdy víc než jednu fotku za
8 sekund (nejvýš 30 na procházku). Ke každé fotce napíše, **co** na ní je
(věc, jak velká, jak daleko, co je kolem) a **proč** ji vybral:
nejzajímavější dosud, barva, která vyniká, nic podobného v dohledu, mnoho
detailů, silueta, která vystupuje z pozadí, objekt z mnoha částí, výhled.
AI, která ho řídí, si říká o vlastní fotky pomocí `snap` (své proč) a `say`
(co).

Fotky se ukládají vedle modelu, do `<model>_foto/<datum a čas>/`, jako JPG
o 1600 px, s `galleria.json`; trasa si pamatuje složku relativně k modelu,
takže ji najde, i když se model přesune i s fotkami. U nikdy neuloženého
modelu, nebo pokud vedle modelu nelze zapisovat, jdou do
`%APPDATA%/DagaWASD/foto`.

V *Kamera › Trasy* má každá trasa své tlačítko **📷** vedle Video: s počtem
fotek otevře galerii v prohlížeči; šedé, pokud trasa žádné nemá, a
kliknutí vysvětlí, jak nějaké pořídit. Pod seznamem jsou série, které
nepatří k žádné trase (fotky mimo nahrávání, smazané trasy).

Galerie je jediná stránka, `galleria.html` ve složce s fotkami, vytvořená
znovu při každém otevření v jazyce SketchUpu. Fotky jsou polaroidy na
dřevěném stole, které se vyvolávají, když se objeví v zorném poli, každá s
lístkem poznámek: co, proč, kdo ji pořídil, kompas se směrem pohledu a čas.
Prohlížejí se dvěma způsoby:

- **v řadě**: posouvají se do strany kolečkem myši, šipkami, tažením, nebo
  z filmového pásu dole (miniatury). Nahoře je procházka nakreslená tužkou:
  očíslované fotky s kuželem toho, na co se dívaly, měřítko, sever, směr.
  Malá mapa v rohu sleduje aktuální fotku. Komentáře AI jsou na lepících
  lístcích na svém místě procházky a na konci je karta s délkou, ušlou
  cestou a fotkami;
- **rozházené po stole**: fotky se berou a posouvají myší (nebo prstem,
  nebo šipkami) a rozložení zůstane na příště. *Uklidit* je znovu srovná do
  řad.

Kliknutí otevře fotku ve velkém, s *Prezentací* (jedna po druhé; mezerník
pozastaví). U fotek více autorů (vy, průzkumník, AI) je filtrují razítka
nahoře. `#3` v adrese vede na fotku 3, `#3z` ji otevře ve velkém. Stránka
se čistě tiskne (fotky s poznámkami), funguje bez sítě a lze ji poslat
někomu i se složkou.

**Upravit** mění texty přímo tam, kde jsou, stejným písmem: název galerie i
každé fotky, *Co*, *Proč*, razítko a poznámky AI; ✕ vyjme fotku z galerie
(soubor zůstane) a ↺ ji vrátí. Texty ze SketchUpu se nikdy neztratí: každý
se může vrátit k původnímu. Změny se hned uchovají v prohlížeči; *Uložit do
složky* (Edge, Chrome) je zapíše do `galleria_modifiche.json` vedle fotek a
do samotné stránky, takže cestují spolu se složkou.

## Dva balíčky

`tools\crea_rbz.bat` vytvoří v `dist\`:

- `dagawasd-<verze>.rbz`: úplný, s **mostem pro Claude Code**
  (`lib/bridge.rb`), čistě lokálním serverem, vypnutým, dokud ho nezapnete
  v panelu, přes který Claude Code kreslí do otevřeného modelu;
- `dagawasd-<verze>-warehouse.rbz`: bez mostu, pro Extension Warehouse. Bez
  `lib/bridge.rb` rozšíření funguje stejně.

## Vývoj

Kód, jeho komentáře a seznam změn jsou v italštině.

- `installa.bat` zkopíruje zdrojový kód do složky Plugins každého
  nalezeného SketchUpu.
- `tests\run_tests.bat` spustí testy (Ruby, se simulovaným SketchUpem;
  panel v simulovaném prohlížeči s Node).
- `tools\controlla_warehouse.bat` zkontroluje balíček podle pravidel
  Trimble (rubocop-sketchup).
- Číslo verze je jen v `dagawasd.rb` (`VERSION`); každá verze má svou
  sekci v `CHANGELOG.md`.
- Ikony vznikají ze SVG v `pubblicazione/`: `tools\rendi_icone.bat` znovu
  vytvoří ikony lišty (`icons/`) a ikonu stránky Warehouse
  (`pubblicazione/icona_512.png`).
- Stránka pro Extension Warehouse (texty v angličtině a poznámky pro
  posuzovatele) je v `pubblicazione/extension_warehouse.md`.
- Toto README existuje ve více jazycích (`README.md` v angličtině,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.nl`, `.sv`, `.pl`, `.cs`, `.ru`, `.ja`, `.ko`, `.zh`):
  změna patří do všech.
- V otevřeném SketchUpu, se zapnutým mostem a zapnutými «Okna a klávesy» v
  panelu (nástroje pro Claude Code, neinstalují se):
  - `tools\finestre.ps1` dosáhne tam, kam Ruby ne: nativní okna, hlášení,
    nabídky, zachycení pohledu s oblohou a mraky, simulované klávesy a
    skutečná kliknutí ve 3D pohledu (například dvojklik na kouli);
  - `tools\collaudo.rb` živě testuje tlačítko a nabídku panelu, potvrzení
    «Smazat» a video až po závěrečné okno;
  - `tools\schermate.rb` vytvoří obrázky stránky v
    `pubblicazione/schermate/` (1920×1080, s obrazovkou alespoň takto
    velkou);
  - `tools\prova_fps.rb` chodí a běhá v režimu FPS a měří houpání hlavy.

## Kontakt

Pište na [DagaWASD@icloud.com](mailto:DagaWASD@icloud.com). Chyby a nápady je lepší hlásit jako
[issue](https://github.com/Dagadam/dagawasd/issues), kde je uvidí a mohou sledovat i ostatní;
bezpečnostní problémy hlaste podle [bezpečnostních zásad](.github/SECURITY.md).

Pokud je vám DagaWASD užitečný, můžete podpořit jeho vývoj na [Ko-fi](https://ko-fi.com/dagadam).

## Licence

[MIT](LICENSE) © 2026 Dagadam. Kód můžete volně používat, upravovat a
šířit, i komerčně, pokud každá kopie zachová upozornění na autorská práva a
text licence.
