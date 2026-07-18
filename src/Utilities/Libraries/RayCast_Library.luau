--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Raycast_Library
--  ◄► Version:     1.0
--  ◄► Date:        28/05/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable raycast and shapecast module
--                  for use in Roblox game development.
--                  Normal raycasts, sphere/box/block shapecasts,
--                  multi-hit, filter helpers, and common patterns
--                  like ground checks, sight lines, and mouse picking.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
--► Constants    ◄--
Module.DefaultMaxDistance = 1000
Module.DefaultRayParams   = nil   -- set once at startup if you want global defaults

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RAYCASTPARAMS BUILDERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a blank RaycastParams with no filter
Module.Params = function(): RaycastParams
	return RaycastParams.new()
end

--► Returns RaycastParams that exclude a list of instances (and their descendants)
Module.ParamsExclude = function(instances: {Instance}): RaycastParams
	local p = RaycastParams.new()
	p.FilterType         = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = instances
	return p
end

--► Returns RaycastParams that include ONLY a list of instances
Module.ParamsInclude = function(instances: {Instance}): RaycastParams
	local p = RaycastParams.new()
	p.FilterType         = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = instances
	return p
end

--► Returns RaycastParams that exclude a character and all its descendants
Module.ParamsExcludeCharacter = function(character: Model): RaycastParams
	return Module.ParamsExclude({character})
end

--► Returns RaycastParams that exclude the local player's character
Module.ParamsExcludeLocalPlayer = function(): RaycastParams
	local player = Players.LocalPlayer
	local char   = player and player.Character
	return char and Module.ParamsExclude({char}) or RaycastParams.new()
end

--► Returns RaycastParams that exclude all current player characters
Module.ParamsExcludeAllPlayers = function(): RaycastParams
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(chars, p.Character) end
	end
	return Module.ParamsExclude(chars)
end

--► Returns RaycastParams that only hit terrain
Module.ParamsTerrainOnly = function(): RaycastParams
	return Module.ParamsInclude({workspace.Terrain})
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	NORMAL RAYCASTS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Casts a ray from origin in a direction and returns the RaycastResult or nil
Module.Cast = function(origin: Vector3, direction: Vector3, params: RaycastParams?): RaycastResult?
	return workspace:Raycast(origin, direction, params or Module.DefaultRayParams)
end

--► Casts a ray from origin toward a target position and returns the result or nil
Module.CastTo = function(origin: Vector3, target: Vector3, params: RaycastParams?): RaycastResult?
	return Module.Cast(origin, target - origin, params)
end

--► Casts a ray with an explicit maximum distance in a unit direction
Module.CastDistance = function(origin: Vector3, direction: Vector3, maxDistance: number, params: RaycastParams?): RaycastResult?
	return Module.Cast(origin, direction.Unit * maxDistance, params)
end

--► Returns true if a ray hits anything between origin and target (line of sight check)
Module.HasLineOfSight = function(origin: Vector3, target: Vector3, params: RaycastParams?): boolean
	return Module.CastTo(origin, target, params) == nil
end

--► Returns the hit position of a ray, or the end point if nothing was hit
Module.HitPositionOrEnd = function(origin: Vector3, direction: Vector3, params: RaycastParams?): Vector3
	local result = Module.Cast(origin, direction, params)
	return result and result.Position or origin + direction
end

--► Returns the hit instance of a ray (the Part/Terrain that was struck), or nil
Module.HitInstance = function(origin: Vector3, direction: Vector3, params: RaycastParams?): Instance?
	local result = Module.Cast(origin, direction, params)
	return result and result.Instance
end

--► Returns the surface normal of a ray hit, or Vector3.new(0,1,0) if nothing was hit
Module.HitNormal = function(origin: Vector3, direction: Vector3, params: RaycastParams?): Vector3
	local result = Module.Cast(origin, direction, params)
	return result and result.Normal or Vector3.new(0, 1, 0)
end

--► Returns the distance to the hit point, or the full ray length if nothing was hit
Module.HitDistance = function(origin: Vector3, direction: Vector3, params: RaycastParams?): number
	local result = Module.Cast(origin, direction, params)
	return result and (result.Position - origin).Magnitude or direction.Magnitude
end

--► Casts a ray downward from a position and returns how far above the ground it is
-- Returns math.huge if nothing is below
Module.DistanceToGround = function(position: Vector3, maxDistance: number?, params: RaycastParams?): number
	local result = Module.Cast(position, Vector3.new(0, -(maxDistance or 500), 0), params)
	return result and (position - result.Position).Magnitude or math.huge
end

--► Returns true if a position is on the ground within a given threshold
Module.IsGrounded = function(position: Vector3, threshold: number?, params: RaycastParams?): boolean
	return Module.DistanceToGround(position, threshold or 1.5, params) <= (threshold or 1.5)
