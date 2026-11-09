# Research reference (background for the implementation)

This is the raw research behind the mod: where the data came from and what the engine does.
For how the shipped code works read `../README.md`; for open gaps read `../TODO.md`.

> Scope: Wilds' **health / stamina / sharpness** gauges only. The item bar, buff icons,
> melody staff and palico HUD are deliberately left alone.

---

## 1. Wilds side: HUD node map

Health HUD is `app.GUI020003` (**GUIID 51**); the weapon/sharpness HUD is `app.GUI020015`
(**60**). Nodes are resolved with `getObject(System.String, System.Type)`:

```
PNL_Pat00/PNL_gaugeMode00/PNL_gauge00/PNL_gaugeMatBase/mat_gauge00..01   health fill
PNL_Pat00/PNL_gaugeMode00/PNL_gaugeEtc/PNL_gaugeRedIn/.../s9g_gaugeRed    recoverable health
PNL_Pat00/PNL_gaugeMode01/PNL_gaugeEasy/PNL_gaugeEasy01/mat_gauge00..03  stamina
PNL_Pat00/PNL_StateIcons                                                  buff / status icons
```

`PNL_StateIcons` is why the whole panel cannot be hidden: it lives under `PNL_Pat00`
together with the gauges. The mod keeps that one subtree and hides its siblings.

Player values:

```
app.PlayerManager
  :getMasterPlayerInfo() -> "<Character>k__BackingField"
  :get_HunterHealth():get_HealthMgr() -> get_Health() / get_MaxHealth()
  :get_HunterStamina()                -> get_Stamina() / get_MaxStamina()
  :get_WeaponHandling()._Kireaji      -> get_KireajiData() (UInt32[]), get_CurrentType(),
                                         get_CurrentRate(), get_CurrentValue()
```

GUI ids: see `gui_ids.csv` (311 enum entries, 11 verified live).

## 2. Sharpness data (the part that is easy to get wrong)

`get_CurrentValue()` is the remaining amount **inside the current tier**, not the total.
`get_KireajiData()` gives the per-tier capacities, indexed by `get_CurrentType()`:

```
example: [1100, 400, 400, 800, 300, 500]  total 3500
CurrentType = WHITE (5), CurrentRate = 0.9286, CurrentValue = 650 (= 700 * 0.9286)

filled = sum(capacities below the current tier) + capacity(current) * rate   -> 3450
len    = filled / total                                                      -> 98.6 %
```

A full white weapon therefore renders a full white bar; the colour then cycles
white -> blue -> green -> yellow -> red as the tiers drop.

## 3. Monster Hunter World `.gui` facts (`ui/hud/hud_gauge.gui`)

Extracted with `tools/parse_gui.py` (header offsets 56/184/200/360/384/392; `GUIObject` is
56 B, `InitParam` 32 B, type 4 = vector4).

```
tex_kBace        113 x 33   at (0, 10)     sword outline behind the sharpness fill
tex_sharpGauge    72 x 34   at (3, 0)      white blade, tinted at runtime
tex_sharpGaugeEff 76 x 32   at (3, 0)      glow, BlendState 5 (additive)
tex_eGaugeL0      11 x 20   at 0           health/stamina left cap
tex_eGaugeC0     403 x 20   at 24 / 20     centre
tex_eGaugeR0      11 x 20   at 414         right tip
tex_eBace         64/32/124 wide x 55 tall translucent black backing (taller than the 20-unit bar)
```

Consequences used by the renderer:

* the sword box aspect is **33/113**, not a flat 0.17;
* the backing is **55 vs 20** units, i.e. the shadow extends above and below the bar;
* the fill is a single tinted sprite (`tex_sharpGauge`), which is why the right tip is pointed
  and not a 9-slice cap.

## 4. Sprite pipeline

`hud02_ID` (512x512) is the gauge page of World's UI atlas. The shipped set:

```
gw3_hp_L/C/R        health fill: diamond cap / gradient centre / tapered tip
gw3_st_L/C/R        stamina
gw_bg_L/C/R         translucent black backing (the shadow)
gw_sword            sharpness sword outline
gw_bar_<tier> x6    sharpness blade, tinted offline (d2d cannot tint)
gw_glow_<tier> x6   baked halo (d2d cannot blend additively)
gauge_bracket       the ">" after each bar
```

`tools/slice_atlas.py` reproduces the raw slices from the user's own `hud02_ID.png`;
`tools/make_glow.py` / `make_glow_tiers.py` build the halos.

Notes:

* The caps are **taller than the bar** in the atlas (health cap 18 rows around a 10-row bar,
  stamina diamond 18 rows around 6). They must be drawn at their own aspect and offset from
  the bar, otherwise the diamond/arrow visibly squares off.
* The right caps must keep the fade column (alpha 174/223); slicing to fully opaque columns
  gives a blunt square end.
* The bars have almost no vertical gradient per column - the visible shading is a left-to-right
  ramp across the whole strip.

## 5. Measured parity (World reference, 2048x1152 training area)

```
health    718 px = 35.1 % of width, 11 px tall
stamina   717 px = 35.0 % of width,  6 px tall
gap        23 px =  2.0 % of height
sharpness 138 px =  6.7 % of width, starts ~25 px left of the bars
```

These are the numbers `mhw_bars.json` is tuned against (`hp_w .351`, `st_w .350`, `gap .02`,
`sw_*`) and they hold at any resolution because everything is a fraction of the surface.

## 6. Gotchas that still apply

* **d2d has no clear()**: stopping the draw leaves the last frame on screen. Hiding is done by
  drawing one quad off-screen.
* **d2d has no blend and no tint**: glows are baked PNGs, tiers are pre-tinted PNGs.
* **HUD setting changes reset the per-gauge display states** (HUD size Small/Default/Large).
  The mod re-applies its hides every ~5 s, and the menu has a *Re-hide* button.
* **Caps are taller than the bar** (see 4).
* **Sprite files are locked while the game runs**; `d2d.Image.new` belongs in the init
  callback, so sprite changes need a relaunch. `mhw_bars.json` does hot-reload.
* **Do not hook `onOpen`/`onClose` to detect menus**: those methods run continuously, and six
  such hooks cost ~78 FPS (90 -> 12) in testing. The working signal is
  `app.GUI020003.get_IsVisible()`.
