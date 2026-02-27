--!strict
--[[
	WeaponConfig.luau
	Shared constants for all weapon configurations.
	Required by WeaponDamage.server and WeaponHandler.client.
	Lives in ReplicatedStorage/Shared so both sides can require() it.
]]

-- ============================================================
-- Exported Types
-- ============================================================

export type WeaponStats = {
	NAME: string,
	DISPLAY_NAME: string,
	FIRE_RATE: number,
	MIN_SHOT_INTERVAL: number,
	DAMAGE: number,
	HEADSHOT_MULTIPLIER: number,
	MAX_DISTANCE: number,
	MAG_SIZE: number,
	RELOAD_TIME: number,
	LOS_TOLERANCE: number,
	MUZZLE_FLASH_DURATION: number,
	GUNSHOT_SOUND_ID: number,
	RELOAD_SOUND_ID: number,
	EMPTY_SOUND_ID: number,
}

export type NpcWeaponStats = {
	DAMAGE: number,
	FIRE_RATE: number,
	MIN_SHOT_INTERVAL: number,
	MAX_DISTANCE: number,
}

-- ============================================================
-- Module
-- ============================================================

local WeaponConfig = {}

-- ============================================================
-- GLOCK 19 (Player Weapon)
-- ============================================================

WeaponConfig.GLOCK_19: WeaponStats = {
	NAME                  = "Glock 19",
	DISPLAY_NAME          = "G19",

	-- Firing
	FIRE_RATE             = 2,       -- max shots per second (semi-auto ceiling)
	MIN_SHOT_INTERVAL     = 0.5,     -- 1 / FIRE_RATE; minimum seconds between shots

	-- Damage
	DAMAGE                = 25,      -- HP per body hit
	HEADSHOT_MULTIPLIER   = 2.0,     -- head hit = 50 HP

	-- Range
	MAX_DISTANCE          = 150,     -- studs; shots rejected beyond this on server

	-- Ammo
	MAG_SIZE              = 15,      -- Glock 19 standard magazine capacity
	RELOAD_TIME           = 2.0,     -- seconds to reload

	-- Server verification
	LOS_TOLERANCE         = 5,       -- max stud delta between server/client hit positions

	-- Visual / Audio (rbxassetid — 0 = placeholder until assets are added)
	MUZZLE_FLASH_DURATION = 0.05,
	GUNSHOT_SOUND_ID      = 0,
	RELOAD_SOUND_ID       = 0,
	EMPTY_SOUND_ID        = 0,
}

-- ============================================================
-- NPC Weapon
-- ============================================================

WeaponConfig.NPC_WEAPON: NpcWeaponStats = {
	DAMAGE             = 15,
	FIRE_RATE          = 1,      -- 1 shot per second
	MIN_SHOT_INTERVAL  = 1.0,
	MAX_DISTANCE       = 40,     -- studs; NPC detection and shoot range
}

return WeaponConfig
