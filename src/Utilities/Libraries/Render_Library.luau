--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Render_Library
--  ◄► Version:     1.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable RunService handler — named
--                  RenderStepped/Heartbeat/Stepped bindings, throttled
--                  and frame-skipped updates, one-shot next-frame calls,
--                  pause/resume, and delta-time smoothing.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local RunService = game:GetService("RunService")
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
local boundNames    = {} :: {[string]: RBXScriptConnection}
local paused        = {} :: {[string]: boolean}
local frameCount    = 0
local startTime     = os.clock()
--► Constants    ◄--
Module.DefaultPriority = Enum.RenderPriority.Last.Value

RunService.Heartbeat:Connect(function()
	frameCount += 1
end)

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	BINDING
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Binds a named callback to RunService:RenderStepped (client-only, runs before camera render)
-- Overwrites any existing binding under the same name
Module.BindRenderStep = function(name: string, priority: number?, callback: (dt: number) -> ())
	Module.Unbind(name)
	RunService:BindToRenderStep(name, priority or Module.DefaultPriority, function(dt: number)
		if paused[name] then return end
		callback(dt)
	end)
	boundNames[name] = "RenderStep" :: any -- marker; unbound via RunService:UnbindFromRenderStep
end

--► Binds a named callback to RunService.Heartbeat (server + client, runs after physics)
Module.BindHeartbeat = function(name: string, callback: (dt: number) -> ())
	Module.Unbind(name)
	boundNames[name] = RunService.Heartbeat:Connect(function(dt: number)
		if paused[name] then return end
		callback(dt)
	end)
end

--► Binds a named callback to RunService.Stepped (client-only, runs before physics)
Module.BindStepped = function(name: string, callback: (time: number, dt: number) -> ())
	Module.Unbind(name)
	boundNames[name] = RunService.Stepped:Connect(function(time: number, dt: number)
		if paused[name] then return end
		callback(time, dt)
	end)
end

--► Removes a binding by name, regardless of which RunService event it used
Module.Unbind = function(name: string)
	local bound = boundNames[name]
	if not bound then return end

	if bound == "RenderStep" then
		RunService:UnbindFromRenderStep(name)
	else
		(bound :: RBXScriptConnection):Disconnect()
	end

	boundNames[name] = nil
	paused[name]     = nil
end

--► Removes every binding this module currently owns
Module.UnbindAll = function()
	for name in pairs(boundNames) do
		Module.Unbind(name)
	end
end

--► Returns true if a named binding currently exists
Module.IsBound = function(name: string): boolean
	return boundNames[name] ~= nil
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PAUSE / RESUME
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Pauses a named binding — its callback stops firing but stays bound
Module.Pause = function(name: string)
	paused[name] = true
end

--► Resumes a previously paused named binding
Module.Resume = function(name: string)
	paused[name] = nil
end

--► Returns true if a named binding is currently paused
Module.IsPaused = function(name: string): boolean
	return paused[name] == true
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ONE-SHOT / DELAYED
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Fires a callback once on the next Heartbeat, then disconnects itself
Module.NextFrame = function(callback: (dt: number) -> ())
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		connection:Disconnect()
		callback(dt)
	end)
end

--► Fires a callback once after a given number of Heartbeat frames have passed
Module.AfterFrames = function(frames: number, callback: () -> ())
	local remaining = math.max(frames, 1)
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		remaining -= 1
		if remaining <= 0 then
			connection:Disconnect()
			callback()
		end
	end)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	THROTTLED / SKIPPED UPDATES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Binds a named Heartbeat callback that only fires once every `interval` seconds
-- The callback receives the actual elapsed time since its last fire
Module.BindThrottled = function(name: string, interval: number, callback: (dt: number) -> ())
	local elapsed = 0
	Module.BindHeartbeat(name, function(dt: number)
		elapsed += dt
		if elapsed >= interval then
			callback(elapsed)
			elapsed = 0
		end
	end)
end

--► Binds a named Heartbeat callback that only fires every N frames
Module.BindEveryNFrames = function(name: string, n: number, callback: (dt: number) -> ())
	local count = 0
	Module.BindHeartbeat(name, function(dt: number)
		count += 1
		if count >= n then
			callback(dt)
			count = 0
		end
	end)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	DELTA TIME
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Clamps a delta-time value to avoid huge jumps after lag spikes/frame drops
Module.ClampDelta = function(dt: number, maxDelta: number?): number
	return math.min(dt, maxDelta or (1 / 15))
end

--► Returns a stateful smoother that averages delta time over a rolling window
-- Usage: local smoother = Render.NewDeltaSmoother(10); smoother:Push(dt); smoother:Average()
Module.NewDeltaSmoother = function(windowSize: number?)
	local self    = {}
	local size    = windowSize or 10
	local samples = {}
	local index   = 1

	--► Pushes a new delta-time sample into the rolling window
	function self:Push(dt: number)
		samples[index] = dt
		index = (index % size) + 1
	end

	--► Returns the average delta time across all collected samples
	function self:Average(): number
		if #samples == 0 then return 0 end
		local sum = 0
		for _, v in ipairs(samples) do
			sum += v
		end
		return sum / #samples
	end

	--► Clears all collected samples
	function self:Reset()
		samples = {}
		index   = 1
	end

	return self
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	FRAME / UPTIME INFO
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the total number of Heartbeat frames counted since this module loaded
Module.GetFrameCount = function(): number
	return frameCount
end

--► Returns the number of seconds since this module loaded
Module.GetUptime = function(): number
	return os.clock() - startTime
end

--► Returns the current estimated frame rate based on the last frame's delta time
Module.GetFPS = function(dt: number): number
	if dt <= 0 then return 0 end
	return 1 / dt
end

return Module
