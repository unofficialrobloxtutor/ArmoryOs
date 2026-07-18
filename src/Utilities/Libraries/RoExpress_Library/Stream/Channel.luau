------------------------------------------------------------------------
--  <> Title:       RoExpress.Stream.Channel
--  <> Version:     2.5
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Stream channel instance.
--
--  SERVER SEND API
--  ────────────────────────────────────────────────────────────────
--  channel:SendTo(player, data)           — reliable or unreliable
--  channel:SendExcept(except, data)       — all players except one
--  channel:Broadcast(data)                — FireAllClients
--  channel:SendToList(players, data)      — specific list
--  channel:SendToDelta(player, data)      — delta-compressed to one player
--  channel:BroadcastDelta(data)           — delta-compressed to all
--
--  CLIENT SEND API
--  ────────────────────────────────────────────────────────────────
--  channel:Send(data)                     — to server
--
--  SUBSCRIBE API (both sides)
--  ────────────────────────────────────────────────────────────────
--  channel:On(fn)   → unsubscribe()       — persistent subscriber
--  channel:Once(fn) → unsubscribe()       — fires once then auto-removes
--
--  OPTIONS (set at Stream.Channel() call)
--  ────────────────────────────────────────────────────────────────
--  reliable      boolean   — use RemoteEvent instead of UnreliableRemoteEvent
--  maxRate       number    — max incoming fires/sec per player (server-side)
--  onDrop        function  — called when a packet is rate-limited
--  deltaInterval number    — full resend every N deltas (default 10)
------------------------------------------------------------------------
local RunService  = game:GetService("RunService")
local TokenBucket = require(script.Parent.Parent.TokenBucket)

local Channel = {}
Channel.__index = Channel

local _isServer = RunService:IsServer()

export type Options = {
	reliable      : boolean?,
	maxRate       : number?,
	onDrop        : ((player: Player, reason: string) -> ())?,
	deltaInterval : number?,
}

export type Type = typeof(setmetatable({}, Channel)) & {
	name          : string,
	id            : number,
	schema        : any,
	reliable      : boolean,
	_remote       : any,
	_subs         : { (data: { [string]: any }, sender: Player?) -> () },
	_seq          : number,
	_lastSeq      : { [any]: number },
	_stateCache   : { [any]: buffer },
	_deltaCount   : { [any]: number },
	_deltaInterval: number,
	_bucket       : any?,
	_onDrop       : ((player: Player, reason: string) -> ())?,
}

------------------------------------------------------------------------
--  Constructor
------------------------------------------------------------------------
function Channel.New(name: string, id: number, schema: any, reliable: boolean, options: Options?): Type
	local self           = setmetatable({}, Channel) :: Type
	self.name            = name
	self.id              = id
	self.schema          = schema
	self.reliable        = reliable
	self._remote         = nil
	self._subs           = {}
	self._seq            = 0
	self._lastSeq        = {}
	self._stateCache     = {}
	self._deltaCount     = {}
	self._deltaInterval  = (options and options.deltaInterval) or 10
	self._bucket         = nil
	self._onDrop         = options and options.onDrop or nil

	if options and options.maxRate then
		self._bucket = TokenBucket.New({ Max = options.maxRate, Refill = options.maxRate })
	end

	return self
end

------------------------------------------------------------------------
--  Internal helpers
------------------------------------------------------------------------

-- Build a wire packet: [ channelId: u16 ][ seq: u16 if unreliable ][ data ]
-- Bit 15 of channelId signals a delta packet to the receiver.
function Channel:_buildPacket(dataBuf: buffer, isDelta: boolean): buffer
	assert(self._remote, "RoExpress.Stream[" .. self.name .. "]: Stream.Init() was not called")
	local dataLen    = buffer.len(dataBuf)
	local headerSize = self.reliable and 2 or 4
	local pkt        = buffer.create(headerSize + dataLen)
	buffer.writeu16(pkt, 0, isDelta and bit32.bor(self.id, 0x8000) or self.id)
	if not self.reliable then
		self._seq = (self._seq + 1) % 65536
		buffer.writeu16(pkt, 2, self._seq)
	end
	buffer.copy(pkt, headerSize, dataBuf, 0, dataLen)
	return pkt
