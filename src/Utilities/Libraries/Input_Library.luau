--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Input_Library
--  ◄► Version:     1.1
--  ◄► Date:        28/05/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable input management module.
--                  Key bindings, held/tap/double-tap detection,
--                  gamepad support, deadzone normalization,
--                  mobile touch gestures, and VR controller support.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local VRService        = game:GetService("VRService")
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
--► Constants    ◄--
Module.DefaultHoldTime      = 0.4   -- seconds before a key is considered "held"
Module.DefaultDoubleTapTime = 0.3   -- seconds within which a second tap counts as double
Module.DefaultDeadzone      = 0.15  -- gamepad stick deadzone radius

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	QUERY HELPERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a key is currently held down
Module.IsKeyDown = function(keyCode: Enum.KeyCode): boolean
	return UserInputService:IsKeyDown(keyCode)
end

--► Returns true if a mouse button is currently held down
Module.IsMouseButtonDown = function(button: Enum.UserInputType): boolean
	return UserInputService:IsMouseButtonPressed(button)
end

--► Returns the current mouse position on screen as a Vector2
Module.MousePosition = function(): Vector2
	return UserInputService:GetMouseLocation()
end

--► Returns the current mouse delta (movement this frame) as a Vector2
Module.MouseDelta = function(): Vector2
	return UserInputService:GetMouseDelta()
end

--► Returns true if a gamepad is connected
Module.IsGamepadConnected = function(): boolean
	return UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1)
end

--► Returns the current position of a gamepad thumbstick as a Vector2 (with deadzone applied)
Module.ThumbstickPosition = function(stick: Enum.KeyCode, deadzone: number?): Vector2
	local dz    = deadzone or Module.DefaultDeadzone
	local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	for _, input in ipairs(state) do
		if input.KeyCode == stick then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			return Module.ApplyDeadzone(pos, dz)
		end
	end
	return Vector2.zero
end

--► Returns true if a gamepad button is currently held
Module.IsGamepadButtonDown = function(button: Enum.KeyCode): boolean
	return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, button)
end

--► Returns true if the device has touch input (mobile)
Module.IsTouchDevice = function(): boolean
	return UserInputService.TouchEnabled
end

--► Returns true if the device has a keyboard
Module.IsKeyboardDevice = function(): boolean
	return UserInputService.KeyboardEnabled
end

--► Returns true if the device has a gamepad
Module.IsGamepadDevice = function(): boolean
	return UserInputService.GamepadEnabled
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	DEADZONE & NORMALIZATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Applies a circular deadzone to a Vector2 thumbstick input
-- Returns Vector2.zero if within the deadzone, otherwise rescales to 0-1
Module.ApplyDeadzone = function(input: Vector2, deadzone: number?): Vector2
	local dz  = deadzone or Module.DefaultDeadzone
	local mag = input.Magnitude
	if mag < dz then return Vector2.zero end
	return input.Unit * ((mag - dz) / (1 - dz))
end

--► Applies a deadzone to a single axis value (-1 to 1)
Module.ApplyDeadzoneAxis = function(value: number, deadzone: number?): number
	local dz  = deadzone or Module.DefaultDeadzone
	local abs = math.abs(value)
	if abs < dz then return 0 end
	local scaled = (abs - dz) / (1 - dz)
	return math.sign(value) * scaled
end

--► Clamps a thumbstick Vector2 to a unit circle (prevents diagonal over-extension)
Module.ClampToUnitCircle = function(input: Vector2): Vector2
	if input.Magnitude > 1 then return input.Unit end
	return input
end

