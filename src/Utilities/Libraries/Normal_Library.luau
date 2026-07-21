--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Normal_Library
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Surface-normal math for hit resolution — incidence
--                  angles, ricochet decisions, reflection, effective
--                  (angle-corrected) wall thickness, and safe surface
--                  offsets for continuing casts past a hit. Built for
--                  the penetration pipeline (FireArm_Class /
--                  FireArmRoutes) but weapon-agnostic: everything here
--                  is pure Vector3 math on a hit direction + normal.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Tables       ◄--
local Module = {}
--► Constants    ◄--
-- Nudge distance used by OffsetThrough/OffsetAway so a continued raycast
-- never re-hits the surface it just resolved due to float error.
Module.SurfaceEpsilon = 0.05

local EPSILON = 1e-6

-- Returns v normalized, or nil if it has no meaningful length.
local function _unit(v: Vector3): Vector3?
	if v.Magnitude < EPSILON then
		return nil
	end
	return v.Unit
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ORIENTATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the normal flipped (if needed) so it opposes the ray direction.
--  Raycast normals already face the ray for outside hits, but a cast that
--  starts inside geometry (or double-sided meshes) can hand back the far
--  face — always run hit normals through this before angle math.
Module.FaceAgainst = function(normal: Vector3, direction: Vector3): Vector3
	if normal:Dot(direction) > 0 then
		return -normal
	end
	return normal
end

--► Projects a vector onto the plane defined by a normal (removes the
--  component along the normal). Useful for sliding/deflection vectors.
Module.ProjectOnPlane = function(vector: Vector3, normal: Vector3): Vector3
	local n = _unit(normal)
	if not n then
		return vector
	end
	return vector - n * vector:Dot(n)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ANGLES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Angle (radians) between the incoming ray and the surface NORMAL.
--  0 = head-on (perpendicular to the surface), pi/2 = perfectly grazing.
Module.IncidenceAngle = function(direction: Vector3, normal: Vector3): number
	local d = _unit(direction)
	local n = _unit(normal)
	if not d or not n then
		return 0
	end
	n = Module.FaceAgainst(n, d)
	-- -d:Dot(n) is cos(angle from the normal); clamp for float safety.
	return math.acos(math.clamp(-d:Dot(n), 0, 1))
end

--► Angle (degrees) between the incoming ray and the surface PLANE.
--  90 = head-on, 0 = perfectly grazing. This is the convention weapon
--  configs use for Ricochet_Angle_Degrees ("bounces at or under N°").
Module.GrazeAngleDegrees = function(direction: Vector3, normal: Vector3): number
	return 90 - math.deg(Module.IncidenceAngle(direction, normal))
end

--► True when the impact is at or shallower than ricochetAngleDegrees
--  against the surface plane — the round should bounce, not penetrate.
--  Pass Config.Penetration.Ricochet_Angle_Degrees; nil/0 never ricochets.
Module.ShouldRicochet = function(direction: Vector3, normal: Vector3, ricochetAngleDegrees: number?): boolean
	if not ricochetAngleDegrees or ricochetAngleDegrees <= 0 then
		return false
	end
	return Module.GrazeAngleDegrees(direction, normal) <= ricochetAngleDegrees
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	REFLECTION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Reflects a direction off a surface normal (mirror bounce). Returns a
--  unit vector — use for ricochet continuation rays and shrapnel.
Module.Reflect = function(direction: Vector3, normal: Vector3): Vector3
	local d = _unit(direction)
	local n = _unit(normal)
	if not d or not n then
		return direction
	end
	n = Module.FaceAgainst(n, d)
	return (d - 2 * d:Dot(n) * n).Unit
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	THICKNESS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Converts a material's face-on thickness limit into the max path length
--  a round may travel through it when entering at this angle. A 0.5-stud
--  wall crossed at 60° from the normal is 1 stud of material along the
--  ray — shallow hits are effectively thicker. Capped so grazing angles
--  don't return absurd/infinite allowances.
Module.MaxPathThrough = function(thickness: number, direction: Vector3, normal: Vector3, maxMultiplier: number?): number
	local cosine = math.cos(Module.IncidenceAngle(direction, normal))
	local cap    = maxMultiplier or 4
	return thickness * math.min(1 / math.max(cosine, EPSILON), cap)
end

--► Path length between an entry and exit point along a ray — the actual
--  material traversed, for comparing against MaxPathThrough.
Module.PathLength = function(entryPosition: Vector3, exitPosition: Vector3): number
	return (exitPosition - entryPosition).Magnitude
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SURFACE OFFSETS — safe continuation points for chained casts
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► A point nudged past the hit along the ray — where a penetration
--  continuation cast should start so it can't re-hit the entry face.
Module.OffsetThrough = function(hitPosition: Vector3, direction: Vector3, epsilon: number?): Vector3
	local d = _unit(direction)
	if not d then
		return hitPosition
	end
	return hitPosition + d * (epsilon or Module.SurfaceEpsilon)
end

--► A point nudged off the surface along its normal — where impact VFX
--  (decals, debris, ricochet sparks) should spawn without z-fighting.
Module.OffsetAway = function(hitPosition: Vector3, normal: Vector3, epsilon: number?): Vector3
	local n = _unit(normal)
	if not n then
		return hitPosition
	end
	return hitPosition + n * (epsilon or Module.SurfaceEpsilon)
end

return Module
