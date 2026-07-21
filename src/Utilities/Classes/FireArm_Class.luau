--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       FireArm_Class
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Classes object definition for firearm-type
--                  weapons — handles firearm state, behavior, and
--                  instance construction within the weapon framework.
--                  Client-side: predicts the shot locally (spread,
--                  penetration, damage preview, VFX/SFX) and reports it
--                  to the server over Data/Streams/FireArmStream, which
--                  is the source of truth (see FireArmRoutes/FireArmStream
--                  server-side validation + Utilities/Core/Server's
--                  weapon event bus).
--
--                  Owns gameplay state only — Equip/UnEquip flip
--                  WeaponState and (un)mute local prediction; the physical
--                  viewmodel (arms + weapon model) is built/torn down by
--                  Utilities/Core/Client, which owns Config.ViewModelSettings.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local Players    = game:GetService("Players")
local Workspace   = game:GetService("Workspace")
--► Requires     ◄--
local FireArmType = require(script.Parent.Parent.Types.Weapons.FireArm)
local State        = require(script.Parent.State_Class)
local ScopeClass    = require(script.Parent.Scope_Class)
local Connection    = require(script.Parent.Parent.Libraries.Connection_Library)
local RayCast       = require(script.Parent.Parent.Libraries.RayCast_Library)
local Damage        = require(script.Parent.Parent.Libraries.Damage_Library)
local GunVisual     = require(script.Parent.Parent.Libraries.Gun_Visual_Library)
local Maths         = require(script.Parent.Parent.Libraries.Math_Library)
local CFrameLib     = require(script.Parent.Parent.Libraries.CFrame_Library)
local Validator     = require(script.Parent.Parent.Libraries.Validator_Library)
local Render        = require(script.Parent.Parent.Libraries.Render_Library)
local RoExpress     = require(script.Parent.Parent.Libraries.RoExpress_Library)
local Penetration   = require(script.Parent.Parent.Libraries.Penetration_Library)
local Normal        = require(script.Parent.Parent.Libraries.Normal_Library)
local Projectile    = require(script.Parent.Parent.Libraries.Projectile_Library)
local SoundLib      = require(script.Parent.Parent.Libraries.Sound_Library)
local Explosion     = require(script.Parent.Parent.Libraries.Explosion_Library)
--► Types        ◄--
type Client     = FireArmType.Client
type Config     = FireArmType.Config
type FireMode   = FireArmType.FireMode
type WeaponState = FireArmType.WeaponState
type DamageConfig = FireArmType.DamageConfig
type FireConfig   = FireArmType.FireConfig
type RecoilConfig = FireArmType.RecoilConfig
type SpreadConfig = FireArmType.SpreadConfig
type ReloadConfig = FireArmType.ReloadConfig
export type Type = FireArmType.Type
--► Tables       ◄--
local Module = {}

