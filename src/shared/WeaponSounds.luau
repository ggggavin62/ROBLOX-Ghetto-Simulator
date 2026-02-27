--!strict
--[[
	WeaponSounds.luau
	Sound asset ID map for every weapon in WeaponData.
	Shared so both server and client can reference it (currently client-only use).

	Fire IDs use a shared standard gunshot: rbxassetid://136365595975777
	Reload and Empty IDs are still 0 (silent placeholder) — replace with
	weapon-specific assets when available.

	WeaponSoundSet fields:
	  Fire   — primary gunshot / firing sound (plays every shot)
	  Reload — full reload sequence or mag-swap sound
	  Empty  — dry-fire click when trying to fire on an empty mag
]]

export type WeaponSoundSet = {
	Fire:   number,
	Reload: number,
	Empty:  number,
}

local WeaponSounds: { [string]: WeaponSoundSet } = {

	-- ---- Sidearms ----

	Glock19 = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: mag click + slide rack
		Empty  = 0,  -- TODO: light trigger click
	},

	DesertEagle = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: deagle mag swap
		Empty  = 0,  -- TODO: heavy trigger click
	},

	-- ---- SMGs ----

	MAC10 = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: small box-mag swap
		Empty  = 0,  -- TODO: trigger click
	},

	Uzi = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: Uzi mag swap
		Empty  = 0,  -- TODO: trigger click
	},

	KrissVector = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: Vector reload
		Empty  = 0,  -- TODO: trigger click
	},

	-- ---- Shotgun ----

	Mossberg500 = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: pump-action rack + shell load
		Empty  = 0,  -- TODO: dry pump click
	},

	-- ---- Rifles ----

	ARPistol = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: AR pistol mag swap
		Empty  = 0,  -- TODO: trigger click
	},

	AK47 = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: AK mag rock-and-lock swap
		Empty  = 0,  -- TODO: trigger click
	},

	SCARL = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: SCAR mag swap
		Empty  = 0,  -- TODO: trigger click
	},

	-- ---- Sniper ----

	AWP = {
		Fire   = 136365595975777,
		Reload = 0,  -- TODO: bolt cycle sound
		Empty  = 0,  -- TODO: bolt-forward click on empty chamber
	},
}

return WeaponSounds
