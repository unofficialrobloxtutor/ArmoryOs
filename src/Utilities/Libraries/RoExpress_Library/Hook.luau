------------------------------------------------------------------------
--  <> Title:       RoExpress.Hook
--  <> Version:     1.0
--  <> Date:        15/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Priority-ordered event dispatcher wrapping every
--                  Roblox built-in signal plus a custom event bus.
--
--  USAGE
--  ---------------------------------------------------------------
--  local Hook = RoExpress.Hook
--
--  -- Subscribe (priority: number | "first"|"high"|"normal"|"low"|"last")
--  Hook("PlayerAdded", 10, function(player) end)
--  Hook("PlayerAdded", "high", function(player) end)
--  Hook("PlayerAdded", function(player) end)            -- default priority 50
--
--  -- Named handler (removable)
--  Hook("PlayerRemoving", { priority = 1, id = "save" }, function(player)
--      DataStore:Save(player)
--  end)
--  Hook.Off("PlayerRemoving", "save")
--
--  -- Once
--  Hook.Once("PlayerAdded", 10, function(player) end)
--
--  -- Custom events
--  Hook.Fire("round.start", { map = "Forest" })
--  Hook("round.start", 10, function(data) end)
--
--  -- CollectionService (parameterised)
--  Hook("TagAdded:Enemy",   10, function(instance) end)
--  Hook("TagRemoved:Enemy", 10, function(instance) end)
--
--  -- Per-player character events (player passed as first arg)
--  Hook("CharacterAdded", 10, function(player, character) end)
--
--  PRIORITY
--  ---------------------------------------------------------------
--  Lower number = runs first. Named aliases:
--    "first"  = 0   |  "high"   = 25  |  "normal" = 50
--    "low"    = 75  |  "last"   = 100
------------------------------------------------------------------------

local RunService         = game:GetService("RunService")
local Players            = game:GetService("Players")
local CollectionService  = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService   = game:GetService("UserInputService")
local TeleportService    = game:GetService("TeleportService")
local SocialService      = game:GetService("SocialService")
local Lighting           = game:GetService("Lighting")

local TextChatService; pcall(function() TextChatService = game:GetService("TextChatService") end)
local VoiceChatService;  pcall(function() VoiceChatService  = game:GetService("VoiceChatService")  end)
local GuiService;        pcall(function() GuiService        = game:GetService("GuiService")         end)

local IS_SERVER = RunService:IsServer()

------------------------------------------------------------------------
--  TYPES
------------------------------------------------------------------------
type Entry = {
	priority : number,
	id       : string?,
	fn       : (...any) -> (),
	once     : boolean,
}

------------------------------------------------------------------------
--  PRIORITY ALIASES
------------------------------------------------------------------------
local ALIAS: { [string]: number } = {
	first  = 0,
	high   = 25,
	normal = 50,
	low    = 75,
	last   = 100,
}

