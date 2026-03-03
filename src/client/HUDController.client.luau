--!strict
--[[
	HUDController.client.luau  (LocalScript — StarterPlayerScripts)

	Builds the "MainHUD" ScreenGui using plain Roblox instances.
	No external packages required — Fusion has been removed.

	Reactive updates are driven by HUDState.onChange() callbacks:
	  hp / maxHp     → health fill bar (TweenService) + HP text
	  ammo / magSize / isReloading → ammo label text + colour
	  weaponName     → weapon name labels
	  slotLine       → slot indicator label

	Elements:
	  Crosshair          — 8 px dot at screen centre
	  HealthContainer    — bottom-left animated fill bar
	  SlotLabel          — bottom-right slot indicator
	  WeaponNameLabel    — bottom-right weapon name
	  AmmoLabel          — bottom-right large ammo counter
	  WeaponCentreLabel  — bottom-centre weapon name
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local HUDState    = require(script.Parent:WaitForChild("HUDState"))

-- ============================================================
-- ScreenGui
-- ============================================================

local screenGui               = Instance.new("ScreenGui")
screenGui.Name                = "MainHUD"
screenGui.ResetOnSpawn        = false
screenGui.IgnoreGuiInset      = true
screenGui.ZIndexBehavior      = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder        = 1
screenGui.Parent              = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- Crosshair  (centre dot)
-- ============================================================

local crosshair               = Instance.new("Frame")
crosshair.Name                = "Crosshair"
crosshair.Size                = UDim2.new(0, 8, 0, 8)
crosshair.AnchorPoint         = Vector2.new(0.5, 0.5)
crosshair.Position            = UDim2.new(0.5, 0, 0.5, 0)
crosshair.BackgroundColor3    = Color3.new(0.85, 0.85, 0.85)
crosshair.BorderSizePixel     = 0
crosshair.Parent              = screenGui
Instance.new("UICorner", crosshair).CornerRadius = UDim.new(1, 0)

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
Instance.new("UICorner", healthContainer).CornerRadius = UDim.new(0, 4)

local healthFill                   = Instance.new("Frame")
healthFill.Name                    = "HealthFill"
healthFill.Size                    = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3        = Color3.fromRGB(0, 200, 60)
healthFill.BorderSizePixel         = 0
healthFill.Parent                  = healthContainer
Instance.new("UICorner", healthFill).CornerRadius = UDim.new(0, 4)

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
-- Slot indicator  (bottom-right)
-- ============================================================

local slotLabel                    = Instance.new("TextLabel")
slotLabel.Name                     = "SlotLabel"
slotLabel.Size                     = UDim2.new(0, 280, 0, 18)
slotLabel.AnchorPoint              = Vector2.new(1, 1)
slotLabel.Position                 = UDim2.new(1, -24, 1, -82)
slotLabel.BackgroundTransparency   = 1
slotLabel.TextColor3               = Color3.fromRGB(140, 140, 140)
slotLabel.TextStrokeColor3         = Color3.new(0, 0, 0)
slotLabel.TextStrokeTransparency   = 0.5
slotLabel.Font                     = Enum.Font.Gotham
slotLabel.TextSize                 = 12
slotLabel.TextXAlignment           = Enum.TextXAlignment.Right
slotLabel.Text                     = ""
slotLabel.Parent                   = screenGui

-- ============================================================
-- Weapon name  (bottom-right)
-- ============================================================

local weaponNameLabel              = Instance.new("TextLabel")
weaponNameLabel.Name               = "WeaponNameLabel"
weaponNameLabel.Size               = UDim2.new(0, 200, 0, 22)
weaponNameLabel.AnchorPoint        = Vector2.new(1, 1)
weaponNameLabel.Position           = UDim2.new(1, -24, 1, -60)
weaponNameLabel.BackgroundTransparency = 1
weaponNameLabel.TextColor3         = Color3.fromRGB(190, 190, 190)
weaponNameLabel.TextStrokeColor3   = Color3.new(0, 0, 0)
weaponNameLabel.TextStrokeTransparency = 0.5
weaponNameLabel.Font               = Enum.Font.Gotham
weaponNameLabel.TextSize           = 14
weaponNameLabel.TextXAlignment     = Enum.TextXAlignment.Right
weaponNameLabel.Text               = ""
weaponNameLabel.Parent             = screenGui

-- ============================================================
-- Ammo counter  (bottom-right, large)
-- ============================================================

local ammoLabel                    = Instance.new("TextLabel")
ammoLabel.Name                     = "AmmoLabel"
ammoLabel.Size                     = UDim2.new(0, 200, 0, 44)
ammoLabel.AnchorPoint              = Vector2.new(1, 1)
ammoLabel.Position                 = UDim2.new(1, -24, 1, -24)
ammoLabel.BackgroundTransparency   = 1
ammoLabel.TextColor3               = Color3.new(1, 1, 1)
ammoLabel.TextStrokeColor3         = Color3.new(0, 0, 0)
ammoLabel.TextStrokeTransparency   = 0.5
ammoLabel.Font                     = Enum.Font.GothamBold
ammoLabel.TextSize                 = 28
ammoLabel.TextXAlignment           = Enum.TextXAlignment.Right
ammoLabel.Text                     = "0 / 0"
ammoLabel.Parent                   = screenGui

-- ============================================================
-- Weapon name  (bottom-centre)
-- ============================================================

local weaponCentreLabel            = Instance.new("TextLabel")
weaponCentreLabel.Name             = "WeaponCentreLabel"
weaponCentreLabel.Size             = UDim2.new(0, 240, 0, 22)
weaponCentreLabel.AnchorPoint      = Vector2.new(0.5, 1)
weaponCentreLabel.Position         = UDim2.new(0.5, 0, 1, -26)
weaponCentreLabel.BackgroundTransparency = 1
weaponCentreLabel.TextColor3       = Color3.new(1, 1, 1)
weaponCentreLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
weaponCentreLabel.TextStrokeTransparency = 0.45
weaponCentreLabel.Font             = Enum.Font.GothamBold
weaponCentreLabel.TextSize         = 18
weaponCentreLabel.TextXAlignment   = Enum.TextXAlignment.Center
weaponCentreLabel.Text             = ""
weaponCentreLabel.Parent           = screenGui

-- ============================================================
-- Reactive update functions
-- ============================================================

local HEALTH_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Colour gradient: green (full HP) → red (empty)
local function hpColour(ratio: number): Color3
	return Color3.new(
		math.clamp(2 * (1 - ratio), 0, 1),
		math.clamp(2 * ratio,       0, 1),
		0
	)
end

local function updateHealth()
	local hp    = HUDState.hp:get()    :: number
	local maxHp = HUDState.maxHp:get() :: number
	local ratio = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 1

	TweenService:Create(healthFill, HEALTH_TWEEN, {
		Size             = UDim2.new(ratio, 0, 1, 0),
		BackgroundColor3 = hpColour(ratio),
	}):Play()

	hpLabel.Text = tostring(math.ceil(math.max(hp, 0))) .. " HP"
end

local function updateAmmo()
	local ammo      = HUDState.ammo:get()        :: number
	local mag       = HUDState.magSize:get()     :: number
	local reloading = HUDState.isReloading:get() :: boolean

	if reloading then
		ammoLabel.Text       = "RELOADING..."
		ammoLabel.TextColor3 = Color3.fromRGB(200, 175, 60)
	else
		ammoLabel.Text       = tostring(ammo) .. " / " .. tostring(mag)
		ammoLabel.TextColor3 = if mag > 0 and ammo <= math.floor(mag * 0.25)
			then Color3.fromRGB(220, 70, 70)
			else Color3.new(1, 1, 1)
	end
end

-- ============================================================
-- Subscribe to HUDState changes
-- ============================================================

HUDState.hp:onChange(function(_: any)         updateHealth() end)
HUDState.maxHp:onChange(function(_: any)      updateHealth() end)
HUDState.ammo:onChange(function(_: any)       updateAmmo()   end)
HUDState.magSize:onChange(function(_: any)    updateAmmo()   end)
HUDState.isReloading:onChange(function(_: any) updateAmmo()  end)

HUDState.weaponName:onChange(function(name: any)
	local s = name :: string
	weaponNameLabel.Text   = s
	weaponCentreLabel.Text = s
end)

HUDState.slotLine:onChange(function(line: any)
	slotLabel.Text = line :: string
end)

-- ============================================================
-- Health tracking  (connects to the character's Humanoid)
-- ============================================================

local function connectHealth(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	HUDState.maxHp:set(humanoid.MaxHealth)
	HUDState.hp:set(humanoid.Health)

	humanoid.HealthChanged:Connect(function(newHealth: number)
		HUDState.hp:set(newHealth)
	end)

	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		HUDState.maxHp:set(humanoid.MaxHealth)
	end)
end

if LocalPlayer.Character then
	connectHealth(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(connectHealth)
