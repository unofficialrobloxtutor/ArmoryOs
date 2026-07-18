--!strict
--[[
	TabGroup
	==================================================================
	Row of tab buttons that switch between content frames. Each tab's
	content frame is exposed via GetContentFrame so you can parent
	your own UI into it after construction.
==================================================================
]]

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Format = require(script.Parent.Format_Library)

local TabGroup = {}

export type TabGroupProps = {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Tabs: { string },
	Default: number?,
	OnChanged: ((index: number, name: string) -> ())?,
}

export type TabGroupAPI = {
	SelectTab: (self: TabGroupAPI, index: number) -> (),
	GetSelectedIndex: (self: TabGroupAPI) -> number,
	GetContentFrame: (self: TabGroupAPI, index: number) -> Frame,
	Destroy: (self: TabGroupAPI) -> (),
}

function TabGroup.new(props: TabGroupProps): (Frame, TabGroupAPI)
	local headerHeight = 36

	local root = Instance.new("Frame")
	root.Name = "TabGroup"
	root.Size = props.Size or UDim2.fromScale(1, 1)
	root.Position = props.Position or UDim2.fromScale(0, 0)
	root.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	root.BackgroundTransparency = 1

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	header.BackgroundTransparency = 1
	header.Parent = root

	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.Padding = UDim.new(0, Theme.Spacing.S)
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Parent = header

	local contentHolder = Instance.new("Frame")
	contentHolder.Name = "ContentHolder"
	contentHolder.Size = UDim2.new(1, 0, 1, -(headerHeight + Theme.Spacing.S))
	contentHolder.Position = UDim2.new(0, 0, 0, headerHeight + Theme.Spacing.S)
	contentHolder.BackgroundTransparency = 1
	contentHolder.Parent = root

	local tabButtons: { TextButton } = {}
	local contentFrames: { Frame } = {}
	local connections: { RBXScriptConnection } = {}
	local selectedIndex = 1

	local function selectTab(index: number, fire: boolean?)
		selectedIndex = index
		for i, btn in tabButtons do
			local isSelected = i == index
			TweenService:Create(btn, Format.TweenInfo_Simple(0.12), {
				BackgroundColor3 = isSelected and Theme.Colors.Primary or Theme.Colors.Surface,
			}):Play()
			contentFrames[i].Visible = isSelected
		end
		if fire ~= false and props.OnChanged then
			props.OnChanged(index, props.Tabs[index])
		end
	end

	for i, tabName in props.Tabs do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. tabName
		btn.Size = UDim2.fromOffset(120, headerHeight)
		btn.BackgroundColor3 = Theme.Colors.Surface
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.Font = Theme.Fonts.Body
		btn.TextSize = Theme.TextSizes.Body
		btn.TextColor3 = Theme.Colors.TextPrimary
		btn.Text = tabName
		btn.LayoutOrder = i
		btn.Parent = header

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadiusSmall
		corner.Parent = btn

		table.insert(connections, btn.Activated:Connect(function()
			selectTab(i, true)
		end))

		table.insert(tabButtons, btn)

		local contentFrame = Instance.new("Frame")
		contentFrame.Name = "Content_" .. tabName
		contentFrame.Size = UDim2.fromScale(1, 1)
		contentFrame.BackgroundTransparency = 1
		contentFrame.Visible = false
		contentFrame.Parent = contentHolder

		table.insert(contentFrames, contentFrame)
	end

	if props.Parent then
		root.Parent = props.Parent
	end

	selectTab(props.Default or 1, false)

	local api = {} :: TabGroupAPI

	function api:SelectTab(index: number)
		selectTab(index, true)
	end

	function api:GetSelectedIndex(): number
		return selectedIndex
	end

	function api:GetContentFrame(index: number): Frame
		return contentFrames[index]
	end

	function api:Destroy()
		for _, conn in connections do
			conn:Disconnect()
		end
		root:Destroy()
	end

	return root, api
end

return TabGroup