--!strict
--!native
--!optimize 2
--[[ 
	Created by pivot99
	
	Module Function
		Name: Connection_Library
		Description: 
			This class provides an alternative to bindable events via scripted Signals that mimic RBXScriptSignals
			This also provides a Signal Container which allows for quick management of Signals

		Changelog:
			- Connections and Signals are now strict and no longer work as tables/containers 

]]

--════════════════════════════════════════════════--
-- Connection Module Begin
local Connection = {}
Connection.__index = Connection

-- Connection Module Type
Connection.__type = "Connection"
export type ConnectionType<A... = ()> = {
	--[[ Private
	]]
	_signal : SignalType<A...>, -- the signal the connection is bound to
	_func	: (A...) -> (), 	-- the callback function that is called upon the signal being fired

	-- Public
	Connected : boolean,
	
	Disconnect : (self: ConnectionType<A...>) -> (),
}

-- Connection Module Class
function Connection.New<A...>(Signal: SignalType<A...>, func: (A...) -> ())
	assert(func and typeof(func) == "function", `Connection expected function, got {typeof(func)}`)
	
	return setmetatable({
		Connected 	= true,
		_signal 	= Signal,
		_func		= func,
	} :: any, Connection) :: ConnectionType<A...>
end

-- Meta-Method that does not allow other values to be added. Strict container.
function Connection.__newindex<A...>(self: ConnectionType<A...>, key: string, value: any)
	warn(`Connections cannot store values`)
	return
end

-- Disconnect() is used to remove the connection from a signal
function Connection.Disconnect<A...>(self: ConnectionType<A...>)
	-- Changed Connected State
	self.Connected = false

	-- Remove Connection From Signal
	rawset(self._signal, self, nil)
end

--════════════════════════════════════════════════--
-- Signal Module Begin
local Signal = {}
Signal.__index = Signal

-- Signal Module Type
Signal.__type = "Signal"
export type SignalType<A... = ()> = {
	-- Public
	Fire 	: (self: SignalType<A...>, A...) -> (),
	Connect : (self: SignalType<A...>, func: (A...) -> ()) -> (ConnectionType<A...>),
	Once 	: (self: SignalType<A...>, func: (A...) -> ()) -> (ConnectionType<A...>),
	Wait	: (self: SignalType<A...>, timeOut: number?) -> (A...),
	Destroy : (self: SignalType<A...>) -> (),
}

-- Signal Module Class
function Signal.New<A...>(): SignalType<A...>
	return setmetatable({} :: any, Signal) :: SignalType<A...>
end

-- Meta-Method that does not allow other values to be added. Strict container.
function Signal.__newindex(self: SignalType, Key: string, Value: any)
	warn(`Signals cannot store values.`)
end

-- Meta-Method that returns the total number of stored connections in the signal
function Signal.__len(self: SignalType)
	local Count = 0

	for _ in pairs(self) do
		Count += 1
	end
	
	return Count
end

-- local helper method for firing singals with behavior options
local function fireSignal(self: SignalType, Threaded: boolean, args: { any })
	for Connection : ConnectionType in pairs(self) do
		if Threaded then
			task.defer(Connection._func, table.unpack(args))
		else
			Connection._func(table.unpack(args))
		end
	end
end

-- Fires all callback functions stored in the signals connections defered
function Signal.Fire(self: SignalType, ...)
	local args = table.pack(...)	
	
	fireSignal(self, true, args)
end

-- Fires all callback functions stored in the signals connections in a single thread
function Signal.FireUnthreaded(self: SignalType, ...)
	local args = table.pack(...)	

	fireSignal(self, false, args)
end

-- Connects a callback function to be called whenever the Signal is Fired.
function Signal.Connect<A...>(self: SignalType<A...>, func: (A...) -> ()) : ConnectionType<A...>
	-- Create Connection
	local NewConnection = Connection.New(self, func)
	
	-- Store and Return the connection
	rawset(self, NewConnection, true)
	return NewConnection
end

-- Connects a callback function that can only be called once whenever the Signal is Fired.
function Signal.Once<A...>(self: SignalType<A...>, func: (A...) -> ()) : ConnectionType<A...>
	-- Create Connection
	local NewConnection : ConnectionType<A...>
	NewConnection = Connection.New(self, function(...)
		NewConnection:Disconnect()
		func(...)
	end)

	-- Store and Return the connection
	rawset(self, NewConnection, true)
	return NewConnection
end

