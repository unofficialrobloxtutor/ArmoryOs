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

-- The server asset loader (Utilities/Core/Server/Assets) — canonical
-- shapes live in Utilities/Types/Assets; typed `any` here to keep this
-- file a leaf (no requires, no cycle risk). Narrow at the use site with
-- Utilities/Types/Assets when you need the full method surface.
-- Server-authoritative per-player equipped-weapon snapshot — see
-- Utilities/Core/Server WeaponSession.
export type WeaponSession = {
	WeaponId   : string,
	Category   : string,
	Config     : any,
	Ammo       : { In: number, Reserve: number, Max: number }?,
	FireMode   : string?,
	Reloading  : boolean,
	LastFireAt : number,
}

export type Type = {
	New: (self: any) -> Type,

	-- Asset helpers — build viewmodels, weapon rigs, first-person models,
	-- animation trees, and third-person character animations from Assets/.
	Assets: any,

	-- Server-side event bus — for other server scripts to react to
	-- weapon lifecycle moments (damage systems, analytics, quests, etc).
	On   : (self: Type, event: WeaponEvent, handler: (payload: WeaponEventData) -> ()) -> RBXScriptConnection,
	Once : (self: Type, event: WeaponEvent, handler: (payload: WeaponEventData) -> ()) -> RBXScriptConnection,
	Fire : (self: Type, event: WeaponEvent, payload: WeaponEventData) -> (),

	-- Weapon sessions — server-authoritative equipped state per player.
	EquipWeapon   : (self: Type, player: Player, config: any) -> WeaponSession,
	UnequipWeapon : (self: Type, player: Player) -> (),
	GetSession    : (self: Type, player: Player) -> WeaponSession?,

	-- State push — server-authoritative weapon state replicated to clients.
	UpdateWeaponState    : (self: Type, player: Player, weaponId: string, state: { [string]: any }) -> (),
	UpdateAllWeaponsState: (self: Type, weaponId: string, state: { [string]: any }) -> (),

	Destroy: (self: Type) -> (),
}

return {}