--► Normalizes a thumbstick input: applies deadzone then clamps to unit circle
Module.NormalizeThumbstick = function(input: Vector2, deadzone: number?): Vector2
	return Module.ClampToUnitCircle(Module.ApplyDeadzone(input, deadzone))
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	KEY BINDING MANAGER
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Creates a key binding manager for registering named actions
--
-- Usage:
--   local binds = Input.Bindings()
--   binds:Bind("Jump",   Enum.KeyCode.Space)
--   binds:Bind("Sprint", Enum.KeyCode.LeftShift)
--   binds:OnPressed("Jump",   function() ... end)
--   binds:OnReleased("Sprint", function() ... end)
--   binds:Destroy() -- cleans up all connections
Module.Bindings = function()
	local self       = {}
	local bindings   = {}   -- {[actionName] = KeyCode}
	local connections = {}  -- RBXScriptConnections to clean up

	--► Binds an action name to a KeyCode
	function self:Bind(actionName: string, keyCode: Enum.UserInputType | Enum.KeyCode)
		bindings[actionName] = keyCode
		return self
	end

	--► Removes a binding for an action
	function self:Unbind(actionName: string)
		bindings[actionName] = nil
		return self
	end

	--► Rebinds an action to a new key
	function self:Rebind(actionName: string, newKey: Enum.UserInputType | Enum.KeyCode)
		bindings[actionName] = newKey
		return self
	end

	--► Returns the KeyCode bound to an action (or nil)
	function self:GetKey(actionName: string): Enum.UserInputType? | Enum.KeyCode?
		return bindings[actionName]
	end

	--► Returns true if the bound key for an action is currently held
	function self:IsHeld(actionName: string): boolean
		local key = bindings[actionName]
		return key and UserInputService:IsKeyDown(key) or false
	end

	--► Registers a callback that fires when the bound key is pressed
	function self:OnPressed(actionName: string, callback: (actionName: string)->())
		local conn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == bindings[actionName] then
				callback(actionName)
			elseif input.UserInputType == bindings[actionName] then
				callback(actionName)
			end
			
			
		end)
		table.insert(connections, conn)
		return self
	end

	--► Registers a callback that fires when the bound key is released
	function self:OnReleased(actionName: string, callback: (actionName: string)->())
		local conn = UserInputService.InputEnded:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == bindings[actionName] then
				callback(actionName)
			elseif input.UserInputType == bindings[actionName] then
				callback(actionName)
			end
		end)
		table.insert(connections, conn)
		return self
	end

	--► Disconnects all connections created by this binding manager
	function self:Destroy()
		for _, conn in ipairs(connections) do conn:Disconnect() end
		connections = {}
	end

	return self
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	TAP / HOLD / DOUBLE-TAP DETECTOR
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Creates a detector for a single key that distinguishes tap, hold, and double-tap
--
-- Usage:
--   local detector = Input.KeyDetector(Enum.KeyCode.E)
--   detector:OnTap(function()        print("tapped") end)
--   detector:OnHold(function()       print("held")   end)
--   detector:OnDoubleTap(function()  print("double") end)
--   detector:Destroy()
Module.KeyDetector = function(keyCode: Enum.KeyCode, holdTime: number?, doubleTapTime: number?)
	local self           = {}
	local holdThreshold  = holdTime      or Module.DefaultHoldTime
	local doubleTapLimit = doubleTapTime or Module.DefaultDoubleTapTime

	local pressTime      = 0
	local lastTapTime    = -math.huge
	local holdFired      = false
	local connections    = {}

	local tapCallbacks       = {}
	local holdCallbacks      = {}
	local doubleTapCallbacks = {}
	local holdTickCallbacks  = {}

	--► Fires when the key is tapped (pressed and released quickly)
	function self:OnTap(fn: ()->())
		table.insert(tapCallbacks, fn)
		return self
	end

	--► Fires when the key is held down past the hold threshold
	function self:OnHold(fn: ()->())
		table.insert(holdCallbacks, fn)
		return self
	end

	--► Fires every frame while the key is held (useful for continuous actions)
	function self:OnHoldTick(fn: ()->())
		table.insert(holdTickCallbacks, fn)
		return self
	end

	--► Fires when the key is pressed twice within the double-tap window
	function self:OnDoubleTap(fn: ()->())
		table.insert(doubleTapCallbacks, fn)
		return self
	end

	local function fireAll(list)
		for _, fn in ipairs(list) do task.spawn(fn) end
	end

	local beganConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode ~= keyCode then return end
		pressTime = os.clock()
		holdFired = false

		-- Hold detection loop
		task.spawn(function()
			while UserInputService:IsKeyDown(keyCode) do
				if not holdFired and os.clock() - pressTime >= holdThreshold then
					holdFired = true
					fireAll(holdCallbacks)
				end
				if holdFired then fireAll(holdTickCallbacks) end
				task.wait()
			end
		end)
	end)

	local endedConn = UserInputService.InputEnded:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode ~= keyCode then return end

		if not holdFired then
			-- It was a tap — check for double tap
			local now = os.clock()
			if now - lastTapTime <= doubleTapLimit then
				fireAll(doubleTapCallbacks)
				lastTapTime = -math.huge  -- reset so triple tap doesn't double-fire
			else
				lastTapTime = now
				-- Delay single tap to let double tap window pass
				task.delay(doubleTapLimit, function()
					if lastTapTime == now then
						fireAll(tapCallbacks)
					end
				end)
			end
		end
	end)

	table.insert(connections, beganConn)
	table.insert(connections, endedConn)

	--► Disconnects all connections for this detector
	function self:Destroy()
		for _, conn in ipairs(connections) do conn:Disconnect() end
		connections = {}
	end

	return self
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	MOUSE UTILITIES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Locks the mouse to the center of the screen
Module.LockMouse = function()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end

