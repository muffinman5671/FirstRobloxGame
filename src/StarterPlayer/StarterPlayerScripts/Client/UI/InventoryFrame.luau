--!strict
--[[
	InventoryFrame
	Ore held, what it is worth, and the two ways to sell it.

	Rows are rebuilt from the snapshot on every update. The inventory is at most
	twenty rows, so pooling them would be more code than it saves, and a full
	rebuild means the view can never drift out of step with the profile.

	Prices shown here are the client's own calculation from OreConfig, purely so
	the numbers appear instantly. The server recomputes the payout on sale and
	its figure is the one that counts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Modules.Format)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local Theme = require(script.Parent.Theme)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local InventoryFrame = {}
InventoryFrame.__index = InventoryFrame

export type InventoryFrame = {
	instance: Frame,
	update: (self: InventoryFrame, snapshot: ProfileSnapshot?) -> (),
	setVisible: (self: InventoryFrame, visible: boolean) -> (),
	onSell: (self: InventoryFrame, callback: (string?) -> ()) -> (),
	destroy: (self: InventoryFrame) -> (),
}

function InventoryFrame.new(parent: Instance): InventoryFrame
	local self = setmetatable({ _sellCallbacks = {}, _rows = {} }, InventoryFrame)

	local outer, inner = Theme.panel({
		Name = "Inventory",
		Size = UDim2.fromOffset(420, 460),
		Position = UDim2.new(0.5, -210, 0.5, -230),
		Visible = false,
	})
	outer.Parent = parent
	self.instance = outer

	-- Header
	local header = Instance.new("Frame")
	header.BackgroundColor3 = Theme.COLOR.panelRaised
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, Theme.METRIC.headerHeight)
	header.Parent = inner

	local title = Theme.label("BACKPACK", {
		Font = Theme.FONT.heading,
		TextSize = Theme.TEXT_SIZE.heading,
		Size = UDim2.new(1, -Theme.METRIC.tapTarget, 1, 0),
		Position = UDim2.fromOffset(Theme.METRIC.pad, 0),
	})
	title.Parent = header

	self._close = Theme.button("X", {
		Size = UDim2.fromOffset(Theme.METRIC.tapTarget, Theme.METRIC.headerHeight),
		Position = UDim2.new(1, -Theme.METRIC.tapTarget, 0, 0),
	})
	self._close.Parent = header

	-- Scrolling list of ore rows.
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, Theme.METRIC.headerHeight + Theme.METRIC.gap)
	list.Size = UDim2.new(1, 0, 1, -(Theme.METRIC.headerHeight + Theme.METRIC.tapTarget + 56))
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

	-- Empty state, shown instead of the rows when the bag is empty.
	self._empty = Theme.label("Bag is empty -- go break some rock.", {
		Size = UDim2.new(1, 0, 0, 40),
		TextColor3 = Theme.COLOR.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})
	self._empty.Parent = list

	-- Footer: total and Sell All.
	self._total = Theme.label("Total: $0", {
		Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, 22),
		Position = UDim2.new(0, Theme.METRIC.pad, 1, -(Theme.METRIC.tapTarget + 30)),
		TextColor3 = Theme.COLOR.coins,
		Font = Theme.FONT.heading,
	})
	self._total.Parent = inner

	self._sellAll = Theme.button("SELL ALL", {
		Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, Theme.METRIC.tapTarget),
		Position = UDim2.new(0, Theme.METRIC.pad, 1, -(Theme.METRIC.tapTarget + 4)),
	})
	self._sellAll.Parent = inner

	self._sellAll.Activated:Connect(function()
		if self._sellAll:GetAttribute("Enabled") == false then
			return
		end
		for _, callback in self._sellCallbacks do
			callback(nil)
		end
	end)

	self._close.Activated:Connect(function()
		self:setVisible(false)
	end)

	return (self :: any) :: InventoryFrame
end

function InventoryFrame:onSell(callback: (string?) -> ())
	table.insert(self._sellCallbacks, callback)
end

-- One row: rarity swatch, name, count, value, and a per-ore sell button.
function InventoryFrame:_buildRow(oreId: string, count: number, multiplier: number, order: number)
	local ore = OreConfig.get(oreId)
	if not ore then
		return
	end

	local row = Instance.new("Frame")
	row.BackgroundColor3 = Theme.COLOR.panelRaised
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, Theme.METRIC.tapTarget)
	row.LayoutOrder = order
	row.Parent = self._list

	-- Rarity reads as a colour bar rather than a word, so the row stays short.
	local swatch = Instance.new("Frame")
	swatch.BackgroundColor3 = Rarity.color(ore.rarity)
	swatch.BorderSizePixel = 0
	swatch.Size = UDim2.new(0, 5, 1, 0)
	swatch.Parent = row

	local name = Theme.label(ore.displayName, {
		Size = UDim2.new(0.46, 0, 1, 0),
		Position = UDim2.fromOffset(13, 0),
		TextSize = Theme.TEXT_SIZE.small,
	})
	name.Parent = row

	local amount = Theme.label(("x%d"):format(count), {
		Size = UDim2.new(0.14, 0, 1, 0),
		Position = UDim2.new(0.46, 13, 0, 0),
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.textDim,
	})
	amount.Parent = row

	local value = Theme.label("$" .. Format.abbreviate(math.floor(ore.baseValue * count * multiplier)), {
		Size = UDim2.new(0.2, 0, 1, 0),
		Position = UDim2.new(0.6, 13, 0, 0),
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.coins,
	})
	value.Parent = row

	local sell = Theme.button("SELL", {
		Size = UDim2.new(0.2, -8, 1, -8),
		Position = UDim2.new(0.8, 0, 0, 4),
		TextSize = Theme.TEXT_SIZE.small,
	})
	sell.Parent = row

	sell.Activated:Connect(function()
		for _, callback in self._sellCallbacks do
			callback(oreId)
		end
	end)

	table.insert(self._rows, row)
end

function InventoryFrame:update(snapshot: ProfileSnapshot?)
	for _, row in self._rows do
		row:Destroy()
	end
	table.clear(self._rows)

	if not snapshot then
		return
	end

	local multiplier = ToolConfig.rebirthMultiplier(snapshot.rebirths)

	-- Sort by rarity then name, so the valuable things sit together and the
	-- order doesn't jump around as counts change.
	local held = {}
	for oreId, count in snapshot.oreCounts do
		if count > 0 and OreConfig.exists(oreId) then
			table.insert(held, oreId)
		end
	end
	table.sort(held, function(a, b)
		local oreA, oreB = OreConfig.get(a), OreConfig.get(b)
		local rankA, rankB = Rarity.rank(oreA.rarity), Rarity.rank(oreB.rarity)
		if rankA ~= rankB then
			return rankA > rankB
		end
		return oreA.displayName < oreB.displayName
	end)

	local total = 0
	for index, oreId in held do
		local count = snapshot.oreCounts[oreId]
		self:_buildRow(oreId, count, multiplier, index)
		total += OreConfig.get(oreId).baseValue * count
	end

	total = math.floor(total * multiplier)
	self._empty.Visible = #held == 0
	self._empty.LayoutOrder = 999
	self._total.Text = "Total: $" .. Format.abbreviate(total)
	self._sellAll:SetAttribute("Enabled", #held > 0)
	self._sellAll.Text = if #held > 0 then "SELL ALL" else "NOTHING TO SELL"
end

function InventoryFrame:setVisible(visible: boolean)
	self.instance.Visible = visible
end

function InventoryFrame:destroy()
	self.instance:Destroy()
	table.clear(self._sellCallbacks)
	table.clear(self._rows)
end

return InventoryFrame
