--!strict
--[[
	HUDState.luau  (ModuleScript — StarterPlayerScripts)

	Shared observable state for all HUD elements.
	Replaces Fusion.Value with a minimal hand-rolled observable so that
	no external packages are required.

	Each value exposes:
	  :get()             → returns the current value
	  :set(newVal)       → sets the value and fires all onChange listeners
	  :onChange(fn)      → registers a callback invoked on every :set() call

	WeaponHandler.client writes via :set().
	HUDController.client reads via :get() and subscribes via :onChange().
]]

-- ============================================================
-- Observable type
-- ============================================================

type Observable = {
	get:      (self: Observable) -> any,
	set:      (self: Observable, newVal: any) -> (),
	onChange: (self: Observable, fn: (any) -> ()) -> (),
}

local function makeValue(initial: any): Observable
	local current: any              = initial
	local listeners: { (any) -> () } = {}

	local obs: Observable = {
		get = function(_self: Observable): any
			return current
		end,

		set = function(_self: Observable, newVal: any)
			current = newVal
			for _, fn in listeners do
				fn(newVal)
			end
		end,

		onChange = function(_self: Observable, fn: (any) -> ())
			table.insert(listeners, fn)
		end,
	}

	return obs
end

-- ============================================================
-- Exported state table
-- ============================================================

return {
	-- Health (written by HUDController on Humanoid.HealthChanged)
	hp    = makeValue(100),
	maxHp = makeValue(100),

	-- Ammo (written by WeaponHandler.updateAmmoUI)
	ammo        = makeValue(0),
	magSize     = makeValue(0),
	isReloading = makeValue(false),

	-- Weapon identity (written by WeaponHandler.updateAmmoUI)
	weaponName = makeValue(""),
	slotLine   = makeValue(""),
}
