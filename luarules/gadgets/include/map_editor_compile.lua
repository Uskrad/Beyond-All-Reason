-- Compile a live Recoil editor session into a loadable maps/*.sdd archive.

local SQUARE = Game.squareSize or 8
local METAL_SQUARE = Game.metalMapSquareSize or 16

local function u16(n)
	n = math.floor(tonumber(n) or 0)
	if n < 0 then
		n = 0
	elseif n > 65535 then
		n = 65535
	end
	return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32(n)
	n = math.floor(tonumber(n) or 0) % 4294967296
	if n < 0 then
		n = n + 4294967296
	end
	local b1 = n % 256
	n = math.floor(n / 256)
	local b2 = n % 256
	n = math.floor(n / 256)
	local b3 = n % 256
	n = math.floor(n / 256)
	return string.char(b1, b2, b3, n % 256)
end

local function i32(n)
	n = math.floor(tonumber(n) or 0)
	if n < 0 then
		n = n + 4294967296
	end
	return u32(n)
end

local function f32(n)
	n = tonumber(n) or 0
	if n == 0 then
		return string.char(0, 0, 0, 0)
	end
	local sign = 0
	if n < 0 then
		sign = 1
		n = -n
	end
	local exp = math.floor(math.log(n) / math.log(2))
	local frac = n / (2 ^ exp)
	while frac >= 2 do
		frac = frac * 0.5
		exp = exp + 1
	end
	while frac < 1 and exp > -126 do
		frac = frac * 2
		exp = exp - 1
	end
	local expBits = exp + 127
	if expBits <= 0 then
		return string.char(0, 0, 0, sign * 128)
	end
	if expBits >= 255 then
		return string.char(0, 0, 128, 127 + sign * 128)
	end
	local mantissa = math.floor((frac - 1) * 8388608 + 0.5)
	if mantissa >= 8388608 then
		mantissa = 0
		expBits = expBits + 1
	end
	local bits = sign * 2147483648 + expBits * 8388608 + mantissa
	return u32(bits)
end

local function ru32(s, i)
	local a, b, c, d = string.byte(s, i, i + 3)
	if not d then
		return 0
	end
	return a + b * 256 + c * 65536 + d * 16777216
end

local function ri32(s, i)
	local v = ru32(s, i)
	if v >= 2147483648 then
		return v - 4294967296
	end
	return v
end

local function rf32(s, i)
	local bits = ru32(s, i)
	local sign = 1
	if bits >= 2147483648 then
		sign = -1
		bits = bits - 2147483648
	end
	local exp = math.floor(bits / 8388608)
	local frac = bits % 8388608
	if exp == 0 then
		return 0
	end
	if exp == 255 then
		return sign * math.huge
	end
	return sign * (1 + frac / 8388608) * (2 ^ (exp - 127))
end

local function splice(s, start, payload)
	return s:sub(1, start - 1) .. payload .. s:sub(start + #payload)
end

local function parentDir(path)
	return path:match("^(.*)/[^/]+$")
end

local function ensureDirs(path)
	if not Spring.CreateDir then
		return
	end
	local acc = ""
	for part in path:gmatch("[^/]+") do
		acc = acc == "" and part or (acc .. "/" .. part)
		Spring.CreateDir(acc)
	end
end

local function writeBytes(path, data)
	local dir = parentDir(path)
	if dir then
		ensureDirs(dir)
	end
	local f = io.open(path, "wb")
	if not f then
		return false
	end
	f:write(data)
	f:close()
	return true
end

local function writeText(path, text)
	local dir = parentDir(path)
	if dir then
		ensureDirs(dir)
	end
	local f = io.open(path, "w")
	if not f then
		return false
	end
	f:write(text)
	f:close()
	return true
end

local function normPath(path)
	path = tostring(path or ""):gsub("\\", "/"):gsub("^%./", "")
	if path:sub(1, 1) == "/" then
		path = path:sub(2)
	end
	return path
end

local function listMapFiles()
	local files = VFS.DirList("", "*", VFS.MAP, true) or {}
	if #files == 0 then
		files = VFS.DirList(".", "*", VFS.MAP, true) or {}
	end
	if #files == 0 then
		files = VFS.DirList("maps/", "*", VFS.MAP, true) or {}
		local extra = VFS.DirList("mapconfig/", "*", VFS.MAP, true) or {}
		for i = 1, #extra do
			files[#files + 1] = extra[i]
		end
		if VFS.FileExists("mapinfo.lua", VFS.MAP) then
			files[#files + 1] = "mapinfo.lua"
		end
	end
	local out = {}
	for i = 1, #files do
		local p = normPath(files[i])
		if p ~= "" and not p:lower():match("/$") then
			out[#out + 1] = p
		end
	end
	return out
end

local function findSmf(files)
	for i = 1, #files do
		if files[i]:lower():match("%.smf$") then
			return files[i]
		end
	end
	local listed = VFS.DirList("maps/", "*.smf", VFS.MAP) or {}
	if listed[1] then
		return normPath(listed[1])
	end
end

local function isCommander(def)
	if not def then
		return false
	end
	local cp = def.customParams
	if cp and (cp.iscommander or cp.commander) then
		return true
	end
	local name = def.name or ""
	return name:find("com", 1, true) and (name:find("armcom", 1, true) or name:find("corcom", 1, true) or name:find("legcom", 1, true))
end

local function boxName(xmin, zmin, xmax, zmax)
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

local function ser(value, indent)
	indent = indent or ""
	local t = type(value)
	if t == "string" then
		return string.format("%q", value)
	end
	if t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end
		return string.format("%.6g", value)
	end
	if t == "boolean" then
		return value and "true" or "false"
	end
	if t ~= "table" then
		return "nil"
	end
	local n = #value
	local array = n > 0
	if array then
		for i = 1, n do
			if value[i] == nil then
				array = false
				break
			end
		end
		local extra = false
		for k in pairs(value) do
			if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
				extra = true
				break
			end
		end
		if extra then
			array = false
		end
	end
	local inner = indent .. "\t"
	local parts = { "{\n" }
	if array then
		for i = 1, n do
			parts[#parts + 1] = inner .. ser(value[i], inner) .. ",\n"
		end
	else
		for k, v in pairs(value) do
			if type(v) ~= "function" then
				local key
				if type(k) == "string" and k:match("^[%a_][%w_]*$") then
					key = k
				elseif type(k) == "number" then
					key = "[" .. tostring(k) .. "]"
				else
					key = "[" .. ser(k) .. "]"
				end
				parts[#parts + 1] = inner .. key .. " = " .. ser(v, inner) .. ",\n"
			end
		end
	end
	parts[#parts + 1] = indent .. "}"
	return table.concat(parts)
end

local function loadMapinfo()
	local raw = VFS.LoadFile("mapinfo.lua", VFS.MAP)
	if not raw then
		return {}, nil
	end
	local fn = loadstring(raw)
	if not fn then
		return {}, raw
	end
	local env = {
		math = math,
		table = table,
		string = string,
		ipairs = ipairs,
		pairs = pairs,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		next = next,
		unpack = unpack,
		Spring = Spring,
		VFS = VFS,
		Game = Game,
	}
	setfenv(fn, env)
	local ok, info = pcall(fn)
	if ok and type(info) == "table" then
		return info, raw
	end
	return {}, raw
end

local function metalByte(x, z)
	local mw, mh = Spring.GetMetalMapSize()
	if mw and mh and (x < 0 or z < 0 or x >= mw or z >= mh) then
		return 0
	end
	local amt = Spring.GetMetalAmount(x, z) or 0
	local maxMetal = Game.maxMetal or 1
	if maxMetal <= 0 then
		maxMetal = 1
	end
	local byte = amt
	if byte > 255 then
		byte = amt / maxMetal
	end
	byte = math.floor(byte + 0.5)
	if byte < 0 then
		byte = 0
	elseif byte > 255 then
		byte = 255
	end
	return byte
end

local function patchSmf(smf)
	local mapx = Game.mapSizeX / SQUARE
	local mapy = Game.mapSizeZ / SQUARE
	if #smf < 80 then
		return nil, "smf header too small"
	end
	local hdrMapx = ri32(smf, 25)
	local hdrMapy = ri32(smf, 29)
	if hdrMapx ~= mapx or hdrMapy ~= mapy then
		Spring.Echo(string.format("Map Editor SMF size mismatch file=%dx%d live=%.0fx%.0f", hdrMapx, hdrMapy, mapx, mapy))
	end
	mapx, mapy = hdrMapx, hdrMapy
	local heightPtr = ri32(smf, 53)
	local metalPtr = ri32(smf, 69)
	local featurePtr = ri32(smf, 73)
	local numExtra = ri32(smf, 77)

	local minH, maxH = math.huge, -math.huge
	local heights = {}
	local hx = mapx + 1
	local hz = mapy + 1
	for z = 0, mapy do
		for x = 0, mapx do
			local h = Spring.GetGroundHeight(x * SQUARE, z * SQUARE) or 0
			heights[#heights + 1] = h
			if h < minH then
				minH = h
			end
			if h > maxH then
				maxH = h
			end
		end
	end
	if minH == math.huge then
		minH, maxH = 0, 1
	end
	if maxH - minH < 1 then
		maxH = minH + 1
	end
	minH = minH - 8
	maxH = maxH + 8
	local span = maxH - minH
	local hChunks = {}
	for i = 1, #heights do
		local u = math.floor((heights[i] - minH) * 65536 / span)
		hChunks[i] = u16(u)
	end
	local heightBlob = table.concat(hChunks)
	local hStart = heightPtr + 1
	if hStart < 1 or hStart + #heightBlob - 1 > #smf then
		return nil, "heightmap out of range"
	end
	smf = splice(smf, hStart, heightBlob)
	smf = splice(smf, 45, f32(minH) .. f32(maxH))

	local mw = mapx / 2
	local mh = mapy / 2
	local mChunks = {}
	local mi = 0
	for z = 0, mh - 1 do
		for x = 0, mw - 1 do
			mi = mi + 1
			mChunks[mi] = string.char(metalByte(x, z))
		end
	end
	local metalBlob = table.concat(mChunks)
	local mStart = metalPtr + 1
	if mStart >= 1 and mStart + #metalBlob - 1 <= #smf then
		smf = splice(smf, mStart, metalBlob)
	end

	local grassPtr
	local extraPos = 81
	for _ = 1, numExtra do
		if extraPos + 7 > #smf then
			break
		end
		local size = ri32(smf, extraPos)
		local typ = ri32(smf, extraPos + 4)
		if size < 8 then
			size = 8
		end
		if typ == 1 and extraPos + 11 <= #smf then
			grassPtr = ri32(smf, extraPos + 8)
		end
		extraPos = extraPos + size
	end

	local gw, gh = mapx / 4, mapy / 4
	local gChunks = {}
	local gi = 0
	local stepX = Game.mapSizeX / gw
	local stepZ = Game.mapSizeZ / gh
	for z = 0, gh - 1 do
		for x = 0, gw - 1 do
			gi = gi + 1
			local worldX = (x + 0.5) * stepX
			local worldZ = (z + 0.5) * stepZ
			gChunks[gi] = string.char(((Spring.GetGrass(worldX, worldZ) or 0) > 0) and 1 or 0)
		end
	end
	local grassBlob = table.concat(gChunks)
	if grassPtr and grassPtr > 80 and grassPtr + #grassBlob <= #smf then
		smf = splice(smf, grassPtr + 1, grassBlob)
	else
		local extraEnd = extraPos
		local shift = 12
		local newGrassPtr = #smf + shift
		local ptrs = { 53, 57, 61, 65, 69, 73 }
		for i = 1, #ptrs do
			smf = splice(smf, ptrs[i], i32(ri32(smf, ptrs[i]) + shift))
		end
		local walk = 81
		for _ = 1, numExtra do
			if walk + 7 > #smf then
				break
			end
			local size = ri32(smf, walk)
			local typ = ri32(smf, walk + 4)
			if typ == 1 and walk + 11 <= #smf then
				smf = splice(smf, walk + 8, i32(ri32(smf, walk + 8) + shift))
			end
			if size < 8 then
				size = 8
			end
			walk = walk + size
		end
		smf = splice(smf, 77, i32(numExtra + 1))
		local extraHdr = u32(12) .. u32(1) .. u32(newGrassPtr)
		smf = smf:sub(1, extraEnd - 1) .. extraHdr .. smf:sub(extraEnd) .. grassBlob
	end

	local types = {}
	local typeIndex = {}
	local feats = {}
	local ids = Spring.GetAllFeatures() or {}
	for i = 1, #ids do
		local defID = Spring.GetFeatureDefID(ids[i])
		local def = defID and FeatureDefs[defID]
		local x, y, z = Spring.GetFeaturePosition(ids[i])
		if def and def.name and x then
			local name = def.name
			if not typeIndex[name] then
				types[#types + 1] = name
				typeIndex[name] = #types - 1
			end
			local heading = Spring.GetFeatureHeading(ids[i]) or 0
			if heading > 32767 then
				heading = heading - 65536
			end
			feats[#feats + 1] = {
				typ = typeIndex[name],
				x = x,
				y = y or 0,
				z = z,
				rot = heading,
			}
		end
	end
	local featParts = { i32(#types), i32(#feats) }
	for i = 1, #types do
		featParts[#featParts + 1] = types[i] .. "\0"
	end
	for i = 1, #feats do
		local f = feats[i]
		featParts[#featParts + 1] = i32(f.typ) .. f32(f.x) .. f32(f.y) .. f32(f.z) .. f32(f.rot) .. f32(1)
	end
	local featBlob = table.concat(featParts)
	local newFeatPtr = #smf
	smf = smf .. featBlob
	smf = splice(smf, 73, i32(newFeatPtr))
	smf = splice(smf, 21, u32(math.floor(os.time() % 2147483647)))
	return smf, minH, maxH
end

local SPAWN_GADGET = [=[
function gadget:GetInfo()
	return {
		name = "Map Editor Unit Spawns",
		desc = "Spawns buildings saved with a map from the in-game editor",
		author = "Uskrad Dragon",
		date = "2026-09",
		license = "GNU GPL, v2 or later",
		layer = -5000,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

function gadget:GameFrame(n)
	if n < 1 then
		return
	end
	gadgetHandler:RemoveGadget(self)
	if not VFS.FileExists("mapconfig/editor_units.lua", VFS.MAP) then
		return
	end
	local units = VFS.Include("mapconfig/editor_units.lua", nil, VFS.MAP)
	if type(units) ~= "table" then
		return
	end
	local gaia = Spring.GetGaiaTeamID()
	for i = 1, #units do
		local u = units[i]
		if u and u.def and u.x and u.z then
			local y = Spring.GetGroundHeight(u.x, u.z)
			Spring.CreateUnit(u.def, u.x, y, u.z, u.facing or 0, gaia)
		end
	end
end
]=]

local function writeStartboxes(dest)
	local chunks = { "-- Generated by BAR in-game map editor\nreturn {\n" }
	local allyCount = (Spring.GetAllyTeamCount and Spring.GetAllyTeamCount()) or 1
	for ally = 0, allyCount - 1 do
		local xmin, zmin, xmax, zmax = Spring.GetAllyTeamStartBox(ally)
		if xmin then
			local longName, shortName = boxName(xmin, zmin, xmax, zmax)
			local teams = Spring.GetTeamList(ally) or {}
			chunks[#chunks + 1] = string.format("\t[%d] = {\n", ally)
			chunks[#chunks + 1] = string.format("\t\tnameLong = %q,\n", longName)
			chunks[#chunks + 1] = string.format("\t\tnameShort = %q,\n", shortName)
			chunks[#chunks + 1] = "\t\tstartpoints = {\n"
			local any = false
			for t = 1, #teams do
				local px, _, pz = Spring.GetTeamStartPosition(teams[t])
				if px and px >= 0 then
					chunks[#chunks + 1] = string.format("\t\t\t{ %.1f, %.1f },\n", px, pz or 0)
					any = true
				end
			end
			if not any then
				chunks[#chunks + 1] = string.format("\t\t\t{ %.1f, %.1f },\n", (xmin + xmax) * 0.5, (zmin + zmax) * 0.5)
			end
			chunks[#chunks + 1] = "\t\t},\n\t\tboxes = {\n\t\t\t{\n"
			chunks[#chunks + 1] = string.format("\t\t\t\t{ %.1f, %.1f },\n", xmin, zmin)
			chunks[#chunks + 1] = string.format("\t\t\t\t{ %.1f, %.1f },\n", xmin, zmax)
			chunks[#chunks + 1] = string.format("\t\t\t\t{ %.1f, %.1f },\n", xmax, zmax)
			chunks[#chunks + 1] = string.format("\t\t\t\t{ %.1f, %.1f },\n", xmax, zmin)
			chunks[#chunks + 1] = "\t\t\t},\n\t\t},\n\t},\n"
		end
	end
	chunks[#chunks + 1] = "}\n"
	return writeText(dest .. "/mapconfig/map_startboxes.lua", table.concat(chunks))
end

local function writeUnits(dest)
	local list = { "-- Generated by BAR in-game map editor\nreturn {\n" }
	local playtest = (Spring.GetGameRulesParam("mapEditorPlaytest") or 0) > 0
	local ids = Spring.GetAllUnits() or {}
	local count = 0
	for i = 1, #ids do
		local defID = Spring.GetUnitDefID(ids[i])
		local def = defID and UnitDefs[defID]
		if def and def.name and not (playtest and isCommander(def)) then
			local x, _, z = Spring.GetUnitPosition(ids[i])
			if x then
				count = count + 1
				list[#list + 1] = string.format(
					"\t{ def = %q, x = %.1f, z = %.1f, facing = %d },\n",
					def.name,
					x,
					z,
					Spring.GetUnitBuildFacing(ids[i]) or 0
				)
			end
		end
	end
	list[#list + 1] = "}\n"
	writeText(dest .. "/mapconfig/editor_units.lua", table.concat(list))
	if count > 0 then
		writeText(dest .. "/luarules/gadgets/map_editor_spawns.lua", SPAWN_GADGET)
	end
end

local function applyLighting(info, minH, maxH, mapName)
	info = info or {}
	info.name = mapName
	info.shortname = mapName
	info.description = info.description or Game.mapDescription or ""
	if not tostring(info.description):find("BAR map editor", 1, true) then
		info.description = info.description .. " — saved from BAR map editor"
	end
	info.author = info.author or "Map Editor"
	local ver = tostring(info.version or "1")
	if not ver:find("edited", 1, true) then
		info.version = ver .. "-edited"
	else
		info.version = ver
	end
	info.smf = info.smf or {}
	info.smf.minheight = minH
	info.smf.maxheight = maxH
	local sx, sy, sz = gl.GetSun("pos")
	local ar, ag, ab = gl.GetSun("ambient")
	local dr, dg, db = gl.GetSun("diffuse")
	local shadow = gl.GetSun("shadowDensity") or 0.8
	info.lighting = info.lighting or {}
	info.lighting.sunDir = { sx or 0, sy or 1, sz or 0 }
	info.lighting.groundAmbientColor = { ar or 0.5, ag or 0.5, ab or 0.5 }
	info.lighting.groundDiffuseColor = { dr or 0.8, dg or 0.8, db or 0.8 }
	info.lighting.groundShadowDensity = shadow
	info.lighting.unitShadowDensity = shadow
	local fogS = gl.GetAtmosphere("fogStart") or 0
	local fogE = gl.GetAtmosphere("fogEnd") or 1
	local fogR, fogG, fogB = gl.GetAtmosphere("fogColor")
	info.atmosphere = info.atmosphere or {}
	info.atmosphere.fogStart = fogS
	info.atmosphere.fogEnd = fogE
	info.atmosphere.fogColor = { fogR or 0.7, fogG or 0.7, fogB or 0.8 }
	local water = (gl.GetWaterRendering and gl.GetWaterRendering("surfaceAlpha")) or 0.4
	info.water = info.water or {}
	info.water.surfaceAlpha = water
	local px, _, pz = Spring.GetTeamStartPosition(0)
	if px and px >= 0 then
		info.teams = info.teams or {}
		info.teams[0] = { startPos = { x = px, z = pz or 0 } }
	end
	return info
end

local function copySplat(dest, info)
	local dump = io.open("mapeditor_splat.tga", "rb")
	if not dump then
		return
	end
	local data = dump:read("*a")
	dump:close()
	if not data or #data < 18 then
		return
	end
	writeBytes(dest .. "/maps/editor_splat.tga", data)
	info.resources = info.resources or {}
	info.resources.splatDistrTex = "maps/editor_splat.tga"
end

local function mapArchiveFiles(files)
	if not VFS.GetArchiveContainingFile then
		return files
	end
	local archive = VFS.GetArchiveContainingFile("mapinfo.lua", VFS.MAP)
	if not archive then
		return files
	end
	local out = {}
	for i = 1, #files do
		local owner = VFS.GetArchiveContainingFile(files[i], VFS.MAP)
		if owner == archive then
			out[#out + 1] = files[i]
		end
	end
	if #out == 0 then
		return files
	end
	return out
end

local function sanitizeMapName(raw)
	if type(raw) ~= "string" then
		return nil
	end
	local name = raw
		:gsub("[%c%z;/\\:*?\"<>|]", " ")
		:gsub(",", " ")
		:gsub("%s+", " ")
		:gsub("^%s+", "")
		:gsub("%s+$", "")
	if name == "" or name == "." or name == ".." then
		return nil
	end
	if #name > 48 then
		name = name:sub(1, 48):gsub("%s+$", "")
	end
	return name
end

local function folderForName(mapName)
	return "maps/" .. mapName:gsub("[^%w%._%-]", "_") .. ".sdd"
end

local function destForCurrentMap()
	local base = tostring(Game.mapName or "map")
	local ours = base:find("%(edited%)$") or base:find("^Untitled")
	if ours then
		return base, folderForName(base)
	end
	return base .. " (edited)", "maps/" .. base:gsub("[^%w%._%-]", "_") .. "_edited.sdd"
end

local function uniqueMapName(wanted)
	wanted = sanitizeMapName(wanted)
	if not wanted then
		return nil
	end
	for i = 1, 99 do
		local name = (i == 1) and wanted or (wanted .. " " .. i)
		local folder = folderForName(name)
		local probe = io.open(folder .. "/mapinfo.lua", "r")
		if not probe then
			return name, folder
		end
		probe:close()
	end
	local stamp = tostring(os.time() % 10000)
	local name = wanted .. " " .. stamp
	return name, folderForName(name)
end

local function bxor(a, b)
	local bitlib = bit or bit32
	if bitlib and bitlib.bxor then
		return bitlib.bxor(a, b)
	end
	a = math.floor(tonumber(a) or 0)
	b = math.floor(tonumber(b) or 0)
	local r, p = 0, 1
	while a > 0 or b > 0 do
		local abit, bbit = a % 2, b % 2
		if abit ~= bbit then
			r = r + p
		end
		a = math.floor(a / 2)
		b = math.floor(b / 2)
		p = p * 2
	end
	return r
end

local crcTable
local function crc32(data)
	if not crcTable then
		crcTable = {}
		for i = 0, 255 do
			local c = i
			for _ = 1, 8 do
				if c % 2 == 1 then
					c = bxor(math.floor(c / 2), 3988292384)
				else
					c = math.floor(c / 2)
				end
			end
			crcTable[i] = c
		end
	end
	local crc = 4294967295
	for i = 1, #data do
		crc = bxor(crcTable[bxor(crc, string.byte(data, i)) % 256], math.floor(crc / 256))
	end
	return bxor(crc, 4294967295)
end

local function collectFolderFiles(folder)
	local out = {}
	local listed = {}
	if VFS and VFS.DirList then
		local ok, result = pcall(VFS.DirList, folder, "*", VFS.RAW, true)
		if not ok or type(result) ~= "table" or #result == 0 then
			ok, result = pcall(VFS.DirList, folder, "*", VFS.RAW)
		end
		if ok and type(result) == "table" then
			listed = result
		end
	end
	local prefix = folder .. "/"
	for i = 1, #listed do
		local p = normPath(listed[i])
		if p:sub(1, #prefix) == prefix then
			p = p:sub(#prefix + 1)
		elseif p:sub(1, #folder) == folder then
			p = p:sub(#folder + 2)
		end
		if p ~= "" and not p:lower():match("%.sd[7z]$") then
			out[#out + 1] = p
		end
	end
	if #out > 0 then
		return out
	end
	local function walk(rel)
		local here = rel == "" and folder or (folder .. "/" .. rel)
		local files = {}
		if VFS and VFS.DirList then
			local ok, result = pcall(VFS.DirList, here, "*", VFS.RAW)
			if ok and type(result) == "table" then
				files = result
			end
		end
		for i = 1, #files do
			local name = normPath(files[i]):match("[^/]+$")
			if name then
				out[#out + 1] = rel == "" and name or (rel .. "/" .. name)
			end
		end
		local dirs = {}
		if VFS and VFS.SubDirs then
			local ok, result = pcall(VFS.SubDirs, here, "*", VFS.RAW)
			if ok and type(result) == "table" then
				dirs = result
			end
		end
		for i = 1, #dirs do
			local name = normPath(dirs[i]):match("[^/]+$")
			if name then
				walk(rel == "" and name or (rel .. "/" .. name))
			end
		end
	end
	walk("")
	return out
end

local function writeZipStore(zipPath, folder, rels)
	local f = io.open(zipPath, "wb")
	if not f then
		return nil
	end
	local offset = 0
	local central = {}
	for i = 1, #rels do
		local inner = rels[i]:gsub("\\", "/")
		local blobFile = io.open(folder .. "/" .. inner, "rb")
		if blobFile then
			local data = blobFile:read("*a") or ""
			blobFile:close()
			local crc = crc32(data)
			local name = inner
			local localHeader = "PK\003\004"
				.. u16(20)
				.. u16(0)
				.. u16(0)
				.. u16(0)
				.. u16(0)
				.. u32(crc)
				.. u32(#data)
				.. u32(#data)
				.. u16(#name)
				.. u16(0)
				.. name
			f:write(localHeader)
			f:write(data)
			central[#central + 1] = {
				offset = offset,
				crc = crc,
				size = #data,
				name = name,
			}
			offset = offset + #localHeader + #data
		end
	end
	local cdStart = offset
	for i = 1, #central do
		local e = central[i]
		local cd = "PK\001\002"
			.. u16(20)
			.. u16(20)
			.. u16(0)
			.. u16(0)
			.. u16(0)
			.. u16(0)
			.. u32(e.crc)
			.. u32(e.size)
			.. u32(e.size)
			.. u16(#e.name)
			.. u16(0)
			.. u16(0)
			.. u16(0)
			.. u16(0)
			.. u32(0)
			.. u32(e.offset)
			.. e.name
		f:write(cd)
		offset = offset + #cd
	end
	f:write(
		"PK\005\006"
			.. u16(0)
			.. u16(0)
			.. u16(#central)
			.. u16(#central)
			.. u32(offset - cdStart)
			.. u32(cdStart)
			.. u16(0)
	)
	f:close()
	return zipPath
end

local function packWith7z(folder, mapName)
	local safe = mapName:gsub("[^%w%._%-]", "_")
	local sd7 = "maps/" .. safe .. ".sd7"
	local exe
	local candidates = {
		"C:/Program Files/7-Zip/7z.exe",
		"C:/Program Files (x86)/7-Zip/7z.exe",
	}
	for i = 1, #candidates do
		local probe = io.open(candidates[i], "r")
		if probe then
			probe:close()
			exe = candidates[i]
			break
		end
	end
	if not exe then
		return nil
	end
	local winFolder = folder:gsub("/", "\\")
	local cmd = string.format('cd /d "%s" & "%s" a -t7z -mx=5 -y "..\\%s" *', winFolder, exe, safe .. ".sd7")
	pcall(os.execute, cmd)
	local probe = io.open(sd7, "rb")
	if probe then
		local magic = probe:read(2)
		probe:close()
		if magic == "7z" then
			return sd7
		end
	end
	return nil
end

local function packMapArchive(folder, mapName)
	if not folder or not mapName then
		return nil
	end
	local packed = packWith7z(folder, mapName)
	if packed then
		return packed
	end
	local zipPath = "maps/" .. mapName:gsub("[^%w%._%-]", "_") .. ".sdz"
	if VFS and VFS.CompressFolder then
		local ok = pcall(VFS.CompressFolder, folder, "zip", zipPath, false)
		if not ok then
			ok = pcall(VFS.CompressFolder, folder, "zip", zipPath, false, VFS.RAW)
		end
		if ok then
			local probe = io.open(zipPath, "rb")
			if probe then
				probe:close()
				return zipPath
			end
		end
	end
	local rels = collectFolderFiles(folder)
	if #rels == 0 then
		Spring.Echo("Map Editor pack failed: no files in " .. folder)
		return nil
	end
	local stored = writeZipStore(zipPath, folder, rels)
	if stored then
		return stored
	end
	Spring.Echo("Map Editor pack failed")
	return nil
end

local function writeEditedMap(wantedName)
	if not io then
		return nil, "no io"
	end
	local files = mapArchiveFiles(listMapFiles())
	local smfRel = findSmf(files)
	if not smfRel then
		return nil, "no smf in map VFS"
	end
	local smfData = VFS.LoadFile(smfRel, VFS.MAP)
	if not smfData then
		return nil, "failed to load smf"
	end
	local patched, minH, maxH = patchSmf(smfData)
	if not patched then
		return nil, minH or "smf patch failed"
	end
	local mapName, folder
	local named = sanitizeMapName(wantedName)
	if named then
		mapName, folder = named, folderForName(named)
	else
		mapName, folder = destForCurrentMap()
	end
	ensureDirs(folder)
	for i = 1, #files do
		local rel = files[i]
		local lower = rel:lower()
		if lower ~= "mapinfo.lua" and lower ~= "mapconfig/map_startboxes.lua" and rel ~= smfRel and not lower:match("^luarules/") then
			local blob = VFS.LoadFile(rel, VFS.MAP)
			if blob then
				writeBytes(folder .. "/" .. rel, blob)
			end
		end
	end
	writeBytes(folder .. "/" .. smfRel, patched)
	local info = loadMapinfo()
	info = applyLighting(info, minH, maxH, mapName)
	copySplat(folder, info)
	writeText(folder .. "/mapinfo.lua", "-- Generated by BAR in-game map editor\nreturn " .. ser(info) .. "\n")
	writeStartboxes(folder)
	writeUnits(folder)
	writeText(
		folder .. "/README_EDITOR.txt",
		"Load this map from BAR (it appears as \"" .. mapName .. "\").\nOr set mapname in tools/StartScripts/startscript_map_editor.txt to:\n"
			.. mapName
			.. "\nPacked archive: maps/<name>.sd7 if 7-Zip is installed, otherwise maps/<name>.sdz (zip).\n"
	)
	local packed = packMapArchive(folder, mapName)
	return folder, mapName, packed
end

local TILE_COLORS = {
	{ 72, 118, 48 },
	{ 124, 88, 52 },
	{ 96, 96, 100 },
	{ 186, 158, 92 },
}

local function rgb565(r, g, b)
	local r5 = math.floor(r * 31 / 255 + 0.5)
	local g6 = math.floor(g * 63 / 255 + 0.5)
	local b5 = math.floor(b * 31 / 255 + 0.5)
	return r5 * 2048 + g6 * 32 + b5
end

local function dxt1Solid(r, g, b)
	local c0 = rgb565(r, g, b)
	local c1 = c0 > 0 and (c0 - 1) or 1
	if c0 < c1 then
		c0, c1 = c1, c0
	end
	return u16(c0) .. u16(c1) .. string.char(0, 0, 0, 0)
end

local function dxt1Fill(width, height, r, g, b)
	local block = dxt1Solid(r, g, b)
	return string.rep(block, math.ceil(width / 4) * math.ceil(height / 4))
end

local function dxt1MipChain(size, r, g, b)
	local parts = {}
	local s = size
	while s >= 4 do
		parts[#parts + 1] = dxt1Fill(s, s, r, g, b)
		s = math.floor(s / 2)
	end
	return table.concat(parts)
end

local function editorScript(mapName)
	local game = tostring(Game.gameName or "Beyond All Reason") .. " " .. tostring(Game.gameVersion or "$VERSION")
	return string.format(
		"[game]\n{\n\t[allyteam0] { numallies = 0; }\n\t[team0] { allyteam = 0; teamleader = 0; side = Armada; rgbcolor = 0.8 0.8 0.8; }\n\t[player0] { team = 0; name = MapEditor; }\n\t[modoptions] { map_editor = 1; ranked_game = 0; }\n\tgametype = %s;\n\tishost = 1;\n\tmapname = %s;\n\tmyplayername = MapEditor;\n\tnohelperais = 1;\n\tstartpostype = 0;\n}\n",
		game,
		mapName
	)
end

local function uniqueUntitled(smu)
	return uniqueMapName(string.format("Untitled %dx%d", smu, smu))
end

local function writeBlankMap(smu, wantedName)
	if not io then
		return nil, "no io"
	end
	smu = math.floor(tonumber(smu) or 16)
	if smu < 8 then
		smu = 8
	elseif smu > 32 then
		smu = 32
	end
	if smu % 2 ~= 0 then
		smu = smu + 1
	end
	local mapx = smu * 64
	local mapy = mapx
	local mapName, folder = uniqueMapName(wantedName)
	if not mapName then
		mapName, folder = uniqueUntitled(smu)
	end
	local safe = mapName:gsub("[^%w%._%-]", "_")
	local smtFile = safe .. ".smt"
	local minH, maxH = -40, 200
	local ground = 72
	local uGround = math.floor((ground - minH) * 65536 / (maxH - minH))
	local heightLen = (mapx + 1) * (mapy + 1) * 2
	local typeLen = (mapx / 2) * (mapy / 2)
	local metalLen = typeLen
	local grassLen = (mapx / 4) * (mapy / 4)
	local tileIndexCount = (mapx / 4) * (mapy / 4)
	local extraLen = 12
	local headerLen = 80
	local tileHeaderLen = 8 + 4 + #smtFile + 1
	local tileIndexLen = 4 * tileIndexCount
	local minimapLen = 699048
	local heightPtr = headerLen + extraLen
	local typePtr = heightPtr + heightLen
	local tilesPtr = typePtr + typeLen
	local minimapPtr = tilesPtr + tileHeaderLen + tileIndexLen
	local metalPtr = minimapPtr + minimapLen
	local grassPtr = metalPtr + metalLen
	local featurePtr = grassPtr + grassLen

	local hSample = u16(uGround)
	local heightBlob = string.rep(hSample, (mapx + 1) * (mapy + 1))
	local typeBlob = string.rep("\0", typeLen)
	local metalBlob = string.rep("\0", metalLen)
	local grassBlob = string.rep("\0", grassLen)
	local tileIndex = string.rep(u32(0), tileIndexCount)
	local tilesBlob = u32(1) .. u32(4) .. u32(4) .. smtFile .. "\0" .. tileIndex
	local minimapBlob = dxt1MipChain(1024, 72, 118, 48)
	if #minimapBlob < minimapLen then
		minimapBlob = minimapBlob .. string.rep("\0", minimapLen - #minimapBlob)
	elseif #minimapBlob > minimapLen then
		minimapBlob = minimapBlob:sub(1, minimapLen)
	end
	local header = "spring map file\0"
		.. i32(1)
		.. u32(math.floor(os.time() % 2147483647))
		.. i32(mapx)
		.. i32(mapy)
		.. i32(8)
		.. i32(8)
		.. i32(32)
		.. f32(minH)
		.. f32(maxH)
		.. i32(heightPtr)
		.. i32(typePtr)
		.. i32(tilesPtr)
		.. i32(minimapPtr)
		.. i32(metalPtr)
		.. i32(featurePtr)
		.. i32(1)
	local extra = u32(12) .. u32(1) .. u32(grassPtr)
	local features = i32(0) .. i32(0)
	local smf = header .. extra .. heightBlob .. typeBlob .. tilesBlob .. minimapBlob .. metalBlob .. grassBlob .. features

	local smtParts = { "spring tilefile\0", i32(1), i32(4), i32(32), i32(1) }
	for i = 1, 4 do
		local c = TILE_COLORS[i]
		smtParts[#smtParts + 1] = dxt1MipChain(32, c[1], c[2], c[3])
	end
	local smt = table.concat(smtParts)

	ensureDirs(folder .. "/maps")
	ensureDirs(folder .. "/mapconfig")
	writeBytes(folder .. "/maps/" .. safe .. ".smf", smf)
	writeBytes(folder .. "/maps/" .. smtFile, smt)

	local world = mapx * 8
	local info = {
		name = mapName,
		shortname = mapName:gsub("%s+", ""):sub(1, 16),
		description = "Created in the BAR map editor",
		author = "Map Editor",
		version = "1",
		modtype = 3,
		maphardness = 100,
		gravity = 130,
		tidalstrength = 0,
		maxmetal = 1,
		extractorRadius = 90,
		voidwater = false,
		notdeformable = false,
		smf = {
			minheight = minH,
			maxheight = maxH,
		},
		atmosphere = {
			minWind = 5,
			maxWind = 25,
			fogStart = 0.1,
			fogEnd = 1.0,
			fogColor = { 0.70, 0.72, 0.80 },
			skyColor = { 0.35, 0.50, 0.75 },
		},
		lighting = {
			sunDir = { 0.35, 0.85, 0.35 },
			groundAmbientColor = { 0.42, 0.42, 0.42 },
			groundDiffuseColor = { 0.82, 0.82, 0.78 },
			groundShadowDensity = 0.8,
			unitAmbientColor = { 0.45, 0.45, 0.45 },
			unitDiffuseColor = { 0.85, 0.85, 0.85 },
			unitShadowDensity = 0.8,
		},
		water = {
			surfaceAlpha = 0.35,
			damage = 0,
		},
		teams = {
			[0] = { startPos = { x = world * 0.2, z = world * 0.5 } },
			[1] = { startPos = { x = world * 0.8, z = world * 0.5 } },
		},
	}
	writeText(folder .. "/mapinfo.lua", "-- Created by BAR in-game map editor\nreturn " .. ser(info) .. "\n")
	writeText(
		folder .. "/mapconfig/map_startboxes.lua",
		string.format(
			"-- Created by BAR in-game map editor\nreturn {\n\t[0] = {\n\t\tnameLong = \"West\",\n\t\tnameShort = \"W\",\n\t\tstartpoints = { { %.1f, %.1f } },\n\t\tboxes = { { { 0, 0 }, { 0, %.1f }, { %.1f, %.1f }, { %.1f, 0 } } },\n\t},\n\t[1] = {\n\t\tnameLong = \"East\",\n\t\tnameShort = \"E\",\n\t\tstartpoints = { { %.1f, %.1f } },\n\t\tboxes = { { { %.1f, 0 }, { %.1f, %.1f }, { %.1f, %.1f }, { %.1f, 0 } } },\n\t},\n}\n",
			world * 0.2,
			world * 0.5,
			world,
			world * 0.45,
			world,
			world * 0.45,
			world * 0.8,
			world * 0.5,
			world * 0.55,
			world * 0.55,
			world,
			world,
			world,
			world
		)
	)
	return folder, mapName, editorScript(mapName)
end

return {
	writeEditedMap = writeEditedMap,
	writeBlankMap = writeBlankMap,
	editorScript = editorScript,
	sanitizeMapName = sanitizeMapName,
	packMapArchive = packMapArchive,
}

