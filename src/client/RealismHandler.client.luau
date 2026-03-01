--!strict
--[[
	RealismHandler.client.luau  (LocalScript — StarterPlayerScripts)

	Starts the Character-Realism client module (MaximumADHD) for the
	local player.

	WHAT IT DOES
	  • Requires RealismClient from ReplicatedStorage and calls Start().
	  • Start() does three things automatically:
	      1. FirstPerson body — patches Roblox's BaseCamera /
	         TransparencyController so the player's head and accessories
	         are visible to themselves in first-person view.
	      2. Head-look — subscribes to CollectionService "RealismHook" tags;
	         any tagged Humanoid (local player, other players, NPCs) gets
	         realistic head / upper-torso rotation driven by camera pitch+yaw.
	         Updates are sent to the server at ≤20 Hz and relayed to all
	         nearby clients (30-stud cull radius).
	      3. Material footsteps — overrides the default "Running" sound on
	         every tagged Humanoid with a surface-specific sound (dirt, wood,
	         concrete, grass, metal, sand …).

	PATH NOTE
	  If you placed the module under a folder (e.g. "Character-Realism/RealismClient")
	  change the WaitForChild path below to match.  The only requirement is
	  that the module and its children (Config, FirstPerson) are accessible
	  from ReplicatedStorage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Require RealismClient
-- Adjust this path if you stored the module under a sub-folder.
-- ============================================================

local RealismClient: any = require(
	ReplicatedStorage:WaitForChild("RealismClient")
)

-- ============================================================
-- Start
-- Initialises first-person body, head-look, and material sounds.
-- All "RealismHook"-tagged Humanoids (players + NPCs) are
-- processed automatically from this point forward.
-- ============================================================

RealismClient.Start()
