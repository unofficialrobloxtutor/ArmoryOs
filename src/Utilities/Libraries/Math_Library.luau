--!nonstrict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Math_Library
--  ◄► Version:     2.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Utilities/Libraries math module for the Armory OS
--                  Advanced Weapon Framework. A human-readable, drop-in
--                  replacement for Lua's math library that makes
--                  arithmetic, algebra, trigonometry, and geometry read
--                  like intent — used across weapon/physics/UI systems
--                  wherever numeric computation is needed.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
setmetatable(Module, {__index = math})

--► Constants ◄--
Module.Pi      = math.pi
Module.Tau     = math.pi * 2       -- 1 full circle in radians
Module.Huge    = math.huge
Module.Euler   = math.exp(1)       -- e ≈ 2.718 (used in growth/decay)
Module.Phi     = (1 + math.sqrt(5)) / 2  -- golden ratio ≈ 1.618
Module.C       = 299792458         -- speed of light in m/s
Module.Epsilon = 1e-6              -- near-zero threshold for equality checks

--► Rounding & Constraints ◄--
Module.Floor   = math.floor        -- rounds down to nearest integer
Module.Ceil    = math.ceil         -- rounds up to nearest integer
Module.Abs     = math.abs          -- absolute value (removes negative sign)
Module.Clamp   = math.clamp        -- keeps a number between a min and max
Module.Sign    = math.sign         -- returns -1, 0, or 1

--► Trigonometry ◄--
Module.Sin     = math.sin
Module.Cos     = math.cos
Module.Tan     = math.tan
Module.Asin    = math.asin         -- inverse sine
Module.Acos    = math.acos         -- inverse cosine
Module.Atan    = math.atan         -- inverse tangent
Module.Atan2   = math.atan2        -- best for finding angles between two points

--► Powers & Roots ◄--
Module.Sqrt    = math.sqrt
Module.Exp     = math.exp          -- e^x
Module.Log     = math.log          -- natural logarithm
Module.Log10   = math.log10        -- base-10 logarithm

--► Conversion ◄--
Module.Rad     = math.rad          -- degrees → radians
Module.Deg     = math.deg          -- radians → degrees

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ROUNDING
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Rounds to the nearest whole number (or to N decimal places)
-- Round(3.14159, 2) → 3.14
Module.Round = function(x: number, places: number?): number
	local m = 10 ^ (places or 0)
	return math.floor(x * m + 0.5) / m
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ARITHMETIC
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Adds all provided numbers together
-- Makes intent explicit: Math.Add(health, regen, bonus)
Module.Add = function(...): number
	local count = select("#", ...)
	if count == 0 then return 0 end
	local result = (select(1, ...))
	for i = 2, count do
		result += (select(i, ...))
	end
	return result
end

--► Subtracts all subsequent numbers from the first
-- Math.Subtract(MaxRopeLength, 1) reads clearly at a glance
Module.Subtract = function(...): number
	local count = select("#", ...)
	if count == 0 then return 0 end
	local result = (select(1, ...))
	for i = 2, count do
		result -= (select(i, ...))
	end
	return result
end

--► Multiplies all provided numbers together
Module.Mult = function(...): number
	local count = select("#", ...)
	if count == 0 then return 0 end
	local result = (select(1, ...))
	for i = 2, count do
		result *= (select(i, ...))
	end
	return result
end

--► Divides the first number by each subsequent number
-- Errors loudly if any divisor is zero
Module.Divide = function(...): number
	local count = select("#", ...)
	if count == 0 then return 0 end
	local result = (select(1, ...))
	for i = 2, count do
		local divisor = (select(i, ...))
		if math.abs(divisor) < Module.Epsilon then
			error("Math_Library: Divide — division by zero at argument " .. i)
		end
		result /= divisor
	end
	return result
end

--► Returns the fraction of a over b (explicit ratio — reads better than a/b in context)
-- Math.Fraction(5, 9) in a temperature formula reads as "five ninths"
Module.Fraction = function(a: number, b: number): number
	if math.abs(b) < Module.Epsilon then
		error("Math_Library: Fraction — denominator cannot be zero")
	end
	return a / b
end

--► Returns the reciprocal of x (1/x)
Module.Reciprocal = function(x: number): number
	if math.abs(x) < Module.Epsilon then
		error("Math_Library: Reciprocal — cannot take reciprocal of zero")
	end
	return 1 / x
end

--► Returns x to a given power (default squares it)
Module.Pow = function(x: number, power: number?): number
	return x ^ (power or 2)
