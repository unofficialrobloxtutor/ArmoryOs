------------------------------------------------------------------------
--  <> Title:       RoExpress.Network
--  <> Version:     2.0
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Network module for RoExpress
--
--  RETRY
--  ────────────────────────────────────────────────────────────────
--  Failed requests retry automatically with exponential backoff.
--  Default: 3 retries, 1s base delay (1s → 2s → 4s).
--
--  Retryable status codes: 408 (timeout), 429 (rate limited), 500 (server error)
--  Non-retryable: 400, 403, 404 — deterministic failures that won't change.
--
--  Global override (apply once after getting the instance):
--    network:Configure({ maxRetries = 5, backoff = 2 })
--
--  Per-request override (last param on any method):
--    network:Get("route", nil, callback, timeout, 0)   -- disable retry
--    network:Get("route", nil, callback, timeout, 5)   -- 5 retries
--
--  Cancellation works at any point — retries scheduled during the
--  backoff delay are cancelled immediately.
------------------------------------------------------------------------
local Base64            = require(script.Parent.Base64)
local Codec             = require(script.Parent.Codec)
local Promise           = require(script.Parent.Promise)

local Module = {}
Module.__index = Module

local _idCounter        = 0
local TIMEOUT           = 10
local ROEXPRESS_VERSION = shared.ROEXPRESS_VERSION

local RETRYABLE: { [number]: boolean } = { [408] = true, [429] = true, [500] = true }

------------------------------------------------------------------------
--  Types
------------------------------------------------------------------------
type PendingEntry = {
	callback    : ((response: NetworkResponse) -> ())?,
	promise     : any?,
	method      : string,
	route       : string,
	data        : any,
	timeout     : number,
	retriesLeft : number,
	retryDelay  : number,
	cancelled   : boolean,
	_originalId : string,
}

export type Type = typeof(setmetatable({}, Module)) & {
	Remote        : RemoteEvent,
	_pending      : { [string]: PendingEntry },
	_inflight     : { [string]: string },
	_connection   : RBXScriptConnection,
	_retryConfig  : { maxRetries: number, backoff: number },
}

export type NetworkPayload = {
	version   : string,
	type      : "request",
	method    : "GET" | "POST" | "PUT" | "DELETE",
	requestId : string,
	route     : string,
	data      : any,
}

export type NetworkResponse = {
	version    : string,
	type       : "response" | "error",
	method     : "GET" | "POST" | "PUT" | "DELETE",
	requestId  : string,
	status     : number,
	data       : any?,
	message    : string?,
	compressed : boolean?,
}

------------------------------------------------------------------------
--  Private helpers
------------------------------------------------------------------------
local function _generateId(): string
	_idCounter += 1
	return tostring(tick()) .. "_" .. tostring(_idCounter)
end

-- Settle an entry — decode data, then resolve promise or call callback
local function _settle(self: Type, originalId: string, response: NetworkResponse)
	local entry = self._pending[originalId]
	if not entry then return end
	self._pending[originalId] = nil

	if response.type == "response" and response.data then
		if response.compressed then
			local ok, decoded = pcall(Codec.Decompress, response.data)
			if ok and decoded ~= nil then
				response.data = decoded
			else
				warn("RoExpress.Network: Failed to decompress response")
				response.data = nil
			end
		elseif entry.method == "POST" or entry.method == "PUT" then
			local ok, decoded = pcall(Base64.DecodeTable, response.data)
			if ok then
				response.data = decoded
			else
				warn("RoExpress.Network: Failed to decode " .. entry.method .. " response")
				response.data = nil
			end
		end
	end

	if entry.promise then
		if response.type == "error" then
			entry.promise:_reject(response)
		else
			entry.promise:_resolve(response)
		end
	elseif entry.callback then
		local ok, err = pcall(entry.callback, response)
		if not ok then
			warn("RoExpress.Network: Callback error:", err)
		end
	end
end

-- Forward declare _fire so _retry can reference it
local _fire: (self: Type, method: string, route: string, data: any, entry: PendingEntry, timeout: number?) -> string

local function _retry(self: Type, entry: PendingEntry, originalId: string)
	entry.retriesLeft -= 1
	local delay = entry.retryDelay
	entry.retryDelay = delay * 2
	task.delay(delay, function()
		if entry.cancelled or not self._pending[originalId] then return end
		_fire(self, entry.method, entry.route, entry.data, entry, entry.timeout)
	end)
end

local function _timeout(self: Type, requestId: string, originalId: string, duration: number)
	task.delay(duration, function()
		if not self._inflight[requestId] then return end
		self._inflight[requestId] = nil
		local entry = self._pending[originalId]
		if not entry or entry.cancelled then return end
		if entry.retriesLeft > 0 then
			_retry(self, entry, originalId)
		else
			_settle(self, originalId, {
				version   = ROEXPRESS_VERSION,
				type      = "error",
				method    = entry.method,
				requestId = originalId,
				status    = 408,
				data      = nil,
				message   = "Request timed out after " .. duration .. "s",
			})
		end
	end)
end

local function _onResponse(self: Type, response: NetworkResponse)
	if response.type ~= "response" and response.type ~= "error" then return end

	local originalId = self._inflight[response.requestId]
	if not originalId then return end
	self._inflight[response.requestId] = nil

	local entry = self._pending[originalId]
	if not entry or entry.cancelled then return end

	if RETRYABLE[response.status] and entry.retriesLeft > 0 then
		_retry(self, entry, originalId)
		return
	end

	_settle(self, originalId, response)
end

