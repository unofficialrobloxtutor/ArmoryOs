------------------------------------------------------------------------
--  <> Title:       RoExpress.Broadcast
--  <> Version:     1.1
--  <> Date:        01/04/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Broadcast module for RoExpress unreliable channel
------------------------------------------------------------------------
-->> Services <<--
local Players = game:GetService("Players")
-->> Tables <<--
local Module = {}
Module.__index = Module
-->> Variables <<--
local TokenBucket  = require(script.Parent.TokenBucket)
local MAX_EVENTS   = 64
local EVENT_MAX    = 20
local EVENT_REFILL = 10
local DATA_CAP     = 900
local BUCKET_TTL   = 30
-->> Types <<--
export type Type = typeof(setmetatable({}, Module)) & {
	Remote         : UnreliableRemoteEvent,
	_eventBuckets  : { [string]: { Tokens: number, Max: number, Refill: number, LastRefill: number, LastUsed: number } },
	_cleanupThread : thread,
}
------------------------------------------------------------------------
--	PRIVATE
------------------------------------------------------------------------
local function _tableSize(t: {}): number
	local count = 0
	for _ in pairs(t) do
		count += 1
	end
	return count
end

local function _newEventBucket()
	return {
		Tokens     = EVENT_MAX,
		Max        = EVENT_MAX,
		Refill     = EVENT_REFILL,
		LastRefill = tick(),
		LastUsed   = tick(),
	}
end

local function _refillEventBucket(bucket)
	local now     = tick()
	local elapsed = now - bucket.LastRefill
	bucket.Tokens     = math.min(bucket.Max, bucket.Tokens + elapsed * bucket.Refill)
	bucket.LastRefill = now
end

local function _consumeEventBucket(self: Type, event: string): boolean
	local bucket = self._eventBuckets[event]
	if not bucket then
		if _tableSize(self._eventBuckets) >= MAX_EVENTS then
			warn("RoExpress.Broadcast: Max event bucket limit reached, dropping event '" .. event .. "'")
			return false
		end
		bucket = _newEventBucket()
		self._eventBuckets[event] = bucket
	end

	_refillEventBucket(bucket)
	bucket.LastUsed = tick()

	if bucket.Tokens < 1 then
		warn("RoExpress.Broadcast: Event '" .. event .. "' is being rate limited")
		return false
	end

	bucket.Tokens -= 1
	return true
end

local function _checkDataSize(data: any): boolean
	local ok, encoded = pcall(function()
		return game:GetService("HttpService"):JSONEncode(data)
	end)
	if ok and #encoded > DATA_CAP then
		warn(string.format("RoExpress.Broadcast: Data size %d bytes exceeds unreliable cap of %d bytes", #encoded, DATA_CAP))
		return false
	end
	return true
end

local function _isPlayerValid(player: Player): boolean
	return player ~= nil and player.Parent ~= nil
end

local function _startCleanup(self: Type)
	self._cleanupThread = task.spawn(function()
		while true do
			task.wait(BUCKET_TTL)
			local now = tick()
			for event, bucket in pairs(self._eventBuckets) do
				if now - bucket.LastUsed > BUCKET_TTL then
					self._eventBuckets[event] = nil
				end
			end
		end
	end)
end
------------------------------------------------------------------------
--	CONSTRUCTORS
------------------------------------------------------------------------
function Module.New(Remote: UnreliableRemoteEvent): Type
	local self         = setmetatable({}, Module) :: Type
	self.Remote        = Remote
	self._eventBuckets = {}
	-- Broadcast owns its own TokenBucket — independent from App's
	self._tokenBucket  = TokenBucket.New({ Max = 10, Refill = 2 })

	_startCleanup(self)

	return self
end
------------------------------------------------------------------------
--	FUNCTIONS
------------------------------------------------------------------------
function Module:Emit(event: string, player: Player, data: any)
	if not _isPlayerValid(player) then
		warn("RoExpress.Broadcast: Invalid player in Emit")
		return
	end
	if not _checkDataSize(data) then return end
	if not _consumeEventBucket(self, event) then return end
	if not self._tokenBucket:HasEnoughTokens(player, 1) then
		warn("RoExpress.Broadcast: Player " .. player.Name .. " token bucket empty, dropping emit")
		return
	end
	self.Remote:FireClient(player, { event = event, data = data })
end

function Module:EmitAll(event: string, data: any)
	if not _checkDataSize(data) then return end
	if not _consumeEventBucket(self, event) then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if _isPlayerValid(player) and self._tokenBucket:HasEnoughTokens(player, 1) then
			self.Remote:FireClient(player, { event = event, data = data })
		end
	end
end

function Module:EmitTo(event: string, targets: { Player }, data: any)
	if not targets or #targets == 0 then
		warn("RoExpress.Broadcast: EmitTo called with empty targets")
		return
	end
	if not _checkDataSize(data) then return end
	if not _consumeEventBucket(self, event) then return end
	for _, player in ipairs(targets) do
		if _isPlayerValid(player) and self._tokenBucket:HasEnoughTokens(player, 1) then
			self.Remote:FireClient(player, { event = event, data = data })
		end
	end
end

function Module:Destroy()
	task.cancel(self._cleanupThread)
	table.clear(self._eventBuckets)
	self._tokenBucket:Destroy()
end

return Module