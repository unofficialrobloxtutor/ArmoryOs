------------------------------------------------------------------------
--  <> Title:       RoExpress.Types
--  <> Version:     1.0
--  <> Date:        15/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Explicit public-facing types for every RoExpress
--                  module. No private fields, no __index leakage.
--
--  USAGE
--  ---------------------------------------------------------------
--  Types are re-exported from the root module so you can annotate
--  variables directly after requiring RoExpress:
--
--    local RoExpress = require(game.ReplicatedStorage.RoExpress)
--    local app: RoExpress.App = RoExpress.GetApp()
--
--  Or require this module directly for sub-module annotation:
--
--    local T = require(game.ReplicatedStorage.RoExpress.Types)
--    type Handler = (data: any) -> ()
------------------------------------------------------------------------

-- ── Primitives ─────────────────────────────────────────────────────────

export type Method = "GET" | "POST" | "PUT" | "DELETE"

export type RouteOptions = {
	compress : boolean?,
	algo     : ("lz77" | "lzh")?,
}

-- ── App / Port ─────────────────────────────────────────────────────────

export type Payload = {
	version   : string,
	type      : "request" | "response" | "error",
	method    : Method,
	requestId : string,
	route     : string,
	data      : any,
}

export type Request = {
	params   : { [string]: any },
	captures : { any },
	query    : { [string]: string },
	data     : any,
	player   : Player?,
	raw      : Payload?,
}

export type Response = {
	Send     : (self: Response, data: any?) -> (),
	Error    : (self: Response, message: string) -> (),
	Status   : (self: Response, code: number) -> Response,
	Redirect : (self: Response, path: string) -> (),
}

export type RouteHandlerCompact = (req: Request, res: Response) -> ()
export type RouteHandlerLegacy  = (Player: Player, Payload: Payload, req: Request, res: Response) -> ()
export type RouteHandler        = RouteHandlerCompact | RouteHandlerLegacy
export type MiddlewareHandler   = (Player: Player, Payload: Payload) -> boolean?

export type ParamErrorHandler = (Player: Player, Payload: Payload, paramName: string, expectedType: string) -> ()

export type Port = {
	Get          : (self: Port, route: string, handler: (req: Request, res: Response) -> (), options: RouteOptions?) -> (),
	Post         : (self: Port, route: string, handler: (req: Request, res: Response) -> (), options: RouteOptions?) -> (),
	Put          : (self: Port, route: string, handler: (req: Request, res: Response) -> (), options: RouteOptions?) -> (),
	Delete       : (self: Port, route: string, handler: (req: Request, res: Response) -> (), options: RouteOptions?) -> (),
	Use          : (self: Port, id: string, fn: MiddlewareHandler) -> (),
	Unuse        : (self: Port, id: string) -> (),
	Push         : (self: Port, player: Player, event: string, data: any) -> (),
	PushAll      : (self: Port, event: string, data: any) -> (),
	PushTo       : (self: Port, players: { Player }, event: string, data: any) -> (),
	OnParamError : (self: Port, fn: ParamErrorHandler) -> (),
	Destroy      : (self: Port) -> (),
}

export type App = {
	Get          : (self: App, route: string, handler: (req: Request, res: Response) -> (), options: RouteOptions?) -> (),
	Post         : (self: App, route: string, handler: (req: Request, res: Response) -> (), options: RouteOptions?) -> (),
	Put          : (self: App, route: string, handler: (req: Request, res: Response) -> (), options: RouteOptions?) -> (),
	Delete       : (self: App, route: string, handler: (req: Request, res: Response) -> (), options: RouteOptions?) -> (),
	Use          : (self: App, id: string, fn: MiddlewareHandler) -> (),
	Unuse        : (self: App, id: string) -> (),
	Push         : (self: App, player: Player, event: string, data: any) -> (),
	PushAll      : (self: App, event: string, data: any) -> (),
	PushTo       : (self: App, players: { Player }, event: string, data: any) -> (),
	Listen       : (self: App, name: string, callback: (port: Port) -> (), settings: { Max: number?, Refill: number? }?) -> Port,
	GetPort      : (self: App, name: string) -> Port?,
	OnParamError : (self: App, fn: ParamErrorHandler) -> (),
	Destroy      : (self: App) -> (),
}