--► Unlocks the mouse so it can move freely
Module.UnlockMouse = function()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

--► Hides the mouse cursor
Module.HideCursor = function()
	UserInputService.MouseIconEnabled = false
end

--► Shows the mouse cursor
Module.ShowCursor = function()
	UserInputService.MouseIconEnabled = true
end

--► Sets the mouse cursor icon to a custom asset ID
Module.SetCursor = function(assetId: string)
	UserInputService.MouseIcon = assetId
end

--► Returns the current mouse sensitivity (delta magnitude per frame, useful for camera)
Module.MouseSensitivity = function(): number
	return UserInputService:GetMouseDelta().Magnitude
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	INPUT TYPE DETECTION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns "Keyboard", "Gamepad", or "Touch" based on the last used input type
Module.GetInputType = function(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Gamepad1
		or last == Enum.UserInputType.Gamepad2 then
		return "Gamepad"
	elseif last == Enum.UserInputType.Touch then
		return "Touch"
	else
		return "Keyboard"
	end
end

--► Creates a watcher that fires a callback whenever the input type changes
-- (e.g. player switches from keyboard to gamepad)
Module.OnInputTypeChanged = function(callback: (string)->()): RBXScriptConnection
	local lastType = Module.GetInputType()
	return UserInputService.LastInputTypeChanged:Connect(function()
		local newType = Module.GetInputType()
		if newType ~= lastType then
			lastType = newType
			callback(newType)
		end
	end)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	MOBILE — TOUCH & GESTURE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if the current device is a mobile touch-only device
Module.IsMobile = function(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

--► Returns a list of all currently active touch positions as Vector2 screen positions
Module.GetTouches = function(): {Vector2}
	local touches = {}
	for _, touch in ipairs(UserInputService:GetTouches()) do
		table.insert(touches, Vector2.new(touch.Position.X, touch.Position.Y))
	end
	return touches
end

--► Returns the number of fingers currently touching the screen
Module.TouchCount = function(): number
	return #UserInputService:GetTouches()
end

--► Returns true if exactly N fingers are currently touching the screen
Module.IsTouching = function(fingerCount: number): boolean
	return Module.TouchCount() == fingerCount
end

--► Creates a tap detector for a GuiObject or the full screen
-- Fires callback with the screen position when the user taps without dragging
--
-- Usage:
--   local t = Input.TouchTap(frame, function(pos) end)
--   t:Destroy()
Module.TouchTap = function(target: GuiObject?, callback: (Vector2)->())
	local self        = {}
	local connections = {}
	local startPos    = nil
	local dragThresh  = 10

	local beganSignal = target and target.InputBegan or UserInputService.TouchStarted
	local endedSignal = target and target.InputEnded  or UserInputService.TouchEnded

	local beganConn = beganSignal:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		startPos = Vector2.new(input.Position.X, input.Position.Y)
	end)

	local endedConn = endedSignal:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if not startPos then return end
		local endPos = Vector2.new(input.Position.X, input.Position.Y)
		if (endPos - startPos).Magnitude < dragThresh then
			callback(endPos)
		end
		startPos = nil
	end)

	table.insert(connections, beganConn)
	table.insert(connections, endedConn)

	function self:Destroy()
		for _, c in ipairs(connections) do c:Disconnect() end
	end

	return self
end

