if not RmlUi then
	return
end

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Map Editor",
		desc = "In-game map editor chrome and tools",
		author = "Uskrad Dragon",
		date = "2026-09",
		license = "GNU GPL, v2 or later",
		layer = 99990,
		enabled = true,
		handler = true,
	}
end

if not Spring.Utilities.IsMapEditor() then
	return false
end

include("keysym.h.lua")

local MSG_PREFIX = "$ME$"
local MODEL_NAME = "map_editor_model"
local RML_PATH = "luaui/RmlWidgets/gui_map_editor/gui_map_editor.rml"
local PAINT_INTERVAL = 0.045
local MIN_RADIUS = 24
local MAX_RADIUS = 1200
local MIN_STRENGTH = 1
local MAX_STRENGTH = 80
local RADIUS_STEP = 20
local STRENGTH_STEP = 1
local FALLOFF_STEP = 0.05

local TOOLS = { "raise", "lower", "flatten", "smooth", "ramp", "metal", "demetal", "grass", "cut", "place", "delete", "box", "start", "erasebox", "sun", "ambient", "fog", "water", "splat1", "splat2", "splat3", "splat4" }
local LAYER_TOOLS = {
	height = { "raise", "lower", "flatten", "smooth", "ramp" },
	metal = { "metal", "demetal" },
	grass = { "grass", "cut" },
	assets = { "place", "delete" },
	starts = { "box", "start", "erasebox" },
	light = { "sun", "ambient", "fog", "water" },
	tex = { "splat1", "splat2", "splat3", "splat4" },
}
local LAYER_DEFAULT = {
	height = "raise",
	metal = "metal",
	grass = "grass",
	assets = "place",
	starts = "box",
	light = "sun",
	tex = "splat1",
}
local LAYER_TAB = {
	height = "sculpt",
	metal = "paint",
	grass = "paint",
	tex = "paint",
	assets = "place",
	starts = "map",
	light = "map",
}
local TOOL_TIP_KEYS = {
	raise = "raiseTip",
	lower = "lowerTip",
	flatten = "flattenTip",
	smooth = "smoothTip",
	ramp = "rampTip",
	metal = "metalTip",
	demetal = "demetalTip",
	grass = "grassTip",
	cut = "cutTip",
	place = "placeTip",
	delete = "deleteTip",
	box = "boxTip",
	start = "startTip",
	erasebox = "eraseboxTip",
	sun = "sunTip",
	ambient = "ambientTip",
	fog = "fogTip",
	water = "waterTip",
	splat1 = "splat1Tip",
	splat2 = "splat2Tip",
	splat3 = "splat3Tip",
	splat4 = "splat4Tip",
}
local TOOL_TIP_FALLBACK = {
	raise = "Adds height under the brush. Hold LMB and drag to build hills. Strength is how fast each dab rises. Falloff feathers the rim. Shift applies at full strength.",
	lower = "Removes height under the brush. Hold LMB and drag to cut valleys. Strength is how fast each dab sinks. Falloff feathers the rim. Shift applies at full strength.",
	flatten = "Levels the brush to the height you clicked when the stroke began. Drag to grow a plateau. Strength is how completely each dab reaches that height. Shift finishes in one pass.",
	smooth = "Blurs height inside the brush. Softens peaks, pits, and cliffs at about 40% of the brush radius. Hold to keep blurring. Does not plateau to the click height — that is Flatten.",
	ramp = "Drag from point A to point B. Heights along the corridor lerp from start height to end height. Radius is corridor width. A click with no drag does nothing.",
	metal = "Paints metal map cells inside the brush. Density follows Strength. Right-click (or Demetal) clears metal. Does not change height or grass.",
	demetal = "Erases metal map cells inside the brush. Strength is how fast cells clear. Does not grow grass or sculpt terrain.",
	grass = "Grows engine grass inside the brush. Right-click (or Cut) removes it. Does not paint metal or splat.",
	cut = "Removes grass inside the brush. Strength is how aggressively tufts clear. Does not erase metal or flatten height.",
	place = "Left-click plants the selected feature or unit at the cursor. Ghost preview follows the mouse. Right-click deletes nearby assets. [ ] cycles the palette. R rotates.",
	delete = "Left-click removes features and units inside the radius. Right-click also deletes. Radius is the delete circle. Does not sculpt or paint.",
	box = "Drag on the ground to set the team 0 start box. A tiny drag is ignored. Right-click or Clear box removes it.",
	start = "Left-click sets the team 0 start point. Does not draw the box — use Start box for that.",
	erasebox = "Clears the start box in one click. Start point is left alone.",
	sun = "Sun direction. Click the ground to aim azimuth from map center. Azimuth / Altitude / Shadow sliders nudge the vector.",
	ambient = "Ground ambient RGB scale. Strength row is diffuse; Falloff row is shadow density.",
	fog = "Atmosphere fog start and end. Keep start below end. Shadow row still controls shadow density.",
	water = "Water surface alpha plus a shared ambient nudge. Switch to Sun to aim the sun.",
	splat1 = "Paints splat channel 1. LMB paints, RMB erases that channel only.",
	splat2 = "Paints splat channel 2. LMB paints, RMB erases this channel only.",
	splat3 = "Paints splat channel 3. LMB paints, RMB erases this channel only.",
	splat4 = "Paints splat channel 4. LMB paints, RMB erases this channel only.",
}
local TOOL_COLORS = {
	raise = { 0.35, 0.95, 0.45, 0.95 },
	lower = { 0.95, 0.4, 0.35, 0.95 },
	flatten = { 0.95, 0.85, 0.3, 0.95 },
	smooth = { 0.4, 0.7, 1.0, 0.95 },
	ramp = { 0.95, 0.65, 0.2, 0.95 },
	metal = { 1.0, 0.82, 0.2, 0.95 },
	demetal = { 0.55, 0.45, 0.2, 0.95 },
	grass = { 0.35, 0.9, 0.4, 0.95 },
	cut = { 0.55, 0.35, 0.15, 0.95 },
	place = { 0.55, 0.85, 1.0, 0.95 },
	delete = { 0.95, 0.45, 0.4, 0.95 },
	box = { 0.35, 0.75, 1.0, 0.95 },
	start = { 1.0, 0.9, 0.35, 0.95 },
	erasebox = { 0.95, 0.45, 0.4, 0.95 },
	sun = { 1.0, 0.85, 0.35, 0.95 },
	ambient = { 0.95, 0.75, 0.55, 0.95 },
	fog = { 0.7, 0.8, 0.95, 0.95 },
	water = { 0.35, 0.65, 1.0, 0.95 },
	splat1 = { 0.95, 0.45, 0.35, 0.95 },
	splat2 = { 0.45, 0.9, 0.4, 0.95 },
	splat3 = { 0.4, 0.55, 0.95, 0.95 },
	splat4 = { 0.95, 0.9, 0.35, 0.95 },
}
local TEX_SIZE = 512
local SPLAT_CH = { splat1 = 1, splat2 = 2, splat3 = 3, splat4 = 4 }
local METAL_SQUARE = Game.metalMapSquareSize or 16
local GRASS_STEP = 16

local HUD_TO_DISABLE = {
	"Pregame UI",
	"Pregame UI - Draft Spawn Order",
	"Pregame Queue",
	"Build menu",
	"Grid menu",
	"Top Bar",
	"Order menu",
	"Info",
	"AdvPlayersList",
	"Quick Start UI",
	"Idle Builders",
	"Start Boxes",
	"Map Lighting Adjuster",
}

local spTraceScreenRay = Spring.TraceScreenRay
local spGetMouseState = Spring.GetMouseState
local spGetGroundHeight = Spring.GetGroundHeight
local spGetGameRulesParam = Spring.GetGameRulesParam
local spGetMetalAmount = Spring.GetMetalAmount
local spGetGrass = Spring.GetGrass
local spI18N = Spring.I18N
local glColor = gl.Color
local glLineWidth = gl.LineWidth
local glDrawGroundCircle = gl.DrawGroundCircle
local glDepthTest = gl.DepthTest

local widgetState = {
	rmlContext = nil,
	document = nil,
	dmHandle = nil,
	tool = "raise",
	layer = "height",
	radius = 240,
	strength = 12,
	falloff = 0.7,
	painting = false,
	rampStart = nil,
	lastPaint = 0,
	cursorX = 0,
	cursorZ = 0,
	hasCursor = false,
	hudHidden = false,
	hudPasses = 0,
	grassRev = -1,
	paletteKind = "features",
	paletteIndex = 1,
	facing = 0,
	features = {},
	units = {},
	unitGhostId = nil,
	boxDrag = nil,
	playtesting = false,
	stashedHud = {},
	paintTex = nil,
	texUndo = {},
	texRedo = {},
	texRev = -1,
	texQueue = {},
	texStroke = false,
	texErase = false,
	newMapSmu = 16,
	mapTitle = "",
	naming = false,
	reloading = false,
	hoverTip = nil,
	lastPaintLayer = "metal",
	lastMapLayer = "starts",
	lightRev = -1,
	lightReady = false,
	light = {
		sx = 0,
		sy = 1,
		sz = 0,
		ar = 0.5,
		ag = 0.5,
		ab = 0.5,
		dr = 0.8,
		dg = 0.8,
		db = 0.8,
		shadow = 0.8,
		fogS = 0.1,
		fogE = 1.0,
		water = 0.4,
		az = 0,
		alt = 45,
	},
}