-- Yields thread until the signal is fired.
function Signal.Wait<A...>(self: SignalType<A...>, timeOut: number?): (A...)
	if timeOut ~= nil then
		assert(typeof(timeOut) == "number", `ConnectionLibrary "Signal:Wait()" arg 1 expected a number, got {typeof(timeOut)}`)
		assert(timeOut > 0, `ConnectionLibrary "Signal:Wait()" arg 1 expected a number greater than 0, got {timeOut}`)
	else
		timeOut = 5		
	end

	local thread = coroutine.running()
	local args = nil

	local toThread = task.delay(timeOut, function()
		warn(`Infinite yield possible on ConnectionLibrary "Signal:Wait()"`)
		task.spawn(thread)
	end)

	self:Once(function(...)
		local toStatus = coroutine.status(toThread)
		if toStatus == "suspended" or toStatus == "dead" then
			coroutine.close(toThread)
		end
		
		args = table.pack(...) :: any
		task.spawn(thread)
	end)
	
	coroutine.yield()

	if args ~= nil then
		return table.unpack(args)
	end
end

-- Removes all connections stored within the signal.
-- This does NOT destroy the reference or functionality of the signal, just empties the container.
function Signal.Destroy(self: SignalType)
	for Connection in pairs(self) do
		Connection:Disconnect()
	end
end

--════════════════════════════════════════════════--
-- Container Begin
local Container = {}
Container.__index = Container

-- Container Module Type
Container.__type = "Container"
export type ContainerType<A... = ()> = {
	NewSignal 		: (self: ContainerType<A...>, key: string) -> (SignalType<A...>),
	GetSignal		: (self: ContainerType<A...>, key: string, createIfMissing: boolean?) -> (SignalType<A...>),
	Disconnect 		: (self: ContainerType<A...>, key: string, runOnDisconnect: boolean?) -> (),
	DisconnectAll 	: (self: ContainerType<A...>, runOnDisconnect : boolean?) -> (),
}

-- Container Module Class
function Container.New<A...>()
	return setmetatable({} :: any, Container) :: ContainerType<A...>
end

-- Meta-Method that does not allow other values to be added. Strict container.
function Container.__newindex(self: ContainerType, key: string, value: any)
	warn(`Signal Containers cannot store values.`)
end

function Container.NewSignal<A...>(self: ContainerType<A...>, key: string): SignalType<A...>
	local sig = Signal.New()
	rawset(self, key, sig)
	
	return sig
end

function Container.GetSignal<A...>(self: ContainerType<A...>, key: string, createIfMissing: boolean?): SignalType<A...>
	if self[key] == nil and createIfMissing then
		return self.NewSignal(self, key)
	end
	
	return self[key]
end

function Container.Disconnect(self: ContainerType, key: string, runOnDisconnect: boolean?)
	if runOnDisconnect then
		local sig = rawget(self, key) :: SignalType
		
		if sig and sig.Fire then
			sig:Fire()
		end
	end
	
	rawset(self, key, nil)
end

function Container.DisconnectAll(self: ContainerType, runOnDisconnect: boolean?)
	for key in pairs(self) do
		self:Disconnect(key, runOnDisconnect)
	end
end

--════════════════════════════════════════════════--
-- Connection Tracker Begin
local Tracker = {}
Tracker.__index = Tracker

-- Tracker Module Type
Tracker.__type = "Tracker"
export type TrackerType = {
	TrackByConnection 	: (self: TrackerType, key: string, connection: ConnectionType | RBXScriptConnection) -> (),
	TrackByFunction 	: (self: TrackerType, key: string, func : () -> ()) -> (),
	Disconnect 			: (self: TrackerType, key: string) -> (),
	DisconnectAll 		: (self: TrackerType) -> (),
}

-- Container Module Class
function Tracker.New()
	return setmetatable({} :: any, Tracker) :: TrackerType
end

-- Meta-Method that does not allow other values to be added. Strict container.
function Tracker.__newindex(self: SignalType, key: string, value: any)
	warn(`Connection Tracker cannot store values.`)
end

-- Stores connection disconnect callback
function Tracker.TrackByConnection(self: TrackerType, key: string, connection: any)
	self:Disconnect(key)
	
	rawset(self, key, function() connection:Disconnect() end)
end

-- Stores a callback for the tracked signal, this callback should disconnect the connection
function Tracker.TrackByFunction(self: TrackerType, key: string, func: () -> ())
	self:Disconnect(key)
	
	rawset(self, key, func)
end

-- Disconnects the given key's callback
function Tracker.Disconnect(self: TrackerType, key: string)
	local disconnect = self[key]
	
	-- run disconnect if any
	if disconnect then
		disconnect()
		self[key] = nil
	end
end

-- Disconnects all stored disconnect callbacks
function Tracker.DisconnectAll(self: TrackerType)
	for key in pairs(self) do
		self:Disconnect(key)
	end
end

-- Module End
return {
	NewSignal 				= Signal.New,
	NewSignalContainer 		= Container.New,
	NewConnectionTracker 	= Tracker.New
} :: {
	NewSignal 				: <A...>() -> (SignalType<A...>),
	NewSignalContainer 		: <A...>() -> (ContainerType<A...>),
	NewConnectionTracker 	: () -> (TrackerType)
}
