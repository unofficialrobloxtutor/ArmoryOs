--!strict
--[[
	Dropdown
	==================================================================
	Header button that expands a scrollable option list below it.
	Rebuild the list via SetOptions when the option set changes.
==================================================================
]]

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Format = require(script.Parent.Format_Library)

local Dropdown = {}

export type DropdownProps = {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Options: { string }?,
	Default: string?,
	MaxVisibleOptions: number?,
	OnChanged: ((selected: string) -> ())?,
}

export type DropdownAPI = {
	SetOptions: (self: DropdownAPI, options: { string }) -> (),
	SetSelected: (self: DropdownAPI, option: string) -> (),
	GetSelected: (self: DropdownAPI) -> string?,
	Destroy: (self: DropdownAPI) -> (),
}

local OPTION_HEIGHT = 32

function Dropdown.new(props: DropdownProps): (Frame, DropdownAPI)
	local options = props.Options or {}
	local selected: string? = props.Default or options[1]
	local open = false
	local maxVisibleOptions = props.MaxVisibleOptions or 5

	local root = Instance.new("Frame")
	root.Name = "Dropdown"
	root.Size = props.Size or UDim2.new(0, 200, 0, 36)
	root.Position = props.Position or UDim2.fromScale(0, 0)
	root.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	root.BackgroundColor3 = Theme.Colors.Surface
	root.BorderSizePixel = 0
	root.ClipsDescendants = false
	root.ZIndex = 5

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Stroke
	stroke.Thickness = Theme.StrokeThickness
	stroke.Parent = root

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 1)
	header.BackgroundTransparency = 1
	header.Font = Theme.Fonts.Body
	header.TextSize = Theme.TextSizes.Body
	header.TextColor3 = Theme.Colors.TextPrimary
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = "   " .. (selected or "Select...")
	header.AutoButtonColor = false
	header.ZIndex = 5
	header.Parent = root

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.fromOffset(24, 24)
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, -8, 0.5, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "v"
	arrow.Font = Theme.Fonts.Body
	arrow.TextSize = Theme.TextSizes.Body
	arrow.TextColor3 = Theme.Colors.TextSecondary
	arrow.ZIndex = 5
	arrow.Parent = root

	local listHolder = Instance.new("ScrollingFrame")
	listHolder.Name = "ListHolder"
	listHolder.Size = UDim2.new(1, 0, 0, 0)
	listHolder.Position = UDim2.new(0, 0, 1, 4)
	listHolder.BackgroundColor3 = Theme.Colors.Surface
	listHolder.BorderSizePixel = 0
	listHolder.ClipsDescendants = true
	listHolder.ScrollBarThickness = 4
	listHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
	listHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listHolder.ZIndex = 6
	listHolder.Parent = root

	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = Theme.CornerRadius
	listCorner.Parent = listHolder

	local listStroke = Instance.new("UIStroke")
	listStroke.Color = Theme.Colors.Stroke
	listStroke.Thickness = Theme.StrokeThickness
	listStroke.Parent = listHolder

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listHolder

	local connections: { RBXScriptConnection } = {}
	local optionButtons: { TextButton } = {}

	local function close()
		open = false
		TweenService:Create(listHolder, Format.TweenInfo_Simple(0.15), { Size = UDim2.new(1, 0, 0, 0) }):Play()
		TweenService:Create(arrow, Format.TweenInfo_Simple(0.15), { Rotation = 0 }):Play()
	end

	local function selectOption(option: string)
		selected = option
		header.Text = "   " .. option
		close()
		if props.OnChanged then
			props.OnChanged(option)
		end
	end

	local function clearOptionButtons()
		for _, btn in optionButtons do
			btn:Destroy()
		end
		optionButtons = {}
	end

	local function buildOptionButtons()
		clearOptionButtons()
		for i, option in options do
			local btn = Instance.new("TextButton")
			btn.Name = "Option_" .. option
			btn.Size = UDim2.new(1, 0, 0, OPTION_HEIGHT)
			btn.BackgroundColor3 = Theme.Colors.SurfaceLight
			btn.BackgroundTransparency = 1
			btn.Font = Theme.Fonts.Body
			btn.TextSize = Theme.TextSizes.Body
			btn.TextColor3 = Theme.Colors.TextPrimary
			btn.Text = "   " .. option
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.AutoButtonColor = false
			btn.LayoutOrder = i
			btn.ZIndex = 6
			btn.Parent = listHolder

			table.insert(connections, btn.MouseEnter:Connect(function()
				TweenService:Create(btn, Format.TweenInfo_Simple(0.1), { BackgroundTransparency = 0 }):Play()
			end))
			table.insert(connections, btn.MouseLeave:Connect(function()
				TweenService:Create(btn, Format.TweenInfo_Simple(0.1), { BackgroundTransparency = 1 }):Play()
			end))
			table.insert(connections, btn.Activated:Connect(function()
				selectOption(option)
			end))

			table.insert(optionButtons, btn)
		end
	end

	local function toggleOpen()
		open = not open
		if open then
			local targetHeight = math.min(#options, maxVisibleOptions) * OPTION_HEIGHT
			TweenService:Create(listHolder, Format.TweenInfo_Simple(0.15), { Size = UDim2.new(1, 0, 0, targetHeight) }):Play()
			TweenService:Create(arrow, Format.TweenInfo_Simple(0.15), { Rotation = 180 }):Play()
		else
			close()
		end
	end

	table.insert(connections, header.Activated:Connect(toggleOpen))

	buildOptionButtons()

	if props.Parent then
		root.Parent = props.Parent
	end

	local api = {} :: DropdownAPI

	function api:SetOptions(newOptions: { string })
		options = newOptions
		buildOptionButtons()
	end

	function api:SetSelected(option: string)
		selected = option
		header.Text = "   " .. option
	end

	function api:GetSelected(): string?
		return selected
	end

	function api:Destroy()
		for _, conn in connections do
			conn:Disconnect()
		end
		root:Destroy()
	end

	return root, api
end

return Dropdown