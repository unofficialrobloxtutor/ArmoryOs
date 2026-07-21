--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Melee_Class
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Classes object definition for melee-type
--                  weapons — handles melee state, behavior, and
--                  instance construction within the weapon framework.
--                  Client-side: predicts the swing locally (HitBox_Class
--                  cone/capsule sweep, damage preview) and reports it to
--                  the server over Data/Streams/MeleeStream, which is the
--                  source of truth (see MeleeRoutes/MeleeStream server-side
--                  validation + Utilities/Core/Server's weapon event bus).
--
--                  Owns gameplay state only — Equip/UnEquip flip
--                  WeaponState; the physical viewmodel (arms + weapon
--                  model) is built/torn down by Utilities/Core/Client,
--                  which owns Config.ViewModelSettings.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Requires     ◄--
local MeleeType  = require(script.Parent.Parent.Types.Weapons.Melee)
local State      = require(script.Parent.State_Class)
local HitBox     = require(script.Parent.HitBox_Class)
local Connection = require(script.Parent.Parent.Libraries.Connection_Library)
local Damage     = require(script.Parent.Parent.Libraries.Damage_Library)
local Validator  = require(script.Parent.Parent.Libraries.Validator_Library)
local Render     = require(script.Parent.Parent.Libraries.Render_Library)
local GunVisual  = require(script.Parent.Parent.Libraries.Gun_Visual_Library)
--► Types        ◄--
type Client      = MeleeType.Client
type Config      = MeleeType.Config
type AttackKind  = MeleeType.AttackKind
type WeaponState = MeleeType.WeaponState
type DamageConfig = MeleeType.DamageConfig
type SwingConfig  = MeleeType.SwingConfig
type ParryConfig  = MeleeType.ParryConfig
export type Type = MeleeType.Type
--► Tables       ◄--
local Module = {}

--► Constants    ◄--
local WEAPON_STATES: {WeaponState} = {"Idle", "Equipping", "Equipped", "Swinging", "Blocking", "Parrying", "UnEquipping"}
local HEAD_PART_NAMES = {Head = true}
local LIMB_PART_NAMES = {["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true,
	LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PRIVATE HELPERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

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

-- Aims the swing cone from the local character's HumanoidRootPart/camera
-- forward direction — mirrors FireArm_Class's camera-driven origin/forward.
local function _swingOrigin(self: any): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position, camera.CFrame.LookVector
	end
	local character = self.Client.Character :: Model?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position, root.CFrame.LookVector
	end
	return Vector3.zero, Vector3.zAxis
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CONSTRUCTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.New(client: Client, weaponId: string, config: Config): Type
	Validator.Assert(weaponId, "string", "Melee_Class.New weaponId")
	Validator.AssertCondition(Validator.IsTable(config), "Melee_Class.New: config must be a table")

	local self = setmetatable({}, {__index = Module}) :: any

	self.Client      = client
	self.attachments = {}
	self.data        = {
		WeaponId = weaponId,
		Config   = config,
		State    = {}, -- freeform slot: ViewModel, Arm, etc.
	}

	self.WeaponState = State.New(WEAPON_STATES)

	-- Local-only feedback signal — UI/animation/HUD systems hook this instead
	-- of polling; fires in addition to (not instead of) the weapon event bus
	-- on the server (Utilities/Core/Server:Fire).
	self.Swung = Connection.NewSignal() :: Connection.SignalType<{WeaponId: string, Kind: AttackKind, Combo: number, Hits: {Player}}>

	self._hitbox      = HitBox.New("Cone")
	self._comboCount  = 0
	self._lastHitTime = 0
	self._blocking    = false
	self._parryToken  = 0

	-- Decays the combo window once it lapses — unbound in Destroy().
	self._renderStepName = "Melee_Render_" .. weaponId .. "_" .. tostring(self):gsub("table: ", "")
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

	local viewModel = this.data.State.ViewModel :: Instance?
	local sound = this.data.Config.Sound and this.data.Config.Sound.Equip
	if viewModel and sound then
		GunVisual.PlaySoundOn(viewModel, sound)
	end

	this.WeaponState:ChangeState("Equipped")
end

function Module.UnEquip(self: Type)
	local this = self :: any
	if this.WeaponState:Is("Idle") or this.WeaponState:Is("UnEquipping") then
		return
	end

	this.WeaponState:ChangeState("UnEquipping")
	this._hitbox:Cancel()
	this._parryToken += 1 -- invalidate any in-flight parry
	this.WeaponState:ChangeState("Idle")
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ATTACHMENTS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Attach(self: Type, attachmentName: string)
	Validator.Assert(attachmentName, "string", "Melee_Class:Attach attachmentName")
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
--	ATTACK
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Attack(self: Type, kind: AttackKind)
	local this = self :: any

	if not this.WeaponState:Is("Equipped") then
		return
	end

	local swingCfg = this.data.Config.Swing :: SwingConfig
	local damageCfg = this.data.Config.Damage :: DamageConfig
	local swingTime = kind == "Heavy" and swingCfg.Heavy_Swing_Time or swingCfg.Light_Swing_Time

	this.WeaponState:ChangeState("Swinging")

	task.delay(swingTime, function()
		if not this.WeaponState:Is("Swinging") then
			return -- unequipped/interrupted mid-swing
		end

		local origin, forward = _swingOrigin(this)
		local thrustBonus = (kind == "Heavy" and this.data.Config.Type == "Spear") and (this.data.Config.Behavior.Thrust_Range_Bonus or 0) or 0
		local range = swingCfg.Range + thrustBonus

		this._hitbox:SetCone(origin, forward, range, swingCfg.Angle_Degrees)
		local hitPlayers = this._hitbox:Fire()

		local baseDamage = damageCfg.Base_Damage
		if kind == "Heavy" and damageCfg.Heavy_Multiplier then
			baseDamage *= damageCfg.Heavy_Multiplier
		end

		for _, player in hitPlayers do
			local character = player.Character
			local limbName = character and "Torso" or nil -- HitBox_Class's OnHit carries the real limb; Fire() only returns players
			local dmg = baseDamage
			if limbName then
				dmg = _applyHitZone(dmg, damageCfg, limbName)
			end
			if damageCfg.Min_Damage or damageCfg.Max_Damage then
				dmg = Damage.ClampDamage(dmg, damageCfg.Min_Damage or 0, damageCfg.Max_Damage or dmg)
			end
			-- TODO: resolve the hit humanoid and apply `dmg` through the
			-- server-authoritative melee/:WeaponId/hit route — this is a
			-- client-side preview for hitmarkers/VFX only, never the source of truth.
		end

		this._comboCount = (#hitPlayers > 0) and (this._comboCount + 1) % (swingCfg.Max_Combo or math.huge) or 0
		this._lastHitTime = os.clock()

		local streams = this.Client.Streams :: {[string]: any}
		if streams and streams.MeleeStream then
			streams.MeleeStream.Attack(this.data.WeaponId, kind, this._comboCount)
		end

		this.Swung:Fire({WeaponId = this.data.WeaponId, Kind = kind, Combo = this._comboCount, Hits = hitPlayers})

		if this.WeaponState:Is("Swinging") then
			this.WeaponState:ChangeState("Equipped")
		end
	end)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	BLOCK / PARRY
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Block(self: Type, isBlocking: boolean)
	local this = self :: any
	if not this.data.Config.Block then
		return
	end

	this._blocking = isBlocking
	if isBlocking and this.WeaponState:Is("Equipped") then
		this.WeaponState:ChangeState("Blocking")
	elseif not isBlocking and this.WeaponState:Is("Blocking") then
		this.WeaponState:ChangeState("Equipped")
	end

	-- TODO: report to the server-authoritative melee/:WeaponId/block route
	-- (Data/Routes/MeleeRoutes) once Utilities/Core/Client exposes a
	-- request-style App caller alongside its Stream loading.
end

function Module.Parry(self: Type)
	local this = self :: any
	local parryCfg = this.data.Config.Parry :: ParryConfig
	if not parryCfg or not this.WeaponState:Is("Equipped") then
		return
	end

	this._parryToken += 1
	local token = this._parryToken

	this.WeaponState:ChangeState("Parrying")
	task.delay(parryCfg.Parry_Window, function()
		if this._parryToken ~= token then
			return -- superseded by a newer Parry/unequip
		end
		if this.WeaponState:Is("Parrying") then
			this.WeaponState:ChangeState("Equipped")
		end
	end)

	-- TODO: report to the server-authoritative melee/:WeaponId/parry route.
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RENDER — combo-window decay, called every frame
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Render(self: Type, deltaTime: number)
	local this = self :: any
	local swingCfg = this.data.Config.Swing :: SwingConfig
	local comboWindow = swingCfg.Combo_Window

	if comboWindow and this._comboCount > 0 and (os.clock() - this._lastHitTime) > comboWindow then
		this._comboCount = 0
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	LIFECYCLE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Not part of MeleeClassType — call explicitly when the weapon is
-- destroyed (after UnEquip) to unbind its render loop, signals, and hitbox.
function Module.Destroy(self: Type)
	local this = self :: any
	Render.Unbind(this._renderStepName)
	this._hitbox:Destroy()
	this.Swung:Destroy()
	this._parryToken += 1 -- invalidate any in-flight parry
end

return Module
