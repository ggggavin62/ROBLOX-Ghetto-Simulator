--!strict
--[[
	HUDController.client.luau  (LocalScript — StarterPlayerScripts)

	Builds "MainHUD" ScreenGui using Fusion 0.2.0 reactive state.
	All UI elements are driven by HUDState values — no manual .Text = ... needed.

	Elements created:
	  Crosshair       — 8 px dot, screen centre  (BackgroundColor3 is NOT reactive;
	                    WeaponHandler sets it directly for flash effects)
	  HealthContainer — bottom-left; animated fill via Fusion Spring
	  SlotLabel       — bottom-right, slot indicator
	  WeaponNameLabel — bottom-right, weapon name
	  AmmoLabel       — bottom-right, large ammo counter
	  WeaponCentreLabel — bottom-centre, current weapon name

	Health is tracked via Humanoid.HealthChanged → HUDState.hp:set(…).
	Ammo is tracked by WeaponHandler → HUDState.ammo:set(…) etc.
]]

local Players    = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- ── Fusion ──────────────────────────────────────────────────────────────────

local Fusion: any = require(
	ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion")
)
local Value    = Fusion.Value
local Computed = Fusion.Computed
local Spring   = Fusion.Spring
local New      = Fusion.New
local Children = Fusion.Children

-- ── Shared HUD state ────────────────────────────────────────────────────────

local HUDState = require(script.Parent:WaitForChild("HUDState"))

-- ── Derived / animated state ─────────────────────────────────────────────────

-- Ratio 0→1 representing current HP fraction
local hpRatio = Computed(function()
	local maxHp = HUDState.maxHp:get()
	if maxHp <= 0 then return 1 end
	return math.clamp(HUDState.hp:get() / maxHp, 0, 1)
end)

-- Smooth Spring animation for the health fill bar (speed=18, damping=0.85)
local springRatio = Spring(hpRatio, 18, 0.85)

-- Colour interpolated green (full) → red (empty) based on animated ratio
local healthColour = Computed(function()
	local r = springRatio:get()
	return Color3.new(
		math.clamp(2 * (1 - r), 0, 1),
		math.clamp(2 * r,       0, 1),
		0
	)
end)

-- ── Build ScreenGui ──────────────────────────────────────────────────────────

