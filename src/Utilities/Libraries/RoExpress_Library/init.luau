------------------------------------------------------------------------
--  <> Title:       RoExpress
--  <> Version:     2.5
--  <> Date:        15/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Root module for RoExpress
------------------------------------------------------------------------
-->> Services <<--
local RunService = game:GetService("RunService")
-->> Variables <<--
local IS_SERVER = RunService:IsServer()

-- Version.luau writes shared.ROEXPRESS_VERSION — must run first.
require(script.Version)

-- Types module (pure export types, returns {}, essentially free to require)
local Types = require(script.Types)

-- Pre-baked RemoteEvents — created by the installer and stored as children
-- of this ModuleScript, so both server and client find them instantly with
-- no Instance.new / WaitForChild timing race.
local Remote           = script:FindFirstChildOfClass("RemoteEvent")           :: RemoteEvent
local UnreliableRemote = script:FindFirstChildOfClass("UnreliableRemoteEvent") :: UnreliableRemoteEvent
assert(Remote,           "[RoExpress] RoExpressRemote not found — re-run the installer.")
assert(UnreliableRemote, "[RoExpress] RoExpressUnreliable not found — re-run the installer.")

------------------------------------------------------------------------
-- Lazy loader — modules are required on first access and cached.
------------------------------------------------------------------------
local _cache: { [string]: any } = {}

local function _load(name: string): any
	if not _cache[name] then
		_cache[name] = require(script[name] :: ModuleScript)
	end
	return _cache[name]
end

-- Modules returned as-is when accessed as RoExpress.X
-- (singletons or factories where the user calls .New themselves)
local _DIRECT: { [string]: true } = {
	Base64      = true,
	Bridge      = true,
	Codec       = true,
	Cross       = true,
	Debounce    = true,
	Hook        = true,
	Promise     = true,
	RTTP        = true,
	Router      = true,
	Stream      = true,
	Tamper      = true,
	TypeCoercer = true,
}

-- Context guards for constructed modules
local _SERVER_ONLY: { [string]: true } = { App = true, Broadcast = true }
local _CLIENT_ONLY: { [string]: true } = { Network = true, Listener = true, Benchmark = true }

-- Constructed instance cache — keyed "ModuleName" or "ModuleName:portName"
local _instances: { [string]: any } = {}

------------------------------------------------------------------------
-- Instance construction
------------------------------------------------------------------------
local function _makeInstance(moduleName: string, portName: string?): any
	local cacheKey = if portName then moduleName .. ":" .. portName else moduleName

	if _instances[cacheKey] then
		return _instances[cacheKey]
	end

	if IS_SERVER and _CLIENT_ONLY[moduleName] then
		error("[RoExpress] '" .. moduleName .. "' is client-only", 2)
	elseif not IS_SERVER and _SERVER_ONLY[moduleName] then
		error("[RoExpress] '" .. moduleName .. "' is server-only", 2)
	end

	local m   = _load(moduleName)
	local instance: any

	if portName and not IS_SERVER then
		-- Named port — client wants a Network or Listener scoped to that port
		local folder = game:GetService("ReplicatedStorage"):WaitForChild("RoExpressPorts", 10)
		assert(folder, "[RoExpress] RoExpressPorts not found — call app:Listen() on the server first")
		local portRemote = folder:WaitForChild(portName, 10)
		assert(portRemote, "[RoExpress] Port '" .. portName .. "' not found")

		instance = if moduleName == "Listener"
			then m.New(UnreliableRemote, portRemote)
			else m.New(portRemote)

	elseif moduleName == "Listener" then
		instance = m.New(UnreliableRemote, Remote)

	elseif moduleName == "Maid" then
		instance = m.new()

	elseif moduleName == "Broadcast" then
		instance = m.New(UnreliableRemote)

	elseif moduleName == "Benchmark" then
		-- Benchmark wraps a Network instance rather than a remote
		instance = m.New(_makeInstance("Network"))

	elseif m.New then
		instance = m.New(Remote)

	else
		instance = m
	end

	_instances[cacheKey] = instance
	return instance
