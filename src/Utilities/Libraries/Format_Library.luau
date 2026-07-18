--!strict
--[[
	Format_Library
	==================================================================
	A general-purpose formatting/stringification utility library
	covering the most commonly used Roblox datatypes and Instance
	classes: numbers, strings, Vector2/Vector3, CFrame, Color3,
	UDim/UDim2, BrickColor, Enum, Instance, Ray, Region3,
	NumberRange/NumberSequence/ColorSequence, Rect, TweenInfo,
	tables, and time/date values.

	~200 functions, grouped into sections below. Every function is
	pure (no side effects, no mutation of inputs) unless noted.

	Author:   [Your Name / @tostadium]
	Module:   Format_Library
	Version:  1.0.0
	License:  MIT
==================================================================
]]

local Format = {}

------------------------------------------------------------------
-- SECTION 1: NUMBER
------------------------------------------------------------------

-- Rounds `n` to `decimals` places (default 0).
function Format.Number_Round(n: number, decimals: number?): number
	local mult = 10 ^ (decimals or 0)
	return math.floor(n * mult + 0.5) / mult
end

-- Clamps `n` between `min` and `max`.
function Format.Number_Clamp(n: number, min: number, max: number): number
	return math.clamp(n, min, max)
end

-- Linearly interpolates between `a` and `b` by `t`.
function Format.Number_Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Inverse lerp: returns t such that Lerp(a,b,t) == value.
function Format.Number_InverseLerp(a: number, b: number, value: number): number
	if a == b then return 0 end
	return (value - a) / (b - a)
end

-- Re-maps `n` from range [inMin, inMax] to [outMin, outMax].
function Format.Number_Remap(n: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	local t = Format.Number_InverseLerp(inMin, inMax, n)
	return Format.Number_Lerp(outMin, outMax, t)
end

-- Formats a number with thousands separators: 1234567 -> "1,234,567"
function Format.Number_Commas(n: number): string
	local negative = n < 0
	local intPart, fracPart = math.floor(math.abs(n)), math.abs(n) - math.floor(math.abs(n))
	local s = tostring(intPart)
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	if fracPart > 0 then
		local fracStr = tostring(Format.Number_Round(fracPart, 2)):match("%.(%d+)") or ""
		if fracStr ~= "" then
			formatted = formatted .. "." .. fracStr
		end
	end
	return (negative and "-" or "") .. formatted
end

-- Abbreviates large numbers: 1500 -> "1.5K", 2400000 -> "2.4M"
function Format.Number_Abbreviate(n: number, decimals: number?): string
	local d = decimals or 1
	local absN = math.abs(n)
	local sign = n < 0 and "-" or ""
	if absN >= 1e12 then
		return sign .. Format.Number_Round(absN / 1e12, d) .. "T"
	elseif absN >= 1e9 then
		return sign .. Format.Number_Round(absN / 1e9, d) .. "B"
	elseif absN >= 1e6 then
		return sign .. Format.Number_Round(absN / 1e6, d) .. "M"
	elseif absN >= 1e3 then
		return sign .. Format.Number_Round(absN / 1e3, d) .. "K"
	else
		return sign .. tostring(absN)
	end
end

-- Formats as a US currency string: 1234.5 -> "$1,234.50"
function Format.Number_Currency(n: number, symbol: string?): string
	local rounded = Format.Number_Round(n, 2)
	local s = string.format("%.2f", rounded)
	local sign = ""
	if s:sub(1, 1) == "-" then
		sign = "-"
		s = s:sub(2)
	end
	local intPart, fracPart = s:match("^(%d+)%.(%d+)$")
	local commaInt = intPart:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. (symbol or "$") .. commaInt .. "." .. fracPart
end

-- Formats as a percentage string: 0.4567 -> "45.67%"
function Format.Number_Percent(n: number, decimals: number?): string
	return Format.Number_Round(n * 100, decimals or 0) .. "%"
end

-- Returns the ordinal suffix string: 1 -> "1st", 2 -> "2nd", 13 -> "13th"
function Format.Number_Ordinal(n: number): string
	local i = math.floor(n)
	local mod100 = i % 100
	if mod100 >= 11 and mod100 <= 13 then
		return i .. "th"
	end
	local mod10 = i % 10
	if mod10 == 1 then return i .. "st"
	elseif mod10 == 2 then return i .. "nd"
	elseif mod10 == 3 then return i .. "rd"
	else return i .. "th" end
end

-- Pads a number with leading zeros to `width`: (7, 3) -> "007"
function Format.Number_PadZero(n: number, width: number): string
	local s = tostring(math.floor(n))
	local negative = s:sub(1, 1) == "-"
	if negative then s = s:sub(2) end
	while #s < width do
		s = "0" .. s
	end
	return (negative and "-" or "") .. s
end

-- Converts a byte count into a human string: 1536 -> "1.50 KB"
function Format.Number_ByteSize(bytes: number): string
	local units = { "B", "KB", "MB", "GB", "TB" }
	local value = bytes
	local i = 1
	while value >= 1024 and i < #units do
		value /= 1024
		i += 1
	end
	return string.format("%.2f %s", value, units[i])
end

-- Converts degrees to radians.
function Format.Number_DegToRad(deg: number): number
	return math.rad(deg)
end

-- Converts radians to degrees.
function Format.Number_RadToDeg(rad: number): number
	return math.deg(rad)
end

-- Converts a decimal integer to a hex string: 255 -> "FF"
function Format.Number_ToHex(n: number): string
	return string.format("%X", math.floor(n))
end

-- Converts a hex string to a decimal number: "FF" -> 255
function Format.Number_FromHex(hex: string): number
	return tonumber(hex, 16) or 0
end

-- Converts a decimal integer to a binary string: 5 -> "101"
function Format.Number_ToBinary(n: number): string
	local i = math.floor(n)
	if i == 0 then return "0" end
	local bits = {}
	local negative = i < 0
	i = math.abs(i)
	while i > 0 do
		table.insert(bits, 1, tostring(i % 2))
		i = math.floor(i / 2)
	end
	return (negative and "-" or "") .. table.concat(bits)
end

-- Formats a number in scientific notation: 1234.5 -> "1.2345e+03"
function Format.Number_Scientific(n: number, decimals: number?): string
	return string.format("%." .. (decimals or 4) .. "e", n)
end

-- Returns true if `n` is approximately equal to `target` within `epsilon`.
function Format.Number_NearlyEqual(n: number, target: number, epsilon: number?): boolean
	return math.abs(n - target) <= (epsilon or 1e-6)
end

-- Wraps `n` between `min` and `max` (circular clamp), useful for angles.
function Format.Number_Wrap(n: number, min: number, max: number): number
	local range = max - min
	if range <= 0 then return min end
	return min + ((n - min) % range + range) % range
end

-- Formats seconds as "MM:SS" (or "H:MM:SS" if over an hour).
function Format.Number_TimeMS(totalSeconds: number): string
	local t = math.floor(totalSeconds)
	local hours = math.floor(t / 3600)
	local minutes = math.floor((t % 3600) / 60)
	local seconds = t % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds)
	end
	return string.format("%02d:%02d", minutes, seconds)
end

-- Formats a duration in seconds as a verbose string: "2h 15m 3s"
function Format.Number_DurationVerbose(totalSeconds: number): string
	local t = math.floor(totalSeconds)
	local days = math.floor(t / 86400)
	local hours = math.floor((t % 86400) / 3600)
	local minutes = math.floor((t % 3600) / 60)
	local seconds = t % 60
	local parts = {}
	if days > 0 then table.insert(parts, days .. "d") end
	if hours > 0 then table.insert(parts, hours .. "h") end
	if minutes > 0 then table.insert(parts, minutes .. "m") end
	if seconds > 0 or #parts == 0 then table.insert(parts, seconds .. "s") end
	return table.concat(parts, " ")
