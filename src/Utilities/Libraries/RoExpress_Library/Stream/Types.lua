------------------------------------------------------------------------
--  <> Title:       RoExpress.Stream.Types
--  <> Version:     2.5
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Binary type registry for Stream schemas.
--
--  BUILT-IN TYPES
--  ────────────────────────────────────────────────────────────────
--  Primitives:
--    u8  u16  u32  i8  i16  i32  f32  f64  bool  string
--
--  Roblox types:
--    Vector2       Vector3       Vector2int16  Vector3int16
--    CFrame        CFrameLight   (position + Y-yaw only, 16B)
--    Color3        Color3float   (HDR/exact f32)
--    BrickColor    UDim          UDim2
--    Rect          NumberRange   Ray
--    Region3       PhysicalProperties
--
--  Parameterized types (use as table in schema):
--    { "flags", "fieldA", "fieldB", ... }  — up to 8 booleans in 1 byte
--    { "enum",  Enum.Material }            — EnumItem encoded as u16
--
--  EXTENSION
--  ────────────────────────────────────────────────────────────────
--  Types.Register(name, typedef) — add custom types at runtime
------------------------------------------------------------------------

export type TypeDef = {
	size          : number,
	write         : (buf: buffer, pos: number, value: any) -> number,
	read          : (buf: buffer, pos: number) -> (any, number),
	parameterized : boolean?,
	compile       : ((args: { any }) -> TypeDef)?,
}

local Types: { [string]: TypeDef } = {}

------------------------------------------------------------------------
--  Primitives
------------------------------------------------------------------------
Types.u8 = {
	size  = 1,
	write = function(buf, pos, v) buffer.writeu8(buf, pos, v)  return pos + 1 end,
	read  = function(buf, pos)    return buffer.readu8(buf, pos),  pos + 1    end,
}
Types.u16 = {
	size  = 2,
	write = function(buf, pos, v) buffer.writeu16(buf, pos, v) return pos + 2 end,
	read  = function(buf, pos)    return buffer.readu16(buf, pos), pos + 2    end,
}
Types.u32 = {
	size  = 4,
	write = function(buf, pos, v) buffer.writeu32(buf, pos, v) return pos + 4 end,
	read  = function(buf, pos)    return buffer.readu32(buf, pos), pos + 4    end,
}
Types.i8 = {
	size  = 1,
	write = function(buf, pos, v) buffer.writei8(buf, pos, v)  return pos + 1 end,
	read  = function(buf, pos)    return buffer.readi8(buf, pos),  pos + 1    end,
}
Types.i16 = {
	size  = 2,
	write = function(buf, pos, v) buffer.writei16(buf, pos, v) return pos + 2 end,
	read  = function(buf, pos)    return buffer.readi16(buf, pos), pos + 2    end,
}
Types.i32 = {
	size  = 4,
	write = function(buf, pos, v) buffer.writei32(buf, pos, v) return pos + 4 end,
	read  = function(buf, pos)    return buffer.readi32(buf, pos), pos + 4    end,
}
Types.f32 = {
	size  = 4,
	write = function(buf, pos, v) buffer.writef32(buf, pos, v) return pos + 4 end,
	read  = function(buf, pos)    return buffer.readf32(buf, pos), pos + 4    end,
}
Types.f64 = {
	size  = 8,
	write = function(buf, pos, v) buffer.writef64(buf, pos, v) return pos + 8 end,
	read  = function(buf, pos)    return buffer.readf64(buf, pos), pos + 8    end,
}
Types.bool = {
	size  = 1,
	write = function(buf, pos, v) buffer.writeu8(buf, pos, v and 1 or 0) return pos + 1   end,
	read  = function(buf, pos)    return buffer.readu8(buf, pos) == 1,    pos + 1          end,
}

-- Variable-length UTF-8 string. Wire format: u16 length prefix + raw bytes.
Types.string = {
	size  = 0,
	write = function(buf, pos, v: string)
		local len = #v
		buffer.writeu16(buf, pos, len)
		buffer.writestring(buf, pos + 2, v, len)
		return pos + 2 + len
	end,
	read = function(buf, pos)
		local len = buffer.readu16(buf, pos)
		return buffer.readstring(buf, pos + 2, len), pos + 2 + len
	end,
}

------------------------------------------------------------------------
--  Vector types
------------------------------------------------------------------------
Types.Vector2 = {
	size  = 8,
	write = function(buf, pos, v: Vector2)
		buffer.writef32(buf, pos,     v.X)
		buffer.writef32(buf, pos + 4, v.Y)
		return pos + 8
	end,
	read = function(buf, pos)
		return Vector2.new(buffer.readf32(buf, pos), buffer.readf32(buf, pos + 4)), pos + 8
	end,
}

