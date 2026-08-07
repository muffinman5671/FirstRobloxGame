--!strict
--[[
	ToolConfig
	Pickaxes, backpacks, and podium slot pricing.

	Tiers are *generated* from the curve constants in GameConfig rather than
	typed out, so rebalancing the whole progression is a one-line edit there and
	no tier can drift off the curve by hand. Only the display names are authored.

	Tier 1 of each track is the free starter kit every profile begins with.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)

type PickaxeDef = SharedTypes.PickaxeDef
type BackpackDef = SharedTypes.BackpackDef

local ToolConfig = {}

local PICKAXE_NAMES = {
	"Cracked Trowel",
	"Tin Pick",
	"Iron Pick",
	"Steel Pick",
	"Tungsten Pick",
	"Obsidian Pick",
	"Quartz Pick",
	"Cobalt Pick",
	"Titanium Pick",
	"Plasma Pick",
	"Meteor Pick",
	"Prism Pick",
	"Voltaic Pick",
	"Magma Pick",
	"Abyssal Pick",
	"Chrono Pick",
	"Nebula Pick",
	"Singularity Pick",
	"Paradox Pick",
	"Static Breaker",
}

local BACKPACK_NAMES = {
	"Paper Sack",
	"Canvas Pouch",
	"Leather Satchel",
	"Miner's Duffel",
	"Reinforced Pack",
	"Hauler Rig",
	"Cargo Harness",
	"Freight Frame",
	"Gravity Well Pack",
	"Compressor Rig",
	"Voidfold Satchel",
	"Infinity Crate",
}

assert(#PICKAXE_NAMES == GameConfig.PickaxeTiers, "ToolConfig: pickaxe name count must match GameConfig.PickaxeTiers")
assert(#BACKPACK_NAMES == GameConfig.BackpackTiers, "ToolConfig: backpack name count must match GameConfig.BackpackTiers")

local function round(value: number, places: number): number
	local scale = 10 ^ places
	return math.floor(value * scale + 0.5) / scale
end

-- Prices are rounded to two significant-ish figures so the shop reads cleanly
-- (1,860 rather than 1,862.34) without breaking the curve's shape.
local function roundPrice(value: number): number
	if value < 100 then
		return math.floor(value + 0.5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(value)) - 1)
	return math.floor(value / magnitude + 0.5) * magnitude
end

-- ==========================================================================
-- Pickaxes
-- ==========================================================================

local pickaxes: { PickaxeDef } = {}
for tier = 1, GameConfig.PickaxeTiers do
	local step = tier - 1
	local progress = if GameConfig.PickaxeTiers > 1 then step / (GameConfig.PickaxeTiers - 1) else 0

	pickaxes[tier] = {
		id = `pickaxe_{tier}`,
		displayName = PICKAXE_NAMES[tier],
		tier = tier,
		power = round(GameConfig.PickaxeBasePower * GameConfig.PickaxePowerGrowth ^ step, 2),
		-- Swing speed and reach interpolate linearly across the track. Both are
		-- feel knobs rather than power knobs, so they stay off the geometric curve.
		swingsPerSecond = round(
			GameConfig.PickaxeBaseSwingsPerSecond
				+ (GameConfig.PickaxeMaxSwingsPerSecond - GameConfig.PickaxeBaseSwingsPerSecond) * progress,
			2
		),
		reach = round(
			GameConfig.PickaxeBaseReach + (GameConfig.PickaxeMaxReach - GameConfig.PickaxeBaseReach) * progress,
			1
		),
		price = if tier == 1 then 0 else roundPrice(GameConfig.PickaxeBasePrice * GameConfig.CostGrowth ^ (tier - 2)),
	}
end

ToolConfig.PICKAXES = table.freeze(pickaxes)

-- ==========================================================================
-- Backpacks
-- ==========================================================================

local backpacks: { BackpackDef } = {}
for tier = 1, GameConfig.BackpackTiers do
	local step = tier - 1

	backpacks[tier] = {
		id = `backpack_{tier}`,
		displayName = BACKPACK_NAMES[tier],
		tier = tier,
		capacity = math.floor(GameConfig.BackpackBaseCapacity * GameConfig.BackpackCapacityGrowth ^ step + 0.5),
		price = if tier == 1 then 0 else roundPrice(GameConfig.BackpackBasePrice * GameConfig.CostGrowth ^ (tier - 2)),
	}
end

ToolConfig.BACKPACKS = table.freeze(backpacks)

-- ==========================================================================
-- Lookups
-- ==========================================================================

local pickaxeById: { [string]: PickaxeDef } = {}
for _, def in pickaxes do
	pickaxeById[def.id] = def
end

local backpackById: { [string]: BackpackDef } = {}
for _, def in backpacks do
	backpackById[def.id] = def
end

ToolConfig.STARTER_PICKAXE = pickaxes[1].id
ToolConfig.STARTER_BACKPACK = backpacks[1].id

function ToolConfig.getPickaxe(id: string): PickaxeDef?
	return pickaxeById[id]
end

function ToolConfig.getBackpack(id: string): BackpackDef?
	return backpackById[id]
end

-- Either track, for generic shop and validation paths.
function ToolConfig.getTool(id: string): (PickaxeDef | BackpackDef)?
	return pickaxeById[id] or backpackById[id]
end

function ToolConfig.isPickaxe(id: string): boolean
	return pickaxeById[id] ~= nil
end

function ToolConfig.isBackpack(id: string): boolean
	return backpackById[id] ~= nil
end

-- Next tier up on the same track, or nil at the top. Drives the shop's
-- "stat delta vs. currently equipped" card.
function ToolConfig.nextPickaxe(id: string): PickaxeDef?
	local current = pickaxeById[id]
	return if current then pickaxes[current.tier + 1] else nil
end

function ToolConfig.nextBackpack(id: string): BackpackDef?
	local current = backpackById[id]
	return if current then backpacks[current.tier + 1] else nil
end

-- ==========================================================================
-- Podium slots
-- ==========================================================================

--[[
	Cost of the next podium slot given how many the player already has.
	Returns nil once GameConfig.MaxPlotSlots is reached, which the shop renders
	as a maxed-out card.
]]
function ToolConfig.plotSlotPrice(currentSlots: number): number?
	if currentSlots >= GameConfig.MaxPlotSlots then
		return nil
	end
	local purchased = currentSlots - GameConfig.StartingPlotSlots
	return roundPrice(GameConfig.PlotSlotBasePrice * GameConfig.CostGrowth ^ math.max(0, purchased))
end

-- Coins to go from the starting slot count to every slot. Shop progress readout.
function ToolConfig.totalPlotSlotCost(): number
	local total = 0
	for slots = GameConfig.StartingPlotSlots, GameConfig.MaxPlotSlots - 1 do
		total += ToolConfig.plotSlotPrice(slots) or 0
	end
	return total
end

-- ==========================================================================
-- Rebirth
-- ==========================================================================

-- Coins required to perform rebirth number `rebirths + 1`.
function ToolConfig.rebirthCost(rebirths: number): number
	return roundPrice(GameConfig.RebirthBaseCost * GameConfig.RebirthCostGrowth ^ rebirths)
end

-- Multiplier applied to both mining damage and passive income.
function ToolConfig.rebirthMultiplier(rebirths: number): number
	return 1 + rebirths * GameConfig.RebirthMultiplierStep
end

return table.freeze(ToolConfig)
