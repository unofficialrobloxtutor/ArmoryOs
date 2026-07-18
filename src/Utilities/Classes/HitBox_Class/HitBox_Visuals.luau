--!nocheck
--[[ 
	Module Function
		Name: Hitbox Visuals Library
		Description:
			Debug-draw helpers for visualizing Hitbox volumes (Cube, Sphere, Cone,
			Cylinder, Pyramid, Capsule, plus Custom shapes like Octahedron/Helix).
			Mirrors the param shapes used by HitboxLibrary's Set* helpers so you can
			feed the same values into both with no translation step.

		Usage:
			local Visuals = require(...)
			Visuals.Cylinder(origin, direction, radius, height) -- auto-cleans up after Visuals.LifeTime
			Visuals.Cylinder(origin, direction, radius, height, { lifetime = 1, color = Color3.new(1,0,0) })

		All functions return the Instance(s) created, in case you want to manage
		cleanup yourself instead of relying on the auto-Debris timeout.
]]

-- Services
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local module = {}

-- Defaults (overridable per-call via the `opts` table, or globally here)
module.Enabled = true -- master switch; set false to no-op every draw call (e.g. in production builds)
module.LifeTime = 0.25
module.Color = Color3.fromRGB(0, 255, 0)
module.Transparency = 0.2
module.Material = Enum.Material.ForceField
module.Folder = workspace.World.Debug :: Folder? -- optional: set to a Folder instance to parent all debug parts there instead of workspace directly

type Opts = {
	lifetime: number?,
	color: Color3?,
	transparency: number?,
	material: Enum.Material?,
	parent: Instance?,
}

-- local helpers
local function _resolve(opts: Opts?)
	opts = opts or {}
	return {
		lifetime = opts.lifetime or module.LifeTime,
		color = opts.color or module.Color,
		transparency = opts.transparency or module.Transparency,
		material = opts.material or module.Material,
		parent = opts.parent or module.Folder or Workspace,
	}
end

local function _basePart(cfg): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = cfg.material
	part.Color = cfg.color
	part.Transparency = cfg.transparency
	return part
end

local function _finish(part: BasePart, cfg): BasePart
	part.Parent = cfg.parent
	Debris:AddItem(part, cfg.lifetime)
	return part
end

local function _perpBasis(axis: Vector3): (Vector3, Vector3)
	local arbitrary = math.abs(axis.Y) < 0.99 and Vector3.yAxis or Vector3.xAxis
	local right = axis:Cross(arbitrary).Unit
	local up = axis:Cross(right).Unit
	return right, up
end

--════════════════════════════════════════════════--
-- Cube
function module.Cube(origin: Vector3, direction: Vector3, size: Vector3, opts: Opts?): BasePart?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local part = _basePart(cfg)
	part.Shape = Enum.PartType.Block
	part.Size = size
	part.CFrame = CFrame.new(origin) * CFrame.lookAt(Vector3.zero, direction.Magnitude > 0 and direction or Vector3.zAxis)

	return _finish(part, cfg)
end

--════════════════════════════════════════════════--
-- Sphere
function module.Sphere(origin: Vector3, radius: number, opts: Opts?): BasePart?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local part = _basePart(cfg)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.CFrame = CFrame.new(origin)

	return _finish(part, cfg)
end

--════════════════════════════════════════════════--
-- Cylinder
function module.Cylinder(origin: Vector3, direction: Vector3, radius: number, height: number, opts: Opts?): BasePart?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local part = _basePart(cfg)
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, radius * 2, radius * 2) -- native cylinder axis = local X
	part.CFrame = CFrame.lookAt(origin, origin + direction.Unit) * CFrame.Angles(0, 0, math.rad(90))

	return _finish(part, cfg)
end

--════════════════════════════════════════════════--
-- Cone (wireframe ring at the cone's base + a tip marker, since there's no native cone PartType)
function module.Cone(origin: Vector3, direction: Vector3, range: number, angleDegrees: number, opts: Opts?): {BasePart}?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local axis = direction.Unit
	local right, up = _perpBasis(axis)
	local edgeRadius = range * math.tan(math.rad(angleDegrees / 2))
	local capCenter = origin + axis * range

	local parts = {}
	local segments = 16
	for i = 0, segments - 1 do
		local angle = (i / segments) * math.pi * 2
		local edgePoint = capCenter + (right * math.cos(angle) + up * math.sin(angle)) * edgeRadius

		local marker = _basePart(cfg)
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(0.4, 0.4, 0.4)
		marker.CFrame = CFrame.new(edgePoint)
		table.insert(parts, _finish(marker, cfg))
	end

	local tip = _basePart(cfg)
	tip.Shape = Enum.PartType.Ball
	tip.Size = Vector3.new(0.5, 0.5, 0.5)
	tip.CFrame = CFrame.new(origin)
	table.insert(parts, _finish(tip, cfg))

	return parts
end

