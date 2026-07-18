------------------------------------------------------------------------
--  <> Title:       RoExpress.Cross
--  <> Version:     1.0
--  <> Date:        15/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Cross-server messaging (MessagingService) and shared
--                  state (MemoryStoreService) wrapped in one API.
--
--  USAGE
--  ---------------------------------------------------------------
--  local Cross = RoExpress.Cross
--
--  -- Broadcast to all servers
--  Cross.Publish("game.event", { map = "Forest" })
--  Cross.Subscribe("game.event", function(data, ctx)
--      print(ctx.serverId, data.map)
--  end)
--  Cross.Once("game.event", function(data, ctx) end)
--  Cross.Unsubscribe("game.event")
--
--  -- Shared key-value store
--  Cross.Memory.Set("global.kills", 0, 3600)
--  local kills = Cross.Memory.Get("global.kills")
--  Cross.Memory.Update("global.kills", function(n) return (n or 0) + 1 end)
--  Cross.Memory.Remove("global.kills")
--
--  -- Server registry (auto-heartbeat, auto-removed on close)
--  Cross.RegisterServer({ mode = "pvp" })
--  local servers = Cross.GetServers()  -- { id, place, players, meta, ts }
--  Cross.UnregisterServer()
--
--  -- This server's JobId (stable across the session)
--  print(Cross.ServerId())
------------------------------------------------------------------------
-->> Services <<--
local HttpService        = game:GetService("HttpService")
local MessagingService   = game:GetService("MessagingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService         = game:GetService("RunService")
local Players            = game:GetService("Players")

assert(RunService:IsServer(), "[RoExpress] Cross is server-only")
------------------------------------------------------------------------
-->> Internal state <<--
------------------------------------------------------------------------
local SERVER_ID: string = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

-- Lazy-created MemoryStoreHashMap instances keyed by map name
local _maps: { [string]: MemoryStoreHashMap } = {}
local function _getMap(name: string): MemoryStoreHashMap
	if not _maps[name] then
		_maps[name] = MemoryStoreService:GetHashMap(name)
	end
	return _maps[name]
end

-- Active MessagingService subscriptions per topic (for Unsubscribe)
local _subs: { [string]: { RBXScriptConnection } } = {}

-- Server registry heartbeat
local _registryActive = false
local _registryMeta: { [string]: any }? = nil

------------------------------------------------------------------------
-->> Constants <<--
------------------------------------------------------------------------
local MEM_MAP     = "rx:mem"
local REG_MAP     = "rx:registry"
local REG_EXPIRY  = 90  -- seconds; heartbeat fires every 30s so 3× margin
local MEM_EXPIRY  = 3600

------------------------------------------------------------------------
-->> Module <<--
------------------------------------------------------------------------
local Cross = {}

------------------------------------------------------------------------
--	ServerId
------------------------------------------------------------------------
function Cross.ServerId(): string
	return SERVER_ID
end

------------------------------------------------------------------------
--	Messaging
------------------------------------------------------------------------

export type MsgContext = {
	serverId : string,
	time     : number,
}

-- Encode/decode helpers keep payload compact (single-letter keys)
local function _encode(data: any): string
	return HttpService:JSONEncode({ d = data, s = SERVER_ID, t = os.time() })
end

local function _decode(raw: string): (any, MsgContext)?
	local ok, m = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok then return nil end
	return m.d, { serverId = m.s, time = m.t }
end

-- Publish to a MessagingService topic. Runs in a detached task so it
-- does not yield the caller.
function Cross.Publish(topic: string, data: any)
	task.spawn(function()
		local ok, err = pcall(MessagingService.PublishAsync, MessagingService, topic, _encode(data))
		if not ok then
			warn("[RoExpress.Cross] Publish '".. topic .."' failed:", err)
		end
	end)
end

-- Subscribe to a topic. Handler receives (data, ctx) and is spawned in
-- its own task so a slow handler cannot block other subscribers.
function Cross.Subscribe(topic: string, handler: (data: any, ctx: MsgContext) -> ())
	local ok, result = pcall(function()
		return MessagingService:SubscribeAsync(topic, function(msg)
			local data, ctx = _decode(msg.Data)
			if data ~= nil or ctx ~= nil then
				task.spawn(handler, data, ctx)
			end
		end)
	end)
	if ok then
		_subs[topic] = _subs[topic] or {}
		table.insert(_subs[topic], result)
	else
		warn("[RoExpress.Cross] Subscribe '".. topic .."' failed:", result)
	end
end

-- Subscribe once and auto-disconnect after the first message.
function Cross.Once(topic: string, handler: (data: any, ctx: MsgContext) -> ())
	local conn: RBXScriptConnection?
	local fired = false
	local ok, result = pcall(function()
		return MessagingService:SubscribeAsync(topic, function(msg)
			if fired then return end
			fired = true
			if conn then
				pcall(function() (conn :: RBXScriptConnection):Disconnect() end)
				conn = nil
			end
			local data, ctx = _decode(msg.Data)
			if data ~= nil or ctx ~= nil then
				task.spawn(handler, data, ctx)
			end
		end)
	end)
	if ok then
		conn = result
	else
		warn("[RoExpress.Cross] Once '".. topic .."' failed:", result)
	end
end

-- Disconnect all subscriptions on a topic.
function Cross.Unsubscribe(topic: string)
	if _subs[topic] then
		for _, c in _subs[topic] do
			pcall(function() c:Disconnect() end)
		end
		_subs[topic] = nil
	end
end

------------------------------------------------------------------------
--	Memory (shared key-value store across servers)
------------------------------------------------------------------------

Cross.Memory = {}

function Cross.Memory.Set(key: string, value: any, expiry: number?)
	local map = _getMap(MEM_MAP)
	local ok, err = pcall(map.SetAsync, map, key, HttpService:JSONEncode(value), expiry or MEM_EXPIRY)
	if not ok then
		warn("[RoExpress.Cross] Memory.Set '".. key .."' failed:", err)
	end
end

function Cross.Memory.Get(key: string): any
	local map = _getMap(MEM_MAP)
	local ok, raw = pcall(map.GetAsync, map, key)
	if not ok or raw == nil then return nil end
	local ok2, val = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok2 then val else nil
end

function Cross.Memory.Remove(key: string)
	local map = _getMap(MEM_MAP)
	pcall(map.RemoveAsync, map, key)
end

-- Atomic read-modify-write. transform receives the current decoded value
-- (nil if the key didn't exist) and returns the new value. Returning nil
-- from transform deletes the key.
function Cross.Memory.Update(key: string, transform: (current: any) -> any, expiry: number?)
	local map = _getMap(MEM_MAP)
	local ok, err = pcall(map.UpdateAsync, map, key, function(raw: string?)
		local current = nil
		if raw ~= nil then
			local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
			if ok2 then current = decoded end
		end
		local next = transform(current)
		if next == nil then return nil end
		return HttpService:JSONEncode(next)
	end, expiry or MEM_EXPIRY)
	if not ok then
		warn("[RoExpress.Cross] Memory.Update '".. key .."' failed:", err)
	end
end

------------------------------------------------------------------------
--	Server Registry
------------------------------------------------------------------------

export type ServerEntry = {
	id      : string,
	place   : number,
	players : number,
	meta    : { [string]: any },
	ts      : number,
}

local function _buildEntry(): string
	return HttpService:JSONEncode({
		id      = SERVER_ID,
		place   = game.PlaceId,
		players = #Players:GetPlayers(),
		meta    = _registryMeta or {},
		ts      = os.time(),
	} :: ServerEntry)
end

local function _refreshEntry()
	local map = _getMap(REG_MAP)
	pcall(map.SetAsync, map, SERVER_ID, _buildEntry(), REG_EXPIRY)
end

-- Register this server. Stores an entry in the shared registry and
-- refreshes it every 30 seconds so it does not expire. Automatically
-- removes the entry when the server closes.
function Cross.RegisterServer(meta: { [string]: any }?)
	_registryMeta   = meta
	_registryActive = true

	_refreshEntry()

	-- Keep the entry alive
	task.spawn(function()
		while _registryActive do
			task.wait(30)
			if _registryActive then
				_refreshEntry()
			end
		end
	end)

	-- Update player count on change so GetServers() stays accurate
	Players.PlayerAdded:Connect(function()
		if _registryActive then _refreshEntry() end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if _registryActive then _refreshEntry() end
		end)
	end)

	-- Best-effort removal on server shutdown (30s budget from Roblox)
	game:BindToClose(function()
		_registryActive = false
		local map = _getMap(REG_MAP)
		pcall(map.RemoveAsync, map, SERVER_ID)
	end)
end

-- Manually remove this server from the registry and stop the heartbeat.
function Cross.UnregisterServer()
	_registryActive = false
	local map = _getMap(REG_MAP)
	pcall(map.RemoveAsync, map, SERVER_ID)
end

-- Returns all currently registered servers. Entries expire automatically
-- if a server crashes without calling UnregisterServer.
function Cross.GetServers(): { ServerEntry }
	local map = _getMap(REG_MAP)
	local servers: { ServerEntry } = {}

	local ok, pages = pcall(map.ListItemsAsync, map, 200)
	if not ok then
		warn("[RoExpress.Cross] GetServers failed:", pages)
		return servers
	end

	while true do
		for _, item in pages:GetCurrentPage() do
			local ok2, entry = pcall(HttpService.JSONDecode, HttpService, item.value)
			if ok2 then
				table.insert(servers, entry :: ServerEntry)
			end
		end
		if pages.IsFinished then break end
		local ok3, err3 = pcall(pages.AdvanceToNextPageAsync, pages)
		if not ok3 then
			warn("[RoExpress.Cross] GetServers pagination failed:", err3)
			break
		end
	end

	return servers
end

return Cross
