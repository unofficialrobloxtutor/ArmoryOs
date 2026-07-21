--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Config
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types type definitions for framework-wide
--                  configuration values and options.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ViewModelTypes = require(`../Types/ViewModel`)
local Weapons = require(`../Types/Weapons`)

export type ViewModelSettings = ViewModelTypes.ViewModelSettings

-- Distinguishes which weapon category WeaponSettings holds — read this
-- before narrowing WeaponSettings (FireArm.Config | Melee.Config |
-- Throw.Config), rather than trying to infer it from WeaponSettings.Type
-- alone (FireArmTypeNames/MeleeTypeNames/ThrowTypeNames aren't guaranteed
-- disjoint from each other).
export type Category = "FireArm" | "Melee" | "Throw"

export type BaseConfig = {
	Name: string,
	Category: Category,
	Damage: {
		Base: number,
		Limb: {
			Head: number?,
			Torso: number?,
			Arms: number?,
			Legs: number?,
			Feet: number?,
		}?
	},
	CameraInfo: {
		DefaultFOV: number?,
	},

	ViewModelSettings: ViewModelSettings,
	WeaponSettings: Weapons.Config, -- FireArm.Config | Melee.Config | Throw.Config
}

return {}

