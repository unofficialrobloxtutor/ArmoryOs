------------------------------------------------------------------------
--  <> Title:       RoExpress.Tamper
--  <> Version:     1.0
--  <> Date:        30/05/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Exploit detection and tamper reporting for RoExpress.
--
--  Tamper hooks into App's request pipeline and surfaces suspicious
--  activity as structured reports. Developers subscribe to detection
--  events and optionally enable auto-kick at a strike threshold.
--
--  TWO DETECTION TIERS
--  ────────────────────────────────────────────────────────────────
--  Immediate — single occurrence is enough to act:
--    • VERSION_SPOOF     client version doesn't match server
--    • MALFORMED_PAYLOAD payload structure is invalid
--    • INVALID_PARAM     typed param consistently fails coercion
--    • UNKNOWN_ROUTE     route fired that has never been registered
--
--  Pattern — accumulates before escalating:
--    • RATE_FLOOD        repeated 429s in a short window
--    • ROUTE_SCAN        many different unknown routes fired
--    • PARAM_FLOOD       repeated typed param failures on same route
--
--  INTEGRATION
--  ────────────────────────────────────────────────────────────────
--  Tamper is passive — it receives signals from App via internal
--  hooks rather than wrapping or replacing App methods. App calls
--  Tamper.Signal() at the relevant pipeline points. If Tamper is
--  not required, those calls are no-ops.
--
--  Developers can also call Tamper.Strike() manually from inside
--  their own route handlers for business-logic violations that
--  Tamper cannot detect generically.
--
--  SINGLETON
--  ────────────────────────────────────────────────────────────────
--  Like Bridge, Tamper has no New() — requiring it IS the
--  constructor. RoExpress("Tamper") always returns the same table.
------------------------------------------------------------------------

-->> Services <<--
local Players = game:GetService("Players")

-->> Tables <<--
local Tamper = {}
Tamper.__index = Tamper

-->> Types <<--
export type Severity = "immediate" | "pattern"

export type Reason =
	"VERSION_SPOOF"     |  -- client sent a mismatched ROEXPRESS_VERSION
"MALFORMED_PAYLOAD" |  -- payload failed structure validation
"INVALID_PARAM"     |  -- typed param coercion failed
"UNKNOWN_ROUTE"     |  -- route does not exist on the server
"RATE_FLOOD"        |  -- repeated rate-limit hits in a short window
"ROUTE_SCAN"        |  -- many distinct unknown routes fired
"PARAM_FLOOD"       |  -- repeated param failures on the same route
"MANUAL"               -- developer called Tamper.Strike() directly

export type Report = {
	player    : Player,
	reason    : Reason,
	severity  : Severity,
	route     : string?,
	evidence  : any?,
	strikes   : number,
	firstSeen : number,
	lastSeen  : number,
}

export type PlayerRecord = {
	strikes   : number,
	firstSeen : number,
	lastSeen  : number,
	-- pattern tracking
	rateHits  : { number },  -- timestamps of recent 429s
	unknownRoutes : { [string]: number },  -- route → count
	paramFails    : { [string]: number },  -- route → count
}

--► State        ◄--
Tamper._records   = {}
Tamper._handler   = nil
Tamper._autoKick  = {
	enabled   = false,
	threshold = 10,
	reason    = "Exploiting detected",
}

-- Pattern thresholds
local RATE_FLOOD_WINDOW    = 10   -- seconds
local RATE_FLOOD_THRESHOLD = 5    -- 429s within window = pattern strike
local ROUTE_SCAN_THRESHOLD = 8    -- distinct unknown routes = pattern strike
local PARAM_FLOOD_THRESHOLD= 5    -- repeated param fails on same route = pattern strike

------------------------------------------------------------------------
--	PRIVATE
------------------------------------------------------------------------

local function _getOrCreate(player: Player): PlayerRecord
	local uid = player.UserId
	if not Tamper._records[uid] then
		Tamper._records[uid] = {
			strikes       = 0,
			firstSeen     = tick(),
			lastSeen      = tick(),
			rateHits      = {},
			unknownRoutes = {},
			paramFails    = {},
		}
	end
	return Tamper._records[uid]
end

