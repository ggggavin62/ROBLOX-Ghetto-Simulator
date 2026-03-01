--!strict
--[[
	WarpEvents.luau  (ModuleScript — StarterPlayerScripts)

	Single source of truth for all client-side Warp event objects.

	Identifiers MUST be declared in the SAME ORDER as
	src/server/WarpEvents.luau so the uint8 IDs match.

	  Client ID 0 → WeaponFired   (this client fires to server)
	  Client ID 1 → ReloadState   (server fires to this client)
	  Client ID 2 → HitConfirmed  (server fires to this client)
	  Client ID 3 → KillFeed      (server fires to this client)
	  Client ID 4 → WeaponPickup  (server fires to this client)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Warp: any = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Warp"))

-- IMPORTANT: order must match src/server/WarpEvents.luau exactly.
return {
	WeaponFired  = Warp.Client("WeaponFired"),   -- 0
	ReloadState  = Warp.Client("ReloadState"),   -- 1
	HitConfirmed = Warp.Client("HitConfirmed"),  -- 2
	KillFeed     = Warp.Client("KillFeed"),      -- 3
	WeaponPickup = Warp.Client("WeaponPickup"),  -- 4
}
