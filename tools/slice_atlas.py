"""Slice the gauge sprites this mod expects out of Monster Hunter World's hud02_ID atlas.

You need:
  * `hud02_ID.png`  - the atlas, extracted from YOUR copy of MH World
                      (`ui/hud/tex/hud02_ID`) with the community .tex tools.
  * nothing else     - the rects below are the ones the mod uses and come from World's
                      `ui/hud/hud_gauge.gui` (see tools/parse_gui.py for the raw dump).

Usage:
    python slice_atlas.py hud02_ID.png ../reframework/images/mhw

Notes
-----
* The PNGs shipped in the release are further trimmed and colour-graded by hand; this
  script gives you the raw slices, which are geometrically correct but not identical.
* `gauge_bracket.png` (the ">" after each bar) is not in this atlas - it is drawn from
  World's guide-line sprite; copy it from the release package.
"""
import os
import sys
from PIL import Image

# name: (x, y, w, h) in the 512x512 atlas
RECTS = {
    # health / stamina fill (left cap, centre, right tip)
    "gw3_hp_L.png": (0, 55, 11, 20),
    "gw3_hp_C.png": (22, 55, 403, 20),
    "gw3_hp_R.png": (502, 55, 11, 20),
    "gw3_st_L.png": (0, 172, 11, 20),
    "gw3_st_C.png": (22, 172, 403, 20),
    "gw3_st_R.png": (502, 172, 11, 20),
    # translucent black backing (tex_eBace): left / centre / right
    "gw_bg_L.png": (0, 93, 64, 38),
    "gw_bg_C.png": (64, 93, 32, 29),
    "gw_bg_R.png": (461, 93, 50, 38),
    # sharpness: sword outline + white blade
    "gw_sword.png": (0, 133, 113, 33),
    "gw_bar_white.png": (114, 134, 72, 34),
    # glow source (eff)
    "gw_glow_src.png": (296, 205, 76, 32),
}


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    atlas_path, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    atlas = Image.open(atlas_path).convert("RGBA")
    for name, (x, y, w, h) in RECTS.items():
        atlas.crop((x, y, x + w, y + h)).save(os.path.join(out_dir, name))
        print("wrote", name, f"({w}x{h})")
    print("\nnext step: python make_glow_tiers.py  (needs the tier blades present)")
    print("missing: gauge_bracket.png and the per-tier tints - copy them from the release.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
