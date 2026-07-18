--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       ThirdPersonStream
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Streams — the binary RoExpress.Stream channel for
--                  head-look replication. When a client tilts their camera
--                  up/down, the local rig smoothly lerps its head/neck to
--                  match — this channel is how that pitch reaches the
--                  server and gets relayed out so every OTHER client's
--                  third-person view of that player sees the same lerp.
--                  It is unrelated to the sender's own camera mode (first
--                  or third person) — it exists purely to feed how
--                  everyone else renders this player in third person.
--
--                  Continuous, high-frequency, no ack needed — same
--                  reasoning as Data/Streams/FireArmStream, so it bypasses
--                  the App/Router entirely.
--
--                  Both Utilities/Core/Server and Utilities/Core/Client
--                  require this module so the channel definition is
--                  identical on both sides before Stream.Init() runs.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Requires     ◄--
local RoExpress = require(script.Parent.Parent.Parent.Utilities.Libraries.RoExpress_Library)
--► Tables       ◄--
local Module = {}
--► Constants    ◄--
-- Clamp to a sane look range — mirrors typical camera pitch limits.
local MAX_PITCH = math.rad(89)

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CHANNEL DEFINITION (shared — must match on server and client)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
Module.Channel = RoExpress.Stream.Channel("camera/thirdperson/look", RoExpress.Stream.Schema({
	{ "Pitch", "f32" }, -- radians, up/down camera angle
}), {
	reliable = false,
	maxRate  = 30, -- sent roughly on camera movement — one clamp is enough, no per-weapon logic needed
})

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SERVER — subscribe, clamp, relay
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Wires the channel up. Called once from Utilities/Core/Server during
-- bootstrap (server-only). Takes no `server` argument — this isn't a
-- weapon event, it's a pose relay, so it doesn't touch the weapon event
-- bus (Utilities/Core/Server:Fire) at all:
--   ThirdPersonStream.Register()
function Module.Register()
	Module.Channel:On(function(data, player)
		if not player then
			return
		end
		if type(data.Pitch) ~= "number" then
			return
		end

		local pitch = math.clamp(data.Pitch, -MAX_PITCH, MAX_PITCH)

		-- Relay to every other client so their third-person view of this
		-- player lerps its head/neck to match. The sender already applied
		-- the lerp locally from their own input.
		Module.Channel:SendExcept(player, { Pitch = pitch })
	end)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CLIENT — send helper
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Sends the local camera's up/down pitch to the server (client-only).
-- Call this on camera change (e.g. from RenderStepped), not every frame
-- unconditionally — only when Pitch actually moved, to stay under maxRate.
--   ThirdPersonStream.UpdateLook(camera.CFrame:ToEulerAnglesYXZ())
function Module.UpdateLook(pitch: number)
	Module.Channel:Send({ Pitch = pitch })
end

return Module
