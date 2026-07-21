------------------------------------------------------------------------
--  <> Title:       RoExpress.Port
--  <> Version:     1.0
--  <> Date:        30/05/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Named port for RoExpress.
--
--  A Port is an isolated request pipeline bound to its own
--  RemoteEvent. Created via app:Listen(name, callback).
--
--  Each port has:
--    - Its own RemoteEvent in ReplicatedStorage
--    - Its own Router (independent route table)
--    - Its own TokenBucket (configurable rate limiting)
--    - Inherited global middleware from the parent App
--    - Full Push / PushAll / PushTo support
--
--  The client connects to a named port via:
--    RoExpress("Network", "portName")
--    RoExpress("Listener", "portName")
------------------------------------------------------------------------
-->> Services <<--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
-->> Tables <<--
local Port = {}
Port.__index = Port
-->> Variables <<--
local Base64      = require(script.Parent.Base64)
local TokenBucket = require(script.Parent.TokenBucket)
local Router      = require(script.Parent.Router)
local Codec       = require(script.Parent.Codec)
local Tamper      = require(script.Parent.Tamper)
local ROEXPRESS_VERSION = shared.ROEXPRESS_VERSION

------------------------------------------------------------------------
--  TYPES
------------------------------------------------------------------------
export type BucketSettings = {
    Max    : number?,
    Refill : number?,
}

export type Payload = {
    version   : string,
    type      : "request" | "response" | "error",
    method    : "GET" | "POST" | "PUT" | "DELETE",
    requestId : string,
    route     : string,
    data      : any,
}

export type Request = {
    params   : { [string]: any },
    captures : { any },
    query    : { [string]: string },
    data     : any,
    port     : string,
    player   : Player?,
    raw      : Payload?,
}

export type Response = {
    Send   : (self: Response, data: any) -> (),
    Error  : (self: Response, message: string) -> (),
    Status : (self: Response, code: number) -> Response,
}

export type MiddlewareFn         = (Player: Player, Payload: Payload) -> (boolean?)
export type RouteHandlerCompact  = (req: Request, res: Response) -> ()
export type RouteHandlerLegacy   = (Player: Player, Payload: Payload, req: Request, res: Response) -> ()
export type RouteHandler         = RouteHandlerCompact | RouteHandlerLegacy

export type Type = typeof(setmetatable({}, Port)) & {
    Name             : string,
    Remote           : RemoteEvent,
    TokenBucket      : TokenBucket.Type,
    _router          : Router.Type,
    _middleware      : { { id: string, fn: MiddlewareFn } },
    _localMiddleware : { { id: string, fn: MiddlewareFn } },
    _connection      : RBXScriptConnection,
}

------------------------------------------------------------------------
--  PRIVATE
------------------------------------------------------------------------
local function _parseQuery(route: string)
    local path, queryString = route:match("^([^?]*)%??(.*)")
    local query = {}
    if queryString and queryString ~= "" then
        for key, value in queryString:gmatch("([^&=]+)=([^&=]+)") do
            query[key] = value
        end
    end
    return path, query
end

local function _validatePayload(Payload): boolean
    return type(Payload) == "table"
        and type(Payload.route) == "string"
        and type(Payload.requestId) == "string"
        and type(Payload.method) == "string"
        and Payload.type == "request"
end

local function _buildResponse(Remote, Player, requestId, method, compress, algo)
    local res   = {}
    res._status = 200
    res._sent   = false

    function res:Status(code)
        self._status = code
        return self
    end

    function res:Send(data)
        if self._sent then
            warn("RoExpress.Port: res:Send() called more than once")
            return
        end
        self._sent = true
        local payload
        if compress then
            payload = algo == "lzh" and Codec.Deflate(data) or Codec.Compress(data)
        elseif method == "POST" then
            payload = Base64.EncodeTable(data)
        else
            payload = data
        end
        Remote:FireClient(Player, {
            version    = ROEXPRESS_VERSION,
            type       = "response",
            method     = method,
            requestId  = requestId,
            status     = self._status,
            data       = payload,
            compressed = compress == true,
        })
    end

    function res:Error(message)
        if self._sent then
            warn("RoExpress.Port: res:Error() called more than once")
            return
        end
        self._sent = true
        Remote:FireClient(Player, {
            version   = ROEXPRESS_VERSION,
            type      = "error",
            method    = method,
            requestId = requestId,
            status    = self._status ~= 200 and self._status or 500,
            message   = message,
        })
    end

    return res