------------------------------------------------------------------------
--  SIGNAL MAP  (key → getter returning RBXScriptSignal)
------------------------------------------------------------------------
local SIGNAL_MAP: { [string]: () -> RBXScriptSignal? } = {
	-- Players
	PlayerAdded                         = function() return Players.PlayerAdded end,
	PlayerRemoving                      = function() return Players.PlayerRemoving end,
	PlayerMembershipChanged             = function() return Players.PlayerMembershipChanged end,

	-- RunService
	Heartbeat                           = function() return RunService.Heartbeat end,
	Stepped                             = function() return RunService.Stepped end,
	PostSimulation                      = function() return RunService.PostSimulation end,
	PreAnimation                        = function() return RunService.PreAnimation end,
	PostAnimation                       = function() return RunService.PostAnimation end,
	RenderStepped                       = function() return if not IS_SERVER then RunService.RenderStepped else nil end,
	PreRender                           = function() return if not IS_SERVER then RunService.PreRender    else nil end,

	-- UserInputService (client only)
	InputBegan                          = function() return if not IS_SERVER then UserInputService.InputBegan                else nil end,
	InputChanged                        = function() return if not IS_SERVER then UserInputService.InputChanged              else nil end,
	InputEnded                          = function() return if not IS_SERVER then UserInputService.InputEnded                else nil end,
	JumpRequest                         = function() return if not IS_SERVER then UserInputService.JumpRequest               else nil end,
	GamepadConnected                    = function() return if not IS_SERVER then UserInputService.GamepadConnected          else nil end,
	GamepadDisconnected                 = function() return if not IS_SERVER then UserInputService.GamepadDisconnected       else nil end,
	WindowFocused                       = function() return if not IS_SERVER then UserInputService.WindowFocused             else nil end,
	WindowFocusReleased                 = function() return if not IS_SERVER then UserInputService.WindowFocusReleased       else nil end,
	TouchStarted                        = function() return if not IS_SERVER then UserInputService.TouchStarted              else nil end,
	TouchMoved                          = function() return if not IS_SERVER then UserInputService.TouchMoved                else nil end,
	TouchEnded                          = function() return if not IS_SERVER then UserInputService.TouchEnded                else nil end,
	TouchTap                            = function() return if not IS_SERVER then UserInputService.TouchTap                  else nil end,
	TouchLongPress                      = function() return if not IS_SERVER then UserInputService.TouchLongPress            else nil end,
	TouchSwipe                          = function() return if not IS_SERVER then UserInputService.TouchSwipe                else nil end,
	TouchPinch                          = function() return if not IS_SERVER then UserInputService.TouchPinch                else nil end,
	TouchRotate                         = function() return if not IS_SERVER then UserInputService.TouchRotate               else nil end,
	DeviceAccelerationChanged           = function() return if not IS_SERVER then UserInputService.DeviceAccelerationChanged else nil end,
	DeviceGravityChanged                = function() return if not IS_SERVER then UserInputService.DeviceGravityChanged      else nil end,
	DeviceRotationChanged               = function() return if not IS_SERVER then UserInputService.DeviceRotationChanged     else nil end,
	PointerAction                       = function() return if not IS_SERVER then UserInputService.PointerAction             else nil end,

	-- MarketplaceService
	PromptPurchaseFinished              = function() return MarketplaceService.PromptPurchaseFinished end,
	PromptGamePassPurchaseFinished      = function() return MarketplaceService.PromptGamePassPurchaseFinished end,
	PromptBundlePurchaseFinished        = function() return MarketplaceService.PromptBundlePurchaseFinished end,
	PromptSubscriptionPurchaseFinished  = function() return MarketplaceService.PromptSubscriptionPurchaseFinished end,

	-- TeleportService
	TeleportInitFailed                  = function() return TeleportService.TeleportInitFailed end,
	LocalPlayerArrivedFromTeleport      = function() return if not IS_SERVER then TeleportService.LocalPlayerArrivedFromTeleport else nil end,

	-- SocialService
	GameInvitePromptClosed              = function() return SocialService.GameInvitePromptClosed end,
	PromptInviteRequested               = function() return SocialService.PromptInviteRequested end,

	-- GuiService (client)
	MenuOpened                          = function() return if GuiService and not IS_SERVER then GuiService.MenuOpened                else nil end,
	MenuClosed                          = function() return if GuiService and not IS_SERVER then GuiService.MenuClosed                else nil end,
	KeyboardVisibilityChanged           = function() return if GuiService and not IS_SERVER then GuiService.KeyboardVisibilityChanged else nil end,

	-- TextChatService
	MessageReceived                     = function() return if TextChatService then TextChatService.MessageReceived else nil end,
	SendingMessage                      = function() return if TextChatService then TextChatService.SendingMessage  else nil end,

	-- VoiceChatService
	ParticipantsStateChanged            = function() return if VoiceChatService then VoiceChatService.ParticipantsStateChanged      else nil end,
	PlayerMicActivitySignalChange       = function() return if VoiceChatService then VoiceChatService.PlayerMicActivitySignalChange  else nil end,

	-- Game / Lighting
	Close                               = function() return game.Close end,
	DescendantAdded                     = function() return game.DescendantAdded end,
	DescendantRemoving                  = function() return game.DescendantRemoving end,
	LightingChanged                     = function() return Lighting.LightingChanged end,
}

-- Per-player signals — wired through PlayerAdded, player passed as first arg
local PER_PLAYER: { [string]: string } = {
	CharacterAdded            = "CharacterAdded",
	CharacterRemoving         = "CharacterRemoving",
	CharacterAppearanceLoaded = "CharacterAppearanceLoaded",
}

------------------------------------------------------------------------
--  INTERNAL STATE
------------------------------------------------------------------------
local _handlers:    { [string]: { Entry } }                          = {}
local _connected:   { [string]: boolean }                            = {}
local _playerConns: { [Player]: { [string]: RBXScriptConnection } }  = {}

------------------------------------------------------------------------
--  PRIVATE HELPERS
------------------------------------------------------------------------
local function _resolvePriority(p: (number | string)?): number
	if p == nil then return 50 end
	if type(p) == "string" then return ALIAS[p] or 50 end
	return (p :: number)
end

local function _insertSorted(list: { Entry }, entry: Entry)
	local lo, hi = 1, #list
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		if list[mid].priority <= entry.priority then lo = mid + 1 else hi = mid - 1 end
	end
	table.insert(list, lo, entry)
end

