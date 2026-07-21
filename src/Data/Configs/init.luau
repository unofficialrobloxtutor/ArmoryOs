--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       Configs
--  ◄► Version:     1.0
--  ◄► Date:        18/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: Data/Configs — registry over every baked weapon
--                  config module under Configs/<Category>/<WeaponId>.
--                  Shared (ReplicatedStorage): the client uses it to
--                  build viewmodels/UI, the server uses it as the
--                  authoritative source when validating equip/fire/
--                  reload requests — the server never trusts a config
--                  sent by a client.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ConfigType = require(script.Parent.Parent.Utilities.Types.Config)

export type BaseConfig = ConfigType.BaseConfig

local Module = {}

-- WeaponId -> config, lazily built on first lookup.
local _byId: { [string]: BaseConfig }? = nil

local function _buildIndex(): { [string]: BaseConfig }
	local index: { [string]: BaseConfig } = {}

	for _, categoryFolder in script:GetChildren() do
		if not categoryFolder:IsA("Folder") then
			continue
		end
		for _, child in categoryFolder:GetChildren() do
			if not child:IsA("ModuleScript") then
				continue
			end
			local ok, config = pcall(require, child)
			if not ok or type(config) ~= "table" or type((config :: any).Name) ~= "string" then
				warn("[Configs] Skipping invalid config module '" .. child:GetFullName() .. "'")
				continue
			end
			local typed = config :: BaseConfig
			if index[typed.Name] then
				warn("[Configs] Duplicate WeaponId '" .. typed.Name .. "' — keeping first, ignoring " .. child:GetFullName())
				continue
			end
			index[typed.Name] = typed
		end
	end

	return index
end

--► Returns the baked config for a WeaponId, or nil if unknown.
function Module.Get(weaponId: string): BaseConfig?
	if not _byId then
		_byId = _buildIndex()
	end
	return (_byId :: { [string]: BaseConfig })[weaponId]
end

--► Returns every registered config, keyed by WeaponId.
function Module.GetAll(): { [string]: BaseConfig }
	if not _byId then
		_byId = _buildIndex()
	end
	return _byId :: { [string]: BaseConfig }
end

return Module
