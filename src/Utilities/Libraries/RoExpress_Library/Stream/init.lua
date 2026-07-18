------------------------------------------------------------------------
--  <> Title:       RoExpress.Stream
--  <> Version:     2.5
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Generic binary streaming channels for RoExpress.
--
--  OVERVIEW
--  ────────────────────────────────────────────────────────────────
--  Stream replaces the old FPS-specific singleton with schema-defined
--  typed channels. Any game domain can use it — no hardcoded packet
--  types, no vocabulary lock-in.
--
--  All channels are multiplexed over two shared remotes:
--    RoExpressStream/StreamUnreliable  (UnreliableRemoteEvent)
--    RoExpressStream/StreamReliable    (RemoteEvent)
--
--  Wire format (unreliable): [ channelId: u16 ][ seq: u16 ][ payload ]
--  Wire format (reliable):   [ channelId: u16 ][ payload ]
--  Bit 15 of channelId = delta flag. Bits 0-14 = channel ID.
--
--  QUICK START
--  ────────────────────────────────────────────────────────────────
--  -- Both sides (server and client, same channel definitions):
--  local Stream = require(RoExpress.Stream)
--
--  local move = Stream.Channel("playerMove", Stream.Schema({
--      { "pos",   "Vector3" },
--      { "vel",   "Vector3" },
--      { "state", { "flags", "jumping", "sprinting" } },
--  }))
--
--  Stream.Init()   -- call once, after all Channel() definitions
--
--  -- Server:
--  move:On(function(data, player)
--      print(player.Name, data.pos, data.state.jumping)
--  end)
--
--  -- Client:
--  move:Send({ pos = hrp.Position, vel = hrp.AssemblyLinearVelocity, state = { jumping = false } })
--
--  NOTES
--  ────────────────────────────────────────────────────────────────
--  • Stream.Channel() must be called BEFORE Stream.Init().
--  • Both sides must define the same channels with identical schemas.
--  • Channel IDs are derived from a hash of the channel name — no
--    manual numbering needed, and no ordering dependency between server
--    and client registration calls.
--  • Types.Register() can add custom types at any point before Init().
------------------------------------------------------------------------
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SchemaModule = require(script.Schema)
local Types        = require(script.Types)
local Channel      = require(script.Channel)

local _isServer = RunService:IsServer()

local FOLDER_NAME     = "RoExpressStream"
local UNRELIABLE_NAME = "StreamUnreliable"
local RELIABLE_NAME   = "StreamReliable"

------------------------------------------------------------------------
--  Module state
------------------------------------------------------------------------
local _channels   : { [string]: Channel.Type } = {}
local _byId       : { [number]: Channel.Type } = {}
local _initialized = false

local _unreliable       : UnreliableRemoteEvent?
local _reliable         : RemoteEvent?
local _connUnreliable   : RBXScriptConnection?
local _connReliable     : RBXScriptConnection?
local _connPlayerLeaving: RBXScriptConnection?

------------------------------------------------------------------------
--  djb2 hash truncated to u15 (bit 15 reserved for future delta flag)
------------------------------------------------------------------------
local function _hashName(name: string): number
	local h = 5381
	for i = 1, #name do
		h = bit32.band(bit32.lshift(h, 5) + h + string.byte(name, i), 0x7FFF)
	end
	return h
end

------------------------------------------------------------------------
--  Mux dispatch
------------------------------------------------------------------------
local function _dispatch(buf: buffer, sender: Player?)
	if buffer.len(buf) < 2 then return end

	local rawId   = buffer.readu16(buf, 0)
	local isDelta = bit32.band(rawId, 0x8000) ~= 0
	local id      = bit32.band(rawId, 0x7FFF)
	local ch      = _byId[id]
	if not ch then
		warn("RoExpress.Stream: received packet for unknown channel id", id)
		return
	end

	-- Unreliable channels carry a u16 sequence number after the channel ID
	local offset = 2
	local seq    = nil
	if not ch.reliable then
		if buffer.len(buf) < 4 then return end
		seq    = buffer.readu16(buf, 2)
		offset = 4
	end

	local dataLen = buffer.len(buf) - offset
	local dataBuf = buffer.create(math.max(dataLen, 0))
	if dataLen > 0 then
		buffer.copy(dataBuf, 0, buf, offset, dataLen)
	end
	ch:_dispatch(dataBuf, sender, seq, isDelta)
end

