--!strict
--[[
	MapSetup.server.luau  (Script — ServerScriptService)

	Procedurally generates an 800 × 800-stud urban arena:

	  • Concrete baseplate + 12-stud boundary walls
	  • 5 × 5 city-block grid (BLOCK_SIZE=110, ROAD_WIDTH=16)
	  • 4 asphalt roads per axis with raised sidewalks + yellow centre lines
	  • Centre park  — grass, cross-paths, ~22 trees
	  • Up to 17 buildings per non-park block:
	      - Skinny footprints 22–28 studs wide
	      - Ground floor solid walls with doorway
	      - Upper floors use segFloorWall() → real window-gap cutouts
	      - Zigzag 45° ramps connecting each floor pair
	      - Flat roof slab + trim
	  • Street cover — concrete barriers, wooden crates, blocky cars
	    scattered at road intersections and mid-block positions
	  • 8 SpawnLocations around the park perimeter

	Grid maths:
	  CELL_SIZE   = BLOCK_SIZE + ROAD_WIDTH = 126
	  Block centres: -252, -126, 0, 126, 252  (both axes)
	  Road centres:  -189,  -63, 63, 189
	  City extent:   ±307
]]

local Workspace = game:GetService("Workspace")

-- ============================================================
-- Grid Constants
-- ============================================================

local ARENA_HALF : number = 400
local BLOCK_SIZE : number = 110
local ROAD_WIDTH : number = 16
local CELL_SIZE  : number = BLOCK_SIZE + ROAD_WIDTH   -- 126
local GRID_N     : number = 5
local GRID_HALF  : number = 2 * CELL_SIZE             -- 252
local CITY_EXTENT: number = GRID_HALF + BLOCK_SIZE / 2 -- 307

-- Road centre axes (between adjacent blocks)
local ROAD_AXES: { number } = {}
for i = 0, GRID_N - 2 do
	table.insert(ROAD_AXES,
		-GRID_HALF + i * CELL_SIZE + BLOCK_SIZE / 2 + ROAD_WIDTH / 2)
end  -- = { -189, -63, 63, 189 }

-- ============================================================
-- Visual Constants
-- ============================================================

local ROAD_THICK  : number = 0.25
local ROAD_Y      : number = ROAD_THICK / 2
local SIDEWALK_W  : number = 3
local SIDEWALK_H  : number = 0.65
local SIDEWALK_Y  : number = SIDEWALK_H / 2

local WALL_T      : number = 2       -- building wall thickness
local DOOR_HW     : number = 2.5     -- half-width of doorway (5 studs total)
local DOOR_H      : number = 9       -- doorway clear height
local FLOOR_STEP  : number = 12      -- floor-to-floor height

local COL_BASE  = Color3.fromRGB( 50,  50,  50)
local COL_ROAD  = Color3.fromRGB( 30,  30,  30)
local COL_LINE  = Color3.fromRGB(255, 215,   0)
local COL_SWALK = Color3.fromRGB(150, 145, 135)
local COL_GRASS = Color3.fromRGB( 72, 140,  55)
local COL_PATH  = Color3.fromRGB(130, 125, 115)
local COL_TRUNK = Color3.fromRGB(110,  65,  30)
local COL_LEAF  = Color3.fromRGB( 38, 115,  32)
local COL_BOUND = Color3.fromRGB( 28,  28,  28)

local BLDG_COLS: { Color3 } = {
	Color3.fromRGB(175, 168, 158),
	Color3.fromRGB(158, 152, 145),
	Color3.fromRGB(140, 155, 168),
	Color3.fromRGB(172, 172, 162),
	Color3.fromRGB(185, 175, 160),
}

local CAR_COLS: { Color3 } = {
	Color3.fromRGB(180,  40,  40),
	Color3.fromRGB( 40,  40, 180),
	Color3.fromRGB( 40, 120,  40),
	Color3.fromRGB( 80,  80,  80),
	Color3.fromRGB(200, 180,  50),
}

-- ============================================================
-- Folders
-- ============================================================

