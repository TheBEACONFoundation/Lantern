# Lantern — handover notes

A macOS menu-bar app that shows battery charge as a Lantern Corps emblem on the
desktop, with a spoken-oath easter egg. macOS 13+, Apple silicon, built with
the Command Line Tools — there is no Xcode project.

Nine corps. Five the charge picks for you — white at a full battery, green,
Sinestro under 20%, red under 10%, black at 1% — and four only an oath reaches:
orange, blue, Star Sapphire and indigo. Each has its own figure, palette,
arrival flourish and particle behaviour.

`README.md` documents what it does and how it's put together. These are the
things that would cost you a day to rediscover.

## Build and run

```bash
./build.sh                  # assembles build/Lantern.app and build/lantern-probe
open build/Lantern.app
```

Development flags on the app binary:

| Flag | |
|---|---|
| `--test-oath` | oath matcher cases; no microphone needed |
| `--export-preview <file.png>` | contact sheet of every emblem state |
| `--export-icon <dir>` | app icon PNGs (build.sh uses this) |
| `--snapshot-menu <file.png> [corps]` | opens the real status menu, captures it, quits; a corps swears the lantern first |
| `--demo-shift [step] [speed]` | walks every corps in a window of its own, so the transitions can be watched without draining a battery. `speed` scales Core Animation's clock |

## How it's structured

`LanternRenderer` is Core Graphics drawing: the menu-bar icon, the app icon,
and the source of the static images. `LanternArt` renders those images once per
size/palette/level. `LanternView` is a Core Animation layer tree that animates
them — it does **no** per-frame drawing, so the app sits at ~0% CPU. Particles
are `CAEmitterLayer`s.

Anything you animate should be a CA animation or emitter over a static image.
Redrawing per frame is how this started, and it cost 44% of a core.

## Adding a corps

Every emblem in `LanternGlyph` was measured off a reference image rather than
eyeballed, and it is worth doing that again rather than guessing — three of
them came out wrong the first time and only measurement said so. What worked:
isolate the artwork's ink to black-on-white, then scan it. Radial runs for
anything built on a hub and a ring; angular runs at fixed radii for a fan or a
band with gaps; a Cartesian scan for straight-edged figures. Two findings that
no amount of looking would have given:

- The Star Sapphire's valleys are **not** at the midpoints between its points.
  Each sits 15° from the diagonal tip it flanks, which is what tapers the long
  points; spaced evenly they come out stubby.
- The White Lantern's fan does not radiate from the emblem's centre. Fitting
  its ray angles to a common origin puts that origin at -0.55, low in the
  triangle's mouth; aimed at the centre the same rays are visibly uneven.

The shared outer ring is deliberate. Several references draw a thinner one, but
the charging comet, the ring sweep and the sealed pulse all ride on
`ringInner`, so the figures are rescaled to it instead — and where a reference
separates its figure from its ring with a dark gap, the figure is held clear of
the ring instead (`sinestroInset`, `blueInset`). A painted dark ring would be
invisible on a dark desktop anyway.

## Traps, each of which bit once

- **Offscreen renders don't match a real window.** `CGContext.setShadow` under a
  live window's layer-backed context only fills the bounds of what the layer
  drew, so the glow stopped dead in a square — invisible in offscreen tests,
  obvious on screen. The glow is now blurred explicitly with vImage. **Verify
  visual changes by capturing a real window**: a process can capture its own
  windows with `CGWindowListCreateImage` without Screen Recording permission.
- **Particles make pixel checks flaky.** Turn `Settings.particleEffects` off in
  geometry checks; keep it on only when checking that nothing reaches the
  window edge.
- **The window is much wider than the emblem** (`LanternGlyph.glowPadding`), so
  the glow can fade to nothing before the edge. If anything — glow, particles,
  shockwave — reaches the edge, it's cut off square and the transparent window
  becomes visible. Keep travel inside ~1.5r.
- **Snap layers to whole device pixels.** A layer at a fractional position is
  resampled and everything in it softens; it closed the gap between glyphs in
  the percentage.
- **Stroke `LanternGlyph.outline(in:)`, never the raw path.** The emblem is
  overlapping sub-paths; stroking them outlines the bracket ends buried inside
  the bars, which shows as seams.
