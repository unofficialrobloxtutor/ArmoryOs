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
--► Types        ◄--
type Client     = FireArmType.Client
type Config     = FireArmType.Config
type FireMode   = FireArmType.FireMode
type WeaponState = FireArmType.WeaponState
export type Type = FireArmType.Type
--► Tables       ◄--
local Module = {}

--► Constants    ◄--
local WEAPON_STATES: {WeaponState} = {"Idle", "Equipping", "Equipped", "Aiming", "Firing", "Reloading", "UnEquipping"}
local HEAD_PART_NAMES  = {Head = true}
local LIMB_PART_NAMES  = {["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true,
	LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true}
local DEFAULT_PENETRATION_FALLOFF = 0.25 -- fraction of damage lost per successive penetration when no per-material table matches

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

-- Classifies a hit part into a damage-zone multiplier using Damage_Library.
local function _applyHitZone(baseDamage: number, damageConfig: Config["Damage"], partName: string): number
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

	-- Drives spread/recoil recovery every frame — unbound in Destroy().
	self._renderStepName = "FireArm_Render_" .. weaponId .. "_" .. tostring(self):gsub("table: ", "")
	Render.BindRenderStep(self._renderStepName, nil, function(dt: number)
		self:Render(dt)
	end)

	return self :: Type
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ATTACHMENTS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Attach(self: Type, attachmentName: string)
	Validator.Assert(attachmentName, "string", "FireArm_Class:Attach attachmentName")
	(self :: any).attachments[attachmentName] = {
		Name   = attachmentName,
		Type   = "Unknown", -- TODO: resolve against an attachment registry once one exists
		Config = {},
	}
end

function Module.Detach(self: Type, attachmentName: string)
	(self :: any).attachments[attachmentName] = nil
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ARM / FIRE MODE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.SwitchArm(self: Type, arm: "Left" | "Right")
	(self :: any).data.State.Arm = arm
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
	this._aiming = isAiming

	if isAiming and this.WeaponState:Is("Equipped") then
		this.WeaponState:ChangeState("Aiming")
	elseif not isAiming and this.WeaponState:Is("Aiming") then
		this.WeaponState:ChangeState("Equipped")
	end

	local aim = this.data.Config.Aim
	this.data.State.AimFov = isAiming and aim.Aim_Fov or nil
end

function Module.IronSightAim(self: Type, isAiming: boolean)
	(self :: any).data.State.AimKind = isAiming and "IronSight" or nil
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
			this._scope = ScopeClass.new((this.data.Config :: any).Scope)
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
		GunVisual.PlaySoundOn(viewModel, sound)
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
	local params      = _rayParams()
	local maxHits      = math.max(penCfg.Penetration_Count or 1, 1)

	local viewModel    = self.data.State.ViewModel :: Model?
	local muzzle       = viewModel and _findMuzzle(viewModel)
	local muzzleCFrame = muzzle and (muzzle:IsA("Attachment") and muzzle.WorldCFrame or (muzzle :: BasePart).CFrame)

	for _ = 1, pelletCount do
		local direction = _jitterDirection(forward, spreadRadians)
		local hits = RayCast.CastMultiHit(origin, direction * physicsCfg.Max_Distance, maxHits, params)

		for penetrationIndex, hit in ipairs(hits) do
			local distance = (hit.Position - origin).Magnitude

			local dmg = damageCfg.Base_Damage
			dmg = Damage.LinearFalloff(dmg, distance, penCfg.Damage_Fall_Off_Start, penCfg.Damage_Fall_Off_End, damageCfg.Min_Damage or 0)
			if penetrationIndex > 1 then
				dmg = Damage.PenetrationFalloff(dmg, penetrationIndex - 1, DEFAULT_PENETRATION_FALLOFF)
			end
			if hit.Instance and hit.Instance.Name then
				dmg = _applyHitZone(dmg, damageCfg, hit.Instance.Name)
			end
			if damageCfg.Min_Damage or damageCfg.Max_Damage then
				dmg = Damage.ClampDamage(dmg, damageCfg.Min_Damage or 0, damageCfg.Max_Damage or dmg)
			end

			-- TODO: resolve the hit character/humanoid and apply `dmg` through
			-- the server-authoritative firearm/:WeaponId/hit route — this is a
			-- client-side preview for hitmarkers/VFX only, never the source of truth.

			local tracerOrigin = muzzleCFrame and muzzleCFrame.Position or origin

			if dataCfg.Use_Trail_As_Bullet then
				GunVisual.CreateTrailTracer(tracerOrigin, hit.Position)
			elseif dataCfg.Use_Ray_As_Bullet then
				GunVisual.CreateBeamTracer(tracerOrigin, hit.Position)
			end

			local impactTemplate = self.data.State.ImpactTemplate :: BasePart?
			if impactTemplate then
				GunVisual.HandleBulletImpact(hit, impactTemplate, self.data.State.BulletHoleDecalId)
			end

			if muzzle then
				GunVisual.CreateMuzzleFlash(muzzle)
			end
		end
	end

	if viewModel and config.Sound and config.Sound.Fire then
		GunVisual.PlaySoundOn(viewModel, config.Sound.Fire)
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
	local streams = self.Client.Streams :: {[string]: any}
	if streams and streams.FireArmStream then
		streams.FireArmStream.Fire(self.data.WeaponId, origin, forward)
	end

	self.Fired:Fire({WeaponId = self.data.WeaponId, Ammo = self._ammoIn, Mode = self._fireMode})
end

function Module.Fire(self: Type)
	local this = self :: any

	if not (this.WeaponState:Is("Equipped") or this.WeaponState:Is("Aiming")) then
		return
	end

	local fireCfg  = this.data.Config.Fire :: Config["Fire"]
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
	local reload = this.data.Config.Reload :: Config["Reload"]
	_startReload(this, reload.Tactical_Reload_Time or reload.Reload_Time, false)
end

function Module.EmptyReload(self: Type)
	local this = self :: any
	local reload = this.data.Config.Reload :: Config["Reload"]
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
	local spreadCfg = this.data.Config.Spread :: Config["Spread"]
	local recoilCfg = this.data.Config.Recoil :: Config["Recoil"]

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
-- unequipped/destroyed to unbind its render loop and signals.
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
