--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       ThrowStream
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Streams — the binary RoExpress.Stream channel for
--                  throwable-weapon releases. A throw is fired once per
--                  use but still benefits from the same low-overhead path
--                  as Data/Streams/FireArmStream — no request/response
--                  round trip needed before the projectile spawns.
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

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CHANNEL DEFINITION (shared — must match on server and client)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
Module.Channel = RoExpress.Stream.Channel("throw/throw", RoExpress.Stream.Schema.New({
	{ "WeaponId", "string" },
	{ "Origin",   "Vector3" },
	{ "Velocity", "Vector3" },
	{ "HeldTime", "f32" },
}), {
	reliable = false,
	maxRate  = 10, -- throws are naturally low-frequency; ceiling just guards against spam
})

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SERVER — subscribe, validate, replicate
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Wires the channel to the weapon event bus / state push. Called once from
-- Utilities/Core/Server during bootstrap (server-only):
--   ThrowStream.Register(server)
function Module.Register(server: Server)
	Module.Channel:On(function(data, player)
		if not player then
			return
		end
		if type(data.WeaponId) ~= "string" or #data.WeaponId == 0 then
			return
		end

		-- TODO: clamp Velocity against Config.Core.Throw_Velocity, spawn the
		-- projectile, consume inventory (Config.Inventory.Consume_On_Use).
		server:Fire("WeaponFired", {
			Player   = player,
			WeaponId = data.WeaponId,
			Data     = { Origin = data.Origin, Velocity = data.Velocity, HeldTime = data.HeldTime },
		})

		-- Replicate the throw (arm/hand animation, projectile spawn) to every other client.
		Module.Channel:SendExcept(player, data)
	end)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CLIENT — send helper
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Sends a throw event to the server over the stream channel (client-only).
--   ThrowStream.Throw(weaponId, origin, velocity, heldTime)
function Module.Throw(weaponId: string, origin: Vector3, velocity: Vector3, heldTime: number?)
	Module.Channel:Send({ WeaponId = weaponId, Origin = origin, Velocity = velocity, HeldTime = heldTime or 0 })
end

return Module