-- ── Network ────────────────────────────────────────────────────────────

export type NetworkPayload = {
	version   : string,
	type      : "request",
	method    : Method,
	requestId : string,
	route     : string,
	data      : any,
}

export type NetworkResponse = {
	version    : string,
	type       : "response" | "error",
	method     : Method,
	requestId  : string,
	status     : number,
	data       : any?,
	message    : string?,
	compressed : boolean?,
}

export type NetworkCallback = (response: NetworkResponse) -> ()

export type Network = {
	Configure   : (self: Network, config: { maxRetries: number?, backoff: number? }) -> (),
	Get         : (self: Network, route: string, data: any?, callback: NetworkCallback?, timeout: number?, retries: number?) -> string,
	Post        : (self: Network, route: string, data: any,  callback: NetworkCallback?, timeout: number?, retries: number?) -> string,
	Put         : (self: Network, route: string, data: any,  callback: NetworkCallback?, timeout: number?, retries: number?) -> string,
	Delete      : (self: Network, route: string, data: any?, callback: NetworkCallback?, timeout: number?, retries: number?) -> string,
	GetAsync    : (self: Network, route: string, data: any?, timeout: number?, retries: number?) -> (string, Promise),
	PostAsync   : (self: Network, route: string, data: any,  timeout: number?, retries: number?) -> (string, Promise),
	PutAsync    : (self: Network, route: string, data: any,  timeout: number?, retries: number?) -> (string, Promise),
	DeleteAsync : (self: Network, route: string, data: any?, timeout: number?, retries: number?) -> (string, Promise),
	Cancel      : (self: Network, id: string) -> boolean,
	Destroy     : (self: Network) -> (),
}

-- ── Promise ────────────────────────────────────────────────────────────

export type PromiseState = "pending" | "resolved" | "rejected"

export type Promise = {
	Then    : (self: Promise, fn: (value: any) -> any) -> Promise,
	Catch   : (self: Promise, fn: (err: any)   -> any) -> Promise,
	Finally : (self: Promise, fn: () -> ())            -> Promise,
	Cancel  : (self: Promise) -> (),
}

-- ── Broadcast ──────────────────────────────────────────────────────────

export type Broadcast = {
	Emit    : (self: Broadcast, event: string, player: Player,      data: any) -> (),
	EmitAll : (self: Broadcast, event: string,                      data: any) -> (),
	EmitTo  : (self: Broadcast, event: string, targets: { Player }, data: any) -> (),
	Destroy : (self: Broadcast) -> (),
}

-- ── Listener ───────────────────────────────────────────────────────────

export type Listener = {
	On      : (self: Listener, event: string, handler: (data: any) -> ()) -> (),
	Once    : (self: Listener, event: string, handler: (data: any) -> ()) -> (),
	Off     : (self: Listener, event: string) -> (),
	Use     : (self: Listener, id: string, fn: (event: string, data: any) -> ()) -> (),
	Unuse   : (self: Listener, id: string) -> (),
	Destroy : (self: Listener) -> (),
}

-- ── Bridge ─────────────────────────────────────────────────────────────

export type BridgeConnection = { Disconnect: (self: BridgeConnection) -> () }

export type Bridge = {
	On        : (name: string, handler: (data: any) -> ()) -> BridgeConnection,
	Once      : (name: string, handler: (data: any) -> ()) -> BridgeConnection,
	Emit      : (name: string, data: any?) -> (),
	Has       : (name: string) -> boolean,
	Clear     : (name: string?) -> (),
	Wait      : (name: string, timeout: number?) -> any?,
	WaitUntil : (name: string, predicate: (data: any) -> boolean, timeout: number?) -> any?,
	WaitFirst : (names: { string }, timeout: number?) -> (string?, any?),
	Destroy   : () -> (),
}

-- ── Hook ───────────────────────────────────────────────────────────────

-- Hook itself is callable: Hook(event, handler)
--                          Hook(event, priority, handler)
--                          Hook(event, { priority, id }, handler)
-- These static methods are accessed as Hook.Once, Hook.Off, etc.

export type HookPriority = number | "first" | "high" | "normal" | "low" | "last"

export type HookOptions = {
	priority : HookPriority?,
	id       : string?,
}