end

-- Pack data and build a full (non-delta) packet.
function Channel:_makePacket(data: { [string]: any }): buffer
	return self:_buildPacket(self.schema:Pack(data), false)
end

-- Called by init.luau's mux dispatch for every incoming packet on this channel.
function Channel:_dispatch(dataBuf: buffer, sender: Player?, seq: number?, isDelta: boolean?)
	-- Server-side rate limiting for client → server packets
	if self._bucket and sender then
		if not self._bucket:Consume(sender, 1) then
			if self._onDrop then
				pcall(self._onDrop, sender, "rate_limited")
			end
			return
		end
	end

	-- Reject duplicate or out-of-order packets on unreliable channels
	if seq ~= nil then
		local key  = sender or 0
		local last = self._lastSeq[key]
		if last ~= nil then
			local delta = (seq - last) % 65536
			if delta == 0 or delta > 32768 then return end
		end
		self._lastSeq[key] = seq
	end

	-- Full unpack or delta-apply
	local key  = sender or 0
	local data : { [string]: any }

	if isDelta then
		local baseBuf = self._stateCache[key]
		if not baseBuf then
			warn("RoExpress.Stream[" .. self.name .. "]: delta received without base state from",
				sender and sender.Name or "server")
			return
		end
		local ok, resultBuf = pcall(function() return self.schema:ApplyDelta(baseBuf, dataBuf) end)
		if not ok then
			warn("RoExpress.Stream[" .. self.name .. "]: ApplyDelta error:", resultBuf)
			return
		end
		self._stateCache[key] = resultBuf
		local ok2, result = pcall(function() return self.schema:Unpack(resultBuf) end)
		if not ok2 then
			warn("RoExpress.Stream[" .. self.name .. "]: Unpack after delta error:", result)
			return
		end
		data = result
	else
		local ok, result = pcall(function() return self.schema:Unpack(dataBuf) end)
		if not ok then
			warn("RoExpress.Stream[" .. self.name .. "]: Unpack error:", result)
			return
		end
		self._stateCache[key] = dataBuf
		data = result
	end

	for _, sub in ipairs(self._subs) do
		local ok, err = pcall(sub, data, sender)
		if not ok then
			warn("RoExpress.Stream[" .. self.name .. "]: Subscriber error:", err)
		end
	end
end

-- Called by Stream.Init() on PlayerRemoving to free per-player memory.
function Channel:_clearPlayer(player: Player)
	self._lastSeq[player]    = nil
	self._stateCache[player] = nil
	self._deltaCount[player] = nil
end

------------------------------------------------------------------------
--  Subscribe API
------------------------------------------------------------------------

-- Subscribe to incoming data. Returns an unsubscribe function.
function Channel:On(fn: (data: { [string]: any }, sender: Player?) -> ()): () -> ()
	table.insert(self._subs, fn)
	return function()
		for i, sub in ipairs(self._subs) do
			if sub == fn then
					table.remove(self._subs, i)
					return
				end
		end
	end
end

-- Subscribe for exactly one invocation, then auto-unsubscribe.
function Channel:Once(fn: (data: { [string]: any }, sender: Player?) -> ()): () -> ()
	local unsub: () -> ()
	unsub = self:On(function(data, sender)
		unsub()
		fn(data, sender)
	end)
	return unsub
end

------------------------------------------------------------------------
--  Server send API
------------------------------------------------------------------------

function Channel:SendTo(player: Player, data: { [string]: any })
	assert(_isServer, "RoExpress.Stream[" .. self.name .. "]: SendTo is server-only")
	assert(player and player.Parent, "RoExpress.Stream[" .. self.name .. "]: SendTo called with invalid player")
	self._remote:FireClient(player, self:_makePacket(data))
end

-- Send to all players except one.
-- Useful for rebroadcasting a client's own update to every other client.
function Channel:SendExcept(except: Player, data: { [string]: any })
	assert(_isServer, "RoExpress.Stream[" .. self.name .. "]: SendExcept is server-only")
	local pkt     = self:_makePacket(data)
	local Players = game:GetService("Players")
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= except and player.Parent then
			self._remote:FireClient(player, pkt)
		end
	end
