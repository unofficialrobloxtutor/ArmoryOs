------------------------------------------------------------------------
--  <> Title:       RoExpress.Codec.LZ77
--  <> Version:     1.0
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: LZ77 sliding-window compression.
--
--  FORMAT
--  ────────────────────────────────────────────────────────────────
--  [0xC0][0xDE]  magic
--  [token stream...]
--    Literal token : [0x00][byte]
--    Match token   : [0x01][dist_hi][dist_lo][len]
--
--  Window : 4096 bytes (12-bit distance)
--  Min match : 4 bytes
--  Max match : 255 bytes (1-byte length field)
------------------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local Base64      = require(script.Parent.Parent.Base64)

local LZ77 = {}

local MAGIC_0       = 0xC0
local MAGIC_1       = 0xDE
local TOKEN_LITERAL = 0x00
local TOKEN_MATCH   = 0x01
local WINDOW_SIZE   = 4096
local MIN_MATCH     = 4
local MAX_MATCH     = 255

local function _findMatch(bytes: { number }, pos: number, windowStart: number): (number, number)
	local bestDist, bestLen = 0, 0
	local n = #bytes
	for i = pos - 1, windowStart, -1 do
		if bytes[i] ~= bytes[pos] then continue end
		local len = 0
		while len < MAX_MATCH and pos + len <= n and bytes[i + len] == bytes[pos + len] do
			len += 1
		end
		if len > bestLen then
			bestLen  = len
			bestDist = pos - i
			if bestLen == MAX_MATCH then break end
		end
	end
	if bestLen >= MIN_MATCH then return bestDist, bestLen end
	return 0, 0
end

local function _bytesToString(bytes: { number }): string
	local CHUNK = 4096
	local parts = table.create(math.ceil(#bytes / CHUNK))
	for i = 1, #bytes, CHUNK do
		parts[#parts + 1] = string.char(table.unpack(bytes, i, math.min(i + CHUNK - 1, #bytes)))
	end
	return table.concat(parts)
end

function LZ77.Compress(data: any): string
	local json  = HttpService:JSONEncode(data)
	local bytes = table.create(#json)
	for i = 1, #json do bytes[i] = string.byte(json, i) end

	local n   = #bytes
	local out = buffer.create(2 + n * 2)
	local p   = 0

	buffer.writeu8(out, p, MAGIC_0) p += 1
	buffer.writeu8(out, p, MAGIC_1) p += 1

	local pos = 1
	while pos <= n do
		local windowStart    = math.max(1, pos - WINDOW_SIZE)
		local dist, matchLen = _findMatch(bytes, pos, windowStart)
		if matchLen >= MIN_MATCH then
			buffer.writeu8(out, p, TOKEN_MATCH)              p += 1
			buffer.writeu8(out, p, math.floor(dist / 256))  p += 1
			buffer.writeu8(out, p, dist % 256)               p += 1
			buffer.writeu8(out, p, matchLen)                 p += 1
			pos += matchLen
		else
			buffer.writeu8(out, p, TOKEN_LITERAL) p += 1
			buffer.writeu8(out, p, bytes[pos])    p += 1
			pos += 1
		end
	end

	local result = buffer.create(p)
	buffer.copy(result, 0, out, 0, p)
	return Base64.Encode(buffer.tostring(result))
end

function LZ77.Decompress(encoded: string): any
	local raw = Base64.Decode(encoded)
	if not raw or #raw < 2 then
		warn("RoExpress.Codec.LZ77: data too short")
		return nil
	end

	local src = buffer.fromstring(raw)
	local len = buffer.len(src)

	if buffer.readu8(src, 0) ~= MAGIC_0 or buffer.readu8(src, 1) ~= MAGIC_1 then
		warn("RoExpress.Codec.LZ77: missing magic header")
		return nil
	end

	local outBytes = {}
	local pos      = 2

	while pos < len do
		local token = buffer.readu8(src, pos) ; pos += 1
		if token == TOKEN_LITERAL then
			if pos >= len then warn("RoExpress.Codec.LZ77: truncated literal") ; break end
			table.insert(outBytes, buffer.readu8(src, pos)) ; pos += 1
		elseif token == TOKEN_MATCH then
			if pos + 2 >= len then warn("RoExpress.Codec.LZ77: truncated match") ; break end
			local distHi = buffer.readu8(src, pos) ; pos += 1
			local distLo = buffer.readu8(src, pos) ; pos += 1
			local mlen   = buffer.readu8(src, pos) ; pos += 1
			local dist   = distHi * 256 + distLo
			local start  = #outBytes - dist + 1
			if start < 1 then warn("RoExpress.Codec.LZ77: invalid back-reference dist=" .. dist) ; break end
			for i = 0, mlen - 1 do
				table.insert(outBytes, outBytes[start + i])
			end
		else
			warn("RoExpress.Codec.LZ77: unknown token 0x" .. string.format("%02X", token))
			break
		end
	end

	local ok, result = pcall(HttpService.JSONDecode, HttpService, _bytesToString(outBytes))
	if not ok then
		warn("RoExpress.Codec.LZ77: JSON decode failed:", result)
		return nil
	end
	return result
end

return LZ77
