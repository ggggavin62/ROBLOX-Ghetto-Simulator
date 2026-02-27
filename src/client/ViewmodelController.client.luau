--!strict
--[[
	ViewmodelController.client.luau  (LocalScript — StarterPlayerScripts)

	Renders a physical first-person gun model parented to the camera.

	Listens for the "WeaponSwitched" BindableEvent (created + fired by
	WeaponHandler) and rebuilds the Part assembly to match the current
	weapon type.

	The assembly is parented to workspace.CurrentCamera so it renders
	in front of world geometry and never depth-fights terrain/walls.

	Gun shapes:
	  Handle  — gun body (PrimaryPart, positioned each RenderStepped)
	  Barrel  — welded to Handle, extends forward
	  Grip    — welded to Handle, angled downward at rear

	Weapon type → GUN_SPECS → body/barrel/grip dimensions + colour.
	Weapon type → GUN_OFFSETS → camera-relative CFrame offset.
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ============================================================
-- Shared weapon config
-- ============================================================

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")

type WeaponEntry = {
	Name: string, Type: string, Damage: number, FireRate: number,
	MagSize: number, Spread: number, Recoil: number,
	FireMode: string, BulletsPerShot: number,
}

local WeaponConfig = require(sharedFolder:WaitForChild("WeaponData")) :: { [string]: WeaponEntry }

-- ============================================================
-- Cross-script channel — WeaponHandler fires when weapon changes
-- ============================================================

local weaponSwitched = LocalPlayer:WaitForChild("WeaponSwitched") :: BindableEvent

-- ============================================================
-- Camera offsets per weapon type
-- ============================================================

local GUN_OFFSETS: { [string]: CFrame } = {
	Pistol  = CFrame.new( 0.40, -0.35, -0.90),
	SMG     = CFrame.new( 0.45, -0.35, -1.00),
	Shotgun = CFrame.new( 0.50, -0.40, -1.10),
	Rifle   = CFrame.new( 0.55, -0.40, -1.30),
	Sniper  = CFrame.new( 0.55, -0.40, -1.45),
}

-- ============================================================
-- Gun appearance per weapon type
-- ============================================================

type GunSpec = {
	bodySize   : Vector3,
	bodyColor  : Color3,
	barrelSize : Vector3,
}

local GUN_SPECS: { [string]: GunSpec } = {
	Pistol  = {
		bodySize   = Vector3.new(0.20, 0.24, 0.50),
		bodyColor  = Color3.fromRGB(45, 45, 45),
		barrelSize = Vector3.new(0.10, 0.10, 0.28),
	},
	SMG     = {
		bodySize   = Vector3.new(0.20, 0.26, 0.65),
		bodyColor  = Color3.fromRGB(40, 40, 40),
		barrelSize = Vector3.new(0.10, 0.10, 0.30),
	},
	Shotgun = {
		bodySize   = Vector3.new(0.22, 0.28, 0.70),
		bodyColor  = Color3.fromRGB(80, 55, 30),
		barrelSize = Vector3.new(0.10, 0.10, 0.45),
	},
	Rifle   = {
		bodySize   = Vector3.new(0.20, 0.26, 0.85),
		bodyColor  = Color3.fromRGB(35, 35, 35),
		barrelSize = Vector3.new(0.09, 0.09, 0.50),
	},
	Sniper  = {
		bodySize   = Vector3.new(0.18, 0.26, 1.00),
		bodyColor  = Color3.fromRGB(30, 30, 30),
		barrelSize = Vector3.new(0.07, 0.07, 0.70),
	},
}

-- ============================================================
-- State
-- ============================================================

local currentModel:      Model? = nil
local currentWeaponType: string = "Rifle"

-- ============================================================
-- Model builder
-- ============================================================

local function destroyModel()
	if currentModel then
		currentModel:Destroy()
		currentModel = nil
	end
end

local function buildGunModel(weaponType: string): Model
	local spec  = GUN_SPECS[weaponType] or GUN_SPECS["Rifle"] :: GunSpec
	local model = Instance.new("Model")
	model.Name  = "Viewmodel_Gun"

	-- ── Body (PrimaryPart / Handle) ─────────────────────────
	local body           = Instance.new("Part")
	body.Name            = "Handle"
	body.Size            = spec.bodySize
	body.Color           = spec.bodyColor
	body.Material        = Enum.Material.SmoothPlastic
	body.CastShadow      = false
	body.CanCollide      = false
	body.Anchored        = false
	body.Parent          = model

	-- ── Barrel ──────────────────────────────────────────────
	local barrel         = Instance.new("Part")
	barrel.Name          = "Barrel"
	barrel.Size          = spec.barrelSize
	barrel.Color         = Color3.fromRGB(22, 22, 22)
	barrel.Material      = Enum.Material.SmoothPlastic
	barrel.CastShadow    = false
	barrel.CanCollide    = false
	barrel.Anchored      = false
	barrel.Parent        = model

	local barrelWeld     = Instance.new("Weld")
	barrelWeld.Part0     = body
	barrelWeld.Part1     = barrel
	barrelWeld.C0        = CFrame.new(
		0, 0,
		-(spec.bodySize.Z * 0.5 + spec.barrelSize.Z * 0.5)
	)
	barrelWeld.Parent    = body

	-- ── Grip ────────────────────────────────────────────────
	local gripH          = spec.bodySize.Y * 0.9
	local gripD          = spec.bodySize.Z * 0.28

	local grip           = Instance.new("Part")
	grip.Name            = "Grip"
	grip.Size            = Vector3.new(spec.bodySize.X, gripH, gripD)
	grip.Color           = spec.bodyColor
	grip.Material        = Enum.Material.SmoothPlastic
	grip.CastShadow      = false
	grip.CanCollide      = false
	grip.Anchored        = false
	grip.Parent          = model

	local gripWeld       = Instance.new("Weld")
	gripWeld.Part0       = body
	gripWeld.Part1       = grip
	-- Hang grip below and slightly rearward of body centre
	gripWeld.C0          = CFrame.new(
		0,
		-(spec.bodySize.Y * 0.5 + gripH * 0.35),
		spec.bodySize.Z * 0.22
	) * CFrame.Angles(math.rad(15), 0, 0)
	gripWeld.Parent      = body

	model.PrimaryPart    = body
	model.Parent         = Camera

	return model
end

-- ============================================================
-- Weapon switch handler
-- ============================================================

local function onWeaponSwitched(weaponKeyRaw: any)
	local weaponKey: string = if typeof(weaponKeyRaw) == "string"
		then weaponKeyRaw :: string
		else ""

	local entry      = WeaponConfig[weaponKey]
	local weaponType = if entry then entry.Type else "Rifle"

	currentWeaponType = weaponType
	destroyModel()
	currentModel = buildGunModel(weaponType)
end

weaponSwitched.Event:Connect(onWeaponSwitched)

-- ============================================================
-- RenderStepped — pin model to camera each frame
-- ============================================================

RunService.RenderStepped:Connect(function()
	if not currentModel or not currentModel.PrimaryPart then return end
	local offset = GUN_OFFSETS[currentWeaponType] or GUN_OFFSETS["Rifle"]
	currentModel:PivotTo(Camera.CFrame * offset)
end)

-- ============================================================
-- Character respawn — clear viewmodel until next WeaponSwitched
-- ============================================================

LocalPlayer.CharacterAdded:Connect(function()
	currentWeaponType = "Rifle"
	destroyModel()
end)
