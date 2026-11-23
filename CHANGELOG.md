# Changelog

## 0.6.0

- The dock's menu and tips in English, Spanish, Portuguese and Japanese (Language option; English by default).
- Tab titles and menus can draw Japanese text.

## 0.5.0

- Renamed from PokeDock to Trainer Desk; mod id `poke_dock` becomes `trainer_desk`.
- English documentation.

## 0.4.1

- A panel new to the layout joins a group as a tab without taking the front from the tab being looked at.

## 0.4.0

- Responsive panels: `register{ responsive = true }` gives `draw(now, w, h)` the room the panel has in its dock, and redraws as soon as that changes. In its own window such a panel is drawn at its registered size.
- `dock.features`.

## 0.3.0

- Tabs that do not fit in a bar go into a menu at the end of the bar; the active tab always shows its whole label.
- Text is cut on whole characters, so a title or error message with accents can no longer stop the window from drawing.
- The mouse wheel over a panel reaches the panel (`pointer("wheel", x, y, amount)`) instead of zooming the game.
- A key (F10 by default) hides and shows every dock; "Hide the IDE" in the menu.
- Esc closes the menu; tooltips on the tab marks.

## 0.2.0

- Panels can be closed and reopened from the menu, and floated into their own desktop windows.
- Theme menu.

## 0.1.0

- First version: docks with tabbed groups, draggable dividers and tabs, saved layout, the second-screen picture as a panel.
