--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Client
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Core client entry point ("AOS") — the
--                  client-side weapon view layer. Owns the equipped
--                  weapon's gameplay class (FireArm_Class | Melee_Class |
--                  Throw_Class) and its physical viewmodel (arms + weapon
--                  model, welded per the Armory OS Easy Rig plugin's
--                  convention — Motor6D Part0 = viewmodel root
--                  (HumanoidRootPart/Root), Part1 = weapon root
--                  (Handle/Grip)), and drives both every frame.
--
--                  AOS:Equip(weaponId, config) auto-builds the viewmodel
--                  and constructs the matching weapon class in one call —
--                  no separate manual build step. AOS:UnEquip() tears both
--                  down. AOS:ApplyAction(name, ...) dispatches straight to
--                  a method on the equipped weapon class, gated by a
--                  per-category whitelist (CategoryActions below) so it
--                  can never be pointed at an arbitrary method.
--
--                  Also defines every Data/Streams channel (same
--                  definitions as Utilities/Core/Network mounts on the
--                  server — RoExpress.Stream requires both sides to
--                  declare identical channels before Stream.Init()) and
--                  exposes the loaded stream modules so weapon classes
--                  can send through them, e.g.
--                  self.Streams.FireArmStream.Fire(weaponId, origin, dir).
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local Players    = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
local RunService  = game:GetService("RunService")
--► Requires     ◄--
local RoExpress   = require(script.Parent.Parent.Libraries.RoExpress_Library)
local Validator   = require(script.Parent.Parent.Libraries.Validator_Library)
local CF          = require(script.Parent.Parent.Libraries.CFrame_Library)
local Spring      = require(script.Parent.Parent.Classes.Spring_Class)
local FireArmClass = require(script.Parent.Parent.Classes.FireArm_Class)
local MeleeClass   = require(script.Parent.Parent.Classes.Melee_Class)
local ThrowClass   = require(script.Parent.Parent.Classes.Throw_Class)
--► Types        ◄--
export type Type = typeof(setmetatable({} :: {
	Streams: {[string]: any},
	Config: any, -- Types/Config.BaseConfig
	Class: any,  -- FireArm_Class.Type | Melee_Class.Type | Throw_Class.Type
}, {} :: {__index: any}))
--► Tables       ◄--
local Module = {}
Module.__index = Module
--► Constants    ◄--
-- Data/Streams modules — must match Utilities/Core/Network's STREAM_MODULES.
local STREAM_MODULES = {
	"FireArmStream",
	"MeleeStream",
	"ThrowStream",
	"ThirdPersonStream",
}

-- Weapon gameplay class per Config.Category — see Types/Config.Category.
local WEAPON_CLASSES: {[string]: any} = {
	FireArm = FireArmClass,
	Melee   = MeleeClass,
	Throw   = ThrowClass,
}

-- App route prefix per Config.Category — matches Data/Routes/{FireArm,
-- Melee,Throw}Routes.luau's mounted paths (e.g. "firearm/:WeaponId/equip").
local ROUTE_PREFIX: {[string]: string} = {
	FireArm = "firearm",
	Melee   = "melee",
	Throw   = "throw",
}