local function _dispatch(key: string, ...: any)
	local list = _handlers[key]
	if not list or #list == 0 then return end
	local i = 1
	while i <= #list do
		local entry = list[i]
		local ok, err = pcall(entry.fn, ...)
		if not ok then
			warn("[RoExpress.Hook] Error in '" .. key .. "' handler: " .. tostring(err))
		end
		if entry.once then table.remove(list, i) else i += 1 end
	end
end

local function _ensureList(key: string): { Entry }
	if not _handlers[key] then _handlers[key] = {} end
	return _handlers[key]
end

local function _wirePlayer(player: Player)
	if not _playerConns[player] then _playerConns[player] = {} end
	for key, sigName in PER_PLAYER do
		if _handlers[key] and #_handlers[key] > 0 then
			if not _playerConns[player][key] then
				_playerConns[player][key] = (player :: any)[sigName]:Connect(function(...)
					_dispatch(key, player, ...)
				end)
			end
		end
	end
end

local function _connectNative(key: string)
	if _connected[key] then return end
	_connected[key] = true

	-- CollectionService parameterised signals
	if key:sub(1, 9) == "TagAdded:" then
		local tag = key:sub(10)
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			_dispatch(key, inst)
		end)
		return
	end
	if key:sub(1, 11) == "TagRemoved:" then
		local tag = key:sub(12)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
			_dispatch(key, inst)
		end)
		return
	end

	-- Per-player events
	if PER_PLAYER[key] then
		local sigName = PER_PLAYER[key]
		-- wire existing players
		for _, player in Players:GetPlayers() do
			if not _playerConns[player] then _playerConns[player] = {} end
			_playerConns[player][key] = (player :: any)[sigName]:Connect(function(...)
				_dispatch(key, player, ...)
			end)
		end
		-- wire future players (one shared PlayerAdded listener)
		if not _connected["__playerWired"] then
			_connected["__playerWired"] = true
			Players.PlayerAdded:Connect(_wirePlayer)
			Players.PlayerRemoving:Connect(function(player)
				if _playerConns[player] then
					for _, conn in _playerConns[player] do conn:Disconnect() end
					_playerConns[player] = nil
				end
			end)
		end
		return
	end

	-- Standard mapped signal
	local getter = SIGNAL_MAP[key]
	if not getter then return end  -- custom event — no native signal to connect
	local signal = getter()
	if not signal then
		warn("[RoExpress.Hook] Signal '" .. key .. "' is not available in this context")
		return
	end
	signal:Connect(function(...) _dispatch(key, ...) end)
end

------------------------------------------------------------------------
--  PUBLIC API
------------------------------------------------------------------------
local Hook = {}

-- Hook(event, priority?, handler)   or   Hook(event, { priority?, id? }, handler)
setmetatable(Hook, {
	__call = function(_, event: string, priorityOrOpts: any, handlerArg: ((...any) -> ())?)
		local priority: number
		local id: string?
		local fn: (...any) -> ()

		if type(priorityOrOpts) == "function" then
			priority, fn = 50, priorityOrOpts
		elseif type(priorityOrOpts) == "table" then
			priority = _resolvePriority(priorityOrOpts.priority)
			id = priorityOrOpts.id
			fn = handlerArg :: (...any) -> ()
		else
			priority = _resolvePriority(priorityOrOpts)
			fn = handlerArg :: (...any) -> ()
		end

		assert(type(fn) == "function", "[RoExpress.Hook] handler must be a function")
		_insertSorted(_ensureList(event), { priority = priority, id = id, fn = fn, once = false })
		_connectNative(event)
	end,
})

-- Hook.Once(event, priority?, handler)
function Hook.Once(event: string, priorityOrHandler: any, handlerArg: ((...any) -> ())?)
	local priority: number
	local fn: (...any) -> ()

	if type(priorityOrHandler) == "function" then
		priority, fn = 50, priorityOrHandler
	else
		priority = _resolvePriority(priorityOrHandler)
		fn = handlerArg :: (...any) -> ()
	end

	assert(type(fn) == "function", "[RoExpress.Hook] handler must be a function")
	_insertSorted(_ensureList(event), { priority = priority, id = nil, fn = fn, once = true })
	_connectNative(event)
end

-- Hook.Off(event, id) — remove all handlers with the given id
function Hook.Off(event: string, id: string)
	local list = _handlers[event]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i].id == id then table.remove(list, i) end
	end
end

-- Hook.Clear(event) — remove every handler for an event
function Hook.Clear(event: string)
	_handlers[event] = {}
end

-- Hook.Fire(event, ...) — dispatch a custom event
function Hook.Fire(event: string, ...: any)
	_dispatch(event, ...)
end

-- Hook.Has(event) — true if at least one handler is registered
function Hook.Has(event: string): boolean
	local list = _handlers[event]
	return list ~= nil and #list > 0
end

return Hook
