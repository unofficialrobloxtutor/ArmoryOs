--!nocheck
--[[ CREDITS: 
		Users: DeathToTheStadium

	Module Function
		Name: Hit Box Library
		Description: 
			Used to Create Custom Hitboxes and detect wether or not a player is
			in custom calculated Bounds

]]

-- Services
local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
-- Requirements
local ConnectionLibary = require(`../Libraries/Connection_Library`)
local Visuals = require("@self/HitBox_Visuals")
-- Connections

-- Remotes

-- Limb whitelist (rejects HumanoidRootPart, tools, accessories, etc.)
local VALID_LIMBS = {
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	Torso = true, -- R6 fallback
	LeftUpperArm = true, RightUpperArm = true,
	LeftLowerArm = true, RightLowerArm = true,
	LeftHand = true, RightHand = true,
	["Left Arm"] = true, ["Right Arm"] = true, -- R6
	LeftUpperLeg = true, RightUpperLeg = true,
	LeftLowerLeg = true, RightLowerLeg = true,
	LeftFoot = true, RightFoot = true,
	["Left Leg"] = true, ["Right Leg"] = true, -- R6
}

-- local Methods
local function _isplayer(Item: Instance?): (boolean, Player?, BasePart?)
	if Item == nil then return false end
	if not Item:IsA("BasePart") then return false end
	if Item.Parent == nil then return false end
	local Player = PlayerService:GetPlayerFromCharacter(Item.Parent)
	if Player == nil then return false end
	if not VALID_LIMBS[Item.Name] then return false end
	return true, Player, Item
end

local function _buildhitbox(self: Type, type: "InBounds"|"InRadius")
	if type == "InBounds" then 
		local CFrame = CFrame.new(self._origin) * CFrame.lookAt(Vector3.zero, self._direction)
		local Size = self._size
		local Params= self._params

		return workspace:GetPartBoundsInBox(CFrame,Size,Params)
	elseif type == "InRadius" then
		local Origin = self._origin
		local Size   = self._radius
		local Params = self._params

		return workspace:GetPartBoundsInRadius(Origin,Size,Params)
	end
end

-- Storage
local VAR_SWITCH = {
	Params    = "_params",
	Origin    = "_origin",
	Direction = "_direction",
	Size      = "_size",
	Radius    = "_radius",
	Angle     = "_angle",
	Range     = "_range",
}

local function _resolveHit(self: Type, item: Instance, check: HitCheck?): (boolean, Player?, BasePart?)
	local Hit, Player, Limb = _isplayer(item)
	if not Hit then return false end
	if check and not check(item.Position, self.Origin, self.Direction) then return false end
	-- veto hook: e.g. a parry/block system can cancel the hit before it's finalized
	if self._beforeHit then
		local ok, allowed = pcall(self._beforeHit, Player, Limb, item.Position)
		if not ok or allowed == false then return false end
	end
	return true, Player, Limb
end