local function _fire(report: Report)
	if Tamper._handler then
		local ok, err = pcall(Tamper._handler, report)
		if not ok then
			warn("RoExpress.Tamper: Handler error:", err)
		end
	end

	if Tamper._autoKick.enabled then
		if report.strikes >= Tamper._autoKick.threshold then
			if report.player and report.player.Parent ~= nil then
				report.player:Kick(Tamper._autoKick.reason)
			end
		end
	end
end

local function _addStrike(player: Player, reason: Reason, severity: Severity, route: string?, evidence: any?)
	local rec = _getOrCreate(player)
	rec.strikes  += 1
	rec.lastSeen  = tick()

	local report: Report = {
		player    = player,
		reason    = reason,
		severity  = severity,
		route     = route,
		evidence  = evidence,
		strikes   = rec.strikes,
		firstSeen = rec.firstSeen,
		lastSeen  = rec.lastSeen,
	}

	_fire(report)
end

------------------------------------------------------------------------
--	INTERNAL SIGNALS (called by App pipeline hooks)
------------------------------------------------------------------------

--[[
	Signal(event, player, context)

	Called internally by App at pipeline checkpoints.
	Not intended for direct use — use Strike() for manual detections.

	Events App signals:
	  "version_mismatch"  — Payload.version != ROEXPRESS_VERSION
	  "malformed"         — _validatePayload returned false
	  "rate_limited"      — TokenBucket.Consume returned false
	  "unknown_route"     — Router found no match
	  "param_fail"        — typed param coercion failed
]]
function Tamper.Signal(event: string, player: Player, context: { route: string?, evidence: any? }?)
	if not player or player.Parent == nil then return end

	local route    = context and context.route
	local evidence = context and context.evidence

	if event == "version_mismatch" then
		_addStrike(player, "VERSION_SPOOF", "immediate", route, evidence)

	elseif event == "malformed" then
		_addStrike(player, "MALFORMED_PAYLOAD", "immediate", route, evidence)

	elseif event == "rate_limited" then
		local rec = _getOrCreate(player)
		local now = tick()

		-- trim hits outside the window
		local fresh = {}
		for _, t in ipairs(rec.rateHits) do
			if now - t <= RATE_FLOOD_WINDOW then
				table.insert(fresh, t)
			end
		end
		table.insert(fresh, now)
		rec.rateHits = fresh

		if #rec.rateHits >= RATE_FLOOD_THRESHOLD then
			rec.rateHits = {}  -- reset window after escalation
			_addStrike(player, "RATE_FLOOD", "pattern", route, {
				hits   = #fresh,
				window = RATE_FLOOD_WINDOW,
			})
		end

	elseif event == "unknown_route" then
		local rec = _getOrCreate(player)
		local key = route or "?"
		rec.unknownRoutes[key] = (rec.unknownRoutes[key] or 0) + 1

		-- immediate strike on first unknown route hit
		_addStrike(player, "UNKNOWN_ROUTE", "immediate", route, evidence)

		-- pattern strike if scanning many different routes
		local distinct = 0
		for _ in pairs(rec.unknownRoutes) do distinct += 1 end
		if distinct >= ROUTE_SCAN_THRESHOLD then
			rec.unknownRoutes = {}  -- reset after escalation
			_addStrike(player, "ROUTE_SCAN", "pattern", route, {
				distinctRoutes = distinct,
			})
		end

	elseif event == "param_fail" then
		local rec = _getOrCreate(player)
		local key = route or "?"
		rec.paramFails[key] = (rec.paramFails[key] or 0) + 1

		-- immediate strike on param failure
		_addStrike(player, "INVALID_PARAM", "immediate", route, evidence)

		-- pattern strike if repeatedly failing the same route
		if rec.paramFails[key] >= PARAM_FLOOD_THRESHOLD then
			rec.paramFails[key] = 0
			_addStrike(player, "PARAM_FLOOD", "pattern", route, {
				failCount = PARAM_FLOOD_THRESHOLD,
			})
		end
	end
end

------------------------------------------------------------------------
--	PUBLIC API
------------------------------------------------------------------------

--[[
	On(handler)

	Register the detection handler. Only one handler is supported —
	calling On() again replaces the previous handler.
	Called whenever a strike is issued, immediate or pattern.

	tamper:On(function(report)
	    print(report.player.Name, report.reason, report.strikes)
	    if report.severity == "immediate" then
	        -- log it, warn, notify admins
	    end
	end)
]]
function Tamper.On(handler: (report: Report) -> ())
	assert(type(handler) == "function", "RoExpress.Tamper: On — handler must be a function")
	Tamper._handler = handler
