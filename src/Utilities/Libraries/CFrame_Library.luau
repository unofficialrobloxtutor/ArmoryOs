--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       CFrame_Library
--  ◄► Description: General-purpose CFrame utilities: composition,
--                  arithmetic (via a wrapper type since CFrame is a
--                  Roblox userdata and can't carry custom metamethods
--                  directly), decomposition, interpolation, spatial
--                  queries, weapon/viewmodel helpers, flying mechanics,
--                  and safety validation.
--
--  ◄► Arithmetic note: Wrap() splits a CFrame into Position (Vector3)
--                  and Euler (Vector3, radians) and does component-wise
--                  math on both — the same additive-offset pattern
--                  already used for Bob+Breath position and Sway+Recoil
--                  rotation in HandleRender. This is NOT raw 4x4 matrix
--                  arithmetic; it's the practical operation you actually
--                  want for blending pose offsets. Lua's grammar already
--                  gives correct precedence/parens once __add/__sub/
--                  __mul/__div exist — no extra work needed for that.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

local Module = {}

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 1: COMPOSITION & ARITHMETIC (BODMAS-safe wrapper)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

export type Wrapped = typeof(setmetatable({} :: {
	Position: Vector3,
	Euler: Vector3, -- radians, XYZ order
}, {} :: any))

local WrapMeta = {}
WrapMeta.__index = WrapMeta

local function _NewWrapped(Position: Vector3, Euler: Vector3): Wrapped
	return setmetatable({ Position = Position, Euler = Euler }, WrapMeta) :: any
end

function WrapMeta.__add(A: Wrapped, B: Wrapped): Wrapped
	return _NewWrapped(A.Position + B.Position, A.Euler + B.Euler)
end

function WrapMeta.__sub(A: Wrapped, B: Wrapped): Wrapped
	return _NewWrapped(A.Position - B.Position, A.Euler - B.Euler)
end

function WrapMeta.__mul(A: Wrapped, B: number): Wrapped
	assert(typeof(B) == "number", "CFrame_Library: Wrapped * only supports a scalar right-hand side")
	return _NewWrapped(A.Position * B, A.Euler * B)
end

function WrapMeta.__div(A: Wrapped, B: number): Wrapped
	assert(typeof(B) == "number", "CFrame_Library: Wrapped / only supports a scalar right-hand side")
	return _NewWrapped(A.Position / B, A.Euler / B)
end

function WrapMeta.__unm(A: Wrapped): Wrapped
	return _NewWrapped(-A.Position, -A.Euler)
end

function WrapMeta.__tostring(A: Wrapped): string
	return `WrappedCFrame(Position={A.Position}, Euler={A.Euler})`
end

-- 1. Splits a CFrame into an arithmetic-friendly wrapper: cf1 + cf2, cf1 - cf2,
--    cf1 * 0.5, cf1 / 2, -cf1 all work once wrapped. Order of ops (BODMAS) is
--    just standard Lua precedence — (A + B) * 0.5 works with no extra code.
function Module.Wrap(CFrame_: CFrame): Wrapped
	local Position = CFrame_.Position
	local rX, rY, rZ = CFrame_:ToEulerAnglesXYZ()
	return _NewWrapped(Position, Vector3.new(rX, rY, rZ))
end

-- 2. Reconstructs a real CFrame from a Wrapped value. Call this once, at the
--    end of your arithmetic chain, before handing the result to PivotTo/etc.
function Module.Unwrap(W: Wrapped): CFrame
	return CFrame.new(W.Position) * CFrame.fromEulerAnglesXYZ(W.Euler.X, W.Euler.Y, W.Euler.Z)
end

-- 3. Ordered multiplicative fold — the "stack these transforms" operation,
--    distinct from Wrap's additive blending. Order matters: never iterate a
--    dictionary into this, only an array with a defined order.
function Module.Compose(CFrames: {CFrame}): CFrame
	local Result = CFrame.new()
	for _, Value in CFrames do
		Result *= Value
	end
	return Result
end

