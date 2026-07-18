--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Physics_Library
--  ◄► Version:     1.0
--  ◄► Date:        28/05/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable physics & kinematics module
--                  for use in Roblox game development.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
--► Constants    ◄--
Module.Gravity        = -196.2        -- Roblox gravity in studs/s² (default workspace gravity)
Module.RealGravity    = -9.80665      -- Real-world gravity in m/s²
Module.AirDensity     = 1.225         -- kg/m³ at sea level
Module.Epsilon        = 1e-6          -- Near-zero threshold

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	MASS & INERTIA
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the total mass of all BaseParts inside a model
Module.GetModelMass = function(model: Model): number
	local total = 0
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			total += part:GetMass()
		end
	end
	return total
end

--► Returns the total mass of a list of parts
Module.GetPartsMass = function(parts: {BasePart}): number
	local total = 0
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			total += part:GetMass()
		end
	end
	return total
end

--► Returns the center of mass of a model as a Vector3
Module.GetCenterOfMass = function(model: Model): Vector3
	local totalMass      = 0
	local weightedSum    = Vector3.zero

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local mass    = part:GetMass()
			totalMass    += mass
			weightedSum  += part.Position * mass
		end
	end

	if totalMass < Module.Epsilon then return Vector3.zero end
	return weightedSum / totalMass
end

--► Returns the moment of inertia of a uniform box (kg·m²)
-- Axis: "X", "Y", or "Z"
Module.MomentOfInertiaBox = function(mass: number, size: Vector3, axis: string): number
	if axis == "X" then
		return (1/12) * mass * (size.Y^2 + size.Z^2)
	elseif axis == "Y" then
		return (1/12) * mass * (size.X^2 + size.Z^2)
	elseif axis == "Z" then
		return (1/12) * mass * (size.X^2 + size.Y^2)
	end
	error("Physics_Library: MomentOfInertiaBox axis must be 'X', 'Y', or 'Z'")
end

--► Returns the moment of inertia of a solid sphere (kg·m²)
Module.MomentOfInertiaSphere = function(mass: number, radius: number): number
	return (2/5) * mass * radius^2
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	KINEMATICS (Linear Motion)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the final velocity given initial velocity, acceleration, and time
-- v = u + at
Module.FinalVelocity = function(initialVelocity: number, acceleration: number, time: number): number
	return initialVelocity + acceleration * time
end

--► Returns the displacement given initial velocity, time, and acceleration
-- s = ut + ½at²
Module.Displacement = function(initialVelocity: number, time: number, acceleration: number): number
	return initialVelocity * time + 0.5 * acceleration * time^2
end

--► Returns the final velocity squared (useful when time is unknown)
-- v² = u² + 2as
Module.FinalVelocitySq = function(initialVelocity: number, acceleration: number, displacement: number): number
	return initialVelocity^2 + 2 * acceleration * displacement
end

--► Returns the time it takes to travel a displacement with given velocity and acceleration
-- Solves: s = ut + ½at² for t using the quadratic formula
Module.TimeToDisplacement = function(initialVelocity: number, acceleration: number, displacement: number): (number?, number?)
	-- At² + Bt + C = 0
	local a = 0.5 * acceleration
	local b = initialVelocity
	local c = -displacement

	if math.abs(a) < Module.Epsilon then
		-- Linear: t = s / u
		if math.abs(b) < Module.Epsilon then return nil, nil end
		return -c / b, nil
	end

	local discriminant = b^2 - 4 * a * c
	if discriminant < 0 then return nil, nil end

	local root = math.sqrt(discriminant)
	return (-b + root) / (2 * a), (-b - root) / (2 * a)
end

--► Returns the average velocity between two velocities
Module.AverageVelocity = function(v1: number, v2: number): number
	return (v1 + v2) / 2
end

--► Returns the accumulated/combined velocity of a list of Vector3 velocities
Module.AccumulativeVelocity = function(velocities: {Vector3}): Vector3
	local sum = Vector3.zero
	for _, v in ipairs(velocities) do
		sum += v
	end
	return sum
