--!strict
--[[
	EconomyService
	Coins, ore sales, layer unlocks, and rebirth.

	Every value in here is computed server-side from config. The client sends at
	most an ore id or a layer index -- never a price, a quantity, or a total. A
	request that names something the player doesn't hold, can't afford, or
	hasn't earned is refused with a reason, not clamped silently.

	ShopService owns tool and slot purchases; this service owns the currency
	those purchases spend.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LayerConfig = require(ReplicatedStorage.Shared.Config.LayerConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

type Profile = SharedTypes.Profile
type PurchaseResult = SharedTypes.PurchaseResult

local EconomyService = {}
EconomyService.Name = "EconomyService"

local AntiCheatService
local DataService
local InventoryService

-- (player, delta, newTotal)
EconomyService.CoinsChanged = Signal.new()
-- (player, newRebirthCount)
EconomyService.Rebirthed = Signal.new()
-- (player, layerIndex)
EconomyService.LayerUnlocked = Signal.new()

-- ==========================================================================
-- Currency
-- ==========================================================================

--[[
	Coin changes are accumulated and flushed on a timer rather than pushed per
	call. `award` is called once per second per player by IncomeService, which
	is fine, but any loop awarding coins would otherwise fire a remote per
	iteration -- that is what wedged a Studio session during balance modelling.

	The in-process CoinsChanged signal still fires immediately: server-side
	listeners (LeaderboardService) want every delta, and they cost nothing.
	Only the network push is batched.
]]
local pendingDelta: { [Player]: number } = {}

local function pushCoins(player: Player, delta: number, total: number)
	pendingDelta[player] = (pendingDelta[player] or 0) + delta
	EconomyService.CoinsChanged:Fire(player, delta, total)
end

-- Sends whatever has accumulated. Safe to call when nothing is pending.
local function flushCoins(player: Player)
	local delta = pendingDelta[player]
	if not delta or delta == 0 then
		pendingDelta[player] = nil
		return
	end
	pendingDelta[player] = nil

	local profile = DataService.get(player)
	if profile then
		RemoteRegistry.event("CoinsChanged"):FireClient(player, profile.coins, delta)
	end
end

-- Exposed so a high-stakes change (a purchase, a rebirth) can land instantly
-- rather than waiting up to CoinsPushIntervalSeconds.
EconomyService.flushCoins = flushCoins

function EconomyService.getCoins(player: Player): number
	local profile = DataService.get(player)
	return if profile then profile.coins else 0
end

-- Adds coins and tells the client. Negative amounts are rejected here; use
-- spend() so the affordability check can't be skipped by passing a negative.
function EconomyService.award(player: Player, amount: number): boolean
	if amount <= 0 then
		return false
	end

	local total = 0
	local ok = DataService.update(player, function(profile)
		profile.coins += amount
		total = profile.coins
	end)
	if not ok then
		return false
	end

	pushCoins(player, amount, total)
	return true
end

--[[
	Deducts coins if the player can afford it. Returns false and changes
	nothing otherwise -- there is no partial spend, and the balance can never
	go negative.
]]
function EconomyService.spend(player: Player, amount: number): boolean
	if amount < 0 then
		return false
	end

	local profile = DataService.get(player)
	if not profile or profile.coins < amount then
		return false
	end

	local total = 0
	DataService.update(player, function(p)
		p.coins -= amount
		total = p.coins
	end)

	pushCoins(player, -amount, total)
	return true
end

-- ==========================================================================
-- Selling ore
-- ==========================================================================

--[[
	Sells one ore type, or the whole bag when oreId is nil.

	The payout is recomputed from OreConfig every time. The client's inventory
	view is a display of server state, never an input to the price.
]]
function EconomyService.sell(player: Player, oreId: string?): PurchaseResult
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local sold: { [string]: number }

	if oreId == nil then
		sold = InventoryService.takeAll(player)
	else
		if not OreConfig.exists(oreId) then
			return { ok = false, reason = "unknown_ore" }
		end
		local held = profile.oreCounts[oreId] or 0
		if held <= 0 then
			return { ok = false, reason = "none_held" }
		end
		local taken = InventoryService.remove(player, oreId, held)
		sold = { [oreId] = taken }
	end

	local payout, units = 0, 0
	for id, count in sold do
		local ore = OreConfig.get(id)
		if ore then
			payout += ore.baseValue * count
			units += count
		end
	end

	if units <= 0 then
		return { ok = false, reason = "nothing_to_sell", coins = profile.coins }
	end

	-- Rebirths multiply sale value as well as mining damage and income, so a
	-- rebirth is felt everywhere rather than only at the podiums.
	payout = math.floor(payout * ToolConfig.rebirthMultiplier(profile.rebirths))
	EconomyService.award(player, payout)

	-- A sale is a deliberate action; the number should move now, not on the
	-- next flush tick.
	flushCoins(player)
	DataService.pushSnapshot(player)
	return { ok = true, coins = DataService.get(player).coins }
end

-- What a bag is worth right now, for the Inventory screen's readout. Uses the
-- same numbers the sale will use.
function EconomyService.quoteBag(player: Player): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	return math.floor(InventoryService.rawValueOf(profile) * ToolConfig.rebirthMultiplier(profile.rebirths))
end

-- ==========================================================================
-- Layer unlocks
-- ==========================================================================

local function hasLayer(profile: Profile, index: number): boolean
	return table.find(profile.unlockedLayers, index) ~= nil
end

EconomyService.hasLayer = hasLayer

--[[
	Layers unlock in order: you cannot buy Crystalis while Ironvein is still
	locked. That keeps the cost curve meaningful and stops a lucky windfall
	skipping three bands of content.
]]
function EconomyService.unlockLayer(player: Player, layerIndex: any): PurchaseResult
	if type(layerIndex) ~= "number" or layerIndex ~= math.floor(layerIndex) then
		return { ok = false, reason = "bad_layer" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local layer = LayerConfig.get(layerIndex)
	if not layer then
		return { ok = false, reason = "unknown_layer" }
	end
	if hasLayer(profile, layerIndex) then
		return { ok = false, reason = "already_unlocked" }
	end
	if layerIndex > 1 and not hasLayer(profile, layerIndex - 1) then
		return { ok = false, reason = "previous_layer_locked" }
	end
	if profile.coins < layer.unlockCost then
		return { ok = false, reason = "cannot_afford", coins = profile.coins }
	end

	if not EconomyService.spend(player, layer.unlockCost) then
		return { ok = false, reason = "cannot_afford", coins = profile.coins }
	end

	DataService.update(player, function(p)
		table.insert(p.unlockedLayers, layerIndex)
		table.sort(p.unlockedLayers)
	end)

	RemoteRegistry.event("LayerUnlocked"):FireClient(player, layerIndex)
	RemoteRegistry.event("NotifyToast"):FireClient(player, "layer_unlocked", `{layer.displayName} unlocked`)
	EconomyService.LayerUnlocked:Fire(player, layerIndex)

	flushCoins(player)
	DataService.saveNow(player)
	DataService.pushSnapshot(player)
	return { ok = true, coins = DataService.get(player).coins }
end

-- ==========================================================================
-- Rebirth
-- ==========================================================================

function EconomyService.rebirthCost(player: Player): number
	local profile = DataService.get(player)
	return ToolConfig.rebirthCost(if profile then profile.rebirths else 0)
end

--[[
	Resets coins, tools, and carried ore for a permanent multiplier.

	Judgment call, since the doc says only "resets coins/tools": unlocked
	layers, owned and placed brainrots, plot slots, and the collection index all
	SURVIVE. Wiping layer keys would erase the single largest coin sink in the
	game every time, which turns rebirth from a boost into a punishment.
]]
function EconomyService.rebirth(player: Player): PurchaseResult
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local cost = ToolConfig.rebirthCost(profile.rebirths)
	if profile.coins < cost then
		return { ok = false, reason = "cannot_afford", coins = profile.coins }
	end

	DataService.update(player, function(p)
		p.coins = 0
		p.rebirths += 1

		table.clear(p.oreCounts)
		table.clear(p.ownedTools)
		p.ownedTools[ToolConfig.STARTER_PICKAXE] = true
		p.ownedTools[ToolConfig.STARTER_BACKPACK] = true
		p.equippedPickaxe = ToolConfig.STARTER_PICKAXE
		p.equippedBackpack = ToolConfig.STARTER_BACKPACK
	end)

	local updated = DataService.get(player)
	EconomyService.Rebirthed:Fire(player, updated.rebirths)
	RemoteRegistry.event("NotifyToast"):FireClient(
		player,
		"rebirth",
		`Rebirth {updated.rebirths} -- {string.format("%.2fx", ToolConfig.rebirthMultiplier(updated.rebirths))} multiplier`
	)

	-- High-stakes and irreversible; write it before anything else can go wrong.
	flushCoins(player)
	DataService.saveNow(player)
	DataService.pushSnapshot(player)
	return { ok = true, coins = 0 }
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function EconomyService.Init()
	AntiCheatService = require(script.Parent.AntiCheatService)
	DataService = require(script.Parent.DataService)
	InventoryService = require(script.Parent.InventoryService)
end

function EconomyService.Start()
	-- Flush loop. One pass per interval over players with something pending.
	task.spawn(function()
		while true do
			task.wait(GameConfig.CoinsPushIntervalSeconds)
			for player in pendingDelta do
				if player.Parent then
					flushCoins(player)
				else
					pendingDelta[player] = nil
				end
			end
		end
	end)

	-- Never leave a delta stranded on a player who left.
	DataService.ProfileReleased:Connect(function(player: Player)
		pendingDelta[player] = nil
	end)

	RemoteRegistry.func("RequestSell").OnServerInvoke = function(player, oreId)
		if not AntiCheatService.guard(player, "RequestSell") then
			return { ok = false, reason = "rate_limited" }
		end
		if oreId ~= nil and not AntiCheatService.isId(oreId) then
			AntiCheatService.report(player, "bad_sell_payload", typeof(oreId), "severe")
			return { ok = false, reason = "bad_request" }
		end
		return EconomyService.sell(player, oreId)
	end

	RemoteRegistry.func("RequestUnlockLayer").OnServerInvoke = function(player, layerIndex)
		if not AntiCheatService.guard(player, "RequestUnlockLayer") then
			return { ok = false, reason = "rate_limited" }
		end
		return EconomyService.unlockLayer(player, layerIndex)
	end

	RemoteRegistry.func("RequestRebirth").OnServerInvoke = function(player)
		if not AntiCheatService.guard(player, "RequestRebirth") then
			return { ok = false, reason = "rate_limited" }
		end
		return EconomyService.rebirth(player)
	end
end

return EconomyService
