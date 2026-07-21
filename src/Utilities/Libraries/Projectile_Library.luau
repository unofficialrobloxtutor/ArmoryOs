--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Projectile_Library
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Stepped physical projectile simulation for
--                  Use_Part_As_Bullet firearms. Each Heartbeat the
--                  bullet advances by velocity*dt, drops under
--                  Workspace.Gravity * Gravity_Modifier, and sweeps the
--                  step with a raycast. Surfaces are judged by
--                  Penetration_Library.ResolveSurface — the same rule
--                  hitscan uses — so physical bullets penetrate and
--                  ricochet identically, just with travel time and drop.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris     = game:GetService("Debris")
--► Requires     ◄--
local Penetration = require(script.Parent.Penetration_Library)
--► Tables       ◄--
local Module = {}
--► Constants    ◄--
Module.DefaultMaxLifetime = 5 -- seconds a bullet may fly before force-cleanup

export type LaunchConfig = {
	Origin          : Vector3,
	Direction       : Vector3,          -- unit travel direction
	Speed           : number,           -- studs/s (Physics.Base_Velocity)
	GravityModifier : number?,          -- scales Workspace.Gravity (Physics.Gravity_Modifier)
	MaxDistance     : number,           -- total path length budget (Physics.Max_Distance)
	Penetration     : any,              -- Config.Penetration block
	Params          : RaycastParams,    -- mutated per surface — pass a fresh one
	BulletTemplate  : BasePart?,        -- cloned as the visible bullet; nil = default tracer part
	StopOnFirstHit  : boolean?,         -- rockets/grenades: never penetrate, stop at surface one
	-- Guided steering (Launcher Guided/Turn_Speed): every step the velocity
	-- turns toward GetAimPoint() at TurnSpeed radians/second.
	Steering        : {TurnSpeed: number, GetAimPoint: () -> Vector3}?,
	OnHit           : (hit: Penetration.PenetrationHit) -> (),
	OnEnd           : ((finalPosition: Vector3) -> ())?, -- after the bullet stops/expires
}

-- The default visible bullet when no template is configured — a small
-- neon streak oriented along its velocity.
local function _defaultBullet(): BasePart
	local part = Instance.new("Part")
	part.Size        = Vector3.new(0.08, 0.08, 0.6)
	part.Color        = Color3.fromRGB(255, 220, 130)
	part.Material      = Enum.Material.Neon
	part.Anchored       = true
	part.CanCollide      = false
	part.CanQuery         = false
	part.CanTouch          = false
	part.CastShadow         = false
	return part
end

--► Launches one simulated bullet. Returns immediately (the flight runs in
--  its own task); every resolved surface is handed to OnHit as a
--  PenetrationHit with the accumulated DamageMultiplier — identical shape
--  to Penetration.Cast results, so hit handling code is shared.
Module.Launch = function(cfg: LaunchConfig)
	local bullet = (cfg.BulletTemplate and cfg.BulletTemplate:Clone()) or _defaultBullet()
	bullet.CFrame = CFrame.lookAt(cfg.Origin, cfg.Origin + cfg.Direction)
	bullet.Parent = Workspace
	Debris:AddItem(bullet, Module.DefaultMaxLifetime + 1)

	task.spawn(function()
		local position = cfg.Origin
		local velocity = cfg.Direction * cfg.Speed
		local gravity  = Vector3.new(0, -Workspace.Gravity * (cfg.GravityModifier or 1), 0)
		local traveled = 0
		local lifetime = 0
		local multiplier = 1
		local surfaceIndex = 1
		local maxSurfaces = math.max(cfg.Penetration.Penetration_Count or 1, 1)
		local excluded = table.clone(cfg.Params.FilterDescendantsInstances)

		while traveled < cfg.MaxDistance and lifetime < Module.DefaultMaxLifetime do
			local dt = RunService.Heartbeat:Wait()
			lifetime += dt

			local step = velocity * dt
			cfg.Params.FilterDescendantsInstances = excluded
			local result = Workspace:Raycast(position, step, cfg.Params)

			if result then
				local hit: Penetration.PenetrationHit = {Result = result, DamageMultiplier = multiplier}
				local verdict = Penetration.ResolveSurface(result, velocity.Unit, cfg.Penetration, surfaceIndex, multiplier)
				hit.Ricocheted   = verdict.Action == "Ricochet" or nil
				hit.ExitPosition = verdict.ExitPosition
				hit.ExitNormal   = verdict.ExitNormal

				cfg.OnHit(hit)

				if cfg.StopOnFirstHit then
					position = result.Position
					break
				end

				surfaceIndex += 1
				if verdict.Action == "Stop" or surfaceIndex > maxSurfaces then
					break
				end

				traveled += (result.Position - position).Magnitude
				position  = verdict.NextOrigin
				multiplier = verdict.Multiplier
				-- Ricochet redirects the full remaining speed; penetration
				-- keeps flying straight (Direction is unchanged for "Through").
				velocity = verdict.Direction * velocity.Magnitude
				table.insert(excluded, result.Instance)
			else
				traveled += step.Magnitude
				position += step
				velocity += gravity * dt

				-- Guided flight: rotate the velocity toward the aim point,
				-- capped at TurnSpeed radians this frame — speed is preserved,
				-- only the heading turns, so guided rockets fly arcs.
				if cfg.Steering then
					local toAim = cfg.Steering.GetAimPoint() - position
					if toAim.Magnitude > 1e-3 then
						local currentDir = velocity.Unit
						local wantedDir  = toAim.Unit
						local maxTurn    = cfg.Steering.TurnSpeed * dt
						local angle      = math.acos(math.clamp(currentDir:Dot(wantedDir), -1, 1))
						if angle > 1e-4 then
							local alpha = math.min(maxTurn / angle, 1)
							local newDir = currentDir:Lerp(wantedDir, alpha)
							if newDir.Magnitude > 1e-4 then
								velocity = newDir.Unit * velocity.Magnitude
							end
						end
					end
				end
			end

			if bullet.Parent then
				bullet.CFrame = CFrame.lookAt(position, position + velocity)
			end
		end

		bullet:Destroy()
		if cfg.OnEnd then
			cfg.OnEnd(position)
		end
	end)
end

return Module