end

--► Finds the ground position directly below a point
-- Returns the hit position or nil if nothing was found
Module.GetGroundPosition = function(position: Vector3, maxDistance: number?, params: RaycastParams?): Vector3?
	local result = Module.Cast(position, Vector3.new(0, -(maxDistance or 500), 0), params)
	return result and result.Position
end

--► Casts multiple rays in a spread pattern and returns all results
-- count: number of rays, spreadAngle: cone half-angle in degrees
Module.CastSpread = function(origin: Vector3, direction: Vector3, count: number, spreadAngle: number, params: RaycastParams?): {RaycastResult}
	local results = {}
	local rad     = math.rad(spreadAngle)
	for _ = 1, count do
		local randX = (math.random() * 2 - 1) * rad
		local randY = (math.random() * 2 - 1) * rad
		local spread = CFrame.new(Vector3.zero, direction) * CFrame.Angles(randX, randY, 0)
		local dir    = spread.LookVector * direction.Magnitude
		local result = Module.Cast(origin, dir, params)
		if result then table.insert(results, result) end
	end
	return results
end

--► Casts a ray from a Camera through the mouse cursor position
-- Returns the RaycastResult or nil
Module.MouseRay = function(camera: Camera, params: RaycastParams?): RaycastResult?
	local mouse  = UserInputService:GetMouseLocation()
	local ray    = camera:ViewportPointToRay(mouse.X, mouse.Y)
	return Module.CastDistance(ray.Origin, ray.Direction, Module.DefaultMaxDistance, params)
end

--► Returns the world position the mouse is pointing at
Module.MouseWorldPosition = function(camera: Camera, params: RaycastParams?): Vector3?
	local result = Module.MouseRay(camera, params)
	return result and result.Position
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SHAPECASTS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Casts a sphere along a direction and returns the first hit
-- radius: sphere radius in studs
Module.SphereCast = function(origin: Vector3, direction: Vector3, radius: number, params: RaycastParams?): RaycastResult?
	return workspace:Spherecast(origin, radius, direction, params or Module.DefaultRayParams)
end

--► Casts a sphere toward a target position
Module.SphereCastTo = function(origin: Vector3, target: Vector3, radius: number, params: RaycastParams?): RaycastResult?
	return Module.SphereCast(origin, target - origin, radius, params)
end

--► Casts a sphere downward from a position — useful for character ground checks
-- More forgiving than a ray for characters on uneven terrain
Module.SphereGroundCheck = function(position: Vector3, radius: number?, maxDistance: number?, params: RaycastParams?): RaycastResult?
	return Module.SphereCast(position, Vector3.new(0, -(maxDistance or 10), 0), radius or 1, params)
end

--► Casts a box along a direction from an origin CFrame
-- size: half-extents of the box in studs
Module.BlockCast = function(originCF: CFrame, size: Vector3, direction: Vector3, params: RaycastParams?): RaycastResult?
	return workspace:Blockcast(originCF, size, direction, params or Module.DefaultRayParams)
end

--► Casts a box downward from a position — useful for vehicle/platform ground checks
Module.BoxGroundCheck = function(position: Vector3, size: Vector3?, maxDistance: number?, params: RaycastParams?): RaycastResult?
	return Module.BlockCast(
		CFrame.new(position),
		size or Vector3.new(1, 1, 1),
		Vector3.new(0, -(maxDistance or 10), 0),
		params
	)
end

--► Returns true if a sphere at a position overlaps anything
Module.SphereOverlap = function(position: Vector3, radius: number, params: RaycastParams?): boolean
	return Module.SphereCast(position, Vector3.new(0, 0.001, 0), radius, params) ~= nil
end

--► Returns all parts inside a sphere at a position using GetPartBoundsInRadius
-- This is NOT a cast — it returns parts already overlapping, not a directional sweep
Module.GetPartsInSphere = function(position: Vector3, radius: number, params: OverlapParams?): {BasePart}
	local op = params or OverlapParams.new()
	return workspace:GetPartBoundsInRadius(position, radius, op)
end

--► Returns all parts inside a box region using GetPartBoundsInBox
Module.GetPartsInBox = function(cf: CFrame, size: Vector3, params: OverlapParams?): {BasePart}
	local op = params or OverlapParams.new()
	return workspace:GetPartBoundsInBox(cf, size, op)
end

