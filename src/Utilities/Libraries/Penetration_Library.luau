--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Penetration_Library
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: The shared penetrating-shot resolver. Casts a round
--                  through surfaces following a firearm config's
--                  Penetration block (Penetration_Count,
--                  Material_Penetration Thickness/Power,
--                  Ricochet_Angle_Degrees), with angle-corrected wall
--                  thickness and ricochet bounces via Normal_Library.
--
--                  Context-free on purpose: FireArm_Class runs it on the
--                  client for prediction/VFX, and FireArmRoutes re-runs
--                  the IDENTICAL logic server-side to validate reported
--                  hits and recompute authoritative damage — both sides
--                  must resolve shots the same way or they will disagree.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local Workspace = game:GetService("Workspace")
--► Requires     ◄--
local Normal = require(script.Parent.Normal_Library)
--► Tables       ◄--
local Module = {}
--► Constants    ◄--
-- Damage retained when passing through a character (flesh has no
-- Material_Penetration entry) — matches the old flat penetration falloff.
Module.CharacterRetention = 0.75
-- Damage retained after a ricochet bounce.
Module.RicochetRetention  = 0.5

--► Types        ◄--
-- One resolved surface along a penetrating shot. DamageMultiplier is the
-- damage fraction remaining when this surface was struck (1 for the first
-- hit). Ricocheted marks a hit that bounced the round rather than
-- stopping/penetrating — the following hit (if any) is along the
-- reflected ray.
export type PenetrationHit = {
	Result           : RaycastResult,
	DamageMultiplier : number,
	Ricocheted       : boolean?,
	-- Set when the round passed THROUGH this surface: where and which way
	-- it came out the far side — VFX draws the exit hole from these.
	ExitPosition     : Vector3?,
	ExitNormal       : Vector3?,
}

-- What happened to the round at one surface, and how it continues.
export type SurfaceVerdict = {
	Action       : "Stop" | "Through" | "Ricochet",
	Multiplier   : number,    -- damage multiplier AFTER this surface
	Direction    : Vector3,   -- travel direction after this surface
	NextOrigin   : Vector3,   -- continuation point (offset off the surface)
	ExitPosition : Vector3?,  -- far-face exit, when Action == "Through" a wall
	ExitNormal   : Vector3?,
}

-- Returns true if the part belongs to a Humanoid character.
local function _isCharacterPart(part: Instance): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

