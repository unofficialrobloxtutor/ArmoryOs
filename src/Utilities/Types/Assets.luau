--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Assets
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types — shapes for the server-side asset
--                  loader (Utilities/Core/Server/Assets). Leaf file: no
--                  requires, safe to pull from anywhere without cycles.
--
--                  Asset folder layout the loader reads from (children of
--                  the AmoryOS root's Assets folder, added in Studio and
--                  preserved by rojo via $ignoreUnknownInstances):
--                    Assets/Rigs/<RigName>                  — viewmodel arm rigs
--                    Assets/Models/<WeaponId>               — weapon rigs
--                    Assets/Animations/FirstPerson/...      — viewmodel anims
--                    Assets/Animations/ThirdPerson/R6/...   — R6 character anims
--                    Assets/Animations/ThirdPerson/R15/...  — R15 character anims
--                  Animation naming: <WeaponId>_<AnimName> (recursive find,
--                  so deeper nesting under those roots is free-form; the
--                  FirstPerson/ThirdPerson/R6/R15 folder names themselves
--                  are load-bearing).
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Everything the Animations folder holds for one weapon, bucketed by
-- which rig the clip plays on. Keys are the AnimName suffix ("Equip",
-- "Fire", "Reload", ...), values are the Animation instances themselves —
-- the caller decides which Animator to load them into. ThirdPerson is
-- split per rig type because R6 and R15 clips are never interchangeable.
export type ThirdPersonAnimations = {
	R6  : { [string]: Animation },
	R15 : { [string]: Animation },
}

export type AnimationTree = {
	FirstPerson : { [string]: Animation },
	ThirdPerson : ThirdPersonAnimations,
}

-- The server asset loader. Owned by Utilities/Core/Server (server.Assets);
-- every method resolves against the Assets folder and errors with a clear
-- path-style message when a required asset is missing.
export type Type = {
	-- Clones a viewmodel arms rig from Assets/Rigs/<rigName> and validates
	-- it has a root (HumanoidRootPart/RootPart) per Types/Rig ViewModelRig.
	BuildViewModel: (self: Type, rigName: string) -> Model,

	-- Clones a weapon rig from Assets/Models/<weaponId> and validates it
	-- has a root (Handle/Grip) per Types/Rig WeaponRig.
	BuildWeaponModel: (self: Type, weaponId: string) -> Model,

	-- Clones arms + weapon and joints them per Types/Rig WeaponMountJoint
	-- (Motor6D, Part0 = viewmodel root, Part1 = weapon root) — the complete
	-- first-person model, ready to hand to a client or pose on the server.
	BuildFirstPersonModel: (self: Type, rigName: string, weaponId: string) -> Model,

	-- Collects every Animation named <weaponId>_* under Assets/Animations
	-- into an AnimationTree — FirstPerson bucket, plus ThirdPerson split
	-- into R6/R15 by the subfolder each clip lives under.
	BuildAnimationTree: (self: Type, weaponId: string) -> AnimationTree,

	-- Loads the ThirdPerson bucket matching the character's own rig type
	-- (Humanoid.RigType → R6 or R15) onto its Animator, returning the
	-- tracks keyed by AnimName. Pair with Data/Streams/ThirdPersonStream
	-- (already registered by Network core) for head/body look replication.
	LoadThirdPersonAnimations: (self: Type, character: Model, weaponId: string) -> { [string]: AnimationTrack },

	-- Boot-time asset audit: walks every config under Data/Configs and
	-- warns (never errors) about missing rigs, models, required parts,
	-- and expected animations — one grouped warning per weapon. Called
	-- automatically by Utilities/Core/Server on boot.
	Audit: (self: Type) -> (),

	Destroy: (self: Type) -> (),
}

return {}
