# Wilds World HUD

Monster Hunter World's **health / stamina / sharpness** gauges, drawn over Monster Hunter
Wilds' native HUD (REFramework + d2d). The sprites are sliced from World's own atlas, so the
bars are the real art, not a redraw.

```
Wilds + REFramework nightly + reframework-d2d  ->  this mod
```

## Install

1. Install [REFramework nightly](https://github.com/praydog/REFramework-nightly/releases)
   and [reframework-d2d](https://github.com/cursey/reframework-d2d).
2. Download a package below and extract it into your Monster Hunter Wilds folder.
3. Launch. Only the three gauges are replaced - item bar, buff icons, melody staff and
   palico HUD stay vanilla.

**Packages**
| File | Use |
|---|---|
| `wilds-world-hud-<ver>.zip` | manual install (extract into the game folder) |
| `wilds-world-hud-<ver>-fluffy.zip` | Fluffy Mod Manager (archive root is `reframework/`) |

## In game (REFramework -> MH World HUD)

| Control | Effect |
|---|---|
| Show MH World overlay | everyday on/off |
| Use MH World HUD (custom gauges) | **checked** = World gauges, **unchecked** = the game's own HUD and our hiding stops |
| Re-hide vanilla gauges | instant fix if the vanilla gauges reappear after changing a HUD setting |
| Hide / Show overlay | same as the checkbox |
| State line | active / paused (game UI open) / vanilla |

The overlay hides itself whenever the game covers its HUD: world map, camp/chest menus, quest
counter, squad counter, NPC dialogue, loading screens.

## Performance

Measured **86 FPS** in the training area with the overlay on (before optimisation: 42 FPS).
No hooks are installed; game state is sampled every 4th frame, the d2d redraw cap is constant,
and the native-panel hide runs every 2 s instead of every frame. Details in
[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md).

## Known limitations

- The sharpness glow is a pre-baked halo - d2d cannot do the game's additive blending.
- Tier tints are derived from World's blade pixels, not parsed from `coladj_sharpness`.
- The recoverable-health red band is not implemented (flat red below 40 % HP).
- The stamina refill can read slightly stepped: it is capped at 120 Hz redraw with sampled
  input, which is the frame-time trade-off that keeps the mod free. See `TODO.md`.

## Repository contents

```
reframework/   Lua + JSON + (no sprites: they ship with the release)
docs/          IMPLEMENTATION.md, REFERENCE.md (research), gui_ids.csv
tools/         parse_gui.py, slice_atlas.py, make_glow*.py
```

**No CAPCOM assets in this repository.** The PNGs are cropped from Monster Hunter World's UI
atlas and are distributed with the release package only; `tools/slice_atlas.py` can rebuild
them from your own copy of World. See `NOTICE-assets.md`.

## Credits

praydog (REFramework), cursey (reframework-d2d), kmy0 (HudController research) and the MH
modding community - full list in [CREDITS.md](CREDITS.md).

### AI disclosure
Parts of the Lua, tooling and documentation were written with an AI assistant (DeepSeek V4.1
Flash in OpenCode), then reviewed, measured and corrected against the live game. Every
performance number here was verified in-game.

MIT for the code (`LICENSE`); the game art is not covered by it.
