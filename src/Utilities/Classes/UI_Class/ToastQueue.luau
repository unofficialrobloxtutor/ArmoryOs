--!strict
--[[
	ToastQueue
	==================================================================
	Stacking notification manager anchored to a corner. Call Push()
	repeatedly; oldest toasts are evicted past MaxVisible, and each
	toast auto-dismisses after its duration.
==================================================================
]]

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Format = require(script.Parent.Format_Library)

local ToastQueue = {}

export type ToastKind = "Info" | "Success" | "Warning" | "Danger"

export type ToastQueueProps = {
	Parent: Instance,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	MaxVisible: number?,
}

export type ToastQueueAPI = {
	Push: (self: ToastQueueAPI, text: string, kind: ToastKind?, duration: number?) -> (),
	Destroy: (self: ToastQueueAPI) -> (),
}

local KIND_COLORS: { [ToastKind]: Color3 } = {
	Info = Theme.Colors.Primary,
	Success = Theme.Colors.Success,
	Warning = Theme.Colors.Warning,
	Danger = Theme.Colors.Danger,
}

function ToastQueue.new(props: ToastQueueProps): (Frame, ToastQueueAPI)
	local root = Instance.new("Frame")
	root.Name = "ToastQueue"
	root.Size = UDim2.fromOffset(300, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Position = props.Position or UDim2.new(1, -16, 1, -16)
	root.AnchorPoint = props.AnchorPoint or Vector2.new(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = props.Parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, Theme.Spacing.S)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local activeToasts: { Frame } = {}
	local layoutOrderCounter = 0

	local function removeToast(toast: Frame)
		local index = table.find(activeToasts, toast)
		if not index then return end
		table.remove(activeToasts, index)

		local tween = TweenService:Create(toast, Format.TweenInfo_Simple(0.2), { BackgroundTransparency = 1 })
		tween:Play()
		local conn: RBXScriptConnection
		conn = tween.Completed:Connect(function()
			conn:Disconnect()
			toast:Destroy()
		end)
	end

	local api = {} :: ToastQueueAPI

	function api:Push(text: string, kind: ToastKind?, duration: number?)
		local color = KIND_COLORS[kind or "Info"]
		layoutOrderCounter += 1

		local toast = Instance.new("Frame")
		toast.Name = "Toast"
		toast.Size = UDim2.new(1, 0, 0, 44)
		toast.BackgroundColor3 = Theme.Colors.Surface
		toast.BackgroundTransparency = 1
		toast.BorderSizePixel = 0
		toast.ClipsDescendants = true
		toast.LayoutOrder = layoutOrderCounter
		toast.Parent = root

		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadiusSmall
		corner.Parent = toast

		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.Size = UDim2.new(0, 4, 1, 0)
		accent.BackgroundColor3 = color
		accent.BorderSizePixel = 0
		accent.Parent = toast

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -16, 1, 0)
		label.Position = UDim2.fromOffset(12, 0)
		label.BackgroundTransparency = 1
		label.Font = Theme.Fonts.Body
		label.TextSize = Theme.TextSizes.Body
		label.TextColor3 = Theme.Colors.TextPrimary
		label.TextWrapped = true
		label.Text = text
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = toast

		table.insert(activeToasts, toast)

		local maxVisible = props.MaxVisible or 5
		while #activeToasts > maxVisible do
			removeToast(activeToasts[1])
		end

		TweenService:Create(toast, Format.TweenInfo_Simple(0.15), { BackgroundTransparency = 0 }):Play()

		task.delay(duration or 3, function()
			if toast.Parent then
				removeToast(toast)
			end
		end)
	end

	function api:Destroy()
		root:Destroy()
	end

	return root, api
end

return ToastQueue