--!strict
--[[
	MapSetup.server.luau  (Script — ServerScriptService)

	Procedurally generates an 800 × 800-stud urban arena.

	Step 1 — Dense NYC Grid:
	  • Concrete baseplate + 12-stud boundary walls
	  • 9 × 9 city-block grid (BLOCK_SIZE=64, ROAD_WIDTH=12, CELL_SIZE=76)
	  • 8 cross streets per axis with raised sidewalks + yellow centre lines
	  • Thin concrete block-plot pads marking each block's footprint
	  • Centre block placeholder (green pad)
	  • 8 SpawnLocations ringing the centre block

	Step 2 — GenerateBuilding():
	  • Hollow shell: solid ground-floor walls + south doorway cutout
	  • Windowed upper-floor walls via segFloorWall()
	  • Interior floor slabs every 12 studs
	  • Roof slab
	  • One test building at origin (30 × 25 × 36)

	Grid maths:
	  CELL_SIZE    = BLOCK_SIZE + ROAD_WIDTH = 76
	  Block centres: -304, -228, -152, -76, 0, 76, 152, 228, 304
	  Road centres:  -266, -190, -114,  -38, 38, 114, 190, 266
	  City extent:   ±336 studs
]]

local Workspace = game:GetService("Workspace")

-- ============================================================
-- Grid Constants
-- ============================================================

local ARENA_HALF  : number = 400
local BLOCK_SIZE  : number = 64       -- was 110; tighter NYC block
local ROAD_WIDTH  : number = 12       -- was 16;  narrow cross street
local CELL_SIZE   : number = BLOCK_SIZE + ROAD_WIDTH   -- 76
local GRID_N      : number = 9        -- was 5; 9×9 = 81 blocks
local GRID_HALF   : number = 4 * CELL_SIZE             -- 304
local CITY_EXTENT : number = GRID_HALF + BLOCK_SIZE / 2 -- 336

-- Road centre axes (one between each pair of adjacent blocks)
local ROAD_AXES: { number } = {}
for i = 0, GRID_N - 2 do
	table.insert(ROAD_AXES,
		-GRID_HALF + i * CELL_SIZE + BLOCK_SIZE / 2 + ROAD_WIDTH / 2)
end  -- = { -266, -190, -114, -38, 38, 114, 190, 266 }

-- ============================================================
-- Visual / Building Constants
-- ============================================================

local ROAD_THICK  : number = 0.25
local ROAD_Y      : number = ROAD_THICK / 2
local SIDEWALK_W  : number = 2        -- narrower than before to fit 12-stud road
local SIDEWALK_H  : number = 0.65
local SIDEWALK_Y  : number = SIDEWALK_H / 2

local WALL_T      : number = 2        -- building wall thickness
local DOOR_HW     : number = 2.5      -- half-width of doorway opening (5 studs total)
local DOOR_H      : number = 9        -- doorway clear height (R15 ~= 5.6 studs, 9 is generous)
local FLOOR_STEP  : number = 12       -- floor-to-floor height

local COL_BASE   = Color3.fromRGB( 50,  50,  50)
local COL_ROAD   = Color3.fromRGB( 30,  30,  30)
local COL_LINE   = Color3.fromRGB(255, 215,   0)
local COL_SWALK  = Color3.fromRGB(150, 145, 135)
local COL_GRASS  = Color3.fromRGB( 72, 140,  55)
local COL_BOUND  = Color3.fromRGB( 28,  28,  28)

