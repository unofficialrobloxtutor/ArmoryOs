------------------------------------------------------------------------
--  <> Title:       RoExpress.Debounce
--  <> Version:     1.0
--  <> Date:        15/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Cooldown / debounce wrappers.
--
--  Two wrappers covering the two real game use cases:
--
--  Debounce.fn   — global cooldown on a function
--  Debounce.key  — per-key cooldown, first argument is the key
--                  (most useful for per-player rate limiting)
--
--  Both return a wrapped function that returns true when the call
--  went through, or false when it was on cooldown.
--
--  USAGE
--  ────────────────────────────────────────────────────────────────
--    local Debounce = RoExpress.Debounce
--
--    -- Global cooldown — only one shot per 0.5s regardless of caller
--    local onShoot = Debounce.fn(function(player, data)
--        -- fire bullet
--    end, 0.5)
--
--    onShoot(player, data)  -- true if fired, false if cooling down
--
--    -- Per-player cooldown — each player has their own 0.5s timer
--    local onShoot = Debounce.key(function(player, data)
--        -- fire bullet
--    end, 0.5)
--
--    onShoot(player, data)  -- player is the key
------------------------------------------------------------------------

local Debounce = {}

-- Wraps fn with a single shared cooldown.
-- Returns a function that returns true when fn fires, false when cooling.
function Debounce.fn<T...>(fn: (T...) -> (), cooldown: number): (T...) -> boolean
	assert(type(fn)       == "function", "[RoExpress.Debounce] fn — fn must be a function")
	assert(type(cooldown) == "number",   "[RoExpress.Debounce] fn — cooldown must be a number")
	local last = 0
	return function(...: any): boolean
		local now = os.clock()
		if now - last < cooldown then return false end
		last = now
		fn(...)
		return true
	end
end

-- Wraps fn with a per-key cooldown. The first argument is used as
-- the key — typically a Player, userId, or string tag.
-- Returns a function that returns true when fn fires, false when cooling.
function Debounce.key<K, T...>(fn: (key: K, T...) -> (), cooldown: number): (key: K, T...) -> boolean
	assert(type(fn)       == "function", "[RoExpress.Debounce] key — fn must be a function")
	assert(type(cooldown) == "number",   "[RoExpress.Debounce] key — cooldown must be a number")
	local last: { [any]: number } = {}
	return function(key: any, ...: any): boolean
		local now = os.clock()
		if now - (last[key] or 0) < cooldown then return false end
		last[key] = now
		fn(key, ...)
		return true
	end
end

function Debounce.default<T...>(fn: (Value: boolean,T...) -> ())
	assert(type(fn)       == "function", "[RoExpress.Debounce] key — fn must be a function")
	
	local deb = false
	return function(...)
		deb = not deb
		local newdeb = fn(deb, ...)
		if newdeb ~= nil and typeof(newdeb) == "boolean" then
			deb = newdeb
		end
		return deb
	end
end


return Debounce