New("ScreenGui")({
	Name            = "MainHUD",
	ResetOnSpawn    = false,
	IgnoreGuiInset  = true,
	ZIndexBehavior  = Enum.ZIndexBehavior.Sibling,
	DisplayOrder    = 1,
	Parent          = LocalPlayer:WaitForChild("PlayerGui"),

	[Children] = {

		-- ── Crosshair (centre dot) ───────────────────────────────────────────
		New("Frame")({
			Name              = "Crosshair",
			Size              = UDim2.new(0, 8, 0, 8),
			AnchorPoint       = Vector2.new(0.5, 0.5),
			Position          = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundColor3  = Color3.new(0.85, 0.85, 0.85),
			BorderSizePixel   = 0,
			[Children] = {
				New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			},
		}),

		-- ── Health bar container ─────────────────────────────────────────────
		New("Frame")({
			Name             = "HealthContainer",
			Size             = UDim2.new(0, 210, 0, 14),
			AnchorPoint      = Vector2.new(0, 1),
			Position         = UDim2.new(0, 24, 1, -24),
			BackgroundColor3 = Color3.fromRGB(25, 25, 25),
			BorderSizePixel  = 0,
			[Children] = {
				New("UICorner")({ CornerRadius = UDim.new(0, 4) }),

				-- Animated fill bar
				New("Frame")({
					Name             = "HealthFill",
					Size             = Computed(function()
						return UDim2.new(springRatio:get(), 0, 1, 0)
					end),
					BackgroundColor3 = healthColour,
					BorderSizePixel  = 0,
					[Children] = {
						New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
					},
				}),

				-- HP text inside the bar
				New("TextLabel")({
					Name                  = "HPLabel",
					Size                  = UDim2.new(1, -6, 1, 0),
					Position              = UDim2.new(0, 6, 0, 0),
					BackgroundTransparency = 1,
					TextColor3            = Color3.new(1, 1, 1),
					TextStrokeColor3      = Color3.new(0, 0, 0),
					TextStrokeTransparency = 0.45,
					Font                  = Enum.Font.GothamBold,
					TextSize              = 11,
					TextXAlignment        = Enum.TextXAlignment.Left,
					Text                  = Computed(function()
						return tostring(math.ceil(math.max(HUDState.hp:get(), 0))) .. " HP"
					end),
				}),
			},
		}),

		-- ── Slot indicator ───────────────────────────────────────────────────
		New("TextLabel")({
			Name                  = "SlotLabel",
			Size                  = UDim2.new(0, 280, 0, 18),
			AnchorPoint           = Vector2.new(1, 1),
			Position              = UDim2.new(1, -24, 1, -82),
			BackgroundTransparency = 1,
			TextColor3            = Color3.fromRGB(140, 140, 140),
			TextStrokeColor3      = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.5,
			Font                  = Enum.Font.Gotham,
			TextSize              = 12,
			TextXAlignment        = Enum.TextXAlignment.Right,
			Text                  = Computed(function() return HUDState.slotLine:get() end),
		}),

		-- ── Weapon name ──────────────────────────────────────────────────────
		New("TextLabel")({
			Name                  = "WeaponNameLabel",
			Size                  = UDim2.new(0, 200, 0, 22),
			AnchorPoint           = Vector2.new(1, 1),
			Position              = UDim2.new(1, -24, 1, -60),
			BackgroundTransparency = 1,
			TextColor3            = Color3.fromRGB(190, 190, 190),
			TextStrokeColor3      = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.5,
			Font                  = Enum.Font.Gotham,
			TextSize              = 14,
			TextXAlignment        = Enum.TextXAlignment.Right,
			Text                  = Computed(function() return HUDState.weaponName:get() end),
		}),

		-- ── Ammo counter (large) ─────────────────────────────────────────────
		New("TextLabel")({
			Name                  = "AmmoLabel",
			Size                  = UDim2.new(0, 200, 0, 44),
			AnchorPoint           = Vector2.new(1, 1),
			Position              = UDim2.new(1, -24, 1, -24),
			BackgroundTransparency = 1,
			TextColor3            = Computed(function()
				if HUDState.isReloading:get() then
					return Color3.fromRGB(200, 175, 60)
				end
				local ammo = HUDState.ammo:get()
				local mag  = HUDState.magSize:get()
				return if mag > 0 and ammo <= math.floor(mag * 0.25)
					then Color3.fromRGB(220, 70, 70)
					else Color3.new(1, 1, 1)
			end),
			TextStrokeColor3      = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.5,
			Font                  = Enum.Font.GothamBold,
			TextSize              = 28,
			TextXAlignment        = Enum.TextXAlignment.Right,
			Text                  = Computed(function()
				if HUDState.isReloading:get() then
					return "RELOADING..."
				end
				return tostring(HUDState.ammo:get()) .. " / " .. tostring(HUDState.magSize:get())
			end),
		}),

		-- ── Current weapon name (bottom centre) ──────────────────────────────
		New("TextLabel")({
			Name                  = "WeaponCentreLabel",
			Size                  = UDim2.new(0, 240, 0, 22),
			AnchorPoint           = Vector2.new(0.5, 1),
			Position              = UDim2.new(0.5, 0, 1, -26),
			BackgroundTransparency = 1,
			TextColor3            = Color3.new(1, 1, 1),
			TextStrokeColor3      = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.45,
			Font                  = Enum.Font.GothamBold,
			TextSize              = 18,
			TextXAlignment        = Enum.TextXAlignment.Center,
			Text                  = Computed(function() return HUDState.weaponName:get() end),
		}),

	},
})

-- ── Health tracking ──────────────────────────────────────────────────────────

local function connectHealth(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Initialise immediately on spawn
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
