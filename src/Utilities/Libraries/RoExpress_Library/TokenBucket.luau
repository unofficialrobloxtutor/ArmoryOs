------------------------------------------------------------------------
--  <> Title:       RoExpress.TokenBucket
--  <> Version:     1.1
--  <> Date:        18/05/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Token bucket rate limiter for the remote pipeline.
--                  Each player is assigned a bucket on join that refills
--                  at a fixed rate. Requests cost tokens — if the bucket
--                  is empty the request is denied. Exposes grant utilities
--                  for rewarding burst capacity after round events.
--                  Buckets are automatically created and cleared via
--                  PlayerAdded and PlayerRemoving.
--
--                  v1.1: Made properly instantiable via TokenBucket.New()
--                  so App and Broadcast each own separate bucket state
--                  and can never stomp each other.
------------------------------------------------------------------------
-->> Services <<--
local PlayerService = game:GetService("Players")

-->> Tables <<--
local TokenBucket = {}
TokenBucket.__index = TokenBucket

-->> Types <<--
export type Settings = {
	Max    : number,
	Refill : number,
}

export type Type = typeof(setmetatable({}, TokenBucket)) & {
	_buckets  : { [number]: { Tokens: number, Max: number, Refill: number, LastRefill: number } },
	_settings : Settings,
	_playerAdded   : RBXScriptConnection,
	_playerRemoving: RBXScriptConnection,
}

------------------------------------------------------------------------
--	PRIVATE
------------------------------------------------------------------------
local function _newBucket(settings: Settings)
	return {
		Tokens     = settings.Max,
		Max        = settings.Max,
		Refill     = settings.Refill,
		LastRefill = tick(),
	}
end

local function _refill(bucket)
	local now         = tick()
	local elapsed     = now - bucket.LastRefill
	bucket.Tokens     = math.min(bucket.Max, bucket.Tokens + elapsed * bucket.Refill)
	bucket.LastRefill = now
end

------------------------------------------------------------------------
--	CONSTRUCTOR
------------------------------------------------------------------------
function TokenBucket.New(settings: Settings?): Type
	local self      = setmetatable({}, TokenBucket) :: Type
	self._buckets   = {}
	self._settings  = settings or { Max = 10, Refill = 2 }

	-- seed buckets for any players already in the server (studio play-solo, etc.)
	for _, player in ipairs(PlayerService:GetPlayers()) do
		self._buckets[player.UserId] = _newBucket(self._settings)
	end

	self._playerAdded = PlayerService.PlayerAdded:Connect(function(player)
		self._buckets[player.UserId] = _newBucket(self._settings)
	end)

	self._playerRemoving = PlayerService.PlayerRemoving:Connect(function(player)
		self._buckets[player.UserId] = nil
	end)

	return self
end

------------------------------------------------------------------------
--	FUNCTIONS
------------------------------------------------------------------------
function TokenBucket:Consume(player: Player, cost: number): boolean
	if not self._buckets[player.UserId] then
		self._buckets[player.UserId] = _newBucket(self._settings)
	end
	local bucket = self._buckets[player.UserId]
	_refill(bucket)
	if bucket.Tokens < cost then
		warn(`{player.Name} is being rate limited`)
		return false
	end
	bucket.Tokens -= cost
	return true
end

function TokenBucket:HasTokens(player: Player): boolean
	local bucket = self._buckets[player.UserId]
	if not bucket then return false end
	_refill(bucket)
	return bucket.Tokens > 0
end

function TokenBucket:HasEnoughTokens(player: Player, cost: number): boolean
	local bucket = self._buckets[player.UserId]
	if not bucket then return false end
	_refill(bucket)
	return bucket.Tokens >= cost
end

function TokenBucket:Grant(player: Player, amount: number)
	local bucket = self._buckets[player.UserId]
	if not bucket then return end
	bucket.Tokens = math.min(bucket.Max, bucket.Tokens + amount)
end

function TokenBucket:GrantAll(amount: number)
	for _, bucket in self._buckets do
		bucket.Tokens = math.min(bucket.Max, bucket.Tokens + amount)
	end
end

function TokenBucket:GrantExact(player: Player, amount: number)
	local bucket = self._buckets[player.UserId]
	if not bucket then return end
	bucket.Tokens += amount
end

function TokenBucket:GrantAllExact(amount: number)
	for _, bucket in self._buckets do
		bucket.Tokens += amount
	end
end

function TokenBucket:Reset(player: Player)
	local bucket = self._buckets[player.UserId]
	if not bucket then return end
	bucket.Tokens     = bucket.Max
	bucket.LastRefill = tick()
end

function TokenBucket:Destroy()
	self._playerAdded:Disconnect()
	self._playerRemoving:Disconnect()
	table.clear(self._buckets)
end

return TokenBucket