local mapFolder = Instance.new("Folder")
mapFolder.Name   = "Map"
mapFolder.Parent = Workspace

local function folder(name: string, parent: Instance): Folder
	local f      = Instance.new("Folder")
	f.Name       = name
	f.Parent     = parent
	return f
end

local fRoads     = folder("Roads",       mapFolder)
local fBuildings = folder("Buildings",   mapFolder)
local fPark      = folder("Park",        mapFolder)
local fSpawns    = folder("Spawns",      mapFolder)
local fBound     = folder("Boundary",    mapFolder)
local fCover     = folder("StreetCover", mapFolder)

-- ============================================================
-- Part Helper
-- ============================================================

local function p(
	name:      string,
	size:      Vector3,
	cf:        CFrame,
	colour:    Color3,
	mat:       Enum.Material,
	parent:    Instance,
	noCollide: boolean?
): Part
	local part              = Instance.new("Part")
	part.Name               = name
	part.Size               = size
	part.CFrame             = cf
	part.Anchored           = true
	part.CanCollide         = if noCollide then false else true
	part.CastShadow         = true
	part.Material           = mat
	part.Color              = colour
	part.TopSurface         = Enum.SurfaceType.Smooth
	part.BottomSurface      = Enum.SurfaceType.Smooth
	part.Parent             = parent
	return part
end

-- ============================================================
-- 1. Baseplate
-- ============================================================

local BPSIZE = ARENA_HALF * 2
if not Workspace:FindFirstChild("Baseplate") then
	p("Baseplate", Vector3.new(BPSIZE, 4, BPSIZE),
		CFrame.new(0, -2, 0), COL_BASE, Enum.Material.Concrete, mapFolder)
end

-- ============================================================
-- 2. Boundary Walls
-- ============================================================

local BW_H = 12
local BW_T = 3

local function bound(pos: Vector3, size: Vector3)
	p("Boundary", size, CFrame.new(pos), COL_BOUND, Enum.Material.SmoothPlastic, fBound)
end

bound(Vector3.new(0, BW_H/2,  ARENA_HALF + BW_T/2), Vector3.new(BPSIZE, BW_H, BW_T))
bound(Vector3.new(0, BW_H/2, -ARENA_HALF - BW_T/2), Vector3.new(BPSIZE, BW_H, BW_T))
bound(Vector3.new( ARENA_HALF + BW_T/2, BW_H/2, 0), Vector3.new(BW_T, BW_H, BPSIZE))
bound(Vector3.new(-ARENA_HALF - BW_T/2, BW_H/2, 0), Vector3.new(BW_T, BW_H, BPSIZE))

-- ============================================================
-- 3. Road Grid
-- ============================================================

local ROAD_LEN = CITY_EXTENT * 2  -- 614

local function makeRoad(axis: number, isNS: boolean)
	local roadSz = if isNS then Vector3.new(ROAD_WIDTH, ROAD_THICK, ROAD_LEN)
		else Vector3.new(ROAD_LEN, ROAD_THICK, ROAD_WIDTH)
	local roadCF = if isNS then CFrame.new(axis, ROAD_Y, 0)
		else CFrame.new(0, ROAD_Y, axis)
	p("Road", roadSz, roadCF, COL_ROAD, Enum.Material.SmoothPlastic, fRoads)

	local lineSz = if isNS then Vector3.new(0.35, ROAD_THICK + 0.05, ROAD_LEN)
		else Vector3.new(ROAD_LEN, ROAD_THICK + 0.05, 0.35)
	local lineCF = if isNS then CFrame.new(axis, ROAD_Y + 0.03, 0)
		else CFrame.new(0, ROAD_Y + 0.03, axis)
	p("CentreLine", lineSz, lineCF, COL_LINE, Enum.Material.SmoothPlastic, fRoads, true)

	for _, side in { -1, 1 } do
		local swOff  = ROAD_WIDTH / 2 + SIDEWALK_W / 2
		local swSize = if isNS then Vector3.new(SIDEWALK_W, SIDEWALK_H, ROAD_LEN)
			else Vector3.new(ROAD_LEN, SIDEWALK_H, SIDEWALK_W)
		local swCF   = if isNS then CFrame.new(axis + side * swOff, SIDEWALK_Y, 0)
			else CFrame.new(0, SIDEWALK_Y, axis + side * swOff)
		p("Sidewalk", swSize, swCF, COL_SWALK, Enum.Material.SmoothPlastic, fRoads)
	end
