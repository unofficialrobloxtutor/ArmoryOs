--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       ArmoryOS Server Smoke Test
--  ◄► Description: Boots Utilities/Core/Server + Utilities/Core/Network
--                  and logs weapon lifecycle events, to confirm the App/
--                  Stream layer actually comes up without erroring.
--                  Runs automatically from ServerScriptService — see
--                  default.project.json ("ArmoryOSServer").
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AmoryOS = ReplicatedStorage:FindFirstChild("ArmoryOS", true) or ReplicatedStorage:WaitForChild("ArmoryOS")

local ServerCore  = require(AmoryOS.Utilities.Core.Server)
local NetworkCore = require(AmoryOS.Utilities.Core.Network)

local server = ServerCore.New()
local network = NetworkCore.New(server)

print("[ArmoryOS Test] Server booted — App mounted, Streams initialized.")

server:On("WeaponEquipped", function(payload)
	print(("[ArmoryOS Test] WeaponEquipped: %s -> %s"):format(payload.Player.Name, payload.WeaponId))
end)

server:On("WeaponUnequipped", function(payload)
	print(("[ArmoryOS Test] WeaponUnequipped: %s -> %s"):format(payload.Player.Name, payload.WeaponId))
end)

server:On("WeaponFired", function(payload)
	print(("[ArmoryOS Test] WeaponFired: %s -> %s"):format(payload.Player.Name, payload.WeaponId))
end)
