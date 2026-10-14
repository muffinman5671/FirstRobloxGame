--!strict
--[[
	IndexBonus
	What the collection log is worth.

	Every character discovered adds GameConfig.IndexBonusPerDiscovery to passive
	income, and finishing a whole rarity band adds that band's
	GameConfig.IndexSetBonus on top. The parts sum into one bonus, which
	multiplies income alongside the rebirth multiplier.

	Pure: it takes a profile's indexDiscovered map and nothing else, so the
	server (what is paid), the Index screen (what is shown) and BalanceModel
	(what is modelled) all read the same number rather than three copies of it.

	indexDiscovered also carries ore ids -- MiningService records those in the
	same map -- so this counts by walking the character list and looking each id
	up, never by counting the map's keys.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)

local IndexBonus = {}

export type Band = {
	rarity: string,
	found: number,
	total: number,
	complete: boolean,
	setBonus: number, -- what finishing this band adds, whether or not it has
}

export type Summary = {
	found: number,
	total: number,
	bonus: number, -- 0.17 means +17% income
	bands: { Band }, -- ascending rarity; bands with no characters are omitted
}

-- Characters per rarity. The roster is frozen config, so this is counted once.
local totals: { [string]: number } = {}
for _, def in BrainrotConfig.BRAINROTS do
	totals[def.rarity] = (totals[def.rarity] or 0) + 1
end

function IndexBonus.summarize(discovered: { [string]: boolean }?): Summary
	local map: { [string]: boolean } = discovered or {}

	local found = 0
	local foundByRarity: { [string]: number } = {}
	for _, def in BrainrotConfig.BRAINROTS do
		if map[def.id] == true then
			found += 1
			foundByRarity[def.rarity] = (foundByRarity[def.rarity] or 0) + 1
		end
	end

	local bonus = found * GameConfig.IndexBonusPerDiscovery
	local bands: { Band } = {}

	for _, rarity in Rarity.ORDER do
		local total = totals[rarity] or 0
		if total > 0 then
			local have = foundByRarity[rarity] or 0
			local setBonus = GameConfig.IndexSetBonus[rarity] or 0
			local complete = have >= total
			if complete then
				bonus += setBonus
			end
			table.insert(bands, {
				rarity = rarity,
				found = have,
				total = total,
				complete = complete,
				setBonus = setBonus,
			})
		end
	end

	return { found = found, total = BrainrotConfig.COUNT, bonus = bonus, bands = bands }
end

-- The factor income is multiplied by: 1 with an empty index.
function IndexBonus.multiplier(discovered: { [string]: boolean }?): number
	return 1 + IndexBonus.summarize(discovered).bonus
end

return table.freeze(IndexBonus)
