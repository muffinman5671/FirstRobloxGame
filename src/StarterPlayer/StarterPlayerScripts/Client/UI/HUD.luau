--!strict
--[[
	HUD
	Always-on readouts: coins, income rate, backpack fill, depth, equipped
	pickaxe, and the buttons that open the other screens.

	Purely a view. It renders whatever snapshot it is handed and reads the
	character's Y for depth; it never asks the server for anything and never
	decides whether an action is allowed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyReward = require(ReplicatedStorage.Shared.Modules.DailyReward)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LayerConfig = require(ReplicatedStorage.Shared.Config.LayerConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local Theme = require(script.Parent.Theme)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local HUD = {}
HUD.__index = HUD

local player = Players.LocalPlayer

export type HUD = {
	instance: Frame,
	update: (self: HUD, snapshot: ProfileSnapshot?) -> (),
	updateDepth: (self: HUD) -> (),
	onOpen: (self: HUD, callback: (string) -> ()) -> (),
	onSurface: (self: HUD, callback: () -> ()) -> (),
	destroy: (self: HUD) -> (),
}

function HUD.new(parent: Instance): HUD
	local self = setmetatable({
		_openCallbacks = {},
		_surfaceCallbacks = {},
		_root = nil,
		-- Cached so updateDepth, which runs every frame, only touches the
		-- button on the frame the answer actually changes.
		_canReturn = nil,
	}, HUD)

	-- Cache the root part per spawn so updateDepth never does a lookup.
	local function bindCharacter(character: Model)
		self._root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not self._root then
			task.spawn(function()
				local found = character:WaitForChild("HumanoidRootPart", 10)
				if found and found:IsA("BasePart") and player.Character == character then
					self._root = found
				end
			end)
		end
	end

	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function()
		self._root = nil
	end)

	local outer, inner = Theme.panel({
		Name = "HUD",
		Size = UDim2.fromOffset(300, 306),
		Position = UDim2.fromOffset(Theme.METRIC.pad, Theme.METRIC.pad),
	})
	outer.Parent = parent
	self.instance = outer

	Theme.padding(inner)
	Theme.list(inner, 6)

	--[[
		Coins, the single most important number on screen -- and in the reference
		art the money readout is the biggest thing on the HUD by a wide margin,
		set several steps above its own label. Given a thicker glyph outline than
		the default to match, since at this size the default looks like a hairline.
	]]
	self._coins = Theme.label("$0", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 38),
		Font = Theme.FONT.heading,
		TextSize = 34,
		TextColor3 = Theme.COLOR.coins,
	})
	self._coins.Parent = inner
	local coinStroke = self._coins:FindFirstChildOfClass("UIStroke")
	if coinStroke then
		coinStroke.Thickness = 3
	end

	self._income = Theme.label("$0/s", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.accent,
	})
	self._income.Parent = inner

	-- Backpack: label above, bar below. The bar shifts colour as it fills so
	-- "go sell" is readable at a glance without reading the numbers.
	self._backpackLabel = Theme.label("Backpack 0 / 0", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.textDim,
	})
	self._backpackLabel.Parent = inner

	local barOuter, barFill = Theme.bar(Theme.COLOR.accent)
	barOuter.LayoutOrder = 4
	barOuter.Parent = inner
	self._backpackFill = barFill

	self._depth = Theme.label("Surface", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.textDim,
	})
	self._depth.Parent = inner

	self._pickaxe = Theme.label("Cracked Trowel", {
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.TEXT_SIZE.small,
		TextColor3 = Theme.COLOR.textDim,
	})
	self._pickaxe.Parent = inner

	-- Screen buttons. Laid out horizontally, each still a full tap target.
	local buttonRow = Instance.new("Frame")
	buttonRow.BackgroundTransparency = 1
	buttonRow.LayoutOrder = 7
	buttonRow.Size = UDim2.new(1, 0, 0, Theme.METRIC.tapTarget)
	buttonRow.Parent = inner

	--[[
		Shop and Convert used to live here too. They are places now: walking into
		the lit circle at the tool shop or the ore exchange opens them, and
		walking out closes them again (UIController's pad watcher).

		What is left is what you carry rather than what you visit -- your bag,
		the index, and rebirth. Those have no stall to stand in, so they keep
		buttons.

		Four across one row, the daily reward being the fourth: it has no stall
		either. At a quarter of the panel each is 67px wide and
		Theme.METRIC.tapTarget tall, still past the 44px minimum both ways, and
		the labels are short enough to fit.
	]]
	--[[
		Each button is coloured to match the header of the panel it opens, so the
		green button opens the green screen. The reference art does the same, and
		it is worth more than it costs: on a HUD of identical purple buttons the
		only way to tell them apart is to read them.
	]]
	local screens = {
		{ "Bag", "inventory", Theme.COLOR.warn },
		{ "Index", "index", Theme.COLOR.accentAlt },
		{ "Rebirth", "rebirth", Theme.COLOR.coins },
		{ "Daily", "daily", Theme.COLOR.reward },
	}

	-- Four cells and three 4px gaps: each cell gives up 3px of its quarter.
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / #screens, -3, 0, Theme.METRIC.tapTarget)
	grid.CellPadding = UDim2.fromOffset(4, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = buttonRow

	for index, spec in screens do
		local button = Theme.button(spec[1], {
			LayoutOrder = index,
			TextSize = Theme.TEXT_SIZE.small,
			accent = spec[3],
		})
		button.Parent = buttonRow
		button.Activated:Connect(function()
			for _, callback in self._openCallbacks do
				callback(spec[2])
			end
		end)

		-- A dot on the corner of Daily while a reward is waiting, so it can be
		-- seen from the HUD without opening anything. `update` shows and hides it.
		if spec[2] == "daily" then
			local badge = Instance.new("Frame")
			badge.Name = "Waiting"
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 4, 0, -4)
			badge.Size = UDim2.fromOffset(14, 14)
			badge.BackgroundColor3 = Theme.COLOR.danger
			badge.BorderSizePixel = 0
			badge.ZIndex = button.ZIndex + 1
			badge.Visible = false
			badge.Parent = button
			Theme.corner(badge, 7)
			Theme.stroke(badge, Theme.METRIC.border)
			self._dailyBadge = badge
		end
	end

	--[[
		Return to surface.

		Its own full-width row rather than a fourth cell in the grid above,
		because it is a different kind of thing: the three buttons up there open
		a screen, this one acts on the world. Four cells across 300px would also
		have left no room for a label anyone could read.

		Disabled at the hub rather than hidden -- a button that comes and goes
		makes the panel jump, and the disabled label is what teaches the player
		it exists at all before they ever go down.
	]]
	self._surface = Theme.button("RETURN TO SURFACE", {
		LayoutOrder = 8,
		Size = UDim2.new(1, 0, 0, Theme.METRIC.tapTarget),
		TextSize = Theme.TEXT_SIZE.small,
		accent = Theme.COLOR.accentAlt,
	})
	self._surface.Parent = inner

	self._surface.Activated:Connect(function()
		if self._surface:GetAttribute("Enabled") == false then
			return
		end
		for _, callback in self._surfaceCallbacks do
			callback()
		end
	end)

	return (self :: any) :: HUD
end

function HUD:onSurface(callback: () -> ())
	table.insert(self._surfaceCallbacks, callback)
end

function HUD:onOpen(callback: (string) -> ())
	table.insert(self._openCallbacks, callback)
end

function HUD:update(snapshot: ProfileSnapshot?)
	if not snapshot then
		return
	end

	self._coins.Text = "$" .. Format.abbreviate(snapshot.coins)
	self._income.Text = Format.rate(snapshot.incomePerSecond) .. "  |  Rebirths " .. snapshot.rebirths

	-- Capacity is weight, not item count, so the bar has to price each ore by
	-- its weightPerUnit rather than summing counts.
	local backpack = ToolConfig.getBackpack(snapshot.equippedBackpack)
	local capacity = if backpack then backpack.capacity else 0
	local used = 0
	for oreId, count in snapshot.oreCounts do
		local ore = OreConfig.get(oreId)
		if ore then
			used += ore.weightPerUnit * count
		end
	end

	local fraction = if capacity > 0 then math.clamp(used / capacity, 0, 1) else 0
	self._backpackLabel.Text = ("Backpack  %d / %d"):format(used, capacity)
	self._backpackFill.Size = UDim2.fromScale(fraction, 1)
	self._backpackFill.BackgroundColor3 = if fraction >= 1
		then Theme.COLOR.danger
		elseif fraction > 0.75 then Theme.COLOR.warn
		else Theme.COLOR.accent

	local pickaxe = ToolConfig.getPickaxe(snapshot.equippedPickaxe)
	self._pickaxe.Text = if pickaxe then pickaxe.displayName else "--"

	-- Read against the player's own clock. That only decides whether a dot is
	-- drawn; the server decides whether a claim is real.
	if self._dailyBadge then
		self._dailyBadge.Visible =
			DailyReward.status(snapshot.dailyLastClaimDay, snapshot.dailyStreak, os.time()).claimable
	end
end

--[[
	Depth changes every frame, so it updates separately from the snapshot.

	The root part is cached on spawn rather than looked up here: this runs on
	RenderStepped, and DESIGN.md §2 forbids per-frame FindFirstChild in hot
	paths.
]]
function HUD:updateDepth()
	local root = self._root
	if not root or not root.Parent then
		return
	end

	local depth = GameConfig.SurfaceY - root.Position.Y

	-- The ride home is only offered from underground. Written on change rather
	-- than every frame: this runs on RenderStepped, and setting the attribute
	-- re-runs the button's colour refresh.
	local canReturn = depth >= GameConfig.SurfaceReturnMinDepth
	if canReturn ~= self._canReturn then
		self._canReturn = canReturn
		self._surface:SetAttribute("Enabled", canReturn)
		self._surface.Text = if canReturn then "RETURN TO SURFACE" else "AT THE SURFACE"
	end

	if depth < 1 then
		self._depth.Text = "Surface"
		return
	end

	local layer = LayerConfig.forDepth(depth)
	self._depth.Text = ("%s  |  %s"):format(layer.displayName, Format.depth(depth))
end

function HUD:destroy()
	self.instance:Destroy()
	table.clear(self._openCallbacks)
	table.clear(self._surfaceCallbacks)
end

return HUD
