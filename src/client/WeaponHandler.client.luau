--!strict
--[[
	WeaponHandler.client.luau
	Full FPS weapon client — input, ammo, firing, scope, HUD.

	Modules required:
	  SoundFX  (StarterPlayerScripts/SoundFX) — fire / reload / empty sounds
	  VisualFX (StarterPlayerScripts/VisualFX) — muzzle flash, impact, scope

	FireMode behaviour:
	  Auto  — fires on every Heartbeat tick while MouseButton1 is held
	  Semi / Pump / Bolt — single shot per fresh click; holding does nothing

	Scope (Sniper-type weapons only):
	  MouseButton2 down → scopeIn (FOV 70 → 20, scope overlay)
	  MouseButton2 up   → scopeOut (FOV 20 → 70)
	  Switching away from a sniper while scoped auto-cancels scope.

	Weapon pickups:
	  WeaponPickup RemoteEvent (server → client) delivers (weaponKey, slot).
	  Client replaces LOADOUT[slot] and initialises ammo for the new weapon.

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
-- Weapon type (re-declared locally for strict-mode compat)
-- ============================================================

type Weapon = {
	Name: string, Type: string, Damage: number, FireRate: number,
	MagSize: number, Spread: number, Recoil: number,
	FireMode: string, BulletsPerShot: number,
}

-- ============================================================
-- Shared module
-- ============================================================

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local WeaponData   = require(sharedFolder:WaitForChild("WeaponData")) :: { [string]: Weapon }

-- ============================================================
-- Client modules (ModuleScripts in same StarterPlayerScripts folder)
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

-- ============================================================
-- Remote Events
-- ============================================================

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local WeaponFired  = eventsFolder:WaitForChild("WeaponFired")  :: RemoteEvent
local ReloadState  = eventsFolder:WaitForChild("ReloadState")  :: RemoteEvent
local WeaponPickup = eventsFolder:WaitForChild("WeaponPickup") :: RemoteEvent

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

-- Slot 1 = Primary rifle, Slot 2 = Secondary pistol
local LOADOUT: { string } = { "AK47", "Glock19" }

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

local function maxDist(): number
	return MAX_DIST_BY_TYPE[weapon().Type] or 150
end

local function reloadTime(): number
	return RELOAD_TIME_BY_TYPE[weapon().Type] or 2.0
end

local function isSingleShot(): boolean
	local mode = weapon().FireMode
	return mode == "Semi" or mode == "Pump" or mode == "Bolt"
end

-- ============================================================
-- HUD References  (elements created by HUDController.client.luau)
-- ============================================================
-- WaitForChild blocks until HUDController has finished building MainHUD.

local playerGui       = LocalPlayer:WaitForChild("PlayerGui")
local mainHUD         = playerGui:WaitForChild("MainHUD") :: ScreenGui
local crosshair          = mainHUD:WaitForChild("Crosshair")          :: Frame
local weaponNameLabel    = mainHUD:WaitForChild("WeaponNameLabel")    :: TextLabel
local ammoLabel          = mainHUD:WaitForChild("AmmoLabel")          :: TextLabel
local slotLabel          = mainHUD:WaitForChild("SlotLabel")          :: TextLabel
local weaponCentreLabel  = mainHUD:WaitForChild("WeaponCentreLabel")  :: TextLabel

-- ============================================================
-- Module Initialisation
-- ============================================================

VisualFX.initMuzzleFlash(mainHUD)
VisualFX.initScope()

-- ============================================================
-- HUD Update
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

	weaponNameLabel.Text    = w.Name
	weaponCentreLabel.Text  = w.Name
	slotLabel.Text          = buildSlotLine()

	if isReloading[key] then
		ammoLabel.Text       = "RELOADING..."
		ammoLabel.TextColor3 = Color3.fromRGB(200, 175, 60)
	else
		local mag = localAmmo[key] or 0
		ammoLabel.Text = tostring(mag) .. " / " .. tostring(w.MagSize)
		ammoLabel.TextColor3 = if mag <= math.floor(w.MagSize * 0.25)
			then Color3.fromRGB(220, 70, 70)
			else Color3.new(1, 1, 1)
	end
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
-- Firing
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
	if isReloading[key] then return end

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

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType                 = Enum.RaycastFilterType.Exclude

	local origin   = Camera.CFrame.Position
	local baseLook = Camera.CFrame.LookVector
	local dist     = maxDist()

	local npcFolder = workspace:FindFirstChild("NPCs")

	local bestPart: BasePart? = nil
	local bestPos: Vector3    = origin + baseLook * dist
	local bestDist: number    = dist + 1

	for _ = 1, w.BulletsPerShot do
		local dir    = applySpread(baseLook, w.Spread) * dist
		local result = workspace:Raycast(origin, dir, rayParams)

		if result then
			local hitInst = result.Instance :: BasePart
			local hitChar = hitInst:FindFirstAncestorOfClass("Model")
			local isChar  = hitChar ~= nil and (
				game:GetService("Players"):GetPlayerFromCharacter(hitChar) ~= nil
				or (npcFolder ~= nil and hitChar:IsDescendantOf(npcFolder :: Instance))
			)

			if isChar and result.Distance < bestDist then
				bestPart  = hitInst
				bestPos   = result.Position
				bestDist  = result.Distance
			elseif bestPart == nil then
				bestPart  = hitInst
				bestPos   = result.Position
				bestDist  = result.Distance
			end
		end
	end

	if bestPart then
		VisualFX.showImpact(bestPos)
		WeaponFired:FireServer(key, bestPart, bestPos, bestDist)
	else
		WeaponFired:FireServer(key, nil, origin + baseLook * dist, dist)
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
-- Server → Client Sync
-- ============================================================

ReloadState.OnClientEvent:Connect(function(
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

WeaponPickup.OnClientEvent:Connect(function(pickupKeyRaw: any, slotRaw: any)
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
	-- Health bar is updated by HUDController.client.luau
end

-- ============================================================
-- Bootstrap
-- ============================================================

if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