--► Constants    ◄--
local WEAPON_STATES: {WeaponState} = {"Idle", "Equipping", "Equipped", "Aiming", "Firing", "Reloading", "UnEquipping"}
-- Built-in client sounds for feedback no per-weapon config covers —
-- bullet impacts and ricochet pings (override per weapon via
-- data.State.ImpactSoundId / RicochetSoundId if wanted).
local DEFAULT_IMPACT_SOUND   = "rbxasset://sounds/collide.wav"
local DEFAULT_RICOCHET_SOUND = "rbxasset://sounds/flashbulb.wav"
local HEAD_PART_NAMES  = {Head = true}
local LIMB_PART_NAMES  = {["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true,
	LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PRIVATE HELPERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Builds RaycastParams that exclude the local character, refreshed per-shot
-- since Character can respawn mid-session.
local function _rayParams(): RaycastParams
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if character then
		return RayCast.ParamsExcludeCharacter(character)
	end
	return RayCast.Params()
end

-- Jitters a forward direction inside a cone of `spreadRadians` half-angle.
local function _jitterDirection(forward: Vector3, spreadRadians: number): Vector3
	if spreadRadians <= Maths.Epsilon then
		return forward
	end
	local randX = (math.random() * 2 - 1) * spreadRadians
	local randY = (math.random() * 2 - 1) * spreadRadians
	local jittered = CFrame.new(Vector3.zero, forward) * CFrame.Angles(randX, randY, 0)
	return jittered.LookVector
end

-- Finds a ViewModel's muzzle Attachment/BasePart directly (mirrors
-- CFrame_Library.MuzzleWorldCFrame's lookup, but returns the instance
-- itself — needed for GunVisual.CreateMuzzleFlash/EjectShell attach points).
local function _findMuzzle(viewModel: Model, muzzleName: string?): (Attachment | BasePart)?
	local muzzle = viewModel:FindFirstChild(muzzleName or "Muzzle", true)
	if muzzle and (muzzle:IsA("BasePart") or muzzle:IsA("Attachment")) then
		return muzzle :: Attachment | BasePart
	end
	return nil
end

-- Plays one of this weapon's Config.Sound entries on the viewmodel with a
-- touch of random pitch so repeated events don't sound robotic.
local function _playWeaponSound(self: any, name: string, volume: number?)
	local viewModel = self.data.State.ViewModel :: Instance?
	local sound     = self.data.Config.Sound and self.data.Config.Sound[name]
	if viewModel and sound then
		SoundLib.PlayOn(viewModel, sound, {Volume = volume or 1, PitchRange = 0.05, Group = "SFX"})
	end
end

-- Classifies a hit part into a damage-zone multiplier using Damage_Library.
local function _applyHitZone(baseDamage: number, damageConfig: DamageConfig, partName: string): number
	if HEAD_PART_NAMES[partName] then
		return Damage.HeadshotDamage(baseDamage, true, damageConfig.Headshot_Multiplier)
	end
	if LIMB_PART_NAMES[partName] then
		return Damage.LimbDamage(baseDamage, true, damageConfig.Limb_Multiplier)
	end
	return baseDamage
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CONSTRUCTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.New(client: Client, weaponId: string, config: Config): Type
	Validator.Assert(weaponId, "string", "FireArm_Class.New weaponId")
	Validator.AssertCondition(Validator.IsTable(config), "FireArm_Class.New: config must be a table")

	local self = setmetatable({}, {__index = Module}) :: any

	self.Client      = client
	self.attachments = {}
	self.data        = {
		WeaponId = weaponId,
		Config   = config,
		State    = {}, -- freeform slot: ViewModel, Arm, AimFov, ShellTemplate, ImpactTemplate, etc.
	}

	self.WeaponState = State.New(WEAPON_STATES)

	-- Local-only feedback signals — UI/animation/HUD systems hook these
	-- instead of polling; they fire in addition to (not instead of) the
	-- weapon event bus on the server (Utilities/Core/Server:Fire).
	self.Fired        = Connection.NewSignal() :: Connection.SignalType<{WeaponId: string, Ammo: number, Mode: FireMode}>
	self.AmmoChanged  = Connection.NewSignal() :: Connection.SignalType<{In: number, Reserve: number}>

	self._ammoIn       = config.Ammo.In or config.Ammo.Max or 0
	self._ammoReserve  = config.Ammo.Reserve or 0
	self._fireMode     = config.Fire.Default_Fire_Mode
	self._lastFireTime = 0
	self._spread       = config.Spread.Base_Spread
	self._recoilOffset = CFrame.identity
	self._aiming       = false
	self._reloadToken  = 0

	-- Warm the sound cache so the first shot/reload isn't silent while
	-- assets stream in (rbxasset:// entries are local and cost nothing).
	if config.Sound then
		local ids = {}
		for _, id in pairs(config.Sound :: any) do
			if type(id) == "string" then
				table.insert(ids, id)
			end
		end
		if #ids > 0 then
			SoundLib.Preload(ids)
		end
	end

	-- Drives spread/recoil recovery every frame — unbound in Destroy().
	self._renderStepName = "FireArm_Render_" .. weaponId .. "_" .. tostring(self):gsub("table: ", "")
	Render.BindRenderStep(self._renderStepName, nil, function(dt: number)
		self:Render(dt)
	end)

	return self :: Type
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	EQUIP / UNEQUIP
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Gameplay-state transition only — the physical viewmodel (arms + weapon
-- model) is already built by Utilities/Core/Client before this is called
-- (Client owns Config.ViewModelSettings, this class never sees it).
function Module.Equip(self: Type)
	local this = self :: any
	if not this.WeaponState:Is("Idle") then
		return
	end

	this.WeaponState:ChangeState("Equipping")

	_playWeaponSound(this, "Equip", 0.8)

	this.WeaponState:ChangeState("Equipped")
end

function Module.UnEquip(self: Type)
	local this = self :: any
	if this.WeaponState:Is("Idle") or this.WeaponState:Is("UnEquipping") then
		return
	end

	this.WeaponState:ChangeState("UnEquipping")
	this._reloadToken += 1 -- invalidate any in-flight reload
	this.WeaponState:ChangeState("Idle")
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ATTACHMENTS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Attach(self: Type, attachmentName: string)
	Validator.Assert(attachmentName, "string", "FireArm_Class:Attach attachmentName")
	local this = self :: any
	this.attachments[attachmentName] = {
		Name   = attachmentName,
		Type   = "Unknown", -- TODO: resolve against an attachment registry once one exists
		Config = {},
	}
end

function Module.Detach(self: Type, attachmentName: string)
	local this = self :: any
	this.attachments[attachmentName] = nil
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ARM / FIRE MODE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.SwitchArm(self: Type, arm: "Left" | "Right")
	local this = self :: any
	this.data.State.Arm = arm
end

function Module.SwitchFireMode(self: Type, fireMode: FireMode)
	local this = self :: any
	if not Validator.IsOneOf(fireMode, this.data.Config.Fire.Fire_Modes) then
		warn("FireArm_Class: '" .. tostring(fireMode) .. "' is not in this weapon's Fire_Modes")
		return
	end
	this._fireMode = fireMode
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	AIMING
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.SetAim(self: Type, isAiming: boolean)
	local this = self :: any
	local wasAiming = this._aiming
	this._aiming = isAiming

	if isAiming and this.WeaponState:Is("Equipped") then
		this.WeaponState:ChangeState("Aiming")
	elseif not isAiming and this.WeaponState:Is("Aiming") then
		this.WeaponState:ChangeState("Equipped")
	end

	if isAiming ~= wasAiming then
		_playWeaponSound(this, isAiming and "Aim_In" or "Aim_Out", 0.6)
	end

	local aim = this.data.Config.Aim
	this.data.State.AimFov = isAiming and aim.Aim_Fov or nil
end

function Module.IronSightAim(self: Type, isAiming: boolean)
	local this = self :: any
	this.data.State.AimKind = isAiming and "IronSight" or nil
	self:SetAim(isAiming)
end

-- Scoped sniper aim — lazily builds a Scope_Class overlay from this
-- weapon's Config.Scope (Sniper-only), reusing the same instance across
-- ADS toggles rather than rebuilding the ScreenGui every time.
function Module.ScopeAim(self: Type, isAiming: boolean)
	local this = self :: any
	this.data.State.AimKind = isAiming and "Scope" or nil

	if this.data.Config.Type == "Sniper" then
		if not this._scope then
			this._scope = ScopeClass.new(this.data.Config.Scope)
		end
		if isAiming then
			this._scope:Show()
		else
			this._scope:Hide()
		end
	end

	self:SetAim(isAiming)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	FIRE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Plays the dry-fire/empty click and reports it locally — no server call,
-- an empty trigger pull never happened as far as the network is concerned.
local function _playEmpty(self: any)
	local viewModel = self.data.State.ViewModel :: Instance?
	local sound     = self.data.Config.Sound and self.data.Config.Sound.Empty
	if viewModel and sound then
		SoundLib.PlayOn(viewModel, sound, {Volume = 0.8, PitchRange = 0.05})
	end
end

-- Fires exactly one round — spread jitter, penetrating raycast, damage calc,
-- VFX/SFX, ammo decrement, spread/recoil buildup, and the network report.
-- Shared by single/auto shots and each sub-shot of a burst.
local function _dischargeOnce(self: any)
	local config     = self.data.Config :: Config
	local fireCfg    = config.Fire
	local spreadCfg  = config.Spread
	local damageCfg  = config.Damage
	local penCfg     = config.Penetration
	local physicsCfg = config.Physics
	local dataCfg    = config.Data

	local camera  = Workspace.CurrentCamera
	if not camera then
		return
	end
	local origin  = camera.CFrame.Position
	local forward = camera.CFrame.LookVector

	-- Effective spread: base spread scaled by movement/stance multipliers the
	-- caller may have written into data.State (Input_Library / Render owns those).
	local effectiveSpread = self._spread
	if self._aiming and spreadCfg.Aiming_Multiplier then
		effectiveSpread *= spreadCfg.Aiming_Multiplier
	end
	if self.data.State.Moving and spreadCfg.Moving_Multiplier then
		effectiveSpread *= spreadCfg.Moving_Multiplier
	end
	if self.data.State.Jumping and spreadCfg.Jumping_Multiplier then
		effectiveSpread *= spreadCfg.Jumping_Multiplier
	end
	if self.data.State.Crouching and spreadCfg.Crouching_Multiplier then
		effectiveSpread *= spreadCfg.Crouching_Multiplier
	end
	local spreadRadians = math.rad(effectiveSpread)

	local pelletCount = (config.Type == "Shotgun") and config.Behavior.Pellet_Count or 1

	local viewModel    = self.data.State.ViewModel :: Model?
	local muzzle       = viewModel and _findMuzzle(viewModel)
	local muzzleCFrame: CFrame? = nil
	if muzzle then
		if muzzle:IsA("Attachment") then
			muzzleCFrame = muzzle.WorldCFrame
		else
			muzzleCFrame = muzzle.CFrame
		end
	end

	for _ = 1, pelletCount do
		local aimDirection = _jitterDirection(forward, spreadRadians)

		-- Two-stage cast: the CAMERA ray decides what you're aiming at
		-- (crosshair-accurate), then the bullet actually flies from the
		-- gun's MUZZLE toward that aim point. If the muzzle is behind
		-- cover the muzzle ray hits the cover, not the crosshair target.
		local aimPoint: Vector3
		local aimHit = Workspace:Raycast(origin, aimDirection * physicsCfg.Max_Distance, _rayParams())
		if aimHit then
			aimPoint = aimHit.Position
		else
			aimPoint = origin + aimDirection * physicsCfg.Max_Distance
		end

		local shotOrigin = muzzleCFrame and muzzleCFrame.Position or origin
		local toAim = aimPoint - shotOrigin
		local shotDirection = toAim.Magnitude > 1e-4 and toAim.Unit or aimDirection

		-- Everything a resolved surface triggers — damage preview, the
		-- server hit report, holes/sparks/exit VFX. Shared verbatim by the
		-- hitscan path and the stepped projectile path (Projectile.Launch
		-- feeds it the same PenetrationHit shape on arrival).
		local function processImpact(penHit: Penetration.PenetrationHit)
			local hit = penHit.Result
			local distance = (hit.Position - shotOrigin).Magnitude

			local dmg = damageCfg.Base_Damage
			dmg = Damage.LinearFalloff(dmg, distance, penCfg.Damage_Fall_Off_Start, penCfg.Damage_Fall_Off_End, damageCfg.Min_Damage or 0)
			dmg *= penHit.DamageMultiplier
			if hit.Instance and hit.Instance.Name then
				dmg = _applyHitZone(dmg, damageCfg, hit.Instance.Name)
			end
			if damageCfg.Min_Damage or damageCfg.Max_Damage then
				dmg = Damage.ClampDamage(dmg, damageCfg.Min_Damage or 0, damageCfg.Max_Damage or dmg)
			end

			-- `dmg` above is a client-side preview for hitmarkers/VFX only.
			-- Character hits are reported to the server-authoritative
			-- firearm/:WeaponId/hit route, which recomputes damage from its
			-- own config and applies it — fire-and-forget (callback form)
			-- so the fire loop never yields on network.
			local hitModel = hit.Instance and hit.Instance:FindFirstAncestorOfClass("Model")
			local hitIsCharacter = hitModel ~= nil and hitModel:FindFirstChildOfClass("Humanoid") ~= nil
			if hitIsCharacter then
				local network = (RoExpress :: any)("Network")
				network:Post("firearm/" .. self.data.WeaponId .. "/hit", {
					HitPart  = hit.Instance,
					Position = hit.Position,
					Normal   = hit.Normal,
					Origin   = shotOrigin,
				}, function() end)
			end

			-- Impact VFX — template/decal when configured, procedural
			-- fallbacks otherwise so impacts are always visible. Characters
			-- get no surface holes (flesh, not walls).
			local impactTemplate = self.data.State.ImpactTemplate :: BasePart?
			if impactTemplate then
				GunVisual.HandleBulletImpact(hit, impactTemplate, self.data.State.BulletHoleDecalId)
			elseif not hitIsCharacter then
				if self.data.State.BulletHoleDecalId then
					GunVisual.CreateBulletHole(self.data.State.BulletHoleDecalId, hit.Instance :: BasePart, hit.Position, hit.Normal)
				else
					GunVisual.CreateSimpleBulletHole(hit.Position, hit.Normal)
				end
			end

			if penHit.Ricocheted then
				-- Sparks + a high ping thrown along the bounce direction.
				GunVisual.CreateRicochetSparks(hit.Position, hit.Normal, {
					Direction = Normal.Reflect(shotDirection, hit.Normal),
				})
				SoundLib.PlayAt(self.data.State.RicochetSoundId or DEFAULT_RICOCHET_SOUND, hit.Position,
					{Volume = 0.6, Pitch = 1.4, PitchRange = 0.2, Group = "SFX"})
			elseif penHit.ExitPosition and penHit.ExitNormal then
				-- The round went through — draw the exit hole on the far face.
				GunVisual.CreateSimpleBulletHole(penHit.ExitPosition, penHit.ExitNormal)
			end

			-- Surface thud at the point of impact (characters get their own
			-- hit feedback via the server's damage path, not a wall thud).
			if not hitIsCharacter then
				SoundLib.PlayAt(self.data.State.ImpactSoundId or DEFAULT_IMPACT_SOUND, hit.Position,
					{Volume = 0.4, PitchRange = 0.25, Group = "SFX", RollOffMax = 80})
			end
		end

		if config.Type == "Explosive" or config.Type == "Launcher" then
			-- Explosive / Launcher rounds: always a physical projectile that
			-- detonates rather than penetrates. The client only shows the
			-- boom and reports WHERE it happened — the server's explode
			-- route deals all radial damage (falloff + line-of-sight).
			local behavior    = (config :: any).Behavior or {}
			local isLauncher  = config.Type == "Launcher"
			local blastRadius = (isLauncher and behavior.Blast_Radius or behavior.Explosion_Radius) or 12
			local speed       = (isLauncher and behavior.Projectile_Speed or physicsCfg.Base_Velocity) or 200
			local launchedAt  = os.clock()
			local exploded    = false

			local function detonate(position: Vector3)
				if exploded then
					return
				end
				exploded = true
				Explosion.CreateExplosionVFX(position, blastRadius)
				local network = (RoExpress :: any)("Network")
				network:Post("firearm/" .. self.data.WeaponId .. "/explode", {Position = position}, function() end)
			end

			Projectile.Launch({
				Origin          = shotOrigin,
				Direction       = shotDirection,
				Speed           = speed,
				GravityModifier = physicsCfg.Gravity_Modifier,
				MaxDistance     = physicsCfg.Max_Distance,
				Penetration     = penCfg,
				Params          = _rayParams(),
				BulletTemplate  = self.data.State.BulletTemplate :: BasePart?,
				StopOnFirstHit  = true,
				Steering        = (isLauncher and behavior.Guided) and {
					TurnSpeed   = behavior.Turn_Speed or 2,
					GetAimPoint = function(): Vector3
						-- Track the crosshair: guided rockets steer toward
						-- wherever the camera is pointing right now.
						local cam = Workspace.CurrentCamera
						if cam then
							return cam.CFrame.Position + cam.CFrame.LookVector * 500
						end
						return aimPoint
					end,
				} or nil,
				OnHit = function(penHit: Penetration.PenetrationHit)
					local position = penHit.Result.Position
					if isLauncher or behavior.Detonate_On_Impact then
						detonate(position)
					else
						-- Impact-armed fuse: the round sits where it landed
						-- for whatever remains of Fuse_Time, then blows.
						local fuseLeft = math.max((behavior.Fuse_Time or 3) - (os.clock() - launchedAt), 0)
						task.delay(fuseLeft, function()
							detonate(position)
						end)
					end
				end,
				OnEnd = function(finalPosition: Vector3)
					-- Fused explosives that never touched anything (air burst
					-- / max range) still detonate where the round died.
					if not isLauncher and behavior.Fuse_Time and not exploded then
						local fuseLeft = math.max(behavior.Fuse_Time - (os.clock() - launchedAt), 0)
						task.delay(fuseLeft, function()
							detonate(finalPosition)
						end)
					end
				end,
			})
		elseif dataCfg.Use_Part_As_Bullet then
			-- Stepped physical projectile: a real part flies at Base_Velocity,
			-- dropping under Gravity_Modifier — hits land on arrival with the
			-- exact same penetration/ricochet rules as hitscan.
			Projectile.Launch({
				Origin          = shotOrigin,
				Direction       = shotDirection,
				Speed           = physicsCfg.Base_Velocity or 1000,
				GravityModifier = physicsCfg.Gravity_Modifier,
				MaxDistance     = physicsCfg.Max_Distance,
				Penetration     = penCfg,
				Params          = _rayParams(),
				BulletTemplate  = self.data.State.BulletTemplate :: BasePart?,
				OnHit           = processImpact,
			})
		else
			-- Hitscan: resolve the whole path instantly, then draw tracers
			-- segment-by-segment — muzzle → first hit, then each exit → next
			-- hit, so ricochets and wall-bangs render as a connected path.
			-- Fresh params per pellet — Penetration.Cast mutates the exclusion list.
			local penetrationHits = Penetration.Cast(shotOrigin, shotDirection, penCfg, physicsCfg.Max_Distance, _rayParams())
			local segmentOrigin = shotOrigin
			local segmentDirection = shotDirection

			for _, penHit in ipairs(penetrationHits) do
				local hit = penHit.Result
				processImpact(penHit)

				if dataCfg.Use_Trail_As_Bullet then
					GunVisual.CreateTrailTracer(segmentOrigin, hit.Position)
					-- Show the round crossing the wall itself: a trail from
					-- the entry face to the exit face.
					if penHit.ExitPosition then
						GunVisual.CreateTrailTracer(hit.Position, penHit.ExitPosition)
					end
				elseif dataCfg.Use_Ray_As_Bullet then
					GunVisual.CreateBeamTracer(segmentOrigin, hit.Position)
					-- Same, as a beam.
					if penHit.ExitPosition then
						GunVisual.CreateBeamTracer(hit.Position, penHit.ExitPosition)
					end
				end

				if penHit.Ricocheted then
					segmentDirection = Normal.Reflect(segmentDirection, hit.Normal)
				end
				segmentOrigin = penHit.ExitPosition or hit.Position
			end

			-- Follow-through: when the round's last surface didn't stop it
			-- (penetrated through, or bounced off), draw the final tracer
			-- continuing into open air for the path distance it had left —
			-- otherwise the chain visually dies at the wall.
			if (dataCfg.Use_Ray_As_Bullet or dataCfg.Use_Trail_As_Bullet) and #penetrationHits > 0 then
				local last = penetrationHits[#penetrationHits]
				if last.ExitPosition or last.Ricocheted then
					local traveled = (segmentOrigin - shotOrigin).Magnitude
					local leftover = math.max(physicsCfg.Max_Distance - traveled, 0)
					if leftover > 0.5 then
						local endPoint = segmentOrigin + segmentDirection * leftover
						if dataCfg.Use_Trail_As_Bullet then
							GunVisual.CreateTrailTracer(segmentOrigin, endPoint)
						else
							GunVisual.CreateBeamTracer(segmentOrigin, endPoint)
						end
					end
				end
			end
		end
	end

	if muzzle then
		GunVisual.CreateMuzzleFlash(muzzle)
	end

	if viewModel and config.Sound then
		-- Fire_Suppressed takes over when a Barrel suppressor is attached.
		local suppressed = self.attachments and self.attachments.Suppressor ~= nil
		local fireSound = (suppressed and config.Sound.Fire_Suppressed) or config.Sound.Fire
		if fireSound then
			SoundLib.PlayOn(viewModel, fireSound, {Volume = 1, PitchRange = 0.06, Group = "SFX"})
		end
	end

	local shellTemplate = self.data.State.ShellTemplate :: BasePart?
	if shellTemplate and muzzleCFrame then
		GunVisual.EjectShell(shellTemplate, muzzleCFrame)
	end

	-- Ammo + spread/recoil buildup
	if not dataCfg.Infinite_Ammo then
		self._ammoIn = math.max(self._ammoIn - 1, 0)
		self.AmmoChanged:Fire({In = self._ammoIn, Reserve = self._ammoReserve})
	end
	self._spread = math.min(self._spread + spreadCfg.Increase_Per_Shot, spreadCfg.Max_Spread)

	local recoilKick = CFrameLib.RecoilImpulse({
		Vertical   = config.Recoil.Vertical,
		Horizontal = config.Recoil.Horizontal + (config.Recoil.Horizontal_Variance or 0) * (math.random() * 2 - 1),
		Kick       = config.Recoil.Camera_Kick or 0,
	})
	self._recoilOffset = CFrameLib.Add(self._recoilOffset, recoilKick)

	-- Report the shot to the server — see Data/Streams/FireArmStream.
	-- Origin is the muzzle when one exists, matching what the hit route
	-- verifies against.
	local streams = self.Client.Streams :: {[string]: any}
	if streams and streams.FireArmStream then
		streams.FireArmStream.Fire(self.data.WeaponId, muzzleCFrame and muzzleCFrame.Position or origin, forward)
	end

	self.Fired:Fire({WeaponId = self.data.WeaponId, Ammo = self._ammoIn, Mode = self._fireMode})
end

function Module.Fire(self: Type)
	local this = self :: any

	if not (this.WeaponState:Is("Equipped") or this.WeaponState:Is("Aiming")) then
		return
	end

	local fireCfg  = this.data.Config.Fire :: FireConfig
	local now      = os.clock()
	local interval = 60 / fireCfg.Fire_Rate
	if now - this._lastFireTime < interval then
		return
	end
	this._lastFireTime = now

	local hasAmmo = this.data.Config.Data.Infinite_Ammo or this._ammoIn > 0
	if not hasAmmo then
		_playEmpty(this)
		return
	end

	if this._fireMode == "Burst" and fireCfg.Burst_Count and fireCfg.Burst_Count > 1 then
		local priorState = this.WeaponState:GetState()
		this.WeaponState:ChangeState("Firing")
		task.spawn(function()
			for shot = 1, fireCfg.Burst_Count :: number do
				local stillHasAmmo = this.data.Config.Data.Infinite_Ammo or this._ammoIn > 0
				if not stillHasAmmo then
					_playEmpty(this)
					break
				end
				_dischargeOnce(this)
				if shot < (fireCfg.Burst_Count :: number) then
					task.wait(60 / (fireCfg.Burst_Rate or fireCfg.Fire_Rate))
				end
			end
			if this.WeaponState:Is("Firing") then
				this.WeaponState:ChangeState(priorState == "Aiming" and "Aiming" or "Equipped")
			end
		end)
	else
		_dischargeOnce(this)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RELOAD
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

local function _startReload(self: any, duration: number, chamberOnFinish: boolean)
	if self.WeaponState:Is("Reloading") then
		return
	end

	local reserveNeeded = self.data.Config.Ammo.Max - self._ammoIn
	if self._ammoReserve <= 0 or reserveNeeded <= 0 then
		return
	end

	self._reloadToken += 1
	local token = self._reloadToken

	self.WeaponState:ChangeState("Reloading")
	_playWeaponSound(self, "Reload")

	task.delay(duration, function()
		-- A newer reload (or an equip/unequip that bumped the token) superseded this one.
		if self._reloadToken ~= token then
			return
		end

		local transfer = math.min(reserveNeeded, self._ammoReserve)
		self._ammoIn      += transfer
		self._ammoReserve -= transfer
		if chamberOnFinish and self.data.Config.Reload.Chamber_Round and self._ammoReserve > 0 then
			self._ammoIn = math.min(self._ammoIn + 1, self.data.Config.Ammo.Max)
			self._ammoReserve -= 1
		end

		self.AmmoChanged:Fire({In = self._ammoIn, Reserve = self._ammoReserve})

		if self.WeaponState:Is("Reloading") then
			self.WeaponState:ChangeState(self._aiming and "Aiming" or "Equipped")
		end
	end)
end

function Module.TacticalReload(self: Type)
	local this = self :: any
	local reload = this.data.Config.Reload :: ReloadConfig
	_startReload(this, reload.Tactical_Reload_Time or reload.Reload_Time, false)
end

function Module.EmptyReload(self: Type)
	local this = self :: any
	local reload = this.data.Config.Reload :: ReloadConfig
	_startReload(this, reload.Empty_Reload_Time or reload.Reload_Time, true)
end

function Module.Reload(self: Type)
	local this = self :: any
	if this._ammoIn <= 0 then
		self:EmptyReload()
	else
		self:TacticalReload()
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RENDER — spread/recoil recovery, called every frame
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Render(self: Type, deltaTime: number)
	local this = self :: any
	local spreadCfg = this.data.Config.Spread :: SpreadConfig
	local recoilCfg = this.data.Config.Recoil :: RecoilConfig

	this._spread = Maths.Lerp(this._spread, spreadCfg.Base_Spread, 1 - math.exp(-spreadCfg.Recovery_Speed * deltaTime))
	this._recoilOffset = CFrameLib.DampTo(this._recoilOffset, CFrame.identity, deltaTime, recoilCfg.Recovery_Speed)

	-- Feed the recoil kick into the scope reticle so it visibly jumps on fire.
	if this._scope then
		local euler = CFrameLib.GetEulerAngles(this._recoilOffset)
		this._scope:SetSwayOffset(Vector2.new(math.deg(euler.Y) * 4, math.deg(euler.X) * 4))
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	LIFECYCLE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Not part of FireArmClassType — call explicitly when the weapon is
-- destroyed (after UnEquip) to unbind its render loop and signals.
function Module.Destroy(self: Type)
	local this = self :: any
	Render.Unbind(this._renderStepName)
	this.Fired:Destroy()
	this.AmmoChanged:Destroy()
	this._reloadToken += 1 -- invalidate any in-flight reload
	if this._scope then
		this._scope:Destroy()
		this._scope = nil
	end
end

return Module