--► Creates a swipe detector on the full screen
-- Fires callback with the swipe direction ("Left","Right","Up","Down") and pixel distance
--
-- Usage:
--   local s = Input.TouchSwipe(function(dir, dist) end)
--   s:Destroy()
Module.TouchSwipe = function(callback: (string, number)->(), threshold: number?)
	local self        = {}
	local connections = {}
	local swipeMin    = threshold or 50
	local startPos    = nil

	local beganConn = UserInputService.TouchStarted:Connect(function(input)
		startPos = Vector2.new(input.Position.X, input.Position.Y)
	end)

	local endedConn = UserInputService.TouchEnded:Connect(function(input)
		if not startPos then return end
		local endPos = Vector2.new(input.Position.X, input.Position.Y)
		local delta  = endPos - startPos
		local dist   = delta.Magnitude
		if dist < swipeMin then startPos = nil return end

		local dir
		if math.abs(delta.X) > math.abs(delta.Y) then
			dir = delta.X > 0 and "Right" or "Left"
		else
			dir = delta.Y > 0 and "Down" or "Up"
		end

		callback(dir, dist)
		startPos = nil
	end)

	table.insert(connections, beganConn)
	table.insert(connections, endedConn)

	function self:Destroy()
		for _, c in ipairs(connections) do c:Disconnect() end
	end

	return self
end

--► Creates a pinch-to-zoom detector using two fingers
-- Fires callback with scale factor (>1 = zoom in, <1 = zoom out) and the midpoint Vector2
--
-- Usage:
--   local p = Input.TouchPinch(function(scale, center) end)
--   p:Destroy()
Module.TouchPinch = function(callback: (number, Vector2)->())
	local self        = {}
	local connections = {}
	local lastDist    = nil

	local movedConn = UserInputService.TouchMoved:Connect(function()
		local touches = UserInputService:GetTouches()
		if #touches < 2 then lastDist = nil return end
		local p1     = Vector2.new(touches[1].Position.X, touches[1].Position.Y)
		local p2     = Vector2.new(touches[2].Position.X, touches[2].Position.Y)
		local dist   = (p2 - p1).Magnitude
		local center = (p1 + p2) / 2
		if lastDist then callback(dist / lastDist, center) end
		lastDist = dist
	end)

	local endedConn = UserInputService.TouchEnded:Connect(function()
		if #UserInputService:GetTouches() < 2 then lastDist = nil end
	end)

	table.insert(connections, movedConn)
	table.insert(connections, endedConn)

	function self:Destroy()
		for _, c in ipairs(connections) do c:Disconnect() end
	end

	return self
end

--► Creates a two-finger twist/rotation detector
-- Fires callback with the delta angle in radians this frame
--
-- Usage:
--   local r = Input.TouchRotate(function(deltaAngle) end)
--   r:Destroy()
Module.TouchRotate = function(callback: (number)->())
	local self        = {}
	local connections = {}
	local lastAngle   = nil

	local movedConn = UserInputService.TouchMoved:Connect(function()
		local touches = UserInputService:GetTouches()
		if #touches < 2 then lastAngle = nil return end
		local p1    = Vector2.new(touches[1].Position.X, touches[1].Position.Y)
		local p2    = Vector2.new(touches[2].Position.X, touches[2].Position.Y)
		local angle = math.atan2((p2 - p1).Y, (p2 - p1).X)
		if lastAngle then
			local delta = angle - lastAngle
			if delta >  math.pi then delta -= math.pi * 2 end
			if delta < -math.pi then delta += math.pi * 2 end
			if math.abs(delta) > 0.01 then callback(delta) end
		end
		lastAngle = angle
	end)

	local endedConn = UserInputService.TouchEnded:Connect(function()
		if #UserInputService:GetTouches() < 2 then lastAngle = nil end
	end)

	table.insert(connections, movedConn)
	table.insert(connections, endedConn)

	function self:Destroy()
		for _, c in ipairs(connections) do c:Disconnect() end
	end

	return self
end

