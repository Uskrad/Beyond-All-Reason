# Map compile helper

The map editor is **in-game**, not this folder.

- Launch: `tools/StartScripts/startscript_map_editor.txt`
- Code: `luarules/gadgets/map_editor.lua`, `luarules/gadgets/include/map_editor_compile.lua`, `luaui/RmlWidgets/gui_map_editor/`
- Plan: `.cursor/plans/map-editor.md`
- Name field + **New Map** writes `maps/<Name>.sdd` (blank name → Untitled NxN) and reloads.
- **Save Map (F7)** overwrites that `.sdd` (or a typed name) and packs a single-file archive: `maps/<Name>.sd7` when 7-Zip is installed, otherwise a zip `maps/<Name>.sdz`. Recoil loads both.

Do not put the editor UI here.