end

-- Returns "+n" for positive numbers, "n" otherwise (signed display).
function Format.Number_Signed(n: number): string
	if n > 0 then
		return "+" .. tostring(n)
	end
	return tostring(n)
end

-- Rounds up to the next multiple of `step`.
function Format.Number_CeilToStep(n: number, step: number): number
	return math.ceil(n / step) * step
end

-- Rounds down to the nearest multiple of `step`.
function Format.Number_FloorToStep(n: number, step: number): number
	return math.floor(n / step) * step
end

-- Rounds to the nearest multiple of `step`.
function Format.Number_RoundToStep(n: number, step: number): number
	return math.floor(n / step + 0.5) * step
end

-- Returns true if `n` is an integer value.
function Format.Number_IsInteger(n: number): boolean
	return n == math.floor(n)
end

-- Formats a ratio pair as "3 / 10".
function Format.Number_Fraction(numerator: number, denominator: number): string
	return string.format("%d / %d", numerator, denominator)
end

-- Formats health-style values as "current/max" with optional percent tag.
function Format.Number_StatBar(current: number, max: number, withPercent: boolean?): string
	local base = string.format("%d/%d", math.floor(current), math.floor(max))
	if withPercent then
		local pct = max > 0 and (current / max) or 0
		base ..= string.format(" (%d%%)", math.floor(pct * 100))
	end
	return base
end

-- Formats a countdown number, floors negatives to zero.
function Format.Number_Countdown(n: number): string
	return tostring(math.max(0, math.ceil(n)))
end

-- Converts a 0-1 alpha value into an 8-bit (0-255) integer.
function Format.Number_AlphaTo255(alpha: number): number
	return math.floor(Format.Number_Clamp(alpha, 0, 1) * 255 + 0.5)
end

------------------------------------------------------------------
-- SECTION 2: STRING
------------------------------------------------------------------

-- Trims leading/trailing whitespace.
function Format.String_Trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Capitalizes only the first letter of the string.
function Format.String_Capitalize(s: string): string
	if #s == 0 then return s end
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- Converts "hello world" -> "Hello World" (Title Case).
function Format.String_TitleCase(s: string): string
	return (s:gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end))
end

