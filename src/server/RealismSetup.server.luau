--!strict
--[[
	RealismSetup.server.luau  (Script — ServerScriptService)

	Provides the server-side half of Character-Realism (MaximumADHD).

	WHY THIS EXISTS
	The Character-Realism library ships as two separate pieces:
	  • RealismServer (Script)      — normally lives in ServerScriptService
	  • RealismClient (ModuleScript) — normally lives in StarterPlayerScripts

	Because both pieces were placed in ReplicatedStorage (they won't
	auto-execute there), this script manually replicates everything that
	RealismServer would have done:

	  1. Creates the "SetLookAngles" RemoteEvent in ReplicatedStorage.
	     RealismClient waits for this event before it can start.
	  2. Validates and broadcasts pitch/yaw angles from each client to
	     every other client, so all players see each other looking around.
	  3. Tags every player's Humanoid with "RealismHook" via CollectionService,
	     which causes RealismClient to mount head-look and material sounds on it.

	NPC humanoids are tagged "RealismHook" by AISpawner.server.luau directly.
]]

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- SetLookAngles RemoteEvent
-- RealismClient does:  ReplicatedStorage:WaitForChild("SetLookAngles")
-- so this must be created before that client module loads.
-- ============================================================

local setLookAngles          = Instance.new("RemoteEvent")
setLookAngles.Archivable     = false
setLookAngles.Name           = "SetLookAngles"
setLookAngles.Parent         = ReplicatedStorage

-- Validate then relay look-angle updates from each client to all others.
-- Clamped to [-1, 1] and NaN-guarded (mirrors RealismServer source exactly).
setLookAngles.OnServerEvent:Connect(function(player: Player, pitch: any, yaw: any)
	if type(pitch) == "number" and pitch == pitch then
		pitch = math.clamp(pitch, -1, 1)
		if type(yaw) == "number" and yaw == yaw then
			yaw = math.clamp(yaw, -1, 1)
			setLookAngles:FireAllClients(player, pitch, yaw)
		end
	end
end)

-- ============================================================
-- Tag player humanoids with "RealismHook"
-- RealismClient subscribes to this tag via CollectionService and
-- automatically calls MountLookAngle + MountMaterialSounds on it.
-- ============================================================

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid and humanoid:IsA("Humanoid") then
		CollectionService:AddTag(humanoid, "RealismHook")
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