end

for _, axis in ROAD_AXES do
	makeRoad(axis, true)
	makeRoad(axis, false)
end

-- ============================================================
-- 4. Centre Park
-- ============================================================

local PARK_HALF = BLOCK_SIZE / 2   -- 55
local GRASS_Y   = 0.15

p("ParkGrass", Vector3.new(BLOCK_SIZE, 0.3, BLOCK_SIZE),
	CFrame.new(0, GRASS_Y, 0), COL_GRASS, Enum.Material.Grass, fPark)

for _, d in {
	{ Vector3.new(BLOCK_SIZE + SIDEWALK_W*2, SIDEWALK_H, SIDEWALK_W), Vector3.new(0, SIDEWALK_Y,  PARK_HALF + SIDEWALK_W/2) },
	{ Vector3.new(BLOCK_SIZE + SIDEWALK_W*2, SIDEWALK_H, SIDEWALK_W), Vector3.new(0, SIDEWALK_Y, -PARK_HALF - SIDEWALK_W/2) },
	{ Vector3.new(SIDEWALK_W, SIDEWALK_H, BLOCK_SIZE), Vector3.new( PARK_HALF + SIDEWALK_W/2, SIDEWALK_Y, 0) },
	{ Vector3.new(SIDEWALK_W, SIDEWALK_H, BLOCK_SIZE), Vector3.new(-PARK_HALF - SIDEWALK_W/2, SIDEWALK_Y, 0) },
} do
	p("ParkSW", d[1] :: Vector3, CFrame.new(d[2] :: Vector3), COL_SWALK, Enum.Material.SmoothPlastic, fPark)
end

p("PathX", Vector3.new(BLOCK_SIZE, 0.35, 4.5), CFrame.new(0, GRASS_Y + 0.15, 0), COL_PATH, Enum.Material.Concrete, fPark)
p("PathZ", Vector3.new(4.5, 0.35, BLOCK_SIZE), CFrame.new(0, GRASS_Y + 0.15, 0), COL_PATH, Enum.Material.Concrete, fPark)

local function tree(tx: number, tz: number)
	local th = math.random(5, 9)
	local lr = math.random(3, 5)

	local trunk            = Instance.new("Part")
	trunk.Name             = "TreeTrunk"
	trunk.Shape            = Enum.PartType.Cylinder
	trunk.Size             = Vector3.new(th, 0.75, 0.75)
	trunk.CFrame           = CFrame.new(tx, th / 2, tz) * CFrame.Angles(0, 0, math.rad(90))
	trunk.Anchored         = true
	trunk.CanCollide       = true
	trunk.Material         = Enum.Material.Wood
	trunk.Color            = COL_TRUNK
	trunk.TopSurface       = Enum.SurfaceType.Smooth
	trunk.BottomSurface    = Enum.SurfaceType.Smooth
	trunk.Parent           = fPark

	local leaves           = Instance.new("Part")
	leaves.Name            = "TreeLeaves"
	leaves.Shape           = Enum.PartType.Ball
	leaves.Size            = Vector3.new(lr * 2, lr * 2, lr * 2)
	leaves.Position        = Vector3.new(tx, th + lr * 0.7, tz)
	leaves.Anchored        = true
	leaves.CanCollide      = false
	leaves.Material        = Enum.Material.Grass
	leaves.Color           = COL_LEAF
	leaves.TopSurface      = Enum.SurfaceType.Smooth
	leaves.BottomSurface   = Enum.SurfaceType.Smooth
	leaves.Parent          = fPark
end

