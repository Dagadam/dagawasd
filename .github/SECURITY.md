# Security policy

## Supported versions

Only the latest release of DagaWASD receives fixes. If you are on an older
version, update from the [Releases](https://github.com/Dagadam/dagawasd/releases)
page first and check whether the problem is still there.

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report them privately through GitHub:
[**Report a vulnerability**](https://github.com/Dagadam/dagawasd/security/advisories/new)
(also reachable from the *Security* tab of this repository).

Please include:

- the DagaWASD version and which package you use (`dagawasd-<version>.rbz`
  or `dagawasd-<version>-warehouse.rbz`);
- your SketchUp and Windows versions;
- what an attacker can do, and the steps or code to reproduce it.

You will get an answer as soon as possible. Once a fix is released, the
advisory is published with credit to you, unless you prefer to stay
anonymous.

## Scope

What matters most:

- **The bridge for Claude Code** (`lib/bridge.rb`, only in the full
  `dagawasd-<version>.rbz`, never in the Extension Warehouse package). It is
  off until the user turns it on, listens only on `127.0.0.1`, requires a
  token that changes at every start (stored in `%APPDATA%\DagaWASD\bridge.json`)
  and rejects requests coming from web pages. Anything that lets someone else
  run code in SketchUp through it, such as a way around the token, the
  local-only check or the browser-origin check, is a vulnerability.
- **Files**: the extension should write only to `%APPDATA%\DagaWASD`, next
  to the model (photos), to `%TEMP%` and to the files the user picks for
  export. Writing anywhere else, or reading files it should not, is a
  vulnerability.
- **Imported settings and the photo gallery**: a crafted settings file,
  model or photo index that runs script or code when it is opened.

Not vulnerabilities: a program already running under your Windows account
using the bridge while you turned it on (that account can do anything
anyway, and the panel says so), and anything that needs the developer tools
in `tools/`, which are not part of the extension.
