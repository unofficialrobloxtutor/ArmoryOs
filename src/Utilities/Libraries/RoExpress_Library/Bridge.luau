------------------------------------------------------------------------
--  <> Title:       RoExpress.Bridge
--  <> Version:     2.0
--  <> Date:        15/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Shared in-process event bus for RoExpress.
--
--  Bridge is a named-channel event bus. Any module can emit or
--  listen on any channel by name — no shared references needed.
--
--    Without Bridge:
--      local e = Instance.new("BindableEvent")
--      e.Event:Connect(handler)   ← ModuleA needs the instance
--      e:Fire(data)               ← ModuleB needs the same instance
--
--    With Bridge:
--      Bridge.On("kill", handler) ← ModuleA
--      Bridge.Emit("kill", data)  ← ModuleB, string is the only ref
--
--  API
--  ────────────────────────────────────────────────────────────────
--  Bridge.On(name, handler)        → Connection
--  Bridge.Once(name, handler)      → Connection   (auto-disconnects)
--  Bridge.Emit(name, data?)        fire all handlers on a channel
--  Bridge.Has(name)                true if channel has handlers
--  Bridge.Clear(name?)             remove all handlers (one or all)
--  Bridge.Destroy()                full teardown
--
--  YIELDABLE
--  ────────────────────────────────────────────────────────────────
--  Bridge.Wait(name, timeout?)              → data | nil
--  Bridge.WaitUntil(name, pred, timeout?)   → data | nil
--  Bridge.WaitFirst(names, timeout?)        → name | nil, data | nil
--
--  CONNECTIONS
--  ────────────────────────────────────────────────────────────────
--  Both On and Once return a Connection with a single :Disconnect()
--  method. Anonymous handlers are fully cleanable without holding
--  the original function reference.
--
--    local conn = Bridge.On("kill", function(data) ... end)
--    conn:Disconnect()
--
--  SINGLETON
--  ────────────────────────────────────────────────────────────────
--  Bridge has no New() — requiring this module IS the instance.
------------------------------------------------------------------------

-->> Tables <<--
local Bridge = {}
Bridge.__index = Bridge

-->> Types <<--
export type Handler    = (data: any) -> ()
export type Predicate  = (data: any) -> boolean
export type Channel    = { handlers: { Handler } }
export type Connection = { Disconnect: (self: Connection) -> () }
export type Type       = typeof(Bridge) & {
	_channels : { [string]: Channel },
}

-->> State <<--
Bridge._channels = {}

local DEFAULT_TIMEOUT = 10

------------------------------------------------------------------------
--	PRIVATE
------------------------------------------------------------------------

local function _getOrCreate(name: string): Channel
	if not Bridge._channels[name] then
		Bridge._channels[name] = { handlers = {} }
	end
	return Bridge._channels[name]
end

local function _removeHandler(name: string, handler: Handler)
	local channel = Bridge._channels[name]
	if not channel then return end
	for i, h in ipairs(channel.handlers) do
		if h == handler then
			table.remove(channel.handlers, i)
			return
		end
	end
end

------------------------------------------------------------------------
--	CORE
------------------------------------------------------------------------

function Bridge.On(name: string, handler: Handler): Connection
	assert(type(name)    == "string",   "Bridge.On — name must be a string")
	assert(type(handler) == "function", "Bridge.On — handler must be a function")
	table.insert(_getOrCreate(name).handlers, handler)
	return { Disconnect = function() _removeHandler(name, handler) end }
end

function Bridge.Once(name: string, handler: Handler): Connection
	assert(type(name)    == "string",   "Bridge.Once — name must be a string")
	assert(type(handler) == "function", "Bridge.Once — handler must be a function")

	local fired   = false
	local wrapper: Handler
	wrapper = function(data: any)
		if fired then return end
		fired = true
		_removeHandler(name, wrapper)
		handler(data)
	end

	table.insert(_getOrCreate(name).handlers, wrapper)
	return { Disconnect = function() _removeHandler(name, wrapper) end }