math.randomseed(42)
local TMARG = 9
for _ = 1, 22 do
	local tx, tz
	local tries = 0
	repeat
		tx    = math.random(-PARK_HALF + TMARG, PARK_HALF - TMARG)
		tz    = math.random(-PARK_HALF + TMARG, PARK_HALF - TMARG)
		tries += 1
	until (math.abs(tx) > 3 or math.abs(tz) > 3) or tries > 20
	tree(tx, tz)
end

-- ============================================================
-- 5. Buildings
-- ============================================================

-- Segmented upper-floor wall with a real window opening.
-- wallCF    = CFrame of the wall section centre (handles rotation for EW walls)
-- wallW     = total width of this wall face
-- thick     = wall thickness
-- col       = colour
local function segFloorWall(
	bf:     Instance,
	wallCF: CFrame,
	wallW:  number,
	thick:  number,
	col:    Color3
)
	local wallH   = FLOOR_STEP
	local mat     = Enum.Material.SmoothPlastic
	local winW    = wallW * 0.40
	local winH    = wallH * 0.50
	local sideW   = (wallW - winW) / 2
	local sillH   = wallH * 0.22
	local lintelH = wallH - winH - sillH

	-- Left solid panel
	p("WallSeg", Vector3.new(sideW, wallH, thick),
		wallCF * CFrame.new(-(wallW/2 - sideW/2), 0, 0), col, mat, bf)
	-- Right solid panel
	p("WallSeg", Vector3.new(sideW, wallH, thick),
		wallCF * CFrame.new( (wallW/2 - sideW/2), 0, 0), col, mat, bf)
	-- Sill (below window opening)
	p("WallSill", Vector3.new(winW, sillH, thick),
		wallCF * CFrame.new(0, -(wallH/2 - sillH/2), 0), col, mat, bf)
	-- Lintel (above window opening)
	p("WallLintel", Vector3.new(winW, lintelH, thick),
		wallCF * CFrame.new(0,  (wallH/2 - lintelH/2), 0), col, mat, bf)
end

