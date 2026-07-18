------------------------------------------------------------------------
--  <> Title:       RoExpress.Base64
--  <> Version:     1.0
--  <> Date:        05/20/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Lightweight Base64 encoder/decoder for RoExpress
------------------------------------------------------------------------
local Base64 = {}

-->> Variables <<--
local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PADDING = "="

local _encodeMap = {}
local _decodeMap = {}

for i = 1, #CHARS do
	local c = CHARS:sub(i, i)
	_encodeMap[i - 1] = c
	_decodeMap[c] = i - 1
end
------------------------------------------------------------------------
--	FUNCTIONS
------------------------------------------------------------------------
function Base64.Encode(data: string): string
	local result = {}
	local padding = 0

	for i = 1, #data, 3 do
		local b1 = data:byte(i)
		local b2 = data:byte(i + 1)
		local b3 = data:byte(i + 2)

		local n = bit32.lshift(b1, 16)
			+ bit32.lshift(b2 or 0, 8)
			+ (b3 or 0)

		table.insert(result, _encodeMap[bit32.rshift(n, 18)])
		table.insert(result, _encodeMap[bit32.band(bit32.rshift(n, 12), 0x3F)])
		table.insert(result, b2 and _encodeMap[bit32.band(bit32.rshift(n, 6), 0x3F)] or PADDING)
		table.insert(result, b3 and _encodeMap[bit32.band(n, 0x3F)] or PADDING)

		if not b2 then padding = 2
		elseif not b3 then padding = 1
		end
	end

	return table.concat(result)
end

function Base64.Decode(data: string): string
	local result = {}
	local cleaned = data:gsub(PADDING, "")

	for i = 1, #cleaned, 4 do
		local c1 = _decodeMap[cleaned:sub(i, i)]
		local c2 = _decodeMap[cleaned:sub(i + 1, i + 1)]
		local c3 = _decodeMap[cleaned:sub(i + 2, i + 2)]
		local c4 = _decodeMap[cleaned:sub(i + 3, i + 3)]

		local n = bit32.lshift(c1, 18)
			+ bit32.lshift(c2, 12)
			+ bit32.lshift(c3 or 0, 6)
			+ (c4 or 0)

		table.insert(result, string.char(bit32.rshift(n, 16)))
		if c3 then table.insert(result, string.char(bit32.band(bit32.rshift(n, 8), 0xFF))) end
		if c4 then table.insert(result, string.char(bit32.band(n, 0xFF))) end
	end

	return table.concat(result)
end

-- Encode a table as JSON-like string then base64
function Base64.EncodeTable(data: any): string
	return Base64.Encode(game:GetService("HttpService"):JSONEncode(data))
end

-- Decode base64 then parse back to table
function Base64.DecodeTable(data: string): any
	return game:GetService("HttpService"):JSONDecode(Base64.Decode(data))
end

return Base64