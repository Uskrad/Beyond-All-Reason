local gadget = gadget ---@type Gadget

local function mapEditorRequested()
	local opts = Spring.GetModOptions()
	local v = opts.map_editor
	local v2 = opts.mapeditor
	if v == true or v == 1 or v == "1" or v2 == true or v2 == 1 or v2 == "1" then
		return true
	end
	local ver = Game and Game.gameVersion or ""
	if string.find(string.upper(ver), "$VERSION", 1, true) then
		return true
	end
	return false
end

function gadget:GetInfo()
	return {
		name = "Map Editor",
		desc = "Synced in-game map editor (sculpt, assets, starts, lighting, splat, save, playtest)",
		author = "Uskrad Dragon",
		date = "2026-09",
		license = "GNU GPL, v2 or later",
		layer = -10000,
		enabled = true,
	}
end

local MSG_PREFIX = "$ME$"
local PREFIX_LEN = #MSG_PREFIX
local SQUARE = Game.squareSize
local METAL_SQUARE = Game.metalMapSquareSize or 16
local GRASS_STEP = 16
local MAX_UNDO = 48
local MAX_RADIUS = 1200
local MIN_RADIUS = 24
local MAX_METAL = 255

local KIND_HEIGHT = "height"
local KIND_METAL = "metal"
local KIND_GRASS = "grass"
local KIND_ASSET = "asset"
local KIND_START = "start"
local KIND_LIGHT = "light"
local KIND_TEX = "tex"

