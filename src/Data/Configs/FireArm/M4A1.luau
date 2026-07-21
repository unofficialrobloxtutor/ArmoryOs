--!nonstrict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       M4A1
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Configs/FireArm — example AssaultRifle BaseConfig
--                  (Utilities/Types/Config.BaseConfig), with WeaponSettings
--                  conforming to Utilities/Types/Weapons/FireArm.Config.
--                  WeaponId = "M4A1".
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ConfigType  = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Config)
local FireArmType = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Weapons.FireArm)
type BaseConfig = ConfigType.BaseConfig
type FireArmConfig = FireArmType.Config

return {
	Name = "M4A1",
	Category = "FireArm",

	Damage = {
		Base = 24,
		Limb = {
			Head  = 2.5,
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
		Arms      = "M4A1_Arms", -- TODO: resolved against Assets/Rigs once a naming convention is settled
		HipOffset = CFrame.new(0.5, -1, -1.2),
		Clothing  = {MatchCharacter = true},
		Sway      = {Intensity = 1,   Speed = 2, MaxOffset = 1.5},
		Bob       = {Intensity = 0.8, Speed = 8},
		Breath    = {Intensity = 0.2, Speed = 1},
	},

	WeaponSettings = {
		Physics = {
			Base_Velocity    = 2000,
			Gravity_Modifier = 1,
			Max_Distance     = 1000,
		},

		Penetration = {
			Penetration_Count = 2,
			Material_Penetration = {
				[Enum.Material.Wood]  = {Thickness = 1, Power = {0.5}},
				[Enum.Material.Metal] = {Thickness = 3, Power = {0.15}},
			},
			Damage_Fall_Off_Start  = 50,
			Damage_Fall_Off_End    = 300,
			Ricochet_Angle_Degrees = 15,
		},

		Damage = {
			Base_Damage         = 24,
			Headshot_Multiplier = 2.5,
			Limb_Multiplier     = 0.8,
			Min_Damage          = 6,
			Max_Damage          = 24,
		},

		Fire = {
			Fire_Modes        = {"Semi", "Auto"},
			Default_Fire_Mode = "Auto",
			Fire_Rate         = 750,
			Auto_Fire         = true,
		},

		Recoil = {
			Vertical             = 1.2,
			Horizontal           = 0.4,
			Horizontal_Variance  = 0.2,
			Recovery_Speed       = 8,
			Camera_Kick          = 0.6,
			Camera_Kick_Recovery = 10,
		},

		Spread = {
			Base_Spread          = 1.5,
			Max_Spread           = 6,
			Moving_Multiplier    = 1.8,
			Jumping_Multiplier   = 3,
			Crouching_Multiplier = 0.7,
			Aiming_Multiplier    = 0.4,
			Increase_Per_Shot    = 0.6,
			Recovery_Speed       = 6,
		},

		Reload = {
			Reload_Time          = 2.4,
			Tactical_Reload_Time = 2.1,
			Empty_Reload_Time    = 2.8,
			Chamber_Round        = true,
			Interruptible        = true,
		},

		Aim = {
			Aim_Fov             = 15,
			Aim_Speed           = 8,
			Aim_Sensitivity     = 0.85,
			Aim_Sway_Multiplier = 0.5,
		},

		Ammo = {
			Bullet        = "5.56x45mm",
			Ejected_Shell = "RifleShell",
			Reserve       = 120,
			In            = 30,
			Max           = 30,
		},

		Data = {
			Use_Bullets         = true,
			Use_Ray_As_Bullet   = false,
			Use_Trail_As_Bullet = true,
			Infinite_Ammo       = false,
			Infinite_Reserve    = false,
		},

		-- Classic built-in client sounds — see 1911.luau's Sound note.
		Sound = {
			Fire    = "rbxasset://sounds/Rubber band sling shot.wav",
			Empty   = "rbxasset://sounds/button.wav",
			Equip   = "rbxasset://sounds/unsheath.wav",
			Reload  = "rbxasset://sounds/electronicpingshort.wav",
			Aim_In  = "rbxasset://sounds/snap.wav",
			Aim_Out = "rbxasset://sounds/snap.wav",
		},

		Type = "AssaultRifle",
		Behavior = {
			Hip_Fire_Accuracy = 0.6,
		},
	} :: FireArmConfig,
} :: BaseConfig