end

local function _handler(self: Type, Player, Payload)
    -- version check
    if Payload.version ~= ROEXPRESS_VERSION then
        warn("RoExpress.Port[" .. self.Name .. "]: Version mismatch from", Player.Name)
        local res = _buildResponse(self.Remote, Player, Payload.requestId or "", Payload.method or "GET", false)
        res:Status(400):Error("Client version mismatch")
        Tamper.Signal("version_mismatch", Player, { route = Payload.route, evidence = { port = self.Name } })
        return
    end

    -- rate limit
    if not self.TokenBucket:Consume(Player, 1) then
        local res = _buildResponse(self.Remote, Player, Payload.requestId or "", Payload.method or "GET", false)
        res:Status(429):Error("Too many requests")
        Tamper.Signal("rate_limited", Player, { route = Payload.route })
        return
    end

    -- payload validation
    if not _validatePayload(Payload) then
        warn("RoExpress.Port[" .. self.Name .. "]: Invalid payload from", Player.Name)
        Tamper.Signal("malformed", Player, { evidence = Payload })
        return
    end

    -- inherited app middleware runs first
    for _, entry in ipairs(self._middleware) do
        local ok, result = pcall(entry.fn, Player, Payload)
        if not ok then
            warn("RoExpress.Port[" .. self.Name .. "]: Middleware '" .. entry.id .. "' error:", result)
            local res = _buildResponse(self.Remote, Player, Payload.requestId, Payload.method, false)
            res:Status(500):Error("Middleware error")
            return
        end
        if result == false then
            local res = _buildResponse(self.Remote, Player, Payload.requestId, Payload.method, false)
            if not res._sent then
                res:Status(403):Error("Blocked by middleware '" .. entry.id .. "'")
            end
            return
        end
    end

    -- port-local middleware
    for _, entry in ipairs(self._localMiddleware) do
        local ok, result = pcall(entry.fn, Player, Payload)
        if not ok then
            warn("RoExpress.Port[" .. self.Name .. "]: Local middleware '" .. entry.id .. "' error:", result)
            local res = _buildResponse(self.Remote, Player, Payload.requestId, Payload.method, false)
            res:Status(500):Error("Middleware error")
            return
        end
        if result == false then
            local res = _buildResponse(self.Remote, Player, Payload.requestId, Payload.method, false)
            if not res._sent then
                res:Status(403):Error("Blocked by middleware '" .. entry.id .. "'")
            end
            return
        end
    end

    local incomingPath, query = _parseQuery(Payload.route)
    local match = self._router:Match(Payload.method, incomingPath)

    if not match then
        local res = _buildResponse(self.Remote, Player, Payload.requestId, Payload.method, false)
        res:Status(404):Error("No handler for route '" .. Payload.route .. "' on port '" .. self.Name .. "'")
        Tamper.Signal("unknown_route", Player, { route = Payload.route, evidence = { port = self.Name } })
        return
    end

    local matchAny = match :: any
    local typeFail = matchAny._typeFail
    if typeFail then
        local res = _buildResponse(self.Remote, Player, Payload.requestId, Payload.method, false)
        if self._router._paramError then
            self._router._paramError(Player, Payload, typeFail.name, typeFail.expectedType)
        else
            res:Status(400):Error("Param '" .. typeFail.name .. "' expected type " .. typeFail.expectedType)
        end
        Tamper.Signal("param_fail", Player, { route = Payload.route, evidence = { param = typeFail.name } })
        return
    end

    local routeAny = match.route :: any
    local compress = routeAny.compress == true
    local algo     = routeAny.algo
    local res      = _buildResponse(self.Remote, Player, Payload.requestId, Payload.method, compress, algo)

    local argcount = debug.info(match.route.handler, "a")
    local req: Request
    local ok, err
    if argcount and argcount == 2 then
        req = {
            player   = Player,
            params   = match.params,
            captures = match.captures,
            query    = query,
            data     = Payload.data,
            port     = self.Name,
            raw      = Payload,
        }
        ok, err = pcall(match.route.handler, req, res)
    else
        req = {
            params   = match.params,
            captures = match.captures,
            query    = query,
            data     = Payload.data,
            port     = self.Name,
        }
        ok, err = pcall(match.route.handler, Player, Payload, req, res)
    end
    if not ok then
        warn("RoExpress.Port[" .. self.Name .. "]: Handler error on '" .. Payload.route .. "':", err)
        if not res._sent then
            res:Status(500):Error("Internal server error")
        end
    end
