--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Client
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Core client entry point — initializes and
--                  drives client-side systems (input, rendering, UI)
--                  for the Armory OS Advanced Weapon Framework.
--
--                  Also defines every Data/Streams channel (same
--                  definitions as Utilities/Core/Network mounts on the
--                  server — RoExpress.Stream requires both sides to
--                  declare identical channels before Stream.Init()) and
--                  exposes the loaded stream modules so client systems
--                  (Input_Library, etc.) can send through them, e.g.
--                  self.Streams.FireArmStream.Fire(weaponId, origin, dir).
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Requires     ◄--
local RoExpress = require(script.Parent.Parent.Libraries.RoExpress_Library)
--► Tables       ◄--
local Module = {}
Module.__index = Module
--► Constants    ◄--
-- Data/Streams modules — must match Utilities/Core/Network's STREAM_MODULES.
local STREAM_MODULES = {
	"FireArmStream",
	"MeleeStream",
	"ThrowStream",
	"ThirdPersonStream",
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	STREAM LOADING (client only)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Requires every module in STREAM_MODULES (defining their channels),
-- then finalizes with Stream.Init() so they connect to the server's remotes.
local function _loadStreams(): { [string]: any }
	local streamsFolder = script.Parent.Parent.Parent.Data.Streams
	local loaded: { [string]: any } = {}

	for _, name in ipairs(STREAM_MODULES) do
		local moduleScript = streamsFolder:FindFirstChild(name)
		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			warn("[Client Core] Missing stream module '" .. name .. "'")
			continue
		end
		loaded[name] = require(moduleScript :: ModuleScript)
	end

	RoExpress.Stream.Init()
	return loaded
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CONSTRUCTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

function Module.New()
	local self = setmetatable({}, Module)
	self.Streams = _loadStreams()
	return self
end

return Module
