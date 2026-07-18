------------------------------------------------------------------------
--  <> Title:       RoExpress.Version
--  <> Version:     1.0
--  <> Date:        30/05/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Single source of truth for the RoExpress version.
--
--  This is the ONLY module that writes shared.ROEXPRESS_VERSION.
--  All other modules read from shared — never write to it.
--
--  To bump the version:
--    1. Change VERSION below
--    2. Bump wally.toml to match
--    3. Done — App and Network stay in sync automatically
--
--  HISTORY
--  ---------------------------------------------------------------
--  2.2.0   TypeCoercer, Promise, new Router types
--  2.1.0   Stream, Port, optional Network callbacks
--  2.0.0   Router, Push, Codec, Bridge, Tamper, TokenBucket rewrite
--  1.6.0   Initial release
------------------------------------------------------------------------

------------------------------------------------------------------------
--  <> Title:       RoExpress.Version
--  <> Version:     1.1
--  <> Date:        30/05/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Single source of truth for the RoExpress version.
--
--  This is the ONLY module that writes shared.ROEXPRESS_VERSION.
--  All other modules read from shared — never write to it.
--
--  To bump the version:
--    1. Change VERSION below
--    2. Bump wally.toml to match
--    3. Done — App and Network stay in sync automatically
--
--  VERSION CHECK
--  ---------------------------------------------------------------
--  On require, a silent background check fires automatically.
--  It pings roexpress.dev/version.json first, falls back to GitHub
--  raw file if that fails. If a newer version is available, a
--  formatted warning is printed to the output.
--
--  Developers can also call Version.Check() manually for a full
--  report including changelog URL and Wally install string.
--
--  HISTORY
--  ---------------------------------------------------------------
--  2.5.0   Types module, lazy loading, pre-baked remotes, Bridge v2 (On/Once/Emit/Clear/Connection), Maid, Debounce
--  2.4.0   Stream rebuilt, Deflate, retry, res:Redirect, full typing, Router digit-type fix
--  2.3.0   PUT/DELETE, compact (req,res) handler form
--  2.2.3   Patch — wally.toml packaging fix (issue #6)
--  2.2.0   TypeCoercer, Promise, new Router types, Version module
--  2.1.0   Stream, Port, optional Network callbacks
--  2.0.0   Router, Push, Codec, Bridge, Tamper, TokenBucket rewrite
--  1.6.0   Initial release
------------------------------------------------------------------------
-->> Services <<--
local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")

------------------------------------------------------------------------
--  VERSION
------------------------------------------------------------------------
local VERSION = "2.5.0"

-- Write once to shared — assert catches any accidental double-write
assert(
    shared.ROEXPRESS_VERSION == nil or shared.ROEXPRESS_VERSION == VERSION,
    "RoExpress.Version: shared.ROEXPRESS_VERSION was already set to '"
        .. tostring(shared.ROEXPRESS_VERSION)
        .. "' — only Version.luau should write this value"
)

shared.ROEXPRESS_VERSION = VERSION

------------------------------------------------------------------------
--  ENDPOINTS
------------------------------------------------------------------------
local ENDPOINTS = {
    "https://roexpress.dev/version.json",
    "https://raw.githubusercontent.com/unofficialrobloxtutor/RoExpress/main/version.json",
}

local FALLBACK_LUAU =
    "https://raw.githubusercontent.com/unofficialrobloxtutor/RoExpress/main/src/Version.luau"

------------------------------------------------------------------------
--  PRIVATE
------------------------------------------------------------------------

-- Semver compare: returns true if b is newer than a
local function _isNewer(a: string, b: string): boolean
    local function parts(v)
        local maj, min, pat = v:match("^(%d+)%.(%d+)%.(%d+)")
        return tonumber(maj) or 0, tonumber(min) or 0, tonumber(pat) or 0
    end
    local amaj, amin, apat = parts(a)
    local bmaj, bmin, bpat = parts(b)
    if bmaj ~= amaj then return bmaj > amaj end
    if bmin ~= amin then return bmin > amin end
    return bpat > apat
end

-- Try to fetch the latest version string from any endpoint
local function _fetchLatest(): (string?, string?)
    -- try JSON endpoints first
    for _, url in ipairs(ENDPOINTS) do
        local ok, res = pcall(HttpService.RequestAsync, HttpService, {
            Url     = url,
            Method  = "GET",
            Headers = { ["Cache-Control"] = "no-cache" },
        })
        if ok and res.Success then
            local decoded = pcall(function()
                return HttpService:JSONDecode(res.Body)
            end)
            local data
            pcall(function() data = HttpService:JSONDecode(res.Body) end)
            if data and data.version then
                return data.version, url
            end
        end
    end

    -- fall back to parsing raw Version.luau from GitHub
    local ok, res = pcall(HttpService.RequestAsync, HttpService, {
        Url     = FALLBACK_LUAU,
        Method  = "GET",
        Headers = { ["Cache-Control"] = "no-cache" },
    })
    if ok and res.Success then
        local v = res.Body:match('local VERSION = "([^"]+)"')
        if v then return v, FALLBACK_LUAU end
    end

    return nil, nil
end

local function _formatReport(latest: string, source: string): string
    return string.format(
        "\n" ..
        "╔══════════════════════════════════════════════════╗\n" ..
        "║  RoExpress Update Available                      ║\n" ..
        "╠══════════════════════════════════════════════════╣\n" ..
        "║  Current : %-38s║\n" ..
        "║  Latest  : %-38s║\n" ..
        "╠══════════════════════════════════════════════════╣\n" ..
        "║  Wally:                                          ║\n" ..
        '║  RoExpress = "unofficialrobloxtutor/roexpress    ║\n' ..
        "║              @%-35s║\n" ..
        "║  Docs    : https://roexpress.dev                 ║\n" ..
        "╚══════════════════════════════════════════════════╝",
        VERSION .. " ",
        latest  .. " ",
        latest  .. '"'
    )
end

------------------------------------------------------------------------
--  PUBLIC API
------------------------------------------------------------------------

local Version = {}

Version.current = VERSION

--[[
    Check() -> { current, latest, upToDate, source }

    Manually trigger a version check. Prints a formatted report to
    output if an update is available. Returns a result table.

    local result = Version.Check()
    if not result.upToDate then
        print("Update available:", result.latest)
    end
]]
function Version.Check(): { current: string, latest: string?, upToDate: boolean, source: string? }
    if not RunService:IsServer() then
        warn("RoExpress.Version.Check: version checks should only run on the server")
        return { current = VERSION, latest = nil, upToDate = true, source = nil }
    end

    local latest, source = _fetchLatest()

    if not latest then
        warn("RoExpress.Version: Could not reach version endpoints — check HttpService is enabled")
        return { current = VERSION, latest = nil, upToDate = true, source = nil }
    end

    local upToDate = not _isNewer(VERSION, latest)

    if not upToDate then
        warn(_formatReport(latest, source))
    else
        print(string.format(
            "[RoExpress] v%s — up to date ✓",
            VERSION
        ))
    end

    return {
        current  = VERSION,
        latest   = latest,
        upToDate = upToDate,
        source   = source,
    }
end

------------------------------------------------------------------------
--  AUTO SILENT CHECK (server only, background task)
------------------------------------------------------------------------
if RunService:IsServer() then
    task.defer(function()
        -- small delay so game startup completes first
        task.wait(5)

        local latest, source = _fetchLatest()
        if not latest then return end  -- silent — no output on network failure

        if _isNewer(VERSION, latest) then
            warn(_formatReport(latest, source))
        end
    end)
end

------------------------------------------------------------------------
--  RETURN
------------------------------------------------------------------------
-- Return both the version string and the Version table so callers
-- can either use it as a simple string or access Check()
return setmetatable(Version, {
    __tostring = function() return VERSION end,
    __index    = function(_, k) if k == "version" then return VERSION end end,
})