--════════════════════════════════════════════════--
-- Pyramid (wireframe: 4 base corners + 4 edges from tip, since there's no native pyramid PartType)
function module.Pyramid(origin: Vector3, direction: Vector3, baseHalfWidth: number, height: number, opts: Opts?): {BasePart}?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local axis = direction.Unit
	local right, up = _perpBasis(axis)
	local baseCenter = origin + axis * height

	local corners = {
		baseCenter + (right * baseHalfWidth) + (up * baseHalfWidth),
		baseCenter + (right * baseHalfWidth) - (up * baseHalfWidth),
		baseCenter - (right * baseHalfWidth) + (up * baseHalfWidth),
		baseCenter - (right * baseHalfWidth) - (up * baseHalfWidth),
	}

	local parts = {}

	local function edge(a: Vector3, b: Vector3)
		local seg = b - a
		local len = seg.Magnitude
		if len == 0 then return end
		local mid = (a + b) / 2

		local line = _basePart(cfg)
		line.Shape = Enum.PartType.Block
		line.Size = Vector3.new(0.15, 0.15, len)
		line.CFrame = CFrame.lookAt(mid, b)
		table.insert(parts, _finish(line, cfg))
	end

	-- tip to each base corner
	for _, corner in corners do
		edge(origin, corner)
	end
	-- base square
	edge(corners[1], corners[2])
	edge(corners[2], corners[4])
	edge(corners[4], corners[3])
	edge(corners[3], corners[1])

	return parts
end

--════════════════════════════════════════════════--
-- Capsule (two end-cap spheres + a connecting cylinder)
function module.Capsule(pointA: Vector3, pointB: Vector3, radius: number, opts: Opts?): {BasePart}?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local segment = pointB - pointA
	local length = segment.Magnitude
	local parts = {}

	if length > 0 then
		local body = _basePart(cfg)
		body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(length, radius * 2, radius * 2)
		body.CFrame = CFrame.lookAt(pointA, pointB) * CFrame.Angles(0, 0, math.rad(90))
		table.insert(parts, _finish(body, cfg))
	end

	for _, capCenter in {pointA, pointB} do
		local cap = _basePart(cfg)
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		cap.CFrame = CFrame.new(capCenter)
		table.insert(parts, _finish(cap, cfg))
	end

	return parts
end

--════════════════════════════════════════════════--
-- Octahedron (8 face-normal markers; matches HitboxLibrary's buildOctahedronFaces pattern)
function module.Octahedron(origin: Vector3, radius: number, opts: Opts?): {BasePart}?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local parts = {}
	local signs = {-1, 1}
	for _, sx in signs do
		for _, sy in signs do
			for _, sz in signs do
				local normal = Vector3.new(sx, sy, sz).Unit
				local vertex = origin + normal * radius

				local marker = _basePart(cfg)
				marker.Shape = Enum.PartType.Ball
				marker.Size = Vector3.new(0.4, 0.4, 0.4)
				marker.CFrame = CFrame.new(vertex)
				table.insert(parts, _finish(marker, cfg))
			end
		end
	end

	return parts
end

--════════════════════════════════════════════════--
-- Helix (sampled points along the curve; matches HitboxLibrary's helixCheck pattern)
function module.Helix(origin: Vector3, axis: Vector3, radius: number, pitch: number, length: number, opts: Opts?): {BasePart}?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local axisUnit = axis.Unit
	local right, up = _perpBasis(axisUnit)
	local segments = 40

	local parts = {}
	for i = 0, segments do
		local alongAxis = (i / segments) * length
		local angle = (alongAxis / pitch) * math.pi * 2
		local pos = origin + axisUnit * alongAxis + (right * math.cos(angle) + up * math.sin(angle)) * radius

		local marker = _basePart(cfg)
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(0.5, 0.5, 0.5)
		marker.CFrame = CFrame.new(pos)
		table.insert(parts, _finish(marker, cfg))
	end

	return parts
end

--════════════════════════════════════════════════--
-- Point (generic single-position marker, e.g. for raycast hit points or OnHit callbacks)
function module.Point(position: Vector3, opts: Opts?): BasePart?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local marker = _basePart(cfg)
	marker.Shape = Enum.PartType.Ball
	marker.Size = Vector3.new(0.3, 0.3, 0.3)
	marker.CFrame = CFrame.new(position)

	return _finish(marker, cfg)
end

--════════════════════════════════════════════════--
-- Ray (thin block from origin along direction*distance, for visualizing raycasts)
function module.Ray(origin: Vector3, direction: Vector3, distance: number, opts: Opts?): BasePart?
	if not module.Enabled then return nil end
	local cfg = _resolve(opts)

	local axis = direction.Unit
	local endPoint = origin + axis * distance
	local mid = (origin + endPoint) / 2

	local line = _basePart(cfg)
	line.Shape = Enum.PartType.Block
	line.Size = Vector3.new(0.1, 0.1, distance)
	line.CFrame = CFrame.lookAt(mid, endPoint)

	return _finish(line, cfg)
end

--════════════════════════════════════════════════--
-- Toggle controls

function module.Enable()
	module.Enabled = true
end

function module.Disable()
	module.Enabled = false
end

function module.Toggle(): boolean
	module.Enabled = not module.Enabled
	return module.Enabled
end

-- Binds a chat-command toggle, server-side only. Call once from a server script, e.g.:
--   Visuals.BindToggleCommand("/hitboxdebug")
-- `isAuthorized` is optional — defaults to allowing everyone, since this is intended for
-- a dev/testing environment. Pass a function (e.g. checking against an admin list or
-- game:GetService("Players"):GetFriendsAsync` / your own permission system) to restrict it.
function module.BindToggleCommand(command: string, isAuthorized: ((Player) -> boolean)?)
	if not RunService:IsServer() then
		warn("HitboxVisuals.BindToggleCommand should only be called from the server")
		return
	end

	command = command:lower()

	Players.PlayerAdded:Connect(function(player: Player)
		player.Chatted:Connect(function(message: string)
			if message:lower() ~= command then return end
			if isAuthorized and not isAuthorized(player) then return end

			local state = module.Toggle()
			print(("[HitboxVisuals] %s %s debug visuals"):format(player.Name, state and "enabled" or "disabled"))
		end)
	end)
end


return module
