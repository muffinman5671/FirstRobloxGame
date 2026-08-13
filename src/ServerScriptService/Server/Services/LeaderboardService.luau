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
	{ key = "coins", store = "TopCoinsEarned_v1", title = "TOP EARNERS", format = "coins" },
	{ key = "rebirths", store = "TopRebirths_v1", title = "TOP REBIRTHS", format = "plain" },
}

local stores: { [string]: OrderedDataStore } = {}
local cached: { [string]: { { name: string, value: number } } } = {}
local boards: { [string]: TextLabel } = {}
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

local function buildBoard(spec, index: number, parent: Instance): TextLabel
	local half = (GameConfig.ShaftRadiusBlocks + 0.5) * GameConfig.BlockSize
	local x = (index - 1.5) * 44
	local z = GameConfig.ShaftCenterZ - half - 34

	local sign = Instance.new("Part")
	sign.Name = `Board_{spec.key}`
	sign.Size = Vector3.new(38, 26, 2)
	sign.Position = Vector3.new(GameConfig.ShaftCenterX + x, GameConfig.SurfaceY + 14, z)
	sign.Anchored = true
	sign.Locked = true
	sign.Color = Color3.fromRGB(30, 32, 38)
	sign.Material = Enum.Material.Concrete
	sign.Parent = parent

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(380, 260)
	surface.Parent = sign

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 34)
	title.BackgroundColor3 = Color3.fromRGB(120, 232, 140)
	title.BorderSizePixel = 0
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(18, 19, 24)
	title.Text = spec.title
	title.Parent = surface

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -16, 1, -44)
	body.Position = UDim2.fromOffset(8, 40)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamBold
	body.TextSize = 17
	body.TextColor3 = Color3.fromRGB(238, 240, 246)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Text = "loading..."
	body.Parent = surface

	return body
end

local function render(spec)
	local label = boards[spec.key]
	if not label then
		return
	end

	local rows = cached[spec.key] or {}
	if #rows == 0 then
		label.Text = "no entries yet"
		return
	end

	local lines = {}
	for rank, row in rows do
		if rank > TOP_N then
			break
		end
		local value = if spec.format == "coins" then "$" .. Format.abbreviate(row.value) else tostring(row.value)
		table.insert(lines, ("%2d. %-14s %s"):format(rank, string.sub(row.name, 1, 14), value))
	end
	label.Text = table.concat(lines, "\n")
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function LeaderboardService.Init()
	DataService = require(script.Parent.DataService)
	EconomyService = require(script.Parent.EconomyService)
end

function LeaderboardService.Start()
	local folder = trove:Add(Instance.new("Folder"))
	folder.Name = "Leaderboards"
	folder.Parent = Workspace

	for index, spec in BOARDS do
		boards[spec.key] = buildBoard(spec, index, folder)
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
