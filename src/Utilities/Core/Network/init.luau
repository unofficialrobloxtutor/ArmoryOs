--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Network
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Core networking entry point — sets up
--                  client-server communication channels used by the
--                  weapon framework's replicated systems. Server-side
--                  it boots the RoExpress App and mounts every route
--                  table in Data/Routes, then defines and initializes
--                  every Data/Streams channel (high-frequency traffic
--                  like weapon fire that skips the request/response
--                  App entirely); client-side it exposes a RoExpress
--                  Network instance for issuing requests.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local RunService = game:GetService("RunService")
--► Requires     ◄--
local RoExpress  = require(script.Parent.Parent.Libraries.RoExpress_Library)
local ServerCore = require(script.Parent.Parent.Types.Server)
--► Tables       ◄--
local Network = {}
Network.__index = Network
--► Variables    ◄--
local IS_SERVER = RunService:IsServer()
--► Constants    ◄--
-- Data/Routes modules mounted on the server when this module boots.
-- Add new route tables here to wire them in.
local ROUTE_MODULES = {
	"FireArmRoutes",
	"MeleeRoutes",
	"ThrowRoutes",
	"FirstPersonRoutes",
	"ThirdPersonRoutes",
}

-- Data/Streams modules — each defines a RoExpress.Stream channel and an
-- optional server-side Register(server) subscriber. Anything fired/checked
-- frequently (fire, melee swings, throws) belongs here instead of Data/Routes.
local STREAM_MODULES = {
	"FireArmStream",
	"MeleeStream",
	"ThrowStream",
	"ThirdPersonStream",
}

--► Types        ◄--
export type Type = typeof(setmetatable({}, Network)) & {
	App     : RoExpress.App?,
	Network : RoExpress.Network?,
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ROUTE MOUNTING (server only)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Requires and registers every module named in ROUTE_MODULES against the App.
-- Each route module is expected to export a Register(app, server) function —
-- `server` is the Utilities/Core/Server instance, handed through so route
-- handlers can fire weapon lifecycle events / push state updates once a
-- request has resolved.
local function _mountRoutes(app: RoExpress.App, server: ServerCore.Type?)
	local routesFolder = script.Parent.Parent.Parent.Data.Routes

	for _, name in ipairs(ROUTE_MODULES) do
		local moduleScript = routesFolder:FindFirstChild(name)
		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			warn("[Network Core] Missing route module '" .. name .. "'")
			continue
		end

		local routes = require(moduleScript :: ModuleScript) :: any
		if type(routes.Register) == "function" then
			routes.Register(app, server)
		else
			warn("[Network Core] Route module '" .. name .. "' has no Register(app, server) function")
		end
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	STREAM MOUNTING (server only)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- Requires every module named in STREAM_MODULES — this defines their
-- RoExpress.Stream channels — then calls each module's optional
-- Register(server) to wire up server-side subscribers, then finalizes
-- with Stream.Init() so the channels connect to their remotes.
local function _mountStreams(server: ServerCore.Type?)
	local streamsFolder = script.Parent.Parent.Parent.Data.Streams

	for _, name in ipairs(STREAM_MODULES) do
		local moduleScript = streamsFolder:FindFirstChild(name)
		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			warn("[Network Core] Missing stream module '" .. name .. "'")
			continue
		end

		local stream = require(moduleScript :: ModuleScript) :: any
		if type(stream.Register) == "function" then
			stream.Register(server)
		end
	end

	RoExpress.Stream.Init()
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CONSTRUCTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Boots the networking layer for the current context (server or client)
-- `server` (server-side only) is the Utilities/Core/Server instance —
-- pass it so every mounted route can reach the weapon event bus / state push.
function Network.New(server: ServerCore.Type?): Type
	local self = setmetatable({}, Network) :: Type

	if IS_SERVER then
		local app = (RoExpress :: any)("App") :: RoExpress.App
		_mountRoutes(app, server)
		_mountStreams(server)
		self.App = app
	else
		self.Network = (RoExpress :: any)("Network") :: RoExpress.Network
	end

	return self
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SERVER API — push / broadcast to clients
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Pushes an event to a single player — server only
function Network.Push(self: Type, player: Player, event: string, data: any)
	local app = self.App :: RoExpress.App
	assert(app, "Network Core: Push() is server-only")
	app:Push(player, event, data)
end

--► Pushes an event to every connected player — server only
function Network.PushAll(self: Type, event: string, data: any)
	local app = self.App :: RoExpress.App
	assert(app, "Network Core: PushAll() is server-only")
	app:PushAll(event, data)
end

--► Pushes an event to a specific list of players — server only
function Network.PushTo(self: Type, players: {Player}, event: string, data: any)
	local app = self.App :: RoExpress.App
	assert(app, "Network Core: PushTo() is server-only")
	app:PushTo(players, event, data)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CLIENT API — request helpers
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Issues a GET request to a route — client only
function Network.Get(self: Type, route: string, data: any?, callback: RoExpress.NetworkCallback?): string
	local net = self.Network :: RoExpress.Network
	assert(net, "Network Core: Get() is client-only")
	return net:Get(route, data, callback)
end

--► Issues a POST request to a route — client only
function Network.Post(self: Type, route: string, data: any, callback: RoExpress.NetworkCallback?): string
	local net = self.Network :: RoExpress.Network
	assert(net, "Network Core: Post() is client-only")
	return net:Post(route, data, callback)
end

--► Issues a PUT request to a route — client only
function Network.Put(self: Type, route: string, data: any, callback: RoExpress.NetworkCallback?): string
	local net = self.Network :: RoExpress.Network
	assert(net, "Network Core: Put() is client-only")
	return net:Put(route, data, callback)
end

--► Issues a DELETE request to a route — client only
function Network.Delete(self: Type, route: string, data: any?, callback: RoExpress.NetworkCallback?): string
	local net = self.Network :: RoExpress.Network
	assert(net, "Network Core: Delete() is client-only")
	return net:Delete(route, data, callback)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	LIFECYCLE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Tears down the App/Network instance this Core owns
function Network.Destroy(self: Type)
	local app = self.App :: RoExpress.App
	local net = self.Network :: RoExpress.Network
	if app then
		app:Destroy()
	end
	if net then
		net:Destroy()
	end
end

return Network
