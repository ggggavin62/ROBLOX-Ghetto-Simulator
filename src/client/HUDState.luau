--!strict
--[[
	HUDState.luau  (ModuleScript — StarterPlayerScripts)

	Shared Fusion reactive state for all HUD elements.
	Both HUDController and WeaponHandler require this module to
	read from (via Computed) or write to (via :set()) the same state objects.

	Fusion 0.2.0 Value objects update all subscribers immediately when :set() is called.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion: any = require(
	ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion")
)

return {
	-- Health (updated by HUDController on Humanoid.HealthChanged)
	hp    = Fusion.Value(100),
	maxHp = Fusion.Value(100),

	-- Ammo (updated by WeaponHandler.updateAmmoUI)
	ammo        = Fusion.Value(0),
	magSize     = Fusion.Value(0),
	isReloading = Fusion.Value(false),

	-- Weapon identity (updated by WeaponHandler.updateAmmoUI)
	weaponName = Fusion.Value(""),
	slotLine   = Fusion.Value(""),
}
