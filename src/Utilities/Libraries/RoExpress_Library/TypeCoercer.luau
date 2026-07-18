------------------------------------------------------------------------
--  <> Title:       RoExpress.TypeCoercer
--  <> Version:     1.0
--  <> Date:        30/05/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Shared type coercion and serialisation utility.
--
--  Provides ToString and FromString for all RoExpress route param
--  types. Used internally by Router and exposed as a singleton for
--  developers who need to manually coerce or serialise values.
--
--  SUPPORTED TYPES
--  ---------------------------------------------------------------
--  string   boolean  number   int
--  vector2  vector3  color3   cframe
--  Enum     Instance
--
--  USAGE
--  ---------------------------------------------------------------
--  local tc = RoExpress("TypeCoercer")
--
--  tc.ToString(Vector3.new(1,2,3))          -- "1,2,3"
--  tc.ToString(Color3.fromRGB(255,0,128))   -- "255,0,128"
--  tc.ToString(Enum.HumanoidStateType.Running) -- "Enum.HumanoidStateType.Running"
--  tc.ToString(workspace.Baseplate)         -- "Part:Baseplate"
--
--  tc.FromString("1,2,3",  "vector3")       -- Vector3.new(1,2,3)
--  tc.FromString("true",   "boolean")       -- true
--  tc.FromString("42",     "int")           -- 42
--  tc.FromString("Running","Enum.HumanoidStateType") -- Enum value
--
--  INSTANCE SEARCH ROOT
--  ---------------------------------------------------------------
--  Instance coercion searches a registered root. Register one with:
--    tc.RegisterInstanceRoot("Workspace", workspace)
--    tc.RegisterInstanceRoot("Players",   Players)
--  Multiple roots can be registered. Search order = registration order.
------------------------------------------------------------------------

local TypeCoercer = {}

------------------------------------------------------------------------
--  INSTANCE ROOTS
------------------------------------------------------------------------
TypeCoercer._instanceRoots = {}  -- { name: string, root: Instance }

--[[
    RegisterInstanceRoot(name, root)
    Register a search root for Instance coercion.
    Multiple roots searched in registration order.

    tc.RegisterInstanceRoot("Workspace", workspace)
    tc.RegisterInstanceRoot("Players",   game:GetService("Players"))
]]
function TypeCoercer.RegisterInstanceRoot(name: string, root: Instance)
    assert(type(name) == "string",   "TypeCoercer.RegisterInstanceRoot: name must be a string")
    assert(typeof(root) == "Instance", "TypeCoercer.RegisterInstanceRoot: root must be an Instance")
    table.insert(TypeCoercer._instanceRoots, { name = name, root = root })
end

------------------------------------------------------------------------
--  PRIVATE HELPERS
------------------------------------------------------------------------
local function _round(n: number, decimals: number?): string
    local d = decimals or 4
    local fmt = "%." .. d .. "g"
    return string.format(fmt, n)
end

local function _findInstance(className: string, instanceName: string): Instance?
    for _, entry in ipairs(TypeCoercer._instanceRoots) do
        local found = entry.root:FindFirstChild(instanceName, true)
        if found and found.ClassName == className then
            return found
        end
    end
    return nil
end

local function _parseEnum(raw: string): (boolean, any)
    -- format: "Enum.TypeName.ValueName" or just "ValueName" or numeric
    local enumType, valueName = raw:match("^Enum%.([^%.]+)%.(.+)$")
    if enumType and valueName then
        local ok, et = pcall(function()
            return (Enum :: any)[enumType]
        end)
        if ok and et then
            local ok2, val = pcall(function()
                return et[valueName]
            end)
            if ok2 and val then return true, val end
        end
        return false, nil
    end
    -- just the value name — requires type hint from router
    return false, nil
end