end

--► Returns the net speed (magnitude) of a Vector3 velocity
Module.Speed = function(velocity: Vector3): number
	return velocity.Magnitude
end

--► Returns the time to reach peak height from an initial upward velocity
-- t = v / g  (where g is positive gravity magnitude)
Module.TimeToPeak = function(initialVerticalVelocity: number, gravity: number?): number
	local g = math.abs(gravity or Module.Gravity)
	if g < Module.Epsilon then error("Physics_Library: TimeToPeak gravity cannot be zero") end
	return math.abs(initialVerticalVelocity) / g
end

--► Returns the maximum height reached from an initial upward velocity
-- h = v² / 2g
Module.PeakHeight = function(initialVerticalVelocity: number, gravity: number?): number
	local g = math.abs(gravity or Module.Gravity)
	return (initialVerticalVelocity^2) / (2 * g)
end

--► Returns the time a projectile takes to hit the ground from a given height
-- Solves: h = ½gt²
Module.FallTime = function(height: number, gravity: number?): number
	local g = math.abs(gravity or Module.Gravity)
	if height < 0 then error("Physics_Library: FallTime height must be positive") end
	return math.sqrt((2 * height) / g)
end

--► Returns the launch velocity needed to reach a target Vector3 from an origin Vector3
-- Returns the velocity as a Vector3, or nil if unreachable
Module.LaunchVelocity = function(origin: Vector3, target: Vector3, speed: number, gravity: number?): Vector3?
	local g   = math.abs(gravity or Module.Gravity)
	local diff = target - origin
	local flat = Vector3.new(diff.X, 0, diff.Z)
	local R    = flat.Magnitude
	local Y    = diff.Y

	local v2   = speed^2
	local disc = v2^2 - g * (g * R^2 + 2 * Y * v2)
	if disc < 0 then return nil end -- Target unreachable at this speed

	local angle = math.atan((v2 - math.sqrt(disc)) / (g * R))
	local cos   = math.cos(angle)
	local sin   = math.sin(angle)

	local dir   = flat.Unit
	return Vector3.new(dir.X * speed * cos, speed * sin, dir.Z * speed * cos)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	FORCES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the force required to accelerate a mass (F = ma)
Module.Force = function(mass: number, acceleration: number): number
	return mass * acceleration
end

--► Returns the acceleration produced by a force on a mass (a = F/m)
Module.Acceleration = function(force: number, mass: number): number
	if mass < Module.Epsilon then error("Physics_Library: Acceleration mass cannot be zero") end
	return force / mass
end

--► Returns the weight of a mass under gravity (W = mg)
Module.Weight = function(mass: number, gravity: number?): number
	return mass * math.abs(gravity or Module.Gravity)
end

--► Returns the normal force on a flat surface (equal and opposite to weight)
Module.NormalForce = function(mass: number, gravity: number?): number
	return Module.Weight(mass, gravity)
end

--► Returns the friction force given a normal force and friction coefficient
Module.Friction = function(normalForce: number, coefficient: number): number
	return normalForce * coefficient
end

--► Returns the net force from a list of scalar forces
Module.NetForce = function(forces: {number}): number
	local net = 0
	for _, f in ipairs(forces) do
		net += f
	end
	return net
end

--► Returns the net force vector from a list of Vector3 forces
Module.NetForceVector = function(forces: {Vector3}): Vector3
	local net = Vector3.zero
	for _, f in ipairs(forces) do
		net += f
	end
	return net
end

--► Returns the drag force on an object moving through a fluid
-- F = ½ρCdAv²
Module.DragForce = function(velocity: number, dragCoefficient: number, crossSectionArea: number, fluidDensity: number?): number
	local rho = fluidDensity or Module.AirDensity
	return 0.5 * rho * dragCoefficient * crossSectionArea * velocity^2
