--!strict
--[[
	RateLimiter
	Per-player sliding-window budget, used to throttle remote handlers.

	MiningService carries its own swing-specific limiter because a swing has a
	pickaxe-derived rate. This is the generic one for everything else: selling,
	buying, equipping, rebirthing. AntiCheatService will take ownership of the
	policy in a later phase; the mechanism lives here so every service is
	already throttled in the meantime.

	Deliberately forgiving on bursts -- a player mashing "Sell All" or clicking
	through shop tabs is normal -- and only meant to stop scripted floods.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = {
	check: (self: RateLimiter, player: Player) -> boolean,
	forget: (self: RateLimiter, player: Player) -> (),
	violationsFor: (self: RateLimiter, player: Player) -> number,
}

type Bucket = {
	windowStart: number,
	count: number,
	violations: number,
}

--[[
	`limit` calls per `window` seconds. `label` only appears in the warning, so
	a flood is traceable to the remote that produced it.
]]
function RateLimiter.new(label: string, limit: number, window: number?): RateLimiter
	local self = setmetatable({
		_label = label,
		_limit = limit,
		_window = window or 1,
		_buckets = {} :: { [Player]: Bucket },
	}, RateLimiter)
	return (self :: any) :: RateLimiter
end

-- Returns true if the call is allowed. Logs once per window when it isn't, so
-- a sustained flood produces one line per window rather than one per call.
function RateLimiter:check(player: Player): boolean
	local now = os.clock()
	local bucket = self._buckets[player]

	if not bucket then
		bucket = { windowStart = now, count = 0, violations = 0 }
		self._buckets[player] = bucket
	end

	if now - bucket.windowStart >= self._window then
		bucket.windowStart = now
		bucket.count = 0
	end

	bucket.count += 1

	if bucket.count > self._limit then
		if bucket.count == self._limit + 1 then
			bucket.violations += 1
			warn(
				`[RateLimiter] {player.Name} exceeded {self._label} `
					.. `({bucket.count} in {self._window}s, limit {self._limit})`
			)
		end
		return false
	end

	return true
end

function RateLimiter:forget(player: Player)
	self._buckets[player] = nil
end

function RateLimiter:violationsFor(player: Player): number
	local bucket = self._buckets[player]
	return if bucket then bucket.violations else 0
end

return RateLimiter