local initialModel = {
	title = "MAP EDITOR",
	mapName = Game.mapName or "",
	dirtyLabel = "",
	terrainLabel = "TERRAIN",
	sectionLabel = "TERRAIN",
	tabSculpt = "Sculpt",
	tabPaint = "Paint",
	tabPlace = "Place",
	tabMap = "Map",
	tipTitle = "Raise",
	tipBody = "Adds height under the brush. Hold LMB and drag to build hills.",
	heightLayer = "Terrain",
	metalLayer = "Metal",
	grassLayer = "Grass",
	raiseLabel = "Raise",
	lowerLabel = "Lower",
	flattenLabel = "Flatten",
	smoothLabel = "Smooth",
	rampLabel = "Ramp",
	metalPaint = "Paint metal",
	metalErase = "Erase metal",
	grassGrow = "Grow grass",
	grassCut = "Cut grass",
	assetsLayer = "Assets",
	placeLabel = "Place",
	deleteLabel = "Delete",
	featuresLabel = "Features",
	unitsLabel = "Units",
	rotateLabel = "Rotate",
	assetName = "—",
	startsLayer = "Starts",
	boxLabel = "Start box",
	startLabel = "Start point",
	eraseBoxLabel = "Clear box",
	lightLayer = "Light",
	sunLabel = "Sun",
	ambientLabel = "Ambient",
	fogLabel = "Fog",
	waterLabel = "Water",
	texLayer = "Tex",
	splat1Label = "Splat 1",
	splat2Label = "Splat 2",
	splat3Label = "Splat 3",
	splat4Label = "Splat 4",
	radiusLabel = "Radius",
	strengthLabel = "Strength",
	falloffLabel = "Falloff",
	undoLabel = "Undo",
	redoLabel = "Redo",
	saveLabel = "Snapshot",
	loadLabel = "Restore",
	playLabel = "Playtest",
	editLabel = "Return to editor",
	exportLabel = "Save Map",
	newLabel = "New Map",
	newSizeLabel = "Size",
	newSizeValue = "16×16",
	nameLabel = "Name",
	namePlaceholder = "Map name",
	radiusValue = "240",
	strengthValue = "12",
	falloffValue = "70%",
	statusLine = "",
	hint = "[ ] radius  ·  RMB erase  ·  Shift full  ·  Ctrl+Z undo  ·  F7 save map",
}

local function t(key, fallback)
	local value = spI18N("ui.mapEditor." .. key)
	if not value or value == "" or value:find("ui.mapEditor", 1, true) then
		return fallback
	end
	return value
end

local function send(body)
	Spring.SendLuaRulesMsg(MSG_PREFIX .. body)
end

local function channel8(v)
	v = tonumber(v) or 0
	if v <= 1 then
		v = v * 255
	end
	v = math.floor(v + 0.5)
	if v < 0 then
		return 0
	end
	if v > 255 then
		return 255
	end
	return v
end

local function saveSplatDump()
	if not widgetState.paintTex or not gl.ReadPixels or not gl.RenderToTexture or not io then
		return
	end
	local pix
	gl.RenderToTexture(widgetState.paintTex, function()
		pix = gl.ReadPixels(0, 0, TEX_SIZE, TEX_SIZE)
	end)
	if type(pix) ~= "table" then
		return
	end
	local function sample(x, y)
		local cell = pix[x] and pix[x][y]
		if type(cell) ~= "table" then
			cell = pix[y] and pix[y][x]
		end
		if type(cell) ~= "table" then
			return 0, 0, 0, 0
		end
		return channel8(cell[1]), channel8(cell[2]), channel8(cell[3]), channel8(cell[4] or 1)
	end
	local header = string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0)
		.. string.char(TEX_SIZE % 256, math.floor(TEX_SIZE / 256) % 256)
		.. string.char(TEX_SIZE % 256, math.floor(TEX_SIZE / 256) % 256)
		.. string.char(32, 8)
	local rows = {}
	for y = 1, TEX_SIZE do
		local row = {}
		for x = 1, TEX_SIZE do
			local r, g, b, a = sample(x, y)
			row[x] = string.char(b, g, r, a)
		end
		rows[y] = table.concat(row)
	end
	local f = io.open("mapeditor_splat.tga", "wb")
	if not f then
		return
	end
	f:write(header)
	f:write(table.concat(rows))
	f:close()
end

local function elementValue(el)
	if not el then
		return ""
	end
	local ok, value = pcall(function()
		return el.value
	end)
	if ok and type(value) == "string" then
		return value
	end
	if el.GetAttribute then
		return tostring(el:GetAttribute("value") or "")
	end
	return ""
end

