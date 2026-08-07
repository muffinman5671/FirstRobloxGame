--!strict
--[[
	LayerConfig
	The six depth bands. Layer index is derived from a block's Y position, never
	stored on the block, so MineService can generate a chunk knowing only where
	it sits in the world.

	Depth is measured downward from GameConfig.SurfaceY: a block at Y = -200 is
	at depth 200, which lands in Ironvein.

	Bands are [minDepth, maxDepth). The last band's maxDepth is the floor of the
	mine -- MineService stops generating below it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)

type LayerDef = SharedTypes.LayerDef

local LayerConfig = {}

-- unlockCost is coins, paid once, and gates descent past minDepth.
-- hpMultiplier compounds with ore hardness against GameConfig.BlockBaseHp.
LayerConfig.LAYERS = table.freeze({
	{
		index = 1,
		id = "topsoil",
		displayName = "Topsoil",
		minDepth = 0,
		maxDepth = 70,
		hpMultiplier = 1,
		unlockCost = 0,
		ambientColor = Color3.fromRGB(118, 106, 88),
		fogColor = Color3.fromRGB(150, 138, 118),
		fogEnd = 220,
	},
	{
		index = 2,
		id = "stonecore",
		displayName = "Stonecore",
		minDepth = 70,
		maxDepth = 180,
		hpMultiplier = 3.5,
		unlockCost = 2500,
		ambientColor = Color3.fromRGB(84, 88, 96),
		fogColor = Color3.fromRGB(96, 102, 112),
		fogEnd = 180,
	},
	{
		index = 3,
		id = "ironvein",
		displayName = "Ironvein",
		minDepth = 180,
		maxDepth = 330,
		hpMultiplier = 12,
		unlockCost = 28000,
		ambientColor = Color3.fromRGB(96, 74, 60),
		fogColor = Color3.fromRGB(112, 84, 66),
		fogEnd = 150,
	},
	{
		index = 4,
		id = "crystalis",
		displayName = "Crystalis",
		minDepth = 330,
		maxDepth = 520,
		hpMultiplier = 42,
		unlockCost = 310000,
		ambientColor = Color3.fromRGB(70, 96, 128),
		fogColor = Color3.fromRGB(78, 118, 158),
		fogEnd = 130,
	},
	{
		index = 5,
		id = "magmadeep",
		displayName = "Magmadeep",
		minDepth = 520,
		maxDepth = 760,
		hpMultiplier = 150,
		unlockCost = 3400000,
		ambientColor = Color3.fromRGB(128, 58, 40),
		fogColor = Color3.fromRGB(158, 62, 36),
		fogEnd = 110,
	},
	{
		index = 6,
		id = "the_static",
		displayName = "The Static",
		minDepth = 760,
		maxDepth = 1040,
		hpMultiplier = 520,
		unlockCost = 38000000,
		ambientColor = Color3.fromRGB(58, 58, 66),
		fogColor = Color3.fromRGB(40, 40, 48),
		fogEnd = 80,
	},
} :: { LayerDef })

local byIndex: { [number]: LayerDef } = {}
local byId: { [string]: LayerDef } = {}
for _, layer in LayerConfig.LAYERS do
	byIndex[layer.index] = layer
	byId[layer.id] = layer
end

LayerConfig.COUNT = #LayerConfig.LAYERS
LayerConfig.MAX_DEPTH = LayerConfig.LAYERS[LayerConfig.COUNT].maxDepth

function LayerConfig.get(index: number): LayerDef?
	return byIndex[index]
end

function LayerConfig.getById(id: string): LayerDef?
	return byId[id]
end

-- Layer index for a depth in studs. Clamped, so depths above the surface read
-- as layer 1 and anything past the mine floor reads as the last layer.
function LayerConfig.indexForDepth(depth: number): number
	for _, layer in LayerConfig.LAYERS do
		if depth < layer.maxDepth then
			return layer.index
		end
	end
	return LayerConfig.COUNT
end

-- Convenience for MineService, which works in world Y rather than depth.
function LayerConfig.indexForY(y: number, surfaceY: number): number
	return LayerConfig.indexForDepth(math.max(0, surfaceY - y))
end

function LayerConfig.forDepth(depth: number): LayerDef
	return byIndex[LayerConfig.indexForDepth(depth)]
end

-- Total coins to own every layer, used by the Shop's progress readout.
function LayerConfig.totalUnlockCost(): number
	local total = 0
	for _, layer in LayerConfig.LAYERS do
		total += layer.unlockCost
	end
	return total
end

return table.freeze(LayerConfig)
