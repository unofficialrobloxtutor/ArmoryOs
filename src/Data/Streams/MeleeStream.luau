--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       MeleeStream
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Streams — the binary RoExpress.Stream channel for
--                  melee attacks. Attacks are fired and checked frequently
--                  (every swing, every combo step) so — same reasoning as
--                  Data/Streams/FireArmStream — this bypasses the App/Router
--                  request/response round trip entirely.
--
--                  Both Utilities/Core/Server and Utilities/Core/Client
--                  require this module so the channel definition is
--                  identical on both sides before Stream.Init() runs.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Requires     ◄--
local RoExpress   = require(script.Parent.Parent.Parent.Utilities.Libraries.RoExpress_Library)
local ServerTypes = require(script.Parent.Parent.Parent.Utilities.Types.Server)
--► Types        ◄--
type Server = ServerTypes.Type
--► Tables       ◄--
local Module = {}
--► Constants    ◄--
local VALID_ATTACK_KINDS = { Light = true, Heavy = true }

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CHANNEL DEFINITION (shared — must match on server and client)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
Module.Channel = RoExpress.Stream.Channel("melee/attack", RoExpress.Stream.Schema({
	{ "WeaponId", "string" },
	{ "Kind",     "string" },
	{ "Combo",    "u8" },
}), {
	reliable = false,
	maxRate  = 30, -- ceiling; real swing-timing/combo-window validation still happens per-weapon below
})

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SERVER — subscribe, validate, replicate
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Wires the channel to the weapon event bus / state push. Called once from
-- Utilities/Core/Server during bootstrap (server-only):
--   MeleeStream.Register(server)
function Module.Register(server: Server)
	Module.Channel:On(function(data, player)
		if not player then
			return
		end
		if type(data.WeaponId) ~= "string" or #data.WeaponId == 0 then
			return
		end
		if not VALID_ATTACK_KINDS[data.Kind] then
			return
		end

		-- TODO: server-authoritative swing timing validation, hitbox activation
		-- window (HitBox_Class), combo-window expiry beyond the channel's flat
		-- maxRate ceiling.
		server:UpdateWeaponState(player, data.WeaponId, { Attacking = data.Kind, Combo = data.Combo })
		server:Fire("WeaponStateChanged", {
			Player   = player,
			WeaponId = data.WeaponId,
			Data     = { Kind = data.Kind, Combo = data.Combo },
		})

		-- Replicate the swing (animation/VFX trigger) to every other client.
		Module.Channel:SendExcept(player, data)
	end)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CLIENT — send helper
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Sends an attack event to the server over the stream channel (client-only).
--   MeleeStream.Attack(weaponId, "Light", 0)
function Module.Attack(weaponId: string, kind: "Light" | "Heavy", combo: number?)
	Module.Channel:Send({ WeaponId = weaponId, Kind = kind, Combo = combo or 0 })
end

return Module