local function makeBuilding(bx: number, bz: number, W: number, D: number, H: number, col: Color3)
	local bf     = folder("Building", fBuildings)
	local mat    = Enum.Material.SmoothPlastic
	local floors = math.floor(H / FLOOR_STEP)

	-- ── Ground-floor walls ───────────────────────────────────
	local gfH  = FLOOR_STEP
	local gfY  = gfH / 2

	-- North (solid)
	p("WallN0", Vector3.new(W, gfH, WALL_T), CFrame.new(bx, gfY, bz - D/2), col, mat, bf)

	-- South (door opening)
	local segW    = W / 2 - DOOR_HW
	local headerH = gfH - DOOR_H
	if segW > 0.3 then
		p("WallSL0", Vector3.new(segW, gfH, WALL_T),
			CFrame.new(bx - DOOR_HW - segW/2, gfY, bz + D/2), col, mat, bf)
		p("WallSR0", Vector3.new(segW, gfH, WALL_T),
			CFrame.new(bx + DOOR_HW + segW/2, gfY, bz + D/2), col, mat, bf)
	end
	if headerH > 0.4 then
		p("WallSTop0", Vector3.new(DOOR_HW * 2, headerH, WALL_T),
			CFrame.new(bx, DOOR_H + headerH/2, bz + D/2), col, mat, bf)
	end

	-- East + West (solid ground floor)
	p("WallE0", Vector3.new(WALL_T, gfH, D), CFrame.new(bx + W/2, gfY, bz), col, mat, bf)
	p("WallW0", Vector3.new(WALL_T, gfH, D), CFrame.new(bx - W/2, gfY, bz), col, mat, bf)

	-- ── Upper-floor walls (windowed) ─────────────────────────
	-- Walls running along X (North/South faces): no rotation needed.
	-- Walls running along Z (East/West faces): rotate 90° around Y so
	-- segFloorWall's local-X offset works along world-Z.
	local ewRot = CFrame.Angles(0, math.rad(90), 0)

	for fl = 1, floors - 1 do
		local flCY = fl * FLOOR_STEP + FLOOR_STEP / 2

		-- North
		segFloorWall(bf, CFrame.new(bx, flCY, bz - D/2),         W, WALL_T, col)
		-- South
		segFloorWall(bf, CFrame.new(bx, flCY, bz + D/2),         W, WALL_T, col)
		-- East
		segFloorWall(bf, CFrame.new(bx + W/2, flCY, bz) * ewRot, D, WALL_T, col)
		-- West
		segFloorWall(bf, CFrame.new(bx - W/2, flCY, bz) * ewRot, D, WALL_T, col)
	end

	-- ── Interior floor slabs ─────────────────────────────────
	for fl = 1, floors - 1 do
		p("Floor", Vector3.new(W - WALL_T * 2, 0.8, D - WALL_T * 2),
			CFrame.new(bx, fl * FLOOR_STEP + 0.4, bz), col, mat, bf)
	end

	-- ── Zigzag ramps (45°, one per floor transition) ─────────
	-- All ramps share the same XZ centre; direction alternates each floor.
	-- Even floor (0-indexed): angle = -45° → walking in +Z goes UP.
	-- Odd  floor             : angle = +45° → walking in -Z goes UP.
	local rampW   = math.min(3.5, W * 0.14)
	local rampLen = FLOOR_STEP * math.sqrt(2)  -- hypotenuse at 45°
	local rampX   = bx                          -- centred on building

	for fl = 0, floors - 2 do
		local angle  = if fl % 2 == 0 then -math.rad(45) else math.rad(45)
		local rampCF = CFrame.new(rampX, fl * FLOOR_STEP + FLOOR_STEP / 2, bz)
			* CFrame.Angles(angle, 0, 0)
		p("Ramp", Vector3.new(rampW, 0.4, rampLen), rampCF, col, mat, bf)
	end

	-- ── Roof ────────────────────────────────────────────────
	p("Roof", Vector3.new(W + 1, 0.8, D + 1),
		CFrame.new(bx, H + 0.4, bz), col, mat, bf)

	local tc     = Color3.new(col.R * 0.82, col.G * 0.82, col.B * 0.82)
	local trimRY = H + 0.8 + 0.5
	local trimT  = 1.2
	local trimH  = 0.8
	for _, td in {
		{ Vector3.new(W + trimT*2 + 2, trimH, trimT), Vector3.new(bx, trimRY, bz - D/2 - trimT/2) },
		{ Vector3.new(W + trimT*2 + 2, trimH, trimT), Vector3.new(bx, trimRY, bz + D/2 + trimT/2) },
		{ Vector3.new(trimT, trimH, D + trimT*2 + 2), Vector3.new(bx - W/2 - trimT/2, trimRY, bz) },
		{ Vector3.new(trimT, trimH, D + trimT*2 + 2), Vector3.new(bx + W/2 + trimT/2, trimRY, bz) },
	} do
		p("RoofTrim", td[1] :: Vector3, CFrame.new(td[2] :: Vector3), tc, mat, bf)
	end
end

-- Build 17 buildings (skinny 22–28 studs, 2–4 floors)
local blockPool: { { number } } = {}
for ci = 0, GRID_N - 1 do
	for cj = 0, GRID_N - 1 do
		if ci == 2 and cj == 2 then continue end  -- park block
		table.insert(blockPool, {
			-GRID_HALF + ci * CELL_SIZE,
			-GRID_HALF + cj * CELL_SIZE,
		})
	end
end

math.randomseed(9001)
for i = #blockPool, 2, -1 do
	local j = math.random(1, i)
	blockPool[i], blockPool[j] = blockPool[j], blockPool[i]
end

