--!native
--!optimize 2
--!strict

--[=[
    @class Spring
    A physics-based 3D spring simulation closure based module using numerical integration.
    Useful for smooth object physics and camera movement.
]=]

-- Constants
local DEFAULT_MASS = 5
local DEFAULT_FORCE = 50
local DEFAULT_DAMPING = 4
local DEFAULT_SPEED = 4
local DEFAULT_ITERATIONS = 8

--[=[
    Represents the current physical state and properties of the spring.
    @interface State
    @within Spring
    @field Position Vector3 -- The current position of the spring.
    @field Target Vector3 -- The target position the spring is moving towards.
    @field Velocity Vector3 -- The current velocity of the spring.
    @field Mass number -- The mass of the spring.
    @field Force number -- The force applied to the spring.
    @field Damping number -- The damping factor (friction) of the spring.
    @field Speed number -- The simulation speed multiplier.
    @field Iterations number -- The number of calculation iterations per update for stability.
]=]
export type State = {
	Position: Vector3,
	Target: Vector3,
	Velocity: Vector3,
	Mass: number,
	Force: number,
	Damping: number,
	Speed: number,
	Iterations: number,
}

--[=[
    A partial state object used for updating specific spring properties.
    @interface PartialState
    @within Spring
    @field Position Vector3? -- Optional position override.
    @field Target Vector3? -- Optional target override.
    @field Velocity Vector3? -- Optional velocity override.
    @field Mass number? -- Optional mass override.
    @field Force number? -- Optional force override.
    @field Damping number? -- Optional damping override.
    @field Speed number? -- Optional speed multiplier override.
    @field Iterations number? -- Optional iterations override.
]=]
export type PartialState = {
	Position: Vector3?,
	Target: Vector3?,
	Velocity: Vector3?,
	Mass: number?,
	Force: number?,
	Damping: number?,
	Speed: number?,
	Iterations: number?,
}

--[=[
    The Spring object instance containing the methods to simulate and interact with the spring.
    @interface SpringObject
    @within Spring
    @field Update (deltaTime: number) -> Vector3 -- Steps the simulation forward and returns the new position.
    @field ApplyImpulse (force: Vector3) -> () -- Applies an instantaneous force to the spring's velocity.
    @field SetState (state: PartialState) -> () -- Updates specific properties of the spring's state.
    @field GetState () -> State -- Returns a read-only copy of the current state.
]=]
export type SpringObject = {
	Update: (deltaTime: number) -> Vector3,
	ApplyImpulse: (force: Vector3) -> (),
	SetState: (state: PartialState) -> (),
	GetState: () -> State,
}

-- Cached
local math_min = math.min
local vector3_zero = Vector3.zero

--[=[
    Creates a new Spring instance.
    @within Spring
    @param mass number? -- The mass of the spring (Default: 5)
    @param force number? -- The force/stiffness of the spring (Default: 50)
    @param damping number? -- The damping/friction (Default: 4)
    @param speed number? -- The speed multiplier (Default: 4)
    @param iteration number? -- The number of iterations per update (Default: 8)
    @return SpringObject
]=]
local function __call(mass: number?, force: number?, damping: number?, speed: number?, iteration: number?): SpringObject
	local self_mass = mass or DEFAULT_MASS
	local self_force = force or DEFAULT_FORCE
	local self_damping = damping or DEFAULT_DAMPING
	local self_speed = speed or DEFAULT_SPEED
	local self_iterations = iteration or DEFAULT_ITERATIONS

	local self_position = vector3_zero
	local self_target = vector3_zero
	local self_velocity = vector3_zero

	local function update(deltaTime: number): Vector3
		local scaledDeltaTime = (math_min(deltaTime, 1) * self_speed) / self_iterations
		for _ = 1, self_iterations do
			local iterationForce = self_target - self_position
			local acceleration = (iterationForce * self_force) / self_mass

			acceleration -= self_velocity * self_damping

			self_velocity += acceleration * scaledDeltaTime
			self_position += self_velocity * scaledDeltaTime
		end

		return self_position
	end

	local function applyImpulse(impulse: Vector3)
		self_velocity += impulse
	end

	local function setState(state: PartialState)
		self_position = state.Position or self_position
		self_target = state.Target or self_target
		self_velocity = state.Velocity or self_velocity

		self_mass = state.Mass or self_mass
		self_force = state.Force or self_force
		self_damping = state.Damping or self_damping
		self_speed = state.Speed or self_speed
		self_iterations = state.Iterations or self_iterations
	end

	local function getState(): State
		local state: State = {
			Position = self_position,
			Target = self_target,
			Velocity = self_velocity,

			Mass = self_mass,
			Force = self_force,
			Damping = self_damping,
			Speed = self_speed,
			Iterations = self_iterations,
		}

		return table.freeze(state) :: State
	end

	local spring: SpringObject = {
		Update = update,
		ApplyImpulse = applyImpulse,

		SetState = setState,
		GetState = getState,
	}

	return table.freeze(spring) :: SpringObject
end

return __call