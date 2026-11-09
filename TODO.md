# MH World HUD — TODO / known gaps

Items are ordered by "what a user would notice first". Each one states the blocker, so the
next modder does not have to rediscover it.

## 1. Sharpness glow is faked, not additive  ★ visible
- **Now:** `tex_sharpGaugeEff` uses `BlendState 5` (additive) in MH World's `.gui`. d2d has
  no blend modes, so the halo is a pre-composited PNG drawn *under* the blade
  (`gw_glow_<tier>.png`).
- **Gap:** it cannot brighten the scene behind it the way true additive blending does, and
  it is fixed per tier (it cannot blend between tiers during the tier-change animation).
- **Possible route:** a C# plugin drawing with D2D1 blend state (or a native `via.gui`
  draw) instead of `reframework-d2d`.

## 2. Sharpness tier colours are derived, not parsed  ★ subtle
- **Now:** `gw_bar_<tier>.png` tints come from averaging the colour of World's own blade
  pixels in the atlas.
- **Gap:** the real per-tier colours live in `coladj_sharpness` in the `.gui` and are applied
  at runtime; they were never parsed.
- **Route:** extend `mhwgui/parse_gui.py` to dump the `coladj_*` init params, then re-tint.

## 3. Recoverable health band not implemented  ★ gameplay-relevant
- **Now:** below 40 % HP the whole fill turns flat red (`0xFFE24A44`).
- **Gap:** World shows a *red band* between `cur` and `cur + red` (the `g9g_gaugeRed` /
  `PNL_gaugeRedIn` node) while the rest stays green. `MHWorldUI` already resolves the node
  (`red_in=true red=true` in the log), but the `HealthMgr` accessor for the recoverable
  amount was never found.
- **Route:** read the red amount from `cHunterHealth` (fields around `_RedHealth`), then draw
  fill → red band → fill.

## 4. Blurred background under the bars  ★ optional
- **Gap:** World's HUD panel sits on a subtle dimmed backdrop; ours only has the thin
  `tex_eBace` shadow strip.

## 5. Non-white tiers verified only by pixels
- Blue/green/yellow/red tier renders were sanity-checked from screenshots, but no numeric
  comparison against World's own tier crops was done (only the white tier was measured).

## 6. Layout is hand-tuned, not read from the .gui at runtime
- `mhw_bars.json` holds fractions measured against a 2048×1152 reference
  (health 35.1 %, stamina 35.0 %, gap 2.04 %, sword 0.1917 × health width, aspect 33/113).
- A fully data-driven layout would parse `hud_gauge.gui` at load and derive the fractions.
  The parser exists (`mhwgui/parse_gui.py`); the runtime binding does not.

## 7. Auto-hide coverage depends on one flag
- `app.GUI020003.get_IsVisible()` covers map / camp-chest / quest counter / squad counter /
  dialogue choice / loading (all verified).
- If a future UI keeps the HUD flag `true`, add that GUI id to the poll (see
  `gui_ids.csv`) instead of reintroducing `sdk.hook` — hooks on `onOpen/onClose` cost
  ~78 FPS (90 → 12) because those methods run continuously, not once per transition.

## 8. Sprite hot-reload
- d2d images are created in the init callback and the files stay locked while the game runs,
  so sprite changes need a game restart. Layout/tuning values in `mhw_bars.json` *do*
  hot-reload (every 30 frames).

---

## Support notes (not mod bugs)

* **The game was crashing with the MCP bridge attached.** Windows Event Log shows an
  unhandled exception inside `REFrameworkWebAPI.PostExplorerMethod` →
  `REFrameworkNET.ManagedObject.get_ref_count`, i.e. the HTTP API invoking a game method.
  Rapid-fire `reframework_invoke_method` calls (e.g. a 320-iteration `getGUI` scan) can take
  the process down. The Lua mod itself was logging normally right before the crash.
  → Keep MCP calls few and batched; disable `reframework/plugins/source` (WebAPI) for normal
  play if stability matters more than live debugging.
* `d2d` keeps the last surface when the draw callback stops drawing, so "hide" is
  implemented by drawing one quad off-screen (`-20000, -20000`).
