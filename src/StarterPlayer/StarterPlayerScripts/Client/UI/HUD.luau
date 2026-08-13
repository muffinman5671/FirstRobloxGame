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
	destroy: (self: HUD) -> (),
}

function HUD.new(parent: Instance): HUD
	local self = setmetatable({ _openCallbacks = {}, _root = nil }, HUD)

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
		Size = UDim2.fromOffset(300, 234),
		Position = UDim2.fromOffset(Theme.METRIC.pad, Theme.METRIC.pad),
	})
	outer.Parent = parent
	self.instance = outer

	Theme.padding(inner)
	Theme.list(inner, 6)

	-- Coins, the single most important number on screen.
	self._coins = Theme.label("$0", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.FONT.heading,
		TextSize = Theme.TEXT_SIZE.title,
		TextColor3 = Theme.COLOR.coins,
	})
	self._coins.Parent = inner

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

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, Theme.METRIC.gap)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonRow

	-- Five screens in one row would give ~52px buttons; the row is two-deep
	-- instead so every target stays comfortably past the 44px minimum.
	local screens = {
		{ "Bag", "inventory" },
		{ "Shop", "shop" },
		{ "Convert", "convert" },
		{ "Index", "index" },
		{ "Rebirth", "rebirth" },
	}
	buttonRow.Size = UDim2.new(1, 0, 0, Theme.METRIC.tapTarget * 2 + 4)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 3, -4, 0, Theme.METRIC.tapTarget)
	grid.CellPadding = UDim2.fromOffset(4, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = buttonRow
	rowLayout:Destroy()

	for index, spec in screens do
		local button = Theme.button(spec[1], {
			LayoutOrder = index,
			TextSize = Theme.TEXT_SIZE.small,
		})
		button.Parent = buttonRow
		button.Activated:Connect(function()
			for _, callback in self._openCallbacks do
				callback(spec[2])
			end
		end)
	end

	return (self :: any) :: HUD
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
end

return HUD
