--!strict
--[[
	RoundHUD.client.luau
	Displays round phase and timer at the top-centre, plus a winner
	announcement overlay at the end of each round.

	RoundState payload (from RoundManager):
	  phase      : "Intermission" | "InRound" | "RoundEnd"
	  timeLeft   : seconds remaining
	  winnerName : "" = draw, otherwise the winner's name
	  winnerKills: 0 = draw, otherwise the winning kill count
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- Remote Events
-- ============================================================

local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local RoundState   = eventsFolder:WaitForChild("RoundState") :: RemoteEvent

-- ============================================================
-- ScreenGui
-- ============================================================

local screenGui              = Instance.new("ScreenGui")
screenGui.Name               = "RoundHUD"
screenGui.ResetOnSpawn       = false
screenGui.IgnoreGuiInset     = true
screenGui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
screenGui.Parent             = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- Timer Bar (top-centre)
-- ============================================================

local timerBar                      = Instance.new("Frame")
timerBar.Name                       = "TimerBar"
timerBar.Size                       = UDim2.new(0, 270, 0, 38)
timerBar.AnchorPoint                = Vector2.new(0.5, 0)
timerBar.Position                   = UDim2.new(0.5, 0, 0, 10)
timerBar.BackgroundColor3           = Color3.fromRGB(0, 0, 0)
timerBar.BackgroundTransparency     = 0.45
timerBar.BorderSizePixel            = 0
timerBar.Parent                     = screenGui

local timerBarCorner                = Instance.new("UICorner")
timerBarCorner.CornerRadius         = UDim.new(0, 6)
timerBarCorner.Parent               = timerBar

local timerLabel                    = Instance.new("TextLabel")
timerLabel.Name                     = "TimerLabel"
timerLabel.Size                     = UDim2.new(1, 0, 1, 0)
timerLabel.BackgroundTransparency   = 1
timerLabel.TextColor3               = Color3.new(1, 1, 1)
timerLabel.TextStrokeColor3         = Color3.new(0, 0, 0)
timerLabel.TextStrokeTransparency   = 0.4
timerLabel.Font                     = Enum.Font.GothamBold
timerLabel.TextSize                 = 18
timerLabel.Text                     = "CONNECTING..."
timerLabel.Parent                   = timerBar

-- ============================================================
-- Winner / Draw Overlay
-- ============================================================

-- Dark full-screen backing
local winnerOverlay                   = Instance.new("Frame")
winnerOverlay.Name                    = "WinnerOverlay"
winnerOverlay.Size                    = UDim2.new(1, 0, 1, 0)
winnerOverlay.BackgroundColor3        = Color3.fromRGB(0, 0, 0)
winnerOverlay.BackgroundTransparency  = 1
winnerOverlay.BorderSizePixel         = 0
winnerOverlay.ZIndex                  = 15
winnerOverlay.Parent                  = screenGui

-- Main headline (VICTORY! / DEFEAT / DRAW / "Name WINS!")
local winnerLabel                     = Instance.new("TextLabel")
winnerLabel.Name                      = "WinnerLabel"
winnerLabel.Size                      = UDim2.new(1, 0, 0, 72)
winnerLabel.AnchorPoint               = Vector2.new(0.5, 0.5)
winnerLabel.Position                  = UDim2.new(0.5, 0, 0.44, 0)
winnerLabel.BackgroundTransparency    = 1
winnerLabel.TextColor3                = Color3.fromRGB(255, 215, 0)
winnerLabel.TextStrokeColor3          = Color3.new(0, 0, 0)
winnerLabel.TextStrokeTransparency    = 0.25
winnerLabel.Font                      = Enum.Font.GothamBold
winnerLabel.TextSize                  = 48
winnerLabel.Text                      = ""
winnerLabel.TextTransparency          = 1
winnerLabel.ZIndex                    = 16
winnerLabel.Parent                    = screenGui

-- Kill count sub-line
local winnerSubLabel                  = Instance.new("TextLabel")
winnerSubLabel.Name                   = "WinnerSubLabel"
winnerSubLabel.Size                   = UDim2.new(1, 0, 0, 34)
winnerSubLabel.AnchorPoint            = Vector2.new(0.5, 0.5)
winnerSubLabel.Position               = UDim2.new(0.5, 0, 0.54, 0)
winnerSubLabel.BackgroundTransparency = 1
winnerSubLabel.TextColor3             = Color3.fromRGB(210, 210, 210)
winnerSubLabel.Font                   = Enum.Font.Gotham
winnerSubLabel.TextSize               = 22
winnerSubLabel.Text                   = ""
winnerSubLabel.TextTransparency       = 1
winnerSubLabel.ZIndex                 = 16
winnerSubLabel.Parent                 = screenGui

local FADE_IN  = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local overlayVisible: boolean = false

local function showWinnerOverlay(winnerName: string, winnerKills: number)
	overlayVisible = true

	local isDraw    = winnerName == "" or winnerKills == 0
	local isLocal   = winnerName == LocalPlayer.Name

	if isDraw then
		winnerLabel.Text       = "DRAW"
		winnerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		winnerSubLabel.Text    = "No winner this round"
	elseif isLocal then
		winnerLabel.Text       = "VICTORY!"
		winnerLabel.TextColor3 = Color3.fromRGB(110, 230, 110)
		winnerSubLabel.Text    = tostring(winnerKills) .. " kills"
	else
		winnerLabel.Text       = winnerName .. " WINS!"
		winnerLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		winnerSubLabel.Text    = tostring(winnerKills) .. " kills"
	end

	TweenService:Create(winnerOverlay,   FADE_IN, { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(winnerLabel,     FADE_IN, { TextTransparency = 0 }):Play()
	TweenService:Create(winnerSubLabel,  FADE_IN, { TextTransparency = 0 }):Play()
end

local function hideWinnerOverlay()
	if not overlayVisible then return end
	overlayVisible = false
	TweenService:Create(winnerOverlay,   FADE_OUT, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(winnerLabel,     FADE_OUT, { TextTransparency = 1 }):Play()
	TweenService:Create(winnerSubLabel,  FADE_OUT, { TextTransparency = 1 }):Play()
end

-- ============================================================
-- Helpers
-- ============================================================

local function formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return ("%d:%02d"):format(mins, secs)
end

-- ============================================================
-- RoundState Handler
-- ============================================================

local lastPhase: string = ""

RoundState.OnClientEvent:Connect(function(
	phaseRaw: any,
	timeLeftRaw: any,
	winnerNameRaw: any,
	winnerKillsRaw: any
)
	local phase: string       = if typeof(phaseRaw) == "string"  then phaseRaw :: string  else "?"
	local timeLeft: number    = if typeof(timeLeftRaw) == "number" then timeLeftRaw :: number else 0
	local winnerName: string  = if typeof(winnerNameRaw) == "string" then winnerNameRaw :: string else ""
	local winnerKills: number = if typeof(winnerKillsRaw) == "number" then winnerKillsRaw :: number else 0

	if phase == "Intermission" then
		if overlayVisible then hideWinnerOverlay() end
		timerBar.BackgroundColor3 = Color3.fromRGB(25, 25, 70)
		timerLabel.Text           = "INTERMISSION  " .. formatTime(timeLeft)

	elseif phase == "InRound" then
		if overlayVisible then hideWinnerOverlay() end
		-- Bar pulses red in final 30 seconds
		timerBar.BackgroundColor3 = if timeLeft <= 30
			then Color3.fromRGB(90, 15, 15)
			else Color3.fromRGB(0, 0, 0)
		timerLabel.Text = "ROUND  " .. formatTime(timeLeft)

	elseif phase == "RoundEnd" then
		timerBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		timerLabel.Text           = "ROUND OVER  " .. formatTime(timeLeft)

		-- Show overlay only on the first RoundEnd tick to avoid re-triggering tweens
		if lastPhase ~= "RoundEnd" then
			showWinnerOverlay(winnerName, winnerKills)
		end
	end

	lastPhase = phase
end)
