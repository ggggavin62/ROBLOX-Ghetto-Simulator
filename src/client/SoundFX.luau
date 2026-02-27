--!strict
--[[
	SoundFX.luau  (ModuleScript — StarterPlayerScripts)
	Manages weapon Sound instances under SoundService and exposes
	three play functions to WeaponHandler.

	Sounds are parented to SoundService (not 3D-positioned) so they play
	as flat first-person audio for the local player only.

	Usage:
	  local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
	  SoundFX.playFire("AK47")
	  SoundFX.playReload("Glock19")
	  SoundFX.playEmpty("Mossberg500")
]]

local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- WeaponSounds (shared asset ID map)
-- ============================================================

type WeaponSoundSet = { Fire: number, Reload: number, Empty: number }

local WeaponSounds = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponSounds")
) :: { [string]: WeaponSoundSet }

-- ============================================================
-- Sound Instance Factory
-- ============================================================

local sfxFolder      = Instance.new("Folder")
sfxFolder.Name       = "WeaponSFX"
sfxFolder.Parent     = SoundService

type SoundSet = { Fire: Sound, Reload: Sound, Empty: Sound }

local soundSets: { [string]: SoundSet } = {}

local function makeSound(assetId: number, volume: number): Sound
	local s              = Instance.new("Sound")
	s.SoundId            = if assetId > 0
		then "rbxassetid://" .. tostring(assetId)
		else ""
	s.Volume             = volume
	s.RollOffMaxDistance = 0  -- no 3D attenuation; flat first-person audio
	s.Parent             = sfxFolder
	return s
end

for key, set in WeaponSounds do
	soundSets[key] = {
		Fire   = makeSound(set.Fire,   0.85),
		Reload = makeSound(set.Reload, 0.65),
		Empty  = makeSound(set.Empty,  0.50),
	}
end

-- ============================================================
-- Public API
-- ============================================================

local SoundFX = {}

-- Play the firing sound for the given weapon key.
-- Silent no-op if the asset ID is 0 (placeholder).
function SoundFX.playFire(weaponKey: string)
	local s = soundSets[weaponKey]
	if s and s.Fire.SoundId ~= "" then
		s.Fire:Play()
	end
end

-- Play the reload sound for the given weapon key.
function SoundFX.playReload(weaponKey: string)
	local s = soundSets[weaponKey]
	if s and s.Reload.SoundId ~= "" then
		s.Reload:Play()
	end
end

-- Play the dry-fire / empty-mag click for the given weapon key.
function SoundFX.playEmpty(weaponKey: string)
	local s = soundSets[weaponKey]
	if s and s.Empty.SoundId ~= "" then
		s.Empty:Play()
	end
end

return SoundFX