for i = 1, math.min(17, #blockPool) do
	local bc  = blockPool[i]
	local W   = math.random(22, 28)
	local D   = math.random(22, 28)
	local H   = math.random(2, 4) * FLOOR_STEP   -- 24, 36, or 48
	local col = BLDG_COLS[math.random(1, #BLDG_COLS)]
	makeBuilding(bc[1], bc[2], W, D, H, col)
end

-- ============================================================
-- 6. Street Cover
-- ============================================================

local COL_BARRIER = Color3.fromRGB(210, 210, 210)
local COL_CRATE   = Color3.fromRGB(120,  95,  65)

-- Concrete barrier (kerbside)
local function makeBarrier(cx: number, cz: number, horizontal: boolean)
	local sz = if horizontal
		then Vector3.new(4.0, 1.2, 0.65)
		else Vector3.new(0.65, 1.2, 4.0)
	p("Barrier", sz, CFrame.new(cx, 0.6, cz),
		COL_BARRIER, Enum.Material.SmoothPlastic, fCover)
end

-- Wooden crate
local function makeCrate(cx: number, cz: number)
	p("Crate", Vector3.new(2, 2, 2), CFrame.new(cx, 1, cz),
		COL_CRATE, Enum.Material.Wood, fCover)
end

-- Simple blocky car (body + roof)
local function makeCar(cx: number, cz: number, horizontal: boolean, carCol: Color3)
	local bodySz = if horizontal then Vector3.new(9, 2.0, 4.0) else Vector3.new(4.0, 2.0, 9)
	local roofSz = if horizontal then Vector3.new(5, 1.5, 3.5) else Vector3.new(3.5, 1.5, 5)
	p("CarBody", bodySz, CFrame.new(cx, 1.0, cz),  carCol, Enum.Material.SmoothPlastic, fCover)
	p("CarRoof", roofSz, CFrame.new(cx, 2.75, cz), carCol, Enum.Material.SmoothPlastic, fCover)
end

math.randomseed(7777)

-- At each road intersection: scatter cover in the four quadrants
for _, ax in ROAD_AXES do
	for _, az in ROAD_AXES do
		for _, off in {
			{ ax - 5, az - 5 },
			{ ax + 5, az - 5 },
			{ ax - 5, az + 5 },
			{ ax + 5, az + 5 },
		} do
			local r = math.random()
			if r < 0.35 then
				makeBarrier(off[1], off[2], math.random() > 0.5)
			elseif r < 0.60 then
				makeCrate(off[1], off[2])
			end
		end

		-- Parked car on the road near the intersection (50% chance)
		if math.random() > 0.5 then
			local side   = if math.random() > 0.5 then 1 else -1
			local carX   = ax + side * (ROAD_WIDTH / 2 - 2.2)
			makeCar(carX, az + math.random(-18, 18), false,
				CAR_COLS[math.random(1, #CAR_COLS)])
		end
	end
end

-- Mid-block cover along each road (scattered along the kerb)
for _, axis in ROAD_AXES do
	for _, pos in { -180, -90, 0, 90, 180 } do
		local side = if math.random() > 0.5 then 1 else -1
		local kOff = side * (ROAD_WIDTH / 2 + 1.8)
		local r    = math.random()
		if r < 0.40 then
			-- N-S road: cover along Z
			makeBarrier(axis + kOff, pos, false)
		elseif r < 0.65 then
			makeCrate(axis + kOff, pos)
		end
		-- E-W road: cover along X (same positions flipped)
		local r2 = math.random()
		if r2 < 0.40 then
			makeBarrier(pos, axis + kOff, true)
		elseif r2 < 0.65 then
			makeCrate(pos, axis + kOff)
		end
	end
end

-- ============================================================
-- 7. SpawnLocations  (8, ring at radius 90 around park)
-- ============================================================

for i = 1, 8 do
	local angle             = (2 * math.pi / 8) * (i - 1)
	local sl                = Instance.new("SpawnLocation")
	sl.Size                 = Vector3.new(6, 1, 6)
	sl.CFrame               = CFrame.new(math.cos(angle) * 90, 1, math.sin(angle) * 90)
	sl.Anchored             = true
	sl.Material             = Enum.Material.SmoothPlastic
	sl.Color                = Color3.fromRGB(50, 130, 210)
	sl.TopSurface           = Enum.SurfaceType.Smooth
	sl.BottomSurface        = Enum.SurfaceType.Smooth
	sl.Neutral              = true
	sl.AllowTeamChangeOnTouch = false
	sl.Duration             = 0
	sl.Parent               = fSpawns
end
