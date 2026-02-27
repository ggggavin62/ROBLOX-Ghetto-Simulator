--!strict
--[[
	RespawnManager.server.luau
	Owns the full character-spawn lifecycle so we can enforce a custom
	respawn delay without relying on Roblox's built-in timer.

	Flow:
	  • Sets CharacterAutoLoads = false immediately (must run before any
	    player triggers CharacterAdded).
	  • PlayerAdded   → connect CharacterAdded hook, then call :LoadCharacter()
	  • Humanoid.Died → wait RESPAWN_DELAY seconds, then call :LoadCharacter()
	  • Studio solo   → re-hook any already-present players in the GetPlayers loop.
]]

local Players = game:GetService("Players")

-- ============================================================
-- Constants
-- ============================================================

local RESPAWN_DELAY: number = 5.0  -- seconds before character reloads after death

-- ============================================================
-- Disable auto-loading so we control every respawn
-- ============================================================

Players.CharacterAutoLoads = false

-- ============================================================
-- Per-Character Setup
-- ============================================================

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	humanoid.Died:Connect(function()
		task.delay(RESPAWN_DELAY, function()
			-- Guard: player may have left during the delay
			if player.Parent then
				player:LoadCharacter()
			end
		end)
	end)
end

-- ============================================================
-- Per-Player Setup
-- ============================================================

local function onPlayerAdded(player: Player)
	-- Hook all future characters BEFORE loading the first one, so we never
	-- miss the CharacterAdded signal.
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)

	player:LoadCharacter()
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- ============================================================
-- Bootstrap: players already present (Studio Play Solo)
-- ============================================================

for _, player in Players:GetPlayers() do
	-- Connect the CharacterAdded hook for future spawns
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		-- Already has a character: hook it for death detection
		onCharacterAdded(player, player.Character)
	else
		-- No character yet: load it now
		player:LoadCharacter()
	end
end
