--!strict
--[[
	WeaponPickups.server.luau  (Script — ServerScriptService)

	Spawns real 3D weapon models (cloned from ReplicatedStorage/Weapons) at
	the positions defined in PICKUP_DEFS.  Each model:
	  • Has all BaseParts anchored + non-collidable (players walk through)
	  • Has a ProximityPrompt on its Handle part
	  • Grants the weapon via RBX_Toolbox when the prompt is triggered
	  • Hides for RESPAWN_DELAY seconds then reappears
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local WeaponData = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponData")
) :: { [string]: { Name: string, Type: string, Damage: number, FireRate: number,
	MagSize: number, Spread: number, Recoil: number, FireMode: string, BulletsPerShot: number } }

-- Physical weapon models live here — one Model per weaponKey
local weaponsFolder = ReplicatedStorage:WaitForChild("Weapons")

-- RBX_Toolbox: server API for granting weapons to player inventory
local RBXToolbox = require(ReplicatedStorage:WaitForChild("RBX_Toolbox"))

-- ============================================================
-- Constants
-- ============================================================

local RESPAWN_DELAY = 30   -- seconds before a pickup reappears
local PICKUP_HEIGHT = 2.0  -- studs above ground

-- 10 pickup definitions: one of every weapon, ringing the centre building.
--
-- The test building at origin is 30×25 studs, so its corners reach ~19.5 studs
-- from centre.  All pickups are placed at radius ≥ 22 studs so they sit in
-- the open green pad area (block edge is at ±32 studs), fully visible from
-- any of the 8 SpawnLocations that ring the centre block.
-- Y = 2 studs: safely above the baseplate (Y=0) and block pad (top at Y=0.1).
type PickupDef = {
	weaponKey: string,
	cf:        CFrame,
}

local PICKUP_DEFS: { PickupDef } = {
	{ weaponKey = "AK47",        cf = CFrame.new(  22, PICKUP_HEIGHT,   0) },  -- E
	{ weaponKey = "SCARL",       cf = CFrame.new( -22, PICKUP_HEIGHT,   0) },  -- W
	{ weaponKey = "MAC10",       cf = CFrame.new(   0, PICKUP_HEIGHT,  22) },  -- S
	{ weaponKey = "KrissVector", cf = CFrame.new(   0, PICKUP_HEIGHT, -22) },  -- N
	{ weaponKey = "Glock19",     cf = CFrame.new(  16, PICKUP_HEIGHT,  16) },  -- SE
	{ weaponKey = "DesertEagle", cf = CFrame.new( -16, PICKUP_HEIGHT,  16) },  -- SW
	{ weaponKey = "Uzi",         cf = CFrame.new(  16, PICKUP_HEIGHT, -16) },  -- NE
	{ weaponKey = "Mossberg500", cf = CFrame.new( -16, PICKUP_HEIGHT, -16) },  -- NW
	{ weaponKey = "ARPistol",    cf = CFrame.new(  22, PICKUP_HEIGHT,  16) },  -- ESE
	{ weaponKey = "AWP",         cf = CFrame.new( -22, PICKUP_HEIGHT, -16) },  -- WNW
}

-- ============================================================
-- Pickup folder in Workspace
-- ============================================================

local pickupsFolder = Instance.new("Folder")
pickupsFolder.Name   = "WeaponPickups"
pickupsFolder.Parent = Workspace

-- ============================================================
-- Helpers
-- ============================================================

-- Set every BasePart in the model to the given transparency.
local function setModelTransparency(model: Model, t: number)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			(desc :: BasePart).Transparency = t
		end
	end
end

-- Enable or disable every ProximityPrompt in the model.
local function setPromptEnabled(model: Model, enabled: boolean)
	for _, desc in model:GetDescendants() do
		if desc:IsA("ProximityPrompt") then
			(desc :: ProximityPrompt).Enabled = enabled
		end
	end
end

-- ============================================================
-- Initialise all pickups
-- ============================================================

for _, def in PICKUP_DEFS do
	local weapon = WeaponData[def.weaponKey]
	if not weapon then
		warn(("[WeaponPickups] Unknown weaponKey '%s' — skipping"):format(def.weaponKey))
		continue
	end

	-- Clone the physical weapon model from ReplicatedStorage/Weapons
	local template = weaponsFolder:FindFirstChild(def.weaponKey)
	if not template or not template:IsA("Model") then
		warn(("[WeaponPickups] No model found for '%s' in ReplicatedStorage.Weapons — skipping"):format(def.weaponKey))
		continue
	end

	local model: Model = (template :: Model):Clone()
	model.Name         = def.weaponKey

	-- Anchor all parts and disable collision so players walk through
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local bp      = desc :: BasePart
			bp.Anchored   = true
			bp.CanCollide = false
		end
	end

	-- Position model at the pickup CFrame, then parent into the world
	model:PivotTo(def.cf)
	model.Parent = pickupsFolder

	-- ProximityPrompt attaches to Handle; fall back to PrimaryPart if absent
	local handle = (
		model:FindFirstChild("Handle") or model.PrimaryPart
	) :: BasePart?

	if not handle then
		warn(("[WeaponPickups] '%s' model has no Handle or PrimaryPart — skipping"):format(def.weaponKey))
		model:Destroy()
		continue
	end

	local prompt                    = Instance.new("ProximityPrompt")
	prompt.ActionText               = "Equip"
	prompt.ObjectText               = weapon.Name
	prompt.MaxActivationDistance    = 8
	prompt.HoldDuration             = 0
	prompt.RequiresLineOfSight      = false
	prompt.Parent                   = handle

	local weaponKey = def.weaponKey   -- capture for closure

	prompt.Triggered:Connect(function(player: Player)
		if not player.Character then return end

		-- Grant the weapon to the player's inventory via RBX_Toolbox
		RBXToolbox:GiveWeapon(player, weaponKey)

		-- Hide the pickup for RESPAWN_DELAY seconds, then restore it
		setModelTransparency(model, 1)
		setPromptEnabled(model, false)

		task.delay(RESPAWN_DELAY, function()
			setModelTransparency(model, 0)
			setPromptEnabled(model, true)
		end)
	end)
end
