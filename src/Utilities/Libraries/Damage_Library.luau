--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Damage_Library
--  ◄► Version:     1.0
--  ◄► Date:        12/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable damage module covering mitigation,
--                  criticals, falloff, hit zones, armor, DOTs, elemental
--                  matchups, knockback, healing, and scaling — reads like
--                  intent. Companion to Math_Library.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
--► Tables       ◄--
local Module = {}
--► Variables    ◄--

--► Constants ◄--
Module.Epsilon           = 1e-6   -- near-zero threshold for equality/divide checks
Module.DefaultCritMult   = 2      -- default critical hit multiplier
Module.DefaultArmorConst = 100    -- default K constant for armor reduction curve

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CORE CALCULATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Multiplies a base damage value by a single multiplier
-- ApplyMultiplier(50, 1.5) → 75
Module.ApplyMultiplier = function(damage: number, multiplier: number): number
	return damage * multiplier
end

--► Chains multiple multipliers together against a base damage value
-- ApplyModifiers(50, 1.5, 1.2) → 90  (multiplicative stacking)
Module.ApplyModifiers = function(damage: number, ...: number): number
	local result = damage
	for i = 1, select("#", ...) do
		result *= (select(i, ...))
	end
	return result
end

--► Sums percentage modifiers (as decimals) and applies them additively
-- ApplyAdditiveModifiers(50, 0.10, 0.05) → 57.5  (50 * (1 + 0.10 + 0.05))
Module.ApplyAdditiveModifiers = function(damage: number, ...: number): number
	local sum = 0
	for i = 1, select("#", ...) do
		sum += (select(i, ...))
	end
	return damage * (1 + sum)
end

--► Subtracts a flat amount of damage, never going below zero
Module.Mitigate = function(damage: number, flatReduction: number): number
	return math.max(damage - flatReduction, 0)
end

--► Reduces damage by a percentage (0-100)
-- MitigatePercent(100, 25) → 75
Module.MitigatePercent = function(damage: number, percent: number): number
	return damage * (1 - math.clamp(percent, 0, 100) / 100)
end

--► Clamps a damage value between a minimum and maximum
Module.ClampDamage = function(damage: number, min: number, max: number): number
	return math.clamp(damage, min, max)
end

--► Rounds damage to the nearest whole number
-- Useful for UI display or systems that only accept integer health values
Module.RoundDamage = function(damage: number): number
	return math.floor(damage + 0.5)
end

--► Splits a damage value evenly across a number of parts
-- SplitDamage(100, 3) → 33.33...  (per target)
Module.SplitDamage = function(damage: number, parts: number): number
	if parts <= 0 then
		error("Damage_Library: SplitDamage — parts must be greater than zero")
	end
	return damage / parts
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CRITICAL HITS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Rolls whether a hit is a critical, given a chance from 0-1
Module.RollCritical = function(chance: number): boolean
	return math.random() <= math.clamp(chance, 0, 1)
end

--► Applies a critical multiplier to a damage value
Module.ApplyCritical = function(damage: number, critMultiplier: number?): number
	return damage * (critMultiplier or Module.DefaultCritMult)
end

--► Rolls for a critical hit and returns the resulting damage alongside whether it crit
-- CriticalOrNormal(50, 0.2, 2) → 100, true  (on a successful roll)
Module.CriticalOrNormal = function(damage: number, chance: number, critMultiplier: number?): (number, boolean)
	local isCrit = Module.RollCritical(chance)
	if isCrit then
		return Module.ApplyCritical(damage, critMultiplier), true
	end
	return damage, false
end

--► Applies a multiplier only if the hit landed on a weakpoint
Module.WeakpointMultiplier = function(damage: number, isWeakpoint: boolean, multiplier: number): number
	if isWeakpoint then
		return damage * multiplier
	end
	return damage
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	FALLOFF & DISTANCE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Linearly falls off damage from full damage at minRange to minDamage at maxRange
-- Distances beyond maxRange are clamped to minDamage
Module.LinearFalloff = function(damage: number, distance: number, minRange: number, maxRange: number, minDamage: number): number
	if distance <= minRange then
		return damage
	end
	if distance >= maxRange then
		return minDamage
	end
	local t = (distance - minRange) / (maxRange - minRange)
	return damage + (minDamage - damage) * t
end

