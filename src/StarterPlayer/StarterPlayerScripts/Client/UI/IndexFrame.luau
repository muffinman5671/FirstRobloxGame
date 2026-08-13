--!strict
--[[
	IndexFrame
	The collection log: every character in the game, with the ones you haven't
	found yet shown as silhouettes, plus a completion percentage.

	Undiscovered entries deliberately still occupy a row and still show their
	rarity band. Hiding them entirely would make the list length itself a
	spoiler-free mystery, but it would also remove the thing that makes a
	collection log motivating -- seeing the gap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local Theme = require(script.Parent.Theme)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local IndexFrame = {}
IndexFrame.__index = IndexFrame

export type IndexFrame = {
	instance: Frame,
	update: (self: IndexFrame, snapshot: ProfileSnapshot?) -> (),
	setVisible: (self: IndexFrame, visible: boolean) -> (),
	destroy: (self: IndexFrame) -> (),
}

function IndexFrame.new(parent: Instance): IndexFrame
	local self = setmetatable({ _rows = {} }, IndexFrame)

	local outer, inner = Theme.panel({
		Name = "Index",
		Size = UDim2.fromOffset(460, 500),
		Position = UDim2.new(0.5, -230, 0.5, -250),
		Visible = false,
	})
	outer.Parent = parent
	self.instance = outer

	local header = Instance.new("Frame")
	header.BackgroundColor3 = Theme.COLOR.panelRaised
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, Theme.METRIC.headerHeight)
	header.Parent = inner

	local title = Theme.label("INDEX", {
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

	-- Completion readout and bar.
	self._completion = Theme.label("0 / 0 discovered", {
		Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, 22),
		Position = UDim2.fromOffset(Theme.METRIC.pad, Theme.METRIC.headerHeight + 6),
		Font = Theme.FONT.heading,
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.accent,
	})
	self._completion.Parent = inner

	local barOuter, barFill = Theme.bar(Theme.COLOR.accent)
	barOuter.Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, 12)
	barOuter.Position = UDim2.fromOffset(Theme.METRIC.pad, Theme.METRIC.headerHeight + 30)
	barOuter.Parent = inner
	self._bar = barFill

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, Theme.METRIC.headerHeight + 50)
	list.Size = UDim2.new(1, 0, 1, -(Theme.METRIC.headerHeight + 56))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.COLOR.borderLight
	list.Parent = inner
	self._list = list

	Theme.list(list, 4)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.METRIC.pad)
	pad.PaddingRight = UDim.new(0, Theme.METRIC.pad)
	pad.Parent = list

	return (self :: any) :: IndexFrame
end

function IndexFrame:update(snapshot: ProfileSnapshot?)
	for _, r in self._rows do
		r:Destroy()
	end
	table.clear(self._rows)

	if not snapshot then
		return
	end

	local discovered = snapshot.indexDiscovered or {}
	local found = 0

	-- Group by rarity, ascending, so the log reads as a progression.
	local order = {}
	for _, def in BrainrotConfig.BRAINROTS do
		table.insert(order, def)
	end
	table.sort(order, function(a, b)
		local ra, rb = Rarity.rank(a.rarity), Rarity.rank(b.rarity)
		if ra ~= rb then
			return ra < rb
		end
		return a.displayName < b.displayName
	end)

	local lastRarity = nil
	local layoutOrder = 0
	local function nextOrder()
		layoutOrder += 1
		return layoutOrder
	end

	for _, def in order do
		if def.rarity ~= lastRarity then
			lastRarity = def.rarity
			local band = Theme.label(def.rarity:upper(), {
				Size = UDim2.new(1, 0, 0, 22),
				Font = Theme.FONT.heading,
				TextSize = Theme.TEXT_SIZE.small,
				TextColor3 = Rarity.color(def.rarity),
				LayoutOrder = nextOrder(),
			})
			band.Parent = self._list
			table.insert(self._rows, band)
		end

		local known = discovered[def.id] == true
		if known then
			found += 1
		end

		local row = Instance.new("Frame")
		row.BackgroundColor3 = if known then Theme.COLOR.panelRaised else Theme.COLOR.panelSunken
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 32)
		row.LayoutOrder = nextOrder()
		row.Parent = self._list
		table.insert(self._rows, row)

		local swatch = Instance.new("Frame")
		-- Undiscovered entries keep the rarity colour but heavily dimmed, so
		-- the band is legible without revealing which character it is.
		swatch.BackgroundColor3 = if known
			then Rarity.color(def.rarity)
			else Rarity.color(def.rarity):Lerp(Color3.new(0, 0, 0), 0.72)
		swatch.BorderSizePixel = 0
		swatch.Size = UDim2.new(0, 5, 1, 0)
		swatch.Parent = row

		local name = Theme.label(if known then def.displayName else "? ? ?", {
			Size = UDim2.new(0.6, 0, 1, 0),
			Position = UDim2.fromOffset(14, 0),
			TextSize = Theme.TEXT_SIZE.small,
			TextColor3 = if known then Theme.COLOR.text else Theme.COLOR.textDisabled,
		})
		name.Parent = row

		local income = Theme.label(if known then Format.rate(def.incomePerSecond) else "--", {
			Size = UDim2.new(0.36, -14, 1, 0),
			Position = UDim2.new(0.62, 0, 0, 0),
			TextSize = Theme.TEXT_SIZE.small,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = if known then Theme.COLOR.accent else Theme.COLOR.textDisabled,
		})
		income.Parent = row
	end

	local total = BrainrotConfig.COUNT
	local fraction = if total > 0 then found / total else 0
	self._completion.Text = ("%d / %d discovered  --  %s"):format(found, total, Format.percent(fraction))
	self._bar.Size = UDim2.fromScale(fraction, 1)
end

function IndexFrame:setVisible(visible: boolean)
	self.instance.Visible = visible
end

function IndexFrame:destroy()
	self.instance:Destroy()
	table.clear(self._rows)
end

return IndexFrame