-- Whitelist of what ApplyAction is allowed to call per category, and onto
-- which real method on the weapon class it maps. Anything not listed here
-- is refused — ApplyAction never does a bare self.Class[Action] lookup.
local CategoryActions: {[string]: {[string]: string}} = {
	FireArm = {
		Fire           = "Fire",
		Reload         = "Reload",
		TacticalReload = "TacticalReload",
		EmptyReload    = "EmptyReload",
		SetAim         = "SetAim",
		IronSightAim   = "IronSightAim",
		ScopeAim       = "ScopeAim",
		SwitchFireMode = "SwitchFireMode",
		SwitchArm      = "SwitchArm",
	},
	Melee = {
		Attack = "Attack",
		Block  = "Block",
		Parry  = "Parry",
	},
	Throw = {
		PullPin  = "PullPin",
		Throw    = "Throw",
		Detonate = "Detonate",
	},
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	STREAM LOADING (client only)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Requires every module in STREAM_MODULES (defining their channels),
-- then finalizes with Stream.Init() so they connect to the server's remotes.
local function _loadStreams(): { [string]: any }
	local streamsFolder = script.Parent.Parent.Parent.Data.Streams
	local loaded: { [string]: any } = {}

	for _, name in ipairs(STREAM_MODULES) do
		local child = streamsFolder:FindFirstChild(name)
		if not child or not child:IsA("ModuleScript") then
			warn("[Client Core] Missing stream module '" .. name .. "'")
			continue
		end
		loaded[name] = require(child)
	end

	RoExpress.Stream.Init()
	return loaded
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ASSET RESOLUTION + RIG VALIDATION — per Plugins/[ARMORY OS] EASY RIG's
--	naming convention (see Utilities/Types/Rig.luau)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

local function _findAsset(folder: string, name: string): Instance?
	local assetsRoot = script.Parent.Parent.Parent.Assets :: Instance?
	local category = assetsRoot and assetsRoot:FindFirstChild(folder)
	return category and category:FindFirstChild(name, true)
end

-- Clones the arms template and validates it has a root (HumanoidRootPart
-- or Root) plus either the R6 (Left Arm/Right Arm) or R15
-- (LeftUpperArm/.../RightHand) limb set — see Types/Rig.ViewModelRig.
local function _buildViewModelRig(self: any, rigName: string): Model
	local template = _findAsset("Rigs", rigName) :: Model?
	if not template then
		error(("[Client Core] ViewModel rig '%s' not found under Assets/Rigs"):format(rigName), 2)
	end

	local clone = template:Clone()
	clone.Name = "ViewModelArms"

	local root = clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChild("Root")
	if not root then
		error(("[Client Core] ViewModel rig '%s' is missing a HumanoidRootPart/Root"):format(rigName), 2)
	end

	local isR15 = clone:FindFirstChild("LeftUpperArm") ~= nil
	if isR15 then
		local required = {"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"}
		for _, partName in required do
			if not clone:FindFirstChild(partName) then
				error(("[Client Core] R15 ViewModel rig '%s' is missing '%s'"):format(rigName, partName), 2)
			end
		end
	else
		if not clone:FindFirstChild("Left Arm") or not clone:FindFirstChild("Right Arm") then
			error(("[Client Core] R6 ViewModel rig '%s' requires 'Left Arm' and 'Right Arm'"):format(rigName), 2)
		end
	end

	clone.PrimaryPart = root :: BasePart
	return clone
end

-- Clones the weapon template and validates its structural parts against
-- the rig plugin's per-category convention — see Types/Rig.WeaponRig.
-- Everything beyond these required parts (Hinge_#, cosmetic weld folders,
-- extras) is ignored here; only the parts this class actually needs to
-- function are checked.
local function _buildWeaponRig(config: any): Model
	local weaponId = config.Name
	local template = _findAsset("Models", weaponId) :: Model?
	if not template then
		error(("[Client Core] Weapon model '%s' not found under Assets/Models"):format(weaponId), 2)
	end

	local clone = template:Clone()
	clone.Name = weaponId

	local root = clone:FindFirstChild("Handle") or clone:FindFirstChild("Grip")
	if not root then
		error(("[Client Core] Weapon '%s' requires a 'Handle' or 'Grip' root part"):format(weaponId), 2)
	end

	local category = config.Category
	if category == "FireArm" then
		local required = {"Muzzle", "EjectShell", "Aim", "Slide"}
		for _, partName in required do
			if not clone:FindFirstChild(partName) then
				error(("[Client Core] FireArm '%s' requires: Muzzle, EjectShell, Aim, and Slide"):format(weaponId), 2)
			end
		end
	elseif category == "Melee" then
		if not clone:FindFirstChild("Blade") then
			error(("[Client Core] Melee '%s' requires a 'Blade' part"):format(weaponId), 2)
		end
	elseif category == "Throw" then
		if not clone:FindFirstChild("Pin") then
			error(("[Client Core] Throw '%s' requires a 'Pin' part"):format(weaponId), 2)
		end
	end

	clone.PrimaryPart = root :: BasePart
	return clone
end

-- Motor6D Part0 = viewmodel root, Part1 = weapon root — always, per the
-- rig plugin's convention (never a hand/grip attachment). Destroys any
-- pre-existing "Handle" motor first so re-equipping the same rig instance
-- is idempotent.
local function _weldWeaponToViewModel(viewModel: Model, weaponModel: Model)
	local root = viewModel.PrimaryPart :: BasePart
	local weaponRoot = weaponModel.PrimaryPart :: BasePart

	local existing = root:FindFirstChild("Handle")
	if existing then
		existing:Destroy()
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "Handle"
	motor.Part0 = root
	motor.Part1 = weaponRoot
	motor.Parent = root

	weaponModel.Parent = viewModel
end

-- Every viewmodel BasePart gets its own CollisionGroup so it never
-- interferes with the local character's own hitbox/ground checks.
local function _applyViewModelCollisions(viewModel: Model)
	for _, part in viewModel:GetDescendants() do
		if part:IsA("BasePart") then
			local ok = pcall(function(p: BasePart)
				p.CollisionGroup = "ViewModel"
			end, part)
			if not ok then
				-- CollisionGroup "ViewModel" not registered via PhysicsService yet;
				-- leave the part on Default rather than erroring the whole build.
			end
		end
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	VIEWMODEL ANIMATIONS — Equip/UnEquip only for now. Playback goes
--	through the viewmodel's OWN AnimationController/Humanoid (the rig
--	plugin adds one of these to every built rig), never the character's
--	Animator — the viewmodel is a separate rig entirely.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Gets (or lazily creates) the Animator sitting under the viewmodel's own
-- AnimationController/Humanoid.
local function _getViewModelAnimator(viewModel: Model): Animator?
	local controller = viewModel:FindFirstChildOfClass("AnimationController")
		or viewModel:FindFirstChildOfClass("Humanoid")
	if not controller then
		return nil
	end
	return controller:FindFirstChildOfClass("Animator") or Instance.new("Animator", controller)
end

