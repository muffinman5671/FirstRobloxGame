--!strict
--[[
	ConvertFrame
	Two tabs: Convert (feed ore, roll a brainrot) and Brainrots (place, unplace,
	sell what you own).

	Placement shares this frame rather than getting its own, because the two are
	the same loop -- you convert, then you place what you got. IndexFrame in
	§6 is a different thing (the collection log of everything discovered) and
	belongs to phase E.

	The odds table is computed from the same shared Conversion module the server
	rolls with, so the percentages shown are the real ones. The doc asks for
	honest odds; sharing the function is the only way to guarantee it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local Conversion = require(ReplicatedStorage.Shared.Modules.Conversion)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local Theme = require(script.Parent.Theme)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local ConvertFrame = {}
ConvertFrame.__index = ConvertFrame

export type ConvertFrame = {
	instance: Frame,
	update: (self: ConvertFrame, snapshot: ProfileSnapshot?) -> (),
	setVisible: (self: ConvertFrame, visible: boolean) -> (),
	showReveal: (self: ConvertFrame, result: any) -> (),
	onConvert: (self: ConvertFrame, cb: (string) -> ()) -> (),
	onPlace: (self: ConvertFrame, cb: (string, number) -> ()) -> (),
	onUnplace: (self: ConvertFrame, cb: (number) -> ()) -> (),
	onSellBrainrot: (self: ConvertFrame, cb: (string) -> ()) -> (),
	destroy: (self: ConvertFrame) -> (),
}

function ConvertFrame.new(parent: Instance): ConvertFrame
	local self = setmetatable({
		_convertCallbacks = {},
		_placeCallbacks = {},
		_unplaceCallbacks = {},
		_sellCallbacks = {},
		_rows = {},
		_tab = "Convert",
		_selectedOre = nil,
		_snapshot = nil,
	}, ConvertFrame)

	local outer, inner = Theme.panel({
		Name = "Convert",
		Size = UDim2.fromOffset(500, 520),
		Position = UDim2.new(0.5, -250, 0.5, -260),
		Visible = false,
	})
	outer.Parent = parent
	self.instance = outer

	local header = Instance.new("Frame")
	header.BackgroundColor3 = Theme.COLOR.panelRaised
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, Theme.METRIC.headerHeight)
	header.Parent = inner

	local title = Theme.label("CONVERSION CHAMBER", {
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

	-- Tabs
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
	for index, name in { "Convert", "Brainrots" } do
		local button = Theme.button(name:upper(), {
			LayoutOrder = index,
			Size = UDim2.new(0.5, -4, 1, 0),
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

	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(0, Theme.METRIC.headerHeight + Theme.METRIC.tapTarget + Theme.METRIC.gap * 2)
	body.Size = UDim2.new(1, 0, 1, -(Theme.METRIC.headerHeight + Theme.METRIC.tapTarget * 2 + Theme.METRIC.gap * 4))
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 6
	body.ScrollBarImageColor3 = Theme.COLOR.borderLight
	body.Parent = inner
	self._body = body

	Theme.list(body, 5)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.METRIC.pad)
	pad.PaddingRight = UDim.new(0, Theme.METRIC.pad)
	pad.Parent = body

	-- Roll button, only meaningful on the Convert tab.
	self._roll = Theme.button("SELECT AN ORE", {
		Size = UDim2.new(1, -Theme.METRIC.pad * 2, 0, Theme.METRIC.tapTarget),
		Position = UDim2.new(0, Theme.METRIC.pad, 1, -(Theme.METRIC.tapTarget + 4)),
	})
	self._roll:SetAttribute("Enabled", false)
	self._roll.Parent = inner
	self._roll.Activated:Connect(function()
		if self._roll:GetAttribute("Enabled") == false or not self._selectedOre then
			return
		end
		for _, cb in self._convertCallbacks do
			cb(self._selectedOre)
		end
	end)

	-- Reveal overlay, shown over everything during the suspense beat.
	local reveal, revealInner = Theme.panel({
		Name = "Reveal",
		Size = UDim2.fromOffset(360, 150),
		Position = UDim2.new(0.5, -180, 0.5, -75),
		Visible = false,
		ZIndex = 20,
	})
	reveal.Parent = parent
	self._reveal = reveal

	self._revealText = Theme.label("", {
		Size = UDim2.new(1, 0, 0.55, 0),
		Font = Theme.FONT.heading,
		TextSize = Theme.TEXT_SIZE.title,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 21,
	})
	self._revealText.Parent = revealInner

	self._revealSub = Theme.label("", {
		Size = UDim2.new(1, 0, 0.45, 0),
		Position = UDim2.fromScale(0, 0.55),
		TextSize = Theme.TEXT_SIZE.body,
		TextColor3 = Theme.COLOR.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 21,
	})
	self._revealSub.Parent = revealInner

	self:_refreshTabs()
	return (self :: any) :: ConvertFrame
end

function ConvertFrame:onConvert(cb) table.insert(self._convertCallbacks, cb) end
function ConvertFrame:onPlace(cb) table.insert(self._placeCallbacks, cb) end
function ConvertFrame:onUnplace(cb) table.insert(self._unplaceCallbacks, cb) end
function ConvertFrame:onSellBrainrot(cb) table.insert(self._sellCallbacks, cb) end

function ConvertFrame:_refreshTabs()
	for name, button in self._tabButtons do
		button.BackgroundColor3 = if name == self._tab then Theme.COLOR.accent else Theme.COLOR.buttonIdle
		button.TextColor3 = if name == self._tab then Theme.COLOR.panelSunken else Theme.COLOR.text
	end
	self._roll.Visible = self._tab == "Convert"
end

local function row(parent: Instance, order: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.COLOR.panelRaised
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.LayoutOrder = order
	frame.Parent = parent
	return frame
end

-- ---------- Convert tab ----------

function ConvertFrame:_buildConvertTab(snapshot: ProfileSnapshot)
	local cost = Conversion.cost()

	local held = {}
	for oreId, count in snapshot.oreCounts do
		if count > 0 and OreConfig.exists(oreId) then
			table.insert(held, oreId)
		end
	end
	table.sort(held, function(a, b)
		local oa, ob = OreConfig.get(a), OreConfig.get(b)
		local ra, rb = Rarity.rank(oa.rarity), Rarity.rank(ob.rarity)
		if ra ~= rb then return ra > rb end
		return oa.displayName < ob.displayName
	end)

	-- Selected ore must still be held, or the roll button lies.
	if self._selectedOre and (snapshot.oreCounts[self._selectedOre] or 0) < cost then
		self._selectedOre = nil
	end

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	if #held == 0 then
		local empty = Theme.label(`No ore. Each roll costs {cost} of a single type.`, {
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = Theme.COLOR.textDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = nextOrder(),
		})
		empty.Parent = self._body
		table.insert(self._rows, empty)
	end

	for _, oreId in held do
		local ore = OreConfig.get(oreId)
		local count = snapshot.oreCounts[oreId]
		local affordable = count >= cost
		local selected = self._selectedOre == oreId

		local frame = row(self._body, nextOrder(), Theme.METRIC.tapTarget)
		table.insert(self._rows, frame)

		local swatch = Instance.new("Frame")
		swatch.BackgroundColor3 = if selected then Theme.COLOR.accent else Rarity.color(ore.rarity)
		swatch.BorderSizePixel = 0
		swatch.Size = UDim2.new(0, if selected then 9 else 5, 1, 0)
		swatch.Parent = frame

		local name = Theme.label(("%s  x%d"):format(ore.displayName, count), {
			Size = UDim2.new(0.62, 0, 1, 0),
			Position = UDim2.fromOffset(16, 0),
			TextSize = Theme.TEXT_SIZE.small,
			TextColor3 = if affordable then Theme.COLOR.text else Theme.COLOR.textDisabled,
		})
		name.Parent = frame

		local pick = Theme.button(if selected then "SELECTED" else "SELECT", {
			Size = UDim2.new(0.32, -8, 1, -8),
			Position = UDim2.new(0.68, 0, 0, 4),
			TextSize = Theme.TEXT_SIZE.small,
		})
		pick:SetAttribute("Enabled", affordable and not selected)
		pick.Parent = frame
		pick.Activated:Connect(function()
			if pick:GetAttribute("Enabled") == false then return end
			self._selectedOre = oreId
			self:update(self._snapshot)
		end)
	end

	-- Odds, computed from the same table the server rolls.
	local oddsHeader = Theme.label(
		if self._selectedOre
			then `ODDS  --  biased by {OreConfig.get(self._selectedOre).displayName}`
			else "ODDS  --  base, before ore bias",
		{
			Size = UDim2.new(1, 0, 0, 26),
			Font = Theme.FONT.heading,
			TextSize = Theme.TEXT_SIZE.small,
			TextColor3 = Theme.COLOR.textDim,
			LayoutOrder = nextOrder(),
		}
	)
	oddsHeader.Parent = self._body
	table.insert(self._rows, oddsHeader)

	local rarityOdds = Conversion.rarityOdds(self._selectedOre)
	for _, rarity in Rarity.ORDER do
		local chance = rarityOdds[rarity] or 0
		local frame = row(self._body, nextOrder(), 24)
		table.insert(self._rows, frame)

		local swatch = Instance.new("Frame")
		swatch.BackgroundColor3 = Rarity.color(rarity)
		swatch.BorderSizePixel = 0
		swatch.Size = UDim2.new(0, 5, 1, 0)
		swatch.Parent = frame

		local label = Theme.label(rarity, {
			Size = UDim2.new(0.5, 0, 1, 0),
			Position = UDim2.fromOffset(14, 0),
			TextSize = Theme.TEXT_SIZE.small,
		})
		label.Parent = frame

		local pct = Theme.label(Format.percent(chance, if chance < 0.01 then 3 else 1), {
			Size = UDim2.new(0.4, -14, 1, 0),
			Position = UDim2.new(0.6, 0, 0, 0),
			TextSize = Theme.TEXT_SIZE.small,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Rarity.color(rarity),
		})
		pct.Parent = frame
	end

	local pity = Theme.label(
		`Guaranteed {require(ReplicatedStorage.Shared.Config.GameConfig).PityMinimumRarity}+ at least every `
			.. `{require(ReplicatedStorage.Shared.Config.GameConfig).PityThreshold} rolls.`,
		{
			Size = UDim2.new(1, 0, 0, 30),
			TextSize = Theme.TEXT_SIZE.small,
			TextColor3 = Theme.COLOR.textDim,
			TextWrapped = true,
			LayoutOrder = nextOrder(),
		}
	)
	pity.Parent = self._body
	table.insert(self._rows, pity)

	if self._selectedOre then
		self._roll.Text = `ROLL  --  {cost} {OreConfig.get(self._selectedOre).displayName}`
		self._roll:SetAttribute("Enabled", true)
	else
		self._roll.Text = if #held > 0 then "SELECT AN ORE" else `NEED {cost} ORE`
		self._roll:SetAttribute("Enabled", false)
	end
end

-- ---------- Brainrots tab ----------

function ConvertFrame:_buildBrainrotsTab(snapshot: ProfileSnapshot)
	local placedByUid: { [string]: number } = {}
	for _, placed in snapshot.placedBrainrots do
		placedByUid[placed.uid] = placed.slot
	end

	-- Lowest free slot, so "Place" never needs the player to pick a number.
	local occupied: { [number]: boolean } = {}
	for _, slot in placedByUid do
		occupied[slot] = true
	end
	local freeSlot: number? = nil
	for slot = 1, snapshot.plotSlots do
		if not occupied[slot] then
			freeSlot = slot
			break
		end
	end

	local owned = table.clone(snapshot.brainrotsOwned)
	table.sort(owned, function(a, b)
		local da, db = BrainrotConfig.get(a.brainrotId), BrainrotConfig.get(b.brainrotId)
		if not da or not db then return false end
		local ra, rb = Rarity.rank(da.rarity), Rarity.rank(db.rarity)
		if ra ~= rb then return ra > rb end
		return da.displayName < db.displayName
	end)

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local summary = Theme.label(
		("%d owned  |  %d / %d podiums used"):format(#owned, (function()
			local n = 0 for _ in placedByUid do n += 1 end return n
		end)(), snapshot.plotSlots),
		{
			Size = UDim2.new(1, 0, 0, 26),
			Font = Theme.FONT.heading,
			TextSize = Theme.TEXT_SIZE.small,
			TextColor3 = Theme.COLOR.textDim,
			LayoutOrder = nextOrder(),
		}
	)
	summary.Parent = self._body
	table.insert(self._rows, summary)

	if #owned == 0 then
		local empty = Theme.label("Nothing yet -- convert some ore.", {
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = Theme.COLOR.textDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = nextOrder(),
		})
		empty.Parent = self._body
		table.insert(self._rows, empty)
		return
	end

	for _, entry in owned do
		local def = BrainrotConfig.get(entry.brainrotId)
		if def then
			local slot = placedByUid[entry.uid]
			local frame = row(self._body, nextOrder(), 58)
			table.insert(self._rows, frame)

			local swatch = Instance.new("Frame")
			swatch.BackgroundColor3 = Rarity.color(def.rarity)
			swatch.BorderSizePixel = 0
			swatch.Size = UDim2.new(0, 5, 1, 0)
			swatch.Parent = frame

			local name = Theme.label(
				if entry.mutation == "Normal" then def.displayName else `{entry.mutation} {def.displayName}`,
				{
					Size = UDim2.new(0.56, 0, 0, 22),
					Position = UDim2.fromOffset(14, 6),
					TextSize = Theme.TEXT_SIZE.small,
				}
			)
			name.Parent = frame

			local detail = Theme.label(
				("%s  |  %s  |  %s"):format(
					def.rarity,
					Format.rate(BrainrotConfig.incomeFor(entry.brainrotId, entry.mutation)),
					if slot then `podium {slot}` else "stored"
				),
				{
					Size = UDim2.new(0.56, 0, 0, 20),
					Position = UDim2.fromOffset(14, 28),
					TextSize = Theme.TEXT_SIZE.small,
					TextColor3 = Theme.COLOR.textDim,
				}
			)
			detail.Parent = frame

			local main = Theme.button(if slot then "REMOVE" else "PLACE", {
				Size = UDim2.new(0.22, -6, 0, Theme.METRIC.tapTarget - 10),
				Position = UDim2.new(0.58, 0, 0, 7),
				TextSize = Theme.TEXT_SIZE.small,
			})
			main:SetAttribute("Enabled", slot ~= nil or freeSlot ~= nil)
			main.Parent = frame
			main.Activated:Connect(function()
				if main:GetAttribute("Enabled") == false then return end
				if slot then
					for _, cb in self._unplaceCallbacks do cb(slot) end
				elseif freeSlot then
					for _, cb in self._placeCallbacks do cb(entry.uid, freeSlot) end
				end
			end)

			local sell = Theme.button("$" .. Format.abbreviate(
				BrainrotConfig.sellValueFor(entry.brainrotId, entry.mutation)
			), {
				Size = UDim2.new(0.2, -6, 0, Theme.METRIC.tapTarget - 10),
				Position = UDim2.new(0.8, 0, 0, 7),
				TextSize = Theme.TEXT_SIZE.small,
			})
			sell.Parent = frame
			sell.Activated:Connect(function()
				for _, cb in self._sellCallbacks do cb(entry.uid) end
			end)
		end
	end
end

function ConvertFrame:update(snapshot: ProfileSnapshot?)
	self._snapshot = snapshot

	for _, r in self._rows do
		r:Destroy()
	end
	table.clear(self._rows)

	if not snapshot then
		return
	end

	if self._tab == "Convert" then
		self:_buildConvertTab(snapshot)
	else
		self:_buildBrainrotsTab(snapshot)
	end
end

--[[
	Suspense, then reveal. The hold scales with rarity via Rarity.REVEAL_SECONDS
	so a Mythic gets a genuinely longer beat than a Common.
]]
function ConvertFrame:showReveal(result: any)
	if not result or not result.ok then
		return
	end

	local def = BrainrotConfig.get(result.brainrotId)
	if not def then
		return
	end

	local hold = Rarity.REVEAL_SECONDS[result.rarity] or 0.5
	self._reveal.Visible = true
	self._revealSub.Text = ""

	task.spawn(function()
		-- Stepped, not a smooth fade: the art direction calls for snappy.
		local frames = { "?", "? ?", "? ? ?", "? ?", "?" }
		local elapsed = 0
		local index = 1
		while elapsed < hold do
			self._revealText.Text = frames[(index - 1) % #frames + 1]
			self._revealText.TextColor3 = Theme.COLOR.textDim
			index += 1
			elapsed += 0.12
			task.wait(0.12)
		end

		self._revealText.Text = if result.mutation == "Normal"
			then def.displayName
			else `{result.mutation} {def.displayName}`
		self._revealText.TextColor3 = Rarity.color(result.rarity)

		local notes = { result.rarity }
		if result.isNewDiscovery then
			table.insert(notes, "NEW")
		end
		if result.pityFired then
			table.insert(notes, "pity")
		end
		self._revealSub.Text = table.concat(notes, "  |  ")

		task.wait(1.6)
		self._reveal.Visible = false
	end)
end

function ConvertFrame:setVisible(visible: boolean)
	self.instance.Visible = visible
end

function ConvertFrame:destroy()
	self.instance:Destroy()
	self._reveal:Destroy()
	table.clear(self._rows)
end

return ConvertFrame