------------------------------------------------------------------------
--  COERCERS  (raw string -> Lua value)
------------------------------------------------------------------------
local _coercers: { [string]: (raw: string) -> (boolean, any) } = {

    string = function(raw)
        return true, raw
    end,

    boolean = function(raw)
        local lo = raw:lower()
        if lo == "true"  or lo == "1" then return true, true  end
        if lo == "false" or lo == "0" then return true, false end
        return false, nil
    end,

    number = function(raw)
        local n = tonumber(raw)
        if n then return true, n end
        return false, nil
    end,

    -- int: whole numbers only, rejects decimals
    int = function(raw)
        local n = tonumber(raw)
        if n and math.floor(n) == n then return true, math.floor(n) end
        return false, nil
    end,

    -- vector2: "x,y"
    vector2 = function(raw)
        local x, y = raw:match("^([^,]+),([^,]+)$")
        local nx, ny = tonumber(x), tonumber(y)
        if nx and ny then return true, Vector2.new(nx, ny) end
        return false, nil
    end,

    -- vector3: "x,y,z"
    vector3 = function(raw)
        local x, y, z = raw:match("^([^,]+),([^,]+),([^,]+)$")
        local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
        if nx and ny and nz then return true, Vector3.new(nx, ny, nz) end
        return false, nil
    end,

    -- color3: "r,g,b" — auto-detects 0-255 vs 0-1
    color3 = function(raw)
        local r, g, b = raw:match("^([^,]+),([^,]+),([^,]+)$")
        local nr, ng, nb = tonumber(r), tonumber(g), tonumber(b)
        if not (nr and ng and nb) then return false, nil end
        if nr > 1 or ng > 1 or nb > 1 then
            return true, Color3.fromRGB(
                math.clamp(nr, 0, 255),
                math.clamp(ng, 0, 255),
                math.clamp(nb, 0, 255)
            )
        end
        return true, Color3.new(
            math.clamp(nr, 0, 1),
            math.clamp(ng, 0, 1),
            math.clamp(nb, 0, 1)
        )
    end,

    -- cframe: "x,y,z,rx,ry,rz" (euler degrees) or "x,y,z" (position only)
    cframe = function(raw)
        local parts = {}
        for v in raw:gmatch("[^,]+") do
            table.insert(parts, tonumber(v))
        end
        if #parts == 3 then
            -- position only
            return true, CFrame.new(parts[1], parts[2], parts[3])
        end
        if #parts == 6 then
            -- position + euler angles in degrees
            return true, CFrame.new(parts[1], parts[2], parts[3])
                * CFrame.Angles(
                    math.rad(parts[4]),
                    math.rad(parts[5]),
                    math.rad(parts[6])
                )
        end
        return false, nil
    end,
}

-- Enum coercer factory — creates a coercer for a specific Enum type
local function _makeEnumCoercer(enumTypeName: string)
    return function(raw: string): (boolean, any)
        local ok, et = pcall(function()
            return (Enum :: any)[enumTypeName]
        end)
        if not ok or not et then return false, nil end

        -- strip "Enum.TypeName." prefix produced by tostring(EnumItem)
        local name = raw:match("^Enum%.[^%.]+%.(.+)$") or raw

        -- try by name first
        local ok2, val = pcall(function() return et[name] end)
        if ok2 and val then return true, val end

        -- try by numeric value
        local n = tonumber(raw)
        if n then
            for _, v in ipairs(et:GetEnumItems()) do
                if v.Value == n then return true, v end
            end
        end
        return false, nil
    end
end

-- Instance coercer — "ClassName:Name"
local function _instanceCoercer(raw: string): (boolean, any)
    local className, instanceName = raw:match("^([^:]+):(.+)$")
    if not className or not instanceName then return false, nil end
    local found = _findInstance(className, instanceName)
    if found then return true, found end
    return false, nil
end

