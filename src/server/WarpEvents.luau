--!strict
--[[
	WarpEvents.luau  (ModuleScript — ServerScriptService)

	Single source of truth for all server-side Warp event objects.

	WHY THIS EXISTS
	Warp v1.0.14 uses a sequential uint8 to identify each event in the
	binary packet instead of sending the full string name.  The uint8 is
	assigned by the ORDER in which Warp.Server("X") / Warp.Client("X") is
	first called in each Luau VM.  If server and client register identifiers
	in different orders the wrong handlers fire.

	The fix: every server script that needs a Warp event requires THIS module.
	Lua's module cache guarantees that Warp.Server("X") is called exactly once
	per identifier, in the order listed below.  The matching client module
	(StarterPlayerScripts/WarpEvents) lists them in identical order.

	  Server ID 0 → WeaponFired   (client → server)
	  Server ID 1 → ReloadState   (server → client)
	  Server ID 2 → HitConfirmed  (server → client)
	  Server ID 3 → KillFeed      (server → client)
	  Server ID 4 → WeaponPickup  (server → client)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Warp: any = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Warp"))

-- IMPORTANT: order must match src/client/WarpEvents.luau exactly.
return {
	WeaponFired  = Warp.Server("WeaponFired"),   -- 0  client→server (damage request)
	ReloadState  = Warp.Server("ReloadState"),   -- 1  server→client
	HitConfirmed = Warp.Server("HitConfirmed"),  -- 2  server→client (hit marker)
	KillFeed     = Warp.Server("KillFeed"),      -- 3  server→client (kill feed)
	WeaponPickup = Warp.Server("WeaponPickup"),  -- 4  server→client
}
