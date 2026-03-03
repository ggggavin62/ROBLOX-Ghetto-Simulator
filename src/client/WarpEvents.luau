--!strict
--[[
	WarpEvents.luau  (ModuleScript — StarterPlayerScripts)

	Single source of truth for all client-side networking events.
	Replaces the Warp library with standard Roblox RemoteEvents stored in
	ReplicatedStorage/Events/ (created by the server-side WarpEvents module).

	Exposes the same call surface used by all callers:
	  :Fire(true, ...)     → FireServer(...)
	  :Connect(handler)   → OnClientEvent:Connect(handler)

	Events (must reference the same names as server/WarpEvents.luau):
	  WeaponFired   — this client fires to server
	  ReloadState   — server fires to this client
	  HitConfirmed  — server fires to this client
	  KillFeed      — server fires to all clients
	  WeaponPickup  — server fires to this client
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for the Events folder and its RemoteEvents to be created by the server.
local eventsFolder = ReplicatedStorage:WaitForChild("Events") :: Folder

-- ============================================================
-- Wrapper factory  (client-side)
-- ============================================================

type ClientEvent = {
	Fire:    (self: ClientEvent, _toServer: boolean, ...any) -> (),
	Connect: (self: ClientEvent, handler:   (...any) -> ()) -> (),
}

local function clientEvent(name: string): ClientEvent
	local re = eventsFolder:WaitForChild(name) :: RemoteEvent
	return {
		Fire = function(_self: ClientEvent, _toServer: boolean, ...: any)
			re:FireServer(...)
		end,
		Connect = function(_self: ClientEvent, handler: (...any) -> ())
			re.OnClientEvent:Connect(handler)
		end,
	} :: ClientEvent
end

-- ============================================================
-- Event registry
-- ============================================================

return {
	WeaponFired  = clientEvent("WeaponFired"),   -- client fires to server
	ReloadState  = clientEvent("ReloadState"),   -- server fires to client
	HitConfirmed = clientEvent("HitConfirmed"),  -- server fires to client
	KillFeed     = clientEvent("KillFeed"),      -- server fires to all
	WeaponPickup = clientEvent("WeaponPickup"),  -- server fires to client
}
