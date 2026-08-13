--!strict
--[[
	ShopService
	Purchase and equip validation for pickaxes, backpacks, and podium slots.

	The client sends an item id and nothing else. Price, ownership, and tier
	come from config and the profile; a client that invents an id, asks for
	something it already owns, or can't afford gets a named refusal.

	EconomyService owns the coins. This service decides whether a purchase is
	legal and what it grants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

type PurchaseResult = SharedTypes.PurchaseResult

local ShopService = {}
ShopService.Name = "ShopService"

local AntiCheatService
local DataService
local EconomyService
local MiningService

-- (player, itemId)
ShopService.Purchased = Signal.new()
-- (player, itemId)
ShopService.Equipped = Signal.new()

-- Sentinel id for the podium slot upgrade, which isn't a ToolConfig entry.
local PLOT_SLOT_ID = "plot_slot"
ShopService.PLOT_SLOT_ID = PLOT_SLOT_ID

-- ==========================================================================
-- Purchase
-- ==========================================================================

local function buyTool(player: Player, itemId: string): PurchaseResult
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local def = ToolConfig.getTool(itemId)
	if not def then
		return { ok = false, reason = "unknown_item" }
	end
	if profile.ownedTools[itemId] then
		return { ok = false, reason = "already_owned" }
	end

	-- Tiers are bought in order on each track. Without this, a windfall lets a
	-- player skip straight to the top tool and the whole cost curve stops
	-- mattering.
	if def.tier > 1 then
		local isPickaxe = ToolConfig.isPickaxe(itemId)
		local previous = if isPickaxe then ToolConfig.PICKAXES[def.tier - 1] else ToolConfig.BACKPACKS[def.tier - 1]
		if previous and not profile.ownedTools[previous.id] then
			return { ok = false, reason = "previous_tier_missing" }
		end
	end

	if profile.coins < def.price then
		return { ok = false, reason = "cannot_afford", coins = profile.coins }
	end
	if not EconomyService.spend(player, def.price) then
		return { ok = false, reason = "cannot_afford", coins = profile.coins }
	end

	DataService.update(player, function(p)
		p.ownedTools[itemId] = true
		-- Auto-equip: nobody buys a better pickaxe and then wants to keep
		-- swinging the old one.
		if ToolConfig.isPickaxe(itemId) then
			p.equippedPickaxe = itemId
		else
			p.equippedBackpack = itemId
		end
	end)

	if ToolConfig.isPickaxe(itemId) and MiningService then
		MiningService.givePickaxe(player)
	end

	ShopService.Purchased:Fire(player, itemId)
	RemoteRegistry.event("NotifyToast"):FireClient(player, "purchase", `Bought {def.displayName}`)

	DataService.saveNow(player)
	DataService.pushSnapshot(player)
	return { ok = true, coins = DataService.get(player).coins }
end

local function buyPlotSlot(player: Player): PurchaseResult
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local price = ToolConfig.plotSlotPrice(profile.plotSlots)
	if not price then
		return { ok = false, reason = "max_slots" }
	end
	if profile.coins < price then
		return { ok = false, reason = "cannot_afford", coins = profile.coins }
	end
	if not EconomyService.spend(player, price) then
		return { ok = false, reason = "cannot_afford", coins = profile.coins }
	end

	local slots = 0
	DataService.update(player, function(p)
		p.plotSlots = math.min(p.plotSlots + 1, GameConfig.MaxPlotSlots)
		slots = p.plotSlots
	end)

	ShopService.Purchased:Fire(player, PLOT_SLOT_ID)
	RemoteRegistry.event("NotifyToast"):FireClient(player, "purchase", `Podium slots: {slots}`)

	DataService.saveNow(player)
	DataService.pushSnapshot(player)
	return { ok = true, coins = DataService.get(player).coins }
end

function ShopService.purchase(player: Player, itemId: any): PurchaseResult
	if type(itemId) ~= "string" then
		return { ok = false, reason = "bad_request" }
	end
	if itemId == PLOT_SLOT_ID then
		return buyPlotSlot(player)
	end
	return buyTool(player, itemId)
end

-- ==========================================================================
-- Equip
-- ==========================================================================

function ShopService.equip(player: Player, itemId: any): PurchaseResult
	if type(itemId) ~= "string" then
		return { ok = false, reason = "bad_request" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local def = ToolConfig.getTool(itemId)
	if not def then
		return { ok = false, reason = "unknown_item" }
	end
	if not profile.ownedTools[itemId] then
		return { ok = false, reason = "not_owned" }
	end

	local isPickaxe = ToolConfig.isPickaxe(itemId)
	if (isPickaxe and profile.equippedPickaxe == itemId) or (not isPickaxe and profile.equippedBackpack == itemId) then
		return { ok = false, reason = "already_equipped" }
	end

	DataService.update(player, function(p)
		if isPickaxe then
			p.equippedPickaxe = itemId
		else
			p.equippedBackpack = itemId
		end
	end)

	if isPickaxe and MiningService then
		MiningService.givePickaxe(player)
	end

	ShopService.Equipped:Fire(player, itemId)
	DataService.pushSnapshot(player)
	return { ok = true, coins = profile.coins }
end

-- ==========================================================================
-- Pricing helpers for the client's shop cards
-- ==========================================================================

-- Price of the podium slot upgrade at the player's current count, or nil when
-- maxed. Kept server-side so the card and the purchase agree.
function ShopService.plotSlotPrice(player: Player): number?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	return ToolConfig.plotSlotPrice(profile.plotSlots)
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function ShopService.Init()
	AntiCheatService = require(script.Parent.AntiCheatService)
	DataService = require(script.Parent.DataService)
	EconomyService = require(script.Parent.EconomyService)
	MiningService = require(script.Parent.MiningService)
end

function ShopService.Start()
	RemoteRegistry.func("RequestPurchase").OnServerInvoke = function(player, itemId)
		if not AntiCheatService.guard(player, "RequestPurchase") then
			return { ok = false, reason = "rate_limited" }
		end
		return ShopService.purchase(player, itemId)
	end

	RemoteRegistry.func("RequestEquip").OnServerInvoke = function(player, itemId)
		if not AntiCheatService.guard(player, "RequestEquip") then
			return { ok = false, reason = "rate_limited" }
		end
		return ShopService.equip(player, itemId)
	end
end

return ShopService
