# Hypr Screen

An [Omarchy shell plugin](https://omarchyplugins.com/develop.html) for saving
named Hyprland monitor layouts ("profiles") and switching between them —
e.g. going from three monitors down to just the laptop panel and back.

This is a native-plugin rewrite of the original
[hypr_screen](https://github.com/) Flutter/GTK app. Moving it into the
Omarchy shell process removes an entire class of problems the standalone app
had: a `libflutter_linux_gtk.so` that could go missing after an Omarchy
upgrade, a separate installed binary that could fall out of sync with the
source, and manual `windowrule`/keybind plumbing to make its window float
and center. Plugins run inside the same long-lived `omarchy-shell`
(Quickshell) process, so none of that applies.

## What it does

One panel, two modes:

- **Switch** — a compact, keyboard-driven list of saved profiles. Up/Down
  (or j/k) to move the selection, Enter to apply it. An optional auto-advance
  timer applies the current selection if left idle (default 10s, matching
  the old `--next --timeout 10` behavior) — pass `{"timeout": 0}` to disable
  it.
- **Edit** — a drag-and-drop canvas: monitors are drawn to scale and
  positioned proportionally to their real layout. Drag a tile to reposition
  it, click one to edit its resolution/refresh/scale/rotation/enabled state,
  then Save as a named profile or Apply immediately.

Applying a profile writes `~/.config/hypr/hypr_screen.lua` as `hl.monitor(...)`
calls (the format Hyprland's Lua config actually understands — see
"Applying a profile", below) and runs `hyprctl reload`.

## Install

```sh
omarchy plugin add https://github.com/<you>/omarchy-hypr-screen.git --enable
```

Or for local development, symlink this checkout into place and let Omarchy
discover it:

```sh
ln -s "$(pwd)" ~/.config/omarchy/plugins/dev.stephenschwarz.hypr-screen
omarchy-shell shell rescanPlugins
omarchy plugin enable dev.stephenschwarz.hypr-screen
```

## Keybind

Add to `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + SHIFT + P")
o.bind("SUPER + SHIFT + P", "Hypr Screen switcher",
  "omarchy-shell shell summon dev.stephenschwarz.hypr-screen '{\"mode\":\"switcher\"}'")
```

(Or bind a second key to `{"mode":"editor"}` — that's also the default
when no mode is given, matching the old app's plain/`--next` split.)

## Profile storage

Profiles live in `~/.config/hypr/profiles/*.conf`, one `monitor = ...` line
per monitor — unchanged from the original app, so existing profiles keep
working with no migration step. This is just the plugin's own storage
format; Hyprland never reads these files directly.

## Applying a profile

Omarchy quattro moved Hyprland's own config from `hyprland.conf`/
`monitors.conf` to a Lua config chain (`hyprland.lua` → `monitors.lua`,
using `hl.monitor({...})` calls). For a profile to actually take effect,
`hyprland.lua` needs to load what this plugin writes:

```lua
-- after require("hypr.monitors")
pcall(require, "hypr.hypr_screen")
```

(`pcall` so a fresh install — before any profile has been applied and the
file exists — doesn't break config parsing.)

## Development

```sh
omarchy plugin validate .                                  # manifest schema
qmllint -I "$OMARCHY_PATH/shell" *.qml                      # syntax
omarchy-shell shell summon dev.stephenschwarz.hypr-screen '{"mode":"editor"}'
omarchy-shell shell hide dev.stephenschwarz.hypr-screen
```

Editing a file under `~/.config/omarchy/plugins/<id>/` usually hot-reloads;
if changes don't seem to take (stale QML component cache), force a clean
reload with `omarchy-restart-shell`.

## Files

- `manifest.json` — plugin manifest (`kind: panel`, standalone/keybind-summoned)
- `Panel.qml` — entry point: layer-shell overlay, mode switch, dismiss
- `SwitcherView.qml` — the quick-switch list
- `EditorView.qml` — the visual editor (sidebar + canvas + inspector)
- `MonitorRect.qml`, `InspectorField.qml`, `ActionButton.qml`, `ModeTab.qml` — small shared components
- `Model.js` — profile parsing/serialization, Lua translation, live-monitor mapping

## License

MIT
