--!strict
--[[
	WeaponDamage.server.luau
	Sole authority for applying player weapon damage.

	Networking: Warp (Packages/Warp) — high-performance batched RemoteEvent replacement.
	  All event names are registered via reg_namespaces() at startup.

	Validation chain (all checks must pass in order):
	  1. Valid weaponKey  — must exist in WeaponData
	  2. Rate limit       — elapsed >= weapon.FireRate since last shot
	  3. Shooter alive    — humanoid.Health > 0
	  4. Client distance  — clientDistance <= type max distance
	  5. Server ammo      — mag > 0 and not reloading
	  6. Server LOS       — independent raycast confirms the hit position
	  7. Valid target     — hitPart belongs to a player or NPC model

	Ammo state is per-player AND per-weapon — never sourced from the client.
	WeaponFired payload: (weaponKey, hitPart?, hitPosition, clientDistance)
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ============================================================
-- WeaponData
-- ============================================================

type Weapon = {
	Name: string, Type: string, Damage: number, FireRate: number,
	MagSize: number, Spread: number, Recoil: number,
	FireMode: string, BulletsPerShot: number,
}

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local WeaponData   = require(sharedFolder:WaitForChild("WeaponData")) :: { [string]: Weapon }

-- ============================================================
-- Warp Networking  (centralised via WarpEvents module)
-- ============================================================

-- WarpEvents registers ALL identifiers in the correct order in one place.
-- Lua module caching ensures Warp.Server("X") is called exactly once per ID.
local WarpEvents        = require(ServerScriptService:WaitForChild("WarpEvents"))
local WeaponFiredEvent  = WarpEvents.WeaponFired
local ReloadStateEvent  = WarpEvents.ReloadState
local HitConfirmedEvent = WarpEvents.HitConfirmed
local KillFeedEvent     = WarpEvents.KillFeed
-- WeaponPickup is fired from WeaponPickups.server.luau via the same WarpEvents module

-- ============================================================
-- Constants
-- ============================================================

local HEADSHOT_MULTIPLIER: number = 2.0   -- single-bullet weapons only
local LOS_TOLERANCE: number       = 5     -- max stud delta between server/client hit positions
local DIST_MISMATCH_TOL: number   = 15    -- max stud delta between client dist and server geometry

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

local function getMaxDist(weaponType: string): number
	return MAX_DIST_BY_TYPE[weaponType] or 150
end

local function getReloadTime(weaponType: string): number
	return RELOAD_TIME_BY_TYPE[weaponType] or 2.0
end

-- ============================================================
-- Bindable Events (server-internal)
-- ============================================================

local serverEvents   = ServerScriptService:WaitForChild("ServerEvents")
local KillRegistered = serverEvents:WaitForChild("KillRegistered") :: BindableEvent

-- ============================================================
-- Server-Authoritative Ammo State
-- ============================================================

type AmmoState = {
	mag: number,
	isReloading: boolean,
}

-- playerAmmo[player][weaponKey] = AmmoState
local playerAmmo:   { [Player]: { [string]: AmmoState } } = {}
local lastFireTime: { [Player]: { [string]: number } }    = {}

local function initPlayer(player: Player)
	playerAmmo[player]   = {}
	lastFireTime[player] = {}
	for key, w in WeaponData do
		playerAmmo[player][key]   = { mag = w.MagSize, isReloading = false }
		lastFireTime[player][key] = 0
	end
end

local function cleanupPlayer(player: Player)
	playerAmmo[player]   = nil :: any
	lastFireTime[player] = nil :: any
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)

-- Studio Play Solo edge case
for _, player in Players:GetPlayers() do
	initPlayer(player)
end

-- ============================================================
-- Server-Side Reload
-- ============================================================

local function serverReload(player: Player, key: string)
	local ammoMap = playerAmmo[player]
	if not ammoMap then return end

	local ammo = ammoMap[key]
	local w    = WeaponData[key]
	if not ammo or not w then return end
	if ammo.isReloading then return end
	if ammo.mag >= w.MagSize then return end

	ammo.isReloading = true
	-- Notify client: reload started (reloadComplete = false)
	ReloadStateEvent:Fire(true, player, false, ammo.mag, key)

	task.delay(getReloadTime(w.Type), function()
		local currentMap = playerAmmo[player]
		if not currentMap then return end   -- player left during reload
		local current = currentMap[key]
		if not current then return end
		current.mag         = w.MagSize
		current.isReloading = false
		-- Notify client: reload complete (reloadComplete = true)
		ReloadStateEvent:Fire(true, player, true, w.MagSize, key)
	end)
end

-- ============================================================
-- Helpers
-- ============================================================

local npcFolder: Folder? = workspace:FindFirstChild("NPCs") :: Folder?

local function isValidTarget(hitPart: BasePart): boolean
	local character = hitPart:FindFirstAncestorOfClass("Model")
	if not character then return false end
	if Players:GetPlayerFromCharacter(character) then return true end
	if npcFolder and character:IsDescendantOf(npcFolder) then return true end
	return false
end

local function getCharacterHumanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function applyDamage(
	hitPart: BasePart,
	baseDamage: number,
	bulletsPerShot: number
): (number, boolean)
	local character = hitPart:FindFirstAncestorOfClass("Model")
	if not character then return 0, false end

	local humanoid = getCharacterHumanoid(character)
	if not humanoid or humanoid.Health <= 0 then return 0, false end

	local damage = baseDamage * bulletsPerShot

	-- Headshot bonus: single-bullet weapons only (not shotguns)
	if hitPart.Name == "Head" and bulletsPerShot == 1 then
		damage = math.floor(damage * HEADSHOT_MULTIPLIER)
	end

	humanoid:TakeDamage(damage)
	return damage, humanoid.Health <= 0
end

-- ============================================================
-- Damage Handler  (Warp — replaces WeaponFired.OnServerEvent)
-- ============================================================

WeaponFiredEvent:Connect(function(
	shooter: Player,
	weaponKeyRaw: any,
	hitPartRaw: any,
	hitPositionRaw: any,
	clientDistanceRaw: any
)
	-- ── Type-guard client arguments ────────────────────────────────────────
	local weaponKey: string = if typeof(weaponKeyRaw) == "string"
		then weaponKeyRaw :: string
		else ""

	local hitPart: BasePart? = if typeof(hitPartRaw) == "Instance" and
		(hitPartRaw :: Instance):IsA("BasePart")
		then hitPartRaw :: BasePart
		else nil

	local hitPosition: Vector3 = if typeof(hitPositionRaw) == "Vector3"
		then hitPositionRaw :: Vector3
		else Vector3.zero

	local clientDistance: number = if typeof(clientDistanceRaw) == "number"
		then clientDistanceRaw :: number
		else math.huge

	-- ── Check 1: Valid weapon key ──────────────────────────────────────────
	local w = WeaponData[weaponKey]
	if not w then
		warn(("[WeaponDamage] Unknown weaponKey '%s' from %s"):format(weaponKey, shooter.Name))
		return
	end

	-- ── Check 2: Rate limit ────────────────────────────────────────────────
	local now     = tick()
	local fireMap = lastFireTime[shooter]
	if not fireMap then return end

	local lastShot = fireMap[weaponKey] or 0
	if (now - lastShot) < w.FireRate then
		warn(("[WeaponDamage] Rate limit: %s fired %s too fast"):format(shooter.Name, weaponKey))
		return
	end

	-- ── Check 3: Shooter alive ─────────────────────────────────────────────
	local shooterChar = shooter.Character
	if not shooterChar then return end

	local shooterHumanoid = getCharacterHumanoid(shooterChar)
	if not shooterHumanoid or shooterHumanoid.Health <= 0 then return end

	-- ── Check 4: Client distance ───────────────────────────────────────────
	local weaponMaxDist = getMaxDist(w.Type)
	if clientDistance > weaponMaxDist then
		warn(("[WeaponDamage] Distance out of range for %s (%s): %.1f studs"):format(
			shooter.Name, weaponKey, clientDistance))
		return
	end

	-- ── Check 5: Server ammo ───────────────────────────────────────────────
	local ammoMap = playerAmmo[shooter]
	if not ammoMap then return end

	local ammo = ammoMap[weaponKey]
	if not ammo then return end
	if ammo.isReloading then return end
	if ammo.mag <= 0 then return end

	-- Consume ammo and stamp fire time BEFORE raycast
	fireMap[weaponKey] = now
	ammo.mag -= 1

	if ammo.mag <= 0 then
		task.spawn(serverReload, shooter, weaponKey)
	end

	-- Miss: no hitPart — ammo consumed, done
	if not hitPart then return end

	-- ── Check 6: Server-side LOS raycast ──────────────────────────────────
	local hrp = shooterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	local eyePos     = hrp.Position + Vector3.new(0, 1.5, 0)
	local hitVec     = hitPosition - eyePos
	local serverDist = hitVec.Magnitude

	if math.abs(serverDist - clientDistance) > DIST_MISMATCH_TOL then
		warn(("[WeaponDamage] Distance mismatch for %s (client %.1f, server %.1f)"):format(
			shooter.Name, clientDistance, serverDist))
		return
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { shooterChar }
	rayParams.FilterType                 = Enum.RaycastFilterType.Exclude

	local serverResult = workspace:Raycast(eyePos, hitVec.Unit * weaponMaxDist, rayParams)
	if not serverResult then
		warn(("[WeaponDamage] Server LOS blocked for %s"):format(shooter.Name))
		return
	end

	local posDiff = (serverResult.Position - hitPosition).Magnitude
	if posDiff > LOS_TOLERANCE then
		warn(("[WeaponDamage] Hit position mismatch for %s: %.2f studs"):format(
			shooter.Name, posDiff))
		return
	end

	-- ── Check 7: Valid target ──────────────────────────────────────────────
	if not isValidTarget(hitPart) then
		warn(("[WeaponDamage] Invalid target from %s: %s"):format(
			shooter.Name, hitPart:GetFullName()))
		return
	end

	-- ── All checks passed → apply damage ──────────────────────────────────
	local isHeadshot       = hitPart.Name == "Head"
	local damage, killed   = applyDamage(hitPart, w.Damage, w.BulletsPerShot)
	if damage <= 0 then return end

	-- Notify shooter: hit confirmed (drives hit-marker on client)
	HitConfirmedEvent:Fire(true, shooter, damage, isHeadshot)

	if not killed then return end

	-- ── Kill processing ────────────────────────────────────────────────────
	local hitCharacter = hitPart:FindFirstAncestorOfClass("Model")
	local victimName   = if hitCharacter then hitCharacter.Name else "Unknown"

	local killerStats = shooter:FindFirstChild("leaderstats")
	if killerStats then
		local killsVal = killerStats:FindFirstChild("Kills")
		if killsVal and killsVal:IsA("IntValue") then
			(killsVal :: IntValue).Value += 1
		end
	end

	if hitCharacter then
		local victim = Players:GetPlayerFromCharacter(hitCharacter)
		if victim then
			victimName = victim.Name
			local victimStats = victim:FindFirstChild("leaderstats")
			if victimStats then
				local deathsVal = victimStats:FindFirstChild("Deaths")
				if deathsVal and deathsVal:IsA("IntValue") then
					(deathsVal :: IntValue).Value += 1
				end
			end
		end
	end

	-- Broadcast kill to all clients (kill feed UI)
	KillFeedEvent:Fires(true, shooter.Name, victimName)

	-- Notify server-side round manager
	KillRegistered:Fire(shooter.Name, victimName)
end)
