--!strict
--[[
	Panel
	==================================================================
	Basic container: rounded surface, optional title bar, padded
	content frame. Used standalone or as the base for Modal.
==================================================================
]]

local Theme = require(script.Parent.Theme)

local Panel = {}

export type PanelProps = {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Title: string?,
	Padding: number?,
}

export type PanelAPI = {
	SetVisible: (self: PanelAPI, visible: boolean) -> (),
	SetTitle: (self: PanelAPI, title: string) -> (),
	GetContentFrame: (self: PanelAPI) -> Frame,
	Destroy: (self: PanelAPI) -> (),
}

function Panel.new(props: PanelProps): (Frame, PanelAPI)
	local p = props.Padding or Theme.Spacing.M

	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.Size = props.Size or UDim2.fromOffset(320, 240)
	root.Position = props.Position or UDim2.fromScale(0, 0)
	root.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	root.BackgroundColor3 = Theme.Colors.Surface
	root.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Stroke
	stroke.Thickness = Theme.StrokeThickness
	stroke.Parent = root

	local titleLabel: TextLabel? = nil
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0

	if props.Title then
		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.Size = UDim2.new(1, -p * 2, 0, 28)
		label.Position = UDim2.fromOffset(p, p)
		label.BackgroundTransparency = 1
		label.Font = Theme.Fonts.Heading
		label.TextSize = Theme.TextSizes.Heading
		label.TextColor3 = Theme.Colors.TextPrimary
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = props.Title
		label.Parent = root
		titleLabel = label

		contentFrame.Size = UDim2.new(1, -p * 2, 1, -(28 + p * 3))
		contentFrame.Position = UDim2.new(0, p, 0, 28 + p * 2)
	else
		contentFrame.Size = UDim2.new(1, -p * 2, 1, -p * 2)
		contentFrame.Position = UDim2.fromOffset(p, p)
	end

	contentFrame.Parent = root

	if props.Parent then
		root.Parent = props.Parent
	end

	local api = {} :: PanelAPI

	function api:SetVisible(visible: boolean)
		root.Visible = visible
	end

	function api:SetTitle(title: string)
		if titleLabel then
			titleLabel.Text = title
		end
	end

	function api:GetContentFrame(): Frame
		return contentFrame
	end

	function api:Destroy()
		root:Destroy()
	end

	return root, api
end

return Panel