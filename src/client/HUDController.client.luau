--!strict
--[[
	HUDController.client.luau  (LocalScript — StarterPlayerScripts)

	Single source of truth for all HUD visuals.
	Creates "MainHUD" ScreenGui in PlayerGui and owns every element:

	  Crosshair        — 8 px white dot, exact screen centre.
	  Health bar       — bottom-left; interpolates green → red as HP falls.
	  Ammo counter     — bottom-right; "30 / 30" format (large bold text).
	  Weapon name      — above ammo counter (small grey text).
	  Slot label       — slot indicator line above weapon name.

	All elements are built in code — zero Studio-placed GUI required.

	WeaponHandler finds and mutates the ammo/weapon labels at runtime
	by calling PlayerGui:WaitForChild("MainHUD") and then finding named
	children.  This script only owns creation and health updates.
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- ScreenGui
-- ============================================================

local screenGui                = Instance.new("ScreenGui")
screenGui.Name                 = "MainHUD"
screenGui.ResetOnSpawn         = false
screenGui.IgnoreGuiInset       = true
screenGui.ZIndexBehavior       = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder         = 1
screenGui.Parent               = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- Crosshair  (centre dot)
-- ============================================================

local crosshair                = Instance.new("Frame")
crosshair.Name                 = "Crosshair"
crosshair.Size                 = UDim2.new(0, 8, 0, 8)
crosshair.AnchorPoint          = Vector2.new(0.5, 0.5)
crosshair.Position             = UDim2.new(0.5, 0, 0.5, 0)
crosshair.BackgroundColor3     = Color3.new(0.85, 0.85, 0.85)
crosshair.BorderSizePixel      = 0
crosshair.Parent               = screenGui

local crossCorner              = Instance.new("UICorner")
crossCorner.CornerRadius       = UDim.new(1, 0)  -- full circle
crossCorner.Parent             = crosshair

-- ============================================================
-- Health bar  (bottom-left)
-- ============================================================

local healthContainer              = Instance.new("Frame")
healthContainer.Name               = "HealthContainer"
healthContainer.Size               = UDim2.new(0, 210, 0, 14)
healthContainer.AnchorPoint        = Vector2.new(0, 1)
healthContainer.Position           = UDim2.new(0, 24, 1, -24)
healthContainer.BackgroundColor3   = Color3.fromRGB(25, 25, 25)
healthContainer.BorderSizePixel    = 0
healthContainer.Parent             = screenGui

local hpCorner                     = Instance.new("UICorner")
hpCorner.CornerRadius              = UDim.new(0, 4)
hpCorner.Parent                    = healthContainer

local healthFill                   = Instance.new("Frame")
healthFill.Name                    = "HealthFill"
healthFill.Size                    = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3        = Color3.fromRGB(80, 200, 80)
healthFill.BorderSizePixel         = 0
healthFill.Parent                  = healthContainer

local fillCorner                   = Instance.new("UICorner")
fillCorner.CornerRadius            = UDim.new(0, 4)
fillCorner.Parent                  = healthFill

-- "HP" label inside the bar
local hpLabel                      = Instance.new("TextLabel")
hpLabel.Name                       = "HPLabel"
hpLabel.Size                       = UDim2.new(1, -6, 1, 0)
hpLabel.Position                   = UDim2.new(0, 6, 0, 0)
hpLabel.BackgroundTransparency     = 1
hpLabel.TextColor3                 = Color3.new(1, 1, 1)
hpLabel.TextStrokeColor3           = Color3.new(0, 0, 0)
hpLabel.TextStrokeTransparency     = 0.45
hpLabel.Font                       = Enum.Font.GothamBold
hpLabel.TextSize                   = 11
hpLabel.TextXAlignment             = Enum.TextXAlignment.Left
hpLabel.Text                       = "100 HP"
hpLabel.Parent                     = healthContainer

-- ============================================================
-- Weapon info panel  (bottom-right, three stacked labels)
-- ============================================================

-- [1] Slot indicator  (topmost of the three)
local slotLabel                        = Instance.new("TextLabel")
slotLabel.Name                         = "SlotLabel"
slotLabel.Size                         = UDim2.new(0, 280, 0, 18)
slotLabel.AnchorPoint                  = Vector2.new(1, 1)
slotLabel.Position                     = UDim2.new(1, -24, 1, -82)
slotLabel.BackgroundTransparency       = 1
slotLabel.TextColor3                   = Color3.fromRGB(140, 140, 140)
slotLabel.TextStrokeColor3             = Color3.new(0, 0, 0)
slotLabel.TextStrokeTransparency       = 0.5
slotLabel.Font                         = Enum.Font.Gotham
slotLabel.TextSize                     = 12
slotLabel.TextXAlignment               = Enum.TextXAlignment.Right
slotLabel.Text                         = ""
slotLabel.Parent                       = screenGui

-- [2] Weapon name
local weaponNameLabel                  = Instance.new("TextLabel")
weaponNameLabel.Name                   = "WeaponNameLabel"
weaponNameLabel.Size                   = UDim2.new(0, 200, 0, 22)
weaponNameLabel.AnchorPoint            = Vector2.new(1, 1)
weaponNameLabel.Position               = UDim2.new(1, -24, 1, -60)
weaponNameLabel.BackgroundTransparency = 1
weaponNameLabel.TextColor3             = Color3.fromRGB(190, 190, 190)
weaponNameLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
weaponNameLabel.TextStrokeTransparency = 0.5
weaponNameLabel.Font                   = Enum.Font.Gotham
weaponNameLabel.TextSize               = 14
weaponNameLabel.TextXAlignment         = Enum.TextXAlignment.Right
weaponNameLabel.Text                   = ""
weaponNameLabel.Parent                 = screenGui

-- [3] Ammo counter (largest, bottommost)
local ammoLabel                        = Instance.new("TextLabel")
ammoLabel.Name                         = "AmmoLabel"
ammoLabel.Size                         = UDim2.new(0, 200, 0, 44)
ammoLabel.AnchorPoint                  = Vector2.new(1, 1)
ammoLabel.Position                     = UDim2.new(1, -24, 1, -24)
ammoLabel.BackgroundTransparency       = 1
ammoLabel.TextColor3                   = Color3.new(1, 1, 1)
ammoLabel.TextStrokeColor3             = Color3.new(0, 0, 0)
ammoLabel.TextStrokeTransparency       = 0.5
ammoLabel.Font                         = Enum.Font.GothamBold
ammoLabel.TextSize                     = 28
ammoLabel.TextXAlignment               = Enum.TextXAlignment.Right
ammoLabel.Text                         = "-- / --"
ammoLabel.Parent                       = screenGui

-- [4] Current weapon name — bottom centre (updated by WeaponHandler)
local weaponCentreLabel                    = Instance.new("TextLabel")
weaponCentreLabel.Name                     = "WeaponCentreLabel"
weaponCentreLabel.Size                     = UDim2.new(0, 240, 0, 22)
weaponCentreLabel.AnchorPoint              = Vector2.new(0.5, 1)
weaponCentreLabel.Position                 = UDim2.new(0.5, 0, 1, -26)
weaponCentreLabel.BackgroundTransparency   = 1
weaponCentreLabel.TextColor3               = Color3.new(1, 1, 1)
weaponCentreLabel.TextStrokeColor3         = Color3.new(0, 0, 0)
weaponCentreLabel.TextStrokeTransparency   = 0.45
weaponCentreLabel.Font                     = Enum.Font.GothamBold
weaponCentreLabel.TextSize                 = 18
weaponCentreLabel.TextXAlignment           = Enum.TextXAlignment.Center
weaponCentreLabel.Text                     = ""
weaponCentreLabel.Parent                   = screenGui

-- ============================================================
-- Health bar update loop
-- ============================================================

local healthConn: RBXScriptConnection? = nil

local function connectHealth(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	if healthConn then
		healthConn:Disconnect()
		healthConn = nil
	end

	-- Reset bar immediately on spawn
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	hpLabel.Text = tostring(humanoid.MaxHealth) .. " HP"

	healthConn = RunService.Heartbeat:Connect(function()
		if not humanoid or not humanoid.Parent then return end
		local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)

		-- Smoothly interpolate colour: green (full) → red (empty)
		local r = math.clamp(2 * (1 - ratio), 0, 1)
		local g = math.clamp(2 * ratio,       0, 1)

		healthFill.Size             = UDim2.new(ratio, 0, 1, 0)
		healthFill.BackgroundColor3 = Color3.new(r, g, 0)
		hpLabel.Text                = tostring(math.ceil(humanoid.Health)) .. " HP"
	end)
end

if LocalPlayer.Character then
	connectHealth(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(connectHealth)
