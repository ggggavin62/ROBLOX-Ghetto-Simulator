--!strict
--[[
	RoundManager.server.luau
	Controls the match lifecycle and win condition.

	Phase loop (repeating):
	  Intermission (15 s) → InRound (5 min) → RoundEnd (10 s) → repeat

	Win condition:
	  • First player/NPC-killer to reach KILLS_TO_WIN ends the round early.
	  • If the timer expires, the player with the highest round-kill count wins.
	  • Tie / no kills → declared a draw.

	Kill source:
	  WeaponDamage fires KillRegistered (BindableEvent in ServerScriptService)
	  after every confirmed kill. We tally kills here without touching
	  the lifetime leaderstats managed by Leaderstats.server.luau.

	Client broadcast:
	  RoundState RemoteEvent is fired every second with:
	    phase      : "Intermission" | "InRound" | "RoundEnd"
	    timeLeft   : seconds remaining in this phase
	    winnerName : non-empty only during RoundEnd ("" = draw)
	    winnerKills: kill count of the winner (0 = draw)
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ============================================================
-- Constants
-- ============================================================

local INTERMISSION_DURATION: number = 15   -- seconds
local ROUND_DURATION: number        = 300  -- seconds (5 minutes)
local ROUND_END_DURATION: number    = 10   -- seconds
local KILLS_TO_WIN: number          = 30   -- early-win threshold

-- ============================================================
-- Events
-- ============================================================

local eventsFolder   = ReplicatedStorage:WaitForChild("Events")
local RoundState     = eventsFolder:WaitForChild("RoundState") :: RemoteEvent

local serverEvents   = ServerScriptService:WaitForChild("ServerEvents")
local KillRegistered = serverEvents:WaitForChild("KillRegistered") :: BindableEvent

-- ============================================================
-- Round State
-- ============================================================

local roundKills: { [string]: number } = {}
local roundActive: boolean             = false

-- ============================================================
-- Helpers
-- ============================================================

local function resetRoundKills()
	roundKills = {}
	for _, player in Players:GetPlayers() do
		roundKills[player.Name] = 0
	end
end

-- Returns ("", 0) when no kills have been registered (draw).
local function getLeader(): (string, number)
	local topName  = ""
	local topKills = 0
	for name, kills in roundKills do
		if kills > topKills then
			topKills = kills
			topName  = name
		end
	end
	return topName, topKills
end

local function broadcast(
	phase: string,
	timeLeft: number,
	winnerName: string,
	winnerKills: number
)
	RoundState:FireAllClients(phase, timeLeft, winnerName, winnerKills)
end

-- ============================================================
-- Kill Listener
-- ============================================================

KillRegistered.Event:Connect(function(killerName: string, _victimName: string)
	if not roundActive then return end
	roundKills[killerName] = (roundKills[killerName] or 0) + 1
end)

-- Initialise slot for newly joined players mid-round
Players.PlayerAdded:Connect(function(player: Player)
	roundKills[player.Name] = roundKills[player.Name] or 0
end)

-- ============================================================
-- Phase Runners
-- ============================================================

local function runIntermission()
	roundActive = false
	local timeLeft = INTERMISSION_DURATION
	while timeLeft > 0 do
		broadcast("Intermission", timeLeft, "", 0)
		task.wait(1)
		timeLeft -= 1
	end
end

-- Returns (winnerName, winnerKills) — empty name means draw.
local function runRound(): (string, number)
	roundActive = true
	resetRoundKills()

	local timeLeft = ROUND_DURATION
	while timeLeft > 0 do
		broadcast("InRound", timeLeft, "", 0)
		task.wait(1)
		timeLeft -= 1

		-- Early win check after each tick
		for name, kills in roundKills do
			if kills >= KILLS_TO_WIN then
				roundActive = false
				return name, kills
			end
		end
	end

	roundActive = false
	return getLeader()
end

local function runRoundEnd(winnerName: string, winnerKills: number)
	local timeLeft = ROUND_END_DURATION
	while timeLeft > 0 do
		broadcast("RoundEnd", timeLeft, winnerName, winnerKills)
		task.wait(1)
		timeLeft -= 1
	end
end

-- ============================================================
-- Main Loop
-- ============================================================

task.spawn(function()
	-- Brief startup delay so other server scripts can finish initialising
	task.wait(3)

	while true do
		runIntermission()
		local winnerName, winnerKills = runRound()
		runRoundEnd(winnerName, winnerKills)
	end
end)
