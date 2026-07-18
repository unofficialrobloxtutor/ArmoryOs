--[[
	ScopeUI
	==================================================================
	Self-contained sniper/optic scope overlay. No external assets or
	dependencies — the circular lens, letterbox bars, and reticle are
	all built procedurally.

	- Circular lens stays a true 1:1 circle on any aspect ratio via
	  UIAspectRatioConstraint, with black bars filling the leftover
	  space (the standard fix for "scope image doesn't fit every
	  device").
	- 20 procedural reticle presets (no image required). Whatever a
	  reticle draws, it is clipped to a perfect circle — the
	  ReticleHolder itself is masked with UICorner(1,0) +
	  ClipsDescendants, so ticks/bars/rings can never poke past the
	  lens edge with square corners.
	- Breathing sway (sine drift) plus an external sway offset hook
	  you can drive from recoil/hold-breath systems.
	- Optional Camera FOV zoom tied to Show()/Hide().

	Intended to be required from a LocalScript (uses PlayerGui/Camera).

	Usage:
		local ScopeUI = require(path.to.ScopeUI)

		local scope = ScopeUI.new({
			ZoomedFOV = 12,
			ReticleColor = Color3.fromRGB(60, 230, 100),
			ReticleType = "Mil-Dot", -- see ScopeUI.ReticleNames for all 20
		})

		-- on ADS with a scoped weapon:
		scope:Show()
		-- on unscope:
		scope:Hide()

		-- swap reticles at runtime (e.g. attachment system):
		scope:SetReticle("Duplex")

		-- optional: feed recoil/hold-breath drift into the reticle
		scope:SetSwayOffset(Vector2.new(recoilX, recoilY))

		-- cleanup (e.g. on tool unequip / character removal):
		scope:Destroy()

	Author:   [Your Name / @tostadium]
	Module:   ScopeUI
	Version:  2.0.0
==================================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ScopeUI = {}

-- Strict union of every valid reticle name — gives autocomplete and
-- compile-time typo checking anywhere a ReticleName is expected,
-- instead of accepting any arbitrary string.
export type ReticleName =
	"Crosshair"
| "Fine Crosshair"
| "Mil-Dot"
| "Duplex"
| "German #4"
| "Chevron"
| "Center Dot"
| "Circle Dot"
| "BDC Ladder"
| "Horseshoe Dot"
| "Cross Circle"
| "Corner Brackets"
| "Plex"
| "Donut Ring"
| "Tri-Dot"
| "Diamond"
| "Mil Grid"
| "ACOG Chevron"
| "Range Stadia"
| "Battle Circle"

export type ReticleBuilder = (holder: Frame, color: Color3, thicknessPx: number) -> ()

export type ScopeUIProps = {
	Parent: Instance?, -- defaults to the LocalPlayer's PlayerGui
	Camera: Camera?, -- defaults to workspace.CurrentCamera
	ScopeSizeFraction: number?, -- lens diameter as a fraction of the shorter screen axis (default 0.9)
	VignetteColor: Color3?, -- bar/stroke color, default pure black
	ReticleColor: Color3?, -- default bright green
	ReticleThickness: number?, -- default 2px
	ReticleType: ReticleName?, -- default "Crosshair"
	SwayIntensity: number?, -- pixels of breathing drift, default 3
	BreathSpeed: number?, -- radians/sec, default 1.4
	ZoomedFOV: number?, -- Camera.FieldOfView while scoped, default 15
	ZoomTweenTime: number?, -- default 0.25
}

export type ScopeUIAPI = {
	Show: (self: ScopeUIAPI) -> (),
	Hide: (self: ScopeUIAPI) -> (),
	IsVisible: (self: ScopeUIAPI) -> boolean,
	SetSwayOffset: (self: ScopeUIAPI, offset: Vector2) -> (),
	SetZoomFOV: (self: ScopeUIAPI, fov: number) -> (),
	SetReticle: (self: ScopeUIAPI, name: ReticleName) -> (),
	GetReticle: (self: ScopeUIAPI) -> ReticleName,
	Destroy: (self: ScopeUIAPI) -> (),
}

----------------------------------------------------------------------
-- Reticle drawing primitives
-- All positions are scale-based (0-1 within the circular ReticleHolder)
-- and all thicknesses are pixel-based, so line weight stays constant
-- regardless of lens size while layout stays proportional.
----------------------------------------------------------------------

local function hline(holder: Frame, color: Color3, thicknessPx: number, fromScale: number, toScale: number, yScale: number): Frame
	if fromScale > toScale then
		fromScale, toScale = toScale, fromScale
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.new(toScale - fromScale, 0, 0, thicknessPx)
	f.Position = UDim2.fromScale(fromScale, yScale)
	f.AnchorPoint = Vector2.new(0, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.Parent = holder
	return f
end

local function vline(holder: Frame, color: Color3, thicknessPx: number, fromScale: number, toScale: number, xScale: number): Frame
	if fromScale > toScale then
		fromScale, toScale = toScale, fromScale
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, thicknessPx, toScale - fromScale, 0)
	f.Position = UDim2.fromScale(xScale, fromScale)
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.Parent = holder
	return f
end

local function dot(holder: Frame, color: Color3, diameterPx: number, xScale: number, yScale: number): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(diameterPx, diameterPx)
	f.Position = UDim2.fromScale(xScale, yScale)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	f.Parent = holder
	return f
end

local function ring(holder: Frame, color: Color3, diameterScale: number, thicknessPx: number, xScale: number, yScale: number): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(diameterScale, diameterScale)
	f.Position = UDim2.fromScale(xScale, yScale)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundTransparency = 1
	f.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thicknessPx
	stroke.Parent = f
	f.Parent = holder
	return f
end

local function square(holder: Frame, color: Color3, sizeScale: number, thicknessPx: number, xScale: number, yScale: number, rotationDeg: number?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(sizeScale, sizeScale)
	f.Position = UDim2.fromScale(xScale, yScale)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Rotation = rotationDeg or 0
	f.BackgroundTransparency = 1
	f.ZIndex = 2
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thicknessPx
	stroke.Parent = f
	f.Parent = holder
	return f
end

-- Pivots at (xScale, yScale) and extends lengthPx in the rotated
-- direction — used for chevrons, brackets, and any angled segment.
local function angledLine(holder: Frame, color: Color3, lengthPx: number, thicknessPx: number, xScale: number, yScale: number, rotationDeg: number, anchorX: number?, anchorY: number?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(lengthPx, thicknessPx)
	f.AnchorPoint = Vector2.new(anchorX or 0, anchorY or 0.5)
	f.Position = UDim2.fromScale(xScale, yScale)
	f.Rotation = rotationDeg
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.Parent = holder
	return f
end

-- An "L" shaped corner mark, used by bracket-style reticles.
local function cornerBracket(holder: Frame, color: Color3, thicknessPx: number, cx: number, cy: number, lenScale: number, dirX: number, dirY: number)
	hline(holder, color, thicknessPx, cx, cx + dirX * lenScale, cy)
	vline(holder, color, thicknessPx, cy, cy + dirY * lenScale, cx)
end

----------------------------------------------------------------------
-- Reticle presets — 20 unique designs.
-- Each entry: function(holder: Frame, color: Color3, thicknessPx: number)
----------------------------------------------------------------------

local Reticles: { [ReticleName]: ReticleBuilder } = {}

-- 1. Classic gapped duplex-free crosshair with a small center dot.
Reticles["Crosshair"] = function(h, c, t)
	hline(h, c, t, 0, 0.46, 0.5)
	hline(h, c, t, 0.54, 1, 0.5)
	vline(h, c, t, 0, 0.46, 0.5)
	vline(h, c, t, 0.54, 1, 0.5)
	dot(h, c, t + 2, 0.5, 0.5)
end

-- 2. Ultra-thin full-length precision crosshair, no gap, no dot.
Reticles["Fine Crosshair"] = function(h, c, t)
	hline(h, c, 1, 0, 1, 0.5)
	vline(h, c, 1, 0, 1, 0.5)
end

-- 3. Crosshair with mil-dot ranging dots along each axis.
Reticles["Mil-Dot"] = function(h, c, t)
	Reticles["Crosshair"](h, c, t)
	for _, s in ipairs({ 0.62, 0.72, 0.82 }) do
		dot(h, c, 4, s, 0.5)
		dot(h, c, 4, 1 - s, 0.5)
		dot(h, c, 4, 0.5, s)
		dot(h, c, 4, 0.5, 1 - s)
	end
end

-- 4. Thick outer posts tapering to a thin center cross.
Reticles["Duplex"] = function(h, c, t)
	hline(h, c, t * 3, 0, 0.35, 0.5)
	hline(h, c, t * 3, 0.65, 1, 0.5)
	hline(h, c, t, 0.35, 0.46, 0.5)
	hline(h, c, t, 0.54, 0.65, 0.5)
	vline(h, c, t * 3, 0, 0.35, 0.5)
	vline(h, c, t * 3, 0.65, 1, 0.5)
	vline(h, c, t, 0.35, 0.46, 0.5)
	vline(h, c, t, 0.54, 0.65, 0.5)
	dot(h, c, t + 2, 0.5, 0.5)
end

-- 5. German #4 style: thick left/right/bottom posts, fine open top.
Reticles["German #4"] = function(h, c, t)
	hline(h, c, t * 3, 0, 0.4, 0.5)
	hline(h, c, t * 3, 0.6, 1, 0.5)
	vline(h, c, t, 0, 0.55, 0.5)
	vline(h, c, t * 3, 0.6, 1, 0.5)
	dot(h, c, t + 2, 0.5, 0.5)
end

-- 6. Simple upward chevron (^) with a small apex dot.
Reticles["Chevron"] = function(h, c, t)
	angledLine(h, c, 55, t, 0.5, 0.55, 135, 0, 0.5)
	angledLine(h, c, 55, t, 0.5, 0.55, 45, 0, 0.5)
	dot(h, c, t + 1, 0.5, 0.55)
end

-- 7. Nothing but a single center aim point.
Reticles["Center Dot"] = function(h, c, t)
	dot(h, c, t + 3, 0.5, 0.5)
end

-- 8. Center dot inside a ranging ring, no crosshair lines.
Reticles["Circle Dot"] = function(h, c, t)
	dot(h, c, t + 3, 0.5, 0.5)
	ring(h, c, 0.3, t, 0.5, 0.5)
end

-- 9. Crosshair with a bullet-drop-compensator hash ladder below center.
Reticles["BDC Ladder"] = function(h, c, t)
	Reticles["Crosshair"](h, c, t)
	for _, s in ipairs({ 0.58, 0.66, 0.74, 0.82 }) do
		hline(h, c, t, 0.45, 0.55, s)
	end
end

-- 10. Open "U" bracket beneath a center dot (fast CQB acquisition).
Reticles["Horseshoe Dot"] = function(h, c, t)
	vline(h, c, t, 0.3, 0.7, 0.35)
	vline(h, c, t, 0.3, 0.7, 0.65)
	hline(h, c, t, 0.35, 0.65, 0.7)
	dot(h, c, t + 2, 0.5, 0.5)
end

-- 11. Full crosshair enclosed in a ranging circle.
Reticles["Cross Circle"] = function(h, c, t)
	Reticles["Crosshair"](h, c, t)
	ring(h, c, 0.6, t, 0.5, 0.5)
end

-- 12. Four corner brackets framing an open center dot (no full lines).
Reticles["Corner Brackets"] = function(h, c, t)
	local len = 0.15
	cornerBracket(h, c, t, 0.2, 0.2, len, 1, 1)
	cornerBracket(h, c, t, 0.8, 0.2, len, -1, 1)
	cornerBracket(h, c, t, 0.2, 0.8, len, 1, -1)
	cornerBracket(h, c, t, 0.8, 0.8, len, -1, -1)
	dot(h, c, t + 1, 0.5, 0.5)
end

-- 13. Plex-style crosshair: medium thick posts, thin waist, open center.
Reticles["Plex"] = function(h, c, t)
	hline(h, c, t * 2, 0, 0.3, 0.5)
	hline(h, c, t * 2, 0.7, 1, 0.5)
	hline(h, c, t, 0.3, 0.46, 0.5)
	hline(h, c, t, 0.54, 0.7, 0.5)
	vline(h, c, t * 2, 0, 0.3, 0.5)
	vline(h, c, t * 2, 0.7, 1, 0.5)
	vline(h, c, t, 0.3, 0.46, 0.5)
	vline(h, c, t, 0.54, 0.7, 0.5)
end

-- 14. A single thick ring, no lines — fast mid-range aim reference.
Reticles["Donut Ring"] = function(h, c, t)
	ring(h, c, 0.4, t * 2, 0.5, 0.5)
end

-- 15. Three dots forming a small triangle around the center point.
Reticles["Tri-Dot"] = function(h, c, t)
	dot(h, c, 5, 0.5, 0.35)
	dot(h, c, 5, 0.4, 0.6)
	dot(h, c, 5, 0.6, 0.6)
	dot(h, c, t + 1, 0.5, 0.5)
end

-- 16. Diamond outline (rotated square) around a center dot.
Reticles["Diamond"] = function(h, c, t)
	square(h, c, 0.28, t, 0.5, 0.5, 45)
	dot(h, c, t + 1, 0.5, 0.5)
end

-- 17. Crosshair with a fine mil-grid of tick lines for holdover/windage.
Reticles["Mil Grid"] = function(h, c, t)
	Reticles["Crosshair"](h, c, t)
	for _, s in ipairs({ 0.35, 0.65 }) do
		vline(h, c, 1, 0, 1, s)
		hline(h, c, 1, 0, 1, s)
	end
end

-- 18. ACOG-style chevron with horizontal ranging stadia beneath it.
Reticles["ACOG Chevron"] = function(h, c, t)
	Reticles["Chevron"](h, c, t)
	for _, s in ipairs({ 0.62, 0.7, 0.78 }) do
		hline(h, c, t, 0.46, 0.54, s)
	end
end

-- 19. Vertical stadia line with horizontal range-estimation ticks.
Reticles["Range Stadia"] = function(h, c, t)
	vline(h, c, t, 0, 1, 0.5)
	for _, s in ipairs({ 0.3, 0.4, 0.6, 0.7 }) do
		hline(h, c, t, 0.45, 0.55, s)
	end
	dot(h, c, t + 2, 0.5, 0.5)
end

-- 20. Large open circle with a center dot — fast close-quarters reticle.
Reticles["Battle Circle"] = function(h, c, t)
	ring(h, c, 0.55, t, 0.5, 0.5)
	dot(h, c, t + 2, 0.5, 0.5)
end

-- Ordered list (Lua dictionaries have no guaranteed order) for building
-- pickers/attachment menus.
ScopeUI.ReticleNames = {
	"Crosshair",
	"Fine Crosshair",
	"Mil-Dot",
	"Duplex",
	"German #4",
	"Chevron",
	"Center Dot",
	"Circle Dot",
	"BDC Ladder",
	"Horseshoe Dot",
	"Cross Circle",
	"Corner Brackets",
	"Plex",
	"Donut Ring",
	"Tri-Dot",
	"Diamond",
	"Mil Grid",
	"ACOG Chevron",
	"Range Stadia",
	"Battle Circle",
} :: { ReticleName }

function ScopeUI.new(props: ScopeUIProps?): ScopeUIAPI
	local config = props or {}
	local sizeFraction = config.ScopeSizeFraction or 0.9
	local vignetteColor = config.VignetteColor or Color3.new(0, 0, 0)
	local reticleColor = config.ReticleColor or Color3.fromRGB(60, 230, 100)
	local reticleThickness = config.ReticleThickness or 2
	local swayIntensity = config.SwayIntensity or 3
	local breathSpeed = config.BreathSpeed or 1.4
	local zoomedFOV = config.ZoomedFOV or 15
	local zoomTweenTime = config.ZoomTweenTime or 0.25
	local camera = config.Camera or workspace.CurrentCamera

	local localPlayer = Players.LocalPlayer
	local parent = config.Parent or (localPlayer and localPlayer:WaitForChild("PlayerGui"))

	local defaultFOV = if camera then camera.FieldOfView else 70

	----------------------------------------------------------------
	-- Root ScreenGui
	----------------------------------------------------------------
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ScopeUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 50
	screenGui.Enabled = false
	screenGui.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	-- Bars fill the leftover space around the centered circle so the
	-- lens is always a true 1:1 circle regardless of screen aspect ratio.
	local barLeft = Instance.new("Frame")
	barLeft.Name = "BarLeft"
	barLeft.BackgroundColor3 = vignetteColor
	barLeft.BorderSizePixel = 0
	barLeft.Parent = root

	local barRight = Instance.new("Frame")
	barRight.Name = "BarRight"
	barRight.BackgroundColor3 = vignetteColor
	barRight.BorderSizePixel = 0
	barRight.AnchorPoint = Vector2.new(1, 0)
	barRight.Parent = root

	local barTop = Instance.new("Frame")
	barTop.Name = "BarTop"
	barTop.BackgroundColor3 = vignetteColor
	barTop.BorderSizePixel = 0
	barTop.Parent = root

	local barBottom = Instance.new("Frame")
	barBottom.Name = "BarBottom"
	barBottom.BackgroundColor3 = vignetteColor
	barBottom.BorderSizePixel = 0
	barBottom.AnchorPoint = Vector2.new(0, 1)
	barBottom.Parent = root

	-- Circular lens with a thick matching-color stroke so its edge
	-- blends seamlessly into the bars.
	local lens = Instance.new("Frame")
	lens.Name = "Lens"
	lens.AnchorPoint = Vector2.new(0.5, 0.5)
	lens.Position = UDim2.fromScale(0.5, 0.5)
	lens.BackgroundTransparency = 1
	lens.Parent = root

	local lensAspect = Instance.new("UIAspectRatioConstraint")
	lensAspect.AspectRatio = 1
	lensAspect.Parent = lens

	local lensCorner = Instance.new("UICorner")
	lensCorner.CornerRadius = UDim.new(1, 0)
	lensCorner.Parent = lens

	local lensStroke = Instance.new("UIStroke")
	lensStroke.Color = vignetteColor
	lensStroke.Thickness = 100
	lensStroke.Parent = lens

	----------------------------------------------------------------
	-- Reticle: swappable procedural design, always clipped to a
	-- perfect circle regardless of what it draws. Lives inside the
	-- lens and drifts with breathing sway.
	----------------------------------------------------------------
	local reticleHolder = Instance.new("Frame")
	reticleHolder.Name = "ReticleHolder"
	reticleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	reticleHolder.Position = UDim2.fromScale(0.5, 0.5)
	reticleHolder.Size = UDim2.fromScale(1, 1)
	reticleHolder.BackgroundTransparency = 1
	reticleHolder.ClipsDescendants = true -- guarantees a circular outer edge for every reticle
	reticleHolder.ZIndex = 2
	reticleHolder.Parent = lens

	local reticleHolderCorner = Instance.new("UICorner")
	reticleHolderCorner.CornerRadius = UDim.new(1, 0)
	reticleHolderCorner.Parent = reticleHolder

	local currentReticleName: ReticleName = "Crosshair"

	-- Takes a plain string (not ReticleName) so runtime-sourced input —
	-- a datastore value, a GUI dropdown, a net message — that bypasses
	-- the type checker still gets validated and safely falls back
	-- instead of indexing Reticles with a bad key.
	local function buildReticle(name: string)
		local validName = (Reticles[name :: ReticleName] and name :: ReticleName) or nil
		if not validName then
			warn(("ScopeUI: unknown ReticleType '%s', falling back to 'Crosshair'. Valid names are in ScopeUI.ReticleNames."):format(tostring(name)))
			validName = "Crosshair"
		end
		for _, child in reticleHolder:GetChildren() do
			child:Destroy()
		end
		Reticles[validName](reticleHolder, reticleColor, reticleThickness)
		currentReticleName = validName
	end

	buildReticle(config.ReticleType or "Crosshair")

	----------------------------------------------------------------
	-- Layout: recompute lens + bar sizes whenever the viewport
	-- changes, keeping the lens a perfect circle.
	----------------------------------------------------------------
	local function relayout()
		local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
		local diameter = math.min(viewport.X, viewport.Y) * sizeFraction

		lens.Size = UDim2.fromOffset(diameter, diameter)

		local leftoverX = math.max(0, (viewport.X - diameter) / 2)
		local leftoverY = math.max(0, (viewport.Y - diameter) / 2)

		barLeft.Size = UDim2.new(0, leftoverX, 1, 0)
		barLeft.Position = UDim2.fromScale(0, 0)

		barRight.Size = UDim2.new(0, leftoverX, 1, 0)
		barRight.Position = UDim2.fromScale(1, 0)

		barTop.Size = UDim2.new(1, 0, 0, leftoverY)
		barTop.Position = UDim2.fromScale(0, 0)

		barBottom.Size = UDim2.new(1, 0, 0, leftoverY)
		barBottom.Position = UDim2.fromScale(0, 1)
	end

	relayout()

	local connections: { RBXScriptConnection } = {}
	if camera then
		table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout))
	end

	----------------------------------------------------------------
	-- Breathing sway + external sway offset (drive from recoil,
	-- hold-breath, movement penalty, etc).
	----------------------------------------------------------------
	local visible = false
	local externalOffset = Vector2.new(0, 0)
	local swayTime = 0

	table.insert(connections, RunService.RenderStepped:Connect(function(dt: number)
		if not visible then return end
		swayTime += dt * breathSpeed
		local breathOffset = Vector2.new(
			math.sin(swayTime) * swayIntensity,
			math.cos(swayTime * 0.7) * swayIntensity * 0.6
		)
		local totalOffset = breathOffset + externalOffset
		reticleHolder.Position = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(totalOffset.X, totalOffset.Y)
	end))

	----------------------------------------------------------------
	-- Public API
	----------------------------------------------------------------
	local api = {} :: ScopeUIAPI

	function api:Show()
		if visible then return end
		visible = true
		relayout()
		screenGui.Enabled = true
		if camera then
			TweenService:Create(
				camera,
				TweenInfo.new(zoomTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = zoomedFOV }
			):Play()
		end
	end

	function api:Hide()
		if not visible then return end
		visible = false
		screenGui.Enabled = false
		if camera then
			TweenService:Create(
				camera,
				TweenInfo.new(zoomTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = defaultFOV }
			):Play()
		end
	end

	function api:IsVisible(): boolean
		return visible
	end

	function api:SetSwayOffset(offset: Vector2)
		externalOffset = offset
	end

	function api:SetZoomFOV(fov: number)
		zoomedFOV = fov
		if visible and camera then
			TweenService:Create(
				camera,
				TweenInfo.new(zoomTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = fov }
			):Play()
		end
	end

	function api:SetReticle(name: ReticleName)
		buildReticle(name)
	end

	function api:GetReticle(): ReticleName
		return currentReticleName
	end

	function api:Destroy()
		for _, conn in connections do
			conn:Disconnect()
		end
		screenGui:Destroy()
	end

	return api
end

return ScopeUI