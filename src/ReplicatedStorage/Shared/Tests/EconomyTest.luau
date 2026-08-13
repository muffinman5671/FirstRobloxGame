--!strict
--[[
	EconomyTest
	The doc's §8.4 "economy price math": that the generated tool curves actually
	follow the constants they claim to, and that the config is internally
	consistent.

	These are pure config assertions -- no player, no DataStore, no running
	game. They catch the class of mistake where someone tunes a growth constant
	and the tiers quietly stop being monotonic, or an ore references a
	character that no longer exists.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LayerConfig = require(ReplicatedStorage.Shared.Config.LayerConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

return function(t)
	-- ---------- starter kit is free ----------
	t.equal(ToolConfig.PICKAXES[1].price, 0, "starter pickaxe is free")
	t.equal(ToolConfig.BACKPACKS[1].price, 0, "starter backpack is free")
	t.equal(ToolConfig.PICKAXES[1].id, ToolConfig.STARTER_PICKAXE, "starter pickaxe id matches tier 1")

	-- ---------- monotonic curves ----------
	local priceOk, powerOk, speedOk = true, true, true
	for i = 2, #ToolConfig.PICKAXES do
		local prev, cur = ToolConfig.PICKAXES[i - 1], ToolConfig.PICKAXES[i]
		if cur.power <= prev.power then powerOk = false end
		if i > 2 and cur.price <= prev.price then priceOk = false end
		if cur.swingsPerSecond < prev.swingsPerSecond then speedOk = false end
	end
	t.ok(powerOk, "pickaxe power strictly increases")
	t.ok(priceOk, "pickaxe price strictly increases past the free tier")
	t.ok(speedOk, "pickaxe swing speed never decreases")

	local capOk = true
	for i = 2, #ToolConfig.BACKPACKS do
		if ToolConfig.BACKPACKS[i].capacity <= ToolConfig.BACKPACKS[i - 1].capacity then capOk = false end
	end
	t.ok(capOk, "backpack capacity strictly increases")

	-- ---------- curves follow their constants ----------
	-- Prices are rounded for readability, so compare ratios with slack rather
	-- than demanding exact geometric values.
	local ratios = {}
	for i = 3, #ToolConfig.PICKAXES do
		table.insert(ratios, ToolConfig.PICKAXES[i].price / ToolConfig.PICKAXES[i - 1].price)
	end
	local sum = 0
	for _, r in ratios do sum += r end
	t.near(sum / #ratios, GameConfig.CostGrowth, 0.03, "average price ratio tracks CostGrowth")

	local powerRatios = 0
	for i = 2, #ToolConfig.PICKAXES do
		powerRatios += ToolConfig.PICKAXES[i].power / ToolConfig.PICKAXES[i - 1].power
	end
	t.near(powerRatios / (#ToolConfig.PICKAXES - 1), GameConfig.PickaxePowerGrowth, 0.02,
		"average power ratio tracks PickaxePowerGrowth")

	t.ok(GameConfig.PickaxePowerGrowth < GameConfig.CostGrowth,
		"damage grows slower than cost, so it never outruns block HP")
	t.ok(GameConfig.IncomeGrowth > GameConfig.CostGrowth,
		"income grows faster than cost, so upgrades stay worth buying")

	-- ---------- rebirth ----------
	t.near(ToolConfig.rebirthMultiplier(0), 1, 1e-9, "no rebirths means no multiplier")
	t.ok(ToolConfig.rebirthMultiplier(3) > ToolConfig.rebirthMultiplier(2), "rebirth multiplier increases")
	t.ok(ToolConfig.rebirthCost(1) > ToolConfig.rebirthCost(0), "rebirth cost increases")

	-- ---------- plot slots ----------
	t.ok(ToolConfig.plotSlotPrice(GameConfig.MaxPlotSlots) == nil, "no price past the slot cap")
	t.ok(ToolConfig.plotSlotPrice(GameConfig.StartingPlotSlots) ~= nil, "the first extra slot has a price")
	t.ok(
		ToolConfig.plotSlotPrice(GameConfig.StartingPlotSlots + 3) > ToolConfig.plotSlotPrice(GameConfig.StartingPlotSlots),
		"slot price rises with each purchase"
	)

	-- ---------- referential integrity ----------
	local badRefs = {}
	for _, ore in OreConfig.ORES do
		for _, id in ore.convertsTo do
			if not BrainrotConfig.exists(id) then
				table.insert(badRefs, `{ore.id} -> {id}`)
			end
		end
	end
	t.equal(#badRefs, 0, "every convertsTo id resolves to a real character")

	local reachable = {}
	for _, ore in OreConfig.ORES do
		for _, id in ore.convertsTo do reachable[id] = true end
	end
	local orphans = {}
	for _, def in BrainrotConfig.BRAINROTS do
		if not reachable[def.id] then table.insert(orphans, def.id) end
	end
	t.equal(#orphans, 0, "every character is reachable from some ore")

	-- ---------- layers ----------
	t.equal(LayerConfig.COUNT, 6, "six layers")
	local layersOk, hpOk = true, true
	for i = 2, LayerConfig.COUNT do
		local prev, cur = LayerConfig.get(i - 1), LayerConfig.get(i)
		if cur.minDepth ~= prev.maxDepth then layersOk = false end
		if cur.hpMultiplier <= prev.hpMultiplier then hpOk = false end
		if cur.unlockCost <= prev.unlockCost then layersOk = false end
	end
	t.ok(layersOk, "layer depth bands are contiguous and costs increase")
	t.ok(hpOk, "block HP multiplier increases with depth")
	t.equal(LayerConfig.get(1).unlockCost, 0, "the surface layer is free")

	-- ---------- ore ----------
	local emptyLayers = {}
	for i = 1, LayerConfig.COUNT do
		if #OreConfig.spawnTableForLayer(i, 0) == 0 then table.insert(emptyLayers, i) end
	end
	t.equal(#emptyLayers, 0, "every layer yields ore at zero rebirths")

	local surfaceOre = {}
	for _, entry in OreConfig.spawnTableForLayer(1, math.huge) do
		if OreConfig.get(entry.id).rarity ~= "Common" then table.insert(surfaceOre, entry.id) end
	end
	t.equal(#surfaceOre, 0, "the surface layer carries filler rock only")

	t.ok(
		#OreConfig.spawnTableForLayer(6, GameConfig.RebirthsForMythicOre) > #OreConfig.spawnTableForLayer(6, 0),
		"the rebirth gate opens extra ore in the deepest layer"
	)

	-- ---------- brainrot economics ----------
	local incomeOk, sellOk = true, true
	local byRarity: { [string]: { number } } = {}
	for _, def in BrainrotConfig.BRAINROTS do
		if def.incomePerSecond <= 0 then incomeOk = false end
		if def.sellValue <= 0 then sellOk = false end
		byRarity[def.rarity] = byRarity[def.rarity] or {}
		table.insert(byRarity[def.rarity], def.incomePerSecond)
	end
	t.ok(incomeOk, "every character earns something")
	t.ok(sellOk, "every character has a sell value")

	-- Rarity bands must not overlap: the weakest Epic should out-earn the
	-- strongest Rare, or rarity stops meaning anything.
	local bandsOk = true
	for i = 2, #Rarity.ORDER do
		local lower, upper = byRarity[Rarity.ORDER[i - 1]], byRarity[Rarity.ORDER[i]]
		if lower and upper then
			local maxLower, minUpper = 0, math.huge
			for _, v in lower do maxLower = math.max(maxLower, v) end
			for _, v in upper do minUpper = math.min(minUpper, v) end
			if minUpper <= maxLower then bandsOk = false end
		end
	end
	t.ok(bandsOk, "income bands do not overlap between rarities")

	-- ---------- mutations ----------
	local m = BrainrotConfig.MUTATIONS
	t.equal(m.Normal, 1.0, "Normal is a 1x multiplier")
	t.ok(m.Golden > m.Normal and m.Diamond > m.Golden and m.Glitched > m.Diamond,
		"mutation multipliers ascend")
	t.near(
		BrainrotConfig.incomeFor("tralalero_tralala", "Golden"),
		BrainrotConfig.incomeFor("tralalero_tralala", "Normal") * m.Golden,
		1e-6,
		"mutation multiplier is applied to income"
	)
	t.equal(BrainrotConfig.incomeFor("not_a_character", "Normal"), 0, "an unknown character earns nothing")
end
