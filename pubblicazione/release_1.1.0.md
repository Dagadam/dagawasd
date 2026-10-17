DagaWASD 1.1.0: a panel for every key position of a camera path, and
translated right-click menus in the settings.

Windows only, SketchUp 2023 or later. All changes are in
[CHANGELOG.md](https://github.com/Dagadam/dagawasd/blob/main/CHANGELOG.md) (in Italian).

## What's new

- **A panel for each sphere of a path.** After *Camera › Paths › Edit*,
  double-click a sphere (or select it and press **Enter**) to open its
  settings:
  - **Position**: X, Y, Z and eye height above the ground.
  - **Look**: compass direction, tilt and roll.
  - **Zoom**: as a field of view or as a magnification.
  - **Timing**: how long to pause there and how fast to travel to the next
    sphere, with the resulting travel time and arrival time.

  The sphere in the model changes as you type, and every change is undone
  with Ctrl+Z.
- **− and + buttons** beside every field change the value by one step; hold
  them down to keep it going. **Right-click** one and the value changes on
  its own, one unit per second, with SketchUp following live; click again to
  stop it there.
- **Preview from the sphere**: the camera dollies into what the sphere sees
  and follows your changes; untick it to dolly back to where you were.
- **◀ ▶** move to the previous or next sphere, always with a smooth dolly;
  with the preview on, along the real path. Also **Take from view**,
  **Insert after** and **Delete**.
- Replay, scenes and video now respect each sphere's pause and speed.

## Fixes

- **Sphere numbers through walls**: the order number of a sphere behind a
  house showed up on its roof. Only spheres in view get a number now.
- **Right-click in the panels**: it showed the browser's own menu, in
  English and with developer items. Now text boxes get a Cut / Copy / Paste
  menu in your language, and nothing appears anywhere else.

## Which file should I download?

| File | For |
|---|---|
| **`dagawasd-1.1.0-warehouse.rbz`** | **Everyone.** This is the version you want. |
| `dagawasd-1.1.0.rbz` | Only if you use **Claude Code**: it also contains the *Claude bridge* (see the [1.0.0 release](https://github.com/Dagadam/dagawasd/releases/tag/v1.0.0)). |

Install from *Extensions › Extension Manager › Install Extension*, over the
previous version. Your settings live in `%APPDATA%\DagaWASD` and are kept.

**For Claude Code users**: the developer tool `tools/finestre.ps1` (in this
repository, not in the extension) can now make real mouse clicks, double
clicks included, under the same *Windows and keys for Claude* permission.

---

## In italiano

**Novità.** Dopo *Camera › Percorsi › Modifica*, doppio clic su una sfera (o
Invio con la sfera selezionata) apre il suo pannello. Si possono cambiare:
- la posizione e gli occhi da terra;
- la direzione, l'inclinazione e il rollio;
- lo zoom;
- la sosta e la velocità del tratto.

La sfera cambia subito e ogni modifica si annulla con Ctrl+Z. I pulsanti
− e + cambiano il valore di un passo. Col destro il valore scorre da solo,
un'unità al secondo, finché un altro clic lo ferma. Con **Anteprima dalla
sfera** la camera entra in dolly in ciò che vede la sfera. **◀ ▶** passano
alla sfera precedente o successiva, sempre in dolly.

**Correzioni.** I numeri delle sfere non si vedono più attraverso i muri.
Il clic destro nei pannelli non mostra più il menu del browser in inglese:
nelle caselle apre Taglia, Copia e Incolla nella lingua scelta.

**Quale file scaricare?** `dagawasd-1.1.0-warehouse.rbz` va bene per tutti;
`dagawasd-1.1.0.rbz` solo per chi usa Claude Code.
