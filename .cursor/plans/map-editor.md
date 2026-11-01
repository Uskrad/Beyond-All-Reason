# In-game map editor — living plan

Active product for this fork. Do not reopen `tools/map-editor/src` as a standalone app.

Quality bar: [`.cursor/rules/map-editor.mdc`](../rules/map-editor.mdc)

## Status

| Slice | Status |
|---|---|
| Harness (this file + rule) | done |
| Editor mode (modoption, IsMapEditor, startscript, spawn/HUD gate) | done |
| RmlUi chrome + height sculpt | done |
| Phase 2: metal + grass in the same chrome | done |
| Phase 3: FeatureDefs/UnitDefs place/rotate/delete | done |
| Phase 4: startboxes + start points | done |
| Phase 4b: mapinfo / lighting | done |
| Phase 5: save/load/autosave + playtest / return-to-editor | done |
| Phase 6: texture / SSMF | done |
| Phase 7: sidecar lua dump | superseded |
| Phase 8: compile live session to a loadable `maps/*.sdd` | done |
| Phase 9: New Map (blank SMF/SMT + reload into editor) | done |
| Phase 10: typed map name + Save Map pack (`.sd7` / `.sdz`) | done |

## Product loop

Launch editor (any installed map as bootstrap) → type a **Name** → **New Map** creates `maps/<Name>.sdd` and reloads onto it → sculpt, place, paint → playtest → **Save Map (F7)** writes the `.sdd` and packs `.sd7` (7-Zip) or `.sdz` (zip).

Launch: the live BAR install at `C:\Program Files\Beyond-All-Reason\data\` (Chobby Map Editor). Repo edits are not shipped until `tools/StartScripts/publish_map_editor.ps1` copies them there. Do not treat a git-only change as done.

## Code

- Synced: `luarules/gadgets/map_editor.lua`
- Compile: `luarules/gadgets/include/map_editor_compile.lua`
- Chrome + tools: `luaui/RmlWidgets/gui_map_editor/`
- Grass visual hook: `WG.grassgl4.syncFromEngine` in `map_grass_gl4.lua`
- HUD hide is **session-only** (`RemoveWidgetRaw` / `InsertWidgetRaw`). Never `DisableWidget`.
- F7 saves the live session into a loadable `maps/*.sdd` and packs `.sd7` (7-Zip) or `.sdz` (zip). **New Map** writes a blank SMF/SMT archive and reloads the editor onto it.

## Next slice

Closed. Do not invent a next slice unless Ben names one. Do not reopen `dbg_*` widgets.

## Restore loop (active)

Get the **Rml** MAP EDITOR panel working like the old floating tool panel: visible tools, clicks land, tools edit. Do **not** use `gui_map_editor_dock.lua`.

Each tick: sweep live `infolog.txt` → fix one defect class on the live copy → publish.

Stop when infolog shows `Rml chrome shown`, no `Terraform Brush] Mode: RAISE` after GameStart, and `Map Editor: click` when a dock button is pressed.

