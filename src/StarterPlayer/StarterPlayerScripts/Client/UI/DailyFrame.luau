--!strict
--[[
	DailyFrame
	The daily reward: the cycle laid out as a row of cards, where the streak
	stands, and one button.

	A view, like the other frames. It reads the two daily fields off the
	snapshot and asks DailyReward what they mean. Pressing the button calls back
	out to UIController, and the server decides whether the claim is real -- the
	clock used here is the player's own, which is good enough to draw with and
	never trusted for anything else.

	The one thing it does unprompted is count down. While it is open it redraws
	once a second, so "NEXT REWARD IN 4h 12m" stays true and the button comes
	alive on its own when the day turns over.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DailyReward = require(ReplicatedStorage.Shared.Modules.DailyReward)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local Theme = require(script.Parent.Theme)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local DailyFrame = {}
DailyFrame.__index = DailyFrame

export type DailyFrame = {
	instance: Frame,
	update: (self: DailyFrame, snapshot: ProfileSnapshot?) -> (),
	setVisible: (self: DailyFrame, visible: boolean) -> (),
	onClaim: (self: DailyFrame, cb: () -> ()) -> (),
	destroy: (self: DailyFrame) -> (),
}

type Card = {
	frame: Frame,
	day: TextLabel,
	amount: TextLabel,
	state: TextLabel,
}

local CARD_GAP = 6
local CARDS_HEIGHT = 104
local REDRAW_SECONDS = 1

function DailyFrame.new(parent: Instance): DailyFrame
	local self = setmetatable({
		_callbacks = {} :: { () -> () },
		_cards = {} :: { Card },
		_snapshot = nil :: ProfileSnapshot?,
		-- The once-a-second redraw; connected only while the panel is open.
		_tick = nil :: RBXScriptConnection?,
	}, DailyFrame)

	local outer, inner = Theme.panel({
		Name = "Daily",
		Size = UDim2.fromOffset(520, 296),
		Position = UDim2.new(0.5, -260, 0.5, -148),
		Visible = false,
	})
	outer.Parent = parent
	self.instance = outer

	local header, close = Theme.header("Daily Rewards", { accent = Theme.COLOR.reward })
	header.Parent = inner
	close.Activated:Connect(function()
		self:setVisible(false)
	end)

	local top = Theme.METRIC.headerHeight + Theme.METRIC.gap + 2

	self._streak = Theme.label("", {
		Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, 22),
		Position = UDim2.fromOffset(Theme.METRIC.pad, top),
		Font = Theme.FONT.heading,
		TextSize = Theme.TEXT_SIZE.body,
	})
	self._streak.Parent = inner

	-- One card per day of the cycle, side by side. Each takes an equal share of
	-- the row less the gap, so the count can change in config without this
	-- needing to know.
	local days = #GameConfig.DailyRewards
	local row = Instance.new("Frame")
	row.Name = "Days"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(Theme.METRIC.pad, top + 28)
	row.Size = UDim2.new(1, -Theme.METRIC.pad * 2 + CARD_GAP, 0, CARDS_HEIGHT)
	row.Parent = inner

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.Parent = row

	for day = 1, days do
		local frame = Instance.new("Frame")
		frame.Name = `Day{day}`
		frame.BackgroundColor3 = Theme.COLOR.panelRaised
		frame.BorderSizePixel = 0
		frame.LayoutOrder = day
		frame.Size = UDim2.new(1 / days, -CARD_GAP, 1, 0)
		frame.Parent = row
		Theme.card(frame)

		local dayLabel = Theme.label(`DAY {day}`, {
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 8),
			Font = Theme.FONT.heading,
			TextSize = Theme.TEXT_SIZE.small,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		dayLabel.Parent = frame

		-- Scaled to fit, capped at heading size: a day-seven reward priced off a
		-- late-game income runs to six characters and a card is ~60px wide.
		local amount = Theme.label("", {
			Size = UDim2.new(1, -8, 0, 28),
			Position = UDim2.new(0, 4, 0.5, -15),
			Font = Theme.FONT.number,
			TextScaled = true,
			TextColor3 = Theme.COLOR.coins,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		amount.Parent = frame
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = Theme.TEXT_SIZE.heading
		limit.MinTextSize = 9
		limit.Parent = amount

		local state = Theme.label("", {
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 1, -24),
			TextSize = Theme.TEXT_SIZE.small - 2,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		state.Parent = frame

		self._cards[day] = { frame = frame, day = dayLabel, amount = amount, state = state }
	end

	local hint = Theme.label("Come back every day. Miss one and the streak starts over at day 1.", {
		Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, 34),
		Position = UDim2.fromOffset(Theme.METRIC.pad, top + 28 + CARDS_HEIGHT + 6),
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.textDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	hint.Parent = inner

	self._button = Theme.button("CLAIM", {
		accent = Theme.COLOR.reward,
		Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, Theme.METRIC.tapTarget),
		Position = UDim2.new(0, Theme.METRIC.pad, 1, -(Theme.METRIC.tapTarget + 4)),
	})
	self._button.Parent = inner

	self._button.Activated:Connect(function()
		if self._button:GetAttribute("Enabled") == false then
			return
		end
		for _, cb in self._callbacks do
			cb()
		end
	end)

	return (self :: any) :: DailyFrame
end

function DailyFrame:onClaim(cb: () -> ())
	table.insert(self._callbacks, cb)
end

-- Redraws from the last snapshot against the clock as it is now. Split from
-- `update` because the countdown needs it without a new snapshot arriving.
function DailyFrame:_refresh()
	local snapshot: ProfileSnapshot? = self._snapshot
	if not snapshot then
		return
	end

	local status = DailyReward.status(snapshot.dailyLastClaimDay, snapshot.dailyStreak, os.time())

	-- Cards up to this one are behind the player. While today's reward is
	-- waiting that stops short of it; once claimed, it is one of them.
	local claimedThrough = if status.claimable then status.cycleDay - 1 else status.cycleDay

	for day, card in self._cards do
		local isToday = status.claimable and day == status.cycleDay
		local isClaimed = day <= claimedThrough

		-- Priced off current income, so a later day shows what it would pay
		-- today. It can only grow from there.
		card.amount.Text = "$" .. Format.abbreviate(DailyReward.rewardFor(day, snapshot.incomePerSecond))

		card.frame.BackgroundColor3 = if isToday
			then Theme.COLOR.reward
			elseif isClaimed then Theme.COLOR.panelSunken
			else Theme.COLOR.panelRaised
		card.state.Text = if isToday then "TODAY" elseif isClaimed then "CLAIMED" else ""

		card.day.TextColor3 = if isClaimed then Theme.COLOR.textDisabled else Theme.COLOR.text
		card.state.TextColor3 = if isToday then Theme.COLOR.text else Theme.COLOR.textDisabled
		card.amount.TextColor3 = if isClaimed
			then Theme.COLOR.textDisabled
			elseif isToday then Theme.COLOR.text
			else Theme.COLOR.coins
	end

	if status.claimable then
		self._streak.Text = if status.streak > 1
			then `Streak: {status.streak - 1} days  --  claim to make it {status.streak}`
			else "Claim today to start a streak"

		local reward = DailyReward.rewardFor(status.cycleDay, snapshot.incomePerSecond)
		self._button:SetAttribute("Enabled", true)
		-- Concatenation, not interpolation, for the same reason RebirthFrame
		-- gives: a `$` next to a brace is too easy to get wrong.
		self._button.Text = "CLAIM DAY " .. status.cycleDay .. "   +$" .. Format.abbreviate(reward)
	else
		self._streak.Text = `Streak: {status.streak} {if status.streak == 1 then "day" else "days"}`
		self._button:SetAttribute("Enabled", false)
		self._button.Text = "NEXT REWARD IN " .. Format.duration(status.secondsUntilNext)
	end
end

function DailyFrame:update(snapshot: ProfileSnapshot?)
	self._snapshot = snapshot
	self:_refresh()
end

function DailyFrame:setVisible(visible: boolean)
	self.instance.Visible = visible

	if visible and not self._tick then
		self:_refresh()
		local elapsed = 0
		self._tick = RunService.Heartbeat:Connect(function(dt: number)
			elapsed += dt
			if elapsed >= REDRAW_SECONDS then
				elapsed = 0
				self:_refresh()
			end
		end)
	elseif not visible and self._tick then
		self._tick:Disconnect()
		self._tick = nil
	end
end

function DailyFrame:destroy()
	if self._tick then
		self._tick:Disconnect()
		self._tick = nil
	end
	self.instance:Destroy()
	table.clear(self._callbacks)
	table.clear(self._cards)
end

return DailyFrame