end

function Channel:Broadcast(data: { [string]: any })
	assert(_isServer, "RoExpress.Stream[" .. self.name .. "]: Broadcast is server-only")
	self._remote:FireAllClients(self:_makePacket(data))
end

function Channel:SendToList(players: { Player }, data: { [string]: any })
	assert(_isServer, "RoExpress.Stream[" .. self.name .. "]: SendToList is server-only")
	if not players or #players == 0 then
		warn("RoExpress.Stream[" .. self.name .. "]: SendToList called with empty player list")
		return
	end
	local pkt = self:_makePacket(data)
	for _, player in ipairs(players) do
		if player and player.Parent then
			self._remote:FireClient(player, pkt)
		end
	end
end

-- Delta-compressed send to one player. Requires a fixed-size schema.
-- Automatically forces a full packet on first call or every deltaInterval
-- deltas to recover from unreliable packet loss.
function Channel:SendToDelta(player: Player, data: { [string]: any })
	assert(_isServer, "RoExpress.Stream[" .. self.name .. "]: SendToDelta is server-only")
	assert(player and player.Parent, "RoExpress.Stream[" .. self.name .. "]: SendToDelta called with invalid player")
	assert(self.schema._fixedSize, "RoExpress.Stream[" .. self.name .. "]: delta requires a fixed-size schema")

	local newBuf = self.schema:Pack(data)
	local oldBuf = self._stateCache[player]
	local count  = self._deltaCount[player] or 0
	self._stateCache[player] = newBuf

	if not oldBuf or count >= self._deltaInterval then
		self._deltaCount[player] = 0
		self._remote:FireClient(player, self:_buildPacket(newBuf, false))
	else
		self._deltaCount[player] = count + 1
		local ok, deltaBuf = pcall(function() return self.schema:PackDelta(oldBuf, newBuf) end)
		if ok then
			self._remote:FireClient(player, self:_buildPacket(deltaBuf, true))
		else
			warn("RoExpress.Stream[" .. self.name .. "]: PackDelta error, falling back to full packet:", deltaBuf)
			self._deltaCount[player] = 0
			self._remote:FireClient(player, self:_buildPacket(newBuf, false))
		end
	end
end

-- Delta-compressed broadcast. Each player gets its own delta since their
-- last-known states may differ (e.g. joined at different times).
function Channel:BroadcastDelta(data: { [string]: any })
	assert(_isServer, "RoExpress.Stream[" .. self.name .. "]: BroadcastDelta is server-only")
	assert(self.schema._fixedSize, "RoExpress.Stream[" .. self.name .. "]: delta requires a fixed-size schema")

	local newBuf  = self.schema:Pack(data)
	local Players = game:GetService("Players")

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent then
			local oldBuf = self._stateCache[player]
			local count  = self._deltaCount[player] or 0
			self._stateCache[player] = newBuf

			if not oldBuf or count >= self._deltaInterval then
				self._deltaCount[player] = 0
				self._remote:FireClient(player, self:_buildPacket(newBuf, false))
			else
				self._deltaCount[player] = count + 1
				local ok, deltaBuf = pcall(function() return self.schema:PackDelta(oldBuf, newBuf) end)
				if ok then
					self._remote:FireClient(player, self:_buildPacket(deltaBuf, true))
				else
					self._deltaCount[player] = 0
					self._remote:FireClient(player, self:_buildPacket(newBuf, false))
				end
			end
		end
	end
end

------------------------------------------------------------------------
--  Client send API
------------------------------------------------------------------------

function Channel:Send(data: { [string]: any })
	assert(not _isServer, "RoExpress.Stream[" .. self.name .. "]: Send is client-only — use SendTo/Broadcast on the server")
	self._remote:FireServer(self:_makePacket(data))
end

------------------------------------------------------------------------
--  Lifecycle
------------------------------------------------------------------------

function Channel:Destroy()
	if self._bucket then self._bucket:Destroy() end
	table.clear(self._subs)
	table.clear(self._lastSeq)
	table.clear(self._stateCache)
	table.clear(self._deltaCount)
end

return Channel