-- 4. Thin, readable wrapper around CFrame:Lerp — exists so call sites read
--    "Blend(Hip, Aim, 0.6)" instead of a bare method call buried in a chain.
function Module.Blend(A: CFrame, B: CFrame, Alpha: number): CFrame
	return A:Lerp(B, Alpha)
end

-- 5. Weighted composite of several CFrames against a base — for combining
--    more than two contributions with different influence, e.g. three
--    overlapping camera-shake sources at different intensities.
function Module.WeightedSum(Entries: {{CFrame: CFrame, Weight: number}}): CFrame
	local Result = Module.Wrap(CFrame.new())
	for _, Entry in Entries do
		Result += Module.Wrap(Entry.CFrame) * Entry.Weight
	end
	return Module.Unwrap(Result)
end

-- 6. Explicit function form of __add, for call sites that prefer not to Wrap.
function Module.Add(A: CFrame, B: CFrame): CFrame
	return Module.Unwrap(Module.Wrap(A) + Module.Wrap(B))
end

-- 7. Explicit function form of __sub.
function Module.Subtract(A: CFrame, B: CFrame): CFrame
	return Module.Unwrap(Module.Wrap(A) - Module.Wrap(B))
end

-- 8. Explicit function form of __mul(scalar).
function Module.Scale(A: CFrame, Scalar: number): CFrame
	return Module.Unwrap(Module.Wrap(A) * Scalar)
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 2: DECOMPOSITION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- 9. Returns XYZ Euler angles in radians as a Vector3 (thin wrapper).
function Module.GetEulerAngles(CFrame_: CFrame): Vector3
	local rX, rY, rZ = CFrame_:ToEulerAnglesXYZ()
	return Vector3.new(rX, rY, rZ)
end

-- 10. Splits into (Position, EulerAngles) in one call.
function Module.GetPositionAndRotation(CFrame_: CFrame): (Vector3, Vector3)
	return CFrame_.Position, Module.GetEulerAngles(CFrame_)
end

-- 11. Inverse of #10 — rebuild a CFrame from separate position + Euler parts.
function Module.FromPositionAndEuler(Position: Vector3, Euler: Vector3): CFrame
	return CFrame.new(Position) * CFrame.fromEulerAnglesXYZ(Euler.X, Euler.Y, Euler.Z)
end

-- 12. Drops rotation, keeps only position.
function Module.StripRotation(CFrame_: CFrame): CFrame
	return CFrame.new(CFrame_.Position)
end

-- 13. Drops position, keeps only rotation (rotation "about the origin").
function Module.StripPosition(CFrame_: CFrame): CFrame
	return CFrame_ - CFrame_.Position
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 3: INTERPOLATION / EASING
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- 14. Lerp with Alpha clamped to [0,1] — guards against a spring or
--     hand-rolled timer producing an out-of-range Alpha, which CFrame:Lerp
--     will happily extrapolate past instead of erroring.
function Module.SafeLerp(A: CFrame, B: CFrame, Alpha: number): CFrame
	return A:Lerp(B, math.clamp(Alpha, 0, 1))
end

-- 15. Framerate-independent exponential decay toward Target — a lighter
--     alternative to a full Spring instance for one-off smoothing where you
--     don't need overshoot/velocity, just "catch up toward the target."
function Module.DampTo(Current: CFrame, Target: CFrame, dt: number, Speed: number): CFrame
	local Alpha = 1 - math.exp(-Speed * dt)
	return Current:Lerp(Target, Alpha)
end

-- 16. Lerp with a smoothstep easing curve applied to Alpha first, for a
--     gentler ease-in/ease-out feel than linear Lerp.
function Module.EaseInOut(A: CFrame, B: CFrame, Alpha: number): CFrame
	local Clamped = math.clamp(Alpha, 0, 1)
	local Eased = Clamped * Clamped * (3 - 2 * Clamped)
	return A:Lerp(B, Eased)
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 4: COMPARISON / MEASUREMENT
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- 17. Straight-line distance between two CFrames' positions.
function Module.Distance(A: CFrame, B: CFrame): number
	return (A.Position - B.Position).Magnitude
