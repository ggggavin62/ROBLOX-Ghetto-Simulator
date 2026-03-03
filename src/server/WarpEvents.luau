--!strict
--[[
	WarpEvents.luau  (ModuleScript — ServerScriptService)

	Single source of truth for all server-side networking events.
	Replaces the Warp library with standard Roblox RemoteEvents stored in
	ReplicatedStorage/Events/.

	Exposes the same call surface used by all callers:
	  :Fire(true, player, ...)  → FireClient(player, ...)
	  :Fires(true, ...)         → FireAllClients(...)
	  :Connect(handler)         → OnServerEvent:Connect(handler)

	Events:
	  WeaponFired   — client → server  (damage request from WeaponHandler)
	  ReloadState   — server → client  (reload started / completed)
	  HitConfirmed  — server → client  (hit-marker confirmation)
	  KillFeed      — server → all     (kill-feed broadcast)
	  WeaponPickup  — server → client  (weapon granted by PlayerSetup)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Events folder  (create once; idempotent)
-- ============================================================

local eventsFolder: Folder
do
	local existing = ReplicatedStorage:FindFirstChild("Events")
	if existing and existing:IsA("Folder") then
		eventsFolder = existing :: Folder
	else
		eventsFolder        = Instance.new("Folder")
		eventsFolder.Name   = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end
end

local function getOrCreate(name: string): RemoteEvent
	local existing = eventsFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing :: RemoteEvent
	end
	local re        = Instance.new("RemoteEvent")
	re.Name         = name
	re.Parent       = eventsFolder
	return re
end

-- ============================================================
-- Wrapper factory  (server-side)
-- ============================================================

type ServerEvent = {
	Fire:    (self: ServerEvent, _toClient: boolean, player: Player,  ...any) -> (),
	Fires:   (self: ServerEvent, _toAll:   boolean,                   ...any) -> (),
	Connect: (self: ServerEvent, handler:  (Player, ...any) -> ())          -> (),
}

local function serverEvent(name: string): ServerEvent
	local re = getOrCreate(name)
	return {
		Fire = function(_self: ServerEvent, _toClient: boolean, player: Player, ...: any)
			re:FireClient(player, ...)
		end,
		Fires = function(_self: ServerEvent, _toAll: boolean, ...: any)
			re:FireAllClients(...)
		end,
		Connect = function(_self: ServerEvent, handler: (Player, ...any) -> ())
			re.OnServerEvent:Connect(handler)
		end,
	} :: ServerEvent
end

-- ============================================================
-- Event registry  (order kept for documentation; no longer matters
-- now that we use named RemoteEvents instead of uint8 IDs)
-- ============================================================

return {
	WeaponFired  = serverEvent("WeaponFired"),   -- client → server
	ReloadState  = serverEvent("ReloadState"),   -- server → client
	HitConfirmed = serverEvent("HitConfirmed"),  -- server → client
	KillFeed     = serverEvent("KillFeed"),      -- server → all
	WeaponPickup = serverEvent("WeaponPickup"),  -- server → client
}
