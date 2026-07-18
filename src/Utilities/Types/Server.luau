--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Server
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Types type definitions for server-side
--                  state and structures used across Utilities/Core/Server.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- The fixed set of purposeful, weapon-only events other server scripts
-- may fire/listen to through Server:Fire / Server:On. Kept generic in
-- payload shape (WeaponEventData) but narrow in *what* they mean — every
-- entry here is a weapon lifecycle moment, nothing app-generic.
export type WeaponEvent =
	"WeaponEquipped"
	| "WeaponUnequipped"
	| "WeaponFired"
	| "WeaponReloaded"
	| "WeaponHit"
	| "WeaponDamaged"
	| "WeaponAttachmentChanged"
	| "WeaponStateChanged"

-- Generic envelope carried by every weapon event — Kind narrows what the
-- rest of Data means, Player/WeaponId identify who/what it happened to.
export type WeaponEventData = {
	Player   : Player,
	WeaponId : string,
	Data     : { [string]: any }?,
}

export type Type = {
	New: (self: any) -> Type,

	-- Server-side event bus — for other server scripts to react to
	-- weapon lifecycle moments (damage systems, analytics, quests, etc).
	On   : (self: Type, event: WeaponEvent, handler: (payload: WeaponEventData) -> ()) -> RBXScriptConnection,
	Once : (self: Type, event: WeaponEvent, handler: (payload: WeaponEventData) -> ()) -> RBXScriptConnection,
	Fire : (self: Type, event: WeaponEvent, payload: WeaponEventData) -> (),

	-- State push — server-authoritative weapon state replicated to clients.
	UpdateWeaponState    : (self: Type, player: Player, weaponId: string, state: { [string]: any }) -> (),
	UpdateAllWeaponsState: (self: Type, weaponId: string, state: { [string]: any }) -> (),

	Destroy: (self: Type) -> (),
}

return {}
