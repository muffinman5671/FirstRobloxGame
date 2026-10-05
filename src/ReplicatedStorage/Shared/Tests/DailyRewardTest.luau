--!strict
--[[
	DailyRewardTest
	The daily reward's rules, driven with fixed clocks.

	DailyReward never reads the time itself, which is what makes this possible:
	"claimed yesterday", "missed a day" and "the clock went backwards" are just
	different numbers passed in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyReward = require(ReplicatedStorage.Shared.Modules.DailyReward)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

return function(t)
	local DAY = 24 * 60 * 60
	-- Noon UTC on an arbitrary day, so "later the same day" and "earlier the
	-- same day" both exist without crossing midnight.
	local NOON = 20000 * DAY + 12 * 60 * 60
	local TODAY = DailyReward.dayIndex(NOON)
	local CYCLE = #GameConfig.DailyRewards

	-- ---------- day boundaries ----------
	t.equal(TODAY, 20000, "dayIndex counts whole UTC days")
	t.equal(DailyReward.dayIndex(20000 * DAY), 20000, "midnight belongs to the day it starts")
	t.equal(DailyReward.dayIndex(20000 * DAY - 1), 19999, "the second before midnight is still yesterday")

	-- ---------- a profile that has never claimed ----------
	local fresh = DailyReward.status(0, 0, NOON)
	t.ok(fresh.claimable, "a new profile can claim straight away")
	t.equal(fresh.streak, 1, "a first claim starts the streak at 1")
	t.equal(fresh.cycleDay, 1, "a first claim is day 1")
	t.equal(fresh.secondsUntilNext, 0, "nothing to wait for when a reward is open")
	t.ok(DailyReward.status(nil, nil, NOON).claimable, "missing fields read as never claimed")

	-- ---------- already claimed today ----------
	local done = DailyReward.status(TODAY, 3, NOON)
	t.ok(not done.claimable, "one claim per day")
	t.equal(done.streak, 3, "a claimed day reports the streak as it stands")
	t.equal(done.secondsUntilNext, 12 * 60 * 60, "the wait runs to the next UTC midnight")
	t.ok(not DailyReward.status(TODAY, 3, NOON + 11 * 60 * 60).claimable, "still closed an hour before midnight")
	t.ok(DailyReward.status(TODAY, 3, NOON + 12 * 60 * 60).claimable, "opens on the stroke of midnight")

	-- ---------- consecutive days ----------
	local next_ = DailyReward.status(TODAY - 1, 3, NOON)
	t.ok(next_.claimable, "yesterday's claim leaves today open")
	t.equal(next_.streak, 4, "a consecutive day extends the streak")
	t.equal(next_.cycleDay, 4, "and moves one day down the cycle")

	-- ---------- a missed day ----------
	local missed = DailyReward.status(TODAY - 2, 5, NOON)
	t.ok(missed.claimable, "a missed day does not lock the reward")
	t.equal(missed.streak, 1, "a missed day resets the streak")
	t.equal(missed.cycleDay, 1, "and the cycle with it")

	-- ---------- the cycle wraps, the streak does not ----------
	local wrap = DailyReward.status(TODAY - 1, CYCLE, NOON)
	t.equal(wrap.streak, CYCLE + 1, "the streak keeps counting past the end of the cycle")
	t.equal(wrap.cycleDay, 1, "the day after the last reward is the first again")
	t.equal(DailyReward.cycleDay(CYCLE), CYCLE, "the last day of the cycle is itself")
	t.equal(DailyReward.cycleDay(CYCLE * 3 + 2), 2, "cycleDay wraps for long streaks")

	-- ---------- a clock that went backwards ----------
	local future = DailyReward.status(TODAY + 1, 2, NOON)
	t.ok(not future.claimable, "a claim day in the future cannot be claimed again")
	t.ok(future.secondsUntilNext > DAY, "and waits out the day it was claimed on")

	-- ---------- what a day pays ----------
	local first = GameConfig.DailyRewards[1]
	t.equal(DailyReward.rewardFor(1, 0), first.coins, "with no income a day pays its flat amount")
	t.equal(DailyReward.rewardFor(1, -5), first.coins, "a negative rate cannot reduce a reward")
	t.equal(DailyReward.rewardFor(CYCLE + 1, 100), 0, "a day outside the cycle pays nothing")

	local rich = 1000 -- coins per second
	t.equal(
		DailyReward.rewardFor(1, rich),
		rich * 60 * first.incomeMinutes,
		"with enough income a day pays its minutes of income instead"
	)

	local ascending = true
	for day = 2, CYCLE do
		local prev, cur = GameConfig.DailyRewards[day - 1], GameConfig.DailyRewards[day]
		if cur.coins <= prev.coins or cur.incomeMinutes <= prev.incomeMinutes then
			ascending = false
		end
	end
	t.ok(ascending, "each day of the cycle pays more than the one before, on both measures")
end
