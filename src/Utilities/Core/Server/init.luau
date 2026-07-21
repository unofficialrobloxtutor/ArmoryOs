--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Server
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Core server entry point — initializes and
--                  drives server-side systems (authority, validation,
--                  simulation) for the Armory OS Advanced Weapon Framework.
--
--                  Owns two things Data/Routes handlers reach for:
--                    1. A weapon-only event bus — other server scripts
--                       (damage, quests, analytics, ...) subscribe with
--                       Server:On(event, handler) and route handlers
--                       fire moments with Server:Fire(event, payload).
--                       The event set is fixed and purposeful (see
--                       Utilities/Types/Server WeaponEvent) — this is
--                       not a general pub/sub bus.
--                    2. State push helpers — UpdateWeaponState /
--                       UpdateAllWeaponsState replicate server-authoritative
--                       weapon state to one player or everyone, over the
--                       same RoExpress App the routes are mounted on.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local PhysicsService = game:GetService("PhysicsService")
local Players        = game:GetService("Players")
--► Requires     ◄--
local RoExpress    = require(script.Parent.Parent.Libraries.RoExpress_Library)
local ServerTypes  = require(script.Parent.Parent.Types.Server)
local AssetsCore   = require(script.Assets)
--► Tables       ◄--
local Module = {}
Module.__index = Module
--► Types        ◄--
export type WeaponEvent     = ServerTypes.WeaponEvent
export type WeaponEventData = ServerTypes.WeaponEventData

-- Server-authoritative snapshot of what a player currently has equipped.
-- Created on a successful equip route, destroyed on unequip/leave. Route
-- handlers and streams read/mutate this — never client-supplied data.
export type WeaponSession = {
	WeaponId   : string,
	Category   : string,
	Config     : any,               -- BaseConfig from Data/Configs
	Ammo       : { In: number, Reserve: number, Max: number }?,
	FireMode   : string?,
	Reloading  : boolean,
	LastFireAt : number,
}

export type Type = typeof(setmetatable({}, Module)) & {
	App        : RoExpress.App,
	Assets     : AssetsCore.Type,
	_bindables : { [string]: BindableEvent },
	_sessions  : { [Player]: WeaponSession },
}

--► Constants    ◄--
-- The only events the bus will fire/listen for — keeps it purposeful
-- (weapon lifecycle only) while still generic in payload shape.
local WEAPON_EVENTS: { [string]: true } = {
	WeaponEquipped           = true,
	WeaponUnequipped         = true,
	WeaponFired              = true,
	WeaponReloaded           = true,
	WeaponHit                = true,
	WeaponDamaged            = true,
	WeaponAttachmentChanged  = true,
	WeaponStateChanged       = true,
}