--► Creates a virtual on-screen joystick tracker
-- center: the anchor point in screen space, radius: the maximum touch radius
-- Returns normalized direction and magnitude each frame
--
-- Usage:
--   local joy = Input.VirtualJoystick(Vector2.new(100, 400), 60)
--   RunService.Heartbeat:Connect(function()
--       local dir = joy:GetDirection()
--       local mag = joy:GetMagnitude()
--   end)
--   joy:Destroy()
Module.VirtualJoystick = function(center: Vector2, radius: number)
	local self        = {}
	local connections = {}
	local touchId     = nil
	local direction   = Vector2.zero
	local magnitude   = 0

	local beganConn = UserInputService.TouchStarted:Connect(function(input)
		if touchId then return end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if (pos - center).Magnitude <= radius * 1.5 then
			touchId = input
		end
	end)

	local movedConn = UserInputService.TouchMoved:Connect(function(input)
		if input ~= touchId then return end
		local pos   = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - center
		magnitude   = math.min(delta.Magnitude / radius, 1)
		direction   = delta.Magnitude > 1 and delta.Unit * magnitude or Vector2.zero
	end)

	local endedConn = UserInputService.TouchEnded:Connect(function(input)
		if input == touchId then
			touchId   = nil
			direction = Vector2.zero
			magnitude = 0
		end
	end)

	table.insert(connections, beganConn)
	table.insert(connections, movedConn)
	table.insert(connections, endedConn)

	--► Returns the current joystick direction as a normalized Vector2 (0-1 magnitude)
	function self:GetDirection(): Vector2
		return direction
	end

	--► Returns the current push magnitude (0 = center, 1 = full radius)
	function self:GetMagnitude(): number
		return magnitude
	end

	--► Returns true if the joystick is being actively touched
	function self:IsActive(): boolean
		return touchId ~= nil
	end

	function self:Destroy()
		for _, c in ipairs(connections) do c:Disconnect() end
	end

	return self
end

--► Creates a long-press detector for touch input
-- Fires callback after the finger has been held for the given duration without moving
--
-- Usage:
--   local lp = Input.TouchLongPress(function(pos) end, 0.6)
--   lp:Destroy()
Module.TouchLongPress = function(callback: (Vector2)->(), holdTime: number?)
	local self        = {}
	local connections = {}
	local threshold   = holdTime or 0.6
	local dragThresh  = 12
	local startPos    = nil
	local holdThread  = nil

	local beganConn = UserInputService.TouchStarted:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		startPos   = Vector2.new(input.Position.X, input.Position.Y)
		holdThread = task.delay(threshold, function()
			if startPos then callback(startPos) end
		end)
	end)

	local movedConn = UserInputService.TouchMoved:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if not startPos then return end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if (pos - startPos).Magnitude > dragThresh then
			if holdThread then task.cancel(holdThread) end
			startPos = nil
		end
	end)

	local endedConn = UserInputService.TouchEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if holdThread then task.cancel(holdThread) end
		startPos = nil
	end)

	table.insert(connections, beganConn)
	table.insert(connections, movedConn)
	table.insert(connections, endedConn)

	function self:Destroy()
		for _, c in ipairs(connections) do c:Disconnect() end
	end

	return self
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	VR — HEADSET & CONTROLLERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a VR headset is currently active
Module.IsVR = function(): boolean
	return VRService.VREnabled
end

--► Returns the CFrame of the VR headset in world space
Module.HeadsetCFrame = function(): CFrame
	return VRService:GetUserCFrameEnabled(Enum.UserCFrame.Head)
		and VRService:GetUserCFrame(Enum.UserCFrame.Head)
		or  CFrame.identity
end

--► Returns the CFrame of the left VR hand controller in world space
Module.LeftHandCFrame = function(): CFrame
	return VRService:GetUserCFrameEnabled(Enum.UserCFrame.LeftHand)
		and VRService:GetUserCFrame(Enum.UserCFrame.LeftHand)
		or  CFrame.identity
end

--► Returns the CFrame of the right VR hand controller in world space
Module.RightHandCFrame = function(): CFrame
	return VRService:GetUserCFrameEnabled(Enum.UserCFrame.RightHand)
		and VRService:GetUserCFrame(Enum.UserCFrame.RightHand)
		or  CFrame.identity
end

--► Returns the world-space position of the VR headset
Module.HeadsetPosition = function(): Vector3
	return Module.HeadsetCFrame().Position
end

--► Returns the world-space look direction of the VR headset as a unit Vector3
Module.HeadsetLookVector = function(): Vector3
	return Module.HeadsetCFrame().LookVector
end

--► Returns the world-space position of the left hand controller
Module.LeftHandPosition = function(): Vector3
	return Module.LeftHandCFrame().Position
end

--► Returns the world-space position of the right hand controller
Module.RightHandPosition = function(): Vector3
	return Module.RightHandCFrame().Position
end

--► Returns the world-space look/point direction of the left hand controller
Module.LeftHandLookVector = function(): Vector3
	return Module.LeftHandCFrame().LookVector
end

--► Returns the world-space look/point direction of the right hand controller
Module.RightHandLookVector = function(): Vector3
	return Module.RightHandCFrame().LookVector
end

