# Accessibility

DagaWASD lets you walk through a SketchUp model like in a video game. Moving
through a 3D view is a visual experience, but nobody should get a headache,
feel sick or be shut out because of a setting that could have been
changed. This page says what you can adjust today, what does not work well
yet, and how to tell us.

Setting names below are as they appear in the settings panel
(*Extensions › DagaWASD › Settings…*). Some are only visible at the
**Advanced** level: pick it at the top of the panel.

## ⚠ Flashes (photosensitivity)

Two things make the view flash. If you are sensitive to flashing light,
read this first.

**One switch turns both off:** *Accessibility › No flashes* in the settings
panel (from the next release, after 1.2.1). Photos are still taken and the
status bar confirms each one; thunderstorms stay rain or snow, with no
lightning and no brightening of the sky.

- **Photo flash.** Taking a photo (**P**, or RB on the gamepad) turns the
  whole 3D view almost white for 0.3 seconds. The autonomous explorer also
  takes photos by itself, at most one every 8 seconds, when the walk is
  being recorded as a path. *No flashes* removes it. In 1.2.1 and earlier
  it cannot be turned off: don't press P, and untick «Record the path» in
  the explorer's start window.
- **Lightning.** Thunderstorms light up the sky and the scene for about half
  a second, at random moments, 1 to 30 times a minute. They are **off by
  default**. They are turned on by *Weather › Rain & snow › Thunderstorm*,
  or by the «Summer thunderstorm» ready-made scene. To stop them, untick
  *Thunderstorm* (or turn on *No flashes*); *Lightning* sets how many per
  minute.

## Motion sickness

- **Head bob**: *Camera › Head bob › Enable head bob* turns it off; at the
  Advanced level you can lower its frequency and amplitude instead.
- **Field of view**: *Camera › View › Field of view (FOV)*. A wider view
  (90–100°) causes less discomfort for many people.
- **Inertia**: *Player › Movement › Acceleration time* and *Braking time*
  (Advanced) set how gently you start and stop.
- **Speed**: walking speed and run multiplier are in *Player › Movement*;
  the explorer's speed changes with the mouse wheel or in its profile (the
  «Slow» profile walks at 0.5 m/s with long pauses).
- **Things moving on their own**: unticking *Weather › Date & time › Time
  passes* stops the sun, moon and stars; clouds still drift with the wind,
  so turn off *Weather › Clouds* (and *Time-lapse clouds*) for a still sky.
  Rain and snow are off unless you turn them on.
- **Panel animations**: *System › Appearance › Animations* (Advanced).
- **Stop at any time**: **Esc** always leaves walking mode, and stops the
  explorer and path replay.

## Input

- **Every key can be changed**: *System › Controls*. The keyboard layout of
  your country is recognised.
- **No mouse needed to look around**: *Camera › View › Look with the
  keypad* turns the numeric keypad into a way to look (4 and 6 turn, 8 and
  2 look up and down), with adjustable speed.
- **Gamepad**: any XInput controller (Xbox and compatible) moves, looks,
  jumps, crouches, uses, grabs, kicks and takes photos; *Menu* (Start)
  leaves walking mode.
- **Mouse**: sensitivity and *Invert Y axis* in *Camera › View*.
- **Hands-free**: the autonomous explorer walks through the model on its
  own and turns the walk into a path; recorded paths replay without any
  input.
- The settings panel can be used with the keyboard (Tab, Enter, arrow keys
  on sliders).

## Seeing the panel and the view

- **Themes**: *System › Appearance › Theme* has **High contrast**, Light,
  Dark and others, or *Automatic* to follow Windows. *Custom background and
  text* lets you pick your own colours.
- **Text**: *Text size* (12–20 px), *Line spacing* and *Spacing*.
- **Crosshair**: colour, size, thickness, opacity and a *Dark outline* to
  see it on light surfaces, or hide it with *Show crosshair*.
- **Less clutter**: the panel has three levels (Basic, Advanced, Expert);
  *Show descriptions* hides the short explanation under each setting. In
  the explorer, **I** hides the information lines at the top left.

## The photo gallery

- The gallery is a web page that opens in your browser: browser zoom
  (Ctrl + / Ctrl −) enlarges everything, and it follows Windows'
  *reduce motion* setting (no smooth scrolling or animations).
- Everything works with the keyboard: arrow keys move between photos,
  Enter opens one large, Esc closes it, Space pauses the slideshow; on
  the table, arrow keys move the focused photo.
- Texts can be edited (*Edit*): Tab reaches each text, Enter opens and
  confirms it, Esc cancels.
- It prints cleanly, without the wooden table: photos with their notes.

## Language and sound

- The interface is in **36 languages**, including right-to-left Arabic and
  Hebrew. It follows SketchUp's language, or you can choose one.
- DagaWASD makes **no sounds**: nothing depends on hearing (thunderstorms are
  only visual).

## Known limitations

- **In 1.2.1 and earlier the photo flash cannot be turned off**: the
  *No flashes* switch arrives with the next release.
- **The 3D view cannot be read by a screen reader.** The settings panel is
  a web page inside SketchUp, but it has not been tested with screen
  readers (NVDA, JAWS, Narrator) and some controls, such as the two-handle
  sliders, may not be announced correctly.
- **Walking needs continuous input**: holding keys or a stick. There is no
  "click to go there" mode yet; the autonomous explorer is the alternative.
- **Some explanations are only in tooltips** shown on mouse hover.
- **Windows only**, because input and gamepads use the Windows API. SketchUp
  2023 or later.

## Tell us

If something gets in your way, please say so: accessibility problems are
treated as bugs. Open an [issue](https://github.com/Dagadam/dagawasd/issues/new/choose)
and describe what you use (screen reader, magnifier, switch, gamepad only…)
and what happened. You can write in English or Italian.

This statement was last reviewed for DagaWASD 1.2.1 (November 2026).
