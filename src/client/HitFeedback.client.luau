--!strict
--[[
	HitFeedback.client.luau
	Three distinct feedback systems, all in one script to keep GUI creation
	minimal and avoid duplicate ScreenGui overhead.

	1. Hit marker   — crosshair-sized dot flashes red (body) or gold (headshot)
	                  when HitConfirmed fires from the server.
	2. Kill feed    — scrolling top-right list; entry is green when you killed,
	                  red when you were killed.
	3. Death screen — semi-transparent red overlay + "ELIMINATED" title +
	                  live countdown, cleared the moment the character respawns.
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Warp Events  (centralised via WarpEvents module)
-- ============================================================

local WarpEvents   = require(script.Parent:WaitForChild("WarpEvents"))
local HitConfirmed = WarpEvents.HitConfirmed
local KillFeed     = WarpEvents.KillFeed

-- ============================================================
-- Constants
-- ============================================================

local KILL_FEED_MAX: number      = 5     -- maximum simultaneous entries
local KILL_FEED_DURATION: number = 6.0   -- seconds before entry fades
local KILL_FEED_FADE: number     = 0.4   -- fade-out tween duration
local HIT_MARKER_DURATION: number = 0.12 -- seconds hit marker stays visible
local RESPAWN_COUNTDOWN: number  = 5     -- must match RespawnManager's delay

-- ============================================================
-- ScreenGui
-- ============================================================

local screenGui              = Instance.new("ScreenGui")
screenGui.Name               = "FeedbackHUD"
screenGui.ResetOnSpawn       = false
screenGui.IgnoreGuiInset     = true
screenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
screenGui.Parent             = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- 1. Hit Marker
-- ============================================================
-- A small dot at screen centre that flashes when a hit is confirmed.
-- Sits behind the crosshair dot drawn by WeaponHandler so it "blooms" around it.

local hitMarker                    = Instance.new("Frame")
hitMarker.Name                     = "HitMarker"
hitMarker.Size                     = UDim2.new(0, 18, 0, 18)
hitMarker.AnchorPoint              = Vector2.new(0.5, 0.5)
hitMarker.Position                 = UDim2.new(0.5, 0, 0.5, 0)
hitMarker.BackgroundColor3         = Color3.fromRGB(255, 80, 80)
hitMarker.BackgroundTransparency   = 1
hitMarker.BorderSizePixel          = 0
hitMarker.ZIndex                   = 2
hitMarker.Parent                   = screenGui

local hitMarkerCorner              = Instance.new("UICorner")
hitMarkerCorner.CornerRadius       = UDim.new(1, 0)
hitMarkerCorner.Parent             = hitMarker

local function flashHitMarker(isHeadshot: boolean)
	hitMarker.BackgroundColor3 = if isHeadshot
		then Color3.fromRGB(255, 215, 0)  -- gold  — headshot
		else Color3.fromRGB(255, 70, 70)  -- red   — body shot

	hitMarker.BackgroundTransparency = 0

	task.delay(HIT_MARKER_DURATION, function()
		hitMarker.BackgroundTransparency = 1
	end)
end

-- ============================================================
-- 2. Kill Feed
-- ============================================================

local killFeedFrame                  = Instance.new("Frame")
killFeedFrame.Name                   = "KillFeed"
killFeedFrame.Size                   = UDim2.new(0, 280, 0, 160)
killFeedFrame.AnchorPoint            = Vector2.new(1, 0)
killFeedFrame.Position               = UDim2.new(1, -16, 0, 16)
killFeedFrame.BackgroundTransparency = 1
killFeedFrame.Parent                 = screenGui

local killFeedLayout                 = Instance.new("UIListLayout")
killFeedLayout.FillDirection         = Enum.FillDirection.Vertical
killFeedLayout.VerticalAlignment     = Enum.VerticalAlignment.Top
killFeedLayout.SortOrder             = Enum.SortOrder.LayoutOrder
killFeedLayout.Padding               = UDim.new(0, 3)
killFeedLayout.Parent                = killFeedFrame

local killFeedEntries: { TextLabel } = {}

local function addKillFeedEntry(killerName: string, victimName: string)
	-- Evict oldest entry when at capacity
	if #killFeedEntries >= KILL_FEED_MAX then
		local oldest = table.remove(killFeedEntries, 1)
		if oldest.Parent then oldest:Destroy() end
	end

	local entry                        = Instance.new("TextLabel")
	entry.Size                         = UDim2.new(1, 0, 0, 24)
	entry.BackgroundColor3             = Color3.fromRGB(0, 0, 0)
	entry.BackgroundTransparency       = 0.5
	entry.TextColor3                   = Color3.new(1, 1, 1)
	entry.TextStrokeColor3             = Color3.new(0, 0, 0)
	entry.TextStrokeTransparency       = 0.4
	entry.Font                         = Enum.Font.GothamBold
	entry.TextSize                     = 13
	entry.TextXAlignment               = Enum.TextXAlignment.Right
	entry.BorderSizePixel              = 0
	entry.LayoutOrder                  = #killFeedEntries + 1
	entry.Parent                       = killFeedFrame

	-- Colour-code entries that involve the local player
	local localName = LocalPlayer.Name
	if killerName == localName then
		entry.TextColor3 = Color3.fromRGB(110, 230, 110)  -- green — you killed
	elseif victimName == localName then
		entry.TextColor3 = Color3.fromRGB(230, 80, 80)    -- red   — you died
	end

	entry.Text = killerName .. "  ›  " .. victimName
	table.insert(killFeedEntries, entry)

	-- Fade out then destroy after duration
	task.delay(KILL_FEED_DURATION, function()
		if not entry.Parent then return end
		TweenService:Create(entry, TweenInfo.new(KILL_FEED_FADE), {
			BackgroundTransparency = 1,
			TextTransparency       = 1,
			TextStrokeTransparency = 1,
		}):Play()

		task.delay(KILL_FEED_FADE + 0.05, function()
			if entry.Parent then
				local idx = table.find(killFeedEntries, entry)
				if idx then table.remove(killFeedEntries, idx) end
				entry:Destroy()
			end
		end)
	end)
end

-- ============================================================
-- 3. Death Screen
-- ============================================================

-- Full-screen red tint
local deathOverlay                      = Instance.new("Frame")
deathOverlay.Name                       = "DeathOverlay"
deathOverlay.Size                       = UDim2.new(1, 0, 1, 0)
deathOverlay.BackgroundColor3           = Color3.fromRGB(160, 0, 0)
deathOverlay.BackgroundTransparency     = 1
deathOverlay.BorderSizePixel            = 0
deathOverlay.ZIndex                     = 20
deathOverlay.Parent                     = screenGui

-- "ELIMINATED" header
local deathLabel                        = Instance.new("TextLabel")
deathLabel.Name                         = "DeathLabel"
deathLabel.Size                         = UDim2.new(1, 0, 0, 64)
deathLabel.AnchorPoint                  = Vector2.new(0.5, 0.5)
deathLabel.Position                     = UDim2.new(0.5, 0, 0.44, 0)
deathLabel.BackgroundTransparency       = 1
deathLabel.TextColor3                   = Color3.new(1, 1, 1)
deathLabel.TextStrokeColor3             = Color3.new(0, 0, 0)
deathLabel.TextStrokeTransparency       = 0.3
deathLabel.Font                         = Enum.Font.GothamBold
deathLabel.TextSize                     = 52
deathLabel.Text                         = "ELIMINATED"
deathLabel.TextTransparency             = 1
deathLabel.ZIndex                       = 21
deathLabel.Parent                       = screenGui

-- Respawn countdown line
local respawnLabel                      = Instance.new("TextLabel")
respawnLabel.Name                       = "RespawnLabel"
respawnLabel.Size                       = UDim2.new(1, 0, 0, 36)
respawnLabel.AnchorPoint                = Vector2.new(0.5, 0.5)
respawnLabel.Position                   = UDim2.new(0.5, 0, 0.54, 0)
respawnLabel.BackgroundTransparency     = 1
respawnLabel.TextColor3                 = Color3.fromRGB(220, 220, 220)
respawnLabel.Font                       = Enum.Font.Gotham
respawnLabel.TextSize                   = 22
respawnLabel.Text                       = ""
respawnLabel.TextTransparency           = 1
respawnLabel.ZIndex                     = 21
respawnLabel.Parent                     = screenGui

-- Tweens re-used on every death
local FADE_IN  = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.5,  Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local isShowingDeathScreen: boolean = false

local function hideDeathScreen()
	isShowingDeathScreen = false
	TweenService:Create(deathOverlay, FADE_OUT, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(deathLabel,   FADE_OUT, { TextTransparency = 1 }):Play()
	TweenService:Create(respawnLabel, FADE_OUT, { TextTransparency = 1 }):Play()
end

local function showDeathScreen()
	isShowingDeathScreen = true

	-- Fade in
	TweenService:Create(deathOverlay, FADE_IN, { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(deathLabel,   FADE_IN, { TextTransparency = 0 }):Play()
	TweenService:Create(respawnLabel, FADE_IN, { TextTransparency = 0 }):Play()

	-- Live countdown; bail if character respawns early
	for i = RESPAWN_COUNTDOWN, 1, -1 do
		if not isShowingDeathScreen then return end
		respawnLabel.Text = "Respawning in " .. tostring(i) .. "..."
		task.wait(1)
	end

	if isShowingDeathScreen then
		respawnLabel.Text = "Respawning..."
	end
end

-- ============================================================
-- Character Hooks
-- ============================================================

local function onCharacterAdded(character: Model)
	-- Cancel any active death screen the moment we get a new character
	if isShowingDeathScreen then
		hideDeathScreen()
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		task.spawn(showDeathScreen)
	end)
end

if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- ============================================================
-- Remote Event Handlers
-- ============================================================

HitConfirmed:Connect(function(damageRaw: any, isHeadshotRaw: any)
	local _damage: number     = if typeof(damageRaw) == "number" then damageRaw :: number else 0
	local isHeadshot: boolean = if typeof(isHeadshotRaw) == "boolean" then isHeadshotRaw :: boolean else false
	flashHitMarker(isHeadshot)
end)

KillFeed:Connect(function(killerNameRaw: any, victimNameRaw: any)
	local killerName: string = if typeof(killerNameRaw) == "string" then killerNameRaw :: string else "?"
	local victimName: string = if typeof(victimNameRaw) == "string" then victimNameRaw :: string else "?"
	addKillFeedEntry(killerName, victimName)
end)
