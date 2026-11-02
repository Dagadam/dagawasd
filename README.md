# DagaWASD

**English** · [Italiano](README.it.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Nederlands](README.nl.md) · [Svenska](README.sv.md) · [Polski](README.pl.md) · [Čeština](README.cs.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [中文](README.zh.md)

A SketchUp extension (Windows): walk through your model in first person with
WASD and the mouse, or with a gamepad.

▶ Demo video: https://youtu.be/w6xE86y7iEw?is=7Gh12tF7atE_N9_K

⬇ **Download**: [latest release](https://github.com/Dagadam/dagawasd/releases/latest) (all versions: [Releases](https://github.com/Dagadam/dagawasd/releases))

## What it does

- **Walking**: inertia, running, crouching, jumping, stairs and slopes, and
  a safe return to the ground if you fall into the void.
- **Object physics**: groups and components fall, bounce and tip over
  according to their material; you can kick, grab and throw them.
- **Sky and weather**: sun, moon and stars for the date, time and location;
  rain, snow, clouds, thunderstorms, snow settling on the ground.
- **Camera paths**: record the camera while you walk, replay it, export it as
  scenes or as an AVI video. Fine-tune it in the model by moving and rotating
  its positions (spheres with an arrow as long as the zoom, and the camera
  frame), or build one from scratch. In the panel every path opens onto the
  list of its positions; clicking a position, or double-clicking its sphere
  (or pressing Enter), opens its settings with a preview of what it sees, and
  a click between two positions adds one from the current view. During replay
  the list lights up the current position. «Thin cameras» merges spheres
  piled on top of each other into one, their average (position, look, zoom),
  as long as they look no more than 45° apart.
- **Autonomous explorer**: the camera looks at the scene, picks the most
  significant thing, takes a step towards it while looking at it, and starts
  again; in the end the walk is a path. See below.
- **Photos and gallery**: P takes a photo of what you see; the explorer
  photographs the most interesting things of its walk by itself. Every path
  opens its gallery in the browser: instant photos on a table, with notes.
  See below.
- XInput **gamepad**, and looking around with the numeric keypad.
- Settings panel in 36 languages.

Requirements: SketchUp 2023 or later, on Windows. On a Mac the extension
installs but does not start, and says so.

## Installation

- From SketchUp's **Extension Warehouse** (signed version), or
- download **`dagawasd-<version>-warehouse.rbz`** from the
  [latest release](https://github.com/Dagadam/dagawasd/releases/latest) (under *Assets*) and install it from
  *Extensions › Extension Manager › Install Extension*. The other file,
  `dagawasd-<version>.rbz`, also contains the bridge for Claude Code (see
  *Two packages*).

Settings are stored in `%APPDATA%\DagaWASD\settings.json`: an update does
not erase them.

## Autonomous explorer

Eye button in the toolbar (or *Extensions › DagaWASD › Autonomous
explorer*): a small window lets you choose the profile (its character, see
below) and whether to record the walk as a path, and remembers your choices
for next time; arrows and Enter, or a double-click on a profile, to start
right away. The same button stops it while it explores. The cycle:
**analyse → pick the point → one step towards the point, looking at it →
analyse**.

- **Analysis**: a retina of rays across the screen grid (`view.pickray` +
  `model.raytest`) gives distance, normal, face, object and colour for every
  cell. From there, saliency: depth edges, creases, detail, colour contrast
  (Lab), rarity, human-sized components and groups; large walls and floors
  count little. Weighted by distance, centre of view and novelty.
- **Memory**: voxels of what the gaze has already seen, places already
  walked on (in plan and in height: the floor above stays new), boredom per
  target and per category (after seeing one sofa, other identical ones are
  less intriguing): so it does not keep going back to the same things.
- **Map of what it has seen**: on foot, the rays passing at body height mark
  on a map of 50 cm cells (one per floor) the floor seen, with its height
  (floor, steps, tops of furniture), and the walls hit. It serves two
  purposes:
  - **frontiers**: the edge between what it has seen and what it has never
    seen (beyond a door, around a corner) becomes a target, an «unexplored
    area»: it goes there and looks inside. It weighs like open space,
    according to the profile's urge to roam; in the attention map they are
    the purple squares on the floor;
  - **planned routes**: for every target it plans the way on the map (A*) to
    a point from which it can be seen: around walls and furniture, keeping a
    little distance, up the stairs (one step at a time yes, a table or a sofa
    no) and up slopes to the player's maximum slope, straight where it can.
    Where it has not looked yet it is optimistic and tries. At every analysis
    it rechecks the rest of the route on the new map and, if it is now
    blocked, looks for another; every 3 s it replans anyway (maybe it has
    spotted a shortcut); where it bumps into something, it marks it and
    replans. If the target disappears behind something, or the route turns
    away from it, it looks where it is going. The current route is the dashed
    line on the floor. The search works in slices, like the analysis.
- **Step**: towards the point, around obstacles, up the stairs, never off an
  edge; it stops at a distance from which the object is seen whole, and looks
  at it. From an aerial view it flies and lands where there is something.
- **Walking around objects**: once it reaches an object, if the profile asks
  for it (*Walks around objects*, in degrees: Photographer 180°, Curious 90°)
  it walks around it while looking at it, on the freer side, to see it from
  several sides; if the way closes it turns back. Then the pause.
- **Jumping**: a low obstacle blocking the way (a low wall, a fence, a large
  step) with no short way around is jumped over, if there is a surface to
  land on beyond it. It uses the player's jump force and gravity (with the
  defaults the feet rise 1.08 m; it jumps what is below 85 % of that
  height); it never jumps onto seats and tables. It can be turned off in the
  profile (Slow does not jump).
- **Body**: eye height, radius, step (at most 25 cm), jump and gravity are
  the player's (panel › Player), even when changed while it explores.
- **Smooth**: like the bridge's live building, the analysis is a Fiber that
  works in slices between one frame and the next; the retina grows or
  shrinks according to how much a ray costs in that model. With *System ›
  Performance › Adaptive analysis* the rate of analyses follows the spare
  computing power too, between a minimum and a maximum per second, without
  slowing down the walk.
- **Controls**: Esc or a click to stop it, right-click to pause, «Look for
  something else», attention map, colour eye; mouse wheel for the speed; I
  hides or shows the information lines at the top left. Another tool stops
  it; orbiting with the middle button suspends it, and it starts again from
  where you put the camera.
- **Stuck?** If it does not move 75 cm in 10 seconds (undecided between
  nearby targets, trapped in a corner), it looks for an escape route among 12
  directions and follows it for a few seconds; if there is no way on foot and
  the mode is automatic, it takes off.
- **At the end**, if you left «Record the path» ticked at the start, the walk
  becomes a path («Exploration 1», …): from the panel you can replay it, or
  turn it into scenes or a video.

### Profiles

The explorer's character is a **profile**, a set of coefficients:
*Extensions › DagaWASD › Explorer profiles…*, or right-click while it
explores › *Profile* (switch on the fly) and *Edit profiles…*.

| Profile | Character |
|---|---|
| Balanced | the usual one |
| Curious | gets bored quickly, looks for details and rare things, explores more, walks 90° around objects |
| Runner | 3.2 m/s, quick reflexes, short pauses |
| Slow | 0.5 m/s, long pauses, a gaze that turns slowly |
| Photographer | zooms in on the target before approaching, then goes there and walks 180° around it |
| Carefree | whimsical choices, changes its mind easily, loves open space |
| Soldier | reconnaissance, always on foot: 3.6 m/s, looks from afar and briefly, goes first where it has not looked yet |

In the window every coefficient has a slider (while you drag it, the
explorer, if it uses that profile, changes live) and a ↺ that restores the
original value. Groups: movement (speed, stopping distance, step, on
foot/flying), gaze (turning, reflexes, **continuity** — how much it prefers
to move on to what is next to what it is looking at, and not to go back to
what it has already turned away from), attention (pause, walking around
objects, duration, **determination** — for how many seconds it does not
change its mind about a target it has just picked — and **loyalty**),
curiosity (memory, boredom, urge to roam, whim), what attracts it (weights
of objects, silhouettes, detail, colour, rarity) and zoom. «New» copies the
profile in use; the ready-made profiles can be changed and then restored.

In `settings.json`: `"explore_profile"` (the one in use),
`"explore_profiles"` (yours, and changes to the ready-made ones) and
`"explore_record"` (the path checkbox of the start window). Values add up in
layers: defaults (`EX_DEFAULTS`, `lib/explore.rb`) ← `"explore": { … }` ←
profile ← options of whoever starts it (the bridge).

With the bridge on, Claude Code controls and watches it (the commands of
the developer tools are in Italian):

```
ruby tools/esplora.rb avvia --secondi 120 --velocita 1.3   # start: 120 s, 1.3 m/s
ruby tools/esplora.rb avvia --profilo Fotografo    # a profile just for this walk
ruby tools/esplora.rb profili                      # list; «profilo NAME» puts it in use
ruby tools/esplora.rb segui --foto esplorazione    # one line and one photo per choice
ruby tools/esplora.rb ferma                        # stop and save the path
```

### AI at the wheel

With `pilota` and `guida` it is Claude Code that decides where to go, while
the explorer keeps walking and looking by itself (`lib/expilot.rb`). Every
thing seen has a short, stable name (`o12` an object, `s7` a face, `F3` an
unexplored area); the AI puts destinations on an agenda, and the explorer
reaches them one after the other with its own steps, its own detours around
walls and its own gaze. With an empty agenda it goes back to choosing by
itself: it never stops to wait for the AI.

```
ruby tools/esplora.rb pilota                       # waits for an event and describes what it sees
ruby tools/esplora.rb guida --vai o12 --giro 90 --commento "The high altar" --vai F3
ruby tools/esplora.rb guida --guarda o7 --per 3    # turns to look, without moving
ruby tools/esplora.rb guida --piace label:colonna=2 --evita o4
ruby tools/esplora.rb guida --sostituisci --punto 12,4,1.7   # new agenda: a point in metres
ruby tools/esplora.rb guida --svuota               # no agenda: back to choosing by itself
ruby tools/esplora.rb guida --foto                 # a photo at the current pause (or the next)
ruby tools/esplora.rb guida --foto-sempre          # a photo at every pause (--foto-mete: only at the AI's destinations, --senza-foto)
```

The events that wake `pilota` up: a destination reached, a destination done
(or given up, and why), agenda almost empty or empty, a destination that
cannot be reached, a remarkable thing never seen before, a photo.

**On foot: where you can get.** While walking, the description says for
every thing and unexplored area whether it can be reached (`reach`: yes,
maybe through areas never seen, no) and with how many metres of walking
(`walk_m`), from the map the explorer has built by looking. A «go» towards
something that cannot be reached on foot is refused at once, with the
reason; in the photos those things have a light grey label. On Stromboli
the autonomous pilot went from about one destination reached per minute to
three.

**Photos with labels.** At pauses in front of the AI's destinations the
explorer, standing still and looking at the destination, takes an image of
the view (800 px) and writes next to every visible thing its short name: the
destination in yellow, objects in blue, faces in grey, unexplored areas in
purple. This way the AI sees what «Group2577#2» and the like are, and refers
to them by name. The photos are in `%APPDATA%\DagaWASD\pilota` (the last
40). A photo freezes SketchUp for the time of one view image (half a second
on a large model): that is why only when standing still.

On the bridge: `GET /explore/percept?since=N` (description and events), `GET
/explore/wait?since=N&timeout=60` (the same description, but the bridge only
answers when there is an event that wakes it: `pilota` does not keep
polling) and `POST /explore` with `{"cmd": "steer", …}`.

**Comments in the video.** What the AI says (`--commento`, `--di`, or `say`
in the steer) stays in the recorded path, at the moment it said it: it
becomes the description of the nearest scene when you make scenes, and an
`.srt` subtitle file next to the video (AVI: same name, players open it by
themselves; PNG images: `crea_video.bat` puts it into the MP4).

**Autonomous pilot.** `tools/pilota_ia.rb` drives on its own, without one
command at a time: it waits for the bridge's events, sends Claude the
description and the photo of the pause, and passes on to the bridge what
Claude decides. The default engine is Claude Code itself (`claude -p`, with
this computer's account: no key); with `ANTHROPIC_API_KEY` set it uses the
Claude API (`anthropic` gem). On Stromboli a turn takes 4–5 s. Every turn
costs: `--turni` (20) and `--secondi` (300) set the limits, and at the end it
prints the tokens used.

```
ruby tools/esplora.rb avvia --a-piedi                   # start, on foot
ruby tools/pilota_ia.rb --turni 15 --secondi 240        # low effort: answers in a few seconds
ruby tools/pilota_ia.rb --sforzo medium --lingua inglese --modello claude-sonnet-5-5
ruby tools/pilota_ia.rb --motore api                     # the API, with the key
```

## Photos and gallery

While walking, **P** (it can be changed in *System › Controls*; on the
gamepad the right bumper, RB) takes a photo of the view, without crosshair
or text, with a flash. If you are recording a path the photo goes with it;
otherwise into a separate series, one for each time you enter the mode.

The explorer takes photos by itself, when the walk becomes a path: the most
interesting destinations among those seen so far, when its gaze rests on
them and sees them large enough (many destinations are looked at without
getting there) or on arrival; the open spaces that appear now and then;
never from where it has already taken a photo, never more than one photo
every 8 seconds (at most 30 per walk). For each photo it writes **what** is
there (the thing, how big it is, how far away, what is around it) and
**why** it chose it: the most interesting so far, the colour that stands
out, nothing similar in view, lots of detail, the silhouette standing out
against the background, an object made of many parts, a view. The AI driving
it asks for its own photos with `snap` (its why) and `say` (the what).

Photos are stored next to the model, in `<model>_foto/<date and time>/`, as
1600 px JPGs, with `galleria.json`; the path keeps the folder relative to the
model, so it finds it again if the model moves with its photos. For a model
never saved, or if it cannot write next to the model, they go to
`%APPDATA%/DagaWASD/foto`.

In *Camera › Paths* every path has its own **📷** button, next to Video:
with the number of photos, it opens the gallery in the browser; greyed out
if the path has none, and a click explains how to take some. Below the list
are the series no path holds (photos outside a recording, deleted paths).

The gallery is a single page, `galleria.html` in the photo folder, rebuilt
every time it opens, in SketchUp's language. The photos are instant photos
on a wooden table that develop as they come into view, each with its note
card: what, why, who took it, a compass with the direction of the gaze, and
the time. There are two ways to look at them:

- **in a row**: they scroll sideways with the mouse wheel, the arrows, by
  dragging, or from the film strip at the bottom (thumbnails on film). At the
  top is the walk drawn in pencil: the numbered photos with the cone of what
  they were looking at, the scale, north, the direction. A small map in a
  corner follows the current photo. The AI's comments are on sticky notes at
  their place in the walk, and at the end there is the card with duration,
  distance walked and photos;
- **scattered on the table**: you pick up the photos and move them with the
  mouse (or a finger, or the arrows), and the layout is kept for next time.
  *Tidy them up* puts them back in rows.

A click opens the photo in large, with *Slideshow* (one after the other;
space pauses it). With photos by several authors (you, the explorer, the AI)
the stamps at the top filter them. `#3` in the address goes to photo 3,
`#3z` opens it large. It prints cleanly (the photos with their notes), works
offline and can be sent to someone together with its folder.

## Two packages

`tools\crea_rbz.bat` creates in `dist\`:

- `dagawasd-<version>.rbz`: complete, with the **bridge for Claude Code**
  (`lib/bridge.rb`), a local-only server, off until you turn it on from the
  panel, through which Claude Code draws in the open model;
- `dagawasd-<version>-warehouse.rbz`: without the bridge, for the Extension
  Warehouse. Without `lib/bridge.rb` the extension works all the same.

## Development

The code, its comments and the changelog are in Italian.

- `installa.bat` copies the source into the Plugins folder of every SketchUp
  it finds.
- `tests\run_tests.bat` runs the tests (Ruby, with a simulated SketchUp; the
  panel in a simulated browser with Node).
- `tools\controlla_warehouse.bat` checks the package against Trimble's rules
  (rubocop-sketchup).
- The version number lives only in `dagawasd.rb` (`VERSION`); every version
  has its section in `CHANGELOG.md`.
- The icons come from the SVGs in `pubblicazione/`: `tools\rendi_icone.bat`
  rebuilds the toolbar ones (`icons/`) and the Warehouse listing one
  (`pubblicazione/icona_512.png`).
- The Extension Warehouse listing (texts in English and notes for the
  reviewers) is in `pubblicazione/extension_warehouse.md`.
- This README is in several languages (`README.md` in English,
  `README.it.md`, `.es`, `.fr`, `.de`, `.pt`, `.nl`, `.sv`, `.pl`, `.cs`, `.ru`, `.ja`, `.ko`, `.zh`): a change goes into all of
  them.
- In the running SketchUp, with the bridge on and «Windows and keys» on in
  the panel (tools for Claude Code, not installed):
  - `tools\finestre.ps1` reaches where Ruby cannot: native windows, alerts,
    menus, capturing the view with sky and clouds, simulated keys and real
    clicks in the 3D view (for example a double-click on a sphere);
  - `tools\collaudo.rb` tests live the panel's button and menu, the
    «Delete» confirmation and a video up to the final window;
  - `tools\schermate.rb` makes the listing images in
    `pubblicazione/schermate/` (1920×1080, with a screen at least that
    large);
  - `tools\prova_fps.rb` walks and runs in FPS mode and measures the head
    bob.

## License

[MIT](LICENSE) © 2026 Dagadam. You may use, modify and redistribute the code
freely, commercially too, as long as every copy keeps the copyright notice
and the license text.
