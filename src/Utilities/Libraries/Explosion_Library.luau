--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Explosion_Library
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Shared blast resolver for Explosive/Launcher
--                  firearms (and later, Throw grenades). Target
--                  discovery in a radius, line-of-sight occlusion,
--                  distance falloff, and client-side explosion VFX.
--                  The SERVER calls Apply() to deal authoritative
--                  damage (FireArmRoutes explode route); the CLIENT
--                  only ever calls CreateExplosionVFX for the visuals.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris    = game:GetService("Debris")
--► Tables       ◄--
local Module = {}
--► Constants    ◄--
-- Damage floor at the blast edge when falloff is on — direct hits always
-- hurt more, but edge clips never round to zero.
Module.EdgeFraction = 0.2
Module.DefaultExplosionSound = "rbxasset://sounds/collide.wav"

export type BlastTarget = {
	Character : Model,
	Humanoid  : Humanoid,
	RootPart  : BasePart,
	Distance  : number,
}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RESOLUTION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Damage fraction for a target at `distance` from the blast center.
--  Falloff on: linear 1 → EdgeFraction across the radius. Off: full
--  damage anywhere inside. Always 0 beyond the radius.
Module.DamageFraction = function(distance: number, radius: number, useFalloff: boolean?): number
	if distance > radius then
		return 0
	end
	if useFalloff == false then
		return 1
	end
	local t = distance / math.max(radius, 1e-4)
	return 1 - t * (1 - Module.EdgeFraction)
end

--► Finds every living Humanoid character within the radius — all player
--  characters plus top-level Workspace models with a Humanoid (test
--  dummies / NPCs). Sorted nearest-first.
Module.FindTargets = function(center: Vector3, radius: number): {BlastTarget}
	local targets: {BlastTarget} = {}
	local seen: {[Model]: true} = {}

	local function consider(model: Instance?)
		if not model or not model:IsA("Model") or seen[model :: Model] then
			return
		end
		local humanoid = (model :: Model):FindFirstChildOfClass("Humanoid")
		local root = (model :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or humanoid.Health <= 0 or not root then
			return
		end
		local distance = (root.Position - center).Magnitude
		if distance > radius then
			return
		end
		seen[model :: Model] = true
		table.insert(targets, {Character = model :: Model, Humanoid = humanoid, RootPart = root, Distance = distance})
	end

	for _, player in ipairs(Players:GetPlayers()) do
		consider(player.Character)
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		consider(child)
	end

	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)
	return targets
end

--► True when the blast center can "see" the target — nothing static
--  between them (the target's own character is ignored). Blasts don't
--  reach through walls.
Module.HasLineOfSight = function(center: Vector3, target: BlastTarget): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {target.Character}

	local delta = target.RootPart.Position - center
	if delta.Magnitude < 1e-3 then
		return true
	end
	local result = Workspace:Raycast(center, delta, params)
	return result == nil
end

--► SERVER: deals blast damage to everything valid in the radius.
--  Occluded targets (behind walls) take nothing. `ignoreCharacter`
--  usually excludes... nothing — shooters CAN hurt themselves with
--  rockets; pass their character only if you want self-damage off.
--  Returns what was damaged so the caller can fire weapon events.
Module.Apply = function(center: Vector3, radius: number, damage: number, useFalloff: boolean?, ignoreCharacter: Model?): {{Character: Model, Damage: number}}
	local damaged = {}

	for _, target in ipairs(Module.FindTargets(center, radius)) do
		if target.Character == ignoreCharacter then
			continue
		end
		if not Module.HasLineOfSight(center, target) then
			continue
		end

		local dealt = damage * Module.DamageFraction(target.Distance, radius, useFalloff)
		if dealt > 0 then
			target.Humanoid:TakeDamage(dealt)
			table.insert(damaged, {Character = target.Character, Damage = dealt})
		end
	end

	return damaged
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	VFX (client)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Spawns the visual explosion at a position — a damage-neutral Roblox
--  Explosion (no BlastPressure/joint breaking; damage is the server's
--  job) plus a low boom. Scale roughly tracks the blast radius.
Module.CreateExplosionVFX = function(position: Vector3, radius: number, soundId: string?)
	local explosion = Instance.new("Explosion")
	explosion.Position                 = position
	explosion.BlastRadius               = radius
	explosion.BlastPressure              = 0 -- visual only — no physics fling, no part damage
	explosion.DestroyJointRadiusPercent   = 0
	explosion.Parent = Workspace

	local holder = Instance.new("Part")
	holder.Anchored     = true
	holder.CanCollide    = false
	holder.CanQuery       = false
	holder.CanTouch        = false
	holder.Transparency     = 1
	holder.Size = Vector3.new(0.05, 0.05, 0.05)
	holder.CFrame = CFrame.new(position)
	holder.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId            = soundId or Module.DefaultExplosionSound
	sound.Volume              = 2
	sound.PlaybackSpeed        = 0.4 -- pitched way down = a passable boom from a stock thud
	sound.RollOffMaxDistance    = 400
	sound.Parent = holder
	sound:Play()

	Debris:AddItem(holder, 5)
end

return Module