-- Naming convention: Assets/Animations/FirstPerson/<WeaponId>_<AnimName>,
-- e.g. "M4A1_Equip" — mirrors the auto-resolve-by-naming-convention
-- comments already on FireArm/Melee/Throw Config.Sound/Animation fields.
-- Scoped to the FirstPerson subfolder (never all of Animations) because
-- ThirdPerson/R6|R15 clips share the same <WeaponId>_<AnimName> names.
local function _loadViewModelAnimation(viewModel: Model, weaponId: string, animName: string): AnimationTrack?
	local animator = _getViewModelAnimator(viewModel)
	if not animator then
		return nil
	end

	local animationsRoot = _findAsset("Animations", "FirstPerson")
	if not animationsRoot then
		warn("[Client Core] Assets/Animations has no FirstPerson folder — viewmodel clips cannot load")
		return nil
	end

	local animation = animationsRoot:FindFirstChild(weaponId .. "_" .. animName, true)
	if not animation or not animation:IsA("Animation") then
		return nil
	end

	return animator:LoadAnimation(animation)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CLOTHING — SurfaceAppearance-based, matches the rig plugin's approach
--	(ColorMap per limb part) since viewmodel arms are custom mesh/part
--	rigs, not humanoid-driven, so a Shirt/Pants instance has nothing to
--	attach to.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- SurfaceAppearance.ColorMap is plugin-only at runtime, so we can't build
-- one from a raw texture id here. Instead we look for a pre-authored
-- SurfaceAppearance under Assets (named "Shirt_<numericId>") and clone it
-- onto every limb part; if no template exists the clothing is skipped with
-- a warning rather than failing the whole viewmodel build.
local function _applyShirtTexture(viewModel: Model, shirtAssetId: string)
	local numericId = shirtAssetId:match("(%d+)$") or shirtAssetId

	local template = _findAsset("Clothing", "Shirt_" .. numericId)
	if not template or not template:IsA("SurfaceAppearance") then
		warn(("[Client Core] Clothing: no SurfaceAppearance asset 'Shirt_%s' under Assets\\Clothing — skipping shirt"):format(numericId))
		return
	end

	for _, part in viewModel:GetDescendants() do
		if part:IsA("BasePart") then
			local existing = part:FindFirstChildOfClass("SurfaceAppearance")
			if existing then
				existing:Destroy()
			end
			local sa = template:Clone()
			sa.Name = "ShirtTexture"
			sa.Parent = part
		end
	end
end

local function _applyClothing(viewModel: Model, character: Model?, clothingCfg)
	if not clothingCfg then
		return
	end

	if clothingCfg.MatchCharacter and character then
		local charShirt = character:FindFirstChildOfClass("Shirt")
		if charShirt and charShirt.ShirtTemplate ~= "" then
			_applyShirtTexture(viewModel, charShirt.ShirtTemplate)
		end
		return
	end

	if clothingCfg.Shirt then
		_applyShirtTexture(viewModel, clothingCfg.Shirt)
	end

	local colors = clothingCfg.BodyColors
	if colors then
		for _, part in viewModel:GetDescendants() do
			if part:IsA("BasePart") then
				local lname = string.lower(part.Name)
				local color = (string.find(lname, "head") and colors.HeadColor)
					or (string.find(lname, "left") and colors.LeftArmColor)
					or (string.find(lname, "right") and colors.RightArmColor)
					or colors.TorsoColor
				if color then
					part.Color = color
				end
			end
		end
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	VISIBILITY — viewmodel stays parented under the Camera at all times;
--	first/third-person is a LocalTransparencyModifier toggle, not a
--	reparent, so it can be re-applied every frame cheaply.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

local function _setModelTransparency(model: Model, transparent: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = transparent and 1 or 0
		elseif part:IsA("Decal") then
			part.LocalTransparencyModifier = transparent and 1 or 0
		end
	end
end

-- True while the camera is actually zoomed into first-person distance —
-- irrelevant (forced) when only one of first/third-person is enabled at
-- all, since there's nothing to zoom between in that case.
local function _isFirstPersonView(self: any): boolean
	if not self._thirdPersonEnabled then
		return true
	end
	if not self._firstPersonEnabled then
		return false
	end
	local camera = self.Camera :: Camera
	return (camera.CFrame.Position - camera.Focus.Position).Magnitude < 1
end

-- Roblox re-derives LocalTransparencyModifier every frame, so both of
-- these are re-applied continuously from Render() rather than set once.
local function _applyViewModelVisibility(self: any, inFirstPersonView: boolean)
	if self.ViewModel then
		_setModelTransparency(self.ViewModel, self._viewModelHidden or not self._firstPersonEnabled or not inFirstPersonView)
	end
end

local function _applyThirdPersonVisibility(self: any, inFirstPersonView: boolean)
	local character = self.Character :: Model?
	if character then
		_setModelTransparency(character, not self._thirdPersonEnabled or (self._firstPersonEnabled and inFirstPersonView))
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CAMERA MODE — first/third-person "off entirely" means constraining the
--	zoom range, not just picking a default distance; with both enabled the
--	player's own scroll wheel decides (CameraMinZoomDistance/Max left
--	alone), matching vanilla Roblox zoom-to-first-person behavior.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

