------------------------------------------------------------------------
--  <> Title:       RoExpress.Codec
--  <> Version:     2.0
--  <> Date:        09/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Compression module for RoExpress.
--
--  ALGORITHMS
--  ────────────────────────────────────────────────────────────────
--  Codec.LZ77  — sliding-window, magic 0xC0 0xDE
--  Codec.LZH   — LZ77 + Huffman coding, magic 0xC0 0xDF
--
--  API
--  ────────────────────────────────────────────────────────────────
--  Codec.Deflate(data)       → string   compress with LZH (best)
--  Codec.Inflate(encoded)    → any      decompress, auto-detects algorithm
--  Codec.Compress(data)      → string   compress with LZ77 (backwards compat)
--  Codec.Decompress(encoded) → any      alias for Inflate
--  Codec.IsCompressed(str)   → boolean  checks for either magic header
--
--  Sub-modules are also accessible directly:
--  Codec.LZ77.Compress / Codec.LZ77.Decompress
--  Codec.LZH.Compress  / Codec.LZH.Decompress
------------------------------------------------------------------------
local Base64 = require(script.Parent.Base64)
local LZ77   = require(script.LZ77)
local LZH    = require(script.LZH)

local MAGIC_LZ77 = { 0xC0, 0xDE }
local MAGIC_LZH  = { 0xC0, 0xDF }

local Codec = {
	LZ77 = LZ77,
	LZH  = LZH,
}

-- Deflate — compress with LZH (LZ77 + Huffman, better ratios)
Codec.Deflate  = LZH.Compress

-- Compress — LZ77 only, kept for backwards compatibility
Codec.Compress = LZ77.Compress

-- Inflate / Decompress — auto-detects which algorithm was used
local function _inflate(encoded: string): any
	if not encoded or #encoded < 4 then return nil end
	local ok, raw = pcall(Base64.Decode, encoded)
	if not ok or #raw < 2 then return nil end
	local src = buffer.fromstring(raw)
	local b1  = buffer.readu8(src, 1)
	if b1 == MAGIC_LZH[2] then
		return LZH.Decompress(encoded)
	end
	return LZ77.Decompress(encoded)
end

Codec.Inflate    = _inflate
Codec.Decompress = _inflate

function Codec.IsCompressed(encoded: string): boolean
	if not encoded or #encoded < 4 then return false end
	local ok, raw = pcall(Base64.Decode, encoded)
	if not ok or #raw < 2 then return false end
	local src = buffer.fromstring(raw)
	local b0  = buffer.readu8(src, 0)
	local b1  = buffer.readu8(src, 1)
	return (b0 == MAGIC_LZ77[1] and b1 == MAGIC_LZ77[2])
		or (b0 == MAGIC_LZH[1]  and b1 == MAGIC_LZH[2])
end

return Codec
