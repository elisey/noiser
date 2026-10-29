# noiser

A macOS menu bar noise generator (white / pink / brown) with a timer you set by
pulling a ball: the further you drag it, the longer it runs. When the time is up
the noise fades out and "time is up" is announced.

Native Swift / AppKit, no dependencies, macOS 15 or newer.

## Build and install

Needs the Xcode Command Line Tools (`xcode-select --install`); full Xcode is not required.

```sh
make            # builds noiser.app in the repo
make run        # builds and launches it
make test       # runs the tests
make install    # copies to ~/Applications (PREFIX=/Applications for system-wide)
make uninstall
```

Launch it from Spotlight or with `open -a noiser`; add it to System Settings →
General → Login Items to start it at login. The bundle is ad-hoc signed; to run
it on another Mac without a Gatekeeper warning you would need a Developer ID and
notarization.

## Usage

The menu bar shows the noiser mark — a ball on a thread: a ring when idle, a
solid ball while playing, half-filled when paused. While a timer runs, the
minutes left sit next to it (`24m`, `<1m` in the last minute).

Click it to open the panel. The ball hangs on its thread under the time and a
status pill:

- **drag the ball** and release — start with that duration; you can drag in any
  direction and beyond the panel's edges, and the pill shows `RELEASE — START`
  with the duration you would get;
- **click the ball** without dragging — run with no timer (`∞`);
- **click the panel** — pause / resume; when paused the ball becomes a ring;
- **settings** (top right) — noise type, volume, ball color, whether to announce
  "time is up"; Escape closes the window;
- **✕** (top left) — quit.

The time reads `24:13` under an hour and `1:05:00` with hours. When a timer
ends the pill turns into `TIME IS UP` for a few seconds.

Settings live in `UserDefaults` (`defaults read com.github.elisey.noiser`).

## Design

Colors, sizes and type styles come from the noiser design system
(`docs/redesign/tokens.json`) and live in `Sources/noiser/Theme.swift`; every
color has a light and a dark value and follows the system appearance.

The interface is set in [Archivo](https://github.com/Omnibus-Type/Archivo), a
variable font with width and weight axes, used at width 125. It is licensed under
the SIL Open Font License 1.1: the font and its license are in `Support/Fonts`
(`Archivo.ttf`, `OFL.txt`), `make` copies them into the bundle's
`Resources/Fonts`, and the app registers the font at launch. Without it (for
example `swift run` outside the bundle) the app falls back to the system font.

The app icon is drawn by `Support/make-icon.swift`; `make icon` regenerates
`Support/noiser.icns` from the default `tomato` variant.

## Layout

| File | What it does |
|---|---|
| `Sources/noiser/NoiseEngine.swift` | AVAudioEngine source node, fades, timer, follows the default output device |
| `Sources/noiser/DSP.swift` | IIR filters, pink/brown coloring, Gaussian RNG safe for the render thread |
| `Sources/noiser/Theme.swift` | Design tokens: colors, metrics, Archivo text styles |
| `Sources/noiser/Drawing.swift` | Ball on its thread, status pill, centered text |
| `Sources/noiser/BallView.swift` | The pull-to-set ball, the time and the status of each state |
| `Sources/noiser/DragOverlay.swift` | Transparent per-screen windows that draw the ball outside the popover |
| `Sources/noiser/PopoverBackground.swift` | Solid paper background for the popover, arrow included |
| `Sources/noiser/IconButton.swift` | The ✕ and settings buttons |
| `Sources/noiser/MenuBarIcon.swift` | Menu bar mark and minutes left |
| `Sources/noiser/SettingsWindow.swift` | Settings window |
| `Sources/noiser/SettingsControls.swift` | Its controls: noise segments, volume slider, color swatches, checkbox |
| `Sources/noiser/AppDelegate.swift` | Status item, popover, tick timer, speech |
| `Tests/noiserTests` | Tests for the tokens, fonts, time format, panel states and controls |
| `Support/Info.plist` | Bundle metadata; `LSUIElement` keeps the app out of the Dock |
| `Support/Fonts` | Archivo and its license |
| `Support/make-icon.swift` | App icon renderer |