end

--► Returns the factorial of a non-negative integer
Module.Factorial = function(x: number): number
	if x < 0 then error("Math_Library: Factorial — x must be non-negative") end
	local c = 1
	for i = 1, x do c *= i end
	return c
end

--► Returns the remainder after dividing Value by Divisor
-- Also returns the quotient: quotient, remainder = Math.GetRemainder(17, 5)
Module.GetRemainder = function(value: number, divisor: number): (number, number)
	if math.abs(divisor) < Module.Epsilon then
		error("Math_Library: GetRemainder — divisor cannot be zero")
	end
	local quotient  = math.floor(value / divisor)
	local remainder = value - (quotient * divisor)
	return quotient, remainder
end

--► Returns x as a decimal percentage (75 → 0.75)
Module.Percent = function(x: number): number
	return x / 100
end

--► Returns the inverse of a percentage (75 → 0.25)
-- Useful for transparency: InversePercent(80) → 0.2 opacity remaining
Module.InversePercent = function(x: number): number
	return 1 - (x / 100)
end

--► Σ (Sigma): sums the results of a function over a range [start, goal]
-- Math.Sigma(1, 10, nil, function(i) return i * 2 end) → 110
Module.Sigma = function(start: number, goal: number, step: number?, callback: (i: number) -> number): number
	local result    = 0
	local increment = step or 1
	for i = start, goal, increment do
		result += callback(i)
	end
	return result
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ALGEBRA
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns y = mx + b (slope-intercept form)
Module.SlopeIntercept = function(m: number, x: number, b: number): number
	return m * x + b
end

--► Returns the slope between two points or two vectors
-- Accepts either 4 numbers (x1, y1, x2, y2) or 2 Vector2/Vector3 values
Module.Slope = function(...): number
	local args = {...}
	local n    = #args
	if n == 2 then
		local v1, v2 = args[1], args[2]
		if typeof(v1) == "Vector3" or typeof(v1) == "Vector2" then
			local diff = v2 - v1
			if math.abs(diff.X) < Module.Epsilon then
				error("Math_Library: Slope — vertical line has undefined slope")
			end
			return diff.Y / diff.X
		end
	elseif n == 4 then
		local x1, y1, x2, y2 = args[1], args[2], args[3], args[4]
		if math.abs(x2 - x1) < Module.Epsilon then
			error("Math_Library: Slope — vertical line has undefined slope")
		end
		return (y2 - y1) / (x2 - x1)
	end
	error("Math_Library: Slope — requires either 2 Vectors or 4 numbers")
end

--► Solves the quadratic formula for ax² + bx + c = 0
-- Returns two solutions, or errors if the discriminant is negative
Module.QuadFormula = function(a: number, b: number, c: number): (number, number)
	local discriminant = Module.Pow(b) - 4 * a * c
	if discriminant < 0 then
		error("Math_Library: QuadFormula — no real solution (discriminant is negative)")
	end
	local root  = Module.Sqrt(discriminant)
	local denom = 2 * a
	return (-b + root) / denom, (-b - root) / denom
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	TRIGONOMETRY
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns c² (the hypotenuse squared) given the two legs of a right triangle
Module.PythagoreanSq = function(a: number, b: number): number
	return a * a + b * b
end

--► Returns c (the hypotenuse) given the two legs of a right triangle
Module.Pythagorean = function(a: number, b: number): number
	return math.sqrt(a * a + b * b)
end

--► Solves for a missing leg given the hypotenuse and the other leg
-- SolveLeg(3, 5) → 4  (the missing side of a 3-4-5 triangle)
Module.SolveLeg = function(knownSide: number, hypotenuse: number): number
	if knownSide >= hypotenuse then
		error("Math_Library: SolveLeg — side cannot be greater than or equal to the hypotenuse")
	end
	return math.sqrt(hypotenuse ^ 2 - knownSide ^ 2)
end

--► Returns the 2D angle in radians from one Vector2 or Vector3 to another (XZ plane)
Module.AngleTo2D = function(from: Vector2 | Vector3, to: Vector2 | Vector3): number
	local diff = to - from
	return math.atan2(diff.Y, diff.X)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	GEOMETRY — 2D AREAS & PERIMETERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the area of a rectangle
Module.RectangleArea = function(width: number, height: number): number
	return width * height
end

--► Returns the area of a triangle given base and height
Module.TriangleArea = function(base: number, height: number): number
	return 0.5 * base * height
end

