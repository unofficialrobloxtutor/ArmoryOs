------------------------------------------------------------------------
--  <> Title:       RoExpress.RTTP
--  <> Version:     1.0
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Outbound HTTP client for server-to-external-API calls.
--
--  Wraps HttpService:RequestAsync with:
--    - persistent base URL and headers set once, reused on every call
--    - automatic retry with exponential backoff (1s → 2s → 4s)
--    - consistent response shape  { ok, status, data, headers, raw }
--    - chainable Promise API via GetAsync / PostAsync / PutAsync / DeleteAsync
--
--  USAGE
--  ---------------------------------------------------------------
--  local RTTP  = RoExpress.RTTP                    -- module reference
--  local client = RTTP.New({ base = "https://api.example.com" })
--
--  client:SetHeader("Authorization", "Bearer " .. SECRET)
--
--  -- Callback style:
--  client:Get("/players/123", function(res)
--      if res.ok then print(res.data.name) end
--  end)
--
--  -- Promise style:
--  client:GetAsync("/leaderboard")
--      :Then(function(res) return res.data end)
--      :Catch(function(err) warn(err.message) end)
--
--  RESPONSE SHAPE
--  ---------------------------------------------------------------
--  {
--      ok      : boolean                -- true if 2xx
--      status  : number                 -- HTTP status code
--      data    : any                    -- JSON-decoded body (or raw string)
--      headers : { [string]: string }   -- response headers
--      raw     : string                 -- raw response body
--  }
--
--  SERVER ONLY — HttpService:RequestAsync is not available on clients.
------------------------------------------------------------------------

local HttpService = game:GetService("HttpService")
local Promise     = require(script.Parent.Promise)

local RTTP = {}
RTTP.__index = RTTP

------------------------------------------------------------------------
--  TYPES
------------------------------------------------------------------------
export type Config = {
	base    : string?,
	headers : { [string]: string }?,
	retries : number?,
}

export type Response = {
	ok      : boolean,
	status  : number,
	data    : any,
	headers : { [string]: string },
	raw     : string,
}

export type Type = typeof(setmetatable({}, RTTP)) & {
	_base    : string,
	_headers : { [string]: string },
	_retries : number,
}

------------------------------------------------------------------------
--  PRIVATE HELPERS
------------------------------------------------------------------------
local function _tryDecode(body: string): any
	if body == "" then return nil end
	local ok, result = pcall(HttpService.JSONDecode, HttpService, body)
	return ok and result or body
end

local function _buildUrl(base: string, path: string): string
	if base == "" then return path end
	local baseEnds  = base:sub(-1) == "/"
	local pathStarts = path:sub(1, 1) == "/"
	if baseEnds and pathStarts then
		return base .. path:sub(2)
	elseif not baseEnds and not pathStarts then
		return base .. "/" .. path
	end
	return base .. path
end

local function _makeResponse(body: string, code: number, hdrs: { [string]: string }): Response
	return {
		ok      = code >= 200 and code < 300,
		status  = code,
		data    = _tryDecode(body),
		headers = hdrs or {},
		raw     = body,
	}
end

------------------------------------------------------------------------
--  CORE REQUEST  (blocking, runs inside task.spawn)
------------------------------------------------------------------------
local function _request(self: Type, method: string, path: string, body: any?): Response
	local url     = _buildUrl(self._base, path)
	local headers = {}
	for k, v in pairs(self._headers) do
		headers[k] = v
	end

	local bodyStr = ""
	if body ~= nil then
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, body)
		bodyStr = ok and encoded or tostring(body)
		if not headers["Content-Type"] then
			headers["Content-Type"] = "application/json"
		end
	end

	local cfg = {
		Url     = url,
		Method  = method,
		Headers = headers,
		Body    = bodyStr ~= "" and bodyStr or nil,
	}

	local maxAttempts = self._retries + 1
	for attempt = 1, maxAttempts do
		local ok, result = pcall(HttpService.RequestAsync, HttpService, cfg)

		if ok then
			local res = _makeResponse(result.Body or "", result.StatusCode, result.Headers)
			-- only retry on 5xx
			if res.ok or result.StatusCode < 500 or attempt >= maxAttempts then
				return res
			end
		elseif attempt >= maxAttempts then
			-- all retries exhausted; return synthetic failure
			break
		end

		task.wait(2 ^ (attempt - 1))
	end

	return { ok = false, status = 0, data = nil, headers = {}, raw = "" }
