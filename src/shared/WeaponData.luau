--!strict
--[[
	WeaponData.luau
	Master weapon database for Urban FPS Battlegrounds.
	Lives in ReplicatedStorage/Shared — required by both server and client.

	Spread  — maximum random cone offset in degrees. Applied per-bullet.
	          0.0 = perfectly accurate; higher = wider spray.
	Recoil  — camera kick magnitude in degrees per shot.
	          Higher values produce more vertical snap on fire.
	FireRate— minimum seconds between shots (1 / rounds-per-second).
	FireMode— "Semi" | "Auto" | "Pump" | "Bolt"
	          Client uses this to decide whether to repeat on held input.
]]

-- ============================================================
-- Type
-- ============================================================

export type Weapon = {
	Name:          string,
	Type:          string,
	Damage:        number,
	FireRate:      number,
	MagSize:       number,
	Spread:        number,
	Recoil:        number,
	FireMode:      string,
	BulletsPerShot: number,
}

-- ============================================================
-- Spread constants (degrees)
-- ============================================================

local SPREAD_NONE:        number = 0.0
local SPREAD_VERY_LOW:    number = 0.5
local SPREAD_LOW:         number = 1.0
local SPREAD_MEDIUM:      number = 2.5
local SPREAD_MEDIUM_HIGH: number = 3.5
local SPREAD_HIGH:        number = 5.0
local SPREAD_VERY_HIGH:   number = 8.0

-- ============================================================
-- Recoil constants (degrees of camera kick per shot)
-- ============================================================

local RECOIL_VERY_LOW: number = 0.5
local RECOIL_LOW:      number = 1.0
local RECOIL_MEDIUM:   number = 2.0
local RECOIL_HIGH:     number = 3.5
local RECOIL_MASSIVE:  number = 6.0

-- ============================================================
-- Weapon Database
-- ============================================================

local WeaponData: { [string]: Weapon } = {

	-- --------------------------------------------------------
	-- Sidearms
	-- --------------------------------------------------------

	Glock19 = {
		Name           = "Glock 19",
		Type           = "Pistol",
		Damage         = 15,
		FireRate       = 0.15,   -- semi-auto: 6.7 rps ceiling
		MagSize        = 15,
		Spread         = SPREAD_LOW,
		Recoil         = RECOIL_LOW,
		FireMode       = "Semi",
		BulletsPerShot = 1,
	},

	DesertEagle = {
		Name           = "Desert Eagle",
		Type           = "Pistol",
		Damage         = 45,     -- near one-shot headshot potential
		FireRate       = 0.40,   -- slow; 2.5 rps ceiling
		MagSize        = 7,
		Spread         = SPREAD_MEDIUM,
		Recoil         = RECOIL_HIGH,
		FireMode       = "Semi",
		BulletsPerShot = 1,
	},

	-- --------------------------------------------------------
	-- Close-Quarters (SMGs / Shotguns)
	-- --------------------------------------------------------

	MAC10 = {
		Name           = "MAC-10",
		Type           = "SMG",
		Damage         = 12,
		FireRate       = 0.05,   -- ~20 rps; burns mags in 1.6 s
		MagSize        = 32,
		Spread         = SPREAD_HIGH,
		Recoil         = RECOIL_HIGH,
		FireMode       = "Auto",
		BulletsPerShot = 1,
	},

	Uzi = {
		Name           = "Uzi",
		Type           = "SMG",
		Damage         = 14,
		FireRate       = 0.07,   -- ~14 rps
		MagSize        = 25,
		Spread         = SPREAD_MEDIUM_HIGH,
		Recoil         = RECOIL_MEDIUM,
		FireMode       = "Auto",
		BulletsPerShot = 1,
	},

	KrissVector = {
		Name           = "Kriss Vector",
		Type           = "SMG",
		Damage         = 11,
		FireRate       = 0.04,   -- ~25 rps; highest fire rate in class
		MagSize        = 33,
		Spread         = SPREAD_LOW,
		Recoil         = RECOIL_VERY_LOW,  -- counter-weight mechanism
		FireMode       = "Auto",
		BulletsPerShot = 1,
	},

	Mossberg500 = {
		Name           = "Mossberg 500",
		Type           = "Shotgun",
		Damage         = 12,     -- per pellet; 8 pellets = 96 max per trigger pull
		FireRate       = 0.80,   -- pump cycle
		MagSize        = 6,
		Spread         = SPREAD_VERY_HIGH,
		Recoil         = RECOIL_HIGH,
		FireMode       = "Pump",
		BulletsPerShot = 8,      -- 8 pellets per shell
	},

	-- --------------------------------------------------------
	-- Mid-to-Long Range (Rifles)
	-- --------------------------------------------------------

	ARPistol = {
		Name           = "AR Pistol",
		Type           = "Rifle",
		Damage         = 22,
		FireRate       = 0.10,   -- 10 rps; mobile street-sweeper
		MagSize        = 30,
		Spread         = SPREAD_MEDIUM,
		Recoil         = RECOIL_MEDIUM,
		FireMode       = "Auto",
		BulletsPerShot = 1,
	},

	AK47 = {
		Name           = "AK-47",
		Type           = "Rifle",
		Damage         = 32,
		FireRate       = 0.12,   -- ~8 rps
		MagSize        = 30,
		Spread         = SPREAD_MEDIUM,
		Recoil         = RECOIL_HIGH,   -- distinctive heavy kick
		FireMode       = "Auto",
		BulletsPerShot = 1,
	},

	SCARL = {
		Name           = "SCAR-L",
		Type           = "Rifle",
		Damage         = 26,
		FireRate       = 0.11,   -- ~9 rps
		MagSize        = 30,
		Spread         = SPREAD_LOW,
		Recoil         = RECOIL_LOW,   -- stable; built for sustained fire
		FireMode       = "Auto",
		BulletsPerShot = 1,
	},

	AWP = {
		Name           = "AWP",
		Type           = "Sniper",
		Damage         = 90,     -- one-shot kill to torso; guaranteed headshot kill
		FireRate       = 1.50,   -- bolt cycle; 0.67 rps
		MagSize        = 5,
		Spread         = SPREAD_NONE, -- pinpoint accurate when scoped/stationary
		Recoil         = RECOIL_MASSIVE,
		FireMode       = "Bolt",
		BulletsPerShot = 1,
	},
}

return WeaponData
