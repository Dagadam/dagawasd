DagaWASD 1.3.0: a real **Export video** window (long videos in pieces,
redo a stretch, audio, draft, contact sheet, export log), weather in the
video, changing weather, full screen walking, an accessibility switch for
flashes, an editable photo gallery and DagaDyn animated objects.

Windows only, SketchUp 2023 or later. All changes are in
[CHANGELOG.md](https://github.com/Dagadam/dagawasd/blob/main/CHANGELOG.md) (in Italian).

▶ Official presentation: https://youtu.be/8eBvtl7DiKU

DagaWASD is **not on the Extension Warehouse yet**: for now, download it
from here (see *Which file should I download?* below).

## What's new

- **Export video window.** *Paths › Video* no longer starts right away: it
  opens a window with format, size, fps, speed, weather, where to save
  (**Browse…**) and **which frames**, from x to y, as numbers or as video
  times (`3:43`, `1:02:05.5`). A **Basic | Advanced** switch keeps the
  essentials in front; a dot on *Advanced* warns when a hidden choice is
  not the usual one.
  - **Long videos in pieces**: a DagaWASD AVI can be **appended to**, so a
    long video is made one piece at a time and stays a single file. A video
    left half-written because SketchUp closed can be resumed (*Resume from
    …*). A piece that starts in the middle has the same weather as a full
    export.
  - **Redo a stretch**: re-export only some frames inside an existing
    video; all the other frames stay identical, byte for byte.
  - **Audio**: a `.wav` file (PCM) goes into the AVI, starting with frame 1.
  - **Draft**: the whole path at half size and 5 frames per second, in a
    separate file, to check it before the real video.
  - **Contact sheet**: a PNG next to the video with a frame every few
    seconds and its time.
  - **JPEG quality** from 50 to 100 (90 by default).
  - **When finished**: a sound, and if you want, **sleep** or **shut down**
    the PC after 2 minutes, with a countdown and *Cancel*. The PC does not
    go to sleep during the export.
  - **Export log** next to the video (`.log`), in the interface language:
    model, path, video, weather, every piece exported, time left, warnings.
    It updates every 5 seconds, so you know where you were even if
    SketchUp closes.
- **Weather in the video** (on by default): sun, moon, stars, clouds, rain,
  snow and lightning also appear in exported frames, AVI or PNG. Sky and
  weather follow the video's own clock, so two identical exports give the
  same video.
- **Changing weather** (*Weather › Date & time*): clear sky, clouds, rain,
  thunderstorm, overcast, snow… a new front every 4 hours of sky time,
  changing smoothly. New ready-made scene **Mixed bag**: changing weather
  as a time-lapse.
- **Full screen** (*Camera › View*, off by default): while walking, the 3D
  view covers the whole monitor; Esc brings the window back as it was.
- **Accessibility › No flashes**: no white flash when taking a photo and
  no lightning in thunderstorms. See
  [ACCESSIBILITY.md](https://github.com/Dagadam/dagawasd/blob/main/.github/ACCESSIBILITY.md).
- **Editable gallery**: change titles, notes and comments where they are,
  in the same handwriting; remove a photo from the gallery and put it back.
  Edits can be saved in the photo folder, so they travel with it.
- **DagaDyn animated objects** (if DagaDyn 0.2.0 or later is installed):
  they move while you walk, explore, replay a path and in videos. Moving
  platforms carry you along. Without DagaDyn nothing changes.
- **▶ in a sphere's panel**: replays the path starting from that sphere.
- **Own turn speed per sphere** (`giro` attribute, degrees per second, set
  by script), for spots where the camera must turn really fast, such as a
  spiral staircase.

## Fixes

- Videos with weather: no more shimmering sea where the model goes below
  SketchUp's ground, no more grey dashed outlines around things against the
  sky, no more thin dark line above the sea horizon.
- **Start** minimizes the settings panel, so you can walk right away.
- The autonomous explorer: fast profiles now stop at their own distance
  instead of sliding into objects; the Carefree profile no longer changes
  its mind every half second; a Soldier started above the void now lands.
- `crea_video.bat` works with `%` and non-ASCII letters in the path;
  redoing a path's scenes no longer removes a user scene with the same
  name; `installa.bat` works with a `!` in the path; and a few smaller
  fixes listed in the changelog.

## Which file should I download?

| File | For |
|---|---|
| **`dagawasd-1.3.0-warehouse.rbz`** | **Everyone.** This is the version you want. |
| `dagawasd-1.3.0.rbz` | Only if you use **Claude Code**: it also contains the *Claude bridge* (see the [1.0.0 release](https://github.com/Dagadam/dagawasd/releases/tag/v1.0.0)). |

Install from *Extensions › Extension Manager › Install Extension*, over the
previous version. Your settings live in `%APPDATA%\DagaWASD` and are kept.

---

## In italiano

**Novità.** *Percorsi › Video* apre la finestra **Esporta video**: quali
fotogrammi (anche come tempi, `3:43`), **in coda** a un video esistente per
farlo a pezzi, **riprendi** un video rimasto a metà, **rifai un tratto**
dentro il video, **audio** `.wav`, **bozza** veloce, **foglio di
controllo**, qualità JPEG, suono e sospendi o spegni il PC alla fine, e il
**registro** `.log` accanto al video. Il **meteo entra nel video**; c'è il
**meteo variabile** e la situazione **Miscellanea**. Poi lo **schermo
intero** mentre cammini, **Accessibilità › Niente lampi**, la **galleria
modificabile**, gli **oggetti animati di DagaDyn**, il tasto **▶** nel
pannello della sfera e il **giro proprio** di una sfera.

**Correzioni.** Nei video col meteo il mare non sfarfalla più e spariscono
contorni tratteggiati e righe scure all'orizzonte; *Avvia* riduce a icona
il pannello; l'esploratore si ferma alla sua distanza; e altre ancora,
tutte nel [CHANGELOG](https://github.com/Dagadam/dagawasd/blob/main/CHANGELOG.md).

DagaWASD **non è ancora nell'Extension Warehouse**: per ora si scarica da
qui. **Quale file scaricare?** `dagawasd-1.3.0-warehouse.rbz` va bene per
tutti; `dagawasd-1.3.0.rbz` solo per chi usa Claude Code.

▶ Presentazione ufficiale: https://youtu.be/8eBvtl7DiKU
