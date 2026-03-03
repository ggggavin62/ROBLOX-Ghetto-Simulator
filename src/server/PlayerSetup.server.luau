--!strict
--[[
	PlayerSetup.server.luau  (Script — ServerScriptService)

	Runs once per player join and once per character spawn.

	PlayerAdded:
	  • Creates the leaderstats folder (Kills, Deaths IntValues) so the
	    server scoreboard and WeaponDamage.server can read and write them.

	CharacterAdded:
	  • Waits for the character Humanoid to be ready.
	  • Fires WeaponPickup to the client for each slot of the default loadout
	    so WeaponHandler.client resets its LOADOUT table on every respawn,
	    regardless of any pickups collected in the previous life.

	Note: weapon-kill Deaths are incremented by WeaponDamage.server.luau;
	this script only creates the IntValue containers.
]]

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Warp event registry — identical identifier order to src/client/WarpEvents.luau
local WarpEvents        = require(ServerScriptService:WaitForChild("WarpEvents"))
local WeaponPickupEvent = WarpEvents.WeaponPickup

-- Default loadout granted on every spawn.
-- Slot 1 = primary rifle, Slot 2 = sidearm.
-- Must match the LOADOUT table hardcoded in WeaponHandler.client.luau.
local DEFAULT_LOADOUT: { string } = { "AK47", "Glock19" }

-- ============================================================
-- Leaderstats
-- ============================================================

local function createLeaderstats(player: Player)
	local ls     = Instance.new("Folder")
	ls.Name      = "leaderstats"
	ls.Parent    = player

	local kills  = Instance.new("IntValue")
	kills.Name   = "Kills"
	kills.Value  = 0
	kills.Parent = ls

	local deaths  = Instance.new("IntValue")
	deaths.Name   = "Deaths"
	deaths.Value  = 0
	deaths.Parent = ls
end

-- ============================================================
-- Character Spawn — reset loadout to defaults
-- ============================================================

local function onCharacterAdded(player: Player, character: Model)
	-- Wait until the Humanoid exists so the character is fully replicated
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then return end

	-- Give WeaponHandler.client.onCharacterAdded a head-start so it can
	-- set up FastCast behaviors and ammo state before we overwrite LOADOUT.
	task.wait(0.15)

	-- Re-grant the default weapons so the client LOADOUT resets on respawn.
	-- WeaponPickupEvent: Fire(true, player, weaponKey, slot)
	for slot, weaponKey in ipairs(DEFAULT_LOADOUT) do
		WeaponPickupEvent:Fire(true, player, weaponKey, slot)
	end
end

-- ============================================================
-- Player hooks
-- ============================================================

local function onPlayerAdded(player: Player)
	createLeaderstats(player)

	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(onCharacterAdded, player, character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Studio Play Solo: local player may already exist when this script starts
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
