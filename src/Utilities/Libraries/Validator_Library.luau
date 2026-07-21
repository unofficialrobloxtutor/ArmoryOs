--!strict
--!native
--!optimize 2
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Validator_Library
--  ◄► Version:     2.0
--  ◄► Date:        17/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A human-readable general-purpose validation module —
--                  type/range/pattern/table/Roblox-type predicates, plus
--                  Assert* variants that error with a config-path style
--                  message, and a generic schema validator that replaces
--                  hand-rolled per-config walkers.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
--► Tables       ◄--
local Module = {}
--► Variables    ◄--
--► Constants    ◄--
Module.Epsilon = 1e-6

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	CORE TYPE PREDICATES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a value's typeof() matches the expected type name
Module.IsType = function(value: any, expected: string): boolean
	return typeof(value) == expected
end

--► Returns true if a value is nil, OR matches the expected type name
Module.IsOptionalType = function(value: any, expected: string): boolean
	return value == nil or typeof(value) == expected
end

--► Returns true if a value's type matches any of a list of expected type names
Module.IsOneOfTypes = function(value: any, types: {string}): boolean
	local t = typeof(value)
	for _, expected in ipairs(types) do
		if t == expected then return true end
	end
	return false
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ASSERTIONS (throw on failure)
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Errors if a value's type doesn't match, naming the offending config path
Module.Assert = function(value: any, expected: string, path: string?)
	if typeof(value) ~= expected then
		error(`[Validator_Library] Expected type '{expected}' at '{path or "?"}', got '{typeof(value)}'`, 3)
	end
end

--► Errors if a present value's type doesn't match — nil is always allowed
Module.AssertOptional = function(value: any, expected: string, path: string?)
	if value ~= nil and typeof(value) ~= expected then
		error(`[Validator_Library] Expected type '{expected}?' at '{path or "?"}', got '{typeof(value)}'`, 3)
	end
end

--► Errors with a custom message if a condition is falsy — general-purpose guard clause
Module.AssertCondition = function(condition: boolean, message: string)
	if not condition then
		error(`[Validator_Library] {message}`, 3)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	NUMBERS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a value is a number
Module.IsNumber = function(value: any): boolean
	return typeof(value) == "number"
end

--► Returns true if a value is a whole-number integer
Module.IsInteger = function(value: any): boolean
	return typeof(value) == "number" and value % 1 == 0
end

