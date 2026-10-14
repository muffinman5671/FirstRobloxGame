--!strict
--[[
	DailyRewardService
	Pays the daily reward.

	The rules -- when a reward opens, which day of the cycle it is, what it is
	worth -- live in Shared/Modules/DailyReward, where the client can read them
	too. This service is the part that owns the clock and the profile: the client
	asks, and the answer is computed here from os.time() and the saved claim day,
	never from anything the client sent. A request carries no arguments at all.

	The claim day and the coins are written to the same profile in the same
	frame, so there is no window in which one is saved without the other.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyReward = require(ReplicatedStorage.Shared.Modules.DailyReward)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)

type PurchaseResult = SharedTypes.PurchaseResult

local DailyRewardService = {}
DailyRewardService.Name = "DailyRewardService"

local AntiCheatService
local DataService
local EconomyService
local IncomeService

-- (player, cycleDay, coins, streak)
DailyRewardService.Claimed = Signal.new()

-- Claims today's reward if there is one to claim.
function DailyRewardService.claim(player: Player): PurchaseResult
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local now = os.time()
	local status = DailyReward.status(profile.dailyLastClaimDay, profile.dailyStreak, now)
	if not status.claimable then
		return { ok = false, reason = "daily_already_claimed", coins = profile.coins }
	end

	-- Priced off the income the player has right now, before anything changes.
	local reward = DailyReward.rewardFor(status.cycleDay, IncomeService.rateFor(profile))

	DataService.update(player, function(p)
		p.dailyStreak = status.streak
		p.dailyLastClaimDay = DailyReward.dayIndex(now)
	end)
	EconomyService.award(player, reward)
	EconomyService.flushCoins(player)

	DailyRewardService.Claimed:Fire(player, status.cycleDay, reward, status.streak)
	RemoteRegistry.event("NotifyToast"):FireClient(
		player,
		"daily_reward",
		-- Concatenated: `$` beside a brace in an interpolated string is easy to
		-- misread, and the codebase has been bitten by `$$` there before.
		"Day " .. status.cycleDay .. " reward: +$" .. Format.abbreviate(reward)
	)

	DataService.pushSnapshot(player)

	-- Written straight away rather than left for the autosave: losing a claim to
	-- a crash costs the player a day of their streak. Off-thread, because the
	-- DataStore call yields and the client is waiting on this return.
	task.spawn(DataService.saveNow, player)

	local updated = DataService.get(player)
	return { ok = true, coins = if updated then updated.coins else nil }
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function DailyRewardService.Init()
	AntiCheatService = require(script.Parent.AntiCheatService)
	DataService = require(script.Parent.DataService)
	EconomyService = require(script.Parent.EconomyService)
	IncomeService = require(script.Parent.IncomeService)
end

function DailyRewardService.Start()
	RemoteRegistry.func("RequestClaimDaily").OnServerInvoke = function(player)
		if not AntiCheatService.guard(player, "RequestClaimDaily") then
			return { ok = false, reason = "rate_limited" }
		end
		return DailyRewardService.claim(player)
	end
end

return DailyRewardService
