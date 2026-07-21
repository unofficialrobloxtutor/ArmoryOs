--!strict
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       ArmoryOS Client Smoke Test
--  ◄► Description: Boots Utilities/Core/Client ("AOS"). Weapons equip
--                  tool-driven: equipping a Tool whose Name matches a
--                  Data/Configs module (e.g. a Tool named "1911") equips
--                  that weapon; unequipping the Tool unequips it. This
--                  script just boots AOS and binds test inputs. Runs
--                  automatically from StarterPlayerScripts — see
--                  default.project.json ("ArmoryOSClient").
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local AmoryOS = ReplicatedStorage:FindFirstChild("ArmoryOS", true) or ReplicatedStorage:WaitForChild("ArmoryOS")

local NetworkCore = require(AmoryOS.Utilities.Core.Network)
local ClientCore  = require(AmoryOS.Utilities.Core.Client)

NetworkCore.New() -- boots RoExpress("Network") client-side (App request calls)
local AOS = ClientCore.New()

print("[ArmoryOS Test] Client booted — equip a Tool named after a config (e.g. \"1911\") to arm up.")

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		AOS:Primary()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		AOS:Secondary()
	elseif input.KeyCode == Enum.KeyCode.R then
		AOS:ApplyAction("Reload")
	elseif input.KeyCode == Enum.KeyCode.Backspace then
		print("[ArmoryOS Test] UnEquipping...")
		AOS:UnEquip()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		AOS:Release("Primary")
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		AOS:Release("Secondary")
	end
end)
