--!strict
--[[
	Leaderstats.server.luau
	Creates "Kills" and "Deaths" IntValues under each Player's "leaderstats"
	Folder on join. Roblox reads this folder automatically and displays it
	on the in-game leaderboard.

	NOTE: Kills and Deaths are incremented in WeaponDamage.server.luau,
	which has full kill context. This script only handles setup/teardown.
]]

local Players = game:GetService("Players")

-- ============================================================
-- Setup
-- ============================================================

local function setupLeaderstats(player: Player)
	local leaderstats      = Instance.new("Folder")
	leaderstats.Name       = "leaderstats"
	leaderstats.Parent     = player

	local kills            = Instance.new("IntValue")
	kills.Name             = "Kills"
	kills.Value            = 0
	kills.Parent           = leaderstats

	local deaths           = Instance.new("IntValue")
	deaths.Name            = "Deaths"
	deaths.Value           = 0
	deaths.Parent          = leaderstats
end

Players.PlayerAdded:Connect(setupLeaderstats)

-- Handle players already in-game (Studio Play Solo edge case)
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end