end

------------------------------------------------------------------------
--  CONSTRUCTOR (called by App:Listen)
------------------------------------------------------------------------
function Port.New(name: string, appMiddleware: { { id: string, fn: MiddlewareFn } }, settings: BucketSettings?): Type
    -- create or reuse the RemoteEvent for this port
    local folder = ReplicatedStorage:FindFirstChild("RoExpressPorts")
        or Instance.new("Folder", ReplicatedStorage)
    folder.Name = "RoExpressPorts"

    local remote = folder:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = folder
    end

    local self = setmetatable({}, Port) :: Type
    self.Name            = name
    self.Remote          = remote
    self.TokenBucket     = TokenBucket.New({
        Max    = settings and settings.Max    or 10,
        Refill = settings and settings.Refill or 2,
    })
    self._router         = Router.New()
    self._middleware     = appMiddleware   -- shared reference to App._middleware
    self._localMiddleware= {}

    self._connection = remote.OnServerEvent:Connect(function(Player, Payload)
        _handler(self, Player, Payload)
    end)

    return self
end

------------------------------------------------------------------------
--  PUBLIC API
------------------------------------------------------------------------

-- Port-local middleware (runs after inherited app middleware)
function Port:Use(id: string, fn: MiddlewareFn): ()
    table.insert(self._localMiddleware, { id = id, fn = fn })
end

function Port:Unuse(id: string): ()
    for i, entry in ipairs(self._localMiddleware) do
        if entry.id == id then
            table.remove(self._localMiddleware, i)
            return
        end
    end
    warn("RoExpress.Port[" .. self.Name .. "]: No local middleware '" .. id .. "'")
end

function Port:Get(route: string, handler: RouteHandler, options: { compress: boolean?, algo: ("lz77" | "lzh")? }?): ()
    self._router:Add("GET", route, handler, options)
end

function Port:Post(route: string, handler: RouteHandler, options: { compress: boolean?, algo: ("lz77" | "lzh")? }?): ()
    self._router:Add("POST", route, handler, options)
end

function Port:Put(route: string, handler: RouteHandler, options: { compress: boolean?, algo: ("lz77" | "lzh")? }?): ()
    self._router:Add("PUT", route, handler, options)
end

function Port:Delete(route: string, handler: RouteHandler, options: { compress: boolean?, algo: ("lz77" | "lzh")? }?): ()
    self._router:Add("DELETE", route, handler, options)
end

function Port:OnParamError(fn: (Player: Player, Payload: Payload, paramName: string, expectedType: string) -> ()): ()
    self._router:OnParamError(fn)
end

function Port:Push(player: Player, event: string, data: any): ()
    if player == nil or player.Parent == nil then
        warn("RoExpress.Port[" .. self.Name .. "]: Push called with invalid player")
        return
    end
    self.Remote:FireClient(player, { type = "push", event = event, data = data })
end

function Port:PushAll(event: string, data: any): ()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Parent ~= nil then
            self.Remote:FireClient(player, { type = "push", event = event, data = data })
        end
    end
end

function Port:PushTo(players: { Player }, event: string, data: any): ()
    if not players or #players == 0 then
        warn("RoExpress.Port[" .. self.Name .. "]: PushTo called with empty player list")
        return
    end
    for _, player in ipairs(players) do
        if player ~= nil and player.Parent ~= nil then
            self.Remote:FireClient(player, { type = "push", event = event, data = data })
        end
    end
end

function Port:Destroy(): ()
    self._connection:Disconnect()
    self._router:Destroy()
    table.clear(self._localMiddleware)
    self.TokenBucket:Destroy()
end

return Port
