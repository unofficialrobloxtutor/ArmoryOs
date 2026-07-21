--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Throw_Class
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Classes object definition for throwable-type
--                  weapons — handles throwable state, behavior, and
--                  instance construction within the weapon framework.
--                  Client-side: predicts the release locally (RayCast_Library
--                  trajectory/impact preview) and the blast (HitBox_Class
--                  sphere query + RayCast_Library line-of-sight occlusion),
--                  then reports the release to the server over
--                  Data/Streams/ThrowStream, which is the source of truth
--                  (see ThrowRoutes/ThrowStream server-side validation +
--                  Utilities/Core/Server's weapon event bus).
--
--                  Owns gameplay state only — Equip/UnEquip flip
--                  WeaponState; the physical viewmodel (arms + weapon
--                  model) is built/torn down by Utilities/Core/Client,
--                  which owns Config.ViewModelSettings.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Requires     ◄--
local ThrowType  = require(script.Parent.Parent.Types.Weapons.Throw)
local State      = require(script.Parent.State_Class)
local HitBox     = require(script.Parent.HitBox_Class)
local Connection = require(script.Parent.Parent.Libraries.Connection_Library)
local RayCast    = require(script.Parent.Parent.Libraries.RayCast_Library)
local Damage     = require(script.Parent.Parent.Libraries.Damage_Library)
local Validator  = require(script.Parent.Parent.Libraries.Validator_Library)
local GunVisual  = require(script.Parent.Parent.Libraries.Gun_Visual_Library)
--► Types        ◄--
type Client      = ThrowType.Client
type Config      = ThrowType.Config
type WeaponState = ThrowType.WeaponState
type PhysicsConfig = ThrowType.PhysicsConfig
type DamageConfig  = ThrowType.DamageConfig
type FuseConfig    = ThrowType.FuseConfig
export type Type = ThrowType.Type
--► Tables       ◄--
local Module = {}

--► Constants    ◄--
local WEAPON_STATES: {WeaponState} = {"Idle", "Equipping", "Equipped", "Cooking", "Thrown", "UnEquipping"}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PRIVATE HELPERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Release point for both the throw preview and a Cooking throwable's
-- auto-detonate — camera position if available, else the character root.
local function _originPosition(self: any): Vector3
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position
	end
	local character = self.Client.Character :: Model?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position or Vector3.zero
end

local function _rayParams(self: any): RaycastParams
	local character = self.Client.Character :: Model?
	if character then
		return RayCast.ParamsExcludeCharacter(character)
	end
	return RayCast.Params()
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CONSTRUCTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.New(client: Client, weaponId: string, config: Config): Type
	Validator.Assert(weaponId, "string", "Throw_Class.New weaponId")
	Validator.AssertCondition(Validator.IsTable(config), "Throw_Class.New: config must be a table")

	local self = setmetatable({}, {__index = Module}) :: any

	self.Client = client
	self.data   = {
		WeaponId = weaponId,
		Config   = config,
		State    = {}, -- freeform slot: ViewModel, etc.
	}

	self.WeaponState = State.New(WEAPON_STATES)

	-- Local-only feedback signal — UI/animation/HUD systems hook this instead
	-- of polling; fires in addition to (not instead of) the weapon event bus
	-- on the server (Utilities/Core/Server:Fire).
	self.Detonated = Connection.NewSignal() :: Connection.SignalType<{WeaponId: string, Position: Vector3, Hits: {Player}}>

	self._hitbox    = HitBox.New("Sphere")
	self._fuseToken = 0

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
	this._fuseToken += 1 -- invalidate any in-flight fuse (e.g. unequipped mid-cook)
	this.WeaponState:ChangeState("Idle")
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	FUSE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.PullPin(self: Type)
	local this = self :: any
	local fuseCfg = this.data.Config.Fuse :: FuseConfig
	if not fuseCfg or not this.WeaponState:Is("Equipped") then
		return
	end

	this._fuseToken += 1
	local token = this._fuseToken

	this.WeaponState:ChangeState("Cooking")

	-- TODO: report to the server-authoritative throw/:WeaponId/pullpin route
	-- (Data/Routes/ThrowRoutes) once Utilities/Core/Client exposes a
	-- request-style App caller alongside its Stream loading.

	if fuseCfg.Fuse_Time then
		task.delay(fuseCfg.Fuse_Time, function()
			if this._fuseToken ~= token then
				return -- superseded by a newer PullPin/Throw/unequip
			end
			if this.WeaponState:Is("Cooking") then
				this:Detonate(_originPosition(this))
			end
		end)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	THROW
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Throw(self: Type, direction: Vector3, heldTime: number?)
	local this = self :: any

	if not (this.WeaponState:Is("Equipped") or this.WeaponState:Is("Cooking")) then
		return
	end
	if direction.Magnitude <= 0 then
		return
	end

	local physicsCfg = this.data.Config.Physics :: PhysicsConfig
	local fuseCfg    = this.data.Config.Fuse :: FuseConfig

	local charge = math.clamp(heldTime or 1, 0, 1)
	local speed  = math.max(physicsCfg.Throw_Velocity * charge, physicsCfg.Min_Velocity or 0)

	local origin   = _originPosition(this)
	local forward  = direction.Unit
	local velocity = forward * speed

	-- Local impact preview — straight-line approximation of the throw's
	-- first-obstruction point (not a full parabolic arc); server resolves
	-- the authoritative trajectory from Origin/Velocity over ThrowStream.
	local previewDistance = physicsCfg.Max_Distance or (speed * 2)
	local hit = RayCast.CastDistance(origin, forward, previewDistance, _rayParams(this))

	this.WeaponState:ChangeState("Thrown")
	this._fuseToken += 1 -- cancel any pending fuse auto-detonate; the throw supersedes it

	local streams = this.Client.Streams :: {[string]: any}
	if streams and streams.ThrowStream then
		streams.ThrowStream.Throw(this.data.WeaponId, origin, velocity, heldTime or 0)
	end

	if fuseCfg and fuseCfg.Detonate_On_Impact and hit then
		local distance   = (hit.Position - origin).Magnitude
		local timeToHit  = speed > 0 and (distance / speed) or 0
		task.delay(timeToHit, function()
			this:Detonate(hit.Position)
		end)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	DETONATE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Detonate(self: Type, position: Vector3)
	local this = self :: any
	local damageCfg = this.data.Config.Damage :: DamageConfig

	this._hitbox:SetSphere(position, damageCfg.Explosion_Radius)
	local candidates = this._hitbox:Fire()

	local params = _rayParams(this)
	local hitPlayers: {Player} = {}

	for _, player in candidates do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		if damageCfg.Requires_Line_Of_Sight and not RayCast.HasLineOfSight(position, root.Position, params) then
			continue -- blast is blocked by geometry between the detonation point and this target
		end

		local distance = (root.Position - position).Magnitude
		local dmg = damageCfg.Explosion_Damage
		if damageCfg.Explosion_Falloff then
			dmg = Damage.ExplosionFalloff(dmg, distance, damageCfg.Explosion_Radius)
		end
		if damageCfg.Min_Damage then
			dmg = math.max(dmg, damageCfg.Min_Damage)
		end

		-- TODO: resolve the hit humanoid and apply `dmg` through the
		-- server-authoritative throw/:WeaponId/detonate route — this is a
		-- client-side preview for hitmarkers/VFX only, never the source of truth.
		table.insert(hitPlayers, player)
	end

	this.Detonated:Fire({WeaponId = this.data.WeaponId, Position = position, Hits = hitPlayers})

	if this.WeaponState:Is("Cooking") or this.WeaponState:Is("Thrown") then
		this.WeaponState:ChangeState("Idle")
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RENDER
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- No continuous per-frame decay to drive (unlike FireArm's spread/recoil or
-- Melee's combo window) — kept only to satisfy ThrowClassType's shape and
-- give callers a consistent per-weapon Render hook to extend later
-- (e.g. a cook-time HUD countdown).
function Module.Render(self: Type, deltaTime: number) end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	LIFECYCLE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Not part of ThrowClassType — call explicitly when the weapon is
-- destroyed (after UnEquip) to unbind its signal and hitbox.
function Module.Destroy(self: Type)
	local this = self :: any
	this._hitbox:Destroy()
	this.Detonated:Destroy()
	this._fuseToken += 1
end

return Module
