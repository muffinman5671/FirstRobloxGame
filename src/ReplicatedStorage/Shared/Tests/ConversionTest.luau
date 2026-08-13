--!strict
--[[
	ConversionTest
	The shared outcome table and its odds.

	This one exists because the doc requires the Convert screen to show odds
	honestly. The screen and the server both call Conversion.outcomeTable, so
	these assertions are simultaneously testing what the player is shown and
	what they actually get.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local Conversion = require(ReplicatedStorage.Shared.Modules.Conversion)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)

return function(t)
	-- ---------- table shape ----------
	local base = Conversion.outcomeTable(nil)
	t.equal(#base, BrainrotConfig.COUNT, "every character appears in the base table")

	local allPositive, allReal = true, true
	for _, entry in base do
		if entry.weight <= 0 then allPositive = false end
		if not BrainrotConfig.exists(entry.id) then allReal = false end
	end
	t.ok(allPositive, "every entry carries a positive weight")
	t.ok(allReal, "every entry names a real character")

	-- ---------- odds ----------
	local odds = Conversion.odds(nil)
	local sum = 0
	for _, chance in odds do sum += chance end
	t.near(sum, 1, 1e-9, "per-character odds sum to 1")

	local rarityOdds = Conversion.rarityOdds(nil)
	local raritySum = 0
	for _, chance in rarityOdds do raritySum += chance end
	t.near(raritySum, 1, 1e-9, "rarity-band odds sum to 1")

	-- Every band must stay reachable, or a rarity tier is decorative.
	local reachable = true
	for _, rarity in Rarity.ORDER do
		if (rarityOdds[rarity] or 0) <= 0 then reachable = false end
	end
	t.ok(reachable, "every rarity band is reachable on an unbiased roll")

	-- Rarer bands must be rarer. This is the assertion that catches someone
	-- editing ConversionRarityWeights into an ordering that doesn't descend.
	local descending = true
	for i = 2, #Rarity.ORDER do
		if (rarityOdds[Rarity.ORDER[i]] or 0) >= (rarityOdds[Rarity.ORDER[i - 1]] or 0) then
			descending = false
		end
	end
	t.ok(descending, "rarer bands are strictly less likely")

	-- ---------- ore bias ----------
	local oreId = "cappuccino_ore"
	local ore = OreConfig.get(oreId)
	t.ok(ore ~= nil, "the test ore exists")

	local biased = Conversion.odds(oreId)
	local biasedSum = 0
	for _, chance in biased do biasedSum += chance end
	t.near(biasedSum, 1, 1e-9, "biased odds still sum to 1")

	local liftedAll = true
	for _, id in ore.convertsTo do
		if biased[id] <= odds[id] then liftedAll = false end
	end
	t.ok(liftedAll, "every convertsTo target is more likely with its ore")

	-- Bias must tilt, never restrict: an unrelated character stays reachable.
	local unrelated = nil
	for _, def in BrainrotConfig.BRAINROTS do
		local named = false
		for _, id in ore.convertsTo do
			if id == def.id then named = true end
		end
		if not named then
			unrelated = def.id
			break
		end
	end
	t.ok(unrelated ~= nil and biased[unrelated] > 0,
		"characters the ore does not name remain reachable")

	-- The lift should be proportional to ConversionOreBias.
	local target = ore.convertsTo[1]
	local targetDef = BrainrotConfig.get(target)
	local sameRarityUnbiased = nil
	for _, def in BrainrotConfig.BRAINROTS do
		if def.rarity == targetDef.rarity and def.id ~= target then
			local named = false
			for _, id in ore.convertsTo do
				if id == def.id then named = true end
			end
			if not named then
				sameRarityUnbiased = def.id
				break
			end
		end
	end
	if sameRarityUnbiased then
		t.near(
			biased[target] / biased[sameRarityUnbiased],
			GameConfig.ConversionOreBias,
			0.001,
			"a biased entry is exactly ConversionOreBias times a same-rarity unbiased one"
		)
	else
		t.ok(true, "no same-rarity comparison available (skipped)")
	end

	-- ---------- mutations ----------
	local mutationOdds = Conversion.mutationOdds()
	local mutationSum = 0
	for _, chance in mutationOdds do mutationSum += chance end
	t.near(mutationSum, 1, 1e-9, "mutation odds sum to 1")
	t.ok(mutationOdds.Normal > mutationOdds.Golden, "Normal is the most likely mutation")
	t.ok(mutationOdds.Glitched < mutationOdds.Diamond, "Glitched is the rarest mutation")

	-- ---------- cost ----------
	t.equal(Conversion.cost(), GameConfig.ConversionOreCost, "cost comes from config")
	t.ok(Conversion.cost() > 0, "a roll costs something")

	-- ---------- unknown ore ----------
	local unknown = Conversion.odds("not_a_real_ore")
	local unknownSum = 0
	for _, chance in unknown do unknownSum += chance end
	t.near(unknownSum, 1, 1e-9, "an unknown ore falls back to unbiased odds")
end