local function readTypedName()
	local el = widgetState.document and widgetState.document:GetElementById("me-name")
	local raw = elementValue(el)
	if raw == "" then
		raw = widgetState.mapTitle or ""
	end
	raw = raw:gsub("[%c%z;/\\:*?\"<>|,]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if #raw > 48 then
		raw = raw:sub(1, 48):gsub("%s+$", "")
	end
	widgetState.mapTitle = raw
	return raw
end

local function nameSuffix()
	local name = readTypedName()
	if name == "" then
		return ""
	end
	return "," .. name
end

local function exportMap()
	saveSplatDump()
	send("export" .. nameSuffix())
end

local NEW_MAP_SIZES = { 8, 12, 16, 20, 24 }

local function newMapSizeLabel()
	local smu = widgetState.newMapSmu or 16
	return tostring(smu) .. "×" .. tostring(smu)
end

local function adjustNewMapSize(dir)
	local cur = widgetState.newMapSmu or 16
	local idx = 3
	for i = 1, #NEW_MAP_SIZES do
		if NEW_MAP_SIZES[i] == cur then
			idx = i
			break
		end
	end
	idx = idx + dir
	if idx < 1 then
		idx = 1
	elseif idx > #NEW_MAP_SIZES then
		idx = #NEW_MAP_SIZES
	end
	widgetState.newMapSmu = NEW_MAP_SIZES[idx]
	if widgetState.dmHandle then
		widgetState.dmHandle.newSizeValue = newMapSizeLabel()
	end
end

local function createNewMap()
	send("newmap," .. tostring(widgetState.newMapSmu or 16) .. nameSuffix())
end

local function groundPos()
	local mx, my = spGetMouseState()
	local _, coords = spTraceScreenRay(mx, my, true)
	if coords then
		return coords[1], coords[3]
	end
end

local function mouseOnChrome()
	local ctx = widgetState.rmlContext
	return ctx and ctx.IsMouseInteracting and ctx:IsMouseInteracting()
end

local function hideGameplayHud()
	if widgetState.playtesting or widgetState.hudHidden or not widgetHandler.RemoveWidgetRaw then
		return
	end
	local known = widgetHandler.knownWidgets
	for i = 1, #HUD_TO_DISABLE do
		local name = HUD_TO_DISABLE[i]
		if known and known[name] and known[name].active then
			local w = widgetHandler:FindWidget(name)
			if w then
				widgetState.stashedHud[#widgetState.stashedHud + 1] = w
				widgetHandler:RemoveWidgetRaw(w)
			end
		end
	end
	widgetState.hudPasses = (widgetState.hudPasses or 0) + 1
	if widgetState.hudPasses >= 3 or (Spring.GetGameFrame() or 0) > 0 then
		widgetState.hudHidden = true
	end
end

local function showGameplayHud()
	if not widgetHandler.InsertWidgetRaw then
		return
	end
	for i = 1, #widgetState.stashedHud do
		local w = widgetState.stashedHud[i]
		if w then
			widgetHandler:InsertWidgetRaw(w)
		end
	end
	widgetState.stashedHud = {}
	widgetState.hudHidden = false
	widgetState.hudPasses = 0
end

local function setPlaytestChrome(playing)
	if not widgetState.document then
		return
	end
	local root = widgetState.document:GetElementById("me-root")
	if root then
		root:SetClass("is-playtest", playing)
	end
	local bar = widgetState.document:GetElementById("me-playtest")
	if bar then
		bar:SetClass("is-hidden", not playing)
	end
end

local function applyPlaytestMode(playing)
	if playing == widgetState.playtesting then
		return
	end
	widgetState.playtesting = playing
	setPlaytestChrome(playing)
	if playing then
		showGameplayHud()
	else
		widgetState.hudHidden = false
		widgetState.hudPasses = 0
		hideGameplayHud()
	end
end

local function setToolClass(tool)
	if not widgetState.document then
		return
	end
	for i = 1, #TOOLS do
		local el = widgetState.document:GetElementById("tool-" .. TOOLS[i])
		if el then
			el:SetClass("is-active", TOOLS[i] == tool)
		end
	end
end

local toolDisplayName

local function setDockTip(title, body)
	local dm = widgetState.dmHandle
	if not dm then
		return
	end
	dm.tipTitle = title
	dm.tipBody = body
end

local function applyToolTip(tool)
	if widgetState.hoverTip then
		return
	end
	setDockTip(
		toolDisplayName(tool),
		t(TOOL_TIP_KEYS[tool] or (tool .. "Tip"), TOOL_TIP_FALLBACK[tool] or "")
	)
end

local function setLayerVisible(layer)
	if not widgetState.document then
		return
	end
	local tab = LAYER_TAB[layer] or "sculpt"
	local tabs = { "sculpt", "paint", "place", "map" }
	for i = 1, #tabs do
		local panel = widgetState.document:GetElementById("panel-" .. tabs[i])
		if panel then
			panel:SetClass("is-hidden", tabs[i] ~= tab)
		end
		local btn = widgetState.document:GetElementById("tab-" .. tabs[i])
		if btn then
			btn:SetClass("is-active", tabs[i] == tab)
		end
	end
	local paintLayers = { "metal", "grass", "tex" }
	for i = 1, #paintLayers do
		local tools = widgetState.document:GetElementById("tools-" .. paintLayers[i])
		if tools then
			tools:SetClass("is-hidden", paintLayers[i] ~= layer)
		end
		local sub = widgetState.document:GetElementById("layer-" .. paintLayers[i])
		if sub then
			sub:SetClass("is-active", paintLayers[i] == layer)
		end
	end
	local hideBrush = layer == "assets" or layer == "starts"
	local strengthRow = widgetState.document:GetElementById("row-strength")
	local falloffRow = widgetState.document:GetElementById("row-falloff")
	local radiusRow = widgetState.document:GetElementById("row-radius")
	if strengthRow then
		strengthRow:SetClass("is-hidden", hideBrush)
	end
	if falloffRow then
		falloffRow:SetClass("is-hidden", hideBrush)
	end
	if radiusRow then
		radiusRow:SetClass("is-hidden", layer == "starts")
	end
	local featTab = widgetState.document:GetElementById("palette-features")
	local unitTab = widgetState.document:GetElementById("palette-units")
	if featTab then
		featTab:SetClass("is-active", widgetState.paletteKind == "features")
	end
	if unitTab then
		unitTab:SetClass("is-active", widgetState.paletteKind == "units")
	end
end

local function currentPalette()
	if widgetState.paletteKind == "units" then
		return widgetState.units
	end
	return widgetState.features
end

local function currentAsset()
	local list = currentPalette()
	return list[widgetState.paletteIndex]
end

local function assetLabel()
	local asset = currentAsset()
	if not asset then
		return "—"
	end
	return asset.label
end

local function buildPalettes()
	local features = {}
	local featureDefs = FeatureDefs
	if featureDefs then
		for defID, def in pairs(featureDefs) do
			if type(def) == "table" and def.name and not def.name:find(",", 1, true) then
				local cat = def.customParams and def.customParams.category
				local name = def.name
				local junk = cat == "corpses" or cat == "heaps"
					or name:find("_dead", 1, true)
					or name:find("_heap", 1, true)
					or name:find("wreck", 1, true)
				if not junk then
					features[#features + 1] = {
						name = name,
						defID = defID,
						label = def.tooltip or def.description or name,
					}
				end
			end
		end
		table.sort(features, function(a, b)
			return a.label < b.label
		end)
	end
	local units = {}
	local unitDefs = UnitDefs
	if unitDefs then
		for defID = 1, #unitDefs do
			local def = unitDefs[defID]
			if def and def.name and not def.name:find(",", 1, true) and def.isBuilding then
				local cp = def.customParams or {}
				local name = def.name
				local skip = cp.isscavenger or cp.iscommander
					or name:find("_scav", 1, true)
					or name:find("raptor", 1, true)
				if not skip then
					units[#units + 1] = {
						name = name,
						defID = defID,
						label = def.translatedHumanName or def.humanName or name,
					}
				end
			end
		end
		table.sort(units, function(a, b)
			return a.label < b.label
		end)
	end
	widgetState.features = features
	widgetState.units = units
	widgetState.paletteIndex = 1
end

local function clearUnitGhost()
	if widgetState.unitGhostId and WG and WG.StopDrawUnitShapeGL4 then
		WG.StopDrawUnitShapeGL4(widgetState.unitGhostId)
		widgetState.unitGhostId = nil
	end
end

local function placeAsset()
	local asset = currentAsset()
	local x, z = groundPos()
	if not asset or not x then
		return
	end
	if widgetState.paletteKind == "units" then
		send(string.format("placeunit,%s,%.1f,%.1f,%d", asset.name, x, z, widgetState.facing))
	else
		send(string.format("placefeat,%s,%.1f,%.1f,%d", asset.name, x, z, widgetState.facing * 16384))
	end
end

local function deleteAsset()
	local x, z = groundPos()
	if not x then
		return
	end
	send(string.format("delete,%.1f,%.1f,%.1f", x, z, widgetState.radius))
end

toolDisplayName = function(tool)
	if tool == "metal" then
		return t("metalPaint", "Paint metal")
	end
	if tool == "demetal" then
		return t("metalErase", "Erase metal")
	end
	if tool == "grass" then
		return t("grassGrow", "Grow grass")
	end
	if tool == "cut" then
		return t("grassCut", "Cut grass")
	end
	if tool == "smooth" then
		return t("smooth", "Smooth")
	end
	if tool == "ramp" then
		return t("ramp", "Ramp")
	end
	if tool == "place" then
		return t("placeLabel", "Place")
	end
	if tool == "delete" then
		return t("deleteLabel", "Delete")
	end
	if tool == "box" then
		return t("boxLabel", "Start box")
	end
	if tool == "start" then
		return t("startLabel", "Start point")
	end
	if tool == "erasebox" then
		return t("eraseBoxLabel", "Clear box")
	end
	if tool == "sun" then
		return t("sunLabel", "Sun")
	end
	if tool == "ambient" then
		return t("ambientLabel", "Ambient")
	end
	if tool == "fog" then
		return t("fogLabel", "Fog")
	end
	if tool == "water" then
		return t("waterLabel", "Water")
	end
	if tool == "splat1" then
		return t("splat1Label", "Splat 1")
	end
	if tool == "splat2" then
		return t("splat2Label", "Splat 2")
	end
	if tool == "splat3" then
		return t("splat3Label", "Splat 3")
	end
	if tool == "splat4" then
		return t("splat4Label", "Splat 4")
	end
	return t(tool, tool)
end

local function syncGrassVisual()
	local grass = WG and WG.grassgl4
	if grass and grass.syncFromEngine then
		grass.syncFromEngine()
	end
end

local function saveStatus()
	if (spGetGameRulesParam("mapEditorExport") or 0) > 0 then
		return t("exported", "Map saved")
	end
	if (spGetGameRulesParam("mapEditorDirty") or 0) > 0 then
		return t("unsaved", "Unsaved")
	end
	return t("saved", "Saved")
end

local function refreshModel()
	local dm = widgetState.dmHandle
	if not dm then
		return
	end
	dm.radiusValue = tostring(math.floor(widgetState.radius + 0.5))
	dm.strengthValue = tostring(math.floor(widgetState.strength + 0.5))
	dm.falloffValue = tostring(math.floor(widgetState.falloff * 100 + 0.5)) .. "%"
	dm.newSizeValue = newMapSizeLabel()
	dm.dirtyLabel = saveStatus()
	dm.rotateLabel = t("rotateLabel", "Rotate") .. " " .. tostring(widgetState.facing * 90) .. "°"
	dm.assetName = assetLabel()
	if not widgetState.hoverTip then
		applyToolTip(widgetState.tool)
	end
	if widgetState.playtesting then
		dm.hint = t("playtestHint", "F9 or Esc returns  ·  F7 save map")
		dm.statusLine = t("playLabel", "Playtest") .. "  ·  " .. saveStatus()
		return
	end
	local layerName = t(widgetState.layer .. "Layer", widgetState.layer)
	dm.sectionLabel = string.upper(layerName)
	if widgetState.layer == "assets" then
		dm.hint = t("rotateHint", "Rotate or R  ·  [ ] next asset  ·  RMB delete")
		dm.statusLine = string.format(
			"%s  ·  %s  ·  %s  ·  face %d  ·  %s",
			layerName,
			toolDisplayName(widgetState.tool),
			assetLabel(),
			widgetState.facing,
			saveStatus()
		)
		return
	end
	if widgetState.layer == "starts" then
		dm.hint = t("startsHint", "Drag box  ·  click start  ·  Ctrl+Z undo")
		dm.statusLine = string.format(
			"%s  ·  %s  ·  %s",
			layerName,
			toolDisplayName(widgetState.tool),
			saveStatus()
		)
		return
	end
	if widgetState.layer == "light" then
		local L = widgetState.light
		local tool = widgetState.tool
		if tool == "sun" then
			dm.radiusLabel = t("azimuthLabel", "Azimuth")
			dm.strengthLabel = t("altitudeLabel", "Altitude")
			dm.falloffLabel = t("shadowLabel", "Shadow")
			dm.radiusValue = tostring(math.floor(L.az + 0.5)) .. "°"
			dm.strengthValue = tostring(math.floor(L.alt + 0.5)) .. "°"
			dm.falloffValue = tostring(math.floor(L.shadow * 100 + 0.5)) .. "%"
		elseif tool == "ambient" then
			dm.radiusLabel = t("ambientLabel", "Ambient")
			dm.strengthLabel = t("diffuseLabel", "Diffuse")
			dm.falloffLabel = t("shadowLabel", "Shadow")
			dm.radiusValue = string.format("%.2f", (L.ar + L.ag + L.ab) / 3)
			dm.strengthValue = string.format("%.2f", (L.dr + L.dg + L.db) / 3)
			dm.falloffValue = tostring(math.floor(L.shadow * 100 + 0.5)) .. "%"
		elseif tool == "fog" then
			dm.radiusLabel = t("fogStartLabel", "Fog start")
			dm.strengthLabel = t("fogEndLabel", "Fog end")
			dm.falloffLabel = t("shadowLabel", "Shadow")
			dm.radiusValue = string.format("%.2f", L.fogS)
			dm.strengthValue = string.format("%.2f", L.fogE)
			dm.falloffValue = tostring(math.floor(L.shadow * 100 + 0.5)) .. "%"
		else
			dm.radiusLabel = t("waterAlphaLabel", "Alpha")
			dm.strengthLabel = t("waterAmbLabel", "Light")
			dm.falloffLabel = t("shadowLabel", "Shadow")
			dm.radiusValue = string.format("%.2f", L.water)
			dm.strengthValue = string.format("%.2f", (L.ar + L.ag + L.ab) / 3)
			dm.falloffValue = tostring(math.floor(L.shadow * 100 + 0.5)) .. "%"
		end
		dm.hint = t("lightHint", "Click ground to aim sun  ·  [ ] nudge  ·  Ctrl+Z undo")
		local desc = Game.mapDescription or ""
		dm.statusLine = string.format(
			"%s  ·  %s  ·  %s  ·  %s",
			layerName,
			toolDisplayName(tool),
			desc ~= "" and desc or (Game.mapName or ""),
			saveStatus()
		)
		return
	end
	if widgetState.layer == "tex" then
		dm.radiusLabel = t("radius", "Radius")
		dm.strengthLabel = t("strength", "Strength")
		dm.falloffLabel = t("falloff", "Falloff")
		dm.hint = t("texHint", "LMB paint splat  ·  RMB erase  ·  Ctrl+Z undo")
		dm.statusLine = string.format(
			"%s  ·  %s  ·  r %d  ·  s %d  ·  %s",
			layerName,
			toolDisplayName(widgetState.tool),
			math.floor(widgetState.radius + 0.5),
			math.floor(widgetState.strength + 0.5),
			saveStatus()
		)
		return
	end
	dm.radiusLabel = t("radius", "Radius")
	dm.strengthLabel = t("strength", "Strength")
	dm.falloffLabel = t("falloff", "Falloff")
	if widgetState.tool == "ramp" then
		dm.hint = t("rampHint", "Drag start to end  ·  radius is width  ·  Ctrl+Z undo")
	elseif widgetState.tool == "smooth" then
		dm.hint = t("smoothHint", "Hold to blur  ·  radius sets size  ·  not a plateau")
	else
		dm.hint = t("hint", "[ ] radius  ·  RMB erase  ·  Shift full  ·  Ctrl+Z undo  ·  F7 save map")
	end
	dm.statusLine = string.format(
		"%s  ·  %s  ·  r %d  ·  s %d  ·  %s",
		layerName,
		toolDisplayName(widgetState.tool),
		math.floor(widgetState.radius + 0.5),
		math.floor(widgetState.strength + 0.5),
		saveStatus()
	)
end

local function setTool(tool)
	widgetState.tool = tool
	if tool ~= "ramp" then
		widgetState.rampStart = nil
	end
	if tool == "metal" or tool == "demetal" then
		widgetState.layer = "metal"
	elseif tool == "grass" or tool == "cut" then
		widgetState.layer = "grass"
	elseif tool == "place" or tool == "delete" then
		widgetState.layer = "assets"
	elseif tool == "box" or tool == "start" or tool == "erasebox" then
		widgetState.layer = "starts"
	elseif tool == "sun" or tool == "ambient" or tool == "fog" or tool == "water" then
		widgetState.layer = "light"
	elseif SPLAT_CH[tool] then
		widgetState.layer = "tex"
	else
		widgetState.layer = "height"
	end
	if widgetState.layer == "metal" or widgetState.layer == "grass" or widgetState.layer == "tex" then
		widgetState.lastPaintLayer = widgetState.layer
	elseif widgetState.layer == "starts" or widgetState.layer == "light" then
		widgetState.lastMapLayer = widgetState.layer
	end
	setLayerVisible(widgetState.layer)
	setToolClass(tool)
	refreshModel()
end

local function setLayer(layer)
	widgetState.layer = layer
	local tools = LAYER_TOOLS[layer]
	local keep = false
	for i = 1, #tools do
		if tools[i] == widgetState.tool then
			keep = true
			break
		end
	end
	if not keep then
		widgetState.tool = LAYER_DEFAULT[layer]
		widgetState.rampStart = nil
	end
	if layer == "metal" or layer == "grass" or layer == "tex" then
		widgetState.lastPaintLayer = layer
	elseif layer == "starts" or layer == "light" then
		widgetState.lastMapLayer = layer
	end
	if layer ~= "assets" then
		clearUnitGhost()
	end
	if layer ~= "starts" then
		widgetState.boxDrag = nil
	end
	if layer ~= "height" then
		widgetState.rampStart = nil
	end
	setLayerVisible(layer)
	setToolClass(widgetState.tool)
	refreshModel()
end

local function setTab(tab)
	if tab == "sculpt" then
		setLayer("height")
		return
	end
	if tab == "paint" then
		if widgetState.layer ~= "metal" and widgetState.layer ~= "grass" and widgetState.layer ~= "tex" then
			setLayer(widgetState.lastPaintLayer or "metal")
		end
		return
	end
	if tab == "place" then
		setLayer("assets")
		return
	end
	if widgetState.layer ~= "starts" and widgetState.layer ~= "light" then
		setLayer(widgetState.lastMapLayer or "starts")
	end
end

local function setPaletteKind(kind)
	widgetState.paletteKind = kind
	widgetState.paletteIndex = 1
	setLayerVisible(widgetState.layer)
	refreshModel()
end

local function cycleAsset(delta)
	local list = currentPalette()
	if #list == 0 then
		return
	end
	local index = widgetState.paletteIndex + delta
	if index < 1 then
		index = #list
	elseif index > #list then
		index = 1
	end
	widgetState.paletteIndex = index
	refreshModel()
end

local function rotateFacing()
	widgetState.facing = (widgetState.facing + 1) % 4
	refreshModel()
end

local function clamp(value, lo, hi)
	if value < lo then
		return lo
	end
	if value > hi then
		return hi
	end
	return value
end

local function deleteTexList(list)
	for i = 1, #list do
		if list[i] then
			gl.DeleteTexture(list[i])
		end
	end
end

local function makeSplatTex()
	return gl.CreateTexture(TEX_SIZE, TEX_SIZE, {
		fbo = true,
		min_filter = GL.LINEAR,
		mag_filter = GL.LINEAR,
		wrap_s = GL.CLAMP_TO_EDGE,
		wrap_t = GL.CLAMP_TO_EDGE,
	})
end

local function blitTex(src, dst)
	if not src or not dst or not gl.RenderToTexture then
		return
	end
	gl.RenderToTexture(dst, function()
		gl.Blending(false)
		gl.Color(1, 1, 1, 1)
		gl.Texture(src)
		gl.TexRect(-1, -1, 1, 1)
		gl.Texture(false)
		gl.Blending(true)
	end)
end

local function ensureSplatTex()
	if widgetState.paintTex then
		return true
	end
	if not gl.CreateTexture then
		return false
	end
	widgetState.paintTex = makeSplatTex()
	if not widgetState.paintTex then
		return false
	end
	gl.RenderToTexture(widgetState.paintTex, function()
		gl.Clear(GL.COLOR_BUFFER_BIT, 0.22, 0.22, 0.22, 0.22)
		gl.Texture("$ssmf_splat_distr")
		gl.TexRect(-1, -1, 1, 1)
		gl.Texture(false)
	end)
	Spring.SetMapShadingTexture("$ssmf_splat_distr", widgetState.paintTex)
	pcall(Spring.SetMapRenderingParams, { splatTexMults = { 1, 1, 1, 1 } })
	return true
end

local function snapshotSplat()
	if not ensureSplatTex() then
		return
	end
	local copy = makeSplatTex()
	if not copy then
		return
	end
	blitTex(widgetState.paintTex, copy)
	widgetState.texUndo[#widgetState.texUndo + 1] = copy
	if #widgetState.texUndo > 8 then
		gl.DeleteTexture(widgetState.texUndo[1])
		table.remove(widgetState.texUndo, 1)
	end
	deleteTexList(widgetState.texRedo)
	widgetState.texRedo = {}
end

local function restoreSplat(from, into)
	if #from == 0 or not widgetState.paintTex then
		return
	end
	local snap = from[#from]
	from[#from] = nil
	local current = makeSplatTex()
	if current then
		blitTex(widgetState.paintTex, current)
		into[#into + 1] = current
	end
	blitTex(snap, widgetState.paintTex)
	gl.DeleteTexture(snap)
	Spring.SetMapShadingTexture("$ssmf_splat_distr", widgetState.paintTex)
end

local function queueSplat(x, z, erase)
	widgetState.texQueue[#widgetState.texQueue + 1] = {
		x = x,
		z = z,
		erase = erase,
		ch = SPLAT_CH[widgetState.tool] or 1,
		radius = widgetState.radius,
		strength = widgetState.strength,
		falloff = widgetState.falloff,
	}
end

local function flushSplatQueue()
	local queue = widgetState.texQueue
	if #queue == 0 or not ensureSplatTex() or not gl.RenderToTexture then
		widgetState.texQueue = {}
		return
	end
	widgetState.texQueue = {}
	local mapX = Game.mapSizeX or 1
	local mapZ = Game.mapSizeZ or 1
	gl.RenderToTexture(widgetState.paintTex, function()
		gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
		for i = 1, #queue do
			local dab = queue[i]
			local nx = (dab.x / mapX) * 2 - 1
			local ny = 1 - (dab.z / mapZ) * 2
			local ru = (dab.radius / mapX) * 2
			local ch = dab.ch
			if gl.ColorMask then
				gl.ColorMask(ch == 1, ch == 2, ch == 3, ch == 4)
			end
			local a = math.min(1, dab.strength / 40)
			if dab.erase then
				gl.Color(0, 0, 0, a)
			else
				gl.Color(1, 1, 1, a)
			end
			gl.BeginEnd(GL.TRIANGLE_FAN, function()
				gl.Vertex(nx, ny, 0)
				local steps = 20
				for s = 0, steps do
					local ang = (s / steps) * math.pi * 2
					gl.Vertex(nx + math.cos(ang) * ru, ny + math.sin(ang) * ru, 0)
				end
			end)
		end
		if gl.ColorMask then
			gl.ColorMask(true, true, true, true)
		end
		gl.Color(1, 1, 1, 1)
	end)
	Spring.SetMapShadingTexture("$ssmf_splat_distr", widgetState.paintTex)
end

local function sunFromAngles()
	local L = widgetState.light
	local alt = math.rad(L.alt)
	local az = math.rad(L.az)
	L.sx = math.cos(alt) * math.sin(az)
	L.sy = math.sin(alt)
	L.sz = math.cos(alt) * math.cos(az)
end

local function syncSunAngles()
	local L = widgetState.light
	L.az = math.deg(math.atan2(L.sx, L.sz))
	local y = L.sy
	if y < -1 then
		y = -1
	elseif y > 1 then
		y = 1
	end
	L.alt = math.deg(math.asin(y))
end

local function applyLighting()
	local L = widgetState.light
	Spring.SetSunDirection(L.sx, L.sy, L.sz)
	Spring.SetSunLighting({
		groundAmbientColor = { L.ar, L.ag, L.ab },
		groundDiffuseColor = { L.dr, L.dg, L.db },
		groundShadowDensity = L.shadow,
		modelShadowDensity = L.shadow,
	})
	Spring.SetAtmosphere({ fogStart = L.fogS, fogEnd = L.fogE })
	pcall(Spring.SetWaterParams, { surfaceAlpha = L.water })
end

local function sendLight()
	local L = widgetState.light
	send(string.format(
		"light,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
		L.sx, L.sy, L.sz, L.ar, L.ag, L.ab, L.dr, L.dg, L.db, L.shadow, L.fogS, L.fogE, L.water
	))
end

local function captureLight()
	local L = widgetState.light
	local sx, sy, sz = gl.GetSun("pos")
	if not sx then
		sx, sy, sz = gl.GetSun()
	end
	if sx then
		L.sx, L.sy, L.sz = sx, sy, sz
		syncSunAngles()
		widgetState.lightReady = true
	end
	local ar, ag, ab = gl.GetSun("ambient")
	if ar then
		L.ar, L.ag, L.ab = ar, ag, ab
	end
	local dr, dg, db = gl.GetSun("diffuse")
	if dr then
		L.dr, L.dg, L.db = dr, dg, db
	end
	local shadow = gl.GetSun("shadowDensity")
	if shadow then
		L.shadow = shadow
	end
	local fogS = gl.GetAtmosphere("fogStart")
	local fogE = gl.GetAtmosphere("fogEnd")
	if fogS then
		L.fogS = fogS
	end
	if fogE then
		L.fogE = fogE
	end
	if gl.GetWaterRendering then
		local water = gl.GetWaterRendering("surfaceAlpha")
		if water then
			L.water = water
		end
	end
end

local function readLightFromGadget()
	local sx = spGetGameRulesParam("mapEditorSunX")
	if not sx then
		return
	end
	local L = widgetState.light
	L.sx = sx
	L.sy = spGetGameRulesParam("mapEditorSunY") or L.sy
	L.sz = spGetGameRulesParam("mapEditorSunZ") or L.sz
	L.ar = spGetGameRulesParam("mapEditorAmbR") or L.ar
	L.ag = spGetGameRulesParam("mapEditorAmbG") or L.ag
	L.ab = spGetGameRulesParam("mapEditorAmbB") or L.ab
	L.dr = spGetGameRulesParam("mapEditorDifR") or L.dr
	L.dg = spGetGameRulesParam("mapEditorDifG") or L.dg
	L.db = spGetGameRulesParam("mapEditorDifB") or L.db
	L.shadow = spGetGameRulesParam("mapEditorShadow") or L.shadow
	L.fogS = spGetGameRulesParam("mapEditorFogS") or L.fogS
	L.fogE = spGetGameRulesParam("mapEditorFogE") or L.fogE
	L.water = spGetGameRulesParam("mapEditorWater") or L.water
	syncSunAngles()
	applyLighting()
end

local function scaleRgb(r, g, b, factor)
	local nr = r * factor
	local ng = g * factor
	local nb = b * factor
	if nr < 0 then nr = 0 elseif nr > 1.5 then nr = 1.5 end
	if ng < 0 then ng = 0 elseif ng > 1.5 then ng = 1.5 end
	if nb < 0 then nb = 0 elseif nb > 1.5 then nb = 1.5 end
	return nr, ng, nb
end

local function nudgeLight(which, dir)
	local L = widgetState.light
	local tool = widgetState.tool
	if tool == "sun" then
		if which == 1 then
			L.az = (L.az + dir * 8 + 360) % 360
			sunFromAngles()
		elseif which == 2 then
			L.alt = clamp(L.alt + dir * 4, 5, 85)
			sunFromAngles()
		else
			L.shadow = clamp(L.shadow + dir * 0.05, 0, 1)
		end
	elseif tool == "ambient" then
		if which == 2 then
			L.dr, L.dg, L.db = scaleRgb(L.dr, L.dg, L.db, 1 + dir * 0.05)
		elseif which == 3 then
			L.shadow = clamp(L.shadow + dir * 0.05, 0, 1)
		else
			L.ar, L.ag, L.ab = scaleRgb(L.ar, L.ag, L.ab, 1 + dir * 0.05)
		end
	elseif tool == "fog" then
		if which == 1 then
			L.fogS = clamp(L.fogS + dir * 0.05, 0, 1.95)
		elseif which == 2 then
			L.fogE = clamp(L.fogE + dir * 0.05, 0.05, 2)
		else
			L.shadow = clamp(L.shadow + dir * 0.05, 0, 1)
		end
		if L.fogS >= L.fogE then
			L.fogS = L.fogE - 0.01
		end
	else
		if which == 1 then
			L.water = clamp(L.water + dir * 0.05, 0, 1)
		elseif which == 2 then
			L.ar, L.ag, L.ab = scaleRgb(L.ar, L.ag, L.ab, 1 + dir * 0.05)
		else
			L.shadow = clamp(L.shadow + dir * 0.05, 0, 1)
		end
	end
	applyLighting()
	sendLight()
	refreshModel()
end

local function adjustRadius(delta)
	if widgetState.layer == "light" then
		nudgeLight(1, delta > 0 and 1 or -1)
		return
	end
	widgetState.radius = clamp(widgetState.radius + delta, MIN_RADIUS, MAX_RADIUS)
	refreshModel()
end

local function adjustStrength(delta)
	if widgetState.layer == "light" then
		nudgeLight(2, delta > 0 and 1 or -1)
		return
	end
	widgetState.strength = clamp(widgetState.strength + delta, MIN_STRENGTH, MAX_STRENGTH)
	refreshModel()
end

local function adjustFalloff(delta)
	if widgetState.layer == "light" then
		nudgeLight(3, delta > 0 and 1 or -1)
		return
	end
	widgetState.falloff = clamp(widgetState.falloff + delta, 0, 1)
	refreshModel()
end

local function paint(kind, toolOverride)
	local x, z = groundPos()
	if not x then
		return
	end
	widgetState.cursorX = x
	widgetState.cursorZ = z
	widgetState.hasCursor = true
	local _, _, _, shift = Spring.GetModKeyState()
	local tool = toolOverride or widgetState.tool
	if kind == "begin" then
		widgetState.strokeTool = tool
		if tool == "ramp" then
			widgetState.rampStart = { x, z }
		end
		send(string.format(
			"begin,%s,%.1f,%.1f,%.1f,%.1f,%.2f,%s",
			tool,
			x,
			z,
			widgetState.radius,
			widgetState.strength,
			widgetState.falloff,
			shift and "1" or "0"
		))
		widgetState.painting = true
		widgetState.lastPaint = os.clock()
	else
		send(string.format("paint,%.1f,%.1f", x, z))
		widgetState.lastPaint = os.clock()
	end
end

local function endPaint()
	if not widgetState.painting then
		return
	end
	send("end")
	widgetState.painting = false
	widgetState.rampStart = nil
end

local function bindClicks()
	local document = widgetState.document
	local function on(id, fn)
		local el = document:GetElementById(id)
		if el then
			el:AddEventListener("click", function(event)
				fn()
				event:StopPropagation()
			end, false)
		end
	end
	local function hover(id, titleKey, titleFb, bodyKey, bodyFb)
		local el = document:GetElementById(id)
		if not el then
			return
		end
		el:AddEventListener("mouseover", function()
			widgetState.hoverTip = id
			setDockTip(t(titleKey, titleFb), t(bodyKey, bodyFb))
		end, false)
		el:AddEventListener("mouseout", function()
			if widgetState.hoverTip == id then
				widgetState.hoverTip = nil
				applyToolTip(widgetState.tool)
			end
		end, false)
	end
	on("tab-sculpt", function() setTab("sculpt") end)
	on("tab-paint", function() setTab("paint") end)
	on("tab-place", function() setTab("place") end)
	on("tab-map", function() setTab("map") end)
	on("tool-raise", function() setTool("raise") end)
	on("tool-lower", function() setTool("lower") end)
	on("tool-flatten", function() setTool("flatten") end)
	on("tool-smooth", function() setTool("smooth") end)
	on("tool-ramp", function() setTool("ramp") end)
	on("tool-metal", function() setTool("metal") end)
	on("tool-demetal", function() setTool("demetal") end)
	on("tool-grass", function() setTool("grass") end)
	on("tool-cut", function() setTool("cut") end)
	on("tool-place", function() setTool("place") end)
	on("tool-delete", function() setTool("delete") end)
	on("layer-metal", function() setLayer("metal") end)
	on("layer-grass", function() setLayer("grass") end)
	on("palette-features", function() setPaletteKind("features") end)
	on("palette-units", function() setPaletteKind("units") end)
	on("asset-prev", function() cycleAsset(-1) end)
	on("asset-next", function() cycleAsset(1) end)
	on("tool-rotate", function() rotateFacing() end)
	on("tool-box", function() setTool("box") end)
	on("tool-start", function() setTool("start") end)
	on("tool-erasebox", function() setTool("erasebox") end)
	on("tool-sun", function() setTool("sun") end)
	on("tool-ambient", function() setTool("ambient") end)
	on("tool-fog", function() setTool("fog") end)
	on("tool-water", function() setTool("water") end)
	on("layer-tex", function() setLayer("tex") end)
	on("tool-splat1", function() setTool("splat1") end)
	on("tool-splat2", function() setTool("splat2") end)
	on("tool-splat3", function() setTool("splat3") end)
	on("tool-splat4", function() setTool("splat4") end)
	on("radius-dec", function() adjustRadius(-RADIUS_STEP) end)
	on("radius-inc", function() adjustRadius(RADIUS_STEP) end)
	on("strength-dec", function() adjustStrength(-STRENGTH_STEP) end)
	on("strength-inc", function() adjustStrength(STRENGTH_STEP) end)
	on("falloff-dec", function() adjustFalloff(-FALLOFF_STEP) end)
	on("falloff-inc", function() adjustFalloff(FALLOFF_STEP) end)
	on("me-undo", function() send("undo") end)
	on("me-redo", function() send("redo") end)
	on("me-save", function() send("save") end)
	on("me-load", function() send("load") end)
	on("me-play", function() send("playtest") end)
	on("me-new", function() createNewMap() end)
	on("newsize-dec", function() adjustNewMapSize(-1) end)
	on("newsize-inc", function() adjustNewMapSize(1) end)
	on("me-export", function() exportMap() end)
	on("me-export-play", function() exportMap() end)
	on("me-edit", function() send("edit") end)
	hover("tab-sculpt", "tabSculpt", "Sculpt", "tabSculptTip", "Height tools. Raise, Lower, Flatten, Smooth, and Ramp only change terrain elevation.")
	hover("tab-paint", "tabPaint", "Paint", "tabPaintTip", "Surface paint. Metal, Grass, and Tex each keep one job.")
	hover("tab-place", "tabPlace", "Place", "tabPlaceTip", "Features and units. Place drops the selected asset. Delete removes nearby assets.")
	hover("tab-map", "tabMap", "Map", "tabMapTip", "Name, New Map, Save Map, Snapshot, Playtest, start boxes, and lighting.")
	hover("tool-raise", "raise", "Raise", "raiseTip", TOOL_TIP_FALLBACK.raise)
	hover("tool-lower", "lower", "Lower", "lowerTip", TOOL_TIP_FALLBACK.lower)
	hover("tool-flatten", "flatten", "Flatten", "flattenTip", TOOL_TIP_FALLBACK.flatten)
	hover("tool-smooth", "smooth", "Smooth", "smoothTip", TOOL_TIP_FALLBACK.smooth)
	hover("tool-ramp", "ramp", "Ramp", "rampTip", TOOL_TIP_FALLBACK.ramp)
	hover("tool-metal", "metalPaint", "Paint metal", "metalTip", TOOL_TIP_FALLBACK.metal)
	hover("tool-demetal", "metalErase", "Erase metal", "demetalTip", TOOL_TIP_FALLBACK.demetal)
	hover("tool-grass", "grassGrow", "Grow grass", "grassTip", TOOL_TIP_FALLBACK.grass)
	hover("tool-cut", "grassCut", "Cut grass", "cutTip", TOOL_TIP_FALLBACK.cut)
	hover("tool-place", "placeLabel", "Place", "placeTip", TOOL_TIP_FALLBACK.place)
	hover("tool-delete", "deleteLabel", "Delete", "deleteTip", TOOL_TIP_FALLBACK.delete)
	hover("tool-box", "boxLabel", "Start box", "boxTip", TOOL_TIP_FALLBACK.box)
	hover("tool-start", "startLabel", "Start point", "startTip", TOOL_TIP_FALLBACK.start)
	hover("tool-erasebox", "eraseBoxLabel", "Clear box", "eraseboxTip", TOOL_TIP_FALLBACK.erasebox)
	hover("tool-sun", "sunLabel", "Sun", "sunTip", TOOL_TIP_FALLBACK.sun)
	hover("tool-ambient", "ambientLabel", "Ambient", "ambientTip", TOOL_TIP_FALLBACK.ambient)
	hover("tool-fog", "fogLabel", "Fog", "fogTip", TOOL_TIP_FALLBACK.fog)
	hover("tool-water", "waterLabel", "Water", "waterTip", TOOL_TIP_FALLBACK.water)
	hover("tool-splat1", "splat1Label", "Splat 1", "splat1Tip", TOOL_TIP_FALLBACK.splat1)
	hover("tool-splat2", "splat2Label", "Splat 2", "splat2Tip", TOOL_TIP_FALLBACK.splat2)
	hover("tool-splat3", "splat3Label", "Splat 3", "splat3Tip", TOOL_TIP_FALLBACK.splat3)
	hover("tool-splat4", "splat4Label", "Splat 4", "splat4Tip", TOOL_TIP_FALLBACK.splat4)
	hover("layer-metal", "metalLayer", "Metal", "metalLayerTip", "Metal map brushes only. Paint adds extractor resources; Erase clears them.")
	hover("layer-grass", "grassLayer", "Grass", "grassLayerTip", "Engine grass brushes only. Grow plants tufts; Cut removes them.")
	hover("layer-tex", "texLayer", "Tex", "texLayerTip", "SSMF splat channels 1–4. Each tool paints one channel.")
	hover("palette-features", "featuresLabel", "Features", "featuresTip", "Palette of map features. Place uses the current entry. [ ] steps through the list.")
	hover("palette-units", "unitsLabel", "Units", "unitsTip", "Palette of buildable structures. Place spawns them as editor units.")
	hover("asset-prev", "featuresLabel", "Previous asset", "featuresTip", "Step backward through the current palette.")
	hover("asset-next", "unitsLabel", "Next asset", "featuresTip", "Step forward through the current palette.")
	hover("tool-rotate", "rotateLabel", "Rotate", "rotateTip", "Turns the next placed asset 90°. Keyboard R does the same.")
	hover("radius-dec", "radius", "Radius", "radiusTip", "Brush radius, or the first lighting row when Light is selected. [ ] also nudges this.")
	hover("radius-inc", "radius", "Radius", "radiusTip", "Brush radius, or the first lighting row when Light is selected. [ ] also nudges this.")
	hover("strength-dec", "strength", "Strength", "strengthTip", "Brush strength, or the second lighting row.")
	hover("strength-inc", "strength", "Strength", "strengthTip", "Brush strength, or the second lighting row.")
	hover("falloff-dec", "falloff", "Falloff", "falloffTip", "Rim softness. On Light this row is shadow density.")
	hover("falloff-inc", "falloff", "Falloff", "falloffTip", "Rim softness. On Light this row is shadow density.")
	hover("me-undo", "undo", "Undo", "undoTip", "Reverts the last editor stroke or action. Ctrl+Z.")
	hover("me-redo", "redo", "Redo", "redoTip", "Re-applies an undone action. Ctrl+Y.")
	hover("me-save", "saveLabel", "Snapshot", "saveTip", "Session Snapshot (F5). Does not write a playable map file — use Save Map (F7).")
	hover("me-load", "loadLabel", "Restore", "loadTip", "Restore (F6) the last Snapshot onto this map.")
	hover("me-play", "playLabel", "Playtest", "playTip", "Playtest (F8) restores the game HUD. Esc or F9 returns.")
	hover("me-new", "newLabel", "New Map", "newTip", "Builds a blank map at the chosen Size, then reloads the editor onto it. Ctrl+N.")
	hover("me-export", "exportLabel", "Save Map", "exportTip", "Save Map (F7). Writes the live session into maps/*.sdd using the Name field when set.")
	hover("me-export-play", "exportLabel", "Save Map", "exportTip", "Save Map (F7). Writes the live session into maps/*.sdd using the Name field when set.")
	hover("me-edit", "editLabel", "Return to editor", "editTip", "Leave playtest and bring the editor chrome back.")
	hover("newsize-dec", "newSizeLabel", "Size", "newSizeTip", "Square map size in Spring map units for New Map only (8–24).")
	hover("newsize-inc", "newSizeLabel", "Size", "newSizeTip", "Square map size in Spring map units for New Map only (8–24).")
	hover("me-name", "nameLabel", "Name", "nameTip", "Typed map name for New Map and Save Map.")
	local nameEl = document:GetElementById("me-name")
	if nameEl then
		nameEl:AddEventListener("focus", function()
			widgetState.naming = true
		end, false)
		nameEl:AddEventListener("blur", function()
			widgetState.naming = false
			readTypedName()
		end, false)
		nameEl:AddEventListener("change", function()
			readTypedName()
		end, false)
	end
end

function widget:Initialize()
	initialModel.title = t("title", "Map Editor")
	initialModel.sectionLabel = t("terrain", "Terrain")
	initialModel.tabSculpt = t("tabSculpt", "Sculpt")
	initialModel.tabPaint = t("tabPaint", "Paint")
	initialModel.tabPlace = t("tabPlace", "Place")
	initialModel.tabMap = t("tabMap", "Map")
	initialModel.tipTitle = t("raise", "Raise")
	initialModel.tipBody = t("raiseTip", TOOL_TIP_FALLBACK.raise)
	initialModel.heightLayer = t("heightLayer", "Terrain")
	initialModel.metalLayer = t("metalLayer", "Metal")
	initialModel.grassLayer = t("grassLayer", "Grass")
	initialModel.raiseLabel = t("raise", "Raise")
	initialModel.lowerLabel = t("lower", "Lower")
	initialModel.flattenLabel = t("flatten", "Flatten")
	initialModel.smoothLabel = t("smooth", "Smooth")
	initialModel.rampLabel = t("ramp", "Ramp")
	initialModel.metalPaint = t("metalPaint", "Paint metal")
	initialModel.metalErase = t("metalErase", "Erase metal")
	initialModel.grassGrow = t("grassGrow", "Grow grass")
	initialModel.grassCut = t("grassCut", "Cut grass")
	initialModel.assetsLayer = t("assetsLayer", "Assets")
	initialModel.placeLabel = t("placeLabel", "Place")
	initialModel.deleteLabel = t("deleteLabel", "Delete")
	initialModel.featuresLabel = t("featuresLabel", "Features")
	initialModel.unitsLabel = t("unitsLabel", "Units")
	initialModel.rotateLabel = t("rotateLabel", "Rotate")
	initialModel.startsLayer = t("startsLayer", "Starts")
	initialModel.boxLabel = t("boxLabel", "Start box")
	initialModel.startLabel = t("startLabel", "Start point")
	initialModel.eraseBoxLabel = t("eraseBoxLabel", "Clear box")
	initialModel.lightLayer = t("lightLayer", "Light")
	initialModel.sunLabel = t("sunLabel", "Sun")
	initialModel.ambientLabel = t("ambientLabel", "Ambient")
	initialModel.fogLabel = t("fogLabel", "Fog")
	initialModel.waterLabel = t("waterLabel", "Water")
	initialModel.texLayer = t("texLayer", "Tex")
	initialModel.splat1Label = t("splat1Label", "Splat 1")
	initialModel.splat2Label = t("splat2Label", "Splat 2")
	initialModel.splat3Label = t("splat3Label", "Splat 3")
	initialModel.splat4Label = t("splat4Label", "Splat 4")
	initialModel.radiusLabel = t("radius", "Radius")
	initialModel.strengthLabel = t("strength", "Strength")
	initialModel.falloffLabel = t("falloff", "Falloff")
	initialModel.undoLabel = t("undo", "Undo")
	initialModel.redoLabel = t("redo", "Redo")
	initialModel.saveLabel = t("saveLabel", "Snapshot")
	initialModel.loadLabel = t("loadLabel", "Restore")
	initialModel.playLabel = t("playLabel", "Playtest")
	initialModel.editLabel = t("editLabel", "Return to editor")
	initialModel.exportLabel = t("exportLabel", "Save Map")
	initialModel.newLabel = t("newLabel", "New Map")
	initialModel.newSizeLabel = t("newSizeLabel", "Size")
	initialModel.nameLabel = t("nameLabel", "Name")
	initialModel.namePlaceholder = t("namePlaceholder", "Map name")
	initialModel.newSizeValue = newMapSizeLabel()
	initialModel.hint = t("hint", initialModel.hint)
	initialModel.mapName = Game.mapName or ""

	widgetState.rmlContext = RmlUi.GetContext("shared")
	if not widgetState.rmlContext then
		return false
	end

	local dm = widgetState.rmlContext:OpenDataModel(MODEL_NAME, initialModel, self)
	if not dm then
		return false
	end
	widgetState.dmHandle = dm

	local document = widgetState.rmlContext:LoadDocument(RML_PATH, self)
	if not document then
		widget:Shutdown()
		return false
	end
	widgetState.document = document
	document:Show()
	buildPalettes()
	bindClicks()
	setToolClass(widgetState.tool)
	setLayerVisible(widgetState.layer)
	local current = Game.mapName or ""
	if current:find("^Untitled") or current:find("%(edited%)$") then
		widgetState.mapTitle = current
	end
	local nameEl = document:GetElementById("me-name")
	if nameEl then
		pcall(function()
			nameEl.value = widgetState.mapTitle
		end)
		if nameEl.SetAttribute then
			nameEl:SetAttribute("value", widgetState.mapTitle)
			nameEl:SetAttribute("placeholder", t("namePlaceholder", "Map name"))
		end
	end
	captureLight()
	if widgetState.lightReady then
		sendLight()
	end
	refreshModel()
	hideGameplayHud()
end

function widget:GameStart()
	hideGameplayHud()
end

function widget:Shutdown()
	clearUnitGhost()
	if widgetState.paintTex then
		gl.DeleteTexture(widgetState.paintTex)
		widgetState.paintTex = nil
	end
	deleteTexList(widgetState.texUndo)
	deleteTexList(widgetState.texRedo)
	if widgetState.painting then
		send("end")
		widgetState.painting = false
		widgetState.rampStart = nil
	end
	if widgetState.rmlContext and widgetState.dmHandle then
		widgetState.rmlContext:RemoveDataModel(MODEL_NAME)
		widgetState.dmHandle = nil
	end
	if widgetState.document then
		widgetState.document:Close()
		widgetState.document = nil
	end
	widgetState.rmlContext = nil
end

function widget:Update()
	if not widgetState.reloading and (spGetGameRulesParam("mapEditorNeedReload") or 0) > 0 then
		widgetState.reloading = true
		local script
		local f = io and io.open("mapeditor_reload.txt", "r")
		if f then
			script = f:read("*a")
			f:close()
		end
		if (not script or script == "") and VFS and VFS.LoadFile then
			script = VFS.LoadFile("mapeditor_reload.txt", VFS.RAW)
		end
		if script and script ~= "" and Spring.Reload then
			Spring.Reload(script)
			return
		end
		widgetState.reloading = false
	end
	hideGameplayHud()
	local x, z = groundPos()
	if x then
		widgetState.cursorX = x
		widgetState.cursorZ = z
		widgetState.hasCursor = true
	else
		widgetState.hasCursor = false
	end
	if widgetState.texStroke then
		local leftDown = select(3, spGetMouseState())
		local rightDown = select(5, spGetMouseState())
		if not leftDown and not rightDown then
			widgetState.texStroke = false
		elseif widgetState.hasCursor then
			queueSplat(widgetState.cursorX, widgetState.cursorZ, widgetState.texErase)
		end
	end
	if widgetState.painting then
		local leftDown = select(3, spGetMouseState())
		local rightDown = select(5, spGetMouseState())
		if not leftDown and not rightDown then
			endPaint()
		elseif os.clock() - widgetState.lastPaint >= PAINT_INTERVAL then
			paint("paint")
		end
	end
	local grassRev = spGetGameRulesParam("mapEditorGrassRev") or 0
	if grassRev ~= widgetState.grassRev then
		widgetState.grassRev = grassRev
		syncGrassVisual()
	end
	local lightRev = spGetGameRulesParam("mapEditorLightRev") or 0
	if lightRev ~= widgetState.lightRev then
		widgetState.lightRev = lightRev
		if lightRev > 0 then
			readLightFromGadget()
		end
	end
	applyPlaytestMode((spGetGameRulesParam("mapEditorPlaytest") or 0) > 0)
	local texRev = spGetGameRulesParam("mapEditorTexRev") or 0
	if texRev ~= widgetState.texRev then
		widgetState.texRev = texRev
		local op = spGetGameRulesParam("mapEditorTexOp") or 0
		if op == 1 then
			restoreSplat(widgetState.texUndo, widgetState.texRedo)
		elseif op == 2 then
			restoreSplat(widgetState.texRedo, widgetState.texUndo)
		end
	end
	refreshModel()
end

function widget:MousePress(_, _, button)
	if mouseOnChrome() then
		return false
	end
	if widgetState.playtesting then
		return false
	end
	if widgetState.layer == "tex" then
		if button == 1 or button == 3 then
			local x, z = groundPos()
			if x then
				snapshotSplat()
				send("tex")
				widgetState.texStroke = true
				widgetState.texErase = button == 3
				queueSplat(x, z, widgetState.texErase)
			end
			return true
		end
		return false
	end
	if widgetState.layer == "light" then
		if button == 1 and widgetState.tool == "sun" then
			local x, z = groundPos()
			if x then
				local cx = (Game.mapSizeX or 0) * 0.5
				local cz = (Game.mapSizeZ or 0) * 0.5
				widgetState.light.az = math.deg(math.atan2(x - cx, z - cz))
				sunFromAngles()
				applyLighting()
				sendLight()
				refreshModel()
			end
			return true
		end
		return false
	end
	if widgetState.layer == "starts" then
		if button == 1 then
			if widgetState.tool == "erasebox" then
				send("clearstart,0")
				return true
			end
			if widgetState.tool == "start" then
				local x, z = groundPos()
				if x then
					send(string.format("startpoint,%.1f,%.1f,0", x, z))
				end
				return true
			end
			local x, z = groundPos()
			if x then
				widgetState.boxDrag = { x, z }
			end
			return true
		end
		if button == 3 then
			send("clearstart,0")
			return true
		end
		return false
	end
	if widgetState.layer == "assets" then
		if button == 1 then
			if widgetState.tool == "delete" then
				deleteAsset()
			else
				placeAsset()
			end
			return true
		end
		if button == 3 then
			deleteAsset()
			return true
		end
		return false
	end
	if button == 1 then
		paint("begin")
		return true
	end
	if button == 3 and widgetState.layer ~= "height" then
		paint("begin", widgetState.layer == "metal" and "demetal" or "cut")
		return true
	end
	return false
end

function widget:MouseRelease(_, _, button)
	if widgetState.texStroke and (button == 1 or button == 3) then
		widgetState.texStroke = false
		return true
	end
	if widgetState.boxDrag and button == 1 then
		local x, z = groundPos()
		local startX = widgetState.boxDrag[1]
		local startZ = widgetState.boxDrag[2]
		widgetState.boxDrag = nil
		if x then
			local dx = x - startX
			local dz = z - startZ
			if (dx * dx + dz * dz) > 400 then
				send(string.format("startbox,%.1f,%.1f,%.1f,%.1f,0", startX, startZ, x, z))
			end
		end
		return true
	end
	if widgetState.painting and (button == 1 or button == 3) then
		endPaint()
		return true
	end
end

function widget:KeyPress(key, mods)
	mods = mods or {}
	if widgetState.naming then
		if key == KEYSYMS.F5 or key == KEYSYMS.F6 or key == KEYSYMS.F7 or key == KEYSYMS.F8 or key == KEYSYMS.ESCAPE then
			widgetState.naming = false
			readTypedName()
		else
			return false
		end
	end
	local nameEl = widgetState.document and widgetState.document:GetElementById("me-name")
	if nameEl and nameEl.IsPseudoClassSet and nameEl:IsPseudoClassSet("focus") then
		if key ~= KEYSYMS.F5 and key ~= KEYSYMS.F6 and key ~= KEYSYMS.F7 and key ~= KEYSYMS.F8 and key ~= KEYSYMS.ESCAPE then
			widgetState.naming = true
			return false
		end
		readTypedName()
	end
	if widgetState.playtesting then
		if key == KEYSYMS.ESCAPE or key == KEYSYMS.F9 then
			send("edit")
			return true
		end
		if key == KEYSYMS.F5 then
			send("save")
			return true
		end
		if key == KEYSYMS.F6 then
			send("load")
			return true
		end
		if key == KEYSYMS.F7 then
			exportMap()
			return true
		end
		return false
	end
	if mouseOnChrome() and not mods.ctrl then
		return false
	end
	if mods.ctrl and key == KEYSYMS.Z then
		send("undo")
		return true
	end
	if mods.ctrl and key == KEYSYMS.Y then
		send("redo")
		return true
	end
	if key == KEYSYMS.LEFTBRACKET then
		if widgetState.layer == "assets" then
			cycleAsset(-1)
		else
			adjustRadius(-RADIUS_STEP)
		end
		return true
	end
	if key == KEYSYMS.RIGHTBRACKET then
		if widgetState.layer == "assets" then
			cycleAsset(1)
		else
			adjustRadius(RADIUS_STEP)
		end
		return true
	end
	if key == KEYSYMS.R then
		if widgetState.layer == "assets" then
			rotateFacing()
			return true
		end
	end
	if key == KEYSYMS.N_1 then
		setTool(LAYER_TOOLS[widgetState.layer][1])
		return true
	end
	if key == KEYSYMS.N_2 then
		local tools = LAYER_TOOLS[widgetState.layer]
		setTool(tools[2] or tools[1])
		return true
	end
	if key == KEYSYMS.N_3 then
		local tools = LAYER_TOOLS[widgetState.layer]
		if tools[3] then
			setTool(tools[3])
			return true
		end
	end
	if key == KEYSYMS.N_4 then
		local tools = LAYER_TOOLS[widgetState.layer]
		if tools[4] then
			setTool(tools[4])
			return true
		end
	end
	if key == KEYSYMS.N_5 then
		setLayer("height")
		return true
	end
	if key == KEYSYMS.N_6 then
		setLayer("metal")
		return true
	end
	if key == KEYSYMS.N_7 then
		setLayer("grass")
		return true
	end
	if key == KEYSYMS.N_8 then
		setLayer("assets")
		return true
	end
	if key == KEYSYMS.N_9 then
		setLayer("starts")
		return true
	end
	if key == KEYSYMS.N_0 then
		setLayer("light")
		return true
	end
	if key == KEYSYMS.T then
		setLayer("tex")
		return true
	end
	if mods.ctrl and key == KEYSYMS.N then
		createNewMap()
		return true
	end
	if key == KEYSYMS.F5 then
		send("save")
		return true
	end
	if key == KEYSYMS.F6 then
		send("load")
		return true
	end
	if key == KEYSYMS.F7 then
		exportMap()
		return true
	end
	if key == KEYSYMS.F8 then
		send("playtest")
		return true
	end
end

function widget:TextInput()
	if widgetState.naming then
		return false
	end
end

local function drawGroundRect(xmin, zmin, xmax, zmax)
	local function edge(x1, z1, x2, z2)
		local steps = 14
		for i = 0, steps do
			local t = i / steps
			local x = x1 + (x2 - x1) * t
			local z = z1 + (z2 - z1) * t
			gl.Vertex(x, spGetGroundHeight(x, z), z)
		end
	end
	gl.BeginEnd(GL.LINE_STRIP, function()
		edge(xmin, zmin, xmax, zmin)
		edge(xmax, zmin, xmax, zmax)
		edge(xmax, zmax, xmin, zmax)
		edge(xmin, zmax, xmin, zmin)
	end)
end

function widget:DrawWorld()
	flushSplatQueue()
	if widgetState.layer == "tex" then
		clearUnitGhost()
		if widgetState.hasCursor then
			local x = widgetState.cursorX
			local z = widgetState.cursorZ
			local y = spGetGroundHeight(x, z)
			local color = TOOL_COLORS[widgetState.tool] or TOOL_COLORS.splat1
			glDepthTest(false)
			glLineWidth(2.5)
			glColor(color[1], color[2], color[3], 0.95)
			glDrawGroundCircle(x, y, z, widgetState.radius, 48)
			glLineWidth(1)
			glColor(1, 1, 1, 1)
			glDepthTest(true)
		end
		return
	end
	if widgetState.layer == "light" then
		clearUnitGhost()
		local L = widgetState.light
		local mx = (Game.mapSizeX or 0) * 0.5
		local mz = (Game.mapSizeZ or 0) * 0.5
		local my = spGetGroundHeight(mx, mz)
		local dist = math.min(Game.mapSizeX or 1000, Game.mapSizeZ or 1000) * 0.35
		glDepthTest(false)
		glLineWidth(3)
		glColor(1.0, 0.85, 0.35, 0.95)
		glDrawGroundCircle(mx, my, mz, 90, 32)
		gl.BeginEnd(GL.LINES, function()
			gl.Vertex(mx - L.sx * dist, my + math.abs(L.sy) * dist + 120, mz - L.sz * dist)
			gl.Vertex(mx, my + 24, mz)
		end)
		glLineWidth(1)
		glColor(1, 1, 1, 1)
		glDepthTest(true)
		return
	end
	if widgetState.layer == "starts" then
		clearUnitGhost()
		glDepthTest(false)
		glLineWidth(3)
		local xmin, zmin, xmax, zmax = Spring.GetAllyTeamStartBox(0)
		local mapX = Game.mapSizeX or 0
		local mapZ = Game.mapSizeZ or 0
		local wholeMap = xmin and xmin <= 1 and zmin <= 1 and xmax >= (mapX - 1) and zmax >= (mapZ - 1)
		if xmin and not wholeMap then
			glColor(0.35, 0.75, 1.0, 0.95)
			drawGroundRect(xmin, zmin, xmax, zmax)
		end
		if widgetState.boxDrag and widgetState.hasCursor then
			glColor(0.55, 0.9, 1.0, 1)
			drawGroundRect(
				widgetState.boxDrag[1],
				widgetState.boxDrag[2],
				widgetState.cursorX,
				widgetState.cursorZ
			)
		end
		local sx, sy, sz = Spring.GetTeamStartPosition(0)
		if sx ~= nil and sx >= 0 then
			local gy = spGetGroundHeight(sx, sz)
			glColor(1.0, 0.9, 0.35, 0.95)
			glDrawGroundCircle(sx, gy, sz, 48, 32)
			glDrawGroundCircle(sx, gy, sz, 16, 16)
		elseif widgetState.hasCursor and widgetState.tool == "start" then
			local color = TOOL_COLORS.start
			glColor(color[1], color[2], color[3], 0.9)
			glDrawGroundCircle(widgetState.cursorX, spGetGroundHeight(widgetState.cursorX, widgetState.cursorZ), widgetState.cursorZ, 28, 24)
		end
		glLineWidth(1)
		glColor(1, 1, 1, 1)
		glDepthTest(true)
		return
	end
	if widgetState.layer ~= "assets" or not widgetState.hasCursor then
		clearUnitGhost()
	end
	if not widgetState.hasCursor then
		return
	end
	local x = widgetState.cursorX
	local z = widgetState.cursorZ
	local y = spGetGroundHeight(x, z)
	local color = TOOL_COLORS[widgetState.tool]
	if widgetState.layer == "assets" then
		glDepthTest(false)
		glLineWidth(2.5)
		glColor(color[1], color[2], color[3], 0.95)
		local marker = widgetState.tool == "delete" and widgetState.radius or 28
		glDrawGroundCircle(x, y, z, marker, 48)
		if widgetState.tool == "place" then
			local asset = currentAsset()
			if asset then
				if widgetState.paletteKind == "units" then
					clearUnitGhost()
					if WG and WG.DrawUnitShapeGL4 then
						widgetState.unitGhostId = WG.DrawUnitShapeGL4(
							asset.defID,
							x,
							y,
							z,
							widgetState.facing * (math.pi / 2),
							0.45,
							Spring.GetMyTeamID(),
							nil,
							nil
						)
					end
				else
					clearUnitGhost()
					gl.PushMatrix()
					gl.Translate(x, y, z)
					gl.Rotate(widgetState.facing * 90, 0, 1, 0)
					glColor(1, 1, 1, 0.55)
					pcall(gl.FeatureShape, asset.defID, Spring.GetGaiaTeamID() or 0)
					gl.PopMatrix()
				end
			end
		else
			clearUnitGhost()
		end
		glLineWidth(1)
		glColor(1, 1, 1, 1)
		glDepthTest(true)
		return
	end
	glDepthTest(false)
	glLineWidth(2.5)
	glColor(color[1], color[2], color[3], 0.95)
	glDrawGroundCircle(x, y, z, widgetState.radius, 64)
	glColor(color[1], color[2], color[3], 0.4)
	glDrawGroundCircle(x, y, z, widgetState.radius * math.max(0.08, 1 - widgetState.falloff), 48)
	if widgetState.tool == "ramp" and widgetState.rampStart then
		local sx = widgetState.rampStart[1]
		local sz = widgetState.rampStart[2]
		local sy = spGetGroundHeight(sx, sz)
		glColor(color[1], color[2], color[3], 0.95)
		glDrawGroundCircle(sx, sy, sz, widgetState.radius, 48)
		glLineWidth(3)
		gl.BeginEnd(GL.LINE_STRIP, function()
			local steps = 24
			for i = 0, steps do
				local u = i / steps
				local px = sx + (x - sx) * u
				local pz = sz + (z - sz) * u
				gl.Vertex(px, spGetGroundHeight(px, pz) + 8, pz)
			end
		end)
	end
	if widgetState.layer == "metal" then
		local r = widgetState.radius
		for pz = z - r, z + r, METAL_SQUARE do
			for px = x - r, x + r, METAL_SQUARE do
				local dx = px - x
				local dz = pz - z
				if dx * dx + dz * dz <= r * r then
					local amount = spGetMetalAmount(math.floor(px / METAL_SQUARE), math.floor(pz / METAL_SQUARE)) or 0
					if amount > 1 then
						local gy = spGetGroundHeight(px, pz)
						glColor(1, 0.82, 0.2, 0.12 + 0.45 * (amount / 255))
						glDrawGroundCircle(px, gy, pz, METAL_SQUARE * 0.42, 10)
					end
				end
			end
		end
	elseif widgetState.layer == "grass" then
		local r = widgetState.radius
		for pz = z - r, z + r, GRASS_STEP do
			for px = x - r, x + r, GRASS_STEP do
				local dx = px - x
				local dz = pz - z
				if dx * dx + dz * dz <= r * r then
					local g = spGetGrass(px, pz) or 0
					if g > 0 then
						local gy = spGetGroundHeight(px, pz)
						glColor(0.3, 0.95, 0.35, 0.55)
						glDrawGroundCircle(px, gy, pz, GRASS_STEP * 0.28, 8)
					end
				end
			end
		end
	end
	glLineWidth(1)
	glColor(1, 1, 1, 1)
	glDepthTest(true)
end

function widget:RecvLuaMsg(message)
	local document = widgetState.document
	if not document then
		return
	end
	if message:sub(1, 19) == "LobbyOverlayActive0" then
		document:Show()
	elseif message:sub(1, 19) == "LobbyOverlayActive1" then
		document:Hide()
	end
end