--► Returns the closest part to a position within a sphere
Module.ClosestPartInSphere = function(position: Vector3, radius: number, params: OverlapParams?): BasePart?
	local parts   = Module.GetPartsInSphere(position, radius, params)
	local closest = nil
	local bestDist = math.huge
	for _, part in ipairs(parts) do
		local dist = (part.Position - position).Magnitude
		if dist < bestDist then
			bestDist = dist
			closest  = part
		end
	end
	return closest
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	MULTI-HIT
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Casts a ray and collects ALL hits along its path up to a maximum count
-- Excludes previously hit instances each pass — simulates penetration
Module.CastMultiHit = function(origin: Vector3, direction: Vector3, maxHits: number?, params: RaycastParams?): {RaycastResult}
	local results   = {}
	local excluded  = {}
	local max       = maxHits or 10
	local p         = params  or RaycastParams.new()

	for _ = 1, max do
		p.FilterDescendantsInstances = excluded
		p.FilterType                 = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(origin, direction, p)
		if not result then break end

		table.insert(results,  result)
		table.insert(excluded, result.Instance)
	end

	return results
end

--► Casts a sphere and collects all hits along its path (penetrating sphere cast)
Module.SphereMultiHit = function(origin: Vector3, direction: Vector3, radius: number, maxHits: number?, params: RaycastParams?): {RaycastResult}
	local results  = {}
	local excluded = {}
	local max      = maxHits or 10
	local p        = params  or RaycastParams.new()

	for _ = 1, max do
		p.FilterDescendantsInstances = excluded
		p.FilterType                 = Enum.RaycastFilterType.Exclude

		local result = workspace:Spherecast(origin, radius, direction, p)
		if not result then break end

		table.insert(results,  result)
		table.insert(excluded, result.Instance)
	end

	return results
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	COMMON PATTERNS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Casts a ray from a part's CFrame in its look direction
Module.CastFromPart = function(part: BasePart, maxDistance: number?, params: RaycastParams?): RaycastResult?
	return Module.CastDistance(part.Position, part.CFrame.LookVector, maxDistance or Module.DefaultMaxDistance, params)
end

--► Casts downward from a character's root part to check if they are grounded
Module.CharacterGroundCheck = function(character: Model, threshold: number?, params: RaycastParams?): boolean
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local p = params or Module.ParamsExcludeCharacter(character)
	return Module.IsGrounded(root.Position, threshold or 3, p)
end

--► Returns the surface material under a character
Module.CharacterSurfaceMaterial = function(character: Model, params: RaycastParams?): Enum.Material?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local p      = params or Module.ParamsExcludeCharacter(character)
	local result = Module.Cast(root.Position, Vector3.new(0, -5, 0), p)
	return result and result.Material
end

--► Checks whether a bullet/projectile has a clear path from origin to target
-- Returns true if the path is clear, false + hit result if something is in the way
Module.BulletPathClear = function(origin: Vector3, target: Vector3, params: RaycastParams?): (boolean, RaycastResult?)
	local result = Module.CastTo(origin, target, params)
	if not result then return true, nil end
	local hitDist    = (result.Position - origin).Magnitude
	local targetDist = (target - origin).Magnitude
	if hitDist >= targetDist - 0.1 then return true, nil end
	return false, result
end

--► Returns the reflect direction of a ray that has bounced off a surface
Module.ReflectRay = function(incomingDirection: Vector3, surfaceNormal: Vector3): Vector3
	return incomingDirection - 2 * incomingDirection:Dot(surfaceNormal) * surfaceNormal
end

--► Simulates a bouncing ray that reflects off surfaces up to N times
-- Returns an array of {origin, hitPosition, normal} for each bounce
Module.BouncingRay = function(origin: Vector3, direction: Vector3, bounces: number, params: RaycastParams?): {{}}
	local hits    = {}
	local current = origin
	local dir     = direction

	for _ = 1, bounces do
		local result = Module.Cast(current, dir, params)
		if not result then
			table.insert(hits, {origin = current, position = current + dir, normal = nil})
			break
		end
		table.insert(hits, {origin = current, position = result.Position, normal = result.Normal, instance = result.Instance})
		current = result.Position + result.Normal * 0.01  -- offset to avoid self-hit
		dir     = Module.ReflectRay(dir, result.Normal)
	end

	return hits
end

--► Casts a ray from the center of a viewport (crosshair) through the 3D world
-- Useful for first-person aiming
Module.ViewportCenterRay = function(camera: Camera, maxDistance: number?, params: RaycastParams?): RaycastResult?
	local vp     = camera.ViewportSize
	local ray    = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	return Module.CastDistance(ray.Origin, ray.Direction, maxDistance or Module.DefaultMaxDistance, params)
end

--► Returns the 3D position at the center of the viewport (where the crosshair points)
Module.CrosshairWorldPosition = function(camera: Camera, params: RaycastParams?): Vector3
	local result = Module.ViewportCenterRay(camera, nil, params)
	if result then return result.Position end
	local vp  = camera.ViewportSize
	local ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	return ray.Origin + ray.Direction * Module.DefaultMaxDistance
end

return Module