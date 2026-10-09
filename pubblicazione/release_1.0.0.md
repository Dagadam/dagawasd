First public release of DagaWASD, a SketchUp extension to walk through your
model in first person, like a video game: WASD and mouse or a gamepad,
object physics, sun, moon and stars, rain, snow, clouds and storms, and
recorded camera paths you can export to video.

Windows only, SketchUp 2023 or later. All changes are in
[CHANGELOG.md](https://github.com/Dagadam/dagawasd/blob/main/CHANGELOG.md) (in Italian).

## Which file should I download?

There are two packages. They are the same extension, with one difference:

| File | For |
|---|---|
| **`dagawasd-1.0.0-warehouse.rbz`** | **Everyone.** This is the version you want. It is the same package submitted to the SketchUp Extension Warehouse. |
| `dagawasd-1.0.0.rbz` | Only if you use **Claude Code** (Anthropic's AI coding assistant). It also contains the *Claude bridge* described below. |

Install either one from *Extensions › Extension Manager › Install
Extension*. Your settings live in `%APPDATA%\DagaWASD` and survive updates.

## What is the Claude bridge?

The bridge lets [Claude Code](https://claude.com/claude-code) work inside
your open SketchUp model: it can draw geometry, read the model and look at
the view, and you watch it build step by step. Every request is a single
operation, so one Ctrl+Z removes it.

How it works and how it is protected:

- It is a small HTTP server that listens **only on this computer**
  (127.0.0.1, ports 47810–47819) and is never reachable from the network.
- It is **off** until you turn it on in the settings panel
  (*System › Claude bridge*), and a settings file imported from someone else
  can never turn it on.
- Every request needs a **secret token** that changes every time the bridge
  starts. It is saved only in `%APPDATA%\DagaWASD\bridge.json`.
- Requests coming from a web page are refused, so a site open in your
  browser cannot use it.
- It runs Ruby code that it receives. Anyone who can run programs under
  your Windows user could use it while it is on: turn it on only when you
  need it.

The command-line client Claude Code uses, `tools/su.rb`, is in this
repository and is not part of the extension.

The Extension Warehouse package leaves the bridge out, because an extension
that runs code received from outside does not belong in a public store and
most people do not need it. Everything else is identical.

---

## In italiano

**Quale file scaricare?** `dagawasd-1.0.0-warehouse.rbz` va bene per tutti
ed è lo stesso pacchetto inviato all'Extension Warehouse.
`dagawasd-1.0.0.rbz` serve solo a chi usa Claude Code: in più contiene il
*ponte per Claude*.

**Il ponte** permette a Claude Code di disegnare nel modello aperto, leggerlo
e guardare la vista, passo per passo; ogni invio si annulla con un solo
Ctrl+Z. È un piccolo server che ascolta solo su questo computer
(127.0.0.1), spento finché non lo accendi dal pannello (*Sistema › Ponte
Claude*), con un codice segreto che cambia a ogni avvio; rifiuta le
richieste che arrivano da una pagina web. Esegue codice Ruby: accendilo solo
quando ti serve. Il pacchetto per l'Extension Warehouse non lo contiene;
per il resto le due versioni sono identiche.