--► Falls off explosion damage linearly to zero at the edge of the blast radius
Module.ExplosionFalloff = function(damage: number, distance: number, radius: number): number
	if radius <= Module.Epsilon then
		error("Damage_Library: ExplosionFalloff — radius must be greater than zero")
	end
	local t = math.clamp(1 - (distance / radius), 0, 1)
	return damage * t
end

--► Reduces damage per successive penetration (e.g. bullets passing through targets)
-- PenetrationFalloff(100, 2, 0.25) → 56.25  (100 * 0.75^2)
Module.PenetrationFalloff = function(damage: number, penetrationCount: number, falloffPerHit: number): number
	local retained = (1 - math.clamp(falloffPerHit, 0, 1)) ^ penetrationCount
	return math.max(damage * retained, 0)
end

--► Returns a damage multiplier that falls off quadratically with distance
-- Distances at or under referenceDistance return a multiplier of 1
Module.DistanceMultiplier = function(distance: number, referenceDistance: number): number
	if distance <= referenceDistance then
		return 1
	end
	return 1 / (1 + ((distance - referenceDistance) / referenceDistance) ^ 2)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	HIT ZONES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Looks up a hit zone's multiplier from a table, defaulting to 1 if not found
-- GetHitZoneMultiplier("Head", {Head = 2, Torso = 1, Limb = 0.75}) → 2
Module.GetHitZoneMultiplier = function(zoneName: string, multiplierTable: {[string]: number}): number
	return multiplierTable[zoneName] or 1
end

--► Applies a headshot multiplier if the hit landed on the head
Module.HeadshotDamage = function(damage: number, isHeadshot: boolean, multiplier: number?): number
	if isHeadshot then
		return damage * (multiplier or 2)
	end
	return damage
end

--► Applies a reduced multiplier if the hit landed on a limb
Module.LimbDamage = function(damage: number, isLimb: boolean, multiplier: number?): number
	if isLimb then
		return damage * (multiplier or 0.75)
	end
	return damage
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ARMOR & RESISTANCE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Reduces damage using a diminishing-returns armor curve: K / (K + Armor)
-- Higher armor asymptotically approaches full mitigation without ever hitting it
Module.ArmorReduction = function(damage: number, armor: number, armorConstant: number?): number
	local k = armorConstant or Module.DefaultArmorConst
	return damage * (k / (k + math.max(armor, 0)))
end

--► Reduces damage by a flat resistance percentage (0-100)
Module.PercentResist = function(damage: number, resistPercent: number): number
	return damage * (1 - math.clamp(resistPercent, 0, 100) / 100)
end

--► Applies ArmorReduction after subtracting armor penetration from the target's armor
-- PierceArmor(100, 50, 20) → ArmorReduction(100, 30)
Module.PierceArmor = function(damage: number, armor: number, penetration: number, armorConstant: number?): number
	local effectiveArmor = math.max(armor - penetration, 0)
	return Module.ArmorReduction(damage, effectiveArmor, armorConstant)
end

--► Absorbs damage into a shield pool first, returning the leftover damage and remaining shield
-- ShieldAbsorb(80, 50) → 30, 0   (shield breaks, 30 damage carries through)
Module.ShieldAbsorb = function(damage: number, shieldHealth: number): (number, number)
	if shieldHealth >= damage then
		return 0, shieldHealth - damage
	end
	return damage - shieldHealth, 0
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	DAMAGE OVER TIME
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Breaks a total DOT amount into per-tick damage and a tick count
-- CreateDOT(100, 5, 1) → 20, 5   (20 damage per second for 5 seconds)
Module.CreateDOT = function(totalDamage: number, duration: number, tickRate: number): (number, number)
	if tickRate <= Module.Epsilon then
		error("Damage_Library: CreateDOT — tickRate must be greater than zero")
	end
	local ticks = math.max(math.floor(duration / tickRate), 1)
	return totalDamage / ticks, ticks
end

--► Accumulates elapsed time and returns whether a tick fired this frame, plus leftover time
-- TickDamage(0.9, 0.2, 1) → false, 1.1   (not yet time to tick)
Module.TickDamage = function(elapsed: number, dt: number, tickInterval: number): (boolean, number)
	local newElapsed = elapsed + dt
	if newElapsed >= tickInterval then
		return true, newElapsed - tickInterval
	end
	return false, newElapsed
end