--► Returns the area of a circle given its radius
Module.CircleArea = function(radius: number): number
	return Module.Pi * radius ^ 2
end

--► Returns the circumference of a circle given its radius
Module.Circumference = function(radius: number): number
	return Module.Tau * radius
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	GEOMETRY — 3D SURFACE AREA & VOLUME
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the surface area of a box (cuboid)
Module.BoxSurfaceArea = function(width: number, height: number, depth: number): number
	return 2 * (width * height + height * depth + width * depth)
end

--► Returns the volume of a box (cuboid)
-- Renamed from CubeArea which was incorrect — this returns VOLUME not area
Module.BoxVolume = function(width: number, height: number, depth: number): number
	return width * height * depth
end

--► Returns the surface area of a sphere
Module.SphereSurfaceArea = function(radius: number): number
	return 4 * Module.Pi * radius ^ 2
end

--► Returns the volume of a sphere
Module.SphereVolume = function(radius: number): number
	return (4 / 3) * Module.Pi * radius ^ 3
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	INTERPOLATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Linearly interpolates between start and goal at alpha (0-1)
-- The backbone of smooth motion, animation, and transitions
Module.Lerp = function(start: number, goal: number, alpha: number): number
	return start + (goal - start) * alpha
end

--► Returns the inverse lerp — where does value sit between a and b as a 0-1 ratio?
-- RevLerp(0, 100, 25) → 0.25
Module.RevLerp = function(a: number, b: number, value: number): number
	if math.abs(b - a) < Module.Epsilon then
		error("Math_Library: RevLerp — a and b cannot be equal")
	end
	return (value - a) / (b - a)
end

