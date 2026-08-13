--!strict
--[[
	AntiCheatService
	One place that owns remote throttling policy, the violation ledger, and the
	shared sanity checks.

	Until now each service carried its own RateLimiter with its own numbers,
	which meant no single view of a player's behaviour and five places to edit
	when tuning. Services now call `guard(player, remoteName)` and the policy
	lives in POLICY below.

	Two budgets apply to every call:
	  per-remote -- the specific limit for that remote
	  global     -- GameConfig.RemoteRateLimitPerSecond across ALL remotes, so
	                a client cannot stay under five individual limits while
	                flooding in aggregate

	What this service does NOT do is duplicate per-service validation. Whether a
	slot is occupied, whether a tier is affordable, whether a block is in reach
	-- those live with the service that knows the rules, because a central
	validator would need to re-derive state it doesn't own and would drift.
	This service owns rate, sanity of raw payloads, and consequences.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RateLimiter = require(ReplicatedStorage.Shared.Modules.RateLimiter)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

local AntiCheatService = {}
AntiCheatService.Name = "AntiCheatService"

-- (player, kind, detail)
AntiCheatService.Violation = Signal.new()

--[[
	Calls allowed per window, per player, per remote.

	Deliberately generous. These exist to stop scripted floods, not to punish a
	player mashing Sell All or clicking through shop tabs. A limit tight enough
	to annoy a real player is a bug.
]]
local POLICY: { [string]: { limit: number, window: number } } = {
	RequestSell = { limit = 8, window = 1 },
	RequestPurchase = { limit = 6, window = 1 },
	RequestEquip = { limit = 8, window = 1 },
	RequestUnlockLayer = { limit = 4, window = 1 },
	RequestRebirth = { limit = 2, window = 2 },
	RequestConvert = { limit = 4, window = 1 },
	RequestPlace = { limit = 8, window = 1 },
	RequestUnplace = { limit = 8, window = 1 },
	RequestSellBrainrot = { limit = 6, window = 1 },
	GetProfileSnapshot = { limit = 4, window = 1 },
}

-- Fallback for a remote with no explicit entry, so adding a remote can never
-- accidentally ship unthrottled.
local DEFAULT_POLICY = { limit = 6, window = 1 }

--[[
	Violations that indicate tampering rather than impatience -- a malformed
	payload, an impossible reach, a claim on something the player doesn't own.
	Enough of them in a session and the player is removed.

	Set high: a false kick is far worse than a slow one, and every one of these
	is already refused before it reaches this counter.
]]
local KICK_THRESHOLD = 40

local limiters: { [string]: RateLimiter.RateLimiter } = {}
local globalLimiter: RateLimiter.RateLimiter
local severe: { [Player]: number } = {}

-- ==========================================================================
-- Throttling
-- ==========================================================================

local function limiterFor(remoteName: string): RateLimiter.RateLimiter
	local existing = limiters[remoteName]
	if existing then
		return existing
	end

	local policy = POLICY[remoteName] or DEFAULT_POLICY
	local limiter = RateLimiter.new(remoteName, policy.limit, policy.window)
	limiters[remoteName] = limiter
	return limiter
end

--[[
	The gate every remote handler calls first. Returns true if the call may
	proceed.

	Checks the global budget first: a client flooding across many remotes is
	the case a per-remote limit alone would miss.
]]
function AntiCheatService.guard(player: Player, remoteName: string): boolean
	if not globalLimiter:check(player) then
		return false
	end
	return limiterFor(remoteName):check(player)
end

-- ==========================================================================
-- Payload sanity
-- ==========================================================================

-- Rejects NaN and both infinities in one test. NaN is the interesting case:
-- it compares false against every bound, so an unchecked NaN slips past naive
-- range checks.
function AntiCheatService.isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < math.huge
		and math.abs(v.Y) < math.huge
		and math.abs(v.Z) < math.huge
end

function AntiCheatService.isInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value == value and math.abs(value) < math.huge
end

function AntiCheatService.isId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= 64
end

-- Distance check shared by anything that needs "is the player actually near
-- this". Returns false when the character is missing or dead.
function AntiCheatService.withinReach(player: Player, position: Vector3, reach: number): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	return (root.Position - position).Magnitude <= reach
end

-- ==========================================================================
-- Violations
-- ==========================================================================

--[[
	Records a violation that suggests tampering. `severity` of "severe" counts
	toward the kick threshold; anything else is logged only.
]]
function AntiCheatService.report(player: Player, kind: string, detail: string?, severity: string?)
	AntiCheatService.Violation:Fire(player, kind, detail)

	if severity ~= "severe" then
		return
	end

	local count = (severe[player] or 0) + 1
	severe[player] = count

	warn(`[AntiCheat] {player.Name}: {kind}{if detail then ` ({detail})` else ""} [severe #{count}]`)

	if count >= KICK_THRESHOLD then
		warn(`[AntiCheat] kicking {player.Name} after {count} severe violations`)
		player:Kick("Disconnected for unusual activity. If this was a mistake, please rejoin.")
	end
end

function AntiCheatService.severeCount(player: Player): number
	return severe[player] or 0
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function AntiCheatService.Init()
	globalLimiter = RateLimiter.new("global", GameConfig.RemoteRateLimitPerSecond, 1)

	-- Build a limiter per declared remote up front, so an unlisted remote is
	-- visible at boot rather than discovered under load.
	for _, spec in RemoteRegistry.SPECS do
		if spec.direction ~= "ServerToClient" then
			limiterFor(spec.name)
		end
	end
end

function AntiCheatService.Start()
	Players.PlayerRemoving:Connect(function(player)
		severe[player] = nil
		globalLimiter:forget(player)
		for _, limiter in limiters do
			limiter:forget(player)
		end
	end)
end

function AntiCheatService.stats()
	local tracked = 0
	for _ in limiters do
		tracked += 1
	end
	return { remotesTracked = tracked, kickThreshold = KICK_THRESHOLD }
end

AntiCheatService._internal = { POLICY = POLICY, DEFAULT_POLICY = DEFAULT_POLICY }

return AntiCheatService