- **Battery readings move between OS versions.** Darwin 27 moved the capacity
  figures into a nested `BatteryData` dictionary and dropped `Temperature`
  entirely; temperature now comes from the SMC sensor `TB0T` (little-endian
  float, no privileges needed). Expect to re-check after updates.
- **The oath flare and a corps flourish collide.** Both draw on the same
  layers under the same animation keys, and `triggerOathFlare` runs *after*
  the flourish, so the generic three rings silently replaced whatever the
  arriving corps threw — for the four corps an oath is the only way into, that
  was every time. It now adds only its burst when a corps has just flourished.
  If you add anything else that animates those layers, check the ordering.
- **A dark or a white emblem needs pulling off its extreme.** The widget draws
  on a transparent window over the wallpaper, so a true-black Black Lantern is
  invisible on a dark desktop and a true-white one on a pale desktop — and 1%
  is exactly when you want to see it. Both are drawn off their extreme, and
  checked against dark, mid and light backdrops.
- **An oath must not hang on a proper noun.** The Sinestro oath's only clincher
  was the word "Sinestro", which no recogniser knows, so the oath could not be
  said at all. Clinchers are now ordinary words in unusual order, the corps
  name only adds to the count, and `contextualStrings` biases recognition
  toward the names. See the matching notes in `README.md`.
- **Recognition ends a session after a beat of silence.** An oath recited with
  pauses used to arrive in pieces, none of which was an oath. `OathListener`
  carries each finished piece for 25 seconds and matches it with what follows.
  Each piece has its own expiry, and asynchronous callbacks are scoped to the
  listening session that created them. Indigo needs a recognized closing
  phrase plus "lantern" or "Abin Sur"; its last line alone is insufficient.
- **Reduce Motion is live.** The widget follows the macOS accessibility
  preference, including when it changes while running. Static battery and
  charging indicators remain visible; moving effects stop.
- **This macOS draws no icons on plain menu items.** Setting `NSMenuItem.image`
  does nothing, confirmed with a bare test menu. Custom row views can draw
  their own.

## Charge control: read before trying again

The oath's gate is **ceremony** — it never touches charging. That's not
laziness:

- The keys AlDente and `batt` use on M1–M4 (`CH0B`/`CH0C`/`CH0I`) don't exist on
  M5. Enumerating all 3,794 SMC keys leaves one writable charging control,
  `CHIE`.
- `CHIE = 01` doesn't stop the battery charging — it **cuts the charger's power
  entirely**. macOS reports it unplugged and the Mac runs from its battery.
- A root helper that held `CHIE` while "sealed" therefore fought its own
  "release when the charger's disconnected" rule and flipped the charger on and
  off every 2 seconds. It has been removed; `uninstall-helper.sh` remains to
  remove an installed copy, and `Probe/main.swift` (`lantern-probe`) is how
  `CHIE` was found.
- If you revisit this: watch `ExternalConnected` in `ioreg -rn AppleSmartBattery`
  while testing a key, not just `IsCharging`. That distinction is what the probe
  originally missed. It now reports charger disconnection separately, verifies
  restores by reading the original value back, and stops on restoration errors.
  `./test-probe.sh` exercises parsing and recovery using a fake SMC, without root.

## Not done yet

- The menu-bar icon changes corps without a transition. It is a still image
  redrawn on state change, and animating it at 19pt previously cost more CPU
  than the entire desktop widget — so this is a deliberate omission, not an
  oversight.
- Below 2% charge there are no motes at all, whatever the corps, so the Black
  Lantern gives off nothing when the *battery* puts you there — only when its
  oath does.
- Ideas raised but not built: low-battery notifications, a battery history
  chart, details on hover.

## Provenance

The emblems are geometric reconstructions of the Lantern Corps insignia, which
are DC's trademarks. Fine for personal use; **publishing the project is what
this note originally warned against**, so if it goes public that is a decision
to take deliberately rather than by default. Nothing in the repo copies DC
artwork — the figures are drawn from measurements, in code — but the marks
themselves are still theirs.

The bundle is ad-hoc signed, so it is for the machine that built it; rebuild
elsewhere. The bundle identifier `com.dominic.lantern` is the author's
namespace: anyone forking it should change it, and note that changing it resets
the saved preferences, which `UserDefaults` keys by bundle ID.