--► Returns true if tracking is available for the given Enum.UserCFrame
Module.IsTracking = function(userCFrame: Enum.UserCFrame): boolean
	return VRService:GetUserCFrameEnabled(userCFrame)
end

--► Returns the angle in radians between the headset look vector and a world target
-- Useful for gaze-based UI and interaction highlighting
Module.GazeAngleTo = function(targetPosition: Vector3, headPosition: Vector3?): number
	local head     = headPosition or Module.HeadsetPosition()
	local look     = Module.HeadsetLookVector()
	local toTarget = (targetPosition - head)
	if toTarget.Magnitude < 1e-6 then return 0 end
	return math.acos(math.clamp(look:Dot(toTarget.Unit), -1, 1))
end

--► Returns true if the headset is looking at a position within a cone angle in radians
-- coneAngle: how wide the gaze cone is (e.g. 0.1 rad ≈ 6°)
Module.IsLookingAt = function(targetPosition: Vector3, coneAngle: number, headPosition: Vector3?): boolean
	return Module.GazeAngleTo(targetPosition, headPosition) <= coneAngle
end

--► Returns a Ray cast from the right hand in its pointing direction
-- Useful for VR laser pointer / selection
Module.RightHandRay = function(length: number?): Ray
	local cf = Module.RightHandCFrame()
	return Ray.new(cf.Position, cf.LookVector * (length or 100))
end

--► Returns a Ray cast from the left hand in its pointing direction
Module.LeftHandRay = function(length: number?): Ray
	local cf = Module.LeftHandCFrame()
	return Ray.new(cf.Position, cf.LookVector * (length or 100))
end

--► Returns a Ray cast from the headset in its look direction (gaze ray)
Module.GazeRay = function(length: number?): Ray
	local cf = Module.HeadsetCFrame()
	return Ray.new(cf.Position, cf.LookVector * (length or 100))
end

--► Recenters the VR experience to the current headset position
Module.RecenterVR = function()
	VRService:RecenterUserHeadCFrame()
end

--► Fires a callback every frame the headset moves more than a threshold in studs
-- Returns the RBXScriptConnection to disconnect when done
--
-- Usage:
--   local conn = Input.OnHeadMoved(function(cf) end, 0.01)
--   conn:Disconnect()
Module.OnHeadMoved = function(callback: (CFrame)->(), threshold: number?): RBXScriptConnection
	local minDelta = threshold or 0.01
	local lastCF   = Module.HeadsetCFrame()
	return RunService.Heartbeat:Connect(function()
		local cf = Module.HeadsetCFrame()
		if (cf.Position - lastCF.Position).Magnitude >= minDelta then
			lastCF = cf
			callback(cf)
		end
	end)
end

--► Fires a callback every frame the left hand moves more than a threshold in studs
Module.OnLeftHandMoved = function(callback: (CFrame)->(), threshold: number?): RBXScriptConnection
	local minDelta = threshold or 0.01
	local lastCF   = Module.LeftHandCFrame()
	return RunService.Heartbeat:Connect(function()
		local cf = Module.LeftHandCFrame()
		if (cf.Position - lastCF.Position).Magnitude >= minDelta then
			lastCF = cf
			callback(cf)
		end
	end)
end

--► Fires a callback every frame the right hand moves more than a threshold in studs
Module.OnRightHandMoved = function(callback: (CFrame)->(), threshold: number?): RBXScriptConnection
	local minDelta = threshold or 0.01
	local lastCF   = Module.RightHandCFrame()
	return RunService.Heartbeat:Connect(function()
		local cf = Module.RightHandCFrame()
		if (cf.Position - lastCF.Position).Magnitude >= minDelta then
			lastCF = cf
			callback(cf)
		end
	end)
end

--► Returns the distance in studs between the two VR hand controllers
-- Useful for two-handed grip detection or scaling interactions
Module.HandSpan = function(): number
	return (Module.RightHandPosition() - Module.LeftHandPosition()).Magnitude
end

--► Returns the midpoint between both hand controllers in world space
-- Useful for two-handed grab center point
Module.HandMidpoint = function(): Vector3
	return (Module.LeftHandPosition() + Module.RightHandPosition()) / 2
end

--► Returns the direction vector from the left hand to the right hand
Module.HandDirection = function(): Vector3
	local span = Module.HandSpan()
	if span < 1e-6 then return Vector3.new(1, 0, 0) end
	return (Module.RightHandPosition() - Module.LeftHandPosition()).Unit
end

return Module