end

--[[
	AutoKick(threshold, reason?)

	Enable automatic kick when a player reaches the strike threshold.
	The kick fires after the detection handler runs, so you can log
	before the player is removed.

	tamper:AutoKick(10, "Cheating detected")
]]
function Tamper.AutoKick(threshold: number, reason: string?)
	assert(type(threshold) == "number" and threshold > 0,
		"RoExpress.Tamper: AutoKick — threshold must be a positive number")
	Tamper._autoKick = {
		enabled   = true,
		threshold = threshold,
		reason    = reason or "Exploiting detected",
	}
end

--[[
	Strike(player, reason?, route?, evidence?)

	Manually issue a strike from inside a route handler.
	Use this for business-logic violations Tamper can't detect:
	negative currency, impossible positions, out-of-range values.

	app:Post("shop/buy", function(Player, Payload, req, res)
	    if req.data.amount < 0 then
	        Tamper.Strike(Player, "Negative purchase amount", "shop/buy", req.data)
	        res:Status(400):Error("Invalid amount")
	        return
	    end
	end)
]]
function Tamper.Strike(player: Player, reason: string?, route: string?, evidence: any?)
	assert(player and typeof(player) == "Instance" and player:IsA("Player"),
		"RoExpress.Tamper: Strike — player must be a Player instance")
	_addStrike(player, "MANUAL", "immediate", route, {
		note     = reason or "Manual strike",
		evidence = evidence,
	})
end

--[[
	GetReport(player) → PlayerRecord?

	Returns the full accumulated record for a player, or nil if
	they have no strikes on record.

	local record = tamper:GetReport(player)
	if record then
	    print("Strikes:", record.strikes)
	    print("First seen:", record.firstSeen)
	end
]]
function Tamper.GetReport(player: Player): PlayerRecord?
	return Tamper._records[player.UserId]
end

--[[
	GetStrikes(player) → number

	Returns the current strike count for a player. Returns 0 if
	the player has no record.
]]
function Tamper.GetStrikes(player: Player): number
	local rec = Tamper._records[player.UserId]
	return rec and rec.strikes or 0
end

--[[
	ClearStrikes(player)

	Reset a player's strike count and pattern tracking.
	Useful after a false positive or a manual review.
]]
function Tamper.ClearStrikes(player: Player)
	Tamper._records[player.UserId] = nil
end

--[[
	ClearAll()

	Reset all player records. Useful on round transitions
	where you want a clean slate.
]]
function Tamper.ClearAll()
	table.clear(Tamper._records)
end

--[[
	SetThresholds(config)

	Override the default pattern detection thresholds.

	tamper:SetThresholds({
	    rateFloodWindow    = 10,  -- seconds
	    rateFloodCount     = 5,   -- 429s within window
	    routeScanCount     = 8,   -- distinct unknown routes
	    paramFloodCount    = 5,   -- repeated param fails on same route
	})
]]
function Tamper.SetThresholds(config: {
	rateFloodWindow  : number?,
	rateFloodCount   : number?,
	routeScanCount   : number?,
	paramFloodCount  : number?,
	})
	if config.rateFloodWindow  then RATE_FLOOD_WINDOW     = config.rateFloodWindow  end
	if config.rateFloodCount   then RATE_FLOOD_THRESHOLD  = config.rateFloodCount   end
	if config.routeScanCount   then ROUTE_SCAN_THRESHOLD  = config.routeScanCount   end
	if config.paramFloodCount  then PARAM_FLOOD_THRESHOLD = config.paramFloodCount  end
end

--[[
	Destroy()

	Clear all records and remove the detection handler.
]]
function Tamper.Destroy()
	table.clear(Tamper._records)
	Tamper._handler  = nil
	Tamper._autoKick = { enabled = false, threshold = 10, reason = "Exploiting detected" }
end

------------------------------------------------------------------------
--	PLAYER CLEANUP
------------------------------------------------------------------------
Players.PlayerRemoving:Connect(function(player)
	Tamper._records[player.UserId] = nil
end)

return Tamper
