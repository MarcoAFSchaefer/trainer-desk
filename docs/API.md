# Trainer Desk API

Other mods use the dock through the table it exports:

```lua
local other = mod.find and mod.find("trainer_desk")
local dock = other and other.exports and other.exports.dock
```

Check `dock.api == 1` before using it, and `dock.active()` before registering: the dock is inactive until the game is ready, and the player can turn it off. A mod that registers panels usually does so from its `core.update` hook, registering again whenever the dock it last talked to is no longer the active one (see Trainer Lens and Trainer Pilot for examples).

`dock.features` lists optional capabilities of this version: `{ responsive = true, wheel = true }`.

## Panels

### `dock.register(def)`

Adds a panel, or updates one already registered with the same id. Returns `true`, or `nil` and a reason.

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Lowercase letters, digits, `_` and `.`. Unique, and the name the saved layout remembers. Convention: `"<mod id>.<panel>"`. |
| `title` | no | The tab's label (up to 40 bytes; cut on a whole character). Defaults to the id. |
| `width`, `height` | yes | The panel's picture size in pixels, 16 to 4096. For a responsive panel, only the size it starts with. |
| `draw(now, w, h)` | one of `draw`/`image` | Paints the picture. The canvas is already set, cleared with the theme's panel colour, and the graphics state is reset. `w` and `h` are the picture's size. |
| `image()` | one of `draw`/`image` | Instead of `draw`: returns a drawable to show, or `nil` for nothing. |
| `imageData()` | no | With `image`: the same picture as ImageData, so the panel can also float in its own window. |
| `pointer(action, x, y, amount)` | no | Pointer input in picture pixels. `action` is `"down"`, `"move"`, `"up"`, `"cancel"` or `"wheel"`; for `"wheel"`, `amount` is positive for up and negative for down. |
| `interval` | no | Seconds between repaints while the panel is visible. Default 0.2, minimum 0.02. |
| `pixel` | no | Size of one art pixel in the picture, so scaling keeps pixels even. Default 1. |
| `side` | no | Where a panel new to the layout goes: `"left"`, `"right"` or `"bottom"`. Default `"right"`. |
| `first` | no | `true` to open ahead of the panels already in that dock. |
| `responsive` | no | `true` for a panel that can draw at any size (`draw` only). Docked, `draw` is called with the size of the room the panel has, and is called again as soon as that size changes. Floating in its own window, it is drawn at `width` x `height`. |

A panel new to the layout goes into its dock as its own group while the dock has fewer than two groups, and otherwise as one more tab in the last group, without taking the front from the tab being looked at.

Errors are contained: if `draw` raises an error, the panel shows the message and the dock logs it once; the rest of the window keeps drawing.

### `dock.unregister(id)`

Removes the panel from the window. The layout keeps its place for next time. Returns `true` if it was registered.

### `dock.panels()`

Every registered panel in registration order: `{ { id, title, state }, ... }`, where `state` is `"docked"`, `"window"` or `"closed"`.

### `dock.show(id, state)`

Puts a panel in `"docked"`, `"window"` or `"closed"` state. Returns `false` if the panel is unknown, or if `"window"` was asked for a panel that cannot float.

## Themes

### `dock.registerTheme(id, definition)`

```lua
dock.registerTheme("light", {
  name = "Light",
  colors = { dock = "f0f0f0", text = { 0.2, 0.2, 0.2 } },
  metrics = { font = 13 },
})
```

`id` is lowercase letters, digits and `_`. Colours are `"rrggbb"` strings or `{ r, g, b [, a] }` tables. Any colour or metric left out is taken from the built-in `dark` theme. If the player had picked this theme before and it is only registered now, it is applied at once.

Colour keys: `window`, `dock`, `panel`, `tabBar`, `tab`, `tabActive`, `tabHover`, `text`, `textActive`, `accent`, `border`, `splitter`, `splitterHot`, `empty`.

Metric keys: `tab` (tab bar height), `splitter` (divider thickness), `padding`, `font`, `minDock` (smallest dock size), `tabMax` (widest tab).

### `dock.setTheme(id)`, `dock.theme()`

`setTheme` picks a registered theme and remembers it. `theme()` returns the theme in use (`{ name, colors, metrics }`), for panels that want to match the window.

## State

| Function | Returns |
| --- | --- |
| `dock.active()` | `true` while the dock is laying out the window. |
| `dock.collapsed()` | `true` while the docks are hidden with the hide/show key. |
| `dock.collapse(state)` | Hides (`true`) or shows (`false`) the docks. |
| `dock.hotkey()` | The key that hides and shows the docks, or `nil` if the player turned it off. |
| `dock.windowPorts()` | `"dock.<panel id>:<port>,..."`: the UDP port each floating panel's window talks from, for a mod that keeps track of the game's windows. |
