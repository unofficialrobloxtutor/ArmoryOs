--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Gore_Library
--  ◄► Version:     1.0
--  ◄► Date:        12/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable module for gore/impact feedback —
--                  blood decals, particles, dismemberment thresholds,
--                  ragdoll forces, wounds, pools, corpse cleanup, and
--                  gore-setting scaling. Companion to Damage_Library.
--                  Pure math/logic only — no Instance creation, so it
--                  drops into client or server code equally.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
--► Tables       ◄--
local Module = {}
--► Variables    ◄--

--► Constants ◄--
Module.Epsilon           = 1e-6
Module.DefaultBloodColor = Color3.fromRGB(138, 7, 7)
Module.GoreLevels        = {None = 0, Low = 0.35, High = 1}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	BLOOD DECALS & SPLATTER
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a randomized blood color by nudging a base color within a variance range
-- RandomBloodColor(Module.DefaultBloodColor, 0.1) → slightly darker/lighter red each call
Module.RandomBloodColor = function(baseColor: Color3, variance: number?): Color3
	local v = variance or 0.08
	local function jitter(c: number): number
		return math.clamp(c + (math.random() * 2 - 1) * v, 0, 1)
	end
	return Color3.new(jitter(baseColor.R), jitter(baseColor.G), jitter(baseColor.B))
end

--► Returns a splatter direction vector by reflecting hit velocity off the surface normal
-- with an added random spread cone, in degrees
Module.BloodSplatterDirection = function(hitNormal: Vector3, incomingVelocity: Vector3, spreadDegrees: number?): Vector3
	local reflected = incomingVelocity - 2 * incomingVelocity:Dot(hitNormal) * hitNormal
	local spread = math.rad(spreadDegrees or 15)
	local jitterX = (math.random() * 2 - 1) * spread
	local jitterY = (math.random() * 2 - 1) * spread
	local cf = CFrame.lookAt(Vector3.zero, reflected.Unit) * CFrame.Angles(jitterX, jitterY, 0)
	return cf.LookVector
end

--► Scales a decal/splatter's size based on how much damage was dealt
-- ScaleSplatterByDamage(80, 100) → 0.5, 2.5  → interpolated between min/max size
Module.ScaleSplatterByDamage = function(damage: number, minSize: number, maxSize: number, referenceDamage: number?): number
	local ref = referenceDamage or 100
	local t = math.clamp(damage / ref, 0, 1)
	return minSize + (maxSize - minSize) * t
end

--► Returns a 0-1 opacity for a full-screen blood overlay based on damage taken
-- Clamped so it never fully blacks/reds out the screen
Module.ScreenBloodOpacity = function(damage: number, maxDamage: number, maxOpacity: number?): number
	local cap = maxOpacity or 0.6
	return math.clamp(damage / maxDamage, 0, 1) * cap
end

--► Returns how long (seconds) a splatter decal should persist before fading, scaled by its size
Module.SplatterDecalLifetime = function(size: number, baseLifetime: number?): number
	return (baseLifetime or 8) * math.clamp(size, 0.5, 3)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PARTICLES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns how many blood particles to emit for a given damage amount
-- BloodParticleCount(50, 5) → 25  (5 base particles per 10 damage, roughly)
Module.BloodParticleCount = function(damage: number, baseCount: number?): number
	return math.floor((baseCount or 5) * math.clamp(damage / 10, 0.5, 8))
end

--► Returns a velocity vector for a single blood particle, scattered within a spread cone
Module.BloodParticleVelocity = function(direction: Vector3, force: number, spreadDegrees: number?): Vector3
	local spread = math.rad(spreadDegrees or 25)
	local jitterX = (math.random() * 2 - 1) * spread
	local jitterY = (math.random() * 2 - 1) * spread
	local cf = CFrame.lookAt(Vector3.zero, direction.Unit) * CFrame.Angles(jitterX, jitterY, 0)
	return cf.LookVector * force
