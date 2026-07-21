--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Rig
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types — describes the Instance-tree shape
--                  produced by the Armory OS Easy Rig plugin
--                  (Plugins/[ARMORY OS] EASY RIG), for both weapon rigs
--                  (FireArm/Melee/Throw) and viewmodel rigs (R6/R15,
--                  Default/Custom). Documentation/resolution types only —
--                  Instance trees aren't statically indexable in Luau, so
--                  these describe what a resolver should look for and
--                  what it hands back once found, not a type-checked tree.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	WEAPON RIGS — resolved structural parts, one shape per Config.Category
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- FireArm: root is "Handle" or "Grip" (exactly one), everything else
-- optional. Hinge_# is unbounded — any number of extra joints (slide
-- stops, hammers, bolts, etc), keyed by its numeric suffix.
export type FireArmRig = {
	Root: BasePart, -- the "Handle" or "Grip" part, whichever the model has
	RootKind: "Handle" | "Grip",

	Slide: BasePart?,
	Magazine: BasePart?,
	Muzzle: BasePart?,
	Aim: BasePart?,
	EjectShell: BasePart?,

	Hinges: {[number]: BasePart}, -- Hinge_1, Hinge_2, ... keyed by the number

	-- Motor6Ds/WeldConstraints the Easy Rig plugin builds always land here,
	-- never on the parts themselves.
	Constraints: {
		Motor6Ds: Folder,
		Welds: Folder,
	},
}

-- Bladed melee: just the two parts, no optional structural set.
export type MeleeRig = {
	Root: BasePart, -- "Handle"
	Blade: BasePart,

	Constraints: {
		Motor6Ds: Folder,
		Welds: Folder,
	},
}

-- Throwable: "Handle" + "Pin", plus whatever else the model brings (fuse
-- caps, spoons, etc) that isn't part of the fixed naming convention.
export type ThrowRig = {
	Root: BasePart, -- "Handle"
	Pin: BasePart?,

	Extra: {[string]: BasePart}, -- any other named BaseParts found, keyed by Name

	Constraints: {
		Motor6Ds: Folder,
		Welds: Folder,
	},
}

-- Discriminated by Types/Config.Category — resolve against the matching
-- one of these three, never guess the shape from Config.Category alone
-- without narrowing first (same rule as Config.WeaponSettings).
export type WeaponRig = FireArmRig | MeleeRig | ThrowRig

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	VIEWMODEL RIGS — R6/R15, Default/Custom (same structure either way,
--	CustomR6/CustomR15 only differ in mesh source, never bone naming)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

export type ViewModelRigType = "DefaultR6" | "DefaultR15" | "CustomMeshR6" | "CustomMeshR15"

-- Minimum 3 parts: root + two single-bone arms.
export type ViewModelRigR6 = {
	Root: BasePart, -- "HumanoidRootPart" or "Root"
	LeftArm: BasePart,  -- "Left Arm"
	RightArm: BasePart, -- "Right Arm"
}

-- Three-bone arms per side.
export type ViewModelRigR15 = {
	Root: BasePart, -- "HumanoidRootPart" or "Root"

	LeftUpperArm: BasePart,
	LeftLowerArm: BasePart,
	LeftHand: BasePart,

	RightUpperArm: BasePart,
	RightLowerArm: BasePart,
	RightHand: BasePart,
}

-- DefaultR6/CustomMeshR6 both resolve to ViewModelRigR6's shape;
-- DefaultR15/CustomMeshR15 both resolve to ViewModelRigR15's shape — the
-- "Custom" variants only change where the mesh comes from, not which
-- named parts a resolver looks for. Extra parts beyond this set (props,
-- decorative meshes, etc) are ignored, not errored on.
export type ViewModelRig = ViewModelRigR6 | ViewModelRigR15

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	WEAPON <-> VIEWMODEL JOINT
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- The weapon is always jointed directly from the viewmodel's root, never
-- from a hand/grip attachment — Part0 = viewmodel Root (HumanoidRootPart
-- or RootPart), Part1 = the weapon rig's Root (Handle/Grip on FireArm and
-- Melee, Handle on Throw).
export type WeaponMountJoint = {
	Part0: BasePart, -- ViewModelRig.Root
	Part1: BasePart, -- WeaponRig.Root
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ANIMATION NAMING — how clips under Assets/Animations bind to a rig
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Every clip is named <WeaponId>_<AnimName> and lives under a subfolder
-- root that decides which rig it plays on: Animations/FirstPerson (the
-- viewmodel arms rig), or Animations/ThirdPerson/R6 / ThirdPerson/R15
-- (the character, split per rig type — R6/R15 clips never interchange).
-- Resolution is recursive under each root, so deeper nesting is free-form.
export type AnimationRigTarget = "FirstPerson" | "ThirdPersonR6" | "ThirdPersonR15"

return {}