_fire = function(self: Type, method: string, route: string, data: any, entry: PendingEntry, timeout: number?): string
	local requestId = _generateId()

	if entry._originalId == "" then
		entry._originalId = requestId
		self._pending[requestId] = entry
	end

	entry.method  = method
	entry.route   = route
	entry.data    = data
	entry.timeout = timeout or TIMEOUT

	self._inflight[requestId] = entry._originalId
	_timeout(self, requestId, entry._originalId, entry.timeout)

	self.Remote:FireServer({
		version   = ROEXPRESS_VERSION,
		type      = "request",
		method    = method,
		requestId = requestId,
		route     = route,
		data      = data,
	})

	return entry._originalId
end

local function _mkEntry(self: Type, callback: ((response: NetworkResponse) -> ())?, retries: number?): PendingEntry
	local maxRetries = if retries ~= nil then retries else self._retryConfig.maxRetries
	return {
		callback    = callback,
		promise     = nil,
		method      = "",
		route       = "",
		data        = nil,
		timeout     = TIMEOUT,
		retriesLeft = maxRetries,
		retryDelay  = self._retryConfig.backoff,
		cancelled   = false,
		_originalId = "",
	}
end

------------------------------------------------------------------------
--  Constructor
------------------------------------------------------------------------
function Module.New(Remote: RemoteEvent): Type
	local self          = setmetatable({}, Module) :: Type
	self.Remote         = Remote
	self._pending       = {}
	self._inflight      = {}
	self._retryConfig   = { maxRetries = 3, backoff = 1 }

	self._connection = self.Remote.OnClientEvent:Connect(function(response: NetworkResponse)
		_onResponse(self, response)
	end)

	return self
end

------------------------------------------------------------------------
--  Public API
------------------------------------------------------------------------

function Module:Configure(config: { maxRetries: number?, backoff: number? })
	if config.maxRetries ~= nil then self._retryConfig.maxRetries = config.maxRetries end
	if config.backoff    ~= nil then self._retryConfig.backoff    = config.backoff    end
end

function Module:Get(route: string, data: any?, callback: ((response: NetworkResponse) -> ())?, timeout: number?, retries: number?): (string, NetworkResponse?)
	if callback ~= nil then
		return _fire(self, "GET", route, data, _mkEntry(self, callback, retries), timeout)
	end
	local thread = coroutine.running()
	local entry  = _mkEntry(self, function(res) task.spawn(thread, res) end, retries)
	local id     = _fire(self, "GET", route, data, entry, timeout)
	return id, coroutine.yield()
end

function Module:Post(route: string, data: any, callback: ((response: NetworkResponse) -> ())?, timeout: number?, retries: number?): (string, NetworkResponse?)
	if callback ~= nil then
		return _fire(self, "POST", route, data, _mkEntry(self, callback, retries), timeout)
	end
	local thread = coroutine.running()
	local entry  = _mkEntry(self, function(res) task.spawn(thread, res) end, retries)
	local id     = _fire(self, "POST", route, data, entry, timeout)
	return id, coroutine.yield()
end

function Module:Put(route: string, data: any, callback: ((response: NetworkResponse) -> ())?, timeout: number?, retries: number?): (string, NetworkResponse?)
	if callback ~= nil then
		return _fire(self, "PUT", route, data, _mkEntry(self, callback, retries), timeout)
	end
	local thread = coroutine.running()
	local entry  = _mkEntry(self, function(res) task.spawn(thread, res) end, retries)
	local id     = _fire(self, "PUT", route, data, entry, timeout)
	return id, coroutine.yield()
end

function Module:Delete(route: string, data: any?, callback: ((response: NetworkResponse) -> ())?, timeout: number?, retries: number?): (string, NetworkResponse?)
	if callback ~= nil then
		return _fire(self, "DELETE", route, data, _mkEntry(self, callback, retries), timeout)
	end
	local thread = coroutine.running()
	local entry  = _mkEntry(self, function(res) task.spawn(thread, res) end, retries)
	local id     = _fire(self, "DELETE", route, data, entry, timeout)
	return id, coroutine.yield()
end

function Module:GetAsync(route: string, data: any?, timeout: number?, retries: number?): (string, Promise.Type)
	local promise = Promise.New()
	local entry   = _mkEntry(self, nil, retries)
	entry.promise = promise
	return _fire(self, "GET", route, data, entry, timeout), promise
end

function Module:PostAsync(route: string, data: any, timeout: number?, retries: number?): (string, Promise.Type)
	local promise = Promise.New()
	local entry   = _mkEntry(self, nil, retries)
	entry.promise = promise
	return _fire(self, "POST", route, data, entry, timeout), promise
end

function Module:PutAsync(route: string, data: any, timeout: number?, retries: number?): (string, Promise.Type)
	local promise = Promise.New()
	local entry   = _mkEntry(self, nil, retries)
	entry.promise = promise
	return _fire(self, "PUT", route, data, entry, timeout), promise
end

function Module:DeleteAsync(route: string, data: any?, timeout: number?, retries: number?): (string, Promise.Type)
	local promise = Promise.New()
	local entry   = _mkEntry(self, nil, retries)
	entry.promise = promise
	return _fire(self, "DELETE", route, data, entry, timeout), promise
end

function Module:Cancel(requestId: string): boolean
	local entry = self._pending[requestId]
	if entry then
		entry.cancelled = true
		if entry.promise then entry.promise:Cancel() end
		self._pending[requestId] = nil
		return true
	end
	return false
end

function Module:Destroy()
	self._connection:Disconnect()
	table.clear(self._pending)
	table.clear(self._inflight)
end

return Module
