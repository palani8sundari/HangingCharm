# Hanging Charm

A lucky charm that hangs from your Mac's menu bar on an elastic cord. Pull it, flick it, or let it sway; every click outside the charm and its thread goes straight through to the apps underneath.

## Build and run

Needs macOS 14 or later and the Xcode command line tools.

```sh
./Scripts/build.sh --install
```

This builds `build/Hanging Charm.app`, copies it to `/Applications` and launches it. Without `--install` it only builds.

## Using it

- Click the hook in the menu bar for the menu. **Hang on Thread** (⌃⌥H) lowers the charm, or winds it up into the menu bar.
- Drag the charm or its thread and let go. Click the charm, or press ⌃⌥F, to flick it.
- ⌥-drag the charm to move its hook along the top of the screen.
- **Add Your Own Picture…** lifts the subject out of a photo and hangs it as a charm.

## Layout

- `Sources/`: the app, AppKit with no dependencies. `Physics.swift` is the elastic cord and rope, `CharmView.swift` draws them, `CharmController.swift` runs the overlay window and pointer, and `CustomCharms.swift` turns pictures into charms.
- `Art/charms.html`: the charm artwork as SVG. `Scripts/render-art.sh` renders it into `Resources/Charms` and needs Google Chrome; rerun it only after changing the artwork.
