--!strict
--[[
	Signal
	Pure-Lua event object. Used for server-internal service-to-service messaging
	where a BindableEvent would needlessly serialize arguments and lose table
	identity.

	Handlers run in their own coroutine via task.spawn, so one erroring listener
	cannot stop the others or block the firing thread.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, handler): Connection
	local self = setmetatable({
		Connected = true,
		_signal = signal,
		_handler = handler,
	}, Connection)
	return (self :: any) :: Connection
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false

	local handlers = self._signal._handlers
	local index = table.find(handlers, self._handler)
	if index then
		table.remove(handlers, index)
	end

	self._signal = nil
	self._handler = nil
end

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_handlers = {},
	}, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal:Connect(handler)
	assert(type(handler) == "function", "Signal:Connect expects a function")
	table.insert(self._handlers, handler)
	return Connection.new(self, handler)
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Fire(...)
	-- Iterate a copy: a handler is allowed to disconnect itself or others.
	local snapshot = table.clone(self._handlers)
	for _, handler in snapshot do
		task.spawn(handler, ...)
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

function Signal:Destroy()
	self:DisconnectAll()
end

return Signal
