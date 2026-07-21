--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       1911
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Configs/FireArm — example Pistol BaseConfig
--                  (Utilities/Types/Config.BaseConfig), with WeaponSettings
--                  conforming to Utilities/Types/Weapons/FireArm.Config.
--                  WeaponId = "1911".
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ConfigType  = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Config)
local FireArmType = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Weapons.FireArm)
type BaseConfig = ConfigType.BaseConfig
type FireArmConfig = FireArmType.Config

return {
	Name = "1911",
	Category = "FireArm",

	Damage = {
		Base = 22,
		Limb = {
			Head  = 3,
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
		Arms      = "Classic", -- R6 (Left Arm / Right Arm), shared arms rig under Assets/Rigs
		HipOffset = CFrame.new(0.4, -1, -1),
		Clothing  = {MatchCharacter = true},
		Sway      = {Intensity = 1.4, Speed = 2.5, MaxOffset = 1.8},
		Bob       = {Intensity = 0.7, Speed = 8},
		Breath    = {Intensity = 0.25, Speed = 1.1},
	},

	WeaponSettings = {
		Physics = {
			Base_Velocity    = 1500,
			Gravity_Modifier = 1,
			Max_Distance     = 500,
		},

		Penetration = {
			Penetration_Count = 1,
			Material_Penetration = {
				[Enum.Material.Wood]  = {Thickness = 0.5, Power = {0.6}},
				[Enum.Material.Metal] = {Thickness = 1.5, Power = {0.2}},
			},
			Damage_Fall_Off_Start  = 25,
			Damage_Fall_Off_End    = 150,
			Ricochet_Angle_Degrees = 15,
		},

		Damage = {
			Base_Damage         = 22,
			Headshot_Multiplier = 3,
			Limb_Multiplier     = 0.8,
			Min_Damage          = 8,
			Max_Damage          = 22,
		},

		Fire = {
			Fire_Modes        = {"Semi"},
			Default_Fire_Mode = "Semi",
			Fire_Rate         = 300,
			Auto_Fire         = false,
		},

		Recoil = {
			Vertical             = 1.8,
			Horizontal           = 0.6,
			Horizontal_Variance  = 0.3,
			Recovery_Speed       = 10,
			Camera_Kick          = 0.4,
			Camera_Kick_Recovery = 12,
		},

		Spread = {
			Base_Spread          = 1,
			Max_Spread           = 4,
			Moving_Multiplier    = 1.6,
			Jumping_Multiplier   = 2.5,
			Crouching_Multiplier = 0.7,
			Aiming_Multiplier    = 0.3,
			Increase_Per_Shot    = 0.4,
			Recovery_Speed       = 8,
		},

		Reload = {
			Reload_Time          = 1.7,
			Tactical_Reload_Time = 1.5,
			Empty_Reload_Time    = 2,
			Chamber_Round        = true,
			Interruptible        = true,
		},

		Aim = {
			Aim_Fov             = 20,
			Aim_Speed           = 10,
			Aim_Sensitivity     = 0.9,
			Aim_Sway_Multiplier = 0.6,
		},

		Ammo = {
			Bullet        = ".45 ACP",
			Ejected_Shell = "PistolShell",
			Reserve       = 63,
			In            = 7,
			Max           = 7,
		},

		Data = {
			Use_Bullets         = true,
			Use_Ray_As_Bullet   = false,
			Use_Trail_As_Bullet = true,
			Infinite_Ammo       = false,
			Infinite_Reserve    = false,
		},

		-- Classic built-in client sounds (rbxasset:// always exists, zero
		-- streaming delay) — swap any entry for a toolbox "rbxassetid://<id>"
		-- to upgrade it.
		Sound = {
			Fire    = "rbxasset://sounds/paintball.wav",
			Empty   = "rbxasset://sounds/button.wav",
			Equip   = "rbxasset://sounds/unsheath.wav",
			Reload  = "rbxasset://sounds/electronicpingshort.wav",
			Aim_In  = "rbxasset://sounds/snap.wav",
			Aim_Out = "rbxasset://sounds/snap.wav",
		},

		Type = "Pistol",
		Behavior = {
			Akimbo = false,
		},
	} :: FireArmConfig,
} :: BaseConfig