local function parseCommand(msg)
	local body = msg:sub(PREFIX_LEN + 1)
	local parts = {}
	for token in body:gmatch("[^,]+") do
		parts[#parts + 1] = token
	end
	return parts
end

local function toolKind(tool)
	if tool == "metal" or tool == "demetal" then
		return KIND_METAL
	end
	if tool == "grass" or tool == "cut" then
		return KIND_GRASS
	end
	return KIND_HEIGHT
end

if gadgetHandler:IsSyncedCode() then
	local undoStack = {}
	local redoStack = {}
	local stroke
	local lightState
	local session
	local playtesting = false
	local playtestUnits = {}
	local origMetal = {}
	local metalW = 0
	local metalH = 0
	local lastAuto = 0

	local function copyLight(state)
		if not state then
			return nil
		end
		return {
			sx = state.sx,
			sy = state.sy,
			sz = state.sz,
			ar = state.ar,
			ag = state.ag,
			ab = state.ab,
			dr = state.dr,
			dg = state.dg,
			db = state.db,
			shadow = state.shadow,
			fogS = state.fogS,
			fogE = state.fogE,
			water = state.water,
		}
	end

	local function publishLight(state)
		if not state then
			return
		end
		Spring.SetGameRulesParam("mapEditorSunX", state.sx)
		Spring.SetGameRulesParam("mapEditorSunY", state.sy)
		Spring.SetGameRulesParam("mapEditorSunZ", state.sz)
		Spring.SetGameRulesParam("mapEditorAmbR", state.ar)
		Spring.SetGameRulesParam("mapEditorAmbG", state.ag)
		Spring.SetGameRulesParam("mapEditorAmbB", state.ab)
		Spring.SetGameRulesParam("mapEditorDifR", state.dr)
		Spring.SetGameRulesParam("mapEditorDifG", state.dg)
		Spring.SetGameRulesParam("mapEditorDifB", state.db)
		Spring.SetGameRulesParam("mapEditorShadow", state.shadow)
		Spring.SetGameRulesParam("mapEditorFogS", state.fogS)
		Spring.SetGameRulesParam("mapEditorFogE", state.fogE)
		Spring.SetGameRulesParam("mapEditorWater", state.water)
		Spring.SetGameRulesParam("mapEditorLightRev", (Spring.GetGameRulesParam("mapEditorLightRev") or 0) + 1)
		SendToUnsynced(
			"mapEditorLight",
			state.sx,
			state.sy,
			state.sz,
			state.ar,
			state.ag,
			state.ab,
			state.dr,
			state.dg,
			state.db,
			state.shadow,
			state.fogS,
			state.fogE,
			state.water
		)
	end

	local function publishState()
		Spring.SetGameRulesParam("mapEditorDirty", (#undoStack > 0) and 1 or 0)
		Spring.SetGameRulesParam("mapEditorUndo", #undoStack)
		Spring.SetGameRulesParam("mapEditorRedo", #redoStack)
		Spring.SetGameRulesParam("mapEditorTool", stroke and 1 or 0)
		Spring.SetGameRulesParam("mapEditorGrassRev", (Spring.GetGameRulesParam("mapEditorGrassRev") or 0))
	end

	local function noteMapUnsaved()
		Spring.SetGameRulesParam("mapEditorExport", 0)
	end

	local function bumpGrassVisual()
		Spring.SetGameRulesParam("mapEditorGrassRev", (Spring.GetGameRulesParam("mapEditorGrassRev") or 0) + 1)
	end

	local function authorized(playerID)
		if mapEditorRequested() then
			return true
		end
		if Spring.Utilities and Spring.Utilities.IsMapEditor and Spring.Utilities.IsMapEditor() then
			return true
		end
		local _, _, spec = Spring.GetPlayerInfo(playerID, false)
		return not spec
	end

	local function cellKey(x, z)
		return x * 1048576 + z
	end

	local liveMirror = { h = false, v = false, radial = 0 }

	local function makeXforms(mh, mv, folds)
		folds = tonumber(folds) or 0
		if folds < 3 then
			folds = 0
		end
		local mapX = Game.mapSizeX or 0
		local mapZ = Game.mapSizeZ or 0
		local ox = mapX * 0.5
		local oz = mapZ * 0.5
		local flips = { { false, false } }
		if mh then
			local n = #flips
			for i = 1, n do
				flips[#flips + 1] = { true, flips[i][2] }
			end
		end
		if mv then
			local n = #flips
			for i = 1, n do
				flips[#flips + 1] = { flips[i][1], true }
			end
		end
		local ks = { 0 }
		if folds >= 3 then
			ks = {}
			for k = 0, folds - 1 do
				ks[#ks + 1] = k
			end
		end
		local xforms = {}
		for i = 1, #flips do
			local flipH = flips[i][1]
			local flipV = flips[i][2]
			for ki = 1, #ks do
				local k = ks[ki]
				xforms[#xforms + 1] = function(x, z)
					local px, pz = x, z
					local rot = 0
					if flipH then
						px = mapX - px
					end
					if flipV then
						pz = mapZ - pz
						rot = math.pi - rot
					end
					if k > 0 then
						local ang = (2 * math.pi / folds) * k
						local dx = px - ox
						local dz = pz - oz
						local c = math.cos(ang)
						local s = math.sin(ang)
						px = ox + dx * c - dz * s
						pz = oz + dx * s + dz * c
						rot = rot + ang
					end
					if px < 0 then
						px = 0
					elseif px > mapX then
						px = mapX
					end
					if pz < 0 then
						pz = 0
					elseif pz > mapZ then
						pz = mapZ
					end
					return px, pz, rot, flipH, flipV
				end
			end
		end
		return xforms
	end

	local function clampRadius(radius)
		if radius < MIN_RADIUS then
			return MIN_RADIUS
		end
		if radius > MAX_RADIUS then
			return MAX_RADIUS
		end
		return radius
	end

	local function applyHeights(xs, zs, hs)
		Spring.SetHeightMapFunc(function()
			for i = 1, #xs do
				Spring.SetHeightMap(xs[i], zs[i], hs[i])
			end
		end)
	end

	local function restoreFrame(xs, zs, values, kind)
		if kind == KIND_METAL then
			for i = 1, #xs do
				Spring.SetMetalAmount(xs[i], zs[i], values[i] or 0)
			end
		elseif kind == KIND_GRASS then
			for i = 1, #xs do
				if (values[i] or 0) > 0 then
					Spring.AddGrass(xs[i], zs[i])
				else
					Spring.RemoveGrass(xs[i], zs[i])
				end
			end
			bumpGrassVisual()
		else
			applyHeights(xs, zs, values)
		end
	end

	local function snapshotValues(xs, zs, kind)
		local values = {}
		if kind == KIND_METAL then
			for i = 1, #xs do
				values[i] = Spring.GetMetalAmount(xs[i], zs[i]) or 0
			end
		elseif kind == KIND_GRASS then
			for i = 1, #xs do
				values[i] = Spring.GetGrass(xs[i], zs[i]) or 0
			end
		else
			for i = 1, #xs do
				values[i] = Spring.GetGroundHeight(xs[i], zs[i])
			end
		end
		return values
	end

	local function strokeMix()
		if stroke.maxMode then
			return 1
		end
		return math.min(1, stroke.strength / 12)
	end

	local function brushWeight(dist, radius, falloff, maxMode)
		if maxMode or falloff <= 0.01 then
			return 1
		end
		local t = dist / radius
		if t >= 1 then
			return 0
		end
		local inner = 1 - falloff
		if t <= inner then
			return 1
		end
		local u = 1 - ((t - inner) / math.max(0.001, falloff))
		return u * u * (3 - 2 * u)
	end

	local function remember(x, z, old)
		local key = cellKey(x, z)
		if not stroke.seen[key] then
			stroke.seen[key] = true
			local n = #stroke.xs + 1
			stroke.xs[n] = x
			stroke.zs[n] = z
			stroke.old[n] = old
		end
	end

	local function applyHeightBrush(cx, cz)
		local radius = stroke.radius
		local x0 = math.floor((cx - radius) / SQUARE) * SQUARE
		local z0 = math.floor((cz - radius) / SQUARE) * SQUARE
		local x1 = math.ceil((cx + radius) / SQUARE) * SQUARE
		local z1 = math.ceil((cz + radius) / SQUARE) * SQUARE
		local xs, zs, hs = {}, {}, {}
		local tool = stroke.tool

		for z = z0, z1, SQUARE do
			for x = x0, x1, SQUARE do
				local dx = x - cx
				local dz = z - cz
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist <= radius then
					local weight = brushWeight(dist, radius, stroke.falloff, stroke.maxMode)
					if weight > 0 then
						local old = Spring.GetGroundHeight(x, z)
						local newH = old
						local mix = strokeMix()
						if tool == "raise" then
							newH = old + stroke.strength * weight
						elseif tool == "lower" then
							newH = old - stroke.strength * weight
						elseif tool == "flatten" then
							newH = old + (stroke.centerH - old) * weight * mix
						else
							weight = 0
						end
						if weight > 0 then
							remember(x, z, old)
							local n = #xs + 1
							xs[n] = x
							zs[n] = z
							hs[n] = newH
						end
					end
				end
			end
		end

		if #xs > 0 then
			applyHeights(xs, zs, hs)
		end
	end

	local function applyMetalBrush(cx, cz)
		local radius = stroke.radius
		local step = METAL_SQUARE
		local x0 = math.floor((cx - radius) / step)
		local z0 = math.floor((cz - radius) / step)
		local x1 = math.ceil((cx + radius) / step)
		local z1 = math.ceil((cz + radius) / step)
		local erase = stroke.tool == "demetal"
		local peak = stroke.maxMode and MAX_METAL or ((stroke.strength / 80) * MAX_METAL)

		for zi = z0, z1 do
			for xi = x0, x1 do
				local wx = xi * step
				local wz = zi * step
				local dx = wx - cx
				local dz = wz - cz
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist <= radius then
					local weight = brushWeight(dist, radius, stroke.falloff, stroke.maxMode)
					if weight > 0 then
						local old = Spring.GetMetalAmount(xi, zi) or 0
						local delta = peak * weight
						local newAmt = erase and (old - delta) or (old + delta)
						if newAmt < 0 then
							newAmt = 0
						elseif newAmt > MAX_METAL then
							newAmt = MAX_METAL
						end
						remember(xi, zi, old)
						Spring.SetMetalAmount(xi, zi, newAmt)
					end
				end
			end
		end
	end

	local function applyGrassBrush(cx, cz)
		local radius = stroke.radius
		local step = GRASS_STEP
		local x0 = math.floor((cx - radius) / step) * step
		local z0 = math.floor((cz - radius) / step) * step
		local x1 = math.ceil((cx + radius) / step) * step
		local z1 = math.ceil((cz + radius) / step) * step
		local grow = stroke.tool == "grass"

		for z = z0, z1, step do
			for x = x0, x1, step do
				local dx = x - cx
				local dz = z - cz
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist <= radius then
					local weight = brushWeight(dist, radius, stroke.falloff, true)
					if weight > 0.35 then
						local old = Spring.GetGrass(x, z) or 0
						remember(x, z, old)
						if grow then
							if old <= 0 then
								Spring.AddGrass(x, z)
							end
						elseif old > 0 then
							Spring.RemoveGrass(x, z)
						end
					end
				end
			end
		end
	end

	local function applySmoothBrush(cx, cz)
		local radius = stroke.radius
		local kRad = math.max(SQUARE, radius * 0.4)
		local x0 = math.floor((cx - radius) / SQUARE) * SQUARE
		local z0 = math.floor((cz - radius) / SQUARE) * SQUARE
		local x1 = math.ceil((cx + radius) / SQUARE) * SQUARE
		local z1 = math.ceil((cz + radius) / SQUARE) * SQUARE
		local gx0 = math.floor((cx - radius - kRad) / SQUARE) * SQUARE
		local gz0 = math.floor((cz - radius - kRad) / SQUARE) * SQUARE
		local gx1 = math.ceil((cx + radius + kRad) / SQUARE) * SQUARE
		local gz1 = math.ceil((cz + radius + kRad) / SQUARE) * SQUARE
		local nx = math.floor((gx1 - gx0) / SQUARE) + 1
		local nz = math.floor((gz1 - gz0) / SQUARE) + 1
		if nx < 1 or nz < 1 then
			return
		end
		local src = {}
		local n = 0
		for iz = 0, nz - 1 do
			local z = gz0 + iz * SQUARE
			for ix = 0, nx - 1 do
				n = n + 1
				src[n] = Spring.GetGroundHeight(gx0 + ix * SQUARE, z)
			end
		end
		local k = math.max(1, math.floor(kRad / SQUARE + 0.5))
		local tmp = {}
		for iz = 0, nz - 1 do
			local row = iz * nx
			local prefix = {}
			local sum = 0
			for ix = 0, nx - 1 do
				sum = sum + src[row + ix + 1]
				prefix[ix + 1] = sum
			end
			for ix = 0, nx - 1 do
				local left = ix - k
				if left < 0 then
					left = 0
				end
				local right = ix + k
				if right >= nx then
					right = nx - 1
				end
				local acc = prefix[right + 1]
				if left > 0 then
					acc = acc - prefix[left]
				end
				tmp[row + ix + 1] = acc / (right - left + 1)
			end
		end
		local blur = {}
		for ix = 0, nx - 1 do
			local prefix = {}
			local sum = 0
			for iz = 0, nz - 1 do
				sum = sum + tmp[iz * nx + ix + 1]
				prefix[iz + 1] = sum
			end
			for iz = 0, nz - 1 do
				local top = iz - k
				if top < 0 then
					top = 0
				end
				local bot = iz + k
				if bot >= nz then
					bot = nz - 1
				end
				local acc = prefix[bot + 1]
				if top > 0 then
					acc = acc - prefix[top]
				end
				blur[iz * nx + ix + 1] = acc / (bot - top + 1)
			end
		end
		local mix = strokeMix()
		local xs, zs, hs = {}, {}, {}
		for z = z0, z1, SQUARE do
			for x = x0, x1, SQUARE do
				local dx = x - cx
				local dz = z - cz
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist <= radius then
					local weight = brushWeight(dist, radius, stroke.falloff, stroke.maxMode)
					if weight > 0 then
						local ix = math.floor((x - gx0) / SQUARE)
						local iz = math.floor((z - gz0) / SQUARE)
						local slot = iz * nx + ix + 1
						local old = src[slot]
						local target = blur[slot]
						if old and target then
							remember(x, z, old)
							local nH = #xs + 1
							xs[nH] = x
							zs[nH] = z
							hs[nH] = old + (target - old) * weight * mix
						end
					end
				end
			end
		end
		if #xs > 0 then
			applyHeights(xs, zs, hs)
		end
	end

	local function stampRampCorridor(ax, az, bx, bz, ah, bh, mix, xs, zs, hs)
		local radius = stroke.radius
		local abx = bx - ax
		local abz = bz - az
		local len2 = abx * abx + abz * abz
		if len2 < 1024 then
			return
		end
		local x0 = math.floor((math.min(ax, bx) - radius) / SQUARE) * SQUARE
		local z0 = math.floor((math.min(az, bz) - radius) / SQUARE) * SQUARE
		local x1 = math.ceil((math.max(ax, bx) + radius) / SQUARE) * SQUARE
		local z1 = math.ceil((math.max(az, bz) + radius) / SQUARE) * SQUARE
		for z = z0, z1, SQUARE do
			for x = x0, x1, SQUARE do
				local t = ((x - ax) * abx + (z - az) * abz) / len2
				if t < 0 then
					t = 0
				elseif t > 1 then
					t = 1
				end
				local px = ax + t * abx
				local pz = az + t * abz
				local dx = x - px
				local dz = z - pz
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist <= radius then
					local weight = brushWeight(dist, radius, stroke.falloff, stroke.maxMode) * mix
					if weight > 0 then
						local key = cellKey(x, z)
						local old
						if stroke.seen[key] then
							old = stroke.oldByKey[key]
						else
							old = Spring.GetGroundHeight(x, z)
							remember(x, z, old)
							stroke.oldByKey[key] = old
						end
						local n = #xs + 1
						xs[n] = x
						zs[n] = z
						hs[n] = old + (ah + (bh - ah) * t - old) * weight
					end
				end
			end
		end
	end

	local function applyRamp(cx, cz)
		if not stroke then
			return
		end
		stroke.endX = cx
		stroke.endZ = cz
		if #stroke.xs > 0 then
			applyHeights(stroke.xs, stroke.zs, stroke.old)
		end
		local ah = stroke.centerH
		local bh = Spring.GetGroundHeight(cx, cz)
		local mix = strokeMix()
		local xs, zs, hs = {}, {}, {}
		local xforms = stroke.xforms
		for i = 1, #xforms do
			local ax, az = xforms[i](stroke.startX, stroke.startZ)
			local bx, bz = xforms[i](cx, cz)
			stampRampCorridor(ax, az, bx, bz, ah, bh, mix, xs, zs, hs)
		end
		if #xs > 0 then
			applyHeights(xs, zs, hs)
		end
	end

	local function applyOneBrush(cx, cz)
		if stroke.tool == "smooth" then
			applySmoothBrush(cx, cz)
		elseif stroke.kind == KIND_METAL then
			applyMetalBrush(cx, cz)
		elseif stroke.kind == KIND_GRASS then
			applyGrassBrush(cx, cz)
		else
			applyHeightBrush(cx, cz)
		end
	end

	local function applyBrush(cx, cz)
		if stroke.tool == "ramp" then
			applyRamp(cx, cz)
			return
		end
		local xforms = stroke.xforms
		for i = 1, #xforms do
			local x, z = xforms[i](cx, cz)
			applyOneBrush(x, z)
		end
	end

	local function beginStroke(tool, x, z, radius, strength, falloff, maxMode, mh, mv, radial)
		if stroke then
			return
		end
		if mh == nil then
			mh = liveMirror.h
		end
		if mv == nil then
			mv = liveMirror.v
		end
		if radial == nil then
			radial = liveMirror.radial
		end
		liveMirror.h = not not mh
		liveMirror.v = not not mv
		liveMirror.radial = tonumber(radial) or 0
		stroke = {
			tool = tool,
			kind = toolKind(tool),
			radius = clampRadius(radius),
			strength = math.max(0.1, strength),
			falloff = math.max(0, math.min(1, falloff)),
			maxMode = maxMode,
			centerH = Spring.GetGroundHeight(x, z),
			startX = x,
			startZ = z,
			endX = x,
			endZ = z,
			xs = {},
			zs = {},
			old = {},
			seen = {},
			oldByKey = {},
			xforms = makeXforms(liveMirror.h, liveMirror.v, liveMirror.radial),
		}
		applyBrush(x, z)
	end

	local function continueStroke(x, z)
		if not stroke then
			return
		end
		applyBrush(x, z)
	end

	local function endStroke()
		if not stroke then
			return
		end
		if #stroke.xs > 0 then
			undoStack[#undoStack + 1] = {
				kind = stroke.kind,
				xs = stroke.xs,
				zs = stroke.zs,
				old = stroke.old,
			}
			if #undoStack > MAX_UNDO then
				table.remove(undoStack, 1)
			end
			redoStack = {}
			noteMapUnsaved()
			if stroke.kind == KIND_GRASS then
				bumpGrassVisual()
			end
		end
		stroke = nil
		publishState()
	end

	local function captureObject(isUnit, objectID)
		if isUnit then
			if not Spring.ValidUnitID(objectID) then
				return nil
			end
			local defID = Spring.GetUnitDefID(objectID)
			local def = defID and UnitDefs[defID]
			local x, y, z = Spring.GetUnitPosition(objectID)
			return {
				kind = KIND_ASSET,
				op = "delete",
				isUnit = true,
				defName = def and def.name,
				x = x,
				y = y,
				z = z,
				heading = Spring.GetUnitHeading(objectID) or 0,
				facing = Spring.GetUnitBuildFacing(objectID) or 0,
				team = Spring.GetUnitTeam(objectID),
			}
		end
		if not Spring.ValidFeatureID(objectID) then
			return nil
		end
		local defID = Spring.GetFeatureDefID(objectID)
		local def = defID and FeatureDefs[defID]
		local x, y, z = Spring.GetFeaturePosition(objectID)
		return {
			kind = KIND_ASSET,
			op = "delete",
			isUnit = false,
			defName = def and def.name,
			x = x,
			y = y,
			z = z,
			heading = Spring.GetFeatureHeading(objectID) or 0,
			team = Spring.GetFeatureTeam(objectID),
		}
	end

	local function spawnAsset(frame)
		local y = frame.y or Spring.GetGroundHeight(frame.x, frame.z)
		if frame.isUnit then
			local unitID = Spring.CreateUnit(frame.defName, frame.x, y, frame.z, frame.facing or 0, frame.team)
			return unitID
		end
		return Spring.CreateFeature(frame.defName, frame.x, y, frame.z, frame.heading or 0, frame.team)
	end

	local function destroyAsset(isUnit, objectID)
		if isUnit then
			if Spring.ValidUnitID(objectID) then
				Spring.DestroyUnit(objectID, false, true)
			end
		elseif Spring.ValidFeatureID(objectID) then
			Spring.DestroyFeature(objectID)
		end
	end

	local function applyAssetUndo(frame)
		if frame.op == "place" then
			local snap = captureObject(frame.isUnit, frame.id)
			destroyAsset(frame.isUnit, frame.id)
			return snap
		end
		local id = spawnAsset(frame)
		if not id then
			return nil
		end
		return {
			kind = KIND_ASSET,
			op = "place",
			isUnit = frame.isUnit,
			id = id,
			defName = frame.defName,
			x = frame.x,
			y = frame.y,
			z = frame.z,
			heading = frame.heading,
			facing = frame.facing,
			team = frame.team,
		}
	end

	local function pushAsset(frame)
		undoStack[#undoStack + 1] = frame
		if #undoStack > MAX_UNDO then
			table.remove(undoStack, 1)
		end
		redoStack = {}
		noteMapUnsaved()
		publishState()
	end

	local function placeFeature(defName, x, z, heading, playerID)
		local team = Spring.GetGaiaTeamID()
		local y = Spring.GetGroundHeight(x, z)
		local id = Spring.CreateFeature(defName, x, y, z, heading or 0, team)
		if id then
			pushAsset({
				kind = KIND_ASSET,
				op = "place",
				isUnit = false,
				id = id,
				defName = defName,
				x = x,
				y = y,
				z = z,
				heading = heading or 0,
				team = team,
			})
		end
	end

	local function placeUnit(defName, x, z, facing, playerID)
		local _, _, _, team = Spring.GetPlayerInfo(playerID, false)
		team = team or 0
		local y = Spring.GetGroundHeight(x, z)
		local id = Spring.CreateUnit(defName, x, y, z, facing or 0, team)
		if id then
			pushAsset({
				kind = KIND_ASSET,
				op = "place",
				isUnit = true,
				id = id,
				defName = defName,
				x = x,
				y = y,
				z = z,
				facing = facing or 0,
				team = team,
			})
		end
	end

	local function deleteNearest(x, z, radius)
		radius = radius or 96
		local bestID, bestDist, isUnit
		local features = Spring.GetFeaturesInCylinder(x, z, radius)
		for i = 1, #features do
			local fx, _, fz = Spring.GetFeaturePosition(features[i])
			local dx, dz = fx - x, fz - z
			local d = dx * dx + dz * dz
			if not bestDist or d < bestDist then
				bestDist = d
				bestID = features[i]
				isUnit = false
			end
		end
		local units = Spring.GetUnitsInCylinder(x, z, radius)
		for i = 1, #units do
			local ux, _, uz = Spring.GetUnitPosition(units[i])
			local dx, dz = ux - x, uz - z
			local d = dx * dx + dz * dz
			if not bestDist or d < bestDist then
				bestDist = d
				bestID = units[i]
				isUnit = true
			end
		end
		if not bestID then
			return
		end
		local snap = captureObject(isUnit, bestID)
		destroyAsset(isUnit, bestID)
		if snap then
			pushAsset(snap)
		end
	end

	local function copyBox(xmin, zmin, xmax, zmax)
		if not xmin then
			return nil
		end
		return { xmin, zmin, xmax, zmax }
	end

	local function applyStartBox(ally, box)
		ally = ally or 0
		if not box then
			Spring.SetAllyTeamStartBox(ally, 0, 0, Game.mapSizeX, Game.mapSizeZ)
			return
		end
		local xmin, xmax = math.min(box[1], box[3]), math.max(box[1], box[3])
		local zmin, zmax = math.min(box[2], box[4]), math.max(box[2], box[4])
		Spring.SetAllyTeamStartBox(ally, xmin, zmin, xmax, zmax)
	end

	local function applyStartPoint(team, point)
		team = team or 0
		if not point then
			Spring.SetTeamStartPosition(team, -1, -1, -1)
			return
		end
		Spring.SetTeamStartPosition(team, point[1], point[2], point[3])
	end

	local function applyStartUndo(frame)
		if frame.op == "box" then
			applyStartBox(frame.ally, frame.old)
			return {
				kind = KIND_START,
				op = "box",
				ally = frame.ally,
				old = frame.new,
				new = frame.old,
			}
		end
		if frame.op == "point" then
			applyStartPoint(frame.team, frame.old)
			return {
				kind = KIND_START,
				op = "point",
				team = frame.team,
				old = frame.new,
				new = frame.old,
			}
		end
	end

	local function setStartBox(xmin, zmin, xmax, zmax, ally)
		ally = ally or 0
		local oldXmin, oldZmin, oldXmax, oldZmax = Spring.GetAllyTeamStartBox(ally)
		local newBox = {
			math.min(xmin, xmax),
			math.min(zmin, zmax),
			math.max(xmin, xmax),
			math.max(zmin, zmax),
		}
		applyStartBox(ally, newBox)
		pushAsset({
			kind = KIND_START,
			op = "box",
			ally = ally,
			old = copyBox(oldXmin, oldZmin, oldXmax, oldZmax),
			new = newBox,
		})
	end

	local function setStartPoint(x, z, team)
		team = team or 0
		local ox, oy, oz = Spring.GetTeamStartPosition(team)
		local y = Spring.GetGroundHeight(x, z)
		local newPoint = { x, y, z }
		applyStartPoint(team, newPoint)
		pushAsset({
			kind = KIND_START,
			op = "point",
			team = team,
			old = (ox and { ox, oy, oz }) or nil,
			new = newPoint,
		})
	end

	local function clearStartBox(ally)
		ally = ally or 0
		local oldXmin, oldZmin, oldXmax, oldZmax = Spring.GetAllyTeamStartBox(ally)
		applyStartBox(ally, nil)
		pushAsset({
			kind = KIND_START,
			op = "box",
			ally = ally,
			old = copyBox(oldXmin, oldZmin, oldXmax, oldZmax),
			new = nil,
		})
	end

	local function applyLightUndo(frame)
		lightState = copyLight(frame.old)
		publishLight(lightState)
		return {
			kind = KIND_LIGHT,
			old = copyLight(frame.new),
			new = copyLight(frame.old),
		}
	end

	local function setLight(newState)
		if not lightState then
			lightState = copyLight(newState)
			publishLight(lightState)
			return
		end
		pushAsset({
			kind = KIND_LIGHT,
			old = copyLight(lightState),
			new = copyLight(newState),
		})
		lightState = copyLight(newState)
		publishLight(lightState)
	end

	local function metalIndex(x, z)
		return z * metalW + x
	end

	local function isPlaytestUnit(unitID)
		return playtestUnits[unitID] and true or false
	end

	local function captureSession(writeFile)
		local xs, zs, hs = {}, {}, {}
		local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
		for z = 0, mapZ, SQUARE do
			for x = 0, mapX, SQUARE do
				local h = Spring.GetGroundHeight(x, z)
				local orig = Spring.GetGroundOrigHeight(x, z)
				if math.abs(h - orig) > 0.15 then
					local n = #xs + 1
					xs[n] = x
					zs[n] = z
					hs[n] = h
				end
			end
		end
		local metal = {}
		for z = 0, metalH - 1 do
			for x = 0, metalW - 1 do
				metal[metalIndex(x, z)] = Spring.GetMetalAmount(x, z) or 0
			end
		end
		local grass = {}
		for z = 0, mapZ, GRASS_STEP do
			for x = 0, mapX, GRASS_STEP do
				if (Spring.GetGrass(x, z) or 0) > 0 then
					grass[#grass + 1] = { x, z }
				end
			end
		end
		local features = {}
		local featIDs = Spring.GetAllFeatures()
		for i = 1, #featIDs do
			local snap = captureObject(false, featIDs[i])
			if snap and snap.defName then
				features[#features + 1] = snap
			end
		end
		local units = {}
		local unitIDs = Spring.GetAllUnits()
		for i = 1, #unitIDs do
			local id = unitIDs[i]
			if not isPlaytestUnit(id) then
				local snap = captureObject(true, id)
				if snap and snap.defName then
					units[#units + 1] = snap
				end
			end
		end
		local xmin, zmin, xmax, zmax = Spring.GetAllyTeamStartBox(0)
		local px, py, pz = Spring.GetTeamStartPosition(0)
		session = {
			xs = xs,
			zs = zs,
			hs = hs,
			metal = metal,
			grass = grass,
			features = features,
			units = units,
			box = (xmin and { xmin, zmin, xmax, zmax }) or nil,
			point = (px and { px, py, pz }) or nil,
			light = copyLight(lightState),
		}
		Spring.SetGameRulesParam("mapEditorHasSave", 1)
		if writeFile then
			SendToUnsynced("mapEditorDoSave")
		end
		publishState()
	end

	local function restoreSession()
		if not session then
			SendToUnsynced("mapEditorDoLoad")
			return
		end
		local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
		Spring.SetHeightMapFunc(function()
			for z = 0, mapZ, SQUARE do
				for x = 0, mapX, SQUARE do
					Spring.SetHeightMap(x, z, Spring.GetGroundOrigHeight(x, z))
				end
			end
			for i = 1, #session.xs do
				Spring.SetHeightMap(session.xs[i], session.zs[i], session.hs[i])
			end
		end)
		if session.metal then
			for z = 0, metalH - 1 do
				for x = 0, metalW - 1 do
					Spring.SetMetalAmount(x, z, session.metal[metalIndex(x, z)] or origMetal[metalIndex(x, z)] or 0)
				end
			end
		end
		for z = 0, mapZ, GRASS_STEP do
			for x = 0, mapX, GRASS_STEP do
				if (Spring.GetGrass(x, z) or 0) > 0 then
					Spring.RemoveGrass(x, z)
				end
			end
		end
		for i = 1, #session.grass do
			Spring.AddGrass(session.grass[i][1], session.grass[i][2])
		end
		bumpGrassVisual()
		local featIDs = Spring.GetAllFeatures()
		for i = 1, #featIDs do
			Spring.DestroyFeature(featIDs[i])
		end
		local unitIDs = Spring.GetAllUnits()
		for i = 1, #unitIDs do
			Spring.DestroyUnit(unitIDs[i], false, true)
		end
		playtestUnits = {}
		for i = 1, #session.features do
			local f = session.features[i]
			Spring.CreateFeature(f.defName, f.x, f.y or Spring.GetGroundHeight(f.x, f.z), f.z, f.heading or 0, f.team)
		end
		for i = 1, #session.units do
			local u = session.units[i]
			Spring.CreateUnit(u.defName, u.x, u.y or Spring.GetGroundHeight(u.x, u.z), u.z, u.facing or 0, u.team or 0)
		end
		if session.box then
			Spring.SetAllyTeamStartBox(0, session.box[1], session.box[2], session.box[3], session.box[4])
		end
		if session.point then
			Spring.SetTeamStartPosition(0, session.point[1], session.point[2], session.point[3])
		end
		if session.light then
			lightState = copyLight(session.light)
			publishLight(lightState)
		end
		publishState()
	end

	local function startPlaytest()
		if playtesting then
			return
		end
		captureSession(false)
		playtesting = true
		Spring.SetGameRulesParam("mapEditorPlaytest", 1)
		local team = 0
		local x, y, z = Spring.GetTeamStartPosition(team)
		if not x or x < 0 then
			local xmin, zmin, xmax, zmax = Spring.GetAllyTeamStartBox(0)
			if xmin then
				x = (xmin + xmax) * 0.5
				z = (zmin + zmax) * 0.5
			else
				x = Game.mapSizeX * 0.5
				z = Game.mapSizeZ * 0.5
			end
		end
		y = Spring.GetGroundHeight(x, z)
		local com = (UnitDefNames.armcom and "armcom") or (UnitDefNames.corcom and "corcom")
		if com then
			local id = Spring.CreateUnit(com, x, y, z, 0, team)
			if id then
				playtestUnits[id] = true
			end
		end
		Spring.SetTeamResource(team, "m", 1000)
		Spring.SetTeamResource(team, "e", 1000)
		publishState()
	end

	local function endPlaytest()
		if not playtesting then
			return
		end
		for unitID in pairs(playtestUnits) do
			if Spring.ValidUnitID(unitID) then
				Spring.DestroyUnit(unitID, false, true)
			end
		end
		playtestUnits = {}
		playtesting = false
		Spring.SetGameRulesParam("mapEditorPlaytest", 0)
		restoreSession()
	end

	local function undo()
		if stroke or #undoStack == 0 then
			return
		end
		noteMapUnsaved()
		local frame = undoStack[#undoStack]
		undoStack[#undoStack] = nil
		if frame.kind == KIND_ASSET then
			local inverse = applyAssetUndo(frame)
			if inverse then
				redoStack[#redoStack + 1] = inverse
			end
			publishState()
			return
		end
		if frame.kind == KIND_START then
			local inverse = applyStartUndo(frame)
			if inverse then
				redoStack[#redoStack + 1] = inverse
			end
			publishState()
			return
		end
		if frame.kind == KIND_LIGHT then
			local inverse = applyLightUndo(frame)
			if inverse then
				redoStack[#redoStack + 1] = inverse
			end
			publishState()
			return
		end
		if frame.kind == KIND_TEX then
			Spring.SetGameRulesParam("mapEditorTexOp", 1)
			Spring.SetGameRulesParam("mapEditorTexRev", (Spring.GetGameRulesParam("mapEditorTexRev") or 0) + 1)
			redoStack[#redoStack + 1] = { kind = KIND_TEX }
			publishState()
			return
		end
		local current = snapshotValues(frame.xs, frame.zs, frame.kind)
		restoreFrame(frame.xs, frame.zs, frame.old, frame.kind)
		redoStack[#redoStack + 1] = {
			kind = frame.kind,
			xs = frame.xs,
			zs = frame.zs,
			old = current,
		}
		publishState()
	end

	local function redo()
		if stroke or #redoStack == 0 then
			return
		end
		noteMapUnsaved()
		local frame = redoStack[#redoStack]
		redoStack[#redoStack] = nil
		if frame.kind == KIND_ASSET then
			local inverse = applyAssetUndo(frame)
			if inverse then
				undoStack[#undoStack + 1] = inverse
			end
			publishState()
			return
		end
		if frame.kind == KIND_START then
			local inverse = applyStartUndo(frame)
			if inverse then
				undoStack[#undoStack + 1] = inverse
			end
			publishState()
			return
		end
		if frame.kind == KIND_LIGHT then
			local inverse = applyLightUndo(frame)
			if inverse then
				undoStack[#undoStack + 1] = inverse
			end
			publishState()
			return
		end
		if frame.kind == KIND_TEX then
			Spring.SetGameRulesParam("mapEditorTexOp", 2)
			Spring.SetGameRulesParam("mapEditorTexRev", (Spring.GetGameRulesParam("mapEditorTexRev") or 0) + 1)
			undoStack[#undoStack + 1] = { kind = KIND_TEX }
			publishState()
			return
		end
		local current = snapshotValues(frame.xs, frame.zs, frame.kind)
		restoreFrame(frame.xs, frame.zs, frame.old, frame.kind)
		undoStack[#undoStack + 1] = {
			kind = frame.kind,
			xs = frame.xs,
			zs = frame.zs,
			old = current,
		}
		publishState()
	end

	function gadget:Initialize()
		Spring.SetGameRulesParam("isMapEditor", 1)
		Spring.SetGameRulesParam("mapEditorPlaytest", 0)
		Spring.SetGameRulesParam("mapEditorGrassRev", 0)
		Spring.SetGameRulesParam("mapEditorLightRev", 0)
		Spring.SetGameRulesParam("mapEditorHasSave", 0)
		Spring.SetGameRulesParam("mapEditorExport", 0)
		Spring.SetGameRulesParam("mapEditorTexRev", 0)
		Spring.SetGameRulesParam("mapEditorTexOp", 0)
		Spring.SetGameRulesParam("mapEditorNeedReload", 0)
		metalW = math.floor(Game.mapSizeX / METAL_SQUARE)
		metalH = math.floor(Game.mapSizeZ / METAL_SQUARE)
		for z = 0, metalH - 1 do
			for x = 0, metalW - 1 do
				origMetal[metalIndex(x, z)] = Spring.GetMetalAmount(x, z) or 0
			end
		end
		publishState()
	end

	function gadget:GameFrame(n)
		if playtesting then
			return
		end
		if n - lastAuto < 450 then
			return
		end
		if (Spring.GetGameRulesParam("mapEditorDirty") or 0) > 0 then
			lastAuto = n
			captureSession(false)
		end
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if type(msg) ~= "string" or msg:sub(1, PREFIX_LEN) ~= MSG_PREFIX then
			return
		end
		if not authorized(playerID) then
			return
		end

		local parts = parseCommand(msg)
		local cmd = parts[1]
		if playtesting and cmd ~= "edit" and cmd ~= "save" and cmd ~= "export" and cmd ~= "newmap" and cmd ~= "reload" then
			return
		end
		if cmd == "begin" then
			local mh, mv, radial
			if parts[9] ~= nil then
				mh = parts[9] == "1"
			end
			if parts[10] ~= nil then
				mv = parts[10] == "1"
			end
			if parts[11] ~= nil then
				radial = tonumber(parts[11])
			end
			beginStroke(
				parts[2],
				tonumber(parts[3]) or 0,
				tonumber(parts[4]) or 0,
				tonumber(parts[5]) or 240,
				tonumber(parts[6]) or 12,
				tonumber(parts[7]) or 0.7,
				parts[8] == "1",
				mh,
				mv,
				radial
			)
		elseif cmd == "mirror" then
			liveMirror.h = parts[2] == "1"
			liveMirror.v = parts[3] == "1"
			liveMirror.radial = tonumber(parts[4]) or 0
		elseif cmd == "paint" then
			continueStroke(tonumber(parts[2]) or 0, tonumber(parts[3]) or 0)
		elseif cmd == "end" then
			endStroke()
		elseif cmd == "undo" then
			undo()
		elseif cmd == "redo" then
			redo()
		elseif cmd == "placefeat" then
			local xforms = makeXforms(liveMirror.h, liveMirror.v, liveMirror.radial)
			local heading = tonumber(parts[5]) or 0
			for i = 1, #xforms do
				local px, pz, rot, flipH, flipV = xforms[i](tonumber(parts[3]) or 0, tonumber(parts[4]) or 0)
				local h = heading
				if flipH then
					h = -h
				end
				if flipV then
					h = 32768 - h
				end
				placeFeature(parts[2], px, pz, h + rot * 65536 / (2 * math.pi), playerID)
			end
		elseif cmd == "placeunit" then
			local xforms = makeXforms(liveMirror.h, liveMirror.v, liveMirror.radial)
			local facing = tonumber(parts[5]) or 0
			for i = 1, #xforms do
				local px, pz, rot, flipH, flipV = xforms[i](tonumber(parts[3]) or 0, tonumber(parts[4]) or 0)
				local face = facing
				if flipH then
					if face == 1 then
						face = 3
					elseif face == 3 then
						face = 1
					end
				end
				if flipV then
					if face == 0 then
						face = 2
					elseif face == 2 then
						face = 0
					end
				end
				face = math.floor(face + rot / (math.pi / 2) + 0.5) % 4
				placeUnit(parts[2], px, pz, face, playerID)
			end
		elseif cmd == "delete" then
			local xforms = makeXforms(liveMirror.h, liveMirror.v, liveMirror.radial)
			local radius = tonumber(parts[4]) or 96
			for i = 1, #xforms do
				local px, pz = xforms[i](tonumber(parts[2]) or 0, tonumber(parts[3]) or 0)
				deleteNearest(px, pz, radius)
			end
		elseif cmd == "startbox" then
			setStartBox(
				tonumber(parts[2]) or 0,
				tonumber(parts[3]) or 0,
				tonumber(parts[4]) or 0,
				tonumber(parts[5]) or 0,
				tonumber(parts[6]) or 0
			)
		elseif cmd == "startpoint" then
			setStartPoint(tonumber(parts[2]) or 0, tonumber(parts[3]) or 0, tonumber(parts[4]) or 0)
		elseif cmd == "clearstart" then
			clearStartBox(tonumber(parts[2]) or 0)
		elseif cmd == "light" then
			setLight({
				sx = tonumber(parts[2]) or 0,
				sy = tonumber(parts[3]) or 1,
				sz = tonumber(parts[4]) or 0,
				ar = tonumber(parts[5]) or 0.5,
				ag = tonumber(parts[6]) or 0.5,
				ab = tonumber(parts[7]) or 0.5,
				dr = tonumber(parts[8]) or 0.8,
				dg = tonumber(parts[9]) or 0.8,
				db = tonumber(parts[10]) or 0.8,
				shadow = tonumber(parts[11]) or 0.8,
				fogS = tonumber(parts[12]) or 0,
				fogE = tonumber(parts[13]) or 1,
				water = tonumber(parts[14]) or 0.4,
			})
		elseif cmd == "save" then
			captureSession(true)
		elseif cmd == "export" then
			SendToUnsynced("mapEditorDoExport", table.concat(parts, ",", 2))
			Spring.SetGameRulesParam("mapEditorExport", 1)
		elseif cmd == "newmap" then
			SendToUnsynced("mapEditorDoNew", tonumber(parts[2]) or 16, table.concat(parts, ",", 3))
		elseif cmd == "reload" then
			Spring.SetGameRulesParam("mapEditorNeedReload", 1)
		elseif cmd == "tex" then
			pushAsset({ kind = KIND_TEX })
		elseif cmd == "load" then
			noteMapUnsaved()
			restoreSession()
		elseif cmd == "playtest" then
			startPlaytest()
		elseif cmd == "edit" then
			endPlaytest()
		elseif cmd == "fbegin" then
			session = {
				xs = {},
				zs = {},
				hs = {},
				metal = {},
				grass = {},
				features = {},
				units = {},
			}
		elseif cmd == "fh" then
			if session then
				session.xs[#session.xs + 1] = tonumber(parts[2]) or 0
				session.zs[#session.zs + 1] = tonumber(parts[3]) or 0
				session.hs[#session.hs + 1] = tonumber(parts[4]) or 0
			end
		elseif cmd == "fm" then
			if session then
				session.metal[metalIndex(tonumber(parts[2]) or 0, tonumber(parts[3]) or 0)] = tonumber(parts[4]) or 0
			end
		elseif cmd == "fg" then
			if session then
				session.grass[#session.grass + 1] = { tonumber(parts[2]) or 0, tonumber(parts[3]) or 0 }
			end
		elseif cmd == "ff" then
			if session then
				session.features[#session.features + 1] = {
					defName = parts[2],
					x = tonumber(parts[3]) or 0,
					z = tonumber(parts[4]) or 0,
					heading = tonumber(parts[5]) or 0,
				}
			end
		elseif cmd == "fu" then
			if session then
				session.units[#session.units + 1] = {
					defName = parts[2],
					x = tonumber(parts[3]) or 0,
					z = tonumber(parts[4]) or 0,
					facing = tonumber(parts[5]) or 0,
					team = 0,
				}
			end
		elseif cmd == "fb" then
			if session then
				session.box = {
					tonumber(parts[2]) or 0,
					tonumber(parts[3]) or 0,
					tonumber(parts[4]) or 0,
					tonumber(parts[5]) or 0,
				}
			end
		elseif cmd == "fp" then
			if session then
				session.point = {
					tonumber(parts[2]) or 0,
					tonumber(parts[3]) or 0,
					tonumber(parts[4]) or 0,
				}
			end
		elseif cmd == "fl" then
			if session then
				session.light = {
					sx = tonumber(parts[2]) or 0,
					sy = tonumber(parts[3]) or 1,
					sz = tonumber(parts[4]) or 0,
					ar = tonumber(parts[5]) or 0.5,
					ag = tonumber(parts[6]) or 0.5,
					ab = tonumber(parts[7]) or 0.5,
					dr = tonumber(parts[8]) or 0.8,
					dg = tonumber(parts[9]) or 0.8,
					db = tonumber(parts[10]) or 0.8,
					shadow = tonumber(parts[11]) or 0.8,
					fogS = tonumber(parts[12]) or 0,
					fogE = tonumber(parts[13]) or 1,
					water = tonumber(parts[14]) or 0.4,
				}
			end
		elseif cmd == "fend" then
			noteMapUnsaved()
			restoreSession()
		end
	end
else
	local SAVE_FILE = "mapeditor_" .. tostring(Game.mapName or "map"):gsub("[^%w%._%-]", "_") .. ".txt"
	local loadLines = {}
	local loadIndex = 0

	local function applyLight(sx, sy, sz, ar, ag, ab, dr, dg, db, shadow, fogS, fogE, water)
		Spring.SetSunDirection(sx, sy, sz)
		Spring.SetSunLighting({
			groundAmbientColor = { ar, ag, ab },
			groundDiffuseColor = { dr, dg, db },
			groundShadowDensity = shadow,
			modelShadowDensity = shadow,
		})
		Spring.SetAtmosphere({ fogStart = fogS, fogEnd = fogE })
		Spring.SetWaterParams({ surfaceAlpha = water })
	end

	local function writeSessionFile()
		if not io then
			return
		end
		local f = io.open(SAVE_FILE, "w")
		if not f then
			return
		end
		local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ
		for z = 0, mapZ, SQUARE do
			for x = 0, mapX, SQUARE do
				local h = Spring.GetGroundHeight(x, z)
				local orig = Spring.GetGroundOrigHeight(x, z)
				if math.abs(h - orig) > 0.15 then
					f:write(string.format("H %d %d %.2f\n", x, z, h))
				end
			end
		end
		local mw = math.floor(mapX / METAL_SQUARE)
		local mh = math.floor(mapZ / METAL_SQUARE)
		for z = 0, mh - 1 do
			for x = 0, mw - 1 do
				f:write(string.format("M %d %d %.2f\n", x, z, Spring.GetMetalAmount(x, z) or 0))
			end
		end
		for z = 0, mapZ, GRASS_STEP do
			for x = 0, mapX, GRASS_STEP do
				if (Spring.GetGrass(x, z) or 0) > 0 then
					f:write(string.format("G %d %d\n", x, z))
				end
			end
		end
		local feats = Spring.GetAllFeatures()
		for i = 1, #feats do
			local defID = Spring.GetFeatureDefID(feats[i])
			local def = defID and FeatureDefs[defID]
			local x, y, z = Spring.GetFeaturePosition(feats[i])
			if def and def.name and x then
				f:write(string.format("F %s %.1f %.1f %d\n", def.name, x, z, Spring.GetFeatureHeading(feats[i]) or 0))
			end
		end
		local units = Spring.GetAllUnits()
		for i = 1, #units do
			local defID = Spring.GetUnitDefID(units[i])
			local def = defID and UnitDefs[defID]
			local x, y, z = Spring.GetUnitPosition(units[i])
			if def and def.name and x then
				f:write(string.format("U %s %.1f %.1f %d\n", def.name, x, z, Spring.GetUnitBuildFacing(units[i]) or 0))
			end
		end
		local xmin, zmin, xmax, zmax = Spring.GetAllyTeamStartBox(0)
		if xmin then
			f:write(string.format("B %.1f %.1f %.1f %.1f\n", xmin, zmin, xmax, zmax))
		end
		local px, py, pz = Spring.GetTeamStartPosition(0)
		if px then
			f:write(string.format("P %.1f %.1f %.1f\n", px, py or 0, pz))
		end
		local sx, sy, sz = gl.GetSun("pos")
		if sx then
			local ar, ag, ab = gl.GetSun("ambient")
			local dr, dg, db = gl.GetSun("diffuse")
			f:write(string.format(
				"L %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f\n",
				sx, sy, sz, ar or 0.5, ag or 0.5, ab or 0.5, dr or 0.8, dg or 0.8, db or 0.8,
				gl.GetSun("shadowDensity") or 0.8,
				gl.GetAtmosphere("fogStart") or 0,
				gl.GetAtmosphere("fogEnd") or 1,
				(gl.GetWaterRendering and gl.GetWaterRendering("surfaceAlpha")) or 0.4
			))
		end
		f:close()
	end

	local function lineToMsg(line)
		local kind = line:sub(1, 1)
		local rest = line:sub(3)
		if kind == "H" then
			return "fh," .. rest:gsub("%s+", ",")
		end
		if kind == "M" then
			return "fm," .. rest:gsub("%s+", ",")
		end
		if kind == "G" then
			return "fg," .. rest:gsub("%s+", ",")
		end
		if kind == "F" then
			return "ff," .. rest:gsub("%s+", ",")
		end
		if kind == "U" then
			return "fu," .. rest:gsub("%s+", ",")
		end
		if kind == "B" then
			return "fb," .. rest:gsub("%s+", ",")
		end
		if kind == "P" then
			return "fp," .. rest:gsub("%s+", ",")
		end
		if kind == "L" then
			return "fl," .. rest:gsub("%s+", ",")
		end
	end

	local function startboxNames(xmin, zmin, xmax, zmax)
		local mapX = Game.mapSizeX or 1
		local mapZ = Game.mapSizeZ or 1
		local midX = ((xmin + xmax) * 0.5) / mapX
		local midZ = ((zmin + zmax) * 0.5) / mapZ
		if midX < 0.33 then
			if midZ < 0.33 then
				return "North-West", "NW"
			end
			if midZ > 0.66 then
				return "South-West", "SW"
			end
			return "West", "W"
		end
		if midX > 0.66 then
			if midZ < 0.33 then
				return "North-East", "NE"
			end
			if midZ > 0.66 then
				return "South-East", "SE"
			end
			return "East", "E"
		end
		if midZ < 0.33 then
			return "North", "N"
		end
		if midZ > 0.66 then
			return "South", "S"
		end
		return "Center", "Center"
	end

	local okCompile, compileMap = pcall(VFS.Include, "luarules/gadgets/include/map_editor_compile.lua")
	if not okCompile then
		Spring.Echo("Map Editor compile include failed: " .. tostring(compileMap))
		compileMap = nil
	end

	local function writeExportFiles(wantedName)
		if not compileMap or not compileMap.writeEditedMap then
			Spring.Echo("Map Editor compile module missing")
			return
		end
		local dest, name, packed = compileMap.writeEditedMap(wantedName)
		if dest then
			Spring.Echo("Map Editor saved map \"" .. tostring(name) .. "\"")
			Spring.Echo("Map Editor working copy: " .. tostring(dest))
			if packed then
				Spring.Echo("Map Editor skirmish file: " .. tostring(packed) .. " — restart the lobby to see it")
			else
				Spring.Echo("Map Editor pack failed — skirmish will not list this map until a .sd7/.sdz lands in the BAR data maps folder")
			end
		else
			Spring.Echo("Map Editor save failed: " .. tostring(name))
		end
	end

	local function beginFileLoad()
		if not io then
			return
		end
		local f = io.open(SAVE_FILE, "r")
		if not f then
			return
		end
		loadLines = {}
		for line in f:lines() do
			if line ~= "" then
				loadLines[#loadLines + 1] = line
			end
		end
		f:close()
		Spring.SendLuaRulesMsg(MSG_PREFIX .. "fbegin")
		loadIndex = 1
	end

	function gadget:RecvFromSynced(name, sx, sy, sz, ar, ag, ab, dr, dg, db, shadow, fogS, fogE, water)
		if name == "mapEditorLight" then
			applyLight(sx, sy, sz, ar, ag, ab, dr, dg, db, shadow, fogS, fogE, water)
		elseif name == "mapEditorDoSave" then
			writeSessionFile()
		elseif name == "mapEditorDoLoad" then
			beginFileLoad()
		elseif name == "mapEditorDoExport" then
			writeExportFiles(sx)
		elseif name == "mapEditorDoNew" then
			if compileMap and compileMap.writeBlankMap then
				local dest, name, script = compileMap.writeBlankMap(sx, sy)
				if dest and script then
					Spring.Echo("Map Editor created \"" .. tostring(name) .. "\" at " .. dest)
					local reloadFile = io.open("mapeditor_reload.txt", "w")
					if reloadFile then
						reloadFile:write(script)
						reloadFile:close()
					end
					Spring.SendLuaRulesMsg(MSG_PREFIX .. "reload")
					if Spring.Reload then
						pcall(Spring.Reload, script)
					end
				else
					Spring.Echo("Map Editor new map failed: " .. tostring(name))
				end
			else
				Spring.Echo("Map Editor compile module missing")
			end
		end
	end

	function gadget:Update()
		if loadIndex < 1 then
			return
		end
		local sent = 0
		while loadIndex <= #loadLines and sent < 50 do
			local msg = lineToMsg(loadLines[loadIndex])
			if msg then
				Spring.SendLuaRulesMsg(MSG_PREFIX .. msg)
			end
			loadIndex = loadIndex + 1
			sent = sent + 1
		end
		if loadIndex > #loadLines then
			Spring.SendLuaRulesMsg(MSG_PREFIX .. "fend")
			loadIndex = 0
			loadLines = {}
		end
	end

	function gadget:Initialize()
		Spring.SendCommands("cheat", "godmode", "globallos")
	end
end
