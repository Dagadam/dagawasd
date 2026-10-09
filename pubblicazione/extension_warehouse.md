# Extension Warehouse — scheda e note per i revisori

Testi pronti da incollare nel portale per sviluppatori
(extensions.sketchup.com), in inglese. Il pacchetto da firmare e caricare è
`dist/dagawasd-<versione>-warehouse.rbz` (senza il ponte per Claude Code),
creato con `tools\crea_rbz.bat` e controllato con
`tools\controlla_warehouse.bat`.

## Dati della scheda

| Campo | Valore |
|---|---|
| Name | DagaWASD |
| Short description | Walk through your model in first person with WASD and mouse or a gamepad, with object physics, sky, weather and camera paths. |
| Category | Animation / Visualization |
| Platforms | Windows only |
| SketchUp versions | 2023, 2024 (and later) |
| Price | Free |
| License | MIT |
| Source code | https://github.com/Dagadam/dagawasd |
| Icon | `pubblicazione/icona_512.png` |

## Description

DagaWASD turns your SketchUp model into a place you can walk through, like a
video game. Click the toolbar button (or press Ctrl+PgUp), move with WASD and
the mouse, and press Esc to stop. Everything you moved is undone with a single
Ctrl+Z.

**Walking.** Inertia, running, crouching, variable jump, automatic stairs and
slopes, a subtle head bob, and a safe return to the ground if you fall into
the void. Xbox-compatible gamepads and the numeric keypad work too.

**Object physics.** Groups and components become real objects as soon as you
touch them: they fall, bounce, slide and tip over, with mass, friction and
bounciness taken from their material (wood, stone, metal, glass, rubber…).
Kick them, grab them, throw them, push them.

**Sky and weather.** Sun, moon (with its phases) and stars for the date, time
and location of the model. Rain and snow around the camera with wind and
shelter under roofs, drifting clouds, thunderstorms with lightning, and snow
that settles on roofs and terrain and then melts. Seven ready-made scenes,
such as "Summer storm" and "Snowy night".

**Camera paths.** Press R while walking to record what you see. Replay it,
turn it into SketchUp scenes, or export it as an AVI video or PNG images.
While the video is being written, a little character keeps you company with
a progress bar, statistics about your walk and model, and jokes made from
those numbers.

**Settings.** Speeds, jump, field of view, mouse, keys, object behaviour,
themes and crosshair, with export and import. The interface is available in
36 languages, including right-to-left Arabic and Hebrew.

Settings are stored in `%APPDATA%\DagaWASD`, so updates never erase them.

## Notes for the reviewers

- **Windows only.** Mouse capture, keyboard state and gamepads use the Win32
  API (user32, kernel32, XInput) through Fiddle. On macOS the extension
  registers, does not load, and says so once.
- **Hotkey timer.** A 50 ms timer checks two shortcuts with
  GetAsyncKeyState: Ctrl+PgUp (start walking, only when SketchUp is the
  foreground window) and Ctrl+Home (open the settings panel). It reads no
  other keys and does nothing else.
- **Keyboard hook only while walking.** During first-person mode a
  low-level keyboard hook keeps the movement keys from reaching SketchUp's
  shortcuts. It is installed when walking starts and removed when it stops.
- **No network access.** The Extension Warehouse package contains no server,
  no HTTP requests and no `eval` of external code (the optional local bridge
  for Claude Code is only in the developer package and is not included).
- **Files.** Writes only to `%APPDATA%\DagaWASD` (settings and an error log),
  to the files the user picks for video/image export, and to one temporary
  JPEG in `%TEMP%`, deleted at the end of each export. Never writes into the
  extension folder.
- **Model changes.** Physics moves are wrapped in operations and undone with
  Ctrl+Z. Recorded camera paths are stored in an attribute dictionary of the
  model (`DagaWASD_percorsi`).
- **Loading.** All files are loaded with `Sketchup.require`; the package
  works signed and encrypted (.rbe). Checked with rubocop-sketchup 1.5.0:
  no offences.
