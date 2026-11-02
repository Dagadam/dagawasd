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

**Camera paths.** Press R while walking to record what you see (mouse-wheel
zoom included). Replay it, turn it into SketchUp scenes, or export it as an
AVI video or PNG images. Fine-tune it right in the model: each key position
is a sphere with an arrow (its length shows the zoom) and the camera frame
with a triangle on top (it tilts when you roll the camera); move and rotate
them with SketchUp's own tools, Ctrl+Move to add one, or start a new path
from the current view. Double-click a sphere (or select it and press Enter)
to open its panel: position, look direction, roll, zoom, pause and speed,
with − and + buttons, a live preview from the sphere and smooth dolly moves
to the previous or next one.
While the video is being written, a little character keeps you company with
a progress bar, statistics about your walk and model, and jokes made from
those numbers.

**Autonomous explorer.** Press the eye button and the camera explores the
model by itself: it looks at the scene, picks the most significant thing in
view (objects that stand out by shape, detail, colour and rarity, not bare
walls), takes a step towards it while turning to look at it, and repeats.
It walks around obstacles, climbs stairs, never steps off a ledge, flies in
from an aerial view and lands where there is something to see, and gets
bored of what it has already seen, so it keeps discovering new rooms. An
attention map shows what it finds interesting; when you stop it, the walk is
saved as a camera path, ready to become scenes or a video.

**Photos and gallery.** Press P while walking (or RB on the gamepad) to
take a photo of the view. The explorer takes its own: the most interesting
things of its walk, each with a note on what it shows and why it was chosen.
The camera button on every path opens its gallery in the browser: instant
photos that develop on a wooden table, with handwritten notes, a film strip
of thumbnails, the route sketched in pencil with where each photo looked,
and a slideshow. Lay them out in a row or scatter them on the table and move
them around by hand. Photos are saved next to the model as JPG files.

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
  foreground window) and Ctrl+Home (open the settings panel), plus Enter,
  which opens a path sphere's panel only when SketchUp's main window is in
  front, the Select tool is active and exactly one sphere is selected. It
  reads no other keys and does nothing else.
- **Clipboard.** The panels replace the browser context menu with their own
  translated Cut/Copy/Paste menu. Paste reads the clipboard text
  (CF_UNICODETEXT) only when the user picks Paste, and inserts it into the
  text box; it is never stored or sent anywhere.
- **Keyboard hook only while walking.** During first-person mode a
  low-level keyboard hook keeps the movement keys from reaching SketchUp's
  shortcuts. It is installed when walking starts and removed when it stops.
- **No network access.** The Extension Warehouse package contains no server,
  no HTTP requests and no `eval` of external code (the optional local bridge
  for Claude Code is only in the developer package and is not included).
- **Files.** Writes only to `%APPDATA%\DagaWASD` (settings and an error log),
  to the files the user picks for video/image export, and to one temporary
  JPEG in `%TEMP%`, deleted at the end of each export. Photos taken while
  walking (P) or by the explorer go to a `<model name>_foto` folder next to
  the model (`%APPDATA%\DagaWASD\foto` for an unsaved model or a read-only
  folder), with a JSON index and a static `galleria.html` built from a
  template in the extension; the camera button opens that local page in the
  default browser with `UI.openURL` (no network, no scripts from outside).
  With the explorer's optional "colour eye" a small temporary BMP of the
  view is written to `%TEMP%` and deleted right after reading it. Never writes into the
  extension folder.
- **Explorer.** It only moves the camera (`View#animation`, ray tests through
  the view) and is stopped by Esc, a click or any other tool; its walk is
  saved as a camera path in one undoable operation.
- **Model changes.** Physics moves are wrapped in operations and undone with
  Ctrl+Z. Recorded camera paths are stored in an attribute dictionary of the
  model (`DagaWASD_percorsi`). Only when the user clicks Edit (or New from
  view) on a path, its key positions are added as component instances
  (definitions «DagaWASD camera <fov>°», one per zoom level, with materials
  «DagaWASD …») on the tag «DagaWASD percorsi», in one undoable operation;
  deleting the path or reverting removes them and any definition left unused.
  Edits made in a sphere's panel, and "Thin cameras" (after a confirmation,
  merges spheres piled on top of each other into one and erases the
  others), are undoable operations too; a model
  observer (onActivePathChanged) only notices a double-click into a sphere,
  closes it again and opens the panel.
- **Loading.** All files are loaded with `Sketchup.require`; the package
  works signed and encrypted (.rbe). Checked with rubocop-sketchup 1.5.0:
  no offences.
