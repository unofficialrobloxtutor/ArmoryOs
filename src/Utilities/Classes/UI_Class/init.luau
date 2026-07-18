--!strict
--[[
	UI_Library
	==================================================================
	Imperative, strict-typed Luau UI component library.

	Components: Button, Panel, Modal, TabGroup, ProgressBar,
	ToastQueue, Dropdown, Slider.

	Every constructor returns (rootInstance, api) — parent the root
	yourself via the Parent prop or manually, update state through
	the api table, and call api:Destroy() to disconnect + clean up.

	No reactive/state system: you own the update calls.

	Usage:
		local UI = require(path.to.UI_Library)

		local btn, btnApi = UI.Button({
			Text = "Play",
			Parent = screenGui,
			Size = UDim2.fromOffset(160, 44),
			OnClick = function()
				print("clicked")
			end,
		})

		btnApi:SetText("Loading...")
		btnApi:Destroy()

	Author:   [Your Name / @tostadium]
	Module:   UI_Library
	Version:  1.0.0
==================================================================
]]

local UI = {}

UI.Theme = require(script.Theme)
UI.Button = require(script.Button).new
UI.Panel = require(script.Panel).new
UI.Modal = require(script.Modal).new
UI.TabGroup = require(script.TabGroup).new
UI.ProgressBar = require(script.ProgressBar).new
UI.ToastQueue = require(script.ToastQueue).new
UI.Dropdown = require(script.Dropdown).new
UI.Slider = require(script.Slider).new

return UI