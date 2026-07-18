------------------------------------------------------------------------
--  <> Title:       RoExpress.Stream.Schema
--  <> Version:     2.5
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Schema compiler for Stream binary channels.
--
--  A schema is an ordered list of named fields, each bound to a type.
--  Field order determines wire order — both sides must define the same
--  fields in the same sequence.
--
--  USAGE
--  ────────────────────────────────────────────────────────────────
--  local schema = Schema.New({
--      { "pos",    "Vector3" },
--      { "health", "u8" },
--      { "state",  { "flags", "jumping", "crouching", "ads" } },
--      { "mat",    { "enum",  Enum.Material } },
--  })
--
--  schema:Pack({ pos = ..., health = 100, state = { jumping = true } })
--  schema:Unpack(buf)
------------------------------------------------------------------------
local Types = require(script.Parent.Types)

local Schema = {}
Schema.__index = Schema

type FieldDef = { name: string, typedef: Types.TypeDef }

export type Type = typeof(setmetatable({}, Schema)) & {
	_fields       : { FieldDef },
	_fixedSize    : number?,
	_fieldOffsets : { number }?,
}

------------------------------------------------------------------------
--  Constructor
------------------------------------------------------------------------
-- definition: ordered array of { fieldName, typeSpec }
-- typeSpec:   string  → plain type  (e.g. "Vector3")
--             table   → parameterized type  (e.g. { "flags", "a", "b" })
function Schema.New(definition: { { any } }): Type
	local fields    = {}
	local fixedSize = 0
	local isFixed   = true

	for idx, entry in ipairs(definition) do
		local name     = entry[1]
		local typeSpec = entry[2]
		assert(type(name) == "string" and #name > 0,
			"Schema.New: field at index " .. idx .. " must have a non-empty string name as entry[1]")

		local typedef: Types.TypeDef
		if type(typeSpec) == "string" then
			typedef = Types[typeSpec]
			assert(typedef, "Schema.New: unknown type '" .. typeSpec .. "' for field '" .. name .. "'")
			assert(not typedef.parameterized,
				"Schema.New: type '" .. typeSpec .. "' requires parameters — use { '" .. typeSpec .. "', ... } for field '" .. name .. "'")
		elseif type(typeSpec) == "table" then
			local typeName = typeSpec[1]
			local base     = Types[typeName]
			assert(base, "Schema.New: unknown type '" .. tostring(typeName) .. "' for field '" .. name .. "'")
			assert(base.parameterized and base.compile,
				"Schema.New: type '" .. typeName .. "' is not parameterizable for field '" .. name .. "'")
			local args = {}
			for i = 2, #typeSpec do args[i - 1] = typeSpec[i] end
			typedef = base.compile(args)
		else
			error("Schema.New: field '" .. name .. "' has invalid type spec (expected string or table)")
		end

		table.insert(fields, { name = name, typedef = typedef })

		if typedef.size == 0 then
			isFixed = false
		else
			fixedSize += typedef.size
		end
	end

	assert(#fields > 0, "Schema.New: definition must contain at least one field")

	local self            = setmetatable({}, Schema) :: Type
	self._fields          = fields
	self._fixedSize       = isFixed and fixedSize or nil
	self._fieldOffsets    = nil :: { number }?

	if isFixed then
		local offsets = {}
		local off = 0
		for i, field in ipairs(fields) do
			offsets[i] = off
			off += field.typedef.size
		end
		self._fieldOffsets = offsets
	end

	return self
end

------------------------------------------------------------------------
--  Pack
------------------------------------------------------------------------
function Schema:Pack(data: { [string]: any }): buffer
	local size = self._fixedSize
	if not size then
		size = 0
		for _, field in ipairs(self._fields) do
			if field.typedef.size == 0 then
				local v = data[field.name]
				size += 2 + (type(v) == "string" and #v or 0)
			else
				size += field.typedef.size
			end
		end
	end

	local buf = buffer.create(size)
	local pos = 0
	for _, field in ipairs(self._fields) do
		local value = data[field.name]
		assert(value ~= nil, "Schema.Pack: missing required field '" .. field.name .. "'")
		pos = field.typedef.write(buf, pos, value)
	end
	return buf
end

------------------------------------------------------------------------
--  Unpack
------------------------------------------------------------------------
function Schema:Unpack(buf: buffer): { [string]: any }
	local data = {}
	local pos  = 0
	for _, field in ipairs(self._fields) do
		local value, newPos = field.typedef.read(buf, pos)
		data[field.name] = value
		pos = newPos
	end
	return data
end

------------------------------------------------------------------------
--  Delta — fixed-size schemas only
------------------------------------------------------------------------

-- Compare two packed buffers field-by-field and emit only changed fields.
-- Wire format: [ bitmask: ceil(N/8) bytes ][ changed field values in field order ]
function Schema:PackDelta(oldBuf: buffer, newBuf: buffer): buffer
	assert(self._fixedSize and self._fieldOffsets,
		"Schema.PackDelta: requires a fixed-size schema (no string fields)")

	local fields      = self._fields
	local offsets     = self._fieldOffsets :: { number }
	local maskBytes   = math.ceil(#fields / 8)
	local changedSet  = {}
	local changedSize = 0

	for i, field in ipairs(fields) do
		local off  = offsets[i]
		local size = field.typedef.size
		local diff = false
		for b = 0, size - 1 do
			if buffer.readu8(oldBuf, off + b) ~= buffer.readu8(newBuf, off + b) then
				diff = true
				break
			end
		end
		if diff then
			changedSet[i] = true
			changedSize  += size
		end
	end

	local buf = buffer.create(maskBytes + changedSize)
	local pos = 0

	for byteIdx = 0, maskBytes - 1 do
		local byte = 0
		for bitIdx = 0, 7 do
			if changedSet[byteIdx * 8 + bitIdx + 1] then
				byte = bit32.bor(byte, bit32.lshift(1, bitIdx))
			end
		end
		buffer.writeu8(buf, pos, byte)
		pos += 1
	end

	for i, field in ipairs(fields) do
		if changedSet[i] then
			buffer.copy(buf, pos, newBuf, offsets[i], field.typedef.size)
			pos += field.typedef.size
		end
	end

	return buf
end

-- Apply a delta buffer produced by PackDelta on top of a full base buffer.
-- Returns a new full packed buffer.
function Schema:ApplyDelta(baseBuf: buffer, deltaBuf: buffer): buffer
	assert(self._fixedSize and self._fieldOffsets,
		"Schema.ApplyDelta: requires a fixed-size schema")

	local fields    = self._fields
	local offsets   = self._fieldOffsets :: { number }
	local maskBytes = math.ceil(#fields / 8)

	local result  = buffer.create(self._fixedSize)
	buffer.copy(result, 0, baseBuf, 0, self._fixedSize)

	local readPos = maskBytes
	for byteIdx = 0, maskBytes - 1 do
		local byte = buffer.readu8(deltaBuf, byteIdx)
		for bitIdx = 0, 7 do
			if bit32.band(byte, bit32.lshift(1, bitIdx)) ~= 0 then
				local fi = byteIdx * 8 + bitIdx + 1
				if fi <= #fields then
					local field = fields[fi]
					buffer.copy(result, offsets[fi], deltaBuf, readPos, field.typedef.size)
					readPos += field.typedef.size
				end
			end
		end
	end

	return result
end

return Schema