Types.Vector3 = {
	size  = 12,
	write = function(buf, pos, v: Vector3)
		buffer.writef32(buf, pos,     v.X)
		buffer.writef32(buf, pos + 4, v.Y)
		buffer.writef32(buf, pos + 8, v.Z)
		return pos + 12
	end,
	read = function(buf, pos)
		return Vector3.new(
			buffer.readf32(buf, pos),
			buffer.readf32(buf, pos + 4),
			buffer.readf32(buf, pos + 8)
		), pos + 12
	end,
}

Types.Vector2int16 = {
	size  = 4,
	write = function(buf, pos, v: Vector2int16)
		buffer.writei16(buf, pos,     v.X)
		buffer.writei16(buf, pos + 2, v.Y)
		return pos + 4
	end,
	read = function(buf, pos)
		return Vector2int16.new(buffer.readi16(buf, pos), buffer.readi16(buf, pos + 2)), pos + 4
	end,
}

Types.Vector3int16 = {
	size  = 6,
	write = function(buf, pos, v: Vector3int16)
		buffer.writei16(buf, pos,     v.X)
		buffer.writei16(buf, pos + 2, v.Y)
		buffer.writei16(buf, pos + 4, v.Z)
		return pos + 6
	end,
	read = function(buf, pos)
		return Vector3int16.new(
			buffer.readi16(buf, pos),
			buffer.readi16(buf, pos + 2),
			buffer.readi16(buf, pos + 4)
		), pos + 6
	end,
}

------------------------------------------------------------------------
--  CFrame types
------------------------------------------------------------------------

-- CFrame (28 bytes) — position + full quaternion. Lossless rotation.
-- Wire format: px py pz qx qy qz qw (7 × f32)
Types.CFrame = {
	size  = 28,
	write = function(buf, pos, v: CFrame)
		local p = v.Position
		buffer.writef32(buf, pos,     p.X)
		buffer.writef32(buf, pos + 4, p.Y)
		buffer.writef32(buf, pos + 8, p.Z)
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
		local trace = r00 + r11 + r22
		local qw, qx, qy, qz
		if trace > 0 then
			local s = 0.5 / math.sqrt(trace + 1)
			qw = 0.25 / s
			qx = (r21 - r12) * s
			qy = (r02 - r20) * s
			qz = (r10 - r01) * s
		elseif r00 > r11 and r00 > r22 then
			local s = 2 * math.sqrt(1 + r00 - r11 - r22)
			qw = (r21 - r12) / s
			qx = 0.25 * s
			qy = (r01 + r10) / s
			qz = (r02 + r20) / s
		elseif r11 > r22 then
			local s = 2 * math.sqrt(1 + r11 - r00 - r22)
			qw = (r02 - r20) / s
			qx = (r01 + r10) / s
			qy = 0.25 * s
			qz = (r12 + r21) / s
		else
			local s = 2 * math.sqrt(1 + r22 - r00 - r11)
			qw = (r10 - r01) / s
			qx = (r02 + r20) / s
			qy = (r12 + r21) / s
			qz = 0.25 * s
		end
		buffer.writef32(buf, pos + 12, qx)
		buffer.writef32(buf, pos + 16, qy)
		buffer.writef32(buf, pos + 20, qz)
		buffer.writef32(buf, pos + 24, qw)
		return pos + 28
	end,
	read = function(buf, pos)
		local x  = buffer.readf32(buf, pos)
		local y  = buffer.readf32(buf, pos + 4)
		local z  = buffer.readf32(buf, pos + 8)
		local qx = buffer.readf32(buf, pos + 12)
		local qy = buffer.readf32(buf, pos + 16)
		local qz = buffer.readf32(buf, pos + 20)
		local qw = buffer.readf32(buf, pos + 24)
		return CFrame.new(x, y, z, qx, qy, qz, qw), pos + 28
	end,
}

-- CFrameLight (16 bytes) — position + Y-axis yaw only.
-- Encodes characters/vehicles that only rotate horizontally. Half the size of CFrame.
-- Wire format: px py pz yaw (4 × f32)
Types.CFrameLight = {
	size  = 16,
	write = function(buf, pos, v: CFrame)
		local p   = v.Position
		local lv  = v.LookVector
		local yaw = math.atan2(-lv.X, -lv.Z)
		buffer.writef32(buf, pos,      p.X)
		buffer.writef32(buf, pos + 4,  p.Y)
		buffer.writef32(buf, pos + 8,  p.Z)
		buffer.writef32(buf, pos + 12, yaw)
		return pos + 16
	end,
	read = function(buf, pos)
		local x   = buffer.readf32(buf, pos)
		local y   = buffer.readf32(buf, pos + 4)
		local z   = buffer.readf32(buf, pos + 8)
		local yaw = buffer.readf32(buf, pos + 12)
		return CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), pos + 16
	end,
}

