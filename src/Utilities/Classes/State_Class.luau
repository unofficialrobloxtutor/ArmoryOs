--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--  ◄► Title:       State_Class
--  ◄► Version:     2.2
--  ◄► Date:        12/07/2026
--  ◄► Author:      DeathToTheStadium
--  ◄► Description: A reusable state manager that accepts a list of
--                  states on construction. Supports controlled
--                  transitions, transition guards, enter/exit
--                  callbacks, state tags, and change events.
--                  Maintains backwards compatibility with the
--                  original Changed event API.
--
--  ◄► Changelog (2.1 -> 2.2):
--     - Type<S> is now generic over the state literal type. Pass a
--       string literal union as S so State/LastState/ChangeState/etc
--       are all typechecked against your actual state list instead
--       of plain `string`. See usage note below Module.New.
--
--  ◄► Changelog (2.0 -> 2.1):
--     - SetTransition split into SetTransition(list) and
--       SetTransitionMap(map) to remove implicit array/dict
--       detection ambiguity.
--     - ForceChangeState now runs Exit/Enter callbacks (still
--       skips guards + transition rules, which is the point of
--       "Force").
--     - Enter/Exit callbacks are now resumed synchronously via
--       coroutine so ordering is deterministic. If a callback
--       yields, State_Class warns (yielding inside a state
--       callback is unsupported) instead of silently detaching
--       from the Changed/AfterChanged firing order.
--■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
--► Services     ◄--
--► Requirements ◄--
--► Tables       ◄--

local Module = {}

export type Type<S> = typeof(setmetatable({} :: {
	State:S,
	LastState:S,

	_States:{S},
	_StateSet:{[S]:boolean},

	_Transitions:{[S]:{[S]:boolean}},
	_Guards:{[S]:() -> boolean},

	_EnterCallbacks:{[S]:{() -> ()}},
	_ExitCallbacks:{[S]:{() -> ()}},

	_Tags:{[S]:{[string]:boolean}},

	_BeforeChanged:BindableEvent,
	_AfterChanged:BindableEvent,
	_Changed:BindableEvent,

	BeforeChanged:RBXScriptSignal,
	Changed:RBXScriptSignal,
	AfterChanged:RBXScriptSignal,

}, {__index=Module}))


