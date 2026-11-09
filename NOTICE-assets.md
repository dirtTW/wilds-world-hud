# Asset notice

`reframework/images/mhw/*.png` are cropped, trimmed and - for the tier tints and the glow
halos - re-composited from **Monster Hunter World**'s own UI textures:

* source atlas: `ui/hud/tex/hud02_ID` (© CAPCOM)
* layout reference: `ui/hud/hud_gauge.gui` (© CAPCOM)

They are included **only** so the mod works without users having to extract World
themselves. They are **not** covered by this project's MIT licence, they are not sold, and
they are fan work for a game the user already owns. All rights remain with CAPCOM.

No Monster Hunter Wilds files are included or redistributed: the mod only reads runtime
state through REFramework.

If CAPCOM (or a representative) asks for removal, the images will be dropped from the
repository and downloads and the project will switch to `tools/slice_atlas.py`, which builds
the sprites from the user's own copy of Monster Hunter World.