------------------------------------------------------------------------
--  Color types
------------------------------------------------------------------------

-- Color3 (3 bytes) — u8 RGB, 0-255 per channel. Lossy but compact.
Types.Color3 = {
	size  = 3,
	write = function(buf, pos, v: Color3)
		buffer.writeu8(buf, pos,     math.clamp(math.round(v.R * 255), 0, 255))
		buffer.writeu8(buf, pos + 1, math.clamp(math.round(v.G * 255), 0, 255))
		buffer.writeu8(buf, pos + 2, math.clamp(math.round(v.B * 255), 0, 255))
		return pos + 3
	end,
	read = function(buf, pos)
		return Color3.fromRGB(
			buffer.readu8(buf, pos),
			buffer.readu8(buf, pos + 1),
			buffer.readu8(buf, pos + 2)
		), pos + 3
	end,
}

-- Color3float (12 bytes) — full f32 precision. Use for HDR lighting values.
Types.Color3float = {
	size  = 12,
	write = function(buf, pos, v: Color3)
		buffer.writef32(buf, pos,     v.R)
		buffer.writef32(buf, pos + 4, v.G)
		buffer.writef32(buf, pos + 8, v.B)
		return pos + 12
	end,
	read = function(buf, pos)
		return Color3.new(
			buffer.readf32(buf, pos),
			buffer.readf32(buf, pos + 4),
			buffer.readf32(buf, pos + 8)
		), pos + 12
	end,
}

-- BrickColor (2 bytes) — encoded as BrickColor.Number (u16).
Types.BrickColor = {
	size  = 2,
	write = function(buf, pos, v: BrickColor)
		buffer.writeu16(buf, pos, v.Number)
		return pos + 2
	end,
	read = function(buf, pos)
		return BrickColor.new(buffer.readu16(buf, pos)), pos + 2
	end,
}

------------------------------------------------------------------------
--  UI / geometry types
------------------------------------------------------------------------

-- UDim (8 bytes) — f32 Scale + i32 Offset.
Types.UDim = {
	size  = 8,
	write = function(buf, pos, v: UDim)
		buffer.writef32(buf, pos,     v.Scale)
		buffer.writei32(buf, pos + 4, v.Offset)
		return pos + 8
	end,
	read = function(buf, pos)
		return UDim.new(buffer.readf32(buf, pos), buffer.readi32(buf, pos + 4)), pos + 8
	end,
}

-- UDim2 (16 bytes) — 2 × UDim.
Types.UDim2 = {
	size  = 16,
	write = function(buf, pos, v: UDim2)
		buffer.writef32(buf, pos,      v.X.Scale)
		buffer.writei32(buf, pos + 4,  v.X.Offset)
		buffer.writef32(buf, pos + 8,  v.Y.Scale)
		buffer.writei32(buf, pos + 12, v.Y.Offset)
		return pos + 16
	end,
	read = function(buf, pos)
		return UDim2.new(
			buffer.readf32(buf, pos),
			buffer.readi32(buf, pos + 4),
			buffer.readf32(buf, pos + 8),
			buffer.readi32(buf, pos + 12)
		), pos + 16
	end,
}

-- Rect (16 bytes) — min/max Vector2.
Types.Rect = {
	size  = 16,
	write = function(buf, pos, v: Rect)
		buffer.writef32(buf, pos,      v.Min.X)
		buffer.writef32(buf, pos + 4,  v.Min.Y)
		buffer.writef32(buf, pos + 8,  v.Max.X)
		buffer.writef32(buf, pos + 12, v.Max.Y)
		return pos + 16
	end,
	read = function(buf, pos)
		return Rect.new(
			buffer.readf32(buf, pos),      buffer.readf32(buf, pos + 4),
			buffer.readf32(buf, pos + 8),  buffer.readf32(buf, pos + 12)
		), pos + 16
	end,
}

-- NumberRange (8 bytes) — min/max as f32.
Types.NumberRange = {
	size  = 8,
	write = function(buf, pos, v: NumberRange)
		buffer.writef32(buf, pos,     v.Min)
		buffer.writef32(buf, pos + 4, v.Max)
		return pos + 8
	end,
	read = function(buf, pos)
		return NumberRange.new(buffer.readf32(buf, pos), buffer.readf32(buf, pos + 4)), pos + 8
	end,
}

