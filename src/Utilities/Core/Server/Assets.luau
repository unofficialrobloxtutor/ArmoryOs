--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Server.Assets
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Core/Server asset loader — the server-side
--                  way to work with the Assets folder. Builds viewmodel
--                  arm rigs, weapon rigs, complete first-person models
--                  (arms + weapon jointed per Types/Rig WeaponMountJoint),
--                  animation trees bucketed by rig target, and loads
--                  third-person character animations onto an Animator.
--
--                  Owned by Utilities/Core/Server — reach it through
--                  server.Assets. Head/body look replication itself is
--                  handled by Data/Streams/ThirdPersonStream, which
--                  Utilities/Core/Network already registers on boot;
--                  LoadThirdPersonAnimations covers the clip side of the
--                  same third-person picture.
--
--                  Shapes: Utilities/Types/Assets (loader + AnimationTree)
--                  and Utilities/Types/Rig (what "valid rig" means).
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Requires     ◄--
local AssetsTypes = require(script.Parent.Parent.Parent.Types.Assets)
--► Tables       ◄--
local Module = {}
Module.__index = Module
--► Types        ◄--
export type AnimationTree = AssetsTypes.AnimationTree
export type Type = AssetsTypes.Type

--► Constants    ◄--
-- Viewmodel rigs root: names accepted for ViewModelRig.Root (Types/Rig).
local VIEWMODEL_ROOT_NAMES = { "HumanoidRootPart", "RootPart", "Root" }
-- Weapon rigs root: names accepted for WeaponRig.Root (Types/Rig).
local WEAPON_ROOT_NAMES = { "Handle", "Grip" }
-- Animations subfolders that decide a clip's rig target (Types/Rig
-- AnimationRigTarget). Clips under ThirdPerson split further into R6/R15
-- subfolders; anything not under ThirdPerson counts as FirstPerson.
local THIRD_PERSON_FOLDER = "ThirdPerson"
local RIG_TYPE_FOLDERS = { "R6", "R15" }

-- Animations every weapon is expected to ship, per category — the audit
-- warns (never errors) when one is missing from the FirstPerson bucket.
local EXPECTED_ANIMATIONS: { [string]: { string } } = {
	FireArm = { "Equip", "UnEquip", "Fire", "Reload" },
	Melee   = { "Equip", "UnEquip", "Swing" },
	Throw   = { "Equip", "UnEquip", "Throw" },
}

-- Structural parts every weapon rig must have, per category — mirrors the
-- client's _buildWeaponRig hard requirements so the audit catches at boot
-- what would otherwise error at equip time.
local REQUIRED_PARTS: { [string]: { string } } = {
	FireArm = { "Muzzle", "EjectShell", "Aim", "Slide" },
	Melee   = { "Blade" },
	Throw   = { "Pin" },
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PRIVATE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- The AmoryOS root's Assets folder (added in Studio, preserved by rojo's
-- $ignoreUnknownInstances). script → Server → Core → Utilities → root.
local function _assetsRoot(): Instance
	local root = script.Parent.Parent.Parent.Parent
	local assets = root:FindFirstChild("Assets")
	if not assets then
		error("[Server Assets] No Assets folder under the AmoryOS root — add Assets/Rigs, Assets/Models, Assets/Animations in Studio", 3)
	end
	return assets
end

-- Recursive lookup under one Assets subfolder, mirroring the client's
-- _findAsset so both sides resolve names identically.
local function _findAsset(folder: string, name: string): Instance?
	local container = _assetsRoot():FindFirstChild(folder)
	if not container then
		return nil
	end
	return container:FindFirstChild(name, true)
end

-- First child (recursive) whose Name matches any entry in a name list.
local function _findFirstNamed(model: Model, names: { string }): BasePart?
	for _, name in ipairs(names) do
		local found = model:FindFirstChild(name, true)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

-- Clones a template Model out of an Assets subfolder, erroring with the
-- full Assets path when it's missing or not a Model.
local function _cloneTemplate(folder: string, name: string): Model
	local template = _findAsset(folder, name)
	if not template or not template:IsA("Model") then
		error(("[Server Assets] '%s' not found under Assets/%s (or is not a Model)"):format(name, folder), 3)
	end
	return template:Clone()
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CONSTRUCTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.New(): Type
	local self = setmetatable({}, Module)
	return (self :: any) :: Type
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RIG BUILDERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Clones a viewmodel arms rig from Assets/Rigs/<rigName> and validates
--  the minimum Types/Rig ViewModelRig structure (a root part; the arm
--  parts differ between R6 and R15 so only the root is hard-required here).
function Module.BuildViewModel(self: Type, rigName: string): Model
	local clone = _cloneTemplate("Rigs", rigName)

	local root = _findFirstNamed(clone, VIEWMODEL_ROOT_NAMES)
	if not root then
		clone:Destroy()
		error(("[Server Assets] Rig '%s' has no HumanoidRootPart/RootPart — not a valid viewmodel rig"):format(rigName), 2)
	end

	clone.PrimaryPart = root
	return clone
