--!strict
--[[
	ShopFrame
	Four tabs -- Pickaxes, Backpacks, Plot Slots, Layer Keys.

	Each card states what it changes relative to what you have equipped, and
	every unbuyable card says WHY it can't be bought rather than just greying
	out: locked behind the previous tier, already owned, or unaffordable. A
	disabled button with no reason is the thing that makes a shop feel broken.

	The frame decides nothing. It renders the snapshot and reports clicks; the
	server re-validates every purchase.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Modules.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LayerConfig = require(ReplicatedStorage.Shared.Config.LayerConfig)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local Theme = require(script.Parent.Theme)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local ShopFrame = {}
ShopFrame.__index = ShopFrame

local TABS = { "Pickaxes", "Backpacks", "Slots", "Layers" }
local PLOT_SLOT_ID = "plot_slot"

export type ShopFrame = {
	instance: Frame,
	update: (self: ShopFrame, snapshot: ProfileSnapshot?) -> (),
	setVisible: (self: ShopFrame, visible: boolean) -> (),
	onPurchase: (self: ShopFrame, callback: (string) -> ()) -> (),
	onEquip: (self: ShopFrame, callback: (string) -> ()) -> (),
	onUnlockLayer: (self: ShopFrame, callback: (number) -> ()) -> (),
	destroy: (self: ShopFrame) -> (),
}

function ShopFrame.new(parent: Instance): ShopFrame
	local self = setmetatable({
		_purchaseCallbacks = {},
		_equipCallbacks = {},
		_layerCallbacks = {},
		_cards = {},
		_tab = "Pickaxes",
		_snapshot = nil,
	}, ShopFrame)

	local outer, inner = Theme.panel({
		Name = "Shop",
		Size = UDim2.fromOffset(520, 500),
		Position = UDim2.new(0.5, -260, 0.5, -250),
		Visible = false,
	})
	outer.Parent = parent
	self.instance = outer

	local header = Instance.new("Frame")
	header.BackgroundColor3 = Theme.COLOR.panelRaised
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, Theme.METRIC.headerHeight)
	header.Parent = inner

	local title = Theme.label("SHOP", {
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

	-- Tab strip.
	local tabRow = Instance.new("Frame")
	tabRow.BackgroundTransparency = 1
	tabRow.Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, Theme.METRIC.tapTarget)
	tabRow.Position = UDim2.fromOffset(Theme.METRIC.pad, Theme.METRIC.headerHeight + Theme.METRIC.gap)
	tabRow.Parent = inner

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	self._tabButtons = {}
	for index, name in TABS do
		local button = Theme.button(name:upper(), {
			LayoutOrder = index,
			Size = UDim2.new(1 / #TABS, -4, 1, 0),
			TextSize = Theme.TEXT_SIZE.small,
		})
		button.Parent = tabRow
		button.Activated:Connect(function()
			self._tab = name
			self:_refreshTabs()
			self:update(self._snapshot)
		end)
		self._tabButtons[name] = button
	end

	local cards = Instance.new("ScrollingFrame")
	cards.BackgroundTransparency = 1
	cards.BorderSizePixel = 0
	cards.Position = UDim2.fromOffset(0, Theme.METRIC.headerHeight + Theme.METRIC.tapTarget + Theme.METRIC.gap * 2)
	cards.Size = UDim2.new(1, 0, 1, -(Theme.METRIC.headerHeight + Theme.METRIC.tapTarget + Theme.METRIC.gap * 3))
	cards.CanvasSize = UDim2.new()
	cards.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cards.ScrollBarThickness = 6
	cards.ScrollBarImageColor3 = Theme.COLOR.borderLight
	cards.Parent = inner
	self._cardList = cards

	Theme.list(cards, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.METRIC.pad)
	pad.PaddingRight = UDim.new(0, Theme.METRIC.pad)
	pad.Parent = cards

	self:_refreshTabs()
	return (self :: any) :: ShopFrame
end

function ShopFrame:onPurchase(callback: (string) -> ())
	table.insert(self._purchaseCallbacks, callback)
end
function ShopFrame:onEquip(callback: (string) -> ())
	table.insert(self._equipCallbacks, callback)
end
function ShopFrame:onUnlockLayer(callback: (number) -> ())
	table.insert(self._layerCallbacks, callback)
end

function ShopFrame:_refreshTabs()
	for name, button in self._tabButtons do
		button.BackgroundColor3 = if name == self._tab then Theme.COLOR.accent else Theme.COLOR.buttonIdle
		button.TextColor3 = if name == self._tab then Theme.COLOR.panelSunken else Theme.COLOR.text
	end
end

--[[
	One card. `state` is the whole reason this function is long: a card is
	either owned-and-equipped, owned, buyable, locked behind a prior tier, or
	unaffordable, and each needs different text and a different button.
]]
function ShopFrame:_buildCard(spec: {
	order: number,
	title: string,
	detail: string,
	price: number?,
	state: string,
	accent: Color3?,
	buttonLabel: string?,
	action: (() -> ())?,
})
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Theme.COLOR.panelRaised
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 76)
	card.LayoutOrder = spec.order
	card.Parent = self._cardList

	local stripe = Instance.new("Frame")
	stripe.BackgroundColor3 = spec.accent or Theme.COLOR.borderLight
	stripe.BorderSizePixel = 0
	stripe.Size = UDim2.new(0, 5, 1, 0)
	stripe.Parent = card

	local name = Theme.label(spec.title, {
		Size = UDim2.new(0.62, 0, 0, 22),
		Position = UDim2.fromOffset(14, 8),
		TextSize = Theme.TEXT_SIZE.body,
	})
	name.Parent = card

	local detail = Theme.label(spec.detail, {
		Size = UDim2.new(0.62, 0, 0, 34),
		Position = UDim2.fromOffset(14, 30),
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.textDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	detail.Parent = card

	local buttonText, enabled
	if spec.state == "equipped" then
		-- `buttonLabel` exists for the Layers tab, where the "you already have
		-- this" state should read UNLOCKED rather than EQUIPPED.
		buttonText, enabled = spec.buttonLabel or "EQUIPPED", false
	elseif spec.state == "owned" then
		buttonText, enabled = "EQUIP", true
	elseif spec.state == "locked" then
		buttonText, enabled = "LOCKED", false
	elseif spec.state == "maxed" then
		buttonText, enabled = "MAX", false
	elseif spec.state == "unaffordable" then
		buttonText, enabled = "$" .. Format.abbreviate(spec.price or 0), false
	else
		buttonText, enabled = "$" .. Format.abbreviate(spec.price or 0), true
	end

	local button = Theme.button(buttonText, {
		Size = UDim2.new(0.32, 0, 0, Theme.METRIC.tapTarget),
		Position = UDim2.new(0.66, 0, 0, 16),
		TextSize = Theme.TEXT_SIZE.small,
	})
	button:SetAttribute("Enabled", enabled)
	button.Parent = card

	if enabled and spec.action then
		button.Activated:Connect(function()
			if button:GetAttribute("Enabled") ~= false then
				spec.action()
			end
		end)
	end

	table.insert(self._cards, card)
end

function ShopFrame:_buildToolTab(snapshot: ProfileSnapshot, isPickaxe: boolean)
	local defs = if isPickaxe then ToolConfig.PICKAXES else ToolConfig.BACKPACKS
	local equippedId = if isPickaxe then snapshot.equippedPickaxe else snapshot.equippedBackpack
	local equipped = if isPickaxe then ToolConfig.getPickaxe(equippedId) else ToolConfig.getBackpack(equippedId)

	for index, def in defs do
		local owned = snapshot.ownedTools[def.id] == true
		local isEquipped = def.id == equippedId

		-- Stat delta against what's currently equipped, which is the number a
		-- player actually cares about.
		local detail: string
		if isPickaxe then
			local dp = def.power - (equipped and (equipped :: any).power or 0)
			detail = ("Power %.1f (%s%.1f)  |  %.2f swings/s  |  reach %.0f"):format(
				def.power, if dp >= 0 then "+" else "", dp, def.swingsPerSecond, def.reach
			)
		else
			local dc = def.capacity - (equipped and (equipped :: any).capacity or 0)
			detail = ("Capacity %d (%s%d)"):format(def.capacity, if dc >= 0 then "+" else "", dc)
		end

		local previous = defs[index - 1]
		local state
		if isEquipped then
			state = "equipped"
		elseif owned then
			state = "owned"
		elseif previous and not snapshot.ownedTools[previous.id] then
			state = "locked"
			detail = detail .. "  --  needs " .. previous.displayName
		elseif snapshot.coins < def.price then
			state = "unaffordable"
		else
			state = "buy"
		end

		self:_buildCard({
			order = index,
			title = ("%d. %s"):format(def.tier, def.displayName),
			detail = detail,
			price = def.price,
			state = state,
			accent = if isEquipped then Theme.COLOR.accent else nil,
			action = function()
				if state == "owned" then
					for _, cb in self._equipCallbacks do
						cb(def.id)
					end
				elseif state == "buy" then
					for _, cb in self._purchaseCallbacks do
						cb(def.id)
					end
				end
			end,
		})
	end
end

function ShopFrame:_buildSlotsTab(snapshot: ProfileSnapshot)
	local price = ToolConfig.plotSlotPrice(snapshot.plotSlots)
	local state
	if not price then
		state = "maxed"
	elseif snapshot.coins < price then
		state = "unaffordable"
	else
		state = "buy"
	end

	self:_buildCard({
		order = 1,
		title = ("Podium Slots: %d / %d"):format(snapshot.plotSlots, GameConfig.MaxPlotSlots),
		detail = if price
			then "Adds one podium to your plot. Each podium holds a brainrot earning passive income."
			else "Every podium slot unlocked.",
		price = price,
		state = state,
		accent = Theme.COLOR.accent,
		action = function()
			for _, cb in self._purchaseCallbacks do
				cb(PLOT_SLOT_ID)
			end
		end,
	})
end

function ShopFrame:_buildLayersTab(snapshot: ProfileSnapshot)
	local unlocked = {}
	for _, index in snapshot.unlockedLayers do
		unlocked[index] = true
	end

	for _, layer in LayerConfig.LAYERS do
		local state
		if unlocked[layer.index] then
			state = "equipped"
		elseif layer.index > 1 and not unlocked[layer.index - 1] then
			state = "locked"
		elseif snapshot.coins < layer.unlockCost then
			state = "unaffordable"
		else
			state = "buy"
		end

		local detail = ("Depth %d-%d studs  |  rock %.0fx tougher"):format(
			layer.minDepth, layer.maxDepth, layer.hpMultiplier
		)
		if state == "locked" then
			local previous = LayerConfig.get(layer.index - 1)
			detail = detail .. "  --  unlock " .. (previous and previous.displayName or "the layer above") .. " first"
		end

		self:_buildCard({
			order = layer.index,
			title = ("%d. %s"):format(layer.index, layer.displayName),
			detail = detail,
			price = layer.unlockCost,
			state = state,
			buttonLabel = "UNLOCKED",
			accent = if unlocked[layer.index] then Theme.COLOR.accent else nil,
			action = function()
				for _, cb in self._layerCallbacks do
					cb(layer.index)
				end
			end,
		})
	end
end

function ShopFrame:update(snapshot: ProfileSnapshot?)
	self._snapshot = snapshot

	for _, card in self._cards do
		card:Destroy()
	end
	table.clear(self._cards)

	if not snapshot then
		return
	end

	if self._tab == "Pickaxes" then
		self:_buildToolTab(snapshot, true)
	elseif self._tab == "Backpacks" then
		self:_buildToolTab(snapshot, false)
	elseif self._tab == "Slots" then
		self:_buildSlotsTab(snapshot)
	else
		self:_buildLayersTab(snapshot)
	end
end

function ShopFrame:setVisible(visible: boolean)
	self.instance.Visible = visible
end

function ShopFrame:destroy()
	self.instance:Destroy()
	table.clear(self._cards)
	table.clear(self._purchaseCallbacks)
	table.clear(self._equipCallbacks)
	table.clear(self._layerCallbacks)
end

return ShopFrame