-- Truncates a string to `maxLen`, appending "..." if cut.
function Format.String_Truncate(s: string, maxLen: number, suffix: string?): string
	if #s <= maxLen then return s end
	local tail = suffix or "..."
	return s:sub(1, math.max(0, maxLen - #tail)) .. tail
end

-- Pads a string on the right to `width` with `char` (default space).
function Format.String_PadRight(s: string, width: number, char: string?): string
	local c = char or " "
	local out = s
	while #out < width do
		out ..= c
	end
	return out
end

-- Pads a string on the left to `width` with `char` (default space).
function Format.String_PadLeft(s: string, width: number, char: string?): string
	local c = char or " "
	local out = s
	while #out < width do
		out = c .. out
	end
	return out
end

-- Centers a string within `width`, padding both sides.
function Format.String_Center(s: string, width: number, char: string?): string
	local c = char or " "
	local totalPad = math.max(0, width - #s)
	local left = math.floor(totalPad / 2)
	local right = totalPad - left
	return string.rep(c, left) .. s .. string.rep(c, right)
end

-- Reverses a string.
function Format.String_Reverse(s: string): string
	return s:reverse()
end

-- Naive pluralization: appends "s" unless count == 1.
function Format.String_Pluralize(word: string, count: number, pluralForm: string?): string
	if count == 1 then return word end
	return pluralForm or (word .. "s")
end

-- Formats "count word(s)": (3, "kill") -> "3 kills"
function Format.String_CountedNoun(count: number, singular: string, plural: string?): string
	return string.format("%d %s", count, Format.String_Pluralize(singular, count, plural))
end

-- Converts "MyVariableName" -> "my_variable_name" (snake_case).
function Format.String_ToSnakeCase(s: string): string
	local result = s:gsub("(%u)", function(c) return "_" .. c:lower() end)
	result = result:gsub("^_", ""):gsub("[%s%-]+", "_")
	return result:lower()
end

-- Converts "my_variable_name" -> "MyVariableName" (PascalCase).
function Format.String_ToPascalCase(s: string): string
	local result = ""
	for word in s:gmatch("[%a%d]+") do
		result ..= Format.String_Capitalize(word:lower())
	end
	return result
end

-- Converts "my_variable_name" -> "myVariableName" (camelCase).
function Format.String_ToCamelCase(s: string): string
	local pascal = Format.String_ToPascalCase(s)
	if #pascal == 0 then return pascal end
	return pascal:sub(1, 1):lower() .. pascal:sub(2)
end

-- Converts "MyVariableName" -> "my-variable-name" (kebab-case).
function Format.String_ToKebabCase(s: string): string
	return (Format.String_ToSnakeCase(s):gsub("_", "-"))
end

-- Splits a string by `separator` into an array of substrings.
function Format.String_Split(s: string, separator: string): { string }
	local result = {}
	for part in (s .. separator):gmatch("(.-)" .. separator:gsub("(%W)", "%%%1")) do
		table.insert(result, part)
	end
	return result
end

-- Joins an array of strings with `separator`.
function Format.String_Join(parts: { string }, separator: string): string
	return table.concat(parts, separator)
end

-- Returns true if `s` starts with `prefix`.
function Format.String_StartsWith(s: string, prefix: string): boolean
	return s:sub(1, #prefix) == prefix
end

-- Returns true if `s` ends with `suffix`.
function Format.String_EndsWith(s: string, suffix: string): boolean
	return suffix == "" or s:sub(-#suffix) == suffix
end

-- Escapes Roblox RichText special characters: < > " & '
function Format.String_EscapeRichText(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

-- Wraps `s` in a RichText color tag using a hex color (e.g. "FF0000").
function Format.String_RichTextColor(s: string, hexColor: string): string
	return string.format('<font color="#%s">%s</font>', hexColor, s)
end

-- Wraps `s` in RichText bold tags.
function Format.String_RichTextBold(s: string): string
	return "<b>" .. s .. "</b>"
end

-- Wraps `s` in RichText italic tags.
function Format.String_RichTextItalic(s: string): string
	return "<i>" .. s .. "</i>"
end

-- Masks a string with `char`, leaving the last `visibleCount` characters visible.
function Format.String_Mask(s: string, visibleCount: number, char: string?): string
	local c = char or "*"
	local len = #s
	if len <= visibleCount then return s end
	local maskedLen = len - visibleCount
	return string.rep(c, maskedLen) .. s:sub(maskedLen + 1)
end

-- Wraps text to `lineWidth`, inserting newlines between words.
function Format.String_WordWrap(s: string, lineWidth: number): string
	local lines = {}
	local currentLine = ""
	for word in s:gmatch("%S+") do
		if #currentLine == 0 then
			currentLine = word
		elseif #currentLine + 1 + #word <= lineWidth then
			currentLine ..= " " .. word
		else
			table.insert(lines, currentLine)
			currentLine = word
		end
	end
	if #currentLine > 0 then table.insert(lines, currentLine) end
	return table.concat(lines, "\n")
end

-- Repeats `s` `count` times, joined by an optional separator.
function Format.String_Repeat(s: string, count: number, separator: string?): string
	local parts = {}
	for _ = 1, count do
		table.insert(parts, s)
	end
	return table.concat(parts, separator or "")
end

-- Removes all whitespace from a string.
function Format.String_StripWhitespace(s: string): string
	return (s:gsub("%s+", ""))
end

-- Counts occurrences of `substring` within `s`.
function Format.String_CountOccurrences(s: string, substring: string): number
	local _, count = s:gsub(substring:gsub("(%W)", "%%%1"), "")
	return count
end

-- Slugifies a string for use in identifiers/URLs: "Hello World!" -> "hello-world"
function Format.String_Slugify(s: string): string
	local lowered = s:lower()
	lowered = lowered:gsub("[^%w%s-]", "")
	lowered = lowered:gsub("%s+", "-")
	return lowered
end

-- Formats a player-facing chat tag: "[Owner] PlayerName"
function Format.String_TagPrefix(tag: string, name: string): string
	return string.format("[%s] %s", tag, name)
end

------------------------------------------------------------------
-- SECTION 3: VECTOR2
------------------------------------------------------------------

-- Formats a Vector2 as "(x, y)" with `decimals` precision.
function Format.Vector2_ToString(v: Vector2, decimals: number?): string
	local d = decimals or 2
	return string.format("(%." .. d .. "f, %." .. d .. "f)", v.X, v.Y)
end

-- Formats a Vector2 as compact "x,y" (no spaces/parens) for networking payloads.
function Format.Vector2_Compact(v: Vector2, decimals: number?): string
	local d = decimals or 2
	return string.format("%." .. d .. "f,%." .. d .. "f", v.X, v.Y)
end

-- Parses a "x,y" compact string back into a Vector2.
function Format.Vector2_FromCompact(s: string): Vector2
	local x, y = s:match("([%-%d%.]+),([%-%d%.]+)")
	return Vector2.new(tonumber(x) or 0, tonumber(y) or 0)
end

-- Rounds both components of a Vector2 to `decimals`.
function Format.Vector2_Round(v: Vector2, decimals: number?): Vector2
	return Vector2.new(Format.Number_Round(v.X, decimals), Format.Number_Round(v.Y, decimals))
end

-- Returns the angle (in degrees) of a Vector2 relative to the +X axis.
function Format.Vector2_AngleDeg(v: Vector2): number
	return math.deg(math.atan2(v.Y, v.X))
end

-- Formats a Vector2 as a percentage pair, useful for UDim2 debug: "45%, 60%"
function Format.Vector2_AsPercent(v: Vector2): string
	return string.format("%d%%, %d%%", math.floor(v.X * 100), math.floor(v.Y * 100))
end

-- Clamps both axes of a Vector2 between min/max Vector2s.
function Format.Vector2_Clamp(v: Vector2, min: Vector2, max: Vector2): Vector2
	return Vector2.new(math.clamp(v.X, min.X, max.X), math.clamp(v.Y, min.Y, max.Y))
end

-- Formats a Vector2 as screen resolution style: "1920x1080"
function Format.Vector2_AsResolution(v: Vector2): string
	return string.format("%dx%d", math.floor(v.X), math.floor(v.Y))
end

-- Returns true if two Vector2s are nearly equal within epsilon.
function Format.Vector2_NearlyEqual(a: Vector2, b: Vector2, epsilon: number?): boolean
	return (a - b).Magnitude <= (epsilon or 1e-4)
end

-- Formats a Vector2 delta with signed components: "(+3.00, -1.50)"
function Format.Vector2_SignedString(v: Vector2, decimals: number?): string
	local d = decimals or 2
	return string.format("(%s, %s)", Format.Number_Signed(Format.Number_Round(v.X, d)), Format.Number_Signed(Format.Number_Round(v.Y, d)))
end

------------------------------------------------------------------
-- SECTION 4: VECTOR3
------------------------------------------------------------------

-- Formats a Vector3 as "(x, y, z)" with `decimals` precision.
function Format.Vector3_ToString(v: Vector3, decimals: number?): string
	local d = decimals or 2
	return string.format("(%." .. d .. "f, %." .. d .. "f, %." .. d .. "f)", v.X, v.Y, v.Z)
end

-- Compact comma-joined form for networking payloads: "1.00,2.00,3.00"
function Format.Vector3_Compact(v: Vector3, decimals: number?): string
	local d = decimals or 2
	return string.format("%." .. d .. "f,%." .. d .. "f,%." .. d .. "f", v.X, v.Y, v.Z)
end

-- Parses a compact "x,y,z" string back into a Vector3.
function Format.Vector3_FromCompact(s: string): Vector3
	local x, y, z = s:match("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
	return Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
end

-- Rounds all components of a Vector3.
function Format.Vector3_Round(v: Vector3, decimals: number?): Vector3
	return Vector3.new(Format.Number_Round(v.X, decimals), Format.Number_Round(v.Y, decimals), Format.Number_Round(v.Z, decimals))
end

-- Formats distance between two points in studs, with unit suffix.
function Format.Vector3_DistanceStuds(a: Vector3, b: Vector3, decimals: number?): string
	return Format.Number_Round((a - b).Magnitude, decimals or 1) .. " studs"
end

-- Formats a Vector3 as a compass-style direction string (N/NE/E/etc) on XZ plane.
function Format.Vector3_ToCompass(v: Vector3): string
	local angle = math.deg(math.atan2(v.X, v.Z))
	if angle < 0 then angle += 360 end
	local directions = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	local index = math.floor((angle + 22.5) / 45) % 8 + 1
	return directions[index]
end

-- Flattens a Vector3 to XZ plane (zeroes Y), commonly used for ground movement.
function Format.Vector3_FlattenXZ(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Formats a Vector3 magnitude as speed: "42.5 studs/s"
function Format.Vector3_AsSpeed(velocity: Vector3, decimals: number?): string
	return Format.Number_Round(velocity.Magnitude, decimals or 1) .. " studs/s"
end

-- Clamps a Vector3's magnitude to `maxLength`.
function Format.Vector3_ClampMagnitude(v: Vector3, maxLength: number): Vector3
	if v.Magnitude <= maxLength then return v end
	return v.Unit * maxLength
end

-- Returns true if two Vector3s are nearly equal within epsilon.
function Format.Vector3_NearlyEqual(a: Vector3, b: Vector3, epsilon: number?): boolean
	return (a - b).Magnitude <= (epsilon or 1e-4)
end

-- Formats a Vector3 with signed component display: "(+1.00, -2.00, +0.00)"
function Format.Vector3_SignedString(v: Vector3, decimals: number?): string
	local d = decimals or 2
	return string.format(
		"(%s, %s, %s)",
		Format.Number_Signed(Format.Number_Round(v.X, d)),
		Format.Number_Signed(Format.Number_Round(v.Y, d)),
		Format.Number_Signed(Format.Number_Round(v.Z, d))
	)
end

-- Formats a Vector3 as a grid cell coordinate string, given `cellSize`: "[3, 0, -2]"
function Format.Vector3_ToGridCell(v: Vector3, cellSize: number): string
	local gx = math.floor(v.X / cellSize)
	local gy = math.floor(v.Y / cellSize)
	local gz = math.floor(v.Z / cellSize)
	return string.format("[%d, %d, %d]", gx, gy, gz)
end

-- Formats a Vector3 length as an altitude readout: "Y: 152.3"
function Format.Vector3_AltitudeReadout(v: Vector3, decimals: number?): string
	return "Y: " .. Format.Number_Round(v.Y, decimals or 1)
end

-- Snaps each axis of a Vector3 to the nearest multiple of `step`.
function Format.Vector3_SnapToStep(v: Vector3, step: number): Vector3
	return Vector3.new(
		Format.Number_RoundToStep(v.X, step),
		Format.Number_RoundToStep(v.Y, step),
		Format.Number_RoundToStep(v.Z, step)
	)
end

------------------------------------------------------------------
-- SECTION 5: CFRAME
------------------------------------------------------------------

-- Formats a CFrame's position component: "(x, y, z)"
function Format.CFrame_PositionString(cf: CFrame, decimals: number?): string
	return Format.Vector3_ToString(cf.Position, decimals)
end

-- Formats a CFrame's rotation as Euler angles in degrees: "(rx, ry, rz)"
function Format.CFrame_EulerDegString(cf: CFrame, decimals: number?): string
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	local d = decimals or 1
	return string.format(
		"(%." .. d .. "f, %." .. d .. "f, %." .. d .. "f)",
		math.deg(rx), math.deg(ry), math.deg(rz)
	)
end

-- Formats a full CFrame as "pos=(x,y,z) rot=(rx,ry,rz)".
function Format.CFrame_FullString(cf: CFrame, decimals: number?): string
	return string.format("pos=%s rot=%s", Format.CFrame_PositionString(cf, decimals), Format.CFrame_EulerDegString(cf, decimals))
end

-- Serializes a CFrame to 12 comma-separated components for storage/networking.
function Format.CFrame_Serialize(cf: CFrame): string
	local components = { cf:GetComponents() }
	local parts = {}
	for _, c in components do
		table.insert(parts, string.format("%.4f", c))
	end
	return table.concat(parts, ",")
end

-- Deserializes a CFrame from the string produced by CFrame_Serialize.
function Format.CFrame_Deserialize(s: string): CFrame
	local nums = {}
	for match in s:gmatch("[%-%d%.]+") do
		table.insert(nums, tonumber(match) or 0)
	end
	return CFrame.new(table.unpack(nums))
end

-- Returns the CFrame's forward-facing look vector formatted as a string.
function Format.CFrame_LookVectorString(cf: CFrame, decimals: number?): string
	return Format.Vector3_ToString(cf.LookVector, decimals)
end

-- Formats yaw (heading) only, in degrees, from a CFrame: "87.5°"
function Format.CFrame_YawDegString(cf: CFrame, decimals: number?): string
	local _, ry, _ = cf:ToEulerAnglesYXZ()
	return Format.Number_Round(math.deg(ry), decimals or 1) .. "°"
end

-- Returns true if two CFrames are nearly equal (position + rotation) within epsilon.
function Format.CFrame_NearlyEqual(a: CFrame, b: CFrame, posEpsilon: number?, angleEpsilonDeg: number?): boolean
	if not Format.Vector3_NearlyEqual(a.Position, b.Position, posEpsilon) then
		return false
	end
	local _, angle = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	return math.deg(angle) <= (angleEpsilonDeg or 0.5)
end

-- Formats a CFrame as a spawn-point style descriptor: "Spawn @ (x, y, z) facing 90°"
function Format.CFrame_SpawnDescriptor(cf: CFrame, decimals: number?): string
	return string.format("Spawn @ %s facing %s", Format.CFrame_PositionString(cf, decimals), Format.CFrame_YawDegString(cf, decimals))
end

-- Extrapolates a CFrame's position along its LookVector by `distance` and formats it.
function Format.CFrame_ProjectedPositionString(cf: CFrame, distance: number, decimals: number?): string
	local projected = cf.Position + cf.LookVector * distance
	return Format.Vector3_ToString(projected, decimals)
end

-- Formats the up-vector of a CFrame as a string, useful for debugging ragdoll/aim state.
function Format.CFrame_UpVectorString(cf: CFrame, decimals: number?): string
	return Format.Vector3_ToString(cf.UpVector, decimals)
end

-- Formats the angular difference between two CFrames' rotations in degrees.
function Format.CFrame_AngleDiffDeg(a: CFrame, b: CFrame, decimals: number?): number
	local _, angle = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	return Format.Number_Round(math.deg(angle), decimals or 1)
end

------------------------------------------------------------------
-- SECTION 6: COLOR3
------------------------------------------------------------------

-- Formats a Color3 as an RGB 0-255 string: "rgb(255, 128, 0)"
function Format.Color3_ToRGBString(c: Color3): string
	return string.format("rgb(%d, %d, %d)", Format.Number_AlphaTo255(c.R), Format.Number_AlphaTo255(c.G), Format.Number_AlphaTo255(c.B))
end

-- Formats a Color3 as a hex string: "#FF8000"
function Format.Color3_ToHex(c: Color3): string
	return string.format("#%02X%02X%02X", Format.Number_AlphaTo255(c.R), Format.Number_AlphaTo255(c.G), Format.Number_AlphaTo255(c.B))
end

-- Parses a hex string ("#FF8000" or "FF8000") into a Color3.
function Format.Color3_FromHex(hex: string): Color3
	local clean = hex:gsub("#", "")
	local r = tonumber(clean:sub(1, 2), 16) or 0
	local g = tonumber(clean:sub(3, 4), 16) or 0
	local b = tonumber(clean:sub(5, 6), 16) or 0
	return Color3.fromRGB(r, g, b)
end

-- Formats a Color3 as HSV string: "hsv(30, 100%, 100%)"
function Format.Color3_ToHSVString(c: Color3): string
	local h, s, v = c:ToHSV()
	return string.format("hsv(%d, %d%%, %d%%)", math.floor(h * 360), math.floor(s * 100), math.floor(v * 100))
end

-- Lerps between two Color3s (thin convenience wrapper over Color3.Lerp with formatting note).
function Format.Color3_Lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

-- Returns a formatted grayscale value string for a Color3: "Gray: 68%"
function Format.Color3_LuminanceString(c: Color3): string
	local luminance = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	return string.format("Gray: %d%%", math.floor(luminance * 100))
end

-- Returns true if a Color3 is closer to white or black (for choosing contrasting text color).
function Format.Color3_ContrastTextColor(c: Color3): Color3
	local luminance = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	if luminance > 0.5 then
		return Color3.new(0, 0, 0)
	end
	return Color3.new(1, 1, 1)
end

-- Formats a Color3 as a compact CSV for networking: "255,128,0"
function Format.Color3_Compact(c: Color3): string
	return string.format("%d,%d,%d", Format.Number_AlphaTo255(c.R), Format.Number_AlphaTo255(c.G), Format.Number_AlphaTo255(c.B))
end

-- Parses a compact "r,g,b" (0-255) string back into a Color3.
function Format.Color3_FromCompact(s: string): Color3
	local r, g, b = s:match("(%d+),(%d+),(%d+)")
	return Color3.fromRGB(tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0)
end

-- Returns true if two Color3s are nearly equal within epsilon.
function Format.Color3_NearlyEqual(a: Color3, b: Color3, epsilon: number?): boolean
	local e = epsilon or 1 / 255
	return math.abs(a.R - b.R) <= e and math.abs(a.G - b.G) <= e and math.abs(a.B - b.B) <= e
end

-- Formats a Color3 as a health-bar tier color descriptor: "Healthy" / "Wounded" / "Critical" based on green channel.
function Format.Color3_HealthTierLabel(c: Color3): string
	if c.G > 0.7 then return "Healthy"
	elseif c.G > 0.3 then return "Wounded"
	else return "Critical" end
end

-- Blends a Color3 toward gray by `amount` (0-1), for desaturation effects.
function Format.Color3_Desaturate(c: Color3, amount: number): Color3
	local gray = (c.R + c.G + c.B) / 3
	return Color3.new(
		Format.Number_Lerp(c.R, gray, amount),
		Format.Number_Lerp(c.G, gray, amount),
		Format.Number_Lerp(c.B, gray, amount)
	)
end

-- Returns the nearest BrickColor name to a given Color3.
function Format.Color3_NearestBrickColorName(c: Color3): string
	return BrickColor.new(c).Name
end

-- Formats a Color3 as a rich text color-tag-ready hex (no '#').
function Format.Color3_ToHexNoHash(c: Color3): string
	return Format.Color3_ToHex(c):gsub("#", "")
end

-- Formats an alpha/transparency value paired with a Color3: "rgba(255,128,0,0.50)"
function Format.Color3_ToRGBAString(c: Color3, alpha: number): string
	return string.format("rgba(%d,%d,%d,%.2f)", Format.Number_AlphaTo255(c.R), Format.Number_AlphaTo255(c.G), Format.Number_AlphaTo255(c.B), alpha)
end

------------------------------------------------------------------
-- SECTION 7: UDIM / UDIM2
------------------------------------------------------------------

-- Formats a UDim as "{scale, offset}".
function Format.UDim_ToString(u: UDim, decimals: number?): string
	return string.format("{%." .. (decimals or 2) .. "f, %d}", u.Scale, u.Offset)
end

-- Formats a UDim2 as "{{sx, ox}, {sy, oy}}".
function Format.UDim2_ToString(u: UDim2, decimals: number?): string
	return string.format("%s, %s", Format.UDim_ToString(u.X, decimals), Format.UDim_ToString(u.Y, decimals))
end

-- Formats a UDim2's scale component only, as a percentage pair: "45%, 60%"
function Format.UDim2_ScaleAsPercent(u: UDim2): string
	return string.format("%d%%, %d%%", math.floor(u.X.Scale * 100), math.floor(u.Y.Scale * 100))
end

-- Formats a UDim2's offset component only, as pixel dims: "128px, 64px"
function Format.UDim2_OffsetAsPixels(u: UDim2): string
	return string.format("%dpx, %dpx", u.X.Offset, u.Y.Offset)
end

-- Creates a UDim2 from percentage numbers (0-100) with zero offset.
function Format.UDim2_FromPercent(xPercent: number, yPercent: number): UDim2
	return UDim2.fromScale(xPercent / 100, yPercent / 100)
end

-- Lerps between two UDim2 values.
function Format.UDim2_Lerp(a: UDim2, b: UDim2, t: number): UDim2
	return a:Lerp(b, t)
end

-- Returns true if two UDim2 values are nearly equal within epsilon.
function Format.UDim2_NearlyEqual(a: UDim2, b: UDim2, epsilon: number?): boolean
	local e = epsilon or 1e-3
	return math.abs(a.X.Scale - b.X.Scale) <= e
		and math.abs(a.Y.Scale - b.Y.Scale) <= e
		and math.abs(a.X.Offset - b.X.Offset) <= 1
		and math.abs(a.Y.Offset - b.Y.Offset) <= 1
end

-- Formats a UDim2 as a CSS-like string for debug overlays: "left: 45%+10px; top: 60%+0px;"
function Format.UDim2_ToCSSDebugString(u: UDim2): string
	return string.format("left: %d%%+%dpx; top: %d%%+%dpx;", math.floor(u.X.Scale * 100), u.X.Offset, math.floor(u.Y.Scale * 100), u.Y.Offset)
end

-- Converts a UDim2 anchored at (0.5, 0.5) into corner-relative offsets given AbsoluteSize.
function Format.UDim2_ToCornerString(u: UDim2, absoluteSize: Vector2): string
	local x = u.X.Scale * absoluteSize.X + u.X.Offset
	local y = u.Y.Scale * absoluteSize.Y + u.Y.Offset
	return Format.Vector2_ToString(Vector2.new(x, y))
end

-- Formats a UDim2 padding shorthand for margin-style values: "10px, 10px, 10px, 10px"
function Format.UDim2_PaddingShorthand(pixels: number): string
	return string.format("%dpx, %dpx, %dpx, %dpx", pixels, pixels, pixels, pixels)
end

------------------------------------------------------------------
-- SECTION 8: BRICKCOLOR
------------------------------------------------------------------

-- Formats a BrickColor as "Name (r,g,b)".
function Format.BrickColor_ToString(bc: BrickColor): string
	local c = bc.Color
	return string.format("%s (%d,%d,%d)", bc.Name, Format.Number_AlphaTo255(c.R), Format.Number_AlphaTo255(c.G), Format.Number_AlphaTo255(c.B))
end

-- Returns the hex string equivalent of a BrickColor.
function Format.BrickColor_ToHex(bc: BrickColor): string
	return Format.Color3_ToHex(bc.Color)
end

-- Returns a BrickColor from a hex string.
function Format.BrickColor_FromHex(hex: string): BrickColor
	return BrickColor.new(Format.Color3_FromHex(hex))
end

-- Returns true if two BrickColors share the same palette Number.
function Format.BrickColor_IsSame(a: BrickColor, b: BrickColor): boolean
	return a.Number == b.Number
end

-- Formats a BrickColor's numeric palette id with its name: "[21] Really red"
function Format.BrickColor_IdLabel(bc: BrickColor): string
	return string.format("[%d] %s", bc.Number, bc.Name)
end

-- Returns a random BrickColor's formatted name, useful for debug team-color assignment.
function Format.BrickColor_RandomName(): string
	return BrickColor.random().Name
end

------------------------------------------------------------------
-- SECTION 9: ENUM
------------------------------------------------------------------

-- Formats an EnumItem as "EnumType.Name": "Material.Wood"
function Format.Enum_ToString(item: EnumItem): string
	return string.format("%s.%s", tostring(item.EnumType), item.Name)
end

-- Returns just the Name portion of an EnumItem.
function Format.Enum_NameOnly(item: EnumItem): string
	return item.Name
end

-- Returns the numeric Value of an EnumItem as a string.
function Format.Enum_ValueString(item: EnumItem): string
	return tostring(item.Value)
end

-- Converts a spaced-out enum name into human readable form: "LeftExit" -> "Left Exit"
function Format.Enum_HumanizeName(item: EnumItem): string
	return (item.Name:gsub("(%l)(%u)", "%1 %2"))
end

-- Finds an EnumItem by name within a given Enum, case-insensitively; nil if not found.
function Format.Enum_FindByName(enumType: Enum, name: string): EnumItem?
	for _, item in enumType:GetEnumItems() do
		if item.Name:lower() == name:lower() then
			return item
		end
	end
	return nil
end

-- Formats a list of EnumItems as a comma-separated readable string.
function Format.Enum_ListToString(items: { EnumItem }): string
	local names = {}
	for _, item in items do
		table.insert(names, item.Name)
	end
	return table.concat(names, ", ")
end

------------------------------------------------------------------
-- SECTION 10: INSTANCE
------------------------------------------------------------------

-- Returns the full dot-separated hierarchy path of an Instance: "Workspace.Map.Doors.Door1"
function Format.Instance_GetPath(inst: Instance): string
	local parts = { inst.Name }
	local current = inst.Parent
	while current do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

-- Formats an Instance as "ClassName \"Name\"": 'Part "Wall1"'
function Format.Instance_ClassAndName(inst: Instance): string
	return string.format('%s "%s"', inst.ClassName, inst.Name)
end

-- Returns a formatted count of direct children: "Folder \"Loot\" (5 children)"
function Format.Instance_ChildCountLabel(inst: Instance): string
	return string.format('%s "%s" (%d children)', inst.ClassName, inst.Name, #inst:GetChildren())
end

-- Returns a formatted count of all descendants.
function Format.Instance_DescendantCountLabel(inst: Instance): string
	return string.format('%s "%s" (%d descendants)', inst.ClassName, inst.Name, #inst:GetDescendants())
end

-- Formats an Instance's attributes as a readable "key=value" list.
function Format.Instance_AttributesString(inst: Instance): string
	local parts = {}
	for key, value in inst:GetAttributes() do
		table.insert(parts, string.format("%s=%s", key, tostring(value)))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- Builds an indented tree string of an Instance and its descendants, up to `maxDepth`.
function Format.Instance_TreeString(inst: Instance, maxDepth: number?): string
	local lines = {}
	local function recurse(node: Instance, depth: number)
		table.insert(lines, string.rep("  ", depth) .. node.ClassName .. ": " .. node.Name)
		if maxDepth == nil or depth < maxDepth then
			for _, child in node:GetChildren() do
				recurse(child, depth + 1)
			end
		end
	end
	recurse(inst, 0)
	return table.concat(lines, "\n")
end

-- Formats a BasePart's Size as a dimensions string: "4.0 x 1.0 x 2.0 studs"
function Format.Instance_PartSizeString(part: BasePart, decimals: number?): string
	local d = decimals or 1
	return string.format("%." .. d .. "f x %." .. d .. "f x %." .. d .. "f studs", part.Size.X, part.Size.Y, part.Size.Z)
end

-- Formats a BasePart's approximate volume in studs^3.
function Format.Instance_PartVolumeString(part: BasePart, decimals: number?): string
	local volume = part.Size.X * part.Size.Y * part.Size.Z
	return Format.Number_Round(volume, decimals or 1) .. " studs^3"
end

-- Formats an Instance's ClassName with a friendly icon-style prefix tag (text only), e.g. "[Model] Car"
function Format.Instance_IconTag(inst: Instance): string
	return string.format("[%s] %s", inst.ClassName, inst.Name)
end

-- Formats a Humanoid's state as a readable label: "Running" / "Freefall" / etc.
function Format.Instance_HumanoidStateLabel(humanoid: Humanoid): string
	return Format.Enum_HumanizeName(humanoid:GetState())
end

-- Formats a Player's UserId + Name as a debug tag: "PlayerName (123456789)"
function Format.Instance_PlayerTag(player: Player): string
	return string.format("%s (%d)", player.Name, player.UserId)
end

-- Formats a Tool's name with an equipped/unequipped state suffix.
function Format.Instance_ToolStateLabel(tool: Tool): string
	local equipped = tool.Parent and tool.Parent:IsA("Model") and tool.Parent:FindFirstChildOfClass("Humanoid") ~= nil
	return string.format("%s [%s]", tool.Name, equipped and "Equipped" or "Stored")
end

-- Returns a formatted, sorted list of an Instance's Tags (CollectionService).
function Format.Instance_TagsString(inst: Instance): string
	local CollectionService = game:GetService("CollectionService")
	local tags = CollectionService:GetTags(inst)
	table.sort(tags)
	return table.concat(tags, ", ")
end

-- Formats a NumberValue/IntValue/StringValue/BoolValue instance as "Name = Value".
function Format.Instance_ValueObjectString(valueObj: Instance & { Value: any }): string
	return string.format("%s = %s", valueObj.Name, tostring(valueObj.Value))
end

------------------------------------------------------------------
-- SECTION 11: RAY
------------------------------------------------------------------

-- Formats a Ray as "Origin -> Direction".
function Format.Ray_ToString(ray: Ray, decimals: number?): string
	return string.format("%s -> %s", Format.Vector3_ToString(ray.Origin, decimals), Format.Vector3_ToString(ray.Direction, decimals))
end

-- Returns the length (magnitude) of a Ray's Direction vector.
function Format.Ray_Length(ray: Ray): number
	return ray.Direction.Magnitude
end

-- Formats a Ray's endpoint (Origin + Direction) as a string.
function Format.Ray_EndpointString(ray: Ray, decimals: number?): string
	return Format.Vector3_ToString(ray.Origin + ray.Direction, decimals)
end

-- Builds a Ray from two points (start, end).
function Format.Ray_FromPoints(startPos: Vector3, endPos: Vector3): Ray
	return Ray.new(startPos, endPos - startPos)
end

-- Formats a Ray as a debug label including its length in studs.
function Format.Ray_DebugLabel(ray: Ray, decimals: number?): string
	return string.format("Ray[%s, len=%s]", Format.Ray_ToString(ray, decimals), Format.Number_Round(Format.Ray_Length(ray), decimals or 1))
end

------------------------------------------------------------------
-- SECTION 12: REGION3
------------------------------------------------------------------

-- Formats a Region3 as "min -> max".
function Format.Region3_ToString(region: Region3, decimals: number?): string
	local half = region.Size / 2
	local min = region.CFrame.Position - half
	local max = region.CFrame.Position + half
	return string.format("%s -> %s", Format.Vector3_ToString(min, decimals), Format.Vector3_ToString(max, decimals))
end

-- Formats a Region3's size as dimensions.
function Format.Region3_SizeString(region: Region3, decimals: number?): string
	return Format.Vector3_ToString(region.Size, decimals)
end

-- Formats a Region3's volume in studs^3.
function Format.Region3_VolumeString(region: Region3, decimals: number?): string
	local volume = region.Size.X * region.Size.Y * region.Size.Z
	return Format.Number_Round(volume, decimals or 1) .. " studs^3"
end

-- Builds a Region3 from two corner points.
function Format.Region3_FromCorners(a: Vector3, b: Vector3): Region3
	local min = Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local max = Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	return Region3.new(min, max)
end

-- Returns true if a point lies within a Region3's bounds.
function Format.Region3_ContainsPoint(region: Region3, point: Vector3): boolean
	local half = region.Size / 2
	local center = region.CFrame.Position
	local min = center - half
	local max = center + half
	return point.X >= min.X and point.X <= max.X
		and point.Y >= min.Y and point.Y <= max.Y
		and point.Z >= min.Z and point.Z <= max.Z
end

------------------------------------------------------------------
-- SECTION 13: NUMBERRANGE / NUMBERSEQUENCE / COLORSEQUENCE
------------------------------------------------------------------

-- Formats a NumberRange as "[min, max]".
function Format.NumberRange_ToString(range: NumberRange, decimals: number?): string
	local d = decimals or 2
	return string.format("[%." .. d .. "f, %." .. d .. "f]", range.Min, range.Max)
end

-- Returns a random value within a NumberRange (uniform).
function Format.NumberRange_RandomValue(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

-- Formats a NumberRange as a damage-roll style string: "12-18 dmg"
function Format.NumberRange_DamageRollString(range: NumberRange): string
	return string.format("%d-%d dmg", math.floor(range.Min), math.floor(range.Max))
end

-- Formats a NumberSequence's keypoints as a readable list: "t=0:v0, t=0.5:v1, t=1:v0.5"
function Format.NumberSequence_ToString(seq: NumberSequence, decimals: number?): string
	local d = decimals or 2
	local parts = {}
	for _, kp in seq.Keypoints do
		table.insert(parts, string.format("t=%." .. d .. "f:v%." .. d .. "f", kp.Time, kp.Value))
	end
	return table.concat(parts, ", ")
end

-- Samples a NumberSequence at time `t` (0-1), linearly interpolating between keypoints.
function Format.NumberSequence_Sample(seq: NumberSequence, t: number): number
	local clamped = Format.Number_Clamp(t, 0, 1)
	local keypoints = seq.Keypoints
	for i = 1, #keypoints - 1 do
		local a, b = keypoints[i], keypoints[i + 1]
		if clamped >= a.Time and clamped <= b.Time then
			local alpha = (b.Time == a.Time) and 0 or (clamped - a.Time) / (b.Time - a.Time)
			return Format.Number_Lerp(a.Value, b.Value, alpha)
		end
	end
	return keypoints[#keypoints].Value
end

-- Formats a ColorSequence's keypoints as a readable list of "t=time:#hex".
function Format.ColorSequence_ToString(seq: ColorSequence, decimals: number?): string
	local d = decimals or 2
	local parts = {}
	for _, kp in seq.Keypoints do
		table.insert(parts, string.format("t=%." .. d .. "f:%s", kp.Time, Format.Color3_ToHex(kp.Value)))
	end
	return table.concat(parts, ", ")
end

-- Samples a ColorSequence at time `t` (0-1), linearly interpolating color between keypoints.
function Format.ColorSequence_Sample(seq: ColorSequence, t: number): Color3
	local clamped = Format.Number_Clamp(t, 0, 1)
	local keypoints = seq.Keypoints
	for i = 1, #keypoints - 1 do
		local a, b = keypoints[i], keypoints[i + 1]
		if clamped >= a.Time and clamped <= b.Time then
			local alpha = (b.Time == a.Time) and 0 or (clamped - a.Time) / (b.Time - a.Time)
			return a.Value:Lerp(b.Value, alpha)
		end
	end
	return keypoints[#keypoints].Value
end

-- Builds a simple two-stop NumberSequence from a start/end value.
function Format.NumberSequence_FromTwoValues(startVal: number, endVal: number): NumberSequence
	return NumberSequence.new(startVal, endVal)
end

-- Builds a simple two-stop ColorSequence from a start/end Color3.
function Format.ColorSequence_FromTwoColors(startColor: Color3, endColor: Color3): ColorSequence
	return ColorSequence.new(startColor, endColor)
end

-- Formats the number of keypoints in a sequence: "NumberSequence(4 keypoints)"
function Format.NumberSequence_KeypointCountLabel(seq: NumberSequence): string
	return string.format("NumberSequence(%d keypoints)", #seq.Keypoints)
end

------------------------------------------------------------------
-- SECTION 14: RECT
------------------------------------------------------------------

-- Formats a Rect as "(minX, minY) -> (maxX, maxY)".
function Format.Rect_ToString(rect: Rect, decimals: number?): string
	local d = decimals or 1
	return string.format(
		"(%." .. d .. "f, %." .. d .. "f) -> (%." .. d .. "f, %." .. d .. "f)",
		rect.Min.X, rect.Min.Y, rect.Max.X, rect.Max.Y
	)
end

-- Returns the width of a Rect.
function Format.Rect_Width(rect: Rect): number
	return rect.Max.X - rect.Min.X
end

-- Returns the height of a Rect.
function Format.Rect_Height(rect: Rect): number
	return rect.Max.Y - rect.Min.Y
end

-- Formats a Rect's dimensions as "WxH": "128x64"
function Format.Rect_DimensionsString(rect: Rect): string
	return string.format("%dx%d", math.floor(Format.Rect_Width(rect)), math.floor(Format.Rect_Height(rect)))
end

-- Returns true if a point lies within a Rect's bounds (useful for ImageLabel slicing math).
function Format.Rect_ContainsPoint(rect: Rect, point: Vector2): boolean
	return point.X >= rect.Min.X and point.X <= rect.Max.X and point.Y >= rect.Min.Y and point.Y <= rect.Max.Y
end

------------------------------------------------------------------
-- SECTION 15: TWEENINFO
------------------------------------------------------------------

-- Formats a TweenInfo as a readable summary string.
function Format.TweenInfo_ToString(info: TweenInfo): string
	return string.format(
		"Time=%.2f Style=%s Dir=%s Reps=%d Rev=%s Delay=%.2f",
		info.Time, info.EasingStyle.Name, info.EasingDirection.Name, info.RepeatCount, tostring(info.Reverses), info.DelayTime
	)
end

-- Builds a simple TweenInfo from just a duration, using sane defaults.
function Format.TweenInfo_Simple(duration: number): TweenInfo
	return TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- Builds a "bouncy" TweenInfo preset.
function Format.TweenInfo_Bouncy(duration: number): TweenInfo
	return TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Builds a looping TweenInfo preset that reverses infinitely.
function Format.TweenInfo_LoopPingPong(duration: number): TweenInfo
	return TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
end

-- Returns the total effective duration of a TweenInfo accounting for delay and repeats.
function Format.TweenInfo_TotalDuration(info: TweenInfo): number
	local repeats = info.RepeatCount < 0 and 1 or (info.RepeatCount + 1)
	local perCycle = info.Reverses and info.Time * 2 or info.Time
	return info.DelayTime + perCycle * repeats
end

------------------------------------------------------------------
-- SECTION 16: TABLE
------------------------------------------------------------------

-- Pretty-prints a table as an indented, JSON-like string (non-cyclic tables only).
function Format.Table_PrettyPrint(t: { [any]: any }, indent: number?): string
	local ind = indent or 0
	local pad = string.rep("  ", ind)
	local lines = { "{" }
	for k, v in t do
		local keyStr = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
		local valStr
		if type(v) == "table" then
			valStr = Format.Table_PrettyPrint(v, ind + 1)
		elseif type(v) == "string" then
			valStr = '"' .. v .. '"'
		else
			valStr = tostring(v)
		end
		table.insert(lines, pad .. "  " .. keyStr .. " = " .. valStr .. ",")
	end
	table.insert(lines, pad .. "}")
	return table.concat(lines, "\n")
end

-- Joins an array of any values into a comma-separated string via tostring().
function Format.Table_JoinToString(arr: { any }, separator: string?): string
	local parts = {}
	for _, v in arr do
		table.insert(parts, tostring(v))
	end
	return table.concat(parts, separator or ", ")
end

-- Formats a dictionary as "key: value" lines.
function Format.Table_DictToLines(t: { [string]: any }): string
	local lines = {}
	for k, v in t do
		table.insert(lines, string.format("%s: %s", k, tostring(v)))
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

-- Counts the number of keys in a dictionary-style table (non-array-safe).
function Format.Table_CountKeys(t: { [any]: any }): number
	local count = 0
	for _ in t do
		count += 1
	end
	return count
end

-- Formats an array's length with a label: "Inventory: 12 items"
function Format.Table_LengthLabel(arr: { any }, label: string): string
	return string.format("%s: %d items", label, #arr)
end

-- Returns a shallow-copied table (new reference, same values one level deep).
function Format.Table_ShallowCopy(t: { [any]: any }): { [any]: any }
	local copy = {}
	for k, v in t do
		copy[k] = v
	end
	return copy
end

-- Formats a leaderboard-style array of {name, value} pairs as ranked lines.
function Format.Table_LeaderboardString(entries: { { name: string, value: number } }): string
	local sorted = Format.Table_ShallowCopy(entries) :: { { name: string, value: number } }
	table.sort(sorted, function(a, b) return a.value > b.value end)
	local lines = {}
	for i, entry in sorted do
		table.insert(lines, string.format("%s. %s - %s", Format.Number_Ordinal(i), entry.name, Format.Number_Commas(entry.value)))
	end
	return table.concat(lines, "\n")
end

-- Formats an array of strings as a comma list with a final "and": "A, B, and C"
function Format.Table_HumanList(items: { string }): string
	local n = #items
	if n == 0 then return "" end
	if n == 1 then return items[1] end
	if n == 2 then return items[1] .. " and " .. items[2] end
	local head = {}
	for i = 1, n - 1 do
		table.insert(head, items[i])
	end
	return table.concat(head, ", ") .. ", and " .. items[n]
end

-- Flattens a nested array of arrays into a single-depth array.
function Format.Table_Flatten(nested: { { any } }): { any }
	local flat = {}
	for _, sub in nested do
		for _, v in sub do
			table.insert(flat, v)
		end
	end
	return flat
end

-- Formats a table's keys as a sorted comma-separated string.
function Format.Table_KeysString(t: { [string]: any }): string
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return table.concat(keys, ", ")
end

------------------------------------------------------------------
-- SECTION 17: TIME / DATE
------------------------------------------------------------------

-- Formats a unix timestamp as "YYYY-MM-DD HH:MM:SS" (UTC).
function Format.Time_ToDateTimeString(unixSeconds: number): string
	return os.date("!%Y-%m-%d %H:%M:%S", unixSeconds) :: string
end

-- Formats a unix timestamp as a short date: "Jul 13, 2026".
function Format.Time_ToShortDate(unixSeconds: number): string
	return os.date("!%b %d, %Y", unixSeconds) :: string
end

-- Formats a unix timestamp as a 12-hour clock time: "3:45 PM".
function Format.Time_ToClockString(unixSeconds: number): string
	local hour24 = tonumber(os.date("!%H", unixSeconds)) :: number
	local minute = os.date("!%M", unixSeconds) :: string
	local suffix = hour24 >= 12 and "PM" or "AM"
	local hour12 = hour24 % 12
	if hour12 == 0 then hour12 = 12 end
	return string.format("%d:%s %s", hour12, minute, suffix)
end

-- Returns a "time ago" style string relative to now: "5 minutes ago".
function Format.Time_Ago(unixSeconds: number, nowUnixSeconds: number?): string
	local now = nowUnixSeconds or os.time()
	local diff = math.max(0, now - unixSeconds)
	if diff < 60 then
		return Format.String_CountedNoun(diff, "second") .. " ago"
	elseif diff < 3600 then
		return Format.String_CountedNoun(math.floor(diff / 60), "minute") .. " ago"
	elseif diff < 86400 then
		return Format.String_CountedNoun(math.floor(diff / 3600), "hour") .. " ago"
	elseif diff < 2592000 then
		return Format.String_CountedNoun(math.floor(diff / 86400), "day") .. " ago"
	elseif diff < 31536000 then
		return Format.String_CountedNoun(math.floor(diff / 2592000), "month") .. " ago"
	else
		return Format.String_CountedNoun(math.floor(diff / 31536000), "year") .. " ago"
	end
end

-- Returns a countdown string until a future unix timestamp: "in 2h 15m".
function Format.Time_Until(unixSeconds: number, nowUnixSeconds: number?): string
	local now = nowUnixSeconds or os.time()
	local diff = math.max(0, unixSeconds - now)
	return "in " .. Format.Number_DurationVerbose(diff)
end

-- Formats os.clock()/tick()-style elapsed seconds as a stopwatch string: "01:23.45"
function Format.Time_StopwatchString(elapsedSeconds: number): string
	local minutes = math.floor(elapsedSeconds / 60)
	local seconds = elapsedSeconds % 60
	return string.format("%02d:%05.2f", minutes, seconds)
end

-- Returns true if a unix timestamp falls on the same UTC calendar day as another.
function Format.Time_IsSameDay(a: number, b: number): boolean
	return os.date("!%Y-%m-%d", a) == os.date("!%Y-%m-%d", b)
end

-- Formats game session uptime (in seconds, e.g. from os.clock at server start) as verbose duration.
function Format.Time_UptimeVerbose(serverStartClock: number): string
	return Format.Number_DurationVerbose(os.clock() - serverStartClock)
end

-- Formats a cooldown remaining value, floored, with a "s" suffix or "Ready".
function Format.Time_CooldownLabel(remainingSeconds: number): string
	if remainingSeconds <= 0 then
		return "Ready"
	end
	return string.format("%.1fs", remainingSeconds)
end

-- Formats a DateTime object (Roblox's DateTime type) as ISO-8601 UTC.
function Format.Time_DateTimeToISO(dt: DateTime): string
	return dt:ToIsoDate()
end

-- Formats ticks-per-second (FPS-like) as a readable rate label: "60.0/s"
function Format.Time_RateLabel(countPerSecond: number, decimals: number?): string
	return Format.Number_Round(countPerSecond, decimals or 1) .. "/s"
end

-- Formats a respawn timer readout: "Respawning in 3..."
function Format.Time_RespawnCountdown(secondsLeft: number): string
	return string.format("Respawning in %d...", math.max(0, math.ceil(secondsLeft)))
end

------------------------------------------------------------------
-- SECTION 18: PLAYER / GAMEPLAY SPECIFIC
------------------------------------------------------------------

-- Formats a kill-feed line: "PlayerA eliminated PlayerB with Weapon".
function Format.Player_KillFeedLine(killer: string, victim: string, weapon: string?): string
	if weapon then
		return string.format("%s eliminated %s with %s", killer, victim, weapon)
	end
	return string.format("%s eliminated %s", killer, victim)
end

-- Formats a K/D ratio string given kills and deaths.
function Format.Player_KDString(kills: number, deaths: number, decimals: number?): string
	local ratio = deaths > 0 and (kills / deaths) or kills
	return string.format("%d/%d (%.2f)", kills, deaths, Format.Number_Round(ratio, decimals or 2))
end

-- Formats a level/XP readout: "Lvl 12 (1,540 / 2,000 XP)"
function Format.Player_LevelXPString(level: number, currentXP: number, requiredXP: number): string
	return string.format("Lvl %d (%s / %s XP)", level, Format.Number_Commas(currentXP), Format.Number_Commas(requiredXP))
end

-- Formats a ping value with a quality label: "45ms (Good)"
function Format.Player_PingLabel(pingMs: number): string
	local label
	if pingMs < 60 then label = "Excellent"
	elseif pingMs < 120 then label = "Good"
	elseif pingMs < 200 then label = "Fair"
	else label = "Poor" end
	return string.format("%dms (%s)", math.floor(pingMs), label)
end

-- Formats a currency/wallet balance for a HUD readout, using coin-style abbreviation.
function Format.Player_WalletLabel(amount: number): string
	return Format.Number_Abbreviate(amount, 1) .. " coins"
end

-- Formats a team-scoped display name: "[Red Team] PlayerName"
function Format.Player_TeamDisplayName(teamName: string, playerName: string): string
	return string.format("[%s] %s", teamName, playerName)
end

-- Formats a rank/placement string: "#3 of 24"
function Format.Player_PlacementString(rank: number, total: number): string
	return string.format("#%d of %d", rank, total)
end

-- Formats a streak counter with an on-fire suffix past a threshold: "5 Kill Streak 🔥" (text-only flame tag).
function Format.Player_StreakLabel(streak: number, hotThreshold: number?): string
	local threshold = hotThreshold or 5
	local base = Format.String_CountedNoun(streak, "Kill") .. " Streak"
	if streak >= threshold then
		return base .. " [ON FIRE]"
	end
	return base
end

return Format