--► Adds incoming DOT stacks to existing stacks, capped at a maximum
Module.StackDOT = function(currentStacks: number, incomingStacks: number, maxStacks: number): number
	return math.min(currentStacks + incomingStacks, maxStacks)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ELEMENTAL & COMBO
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Looks up an elemental matchup multiplier from a nested chart table
-- chart[attackElement][defenseElement], defaulting to 1 if no matchup is defined
-- ElementalMultiplier(50, "Fire", "Ice", {Fire = {Ice = 2}}) → 100
Module.ElementalMultiplier = function(damage: number, attackElement: string, defenseElement: string, chart: {[string]: {[string]: number}}): number
	local row = chart[attackElement]
	local multiplier = (row and row[defenseElement]) or 1
	return damage * multiplier
end

--► Scales damage up with combo count, capped at a maximum multiplier
-- ComboMultiplier(20, 5, 10, 2.5) → damage, multiplier at 5 hits with +10%/hit, capped at 2.5x
Module.ComboMultiplier = function(damage: number, comboCount: number, incrementPercent: number, maxMultiplier: number): (number, number)
	local multiplier = math.min(1 + (comboCount * incrementPercent / 100), maxMultiplier)
	return damage * multiplier, multiplier
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	KNOCKBACK & IMPULSE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a knockback force scaled by how much damage was dealt
Module.CalculateKnockback = function(damage: number, baseForce: number, scale: number): number
	return baseForce + (damage * scale)
end

--► Converts damage into a physical impulse magnitude given a target's mass
Module.ImpulseFromDamage = function(damage: number, mass: number, scale: number): number
	if mass <= Module.Epsilon then
		error("Damage_Library: ImpulseFromDamage — mass must be greater than zero")
	end
	return (damage * scale) / mass
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	TEAM & SOURCE CHECKS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if the attacker is allowed to damage the target
-- Blocks damage between matching teams unless friendly fire is enabled
Module.CanDamage = function(attackerTeam: string, targetTeam: string, friendlyFireEnabled: boolean?): boolean
	if attackerTeam == targetTeam then
		return friendlyFireEnabled == true
	end
	return true
end

--► Applies a multiplier when damage is self-inflicted (e.g. rocket jumping, explosive splash)
Module.SelfDamageMultiplier = function(damage: number, isSelfInflicted: boolean, multiplier: number?): number
	if isSelfInflicted then
		return damage * (multiplier or 0.5)
	end
	return damage
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	HEALING & OVERKILL
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Heals a target, clamping to max health and returning any overheal that spilled over
-- Heal(90, 100, 20) → 100, 10
Module.Heal = function(currentHealth: number, maxHealth: number, healAmount: number): (number, number)
	local newHealth = math.min(currentHealth + healAmount, maxHealth)
	local overheal   = math.max((currentHealth + healAmount) - maxHealth, 0)
	return newHealth, overheal
end

--► Returns how much damage exceeded the target's remaining health
-- Overkill(30, 50) → 20
Module.Overkill = function(currentHealth: number, damage: number): number
	return math.max(damage - currentHealth, 0)
end

--► Returns true if the incoming damage would kill the target
Module.IsLethal = function(currentHealth: number, damage: number): boolean
	return damage >= currentHealth
end

--► Clamps a health value between zero and its maximum
Module.ClampHealth = function(health: number, maxHealth: number): number
	return math.clamp(health, 0, maxHealth)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	VARIANCE
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Applies random variance to a damage value within +/- a percentage
-- RandomVariance(100, 10) → somewhere between 90 and 110
Module.RandomVariance = function(damage: number, variancePercent: number): number
	local v = math.clamp(variancePercent, 0, 100) / 100
	local low, high = damage * (1 - v), damage * (1 + v)
	return low + math.random() * (high - low)
end

--► Rolls a random float damage value between a min and max (inclusive)
Module.RollDamageRange = function(min: number, max: number): number
	if min > max then
		error("Damage_Library: RollDamageRange — min cannot be greater than max")
	end
	return min + math.random() * (max - min)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	LEVEL SCALING
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Scales base damage up linearly per level above 1
-- ScaleByLevel(10, 5, 0.1) → 14  (10 * (1 + 4 * 0.1))
Module.ScaleByLevel = function(baseDamage: number, level: number, scalePerLevel: number): number
	return baseDamage * (1 + (math.max(level, 1) - 1) * scalePerLevel)
end

--► Applies diminishing returns to a value past a soft cap
-- Useful for stat scaling like crit chance, resistance, or lifesteal
Module.DiminishingReturns = function(value: number, softCap: number, scale: number): number
	if value <= softCap then
		return value
	end
	return softCap + (value - softCap) * scale
end

return Module
