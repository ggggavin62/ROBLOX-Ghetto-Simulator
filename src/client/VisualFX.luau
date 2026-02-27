--!strict
--[[
	VisualFX.luau  (ModuleScript — StarterPlayerScripts)
	Three client-side visual systems for the weapon handler.

	1. Muzzle Flash
	   A brief yellow-white bloom Frame at screen centre that fades in 0.06 s.
	   Call initMuzzleFlash(screenGui) once after HUD is built, then
	   showMuzzleFlash() every shot.

	2. Bullet Impact Spark
	   A tiny Neon Part at the world hit position, destroyed after 0.12 s.
	   Call showImpact(position) on every client-confirmed hit.

	3. Scope Overlay  (AWP / Sniper)
	   Dark top/bottom panels + scope ring + thin crosshair lines.
	   Tweens Camera.FieldOfView: 70 ↔ 20.
	   Call initScope() once on startup, then scopeIn/scopeOut(crosshair)
	   on right-click. WeaponHandler owns the isScoped boolean state;
	   this module is purely visual with no state of its own.
]]

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local Debris       = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- 1. Muzzle Flash
-- ============================================================

local muzzleFlash: Frame? = nil

local FLASH_FADE = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function initMuzzleFlash(parent: ScreenGui)
	local flash                    = Instance.new("Frame")
	flash.Name                     = "MuzzleFlash"
	flash.Size                     = UDim2.new(0, 22, 0, 22)
	flash.AnchorPoint              = Vector2.new(0.5, 0.5)
	flash.Position                 = UDim2.new(0.5, 0, 0.5, 0)
	flash.BackgroundColor3         = Color3.fromRGB(255, 225, 80)
	flash.BackgroundTransparency   = 1
	flash.BorderSizePixel          = 0
	flash.ZIndex                   = 5
	flash.Parent                   = parent

	local corner                   = Instance.new("UICorner")
	corner.CornerRadius            = UDim.new(1, 0)
	corner.Parent                  = flash

	muzzleFlash = flash
end

local function showMuzzleFlash()
	if not muzzleFlash then return end
	muzzleFlash.BackgroundTransparency = 0
	TweenService:Create(muzzleFlash, FLASH_FADE, { BackgroundTransparency = 1 }):Play()
end

-- ============================================================
-- 2. Bullet Impact Spark
-- ============================================================

local function showImpact(position: Vector3)
	local spark              = Instance.new("Part")
	spark.Name               = "ImpactSpark"
	spark.Size               = Vector3.new(0.18, 0.18, 0.18)
	spark.CFrame             = CFrame.new(position)
	spark.Anchored           = true
	spark.CanCollide         = false
	spark.CanQuery           = false
	spark.CastShadow         = false
	spark.Material           = Enum.Material.Neon
	spark.Color              = Color3.fromRGB(255, 190, 45)
	spark.Parent             = workspace
	Debris:AddItem(spark, 0.12)
end

-- ============================================================
-- 3. Scope Overlay
-- ============================================================

local scopeGui: ScreenGui? = nil

local FOV_DEFAULT: number = 70
local FOV_SCOPED:  number = 20

local SCOPE_IN  = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SCOPE_OUT = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function initScope()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	local gui                    = Instance.new("ScreenGui")
	gui.Name                     = "ScopeHUD"
	gui.ResetOnSpawn             = false
	gui.IgnoreGuiInset           = true
	gui.ZIndexBehavior           = Enum.ZIndexBehavior.Sibling
	gui.Enabled                  = false
	gui.Parent                   = playerGui

	-- Top dark panel (top 33 % of screen)
	local topPanel                     = Instance.new("Frame")
	topPanel.Name                      = "ScopeTop"
	topPanel.Size                      = UDim2.new(1, 0, 0.33, 0)
	topPanel.Position                  = UDim2.new(0, 0, 0, 0)
	topPanel.BackgroundColor3          = Color3.fromRGB(0, 0, 0)
	topPanel.BackgroundTransparency    = 0.04
	topPanel.BorderSizePixel           = 0
	topPanel.Parent                    = gui

	-- Bottom dark panel (bottom 33 % of screen)
	local bottomPanel                  = Instance.new("Frame")
	bottomPanel.Name                   = "ScopeBottom"
	bottomPanel.Size                   = UDim2.new(1, 0, 0.33, 0)
	bottomPanel.AnchorPoint            = Vector2.new(0, 1)
	bottomPanel.Position               = UDim2.new(0, 0, 1, 0)
	bottomPanel.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	bottomPanel.BackgroundTransparency = 0.04
	bottomPanel.BorderSizePixel        = 0
	bottomPanel.Parent                 = gui

	-- Decorative scope ring (transparent circle with dark border)
	local ring                         = Instance.new("Frame")
	ring.Name                          = "ScopeRing"
	ring.Size                          = UDim2.new(0.335, 0, 0.335, 0)
	ring.AnchorPoint                   = Vector2.new(0.5, 0.5)
	ring.Position                      = UDim2.new(0.5, 0, 0.5, 0)
	ring.BackgroundTransparency        = 1
	ring.BorderSizePixel               = 0
	ring.Parent                        = gui

	local ringCorner                   = Instance.new("UICorner")
	ringCorner.CornerRadius            = UDim.new(1, 0)
	ringCorner.Parent                  = ring

	local ringStroke                   = Instance.new("UIStroke")
	ringStroke.Color                   = Color3.fromRGB(12, 12, 12)
	ringStroke.Thickness               = 3
	ringStroke.Parent                  = ring

	-- Horizontal crosshair line (full-width, 1 px tall, centred)
	local hLine                        = Instance.new("Frame")
	hLine.Name                         = "HLine"
	hLine.Size                         = UDim2.new(1, 0, 0, 1)
	hLine.AnchorPoint                  = Vector2.new(0, 0.5)
	hLine.Position                     = UDim2.new(0, 0, 0.5, 0)
	hLine.BackgroundColor3             = Color3.fromRGB(18, 18, 18)
	hLine.BackgroundTransparency       = 0
	hLine.BorderSizePixel              = 0
	hLine.Parent                       = gui

	-- Vertical crosshair line (full-height, 1 px wide, centred)
	local vLine                        = Instance.new("Frame")
	vLine.Name                         = "VLine"
	vLine.Size                         = UDim2.new(0, 1, 1, 0)
	vLine.AnchorPoint                  = Vector2.new(0.5, 0)
	vLine.Position                     = UDim2.new(0.5, 0, 0, 0)
	vLine.BackgroundColor3             = Color3.fromRGB(18, 18, 18)
	vLine.BackgroundTransparency       = 0
	vLine.BorderSizePixel              = 0
	vLine.Parent                       = gui

	scopeGui = gui
end

local function scopeIn(crosshair: Frame)
	crosshair.Visible = false
	if scopeGui then scopeGui.Enabled = true end
	TweenService:Create(
		workspace.CurrentCamera :: Camera,
		SCOPE_IN,
		{ FieldOfView = FOV_SCOPED }
	):Play()
end

local function scopeOut(crosshair: Frame)
	crosshair.Visible = true
	if scopeGui then scopeGui.Enabled = false end
	TweenService:Create(
		workspace.CurrentCamera :: Camera,
		SCOPE_OUT,
		{ FieldOfView = FOV_DEFAULT }
	):Play()
end

-- ============================================================
-- Module Table
-- ============================================================

return {
	initMuzzleFlash = initMuzzleFlash,
	showMuzzleFlash = showMuzzleFlash,
	showImpact      = showImpact,
	initScope       = initScope,
	scopeIn         = scopeIn,
	scopeOut        = scopeOut,
}
