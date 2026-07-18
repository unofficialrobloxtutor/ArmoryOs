--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Tween_Library
--  ◄► Version:     1.0
--  ◄► Date:        28/05/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable TweenService wrapper with
--                  chainable sequences, parallel groups, and callbacks.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local TweenService = game:GetService("TweenService")
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
--► Constants    ◄--
Module.DefaultStyle     = Enum.EasingStyle.Quad
Module.DefaultDirection = Enum.EasingDirection.Out
Module.DefaultDuration  = 0.5

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	TWEEN INFO BUILDERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a TweenInfo with sensible defaults — override any parameter you need
Module.Info = function(
	duration:  number?,
	style:     Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	repeats:   number?,
	reverses:  boolean?,
	delay:     number?
): TweenInfo
	return TweenInfo.new(
		duration  or Module.DefaultDuration,
		style     or Module.DefaultStyle,
		direction or Module.DefaultDirection,
		repeats   or 0,
		reverses  or false,
		delay     or 0
	)
end

--► Returns a TweenInfo preset for a quick snappy transition
Module.InfoSnappy = function(duration: number?): TweenInfo
	return TweenInfo.new(duration or 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

--► Returns a TweenInfo preset for a smooth gentle transition
Module.InfoSmooth = function(duration: number?): TweenInfo
	return TweenInfo.new(duration or 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

--► Returns a TweenInfo preset for a springy elastic feel
Module.InfoElastic = function(duration: number?): TweenInfo
	return TweenInfo.new(duration or 0.8, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
end

--► Returns a TweenInfo preset for a bouncy landing effect
Module.InfoBounce = function(duration: number?): TweenInfo
	return TweenInfo.new(duration or 0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
end

--► Returns a TweenInfo that loops forever
Module.InfoLooping = function(duration: number?, style: Enum.EasingStyle?): TweenInfo
	return TweenInfo.new(
		duration or 1,
		style    or Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,   -- repeat forever
		true  -- reverses
	)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SINGLE TWEEN HELPERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Creates and plays a tween immediately, returns the Tween object
Module.Play = function(instance: Instance, info: TweenInfo, properties: {}): Tween
	local tween = TweenService:Create(instance, info, properties)
	tween:Play()
	return tween
end

--► Creates and plays a tween, calls a callback when it completes
Module.PlayThen = function(instance: Instance, info: TweenInfo, properties: {}, callback: ()->()): Tween
	local tween = TweenService:Create(instance, info, properties)
	tween.Completed:Once(function()
		callback()
	end)
	tween:Play()
	return tween
end

--► Plays a tween and yields the current thread until it finishes
Module.PlayAsync = function(instance: Instance, info: TweenInfo, properties: {})
	local tween = TweenService:Create(instance, info, properties)
	tween:Play()
	tween.Completed:Wait()
end

--► Cancels a tween if it is still playing
Module.Cancel = function(tween: Tween)
	if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
		tween:Cancel()
	end
end

--► Pauses a tween if it is playing
Module.Pause = function(tween: Tween)
	if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
		tween:Pause()
	end
end

--► Quickly fades a BasePart or GuiObject to a target transparency/alpha
Module.FadeTo = function(instance: Instance, transparency: number, duration: number?): Tween
	local prop = instance:IsA("GuiObject") and {BackgroundTransparency = transparency}
		or {Transparency = transparency}
	return Module.Play(instance, Module.Info(duration or 0.3), prop)
end

--► Quickly moves an instance to a target position
Module.MoveTo = function(instance: BasePart, position: Vector3, duration: number?, style: Enum.EasingStyle?): Tween
	return Module.Play(instance, Module.Info(duration, style), {Position = position})
end

--► Quickly scales a GuiObject to a target size
Module.SizeTo = function(instance: GuiObject, size: UDim2, duration: number?): Tween
	return Module.Play(instance, Module.InfoSmooth(duration), {Size = size})
end

--► Quickly moves a GuiObject to a target position
Module.GuiMoveTo = function(instance: GuiObject, position: UDim2, duration: number?): Tween
	return Module.Play(instance, Module.InfoSmooth(duration), {Position = position})
end

--► Tweens a NumberValue or IntValue to a target value
Module.ValueTo = function(valueObject: Instance, target: number, duration: number?): Tween
	return Module.Play(valueObject, Module.Info(duration), {Value = target})
end

--► Pulses a property back and forth forever using a looping tween
Module.Pulse = function(instance: Instance, property: string, from: any, to: any, duration: number?): Tween
	(instance :: any)[property] = from
	return Module.Play(instance, Module.InfoLooping(duration), {[property] = to})
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PARALLEL GROUP
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Plays multiple tweens at the same time and calls a callback when ALL finish
-- steps: array of {instance, info, properties}
Module.Parallel = function(steps: {{any}}, onComplete: (()->())?): {Tween}
	local tweens    = {}
	local total     = #steps
	local finished  = 0

	for _, step in ipairs(steps) do
		local instance   = step[1]
		local info       = step[2]
		local properties = step[3]
		local tween      = TweenService:Create(instance, info, properties)

		tween.Completed:Once(function()
			finished += 1
			if finished >= total and onComplete then
				onComplete()
			end
		end)

		tween:Play()
		table.insert(tweens, tween)
	end

	return tweens
end

--► Cancels all tweens in a parallel group
Module.CancelAll = function(tweens: {Tween})
	for _, tween in ipairs(tweens) do
		Module.Cancel(tween)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SEQUENCE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Creates a chainable tween sequence that plays steps one after another
--
-- Usage:
--   local seq = Tween.Sequence()
--   seq:Add(part, Tween.Info(1), {Position = target})
--   seq:Add(part, Tween.Info(0.5), {Transparency = 1})
--   seq:OnComplete(function() print("done") end)
--   seq:Play()
Module.Sequence = function()
	local self    = {}
	local steps   = {}
	local running = false
	local onCompleteCallback = nil

	--► Adds a tween step to the sequence
	function self:Add(instance: Instance, info: TweenInfo, properties: {})
		table.insert(steps, {instance = instance, info = info, properties = properties})
		return self  -- allows chaining
	end

	--► Adds a delay step (in seconds) between tweens
	function self:Wait(duration: number)
		table.insert(steps, {delay = duration})
		return self
	end

	--► Adds a callback step that fires mid-sequence
	function self:Call(fn: ()->())
		table.insert(steps, {callback = fn})
		return self
	end

	--► Registers a function to call when the entire sequence finishes
	function self:OnComplete(fn: ()->())
		onCompleteCallback = fn
		return self
	end

	--► Starts playing the sequence from the beginning
	function self:Play()
		if running then return end
		running = true
		task.spawn(function()
			for _, step in ipairs(steps) do
				if step.delay then
					task.wait(step.delay)
				elseif step.callback then
					step.callback()
				else
					local tween = TweenService:Create(step.instance, step.info, step.properties)
					tween:Play()
					tween.Completed:Wait()
				end
			end
			running = false
			if onCompleteCallback then onCompleteCallback() end
		end)
	end

	--► Stops the sequence mid-play (does not revert properties)
	function self:Stop()
		running = false
	end

	--► Returns true if the sequence is currently playing
	function self:IsRunning(): boolean
		return running
	end

	--► Clears all steps from the sequence
	function self:Clear()
		steps = {}
		onCompleteCallback = nil
		return self
	end

	return self
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	COMMON PRESETS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Fades a GuiObject in from fully transparent to fully visible
Module.FadeIn = function(instance: GuiObject, duration: number?): Tween
	instance.BackgroundTransparency = 1
	return Module.Play(instance, Module.Info(duration or 0.4, Enum.EasingStyle.Sine), {BackgroundTransparency = 0})
end

--► Fades a GuiObject out from fully visible to fully transparent
Module.FadeOut = function(instance: GuiObject, duration: number?): Tween
	return Module.Play(instance, Module.Info(duration or 0.4, Enum.EasingStyle.Sine), {BackgroundTransparency = 1})
end

--► Scales a GuiObject from zero size up to its target size (pop-in effect)
Module.PopIn = function(instance: GuiObject, targetSize: UDim2, duration: number?): Tween
	instance.Size = UDim2.new(0, 0, 0, 0)
	return Module.Play(instance, Module.InfoSnappy(duration), {Size = targetSize})
end

--► Scales a GuiObject down to zero size (pop-out effect)
Module.PopOut = function(instance: GuiObject, duration: number?): Tween
	return Module.Play(instance, Module.InfoSnappy(duration), {Size = UDim2.new(0, 0, 0, 0)})
end

--► Shakes a BasePart around its current position by a given intensity
Module.Shake = function(instance: BasePart, intensity: number?, duration: number?)
	local origin = instance.Position
	local mag    = intensity or 0.5
	local dur    = duration  or 0.4
	local steps  = 8
	local seq    = Module.Sequence()

	for i = 1, steps do
		local offset = Vector3.new(
			(math.random() * 2 - 1) * mag,
			(math.random() * 2 - 1) * mag,
			(math.random() * 2 - 1) * mag
		) * (1 - i / steps)  -- dampens over time
		seq:Add(instance, Module.Info(dur / steps, Enum.EasingStyle.Linear), {Position = origin + offset})
	end

	seq:Add(instance, Module.Info(dur / steps), {Position = origin})
	seq:Play()
end

--► Highlights an instance by briefly scaling it up then back to normal
Module.Ping = function(instance: GuiObject, scale: number?, duration: number?)
	local originalSize = instance.Size
	local s            = scale or 1.15
	local d            = duration or 0.2
	local bigSize      = UDim2.new(
		originalSize.X.Scale * s, originalSize.X.Offset,
		originalSize.Y.Scale * s, originalSize.Y.Offset
	)
	Module.Sequence()
		:Add(instance, Module.InfoSnappy(d * 0.4), {Size = bigSize})
		:Add(instance, Module.InfoSnappy(d * 0.6), {Size = originalSize})
		:Play()
end

return Module