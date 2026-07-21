--!strict
--[[
	ProgressBar
	==================================================================
	Track + fill bar for health, XP, loading, cooldowns, etc.
	SetProgress accepts an 0-1 alpha; pair with Format_Library's
	Number_StatBar/Number_Percent for the label text upstream.
==================================================================
]]

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Format = require(script.Parent.Parent.Parent.Libraries.Format_Library)

local ProgressBar = {}

export type ProgressBarProps = {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Default: number?,
	Color: Color3?,
	ShowLabel: boolean?,
}

export type ProgressBarAPI = {
	SetProgress: (self: ProgressBarAPI, alpha: number, animate: boolean?) -> (),
	SetColor: (self: ProgressBarAPI, color: Color3) -> (),
	GetProgress: (self: ProgressBarAPI) -> number,
	Destroy: (self: ProgressBarAPI) -> (),
}

function ProgressBar.new(props: ProgressBarProps): (Frame, ProgressBarAPI)
	local startAlpha = Format.Number_Clamp(props.Default or 0, 0, 1)

	local root = Instance.new("Frame")
	root.Name = "ProgressBar"
	root.Size = props.Size or UDim2.new(1, 0, 0, 20)
	root.Position = props.Position or UDim2.fromScale(0, 0)
	root.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	root.BackgroundColor3 = Theme.Colors.SurfaceLight
	root.BorderSizePixel = 0
	root.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadiusSmall
	corner.Parent = root

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = props.Color or Theme.Colors.Success
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(startAlpha, 1)
	fill.Parent = root

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = Theme.CornerRadiusSmall
	fillCorner.Parent = fill

	local label: TextLabel? = nil
	if props.ShowLabel then
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Theme.Fonts.Body
		lbl.TextSize = Theme.TextSizes.Small
		lbl.TextColor3 = Theme.Colors.TextPrimary
		lbl.Text = Format.Number_Percent(startAlpha, 0)
		lbl.ZIndex = 2
		lbl.Parent = root
		label = lbl
	end

	local currentAlpha = startAlpha

	if props.Parent then
		root.Parent = props.Parent
	end

	local api = {} :: ProgressBarAPI

	function api:SetProgress(alpha: number, animate: boolean?)
		currentAlpha = Format.Number_Clamp(alpha, 0, 1)
		if animate then
			TweenService:Create(fill, Format.TweenInfo_Simple(0.2), { Size = UDim2.fromScale(currentAlpha, 1) }):Play()
		else
			fill.Size = UDim2.fromScale(currentAlpha, 1)
		end
		if label then
			label.Text = Format.Number_Percent(currentAlpha, 0)
		end
	end

	function api:SetColor(color: Color3)
		fill.BackgroundColor3 = color
	end

	function api:GetProgress(): number
		return currentAlpha
	end

	function api:Destroy()
		root:Destroy()
	end

	return root, api
end

return ProgressBar