end

-- 18. Angle in radians between two CFrames' LookVectors.
function Module.AngleBetween(A: CFrame, B: CFrame): number
	local Dot = math.clamp(A.LookVector:Dot(B.LookVector), -1, 1)
	return math.acos(Dot)
end

-- 19. True if two CFrames are within Epsilon on both position and rotation
--     (rotation compared via LookVector dot product, not raw matrix diff).
function Module.IsApproximatelyEqual(A: CFrame, B: CFrame, Epsilon: number?): boolean
	local Eps = Epsilon or 1e-3
	local PositionClose = (A.Position - B.Position).Magnitude <= Eps
	local RotationClose = A.LookVector:Dot(B.LookVector) >= (1 - Eps)
	return PositionClose and RotationClose
end

-- 20. True if Origin is facing Target within ToleranceDegrees.
function Module.IsFacing(Origin: CFrame, Target: Vector3, ToleranceDegrees: number): boolean
	local ToTarget = (Target - Origin.Position)
	if ToTarget.Magnitude < 1e-4 then
		return true
	end
	local Angle = math.acos(math.clamp(Origin.LookVector:Dot(ToTarget.Unit), -1, 1))
	return Angle <= math.rad(ToleranceDegrees)
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 5: PROJECTION / SPATIAL
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- 21. World point → CFrame's local space (named wrapper around PointToObjectSpace).
function Module.Project(CFrame_: CFrame, WorldPoint: Vector3): Vector3
	return CFrame_:PointToObjectSpace(WorldPoint)
end

-- 22. Local point → world space (named wrapper around PointToWorldSpace).
function Module.Unproject(CFrame_: CFrame, LocalPoint: Vector3): Vector3
	return CFrame_:PointToWorldSpace(LocalPoint)
end

-- 23. Keeps yaw only — strips pitch/roll, useful for character-facing or
--     aligning a flat marker to a tilted surface's forward direction.
function Module.FlattenY(CFrame_: CFrame): CFrame
	local Look = CFrame_.LookVector
	local FlatLook = Vector3.new(Look.X, 0, Look.Z)
	if FlatLook.Magnitude < 1e-4 then
		FlatLook = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(CFrame_.Position, CFrame_.Position + FlatLook.Unit)
end

-- 24. Mirrors position and rotation across a world axis through the origin.
--     Verify sign conventions against your specific use (e.g. left/right
--     hand IK, symmetric weapon mounts) before relying on this — mirroring
--     inverts handedness, and "correct" depends on what you're mirroring for.
function Module.MirrorAcrossAxis(CFrame_: CFrame, Axis: "X" | "Y" | "Z"): CFrame
	local function Flip(V: Vector3): Vector3
		if Axis == "X" then
			return Vector3.new(-V.X, V.Y, V.Z)
		elseif Axis == "Y" then
			return Vector3.new(V.X, -V.Y, V.Z)
		else
			return Vector3.new(V.X, V.Y, -V.Z)
		end
	end

	local Position = Flip(CFrame_.Position)
	local Look = Flip(CFrame_.LookVector)
	local Up = Flip(CFrame_.UpVector)

	return CFrame.fromMatrix(Position, Up:Cross(-Look), Up, -Look)
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 6: RANDOMIZATION / JITTER
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- 25. Small random CFrame — good for a one-shot procedural recoil kick or
--     impact shake. MaxPosition in studs, MaxRotationDegrees in degrees.
function Module.RandomOffset(MaxPosition: number, MaxRotationDegrees: number): CFrame
	local Position = Vector3.new(
		(math.random() * 2 - 1) * MaxPosition,
		(math.random() * 2 - 1) * MaxPosition,
		(math.random() * 2 - 1) * MaxPosition
	)
	local MaxRad = math.rad(MaxRotationDegrees)
	return CFrame.new(Position) * CFrame.fromEulerAnglesXYZ(
		(math.random() * 2 - 1) * MaxRad,
		(math.random() * 2 - 1) * MaxRad,
		(math.random() * 2 - 1) * MaxRad
	)