--► Decides what one surface does to the round — the single shared rule
--  used by the straight-line Cast below AND the stepped projectile
--  simulation (Projectile_Library), so hitscan and physical bullets
--  penetrate/ricochet identically.
Module.ResolveSurface = function(result: RaycastResult, direction: Vector3, penCfg: any, penetrationIndex: number, multiplier: number): SurfaceVerdict
	if _isCharacterPart(result.Instance) then
		return {
			Action     = "Through",
			Multiplier = multiplier * Module.CharacterRetention,
			Direction  = direction,
			NextOrigin = Normal.OffsetThrough(result.Position, direction),
		}
	end

	if Normal.ShouldRicochet(direction, result.Normal, penCfg.Ricochet_Angle_Degrees) then
		local bounced = Normal.Reflect(direction, result.Normal)
		return {
			Action     = "Ricochet",
			Multiplier = multiplier * Module.RicochetRetention,
			Direction  = bounced,
			NextOrigin = Normal.OffsetAway(result.Position, result.Normal),
		}
	end

	local matEntry = penCfg.Material_Penetration and penCfg.Material_Penetration[result.Material]
	if not matEntry then
		return {Action = "Stop", Multiplier = multiplier, Direction = direction, NextOrigin = result.Position}
	end

	-- Angle-corrected allowance, then measure the wall with a reverse
	-- probe from just past it. A probe that starts inside the part (wall
	-- too thick) finds no exit face — thickness reads infinite, round stops.
	local maxPath = Normal.MaxPathThrough(matEntry.Thickness, direction, result.Normal)
	local probeStart = result.Position + direction * (maxPath + 0.1)
	local backParams = RaycastParams.new()
	backParams.FilterType = Enum.RaycastFilterType.Include
	backParams.FilterDescendantsInstances = {result.Instance}
	local exit = Workspace:Raycast(probeStart, -direction * (maxPath + 0.2), backParams)
	local pathThroughWall = exit and Normal.PathLength(result.Position, exit.Position) or math.huge
	if pathThroughWall > maxPath then
		return {Action = "Stop", Multiplier = multiplier, Direction = direction, NextOrigin = result.Position}
	end

	local power = matEntry.Power
	return {
		Action       = "Through",
		Multiplier   = multiplier * ((power and (power[penetrationIndex] or power[#power])) or Module.CharacterRetention),
		Direction    = direction,
		NextOrigin   = Normal.OffsetThrough(result.Position, direction),
		ExitPosition = exit and exit.Position or nil,
		ExitNormal   = exit and exit.Normal or nil,
	}
end

--[[
	Casts a round through up to penCfg.Penetration_Count surfaces.

	Per surface, in order:
	• Character parts — always penetrable at CharacterRetention.
	• Impacts at or under Ricochet_Angle_Degrees against the surface
	  plane — the round BOUNCES: direction reflects off the normal,
	  damage drops to RicochetRetention, and the cast continues (the
	  bounce consumes a penetration slot).
	• Material with a Material_Penetration entry — penetrable when the
	  measured path through the wall fits the angle-corrected allowance
	  (Normal.MaxPathThrough of the entry's Thickness); damage scales by
	  Power[penetrationNumber] (last entry reused).
	• Anything else stops the round.

	`params` is mutated (exclusion list grows per surface) — hand in a
	fresh RaycastParams per shot.
]]
Module.Cast = function(origin: Vector3, direction: Vector3, penCfg: any, maxDistance: number, params: RaycastParams): {PenetrationHit}
	local hits: {PenetrationHit} = {}
	local excluded = table.clone(params.FilterDescendantsInstances)
	local multiplier = 1
	local maxHits = math.max(penCfg.Penetration_Count or 1, 1)
	local remaining = maxDistance
	local currentOrigin = origin
	local currentDirection = direction

	for index = 1, maxHits do
		params.FilterDescendantsInstances = excluded
		local result = Workspace:Raycast(currentOrigin, currentDirection * remaining, params)
		if not result then
			break
		end

		local hit: PenetrationHit = {Result = result, DamageMultiplier = multiplier}
		table.insert(hits, hit)

		if index == maxHits then
			break
		end

		local verdict = Module.ResolveSurface(result, currentDirection, penCfg, index, multiplier)
		if verdict.Action == "Stop" then
			break
		end

		hit.Ricocheted   = verdict.Action == "Ricochet" or nil
		hit.ExitPosition = verdict.ExitPosition
		hit.ExitNormal   = verdict.ExitNormal

		multiplier       = verdict.Multiplier
		currentDirection = verdict.Direction
		currentOrigin    = verdict.NextOrigin
		table.insert(excluded, result.Instance)

		remaining = maxDistance - (result.Position - origin).Magnitude
		if remaining <= 0 then
			break
		end
	end

	return hits
end

--► Server-side hit verification: re-runs Cast from the shooter toward a
--  claimed hit and looks for the claimed part among the resolved
--  surfaces. Returns the matching hit (with its authoritative
--  DamageMultiplier) or nil if the shot could not have reached it —
--  wrong part, blocked line of fire, or beyond penetration ability.
--  `tolerance` (studs, default 5) allows for the client camera origin
--  differing from the server-side shooter position.
Module.VerifyHit = function(origin: Vector3, targetPosition: Vector3, claimedPart: Instance, penCfg: any, maxDistance: number, params: RaycastParams, tolerance: number?): PenetrationHit?
	local direction = targetPosition - origin
	if direction.Magnitude < 1e-4 then
		return nil
	end

	local hits = Module.Cast(origin, direction.Unit, penCfg, maxDistance, params)
	local allowed = tolerance or 5

	for _, hit in ipairs(hits) do
		local samePart = hit.Result.Instance == claimedPart
			or claimedPart:IsDescendantOf(hit.Result.Instance)
			or hit.Result.Instance:IsDescendantOf(claimedPart.Parent or claimedPart)
		if samePart and Normal.PathLength(hit.Result.Position, targetPosition) <= allowed then
			return hit
		end
	end

	return nil
end

return Module
