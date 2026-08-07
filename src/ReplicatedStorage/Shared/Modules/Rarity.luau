--!strict
--[[
	Rarity
	Weighted selection plus the pity system that backs ConversionService.

	Every function takes an optional Random so the Tests/ suite can seed it and
	assert distributions deterministically. Nothing here touches game state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)

type Rarity = SharedTypes.Rarity

local RarityModule = {}

-- Ascending. Index in this list is the comparable rank.
RarityModule.ORDER = table.freeze({
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
} :: { Rarity })

RarityModule.RANK = table.freeze({
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
})

-- Accent colors, consumed by every UI surface that renders a rarity.
RarityModule.COLORS = table.freeze({
	Common = Color3.fromRGB(154, 163, 178),
	Uncommon = Color3.fromRGB(86, 196, 118),
	Rare = Color3.fromRGB(74, 149, 245),
	Epic = Color3.fromRGB(168, 101, 242),
	Legendary = Color3.fromRGB(245, 166, 51),
	Mythic = Color3.fromRGB(240, 78, 116),
})

-- Seconds the reveal animation should hold before showing the result.
RarityModule.REVEAL_SECONDS = table.freeze({
	Common = 0.35,
	Uncommon = 0.5,
	Rare = 0.9,
	Epic = 1.4,
	Legendary = 2.1,
	Mythic = 3.0,
})

export type WeightedEntry = {
	id: string,
	weight: number,
	rarity: Rarity,
}

export type PityConfig = {
	threshold: number,
	minimumRarity: Rarity,
}

local defaultRandom = Random.new()

function RarityModule.rank(rarity: Rarity): number
	return RarityModule.RANK[rarity] or 0
end

-- True when `rarity` is at least as rare as `minimum`.
function RarityModule.atLeast(rarity: Rarity, minimum: Rarity): boolean
	return RarityModule.rank(rarity) >= RarityModule.rank(minimum)
end

function RarityModule.color(rarity: Rarity): Color3
	return RarityModule.COLORS[rarity] or RarityModule.COLORS.Common
end

--[[
	Weighted pick over entries. Non-positive weights are skipped entirely, so a
	caller can zero out an entry instead of rebuilding the table.
	Returns nil only when the list is empty or every weight is <= 0.
]]
function RarityModule.roll(entries: { WeightedEntry }, rng: Random?): WeightedEntry?
	local total = 0
	for _, entry in entries do
		if entry.weight > 0 then
			total += entry.weight
		end
	end

	if total <= 0 then
		return nil
	end

	local random = rng or defaultRandom
	local target = random:NextNumber() * total

	local cursor = 0
	for _, entry in entries do
		if entry.weight > 0 then
			cursor += entry.weight
			if target < cursor then
				return entry
			end
		end
	end

	-- Float accumulation can leave `target` a hair past `cursor`. Fall back to
	-- the last positive-weight entry rather than returning nil.
	for index = #entries, 1, -1 do
		if entries[index].weight > 0 then
			return entries[index]
		end
	end
	return nil
end

-- Same as roll(), for the { [id] = weight } shape configs tend to use.
function RarityModule.rollMap(map: { [string]: number }, rng: Random?): string?
	local entries: { WeightedEntry } = {}
	for id, weight in map do
		table.insert(entries, { id = id, weight = weight, rarity = "Common" })
	end

	-- Map iteration order is unspecified; sort so a seeded Random reproduces.
	table.sort(entries, function(a, b)
		return a.id < b.id
	end)

	local picked = RarityModule.roll(entries, rng)
	return if picked then picked.id else nil
end

--[[
	rollWithPity
	Returns (entry, nextPityCounter, pityFired).

	When the incoming counter has reached the threshold, the roll is restricted
	to entries at or above `minimumRarity` and the counter resets. Otherwise a
	normal roll happens, and the counter resets on its own if the result already
	met the minimum.

	The counter passed in is "rolls since the last qualifying result", so a
	threshold of 25 guarantees a qualifying result on the 25th roll at worst.
]]
function RarityModule.rollWithPity(
	entries: { WeightedEntry },
	pityCounter: number,
	config: PityConfig,
	rng: Random?
): (WeightedEntry?, number, boolean)
	local shouldForce = (pityCounter + 1) >= config.threshold

	if shouldForce then
		local qualifying: { WeightedEntry } = {}
		for _, entry in entries do
			if entry.weight > 0 and RarityModule.atLeast(entry.rarity, config.minimumRarity) then
				table.insert(qualifying, entry)
			end
		end

		local forced = RarityModule.roll(qualifying, rng)
		if forced then
			return forced, 0, true
		end
		-- No qualifying entry exists in this table at all. Fall through to a
		-- normal roll rather than returning nothing, and hold the counter so
		-- pity fires as soon as a qualifying entry becomes reachable.
	end

	local picked = RarityModule.roll(entries, rng)
	if not picked then
		return nil, pityCounter, false
	end

	if RarityModule.atLeast(picked.rarity, config.minimumRarity) then
		return picked, 0, false
	end

	return picked, pityCounter + 1, false
end

-- Normalizes weights to probabilities, for the Convert screen's odds table.
-- The doc requires showing these honestly, so this reads the same table the
-- roll uses rather than a hand-maintained display copy.
function RarityModule.odds(entries: { WeightedEntry }): { [string]: number }
	local total = 0
	for _, entry in entries do
		if entry.weight > 0 then
			total += entry.weight
		end
	end

	local out: { [string]: number } = {}
	if total <= 0 then
		return out
	end

	for _, entry in entries do
		if entry.weight > 0 then
			out[entry.id] = entry.weight / total
		end
	end
	return out
end

return RarityModule
