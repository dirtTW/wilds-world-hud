# Credits

This mod exists because of other people's work. Please keep these credits if you fork it.

## Runtime dependencies
| Project | Author | Licence | What it does here |
|---|---|---|---|
| [REFramework](https://github.com/praydog/REFramework) | praydog | MIT | Lua scripting host, `sdk`/`re` API, plugin loader |
| [reframework-d2d](https://github.com/cursey/reframework-d2d) | cursey (praydog org) | MIT | Direct2D drawing API used for the whole overlay |

## Reference / research
| Project | Author | What we learned |
|---|---|---|
| [HudController](https://github.com/kmy0/HudController) | kmy0 | Wilds' HUD element structure: `PNL_Pat00` / `PNL_StateIcons`, the element -> GUI class map (health `GUI020003`, stamina `GUI020004`, sharpness `GUI020015`, item bar `GUI020006`, companion `GUI020002`), and the `GUIManager:getGUI(id)` accessor pattern that our auto-hide is built on |
| [re-engine-mcp](https://github.com/praydog/re-engine-mcp) | praydog | Live object inspection used while reverse-engineering the gauge data (`cWeaponKireaji`, `cHunterHealth`, GUI visibility) |

## Game data
* Monster Hunter World's HUD sprites (`ui/hud/tex/hud02_ID`) and `.gui` layout
  (`ui/hud/hud_gauge.gui`) — **© CAPCOM**. The PNGs in `reframework/images/mhw/` are
  slices/derivatives of World's own assets, included so the mod works out of the box.
  They are fan-use only, not covered by this project's MIT licence. See `NOTICE-assets.md`.
* Monster Hunter Wilds — **© CAPCOM**. No game binaries are included; the mod only reads
  runtime state through REFramework.

## Community
* The MH modding community (Nexus Mods, the REFramework Discord) for the endless
  `.gui`/RE Engine notes that made the atlas and node names decipherable.
