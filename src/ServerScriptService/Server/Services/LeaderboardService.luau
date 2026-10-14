--!strict
--[[
	LeaderboardService
	Top-10 boards backed by OrderedDataStore, rendered on physical signs in the
	hub.

	Two boards: total coins earned (a lifetime counter, not the current balance,
	so spending doesn't knock you off) and rebirths.

	Lifetime-earned is tracked here rather than on the profile schema because it
	is a leaderboard concern; DataService's Profile stays the shape the game
	logic needs. It is derived by accumulating EconomyService.CoinsChanged.

	Like DataService, this degrades rather than erroring when DataStores are
	unavailable: in Studio the boards simply show the live server's players.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Modules.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

local LeaderboardService = {}
LeaderboardService.Name = "LeaderboardService"

local DataService
local EconomyService

local trove = Trove.new()

local REFRESH_SECONDS = 60
local TOP_N = 10

-- OrderedDataStore only stores integers, and only positive ones sort usefully.
local BOARDS = {
	-- Accent lives on the placement in GameConfig, not here: HubDecor paints the
	-- board's lamp bollards with it too, and two copies would drift.
	{ key = "coins", store = "TopCoinsEarned_v1", title = "TOP EARNERS", format = "coins" },
	{ key = "rebirths", store = "TopRebirths_v1", title = "TOP REBIRTHS", format = "plain" },
}

local stores: { [string]: OrderedDataStore } = {}
local cached: { [string]: { { name: string, value: number } } } = {}
local boards: { [string]: Frame } = {}
local lifetimeEarned: { [Player]: number } = {}
local available = true

-- ==========================================================================
-- Store access
-- ==========================================================================

local function markUnavailable(reason: string)
	if available then
		available = false
		if RunService:IsStudio() then
			warn(
				`[LeaderboardService] OrderedDataStores unavailable ({reason}). `
					.. `Boards will show this server's players only.`
			)
		else
			warn(`[LeaderboardService] OrderedDataStores unavailable: {reason}`)
		end
	end
end

local function storeFor(spec): OrderedDataStore?
	if not available then
		return nil
	end
	if stores[spec.key] then
		return stores[spec.key]
	end

	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(spec.store)
	end)
	if not ok or not result then
		markUnavailable(tostring(result))
		return nil
	end

	stores[spec.key] = result
	return result
end

-- ==========================================================================
-- Publishing and reading
-- ==========================================================================

local function publish(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	for _, spec in BOARDS do
		local store = storeFor(spec)
		if store then
			local value = if spec.key == "coins"
				then math.floor(lifetimeEarned[player] or 0)
				else math.floor(profile.rebirths)

			-- Zero entries are noise on a top-10 and waste a write.
			if value > 0 then
				local ok, err = pcall(function()
					store:SetAsync(tostring(player.UserId), value)
				end)
				if not ok then
					markUnavailable(tostring(err))
				end
			end
		end
	end
end

--[[
	Fetches the top N. Falls back to ranking the current server's players when
	the store is unavailable, so the board is never blank in Studio and never
	blank on a live server having a bad minute.
]]
local function fetch(spec): { { name: string, value: number } }
	local store = storeFor(spec)

	if store then
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, TOP_N)
		end)

		if ok and pages then
			local rows = {}
			for _, entry in pages:GetCurrentPage() do
				local userId = tonumber(entry.key)
				local name = "Player"
				if userId then
					local nameOk, fetched = pcall(function()
						return Players:GetNameFromUserIdAsync(userId)
					end)
					name = if nameOk and fetched then fetched else `User {userId}`
				end
				table.insert(rows, { name = name, value = entry.value })
			end
			return rows
		end
		markUnavailable("GetSortedAsync failed")
	end

	local rows = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile then
			local value = if spec.key == "coins"
				then math.floor(lifetimeEarned[player] or 0)
				else profile.rebirths
			table.insert(rows, { name = player.DisplayName, value = value })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	return rows
end

-- ==========================================================================
-- Board geometry
-- ==========================================================================

--[[
	Boards stand in a row along the west side of the stem, turned to face east
	across it.

	The row runs along Z and the signs face +X, which is why the spacing is
	applied to Z and the cabinet is yawed -90 degrees. Everything is built from
	that one origin CFrame with local offsets -- local +X runs along the board's
	width, local -Z is the face -- rather than in world coordinates, so the whole
	cabinet turns as a unit and no offset has to be re-derived if the row moves.

	This used to be a single grey slab hanging in the air with a flat green strip
	across the top. It is a cabinet now: plinth, two posts, a heavy frame round
	the face and a coloured crown. That is DESIGN.md 2b's outline-and-chunk
	treatment done in geometry, because 2a wants world detail built rather than
	textured.
]]
local function panelPart(
	parent: Instance,
	name: string,
	origin: CFrame,
	offset: Vector3,
	size: Vector3,
	colour: Color3
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Locked = true
	part.Size = size
	part.CFrame = origin * CFrame.new(offset)
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function corner(parent: Instance, radius: number)
	local ui = Instance.new("UICorner")
	ui.CornerRadius = UDim.new(0, radius)
	ui.Parent = parent
end

-- Border mode draws outside the frame, so an outline costs no layout: a row is
-- still exactly as wide as it was laid out to be.
local function stroke(parent: Instance, thickness: number)
	local ui = Instance.new("UIStroke")
	ui.Thickness = thickness
	ui.Color = GameConfig.BoardPalette.border
	ui.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ui.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Size = size
	item.Position = position
	item.Font = Enum.Font.GothamBlack
	item.Text = text
	item.TextColor3 = GameConfig.BoardPalette.text
	-- Outlined glyphs, per 2b. White on a black outline reads against the panel,
	-- against a gold badge, and at the distance these are read from.
	item.TextStrokeColor3 = GameConfig.BoardPalette.border
	item.TextStrokeTransparency = 0
	item.Parent = parent
	return item
end

--[[
	The cabinet, returning the frame the rows are laid into.

	The canvas is FixedSize on purpose. SurfaceGui ignores CanvasSize unless
	SizingMode says to use it, and the default is PixelsPerStud -- so the old
	board declared a 380x260 canvas and then drew onto the ~1900x1300 one
	PixelsPerStud gives a 38x26 face. That is why its 34px title bar came out as
	a hairline and its text sat in the top corner.
]]
local function buildBoard(spec, parent: Instance): Frame
	local pal = GameConfig.BoardPalette
	local placement = GameConfig.LeaderboardPlacements[spec.key]
	local accent = placement.accent

	local faceW = GameConfig.LeaderboardFaceWidth
	local faceH = GameConfig.LeaderboardFaceHeight
	local frame = GameConfig.LeaderboardFrame
	local halfW, halfH = faceW / 2, faceH / 2
	local boardY = GameConfig.LeaderboardHeight

	-- Ground level, so every offset below reads as a height above the lawn, and
	-- yawed so the whole cabinet turns as a unit.
	local origin = CFrame.new(placement.position.X, GameConfig.SurfaceY, placement.position.Z)
		* CFrame.Angles(0, math.rad(placement.yaw), 0)

	local cabinet = Instance.new("Model")
	cabinet.Name = "Board_" .. spec.key
	cabinet.Parent = parent

	-- Plinth and legs. Without these the slab floats, which was most of what
	-- made the old board look unfinished.
	panelPart(cabinet, "Plinth", origin, Vector3.new(0, 0.9, 0), Vector3.new(faceW + 4, 1.8, 7), pal.border)
	for _, side in { -1, 1 } do
		panelPart(
			cabinet,
			"Post",
			origin,
			Vector3.new(side * (halfW - 6), GameConfig.LeaderboardPostHeight / 2 + 1.8, 0),
			Vector3.new(3.6, GameConfig.LeaderboardPostHeight, 3.6),
			pal.post
		)
	end

	local slab =
		panelPart(cabinet, "Face", origin, Vector3.new(0, boardY, 0), Vector3.new(faceW, faceH, 2), pal.panelSunken)
	cabinet.PrimaryPart = slab

	--[[
		The frame, as four bars round the opening rather than a plate over it.

		Each bar sits flush against an edge of the slab and stands proud of the
		face, so it reads as a moulding. Laying it over the face instead would put
		two surfaces on one plane and z-fight, which is the most visible bug
		available in this codebase.
	]]
	local bar = frame / 2
	local depth = 3.4
	local z = -0.6
	for _, side in { -1, 1 } do
		panelPart(
			cabinet,
			"FrameH",
			origin,
			Vector3.new(0, boardY + side * (halfH + bar), z),
			Vector3.new(faceW + frame * 2, frame, depth),
			pal.border
		)
		panelPart(
			cabinet,
			"FrameV",
			origin,
			Vector3.new(side * (halfW + bar), boardY, z),
			Vector3.new(frame, faceH, depth),
			pal.border
		)
	end

	-- Crown: the board's own accent, as a chunky cap with a block at each end,
	-- so the two are told apart by colour and silhouette from across the
	-- corridor, before either is close enough to read.
	local crownY = boardY + halfH + frame + 1.7
	panelPart(cabinet, "Crown", origin, Vector3.new(0, crownY, z), Vector3.new(faceW + frame * 2, 3.4, depth), accent)
	for _, side in { -1, 1 } do
		panelPart(
			cabinet,
			"Finial",
			origin,
			Vector3.new(side * (halfW + bar), crownY + 2.4, z),
			Vector3.new(4.2, 4.2, depth + 0.6),
			accent
		)
	end

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(faceW * 20, faceH * 20)
	-- Unlit: this is a poster, and a board that dims as the sun moves round is a
	-- board nobody reads from the far side of the corridor.
	surface.LightInfluence = 0
	surface.Parent = slab

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = pal.panel
	backdrop.BorderSizePixel = 0
	backdrop.Parent = surface

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = backdrop

	local title = Instance.new("Frame")
	title.Size = UDim2.new(1, 0, 0, 78)
	title.BackgroundColor3 = accent
	title.BorderSizePixel = 0
	title.Parent = backdrop
	corner(title, 16)
	stroke(title, 6)

	local titleText = label(title, spec.title, UDim2.fromScale(1, 1), UDim2.new())
	titleText.TextSize = 46

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(0, 90)
	rows.Size = UDim2.new(1, 0, 1, -90)
	rows.Parent = backdrop

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rows

	return rows
end

--[[
	One rank per row: a coloured badge, the name, then the number.

	The old board wrote all ten lines into a single TextLabel and lined the
	columns up with a "%-14s" pad. Padding only aligns in a monospaced font and
	Gotham is not one, so the values never actually formed a column. Three
	positioned labels do, at any name length.
]]
local function buildRow(parent: Instance, rank: number, name: string, value: string)
	local pal = GameConfig.BoardPalette
	local podium = rank <= #GameConfig.BoardRankColors

	local row = Instance.new("Frame")
	row.Name = "Rank" .. rank
	row.LayoutOrder = rank
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = if rank % 2 == 1 then pal.panelRaised else pal.panelSunken
	row.BorderSizePixel = 0
	row.Parent = parent
	corner(row, 8)
	stroke(row, 3)

	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(38, 26)
	badge.Position = UDim2.fromOffset(5, 4)
	badge.BackgroundColor3 = GameConfig.BoardRankColors[rank] or GameConfig.BoardRankOther
	badge.BorderSizePixel = 0
	badge.Parent = row
	corner(badge, 7)
	stroke(badge, 3)

	local rankText = label(badge, tostring(rank), UDim2.fromScale(1, 1), UDim2.new())
	rankText.TextSize = 20
	-- The three podium colours are light, so their numerals take the dark ink and
	-- drop the outline; everyone else sits on the muted slate and keeps white.
	rankText.TextColor3 = if podium then pal.border else pal.text
	rankText.TextStrokeTransparency = if podium then 1 else 0

	local who = label(row, name, UDim2.new(1, -190, 1, 0), UDim2.fromOffset(52, 0))
	who.TextSize = 22
	who.TextXAlignment = Enum.TextXAlignment.Left
	who.TextTruncate = Enum.TextTruncate.AtEnd

	local amount = label(row, value, UDim2.new(0, 128, 1, 0), UDim2.new(1, -134, 0, 0))
	amount.TextSize = 22
	amount.TextColor3 = pal.coins
	amount.TextXAlignment = Enum.TextXAlignment.Right
end

local function render(spec)
	local rows = boards[spec.key]
	if not rows then
		return
	end

	-- Rebuilt wholesale on every refresh: ten rows a minute is not worth pooling,
	-- and a rebuild cannot leave a stale name behind a shorter list.
	for _, child in rows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local entries = cached[spec.key] or {}
	if #entries == 0 then
		local empty = label(rows, "no entries yet", UDim2.new(1, 0, 0, 40), UDim2.new())
		empty.TextSize = 22
		empty.TextColor3 = GameConfig.BoardPalette.textDim
		return
	end

	for rank, entry in entries do
		if rank > TOP_N then
			break
		end
		local value = if spec.format == "coins" then "$" .. Format.abbreviate(entry.value) else tostring(entry.value)
		buildRow(rows, rank, entry.name, value)
	end
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

--[[
	Builds the cabinets into a preview folder, filled with placeholder ranks.

	Mirrors PlotService.appendPreview, and exists for the same reason: the hub is
	worked on in Edit, and until now the boards only existed once the game was
	running. A SurfaceGui parented to a Part in Workspace *does* render in the
	Edit viewport -- unlike a ScreenGui, which needs Play -- so the whole board,
	rows and all, can be looked at without starting the game.

	Sample rows rather than real ones: DataStores are not reachable from Edit,
	and an empty board tells you nothing about whether the layout works.
]]
local PREVIEW_NAMES = {
	"Braindrop", "Tralalero", "SigmaMiner", "CrocPilot", "BombardiroX",
	"Lirili", "PatapimFan", "Bananini", "TungTung", "CappuccinoA",
}

function LeaderboardService.appendPreview(parent: Instance): number
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"

	local previousBoards = {}
	for key, value in boards do
		previousBoards[key] = value
	end

	local ok, err = pcall(function()
		for _, spec in BOARDS do
			boards[spec.key] = buildBoard(spec, folder)

			local sample = {}
			for rank, name in PREVIEW_NAMES do
				local value = if spec.format == "coins"
					then math.floor(12_500_000 / (rank * rank))
					else 40 - rank * 3
				table.insert(sample, { name = name, value = value })
			end
			cached[spec.key] = sample
			render(spec)
			cached[spec.key] = nil
		end
	end)

	table.clear(boards)
	for key, value in previousBoards do
		boards[key] = value
	end

	if not ok then
		folder:Destroy()
		error(`[LeaderboardService] preview build failed: {err}`, 0)
	end

	folder.Parent = parent
	return #folder:GetChildren()
end

function LeaderboardService.Init()
	DataService = require(script.Parent.DataService)
	EconomyService = require(script.Parent.EconomyService)
end

function LeaderboardService.Start()
	local folder = trove:Add(Instance.new("Folder"))
	folder.Name = "Leaderboards"
	folder.Parent = Workspace

	for _, spec in BOARDS do
		boards[spec.key] = buildBoard(spec, folder)
	end

	-- Lifetime earnings accumulate from every positive coin change, so
	-- spending never costs you leaderboard position.
	EconomyService.CoinsChanged:Connect(function(player: Player, delta: number)
		if delta > 0 then
			lifetimeEarned[player] = (lifetimeEarned[player] or 0) + delta
		end
	end)

	DataService.ProfileLoaded:Connect(function(player: Player)
		local profile = DataService.get(player)
		-- Seed from the current balance so a returning player isn't ranked
		-- from zero. Approximate by design: exact lifetime tracking would need
		-- a schema field, and this is a display board.
		lifetimeEarned[player] = if profile then profile.coins else 0
	end)

	DataService.ProfileReleased:Connect(function(player: Player)
		publish(player)
		lifetimeEarned[player] = nil
	end)

	trove:Add(task.spawn(function()
		while true do
			for _, spec in BOARDS do
				local ok, rows = pcall(fetch, spec)
				if ok then
					cached[spec.key] = rows
					render(spec)
				end
			end

			-- Publish everyone still online so the boards move during a long
			-- session rather than only when players leave.
			for _, player in Players:GetPlayers() do
				pcall(publish, player)
			end

			task.wait(REFRESH_SECONDS)
		end
	end))
end

function LeaderboardService.Stop()
	trove:Clean()
	table.clear(lifetimeEarned)
end

function LeaderboardService.stats()
	return {
		available = available,
		boards = #BOARDS,
		cachedCoins = #(cached.coins or {}),
		cachedRebirths = #(cached.rebirths or {}),
	}
end

return LeaderboardService