--► Returns true if a number is finite (not NaN or +/- infinity)
Module.IsFinite = function(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

--► Returns true if a number is strictly greater than zero
Module.IsPositive = function(value: number): boolean
	return value > 0
end

--► Returns true if a number is zero or greater
Module.IsNonNegative = function(value: number): boolean
	return value >= 0
end

--► Returns true if a number falls within an inclusive min/max range
Module.InRange = function(value: number, min: number, max: number): boolean
	return value >= min and value <= max
end

--► Errors if a number falls outside an inclusive min/max range
Module.AssertInRange = function(value: number, min: number, max: number, path: string?)
	if value < min or value > max then
		error(`[Validator_Library] Expected value in range [{min}, {max}] at '{path or "?"}', got {value}`, 3)
	end
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	STRINGS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a value is a string
Module.IsString = function(value: any): boolean
	return typeof(value) == "string"
end

--► Returns true if a value is a string containing at least one non-whitespace character
Module.IsNonEmptyString = function(value: any): boolean
	return typeof(value) == "string" and value:match("%S") ~= nil
end

--► Returns true if a string matches a Lua pattern
Module.MatchesPattern = function(value: string, pattern: string): boolean
	return value:match(pattern) ~= nil
end

--► Returns true if a value is equal to any entry in a list of allowed values
Module.IsOneOf = function(value: any, allowed: {any}): boolean
	for _, entry in ipairs(allowed) do
		if value == entry then return true end
	end
	return false
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	TABLES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a value is a table
Module.IsTable = function(value: any): boolean
	return typeof(value) == "table"
end

--► Returns true if a table is a dense, 1-indexed array (no gaps, no non-integer keys)
Module.IsArray = function(value: any): boolean
	if typeof(value) ~= "table" then return false end
	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	for i = 1, count do
		if value[i] == nil then return false end
	end
	return true
end

--► Returns true if a table has no entries
Module.IsEmpty = function(value: {[any]: any}): boolean
	return next(value) == nil
end

--► Returns true if a table contains every key in a given list
Module.HasKeys = function(value: {[string]: any}, keys: {string}): boolean
	for _, key in ipairs(keys) do
		if value[key] == nil then return false end
	end
	return true
end

--► Returns true if a table contains no keys outside a given allow-list
Module.HasOnlyKeys = function(value: {[string]: any}, allowedKeys: {string}): boolean
	local allowed = {}
	for _, key in ipairs(allowedKeys) do
		allowed[key] = true
	end
	for key in pairs(value) do
		if not allowed[key] then return false end
	end
	return true
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	ROBLOX TYPES
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a value is a boolean
Module.IsBoolean = function(value: any): boolean
	return typeof(value) == "boolean"
end

--► Returns true if a value is a Vector3
Module.IsVector3 = function(value: any): boolean
	return typeof(value) == "Vector3"
end

--► Returns true if a value is a CFrame
Module.IsCFrame = function(value: any): boolean
	return typeof(value) == "CFrame"
end

--► Returns true if a value is a Color3
Module.IsColor3 = function(value: any): boolean
	return typeof(value) == "Color3"
end

--► Returns true if a value is a UDim2
Module.IsUDim2 = function(value: any): boolean
	return typeof(value) == "UDim2"
end

--► Returns true if a value is a Roblox Instance
Module.IsInstance = function(value: any): boolean
	return typeof(value) == "Instance"
end

--► Returns true if a value is an Instance of (or descending from) a given ClassName
Module.IsInstanceOfClass = function(value: any, className: string): boolean
	if typeof(value) ~= "Instance" then return false end
	return value:IsA(className)
end

--► Returns true if a value is a member of a given Enum
-- IsEnumMember(Enum.Material.Wood, Enum.Material) → true
Module.IsEnumMember = function(value: any, enumType: Enum): boolean
	if typeof(value) ~= "EnumItem" then return false end
	return value.EnumType == enumType
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	FUNCTIONS
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■

--► Returns true if a value is callable (a function)
Module.IsCallable = function(value: any): boolean
	return typeof(value) == "function"
end

--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--	SCHEMA VALIDATION
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--
--  A schema is a table mapping field names to either:
--    * a typeof() string,               e.g. "number"
--    * a typeof() string + "?" suffix,  e.g. "number?" (optional)
--    * a validator function (value) -> (boolean, string?)
--
--  Example:
--    local schema = {
--        Name       = "string",
--        BaseDamage = "number?",
--        Fov        = function(v) return Validator.InRange(v, 1, 120), "Fov must be 1-120" end,
--    }

--► Validates a table against a schema, returning true or false + a descriptive error string
Module.ValidateSchema = function(value: {[string]: any}, schema: {[string]: any}, path: string?): (boolean, string?)
	local base = path or "Root"

	if typeof(value) ~= "table" then
		return false, `Expected type 'table' at '{base}', got '{typeof(value)}'`
	end

	for field, rule in pairs(schema) do
		local fieldPath = `{base}.{field}`
		local fieldValue = value[field]

		if typeof(rule) == "string" then
			local optional = rule:sub(-1) == "?"
			local expected = optional and rule:sub(1, -2) or rule

			if fieldValue == nil then
				if not optional then
					return false, `Missing required field at '{fieldPath}' (expected '{expected}')`
				end
			elseif typeof(fieldValue) ~= expected then
				return false, `Expected type '{expected}' at '{fieldPath}', got '{typeof(fieldValue)}'`
			end
		elseif typeof(rule) == "function" then
			local ok, message = rule(fieldValue)
			if not ok then
				return false, message or `Validation failed at '{fieldPath}'`
			end
		end
	end

	return true, nil
end

--► Validates a table against a schema, erroring with the descriptive message on failure
Module.AssertSchema = function(value: {[string]: any}, schema: {[string]: any}, path: string?)
	local ok, message = Module.ValidateSchema(value, schema, path)
	if not ok then
		error(`[Validator_Library] {message}`, 3)
	end
end

return Module
