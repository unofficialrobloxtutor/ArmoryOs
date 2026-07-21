--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       RPG7
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Configs/FireArm — example Launcher BaseConfig.
--                  Fires a slow visible rocket (stepped projectile via
--                  Projectile_Library) that detonates on first impact;
--                  blast damage is dealt server-side by the
--                  firearm/RPG7/explode route. WeaponId = "RPG7".
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ConfigType  = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Config)
local FireArmType = require(script.Parent.Parent.Parent.Parent.Utilities.Types.Weapons.FireArm)
type BaseConfig = ConfigType.BaseConfig
type FireArmConfig = FireArmType.Config

return {
	Name = "RPG7",
	Category = "FireArm",

	Damage = {
		Base = 90,
	},

	CameraInfo = {
		DefaultFOV = 90,
	},

	ViewModelSettings = {
		Arms      = "Classic",
		HipOffset = CFrame.new(0.5, -1.1, -1.2),
		Clothing  = {MatchCharacter = true},
		Sway      = {Intensity = 1.1, Speed = 2, MaxOffset = 1.4},
		Bob       = {Intensity = 0.6, Speed = 7},
		Breath    = {Intensity = 0.3, Speed = 1},
	},

	WeaponSettings = {
		Physics = {
			Base_Velocity    = 180,
			Gravity_Modifier = 0.35, -- rockets sag a little, not like a mortar
			Max_Distance     = 600,
		},

		-- Rockets never penetrate — they stop and detonate at surface one
		-- (StopOnFirstHit), so this block only matters for the ray budget.
		Penetration = {
			Penetration_Count = 1,
			Damage_Fall_Off_Start = 600,
			Damage_Fall_Off_End   = 600,
			Ricochet_Angle_Degrees = 0,
		},

		-- Direct-hit damage of the rocket body itself (rarely relevant —
		-- the blast is what kills).
		Damage = {
			Base_Damage         = 90,
			Headshot_Multiplier = 1,
			Limb_Multiplier     = 1,
			Min_Damage          = 90,
			Max_Damage          = 90,
		},

		Fire = {
			Fire_Modes        = {"Semi"},
			Default_Fire_Mode = "Semi",
			Fire_Rate         = 30, -- one rocket every 2 seconds
			Auto_Fire         = false,
		},

		Recoil = {
			Vertical             = 6,
			Horizontal           = 1.2,
			Horizontal_Variance  = 0.4,
			Recovery_Speed       = 5,
			Camera_Kick          = 1.5,
			Camera_Kick_Recovery = 6,
		},

		Spread = {
			Base_Spread          = 0.5,
			Max_Spread           = 2,
			Moving_Multiplier    = 1.8,
			Jumping_Multiplier   = 3,
			Crouching_Multiplier = 0.7,
			Aiming_Multiplier    = 0.4,
			Increase_Per_Shot    = 1,
			Recovery_Speed       = 4,
		},

		Reload = {
			Reload_Time          = 3.5,
			Tactical_Reload_Time = 3.5,
			Empty_Reload_Time    = 3.5,
			Chamber_Round        = false,
			Interruptible        = true,
		},

		Aim = {
			Aim_Fov             = 45,
			Aim_Speed           = 6,
			Aim_Sensitivity     = 0.8,
			Aim_Sway_Multiplier = 0.7,
		},

		Ammo = {
			Bullet        = "PG-7V Rocket",
			Reserve       = 4,
			In            = 1,
			Max           = 1,
		},

		Sound = {
			Fire    = "rbxasset://sounds/Shoulder fired rocket.wav",
			Empty   = "rbxasset://sounds/button.wav",
			Equip   = "rbxasset://sounds/unsheath.wav",
			Reload  = "rbxasset://sounds/electronicpingshort.wav",
			Aim_In  = "rbxasset://sounds/snap.wav",
			Aim_Out = "rbxasset://sounds/snap.wav",
		},

		Data = {
			Use_Bullets         = true,
			Use_Ray_As_Bullet   = false,
			Use_Trail_As_Bullet = false, -- the projectile part IS the visual
			Infinite_Ammo       = false,
			Infinite_Reserve    = false,
		},

		Type = "Launcher",
		Behavior = {
			Projectile_Speed = 180,
			Blast_Radius     = 14,
			Blast_Damage     = 95,

			Guided     = false, -- flip on (with Turn_Speed) for wire-guided steering
			Turn_Speed = 1.5,
		},
	} :: FireArmConfig,
} :: BaseConfig
