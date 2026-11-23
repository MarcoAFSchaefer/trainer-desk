# Trainer Desk architecture

## Files

| File | Role |
| --- | --- |
| `manifest.json` | Mod id `trainer_desk`, API 3, Gen 3 games, permissions `engine_internals` and `network`. |
| `main.lua` | Options, the API table, painting, pointer and key handling, and the engine hooks. |
| `layout.lua` | The layout model. No drawing and no engine calls: where panels live, sizes, and the rectangles that follow from a window size. |
| `theme.lua` | Built-in `dark` theme, theme registration, and resolving a theme over `dark`. |
| `windows.lua` | Desktop windows for floating panels. |

## The layout model (`layout.lua`)

```
layout.docks.left | right | bottom = {
  size = fraction of the window,
  groups = { { tabs = { panelId, ... }, active = index, weight = n }, ... }
}
layout.hidden[id]   -- a closed panel
layout.floating[id] -- a panel shown in its own window
```

Left and right docks run the full height; the bottom dock sits between them. Closed and floating panels keep their place in the docks for when they come back.

`Layout.geometry(layout, area, metrics, present, tabWidth)` turns the model into rectangles: `{ center, docks = { side = { rect, splitter, groups = { view } } } }`. Each view has its `rect`, tab `bar`, `body`, the visible `tabs` with their rectangles, the full list of `ids` in the group, and `more` (the button for tabs that do not fit) when needed. A group whose panels are all absent takes no room, and a dock with no visible group is closed.

When a bar cannot hold every tab, tabs keep a readable width (72 px at least, the active one its whole label) and a run of them that includes the active tab is shown; the rest are reached from the `more` button.

`Layout.encode` / `Layout.decode` save the model as one line of text; `Layout.hit`, `Layout.dropTarget`, `Layout.resizeDock` and `Layout.resizeGroups` answer pointer questions.

## Painting

`render.viewport` (priority 0) runs housekeeping, computes the geometry for the window and hands the game the centre rectangle, with `capture = true` so the dock's menu button stays reachable even with every dock closed. A mod that lays out its own views at a higher priority (Kanto Gear's combined mode uses 1000) is then given the centre area to work in.

`render.window` (priority 0) draws the docks over the window after the game: tab bars, each active panel's picture, dividers, a dragged tab and its drop target, tooltips for the tab marks, and the menu. Drawing is wrapped in `pcall` and the graphics stack is restored afterwards.

Panels with `draw` are painted into their own canvas (`refresh`) when their interval has passed, or at once when a responsive panel's room changes size. The picture is scaled to fit its body, keeping art pixels even when that costs little room.

## Input

| Hook | Priority | What the dock does |
| --- | --- | --- |
| `input.pointer` | 2000 | Clicks on tabs, tab marks (own window, close), the `more` button, dividers, panel bodies and the menu. Panel clicks are passed to the panel in picture pixels. Clicks on the game area are left to the game. |
| `input.wheel` | 2000 | The wheel over a panel goes to the panel as `pointer("wheel", x, y, amount)` and is not passed on; over the game it is passed on (the game's zoom). |
| `input.key` | 3500 | Esc closes an open menu; the hide/show key toggles the docks. Other keys are passed on. |

## Second screen

At priority 2000 in `render.compose`, while "dock second screen" is on, the dock hands the composing mod its own bridge object in place of the engine's second-screen bridge. Whatever that mod pushes becomes the `second_screen` panel, and pointer input on the panel is returned to the mod through the bridge's `pollTouch`.

## Floating windows (`windows.lua`)

The host shows a second display by starting a minimal copy of itself (`--display-companion=<port>,<token>`) that draws frames received over a loopback ENet link and sends pointer input back. A floating panel is one such companion, keyed by its panel id:

- `Windows.update(wanted)` keeps exactly the windows named in `wanted` alive, starting at most one every 0.7 s and giving up on a window after five failures.
- `Windows.push(key, imageData, ...)` sends a frame, LZ4-compressed; an unchanged frame is not sent again.
- A window the player closes is reported once by `Windows.gone`, and the panel goes back to its dock.

`core.update` (priority 890) keeps the floating windows in step; `core.quit_to_launcher` closes them all.

## Saved data

Stored with `mod.cache` under `mod_cache/trainer_desk/`:

| Key | Content |
| --- | --- |
| `layout/v1` | The layout model, as written by `Layout.encode`. Saved half a second after the last change, never in the middle of a drag. |
| `theme` | The id of the chosen theme. |