--► Maps a value from one range to another (unclamped)
-- Map(0.5, 0, 1, 0, 100) → 50
Module.Map = function(value: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	if math.abs(inMax - inMin) < Module.Epsilon then
		error("Math_Library: Map — input range cannot be zero")
	end
	local t = (value - inMin) / (inMax - inMin)
	return outMin + (outMax - outMin) * t
end

--► Maps a value from one range to another and clamps the result to the output range
-- Safer than Map when the input might exceed its bounds
Module.Remap = function(value: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	if math.abs(inMax - inMin) < Module.Epsilon then
		error("Math_Library: Remap — input range cannot be zero")
	end
	local t = math.clamp((value - inMin) / (inMax - inMin), 0, 1)
	return outMin + (outMax - outMin) * t
end

--► Wraps a value so it always stays within [Min, Max)
-- Perfect for looping angles, repeating maps, or cyclic indices
Module.Wrap = function(value: number, min: number, max: number): number
	local range = max - min
	return ((value - min) % range + range) % range + min
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ENGINE UTILITIES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns half of any supported datatype
-- Supports: number, Vector2, Vector3, CFrame, UDim2, UDim, Color3,
--           BrickColor, ColorSequence, NumberRange, NumberSequence, Ray, Rect
Module.Half = function(x: any): any
	local t = typeof(x)

	if t == "number" or t:find("Vector") then
		return x * 0.5
	end

	if t == "CFrame" then
		return CFrame.identity:Lerp(x, 0.5)
	end

	if t == "UDim2" then
		return UDim2.new(x.X.Scale * 0.5, x.X.Offset * 0.5, x.Y.Scale * 0.5, x.Y.Offset * 0.5)
	end

	if t == "UDim" then
		return UDim.new(x.Scale * 0.5, x.Offset * 0.5)
	end

	if t == "Rect" then
		return Rect.new(x.Min * 0.5, x.Max * 0.5)
	end

	if t == "Color3" then
		return Color3.new(x.R * 0.5, x.G * 0.5, x.B * 0.5)
	end

	if t == "BrickColor" then
		return BrickColor.new(Module.Half(x.Color))
	end

	if t == "ColorSequence" then
		local keypoints = table.create(#x.Keypoints)
		for i, kp in ipairs(x.Keypoints) do
			keypoints[i] = ColorSequenceKeypoint.new(kp.Time, Color3.new(
				kp.Value.R * 0.5, kp.Value.G * 0.5, kp.Value.B * 0.5
				))
		end
		return ColorSequence.new(keypoints)
	end

	if t == "NumberRange" then
		return NumberRange.new(x.Min * 0.5, x.Max * 0.5)
	end

	if t == "NumberSequence" then
		local keypoints = {}
		for _, kp in ipairs(x.Keypoints) do
			table.insert(keypoints, NumberSequenceKeypoint.new(kp.Time, kp.Value * 0.5, kp.Envelope * 0.5))
		end
		return NumberSequence.new(keypoints)
	end

	if t == "Ray" then
		return Ray.new(x.Origin, x.Direction * 0.5)
	end

	error("Math_Library: Half — unsupported type '" .. t .. "'")
end

--► Returns the individual components of any supported datatype as multiple return values
-- GetComponents(Vector3.new(1,2,3)) → 1, 2, 3
Module.GetComponents = function(x: any): ...any
	local t = typeof(x)

	if t == "Vector3"          then return x.X, x.Y, x.Z end
	if t == "Vector2"          then return x.X, x.Y end
	if t == "Color3"           then return x.R, x.G, x.B end
	if t == "UDim2"            then return x.X.Scale, x.X.Offset, x.Y.Scale, x.Y.Offset end
	if t == "UDim"             then return x.Scale, x.Offset end
	if t == "CFrame"           then return x:GetComponents() end
	if t == "NumberRange"      then return x.Min, x.Max end
	if t == "Rect"             then return x.Min.X, x.Min.Y, x.Max.X, x.Max.Y end
	if t == "PhysicalProperties" then return x.Density, x.Friction, x.Elasticity end
	if t == "BrickColor"       then return x.Color.R, x.Color.G, x.Color.B end

	warn("Math_Library: GetComponents — unsupported type '" .. t .. "'")
	return x
end

--► Converts a world 2D distance between two Vector3 points projected onto a face plane
-- FaceNormalID determines which two axes are used for the 2D distance
Module.Calc2DMagnitude = function(faceNormalID: Enum.NormalId, start: Vector3, finish: Vector3): number
	if not faceNormalID then
		return (finish - start).Magnitude
	end

	local v1, v2
	if faceNormalID == Enum.NormalId.Front or faceNormalID == Enum.NormalId.Back then
		v1 = Vector2.new(start.X,  start.Y)
		v2 = Vector2.new(finish.X, finish.Y)
	elseif faceNormalID == Enum.NormalId.Right or faceNormalID == Enum.NormalId.Left then
		v1 = Vector2.new(start.Y,  start.Z)
		v2 = Vector2.new(finish.Y, finish.Z)
	elseif faceNormalID == Enum.NormalId.Top or faceNormalID == Enum.NormalId.Bottom then
		v1 = Vector2.new(start.X,  start.Z)
		v2 = Vector2.new(finish.X, finish.Z)
	else
		return 0
	end

	return (v2 - v1).Magnitude
end

--► Returns the distance between two points
-- Accepts either two Vectors or four numbers (x1, y1, x2, y2)
Module.Distance = function(...): number
	local a, b = ...
	if typeof(a) == typeof(b) and typeof(a):find("Vector") then
		return (b - a).Magnitude
	end
	local x1, y1, x2, y2 = ...
	return Module.Sqrt(Module.Pow(x2 - x1) + Module.Pow(y2 - y1))
end

--► Returns a normalized unit vector
Module.UnitVector = function(vector: Vector3): Vector3
	if vector.Magnitude < Module.Epsilon then
		error("Math_Library: UnitVector — cannot normalize a zero-length vector")
	end
	return vector / vector.Magnitude
end

--► Returns the delta (change) between an initial and final value
-- Delta(10, 15) → 5   (used in angle tracking, physics, etc.)
Module.Delta = function(initial: number, final: number): number
	return final - initial
end

--► Returns true if a value is close enough to zero to be treated as zero
-- Uses Module.Epsilon as the threshold
Module.IsNearlyZero = function(value: number): boolean
	return math.abs(value) < Module.Epsilon
end

--► Returns true if two numbers are approximately equal within an optional tolerance
Module.IsNearlyEqual = function(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) < (tolerance or Module.Epsilon)
end

--► Converts a 1D loop index into a 2D grid coordinate
-- ToGrid(5, 3) → x=1, y=1  (zero-based)
Module.ToGrid = function(index: number, columns: number): (number, number)
	local x = (index - 1) % columns
	local y = math.floor((index - 1) / columns)
	return x, y
end

--► Returns true if a Vector3 point is inside an axis-aligned bounding box
Module.InBounds = function(point: Vector3, min: Vector3, max: Vector3): boolean
	return  point.X >= min.X and point.X <= max.X and
		point.Y >= min.Y and point.Y <= max.Y and
		point.Z >= min.Z and point.Z <= max.Z
end

--► Returns a hex string for a numeric value (e.g. 255 → "0xFF")
Module.GetHexValue = function(value: number): string
	return string.format("0x%X", math.floor(math.abs(value)))
end

--► Returns a number from a hex string (e.g. "FF" → 255)
Module.GetNumberFromHexString = function(hex: string): number
	return tonumber(hex, 16) or 0
end

--► Abbreviates large numbers into readable shorthand
-- 1500 → "1.5K", 2000000 → "2M"
Module.AbbreviateNumber = function(n: number): string
	local suffixes = {"", "K", "M", "B", "T", "Qd", "Qn"}
	if n < 1000 then return tostring(n) end
	local exp    = math.floor(math.log10(n) / 3)
	local suffix = suffixes[exp + 1] or ("e+" .. exp)
	local short  = n / (10 ^ (exp * 3))
	return string.format("%.2f%s", short, suffix):gsub("%.?0+$", "")
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	STATISTICS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns the standard deviation of a dataset
Module.StandardDeviation = function(numbers: {number}): number
	if #numbers == 0 then error("Math_Library: StandardDeviation — dataset cannot be empty") end
	local sum   = 0
	local count = #numbers
	for _, v in ipairs(numbers) do sum += v end
	local mean  = sum / count
	sum         = 0
	for _, v in ipairs(numbers) do sum += (v - mean) ^ 2 end
	return math.sqrt(sum / count)
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	TEMPERATURE CONVERSION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Converts Fahrenheit to Celsius
Module.FahrenheitToCelsius = function(fahrenheit: number): number
	return Module.Fraction(5, 9) * (fahrenheit - 32)
end

--► Converts Celsius to Fahrenheit
Module.CelsiusToFahrenheit = function(celsius: number): number
	return Module.Fraction(9, 5) * celsius + 32
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	NUMBER THEORY
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a number is even
Module.IsEven = function(n: number): boolean
	return n % 2 == 0
end

--► Returns true if a number is odd
Module.IsOdd = function(n: number): boolean
	return n % 2 ~= 0
end

--► Returns true if a number is prime
Module.IsPrime = function(n: number): boolean
	if n <= 1 then return false end
	if n <= 3 then return true end
	if n % 2 == 0 or n % 3 == 0 then return false end
	local i = 5
	while i * i <= n do
		if n % i == 0 or n % (i + 2) == 0 then return false end
		i += 6
	end
	return true
end

--► Generates all prime numbers up to a limit using the Sieve of Eratosthenes
Module.GeneratePrimes = function(limit: number): {number}
	local isPrime = table.create(limit, true)
	isPrime[1]    = false
	for p = 2, math.sqrt(limit) do
		if isPrime[p] then
			for i = p * p, limit, p do
				isPrime[i] = false
			end
		end
	end
	local primes = {}
	for p = 2, limit do
		if isPrime[p] then table.insert(primes, p) end
	end
	return primes
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CURVES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a point on a quadratic Bezier curve at t (0-1)
-- p0: start, p1: control point (the pull), p2: end
-- Note: For full curve and spline support see Curve_Library
Module.Bezier = function(t: number, p0: Vector3, p1: Vector3, p2: Vector3): Vector3
	local l1 = p0:Lerp(p1, t)
	local l2 = p1:Lerp(p2, t)
	return l1:Lerp(l2, t)
end

--► A simple PID controller
-- Returns a function(dt, setpoint, processVariable) → output
--
-- Usage:
--   local pid = Math.CreatePID(1, 0.1, 0.05)
--   RunService.Heartbeat:Connect(function(dt)
--       local output = pid(dt, targetAngle, currentAngle)
--   end)
Module.CreatePID = function(kp: number, ki: number, kd: number): (number, number, number) -> number
	local state = {kp = kp, ki = ki, kd = kd, lastError = 0, integral = 0}
	return function(dt: number, setpoint: number, pv: number): number
		local err        = setpoint - pv
		state.integral  += err * dt
		local derivative = (err - state.lastError) / dt
		state.lastError  = err
		return (err * state.kp) + (state.integral * state.ki) + (derivative * state.kd)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	PHYSICS HELPERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns a displacement Vector3 at speed of light along a unit direction
-- Used for relativistic position calculations
-- Mu(time, 1, 0, 0) → position along the X axis after `time` seconds at c
Module.Mu = function(time: number, x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z).Unit * Module.C * time
end

--► Returns an interval gap value for UI grid coordinates that won't exceed bounds
Module.IntervalGap = function(index: number, range: number): number
	return math.clamp(1 - (index - 1) * range, 0, 1)
end

return Module :: typeof(math) & typeof(Module)