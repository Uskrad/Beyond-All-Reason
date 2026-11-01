function widget:GetInfo()
	return {
		name = "Map Editor Dev Redirect",
		desc = "Keeps Chobby Map Editor on the live game and sets map_editor=1",
		author = "Uskrad Dragon",
		date = "2026-09",
		license = "GNU GPL, v2 or later",
		layer = -10000,
		enabled = true,
	}
end

local wrappedReload = false
local wrappedWrapper = false

local function rewriteEditorScript(script)
	if type(script) ~= "string" then
		return script
	end
	local lower = script:lower()
	if not (lower:find("mapeditor", 1, true) or lower:find("map_editor", 1, true)) then
		return script
	end
	-- Do not change GameType. Swapping to $VERSION dropped Map Project loads
	-- and opened a blank Editor Flat instead of the saved project.
	if not lower:find("map_editor", 1, true) then
		script = script:gsub("[Mm][Aa][Pp][Ee][Dd][Ii][Tt][Oo][Rr]%s*=%s*1;", "mapeditor=1;\n\t\tmap_editor=1;")
	end
	return script
end

local function install()
	if not wrappedReload and Spring.Reload then
		local orig = Spring.Reload
		Spring.Reload = function(script)
			return orig(rewriteEditorScript(script))
		end
		wrappedReload = true
	end
	if not wrappedWrapper and WG and WG.WrapperLoopback and WG.WrapperLoopback.StartNewSpring then
		local orig = WG.WrapperLoopback.StartNewSpring
		WG.WrapperLoopback.StartNewSpring = function(opts)
			if type(opts) == "table" and type(opts.StartScriptContent) == "string" then
				opts.StartScriptContent = rewriteEditorScript(opts.StartScriptContent)
			end
			return orig(opts)
		end
		wrappedWrapper = true
	end
end

function widget:Initialize()
	install()
end

function widget:Update()
	install()
end
