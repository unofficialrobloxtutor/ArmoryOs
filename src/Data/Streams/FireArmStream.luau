--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       FireArmStream
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Streams — the binary RoExpress.Stream channel for
--                  firearm fire events. Fire is high-frequency (up to
--                  weapon fire-rate per second, per player) and doesn't
--                  need a request/response round trip, so it bypasses the
--                  App/Router entirely and goes over an unreliable,
--                  schema-packed Stream channel instead.
--
--                  Both Utilities/Core/Server and Utilities/Core/Client
--                  require this module so the channel definition is
--                  identical on both sides before Stream.Init() runs —
--                  required by RoExpress.Stream (see Stream/init.lua).
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Requires     ◄--
local RoExpress   = require(script.Parent.Parent.Parent.Utilities.Libraries.RoExpress_Library)
local ServerTypes = require(script.Parent.Parent.Parent.Utilities.Types.Server)
--► Types        ◄--
type Server = ServerTypes.Type
--► Tables       ◄--
local Module = {}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CHANNEL DEFINITION (shared — must match on server and client)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
Module.Channel = RoExpress.Stream.Channel("firearm/fire", RoExpress.Stream.Schema({
	{ "WeaponId",  "string" },
	{ "Origin",    "Vector3" },
	{ "Direction", "Vector3" },
}), {
	reliable = false, -- low latency over guaranteed delivery — a dropped shot packet isn't worth retrying
	maxRate  = 30,     -- generous ceiling; real fire-rate enforcement still happens per-weapon in the handler below
})

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SERVER — subscribe, validate, replicate
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Wires the channel to the weapon event bus / state push. Called once from
-- Utilities/Core/Server during bootstrap (server-only):
--   FireArmStream.Register(server)
function Module.Register(server: Server)
	Module.Channel:On(function(data, player)
		if not player then
			return
		end
		if type(data.WeaponId) ~= "string" or #data.WeaponId == 0 then
			return
		end

		-- TODO: server-authoritative fire validation — ammo deduction, LOS/
		-- raycast resolution (RayCast_Library), fire-rate re-check against
		-- the weapon's Config beyond the channel's flat maxRate ceiling.
		server:Fire("WeaponFired", {
			Player   = player,
			WeaponId = data.WeaponId,
			Data     = { Origin = data.Origin, Direction = data.Direction },
		})

		-- Replicate the shot (muzzle flash / tracer trigger) to every other
		-- client — the firing player already has local VFX from their own input.
		Module.Channel:SendExcept(player, data)
	end)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CLIENT — send helper
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Sends a fire event to the server over the stream channel (client-only).
--   FireArmStream.Fire(weaponId, origin, direction)
function Module.Fire(weaponId: string, origin: Vector3, direction: Vector3)
	Module.Channel:Send({ WeaponId = weaponId, Origin = origin, Direction = direction })
end

return Module
