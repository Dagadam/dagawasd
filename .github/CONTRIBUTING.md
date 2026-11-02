# Contributing to DagaWASD

Thanks for wanting to help! Bug reports, translation fixes, ideas and pull
requests are all welcome.

## Reporting a bug or asking for a feature

Use the [issue forms](https://github.com/Dagadam/dagawasd/issues/new/choose):
they ask for the details that are needed (SketchUp, Windows and DagaWASD
versions, steps, error log). Security problems go through the
[security policy](SECURITY.md) instead, never in a public issue.

## Translations

The interface is in 36 languages, one file per language in `lang/`
(`lang/en.json`, `lang/it.json`, …). If a text in your language sounds
wrong or unnatural, a pull request that fixes it is very welcome, even a
single line. Keep the placeholders as they are (`%{name}`, `%{n}`…) and the
`\n` line breaks.

## Code

Before you start on something big, open an issue to talk about it.

- **Language.** Code, comments, commit messages and `CHANGELOG.md` are in
  Italian. If you don't speak Italian, write in English: it will be
  translated when merging.
- **Windows only.** Input, windows and gamepads use the Win32 API through
  Fiddle; SketchUp 2023 or later.
- **Install your copy** into every SketchUp found with `installa.bat`, then
  restart SketchUp.
- **Tests.** `tests\run_tests.bat` must end with `TUTTO OK`. It needs Ruby
  3.2 (`C:\Ruby32-x64`) and, for the panel tests, Node.js. SketchUp is
  simulated, so the tests run without it. Add a test for what you change: a
  fixed bug gets a test in `tests/test_regressions.rb` or next to the code it
  touches.
- **New texts** go into **all** files in `lang/`, not only Italian and
  English: `tests/test_i18n.rb` fails otherwise.
- **New Ruby files** in `lib/` must be listed in `main.rb`.
- **Changelog.** Describe what changes for the user under
  `## [Non ancora uscito]` at the top of `CHANGELOG.md`.
- **Version.** Don't change `VERSION` in `dagawasd.rb`: it is bumped when a
  release is made.
- **Extension Warehouse rules.** If you have rubocop-sketchup,
  `tools\controlla_warehouse.bat` checks the package against Trimble's rules.

## Pull requests

Keep a pull request to one topic, and fill in the checklist of the template.
By contributing you agree that your work is released under the
[MIT license](../LICENSE) of the project.

Everyone taking part is expected to follow the
[code of conduct](CODE_OF_CONDUCT.md).
