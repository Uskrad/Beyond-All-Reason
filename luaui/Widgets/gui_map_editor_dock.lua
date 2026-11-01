local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Map Editor Dock",
		desc = "Visible left dock if Rml chrome is missing",
		author = "Uskrad Dragon",
		date = "2026-09",
		license = "GNU GPL, v2 or later",
		layer = 99991,
		enabled = false,
		handler = true,
	}
end

return false

local MSG = "$ME$"
local TABS = { "Sculpt", "Paint", "Place", "Map" }
local TOOLS = { "Raise", "Lower", "Flatten", "Smooth", "Ramp" }
local TOOL_IDS = { "raise", "lower", "flatten", "smooth", "ramp" }

local function editorRequested()
	local ok, opts = pcall(Spring.GetModOptions)
	if not ok or type(opts) ~= "table" then
		return false
	end
	local v, v2 = opts.map_editor, opts.mapeditor
	return v == true or v == 1 or v == "1" or v2 == true or v2 == 1 or v2 == "1"
end

local state = {
	tab = 1,
	tool = 1,
	mirrorH = false,
	mirrorV = false,
	radial = 0,
	radialSteps = { 0, 3, 4, 5, 6, 8 },
	hits = {},
}

local function send(body)
	Spring.SendLuaRulesMsg(MSG .. body)
end

local function radialLabel()
	if (state.radial or 0) < 3 then
		return "Off"
	end
	return tostring(state.radial) .. " pt"
end

local function sendMirror()
	send(string.format("mirror,%s,%s,%d", state.mirrorH and "1" or "0", state.mirrorV and "1" or "0", state.radial or 0))
end

function widget:Initialize()
	Spring.Echo("Map Editor Dock: loaded")
end

function widget:Update()
end

local function hit(id, x1, y1, x2, y2)
	state.hits[id] = { x1, y1, x2, y2 }
end

local function inside(box, x, y)
	return box and x >= box[1] and y >= box[2] and x <= box[3] and y <= box[4]
end

local function btn(id, x, y, w, h, label, on)
	hit(id, x, y, x + w, y + h)
	if on then
		gl.Color(0.27, 0.47, 0.27, 0.95)
	else
		gl.Color(0.07, 0.07, 0.07, 0.95)
	end
	gl.Rect(x, y, x + w, y + h)
	gl.Color(1, 1, 1, 1)
	gl.Text(label, x + 8, y + h * 0.28, 14, "o")
end

function widget:DrawScreen()
	if not editorRequested() then
		return
	end
	if WG and WG.mapEditorLive then
		return
	end
	local vsx, vsy = Spring.GetViewGeometry()
	if not vsx then
		return
	end
	state.hits = {}
	local w = vsx * 0.18
	gl.Color(0.07, 0.08, 0.07, 0.96)
	gl.Rect(0, 0, w, vsy)
	gl.Color(0.55, 0.9, 0.4, 1)
	gl.Text("MAP EDITOR", 12, vsy - 36, 20, "o")
	local y = vsy - 70
	local tw = (w - 20) / 4
	for i = 1, #TABS do
		btn("tab" .. i, 8 + (i - 1) * tw, y - 28, tw - 4, 28, TABS[i], state.tab == i)
	end
	y = y - 58
	gl.Color(0.7, 0.7, 0.7, 1)
	gl.Text("SYMMETRY", 12, y, 13, "o")
	y = y - 36
	local hw = (w - 24) / 2
	btn("mh", 8, y - 28, hw, 28, "Mirror H", state.mirrorH)
	btn("mv", 12 + hw, y - 28, hw, 28, "Mirror V", state.mirrorV)
	y = y - 70
	gl.Color(0.7, 0.7, 0.7, 1)
	gl.Text("RADIAL  " .. radialLabel(), 12, y, 13, "o")
	btn("rd", w - 84, y - 6, 32, 24, "-", false)
	btn("ri", w - 44, y - 6, 32, 24, "+", false)
	y = y - 50
	if state.tab == 1 then
		for i = 1, #TOOLS do
			btn("tool" .. i, 8, y - 32, w - 16, 32, TOOLS[i], state.tool == i)
			y = y - 38
		end
	elseif state.tab == 2 then
		gl.Color(1, 1, 1, 1)
		gl.Text("Metal / Grass / Tex in Rml dock", 12, y, 14, "o")
	elseif state.tab == 3 then
		gl.Color(1, 1, 1, 1)
		gl.Text("Place / Delete in Rml dock", 12, y, 14, "o")
	else
		gl.Color(1, 1, 1, 1)
		gl.Text("Name / New / Save Map in Rml dock", 12, y, 14, "o")
	end
	gl.Color(1, 1, 1, 1)
end

function widget:MousePress(mx, my, button)
	if not editorRequested() then
		return false
	end
	if WG and WG.mapEditorLive then
		return false
	end
	if button ~= 1 then
		return false
	end
	for i = 1, #TABS do
		if inside(state.hits["tab" .. i], mx, my) then
			state.tab = i
			return true
		end
	end
	if inside(state.hits.mh, mx, my) then
		state.mirrorH = not state.mirrorH
		sendMirror()
		return true
	end
	if inside(state.hits.mv, mx, my) then
		state.mirrorV = not state.mirrorV
		sendMirror()
		return true
	end
	if inside(state.hits.rd, mx, my) then
		for i = #state.radialSteps, 1, -1 do
			if state.radialSteps[i] < (state.radial or 0) then
				state.radial = state.radialSteps[i]
				break
			end
			if i == 1 then
				state.radial = 0
			end
		end
		sendMirror()
		return true
	end
	if inside(state.hits.ri, mx, my) then
		for i = 1, #state.radialSteps do
			if state.radialSteps[i] > (state.radial or 0) then
				state.radial = state.radialSteps[i]
				break
			end
		end
		sendMirror()
		return true
	end
	for i = 1, #TOOLS do
		if inside(state.hits["tool" .. i], mx, my) then
			state.tool = i
			return true
		end
	end
	return false
end