------------------------------------------------------------------------
--  Public API
------------------------------------------------------------------------
local Stream = {}

Stream.Types  = Types
Stream.Schema = SchemaModule

-- Define a typed channel. Must be called before Stream.Init().
--
-- options.reliable      = true   → RemoteEvent (ordered, guaranteed delivery)
-- options.reliable      = false  → UnreliableRemoteEvent (default, low latency)
-- options.maxRate       = number → max incoming fires/sec per player (server-side)
-- options.onDrop        = fn     → called when a packet is rate-limited
-- options.deltaInterval = number → force a full packet every N deltas (default 10)
function Stream.Channel(name: string, schema: SchemaModule.Type, options: Channel.Options?): Channel.Type
	assert(not _initialized,   "RoExpress.Stream: Stream.Channel() must be called before Stream.Init()")
	assert(not _channels[name],"RoExpress.Stream: channel '" .. name .. "' already defined")

	local id = _hashName(name)
	if _byId[id] then
		error("RoExpress.Stream: channel name hash collision between '"
			.. name .. "' and '" .. _byId[id].name .. "' — rename one of them")
	end

	local reliable  = options ~= nil and options.reliable == true
	local ch        = Channel.New(name, id, schema, reliable, options)
	_channels[name] = ch
	_byId[id]       = ch

	return ch
end

-- Returns a previously defined channel by name, or nil if not found.
function Stream.GetChannel(name: string): Channel.Type?
	return _channels[name]
end

-- Returns the full channel registry (read-only — do not modify).
function Stream.GetChannels(): { [string]: Channel.Type }
	return _channels
end

-- Finalize and connect to remotes. Call once on both server and client
-- AFTER all Stream.Channel() definitions have been made.
function Stream.Init()
	assert(not _initialized, "RoExpress.Stream: Init() already called")
	_initialized = true

	if _isServer then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name   = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end

		if not folder:FindFirstChild(UNRELIABLE_NAME) then
			local r = Instance.new("UnreliableRemoteEvent")
			r.Name   = UNRELIABLE_NAME
			r.Parent = folder
		end
		if not folder:FindFirstChild(RELIABLE_NAME) then
			local r = Instance.new("RemoteEvent")
			r.Name   = RELIABLE_NAME
			r.Parent = folder
		end

		_unreliable = folder:FindFirstChild(UNRELIABLE_NAME) :: UnreliableRemoteEvent
		_reliable   = folder:FindFirstChild(RELIABLE_NAME)   :: RemoteEvent

		_connUnreliable   = _unreliable.OnServerEvent:Connect(function(player, buf) _dispatch(buf, player) end)
		_connReliable     = _reliable.OnServerEvent:Connect(function(player, buf)   _dispatch(buf, player) end)
		_connPlayerLeaving = game:GetService("Players").PlayerRemoving:Connect(function(player)
			for _, ch in pairs(_channels) do
				ch:_clearPlayer(player)
			end
		end)
	else
		local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 10)
		assert(folder, "RoExpress.Stream: server folder '" .. FOLDER_NAME
			.. "' not found — ensure Stream.Init() is called on the server before the client")

		_unreliable = folder:WaitForChild(UNRELIABLE_NAME, 5) :: UnreliableRemoteEvent
		_reliable   = folder:WaitForChild(RELIABLE_NAME,   5) :: RemoteEvent

		assert(_unreliable, "RoExpress.Stream: UnreliableRemoteEvent not found")
		assert(_reliable,   "RoExpress.Stream: RemoteEvent not found")

		_connUnreliable = _unreliable.OnClientEvent:Connect(function(buf) _dispatch(buf, nil) end)
		_connReliable   = _reliable.OnClientEvent:Connect(function(buf)   _dispatch(buf, nil) end)
	end

	for _, ch in pairs(_channels) do
		ch._remote = ch.reliable and _reliable or _unreliable
	end
end

-- Tear down all channels and reset state. Useful for testing.
function Stream.Destroy()
	if _connUnreliable    then _connUnreliable:Disconnect()    end
	if _connReliable      then _connReliable:Disconnect()      end
	if _connPlayerLeaving then _connPlayerLeaving:Disconnect() end
	for _, ch in pairs(_channels) do
		ch:Destroy()
	end
	table.clear(_channels)
	table.clear(_byId)
	_initialized       = false
	_unreliable        = nil
	_reliable          = nil
	_connUnreliable    = nil
	_connReliable      = nil
	_connPlayerLeaving = nil
end

return Stream