local BLDG_COLS: { Color3 } = {
	Color3.fromRGB(175, 168, 158),
	Color3.fromRGB(158, 152, 145),
	Color3.fromRGB(140, 155, 168),
	Color3.fromRGB(172, 172, 162),
	Color3.fromRGB(185, 175, 160),
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
local _fPark     = folder("Park",        mapFolder)  -- populated in a later step
local fSpawns    = folder("Spawns",      mapFolder)
local fBound     = folder("Boundary",    mapFolder)
local _fCover    = folder("StreetCover", mapFolder)  -- populated in a later step

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
	local part          = Instance.new("Part")
	part.Name           = name
	part.Size           = size
	part.CFrame         = cf
	part.Anchored       = true
	part.CanCollide     = if noCollide then false else true
	part.CastShadow     = true
	part.Material       = mat
	part.Color          = colour
	part.TopSurface     = Enum.SurfaceType.Smooth
	part.BottomSurface  = Enum.SurfaceType.Smooth
	part.Parent         = parent
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
-- 3. Road Grid  (8 corridors per axis)
-- ============================================================

local ROAD_LEN = CITY_EXTENT * 2  -- 672

local function makeRoad(axis: number, isNS: boolean)
	local roadSz = if isNS then Vector3.new(ROAD_WIDTH, ROAD_THICK, ROAD_LEN)
		else Vector3.new(ROAD_LEN, ROAD_THICK, ROAD_WIDTH)
	local roadCF = if isNS then CFrame.new(axis, ROAD_Y, 0)
		else CFrame.new(0, ROAD_Y, axis)
	p("Road", roadSz, roadCF, COL_ROAD, Enum.Material.SmoothPlastic, fRoads)

	-- Yellow centre line (non-collidable, floated 0.03 above road surface)
	local lineSz = if isNS then Vector3.new(0.35, ROAD_THICK + 0.05, ROAD_LEN)
		else Vector3.new(ROAD_LEN, ROAD_THICK + 0.05, 0.35)
	local lineCF = if isNS then CFrame.new(axis, ROAD_Y + 0.03, 0)
		else CFrame.new(0, ROAD_Y + 0.03, axis)
	p("CentreLine", lineSz, lineCF, COL_LINE, Enum.Material.SmoothPlastic, fRoads, true)

	-- Sidewalks — one on each side of the road
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
-- 4. Block Plot Pads  (thin slab marking each block's footprint)
--    Centre block (ci=4, cj=4 → bx=0, bz=0) gets a green placeholder.
--    All others are dark concrete.  Buildings are placed on top in later steps.
-- ============================================================

local BLOCK_PAD_H: number = 0.1
local CENTER_IDX : number = (GRID_N - 1) // 2  -- = 4  (zero-based centre)

for ci = 0, GRID_N - 1 do
	for cj = 0, GRID_N - 1 do
		local bx       = -GRID_HALF + ci * CELL_SIZE
		local bz       = -GRID_HALF + cj * CELL_SIZE
		local isCenter = (ci == CENTER_IDX) and (cj == CENTER_IDX)
		local col      = if isCenter then COL_GRASS else COL_BASE
		local mat      = if isCenter then Enum.Material.Grass else Enum.Material.Concrete
		p("BlockPlot",
			Vector3.new(BLOCK_SIZE, BLOCK_PAD_H, BLOCK_SIZE),
			CFrame.new(bx, BLOCK_PAD_H / 2, bz),
			col, mat, fBuildings)
	end
end

-- ============================================================
-- 5. segFloorWall  (shared helper — windowed upper-floor wall segment)
--    wallCF  = world CFrame of the wall segment centre
--    wallW   = total width of this wall face
--    thick   = wall thickness
--    col     = colour
-- ============================================================

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
		wallCF * CFrame.new(-(wallW / 2 - sideW / 2), 0, 0), col, mat, bf)
	-- Right solid panel
	p("WallSeg", Vector3.new(sideW, wallH, thick),
		wallCF * CFrame.new( (wallW / 2 - sideW / 2), 0, 0), col, mat, bf)
	-- Sill (below window opening)
	p("WallSill", Vector3.new(winW, sillH, thick),
		wallCF * CFrame.new(0, -(wallH / 2 - sillH / 2), 0), col, mat, bf)
	-- Lintel (above window opening)
	p("WallLintel", Vector3.new(winW, lintelH, thick),
		wallCF * CFrame.new(0,  (wallH / 2 - lintelH / 2), 0), col, mat, bf)
end

-- ============================================================
-- 6. GenerateBuilding
--    Hollow building shell placed at plotCF (world CFrame).
--    All wall offsets are expressed in plotCF's local space so
--    the building can be rotated and translated freely.
--
--    Parameters:
--      plotCF  — CFrame of the building's ground-level centre
--      sizeX   — footprint width  (along plotCF's X axis)
--      sizeZ   — footprint depth  (along plotCF's Z axis)
--      height  — total height in studs; should be a multiple of FLOOR_STEP
--
--    South face (plotCF's +Z) always gets the ground-floor doorway.
--    Stairs are added in Step 3.
-- ============================================================

math.randomseed(9001)

local function GenerateBuilding(
	plotCF: CFrame,
	sizeX:  number,
	sizeZ:  number,
	height: number
)
	local bf     = folder("Building", fBuildings)
	local mat    = Enum.Material.SmoothPlastic
	local col    = BLDG_COLS[math.random(1, #BLDG_COLS)]
	local floors = math.max(1, math.floor(height / FLOOR_STEP))

	-- ── Ground-floor walls ──────────────────────────────────────
	local gfH  = FLOOR_STEP
	local gfHY = gfH / 2

	-- North (solid)
	p("WallN0",
		Vector3.new(sizeX, gfH, WALL_T),
		plotCF * CFrame.new(0, gfHY, -sizeZ / 2),
		col, mat, bf)

	-- East (solid)
	p("WallE0",
		Vector3.new(WALL_T, gfH, sizeZ),
		plotCF * CFrame.new(sizeX / 2, gfHY, 0),
		col, mat, bf)

	-- West (solid)
	p("WallW0",
		Vector3.new(WALL_T, gfH, sizeZ),
		plotCF * CFrame.new(-sizeX / 2, gfHY, 0),
		col, mat, bf)

	-- South — doorway cutout: two side panels + header above door
	local segW    = sizeX / 2 - DOOR_HW
	local headerH = gfH - DOOR_H
	if segW > 0.3 then
		p("WallSL0",
			Vector3.new(segW, gfH, WALL_T),
			plotCF * CFrame.new(-DOOR_HW - segW / 2, gfHY, sizeZ / 2),
			col, mat, bf)
		p("WallSR0",
			Vector3.new(segW, gfH, WALL_T),
			plotCF * CFrame.new( DOOR_HW + segW / 2, gfHY, sizeZ / 2),
			col, mat, bf)
	end
	if headerH > 0.4 then
		p("WallSTop0",
			Vector3.new(DOOR_HW * 2, headerH, WALL_T),
			plotCF * CFrame.new(0, DOOR_H + headerH / 2, sizeZ / 2),
			col, mat, bf)
	end

	-- ── Upper-floor walls (windowed) ────────────────────────────
	-- E/W walls are rotated 90° around Y so segFloorWall's local-X
	-- offset runs along world-Z (the depth of the building).
	local ewRot = CFrame.Angles(0, math.rad(90), 0)

	for fl = 1, floors - 1 do
		local cy = fl * FLOOR_STEP + FLOOR_STEP / 2
		-- North
		segFloorWall(bf, plotCF * CFrame.new(0,          cy, -sizeZ / 2),         sizeX, WALL_T, col)
		-- South
		segFloorWall(bf, plotCF * CFrame.new(0,          cy,  sizeZ / 2),         sizeX, WALL_T, col)
		-- East
		segFloorWall(bf, plotCF * CFrame.new( sizeX / 2, cy,  0) * ewRot, sizeZ, WALL_T, col)
		-- West
		segFloorWall(bf, plotCF * CFrame.new(-sizeX / 2, cy,  0) * ewRot, sizeZ, WALL_T, col)
	end

	-- ── Interior floor slabs ────────────────────────────────────
	-- One slab per floor junction, inset by wall thickness on all sides.
	for fl = 1, floors - 1 do
		p("Floor",
			Vector3.new(sizeX - WALL_T * 2, 0.8, sizeZ - WALL_T * 2),
			plotCF * CFrame.new(0, fl * FLOOR_STEP + 0.4, 0),
			col, mat, bf)
	end

	-- ── Zigzag ramps (45°, centred in building, alternating Z-direction) ──────
	-- Each ramp connects one floor to the next.
	-- Horizontal run = FLOOR_STEP (12), vertical rise = FLOOR_STEP (12) → 45°.
	-- 45° is well within Roblox's default Humanoid.MaxSlopeAngle of 89°.
	-- rampLen = FLOOR_STEP × √2 ≈ 16.97 studs (hypotenuse at 45°).
	-- Even transitions (fl=0,2,…) tilt so walking in +Z = going up.
	-- Odd  transitions (fl=1,3,…) tilt so walking in -Z = going up.
	-- Both ramps share the same XZ centre (x=0, z=0 in building-local space)
	-- so a player walks up one, takes two steps, then walks back to climb the next.
	local rampW   = math.max(3.0, math.min(4.0, sizeX * 0.10))
	local rampLen = FLOOR_STEP * math.sqrt(2)   -- ≈ 16.97

	for fl = 0, floors - 2 do
		local midY  = fl * FLOOR_STEP + FLOOR_STEP / 2
		local angle = if fl % 2 == 0 then -math.rad(45) else math.rad(45)
		p("Ramp",
			Vector3.new(rampW, 0.4, rampLen),
			plotCF * CFrame.new(0, midY, 0) * CFrame.Angles(angle, 0, 0),
			col, mat, bf)
	end

	-- ── Roof ────────────────────────────────────────────────────
	p("Roof",
		Vector3.new(sizeX + 1, 0.8, sizeZ + 1),
		plotCF * CFrame.new(0, height + 0.4, 0),
		col, mat, bf)
end

-- ============================================================
-- 7. SpawnLocations  (8, ring at radius 55 around centre block)
--    Radius 55 places spawns just outside the 64-stud centre block
--    while staying clear of the first ring of roads.
-- ============================================================

for i = 1, 8 do
	local angle = (2 * math.pi / 8) * (i - 1)
	local sl                    = Instance.new("SpawnLocation")
	sl.Size                     = Vector3.new(6, 1, 6)
	sl.CFrame                   = CFrame.new(math.cos(angle) * 55, 1, math.sin(angle) * 55)
	sl.Anchored                 = true
	sl.Material                 = Enum.Material.SmoothPlastic
	sl.Color                    = Color3.fromRGB(50, 130, 210)
	sl.TopSurface               = Enum.SurfaceType.Smooth
	sl.BottomSurface            = Enum.SurfaceType.Smooth
	sl.Neutral                  = true
	sl.AllowTeamChangeOnTouch   = false
	sl.Duration                 = 0
	sl.Parent                   = fSpawns
end

-- ============================================================
-- 8. Populate city blocks
--    One building per block across the full 9×9 grid.
--    Centre block (ci=4, cj=4) is skipped — reserved for the park.
--    Footprint: 58–64 studs → road + setbacks = 12–18 stud alleys.
--    Height: 2–4 floors (24, 36, or 48 studs).
-- ============================================================

for ci = 0, GRID_N - 1 do
	for cj = 0, GRID_N - 1 do
		if ci == CENTER_IDX and cj == CENTER_IDX then continue end

		local bx = -GRID_HALF + ci * CELL_SIZE
		local bz = -GRID_HALF + cj * CELL_SIZE

		-- Vary footprint per block for visual interest.
		-- 58–64 studs wide/deep on a 64-stud block → exterior walls within 1–3 studs of block edge.
		local sX = math.random(58, 64)
		local sZ = math.random(58, 64)

		-- 2–4 floors.  Heights must be exact multiples of FLOOR_STEP so
		-- floor slabs and ramps land at integer stud positions.
		local h = math.random(2, 4) * FLOOR_STEP

		GenerateBuilding(CFrame.new(bx, 0, bz), sX, sZ, h)
	end
end
