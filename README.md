# MH World HUD for Monster Hunter Wilds

Monster Hunter World's **health / stamina / sharpness** gauges, drawn over Monster Hunter
Wilds' native HUD with REFramework's d2d layer. The sprites are sliced from World's own
`hud02_ID` atlas, so the bars are the real art instead of a hand-drawn imitation.

* **Install:** [REFramework nightly](https://github.com/praydog/REFramework-nightly/releases)
  plus [reframework-d2d](https://github.com/cursey/reframework-d2d), then copy this repo's
  `reframework/` folder into your Monster Hunter Wilds directory **and** add the sprite set
  from the release package (or build it, see below).
* **Scope:** only the health, stamina and sharpness gauges are replaced. The item bar, buff
  icons, melody staff and palico HUD are untouched.
* **Auto-hide:** the overlay switches itself off whenever the game covers its HUD (world
  map, camp/chest menus, quest counter, squad counter, NPC dialogue, loading screens).
* **Tuning:** layout and feel live in `reframework/data/mhw_bars.json` and hot-reload.
* **Packages:** `wilds-world-hud-<ver>.zip` for manual install, `wilds-world-hud-<ver>-fluffy.zip` for **Fluffy Mod Manager** (its archive root is
  `reframework/`, so Fluffy extracts it cleanly; enable/disable the mod to install/remove).

Two caveats up front: the sharpness **glow** is a pre-baked halo because the game uses
additive blending and d2d cannot blend, and **this repository ships no CAPCOM art** - the
sprite folder comes with the release download, or you can rebuild it from your own copy of
World with `tools/slice_atlas.py` (see `reframework/images/mhw/README.md`).


> **No game assets in this repository.** The sprites are cropped from Monster Hunter
> World's atlas and are therefore distributed with the release package only, not committed
> here. See `reframework/images/mhw/README.md` and `NOTICE-assets.md`.

### AI disclosure
Parts of the Lua, tooling and this documentation were written with an **AI assistant**
(DeepSeek V4.1 Flash running in OpenCode), then reviewed, measured and corrected against the
live game. Every performance number and behaviour claim here was verified in-game. Human and
project credits are in `CREDITS.md`.

---

## 1. Architecture

```
reframework/autorun/
  MHWorldUI.lua     hides the native gauges + owns the "should the overlay draw?" flag
  MHWorldBars.lua   draws the World bars with d2d (health, stamina, sharpness)
reframework/data/
  mhw_bars.json     layout + tuning (hot-reloaded every 30 frames)
  mhw_gauge.json    rects parsed out of MH World's ui/hud/hud_gauge.gui
reframework/images/mhw/
  gw3_hp_L/C/R.png  health: diamond cap, gradient centre, tapered right cap
  gw3_st_L/C/R.png  stamina
  gw_bg_L/C/R.png   translucent black backing (the "shadow")
  gw_sword.png      sharpness sword outline
  gw_bar_<tier>.png sharpness blade tinted per tier (d2d cannot tint at runtime)
  gw_glow_<tier>.png pre-composited halo per tier (d2d cannot blend additively)
```

Two scripts are needed because they run on **different threads**:

| Script | Thread | Job |
|---|---|---|
| `MHWorldUI.lua` | `re.on_frame` (main) | engine calls: find the HUD, hide nodes, poll visibility |
| `MHWorldBars.lua` | `d2d` draw callback (render) | draw sprites only |

**Never call the engine from the d2d callback.** Doing heavy `sdk` work there is what made
the game hang / drop to 11 FPS during development. The render thread only reads a global
flag written by `MHWorldUI`.

---

## 2. Replacing the native gauges

Wilds' HUD canvas (GUI 51) contains `PNL_Pat00`, which holds both gauge modes **and**
`PNL_StateIcons` (the buff / status icons). The rule is therefore:

```lua
hide_children_except(PNL_Pat00, "PNL_StateIcons")  -- keep the icons, hide everything else
setHudDisplay(SHARPNESS, HIDDEN)                   -- sharpness is its own display element
setHudDisplay(HEALTH, DEFAULT)                     -- must stay visible: it owns the icons
```

Two traps here:

* Hiding the `HEALTH` **display element** also removes the buff icons (they belong to it).
  Hide the gauge nodes instead.
* `hide_children_except` walks the whole subtree. Doing that **every frame** was the single
  biggest frame cost of the script. It now runs once, then refreshes every 2 s.

---

## 3. Hiding the overlay when the game shows a menu

Every "menu sensor" the game exposes was tested with the map open, and **all of them lie**:

| API | Map open |
|---|---|
| `isHudVisible(HEALTH)` | True |
| `findDisplayControl(51)` | non-null |
| `isOpenFullScreenUI()` | False |
| `isOpenRadarMapGUI()` | False |
| `GUI060000.get_IsOpen()` | False |
| `GUI020003.get_ActualVisible()` | True |
| `checkEnableMoveAction()` | True |

What *does* work is the player HUD GUI's own visible flag:

```lua
local gui = gm:call("getGUI", 51)          -- app.GUI020003
if gui:call("get_IsVisible") == false then hide end
```

Measured: **True** in free roam, **False** over the map, camp/chest/quest menus, dialogue
choices and loading screens. Polled every 4th frame (≈15 Hz, two calls) — fast enough that
the overlay disappears in ~60 ms, cheap enough to be unmeasurable.

`GUIManager:isMouseCursorAvailable()` (the trick the Nier UI mod uses) was **not** usable
here: it returns True during normal mouse/keyboard play, so it would hide the HUD always.

### Why drawing "nothing" is not enough

`d2d` has **no `clear()`**, and it skips the surface upload when the callback draws nothing —
so the last frame stays on screen. When hidden we still emit one draw, off-screen:

```lua
d2d.fill_rect(-20000, -20000, 2, 2, 0xFF000000)
```

The same applies when the player HUD is not resolvable (loading): draw the quad, not `return`.

---

## 4. Sharpness semantics (the part everyone gets wrong)

`get_CurrentValue()` is **not** "total sharpness remaining". The game reports:

```
get_CurrentType() = WHITE (5)     -- which tier the weapon is in
get_CurrentRate() = 0.9286        -- how much of THAT tier is left
get_CurrentValue() = 650          -- 700 * 0.9286, the tier's remaining amount
```

So a nearly full weapon is *not* "650/3500 = 19 % red"; it is all lower tiers full plus
93 % of white = 98.6 %, drawn in the current tier's colour:

```lua
filled = sum(vals[1..tier-1]) + vals[tier] * rate
len    = filled / sum(vals)
```

`_KireajiData` (a `UInt32[]`) gives the per-tier capacities, indexed by the same enum, so
`vals[tier+1]` is the capacity of the active tier.

---

## 5. Rendering notes

* **9-slice fill.** Diamond cap on the left, centre stretched to the fill width, tapered cap
  at the fill tip. The cap's tip must travel with the fill (that is World's look), and the
  centre is drawn 2 px *under* the cap so the cap's fractional edge does not blend with the
  empty track (that blend shows as a 1 px seam).
* **The backing.** `tex_eBace` is ~55 units tall against a 20-unit bar in the .gui, i.e. the
  soft black shadow extends above and below the bar. Its sprite art is inset (the arrow tip
  is 23/64 into `gw_bg_L`, the fade ends 28/50 into `gw_bg_R`), so those *art* points are
  anchored to the bar ends — anchoring the sprite boxes instead makes the shadow diamond
  drift inward and look broken.
* **No runtime tint / blend.** d2d can only draw images with their own pixels:
  * sharpness tiers are pre-tinted PNGs (`gw_bar_<tier>.png`),
  * the additive glow (`tex_sharpGaugeEff`, BlendState 5) is faked with a pre-composited
    halo PNG per tier drawn under the blade.

---

## 6. Performance

Measured in the training area with the overlay visible:

| Change | Effect |
|---|---|
| Hook `onOpen/onClose` on 6 GUI classes to detect menus | 90 → **12 FPS** (those methods run per frame) |
| Per-frame `hide_children_except` over the gauge panel | large, continuous cost |
| Per-frame HP/stamina reads (~8 managed calls/frame) | significant at 120 Hz |
| Final build (see below) | **74 FPS** |

What the final build does:

1. **Sample, don't poll every frame.** HP/stamina are read every 4th frame into cached
   values; the spring interpolates between samples. The health/stamina manager objects are
   cached and re-resolved every 5 s.
2. **One visibility call per poll** (`getGUI` + `get_IsVisible`), every 4th frame.
3. **Adaptive d2d rate** — 120 Hz only while a bar is animating, 45 Hz when settled:
   ```lua
   if M.tick % 30 == 0 then
       d2d.detail.set_max_updaterate(M.moving and 120 or 45)
   end
   ```
4. **Periodic, not per-frame** native-panel hiding (every 2 s).
5. **Cache nothing that the game recreates** — the HUD GUI object is re-resolved each poll,
   otherwise the overlay survives loading screens.

Also: the spring must be integrated with the *measured* update interval. A hard-coded
`dt = 1/60` at 120 Hz makes the spring ~2× too stiff, which makes the stamina refill snap
to each regen tick instead of gliding.

```lua
local rate = update_rate()          -- measured draws/second
M.st_v, M.st_vel = spring_step(M.st_v, M.st_vel, target, F.k_st or 18.0, 1.0 / rate)
```

---

## 6b. In-game controls (REFramework -> MH World HUD)

| Control | What it does |
|---|---|
| **Show MH World overlay** | everyday on/off switch (same as `"hud_off": 1`) |
| **Use MH World HUD (custom gauges)** | **checked (default)** = our gauges. Uncheck to switch back to the game's own HUD: our hiding stops, the display states are restored, the gauge nodes are made visible again and our overlay switches off |
| **Re-hide vanilla gauges** | re-applies the hides immediately (only meaningful in custom mode) |
| **Hide / Show overlay** | buttons for the same flag |
| State line | shows whether the overlay is active, paused (game UI open) or replaced by the vanilla HUD |

Changing **any** HUD setting in game (HUD size Small / Default / Large, item bar, ...) makes
the game reset the per-gauge display states, which brings the native stamina and sharpness
gauges back on top of ours. The mod re-applies the overrides every ~5 seconds by itself; the
**Re-hide** button is for when you do not want to wait.

## 7. Layout tuning (`mhw_bars.json`, hot-reload)

```json
{
  "x": 0.095, "y": 0.061,
  "hp_w": 0.351, "hp_h": 0.00955, "hp_low": 0.40,
  "st_w": 0.35, "st_h": 0.00521, "gap": 0.02,
  "k_hp": 55, "k_st": 18,
  "base_h": 1.9,
  "sw_hl": 0.0194, "sw_bw": 0.0479, "sw_dx": 0.0107,
  "sw_bx": 0.30, "sw_bw_frac": 0.66, "sw_bh": 0.97,
  "glow_on": 1, "glow_scale": 1.0,
  "hud_off": 0
}
```

* All positions/sizes are fractions of the render surface, so they follow the resolution.
* World parity targets: health 35.1 % of screen width, stamina 35.0 %, gap 2.04 %; the
  sharpness sword is 0.1917 × health width and uses the .gui's 33/113 aspect.
* `k_hp` / `k_st` are spring stiffness (lower = smoother/slower), `hud_off: 1` force-hides
  the overlay, `glow_on: 0` disables the baked halo.

Sprites are **not** hot-swappable: d2d images are created in the init callback and the files
stay locked while the game runs. Scripts need a game restart (or REFramework's script reset)
to reload.

---

## 8. Known limitations

**Stamina refill smoothness.** To be precise: this is *our* trade-off, not a hard d2d limit.
`d2d.detail.set_max_updaterate` accepts up to 300 Hz; the overlay is capped at 120 Hz while a
gauge animates and 45 Hz when idle, and stamina is sampled every 4th frame, because at 240 Hz
with per-frame reads the mod cost ~20 FPS in testing. The game also reports stamina in coarse
steps, so on top of the cap the refill can read as slightly stepped, especially in busy
scenes. If perfect smoothness matters more than frames, raise the moving rate in
`MHWorldBars.lua` (`set_max_updaterate(M.moving and 120 or 45)`) and sample every frame
(`M.tick % 4`), or redraw from a C#/native hook instead of this overlay.

## 9. Research artefacts

* `.gui` parser: `mhwgui/parse_gui.py` (header offsets 56/184/200/360/384/392; GUIObject is
  56 B; InitParam 32 B; type 4 = vector4).
* Extracted atlas: `hud02_ID.png` (512×512) — every gauge sprite above is a crop of it.
* `gui_ids.csv` - full `GUIID.ID` enum (311 entries) with the manager class for each id,
  plus the six ids verified live with `GUIManager:getGUI(id)`: 51 `GUI020003` health HUD,
  52 `GUI020004` stamina HUD, 60 `GUI020015` sharpness HUD, 53 `GUI020006` item bar,
  50 `GUI020002` companion, 49 `GUI020001`.
* `.gui` facts used here: `tex_kBace` 113×33, `tex_sharpGauge` 72×34 at x=3, `tex_eBace`
  64/32/124 wide × 55 tall, `tex_eGaugeC0` 403×20.

---

## 10. References and what was borrowed from each

### `kmy0/HudController` (MIT, Monster Hunter Wilds)
The single most useful reference for Wilds' HUD structure. Used for:

* **Element -> GUI class mapping**, which our live probes confirmed:
  health = `app.GUI020003`, stamina = `app.GUI020004`, sharpness = `app.GUI020015`,
  item bar = `app.GUI020006`, companion = `app.GUI020002`.
* **The `GUIManager:getGUI(id)` accessor pattern** (`util/mod.get_gui_cls`):
  `sdk.get("app.GUIManager"):getGUI(gui_id)` is how any HUD GUI object is obtained by id.
  Our auto-hide is literally that call plus `get_IsVisible()`.
* **`PNL_StateIcons`** living under `PNL_Pat00`: this is why hiding the whole gauge panel
  also removed the buff icons, and why we keep that one subtree and hide its siblings.
* **Element child lists** used to know what a gauge is made of
  (`gauge / background / frame / light_start / light_end / red_health / incoming_health /
  skill_list / skill_line / max_fall` for health; `gauge / background / frame / frame_max /
  ex` for stamina; `anim_max / background / frame / next / edge` for sharpness).
* Confirmation that the sharpness HUD keeps its own state machine ("small" knife vs "big"),
  which is why the sharpness gauge is hidden through the display element, not by node names.

What we deliberately did **not** copy: their hook-heavy approach. `HudController` hooks many
engine methods (`onOpen`, `onClose`, `guiOpenUpdate`, ...) to drive its per-element UI. That
is fine for an ImGui settings panel, but for a per-frame overlay it cost us 90 -> 12 FPS,
because those methods run continuously rather than once per transition.

### `praydog/REFramework` + `cursey/reframework-d2d`
* d2d API surface: `d2d.image`, `fill_rect`, `fill_quad`, `surface_size`,
  `detail.get/set_max_updaterate`, `register(init, draw)`.
* Confirmed constraints that shaped the design: **no clear()**, **no blend mode**, **no
  runtime tint**, and images must be created in the init callback.
* The C# side (`REFrameworkWebAPI`) is also what taught us the hard lesson in TODO.md:
  rapid-fire `invoke_method` calls through the WebAPI can take the process down.

### MH World `.gui` (the game's own UI data)
* `ui/hud/hud_gauge.gui` parsed with `mhwgui/parse_gui.py`: exact sprite rects
  (`tex_kBace` 113x33, `tex_sharpGauge` 72x34 at x=3, `tex_eBace` 64/32/124 wide x 55 tall,
  `tex_eGaugeC0` 403x20) and the node sizes that define the 33/113 sword aspect and the
  55-vs-20 backing height.
* `coladj_sharpness` exists there but its per-tier values were never parsed (see TODO #2).
