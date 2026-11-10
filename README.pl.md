# DagaWASD

[English](README.md) · [Italiano](README.it.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Nederlands](README.nl.md) · [Svenska](README.sv.md) · **Polski** · [Čeština](README.cs.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [中文](README.zh.md)

Rozszerzenie do SketchUp (Windows): chodź po swoim modelu w widoku
pierwszoosobowym za pomocą WASD i myszy albo pada.

▶ Film demonstracyjny: https://youtu.be/w6xE86y7iEw?is=7Gh12tF7atE_N9_K

⬇ **Pobierz**: [najnowsza wersja](https://github.com/Dagadam/dagawasd/releases/latest) (wszystkie wersje: [Releases](https://github.com/Dagadam/dagawasd/releases))

## Co potrafi

- **Chodzenie**: bezwładność, bieg, kucanie, skok, schody i rampy oraz
  bezpieczny powrót na ziemię, jeśli spadniesz w pustkę.
- **Fizyka obiektów**: grupy i komponenty spadają, odbijają się i
  przewracają zgodnie z materiałem; można je kopać, chwytać i rzucać.
- **Niebo i pogoda**: słońce, księżyc i gwiazdy według daty, godziny i
  miejsca; deszcz, śnieg, chmury, burze, śnieg zalegający na ziemi. Gotowe
  sytuacje i zmienna pogoda, która sama się zmienia z czasem nieba. Pogoda
  pojawia się też w eksportowanych filmach.
- **Trasy**: nagrywaj kamerę podczas chodzenia, odtwarzaj ją, eksportuj jako
  sceny lub film AVI. Dopracuj ją w modelu, przesuwając i obracając jej
  pozycje (kule ze strzałką długą jak zoom oraz ramka kadru), albo zbuduj
  trasę od zera. W panelu każda trasa otwiera listę swoich pozycji;
  kliknięcie pozycji albo dwuklik na jej kuli (lub Enter) otwiera jej
  ustawienia z podglądem tego, co widzi, a kliknięcie między dwiema
  pozycjami dodaje nową z bieżącego widoku. Podczas odtwarzania lista
  podświetla bieżącą pozycję. «Przerzedź kamery» łączy kule nagromadzone
  jedna na drugiej w jedną, ich średnią (pozycja, spojrzenie, zoom), o ile
  nie patrzą w kierunkach różniących się o więcej niż 45°.
- **Autonomiczny odkrywca**: kamera patrzy na scenę, wybiera najbardziej
  znaczącą rzecz, robi krok w jej stronę, patrząc na nią, i zaczyna od
  nowa; na koniec spacer staje się trasą. Zobacz niżej.
- **Zdjęcia i galeria**: P robi zdjęcie tego, co widzisz; odkrywca sam
  fotografuje najciekawsze rzeczy swojego spaceru. Każda trasa otwiera swoją
  galerię w przeglądarce: zdjęcia z polaroidu na stole, z notatkami. Zobacz
  niżej.
- **Pad** XInput i rozglądanie się klawiaturą numeryczną.
- Panel ustawień w 36 językach.
- **Dostępność**: *Dostępność › Bez błysków* wyłącza każdy błysk, zdjęć i
  błyskawic (zob. [ACCESSIBILITY.md](.github/ACCESSIBILITY.md)).

Wymagania: SketchUp 2023 lub nowszy, w systemie Windows. Na Macu
rozszerzenie się instaluje, ale nie uruchamia, i o tym informuje.

## Instalacja

- Z **Extension Warehouse** SketchUpa (wersja podpisana) albo
- pobierz **`dagawasd-<wersja>-warehouse.rbz`** z
  [najnowszej wersji](https://github.com/Dagadam/dagawasd/releases/latest) (w sekcji *Assets*) i zainstaluj
  przez *Rozszerzenia › Extension Manager › Zainstaluj rozszerzenie*. Drugi
  plik, `dagawasd-<wersja>.rbz`, zawiera dodatkowo most dla Claude Code
  (zobacz *Dwa pakiety*).

Ustawienia są zapisywane w `%APPDATA%\DagaWASD\settings.json`: aktualizacja
ich nie usuwa.

## Autonomiczny odkrywca

Przycisk z okiem na pasku (lub *Rozszerzenia › DagaWASD › Autonomiczny
odkrywca*): małe okno pozwala wybrać profil (jego charakter, zobacz niżej)
oraz czy nagrać spacer jako trasę, i zapamiętuje wybór na następny raz;
strzałki i Enter albo dwuklik na profilu, by od razu ruszyć. Ten sam
przycisk zatrzymuje go podczas eksploracji. Cykl: **analiza → wybór punktu
→ krok w stronę punktu, patrząc na niego → analiza**.

- **Analiza**: siatkówka promieni przechodzących przez siatkę ekranu
  (`view.pickray` + `model.raytest`) daje dla każdej komórki odległość,
  normalną, ścianę, obiekt i kolor. Stąd wyrazistość: krawędzie głębi,
  krawędzie, detal, kontrast barw (Lab), rzadkość, komponenty i grupy w
  ludzkiej skali; duże ściany i podłogi liczą się mało. Ważona odległością,
  środkiem widoku i nowością.
- **Pamięć**: woksele tego, co spojrzenie już widziało, miejsca już
  przedeptane (w rzucie i wysokości: piętro wyżej pozostaje nowe), nuda
  wobec celu i kategorii (po jednej kanapie kolejne takie same ciekawią
  mniej): dzięki temu nie wraca ciągle do tych samych rzeczy.
- **Mapa tego, co widział**: pieszo promienie biegnące na wysokości ciała
  zaznaczają na mapie z komórkami 50 cm (jedna na piętro) widzianą podłogę z
  jej wysokością (podłoga, stopnie, blaty mebli) oraz trafione ściany. Służy
  do dwóch rzeczy:
  - **granice**: brzeg między tym, co widział, a tym, czego nigdy nie
    widział (za drzwiami, za rogiem), staje się celem, «niezbadanym
    obszarem»: idzie tam i zagląda do środka. Waży jak otwarta przestrzeń,
    zależnie od chęci do chodzenia w profilu; na mapie uwagi to fioletowe
    kwadraciki na podłodze;
  - **planowane trasy**: dla każdego celu planuje drogę na mapie (A*) do
    punktu, z którego cel widać: wokół ścian i mebli z pewnym odstępem, po
    schodach w górę (stopień po stopniu tak, stół czy kanapa nie) i po
    rampach do maksymalnego nachylenia gracza, prosto tam, gdzie się da. Tam,
    gdzie jeszcze nie patrzył, jest optymistą i próbuje. Przy każdej analizie
    sprawdza resztę drogi na nowej mapie i jeśli jest zablokowana, szuka
    innej; co 3 s i tak planuje od nowa (może zobaczył skrót); gdzie się
    zderzy, zaznacza to i przelicza. Jeśli cel zniknie za czymś albo droga od
    niego odbiega, patrzy, dokąd idzie. Bieżąca droga to przerywana linia na
    podłodze. Wyszukiwanie działa w kawałkach, jak analiza.
- **Krok**: w stronę punktu, omijając przeszkody, wchodząc po schodach,
  nigdy nie schodząc z krawędzi; zatrzymuje się w odległości, z której
  obiekt widać w całości, i patrzy na niego. Z widoku z lotu ptaka leci i
  ląduje tam, gdzie jest coś do zobaczenia.
- **Obchodzenie obiektów**: po dotarciu do obiektu, jeśli profil tego chce
  (*Obchodzi obiekty*, w stopniach: Fotograf 180°, Ciekawski 90°), obchodzi
  go, patrząc na niego, od strony najbardziej wolnej, aby zobaczyć go z
  wielu stron; jeśli droga się zamknie, zawraca. Potem postój.
- **Skok**: niską przeszkodę, która blokuje drogę (murek, płot, wysoki
  stopień) i której nie da się krótko obejść, przeskakuje, jeśli za nią
  jest powierzchnia do lądowania. Używa siły skoku i grawitacji gracza (przy
  domyślnych wartościach stopy unoszą się o 1,08 m; przeskakuje to, co jest
  niższe niż 85 % tej wysokości); nigdy nie wskakuje na siedzenia i stoły.
  Można to wyłączyć w profilu (Powolny nie skacze).
- **Ciało**: wysokość oczu, promień, stopień (najwyżej 25 cm), skok i
  grawitacja są takie jak gracza (panel › Gracz), także gdy zmienisz je
  podczas eksploracji.
- **Płynność**: jak budowanie na żywo przez most, analiza to Fiber, który
  pracuje w kawałkach między jedną klatką a następną; siatkówka gęstnieje
  lub rzednie zależnie od kosztu jednego promienia w danym modelu. Z
  *System › Wydajność › Analiza adaptacyjna* także częstotliwość analiz
  podąża za wolną mocą obliczeniową, między minimum a maksimum na sekundę,
  bez spowalniania chodu.
- **Sterowanie**: Esc lub kliknięcie, by go zatrzymać, prawy przycisk na
  pauzę, «Poszukaj czegoś innego», mapa uwagi, oko kolorowe; kółko myszy
  dla prędkości; I ukrywa lub pokazuje wiersze informacji w lewym górnym
  rogu. Inne narzędzie go zatrzymuje; orbitowanie środkowym przyciskiem go
  wstrzymuje, a on rusza dalej z miejsca, w którym ustawiłeś kamerę.
- **Utknął?** Jeśli w ciągu 10 sekund nie przesunie się o 75 cm (niezdecydowany
  między bliskimi celami, zamknięty w kącie), szuka drogi ucieczki wśród 12
  kierunków i podąża nią przez kilka sekund; jeśli pieszo nie ma drogi, a
  tryb jest automatyczny, wzbija się w powietrze.
- **Na koniec**, jeśli przy starcie zostawiłeś zaznaczone «Nagraj trasę»,
  spacer staje się trasą («Eksploracja 1», …): z panelu możesz ją obejrzeć
  ponownie albo zrobić z niej sceny lub film.

### Profile

Charakter odkrywcy to **profil**, zestaw współczynników: *Rozszerzenia ›
DagaWASD › Profile odkrywcy…* albo prawy przycisk podczas eksploracji ›
*Profil* (zmiana w locie) i *Edytuj profile…*.

| Profil | Charakter |
|---|---|
| Zrównoważony | ten co zwykle |
| Ciekawski | szybko się nudzi, szuka detali i rzadkich rzeczy, więcej eksploruje, obchodzi obiekty o 90° |
| Biegacz | 3,2 m/s, szybki refleks, krótkie postoje |
| Powolny | 0,5 m/s, długie postoje, spojrzenie obraca się powoli |
| Fotograf | zanim podejdzie, przybliża cel (zoom), potem idzie i obchodzi go o 180° |
| Beztroski | kapryśne wybory, łatwo zmienia zdanie, kocha otwartą przestrzeń |
| Żołnierz | zwiad, zawsze pieszo: 3,6 m/s, patrzy z daleka i krótko, najpierw idzie tam, gdzie jeszcze nie patrzył |

W oknie każdy współczynnik ma suwak (gdy go przeciągasz, odkrywca używający
tego profilu zmienia się na żywo) i ↺, które przywraca pierwotną wartość.
Grupy: ruch (prędkość, odległość zatrzymania, stopień, pieszo/w locie),
spojrzenie (obrót, refleks, **ciągłość** — jak chętnie przechodzi do tego,
co jest obok oglądanej rzeczy, zamiast wracać do tego, od czego już się
odwrócił), uwaga (postój, obchodzenie obiektów, czas, **zdecydowanie** —
przez ile sekund nie zmienia zdania co do świeżo wybranego celu — i
**wierność**), ciekawość (pamięć, nuda, chęć do chodzenia, kaprys), co go
przyciąga (wagi obiektów, sylwetek, detalu, koloru, rzadkości) i zoom.
«Nowy» kopiuje używany profil; gotowe profile można zmieniać, a potem
przywrócić.

W `settings.json`: `"explore_profile"` (używany), `"explore_profiles"`
(twoje własne i zmiany w gotowych) oraz `"explore_record"` (pole trasy w
oknie startowym). Wartości nakładają się warstwami: domyślne
(`EX_DEFAULTS`, `lib/explore.rb`) ← `"explore": { … }` ← profil ← opcje
tego, kto go uruchamia (most).

Przy włączonym moście Claude Code nim steruje i go obserwuje (polecenia
narzędzi deweloperskich są po włosku):

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # start: 120 s, 1,3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # profil tylko na ten spacer
ruby tools/esplora.rb profili                      # lista; «profilo NAZWA» ustawia go jako używany
ruby tools/esplora.rb segui --foto esplorazione    # jeden wiersz i jedno zdjęcie na każdy wybór
ruby tools/esplora.rb ferma                        # zatrzymuje i zapisuje trasę
```

### SI za kierownicą

Z `pilota` i `guida` to Claude Code decyduje, dokąd iść, a odkrywca nadal
sam chodzi i patrzy (`lib/expilot.rb`). Każda widziana rzecz ma krótką,
stałą nazwę (`o12` obiekt, `s7` ściana, `F3` niezbadany obszar); SI wpisuje
cele do planu, a odkrywca osiąga je po kolei własnymi krokami, własnymi
objazdami wokół ścian i własnym spojrzeniem. Gdy plan jest pusty, znów
wybiera sam: nigdy nie staje, by czekać na SI.

```
ruby tools/esplora.rb pilota                       # czeka na zdarzenie i opisuje, co widzi
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "Ołtarz główny" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # odwraca się, by patrzeć, bez ruchu
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # nowy plan: punkt w metrach
ruby tools/esplora.rb guida --svuota               # bez planu: znów wybiera sam
ruby tools/esplora.rb guida --foto                 # zdjęcie na bieżącym (lub następnym) postoju
ruby tools/esplora.rb guida --foto-sempre          # zdjęcie na każdym postoju (--foto-mete: tylko przy celach SI, --senza-foto)
```

Zdarzenia, które budzą `pilota`: cel osiągnięty, cel wykonany (lub
porzucony, i dlaczego), plan prawie pusty lub pusty, cel nieosiągalny, coś
godnego uwagi, czego nigdy nie widział, zdjęcie.

**Pieszo: dokąd się dojdzie.** Podczas chodzenia opis mówi dla każdej
rzeczy i niezbadanego obszaru, czy da się tam dojść (`reach`: tak, może
przez nigdy niewidziane obszary, nie) i ile metrów drogi to zajmie
(`walk_m`), na podstawie mapy, którą odkrywca zrobił, patrząc. «Idź» do
czegoś, do czego pieszo się nie dojdzie, jest od razu odrzucane z podaniem
przyczyny; na zdjęciach takie rzeczy mają jasnoszarą etykietę. Na Stromboli
autonomiczny pilot przeszedł z około jednego osiągniętego celu na minutę do
trzech.

**Zdjęcia z etykietami.** Na postojach przed celami SI odkrywca, stojąc
nieruchomo i patrząc na cel, robi obraz widoku (800 px) i pisze obok każdej
widocznej rzeczy jej krótką nazwę: cel na żółto, obiekty na niebiesko,
ściany na szaro, niezbadane obszary na fioletowo. Dzięki temu SI widzi,
czym są «Grupa2577#2» i podobne, i wskazuje je po nazwie. Zdjęcia są w
`%APPDATA%\DagaWASD\pilota` (ostatnie 40). Zdjęcie blokuje SketchUp na czas
jednego obrazu widoku (pół sekundy przy dużym modelu): dlatego tylko w
bezruchu.

Na moście: `GET /explore/percept?since=N` (opis i zdarzenia), `GET
/explore/wait?since=N&timeout=60` (ten sam opis, ale most odpowiada dopiero,
gdy jest budzące zdarzenie: `pilota` nie pyta bez przerwy) oraz `POST
/explore` z `{"cmd": "steer", …}`.

**Komentarze w filmie.** To, co mówi SI (`--commento`, `--di` lub `say` w
steer), zostaje w nagranej trasie, w chwili, gdy to powiedziała: staje się
opisem najbliższej sceny przy tworzeniu scen oraz plikiem napisów `.srt`
obok filmu (AVI: ta sama nazwa, odtwarzacze otwierają go same; obrazy PNG:
`crea_video.bat` wkłada go do MP4).

**Autonomiczny pilot.** `tools/pilota_ia.rb` prowadzi sam, bez poleceń po
jednym: czeka na zdarzenia mostu, wysyła Claude'owi opis i zdjęcie z
postoju i przekazuje mostowi to, co Claude postanowi. Domyślnym silnikiem
jest sam Claude Code (`claude -p`, z kontem tego komputera: bez klucza); gdy
ustawiony jest `ANTHROPIC_API_KEY`, używa API Claude (gem `anthropic`). Na
Stromboli jedna tura trwa 4–5 s. Każda tura kosztuje: `--turni` (20) i
`--secondi` (300) ustalają limit, a na koniec wypisuje zużyte tokeny.

```
ruby tools/esplora.rb avvia --a-piedi                   # start, pieszo
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # mały wysiłek: odpowiedzi w kilka sekund
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # API, z kluczem
```

## Zdjęcia i galeria

Podczas chodzenia **P** (zmienisz w *System › Sterowanie*; na padzie prawy
przycisk na ramieniu, RB) robi zdjęcie widoku, bez celownika i napisów, z
błyskiem. Jeśli nagrywasz trasę, zdjęcie trafia do niej; jeśli nie, do
osobnej serii, jednej za każdym razem, gdy wchodzisz w ten tryb.

Odkrywca fotografuje sam, gdy spacer staje się trasą: najciekawsze cele
spośród dotąd widzianych, gdy spojrzenie na nich spocznie i widzi je
dostatecznie duże (wiele celów ogląda, nie docierając do nich), albo po
dotarciu; przestrzenie, które od czasu do czasu się otwierają; nigdy z
miejsca, w którym już robił zdjęcie, nigdy częściej niż jedno zdjęcie na 8
sekund (najwyżej 30 na spacer). Do każdego zdjęcia pisze, **co** na nim jest
(rzecz, jak duża, jak daleko, co jest wokół) i **dlaczego** je wybrał:
najciekawsze do tej pory, wyróżniający się kolor, nic podobnego w polu
widzenia, dużo detali, sylwetka odcinająca się od tła, obiekt z wielu
części, widok. SI, która nim kieruje, prosi o własne zdjęcia przez `snap`
(swoje dlaczego) i `say` (co).

Zdjęcia są zapisywane obok modelu, w `<model>_foto/<data i godzina>/`, jako
JPG 1600 px, z `galleria.json`; trasa zapamiętuje folder względem modelu,
więc znajdzie go, jeśli model zostanie przeniesiony razem ze zdjęciami. Dla
modelu nigdy niezapisanego albo gdy obok modelu nie da się zapisywać, trafiają
do `%APPDATA%/DagaWASD/foto`.

W *Kamera › Trasy* każda trasa ma swój przycisk **📷** obok Wideo: z liczbą
zdjęć otwiera galerię w przeglądarce; wyszarzony, jeśli trasa nie ma
zdjęć, a kliknięcie wyjaśnia, jak je zrobić. Pod listą są serie, których
nie ma w żadnej trasie (zdjęcia spoza nagrania, usunięte trasy).

Galeria to jedna strona, `galleria.html` w folderze zdjęć, tworzona od
nowa przy każdym otwarciu w języku SketchUpa. Zdjęcia to polaroidy na
drewnianym stole, które wywołują się, gdy pojawiają się w widoku, każde z
karteczką notatek: co, dlaczego, kto je zrobił, kompas z kierunkiem
spojrzenia i godzina. Ogląda się je na dwa sposoby:

- **w rzędzie**: przewijają się w bok kółkiem myszy, strzałkami,
  przeciąganiem albo z paska filmu na dole (miniatury). U góry jest spacer
  narysowany ołówkiem: ponumerowane zdjęcia ze stożkiem tego, na co
  patrzyły, skala, północ, kierunek. Mała mapka w rogu podąża za bieżącym
  zdjęciem. Komentarze SI są na karteczkach samoprzylepnych w swoim miejscu
  spaceru, a na końcu jest karta z czasem, przebytą drogą i zdjęciami;
- **rozrzucone na stole**: zdjęcia bierze się i przesuwa myszą (lub palcem,
  lub strzałkami), a układ zostaje na następny raz. *Uporządkuj* znów
  układa je w rzędy.

Kliknięcie otwiera zdjęcie w dużym rozmiarze, z *Pokazem slajdów* (jedno
po drugim; spacja wstrzymuje). Przy zdjęciach kilku autorów (ty, odkrywca,
SI) pieczątki u góry je filtrują. `#3` w adresie prowadzi do zdjęcia 3,
`#3z` otwiera je w dużym rozmiarze. Strona drukuje się czysto (zdjęcia z
notatkami), działa bez sieci i można ją wysłać komuś razem z folderem.

**Edytuj** zmienia teksty tam, gdzie są, tym samym pismem: tytuł galerii i
każdego zdjęcia, *Co*, *Dlaczego*, pieczątkę i notatki AI; ✕ usuwa zdjęcie z
galerii (plik zostaje), a ↺ je przywraca. Teksty SketchUpa nigdy nie giną:
każdy może wrócić do oryginału. Zmiany od razu zostają w przeglądarce;
*Zapisz w folderze* (Edge, Chrome) zapisuje je w `galleria_modifiche.json`
obok zdjęć i w samej stronie, więc podróżują razem z folderem.

## Dwa pakiety

`tools\crea_rbz.bat` tworzy w `dist\`:

- `dagawasd-<wersja>.rbz`: pełny, z **mostem dla Claude Code**
  (`lib/bridge.rb`), serwerem działającym tylko lokalnie, wyłączonym, dopóki
  nie włączysz go w panelu, przez który Claude Code rysuje w otwartym
  modelu;
- `dagawasd-<wersja>-warehouse.rbz`: bez mostu, do Extension Warehouse. Bez
  `lib/bridge.rb` rozszerzenie działa tak samo.

## Rozwój

Kod, jego komentarze i dziennik zmian są po włosku.

- `installa.bat` kopiuje źródła do folderu Plugins każdego znalezionego
  SketchUpa.
- `tests\run_tests.bat` uruchamia testy (Ruby, z symulowanym SketchUpem;
  panel w symulowanej przeglądarce z Node).
- `tools\controlla_warehouse.bat` sprawdza pakiet według reguł Trimble
  (rubocop-sketchup).
- Numer wersji jest tylko w `dagawasd.rb` (`VERSION`); każda wersja ma swoją
  sekcję w `CHANGELOG.md`.
- Ikony powstają z plików SVG w `pubblicazione/`: `tools\rendi_icone.bat`
  tworzy na nowo ikony paska (`icons/`) i ikonę strony Warehouse
  (`pubblicazione/icona_512.png`).
- Strona dla Extension Warehouse (teksty po angielsku i uwagi dla
  recenzentów) jest w `pubblicazione/extension_warehouse.md`.
- Ten README istnieje w wielu językach (`README.md` po angielsku,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.nl`, `.sv`, `.pl`, `.cs`, `.ru`, `.ja`, `.ko`, `.zh`):
  zmiana trafia do wszystkich.
- W otwartym SketchUpie, z włączonym mostem i włączonym w panelu «Okna i
  klawisze» (narzędzia dla Claude Code, nieinstalowane):
  - `tools\finestre.ps1` sięga tam, gdzie Ruby nie sięga: natywne okna,
    komunikaty, menu, przechwytywanie widoku z niebem i chmurami, symulowane
    klawisze i prawdziwe kliknięcia w widoku 3D (na przykład dwuklik na
    kuli);
  - `tools\collaudo.rb` testuje na żywo przycisk i menu panelu, potwierdzenie
    «Usuń» i film aż do okna końcowego;
  - `tools\schermate.rb` tworzy obrazy strony w `pubblicazione/schermate/`
    (1920×1080, z ekranem co najmniej takiej wielkości);
  - `tools\prova_fps.rb` chodzi i biega w trybie FPS i mierzy kołysanie
    głowy.

## Kontakt

Napisz na [DagaWASD@icloud.com](mailto:DagaWASD@icloud.com). Błędy i pomysły lepiej zgłaszać jako
[issue](https://github.com/Dagadam/dagawasd/issues), gdzie inni mogą je zobaczyć i śledzić;
problemy z bezpieczeństwem zgodnie z [polityką bezpieczeństwa](.github/SECURITY.md).

Jeśli DagaWASD jest dla ciebie przydatny, możesz wesprzeć jego rozwój na [Ko-fi](https://ko-fi.com/dagadam).

## Licencja

[MIT](LICENSE) © 2026 Dagadam. Możesz swobodnie używać, zmieniać i
rozpowszechniać kod, także komercyjnie, pod warunkiem że każda kopia
zachowa informację o prawach autorskich i tekst licencji.