end

------------------------------------------------------------------------
-- Root table
------------------------------------------------------------------------
local RoExpress = {}

setmetatable(RoExpress, {
	-- Lazy-load singleton / factory modules on first property access
	__index = function(t, key: string)
		if _DIRECT[key] then
			local m = _load(key)
			rawset(t, key, m)
			return m
		end
		return nil
	end,
	-- RoExpress("ModuleName") or RoExpress("ModuleName", "portName")
	__call = function(_, moduleName: string, portName: string?)
		return _makeInstance(moduleName, portName)
	end,
})

------------------------------------------------------------------------
-- Type re-exports
-- All public types from Types.luau are surfaced here so consumers only
-- need one require:
--
--   local RoExpress = require(game.ReplicatedStorage.RoExpress)
--   local app: RoExpress.App = RoExpress("App")
------------------------------------------------------------------------

-- Module instance types
export type App          = Types.App
export type Network      = Types.Network
export type Broadcast    = Types.Broadcast
export type Listener     = Types.Listener
export type Port         = Types.Port
export type Maid             = Types.Maid
export type Debounce         = Types.Debounce
export type Bridge           = Types.Bridge
export type BridgeConnection = Types.BridgeConnection
export type Hook         = Types.Hook
export type TokenBucket  = Types.TokenBucket
export type Tamper       = Types.Tamper
export type RTTP         = Types.RTTP
export type RTTPInstance = Types.RTTPInstance
export type Cross        = Types.Cross
export type Promise      = Types.Promise

-- Data / handler types
export type Payload             = Types.Payload
export type Request             = Types.Request
export type Response            = Types.Response
export type NetworkPayload      = Types.NetworkPayload
export type NetworkResponse     = Types.NetworkResponse
export type NetworkCallback     = Types.NetworkCallback
export type RouteHandler        = Types.RouteHandler
export type RouteHandlerCompact = Types.RouteHandlerCompact
export type RouteHandlerLegacy  = Types.RouteHandlerLegacy
export type MiddlewareHandler   = Types.MiddlewareHandler
export type ParamErrorHandler   = Types.ParamErrorHandler
export type BroadcastEnvelope   = Types.BroadcastEnvelope
export type MsgContext          = Types.MsgContext
export type ServerEntry         = Types.ServerEntry
export type TamperReport        = Types.TamperReport
export type TamperRecord        = Types.TamperRecord
export type TamperReason        = Types.TamperReason
export type TamperSeverity      = Types.TamperSeverity
export type RTTPResponse        = Types.RTTPResponse
export type RTTPConfig          = Types.RTTPConfig
export type RTTPCallback        = Types.RTTPCallback
export type HookPriority        = Types.HookPriority
export type HookOptions         = Types.HookOptions
export type TokenBucketSettings = Types.TokenBucketSettings
export type Method              = Types.Method
export type RouteOptions        = Types.RouteOptions
export type PromiseState        = Types.PromiseState
export type CrossMemory         = Types.CrossMemory
export type RoExpressCall       = Types.RoExpressCall

-- Explicit property surface for the root table (covers lazy-loaded modules
-- that __index sets at runtime and are invisible to typeof()).
type _Props = {
	Debounce    : Types.Debounce,
	Base64      : Types.Base64,
	Bridge      : Types.Bridge,
	Hook        : Types.Hook,
	Cross       : Types.Cross,
	Tamper      : Types.Tamper,
	RTTP        : Types.RTTP,
	Promise     : Types.Promise,
	Stream      : any,
	Router      : any,
	Codec       : any,
	TypeCoercer : any,
}

-- Double-cast through any so Luau accepts the table+callable intersection.
return (RoExpress :: any) :: _Props & Types.RoExpressCall
