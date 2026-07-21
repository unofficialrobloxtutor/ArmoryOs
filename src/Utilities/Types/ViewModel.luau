--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       ViewModel
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types/ViewModelSettings — split out of
--                  Config.luau so it has no dependency on Weapons/Config,
--                  letting BaseConfig reference a weapon's Config (which
--                  itself needs ViewModelSettings) without a cyclic require.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Arms + weapon-model build/behavior settings — consumed when the
-- viewmodel is auto-built on Equip (Utilities/Core/Client). Shared by
-- every weapon category's Config (see Types/Weapons/FireArm.luau, etc)
-- so each one only needs `ViewModel: ViewModelTypes.ViewModelSettings`.
export type ViewModelSettings = {
	Arms: string, -- arms rig template (Assets/Rigs), cloned and held onto Camera on build
	HipOffset: CFrame?, -- rest pose offset from camera, relative

	Clothing: {
		MatchCharacter: boolean?, -- if true, will attempt to match the player's character clothing (Shirt, Pants, BodyColors) on build
		Shirt: string?,
		Pants: string?,
		BodyColors: {
			HeadColor: Color3?,
			LeftArmColor: Color3?,
			RightArmColor: Color3?,
			TorsoColor: Color3?,
			LeftLegColor: Color3?,
			RightLegColor: Color3?,
		}?
	}?,

	Sway: {
		Intensity: number?,
		Speed: number?,
		MaxOffset: number?,
	}?,
	Bob: {
		Intensity: number?,
		Speed: number?,
	}?,
	Breath: {
		Intensity: number?,
		Speed: number?,
	}?,
}

return {}
