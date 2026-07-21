--!strict
--[[
	Button
	==================================================================
	Imperative button component. Hover/press feedback is tweened using
	TweenInfo presets from Format_Library. Returns the root TextButton
	plus a typed API for updates.
==================================================================
]]

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Format = require(script.Parent.Parent.Parent.Libraries.Format_Library)

local Button = {}

export type ButtonVariant = "Primary" | "Secondary" | "Danger"

export type ButtonProps = {
	Text: string,
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Variant: ButtonVariant?,
	OnClick: (() -> ())?,
}

export type ButtonAPI = {
	SetText: (self: ButtonAPI, text: string) -> (),
	SetEnabled: (self: ButtonAPI, enabled: boolean) -> (),
	SetVariant: (self: ButtonAPI, variant: ButtonVariant) -> (),
	Destroy: (self: ButtonAPI) -> (),
}

local VARIANT_COLORS: { [ButtonVariant]: Color3 } = {
	Primary = Theme.Colors.Primary,
	Secondary = Theme.Colors.Secondary,
	Danger = Theme.Colors.Danger,
}

function Button.new(props: ButtonProps): (TextButton, ButtonAPI)
	local variant = props.Variant or "Primary"
	local baseColor = VARIANT_COLORS[variant]
	local enabled = true

	local root = Instance.new("TextButton")
	root.Name = "Button"
	root.Size = props.Size or UDim2.fromOffset(160, 40)
	root.Position = props.Position or UDim2.fromScale(0, 0)
	root.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	root.BackgroundColor3 = baseColor
	root.AutoButtonColor = false
	root.Font = Theme.Fonts.Body
	root.TextSize = Theme.TextSizes.Body
	root.TextColor3 = Theme.Colors.TextPrimary
	root.Text = props.Text
	root.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Stroke
	stroke.Thickness = Theme.StrokeThickness
	stroke.Parent = root

	local scaleConstraint = Instance.new("UIScale")
	scaleConstraint.Parent = root

	local connections: { RBXScriptConnection } = {}

	local function tweenTo(goal: { [string]: any }, duration: number?)
		TweenService:Create(root, Format.TweenInfo_Simple(duration or 0.12), goal):Play()
	end

	table.insert(connections, root.MouseEnter:Connect(function()
		if not enabled then return end
		tweenTo({ BackgroundColor3 = baseColor:Lerp(Color3.new(1, 1, 1), 0.12) })
	end))

	table.insert(connections, root.MouseLeave:Connect(function()
		if not enabled then return end
		tweenTo({ BackgroundColor3 = baseColor })
	end))

	table.insert(connections, root.MouseButton1Down:Connect(function()
		if not enabled then return end
		TweenService:Create(scaleConstraint, Format.TweenInfo_Simple(0.08), { Scale = 0.94 }):Play()
	end))

	table.insert(connections, root.MouseButton1Up:Connect(function()
		if not enabled then return end
		TweenService:Create(scaleConstraint, Format.TweenInfo_Bouncy(0.18), { Scale = 1 }):Play()
	end))

	table.insert(connections, root.Activated:Connect(function()
		if enabled and props.OnClick then
			props.OnClick()
		end
	end))

	if props.Parent then
		root.Parent = props.Parent
	end

	local api = {} :: ButtonAPI

	function api:SetText(text: string)
		root.Text = text
	end

	function api:SetEnabled(isEnabled: boolean)
		enabled = isEnabled
		tweenTo({
			BackgroundColor3 = isEnabled and baseColor or Theme.Colors.SurfaceLight,
			TextTransparency = isEnabled and 0 or 0.4,
		})
	end

	function api:SetVariant(variantName: ButtonVariant)
		baseColor = VARIANT_COLORS[variantName] or Theme.Colors.Primary
		tweenTo({ BackgroundColor3 = baseColor })
	end

	function api:Destroy()
		for _, conn in connections do
			conn:Disconnect()
		end
		root:Destroy()
	end

	return root, api
end

return Button