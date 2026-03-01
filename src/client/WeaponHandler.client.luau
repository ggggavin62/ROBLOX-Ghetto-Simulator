--!strict
--[[
	WeaponHandler.client.luau
	Full FPS weapon client — input, ammo, firing, scope, HUD.

	Libraries integrated:
	  FastCast  (src/shared/FastCast.luau)       — physics-simulated bullet tracers
	  Warp      (Packages/Warp)                  — high-performance batched networking
	  HUDState  (StarterPlayerScripts/HUDState)  — Fusion reactive HUD state

	FireMode behaviour:
	  Auto  — fires on every Heartbeat tick while MouseButton1 is held
	  Semi / Pump / Bolt — single shot per fresh click; holding does nothing

	Scope (Sniper-type weapons only):
	  MouseButton2 down → scopeIn (FOV 70 → 20, scope overlay)
	  MouseButton2 up   → scopeOut (FOV 20 → 70)

	Weapon pickups:
	  WeaponPickup (Warp event, server → client) delivers (weaponKey, slot).

	Security: NO damage is ever applied here. WeaponDamage.server.luau
	performs all 7 validation checks before any health change.
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- Cross-LocalScript channel: ViewmodelController listens for weapon changes
local weaponSwitched      = Instance.new("BindableEvent")
weaponSwitched.Name       = "WeaponSwitched"
weaponSwitched.Parent     = LocalPlayer

-- ============================================================
-- Shared modules
-- ============================================================

type Weapon = {
	Name: string, Type: string, Damage: number, FireRate: number,
	MagSize: number, Spread: number, Recoil: number,
	FireMode: string, BulletsPerShot: number,
}

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local WeaponData   = require(sharedFolder:WaitForChild("WeaponData")) :: { [string]: Weapon }
local FastCast: any = require(sharedFolder:WaitForChild("FastCast"))

-- ============================================================
-- Client modules
-- ============================================================

type SoundFXType = {
	playFire:   (string) -> (),
	playReload: (string) -> (),
	playEmpty:  (string) -> (),
}
type VisualFXType = {
	initMuzzleFlash: (ScreenGui) -> (),
	showMuzzleFlash: () -> (),
	showImpact:      (Vector3) -> (),
	initScope:       () -> (),
	scopeIn:         (Frame) -> (),
	scopeOut:        (Frame) -> (),
}

local SoundFX  = require(script.Parent:WaitForChild("SoundFX"))  :: SoundFXType
local VisualFX = require(script.Parent:WaitForChild("VisualFX")) :: VisualFXType
local HUDState = require(script.Parent:WaitForChild("HUDState"))

-- ============================================================
-- Warp networking
-- ============================================================

-- Centralised Warp event objects (identical identifier order to server WarpEvents.luau)
local WarpEvents        = require(script.Parent:WaitForChild("WarpEvents"))
local WeaponFiredEvent  = WarpEvents.WeaponFired
local ReloadStateEvent  = WarpEvents.ReloadState
local WeaponPickupEvent = WarpEvents.WeaponPickup

-- ============================================================
-- Constants
-- ============================================================

local MAX_DIST_BY_TYPE: { [string]: number } = {
	Pistol  = 100,
	SMG     = 80,
	Shotgun = 40,
	Rifle   = 250,
	Sniper  = 600,
}

local RELOAD_TIME_BY_TYPE: { [string]: number } = {
	Pistol  = 1.5,
	SMG     = 2.0,
	Shotgun = 2.5,
	Rifle   = 2.5,
	Sniper  = 3.5,
}

-- Bullet travel speed (studs/s) per weapon type
local BULLET_SPEED: { [string]: number } = {
	Pistol  = 200,
	SMG     = 250,
	Shotgun = 180,
	Rifle   = 400,
	Sniper  = 800,
}

-- Fraction of workspace.Gravity applied as bullet drop
local BULLET_GRAVITY_SCALE: { [string]: number } = {
	Pistol  = 0.05,
	SMG     = 0.03,
	Shotgun = 0.08,
	Rifle   = 0.02,
	Sniper  = 0.01,
}

-- Slot 1 = Primary rifle, Slot 2 = Secondary pistol
local LOADOUT: { string } = { "AK47", "Glock19" }

-- ============================================================
-- FastCast Setup
-- ============================================================

-- Thin neon tracer Part (cloned per bullet by FastCast)
local TRACER_TEMPLATE           = Instance.new("Part")
TRACER_TEMPLATE.Name            = "Tracer"
TRACER_TEMPLATE.Size            = Vector3.new(0.05, 0.05, 1)
TRACER_TEMPLATE.Material        = Enum.Material.Neon
TRACER_TEMPLATE.Color           = Color3.fromRGB(255, 240, 120)
TRACER_TEMPLATE.CastShadow      = false
TRACER_TEMPLATE.CanCollide      = false
TRACER_TEMPLATE.Anchored        = true

local caster: any = FastCast.new()

-- Behaviors are rebuilt on each character spawn to exclude the fresh character
local activeBehaviors: { [string]: any } = {}

local function rebuildBehaviors(character: Model)
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType                 = Enum.RaycastFilterType.Exclude

	for wepType, maxDist in MAX_DIST_BY_TYPE do
		local b = FastCast.newBehavior()
		b.RaycastParams           = rayParams
		b.MaxDistance             = maxDist
		b.Acceleration            = Vector3.new(
			0,
			-workspace.Gravity * (BULLET_GRAVITY_SCALE[wepType] or 0.05),
			0
		)
		b.CosmeticBulletTemplate  = TRACER_TEMPLATE
		b.CosmeticBulletContainer = workspace.Terrain
		activeBehaviors[wepType]  = b
	end
end

-- ── LengthChanged: stretch tracer Part to match bullet segment ─────────────
caster.LengthChanged:Connect(function(
	_cast: any,
	lastPoint: Vector3,
	rayDir: Vector3,
	length: number,
	_vel: Vector3,
	tracerPart: BasePart?
)
	if not tracerPart then return end
	local safeLen = math.max(length, 0.01)
	tracerPart.Size  = Vector3.new(0.05, 0.05, safeLen)
	tracerPart.CFrame = CFrame.new(
		lastPoint + rayDir * (safeLen * 0.5),
		lastPoint + rayDir * safeLen
	)
end)

-- ── RayHit: bullet struck something — notify server + show impact VFX ──────
caster.RayHit:Connect(function(
	cast: any,
	result: RaycastResult,
	_vel: Vector3,
	_tracerPart: BasePart?
)
	cast.UserData.hitDetected = true
	local key = (cast.UserData.weaponKey or "") :: string
	VisualFX.showImpact(result.Position)
	WeaponFiredEvent:Fire(true, key, result.Instance, result.Position, result.Distance)
end)

-- ── CastTerminating: fired for both hits AND misses.
--   Hits are already handled by RayHit; only send a miss if no hit occurred.
caster.CastTerminating:Connect(function(cast: any)
	if cast.UserData.hitDetected then return end
	local key = (cast.UserData.weaponKey or "") :: string
	if key == "" then return end
	-- Send miss to server so server-side ammo is consumed
	WeaponFiredEvent:Fire(true, key, nil, Camera.CFrame.Position, 0)
end)

-- ============================================================
-- State
-- ============================================================

local currentSlot: number                = 1
local canFire: { [string]: boolean }     = {}
local mouseHeld: boolean                 = false
local isScoped: boolean                  = false
local localAmmo: { [string]: number }    = {}
local isReloading: { [string]: boolean } = {}

for _, key in LOADOUT do
	local w = WeaponData[key]
	if w then
		localAmmo[key]   = w.MagSize
		isReloading[key] = false
		canFire[key]     = true
	end
end

-- ============================================================
-- Accessors
-- ============================================================

local function weapon(): Weapon
	return WeaponData[LOADOUT[currentSlot]]
end

local function weaponKey(): string
	return LOADOUT[currentSlot]
end

local function reloadTime(): number
	return RELOAD_TIME_BY_TYPE[weapon().Type] or 2.0
end

local function isSingleShot(): boolean
	local mode = weapon().FireMode
	return mode == "Semi" or mode == "Pump" or mode == "Bolt"
end

-- ============================================================
-- HUD References  (only mainHUD and crosshair — labels are now Fusion-reactive)
-- ============================================================

local playerGui  = LocalPlayer:WaitForChild("PlayerGui")
local mainHUD    = playerGui:WaitForChild("MainHUD") :: ScreenGui
local crosshair  = mainHUD:WaitForChild("Crosshair") :: Frame

-- ============================================================
-- Module Initialisation
-- ============================================================

VisualFX.initMuzzleFlash(mainHUD)
VisualFX.initScope()

-- ============================================================
-- HUD Update — writes Fusion state; HUDController reacts automatically
-- ============================================================

local function buildSlotLine(): string
	local parts: { string } = {}
	for i, key in LOADOUT do
		local w     = WeaponData[key]
		local name  = if w then w.Name else "?"
		local entry = "[" .. tostring(i) .. "] " .. name
		if i == currentSlot then entry = "• " .. entry end
		table.insert(parts, entry)
	end
	return table.concat(parts, "  ")
end

local function updateAmmoUI()
	local key = weaponKey()
	local w   = weapon()

	HUDState.weaponName:set(w.Name)
	HUDState.slotLine:set(buildSlotLine())
	HUDState.ammo:set(localAmmo[key] or 0)
	HUDState.magSize:set(w.MagSize)
	HUDState.isReloading:set(isReloading[key] or false)
end

-- ============================================================
-- Weapon Switching
-- ============================================================

local function switchWeapon(slot: number)
	if slot == currentSlot then return end
	if slot < 1 or slot > #LOADOUT then return end

	-- Cancel scope if leaving a sniper slot
	if isScoped then
		isScoped = false
		VisualFX.scopeOut(crosshair)
	end

	currentSlot          = slot
	canFire[weaponKey()] = true

	crosshair.BackgroundColor3 = Color3.fromRGB(255, 200, 70)
	task.delay(0.15, function()
		crosshair.BackgroundColor3 = Color3.new(0.85, 0.85, 0.85)
	end)

	updateAmmoUI()
	weaponSwitched:Fire(weaponKey())
end

-- ============================================================
-- Reload
-- ============================================================

local function startReload()
	local key = weaponKey()
	local w   = weapon()

	if isReloading[key] then return end
	if (localAmmo[key] or 0) >= w.MagSize then return end

	isReloading[key] = true
	SoundFX.playReload(key)
	updateAmmoUI()

	task.delay(reloadTime(), function()
		if isReloading[key] then
			isReloading[key] = false
			localAmmo[key]   = w.MagSize
			updateAmmoUI()
		end
	end)
end

-- ============================================================
-- Spread
-- ============================================================

local function applySpread(baseDir: Vector3, spreadDeg: number): Vector3
	if spreadDeg <= 0 then return baseDir end
	local spreadRad = math.rad(spreadDeg)
	local angle     = math.random() * math.pi * 2
	local radius    = math.random() * spreadRad
	local right     = Camera.CFrame.RightVector
	local up        = Camera.CFrame.UpVector
	local offset    = (right * math.cos(angle) + up * math.sin(angle)) * math.sin(radius)
	return (baseDir + offset).Unit
end

-- ============================================================
-- Firing — FastCast-based
-- ============================================================

local function tryFire()
	local key = weaponKey()
	local w   = weapon()

	-- Empty-mag: dry-fire click + auto-reload
	if (localAmmo[key] or 0) <= 0 and not isReloading[key] then
		SoundFX.playEmpty(key)
		task.spawn(startReload)
		return
	end

	if not canFire[key] then return end
	if isReloading[key]  then return end

	local character = LocalPlayer.Character
	if not character then return end

	canFire[key] = false
	task.delay(w.FireRate, function()
		canFire[key] = true
	end)

	localAmmo[key] -= 1
	updateAmmoUI()

	SoundFX.playFire(key)
	VisualFX.showMuzzleFlash()

	local origin  = Camera.CFrame.Position
	local look    = Camera.CFrame.LookVector
	local wType   = w.Type
	local behavior = activeBehaviors[wType] or activeBehaviors["Rifle"] or FastCast.newBehavior()
	local speed    = BULLET_SPEED[wType] or 300

	-- Fire one FastCast per pellet (shotgun fires BulletsPerShot pellets)
	for _ = 1, w.BulletsPerShot do
		local dir  = applySpread(look, w.Spread)
		local cast = caster:Fire(origin, dir, speed, behavior)
		-- Attach per-shot metadata; RayHit/CastTerminating handlers read these
		cast.UserData.weaponKey    = key
		cast.UserData.hitDetected  = false
	end

	if (localAmmo[key] or 0) <= 0 then
		task.spawn(startReload)
	end
end

-- ============================================================
-- Auto-fire Loop
-- ============================================================

RunService.Heartbeat:Connect(function()
	if mouseHeld and not isSingleShot() then
		tryFire()
	end
end)

-- ============================================================
-- Server → Client Sync  (Warp per-event objects)
-- ============================================================

-- Server notifies of reload state changes
ReloadStateEvent:Connect(function(
	reloadCompleteRaw: any,
	newMagRaw: any,
	syncKeyRaw: any
)
	local reloadComplete: boolean = if typeof(reloadCompleteRaw) == "boolean"
		then reloadCompleteRaw :: boolean
		else false

	local newMag: number = if typeof(newMagRaw) == "number"
		then newMagRaw :: number
		else 0

	local syncKey: string = if typeof(syncKeyRaw) == "string"
		then syncKeyRaw :: string
		else weaponKey()

	if reloadComplete then
		localAmmo[syncKey]   = newMag
		isReloading[syncKey] = false
	else
		isReloading[syncKey] = true
	end
	updateAmmoUI()
end)

-- Server grants a new weapon (pickup / round start)
WeaponPickupEvent:Connect(function(pickupKeyRaw: any, slotRaw: any)
	local pickupKey: string = if typeof(pickupKeyRaw) == "string"
		then pickupKeyRaw :: string
		else ""

	local slot: number = if typeof(slotRaw) == "number"
		then math.clamp(slotRaw :: number, 1, #LOADOUT)
		else 1

	local w = WeaponData[pickupKey]
	if not w then return end

	LOADOUT[slot] = pickupKey

	if not localAmmo[pickupKey] then
		localAmmo[pickupKey]   = w.MagSize
		isReloading[pickupKey] = false
		canFire[pickupKey]     = true
	end

	if slot == currentSlot then
		updateAmmoUI()
		weaponSwitched:Fire(pickupKey)
	end
end)

-- ============================================================
-- Input
-- ============================================================

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = true
		tryFire()

	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if weapon().Type == "Sniper" and not isScoped then
			isScoped = true
			VisualFX.scopeIn(crosshair)
		end

	elseif input.KeyCode == Enum.KeyCode.R then
		startReload()

	elseif input.KeyCode == Enum.KeyCode.One   then switchWeapon(1)
	elseif input.KeyCode == Enum.KeyCode.Two   then switchWeapon(2)
	elseif input.KeyCode == Enum.KeyCode.Three then switchWeapon(3)
	elseif input.KeyCode == Enum.KeyCode.Four  then switchWeapon(4)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if isScoped then
			isScoped = false
			VisualFX.scopeOut(crosshair)
		end
	end
end)

UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local delta   = -math.sign(input.Position.Z)
		local newSlot = ((currentSlot - 1 + delta) % #LOADOUT) + 1
		switchWeapon(newSlot)
	end
end)

-- ============================================================
-- Character Setup
-- ============================================================

local function onCharacterAdded(character: Model)
	Camera.CameraMode = Enum.CameraMode.LockFirstPerson

	if isScoped then
		isScoped = false
		VisualFX.scopeOut(crosshair)
	end

	-- Rebuild FastCast behaviors with fresh character exclusion filter
	rebuildBehaviors(character)

	for _, key in LOADOUT do
		local w = WeaponData[key]
		if w then
			localAmmo[key]   = w.MagSize
			isReloading[key] = false
			canFire[key]     = true
		end
	end
	mouseHeld   = false
	currentSlot = 1
	updateAmmoUI()
	weaponSwitched:Fire(weaponKey())
end

-- ============================================================
-- Bootstrap
-- ============================================================

if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
