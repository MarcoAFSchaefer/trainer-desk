# Tests

`main.lua` is a LÖVE program that loads Trainer Desk and Trainer Lens against a stand-in for the game and checks how they behave: docking, tabs, dragging, closing and floating panels, themes, the hide/show key, the mouse wheel, and every Trainer Lens panel at several sizes.

It runs on Linux with LÖVE 11.5 and a virtual X server:

```
DOCK_MOD=/path/to/trainer-desk/trainer_desk \
PP_MOD=/path/to/trainer-lens/trainer_lens \
TEST_OUT=/tmp/trainer_out \
xvfb-run -a -s "-screen 0 1280x800x24" love tests
```

| Variable | Meaning |
| --- | --- |
| `DOCK_MOD` | Path to the `trainer_desk` mod folder. |
| `PP_MOD` | Path to the `trainer_lens` mod folder. |
| `TEST_OUT` | Where screenshots of the panels are written (default `/tmp/kg_out`). |
| `KG_HOST` | Optional: path to a Gen1Recomp checkout, to also open real floating windows. |

Each passing check prints a line starting with `ok`. The run ends with `ALL DOCK CHECKS PASSED`; a failing check prints `CHECK FAILED` with the reason and stops.

The same file is kept in the Trainer Lens repository.
