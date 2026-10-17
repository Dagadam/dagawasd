DagaWASD 1.0.1: camera paths you can fine-tune right in the model, a more
natural head bob, and a fix for the settings panel opening off-screen.

Windows only, SketchUp 2023 or later. All changes are in
[CHANGELOG.md](https://github.com/Dagadam/dagawasd/blob/main/CHANGELOG.md) (in Italian).

## What's new

- **Edit a recorded path in the model.** In *Camera › Paths*, **Edit** puts
  the path's key positions in the model: each one is a sphere with an arrow
  (where the camera looks; the longer the arrow, the more it is zoomed in)
  and the camera frame with a triangle on its top side, which tilts when you
  roll the camera. Move and rotate them with SketchUp's own Move and Rotate
  tools; Ctrl+Move adds a position, Delete removes one. Replay, scenes and
  video follow the spheres on a smooth curve at constant speed.
  **New from view** starts a path without recording.
- **Mouse-wheel zoom** used while recording (R) is kept: a zoom change now
  makes its own position, even when standing still.

## Fixes

- **Head bob**: running made the head bounce up to ±7.7 cm, seven times a
  second. It now stays within ±4.5 cm (±3 cm sideways), and *Frequency* is
  what it says: steps per second when walking, rising when running up to
  3 per second.
- **Settings panel off-screen**: if SketchUp remembered a position where
  there is no monitor any more (a screen unplugged, a remote session), the
  panel opened off-screen and seemed not to open at all. It now comes back
  to the centre. Same for the video progress window.

## Which file should I download?

| File | For |
|---|---|
| **`dagawasd-1.0.1-warehouse.rbz`** | **Everyone.** This is the version you want. |
| `dagawasd-1.0.1.rbz` | Only if you use **Claude Code**: it also contains the *Claude bridge* (see the [1.0.0 release](https://github.com/Dagadam/dagawasd/releases/tag/v1.0.0)). |

Install from *Extensions › Extension Manager › Install Extension*, over the
previous version. Your settings live in `%APPDATA%\DagaWASD` and are kept.

**For Claude Code users** (full package only): in *System › Claude bridge*
there is a new permission, **Windows and keys for Claude**, off by default.
It lets the developer tool `tools/finestre.ps1` (in this repository, not in
the extension) press buttons, open menus, answer message boxes, capture the
view and simulate keys in SketchUp, only in SketchUp's own windows. With
**Show the mouse** (on by default) you see the pointer travel to each button,
framed in green, before it is pressed. A live build from the bridge now also
brings SketchUp to the front.

---

## In italiano

**Novità.** In *Camera › Percorsi*, **Modifica** mette nel modello le
posizioni del percorso: sfere con una freccia (lo sguardo; più è lunga, più
la vista è zoomata) e il riquadro dell'inquadratura col triangolo in alto,
che si inclina col rollio. Si spostano e ruotano con Sposta e Ruota di
SketchUp; Ctrl+Sposta ne aggiunge una. **Nuovo dalla vista** crea un percorso
senza registrare. Lo zoom della rotella usato registrando con R ora resta.

**Correzioni.** Il dondolio della testa correndo non supera più ±4,5 cm e
3 passi al secondo; la *Frequenza* del pannello sono i passi al secondo
camminando. Il pannello ricordato fuori dallo schermo si riapre al centro.

**Quale file scaricare?** `dagawasd-1.0.1-warehouse.rbz` va bene per tutti;
`dagawasd-1.0.1.rbz` solo per chi usa Claude Code (contiene il ponte e il
nuovo permesso **Finestre e tasti per Claude**, spento di default, con
**Mostra il mouse** per vedere il cursore andare su ogni pulsante).
