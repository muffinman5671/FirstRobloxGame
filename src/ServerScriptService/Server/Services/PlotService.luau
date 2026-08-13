--!strict
--[[
	PlotService
	Private base plots: claiming, podiums, and placing brainrots on them.

	Plots are built once at boot, not per join. Claiming then costs a table
	write rather than making a joining player wait on geometry, and releasing a
	plot is a matter of clearing its podiums rather than destroying and
	rebuilding walls.

	Slot state is authoritative on the profile (`placedBrainrots`), not on the
	world. The models on podiums are a rendering of that list; wiping them and
	rebuilding from the profile always produces the correct plot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ModelFactory = require(ReplicatedStorage.Shared.Modules.ModelFactory)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

type Profile = SharedTypes.Profile
type PurchaseResult = SharedTypes.PurchaseResult

local PlotService = {}
PlotService.Name = "PlotService"

local AntiCheatService
local DataService
local EconomyService

-- (player, plotIndex)
PlotService.PlotAssigned = Signal.new()
-- (player)
PlotService.PlacementChanged = Signal.new()

local trove = Trove.new()

type Plot = {
	index: number,
	model: Model,
	origin: CFrame,
	podiums: { BasePart },
	sign: TextLabel?,
	owner: Player?,
	models: { [number]: Model }, -- slot -> spawned brainrot
}

local plots: { Plot } = {}
local byPlayer: { [Player]: Plot } = {}
local plotFolder: Folder


-- ==========================================================================
-- Construction
-- ==========================================================================

local function makePart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.Concrete
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Podium n sits in a PodiumsPerRow grid on the floor, numbered left to right,
-- front to back, so slot 1 is always the nearest-left podium.
local function podiumOffset(slot: number): Vector3
	local index = slot - 1
	local col = index % GameConfig.PodiumsPerRow
	local row = math.floor(index / GameConfig.PodiumsPerRow)

	local rows = math.ceil(GameConfig.MaxPlotSlots / GameConfig.PodiumsPerRow)
	local x = (col - (GameConfig.PodiumsPerRow - 1) / 2) * GameConfig.PodiumSpacing
	local z = (row - (rows - 1) / 2) * GameConfig.PodiumSpacing

	return Vector3.new(x, GameConfig.PodiumSize.Y / 2, z)
end

local function buildPlot(index: number): Plot
	local spacing = GameConfig.PlotWidth + GameConfig.PlotSpacing
	local origin = CFrame.new(GameConfig.PlotOrigin + Vector3.new((index - 1) * spacing, 0, 0))

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local halfW, halfD = GameConfig.PlotWidth / 2, GameConfig.PlotDepth / 2
	local wallH, wallT = GameConfig.PlotWallHeight, GameConfig.PlotWallThickness

	makePart(
		"Floor",
		Vector3.new(GameConfig.PlotWidth, GameConfig.PlotFloorThickness, GameConfig.PlotDepth),
		origin * CFrame.new(0, -GameConfig.PlotFloorThickness / 2, 0),
		Color3.fromRGB(96, 100, 110),
		model
	)

	-- Three walls; the front is left open so the plot is walkable.
	makePart("WallBack", Vector3.new(GameConfig.PlotWidth, wallH, wallT), origin * CFrame.new(0, wallH / 2, -halfD), Color3.fromRGB(74, 78, 88), model)
	makePart("WallLeft", Vector3.new(wallT, wallH, GameConfig.PlotDepth), origin * CFrame.new(-halfW, wallH / 2, 0), Color3.fromRGB(74, 78, 88), model)
	makePart("WallRight", Vector3.new(wallT, wallH, GameConfig.PlotDepth), origin * CFrame.new(halfW, wallH / 2, 0), Color3.fromRGB(74, 78, 88), model)

	-- Owner sign on the back wall.
	local signPart = makePart("Sign", Vector3.new(28, 6, 1), origin * CFrame.new(0, wallH + 3, -halfD), Color3.fromRGB(38, 41, 49), model)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(560, 120)
	surface.Parent = signPart

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(238, 240, 246)
	signLabel.Text = "UNCLAIMED"
	signLabel.Parent = surface

	local podiums: { BasePart } = {}
	for slot = 1, GameConfig.MaxPlotSlots do
		local podium = makePart(
			`Podium{slot}`,
			GameConfig.PodiumSize,
			origin * CFrame.new(podiumOffset(slot)),
			Color3.fromRGB(58, 62, 72),
			model
		)
		podium:SetAttribute("Slot", slot)
		podiums[slot] = podium
	end

	model.Parent = plotFolder

	return {
		index = index,
		model = model,
		origin = origin,
		podiums = podiums,
		sign = signLabel,
		owner = nil,
		models = {},
	}
end

-- ==========================================================================
-- Rendering placed brainrots
-- ==========================================================================

local function clearSlot(plot: Plot, slot: number)
	local existing = plot.models[slot]
	if existing then
		existing:Destroy()
		plot.models[slot] = nil
	end
end

local function renderSlot(plot: Plot, slot: number, brainrotId: string, mutation: string, rebirths: number)
	clearSlot(plot, slot)

	local model = ModelFactory.create(brainrotId, mutation)
	if not model then
		return
	end

	local podium = plot.podiums[slot]
	if not podium then
		model:Destroy()
		return
	end

	model:PivotTo(podium.CFrame * CFrame.new(0, GameConfig.PodiumSize.Y / 2, 0))
	model.Parent = plot.model

	local def = BrainrotConfig.get(brainrotId)
	if def then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(190, 52)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, GameConfig.BrainrotHeight + 1.6, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 140
		billboard.Adornee = podium
		billboard.Parent = model

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, 0, 0.55, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextColor3 = Rarity.color(def.rarity)
		name.Text = if mutation == "Normal" then def.displayName else `{mutation} {def.displayName}`
		name.Parent = billboard

		local income = Instance.new("TextLabel")
		income.Size = UDim2.new(1, 0, 0.45, 0)
		income.Position = UDim2.fromScale(0, 0.55)
		income.BackgroundTransparency = 1
		income.Font = Enum.Font.GothamBold
		income.TextScaled = true
		income.TextColor3 = Color3.fromRGB(120, 232, 140)
		-- Matches what IncomeService actually pays: base x mutation x rebirth.
		income.Text = Format.rate(
			BrainrotConfig.incomeFor(brainrotId, mutation) * ToolConfig.rebirthMultiplier(rebirths)
		)
		income.Parent = billboard
	end

	plot.models[slot] = model
end

--[[
	Rebuilds every podium from the profile. Called on claim and after any
	placement change -- rebuilding the whole plot is cheap at 24 slots and
	removes any chance of the world disagreeing with the save.
]]
local function renderPlot(plot: Plot)
	for slot in plot.models do
		clearSlot(plot, slot)
	end

	local player = plot.owner
	if not player then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local owned: { [string]: SharedTypes.OwnedBrainrot } = {}
	for _, entry in profile.brainrotsOwned do
		owned[entry.uid] = entry
	end

	for _, placed in profile.placedBrainrots do
		local entry = owned[placed.uid]
		if entry and placed.slot >= 1 and placed.slot <= profile.plotSlots then
			renderSlot(plot, placed.slot, entry.brainrotId, entry.mutation, profile.rebirths)
		end
	end

	-- Podiums beyond the player's purchased slot count are visually inert.
	for slot, podium in plot.podiums do
		local active = slot <= profile.plotSlots
		podium.Transparency = if active then 0 else 0.72
		podium.Color = if active then Color3.fromRGB(58, 62, 72) else Color3.fromRGB(42, 44, 52)
	end
end

PlotService.renderPlot = renderPlot

-- ==========================================================================
-- Claim / release
-- ==========================================================================

local function claim(player: Player)
	if byPlayer[player] then
		return
	end

	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			byPlayer[player] = plot
			if plot.sign then
				plot.sign.Text = player.DisplayName
			end

			renderPlot(plot)
			RemoteRegistry.event("PlotAssigned"):FireClient(player, plot.index, plot.origin.Position)
			PlotService.PlotAssigned:Fire(player, plot.index)
			return
		end
	end

	warn(`[PlotService] no free plot for {player.Name} ({#plots} built)`)
end

local function release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end

	for slot in plot.models do
		clearSlot(plot, slot)
	end
	plot.owner = nil
	if plot.sign then
		plot.sign.Text = "UNCLAIMED"
	end
	byPlayer[player] = nil
end

function PlotService.plotFor(player: Player): Plot?
	return byPlayer[player]
end

-- ==========================================================================
-- Placement
-- ==========================================================================

local function findOwned(profile: Profile, uid: string): SharedTypes.OwnedBrainrot?
	for _, entry in profile.brainrotsOwned do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

local function slotOccupant(profile: Profile, slot: number): string?
	for _, placed in profile.placedBrainrots do
		if placed.slot == slot then
			return placed.uid
		end
	end
	return nil
end

function PlotService.place(player: Player, uid: any, slot: any): PurchaseResult
	if type(uid) ~= "string" or type(slot) ~= "number" or slot ~= math.floor(slot) then
		return { ok = false, reason = "bad_request" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end
	if not byPlayer[player] then
		return { ok = false, reason = "no_plot" }
	end
	if slot < 1 or slot > profile.plotSlots then
		return { ok = false, reason = "slot_not_unlocked" }
	end
	if not findOwned(profile, uid) then
		return { ok = false, reason = "not_owned" }
	end
	if slotOccupant(profile, slot) then
		return { ok = false, reason = "slot_occupied" }
	end

	for _, placed in profile.placedBrainrots do
		if placed.uid == uid then
			return { ok = false, reason = "already_placed" }
		end
	end

	DataService.update(player, function(p)
		table.insert(p.placedBrainrots, { uid = uid, slot = slot })
	end)

	renderPlot(byPlayer[player])
	RemoteRegistry.event("PlacementChanged"):FireClient(player)
	PlotService.PlacementChanged:Fire(player)
	DataService.pushSnapshot(player)
	return { ok = true }
end

function PlotService.unplace(player: Player, slot: any): PurchaseResult
	if type(slot) ~= "number" or slot ~= math.floor(slot) then
		return { ok = false, reason = "bad_request" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end
	if not slotOccupant(profile, slot) then
		return { ok = false, reason = "slot_empty" }
	end

	DataService.update(player, function(p)
		for index = #p.placedBrainrots, 1, -1 do
			if p.placedBrainrots[index].slot == slot then
				table.remove(p.placedBrainrots, index)
			end
		end
	end)

	local plot = byPlayer[player]
	if plot then
		renderPlot(plot)
	end
	RemoteRegistry.event("PlacementChanged"):FireClient(player)
	PlotService.PlacementChanged:Fire(player)
	DataService.pushSnapshot(player)
	return { ok = true }
end

--[[
	Sells a brainrot outright. Placed ones are unplaced first, so a sale can
	never leave a podium rendering something the player no longer owns.
]]
function PlotService.sellBrainrot(player: Player, uid: any): PurchaseResult
	if type(uid) ~= "string" then
		return { ok = false, reason = "bad_request" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local entry = findOwned(profile, uid)
	if not entry then
		return { ok = false, reason = "not_owned" }
	end

	local payout = BrainrotConfig.sellValueFor(entry.brainrotId, entry.mutation)

	DataService.update(player, function(p)
		for index = #p.placedBrainrots, 1, -1 do
			if p.placedBrainrots[index].uid == uid then
				table.remove(p.placedBrainrots, index)
			end
		end
		for index = #p.brainrotsOwned, 1, -1 do
			if p.brainrotsOwned[index].uid == uid then
				table.remove(p.brainrotsOwned, index)
			end
		end
	end)

	if payout > 0 then
		EconomyService.award(player, payout)
	end

	local plot = byPlayer[player]
	if plot then
		renderPlot(plot)
	end
	RemoteRegistry.event("PlacementChanged"):FireClient(player)
	PlotService.PlacementChanged:Fire(player)
	DataService.pushSnapshot(player)
	return { ok = true, coins = DataService.get(player).coins }
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function PlotService.Init()
	AntiCheatService = require(script.Parent.AntiCheatService)
	DataService = require(script.Parent.DataService)
	EconomyService = require(script.Parent.EconomyService)

	plotFolder = trove:Add(Instance.new("Folder"))
	plotFolder.Name = "Plots"
end

function PlotService.Start()
	plotFolder.Parent = Workspace
	for index = 1, GameConfig.PlotCount do
		table.insert(plots, buildPlot(index))
	end

	RemoteRegistry.func("RequestPlace").OnServerInvoke = function(player, uid, slot)
		if not AntiCheatService.guard(player, "RequestPlace") then
			return { ok = false, reason = "rate_limited" }
		end
		return PlotService.place(player, uid, slot)
	end

	RemoteRegistry.func("RequestUnplace").OnServerInvoke = function(player, slot)
		if not AntiCheatService.guard(player, "RequestUnplace") then
			return { ok = false, reason = "rate_limited" }
		end
		return PlotService.unplace(player, slot)
	end

	RemoteRegistry.func("RequestSellBrainrot").OnServerInvoke = function(player, uid)
		if not AntiCheatService.guard(player, "RequestSellBrainrot") then
			return { ok = false, reason = "rate_limited" }
		end
		return PlotService.sellBrainrot(player, uid)
	end

	-- A plot is claimed once the profile exists, so the podiums can be built
	-- from saved placements rather than appearing empty and then popping in.
	DataService.ProfileLoaded:Connect(function(player: Player)
		claim(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			claim(player)
		end
	end

	DataService.ProfileReleased:Connect(function(player: Player)
		release(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		release(player)
	end)

	-- Buying a podium slot changes how many are active, so the plot needs a
	-- repaint even though no brainrot moved.
	local ShopService = require(script.Parent.ShopService)
	ShopService.Purchased:Connect(function(player: Player, itemId: string)
		if itemId == ShopService.PLOT_SLOT_ID then
			local plot = byPlayer[player]
			if plot then
				renderPlot(plot)
			end
		end
	end)
end

function PlotService.stats()
	local claimed = 0
	for _, plot in plots do
		if plot.owner then
			claimed += 1
		end
	end
	return { built = #plots, claimed = claimed }
end

return PlotService
