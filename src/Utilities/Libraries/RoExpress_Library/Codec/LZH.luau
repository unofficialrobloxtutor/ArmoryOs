------------------------------------------------------------------------
--  <> Title:       RoExpress.Codec.LZH
--  <> Version:     1.0
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: LZH compression — LZ77 sliding window + Huffman coding.
--
--  PIPELINE
--  ────────────────────────────────────────────────────────────────
--  Compress:   JSON → bytes → LZ77 tokens → Huffman → Base64
--  Decompress: Base64 → Huffman → LZ77 bytes → JSON
--
--  FORMAT
--  ────────────────────────────────────────────────────────────────
--  [0xC0][0xDF]   magic (2 bytes)
--  [257 × u8]     canonical Huffman code lengths, symbols 0–256
--                 (symbol 256 = EOF, 0 = unused)
--  [u32 LE]       total bit count in the Huffman stream
--  [bit stream]   Huffman-encoded LZ77 byte stream, MSB-first,
--                 padded to byte boundary
------------------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local Base64      = require(script.Parent.Parent.Base64)

local LZH = {}

local MAGIC_0 = 0xC0
local MAGIC_1 = 0xDF
local EOF_SYM = 256

------------------------------------------------------------------------
--  LZ77 (raw — no JSON/Base64 wrapper)
------------------------------------------------------------------------
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

local function _lz77Compress(bytes: { number }): { number }
	local n   = #bytes
	local out = {}
	local pos = 1
	while pos <= n do
		local windowStart    = math.max(1, pos - WINDOW_SIZE)
		local dist, matchLen = _findMatch(bytes, pos, windowStart)
		if matchLen >= MIN_MATCH then
			table.insert(out, TOKEN_MATCH)
			table.insert(out, math.floor(dist / 256))
			table.insert(out, dist % 256)
			table.insert(out, matchLen)
			pos += matchLen
		else
			table.insert(out, TOKEN_LITERAL)
			table.insert(out, bytes[pos])
			pos += 1
		end
	end
	return out
end

local function _lz77Decompress(tokenBytes: { number }): { number }?
	local outBytes = {}
	local pos      = 1
	local n        = #tokenBytes
	while pos <= n do
		local token = tokenBytes[pos] ; pos += 1
		if token == TOKEN_LITERAL then
			table.insert(outBytes, tokenBytes[pos]) ; pos += 1
		elseif token == TOKEN_MATCH then
			local distHi = tokenBytes[pos] ; pos += 1
			local distLo = tokenBytes[pos] ; pos += 1
			local mlen   = tokenBytes[pos] ; pos += 1
			local dist   = distHi * 256 + distLo
			local start  = #outBytes - dist + 1
			if start < 1 then
				warn("RoExpress.Codec.LZH: invalid back-reference dist=" .. dist)
				return nil
			end
			for i = 0, mlen - 1 do
				table.insert(outBytes, outBytes[start + i])
			end
		else
			warn("RoExpress.Codec.LZH: unknown LZ77 token 0x" .. string.format("%02X", token))
			return nil
		end
	end
	return outBytes
end

------------------------------------------------------------------------
--  Huffman
------------------------------------------------------------------------

local function _buildLengths(bytes: { number }): { [number]: number }
	local freq: { [number]: number } = {}
	for i = 0, EOF_SYM do freq[i] = 0 end
	for _, b in ipairs(bytes) do freq[b] += 1 end
	freq[EOF_SYM] = 1

	local heap = {}
	for sym = 0, EOF_SYM do
		if freq[sym] > 0 then
			table.insert(heap, { w = freq[sym], sym = sym, l = nil, r = nil })
		end
	end
	if #heap == 0 then return {} end
	table.sort(heap, function(a, b) return a.w < b.w end)

	while #heap > 1 do
		local a = table.remove(heap, 1)
		local b = table.remove(heap, 1)
		local parent = { w = a.w + b.w, sym = nil, l = a, r = b }
		local placed = false
		for i = 1, #heap do
			if parent.w <= heap[i].w then
				table.insert(heap, i, parent)
				placed = true
				break
			end
		end
		if not placed then table.insert(heap, parent) end
	end

	local lengths: { [number]: number } = {}
	for i = 0, EOF_SYM do lengths[i] = 0 end

	local function _walk(node, depth: number)
		if node.sym ~= nil then
			lengths[node.sym] = math.max(1, depth)
		else
			if node.l then _walk(node.l, depth + 1) end
			if node.r then _walk(node.r, depth + 1) end
		end
	end
	_walk(heap[1], 0)
	return lengths