local FIRST_PERSON_ONLY_ZOOM = 0.5
local THIRD_PERSON_MIN_ZOOM  = 10
local THIRD_PERSON_MAX_ZOOM  = 20

local function _applyCameraZoomConstraints(self: any)
	local humanoid = self.Humanoid :: Humanoid?
	if not humanoid then
		return
	end

	local player = self.Player :: Player

	if self._firstPersonEnabled and not self._thirdPersonEnabled then
		humanoid.CameraOffset = Vector3.zero
		player.CameraMinZoomDistance = 0
		player.CameraMaxZoomDistance = FIRST_PERSON_ONLY_ZOOM
	elseif self._thirdPersonEnabled and not self._firstPersonEnabled then
		player.CameraMinZoomDistance = THIRD_PERSON_MIN_ZOOM
		player.CameraMaxZoomDistance = THIRD_PERSON_MAX_ZOOM
	else
		-- Both on (or both off, which falls back to letting the player scroll
		-- freely rather than leaving them with no usable camera at all) —
		-- leave Roblox's own zoom range alone.
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 400
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	HEAD LOOK — own camera pitch applied to own Neck (visible in
--	third-person / mirrors) and broadcast over ThirdPersonStream so other
--	clients' third-person view of this player matches.
--
--	NOTE: ThirdPersonStream's schema is Pitch-only ({Pitch: f32}, no
--	player id), and Stream/init.lua's client-side _dispatch always passes
--	sender = nil (only OnServerEvent gets a Player arg — OnClientEvent
--	never does). That means a receiving client currently has no way to
--	tell which other player a given Pitch broadcast belongs to, so only
--	the *local* player's own look is applied here. Rendering other
--	players' head look needs a player id added to that channel's schema
--	first — flagging rather than guessing at a workaround.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

local MAX_LOOK_PITCH = math.rad(89)
local LOOK_SEND_EPSILON = math.rad(1) -- only send when pitch moved at least this much

local function _cacheNeckBaseC0(self: any)
	local character = self.Character :: Model?
	local head = character and character:FindFirstChild("Head")
	local neck = head and head:FindFirstChild("Neck")
	self._neckBaseC0 = (neck and neck:IsA("Motor6D")) and neck.C0 or nil
end

local function _applyOwnHeadLook(self: any, dt: number)
	local character = self.Character :: Model?
	local head = character and character:FindFirstChild("Head")
	local neck = head and head:FindFirstChild("Neck")
	if not (neck and neck:IsA("Motor6D") and self._neckBaseC0) then
		return
	end

	local camera = self.Camera :: Camera
	local pitch = math.clamp((select(1, camera.CFrame:ToEulerAnglesYXZ())), -MAX_LOOK_PITCH, MAX_LOOK_PITCH)

	neck.C0 = (self._neckBaseC0 :: CFrame) * CFrame.Angles(-pitch, 0, 0)

	local streams = self.Streams :: {[string]: any}
	if streams.ThirdPersonStream and math.abs(pitch - (self._lastSentPitch or 0)) >= LOOK_SEND_EPSILON then
		self._lastSentPitch = pitch
		streams.ThirdPersonStream.UpdateLook(pitch)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SPRINGS — Bob/Sway/Breath drive the hip-fire pose every frame; Recoil
