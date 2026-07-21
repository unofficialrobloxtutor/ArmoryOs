--!strict
--[[
	Modal
	==================================================================
	Backdrop + centered Panel that scales/fades in and out. Click
	outside the panel or the close button to dismiss.
==================================================================
]]

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.Theme)
local Format = require(script.Parent.Parent.Parent.Libraries.Format_Library)
local Panel = require(script.Parent.Panel)
local Button = require(script.Parent.Button)

local Modal = {}

export type ModalProps = {
	Parent: Instance,
	Size: UDim2?,
	Title: string?,
	ShowCloseButton: boolean?,
	CloseOnBackdropClick: boolean?,
	OnClosed: (() -> ())?,
}

export type ModalAPI = {
	Open: (self: ModalAPI) -> (),
	Close: (self: ModalAPI) -> (),
	IsOpen: (self: ModalAPI) -> boolean,
	GetContentFrame: (self: ModalAPI) -> Frame,
	Destroy: (self: ModalAPI) -> (),
}

function Modal.new(props: ModalProps): (Frame, ModalAPI)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "ModalBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.ZIndex = 10
	backdrop.Parent = props.Parent

	local panelInstance, panelAPI = Panel.new({
		Size = props.Size or UDim2.fromOffset(420, 300),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Title = props.Title,
		Parent = backdrop,
	})
	panelInstance.ZIndex = 11

	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = panelInstance

	local connections: { RBXScriptConnection } = {}
	local isOpen = false

	-- forward-declared so the close button (and backdrop click) can call it
	local close: () -> ()

	local function open()
		if isOpen then return end
		isOpen = true
		backdrop.Visible = true
		TweenService:Create(backdrop, Format.TweenInfo_Simple(0.15), { BackgroundTransparency = 0.4 }):Play()
		TweenService:Create(scale, Format.TweenInfo_Bouncy(0.22), { Scale = 1 }):Play()
	end

	close = function()
		if not isOpen then return end
		isOpen = false
		local fadeTween = TweenService:Create(backdrop, Format.TweenInfo_Simple(0.15), { BackgroundTransparency = 1 })
		local shrinkTween = TweenService:Create(scale, Format.TweenInfo_Simple(0.15), { Scale = 0.85 })
		fadeTween:Play()
		shrinkTween:Play()

		local conn: RBXScriptConnection
		conn = shrinkTween.Completed:Connect(function()
			conn:Disconnect()
			backdrop.Visible = false
		end)

		if props.OnClosed then
			props.OnClosed()
		end
	end

	if props.ShowCloseButton ~= false then
		local closeButtonInstance = Button.new({
			Text = "X",
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -8, 0, 8),
			AnchorPoint = Vector2.new(1, 0),
			Variant = "Danger",
			Parent = panelInstance,
			OnClick = function()
				close()
			end,
		})
		closeButtonInstance.ZIndex = 12
	end

	if props.CloseOnBackdropClick ~= false then
		table.insert(connections, backdrop.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local mousePos = input.Position
			local panelPos = panelInstance.AbsolutePosition
			local panelSize = panelInstance.AbsoluteSize
			local insidePanel = mousePos.X >= panelPos.X and mousePos.X <= panelPos.X + panelSize.X
				and mousePos.Y >= panelPos.Y and mousePos.Y <= panelPos.Y + panelSize.Y
			if not insidePanel then
				close()
			end
		end))
	end

	local api = {} :: ModalAPI

	function api:Open()
		open()
	end

	function api:Close()
		close()
	end

	function api:IsOpen(): boolean
		return isOpen
	end

	function api:GetContentFrame(): Frame
		return panelAPI:GetContentFrame()
	end

	function api:Destroy()
		for _, conn in connections do
			conn:Disconnect()
		end
		panelAPI:Destroy()
		backdrop:Destroy()
	end

	return backdrop, api
end

return Modal