-- Ray (24 bytes) — origin + direction as Vector3.
Types.Ray = {
	size  = 24,
	write = function(buf, pos, v: Ray)
		buffer.writef32(buf, pos,      v.Origin.X)
		buffer.writef32(buf, pos + 4,  v.Origin.Y)
		buffer.writef32(buf, pos + 8,  v.Origin.Z)
		buffer.writef32(buf, pos + 12, v.Direction.X)
		buffer.writef32(buf, pos + 16, v.Direction.Y)
		buffer.writef32(buf, pos + 20, v.Direction.Z)
		return pos + 24
	end,
	read = function(buf, pos)
		return Ray.new(
			Vector3.new(buffer.readf32(buf, pos),      buffer.readf32(buf, pos + 4),  buffer.readf32(buf, pos + 8)),
			Vector3.new(buffer.readf32(buf, pos + 12), buffer.readf32(buf, pos + 16), buffer.readf32(buf, pos + 20))
		), pos + 24
	end,
}

-- Region3 (24 bytes) — min/max corners as Vector3.
Types.Region3 = {
	size  = 24,
	write = function(buf, pos, v: Region3)
		local half = v.Size * 0.5
		local mn   = v.CFrame.Position - half
		local mx   = v.CFrame.Position + half
		buffer.writef32(buf, pos,      mn.X)
		buffer.writef32(buf, pos + 4,  mn.Y)
		buffer.writef32(buf, pos + 8,  mn.Z)
		buffer.writef32(buf, pos + 12, mx.X)
		buffer.writef32(buf, pos + 16, mx.Y)
		buffer.writef32(buf, pos + 20, mx.Z)
		return pos + 24
	end,
	read = function(buf, pos)
		return Region3.new(
			Vector3.new(buffer.readf32(buf, pos),      buffer.readf32(buf, pos + 4),  buffer.readf32(buf, pos + 8)),
			Vector3.new(buffer.readf32(buf, pos + 12), buffer.readf32(buf, pos + 16), buffer.readf32(buf, pos + 20))
		), pos + 24
	end,
}

-- PhysicalProperties (20 bytes) — 5 × f32.
Types.PhysicalProperties = {
	size  = 20,
	write = function(buf, pos, v: PhysicalProperties)
		buffer.writef32(buf, pos,      v.Density)
		buffer.writef32(buf, pos + 4,  v.Friction)
		buffer.writef32(buf, pos + 8,  v.Elasticity)
		buffer.writef32(buf, pos + 12, v.FrictionWeight)
		buffer.writef32(buf, pos + 16, v.ElasticityWeight)
		return pos + 20
	end,
	read = function(buf, pos)
		return PhysicalProperties.new(
			buffer.readf32(buf, pos),
			buffer.readf32(buf, pos + 4),
			buffer.readf32(buf, pos + 8),
			buffer.readf32(buf, pos + 12),
			buffer.readf32(buf, pos + 16)
		), pos + 20
	end,
}

------------------------------------------------------------------------
--  Parameterized types
------------------------------------------------------------------------

-- flags — packs up to 8 named booleans into one u8.
-- Decodes back to a table keyed by the provided field names.
--
-- Schema usage:
--   { "myField", { "flags", "jumping", "crouching", "ads", "sprinting" } }
Types.flags = {
	parameterized = true,
	compile = function(args: { string }): TypeDef
		assert(#args <= 8, "Stream.Types.flags: max 8 flags per field (got " .. #args .. ")")
		return {
			size  = 1,
			write = function(buf, pos, v)
				local byte = 0
				for i, name in ipairs(args) do
					if v[name] then byte = bit32.bor(byte, bit32.lshift(1, i - 1)) end
				end
				buffer.writeu8(buf, pos, byte)
				return pos + 1
			end,
			read = function(buf, pos)
				local byte   = buffer.readu8(buf, pos)
				local result = {}
				for i, name in ipairs(args) do
					result[name] = bit32.band(byte, bit32.lshift(1, i - 1)) ~= 0
				end
				return result, pos + 1
			end,
		}
	end,
}

-- enum — encodes a Roblox EnumItem as its u16 Value.
--
-- Schema usage:
--   { "material", { "enum", Enum.Material } }
Types.enum = {
	parameterized = true,
	compile = function(args: { any }): TypeDef
		local enumType = args[1]
		assert(enumType, "Stream.Types.enum: missing enum type argument")
		return {
			size  = 2,
			write = function(buf, pos, v)
				buffer.writeu16(buf, pos, v.Value)
				return pos + 2
			end,
			read = function(buf, pos)
				local val = buffer.readu16(buf, pos)
				for _, item in ipairs(enumType:GetEnumItems()) do
					if item.Value == val then return item, pos + 2 end
				end
				warn("Stream.Types.enum: no item with value", val, "in", tostring(enumType))
				return nil, pos + 2
			end,
		}
	end,
}

------------------------------------------------------------------------
--  Extension point
------------------------------------------------------------------------
function Types.Register(name: string, typedef: TypeDef)
	assert(not Types[name], "Stream.Types.Register: type '" .. name .. "' is already registered")
	Types[name] = typedef
end

return Types