--	is fed impulses by the weapon class (FireArm_Class.Render already
--	tracks its own recoil offset — Client's Recoil spring is the
--	camera-facing complement, driven from Fired-style feedback signals
--	rather than duplicating FireArm_Class's math here).
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

local function _handleBob(self: any, dt: number): Vector3
	local moveDir = self.Humanoid.MoveDirection
	local magnitude = moveDir.Magnitude

	if magnitude > 0.05 then
		local amplitude = math.clamp(magnitude * 2, 0.05, 1)
		local time = os.clock() * 9
		self.Springs.Bob.SetState({
			Target = Vector3.new(
				math.sin(time) * 0.09 * amplitude,
				math.cos(time * 1.85) * 0.065 * amplitude,
				math.sin(time * 1.4) * 0.025 * amplitude
			),
		})
	else
		self.Springs.Bob.SetState({Target = Vector3.zero})
	end

	return self.Springs.Bob.Update(dt)
end

local function _handleSway(self: any, dt: number): Vector3
	self.Springs.Sway.SetState({Target = Vector3.zero})

	local delta = self.Camera.CFrame.LookVector -- placeholder direction sample; real mouse delta belongs to Input_Library, wired by the caller driving input
	if self._lastLook then
		local diff = delta - self._lastLook
		if diff.Magnitude > 0 then
			self.Springs.Sway.ApplyImpulse(Vector3.new(-diff.Y * 4, -diff.X * 4, 0))
		end
	end
	self._lastLook = delta

	return self.Springs.Sway.Update(dt)
end

local function _handleBreath(self: any, dt: number): Vector3
	local isIdle = self.Class ~= nil and self.Humanoid.MoveDirection.Magnitude < 0.05
	if isIdle then
		local time = os.clock() * 1.2
		self.Springs.Breath.SetState({
			Target = Vector3.new(math.sin(time) * 0.023, math.cos(time * 0.7) * 0.012, 0),
		})
	else
		self.Springs.Breath.SetState({Target = Vector3.zero})
	end

	return self.Springs.Breath.Update(dt)
end

local function _handleRecoil(self: any, dt: number): Vector3
	return self.Springs.Recoil.Update(dt)
end

-- Per-category viewmodel pose composition — only FireArm has a meaningful
-- hip/aim blend today; Melee/Throw fall back to the plain hip offset until
-- their classes grow their own pose concerns.
local CategoryCalculations: {[string]: (self: any, dt: number, bob: Vector3, breath: Vector3, sway: Vector3, recoil: Vector3) -> CFrame} = {
	FireArm = function(self, dt, bob, breath, sway, recoil)
		local cameraCF = self.Camera.CFrame
		local positionOffset = CFrame.new(bob + breath)
		local angleOffset = CFrame.fromEulerAnglesXYZ(sway.X + recoil.X, sway.Y + recoil.Y, sway.Z + recoil.Z)
		local hipOffset = self.Config.ViewModelSettings.HipOffset or CFrame.identity

		local aimPart = self.WeaponModel and self.WeaponModel:FindFirstChild("Aim")
		local aimOffset = aimPart and self.ViewModel:GetPivot():ToObjectSpace(aimPart.CFrame):Inverse() or CFrame.identity
		local aimAlpha = (self.Class and self.Class.data.State.AimFov) and 1 or 0
		local blended = CF.Blend(hipOffset, aimOffset, aimAlpha)

		return CF.Compose({cameraCF, blended, positionOffset, angleOffset})
	end,
	Melee = function(self, dt, bob, breath, sway, recoil)
		local cameraCF = self.Camera.CFrame
		local hipOffset = self.Config.ViewModelSettings.HipOffset or CFrame.identity
		return cameraCF * hipOffset * CFrame.new(bob + breath) * CFrame.fromEulerAnglesXYZ(sway.X, sway.Y, sway.Z)
	end,
	Throw = function(self, dt, bob, breath, sway, recoil)
		local cameraCF = self.Camera.CFrame
		local hipOffset = self.Config.ViewModelSettings.HipOffset or CFrame.identity
		return cameraCF * hipOffset * CFrame.new(bob + breath) * CFrame.fromEulerAnglesXYZ(sway.X, sway.Y, sway.Z)
	end,
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	TOOL-DRIVEN EQUIP — equipping a Tool whose Name matches a config
--	under Data/Configs equips that weapon; unequipping the Tool (or it
--	leaving the character for any reason) unequips it. Tools with no
--	matching config are ignored with a warning so ordinary tools still
--	work alongside Armory OS ones.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Finds and requires the config ModuleScript named <weaponId> anywhere
-- under Data/Configs (the category subfolders are organizational only).
-- Returns nil — never errors — when there's no matching, valid config.
local function _findWeaponConfig(weaponId: string): any?
	local root = script.Parent.Parent.Parent
	local data = root:FindFirstChild("Data")
	local configsFolder = data and data:FindFirstChild("Configs")
	if not configsFolder then
		return nil
	end

	local moduleScript = configsFolder:FindFirstChild(weaponId, true)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end

	local ok, config = pcall(require, moduleScript)
	if not ok then
		warn(("[Client Core] Config '%s' failed to load: %s"):format(weaponId, tostring(config)))
		return nil
	end
	if type(config) ~= "table" or config.Name ~= weaponId then
		warn(("[Client Core] Config module '%s' is not a BaseConfig whose Name matches its module name"):format(weaponId))
		return nil
	end

	return config
end

-- (Re)binds the Tool watcher onto a character — called at construction
-- and again on every respawn. Reacts to Tools entering/leaving the
-- character, which is how Roblox represents equip/unequip.
local function _watchCharacterTools(self: any, character: Model)
	if self.LiveSignals.ToolAdded then
		self.LiveSignals.ToolAdded:Disconnect()
	end
	if self.LiveSignals.ToolRemoved then
		self.LiveSignals.ToolRemoved:Disconnect()
	end

	self.LiveSignals.ToolAdded = character.ChildAdded:Connect(function(child)
		if not child:IsA("Tool") then
			return
		end
		if self.Config and self.Config.Name == child.Name then
			return -- already equipped (e.g. tool re-parented mid-animation)
		end
		local config = _findWeaponConfig(child.Name)
		if not config then
			warn(("[Client Core] Tool '%s' has no matching config under Data/Configs — ignored"):format(child.Name))
			return
		end
		self:Equip(child.Name, config)
	end)

	self.LiveSignals.ToolRemoved = character.ChildRemoved:Connect(function(child)
		if not child:IsA("Tool") then
			return
		end
		if self.Config and self.Config.Name == child.Name then
			self:UnEquip()
		end
	end)

	-- A Tool can already be in hand when watching starts (respawning with
	-- a tool equipped) — deferred so construction finishes first.
	local existing = character:FindFirstChildOfClass("Tool")
	if existing then
		local toolName = existing.Name
		task.defer(function()
			if self.Config and self.Config.Name == toolName then
				return
			end
			local config = _findWeaponConfig(toolName)
			if config then
				self:Equip(toolName, config)
			end
		end)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CONSTRUCTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.New()
	local player = Players.LocalPlayer
	Validator.AssertCondition(player ~= nil, "Client Core: New() must be called from a LocalScript")

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

	local self = setmetatable({}, Module)

	self.Player    = player
	self.Character = character
	self.Humanoid  = humanoid
	self.Animator  = animator
	self.Camera    = Workspace.CurrentCamera

	self.Config      = nil :: any
	self.State       = {}
	self.Class       = nil :: any
	self.ViewModel   = nil :: Model?
	self.WeaponModel = nil :: Model?
	self.LiveSignals = {}

	self.Springs = {
		Bob    = Spring(1, 40, 4, 4),
		Sway   = Spring(1, 60, 6, 6),
		Breath = Spring(1, 20, 3, 2),
		Recoil = Spring(1, 80, 8, 8),
	}

	self.Animations = {
		Character = {Movement = {}, Weapon = {}},
		ViewModel = {},
	} :: any

	self._enabled            = true
	self._triggerHeld        = false
	self._firstPersonEnabled = true
	self._thirdPersonEnabled = true
	self._viewModelHidden    = false
	self._neckBaseC0         = nil :: CFrame?
	self._lastSentPitch      = nil :: number?

	self.Streams = _loadStreams()

	_cacheNeckBaseC0(self)
	_applyCameraZoomConstraints(self)

	self.LiveSignals.CharacterAdded = player.CharacterAdded:Connect(function(newCharacter: Model)
		self.Character = newCharacter
		self.Humanoid  = newCharacter:WaitForChild("Humanoid") :: Humanoid
		self.Animator  = self.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", self.Humanoid)
		if self.Class then
			self:UnEquip()
		end
		_cacheNeckBaseC0(self)
		_applyCameraZoomConstraints(self)
		_watchCharacterTools(self, newCharacter)
	end)

	-- Tool-driven equip: a Tool entering the character whose Name matches
	-- a Data/Configs module equips that weapon automatically.
	_watchCharacterTools(self, character)

	-- Drives the equipped weapon's Render(), viewmodel pose, and
	-- first/third-person visibility every frame.
	self.LiveSignals.Render = RunService.RenderStepped:Connect(function(dt: number)
		self:Render(dt)
	end)

	-- Server-authoritative state pushes (ammo after each shot, reload
	-- completion, fire-mode changes — see Server:UpdateWeaponState).
	-- Applied onto the equipped weapon class's State so client logic
	-- (HUD, fire checks) always reflects what the server decided.
	local listener = (RoExpress :: any)("Listener")
	listener:On("WeaponStateUpdate", function(payload: any)
		local this = self :: any
		if type(payload) ~= "table" or not this.Class or not this.Config then
			return
		end
		if payload.WeaponId ~= this.Config.Name then
			return
		end

		local state = payload.State
		if type(state) ~= "table" then
			return
		end

		local weaponState = this.Class.data and this.Class.data.State
		if weaponState then
			for key, value in pairs(state) do
				weaponState[key] = value
			end
		end

		-- Reconcile the class's live ammo/fire-mode with the server's
		-- authoritative numbers (pushed after every shot and reload).
		local weapon = this.Class :: any
		if type(state.Ammo) == "table" then
			weapon._ammoIn      = state.Ammo.In or weapon._ammoIn
			weapon._ammoReserve = state.Ammo.Reserve or weapon._ammoReserve
			if weapon.AmmoChanged then
				weapon.AmmoChanged:Fire({In = weapon._ammoIn, Reserve = weapon._ammoReserve})
			end
		end
		if type(state.FireMode) == "string" then
			weapon._fireMode = state.FireMode
		end
	end)

	return self
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	EQUIP / UNEQUIP
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Equip(self: Type, weaponId: string, config: any)
	local this = self :: any
	Validator.Assert(weaponId, "string", "Client:Equip weaponId")
	Validator.AssertCondition(Validator.IsTable(config), "Client:Equip: config must be a BaseConfig table")

	local WeaponClassModule = WEAPON_CLASSES[config.Category]
	if not WeaponClassModule then
		warn("[Client Core] Equip: unknown Category '" .. tostring(config.Category) .. "'")
		return
	end

	if this.Class then
		this:UnEquip()
	end

	this.Config = config

	if this._firstPersonEnabled then
		local vmSettings = config.ViewModelSettings
		local ok, err = pcall(function()
			local viewModel = _buildViewModelRig(this, vmSettings.Arms)
			local weaponModel = _buildWeaponRig(config)
			_weldWeaponToViewModel(viewModel, weaponModel)
			_applyViewModelCollisions(viewModel)
			_applyClothing(viewModel, this.Character, vmSettings.Clothing)

			viewModel.Parent = this.Camera

			this.ViewModel   = viewModel
			this.WeaponModel = weaponModel
			this.Animations.ViewModel.Equip   = _loadViewModelAnimation(viewModel, weaponId, "Equip")
			this.Animations.ViewModel.Unequip = _loadViewModelAnimation(viewModel, weaponId, "UnEquip")

			local idleTrack = _loadViewModelAnimation(viewModel, weaponId, "Idle")
			if idleTrack then
				idleTrack.Looped = true
			end
			this.Animations.ViewModel.Idle = idleTrack
		end)
		if not ok then
			warn("[Client Core] Equip: failed to build viewmodel — " .. tostring(err))
		end
	end

	local weapon = WeaponClassModule.New(this, weaponId, config.WeaponSettings)
	weapon.data.State.ViewModel = this.ViewModel
	this.Class = weapon

	local route = ("%s/%s/equip"):format(ROUTE_PREFIX[config.Category], weaponId)
	local network = (RoExpress :: any)("Network")
	local _id, response = network:Post(route)

	if response and response.status == 200 then
		local equipTrack = this.Animations.ViewModel.Equip :: AnimationTrack?
		local idleTrack  = this.Animations.ViewModel.Idle :: AnimationTrack?
		if equipTrack then
			equipTrack:Play()
			if idleTrack then
				-- Hand off to the looping idle once the equip finishes.
				equipTrack.Stopped:Once(function()
					if this.Animations.ViewModel.Idle == idleTrack then
						idleTrack:Play()
					end
				end)
			end
		elseif idleTrack then
			idleTrack:Play()
		end
		weapon:Equip()
	else
		warn("[Client Core] Equip: server rejected '" .. weaponId .. "' — " .. tostring(response and response.message))
		this:UnEquip()
	end
end

function Module.UnEquip(self: Type)
	local this = self :: any
	if not this.Class then
		return
	end

	local weaponId = this.Config and this.Config.Name
	local category  = this.Config and this.Config.Category

	this._triggerHeld = false
	local weapon = this.Class :: any
	weapon:UnEquip()
	if weapon.Destroy then
		weapon:Destroy()
	end

	if weaponId and category and ROUTE_PREFIX[category] then
		local route = ("%s/%s/unequip"):format(ROUTE_PREFIX[category], weaponId)
		local network = (RoExpress :: any)("Network")
		network:Post(route)
	end

	-- Let the Unequip animation actually play out before the viewmodel is
	-- torn down — otherwise it'd get cut off mid-holster every time.
	local unequipTrack = this.Animations.ViewModel.Unequip :: AnimationTrack?
	local idleTrack = this.Animations.ViewModel.Idle :: AnimationTrack?
	if idleTrack then
		idleTrack:Stop()
	end
	if unequipTrack then
		local equipTrack = this.Animations.ViewModel.Equip :: AnimationTrack?
		if equipTrack then
			equipTrack:Stop()
		end
		unequipTrack:Play()
		task.wait(unequipTrack.Length)
	end

	this.Animations.ViewModel.Equip   = nil
	this.Animations.ViewModel.Unequip = nil
	this.Animations.ViewModel.Idle    = nil

	this.Class  = nil
	this.Config = nil

	if this.ViewModel then
		this.ViewModel:Destroy()
	end
	this.ViewModel   = nil
	this.WeaponModel = nil
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ACTIONS — whitelisted per category, see CategoryActions above
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.ApplyAction(self: Type, action: string, ...: any)
	local this = self :: any
	if not this.Class or not this.Config then
		return
	end

	local allowed = CategoryActions[this.Config.Category]
	local methodName = allowed and allowed[action]
	if not methodName then
		warn("[Client Core] ApplyAction: '" .. tostring(action) .. "' is not valid for category '" .. tostring(this.Config.Category) .. "'")
		return
	end

	local weapon = this.Class :: any
	local handler = weapon[methodName]
	if type(handler) ~= "function" then
		warn("[Client Core] ApplyAction: Class is missing method '" .. methodName .. "'")
		return
	end

	handler(weapon, ...)

	-- Reloads must also run server-side — the server owns the real ammo
	-- counts (see FireArmRoutes reload) and rejects fire from an empty
	-- server-side magazine, so a purely local reload would soft-lock the gun.
	if this.Config.Category == "FireArm" and methodName:find("Reload") then
		local route = ("%s/%s/reload"):format(ROUTE_PREFIX[this.Config.Category], this.Config.Name)
		local network = (RoExpress :: any)("Network")
		network:Post(route)
	end
end

function Module.Primary(self: Type): any
	local this = self :: any
	if not this.Class or not this.Config then
		return nil
	end

	local category = this.Config.Category
	if category == "FireArm" then
		this:ApplyAction("Fire")

		-- Hold-to-fire: while the trigger stays held and the weapon's
		-- current fire mode is Auto, keep pulling Fire() every heartbeat —
		-- the class's own Fire_Rate gate spaces the actual shots.
		local weapon = this.Class :: any
		if weapon._fireMode == "Auto" then
			this._triggerHeld = true
			task.spawn(function()
				while this._triggerHeld and this.Class == weapon do
					this:ApplyAction("Fire")
					task.wait()
				end
			end)
		end
	elseif category == "Melee" then
		this:ApplyAction("Attack", "Light")
	elseif category == "Throw" then
		local forward = this.Camera and this.Camera.CFrame.LookVector or Vector3.zAxis
		this:ApplyAction("Throw", forward, 1)
	end

	return this.Class
end

function Module.Secondary(self: Type): any
	local this = self :: any
	if not this.Class or not this.Config then
		return nil
	end

	local category = this.Config.Category
	if category == "FireArm" then
		this:ApplyAction("SetAim", true)
	elseif category == "Melee" then
		this:ApplyAction("Block", true)
	elseif category == "Throw" then
		this:ApplyAction("PullPin")
	end

	return this.Class
end

function Module.Release(self: Type, releaseWhat: string)
	local this = self :: any
	if not this.Class or not this.Config then
		return
	end

	local category = this.Config.Category
	if releaseWhat == "Primary" or releaseWhat == "All" then
		this._triggerHeld = false
	end
	if releaseWhat == "Secondary" or releaseWhat == "All" then
		if category == "FireArm" then
			this:ApplyAction("SetAim", false)
		elseif category == "Melee" then
			this:ApplyAction("Block", false)
		end
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	VISIBILITY
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Hide(self: Type)
	local this = self :: any
	this._viewModelHidden = true
end

function Module.Show(self: Type)
	local this = self :: any
	this._viewModelHidden = false
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	DROP / PICKUP
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Drop(self: Type)
	local this = self :: any
	if not this.Class or not this.Config then
		return
	end

	local route = ("%s/%s/drop"):format(ROUTE_PREFIX[this.Config.Category], this.Config.Name)
	local network = (RoExpress :: any)("Network")
	local _id, response = network:Get(route)

	if response and response.status == 200 then
		this:UnEquip()
	end
end

function Module.Pickup(self: Type, weaponId: string)
	-- TODO: server hands back the weapon's baked Config on a successful
	-- pickup (GET firearm|melee|throw/:WeaponId/config, see Data/Routes) —
	-- wire that response straight into Equip(weaponId, config) once the
	-- pickup route actually returns a Config payload.
	local network = (RoExpress :: any)("Network")
	network:Get("pickup/" .. weaponId)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ENABLE / DISABLE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Enable(self: Type)
	local this = self :: any
	this._enabled = true
	this:Show()
end

function Module.Disable(self: Type)
	local this = self :: any
	this._enabled = false
	this:Hide()
end

function Module.SetEnabled(self: Type, enabled: boolean)
	if enabled then
		self:Enable()
	else
		self:Disable()
	end
end

function Module.SetFirstPersonEnabled(self: Type, enabled: boolean)
	local this = self :: any
	this._firstPersonEnabled = enabled
	_applyCameraZoomConstraints(this)

	if enabled and this.Config and not this.ViewModel then
		this:Equip(this.Config.Name, this.Config) -- rebuild the viewmodel for the currently-equipped weapon
	end
end

function Module.SetThirdPersonEnabled(self: Type, enabled: boolean)
	local this = self :: any
	this._thirdPersonEnabled = enabled
	_applyCameraZoomConstraints(this)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	APPEARANCE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Applied via SurfaceAppearance.ColorMap on every viewmodel BasePart —
-- matches the rig plugin's own approach (see buildViewModel's shirt-texture
-- pass). Viewmodel arms are custom part/mesh rigs, not humanoid-driven, so
-- a Shirt instance has no Humanoid to attach to.
function Module.SetShirt(self: Type, shirtId: string)
	local this = self :: any
	if this.ViewModel then
		_applyShirtTexture(this.ViewModel, shirtId)
	end

	local shirt = this.Character:FindFirstChildOfClass("Shirt") or Instance.new("Shirt")
	shirt.ShirtTemplate = "rbxassetid://" .. (shirtId:match("(%d+)$") or shirtId)
	shirt.Parent = this.Character
end

function Module.SetPants(self: Type, pantsId: string)
	local this = self :: any
	local pants = this.Character:FindFirstChildOfClass("Pants") or Instance.new("Pants")
	pants.PantsTemplate = "rbxassetid://" .. (pantsId:match("(%d+)$") or pantsId)
	pants.Parent = this.Character
end

function Module.SetAccessory(self: Type, accessoryId: string)
	-- TODO: InsertService-based accessory loading — out of scope for the
	-- weapon view layer.
	warn("[Client Core] SetAccessory('" .. accessoryId .. "'): not yet wired — needs InsertService asset loading")
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RENDER
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Render(self: Type, dt: number)
	local this = self :: any

	if this.Class and this.Class.Render then
		this.Class:Render(dt)
	end

	local inFirstPersonView = _isFirstPersonView(this)
	_applyViewModelVisibility(this, inFirstPersonView)
	_applyThirdPersonVisibility(this, inFirstPersonView)
	_applyOwnHeadLook(this, dt)

	if not this.ViewModel or not this.Config then
		return
	end

	local bob    = _handleBob(this, dt)
	local breath = _handleBreath(this, dt)
	local sway   = _handleSway(this, dt)
	local recoil = _handleRecoil(this, dt)

	local calculate = CategoryCalculations[this.Config.Category]
	local result = calculate and calculate(this, dt, bob, breath, sway, recoil)

	if result and CF.Validate(result) then
		this.ViewModel:PivotTo(result)
	end
end

return Module