end

-- Build canonical Huffman encode table: sym → { code, len }
local function _buildEncodeTable(lengths: { [number]: number })
	local syms = {}
	for sym = 0, EOF_SYM do
		if lengths[sym] > 0 then
			table.insert(syms, { sym = sym, len = lengths[sym] })
		end
	end
	table.sort(syms, function(a, b)
		return a.len < b.len or (a.len == b.len and a.sym < b.sym)
	end)

	local codes = {}
	local code, prevLen = 0, 0
	for _, e in ipairs(syms) do
		if e.len > prevLen then
			code    = bit32.lshift(code, e.len - prevLen)
			prevLen = e.len
		end
		codes[e.sym] = { code = code, len = e.len }
		code += 1
	end
	return codes
end

-- Build canonical Huffman decode table: decTable[len][code] = sym
local function _buildDecodeTable(lengths: { [number]: number }): ({ [number]: { [number]: number } }, number)
	local syms = {}
	for sym = 0, EOF_SYM do
		if lengths[sym] > 0 then
			table.insert(syms, { sym = sym, len = lengths[sym] })
		end
	end
	table.sort(syms, function(a, b)
		return a.len < b.len or (a.len == b.len and a.sym < b.sym)
	end)

	local tbl: { [number]: { [number]: number } } = {}
	local maxLen = 0
	local code, prevLen = 0, 0
	for _, e in ipairs(syms) do
		if e.len > prevLen then
			code    = bit32.lshift(code, e.len - prevLen)
			prevLen = e.len
		end
		if not tbl[e.len] then tbl[e.len] = {} end
		tbl[e.len][code] = e.sym
		if e.len > maxLen then maxLen = e.len end
		code += 1
	end
	return tbl, maxLen
end

------------------------------------------------------------------------
--  Bit I/O
------------------------------------------------------------------------

local function _newWriter()
	local bytes = {}
	local cur, bits, total = 0, 0, 0
	return {
		write = function(code: number, len: number)
			for i = len - 1, 0, -1 do
				cur   = bit32.bor(bit32.lshift(cur, 1), bit32.extract(code, i, 1))
				bits  += 1
				total += 1
				if bits == 8 then
					table.insert(bytes, cur)
					cur  = 0
					bits = 0
				end
			end
		end,
		flush = function()
			if bits > 0 then
				table.insert(bytes, bit32.lshift(cur, 8 - bits))
			end
		end,
		getBytes     = function() return bytes end,
		getBitCount  = function() return total end,
	}
end

local function _newReader(bytes: { number })
	local byteIdx = 1
	local cur, bits = 0, 0
	return {
		read = function(): number?
			if bits == 0 then
				if byteIdx > #bytes then return nil end
				cur      = bytes[byteIdx]
				byteIdx += 1
				bits     = 8
			end
			bits -= 1
			return bit32.extract(cur, bits, 1)
		end,
	}
end

------------------------------------------------------------------------
--  Helpers
------------------------------------------------------------------------