-- CollisionGroup used by every client-built viewmodel (see Utilities/Core/
-- Client _applyViewModelCollisions). Registered here so the group exists
-- before any client assigns parts to it — groups replicate to clients.
local VIEWMODEL_COLLISION_GROUP = "ViewModel"

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PRIVATE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Registers the ViewModel collision group and makes it collide with
-- nothing (including itself) — viewmodels are purely visual, camera-
-- parented rigs and must never touch characters, hitboxes, or the map.
local function _initCollisionGroups()
	if not PhysicsService:IsCollisionGroupRegistered(VIEWMODEL_COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(VIEWMODEL_COLLISION_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(VIEWMODEL_COLLISION_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(VIEWMODEL_COLLISION_GROUP, VIEWMODEL_COLLISION_GROUP, false)
end

-- Lazily creates (and caches) the BindableEvent backing a weapon event.
local function _bindable(self: Type, event: string): BindableEvent
	local existing = self._bindables[event]
	if existing then
		return existing
	end
	local created = Instance.new("BindableEvent")
	self._bindables[event] = created
	return created
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CONSTRUCTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Boots the server layer. Grabs the shared RoExpress App singleton — the
-- same instance Utilities/Core/Network mounts Data/Routes onto — so route
-- handlers and this module always push through one App regardless of
-- construction order.
function Module.New(): Type
	local self = setmetatable({}, Module) :: Type
	self.App        = (RoExpress :: any)("App") :: RoExpress.App
	self.Assets     = AssetsCore.New()
	self._bindables = {}
	self._sessions  = {}

	-- Boot-time asset audit — warns about every rig/model/animation a
	-- config expects but Assets/ doesn't provide, before anyone equips.
	-- Deferred so boot never blocks on it and a bad config can't stall New().
	task.defer(function()
		self.Assets:Audit()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self._sessions[player] = nil
	end)

	_initCollisionGroups()

	return self
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	EVENT BUS — weapon-only, for other server scripts
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Subscribes to a weapon lifecycle event. Fires for every occurrence.
--  Server:On("WeaponFired", function(payload) ... end)
function Module.On(self: Type, event: WeaponEvent, handler: (payload: WeaponEventData) -> ()): RBXScriptConnection
	assert(WEAPON_EVENTS[event], "Server Core: On() — unknown weapon event '" .. tostring(event) .. "'")
	return _bindable(self, event).Event:Connect(handler)
end

--► Subscribes to a weapon lifecycle event for a single occurrence.
function Module.Once(self: Type, event: WeaponEvent, handler: (payload: WeaponEventData) -> ()): RBXScriptConnection
	assert(WEAPON_EVENTS[event], "Server Core: Once() — unknown weapon event '" .. tostring(event) .. "'")
	return _bindable(self, event).Event:Once(handler)
end

--► Fires a weapon lifecycle event — called by Data/Routes handlers (or
--  any other server-side weapon logic) once a moment has actually
--  resolved server-authoritatively.
--  Server:Fire("WeaponFired", { Player = player, WeaponId = weaponId, Data = { Ammo = 29 } })
function Module.Fire(self: Type, event: WeaponEvent, payload: WeaponEventData)
	assert(WEAPON_EVENTS[event], "Server Core: Fire() — unknown weapon event '" .. tostring(event) .. "'")
	_bindable(self, event):Fire(payload)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	WEAPON SESSIONS — server-authoritative per-player equipped state
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Creates (replacing any existing) the player's weapon session from a
--  server-side baked config — called by the equip route handlers.
function Module.EquipWeapon(self: Type, player: Player, config: any): WeaponSession
	local settings = config.WeaponSettings or {}
	local ammoCfg  = settings.Ammo

	local session: WeaponSession = {
		WeaponId   = config.Name,
		Category   = config.Category,
		Config     = config,
		Ammo       = ammoCfg and {In = ammoCfg.In, Reserve = ammoCfg.Reserve, Max = ammoCfg.Max} or nil,
		FireMode   = settings.Fire and settings.Fire.Default_Fire_Mode or nil,
		Reloading  = false,
		LastFireAt = 0,
	}
	self._sessions[player] = session
	return session
end

--► Clears the player's weapon session — called by the unequip routes.
function Module.UnequipWeapon(self: Type, player: Player)
	self._sessions[player] = nil
end

--► Returns the player's current weapon session, or nil if nothing equipped.
function Module.GetSession(self: Type, player: Player): WeaponSession?
	return self._sessions[player]
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	STATE PUSH — server-authoritative weapon state replication
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Pushes a weapon state update to a single player.
--  Server:UpdateWeaponState(player, weaponId, { Ammo = { In = 29, Reserve = 90 } })
function Module.UpdateWeaponState(self: Type, player: Player, weaponId: string, state: { [string]: any })
	self.App:Push(player, "WeaponStateUpdate", { WeaponId = weaponId, State = state })
end

--► Pushes a weapon state update to every connected player — e.g. a
--  balance change or a global config hotfix that every equipped
--  instance of a weapon needs to react to.
--  Server:UpdateAllWeaponsState(weaponId, { Config = { Damage = 24 } })
function Module.UpdateAllWeaponsState(self: Type, weaponId: string, state: { [string]: any })
	self.App:PushAll("WeaponStateUpdate", { WeaponId = weaponId, State = state })
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	LIFECYCLE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.Destroy(self: Type)
	self.Assets:Destroy()
	for _, bindable in pairs(self._bindables) do
		bindable:Destroy()
	end
	table.clear(self._bindables)
	table.clear(self._sessions)
end

return Module
