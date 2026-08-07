--!strict
--[[
	Trove
	Cleanup helper. Every service that connects an event, spawns a loop, or
	parents an Instance for a player puts the handle in that player's Trove, so
	teardown on leave is one call and cannot miss a connection.

	This is the mechanism behind the "all connections cleaned up on player leave"
	and "no memory leaks from block pooling" acceptance items.
]]

local Trove = {}
Trove.__index = Trove

export type Trackable = Instance | RBXScriptConnection | thread | () -> () | { [any]: any }

export type Trove = {
	Add: <T>(self: Trove, object: T, cleanupMethod: string?) -> T,
	Remove: (self: Trove, object: any) -> boolean,
	Connect: (self: Trove, signal: RBXScriptSignal, handler: (...any) -> ()) -> RBXScriptConnection,
	Extend: (self: Trove) -> Trove,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
}

-- Works out how to dispose of an object, or errors loudly at Add time rather
-- than silently leaking at Clean time.
local function resolveCleanup(object: any, explicit: string?): string
	if explicit then
		return explicit
	end

	local kind = typeof(object)

	if kind == "function" then
		return "__call"
	elseif kind == "thread" then
		return "__thread"
	elseif kind == "RBXScriptConnection" then
		return "Disconnect"
	elseif kind == "Instance" then
		return "Destroy"
	elseif kind == "table" then
		if type(object.Destroy) == "function" then
			return "Destroy"
		elseif type(object.Disconnect) == "function" then
			return "Disconnect"
		end
	end

	error(`Trove: don't know how to clean up a {kind}; pass an explicit method name`, 3)
end

local function dispose(object: any, method: string)
	if method == "__call" then
		object()
	elseif method == "__thread" then
		-- Cancelling an already-dead thread throws; the running thread can't
		-- cancel itself either, so defer that case.
		if coroutine.status(object) == "running" then
			task.defer(task.cancel, object)
		elseif coroutine.status(object) ~= "dead" then
			pcall(task.cancel, object)
		end
	else
		object[method](object)
	end
end

function Trove.new(): Trove
	local self = setmetatable({
		_objects = {},
	}, Trove)
	return (self :: any) :: Trove
end

-- Returns the object so you can write `local part = trove:Add(Instance.new("Part"))`.
function Trove:Add(object, cleanupMethod)
	local method = resolveCleanup(object, cleanupMethod)
	table.insert(self._objects, { object = object, method = method })
	return object
end

-- Cleans the object immediately and stops tracking it. Returns whether it was
-- being tracked in the first place.
function Trove:Remove(object): boolean
	for index, entry in self._objects do
		if entry.object == object then
			table.remove(self._objects, index)
			dispose(entry.object, entry.method)
			return true
		end
	end
	return false
end

-- Sugar for the overwhelmingly common case.
function Trove:Connect(signal, handler): RBXScriptConnection
	return self:Add(signal:Connect(handler))
end

-- A child trove, cleaned when this one is. Useful for per-plot or per-chunk
-- scopes nested inside a per-player scope.
function Trove:Extend(): Trove
	return self:Add(Trove.new())
end

-- Disposes everything in reverse insertion order, so objects torn down last
-- were created first. Errors in one cleanup never skip the rest.
function Trove:Clean()
	local objects = self._objects
	self._objects = {}

	for index = #objects, 1, -1 do
		local entry = objects[index]
		local ok, err = pcall(dispose, entry.object, entry.method)
		if not ok then
			warn(`[Trove] cleanup failed for {typeof(entry.object)}: {err}`)
		end
	end
end

function Trove:Destroy()
	self:Clean()
end

return Trove
