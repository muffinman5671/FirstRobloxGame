--!strict
--[[
	DailyReward
	The rules of the daily reward: when it can be claimed, which day of the
	cycle that is, and what it pays.

	Pure, and shared. The server decides with it, the Daily screen draws with
	it, and the tests drive it with fixed clocks. Nothing here reads os.time() --
	the caller passes the time in, which is what makes "the day rolls over"
	something a test can ask about.

	A day is a UTC calendar day, and the reward can be claimed once in each. The
	streak survives as long as no whole day is skipped: claim on Monday and
	again on Tuesday and it grows, miss Tuesday and Wednesday starts over at day
	1. The rewards themselves repeat every #GameConfig.DailyRewards days, while
	the streak count keeps climbing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DailyReward = {}

local SECONDS_PER_DAY = 24 * 60 * 60

export type Status = {
	claimable: boolean,
	-- The streak once today's reward is claimed -- or as it stands, if it
	-- already has been.
	streak: number,
	-- Which entry of GameConfig.DailyRewards that streak lands on. 1-based.
	cycleDay: number,
	-- Until the next reward opens. 0 when one is claimable now.
	secondsUntilNext: number,
}

-- Days since the Unix epoch, in UTC. Two timestamps share a reward day exactly
-- when this matches.
function DailyReward.dayIndex(unix: number): number
	return math.floor(unix / SECONDS_PER_DAY)
end

function DailyReward.cycleDay(streak: number): number
	return (math.max(streak, 1) - 1) % #GameConfig.DailyRewards + 1
end

--[[
	Where a profile stands at `nowUnix`. `lastClaimDay` is the dayIndex of the
	last claim, 0 if there has never been one.
]]
function DailyReward.status(lastClaimDay: number?, streak: number?, nowUnix: number): Status
	local today = DailyReward.dayIndex(nowUnix)
	local last = lastClaimDay or 0
	local held = math.max(streak or 0, 0)

	-- `>=` rather than `==`: a claim day in the future means a clock stepped
	-- backwards, and that must wait rather than pay out a second time.
	if last >= today then
		return {
			claimable = false,
			streak = held,
			cycleDay = DailyReward.cycleDay(held),
			secondsUntilNext = (last + 1) * SECONDS_PER_DAY - nowUnix,
		}
	end

	local nextStreak = if last == today - 1 then held + 1 else 1
	return {
		claimable = true,
		streak = nextStreak,
		cycleDay = DailyReward.cycleDay(nextStreak),
		secondsUntilNext = 0,
	}
end

--[[
	Coins for a day of the cycle: the flat amount, or that day's minutes of the
	player's passive income, whichever is larger. See GameConfig.DailyRewards.
]]
function DailyReward.rewardFor(cycleDay: number, incomePerSecond: number): number
	local entry = GameConfig.DailyRewards[cycleDay]
	if not entry then
		return 0
	end
	return math.max(entry.coins, math.floor(math.max(incomePerSecond, 0) * 60 * entry.incomeMinutes))
end

return table.freeze(DailyReward)
