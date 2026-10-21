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
make install    # copies to ~/Applications (PREFIX=/Applications for system-wide)
make uninstall
```

Launch it from Spotlight or with `open -a noiser`; add it to System Settings →
General → Login Items to start it at login. The bundle is ad-hoc signed; to run
it on another Mac without a Gatekeeper warning you would need a Developer ID and
notarization.

## Usage

Click the menu bar icon to open the panel:

- **drag the ball** and release — start with that duration; you can drag in any
  direction and beyond the panel's edges;
- **click the ball** without dragging — run with no timer;
- **click the panel** — pause / resume;
- **⚙** — settings: noise type, volume, ball color, whether to announce "time is up";
- **✕** — quit.

Settings live in `UserDefaults` (`defaults read com.github.elisey.noiser`).

## Layout

| File | What it does |
|---|---|
| `Sources/noiser/NoiseEngine.swift` | AVAudioEngine source node, fades, timer, follows the default output device |
| `Sources/noiser/DSP.swift` | IIR filters, pink/brown coloring, Gaussian RNG safe for the render thread |
| `Sources/noiser/BallView.swift` | The pull-to-set ball and its labels |
| `Sources/noiser/DragOverlay.swift` | Transparent per-screen windows that draw the ball outside the popover |
| `Sources/noiser/SettingsWindow.swift` | Settings window |
| `Sources/noiser/AppDelegate.swift` | Status item, popover, tick timer, speech |
| `Support/Info.plist` | Bundle metadata; `LSUIElement` keeps the app out of the Dock |
