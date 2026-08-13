--!strict
--[[
	RebirthFrame
	Requirement check, multiplier preview, and a confirm step.

	Rebirth is the only irreversible action a player can take, so this screen
	spells out exactly what is lost and what is kept before the confirm button
	becomes live. The two-step confirm exists because "I didn't know it would
	reset my tools" is not a recoverable mistake.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Modules.Format)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local Theme = require(script.Parent.Theme)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local RebirthFrame = {}
RebirthFrame.__index = RebirthFrame

export type RebirthFrame = {
	instance: Frame,
	update: (self: RebirthFrame, snapshot: ProfileSnapshot?) -> (),
	setVisible: (self: RebirthFrame, visible: boolean) -> (),
	onRebirth: (self: RebirthFrame, cb: () -> ()) -> (),
	destroy: (self: RebirthFrame) -> (),
}

function RebirthFrame.new(parent: Instance): RebirthFrame
	local self = setmetatable({ _callbacks = {}, _armed = false }, RebirthFrame)

	local outer, inner = Theme.panel({
		Name = "Rebirth",
		Size = UDim2.fromOffset(420, 380),
		Position = UDim2.new(0.5, -210, 0.5, -190),
		Visible = false,
	})
	outer.Parent = parent
	self.instance = outer

	local header = Instance.new("Frame")
	header.BackgroundColor3 = Theme.COLOR.panelRaised
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, Theme.METRIC.headerHeight)
	header.Parent = inner

	local title = Theme.label("REBIRTH", {
		Font = Theme.FONT.heading,
		TextSize = Theme.TEXT_SIZE.heading,
		Size = UDim2.new(1, -Theme.METRIC.tapTarget, 1, 0),
		Position = UDim2.fromOffset(Theme.METRIC.pad, 0),
	})
	title.Parent = header

	local close = Theme.button("X", {
		Size = UDim2.fromOffset(Theme.METRIC.tapTarget, Theme.METRIC.headerHeight),
		Position = UDim2.new(1, -Theme.METRIC.tapTarget, 0, 0),
	})
	close.Parent = header
	close.Activated:Connect(function()
		self:setVisible(false)
	end)

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(Theme.METRIC.pad, Theme.METRIC.headerHeight + Theme.METRIC.gap)
	body.Size = UDim2.new(1, -Theme.METRIC.pad * 2, 1, -(Theme.METRIC.headerHeight + Theme.METRIC.tapTarget + 26))
	body.Parent = inner
	Theme.list(body, 6)

	self._current = Theme.label("", {
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 1,
		Font = Theme.FONT.heading,
		TextSize = Theme.TEXT_SIZE.body,
	})
	self._current.Parent = body

	self._preview = Theme.label("", {
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 2,
		TextSize = Theme.TEXT_SIZE.body,
		TextColor3 = Theme.COLOR.accent,
	})
	self._preview.Parent = body

	self._requirement = Theme.label("", {
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 3,
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.coins,
	})
	self._requirement.Parent = body

	local lost = Theme.label(
		"RESETS:  coins, all pickaxes and backpacks, and any ore you are carrying.",
		{
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = 4,
			TextSize = Theme.TEXT_SIZE.small,
			TextColor3 = Theme.COLOR.danger,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		}
	)
	lost.Parent = body

	local kept = Theme.label(
		"KEEPS:  unlocked layers, every brainrot you own and have placed, podium slots, and your index.",
		{
			Size = UDim2.new(1, 0, 0, 52),
			LayoutOrder = 5,
			TextSize = Theme.TEXT_SIZE.small,
			TextColor3 = Theme.COLOR.textDim,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		}
	)
	kept.Parent = body

	self._button = Theme.button("REBIRTH", {
		Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, Theme.METRIC.tapTarget),
		Position = UDim2.new(0, Theme.METRIC.pad, 1, -(Theme.METRIC.tapTarget + 4)),
	})
	self._button.Parent = inner

	self._button.Activated:Connect(function()
		if self._button:GetAttribute("Enabled") == false then
			return
		end

		-- Two-step: the first press arms, the second commits. Arming resets
		-- whenever the panel closes or the snapshot changes, so a stale armed
		-- state can never fire on a later click.
		if not self._armed then
			self._armed = true
			self._button.Text = "CONFIRM -- THIS CANNOT BE UNDONE"
			self._button.BackgroundColor3 = Theme.COLOR.danger
			return
		end

		self._armed = false
		for _, cb in self._callbacks do
			cb()
		end
	end)

	return (self :: any) :: RebirthFrame
end

function RebirthFrame:onRebirth(cb: () -> ())
	table.insert(self._callbacks, cb)
end

function RebirthFrame:update(snapshot: ProfileSnapshot?)
	-- Any state change disarms: the numbers the player confirmed against may
	-- no longer hold.
	self._armed = false

	if not snapshot then
		return
	end

	local cost = ToolConfig.rebirthCost(snapshot.rebirths)
	local current = ToolConfig.rebirthMultiplier(snapshot.rebirths)
	local next_ = ToolConfig.rebirthMultiplier(snapshot.rebirths + 1)
	local affordable = snapshot.coins >= cost

	self._current.Text = ("Rebirths: %d  --  %.2fx multiplier"):format(snapshot.rebirths, current)
	self._preview.Text = ("After rebirth: %.2fx  (mining, income, and sale value)"):format(next_)
	self._requirement.Text = ("Cost: $%s  --  you have $%s"):format(
		Format.abbreviate(cost),
		Format.abbreviate(snapshot.coins)
	)

	self._button:SetAttribute("Enabled", affordable)
	-- Concatenation, not interpolation: `$$` in a Luau interpolated string is
	-- two literal dollars, not an escape, and renders as "NEED $$250K MORE".
	self._button.Text = if affordable
		then "REBIRTH"
		else "NEED $" .. Format.abbreviate(cost - snapshot.coins) .. " MORE"
	self._button.BackgroundColor3 = if affordable then Theme.COLOR.buttonIdle else Theme.COLOR.buttonDisabled
end

function RebirthFrame:setVisible(visible: boolean)
	self.instance.Visible = visible
	if not visible then
		self._armed = false
	end
end

function RebirthFrame:destroy()
	self.instance:Destroy()
	table.clear(self._callbacks)
end

return RebirthFrame
