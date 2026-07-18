------------------------------------------------------------------------
--  <> Title:       RoExpress.Benchmark
--  <> Version:     2.5
--  <> Date:        10/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Round-trip benchmarking for RoExpress routes and
--                  vanilla Roblox RemoteEvent / RemoteFunction.
--
--  Fires real requests and measures wall-clock round-trip time.
--  All timing includes serialisation, network, handler execution,
--  and deserialisation.
--
--  QUICK START
--  ──────────────────────────────────────────────────────────────────
--  local bench = RoExpress("Benchmark")
--
--  -- RoExpress main channel
--  bench:RunAndPrint("player/123", { method = "GET", iterations = 20 })
--
--  -- RoExpress named port
--  local portNet = RoExpress("Network", "combat")
--  bench:RunOnPort(portNet, "shoot/123", { method = "POST" })
--
--  -- Vanilla RemoteFunction (full round-trip)
--  local rf = game:GetService("ReplicatedStorage"):WaitForChild("EchoFunc")
--  bench:RunRemoteFunction(rf, { args = { "hello" }, iterations = 20 })
--
--  -- Vanilla RemoteEvent (fire timing — no round-trip)
--  local re = game:GetService("ReplicatedStorage"):WaitForChild("FireEvent")
--  bench:RunRemoteEvent(re, { args = { "hello" }, iterations = 20 })
--
--  -- Compare all side-by-side
--  bench:Compare({ r1, r2, r3, r4 })
--
--  OUTPUT (Run / RunOnPort / RunRemoteFunction)
--  ──────────────────────────────────────────────────────────────────
--  ── player/123   [RoExpress GET] × 20  (warmup: 3) ────────────────
--    min          4.21 ms
--    avg          6.83 ms
--    median       6.10 ms
--    p95         12.44 ms
--    p99         18.07 ms
--    max         18.71 ms
--  ──────────────────────────────────────────────────────────────────
--    errors       0 / 20
--    throughput   8.3 req/s
--  ──────────────────────────────────────────────────────────────────
------------------------------------------------------------------------
-->> Tables <<--
local Benchmark = {}
Benchmark.__index = Benchmark
-->> Variables <<--
local Network = require(script.Parent.Network)  -- for type only

------------------------------------------------------------------------
--  TYPES
------------------------------------------------------------------------
export type Config = {
    method     : ("GET" | "POST" | "PUT" | "DELETE")?,
    data       : any?,
    args       : { any }?,      -- arguments for vanilla RemoteEvent / RemoteFunction
    iterations : number?,
    warmup     : number?,
    interval   : number?,
    timeout    : number?,
    label      : string?,
}

export type Results = {
    label      : string,
    target     : string,        -- "RoExpress" | "RoExpress Port" | "RemoteEvent" | "RemoteFunction"
    route      : string,
    method     : string,        -- GET/POST/PUT/DELETE/fire/invoke
    iterations : number,
    completed  : number,
    errors     : number,
    errorCodes : { [number]: number },
    warmup     : number,
    min        : number,
    max        : number,
    avg        : number,
    median     : number,
    p95        : number,
    p99        : number,
    total      : number,
    throughput : number,
}

export type Type = typeof(setmetatable({}, Benchmark)) & {
    _network: Network.Type,
}