end

--► Returns true if a hit should produce a fine blood mist (typically on high-damage/crit hits)
Module.BloodMistChance = function(damage: number, threshold: number): boolean
	if damage < threshold then
		return false
	end
	local chance = math.clamp((damage - threshold) / threshold, 0, 1)
	return math.random() <= chance
end

--► Returns a particle emitter's Rate property scaled by damage
Module.ParticleEmitRate = function(damage: number, baseRate: number?): number
	return (baseRate or 20) * math.clamp(damage / 25, 0.25, 4)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	DISMEMBERMENT
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a single hit's damage is enough to sever a limb outright
Module.ShouldDismember = function(damage: number, threshold: number): boolean
	return damage >= threshold
end

--► Returns an impulse force for the severed limb, scaled by the damage that severed it
Module.SeverForce = function(damage: number, scale: number?): number
	return damage * (scale or 8)
end

--► Returns the damage threshold at which a kill should gib (fully destroy) the ragdoll,
-- expressed as a percentage of max health overshot
-- GibThreshold(100, 0.5) → 50  (50 excess damage beyond lethal triggers a gib)
Module.GibThreshold = function(maxHealth: number, gibPercent: number?): number
	return maxHealth * (gibPercent or 0.5)
end

--► Returns true if a killing blow overshoots current health by enough to gib
-- ShouldGib(150, 20, 50) → true  (150 damage on 20 hp, gib threshold 50 excess)
Module.ShouldGib = function(damage: number, currentHealth: number, gibThreshold: number): boolean
	return (damage - currentHealth) >= gibThreshold
end

--► Rolls whether a lethal, high-damage hit dismembers the limb it struck
-- Chance scales with how far damage exceeds the threshold
Module.DismemberChance = function(damage: number, threshold: number, randomFactor: number?): boolean
	if damage < threshold then
		return false
	end
	local overshoot = math.clamp((damage - threshold) / threshold, 0, 1)
	return math.random() <= overshoot * (randomFactor or 1)
end

--► Weighted-random pick of which limb gets severed, given a {limbName = weight} table
Module.LimbSeverProbability = function(weightTable: {[string]: number}): string?
	local total = 0
	for _, w in pairs(weightTable) do
		total += w
	end
	if total <= Module.Epsilon then
		return nil
	end
	local roll = math.random() * total
	local cumulative = 0
	for limb, w in pairs(weightTable) do
		cumulative += w
		if roll <= cumulative then
			return limb
		end
	end
	return nil
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	RAGDOLL
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns an impulse vector to apply to a ragdolled root part on death
Module.RagdollImpulse = function(damage: number, direction: Vector3, scale: number?): Vector3
	return direction.Unit * damage * (scale or 3)
end

--► Returns how long (seconds) a ragdoll should stay physics-active before freezing/cleanup
Module.RagdollDuration = function(damage: number, baseDuration: number?, maxDuration: number?): number
	local dur = (baseDuration or 4) + (damage / 50)
	return math.min(dur, maxDuration or 15)
end

--► Returns a torque vector to add spin to a ragdoll on a heavy hit
Module.RagdollSpinTorque = function(damage: number, scale: number?): Vector3
	local magnitude = damage * (scale or 1.5)
	return Vector3.new(
		(math.random() * 2 - 1) * magnitude,
		(math.random() * 2 - 1) * magnitude,
		(math.random() * 2 - 1) * magnitude
	)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	WOUNDS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a wound decal's size interpolated between a min/max based on damage
Module.WoundSizeFromDamage = function(damage: number, minSize: number, maxSize: number, referenceDamage: number?): number
	local ref = referenceDamage or 100
	local t = math.clamp(damage / ref, 0, 1)
	return minSize + (maxSize - minSize) * t
end

--► Looks up a wound decal ID for a given damage type, falling back to a "Default" entry
Module.WoundDecalID = function(damageType: string, decalTable: {[string]: string}): string?
	return decalTable[damageType] or decalTable.Default
