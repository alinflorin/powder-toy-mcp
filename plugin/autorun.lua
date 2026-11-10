-- Powder Toy MCP plugin (LuaJIT / Lua 5.1 semantics).
-- Connects over TCP to the MCP server and executes commands from an event tick hook.
-- Protocol: server -> "<id> <command>\n"; plugin -> "<id> <ok|err> <text|png> <base64>\n"

local HOST, PORT = "127.0.0.1", 8787
local RECONNECT_TICKS = 120

local bit = bit
local floor = math.floor

local function log(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	print("[pt-mcp] " .. table.concat(t, " "))
end

---------------------------------------------------------------- base64
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64c = {}
for i = 1, 64 do b64c[i - 1] = B64:sub(i, i) end

local function b64(s)
	local out, n = {}, #s
	for i = 1, n - 2, 3 do
		local a, b, c = s:byte(i, i + 2)
		local v = a * 65536 + b * 256 + c
		out[#out + 1] = b64c[floor(v / 262144)] .. b64c[floor(v / 4096) % 64] .. b64c[floor(v / 64) % 64] .. b64c[v % 64]
	end
	local r = n % 3
	if r == 1 then
		local a = s:byte(n)
		local v = a * 65536
		out[#out + 1] = b64c[floor(v / 262144)] .. b64c[floor(v / 4096) % 64] .. "=="
	elseif r == 2 then
		local a, b = s:byte(n - 1, n)
		local v = a * 65536 + b * 256
		out[#out + 1] = b64c[floor(v / 262144)] .. b64c[floor(v / 4096) % 64] .. b64c[floor(v / 64) % 64] .. "="
	end
	return table.concat(out)
end

---------------------------------------------------------------- helpers
local XRES = sim.XRES or 612
local YRES = sim.YRES or 384

local function errorf(fmt, ...) error(string.format(fmt, ...), 0) end

-- element name -> id map (lazy)
local nameMap, idName
local function buildNames()
	nameMap, idName = {}, {}
	for id = 0, 511 do
		local ok, exists = pcall(elem.exists, id)
		if ok and exists then
			local okn, name = pcall(elem.property, id, "Name")
			if okn and name and name ~= "" then
				nameMap[name:lower()] = id
				idName[id] = name
			end
		end
	end
end

local function elemId(s)
	if not nameMap then buildNames() end
	if s == nil then errorf("missing element") end
	local n = tonumber(s)
	if n then
		if idName[n] then return n end
		errorf("unknown element id %s", s)
	end
	local id = nameMap[tostring(s):lower()] or nameMap[(tostring(s):lower():gsub("^dmnd$", "dmnd"))]
	if not id then errorf("unknown element '%s' (try: elements)", s) end
	return id
end

local function num(s, name, lo, hi)
	local n = tonumber(s)
	if not n then errorf("expected number for %s, got '%s'", name, tostring(s)) end
	n = floor(n)
	if lo and (n < lo or n > hi) then errorf("%s=%d out of range %d..%d", name, n, lo, hi) end
	return n
end
local function X(s, name) return num(s, name or "x", 0, XRES - 1) end
local function Y(s, name) return num(s, name or "y", 0, YRES - 1) end

local function onoff(s)
	s = tostring(s):lower()
	if s == "on" or s == "1" or s == "true" then return true end
	if s == "off" or s == "0" or s == "false" then return false end
	errorf("expected on|off, got '%s'", s)
end

local function enum(s, names)
	s = tostring(s):lower()
	for i, n in ipairs(names) do
		if n == s then return i - 1 end
	end
	local n = tonumber(s)
	if n and n >= 0 and n < #names then return floor(n) end
	errorf("expected one of %s", table.concat(names, "|"))
end

-- walls: id <-> name, built from sim.walls (entries like [8] = "DEFAULT_WL_WALL")
local wallNames, wallById
local WALL_ALIAS = {
	conductivewall = 1, ewall = 2, electricwall = 2, detector = 3, detect = 3, stream = 4, strm = 4, fan = 5,
	liquid = 6, liquidwall = 6, absorb = 7, wall = 8, air = 9, allowair = 9, powder = 10, conductor = 11,
	ehole = 12, gas = 13, gravity = 14, energy = 15, noair = 16, eraseall = 17, stasis = 18, eraser = 0,
}
local function buildWalls()
	wallNames, wallById = {}, {}
	for k, v in pairs(sim.walls or {}) do
		if type(k) == "number" and type(v) == "string" then
			local n = v:gsub("^DEFAULT_WL_", "")
			wallById[k] = n
			wallNames[n:lower()] = k
		end
	end
	for n, id in pairs(WALL_ALIAS) do
		if not wallNames[n] then wallNames[n] = id end
	end
end

local function wallId(s)
	if not wallNames then buildWalls() end
	local n = tonumber(s)
	if n then return floor(n) end
	local id = wallNames[tostring(s):lower():gsub("^default_wl_", "")]
	if id then return id end
	errorf("unknown wall '%s' (try: walls)", tostring(s))
end

local WALL_COLOR = {
	[1] = { 150, 150, 40 }, [2] = { 40, 160, 40 }, [3] = { 200, 120, 40 }, [4] = { 40, 120, 200 },
	[5] = { 120, 120, 220 }, [6] = { 60, 60, 200 }, [7] = { 200, 60, 200 }, [8] = { 120, 120, 120 },
	[9] = { 60, 60, 60 }, [10] = { 160, 140, 90 }, [11] = { 160, 160, 60 }, [12] = { 200, 40, 40 },
	[13] = { 150, 200, 200 }, [14] = { 90, 90, 160 }, [15] = { 200, 200, 90 }, [16] = { 80, 80, 80 },
	[18] = { 130, 90, 200 },
}

-- wall at pixel coordinates (wall map is 4x4-pixel cells)
local function wallAt(x, y)
	local ok, w = pcall(sim.wallMap, floor(x / 4), floor(y / 4))
	if ok then return w or 0 end
	return 0
end

local function prop(id, name)
	local ok, v = pcall(sim.partProperty, id, name)
	if ok then return v end
end

local function takeFlag(a, flag)
	for i = #a, 1, -1 do
		if a[i] == flag then table.remove(a, i); return true end
	end
	return false
end

local function box(a, i, names)
	local x1, y1, x2, y2 = X(a[i], "x1"), Y(a[i + 1], "y1"), X(a[i + 2], "x2"), Y(a[i + 3], "y2")
	return math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2)
end

-- iterate over particle ids (snapshot, so callers may kill/modify) with integer positions
local function particles(pred)
	local ids = {}
	for id in sim.parts() do
		local x, y = prop(id, "x"), prop(id, "y")
		if x and y then
			x, y = floor(x + 0.5), floor(y + 0.5)
			if not pred or pred(x, y, id) then ids[#ids + 1] = id end
		end
	end
	return ids
end

local function inBox(lx, ly, hx, hy)
	return function(x, y) return x >= lx and x <= hx and y >= ly and y <= hy end
end

-- aggregate stats over a box: per-element counts, temperature and pressure
local function stats(lx, ly, hx, hy)
	local s = { counts = {}, total = 0, tsum = 0, tmax = nil, tmin = nil, pmax = nil, pmin = nil, psum = 0, pn = 0 }
	for _, id in ipairs(particles(inBox(lx, ly, hx, hy))) do
		local t = prop(id, "type")
		s.counts[t] = (s.counts[t] or 0) + 1
		s.total = s.total + 1
		local T = prop(id, "temp")
		if T then
			s.tsum = s.tsum + T
			if not s.tmax or T > s.tmax then s.tmax = T end
			if not s.tmin or T < s.tmin then s.tmin = T end
		end
	end
	for cy = floor(ly / 4), floor(hy / 4) do
		for cx = floor(lx / 4), floor(hx / 4) do
			local ok, p = pcall(sim.pressure, cx, cy)
			if ok and p then
				s.psum, s.pn = s.psum + p, s.pn + 1
				if not s.pmax or p > s.pmax then s.pmax = p end
				if not s.pmin or p < s.pmin then s.pmin = p end
			end
		end
	end
	return s
end

---------------------------------------------------------------- environment
local GRAV = { "vertical", "off", "radial" }
local AIR = { "on", "pressure_off", "velocity_off", "off", "no_update" }
local EDGE = { "void", "solid", "loop" }

local function getset(key, ...)
	local v = sim[key]
	if select("#", ...) > 0 then
		if type(v) == "function" then v(...) else sim[key] = ... end
	else
		if type(v) == "function" then return v() end
		return v
	end
end

local ENV = {
	gravity = { function(v) if v then getset("gravityMode", enum(v, GRAV)) else return GRAV[getset("gravityMode") + 1] end end },
	air = { function(v) if v then getset("airMode", enum(v, AIR)) else return AIR[getset("airMode") + 1] end end },
	edge = { function(v) if v then getset("edgeMode", enum(v, EDGE)) else return EDGE[getset("edgeMode") + 1] end end },
	ambient = { function(v)
		if v then
			getset("ambientAirTemp", num(v, "kelvin", 0, 10000) + 0.0)
		else return getset("ambientAirTemp") end
	end },
	heat = { function(v) if v then getset("ambientHeatSim", onoff(v)) else return getset("ambientHeatSim") end end },
	newtonian = { function(v) if v then getset("newtonianGravity", onoff(v)) else return getset("newtonianGravity") end end },
}
local ENV_ORDER = { "gravity", "air", "edge", "ambient", "heat", "newtonian" }

---------------------------------------------------------------- rendering
local function elemColor(t)
	local c = elem.property(t, "Color")
	return c or 0xFFFFFF
end

local function render(scale, x1, y1, x2, y2)
	local colorCache = {}
	local w, h = x2 - x1 + 1, y2 - y1 + 1
	local BLACK = "\0\0\0"
	local grid = {} -- (y - y1) * w + (x - x1) -> 3-byte pixel string
	-- walls: sample once per 4x4 wall cell (sim.wallMap takes cell coordinates)
	local wallPx = {}
	for cy = floor(y1 / 4) * 4, y2, 4 do
		for cx = floor(x1 / 4) * 4, x2, 4 do
			local wl = wallAt(cx, cy)
			if wl ~= 0 then
				local px = wallPx[wl]
				if not px then
					local c = WALL_COLOR[wl] or { 100, 100, 140 }
					px = string.char(c[1], c[2], c[3]); wallPx[wl] = px
				end
				for py = math.max(cy, y1), math.min(cy + 3, y2) do
					for pxx = math.max(cx, x1), math.min(cx + 3, x2) do grid[(py - y1) * w + (pxx - x1)] = px end
				end
			end
		end
	end
	-- particles: iterate existing particles only (O(particles), not O(pixels))
	for id in sim.parts() do
		local x, y = prop(id, "x"), prop(id, "y")
		if x and y then
			x, y = floor(x + 0.5), floor(y + 0.5)
			if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
				local t = prop(id, "type")
				if t and t ~= 0 then
					local deco = prop(id, "dcolour") or 0
					local da = floor(deco / 16777216) % 256
					local c = colorCache[t]
					if not c then c = elemColor(t); colorCache[t] = c end
					local r, g, b = floor(c / 65536) % 256, floor(c / 256) % 256, c % 256
					if da > 0 then
						local dr, dg, db = floor(deco / 65536) % 256, floor(deco / 256) % 256, deco % 256
						r = floor((r * (255 - da) + dr * da) / 255)
						g = floor((g * (255 - da) + dg * da) / 255)
						b = floor((b * (255 - da) + db * da) / 255)
					end
					grid[(y - y1) * w + (x - x1)] = string.char(r, g, b)
				end
			end
		end
	end
	-- raw RGB; the MCP server scales and PNG-encodes it (keeps the game thread fast)
	local rows = { string.char(floor(w / 256), w % 256, floor(h / 256), h % 256, scale) }
	for y = 0, h - 1 do
		local line = {}
		local base = y * w
		for x = 0, w - 1 do line[x + 1] = grid[base + x] or BLACK end
		rows[#rows + 1] = table.concat(line)
	end
	return table.concat(rows)
end

---------------------------------------------------------------- commands
local C = {}
local execute_line -- forward declaration (assigned after execute is defined)

local function particleCount()
	if sim.partCount then
		local ok, n = pcall(sim.partCount)
		if ok and n then return n end
	end
	if tpt and tpt.get_numOfParts then return tpt.get_numOfParts() end
	local n = 0
	if sim.parts then for _ in sim.parts() do n = n + 1 end end
	return n
end

function C.ping() return "pong" end

function C.play() sim.paused(false); return "running" end
function C.pause() sim.paused(true); return "paused" end

function C.step(a)
	local n = a[1] and num(a[1], "n", 1, 10000) or 1
	sim.paused(true)
	if sim.framerender then
		sim.framerender(n)
	elseif tpt and tpt.set_pause then
		errorf("sim.framerender unavailable")
	end
	return string.format("stepped %d frame(s); paused; particles=%s", n, tostring(particleCount()))
end

-- watch <frames> <every> [x1 y1 x2 y2]: step and print a stats line every <every> frames
function C.watch(a)
	local frames = num(a[1], "frames", 1, 100000)
	local every = a[2] and num(a[2], "every", 1, 100000) or math.max(1, floor(frames / 10))
	local lx, ly, hx, hy = 0, 0, XRES - 1, YRES - 1
	if a[3] then lx, ly, hx, hy = box(a, 3) end
	if not idName then buildNames() end
	sim.paused(true)
	local out, done = {}, 0
	while done < frames do
		local n = math.min(every, frames - done)
		sim.framerender(n)
		done = done + n
		local s = stats(lx, ly, hx, hy)
		local parts = {}
		for t, c in pairs(s.counts) do parts[#parts + 1] = { idName[t] or tostring(t), c } end
		table.sort(parts, function(p, q) return p[2] > q[2] end)
		local els = {}
		for i = 1, math.min(6, #parts) do els[#els + 1] = parts[i][1] .. "=" .. parts[i][2] end
		out[#out + 1] = string.format("f+%d total=%d Tmax=%s Pmax=%s %s", done, s.total,
			s.tmax and string.format("%.0f", s.tmax) or "-", s.pmax and string.format("%.1f", s.pmax) or "-", table.concat(els, " "))
	end
	return table.concat(out, "\n") .. "\n(paused)"
end

function C.undo() sim.historyRestore(); return "ok" end
function C.redo() sim.historyForward(); return "ok" end
function C.snapshot() sim.takeSnapshot(); return "snapshot taken (use undo to restore)" end

function C.batch(_, raw)
	local body = raw:gsub("^%s*batch%s*", "")
	local out = {}
	for cmd in (body .. ";"):gmatch("([^;]*);") do
		if cmd:match("%S") then
			local ok, res = execute_line(cmd)
			out[#out + 1] = "> " .. cmd:gsub("^%s+", "") .. "\n" .. tostring(res)
			if not ok then error(table.concat(out, "\n"), 0) end
		end
	end
	return table.concat(out, "\n")
end

function C.clear()
	if sim.clearSim then sim.clearSim() else tpt.reset_velocity() end
	return "cleared"
end

function C.draw(a)
	local replace = takeFlag(a, "--replace")
	local kind = a[1]
	if kind == "pixel" then
		local t, x, y = elemId(a[2]), X(a[3]), Y(a[4])
		if replace then for _, id in ipairs(particles(inBox(x, y, x, y))) do sim.partKill(id) end end
		sim.createParts(x, y, 0, 0, t)
		return "ok"
	elseif kind == "line" then
		local t = elemId(a[2])
		local rx, ry = a[7] and num(a[7], "rx", 0, 100) or 0, a[8] and num(a[8], "ry", 0, 100) or 0
		sim.createLine(X(a[3], "x1"), Y(a[4], "y1"), X(a[5], "x2"), Y(a[6], "y2"), rx, ry, t)
		return "ok"
	elseif kind == "rect" then
		local t = elemId(a[2])
		local lx, ly, hx, hy = box(a, 3)
		if replace then for _, id in ipairs(particles(inBox(lx, ly, hx, hy))) do sim.partKill(id) end end
		sim.createBox(lx, ly, hx, hy, t)
		return "ok"
	elseif kind == "circle" then
		local t, x, y, r = elemId(a[2]), X(a[3]), Y(a[4]), num(a[5], "r", 0, 200)
		if replace then
			for _, id in ipairs(particles(function(px, py) return (px - x) ^ 2 + (py - y) ^ 2 <= r * r + r end)) do sim.partKill(id) end
		end
		sim.createParts(x, y, r, r, t, sim.BRUSH_CIRCLE or 0)
		return "ok"
	elseif kind == "fill" then
		local t, x, y = elemId(a[2]), X(a[3]), Y(a[4])
		local n = sim.floodParts(x, y, t)
		return string.format("filled %s particles", tostring(n))
	elseif kind == "wall" then
		local w = wallId(a[2])
		local lx, ly, hx, hy = box(a, 3)
		sim.createWallBox(lx, ly, hx, hy, w)
		return "ok"
	elseif kind == "hollow" then
		-- hollow rectangle outline: draw hollow <elem> <x1> <y1> <x2> <y2> [thickness]
		local t = elemId(a[2])
		local lx, ly, hx, hy = box(a, 3)
		local th = a[7] and num(a[7], "thickness", 1, 100) or 1
		sim.createBox(lx, ly, hx, ly + th - 1, t)
		sim.createBox(lx, hy - th + 1, hx, hy, t)
		sim.createBox(lx, ly, lx + th - 1, hy, t)
		sim.createBox(hx - th + 1, ly, hx, hy, t)
		return "ok"
	elseif kind == "tank" then
		-- walled container: draw tank <wallname|id> <x1> <y1> <x2> <y2> [thickness]
		local w = wallId(a[2])
		local lx, ly, hx, hy = box(a, 3)
		local th = a[7] and num(a[7], "thickness", 1, 100) or 4
		sim.createWallBox(lx, ly, hx, ly + th - 1, w)
		sim.createWallBox(lx, hy - th + 1, hx, hy, w)
		sim.createWallBox(lx, ly, lx + th - 1, hy, w)
		sim.createWallBox(hx - th + 1, ly, hx, hy, w)
		return string.format("ok (inside: %d %d %d %d)", lx + th, ly + th, hx - th, hy - th)
	end
	errorf("usage: draw pixel|line|rect|circle|fill|wall|hollow|tank ... [--replace]")
end

-- erase [particles|walls] <x1> <y1> <x2> <y2>
function C.erase(a)
	local what = "both"
	if a[1] == "particles" or a[1] == "walls" then what = table.remove(a, 1) end
	local lx, ly, hx, hy = box(a, 1)
	if what ~= "walls" then sim.createBox(lx, ly, hx, hy, 0) end
	if what ~= "particles" then pcall(sim.createWallBox, lx, ly, hx, hy, 0) end
	return "ok"
end

function C.walls()
	if not wallNames then buildWalls() end
	local ids = {}
	for id in pairs(wallById) do ids[#ids + 1] = id end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do out[#out + 1] = id .. "=" .. wallById[id] end
	return table.concat(out, " ") .. "\n(also accepted: WALL STREAM ERASEALL ... and ids; plain solid wall = 8)"
end

function C.elements()
	if not nameMap then buildNames() end
	local ids = {}
	for id in pairs(idName) do ids[#ids + 1] = id end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do out[#out + 1] = id .. "=" .. idName[id] end
	return table.concat(out, " ")
end

local PROPS = { "type", "life", "ctype", "x", "y", "vx", "vy", "temp", "tmp", "tmp2", "tmp3", "tmp4", "dcolour", "flags" }

function C.get(a)
	local what = a[1]
	if what == "element" then
		local t = elemId(a[2])
		local keys = { "Name", "Description", "Colour", "Color", "MenuSection", "Weight", "Temperature", "HeatConduct",
			"Gravity", "Flammability", "Explosive", "Meltable", "Hardness", "Falldown", "State", "Properties", "Loss", "Advection", "AirDrag", "AirLoss", "Diffusion", "Enabled" }
		local out = { "id=" .. t }
		for _, k in ipairs(keys) do
			local ok, v = pcall(elem.property, t, k)
			if ok and v ~= nil then out[#out + 1] = k .. "=" .. tostring(v) end
		end
		return table.concat(out, "\n")
	elseif what == "particle" then
		local x, y = X(a[2]), Y(a[3])
		local id = sim.partID(x, y)
		if not id then return "no particle at " .. x .. "," .. y end
		if not idName then buildNames() end
		local out = { "index=" .. id }
		for _, k in ipairs(PROPS) do
			local v = prop(id, k)
			if k == "type" then v = tostring(v) .. " (" .. tostring(idName[v] or "?") .. ")" end
			out[#out + 1] = k .. "=" .. tostring(v)
		end
		local wl = wallAt(x, y)
		if wl ~= 0 then out[#out + 1] = "wall=" .. wl .. " (" .. tostring(wallById and wallById[wl] or "?") .. ")" end
		return table.concat(out, "\n")
	elseif what == "wall" then
		local x, y = X(a[2]), Y(a[3])
		if not wallNames then buildWalls() end
		local wl = wallAt(x, y)
		return string.format("wall=%d (%s)", wl, wl == 0 and "none" or tostring(wallById[wl] or "?"))
	elseif what == "cell" then
		-- air/wall info for the 4x4 cell containing x,y
		local x, y = X(a[2]), Y(a[3])
		local cx, cy = floor(x / 4), floor(y / 4)
		if not wallNames then buildWalls() end
		local wl = wallAt(x, y)
		local out = { string.format("cell=%d,%d", cx, cy), string.format("wall=%d (%s)", wl, wl == 0 and "none" or tostring(wallById[wl] or "?")) }
		local okp, p = pcall(sim.pressure, cx, cy)
		if okp then out[#out + 1] = "pressure=" .. tostring(p) end
		local okx, vx = pcall(sim.velocityX, cx, cy)
		local oky, vy = pcall(sim.velocityY, cx, cy)
		if okx and oky then out[#out + 1] = "velocity=" .. tostring(vx) .. "," .. tostring(vy) end
		local oka, at = pcall(sim.ambientHeat, cx, cy)
		if oka and at then out[#out + 1] = "ambient_temp=" .. tostring(at) end
		return table.concat(out, "\n")
	elseif what == "area" then
		local lx, ly, hx, hy = box(a, 2)
		if not idName then buildNames() end
		local s = stats(lx, ly, hx, hy)
		local out = { "total=" .. s.total }
		if s.tmax then
			out[#out + 1] = string.format("temp_K avg=%.1f min=%.1f max=%.1f (avg %.1fC)", s.tsum / s.total, s.tmin, s.tmax, s.tsum / s.total - 273.15)
		end
		if s.pn > 0 then
			out[#out + 1] = string.format("pressure avg=%.2f min=%.2f max=%.2f", s.psum / s.pn, s.pmin, s.pmax)
		end
		for t, n in pairs(s.counts) do out[#out + 1] = (idName[t] or tostring(t)) .. "=" .. n end
		return table.concat(out, "\n")
	end
	errorf("usage: get element|particle|wall|cell|area ...")
end

-- count [elem]: particles of one element (or all) on the whole screen
function C.count(a)
	if not idName then buildNames() end
	if not a[1] then return tostring(particleCount()) end
	local t = elemId(a[1])
	local n = 0
	for _, id in ipairs(particles()) do if prop(id, "type") == t then n = n + 1 end end
	return string.format("%s=%d", idName[t], n)
end

-- find <elem> [x1 y1 x2 y2]: count, bounding box and a few sample positions
function C.find(a)
	local t = elemId(a[1])
	local lx, ly, hx, hy = 0, 0, XRES - 1, YRES - 1
	if a[2] then lx, ly, hx, hy = box(a, 2) end
	local n, bx1, by1, bx2, by2, samples = 0, 1e9, 1e9, -1, -1, {}
	for _, id in ipairs(particles(inBox(lx, ly, hx, hy))) do
		if prop(id, "type") == t then
			local x, y = floor(prop(id, "x") + 0.5), floor(prop(id, "y") + 0.5)
			n = n + 1
			bx1, by1, bx2, by2 = math.min(bx1, x), math.min(by1, y), math.max(bx2, x), math.max(by2, y)
			if n <= 8 then samples[#samples + 1] = x .. "," .. y end
		end
	end
	if n == 0 then return "none found" end
	return string.format("count=%d bbox=%d %d %d %d samples=%s", n, bx1, by1, bx2, by2, table.concat(samples, " "))
end

-- replace <from> <to> [x1 y1 x2 y2]: change element type of matching particles
function C.replace(a)
	local from, to = elemId(a[1]), elemId(a[2])
	local lx, ly, hx, hy = 0, 0, XRES - 1, YRES - 1
	if a[3] then lx, ly, hx, hy = box(a, 3) end
	local n = 0
	for _, id in ipairs(particles(inBox(lx, ly, hx, hy))) do
		if prop(id, "type") == from then sim.partChangeType(id, to); n = n + 1 end
	end
	return "replaced " .. n
end

local SETTABLE = { temp = true, life = true, ctype = true, tmp = true, tmp2 = true, tmp3 = true, tmp4 = true, vx = true, vy = true, dcolour = true }
local function propValue(key, v)
	if key == "temp" then
		local s = tostring(v)
		local c = s:match("^(-?[%d%.]+)[Cc]$")
		if c then return tonumber(c) + 273.15 end
		local k = tonumber((s:gsub("[Kk]$", "")))
		if not k then errorf("bad temperature '%s' (kelvin, or e.g. 25C)", s) end
		return k
	elseif key == "ctype" then
		local n = tonumber(v)
		if n then return n end
		return elemId(v)
	end
	local n = tonumber(v)
	if not n then errorf("expected number for %s", key) end
	return n
end

-- set particle <x> <y> <prop> <value>
-- set area <x1> <y1> <x2> <y2> <prop> <value> [elem]
function C.set(a)
	if a[1] == "particle" then
		local x, y, key = X(a[2]), Y(a[3]), a[4]
		if not SETTABLE[key] then errorf("settable props: temp life ctype tmp tmp2 tmp3 tmp4 vx vy dcolour") end
		local id = sim.partID(x, y)
		if not id then errorf("no particle at %d,%d", x, y) end
		sim.partProperty(id, key, propValue(key, a[5]))
		return key .. "=" .. tostring(prop(id, key))
	elseif a[1] == "area" then
		local lx, ly, hx, hy = box(a, 2)
		local key = a[6]
		if not SETTABLE[key or ""] then errorf("settable props: temp life ctype tmp tmp2 tmp3 tmp4 vx vy dcolour") end
		local v = propValue(key, a[7])
		local only = a[8] and elemId(a[8])
		local n = 0
		for _, id in ipairs(particles(inBox(lx, ly, hx, hy))) do
			if not only or prop(id, "type") == only then sim.partProperty(id, key, v); n = n + 1 end
		end
		return string.format("set %s=%s on %d particle(s)", key, tostring(v), n)
	end
	errorf("usage: set particle <x> <y> <prop> <value> | set area <x1> <y1> <x2> <y2> <prop> <value> [elem]")
end

-- stamps: stamp save <x1> <y1> <x2> <y2> | stamp load <name> <x> <y> | stamp list
function C.stamp(a)
	if a[1] == "save" then
		local lx, ly, hx, hy = box(a, 2)
		local name = sim.saveStamp(lx, ly, hx - lx + 1, hy - ly + 1)
		return "saved stamp " .. tostring(name)
	elseif a[1] == "load" then
		if not a[2] then errorf("missing stamp name") end
		sim.loadStamp(a[2], X(a[3]), Y(a[4]))
		return "ok"
	elseif a[1] == "list" then
		local l = sim.listStamps and sim.listStamps() or {}
		return #l > 0 and table.concat(l, " ") or "no stamps"
	end
	errorf("usage: stamp save <x1> <y1> <x2> <y2> | stamp load <name> <x> <y> | stamp list")
end

local function envLines()
	local out = {}
	for _, k in ipairs(ENV_ORDER) do
		local ok, v = pcall(ENV[k][1])
		out[#out + 1] = k .. "=" .. (ok and tostring(v) or ("? (" .. tostring(v) .. ")"))
	end
	return out
end

function C.info()
	local out = {
		"paused=" .. tostring(sim.paused()),
		"particles=" .. tostring(particleCount()),
	}
	local okf, fr = pcall(function() return sim.frameCount and sim.frameCount() or tpt.get_property and nil end)
	if okf and fr then out[#out + 1] = "frame=" .. tostring(fr) end
	for _, l in ipairs(envLines()) do out[#out + 1] = l end
	local s = stats(0, 0, XRES - 1, YRES - 1)
	if s.tmax then out[#out + 1] = string.format("temp_K avg=%.1f min=%.1f max=%.1f", s.tsum / s.total, s.tmin, s.tmax) end
	if s.pn > 0 then out[#out + 1] = string.format("pressure avg=%.2f min=%.2f max=%.2f", s.psum / s.pn, s.pmin, s.pmax) end
	return table.concat(out, "\n")
end

function C.env(a)
	if not a[1] then return table.concat(envLines(), "\n") end
	if a[1] == "set" then
		local e = ENV[a[2] or ""]
		if not e then errorf("unknown env key '%s' (keys: %s)", tostring(a[2]), table.concat(ENV_ORDER, ", ")) end
		if a[3] == nil then errorf("missing value") end
		e[1](a[3])
		return a[2] .. "=" .. tostring(e[1]())
	elseif a[1] == "reset" then
		if a[2] == "pressure" then sim.resetPressure()
		elseif a[2] == "temp" then sim.resetTemp()
		else errorf("usage: env reset pressure|temp") end
		return "ok"
	end
	errorf("usage: env | env set <key> <value> | env reset pressure|temp")
end

function C.screenshot(a)
	local scale = a[1] and num(a[1], "scale", 1, 4) or 1
	local x1, y1, x2, y2 = 0, 0, XRES - 1, YRES - 1
	if a[2] then
		x1, y1, x2, y2 = X(a[2], "x1"), Y(a[3], "y1"), X(a[4], "x2"), Y(a[5], "y2")
		x1, x2 = math.min(x1, x2), math.max(x1, x2)
		y1, y2 = math.min(y1, y2), math.max(y1, y2)
	end
	return render(scale, x1, y1, x2, y2), "rgb"
end

function C.lua(_, raw)
	local code = raw:gsub("^%s*lua%s+", "")
	local f, err = loadstring("return " .. code)
	if not f then f, err = loadstring(code) end
	if not f then errorf("%s", err) end
	local r = { pcall(f) }
	if not r[1] then errorf("%s", tostring(r[2])) end
	local out = {}
	for i = 2, #r do out[#out + 1] = tostring(r[i]) end
	return #out > 0 and table.concat(out, "\t") or "ok"
end

function C.api(a)
	local name = a[1]
	local tables = { sim = sim, elem = elem, tpt = tpt, gfx = gfx, interface = interface, event = event, socket = socket, fileSystem = fileSystem }
	if not name then
		local n = {}
		for k, v in pairs(tables) do n[#n + 1] = k end
		table.sort(n)
		return "tables: " .. table.concat(n, " ")
	end
	local t = tables[name]
	if type(t) ~= "table" then errorf("no such table '%s'", name) end
	local keys = {}
	for k, v in pairs(t) do keys[#keys + 1] = k .. (type(v) == "function" and "()" or "") end
	table.sort(keys)
	return table.concat(keys, " ")
end

local function split(s)
	local t = {}
	for w in s:gmatch("%S+") do t[#t + 1] = w end
	return t
end

local function execute(line)
	local toks = split(line)
	local cmd = table.remove(toks, 1)
	local fn = cmd and C[cmd]
	if not fn then return false, "unknown command '" .. tostring(cmd) .. "' (see read_instructions)" end
	local ok, res, kind = pcall(fn, toks, line)
	if not ok then return false, tostring(res) end
	return true, res, kind
end
execute_line = execute

---------------------------------------------------------------- transport
local sock, connected, rxbuf, ticks = nil, false, "", 0
local txq = {}

local function disconnect(why)
	if sock then pcall(function() sock:close() end) end
	sock, connected, rxbuf, txq = nil, false, "", {}
	if why then log("disconnected: " .. tostring(why)) end
end

local lastFail
local function failOnce(m)
	if m ~= lastFail then lastFail = m; log(m) end
end

-- Non-blocking connect: call connect() once per tick until status() reports "connected".
local pending, pendingTicks = nil, 0

local function finishConnect(s, how)
	pending, sock, connected = nil, s, true
	lastFail = nil
	log("connected to " .. HOST .. ":" .. PORT .. " (" .. how .. ")")
end

local function tryConnect()
	local ok, s = pcall(socket.tcp)
	if not ok or not s then return failOnce("socket.tcp failed: " .. tostring(s)) end
	pcall(function() s:settimeout(0) end)
	pending, pendingTicks = s, 0
end

local function pollPending()
	local s = pending
	pendingTicks = pendingTicks + 1
	local okc, res, err = pcall(function() return s:connect(HOST, PORT) end)
	local okst, st = pcall(function() return s:status() end)
	st = okst and tostring(st):lower() or "error"
	if pendingTicks <= 5 or pendingTicks % 120 == 0 then
		log("connect poll " .. pendingTicks .. ": ok=" .. tostring(okc) .. " res=" .. tostring(res) .. " err=" .. tostring(err) .. " status=" .. st)
	end
	if st == "connected" then return finishConnect(s, "status") end
	if not okc and tostring(res):find("connected socket", 1, true) then return finishConnect(s, "already connected") end
	if st == "dead" or st == "error" or pendingTicks > 600 then
		pending = nil
		pcall(function() s:close() end)
		failOnce("connect failed: status=" .. st .. " res=" .. tostring(res) .. " err=" .. tostring(err))
	end
end

local function reply(id, ok, kind, payload)
	txq[#txq + 1] = string.format("%s %s %s %s\n", id, ok and "ok" or "err", kind, b64(payload))
end

local function pump()
	-- write
	if #txq > 0 then
		local data = table.remove(txq, 1)
		local okc, n, err, sent = pcall(function() return sock:send(data) end)
		if not okc then return disconnect(n) end
		-- LuaSocket-style: on "timeout" the bytes already sent come back as the 3rd value
		if type(n) ~= "number" and err and err ~= "timeout" then return disconnect(err) end
		local count = type(n) == "number" and n or sent or 0
		if count < #data then table.insert(txq, 1, data:sub(count + 1)) end
	end
	-- read
	-- LuaSocket-style: on timeout/closed the bytes read so far come back as the 3rd value
	local okr, data, err, partial = pcall(function() return sock:receive(65536) end)
	if not okr then return disconnect(data) end
	if not data or #data == 0 then data = partial end
	if data and #data > 0 then rxbuf = rxbuf .. data
	end
	if err == "closed" and not rxbuf:find("\n", 1, true) then return disconnect("closed by server") end
	while true do
		local i = rxbuf:find("\n", 1, true)
		if not i then break end
		local line = rxbuf:sub(1, i - 1)
		rxbuf = rxbuf:sub(i + 1)
		local id, cmd = line:match("^(%d+) (.*)$")
		if id then
			local ok, res, kind = execute(cmd)
			if not ok then reply(id, false, "text", res)
			else reply(id, true, kind or "text", res) end
		end
	end
end

event.register(event.tick, function()
	ticks = ticks + 1
	if not connected then
		if pending then pollPending()
		elseif ticks % RECONNECT_TICKS == 1 then tryConnect() end
		return
	end
	local ok, err = pcall(pump)
	if not ok then disconnect(err) end
end)

log("plugin loaded; connecting to " .. HOST .. ":" .. PORT)