-- Built-in geometry checks (kept separate from Custom so simple shapes don't need a handler)
local function _inCone(origin: Vector3, axis: Vector3, range: number, angleDegrees: number, point: Vector3): boolean
	local toPoint = point - origin
	local dist = toPoint.Magnitude
	if dist == 0 or dist > range then return false end
	local halfAngleCos = math.cos(math.rad(angleDegrees / 2))
	return toPoint.Unit:Dot(axis) >= halfAngleCos
end

local function _inCylinder(origin: Vector3, axis: Vector3, radius: number, height: number, point: Vector3): boolean
	local offset = point - origin
	local alongAxis = offset:Dot(axis)
	local radial = offset - (axis * alongAxis)
	return radial.Magnitude <= radius and math.abs(alongAxis) <= height / 2
end

-- Square-based pyramid: tip at origin, base centered along axis at `height`, half-width `baseSize` at the base
local function _inPyramid(origin: Vector3, axis: Vector3, baseSize: number, height: number, point: Vector3): boolean
	local offset = point - origin
	local alongAxis = offset:Dot(axis)
	if alongAxis < 0 or alongAxis > height then return false end

	local arbitrary = math.abs(axis.Y) < 0.99 and Vector3.yAxis or Vector3.xAxis
	local right = axis:Cross(arbitrary).Unit
	local up = axis:Cross(right).Unit

	local radial = offset - (axis * alongAxis)
	local localX = math.abs(radial:Dot(right))
	local localY = math.abs(radial:Dot(up))

	-- half-width grows linearly from 0 at the tip to baseSize at the base
	local halfWidthAtHeight = baseSize * (alongAxis / height)
	return localX <= halfWidthAtHeight and localY <= halfWidthAtHeight
end

-- Draws the current shape if self._debug is enabled. Centralized here so every
-- METHOD_SWITCH entry just calls _drawDebug(self) once instead of duplicating
-- per-shape Visuals calls + the `if self._debug` guard six times over.
local function _drawDebug(self: Type)
	if not self._debug then return end
	local t = self._type

	if t == "Cube" then
		Visuals.Cube(self._origin, self._direction, self._size)
	elseif t == "Sphere" then
		Visuals.Sphere(self._origin, self._radius)
	elseif t == "Cone" then
		Visuals.Cone(self._origin, self._direction, self._range, self._angle)
	elseif t == "Cylinder" then
		Visuals.Cylinder(self._origin, self._direction, self._radius, self._size.Y)
	elseif t == "Pyramid" then
		Visuals.Pyramid(self._origin, self._direction, self._radius, self._size.Y)
	elseif t == "Custom" then
		-- no fixed shape to draw precisely; show the broad-phase bounding box instead
		Visuals.Cube(self._origin, self._direction, self._size, { color = Color3.fromRGB(255, 0, 255) })
	end
end

local METHOD_SWITCH = {
	["Cube"] = function(self: Type)
		_drawDebug(self)
		local Parts = _buildhitbox(self, "InBounds")
		local list = {}
		for _, item in Parts do
			local Hit, Player, Limb = _resolveHit(self, item)
			if not Hit then continue end
			if self._alreadyHit and self._alreadyHit[Player] then continue end
			table.insert(list, Player)
			self._hit:Fire(Player, Limb, item.Position, self.Origin, self.Direction, os.clock())
		end
		if #list == 0 then self._miss:Fire(Parts, self.Origin, self.Direction, os.clock()) end
		return list
	end,
	["Sphere"] = function(self: Type)
		_drawDebug(self)
		local Parts = _buildhitbox(self, "InRadius")
		local list = {}
		for _, item in Parts do
			local Hit, Player, Limb = _resolveHit(self, item)
			if not Hit then continue end
			if self._alreadyHit and self._alreadyHit[Player] then continue end
			table.insert(list, Player)
			self._hit:Fire(Player, Limb, item.Position, self.Origin, self.Direction, os.clock())
		end
		if #list == 0 then self._miss:Fire(Parts, self.Origin, self.Direction, os.clock()) end
		return list
	end,

	["Cone"] = function(self: Type)
		_drawDebug(self)
		local Parts = _buildhitbox(self, "InBounds") -- Size must bound the cone, e.g. Vector3.new(range*2, range*2, range*2)
		local axis = self._direction.Unit
		local list = {}
		for _, item in Parts do
			if not _inCone(self._origin, axis, self._range, self._angle, item.Position) then continue end
			local Hit, Player, Limb = _resolveHit(self, item)
			if not Hit then continue end
			if self._alreadyHit and self._alreadyHit[Player] then continue end
			table.insert(list, Player)
			self._hit:Fire(Player, Limb, item.Position, self.Origin, self.Direction, os.clock())
		end
		if #list == 0 then self._miss:Fire(Parts, self.Origin, self.Direction, os.clock()) end
		return list
	end,

	["Cylinder"] = function(self: Type)
		_drawDebug(self)
		local Parts = _buildhitbox(self, "InBounds") -- Size must bound the cylinder, e.g. Vector3.new((radius+0)*2, height, (radius+0)*2) oriented to Direction
		local axis = self._direction.Unit
		local list = {}
		for _, item in Parts do
			if not _inCylinder(self._origin, axis, self._radius, self._size.Y, item.Position) then continue end
			local Hit, Player, Limb = _resolveHit(self, item)
			if not Hit then continue end
			if self._alreadyHit and self._alreadyHit[Player] then continue end
			table.insert(list, Player)
			self._hit:Fire(Player, Limb, item.Position, self.Origin, self.Direction, os.clock())
		end
		if #list == 0 then self._miss:Fire(Parts, self.Origin, self.Direction, os.clock()) end
		return list
	end,

	["Pyramid"] = function(self: Type)
		_drawDebug(self)
		local Parts = _buildhitbox(self, "InBounds") -- Size must bound the pyramid, e.g. Vector3.new(baseSize*2, height, baseSize*2) oriented to Direction
		local axis = self._direction.Unit
		local list = {}
		for _, item in Parts do
			if not _inPyramid(self._origin, axis, self._radius, self._size.Y, item.Position) then continue end
			local Hit, Player, Limb = _resolveHit(self, item)
			if not Hit then continue end
			if self._alreadyHit and self._alreadyHit[Player] then continue end
			table.insert(list, Player)
			self._hit:Fire(Player, Limb, item.Position, self.Origin, self.Direction, os.clock())
		end
		if #list == 0 then self._miss:Fire(Parts, self.Origin, self.Direction, os.clock()) end
		return list
	end,

	["Custom"] = function(self: Type, check: HitCheck)
		_drawDebug(self)
		local Parts = _buildhitbox(self, "InBounds")
		local list = {}
		for _, item in Parts do
			local Hit, Player, Limb = _resolveHit(self, item, check)
			if not Hit then continue end
			if self._alreadyHit and self._alreadyHit[Player] then continue end
			table.insert(list, Player)
			self._hit:Fire(Player, Limb, item.Position, self.Origin, self.Direction, os.clock())
		end
		if #list == 0 then self._miss:Fire(Parts, self.Origin, self.Direction, os.clock()) end
		return list
	end,
}

-- Types
--
-- HitCheck: a per-candidate validity check, used by the "Custom" shape and
-- optionally by any built-in shape too. Called once for every candidate part
-- that already passed the broad-phase geometry test and the limb whitelist.
-- Return true to allow the hit, false/nil to reject it.
--   Point     = the candidate limb's world position
--   Origin    = this Hitbox's current Origin (for convenience, same as self.Origin)
--   Direction = this Hitbox's current Direction (same as self.Direction)
type HitCheck = (Point: Vector3, Origin: Vector3, Direction: Vector3) -> (boolean?)

-- The set of built-in shapes this module knows how to test natively.
-- Anything more complex (octahedron, helix, etc.) goes through "Custom" with a HitCheck.
type HitTypes = "Cube" | "Sphere" | "Cone" | "Cylinder" | "Pyramid" | "Custom"

-- A snapshot of fields to apply to a Hitbox instance in one atomic call, instead
-- of setting Origin/Direction/Size/Radius individually via property assignment.
-- Any field left nil is untouched (the instance keeps its current value for that field).
-- Pass this as the first table-shaped argument to Fire() or FireUntil().
type FireUpdate = {
	Origin: Vector3?,
	Direction: Vector3?,
	Size: Vector3?,
	Radius: number?,
}

-- A function called once per Heartbeat tick *inside* a FireUntil run, before that
-- tick's Fire() executes. Use this when the Hitbox needs to track something that
-- moves over time (a weapon's live blade position, a moving spawn point, etc.) —
-- unlike a static FireUpdate table (applied once, unchanged for the whole run),
-- this re-evaluates fresh every tick. Return a FireUpdate (or nil to change nothing
-- this tick). `dt` is the time since the last tick, same as RunService.Heartbeat.
--
-- IMPORTANT: this must take exactly ONE parameter (dt). FireUntil tells a
-- FireTrackingFn apart from a HitCheck purely by counting parameters
-- (1 = tracking function, 3 = HitCheck) — see FireUntil's doc comment below.
type FireTrackingFn = (dt: number) -> FireUpdate?

--════════════════════════════════════════════════--
-- Module Begin
local module = {}

module.Visuals = Visuals

export type Visuals = typeof(Visuals)
export type Type = {
	--[[ Private
		_params: OverlapParams,
		_origin: Vector3,
		_direction: Vector3,
		_size: Vector3,
		_radius: number,
		_angle: number,
		_range: number,
		_type: HitTypes,

		_hit: BindableEvent,
		_miss: BindableEvent,
		_finished: BindableEvent,
		_cancelled: BindableEvent,
		_destroyed: BindableEvent,
		_activeConnection: RBXScriptConnection?,
		_alreadyHit: {[Player]: boolean}?,
		_beforeHit: ((Player, BasePart, Vector3) -> boolean?)?,
		_debug: boolean?,
	]]
 
	-- Public
	--Variables
	Params: OverlapParams,
	Origin: Vector3,
	Direction: Vector3,
	Size: Vector3,
	Radius: number,
	Angle: number,
	Range: number,

	--Functions
	Fire: (self: Type, updateOrCheck: (FireUpdate | HitCheck)?, check: HitCheck?) -> ({Player?}),
	FireUntil: (self: Type, TimeOut: number, updateOrTrackingFnOrCheck: (FireUpdate | FireTrackingFn | HitCheck)?, check: HitCheck?) -> (RBXScriptConnection),
	Cancel: (self: Type) -> (),
	Destroy: (self: Type) -> (),
	IsActive: (self: Type) -> (boolean),
	OnBeforeHit: (self: Type, handler: ((Player: Player, Limb: BasePart, Point: Vector3) -> boolean?)?) -> (),
	Debug: (self: Type, enabled: boolean) -> (),

	--math-helpers
	SetCube: (self: Type, origin: Vector3, direction: Vector3, size: Vector3) -> (),
	SetSphere: (self: Type, origin: Vector3, radius: number) -> (),
	SetCone: (self: Type, origin: Vector3, direction: Vector3, range: number, angleDegrees: number) -> (),
	SetCylinder: (self: Type, origin: Vector3, direction: Vector3, radius: number, height: number) -> (),
	SetPyramid: (self: Type, origin: Vector3, direction: Vector3, baseHalfWidth: number, height: number) -> (),
	SetCapsule: (self: Type, pointA: Vector3, pointB: Vector3, radius: number) -> (HitCheck),  

	--Events
	OnHit: {
		Connect: (self: any, handler: (Player: Player, Limb: BasePart, Point:Vector3,Origin:Vector3,Direction: Vector3, TimeStamp: number)->())->(),
		Once: (self: any,handler: (Player: Player, Limb: BasePart, Point:Vector3,Origin:Vector3,Direction: Vector3, TimeStamp: number)->())->(),
		Wait: (self: any)->(Player,BasePart,Vector3,Vector3,Vector3,number),
	},
	OnMiss: {
		Connect: (self: any,handler: (Missed: {Instances?}, Origin:Vector3,Direction: Vector3, TimeStamp: number)->())->(),
		Once: (self: any,handler: (Missed: {Instances?},Origin:Vector3,Direction: Vector3, TimeStamp: number)->())->(),
		Wait: (self: any)->({Instances?},Vector3,Vector3, number),
	},
	-- Fires once when a FireUntil run completes naturally (its TimeOut elapsed).
	-- hitPlayers is the deduped list of every player hit at any point during the run.
	OnFinished: {
		Connect: (self: any, handler: (reason: "Timeout", hitPlayers: {Player}) -> ()) -> (),
		Once: (self: any, handler: (reason: "Timeout", hitPlayers: {Player}) -> ()) -> (),
		Wait: (self: any) -> ("Timeout", {Player}),
	},
	-- Fires when an active FireUntil run is stopped early — either via an explicit
	-- :Cancel() call ("Manual") or because a per-tick error occurred ("Error").
	-- Does NOT fire from the internal auto-Cancel at the start of a fresh FireUntil call.
	OnCancel: {
		Connect: (self: any, handler: (reason: "Manual" | "Error", hitPlayers: {Player}) -> ()) -> (),
		Once: (self: any, handler: (reason: "Manual" | "Error", hitPlayers: {Player}) -> ()) -> (),
		Wait: (self: any) -> ("Manual" | "Error", {Player}),
	},
	-- Fires once when :Destroy() is called, before signals are torn down.
	OnDestroy: {
		Connect: (self: any, handler: () -> ()) -> (),
		Once: (self: any, handler: () -> ()) -> (),
		Wait: (self: any) -> (),
	},
}

--════════════════════════════════════════════════--
-- Module Class
function module.New(HitType: HitTypes)
	return setmetatable({
		_params           = OverlapParams.new(),
		_origin           = Vector3.zero,
		_direction        = Vector3.FromNormalId(Enum.NormalId.Front),
		_size             = Vector3.zero,
		_radius           = 1,
		_angle            = 60,
		_range            = 10,
		_type             = HitType,
		_hit              = ConnectionLibary.NewSignal(),
		_miss             = ConnectionLibary.NewSignal(),
		_finished         = ConnectionLibary.NewSignal(),
		_cancelled        = ConnectionLibary.NewSignal(),
		_destroyed        = ConnectionLibary.NewSignal(),
		_activeConnection = nil,
		_alreadyHit       = nil,
		_beforeHit        = nil,
		_debug            = false,
	}, module) :: Type
end

--════════════════════════════════════════════════--
-- Meta-Methods
function module.__index(self: Type, key: string)
	if key == "OnHit" then return self._hit end
	if key == "OnMiss" then return self._miss end
	if key == "OnFinished" then return self._finished end
	if key == "OnCancel" then return self._cancelled end
	if key == "OnDestroy" then return self._destroyed end
	if module[key] then return module[key] end
	if VAR_SWITCH[key] then return self[VAR_SWITCH[key]] end
end

function module.__newindex(self: Type, key: string, value: any)
	if VAR_SWITCH[key] then
		rawset(self, VAR_SWITCH[key], value)
	else
		rawset(self, key, value)
	end
end
--══════════════════════════════════--
-- Code Break (Rename)

local function _applyUpdate(self: Type, update: FireUpdate?)
	if not update then return end
	if update.Origin then self._origin = update.Origin end
	if update.Direction then self._direction = update.Direction end
	if update.Size then self._size = update.Size end
	if update.Radius then self._radius = update.Radius end
end

local function _splitArgs(updateOrCheck: (FireUpdate | HitCheck)?, maybeCheck: HitCheck?): (FireUpdate?, HitCheck?)
	if type(updateOrCheck) == "table" then
		return updateOrCheck :: FireUpdate, maybeCheck
	end
	return nil, updateOrCheck :: HitCheck?
end

-- Distinguishes the three valid second-arg shapes for FireUntil:
--   table              -> static FireUpdate, applied once and reused every tick (existing behavior)
--   function, 1 arg    -> FireTrackingFn, called fresh every tick with dt
--   function, 3 args   -> HitCheck, same as Fire's existing behavior
-- Arity is read via debug.info, same pattern already used to route METHOD_SWITCH.
local function _splitFireUntilArgs(updateOrTrackingFnOrCheck: (FireUpdate | FireTrackingFn | HitCheck)?, maybeCheck: HitCheck?): (FireUpdate?, FireTrackingFn?, HitCheck?)
	if type(updateOrTrackingFnOrCheck) == "table" then
		return updateOrTrackingFnOrCheck :: FireUpdate, nil, maybeCheck
	end
	if type(updateOrTrackingFnOrCheck) == "function" then
		local arity = debug.info(updateOrTrackingFnOrCheck, "a")
		if arity == 1 then
			return nil, updateOrTrackingFnOrCheck :: FireTrackingFn, maybeCheck
		end
		return nil, nil, updateOrTrackingFnOrCheck :: HitCheck
	end
	return nil, nil, nil
end

--[[
	Fire(): runs one geometry check immediately and returns the list of players hit.
	Two call shapes:
 		Fire()                          -- just check, using whatever Origin/Direction/etc. are currently set
	   	Fire(check)                     -- same, but validates each candidate with a HitCheck (only used by "Custom")
	   	Fire(update)                    -- applies a FireUpdate snapshot first, then checks
	   	Fire(update, check)             -- applies the update, then checks with a HitCheck
   	`check` is ignored for built-in shapes (Cube/Sphere/Cone/Cylinder/Pyramid) — they
	 have their own geometry test built in. It's only consumed by the "Custom" type.
]]
function module.Fire(self: Type, updateOrCheck: (FireUpdate | HitCheck)?, maybeCheck: HitCheck?)
	local update, Check = _splitArgs(updateOrCheck, maybeCheck)
	_applyUpdate(self, update)

	local args = debug.info(METHOD_SWITCH[self._type], "a")
	if args == 2 then
		return METHOD_SWITCH[self._type](self, Check)
	end
	return METHOD_SWITCH[self._type](self)
end

local function _collectHitList(self: Type): {Player}
	local list = {}
	if self._alreadyHit then
		for player in self._alreadyHit do
			table.insert(list, player)
		end
	end
	return list
end

--[[ 
	FireUntil(): runs Fire() every Heartbeat for `TimeOut` seconds (or until :Cancel()'d),
		 deduping hits per-player across the whole run. Fires OnFinished on natural completion,
		 or OnCancel if stopped early (manually, or due to a per-tick error).
		
		 Three call shapes for the third argument:
		   FireUntil(timeout)                          -- just sustained checking, nothing fancy
		   FireUntil(timeout, check)                    -- check is a HitCheck (3 params), used by "Custom"
		   FireUntil(timeout, trackingFn)               -- trackingFn is a FireTrackingFn (1 param: dt),		                                                    called every tick to recompute Origin/Direction/etc.
		                                                    for a moving target (e.g. a live blade, a moving spawn)
		   FireUntil(timeout, trackingFn, check)         -- both at once
		   FireUntil(timeout, staticUpdate)              -- staticUpdate is a FireUpdate table, applied once
		                                                    up front (NOT re-evaluated per tick — use trackingFn
		                                                    instead if you need live per-tick updates)
		   FireUntil(timeout, staticUpdate, check)        -- both at once
		
		 The third argument's *type* and, for functions, its *parameter count* determine which
		 of the above you get — a table is always a staticUpdate, a 1-parameter function is
		 always a trackingFn, and a 3-parameter function is always a check. This is read via
		 debug.info at runtime, so a trackingFn MUST be written with exactly one parameter (dt)
		 or it will be misinterpreted as a HitCheck.
]]
function module.FireUntil(self: Type, TimeOut: number, updateOrTrackingFnOrCheck: (FireUpdate | FireTrackingFn | HitCheck)?, maybeCheck: HitCheck?): RBXScriptConnection
	-- prevent overlapping swing-checks on the same Hitbox instance
	self:Cancel()

	local staticUpdate, TrackingFn, Check = _splitFireUntilArgs(updateOrTrackingFnOrCheck, maybeCheck)
	_applyUpdate(self, staticUpdate) -- applied once up front if a static table was passed
	self._alreadyHit = {}

	local Connection: RBXScriptConnection
	Connection = RunService.Heartbeat:Connect(function(dt: number)
		TimeOut -= dt

		local ok, result = pcall(function()
			if TrackingFn then
				_applyUpdate(self, TrackingFn(dt))
			end
			return self:Fire(Check)
		end)

		if ok and result then
			for _, player in result do
				self._alreadyHit[player] = true
			end
		elseif not ok then
			-- swallow per-tick errors (e.g. weapon unequipped mid-swing) and stop cleanly
			warn("[Hitbox] FireUntil tick error, cancelling:", result)
			Connection:Disconnect()
			self._activeConnection = nil
			self._cancelled:Fire("Error", _collectHitList(self))
			return
		end

		if TimeOut <= 0 then
			Connection:Disconnect()
			self._activeConnection = nil
			self._finished:Fire("Timeout", _collectHitList(self))
		end
	end)

	self._activeConnection = Connection
	return Connection
end

function module.Cancel(self: Type)
	if self._activeConnection then
		self._activeConnection:Disconnect()
		self._activeConnection = nil
		self._cancelled:Fire("Manual", _collectHitList(self))
	end
	self._alreadyHit = nil
end

function module.IsActive(self: Type): boolean
	return self._activeConnection ~= nil
end

function module.Destroy(self: Type)
	self:Cancel()
	self._destroyed:Fire()
	self._hit:Destroy()
	self._miss:Destroy()
	self._finished:Destroy()
	self._cancelled:Destroy()
	self._destroyed:Destroy()
end

-- OnBeforeHit: registers a veto callback. Return false (or error) to cancel the hit
-- before OnHit fires. Only one veto callback per Hitbox instance — last one wins.
function module.OnBeforeHit(self: Type, handler: ((Player: Player, Limb: BasePart, Point: Vector3) -> boolean?)?)
	self._beforeHit = handler
end

-- Debug: when enabled, every Fire()/FireUntil() tick auto-draws this hitbox's
-- current shape via the Visuals library, no separate Visuals.* call needed.
function module.Debug(self: Type, enabled: boolean)
	self._debug = enabled
end

--════════════════════════════════════════════════--
-- Shape setter helpers
-- These derive the broad-phase `Size`/`Radius` automatically so callers never
-- have to hand-compute a bounding box that matches the real shape params.

function module.SetCube(self: Type, origin: Vector3, direction: Vector3, size: Vector3)
	self._type = "Cube"
	self._origin = origin
	self._direction = direction.Magnitude > 0 and direction.Unit or self._direction
	self._size = size
end

function module.SetSphere(self: Type, origin: Vector3, radius: number)
	self._type = "Sphere"
	self._origin = origin
	self._radius = radius
end

function module.SetCone(self: Type, origin: Vector3, direction: Vector3, range: number, angleDegrees: number)
	self._type = "Cone"
	self._origin = origin
	self._direction = direction.Unit
	self._range = range
	self._angle = angleDegrees
	local bound = range * 2
	self._size = Vector3.new(bound, bound, bound)
end

function module.SetCylinder(self: Type, origin: Vector3, direction: Vector3, radius: number, height: number)
	self._type = "Cylinder"
	self._origin = origin
	self._direction = direction.Unit
	self._radius = radius
	self._size = Vector3.new(radius * 2, height, radius * 2)
end

function module.SetPyramid(self: Type, origin: Vector3, direction: Vector3, baseHalfWidth: number, height: number)
	self._type = "Pyramid"
	self._origin = origin
	self._direction = direction.Unit
	self._radius = baseHalfWidth
	self._size = Vector3.new(baseHalfWidth * 2, height, baseHalfWidth * 2)
end

function module.SetCapsule(self: Type, pointA: Vector3, pointB: Vector3, radius: number): HitCheck
	self._type = "Custom"
	local mid = (pointA + pointB) / 2
	local segment = pointB - pointA
	local axis = segment.Magnitude > 0 and segment.Unit or Vector3.yAxis
	self._origin = mid
	self._direction = axis
	self._size = Vector3.new(segment.Magnitude + radius * 2, radius * 2, radius * 2)

	return function(point: Vector3): boolean
		local segLenSq = segment:Dot(segment)
		local t = segLenSq > 0 and math.clamp((point - pointA):Dot(segment) / segLenSq, 0, 1) or 0
		local closest = pointA + segment * t
		return (point - closest).Magnitude <= radius
	end
end
-- Module End

return module :: {
	New: (HitType: HitTypes) -> (Type),
}