end

--► Returns the terminal velocity of a falling object
-- v = sqrt(2mg / ρCdA)
Module.TerminalVelocity = function(mass: number, dragCoefficient: number, crossSectionArea: number, gravity: number?, fluidDensity: number?): number
	local g   = math.abs(gravity or Module.Gravity)
	local rho = fluidDensity or Module.AirDensity
	local denom = rho * dragCoefficient * crossSectionArea
	if denom < Module.Epsilon then error("Physics_Library: TerminalVelocity denominator is zero") end
	return math.sqrt((2 * mass * g) / denom)
end

--► Returns the gravitational force between two masses
-- F = G * m1 * m2 / r²
Module.GravitationalForce = function(mass1: number, mass2: number, distance: number): number
	local G = 6.674e-11
	if distance < Module.Epsilon then error("Physics_Library: GravitationalForce distance cannot be zero") end
	return G * mass1 * mass2 / distance^2
end

--► Returns the spring force given stiffness and displacement (Hooke's Law)
-- F = -kx
Module.SpringForce = function(stiffness: number, displacement: number): number
	return -stiffness * displacement
end

--► Returns the buoyancy force on a submerged object
-- F = ρVg
Module.Buoyancy = function(fluidDensity: number, volume: number, gravity: number?): number
	local g = math.abs(gravity or Module.Gravity)
	return fluidDensity * volume * g
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ENERGY & WORK
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the kinetic energy of a moving object (KE = ½mv²)
Module.KineticEnergy = function(mass: number, velocity: number): number
	return 0.5 * mass * velocity^2
end

--► Returns the potential energy of an object at a height (PE = mgh)
Module.PotentialEnergy = function(mass: number, height: number, gravity: number?): number
	local g = math.abs(gravity or Module.Gravity)
	return mass * g * height
end

--► Returns the total mechanical energy (KE + PE)
Module.MechanicalEnergy = function(mass: number, velocity: number, height: number, gravity: number?): number
	return Module.KineticEnergy(mass, velocity) + Module.PotentialEnergy(mass, height, gravity)
end

--► Returns the work done by a force over a displacement (W = Fd·cos θ)
Module.Work = function(force: number, displacement: number, angleRad: number?): number
	return force * displacement * math.cos(angleRad or 0)
end

--► Returns the power output given work done over time (P = W/t)
Module.Power = function(work: number, time: number): number
	if time < Module.Epsilon then error("Physics_Library: Power time cannot be zero") end
	return work / time
end

--► Returns the impulse applied to an object (J = Ft)
Module.Impulse = function(force: number, time: number): number
	return force * time
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	MOMENTUM & COLLISIONS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the momentum of an object (p = mv)
Module.Momentum = function(mass: number, velocity: number): number
	return mass * velocity
end

--► Returns the momentum vector of an object
Module.MomentumVector = function(mass: number, velocity: Vector3): Vector3
	return velocity * mass
end

--► Returns the velocity after a perfectly elastic 1D collision
-- Returns: v1_after, v2_after
Module.ElasticCollision = function(m1: number, v1: number, m2: number, v2: number): (number, number)
	local totalMass = m1 + m2
	local v1_after  = ((m1 - m2) * v1 + 2 * m2 * v2) / totalMass
	local v2_after  = ((m2 - m1) * v2 + 2 * m1 * v1) / totalMass
	return v1_after, v2_after
end

--► Returns the shared velocity after a perfectly inelastic collision
-- Both objects stick together: v = (m1v1 + m2v2) / (m1 + m2)
Module.InelasticCollision = function(m1: number, v1: number, m2: number, v2: number): number
	return (m1 * v1 + m2 * v2) / (m1 + m2)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ROTATIONAL MOTION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the torque applied given a force and lever arm length (τ = rF·sin θ)
Module.Torque = function(force: number, leverArm: number, angleRad: number?): number
	return force * leverArm * math.sin(angleRad or math.pi / 2)
end

--► Returns the angular velocity given linear velocity and radius (ω = v/r)
Module.AngularVelocity = function(linearVelocity: number, radius: number): number
	if radius < Module.Epsilon then error("Physics_Library: AngularVelocity radius cannot be zero") end
	return linearVelocity / radius
end

--► Returns the linear velocity from angular velocity and radius (v = ωr)
Module.LinearVelocityFromAngular = function(angularVelocity: number, radius: number): number
	return angularVelocity * radius
end

--► Returns the centripetal acceleration (a = v²/r)
Module.CentripetalAcceleration = function(velocity: number, radius: number): number
	if radius < Module.Epsilon then error("Physics_Library: CentripetalAcceleration radius cannot be zero") end
	return velocity^2 / radius
end

--► Returns the centripetal force needed to keep a mass in circular motion (F = mv²/r)
Module.CentripetalForce = function(mass: number, velocity: number, radius: number): number
	return mass * Module.CentripetalAcceleration(velocity, radius)
end

--► Returns the angular momentum of a rotating object (L = Iω)
Module.AngularMomentum = function(momentOfInertia: number, angularVelocity: number): number
	return momentOfInertia * angularVelocity
end

--► Returns the rotational kinetic energy (KE = ½Iω²)
Module.RotationalKineticEnergy = function(momentOfInertia: number, angularVelocity: number): number
	return 0.5 * momentOfInertia * angularVelocity^2
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	UTILITIES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a part is moving (velocity magnitude above epsilon)
Module.IsMoving = function(part: BasePart): boolean
	return part.AssemblyLinearVelocity.Magnitude > Module.Epsilon
end

--► Returns the relative velocity between two parts
Module.RelativeVelocity = function(part1: BasePart, part2: BasePart): Vector3
	return part1.AssemblyLinearVelocity - part2.AssemblyLinearVelocity
end

--► Returns the velocity a part needs to reach a target position in a given time
Module.VelocityToReach = function(current: Vector3, target: Vector3, time: number): Vector3
	if time < Module.Epsilon then error("Physics_Library: VelocityToReach time cannot be zero") end
	return (target - current) / time
end

--► Returns whether a part will overshoot a target this frame given velocity and dt
Module.WillOvershoot = function(current: Vector3, target: Vector3, velocity: Vector3, dt: number): boolean
	local toTarget  = (target - current).Magnitude
	local stepDist  = velocity.Magnitude * dt
	return stepDist >= toTarget
end

--► Returns the stopping distance given speed and deceleration (d = v²/2a)
Module.StoppingDistance = function(speed: number, deceleration: number): number
	if deceleration < Module.Epsilon then error("Physics_Library: StoppingDistance deceleration cannot be zero") end
	return speed^2 / (2 * deceleration)
end

--► Returns the time to stop given speed and deceleration
Module.StoppingTime = function(speed: number, deceleration: number): number
	if deceleration < Module.Epsilon then error("Physics_Library: StoppingTime deceleration cannot be zero") end
	return speed / deceleration
end

--► Returns the coefficient of restitution between two colliding objects
-- e = relative speed after / relative speed before
Module.CoefficientOfRestitution = function(relSpeedBefore: number, relSpeedAfter: number): number
	if math.abs(relSpeedBefore) < Module.Epsilon then error("Physics_Library: CoefficientOfRestitution speed before cannot be zero") end
	return math.abs(relSpeedAfter / relSpeedBefore)
end

--► Returns a reflected velocity vector off a surface normal
Module.ReflectVelocity = function(velocity: Vector3, normal: Vector3, restitution: number?): Vector3
	local e = restitution or 1
	return velocity - (1 + e) * velocity:Dot(normal) * normal
end

--► Returns the pressure exerted by a force on an area (P = F/A)
Module.Pressure = function(force: number, area: number): number
	if area < Module.Epsilon then error("Physics_Library: Pressure area cannot be zero") end
	return force / area
end

return Module