------------------------------------------------------------------------
--  SERIALISERS  (Lua value -> wire string)
------------------------------------------------------------------------
local function _toStringValue(value: any): (boolean, string)
    local t = typeof(value)

    if t == "string"  then return true, value end
    if t == "boolean" then return true, tostring(value) end
    if t == "number"  then
        -- preserve int representation for cleanliness
        if math.floor(value) == value then
            return true, tostring(math.floor(value))
        end
        return true, _round(value)
    end

    if t == "Vector2" then
        return true, _round(value.X) .. "," .. _round(value.Y)
    end

    if t == "Vector3" then
        return true, _round(value.X) .. "," .. _round(value.Y) .. "," .. _round(value.Z)
    end

    if t == "Color3" then
        -- always serialise as 0-255 integers for readability
        return true, string.format("%d,%d,%d",
            math.round(value.R * 255),
            math.round(value.G * 255),
            math.round(value.B * 255)
        )
    end

    if t == "CFrame" then
        -- serialise as position + euler angles in degrees
        local p = value.Position
        local rx, ry, rz = value:ToEulerAnglesXYZ()
        return true, string.format("%s,%s,%s,%s,%s,%s",
            _round(p.X), _round(p.Y), _round(p.Z),
            _round(math.deg(rx)), _round(math.deg(ry)), _round(math.deg(rz))
        )
    end

    if t == "EnumItem" then
        return true, "Enum." .. tostring(value.EnumType) .. "." .. value.Name
    end

    if t == "Instance" then
        return true, value.ClassName .. ":" .. value.Name
    end

    return false, ""
end

------------------------------------------------------------------------
--  PUBLIC API
------------------------------------------------------------------------

--[[
    ToString(value) -> string

    Converts any supported RoExpress type to its wire string.
    Useful for building route URLs with typed params.

    tc.ToString(Vector3.new(10, 5, -20))      -- "10,5,-20"
    tc.ToString(Color3.fromRGB(255, 0, 128))  -- "255,0,128"
    tc.ToString(Enum.Material.Grass)          -- "Enum.Material.Grass"
    tc.ToString(workspace.Baseplate)          -- "Part:Baseplate"
]]
function TypeCoercer.ToString(value: any): string
    local ok, result = _toStringValue(value)
    if ok then return result end
    warn("TypeCoercer.ToString: unsupported type '" .. typeof(value) .. "'")
    return tostring(value)
end

--[[
    FromString(raw, typeName) -> (boolean, value)

    Converts a wire string to a Lua value of the given type.
    Returns (true, value) on success, (false, nil) on failure.

    tc.FromString("10,5,-20", "vector3")           -- true, Vector3
    tc.FromString("Running", "Enum.HumanoidStateType") -- true, EnumItem
    tc.FromString("Part:Baseplate", "Instance")    -- true, Instance
]]
function TypeCoercer.FromString(raw: string, typeName: string): (boolean, any)
    -- bare Enum — accept any EnumItem, wire format must be "Enum.TypeName.ValueName"
    if typeName == "Enum" then
        return _parseEnum(raw)
    end

    -- handle Enum.TypeName syntax
    if typeName:sub(1, 5) == "Enum." then
        local enumTypeName = typeName:sub(6)
        return _makeEnumCoercer(enumTypeName)(raw)
    end

    -- handle Instance
    if typeName == "Instance" then
        return _instanceCoercer(raw)
    end

    local coercer = _coercers[typeName]
    if not coercer then
        warn("TypeCoercer.FromString: unknown type '" .. typeName .. "'")
        return false, nil
    end
    return coercer(raw)
end

--[[
    Supports(typeName) -> boolean
    Returns true if the type name is recognised.
]]
function TypeCoercer.Supports(typeName: string): boolean
    if typeName          == "Enum"       then return true end
    if typeName:sub(1, 5) == "Enum."     then return true end
    if typeName          == "Instance"   then return true end
    return _coercers[typeName] ~= nil
end

-- expose coercers for Router internal use
TypeCoercer._coercers            = _coercers
TypeCoercer._makeEnumCoercer     = _makeEnumCoercer
TypeCoercer._instanceCoercer     = _instanceCoercer

return TypeCoercer
