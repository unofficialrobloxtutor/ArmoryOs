------------------------------------------------------------------------
--  <> Title:       RoExpress.Maid
--  <> Version:     1.0
--  <> Date:        15/06/2026
--  <> Author:      DeathToTheStadium
--  <> Description: Lifecycle cleanup utility.
--
--  A Maid tracks objects that need cleaning up and destroys them all
--  at once. Works with anything that has a natural teardown:
--
--    Disconnect  →  RBXScriptConnection, BridgeConnection, any :Disconnect()
--    Destroy     →  Instance, any :Destroy()
--    Cancel      →  coroutine thread via task.cancel()
--    Call        →  plain function, called with no arguments
--
--  USAGE
--  ────────────────────────────────────────────────────────────────
--    local maid = RoExpress("Maid")
--
--    maid:Add(Bridge.On("kill", handler))   -- BridgeConnection
--    maid:Add(part.Touched:Connect(fn))     -- RBXScriptConnection
--    maid:Add(task.spawn(loop))             -- thread
--    maid:Add(function() cleanup() end)     -- arbitrary teardown
--    maid:Add(Instance.new("Part"))         -- Instance
--
--    maid:Destroy()  -- cleans everything, in reverse-add order
--
--  Add returns its argument so connections can be stored and tracked
--  in one step:
--
--    local conn = maid:Add(Bridge.On("kill", handler))
--    -- conn is still typed as BridgeConnection
--
--  NESTING
--  ────────────────────────────────────────────────────────────────
--  Maids can be nested — a child Maid added to a parent Maid will
--  have its own :Destroy() called when the parent is destroyed.
--
--    local childMaid = maid:Add(RoExpress("Maid"))
------------------------------------------------------------------------

-->> Tables <<--
local Maid      = {}
Maid.__index    = Maid

-->> Types <<--
export type Type = typeof(setmetatable({} :: { _items: { any } }, Maid))

------------------------------------------------------------------------
--	PRIVATE
------------------------------------------------------------------------

local function _clean(item: any)
	local t = typeof(item)
	if type(item) == "function" then
		item()
	elseif type(item) == "thread" then
		task.cancel(item)
	elseif t == "RBXScriptConnection" then
		item:Disconnect()
	elseif type(item) == "table" then
		if item.Disconnect then
			item:Disconnect()
		elseif item.Destroy then
			item:Destroy()
		else
			warn("[RoExpress.Maid] Cannot clean item — no Disconnect or Destroy method")
		end
	else
		warn("[RoExpress.Maid] Cannot clean item of type: " .. t)
	end
end

------------------------------------------------------------------------
--	CONSTRUCTOR
------------------------------------------------------------------------

function Maid.new(): Type
	return setmetatable({ _items = {} }, Maid) :: any
end

------------------------------------------------------------------------
--	METHODS
------------------------------------------------------------------------

-- Add an item to be cleaned on Destroy. Returns the item unchanged
-- so it can be stored and tracked in one expression.
function Maid:Add<T>(item: T): T
	assert(item ~= nil, "[RoExpress.Maid] Add — item must not be nil")
	table.insert(self._items, item)
	return item
end

-- Immediately clean and stop tracking a specific item.
function Maid:Remove(item: any)
	for i, v in self._items do
		if v == item then
			_clean(v)
			table.remove(self._items, i)
			return
		end
	end
end

-- Clean all items without destroying the Maid — it can be reused.
function Maid:Clear()
	for i = #self._items, 1, -1 do
		_clean(self._items[i])
	end
	table.clear(self._items)
end

-- Clean all items and make the Maid inert. Do not use after Destroy.
function Maid:Destroy()
	self:Clear()
	setmetatable(self, nil)
end

return Maid