end

-- 26. Deterministic sine-based shake driven by a time value rather than
--     math.random — use this over RandomOffset when you want a smooth,
--     continuous shake (e.g. sustained camera shake) instead of a single jolt.
function Module.Shake(Intensity: number, Time: number): CFrame
	local Position = Vector3.new(
		math.sin(Time * 13.7) * Intensity,
		math.sin(Time * 17.3 + 1.1) * Intensity,
		math.sin(Time * 11.1 + 2.7) * Intensity
	)
	return CFrame.new(Position)
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 7: WEAPON / VIEWMODEL SPECIFIC
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- 27. Safely fetches a muzzle attachment's world CFrame, defaulting to
--     "Muzzle" — centralizes the null-check instead of repeating
--     FindFirstChild + nil-guard at every bullet-origin call site.
function Module.MuzzleWorldCFrame(ViewModel: Model, MuzzleName: string?): CFrame?
	local Muzzle = ViewModel:FindFirstChild(MuzzleName or "Muzzle", true)
	if not Muzzle or not Muzzle:IsA("BasePart") and not Muzzle:IsA("Attachment") then
		return nil
	end
	return Muzzle.WorldCFrame
end

-- 28. Builds a randomized recoil-kick CFrame from a config table, so
--     WeaponConfig values drive recoil feel directly instead of every
--     weapon's Shoot() hand-rolling its own math.random calls.
function Module.RecoilImpulse(Config: { Vertical: number, Horizontal: number, Kick: number }): CFrame
	local VerticalKick = math.rad(Config.Vertical) * (0.8 + math.random() * 0.4)
	local HorizontalKick = math.rad(Config.Horizontal) * ((math.random() * 2 - 1))
	return CFrame.new(0, 0, Config.Kick) * CFrame.fromEulerAnglesXYZ(-VerticalKick, HorizontalKick, 0)
end

-- 29. Domain-specific name for Blend, for the exact hip-to-ADS use case —
--     reads clearer at the FireArm call site than a generic Blend call.
function Module.AimBlendOffset(HipOffset: CFrame, AimOffset: CFrame, Alpha: number): CFrame
	return Module.Blend(HipOffset, AimOffset, Alpha)
end

-- 30. Mutator convenience — applies DampTo directly to a BasePart each frame,
--     for cases simpler than a full viewmodel render pipeline (e.g. a
--     dropped weapon settling into a resting pose).
function Module.HandleAlignment(Part: BasePart, Target: CFrame, dt: number, Speed: number)
	Part.CFrame = Module.DampTo(Part.CFrame, Target, dt, Speed)
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 8: FLYING MECHANICS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- 31. Builds a CFrame whose LookVector matches Velocity's direction — the
--     base building block for "face the direction you're moving."
function Module.AlignToVelocity(Position: Vector3, Velocity: Vector3, UpVector: Vector3?): CFrame
	if Velocity.Magnitude < 1e-4 then
		return CFrame.new(Position)
	end
	return CFrame.lookAt(Position, Position + Velocity.Unit, UpVector or Vector3.new(0, 1, 0))
end

-- 32. Rolls a craft into a turn proportional to its yaw angular velocity —
--     classic flight-sim "bank into the turn" feel. AngularVelocityY in
--     rad/s (positive = turning right), MaxBankDegrees caps the roll.
function Module.BankFromTurn(CurrentCFrame: CFrame, AngularVelocityY: number, MaxBankDegrees: number): CFrame
	local BankAmount = math.clamp(-AngularVelocityY, -math.rad(MaxBankDegrees), math.rad(MaxBankDegrees))
	return CurrentCFrame * CFrame.fromEulerAnglesXYZ(0, 0, BankAmount)
end

-- 33. Tilts the nose up/down based on climb/descent rate — VerticalSpeed in
--     studs/s (positive = climbing), MaxPitchDegrees caps the tilt.
function Module.PitchFromVerticalSpeed(CurrentCFrame: CFrame, VerticalSpeed: number, MaxPitchDegrees: number): CFrame
	local PitchAmount = math.clamp(VerticalSpeed * 0.02, -math.rad(MaxPitchDegrees), math.rad(MaxPitchDegrees))
	return CurrentCFrame * CFrame.fromEulerAnglesXYZ(PitchAmount, 0, 0)
