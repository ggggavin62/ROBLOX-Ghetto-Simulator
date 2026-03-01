--!strict
--[[
	WeaponPickups.server.luau  (Script — ServerScriptService)

	Spawns 8 weapon pickup parts around the map arena.
	Each pickup has:
	  • A coloured Part (weapon indicator colour by type)
	  • A BillboardGui showing the weapon name
	  • A ProximityPrompt ("Pick Up [WeaponName]")

	When a player triggers the prompt:
	  1. Slot 1 (primary) is replaced with the picked-up weapon.
	  2. WeaponPickup:FireClient sends (player, weaponKey, 1).
	  3. The pickup disappears for 30 s then respawns.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace           = game:GetService("Workspace")

local WeaponData = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponData")
) :: { [string]: { Name: string, Type: string, Damage: number, FireRate: number,
	MagSize: number, Spread: number, Recoil: number, FireMode: string, BulletsPerShot: number } }

-- Centralised Warp events (all identifiers registered in WarpEvents.luau)
local WarpEvents        = require(ServerScriptService:WaitForChild("WarpEvents"))
local WeaponPickupEvent = WarpEvents.WeaponPickup

-- ============================================================
-- Constants
-- ============================================================

local RESPAWN_DELAY = 30   -- seconds before a pickup reappears
local PICKUP_SIZE   = Vector3.new(1.5, 0.4, 3.5)
local PICKUP_HEIGHT = 1.0  -- studs above ground

-- Colour coding by weapon type
local TYPE_COLOUR: { [string]: Color3 } = {
	Pistol  = Color3.fromRGB(180, 180, 180),  -- grey
	SMG     = Color3.fromRGB(80,  160, 220),  -- blue
	Shotgun = Color3.fromRGB(200, 100, 50),   -- orange
	Rifle   = Color3.fromRGB(60,  180, 80),   -- green
	Sniper  = Color3.fromRGB(220, 60,  60),   -- red
}

-- 8 pickup definitions: { weaponKey, CFrame }
-- Positions assume a ~100-stud square arena centred at origin.
-- Adjust these to match your actual map layout.
type PickupDef = {
	weaponKey: string,
	cf:        CFrame,
}

local PICKUP_DEFS: { PickupDef } = {
	{ weaponKey = "AK47",        cf = CFrame.new( 40,  PICKUP_HEIGHT,   0) },
	{ weaponKey = "SCARL",       cf = CFrame.new(-40,  PICKUP_HEIGHT,   0) },
	{ weaponKey = "AWP",         cf = CFrame.new(  0,  PICKUP_HEIGHT,  45) },
	{ weaponKey = "Mossberg500", cf = CFrame.new(  0,  PICKUP_HEIGHT, -45) },
	{ weaponKey = "KrissVector", cf = CFrame.new( 35,  PICKUP_HEIGHT,  35) },
	{ weaponKey = "MAC10",       cf = CFrame.new(-35,  PICKUP_HEIGHT,  35) },
	{ weaponKey = "DesertEagle", cf = CFrame.new( 35,  PICKUP_HEIGHT, -35) },
	{ weaponKey = "ARPistol",    cf = CFrame.new(-35,  PICKUP_HEIGHT, -35) },
}

-- ============================================================
-- Pickup folder in Workspace
-- ============================================================

local pickupsFolder = Instance.new("Folder")
pickupsFolder.Name   = "WeaponPickups"
pickupsFolder.Parent = Workspace

-- ============================================================
-- Factories
-- ============================================================

local function makeBillboard(parent: BasePart, weaponName: string): BillboardGui
	local bg                  = Instance.new("BillboardGui")
	bg.Name                   = "Label"
	bg.Size                   = UDim2.new(0, 140, 0, 36)
	bg.StudsOffset            = Vector3.new(0, 2.4, 0)
	bg.AlwaysOnTop            = false
	bg.ResetOnSpawn           = false
	bg.Parent                 = parent

	local label               = Instance.new("TextLabel")
	label.Size                = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3    = Color3.fromRGB(15, 15, 15)
	label.BackgroundTransparency = 0.35
	label.TextColor3          = Color3.new(1, 1, 1)
	label.Font                = Enum.Font.GothamBold
	label.TextSize            = 14
	label.Text                = weaponName
	label.Parent              = bg

	local corner              = Instance.new("UICorner")
	corner.CornerRadius       = UDim.new(0, 6)
	corner.Parent             = label

	return bg
end

local function makePickupPart(def: PickupDef): BasePart
	local weapon     = WeaponData[def.weaponKey]
	local colour     = TYPE_COLOUR[weapon.Type] or Color3.new(1, 1, 1)

	local part            = Instance.new("Part")
	part.Name             = def.weaponKey
	part.Size             = PICKUP_SIZE
	part.CFrame           = def.cf
	part.Anchored         = true
	part.CanCollide       = false
	part.CastShadow       = false
	part.Material         = Enum.Material.Neon
	part.Color            = colour
	part.Parent           = pickupsFolder

	-- Spinning highlight via a SelectionBox-style visual (lightweight)
	local selBox          = Instance.new("SelectionBox")
	selBox.Adornee        = part
	selBox.Color3         = colour
	selBox.LineThickness  = 0.04
	selBox.SurfaceTransparency = 1
	selBox.Parent         = part

	makeBillboard(part, weapon.Name)

	local prompt              = Instance.new("ProximityPrompt")
	prompt.ActionText         = "Pick Up"
	prompt.ObjectText         = weapon.Name
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration       = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent             = part

	return part
end

-- ============================================================
-- Pickup logic
-- ============================================================

local function hidePickup(part: BasePart)
	part.Transparency = 1
	part.CanCollide   = false
	for _, child in part:GetChildren() do
		if child:IsA("ProximityPrompt") then
			(child :: ProximityPrompt).Enabled = false
		elseif child:IsA("BillboardGui") then
			child.Enabled = false
		end
	end
end

local function showPickup(part: BasePart)
	part.Transparency = 0
	part.CanCollide   = false  -- stay non-collidable; players walk through
	for _, child in part:GetChildren() do
		if child:IsA("ProximityPrompt") then
			(child :: ProximityPrompt).Enabled = true
		elseif child:IsA("BillboardGui") then
			child.Enabled = true
		end
	end
end

local function onPromptTriggered(part: BasePart, weaponKey: string, player: Player)
	local character = player.Character
	if not character then return end

	-- Slot 1 = primary; fire pickup event to client via Warp
	WeaponPickupEvent:Fire(true, player, weaponKey, 1)

	-- Hide pickup; respawn after delay
	hidePickup(part)
	task.delay(RESPAWN_DELAY, function()
		showPickup(part)
	end)
end

-- ============================================================
-- Initialise all pickups
-- ============================================================

for _, def in PICKUP_DEFS do
	local part = makePickupPart(def)
	local weaponKey = def.weaponKey

	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(player: Player)
		onPromptTriggered(part, weaponKey, player)
	end)
end