end

function Bridge.Emit(name: string, data: any?)
	assert(type(name) == "string", "Bridge.Emit — name must be a string")
	local channel = Bridge._channels[name]
	if not channel or #channel.handlers == 0 then return end
	local snapshot = table.clone(channel.handlers)
	for _, handler in ipairs(snapshot) do
		local ok, err = pcall(handler, data)
		if not ok then
			warn("Bridge: handler error on '" .. name .. "':", err)
		end
	end
end

function Bridge.Has(name: string): boolean
	local channel = Bridge._channels[name]
	return channel ~= nil and #channel.handlers > 0
end

function Bridge.Clear(name: string?)
	if name ~= nil then
		assert(type(name) == "string", "Bridge.Clear — name must be a string")
		Bridge._channels[name] = nil
	else
		table.clear(Bridge._channels)
	end
end

------------------------------------------------------------------------
--	YIELDABLE
------------------------------------------------------------------------

function Bridge.Wait(name: string, timeout: number?): any?
	assert(type(name) == "string", "Bridge.Wait — name must be a string")

	local thread   = coroutine.running()
	local resolved = false
	local handler: Handler

	handler = function(data: any)
		if resolved then return end
		resolved = true
		_removeHandler(name, handler)
		task.spawn(thread, data)
	end

	table.insert(_getOrCreate(name).handlers, handler)

	task.delay(timeout or DEFAULT_TIMEOUT, function()
		if resolved then return end
		resolved = true
		_removeHandler(name, handler)
		task.spawn(thread, nil)
	end)

	return coroutine.yield()
end

function Bridge.WaitUntil(name: string, predicate: Predicate, timeout: number?): any?
	assert(type(name)      == "string",   "Bridge.WaitUntil — name must be a string")
	assert(type(predicate) == "function", "Bridge.WaitUntil — predicate must be a function")

	local thread   = coroutine.running()
	local resolved = false
	local handler: Handler

	handler = function(data: any)
		if resolved then return end
		local ok, result = pcall(predicate, data)
		if not ok then
			warn("Bridge.WaitUntil: predicate error on '" .. name .. "':", result)
			return
		end
		if not result then return end
		resolved = true
		_removeHandler(name, handler)
		task.spawn(thread, data)
	end

	table.insert(_getOrCreate(name).handlers, handler)

	task.delay(timeout or DEFAULT_TIMEOUT, function()
		if resolved then return end
		resolved = true
		_removeHandler(name, handler)
		task.spawn(thread, nil)
	end)

	return coroutine.yield()
end

function Bridge.WaitFirst(names: { string }, timeout: number?): (string?, any?)
	assert(type(names) == "table" and #names > 0,
		"Bridge.WaitFirst — names must be a non-empty array")

	local thread   = coroutine.running()
	local resolved = false
	local handlers: { [string]: Handler } = {}

	local function cleanup()
		for _, name in ipairs(names) do
			if handlers[name] then
				_removeHandler(name, handlers[name])
			end
		end
	end

	for _, name in ipairs(names) do
		assert(type(name) == "string",
			"Bridge.WaitFirst — each name must be a string, got " .. type(name))
		local captured = name
		local handler: Handler
		handler = function(data: any)
			if resolved then return end
			resolved = true
			cleanup()
			task.spawn(thread, captured, data)
		end
		handlers[name] = handler
		table.insert(_getOrCreate(name).handlers, handler)
	end

	task.delay(timeout or DEFAULT_TIMEOUT, function()
		if resolved then return end
		resolved = true
		cleanup()
		task.spawn(thread, nil, nil)
	end)

	return coroutine.yield()
end

------------------------------------------------------------------------
--	DESTROY
------------------------------------------------------------------------

function Bridge.Destroy()
	table.clear(Bridge._channels)
end

return Bridge
