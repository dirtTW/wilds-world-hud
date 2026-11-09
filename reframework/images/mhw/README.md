# Sprites are not stored in this repository

The PNGs this mod draws are cropped / re-composited from **Monster Hunter World**'s own UI
atlas (`ui/hud/tex/hud02_ID`, (c) CAPCOM). To keep this project free of game assets, they
are not committed here.

Put these 23 files in `reframework/images/mhw/`:

```
gw3_hp_L/C/R.png        health fill: diamond cap, gradient centre, tapered tip
gw3_st_L/C/R.png        stamina fill
gw_bg_L/C/R.png         translucent black backing (the shadow)
gw_sword.png            sharpness sword outline
gw_bar_<tier>.png       sharpness blade, tinted per tier (red orange yellow green blue white)
gw_glow_<tier>.png      baked halo per tier (same six names)
gauge_bracket.png       the ">" at the end of each bar
```

## Where to get them

1. **The packaged download** (Nexus Mods / GitHub Releases) ships the sprite folder, so the
   mod works out of the box.
2. **Build them from your own copy of Monster Hunter World**: extract
   `ui/hud/tex/hud02_ID` with the community `.tex` tools, then run

   ```
   python tools/slice_atlas.py hud02_ID.png reframework/images/mhw
   ```

   `tools/parse_gui.py` prints the `.gui` rects if you want to verify the coordinates
   (`ui/hud/hud_gauge.gui`).

The mod degrades gracefully: a gauge whose sprites are missing is simply not drawn.