------------------------------------------------------------------------
--  PRIVATE HELPERS
------------------------------------------------------------------------
local function _pct(sorted: { number }, p: number): number
    if #sorted == 0 then return 0 end
    return sorted[math.clamp(math.ceil(#sorted * p), 1, #sorted)]
end

local function _fmt(n: number): string
    return string.format("%.2f ms", n)
end

-- Fire a RoExpress Network request and return the response synchronously.
-- The Network callback form blocks via coroutine resumption.
local function _fireNetwork(network: Network.Type, method: string, route: string, data: any, timeout: number?)
    if method == "POST" then
        return network:Post(route, data, nil, timeout)
    elseif method == "PUT" then
        return network:Put(route, data, nil, timeout)
    elseif method == "DELETE" then
        return network:Delete(route, data, nil, timeout)
    end
    return network:Get(route, data, nil, timeout)
end

-- Shared timed loop. `measureFn` returns (elapsedMs, hadError, errorCode?).
local function _loop(
    measureFn : () -> (number, boolean, number?),
    iterations: number,
    warmup    : number,
    interval  : number
): (number, { number }, number, { [number]: number })
    for _ = 1, warmup do
        measureFn()
        if interval > 0 then task.wait(interval) end
    end

    local times:      { number }          = {}
    local errors:     number              = 0
    local errorCodes: { [number]: number } = {}
    local wallStart = os.clock()

    for _ = 1, iterations do
        local elapsed, hadError, code = measureFn()
        table.insert(times, elapsed)
        if hadError then
            errors += 1
            if code then
                errorCodes[code] = (errorCodes[code] or 0) + 1
            end
        end
        if interval > 0 then task.wait(interval) end
    end

    local wallMs = (os.clock() - wallStart) * 1000
    table.sort(times)
    return wallMs, times, errors, errorCodes
end

-- Build a Results table from the raw loop output.
local function _buildResults(
    label     : string,
    target    : string,
    route     : string,
    method    : string,
    iterations: number,
    warmup    : number,
    wallMs    : number,
    times     : { number },
    errors    : number,
    errorCodes: { [number]: number }
): Results
    local n = #times
    local sum = 0
    for _, t in ipairs(times) do sum += t end
    return {
        label      = label,
        target     = target,
        route      = route,
        method     = method,
        iterations = iterations,
        completed  = n,
        errors     = errors,
        errorCodes = errorCodes,
        warmup     = warmup,
        min        = n > 0 and times[1]     or 0,
        max        = n > 0 and times[n]     or 0,
        avg        = n > 0 and sum / n      or 0,
        median     = _pct(times, 0.50),
        p95        = _pct(times, 0.95),
        p99        = _pct(times, 0.99),
        total      = wallMs,
        throughput = wallMs > 0 and (n / (wallMs / 1000)) or 0,
    }
end

------------------------------------------------------------------------
--  CONSTRUCTOR
------------------------------------------------------------------------
function Benchmark.New(network: Network.Type): Type
    local self    = setmetatable({}, Benchmark) :: Type
    self._network = network
    return self
end

------------------------------------------------------------------------
--  PUBLIC API — RoExpress routes
------------------------------------------------------------------------

--[[
    Run(route, config?) -> Results

    Benchmarks a route on the main RoExpress channel.
    Supports GET, POST, PUT, DELETE (config.method, default "GET").

    Config defaults:
        method     = "GET"
        iterations = 20
        warmup     = 3
        interval   = 0      -- seconds between requests (0 = sequential)
        timeout    = nil    -- per-request timeout passed to Network
]]
function Benchmark:Run(route: string, config: Config?): Results
    local cfg        = config or {}
    local method     = (cfg.method or "GET"):upper()
    local data       = cfg.data
    local iterations = cfg.iterations or 20
    local warmup     = cfg.warmup     or 3
    local interval   = cfg.interval   or 0
    local timeout    = cfg.timeout
    local label      = cfg.label      or route

    assert(iterations > 0, "Benchmark: iterations must be > 0")
    assert(warmup >= 0,    "Benchmark: warmup must be >= 0")

    local net = self._network
    local function measure(): (number, boolean, number?)
        local t0 = os.clock()
        local _, response = _fireNetwork(net, method, route, data, timeout)
        local elapsed = (os.clock() - t0) * 1000
        local hadError = response and response.type == "error"
        local code = hadError and (response.status or 0) or nil
        return elapsed, hadError == true, code
    end

    local wallMs, times, errors, errorCodes = _loop(measure, iterations, warmup, interval)
    return _buildResults(label, "RoExpress", route, method, iterations, warmup, wallMs, times, errors, errorCodes)
end

--[[
    RunOnPort(portNetwork, route, config?) -> Results

    Benchmarks a route on a named port channel. Pass the Network
    instance for that port:

        local portNet = RoExpress("Network", "combat")
        bench:RunOnPort(portNet, "shoot/123", { method = "POST" })
]]
function Benchmark:RunOnPort(portNetwork: Network.Type, route: string, config: Config?): Results
    local cfg        = config or {}
    local method     = (cfg.method or "GET"):upper()
    local data       = cfg.data
    local iterations = cfg.iterations or 20
    local warmup     = cfg.warmup     or 3
    local interval   = cfg.interval   or 0
    local timeout    = cfg.timeout
    local label      = cfg.label      or route

    assert(iterations > 0, "Benchmark: iterations must be > 0")
    assert(warmup >= 0,    "Benchmark: warmup must be >= 0")

    local function measure(): (number, boolean, number?)
        local t0 = os.clock()
        local _, response = _fireNetwork(portNetwork, method, route, data, timeout)
        local elapsed = (os.clock() - t0) * 1000
        local hadError = response and response.type == "error"
        local code = hadError and (response.status or 0) or nil
        return elapsed, hadError == true, code
    end

    local wallMs, times, errors, errorCodes = _loop(measure, iterations, warmup, interval)
    return _buildResults(label, "RoExpress Port", route, method, iterations, warmup, wallMs, times, errors, errorCodes)
end

------------------------------------------------------------------------
--  PUBLIC API — vanilla Roblox remotes
------------------------------------------------------------------------

--[[
    RunRemoteFunction(remote, config?) -> Results

    Full round-trip benchmark against a vanilla RemoteFunction.
    Uses pcall(remote:InvokeServer(...)) — errors counted on pcall failure.

        local rf = RS:WaitForChild("EchoFunc")
        bench:RunRemoteFunction(rf, { args = { "hello" }, iterations = 30 })
]]
function Benchmark:RunRemoteFunction(remote: RemoteFunction, config: Config?): Results
    local cfg        = config or {}
    local args       = cfg.args       or {}
    local iterations = cfg.iterations or 20
    local warmup     = cfg.warmup     or 3
    local interval   = cfg.interval   or 0
    local label      = cfg.label      or remote.Name

    assert(iterations > 0, "Benchmark: iterations must be > 0")
    assert(warmup >= 0,    "Benchmark: warmup must be >= 0")

    local function measure(): (number, boolean, number?)
        local t0 = os.clock()
        local ok = pcall(function()
            remote:InvokeServer(table.unpack(args))
        end)
        local elapsed = (os.clock() - t0) * 1000
        return elapsed, not ok, ok and nil or 0
    end

    local wallMs, times, errors, errorCodes = _loop(measure, iterations, warmup, interval)
    return _buildResults(label, "RemoteFunction", remote.Name, "invoke", iterations, warmup, wallMs, times, errors, errorCodes)
end

--[[
    RunRemoteEvent(remote, config?) -> Results

    Fire-only timing for a vanilla RemoteEvent.
    NOTE: RemoteEvent:FireServer is non-blocking — this measures client-side
    fire overhead only, not round-trip. Use RunRemoteFunction for a fair
    comparison against RoExpress routes.

        local re = RS:WaitForChild("MyEvent")
        bench:RunRemoteEvent(re, { args = { "hello" }, iterations = 100 })
]]
function Benchmark:RunRemoteEvent(remote: RemoteEvent, config: Config?): Results
    local cfg        = config or {}
    local args       = cfg.args       or {}
    local iterations = cfg.iterations or 20
    local warmup     = cfg.warmup     or 3
    local interval   = cfg.interval   or 0
    local label      = cfg.label      or remote.Name

    assert(iterations > 0, "Benchmark: iterations must be > 0")
    assert(warmup >= 0,    "Benchmark: warmup must be >= 0")

    local function measure(): (number, boolean, number?)
        local t0 = os.clock()
        remote:FireServer(table.unpack(args))
        local elapsed = (os.clock() - t0) * 1000
        return elapsed, false, nil
    end

    local wallMs, times, errors, errorCodes = _loop(measure, iterations, warmup, interval)
    return _buildResults(label, "RemoteEvent (fire only)", remote.Name, "fire", iterations, warmup, wallMs, times, errors, errorCodes)
end

------------------------------------------------------------------------
--  OUTPUT
------------------------------------------------------------------------

--[[
    Print(results)

    Prints a formatted summary to the output window.
    Header shows target type and method for clarity.
]]
function Benchmark:Print(results: Results): ()
    local bar  = "── " .. string.rep("─", 54)
    local thin = "   " .. string.rep("─", 54)

    local function row(k: string, v: string)
        print(string.format("   %-12s %s", k, v))
    end

    local tag = string.format("[%s %s]", results.target, results.method)

    print("")
    print(string.format("%s  %s  %s × %d  (warmup: %d)",
        bar, results.label, tag, results.iterations, results.warmup))
    print(thin)
    row("min",    _fmt(results.min))
    row("avg",    _fmt(results.avg))
    row("median", _fmt(results.median))
    row("p95",    _fmt(results.p95))
    row("p99",    _fmt(results.p99))
    row("max",    _fmt(results.max))
    print(thin)

    local errStr = results.errors .. " / " .. results.iterations
    if results.errors > 0 then
        local parts: { string } = {}
        for code, count in pairs(results.errorCodes) do
            table.insert(parts, count .. " x " .. code)
        end
        table.sort(parts)
        errStr = errStr .. "   (" .. table.concat(parts, ", ") .. ")"
    end

    row("errors",     errStr)
    row("throughput", string.format("%.1f req/s", results.throughput))
    print(bar .. "\n")
end

--[[
    RunAndPrint(route, config?) -> Results

    Convenience wrapper — runs the benchmark and immediately prints results.
]]
function Benchmark:RunAndPrint(route: string, config: Config?): Results
    local results = self:Run(route, config)
    self:Print(results)
    return results
end

--[[
    Compare(results)

    Prints multiple Results side-by-side. Useful for comparing RoExpress
    routes against each other or against vanilla remotes.

        bench:Compare({
            bench:Run("player/:id",   { label = "RoExpress GET" }),
            bench:RunRemoteFunction(rf, { label = "Vanilla RF"  }),
        })
]]
function Benchmark:Compare(resultSet: { Results }): ()
    assert(#resultSet > 0, "Benchmark:Compare — resultSet is empty")

    local COL = 16
    local bar  = "── " .. string.rep("─", 10 + COL * #resultSet)
    local thin = "   " .. string.rep("─", 10 + COL * #resultSet)

    print("")
    local header = string.format("   %-10s", "metric")
    for _, r in ipairs(resultSet) do
        header = header .. string.format("  %-" .. COL .. "s", r.label)
    end
    print(bar)
    print(header)
    print(thin)

    local metrics: { { label: string, key: string } } = {
        { label = "min",    key = "min"    },
        { label = "avg",    key = "avg"    },
        { label = "median", key = "median" },
        { label = "p95",    key = "p95"    },
        { label = "p99",    key = "p99"    },
        { label = "max",    key = "max"    },
    }

    for _, m in ipairs(metrics) do
        local line = string.format("   %-10s", m.label)
        for _, r in ipairs(resultSet) do
            line = line .. string.format("  %-" .. COL .. "s", _fmt((r :: any)[m.key]))
        end
        print(line)
    end

    print(thin)

    local errLine = string.format("   %-10s", "errors")
    for _, r in ipairs(resultSet) do
        errLine = errLine .. string.format("  %-" .. COL .. "s", r.errors .. "/" .. r.iterations)
    end
    print(errLine)

    local tpLine = string.format("   %-10s", "req/s")
    for _, r in ipairs(resultSet) do
        tpLine = tpLine .. string.format("  %-" .. COL .. "s", string.format("%.1f", r.throughput))
    end
    print(tpLine)

    local targetLine = string.format("   %-10s", "target")
    for _, r in ipairs(resultSet) do
        targetLine = targetLine .. string.format("  %-" .. COL .. "s", r.target)
    end
    print(targetLine)

    print(bar .. "\n")
end

--[[
    Destroy()

    Clears the internal Network reference. Does NOT destroy the Network
    instance — the caller owns it.
]]
function Benchmark:Destroy(): ()
    self._network = nil :: any
end

return Benchmark
