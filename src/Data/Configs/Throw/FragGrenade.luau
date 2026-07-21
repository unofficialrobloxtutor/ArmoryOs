--!nonstrict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       FragGrenade
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Configs/Throw — example Grenade BaseConfig
--                  (Utilities/Types/Config.BaseConfig), with WeaponSettings
--                  conforming to Utilities/Types/Weapons/Throw.Config.
--                  WeaponId = "FragGrenade".
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ConfigType = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Config)
local ThrowType  = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Weapons.Throw)
type BaseConfig = ConfigType.BaseConfig
type ThrowConfig = ThrowType.Config

return {
	Name = "FragGrenade",
	Category = "Throw",

	Damage = {
		Base = 100,
		Limb = {
			Head  = 1,
			Torso = 1,
			Arms  = 1,
			Legs  = 1,
			Feet  = 1,
		},
	},

	CameraInfo = {
		DefaultFOV = 90,
	},

	ViewModelSettings = {
		Arms      = "FragGrenade_Arms", -- TODO: resolved against Assets/Rigs once a naming convention is settled
		HipOffset = CFrame.new(0.3, -0.8, -0.9),
		Sway      = {Intensity = 0.8, Speed = 2, MaxOffset = 1},
		Bob       = {Intensity = 0.5, Speed = 6},
	},

	WeaponSettings = {
		Physics = {
			Throw_Velocity   = 90,
			Min_Velocity     = 30,
			Gravity_Modifier = 1,
			Max_Distance     = 120,
		},

		Damage = {
			Explosion_Radius       = 18,
			Explosion_Damage       = 100,
			Explosion_Falloff      = true,
			Min_Damage             = 10,
			Headshot_Multiplier    = 1,
			Limb_Multiplier        = 1,
			Requires_Line_Of_Sight = true,
		},

		Fuse = {
			Fuse_Time          = 3.5,
			Cookable           = true,
			Detonate_On_Impact = false,
		},

		Inventory = {
			Max_Capacity   = 2,
			Count          = 2,
			Consume_On_Use = true,
		},

		Type = "Grenade",
		Behavior = {
			Bounce_Count       = 2,
			Bounce_Restitution = 0.4,
		},
	} :: ThrowConfig,
} :: BaseConfig