-- Usage: define a state literal union, then cast the array so S is
-- inferred as that union rather than widened to plain `string`:
--
--   type WeaponState = "Idle" | "Equipping" | "Equipped" | "Firing"
--                     | "Reloading" | "UnEquipping" | "Sprinting"
--
--   local Weapon = StateClass.New(({
--       "Idle","Equipping","Equipped","Firing","Reloading","UnEquipping","Sprinting"
--   } :: {WeaponState}))
--
-- From here on, Weapon.State, ChangeState(...), Is(...), OnEnter(...), etc.
-- all only accept WeaponState literals — a typo like "Realoding" is now
-- a compile-time error instead of a silent runtime `warn`.
function Module.New<S>(States:{S}):Type<S>
	assert(States and #States > 0,"State_Class: States list cannot be empty")

	local StateSet = {}

	for _,State in States do
		StateSet[State] = true
	end

	local self = setmetatable({}, {__index = Module})

	self._States = States
	self._StateSet = StateSet

	self._Transitions = {}
	self._Guards = {}

	self._EnterCallbacks = {}
	self._ExitCallbacks = {}

	self._Tags = {}

	self._BeforeChanged = Instance.new("BindableEvent")
	self._Changed = Instance.new("BindableEvent")
	self._AfterChanged = Instance.new("BindableEvent")

	self.BeforeChanged = self._BeforeChanged.Event
	self.Changed = self._Changed.Event
	self.AfterChanged = self._AfterChanged.Event

	self.State = States[1]
	self.LastState = States[1]

	return (self :: any) :: Type<S>
end


local function _validate<S>(self:Type<S>, State:S):boolean
	if not self._StateSet[State] then
		warn(`State_Class: "{tostring(State)}" is not a valid state`)
		return false
	end

	return true
end


-- Explicit array form: SetTransition(self, "Idle", {"Equipping", "Sprinting"})
function Module.SetTransition<S>(self:Type<S>, From:S, Allowed:{S})
	if not _validate(self,From) then
		return
	end

	local Map = {}

	for _,State in Allowed do
		if _validate(self,State) then
			Map[State] = true
		end
	end

	self._Transitions[From] = Map
end


-- Explicit map form: SetTransitionMap(self, "Idle", {Equipping = true, Sprinting = true})
function Module.SetTransitionMap<S>(self:Type<S>, From:S, Allowed:{[S]:boolean})
	if not _validate(self,From) then
		return
	end

	local Map = {}

	for State,AllowedState in Allowed do
		if AllowedState and _validate(self,State) then
			Map[State] = true
		end
	end

	self._Transitions[From] = Map
end


function Module.GetTransitions<S>(self:Type<S>, State:S):{S}
	if not _validate(self,State) then
		return {}
	end

	local Results = {}

	for Name in self._Transitions[State] or {} do
		table.insert(Results,Name)
	end

	return Results
end


function Module.SetGuard<S>(self:Type<S>, State:S, Callback:()->boolean)
	if not _validate(self,State) then
		return
	end

	self._Guards[State] = Callback
end


function Module.CanTransition<S>(self:Type<S>, To:S):boolean
	if not _validate(self,To) then
		return false
	end

	local Rules = self._Transitions[self.State]

	if Rules and not Rules[To] then
		return false
	end

	local Guard = self._Guards[To]

	if Guard then
		local Success,Result = pcall(Guard)

		if not Success or not Result then
			return false
		end
	end

	return true
end


function Module.OnEnter<S>(self:Type<S>, State:S, Callback:()->())
	if not self._EnterCallbacks[State] then
		self._EnterCallbacks[State] = {}
	end

	table.insert(self._EnterCallbacks[State],Callback)
end


function Module.OnExit<S>(self:Type<S>, State:S, Callback:()->())
	if not self._ExitCallbacks[State] then
		self._ExitCallbacks[State] = {}
	end

	table.insert(self._ExitCallbacks[State],Callback)
end


-- Resumes callbacks synchronously (deterministic ordering relative to
-- Changed/AfterChanged). If a callback yields, it is warned about and left
-- running in the background rather than silently detaching from the
-- transition's timing guarantees.
local function _FireCallbacks<S>(List:{() -> ()}?, State:S, Phase:string)
	if not List then
		return
	end

	for _,Callback in List do
		local Thread = coroutine.create(Callback)
		local Success,Err = coroutine.resume(Thread)

		if not Success then
			warn(`State_Class: {Phase} callback for "{tostring(State)}" errored: {Err}`)
		elseif coroutine.status(Thread) ~= "dead" then
			warn(`State_Class: {Phase} callback for "{tostring(State)}" yielded — this is unsupported and breaks ordering guarantees relative to Changed/AfterChanged. Avoid yielding inside state callbacks.`)
		end
	end
end


function Module.ChangeState<S>(self:Type<S>, State:S)
	if not _validate(self,State) then
		return
	end

	if self.State == State then
		return
	end

	if not self:CanTransition(State) then
		warn(`State_Class: Invalid transition "{tostring(self.State)}" -> "{tostring(State)}"`)
		return
	end

	local Previous = self.State

	self._BeforeChanged:Fire(Previous,State)

	_FireCallbacks(self._ExitCallbacks[Previous], Previous, "Exit")

	self.LastState = Previous
	self.State = State

	_FireCallbacks(self._EnterCallbacks[State], State, "Enter")

	self._Changed:Fire(State,Previous)

	self._AfterChanged:Fire(State,Previous)
end


-- Bypasses guards and transition rules (e.g. for server-authoritative
-- corrections), but still runs Exit/Enter callbacks so cleanup and
-- animation/visual side effects stay consistent.
function Module.ForceChangeState<S>(self:Type<S>, State:S)
	if not _validate(self,State) then
		return
	end

	if self.State == State then
		return
	end

	local Previous = self.State

	self._BeforeChanged:Fire(Previous,State)

	_FireCallbacks(self._ExitCallbacks[Previous], Previous, "Exit")

	self.LastState = Previous
	self.State = State

	_FireCallbacks(self._EnterCallbacks[State], State, "Enter")

	self._Changed:Fire(State,Previous)

	self._AfterChanged:Fire(State,Previous)
end


function Module.GetState<S>(self:Type<S>):S
	return self.State
end


function Module.GetLastState<S>(self:Type<S>):S
	return self.LastState
end


function Module.AddTag<S>(self:Type<S>, State:S, Tag:string)
	if not self._Tags[State] then
		self._Tags[State] = {}
	end

	self._Tags[State][Tag] = true
end


function Module.HasTag<S>(self:Type<S>, Tag:string):boolean
	local Tags = self._Tags[self.State]

	return Tags and Tags[Tag] == true or false
end


function Module.NextState<S>(self:Type<S>)
	local Index = table.find(self._States,self.State)

	if not Index then
		return
	end

	local Next = self._States[Index + 1] or self._States[1]

	self:ChangeState(Next)
end


function Module.Is<S>(self:Type<S>,State:S):boolean
	return self.State == State
end


function Module.WasIn<S>(self:Type<S>,State:S):boolean
	return self.LastState == State
end


function Module.Reset<S>(self:Type<S>)
	self:ForceChangeState(self._States[1])
end


function Module.Destroy<S>(self:Type<S>)
	table.clear(self._Transitions)
	table.clear(self._Guards)

	table.clear(self._EnterCallbacks)
	table.clear(self._ExitCallbacks)

	table.clear(self._Tags)

	self._BeforeChanged:Destroy()
	self._Changed:Destroy()
	self._AfterChanged:Destroy()

	table.clear(self)
end


return Module