local function _bytesToString(bytes: { number }): string
	local CHUNK = 4096
	local parts = table.create(math.ceil(#bytes / CHUNK))
	for i = 1, #bytes, CHUNK do
		parts[#parts + 1] = string.char(table.unpack(bytes, i, math.min(i + CHUNK - 1, #bytes)))
	end
	return table.concat(parts)
end

------------------------------------------------------------------------
--  Public API
------------------------------------------------------------------------

function LZH.Compress(data: any): string
	local json  = HttpService:JSONEncode(data)
	local bytes = table.create(#json)
	for i = 1, #json do bytes[i] = string.byte(json, i) end

	local lzBytes = _lz77Compress(bytes)
	local lengths = _buildLengths(lzBytes)
	local codes   = _buildEncodeTable(lengths)

	local writer = _newWriter()
	for _, b in ipairs(lzBytes) do
		local c = codes[b]
		writer.write(c.code, c.len)
	end
	local eof = codes[EOF_SYM]
	writer.write(eof.code, eof.len)
	writer.flush()

	local huffBytes = writer.getBytes()
	local bitCount  = writer.getBitCount()

	local outSize = 2 + 257 + 4 + #huffBytes
	local out     = buffer.create(outSize)
	local p       = 0

	buffer.writeu8(out, p, MAGIC_0) p += 1
	buffer.writeu8(out, p, MAGIC_1) p += 1

	for sym = 0, 256 do
		buffer.writeu8(out, p, lengths[sym] or 0) p += 1
	end

	buffer.writeu8(out, p, bit32.band(bitCount, 0xFF))                         p += 1
	buffer.writeu8(out, p, bit32.band(bit32.rshift(bitCount, 8),  0xFF))       p += 1
	buffer.writeu8(out, p, bit32.band(bit32.rshift(bitCount, 16), 0xFF))       p += 1
	buffer.writeu8(out, p, bit32.band(bit32.rshift(bitCount, 24), 0xFF))       p += 1

	for _, b in ipairs(huffBytes) do
		buffer.writeu8(out, p, b) p += 1
	end

	return Base64.Encode(buffer.tostring(out))
end

function LZH.Decompress(encoded: string): any
	local raw = Base64.Decode(encoded)
	if not raw or #raw < 2 + 257 + 4 then
		warn("RoExpress.Codec.LZH: data too short")
		return nil
	end

	local src = buffer.fromstring(raw)
	local p   = 0

	if buffer.readu8(src, p) ~= MAGIC_0 or buffer.readu8(src, p + 1) ~= MAGIC_1 then
		warn("RoExpress.Codec.LZH: missing magic header")
		return nil
	end
	p += 2

	local lengths: { [number]: number } = {}
	for sym = 0, 256 do
		lengths[sym] = buffer.readu8(src, p) ; p += 1
	end

	local bitCount = buffer.readu8(src, p)
		+ buffer.readu8(src, p + 1) * 256
		+ buffer.readu8(src, p + 2) * 65536
		+ buffer.readu8(src, p + 3) * 16777216
	p += 4

	local huffBytes = {}
	for i = p, buffer.len(src) - 1 do
		table.insert(huffBytes, buffer.readu8(src, i))
	end

	local decTable, maxLen = _buildDecodeTable(lengths)
	local reader            = _newReader(huffBytes)
	local lzBytes           = {}
	local bitsRead          = 0
	local curCode, curLen   = 0, 0

	while bitsRead < bitCount do
		local bit = reader.read()
		if bit == nil then break end
		bitsRead += 1
		curCode   = bit32.bor(bit32.lshift(curCode, 1), bit)
		curLen   += 1

		local sym = decTable[curLen] and decTable[curLen][curCode]
		if sym ~= nil then
			if sym == EOF_SYM then break end
			table.insert(lzBytes, sym)
			curCode = 0
			curLen  = 0
		elseif curLen > maxLen then
			warn("RoExpress.Codec.LZH: Huffman code exceeded max length — data corrupt")
			return nil
		end
	end

	local decompBytes = _lz77Decompress(lzBytes)
	if not decompBytes then return nil end

	local ok, result = pcall(HttpService.JSONDecode, HttpService, _bytesToString(decompBytes))
	if not ok then
		warn("RoExpress.Codec.LZH: JSON decode failed:", result)
		return nil
	end
	return result
end

return LZH