end

--► Adds a new wound to an existing count, capped at a maximum visible wound count
Module.WoundStacking = function(existingWounds: number, maxWounds: number): number
	return math.min(existingWounds + 1, maxWounds)
end

--► Rolls whether a hit leaves a scorch/burn mark instead of a standard wound, by damage type
Module.BurnMarkChance = function(damageType: string, chanceTable: {[string]: number}): boolean
	local chance = chanceTable[damageType] or 0
	return math.random() <= chance
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	BLOOD POOLS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns how fast a blood pool decal should grow (studs/second) based on damage
Module.BloodPoolGrowthRate = function(damage: number, baseRate: number?): number
	return (baseRate or 0.15) * math.clamp(damage / 50, 0.5, 3)
end

--► Returns the maximum size a blood pool can reach, capped for performance
Module.BloodPoolMaxSize = function(damage: number, cap: number?): number
	return math.min(damage * 0.05, cap or 6)
end

--► Returns how long a blood pool should exist before fading, scaled by its final size
Module.BloodPoolLifetime = function(size: number, baseLifetime: number?): number
	return (baseLifetime or 20) * math.clamp(size, 1, 4)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CORPSE & CLEANUP
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a corpse despawn time, shortened under heavy server load to save perf
-- serverLoad expected as a 0-1 ratio (e.g. CurrentPlayers / MaxCorpses)
Module.CorpseDespawnTime = function(baseTime: number, serverLoad: number): number
	local reduction = math.clamp(serverLoad, 0, 1) * 0.6
	return baseTime * (1 - reduction)
end

--► Returns a 0-1 alpha for fading a corpse out over its lifetime
Module.CorpseFadeAlpha = function(elapsed: number, duration: number): number
	if duration <= Module.Epsilon then
		return 1
	end
	return math.clamp(elapsed / duration, 0, 1)
end

--► Returns true if a corpse has exceeded its lifetime and should be cleaned up
Module.ShouldCleanupCorpse = function(elapsed: number, maxLifetime: number): boolean
	return elapsed >= maxLifetime
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	AUDIO
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Looks up an appropriate gore sound ID for a damage type, falling back to "Default"
Module.SelectGoreSound = function(damageType: string, soundTable: {[string]: string}): string?
	return soundTable[damageType] or soundTable.Default
end

--► Returns an impact sound's volume scaled by damage dealt
Module.ImpactSoundVolume = function(damage: number, maxDamage: number, maxVolume: number?): number
	return math.clamp(damage / maxDamage, 0, 1) * (maxVolume or 1)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CAMERA & FEEDBACK
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a 0-1 intensity for a hitmarker/UI flash based on damage relative to max
Module.HitmarkerIntensity = function(damage: number, maxDamage: number): number
	return math.clamp(damage / maxDamage, 0.1, 1)
end

--► Returns a camera shake magnitude for a gory kill, scaled by damage
Module.CameraShakeFromGore = function(damage: number, scale: number?): number
	return math.clamp(damage * (scale or 0.02), 0, 1)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SETTINGS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a hit counts as "critical gore" (headshot or dismemberment) for
-- systems that want to trigger extra feedback (slow-mo, sound stingers, etc.)
Module.IsCriticalGore = function(isHeadshot: boolean, isDismember: boolean): boolean
	return isHeadshot or isDismember
end

--► Scales any gore-related value (particle count, decal size, opacity, etc.) by a
-- player's gore setting. Pass "None" to zero it out entirely for content preferences.
-- ApplyGoreSetting(20, "Low") → 7  (20 * 0.35)
Module.ApplyGoreSetting = function(value: number, goreLevel: string): number
	local scale = Module.GoreLevels[goreLevel]
	if scale == nil then
		error("Gore_Library: ApplyGoreSetting — unknown gore level '" .. tostring(goreLevel) .. "'")
	end
	return value * scale
end

return Module