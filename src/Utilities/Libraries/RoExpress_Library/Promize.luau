------------------------------------------------------------------------
--  <> Title:       RoExpress.Promise
--  <> Version:     1.0
--  <> Date:        30/05/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Lightweight Promise implementation for Network.
--
--  A minimal Promise built specifically for RoExpress's Network
--  module. No external dependencies. Returns a chainable object
--  from network:Get and network:Post.
--
--  STATES
--  ---------------------------------------------------------------
--  pending   -> waiting for server response
--  resolved  -> server responded successfully (2xx)
--  rejected  -> server responded with error, or timed out
--
--  API
--  ---------------------------------------------------------------
--  promise:Then(fn)        called with response on resolve
--  promise:Catch(fn)       called with response on reject
--  promise:Finally(fn)     called regardless of outcome
--  promise:Cancel()        cancel before resolution
--
--  CHAINING
--  ---------------------------------------------------------------
--  network:Get("player/123")
--      :Then(function(res) return res.data.coins end)
--      :Then(function(coins) UI:SetCoins(coins) end)
--      :Catch(function(err) warn(err.message) end)
--      :Finally(function() UI:HideLoader() end)
--
--  Then handlers can return a value which is passed to the next
--  Then in the chain. If a Then handler errors, the chain falls
--  through to the nearest Catch.
------------------------------------------------------------------------

local Promise = {}
Promise.__index = Promise

------------------------------------------------------------------------
--  TYPES
------------------------------------------------------------------------
export type State = "pending" | "resolved" | "rejected"

export type Type = typeof(setmetatable({}, Promise)) & {
    _state     : State,
    _value     : any,
    _thenCbs   : { (value: any) -> any },
    _catchCbs  : { (err: any)   -> any },
    _finallyCbs: { () -> () },
    _cancelled : boolean,
}

------------------------------------------------------------------------
--  CONSTRUCTOR
------------------------------------------------------------------------
function Promise.New(): Type
    local self = setmetatable({}, Promise) :: Type
    self._state      = "pending"
    self._value      = nil
    self._thenCbs    = {}
    self._catchCbs   = {}
    self._finallyCbs = {}
    self._cancelled  = false
    return self
end

------------------------------------------------------------------------
--  INTERNAL RESOLUTION
------------------------------------------------------------------------

-- Run through the Then chain passing values along
local function _runChain(self: Type, value: any)
    local current = value
    for _, fn in ipairs(self._thenCbs) do
        local ok, result = pcall(fn, current)
        if not ok then
            -- Then handler errored — fall through to Catch
            self._state = "rejected"
            for _, catchFn in ipairs(self._catchCbs) do
                pcall(catchFn, { message = result, status = 0, type = "error" })
            end
            for _, finallyFn in ipairs(self._finallyCbs) do
                pcall(finallyFn)
            end
            return
        end
        -- if handler returned a value, pass it to the next Then
        if result ~= nil then current = result end
    end
    for _, finallyFn in ipairs(self._finallyCbs) do
        pcall(finallyFn)
    end
end

local function _runCatch(self: Type, err: any)
    local handled = false
    for _, fn in ipairs(self._catchCbs) do
        local ok, _ = pcall(fn, err)
        if ok then handled = true end
    end
    for _, finallyFn in ipairs(self._finallyCbs) do
        pcall(finallyFn)
    end
    if not handled then
        warn("RoExpress.Promise: Unhandled rejection —", err and err.message or tostring(err))
    end
end

------------------------------------------------------------------------
--  RESOLUTION (called by Network)
------------------------------------------------------------------------

--[[
    _resolve(response)
    Called internally by Network when the server responds successfully.
    Triggers the Then chain.
]]
function Promise:_resolve(response: any): ()
    if self._cancelled or self._state ~= "pending" then return end
    self._state = "resolved"
    self._value = response
    task.spawn(_runChain, self, response)
end

--[[
    _reject(response)
    Called internally by Network when the server responds with an error
    or the request times out. Triggers the Catch chain.
]]
function Promise:_reject(response: any): ()
    if self._cancelled or self._state ~= "pending" then return end
    self._state = "rejected"
    self._value = response
    task.spawn(_runCatch, self, response)
end

------------------------------------------------------------------------
--  PUBLIC API
------------------------------------------------------------------------

--[[
    Then(fn) -> Promise

    Register a handler called when the request resolves successfully.
    The handler receives the NetworkResponse.
    Returning a value from the handler passes it to the next Then.
    Chainable.

    network:Get("player/123")
        :Then(function(res)
            return res.data.coins
        end)
        :Then(function(coins)
            UI:SetCoins(coins)
        end)
]]
function Promise:Then(fn: (value: any) -> any): Type
    assert(type(fn) == "function", "Promise:Then — handler must be a function")

    if self._state == "resolved" then
        -- already resolved — run immediately
        task.spawn(_runChain, self, self._value)
    elseif self._state == "pending" then
        table.insert(self._thenCbs, fn)
    end
    -- if rejected, Then is skipped — falls through to Catch
    return self
end

--[[
    Catch(fn) -> Promise

    Register a handler called when the request fails or times out.
    The handler receives the NetworkResponse (with type = "error").
    Chainable.

    network:Post("stats/save", data)
        :Catch(function(err)
            warn("Failed:", err.status, err.message)
        end)
]]
function Promise:Catch(fn: (err: any) -> any): Type
    assert(type(fn) == "function", "Promise:Catch — handler must be a function")

    if self._state == "rejected" then
        task.spawn(_runCatch, self, self._value)
    elseif self._state == "pending" then
        table.insert(self._catchCbs, fn)
    end
    return self
end

--[[
    Finally(fn) -> Promise

    Register a handler called regardless of whether the request
    resolved or rejected. Use for cleanup — hiding loaders, etc.
    Chainable.

    network:Get("feed/all")
        :Then(function(res) UI:LoadFeed(res.data) end)
        :Catch(function(err) UI:ShowError(err.message) end)
        :Finally(function() UI:HideLoader() end)
]]
function Promise:Finally(fn: () -> ()): Type
    assert(type(fn) == "function", "Promise:Finally — handler must be a function")

    if self._state ~= "pending" then
        task.spawn(fn)
    else
        table.insert(self._finallyCbs, fn)
    end
    return self
end

--[[
    Cancel()

    Cancel a pending request. If the server responds after cancellation
    the handlers will not fire. Note: the server still executes — only
    the client-side resolution is cancelled.
]]
function Promise:Cancel(): ()
    self._cancelled = true
    self._state     = "rejected"
    table.clear(self._thenCbs)
    table.clear(self._catchCbs)
    table.clear(self._finallyCbs)
end

--[[
    IsResolved() -> boolean
    IsPending()  -> boolean
    IsRejected() -> boolean
]]
function Promise:IsResolved(): boolean return self._state == "resolved" end
function Promise:IsPending():  boolean return self._state == "pending"  end
function Promise:IsRejected(): boolean return self._state == "rejected" end

return Promise
