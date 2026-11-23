# Trainer Desk: player guide

Trainer Desk turns the game window into a workspace: the game stays in the middle, and panels from other mods (such as Trainer Lens and Trainer Pilot) sit in docks around it. On its own it shows nothing; install it together with a mod that has panels.

## Installing

1. Download `trainer_desk-<version>.zip`, or install it from the launcher's **Find mods** tab.
2. If you downloaded the zip, use **Import mod .zip** in the launcher, or unpack it into `%APPDATA%\pokemon-love2d\mods\trainer_desk`.
3. Turn the mod on in the launcher's mod list and start the game.

The first time, panels open in their default places: most at the bottom, some on the right.

## The layout

```
+-----------+---------------------+-----------+
|           |                     |           |
|   left    |        game         |   right   |
|   dock    |                     |   dock    |
|           |                     |           |
+-----------+---------------------+-----------+
|                 bottom dock                 |
+---------------------------------------------+
```

Each dock holds one or more groups of tabs. Only one tab of a group shows at a time.

| To... | Do this |
| --- | --- |
| Show another panel of a group | Click its tab. |
| See every tab of a crowded group | Click the arrow at the end of the tab bar. |
| Resize a dock or a group | Drag the divider between them. |
| Move a panel | Drag its tab to another dock, group or position. |
| Close a panel | Click the **x** on its tab. |
| Open a panel in its own desktop window | Click the window mark on its tab (only panels that support it have one). |
| Bring a closed panel back | Open the menu and click its name. |

The layout is saved by itself and comes back the next time you play.

## The menu

The menu button sits in the top-right corner of the game area. It stays faint until the pointer comes near it. The menu has:

- **Panels**: every panel the mods registered. A tick means it is showing. Click a docked panel to close it, or a closed or floating one to bring it back to its dock.
- **Theme**: the look of the docks.
- **Reset layout**: puts every panel back in its default place.
- **Hide the IDE**: hides the docks so the game takes the whole window.

Press **Esc** to close the menu.

## Hiding the docks

Press **F10** to hide every dock and play in the whole window; press it again to bring them back. Panels open in their own desktop windows stay open. You can choose another key, or none, in the mod's settings.

## The second screen

Some mods send a picture to a second screen (Kanto Gear in Separate Screens mode, for example). With **Dock second screen** on, Trainer Desk shows that picture as a panel instead of opening another window.

## Settings

Open the launcher's mod list, select Trainer Desk and open its settings.

| Setting | What it does |
| --- | --- |
| IDE layout | Turns the docks on or off. |
| Dock second screen | Shows another mod's second-screen picture as a panel. |
| Language | English, Spanish, Portuguese or Japanese, for the menu and tips. |
| Hide/show key | F10, F9, F8, F6 or none. |
| Reset layout | Turn it on to put every panel back in its default place. |

## Problems

- **I can't find a panel.** Open the menu: a closed panel has no tick; click it. If it is not listed at all, the mod that owns it is not running.
- **The docks are gone.** You probably pressed the hide key (F10). Press it again.
- **The layout is a mess.** Menu, then **Reset layout**.
- **Text in a panel is cut with "..".** The panel has less room than it needs: drag a divider to give it more.
