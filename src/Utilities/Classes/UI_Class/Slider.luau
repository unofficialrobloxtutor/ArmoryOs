--!strict
--[[
	Slider
	==================================================================
	Track + draggable knob. Works with mouse and touch. Supports an
	optional Step for snapping (e.g. volume in increments of 5).
==================================================================
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Format = require(script.Parent.Format_Library)

local Slider = {}

export type SliderProps = {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Min: number?,
	Max: number?,
	Default: number?,
	Step: number?,
	OnChanged: ((value: number) -> ())?,
}

export type SliderAPI = {
	SetValue: (self: SliderAPI, value: number, animate: boolean?) -> (),
	GetValue: (self: SliderAPI) -> number,
	Destroy: (self: SliderAPI) -> (),
}

function Slider.new(props: SliderProps): (Frame, SliderAPI)
	local min = props.Min or 0
	local max = props.Max or 1
	local step = props.Step or 0
	local value = Format.Number_Clamp(props.Default or min, min, max)

	local root = Instance.new("Frame")
	root.Name = "Slider"
	root.Size = props.Size or UDim2.new(1, 0, 0, 24)
	root.Position = props.Position or UDim2.fromScale(0, 0)
	root.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	root.BackgroundTransparency = 1

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.fromScale(0, 0.5)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.BackgroundColor3 = Theme.Colors.SurfaceLight
	track.BorderSizePixel = 0
	track.Parent = root

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Colors.Primary
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(18, 18)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Theme.Colors.TextPrimary
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local connections: { RBXScriptConnection } = {}
	local dragging = false

	local function alphaFromValue(v: number): number
		if max == min then return 0 end
		return Format.Number_Clamp((v - min) / (max - min), 0, 1)
	end

	local function applyVisual(animate: boolean?)
		local alpha = alphaFromValue(value)
		if animate then
			TweenService:Create(fill, Format.TweenInfo_Simple(0.1), { Size = UDim2.fromScale(alpha, 1) }):Play()
			TweenService:Create(knob, Format.TweenInfo_Simple(0.1), { Position = UDim2.fromScale(alpha, 0.5) }):Play()
		else
			fill.Size = UDim2.fromScale(alpha, 1)
			knob.Position = UDim2.fromScale(alpha, 0.5)
		end
	end

	local function setValue(newValue: number, animate: boolean?, fire: boolean?)
		local clamped = Format.Number_Clamp(newValue, min, max)
		if step > 0 then
			clamped = Format.Number_RoundToStep(clamped, step)
		end
		value = clamped
		applyVisual(animate)
		if fire ~= false and props.OnChanged then
			props.OnChanged(value)
		end
	end

	local function updateFromInputX(inputX: number)
		local trackAbsPos = track.AbsolutePosition.X
		local trackAbsSize = track.AbsoluteSize.X
		local alpha = Format.Number_Clamp((inputX - trackAbsPos) / math.max(1, trackAbsSize), 0, 1)
		setValue(min + alpha * (max - min), false)
	end

	table.insert(connections, knob.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end))

	table.insert(connections, track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromInputX(input.Position.X)
		end
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInputX(input.Position.X)
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	applyVisual(false)

	if props.Parent then
		root.Parent = props.Parent
	end

	local api = {} :: SliderAPI

	function api:SetValue(newValue: number, animate: boolean?)
		setValue(newValue, animate, false)
	end

	function api:GetValue(): number
		return value
	end

	function api:Destroy()
		for _, conn in connections do
			conn:Disconnect()
		end
		root:Destroy()
	end

	return root, api
end

return Slider