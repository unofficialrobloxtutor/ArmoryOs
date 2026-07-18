--!strict
--[[
	Theme
	==================================================================
	Single source of truth for the UI library's colors, fonts, sizing,
	and spacing. Swap values here to reskin every component at once.

	Author:   [Your Name / @tostadium]
	Module:   UI_Library.Theme
==================================================================
]]

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(20, 20, 24),
	Surface = Color3.fromRGB(32, 32, 38),
	SurfaceLight = Color3.fromRGB(46, 46, 54),
	Primary = Color3.fromRGB(88, 101, 242),
	PrimaryHover = Color3.fromRGB(108, 121, 255),
	Secondary = Color3.fromRGB(46, 46, 54),
	Success = Color3.fromRGB(87, 201, 122),
	Warning = Color3.fromRGB(240, 173, 78),
	Danger = Color3.fromRGB(230, 79, 79),
	TextPrimary = Color3.fromRGB(235, 235, 240),
	TextSecondary = Color3.fromRGB(160, 160, 170),
	Stroke = Color3.fromRGB(56, 56, 64),
}

Theme.Fonts = {
	Body = Enum.Font.Gotham,
	Heading = Enum.Font.GothamBold,
	Mono = Enum.Font.RobotoMono,
}

Theme.TextSizes = {
	Small = 14,
	Body = 16,
	Heading = 20,
	Title = 28,
}

Theme.CornerRadius = UDim.new(0, 8)
Theme.CornerRadiusSmall = UDim.new(0, 4)
Theme.StrokeThickness = 1

Theme.Spacing = {
	XS = 4,
	S = 8,
	M = 16,
	L = 24,
	XL = 32,
}

-- Applies a UIScale to `guiObject` that tracks the device's viewport so
-- text/padding stays proportionate on mobile. Call once per top-level
-- ScreenGui or panel that needs to shrink on small screens.
function Theme.ApplyMobileScale(guiObject: Instance, minScale: number?, maxScale: number?)
	local scale = Instance.new("UIScale")
	scale.Parent = guiObject

	local function update()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewportY = camera.ViewportSize.Y
		local factor = math.clamp(viewportY / 1080, minScale or 0.7, maxScale or 1.15)
		scale.Scale = factor
	end

	update()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end

	return scale
end

return Theme