end

-- 34. Combines AlignToVelocity + DampTo into one call — smoothly turns to
--     face the current velocity direction instead of snapping, which
--     matters at low speed where velocity direction can jitter frame to
--     frame (e.g. hovering, or fighting against gravity/drag).
function Module.SmoothFlightOrientation(Current: CFrame, Velocity: Vector3, dt: number, TurnSpeed: number): CFrame
	local Target = Module.AlignToVelocity(Current.Position, Velocity)
	return Module.DampTo(Current, Target, dt, TurnSpeed)
end

-- 35. Applies a full roll animation driven by Progress in [0,1] — for a
--     scripted flying trick/ability rather than continuous flight control.
function Module.BarrelRoll(CFrame_: CFrame, Progress: number): CFrame
	return CFrame_ * CFrame.fromEulerAnglesXYZ(0, 0, Progress * math.rad(360))
end

-- 36. Prevents pitch from exceeding MaxPitchDegrees either direction — stops
--     a flying camera/craft from over-rotating into a disorienting flip.
function Module.ClampPitch(CFrame_: CFrame, MaxPitchDegrees: number): CFrame
	local rX, rY, rZ = CFrame_:ToEulerAnglesXYZ()
	local Clamped = math.clamp(rX, -math.rad(MaxPitchDegrees), math.rad(MaxPitchDegrees))
	return CFrame.new(CFrame_.Position) * CFrame.fromEulerAnglesXYZ(Clamped, rY, rZ)
end

-- 37. Smoothly zeroes out roll and pitch while preserving yaw and position —
--     an "auto-level / stabilize" assist for flying mechanics.
function Module.LevelOut(CFrame_: CFrame, dt: number, Speed: number): CFrame
	local Target = Module.FlattenY(CFrame_)
	return Module.DampTo(CFrame_, Target, dt, Speed)
end

-- 38. Small positional lean opposite a thrust vector — purely visual
--     feedback for acceleration (e.g. a flying craft or viewmodel leaning
--     back under boost), not a physics force.
function Module.ThrustOffset(CFrame_: CFrame, ThrustVector: Vector3, Amount: number): CFrame
	if ThrustVector.Magnitude < 1e-4 then
		return CFrame_
	end
	local Local = CFrame_:VectorToObjectSpace(ThrustVector.Unit)
	return CFrame_ * CFrame.new(-Local * Amount)
end


--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
-- SECTION 9: SAFETY / VALIDATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

-- 39. Re-orthogonalizes a rotation matrix via Gram-Schmidt — corrects
--     floating-point drift that accumulates from repeated CFrame
--     multiplication over many frames (a long-running viewmodel pivot
--     chain is exactly the kind of thing this can happen to). Verify this
--     produces the handedness/sign convention you expect before relying
--     on it — matrix reconstruction is easy to get subtly backwards.
function Module.Orthonormalize(CFrame_: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = CFrame_:GetComponents()

	local Right = Vector3.new(r00, r10, r20).Unit
	local Up = Vector3.new(r01, r11, r21)
	Up = (Up - Right * Right:Dot(Up)).Unit
	local Look = Right:Cross(Up)

	return CFrame.fromMatrix(Vector3.new(x, y, z), Right, Up, -Look)
end

-- 40. Guards against NaN/Inf components — a bad Spring value or a divide
--     that slipped through can otherwise silently produce a CFrame that
--     breaks PivotTo (or worse, renders as a huge silent teleport). Check
--     this before applying anything computed through several Spring/Wrap
--     operations in a row.
function Module.Validate(CFrame_: CFrame): boolean
	local Components = { CFrame_:GetComponents() }
	for _, N in Components do
		if N ~= N or N == math.huge or N == -math.huge then
			return false
		end
	end
	return true
end


return Module