-- Internal shorthands for common handler signatures
type _H_NoArgs    = () -> ()
type _H_Player    = (player: Player) -> ()
type _H_DeltaTime = (deltaTime: number) -> ()
type _H_Stepped   = (time: number, deltaTime: number) -> ()
type _H_Input     = (input: InputObject, gameProcessedEvent: boolean) -> ()
type _H_Gamepad   = (gamepadNum: Enum.UserInputType) -> ()
type _H_Instance  = (instance: Instance) -> ()
type _H_Character = (player: Player, character: Model) -> ()

export type Hook = {
	Once  : (event: string, priorityOrHandler: HookPriority | ((...any) -> ()), handler: ((...any) -> ())?) -> (),
	Off   : (event: string, id: string) -> (),
	Clear : (event: string) -> (),
	Fire  : (event: string, ...any) -> (),
	Has   : (event: string) -> boolean,
}
	-- ── Players ────────────────────────────────────────────────────────
	& ((event: "PlayerAdded",                handler: _H_Player) -> ())
	& ((event: "PlayerAdded",                priority: HookPriority, handler: _H_Player) -> ())
	& ((event: "PlayerAdded",                opts: HookOptions,      handler: _H_Player) -> ())
	& ((event: "PlayerRemoving",             handler: _H_Player) -> ())
	& ((event: "PlayerRemoving",             priority: HookPriority, handler: _H_Player) -> ())
	& ((event: "PlayerRemoving",             opts: HookOptions,      handler: _H_Player) -> ())
	& ((event: "PlayerMembershipChanged",    handler: _H_Player) -> ())
	& ((event: "PlayerMembershipChanged",    priority: HookPriority, handler: _H_Player) -> ())
	& ((event: "PlayerMembershipChanged",    opts: HookOptions,      handler: _H_Player) -> ())
	-- ── RunService ─────────────────────────────────────────────────────
	& ((event: "Heartbeat",      handler: _H_DeltaTime) -> ())
	& ((event: "Heartbeat",      priority: HookPriority, handler: _H_DeltaTime) -> ())
	& ((event: "Heartbeat",      opts: HookOptions,      handler: _H_DeltaTime) -> ())
	& ((event: "Stepped",        handler: _H_Stepped) -> ())
	& ((event: "Stepped",        priority: HookPriority, handler: _H_Stepped) -> ())
	& ((event: "Stepped",        opts: HookOptions,      handler: _H_Stepped) -> ())
	& ((event: "PostSimulation", handler: _H_DeltaTime) -> ())
	& ((event: "PostSimulation", priority: HookPriority, handler: _H_DeltaTime) -> ())
	& ((event: "PostSimulation", opts: HookOptions,      handler: _H_DeltaTime) -> ())
	& ((event: "PreAnimation",   handler: _H_DeltaTime) -> ())
	& ((event: "PreAnimation",   priority: HookPriority, handler: _H_DeltaTime) -> ())
	& ((event: "PreAnimation",   opts: HookOptions,      handler: _H_DeltaTime) -> ())
	& ((event: "PostAnimation",  handler: _H_DeltaTime) -> ())
	& ((event: "PostAnimation",  priority: HookPriority, handler: _H_DeltaTime) -> ())
	& ((event: "PostAnimation",  opts: HookOptions,      handler: _H_DeltaTime) -> ())
	& ((event: "RenderStepped",  handler: _H_DeltaTime) -> ())
	& ((event: "RenderStepped",  priority: HookPriority, handler: _H_DeltaTime) -> ())
	& ((event: "RenderStepped",  opts: HookOptions,      handler: _H_DeltaTime) -> ())
	& ((event: "PreRender",      handler: _H_DeltaTime) -> ())
	& ((event: "PreRender",      priority: HookPriority, handler: _H_DeltaTime) -> ())
	& ((event: "PreRender",      opts: HookOptions,      handler: _H_DeltaTime) -> ())
	-- ── UserInputService ───────────────────────────────────────────────
	& ((event: "InputBegan",   handler: _H_Input) -> ())
	& ((event: "InputBegan",   priority: HookPriority, handler: _H_Input) -> ())
	& ((event: "InputBegan",   opts: HookOptions,      handler: _H_Input) -> ())
	& ((event: "InputChanged", handler: _H_Input) -> ())
	& ((event: "InputChanged", priority: HookPriority, handler: _H_Input) -> ())
	& ((event: "InputChanged", opts: HookOptions,      handler: _H_Input) -> ())
	& ((event: "InputEnded",   handler: _H_Input) -> ())
	& ((event: "InputEnded",   priority: HookPriority, handler: _H_Input) -> ())
	& ((event: "InputEnded",   opts: HookOptions,      handler: _H_Input) -> ())
	& ((event: "JumpRequest",  handler: _H_NoArgs) -> ())
	& ((event: "JumpRequest",  priority: HookPriority, handler: _H_NoArgs) -> ())
	& ((event: "JumpRequest",  opts: HookOptions,      handler: _H_NoArgs) -> ())
	& ((event: "GamepadConnected",    handler: _H_Gamepad) -> ())
	& ((event: "GamepadConnected",    priority: HookPriority, handler: _H_Gamepad) -> ())
	& ((event: "GamepadConnected",    opts: HookOptions,      handler: _H_Gamepad) -> ())
	& ((event: "GamepadDisconnected", handler: _H_Gamepad) -> ())
	& ((event: "GamepadDisconnected", priority: HookPriority, handler: _H_Gamepad) -> ())
	& ((event: "GamepadDisconnected", opts: HookOptions,      handler: _H_Gamepad) -> ())
	& ((event: "WindowFocused",       handler: _H_NoArgs) -> ())
	& ((event: "WindowFocused",       priority: HookPriority, handler: _H_NoArgs) -> ())
	& ((event: "WindowFocused",       opts: HookOptions,      handler: _H_NoArgs) -> ())
	& ((event: "WindowFocusReleased", handler: _H_NoArgs) -> ())
	& ((event: "WindowFocusReleased", priority: HookPriority, handler: _H_NoArgs) -> ())
	& ((event: "WindowFocusReleased", opts: HookOptions,      handler: _H_NoArgs) -> ())
	& ((event: "TouchStarted", handler: _H_Input) -> ())
	& ((event: "TouchStarted", priority: HookPriority, handler: _H_Input) -> ())
	& ((event: "TouchStarted", opts: HookOptions,      handler: _H_Input) -> ())
	& ((event: "TouchMoved",   handler: _H_Input) -> ())
	& ((event: "TouchMoved",   priority: HookPriority, handler: _H_Input) -> ())
	& ((event: "TouchMoved",   opts: HookOptions,      handler: _H_Input) -> ())
	& ((event: "TouchEnded",   handler: _H_Input) -> ())
	& ((event: "TouchEnded",   priority: HookPriority, handler: _H_Input) -> ())
	& ((event: "TouchEnded",   opts: HookOptions,      handler: _H_Input) -> ())
	& ((event: "TouchTap",       handler: (touchPositions: { Vector2 }, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchTap",       priority: HookPriority, handler: (touchPositions: { Vector2 }, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchTap",       opts: HookOptions,      handler: (touchPositions: { Vector2 }, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchLongPress", handler: (touchPositions: { Vector2 }, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchLongPress", priority: HookPriority, handler: (touchPositions: { Vector2 }, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchLongPress", opts: HookOptions,      handler: (touchPositions: { Vector2 }, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchSwipe",     handler: (swipeDirection: Enum.SwipeDirection, numberOfTouches: number, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchSwipe",     priority: HookPriority, handler: (swipeDirection: Enum.SwipeDirection, numberOfTouches: number, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchSwipe",     opts: HookOptions,      handler: (swipeDirection: Enum.SwipeDirection, numberOfTouches: number, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchPinch",     handler: (touchPositions: { Vector2 }, scale: number, velocity: number, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchPinch",     priority: HookPriority, handler: (touchPositions: { Vector2 }, scale: number, velocity: number, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchPinch",     opts: HookOptions,      handler: (touchPositions: { Vector2 }, scale: number, velocity: number, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchRotate",    handler: (touchPositions: { Vector2 }, rotation: number, velocity: number, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchRotate",    priority: HookPriority, handler: (touchPositions: { Vector2 }, rotation: number, velocity: number, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "TouchRotate",    opts: HookOptions,      handler: (touchPositions: { Vector2 }, rotation: number, velocity: number, state: Enum.UserInputState, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "DeviceAccelerationChanged", handler: (acceleration: InputObject) -> ()) -> ())
	& ((event: "DeviceAccelerationChanged", priority: HookPriority, handler: (acceleration: InputObject) -> ()) -> ())
	& ((event: "DeviceAccelerationChanged", opts: HookOptions,      handler: (acceleration: InputObject) -> ()) -> ())
	& ((event: "DeviceGravityChanged",      handler: (gravity: InputObject) -> ()) -> ())
	& ((event: "DeviceGravityChanged",      priority: HookPriority, handler: (gravity: InputObject) -> ()) -> ())
	& ((event: "DeviceGravityChanged",      opts: HookOptions,      handler: (gravity: InputObject) -> ()) -> ())
	& ((event: "DeviceRotationChanged",     handler: (deltaRotation: InputObject, cframe: CFrame) -> ()) -> ())
	& ((event: "DeviceRotationChanged",     priority: HookPriority, handler: (deltaRotation: InputObject, cframe: CFrame) -> ()) -> ())
	& ((event: "DeviceRotationChanged",     opts: HookOptions,      handler: (deltaRotation: InputObject, cframe: CFrame) -> ()) -> ())
	& ((event: "PointerAction", handler: (wheel: number, pan: Vector2, pinch: number, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "PointerAction", priority: HookPriority, handler: (wheel: number, pan: Vector2, pinch: number, gameProcessedEvent: boolean) -> ()) -> ())
	& ((event: "PointerAction", opts: HookOptions,      handler: (wheel: number, pan: Vector2, pinch: number, gameProcessedEvent: boolean) -> ()) -> ())
	-- ── MarketplaceService ─────────────────────────────────────────────
	& ((event: "PromptPurchaseFinished",             handler: (player: Player, assetId: number, isPurchased: boolean) -> ()) -> ())
	& ((event: "PromptPurchaseFinished",             priority: HookPriority, handler: (player: Player, assetId: number, isPurchased: boolean) -> ()) -> ())
	& ((event: "PromptPurchaseFinished",             opts: HookOptions,      handler: (player: Player, assetId: number, isPurchased: boolean) -> ()) -> ())
	& ((event: "PromptGamePassPurchaseFinished",     handler: (player: Player, gamePassId: number, wasPurchased: boolean) -> ()) -> ())
	& ((event: "PromptGamePassPurchaseFinished",     priority: HookPriority, handler: (player: Player, gamePassId: number, wasPurchased: boolean) -> ()) -> ())
	& ((event: "PromptGamePassPurchaseFinished",     opts: HookOptions,      handler: (player: Player, gamePassId: number, wasPurchased: boolean) -> ()) -> ())
	& ((event: "PromptBundlePurchaseFinished",       handler: (player: Player, bundleId: number, wasPurchased: boolean) -> ()) -> ())
	& ((event: "PromptBundlePurchaseFinished",       priority: HookPriority, handler: (player: Player, bundleId: number, wasPurchased: boolean) -> ()) -> ())
	& ((event: "PromptBundlePurchaseFinished",       opts: HookOptions,      handler: (player: Player, bundleId: number, wasPurchased: boolean) -> ()) -> ())
	& ((event: "PromptSubscriptionPurchaseFinished", handler: (player: Player, subscriptionId: string, wasPurchased: boolean) -> ()) -> ())
	& ((event: "PromptSubscriptionPurchaseFinished", priority: HookPriority, handler: (player: Player, subscriptionId: string, wasPurchased: boolean) -> ()) -> ())
	& ((event: "PromptSubscriptionPurchaseFinished", opts: HookOptions,      handler: (player: Player, subscriptionId: string, wasPurchased: boolean) -> ()) -> ())
	-- ── TeleportService ────────────────────────────────────────────────
	& ((event: "TeleportInitFailed",             handler: (player: Player, teleportResult: Enum.TeleportResult, errorMessage: string) -> ()) -> ())
	& ((event: "TeleportInitFailed",             priority: HookPriority, handler: (player: Player, teleportResult: Enum.TeleportResult, errorMessage: string) -> ()) -> ())
	& ((event: "TeleportInitFailed",             opts: HookOptions,      handler: (player: Player, teleportResult: Enum.TeleportResult, errorMessage: string) -> ()) -> ())
	& ((event: "LocalPlayerArrivedFromTeleport", handler: (loadingGui: ScreenGui, dataTable: any?) -> ()) -> ())
	& ((event: "LocalPlayerArrivedFromTeleport", priority: HookPriority, handler: (loadingGui: ScreenGui, dataTable: any?) -> ()) -> ())
	& ((event: "LocalPlayerArrivedFromTeleport", opts: HookOptions,      handler: (loadingGui: ScreenGui, dataTable: any?) -> ()) -> ())
	-- ── SocialService ──────────────────────────────────────────────────
	& ((event: "GameInvitePromptClosed", handler: (player: Player, recipientIds: { number }) -> ()) -> ())
	& ((event: "GameInvitePromptClosed", priority: HookPriority, handler: (player: Player, recipientIds: { number }) -> ()) -> ())
	& ((event: "GameInvitePromptClosed", opts: HookOptions,      handler: (player: Player, recipientIds: { number }) -> ()) -> ())
	& ((event: "PromptInviteRequested",  handler: _H_Player) -> ())
	& ((event: "PromptInviteRequested",  priority: HookPriority, handler: _H_Player) -> ())
	& ((event: "PromptInviteRequested",  opts: HookOptions,      handler: _H_Player) -> ())
	-- ── GuiService ─────────────────────────────────────────────────────
	& ((event: "MenuOpened",               handler: _H_NoArgs) -> ())
	& ((event: "MenuOpened",               priority: HookPriority, handler: _H_NoArgs) -> ())
	& ((event: "MenuOpened",               opts: HookOptions,      handler: _H_NoArgs) -> ())
	& ((event: "MenuClosed",               handler: _H_NoArgs) -> ())
	& ((event: "MenuClosed",               priority: HookPriority, handler: _H_NoArgs) -> ())
	& ((event: "MenuClosed",               opts: HookOptions,      handler: _H_NoArgs) -> ())
	& ((event: "KeyboardVisibilityChanged", handler: (isVisible: boolean) -> ()) -> ())
	& ((event: "KeyboardVisibilityChanged", priority: HookPriority, handler: (isVisible: boolean) -> ()) -> ())
	& ((event: "KeyboardVisibilityChanged", opts: HookOptions,      handler: (isVisible: boolean) -> ()) -> ())
	-- ── TextChatService ────────────────────────────────────────────────
	& ((event: "MessageReceived", handler: (message: TextChatMessage) -> ()) -> ())
	& ((event: "MessageReceived", priority: HookPriority, handler: (message: TextChatMessage) -> ()) -> ())
	& ((event: "MessageReceived", opts: HookOptions,      handler: (message: TextChatMessage) -> ()) -> ())
	& ((event: "SendingMessage",  handler: (message: TextChatMessage) -> ()) -> ())
	& ((event: "SendingMessage",  priority: HookPriority, handler: (message: TextChatMessage) -> ()) -> ())
	& ((event: "SendingMessage",  opts: HookOptions,      handler: (message: TextChatMessage) -> ()) -> ())
	-- ── VoiceChatService ───────────────────────────────────────────────
	& ((event: "ParticipantsStateChanged",      handler: (...any) -> ()) -> ())
	& ((event: "ParticipantsStateChanged",      priority: HookPriority, handler: (...any) -> ()) -> ())
	& ((event: "ParticipantsStateChanged",      opts: HookOptions,      handler: (...any) -> ()) -> ())
	& ((event: "PlayerMicActivitySignalChange", handler: (...any) -> ()) -> ())
	& ((event: "PlayerMicActivitySignalChange", priority: HookPriority, handler: (...any) -> ()) -> ())
	& ((event: "PlayerMicActivitySignalChange", opts: HookOptions,      handler: (...any) -> ()) -> ())
	-- ── Game / Lighting ────────────────────────────────────────────────
	& ((event: "Close",              handler: _H_NoArgs) -> ())
	& ((event: "Close",              priority: HookPriority, handler: _H_NoArgs) -> ())
	& ((event: "Close",              opts: HookOptions,      handler: _H_NoArgs) -> ())
	& ((event: "DescendantAdded",    handler: _H_Instance) -> ())
	& ((event: "DescendantAdded",    priority: HookPriority, handler: _H_Instance) -> ())
	& ((event: "DescendantAdded",    opts: HookOptions,      handler: _H_Instance) -> ())
	& ((event: "DescendantRemoving", handler: _H_Instance) -> ())
	& ((event: "DescendantRemoving", priority: HookPriority, handler: _H_Instance) -> ())
	& ((event: "DescendantRemoving", opts: HookOptions,      handler: _H_Instance) -> ())
	& ((event: "LightingChanged",    handler: _H_NoArgs) -> ())
	& ((event: "LightingChanged",    priority: HookPriority, handler: _H_NoArgs) -> ())
	& ((event: "LightingChanged",    opts: HookOptions,      handler: _H_NoArgs) -> ())
	-- ── Per-player characters ──────────────────────────────────────────
	& ((event: "CharacterAdded",            handler: _H_Character) -> ())
	& ((event: "CharacterAdded",            priority: HookPriority, handler: _H_Character) -> ())
	& ((event: "CharacterAdded",            opts: HookOptions,      handler: _H_Character) -> ())
	& ((event: "CharacterRemoving",         handler: _H_Character) -> ())
	& ((event: "CharacterRemoving",         priority: HookPriority, handler: _H_Character) -> ())
	& ((event: "CharacterRemoving",         opts: HookOptions,      handler: _H_Character) -> ())
	& ((event: "CharacterAppearanceLoaded", handler: _H_Character) -> ())
	& ((event: "CharacterAppearanceLoaded", priority: HookPriority, handler: _H_Character) -> ())
	& ((event: "CharacterAppearanceLoaded", opts: HookOptions,      handler: _H_Character) -> ())
	-- ── Custom / unknown events (fallback) ─────────────────────────────
	& ((event: string, handler: (...any) -> ()) -> ())
	& ((event: string, priority: HookPriority, handler: (...any) -> ()) -> ())
	& ((event: string, opts: HookOptions,      handler: (...any) -> ()) -> ())

-- ── TokenBucket ────────────────────────────────────────────────────────

export type TokenBucketSettings = {
	Max    : number,
	Refill : number,
}

export type TokenBucket = {
	Consume        : (self: TokenBucket, player: Player, cost: number) -> boolean,
	HasTokens      : (self: TokenBucket, player: Player) -> boolean,
	HasEnoughTokens: (self: TokenBucket, player: Player, cost: number) -> boolean,
	Grant          : (self: TokenBucket, player: Player, amount: number) -> (),
	GrantAll       : (self: TokenBucket, amount: number) -> (),
	GrantExact     : (self: TokenBucket, player: Player, amount: number) -> (),
	GrantAllExact  : (self: TokenBucket, amount: number) -> (),
	Reset          : (self: TokenBucket, player: Player) -> (),
	Destroy        : (self: TokenBucket) -> (),
}

-- ── Tamper ─────────────────────────────────────────────────────────────

export type TamperSeverity = "immediate" | "pattern"

export type TamperReason =
	"VERSION_SPOOF"     |
	"MALFORMED_PAYLOAD" |
	"INVALID_PARAM"     |
	"UNKNOWN_ROUTE"     |
	"RATE_FLOOD"        |
	"ROUTE_SCAN"        |
	"PARAM_FLOOD"       |
	"MANUAL"

export type TamperReport = {
	player    : Player,
	reason    : TamperReason,
	severity  : TamperSeverity,
	route     : string?,
	evidence  : any?,
	strikes   : number,
	firstSeen : number,
	lastSeen  : number,
}

export type TamperRecord = {
	strikes   : number,
	firstSeen : number,
	lastSeen  : number,
}

export type Tamper = {
	On        : (handler: (report: TamperReport) -> ()) -> (),
	AutoKick  : (threshold: number, reason: string?) -> (),
	Strike    : (player: Player, reason: string?, route: string?, evidence: any?) -> (),
	GetReport : (player: Player) -> TamperRecord?,
}

-- ── RTTP ───────────────────────────────────────────────────────────────

export type RTTPConfig = {
	base    : string?,
	headers : { [string]: string }?,
	retries : number?,
}

export type RTTPResponse = {
	ok      : boolean,
	status  : number,
	data    : any,
	headers : { [string]: string },
	raw     : string,
}

export type RTTPCallback = (res: RTTPResponse) -> ()

export type RTTPInstance = {
	SetBase      : (self: RTTPInstance, url: string) -> (),
	SetHeader    : (self: RTTPInstance, key: string, value: string) -> (),
	RemoveHeader : (self: RTTPInstance, key: string) -> (),
	SetRetries   : (self: RTTPInstance, n: number) -> (),
	Get          : (self: RTTPInstance, path: string, callback: RTTPCallback?) -> (),
	Post         : (self: RTTPInstance, path: string, body: any?, callback: RTTPCallback?) -> (),
	Put          : (self: RTTPInstance, path: string, body: any?, callback: RTTPCallback?) -> (),
	Delete       : (self: RTTPInstance, path: string, callback: RTTPCallback?) -> (),
	GetAsync     : (self: RTTPInstance, path: string) -> Promise,
	PostAsync    : (self: RTTPInstance, path: string, body: any?) -> Promise,
	PutAsync     : (self: RTTPInstance, path: string, body: any?) -> Promise,
	DeleteAsync  : (self: RTTPInstance, path: string) -> Promise,
}

-- RTTP is a factory — call RTTP.New(config?) to get an RTTPInstance
export type RTTP = {
	New : (config: RTTPConfig?) -> RTTPInstance,
}

-- ── Cross ──────────────────────────────────────────────────────────────

export type MsgContext = {
	serverId : string,
	time     : number,
}

export type ServerEntry = {
	id      : string,
	place   : number,
	players : number,
	meta    : { [string]: any },
	ts      : number,
}

export type CrossMemory = {
	Set    : (key: string, value: any, expiry: number?) -> (),
	Get    : (key: string) -> any,
	Remove : (key: string) -> (),
	Update : (key: string, transform: (current: any) -> any, expiry: number?) -> (),
}

export type Cross = {
	ServerId         : () -> string,
	Publish          : (topic: string, data: any) -> (),
	Subscribe        : (topic: string, handler: (data: any, ctx: MsgContext) -> ()) -> (),
	Once             : (topic: string, handler: (data: any, ctx: MsgContext) -> ()) -> (),
	Unsubscribe      : (topic: string) -> (),
	RegisterServer   : (meta: { [string]: any }?) -> (),
	GetServers       : () -> { ServerEntry },
	UnregisterServer : () -> (),
	Memory           : CrossMemory,
}

-- ── Maid ───────────────────────────────────────────────────────────────

export type Maid = {
	Add     : <T>(self: Maid, item: T) -> T,
	Remove  : (self: Maid, item: any) -> (),
	Clear   : (self: Maid) -> (),
	Destroy : (self: Maid) -> (),
}

-- ── Debounce ───────────────────────────────────────────────────────────

export type Debounce = {
	fn  : <T...>(fn: (T...) -> (), cooldown: number) -> (T...) -> boolean,
	key : <K, T...>(fn: (key: K, T...) -> (), cooldown: number) -> (key: K, T...) -> boolean,
	default : <T...>(fn: (Value: boolean,T...) -> ()) -> (T...) -> boolean,
}

-- ── BroadcastEnvelope (internal wire format) ───────────────────────────

export type BroadcastEnvelope = {
	event : string,
	data  : any,
}

-- ── RoExpress callable interface ───────────────────────────────────────
-- Typing for the RoExpress("ModuleName") and RoExpress("ModuleName", portName)
-- call syntax. The overload order matters — Luau picks the first match.

export type RoExpressCall =
	-- Constructed instances
	((name: "App")         -> App)         &
	((name: "Network")     -> Network)     &
	((name: "Broadcast")   -> Broadcast)   &
	((name: "Listener")    -> Listener)    &
	((name: "Benchmark")   -> any)         &
	((name: "Maid")        -> Maid)        &
	-- Named-port variants (client)
	((name: "Network",  portName: string)  -> Network)  &
	((name: "Listener", portName: string)  -> Listener) &
	-- Singleton / factory module references
	((name: "Base64")      -> any)         &
	((name: "Bridge")      -> Bridge)      &
	((name: "Codec")       -> any)         &
	((name: "Cross")       -> Cross)       &
	((name: "Hook")        -> Hook)        &
	((name: "Promise")     -> Promise)     &
	((name: "RTTP")        -> RTTP)        &
	((name: "Router")      -> any)         &
	((name: "Stream")      -> any)         &
	((name: "Tamper")      -> Tamper)      &
	((name: "TypeCoercer") -> any)         &
	((name: "Debounce")    -> Debounce)

return {}