end

--► Clones a weapon rig from Assets/Models/<weaponId> and validates the
--  Types/Rig WeaponRig root (Handle or Grip, whichever the model has).
function Module.BuildWeaponModel(self: Type, weaponId: string): Model
	local clone = _cloneTemplate("Models", weaponId)

	local root = _findFirstNamed(clone, WEAPON_ROOT_NAMES)
	if not root then
		clone:Destroy()
		error(("[Server Assets] Weapon '%s' has no Handle/Grip root — not a valid weapon rig"):format(weaponId), 2)
	end

	clone.PrimaryPart = root
	return clone
end

--► Builds the complete first-person model: arms rig + weapon rig under
--  one Model, jointed per Types/Rig WeaponMountJoint — a Motor6D with
--  Part0 = viewmodel root, Part1 = weapon root. Never a grip attachment.
function Module.BuildFirstPersonModel(self: Type, rigName: string, weaponId: string): Model
	local arms   = self:BuildViewModel(rigName)
	local weapon = self:BuildWeaponModel(weaponId)

	local armsRoot   = arms.PrimaryPart
	local weaponRoot = weapon.PrimaryPart
	if not armsRoot or not weaponRoot then
		error("[Server Assets] BuildFirstPersonModel — rig roots missing after build", 2)
	end

	weapon:PivotTo(armsRoot.CFrame)

	local joint = Instance.new("Motor6D")
	joint.Name  = "WeaponMount"
	joint.Part0 = armsRoot
	joint.Part1 = weaponRoot
	joint.Parent = armsRoot

	weapon.Parent = arms
	return arms
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ANIMATIONS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Collects every Animation named <weaponId>_<AnimName> anywhere under
--  Assets/Animations into an AnimationTree. A clip under a ThirdPerson
--  subfolder buckets into R6 or R15 by the rig-type folder it sits under
--  (clips under ThirdPerson but outside both are skipped with a warning —
--  R6/R15 clips never interchange, so there is no safe default); anything
--  not under ThirdPerson counts as FirstPerson.
function Module.BuildAnimationTree(self: Type, weaponId: string): AnimationTree
	local tree: AnimationTree = { FirstPerson = {}, ThirdPerson = { R6 = {}, R15 = {} } }

	local animations = _assetsRoot():FindFirstChild("Animations")
	if not animations then
		return tree
	end

	local prefix = weaponId .. "_"
	for _, descendant in animations:GetDescendants() do
		if not descendant:IsA("Animation") then
			continue
		end
		if descendant.Name:sub(1, #prefix) ~= prefix then
			continue
		end

		local animName = descendant.Name:sub(#prefix + 1)
		if animName == "" then
			continue
		end

		local thirdPerson = descendant:FindFirstAncestor(THIRD_PERSON_FOLDER)
		if thirdPerson and thirdPerson:IsDescendantOf(animations) then
			local bucketed = false
			for _, rigType in ipairs(RIG_TYPE_FOLDERS) do
				local rigFolder = descendant:FindFirstAncestor(rigType)
				if rigFolder and rigFolder:IsDescendantOf(thirdPerson) then
					tree.ThirdPerson[rigType][animName] = descendant
					bucketed = true
					break
				end
			end
			if not bucketed then
				warn(("[Server Assets] '%s' sits under Animations/ThirdPerson but outside an R6/R15 subfolder — skipped"):format(descendant.Name))
			end
		else
			tree.FirstPerson[animName] = descendant
		end
	end

	return tree
end

--► Loads the ThirdPerson bucket matching a character's own rig type
--  (Humanoid.RigType → R6 or R15) onto its Animator, returning the tracks
--  keyed by AnimName. The head/body look side of third person is
--  Data/Streams/ThirdPersonStream, already registered by Utilities/Core/
--  Network on boot — this covers the clips.
function Module.LoadThirdPersonAnimations(self: Type, character: Model, weaponId: string): { [string]: AnimationTrack }
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		error(("[Server Assets] Character '%s' has no Humanoid — cannot load third-person animations"):format(character.Name), 2)
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end

	local rigType = if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"

	local tree = self:BuildAnimationTree(weaponId)
	local tracks: { [string]: AnimationTrack } = {}
	for animName, animation in tree.ThirdPerson[rigType] do
		tracks[animName] = animator:LoadAnimation(animation)
	end

	return tracks
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	BOOT-TIME ASSET AUDIT
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Requires every config ModuleScript under Data/Configs, returning the
-- ones that loaded and look like a BaseConfig (Name + Category).
local function _collectConfigs(): { any }
	local configs: { any } = {}

	local root = script.Parent.Parent.Parent.Parent
	local data = root:FindFirstChild("Data")
	local configsFolder = data and data:FindFirstChild("Configs")
	if not configsFolder then
		warn("[Asset Audit] No Data/Configs folder found — nothing to audit")
		return configs
	end

	for _, descendant in configsFolder:GetDescendants() do
		if not descendant:IsA("ModuleScript") then
			continue
		end
		local ok, config = pcall(require, descendant)
		if not ok then
			warn(("[Asset Audit] Config '%s' failed to load: %s"):format(descendant.Name, tostring(config)))
			continue
		end
		if type(config) ~= "table" or type(config.Name) ~= "string" or type(config.Category) ~= "string" then
			warn(("[Asset Audit] Config '%s' is not a BaseConfig (missing Name/Category)"):format(descendant.Name))
			continue
		end
		table.insert(configs, config)
	end

	return configs
end

--► Walks every config under Data/Configs and warns — never errors — about
--  anything a weapon expects but the Assets folder doesn't provide:
--  missing arms rig, missing weapon model, missing category-required
--  parts, missing expected FirstPerson animations, and a ThirdPerson
--  bucket with no clips for either rig type. One grouped warning per
--  weapon so Output stays readable. Called by Utilities/Core/Server on boot.
function Module.Audit(self: Type)
	local assets = script.Parent.Parent.Parent.Parent:FindFirstChild("Assets")
	if not assets then
		warn("[Asset Audit] No Assets folder under the AmoryOS root — every weapon will fail to equip")
		return
	end

	for _, config in _collectConfigs() do
		local problems: { string } = {}
		local weaponId = config.Name
		local category = config.Category

		-- Arms rig
		local viewModelSettings = config.ViewModelSettings
		local rigName = if type(viewModelSettings) == "table" then viewModelSettings.Arms else nil
		if type(rigName) ~= "string" then
			table.insert(problems, "config has no ViewModelSettings.Arms rig name")
		else
			local rig = _findAsset("Rigs", rigName)
			if not rig or not rig:IsA("Model") then
				table.insert(problems, ("missing arms rig Assets/Rigs/%s"):format(rigName))
			elseif not _findFirstNamed(rig, VIEWMODEL_ROOT_NAMES) then
				table.insert(problems, ("rig '%s' has no HumanoidRootPart/RootPart"):format(rigName))
			end
		end

		-- Weapon model + required parts
		local model = _findAsset("Models", weaponId)
		if not model or not model:IsA("Model") then
			table.insert(problems, ("missing weapon model Assets/Models/%s"):format(weaponId))
		else
			if not _findFirstNamed(model, WEAPON_ROOT_NAMES) then
				table.insert(problems, "weapon model has no Handle/Grip root")
			end
			for _, partName in ipairs(REQUIRED_PARTS[category] or {}) do
				if not model:FindFirstChild(partName, true) then
					table.insert(problems, ("weapon model is missing required part '%s'"):format(partName))
				end
			end
		end

		-- Animations
		local tree = self:BuildAnimationTree(weaponId)
		for _, animName in ipairs(EXPECTED_ANIMATIONS[category] or {}) do
			if not tree.FirstPerson[animName] then
				table.insert(problems, ("missing Animations/FirstPerson clip '%s_%s'"):format(weaponId, animName))
			end
		end
		if next(tree.ThirdPerson.R6) == nil and next(tree.ThirdPerson.R15) == nil then
			table.insert(problems, "no ThirdPerson clips for either rig type (Animations/ThirdPerson/R6|R15)")
		end

		if #problems > 0 then
			warn(("[Asset Audit] %s (%s):\n  - %s"):format(weaponId, category, table.concat(problems, "\n  - ")))
		end
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	LIFECYCLE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Destroy(self: Type)
	-- Stateless — clones are owned by their callers.
end

return Module
