------------------------------------------------------------------------
--  <> Title:       RoExpress.Listener
--  <> Version:     2.0
--  <> Date:        30/05/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Listener module for RoExpress
--
--  v2.0 changes
--  ────────────────────────────────────────────────────────────────
--  • Now accepts an optional second remote (the reliable RemoteEvent)
--    so it can receive server-push events alongside unreliable broadcasts.
--  • Push packets carry type = "push" — filtered here, invisible to
--    the user. On/Once/Off/middleware API is identical for both sources.
--  • Reliable push connection is stored in _pushConnection and cleaned
--    up in Destroy().
------------------------------------------------------------------------
-->> Tables <<--
local Module = {}
Module.__index = Module
-->> Types <<--
export type Type = typeof(setmetatable({}, Module)) & {
	Remote          : UnreliableRemoteEvent,
	_on             : { [string]: (data: any) -> () },
	_once           : { [string]: (data: any) -> () },
	_middleware     : { { id: string, fn: (event: string, data: any) -> () } },
	_connection     : RBXScriptConnection,
	_pushConnection : RBXScriptConnection?,  -- reliable remote connection (optional)
}
------------------------------------------------------------------------
--	PRIVATE
------------------------------------------------------------------------

-- Shared dispatch — routes an envelope through middleware then On/Once handlers.
-- Called by both the unreliable and reliable connections.
local function _dispatch(self: Type, envelope: { event: string, data: any })
	if type(envelope) ~= "table" or type(envelope.event) ~= "string" then
		warn("RoExpress.Listener: Invalid envelope received")
		return
	end

	local event = envelope.event
	local data  = envelope.data

	-- run middleware before handlers
	for _, entry in ipairs(self._middleware) do
		local ok, err = pcall(entry.fn, event, data)
		if not ok then
			warn("RoExpress.Listener: Middleware error on '" .. event .. "':", err)
		end
	end

	-- once handler fires first, unsubscribed before calling to avoid race
	local onceHandler = self._once[event]
	if onceHandler then
		self._once[event] = nil
		local ok, err = pcall(onceHandler, data)
		if not ok then
			warn("RoExpress.Listener: Once handler error on '" .. event .. "':", err)
		end
	end

	-- persistent handler
	local onHandler = self._on[event]
	if onHandler then
		local ok, err = pcall(onHandler, data)
		if not ok then
			warn("RoExpress.Listener: On handler error on '" .. event .. "':", err)
		end
	end
end

------------------------------------------------------------------------
--	CONSTRUCTORS
------------------------------------------------------------------------

--[[
	New(unreliableRemote, reliableRemote?)

	unreliableRemote  — the UnreliableRemoteEvent (broadcast channel)
	reliableRemote    — optional RemoteEvent (reliable push channel)

	Passing the reliable remote enables server-push events.
	The API surface is identical regardless — On/Once/Off work for both.
]]
function Module.New(unreliableRemote: UnreliableRemoteEvent, reliableRemote: RemoteEvent?): Type
	local self          = setmetatable({}, Module) :: Type
	self.Remote         = unreliableRemote
	self._on            = {}
	self._once          = {}
	self._middleware    = {}
	self._pushConnection = nil

	-- unreliable broadcast channel (existing behaviour)
	self._connection = unreliableRemote.OnClientEvent:Connect(function(envelope)
		_dispatch(self, envelope)
	end)

	-- reliable push channel — filter to type = "push" only so Network
	-- responses passing through the same remote are never intercepted here
	if reliableRemote then
		self._pushConnection = reliableRemote.OnClientEvent:Connect(function(packet)
			if type(packet) ~= "table" or packet.type ~= "push" then return end
			_dispatch(self, { event = packet.event, data = packet.data })
		end)
	end

	return self
end

------------------------------------------------------------------------
--	FUNCTIONS
------------------------------------------------------------------------
function Module:Use(id: string, fn: (event: string, data: any) -> ())
	table.insert(self._middleware, { id = id, fn = fn })
end

function Module:Unuse(id: string)
	for i, entry in ipairs(self._middleware) do
		if entry.id == id then
			table.remove(self._middleware, i)
			return
		end
	end
	warn("RoExpress.Listener: No middleware found with id '" .. id .. "'")
end

function Module:On(event: string, handler: (data: any) -> ())
	self._on[event] = handler
end

function Module:Once(event: string, handler: (data: any) -> ())
	self._once[event] = handler
end

function Module:Off(event: string)
	self._on[event]   = nil
	self._once[event] = nil
end

function Module:Destroy()
	self._connection:Disconnect()
	if self._pushConnection then
		self._pushConnection:Disconnect()
	end
	table.clear(self._on)
	table.clear(self._once)
	table.clear(self._middleware)
end

return Module
