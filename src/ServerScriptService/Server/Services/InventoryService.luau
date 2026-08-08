--!strict
--[[
	InventoryService
	Ore counts and backpack capacity enforcement.

	Pulled forward from phase C: mining that cannot credit ore isn't a working
	system, and the doc requires every system to function end to end. Phase C
	adds selling and the shop on top of this; the storage rules live here.

	Capacity is weight, not slot count -- an ore's weightPerUnit decides how much
	room a unit takes, so a Mythic haul fills a bag far faster than dirt. All
	quantities are server-computed; a client never supplies a count.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

type Profile = SharedTypes.Profile

local InventoryService = {}
InventoryService.Name = "InventoryService"

local DataService

-- (player, oreId, amount, newTotal)
InventoryService.OreCredited = Signal.new()
-- (player) -- fired once per fill, not once per rejected unit
InventoryService.BackpackFilled = Signal.new()

-- Tracks who has already been told they're full, so a player swinging at a
-- full bag gets one notification rather than one per swing.
local notifiedFull: { [Player]: boolean } = {}

-- ==========================================================================
-- Queries
-- ==========================================================================

function InventoryService.capacityOf(profile: Profile): number
	local backpack = ToolConfig.getBackpack(profile.equippedBackpack)
	if not backpack then
		-- Equipped id isn't a real backpack (corrupt or hand-edited save).
		-- Fall back to the starter rather than granting infinite room.
		local starter = ToolConfig.getBackpack(ToolConfig.STARTER_BACKPACK)
		return if starter then starter.capacity else 0
	end
	return backpack.capacity
end

function InventoryService.usedWeightOf(profile: Profile): number
	local total = 0
	for oreId, count in profile.oreCounts do
		local ore = OreConfig.get(oreId)
		if ore and count > 0 then
			total += count * ore.weightPerUnit
		end
	end
	return total
end

function InventoryService.freeWeightOf(profile: Profile): number
	return math.max(0, InventoryService.capacityOf(profile) - InventoryService.usedWeightOf(profile))
end

function InventoryService.isFull(profile: Profile): boolean
	return InventoryService.freeWeightOf(profile) <= 0
end

-- Raw coin value of everything in the bag, at base prices. EconomyService
-- applies any multipliers on top when the sale actually happens.
function InventoryService.rawValueOf(profile: Profile): number
	local total = 0
	for oreId, count in profile.oreCounts do
		local ore = OreConfig.get(oreId)
		if ore and count > 0 then
			total += count * ore.baseValue
		end
	end
	return total
end

-- ==========================================================================
-- Mutation
-- ==========================================================================

--[[
	Credits up to `amount` units of ore, clamped to remaining capacity.
	Returns (credited, wasCapped).

	A partial credit is deliberate: breaking a block with one slot left gives
	you that one unit rather than voiding the whole drop.
]]
function InventoryService.tryAdd(player: Player, oreId: string, amount: number): (number, boolean)
	local ore = OreConfig.get(oreId)
	if not ore or amount <= 0 then
		return 0, false
	end

	local profile = DataService.get(player)
	if not profile then
		return 0, false
	end

	local free = InventoryService.freeWeightOf(profile)
	if free <= 0 then
		if not notifiedFull[player] then
			notifiedFull[player] = true
			RemoteRegistry.event("BackpackFull"):FireClient(player)
			InventoryService.BackpackFilled:Fire(player)
		end
		return 0, true
	end

	local fits = math.floor(free / ore.weightPerUnit)
	local credited = math.min(amount, fits)
	if credited <= 0 then
		-- Room remains, but not enough for even one unit of something this
		-- heavy. Treat as full so the player gets told to sell.
		if not notifiedFull[player] then
			notifiedFull[player] = true
			RemoteRegistry.event("BackpackFull"):FireClient(player)
			InventoryService.BackpackFilled:Fire(player)
		end
		return 0, true
	end

	local newTotal = 0
	DataService.update(player, function(p)
		p.oreCounts[oreId] = (p.oreCounts[oreId] or 0) + credited
		newTotal = p.oreCounts[oreId]
	end)

	RemoteRegistry.event("OreCredited"):FireClient(player, oreId, credited, newTotal)
	InventoryService.OreCredited:Fire(player, oreId, credited, newTotal)

	local capped = credited < amount
	if capped and not notifiedFull[player] then
		notifiedFull[player] = true
		RemoteRegistry.event("BackpackFull"):FireClient(player)
		InventoryService.BackpackFilled:Fire(player)
	end

	return credited, capped
end

-- Removes ore. Returns how much was actually taken, which is never more than
-- the player holds -- the caller cannot drive a count negative.
function InventoryService.remove(player: Player, oreId: string, amount: number): number
	if amount <= 0 then
		return 0
	end

	local profile = DataService.get(player)
	if not profile then
		return 0
	end

	local held = profile.oreCounts[oreId] or 0
	local taken = math.min(held, amount)
	if taken <= 0 then
		return 0
	end

	DataService.update(player, function(p)
		local remaining = (p.oreCounts[oreId] or 0) - taken
		p.oreCounts[oreId] = if remaining > 0 then remaining else nil
	end)

	notifiedFull[player] = nil
	return taken
end

-- Empties the bag and returns what was in it, for EconomyService's "Sell All".
function InventoryService.takeAll(player: Player): { [string]: number }
	local profile = DataService.get(player)
	if not profile then
		return {}
	end

	local taken: { [string]: number } = {}
	for oreId, count in profile.oreCounts do
		if count > 0 then
			taken[oreId] = count
		end
	end

	DataService.update(player, function(p)
		table.clear(p.oreCounts)
	end)

	notifiedFull[player] = nil
	return taken
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function InventoryService.Init()
	DataService = require(script.Parent.DataService)
end

function InventoryService.Start()
	-- Clearing space re-arms the full notification.
	DataService.ProfileReleased:Connect(function(player: Player)
		notifiedFull[player] = nil
	end)
end

return InventoryService
