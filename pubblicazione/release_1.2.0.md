DagaWASD 1.2.0: an autonomous explorer that walks through your model by
itself, photos with a gallery, and a list of key positions for every camera
path.

Windows only, SketchUp 2023 or later. All changes are in
[CHANGELOG.md](https://github.com/Dagadam/dagawasd/blob/main/CHANGELOG.md) (in Italian).

## What's new

- **Autonomous explorer.** Press the eye button and the camera explores the
  model on its own. It looks at the scene, picks the most significant thing
  in view (objects that stand out by shape, detail, colour and rarity, not
  bare walls), takes a step towards it while looking at it, and repeats.
  - It plans its route on a map of what it has seen: around walls and
    furniture, up stairs and slopes, never over a table or off a ledge. It
    jumps low obstacles, flies in from an aerial view and lands where there
    is something to see.
  - It remembers what it has already looked at and where it has been, so it
    gets bored and goes looking for new rooms and unexplored areas behind
    doors and corners.
  - An attention map shows what it finds interesting. Esc or a click stops
    it, right-click pauses it, the mouse wheel changes its speed.
  - When you stop it, the walk becomes a camera path, ready for scenes or a
    video.
- **Explorer profiles** (*Extensions › DagaWASD › Explorer profiles…*):
  seven ready-made characters (Balanced, Curious, Runner, Slow,
  Photographer, Carefree, Soldier) or your own, built from speed, reflexes,
  curiosity, boredom, what attracts it and more. Changes apply right away,
  even while it explores.
- **Adaptive analysis** (*System › Performance*, advanced level): the
  explorer looks at the scene more often when the computer has spare power,
  between a minimum and a maximum per second, without slowing down the walk.
- **Photos and gallery.** Press **P** while walking (or RB on the gamepad)
  to take a photo; the explorer takes its own of the most interesting
  things, with a note on what they are and why it chose them. The 📷 button
  on every path opens its gallery in the browser: instant photos developing
  on a wooden table, with handwritten notes, a film strip, the route
  sketched in pencil, a slideshow and printing.
- **List of key positions** in *Camera › Paths*: the triangle beside a path
  opens its positions, with arrival time, pause, speed and zoom. Click one
  to open its panel; click between two to add a position from the current
  view. During replay the current position lights up.
- **Thin cameras**: on paths with more than two positions, merges spheres
  piled on top of each other (typical when you turn on the spot while
  recording) into one, with their average position, look and zoom; pauses
  add up. Spheres looking more than 45° apart stay separate. Asks for
  confirmation and is undone with Ctrl+Z.

## Fixes

- Entering WASD mode no longer moves the view: you start exactly where you
  were, and eye height and zoom glide in on the first step.
- After replaying a path the view goes back to where it was, instead of
  staying inside the last sphere.
- Spheres could stay hidden after quickly toggling the sphere panel's
  preview, and parallel projection turned into perspective when moving to
  the next sphere.
- Starting to walk inside an open sphere, and drawing the sphere numbers,
  could write errors in the log.

## Which file should I download?

| File | For |
|---|---|
| **`dagawasd-1.2.0-warehouse.rbz`** | **Everyone.** This is the version you want. |
| `dagawasd-1.2.0.rbz` | Only if you use **Claude Code**: it also contains the *Claude bridge* (see the [1.0.0 release](https://github.com/Dagadam/dagawasd/releases/tag/v1.0.0)). |

Install from *Extensions › Extension Manager › Install Extension*, over the
previous version. Your settings live in `%APPDATA%\DagaWASD` and are kept.

**For Claude Code users**: through the bridge Claude can now drive the
explorer. It sees what the explorer has seen, gives it an agenda of places
to go and things to look at, and asks for photos (`tools/esplora.rb pilota`,
or `tools/pilota_ia.rb` to let it drive on its own). Its comments end up in
the recorded path, in scene descriptions and in `.srt` subtitles of the
video.

---

## In italiano

**Novità.** L'**esploratore autonomo** (pulsante con l'occhio) gira il
modello da solo: guarda la scena, sceglie la cosa più significativa, le va
incontro guardandola e ricomincia. Pianifica la strada su una pianta di ciò
che ha visto, sale le scale, salta gli ostacoli bassi, vola da una vista
aerea e si stanca di ciò che ha già visto. Alla fine il giro diventa un
percorso. Sette **profili** pronti o fatti da te; con l'**analisi adattiva**
(*Sistema › Prestazioni*) guarda più spesso quando il computer ha calcolo
libero.

**Foto e galleria**: P scatta una foto, l'esploratore ne scatta da sé con
un appunto; 📷 apre la galleria nel browser, Polaroid su un tavolo di legno.

**Percorsi**: il triangolo accanto al nome apre l'elenco delle posizioni, da
cui aprirle o aggiungerne una dalla vista. **Dirada camere** unisce le
sfere ammassate in una sola, la loro media; si annulla con Ctrl+Z.

**Correzioni.** Entrando in modalità WASD la vista non salta più; finita la
riproduzione si torna dov'eri; le sfere non restano più nascoste per
sbaglio.

**Quale file scaricare?** `dagawasd-1.2.0-warehouse.rbz` va bene per tutti;
`dagawasd-1.2.0.rbz` solo per chi usa Claude Code.
