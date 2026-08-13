--!strict
--[[
	Conversion
	The outcome table for a Conversion Chamber roll, and the odds derived from
	it.

	Shared deliberately. The doc requires the Convert screen to "show the
	outcome odds table honestly", and the only way to guarantee that is for the
	screen and the server to compute from the same function. If this lived on
	the server with the UI keeping its own copy, the two would drift and the
	displayed odds would quietly become a lie.

	Pure: no state, no remotes, no randomness. ConversionService supplies the
	Random and the pity counter.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)

local Conversion = {}

export type Entry = Rarity.WeightedEntry

--[[
	Every brainrot is reachable from every ore -- the fed ore only tilts the
	odds, it never restricts the pool. That means a Common ore can still, very
	rarely, produce a Mythic, which is what keeps early conversions worth doing.

	Entries the ore points at get their base rarity weight multiplied by
	GameConfig.ConversionOreBias.
]]
function Conversion.outcomeTable(oreId: string?): { Entry }
	local biased: { [string]: boolean } = {}
	if oreId then
		local ore = OreConfig.get(oreId)
		if ore then
			for _, id in ore.convertsTo do
				biased[id] = true
			end
		end
	end

	local entries: { Entry } = {}
	for _, def in BrainrotConfig.BRAINROTS do
		local weight = GameConfig.ConversionRarityWeights[def.rarity] or 0
		if biased[def.id] then
			weight *= GameConfig.ConversionOreBias
		end
		if weight > 0 then
			table.insert(entries, { id = def.id, weight = weight, rarity = def.rarity })
		end
	end

	-- Stable order so a seeded Random reproduces in tests.
	table.sort(entries, function(a, b)
		return a.id < b.id
	end)
	return entries
end

-- Per-character probabilities for the given ore. Sums to 1.
function Conversion.odds(oreId: string?): { [string]: number }
	return Rarity.odds(Conversion.outcomeTable(oreId))
end

-- Probabilities collapsed to rarity bands, which is what the Convert screen
-- actually shows -- 26 rows of character odds is unreadable.
function Conversion.rarityOdds(oreId: string?): { [string]: number }
	local perCharacter = Conversion.odds(oreId)
	local out: { [string]: number } = {}

	for id, chance in perCharacter do
		local def = BrainrotConfig.get(id)
		if def then
			out[def.rarity] = (out[def.rarity] or 0) + chance
		end
	end
	return out
end

-- Mutation weights as a rollable table. Multipliers live per-character in
-- BrainrotConfig; these are only the odds of each tier.
function Conversion.mutationTable(): { [string]: number }
	local out: { [string]: number } = {}
	for mutation, weight in GameConfig.MutationWeights do
		out[mutation] = weight
	end
	return out
end

function Conversion.mutationOdds(): { [string]: number }
	local total = 0
	for _, weight in GameConfig.MutationWeights do
		total += weight
	end

	local out: { [string]: number } = {}
	if total <= 0 then
		return out
	end
	for mutation, weight in GameConfig.MutationWeights do
		out[mutation] = weight / total
	end
	return out
end

-- Ore units one roll costs. Exposed so the UI and the server never disagree.
function Conversion.cost(): number
	return GameConfig.ConversionOreCost
end

return Conversion
