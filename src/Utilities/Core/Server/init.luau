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
--► Requires     ◄--
local RoExpress    = require(script.Parent.Parent.Libraries.RoExpress_Library)
local ServerTypes  = require(script.Parent.Parent.Types.Server)
--► Tables       ◄--
local Module = {}
Module.__index = Module
--► Types        ◄--
export type WeaponEvent     = ServerTypes.WeaponEvent
export type WeaponEventData = ServerTypes.WeaponEventData

export type Type = typeof(setmetatable({}, Module)) & {
	App        : RoExpress.App,
	_bindables : { [string]: BindableEvent },
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

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PRIVATE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

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
	self._bindables = {}
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
	for _, bindable in pairs(self._bindables) do
		bindable:Destroy()
	end
	table.clear(self._bindables)
end

return Module
