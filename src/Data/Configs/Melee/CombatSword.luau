--!nonstrict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       CombatSword
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Configs/Melee — example Sword BaseConfig
--                  (Utilities/Types/Config.BaseConfig), with WeaponSettings
--                  conforming to Utilities/Types/Weapons/Melee.Config.
--                  WeaponId = "CombatSword".
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ConfigType = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Config)
local MeleeType  = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Weapons.Melee)
type BaseConfig = ConfigType.BaseConfig
type MeleeConfig = MeleeType.Config

return {
	Name = "CombatSword",
	Category = "Melee",

	Damage = {
		Base = 35,
		Limb = {
			Head  = 2,
			Torso = 1,
			Arms  = 0.8,
			Legs  = 0.8,
			Feet  = 0.8,
		},
	},

	CameraInfo = {
		DefaultFOV = 90,
	},

	ViewModelSettings = {
		Arms      = "CombatSword_Arms", -- TODO: resolved against Assets/Rigs once a naming convention is settled
		HipOffset = CFrame.new(0.4, -0.9, -1),
		Sway      = {Intensity = 1.2, Speed = 2.5, MaxOffset = 1.8},
		Bob       = {Intensity = 0.6, Speed = 6},
	},

	WeaponSettings = {
		Damage = {
			Base_Damage         = 35,
			Heavy_Multiplier    = 1.8,
			Headshot_Multiplier = 2,
			Limb_Multiplier     = 0.8,
			Min_Damage          = 10,
		},

		Swing = {
			Range            = 6,
			Angle_Degrees    = 70,
			Light_Swing_Time = 0.35,
			Heavy_Swing_Time = 0.65,
			Combo_Window     = 1.2,
			Max_Combo        = 3,
		},

		Block = {
			Damage_Reduction    = 50,
			Block_Angle_Degrees = 100,
		},

		Parry = {
			Parry_Window     = 0.25,
			Stagger_Duration = 1,
		},

		Knockback = {
			Base_Force = 15,
			Scale      = 0.3,
		},

		Data = {
			Hitbox_Debug = false,
		},

		Type = "Sword",
		Behavior = {
			Bleed_Chance          = 0.15,
			Bleed_Damage_Per_Tick = 2,
		},
	} :: MeleeConfig,
} :: BaseConfig