end

------------------------------------------------------------------------
--  CONSTRUCTOR
------------------------------------------------------------------------
function RTTP.New(config: Config?): Type
	local self = setmetatable({}, RTTP) :: Type
	local cfg  = config or {}
	self._base    = cfg.base    or ""
	self._retries = cfg.retries or 3
	self._headers = {}

	if cfg.headers then
		for k, v in pairs(cfg.headers) do
			self._headers[k] = v
		end
	end

	return self
end

------------------------------------------------------------------------
--  CONFIGURATION
------------------------------------------------------------------------

--[[  SetBase(url)  — set or update the base URL. ]]
function RTTP:SetBase(url: string)
	self._base = url
end

--[[  SetHeader(key, value)  — add a persistent header sent on every request. ]]
function RTTP:SetHeader(key: string, value: string)
	self._headers[key] = value
end

--[[  RemoveHeader(key)  — remove a persistent header. ]]
function RTTP:RemoveHeader(key: string)
	self._headers[key] = nil
end

--[[  SetRetries(n)  — change max retry count (default 3). ]]
function RTTP:SetRetries(n: number)
	self._retries = n
end

------------------------------------------------------------------------
--  CALLBACK STYLE
------------------------------------------------------------------------

--[[
	Get(path, callback?)
	Fire a GET request. Callback receives the Response when done.

	client:Get("/players/123", function(res)
	    if res.ok then print(res.data.name) end
	end)
]]
function RTTP:Get(path: string, callback: ((res: Response) -> ())?): ()
	task.spawn(function()
		local res = _request(self, "GET", path)
		if callback then callback(res) end
	end)
end

--[[
	Post(path, body, callback?)
	Fire a POST request with an optional body table (JSON-encoded automatically).

	client:Post("/events", { type = "round_end", winner = "Player1" }, function(res)
	    print(res.status)
	end)
]]
function RTTP:Post(path: string, body: any, callback: ((res: Response) -> ())?): ()
	task.spawn(function()
		local res = _request(self, "POST", path, body)
		if callback then callback(res) end
	end)
end

--[[  Put(path, body, callback?)  — fire a PUT request. ]]
function RTTP:Put(path: string, body: any, callback: ((res: Response) -> ())?): ()
	task.spawn(function()
		local res = _request(self, "PUT", path, body)
		if callback then callback(res) end
	end)
end

--[[  Delete(path, callback?)  — fire a DELETE request. ]]
function RTTP:Delete(path: string, callback: ((res: Response) -> ())?): ()
	task.spawn(function()
		local res = _request(self, "DELETE", path)
		if callback then callback(res) end
	end)
end

------------------------------------------------------------------------
--  PROMISE STYLE
------------------------------------------------------------------------
local function _async(self: Type, method: string, path: string, body: any?): Promise.Type
	local p = Promise.New()
	task.spawn(function()
		local res = _request(self, method, path, body)
		if res.ok then
			p:_resolve(res)
		else
			p:_reject({
				message  = "HTTP " .. res.status,
				status   = res.status,
				type     = "http",
				response = res,
			})
		end
	end)
	return p
end

--[[
	GetAsync(path) -> Promise
	Returns a chainable Promise. Resolves with the Response on 2xx,
	rejects with { message, status, response } on failure.

	client:GetAsync("/leaderboard")
	    :Then(function(res) return res.data end)
	    :Catch(function(err) warn(err.message) end)
]]
function RTTP:GetAsync(path: string): Promise.Type
	return _async(self, "GET", path)
end

--[[  PostAsync(path, body) -> Promise ]]
function RTTP:PostAsync(path: string, body: any): Promise.Type
	return _async(self, "POST", path, body)
end

--[[  PutAsync(path, body) -> Promise ]]
function RTTP:PutAsync(path: string, body: any): Promise.Type
	return _async(self, "PUT", path, body)
end

--[[  DeleteAsync(path) -> Promise ]]
function RTTP:DeleteAsync(path: string): Promise.Type
	return _async(self, "DELETE", path)
end

return RTTP
