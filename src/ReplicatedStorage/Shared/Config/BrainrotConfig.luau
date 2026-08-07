--!strict
--[[
	BrainrotConfig
	26 original brainrot characters across the six rarities.

	All names, silhouettes, and builders here are invented for this project in a
	generic surreal animal/object-mashup style. Nothing references an existing
	meme character, real brand, or third-party asset, and no asset IDs appear
	anywhere in this file -- ModelFactory builds every character from
	Instance.new primitives. Art passes are marked `-- ART TODO` at the builder.

	Income scales ~3.4x per rarity step, which is GameConfig.IncomeGrowth (1.8)
	applied across roughly two upgrade tiers per rarity band.

	Adding a brainrot: append an entry here, point at least one ore's
	`convertsTo` at its id, and add the matching builder to ModelFactory.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)

type BrainrotDef = SharedTypes.BrainrotDef

local BrainrotConfig = {}

-- Income multiplier per mutation tier. Shared by every character; a character
-- can override with its own table to opt out of a tier (set it to nil).
BrainrotConfig.MUTATIONS = table.freeze({
	Normal = 1.0,
	Golden = 2.5,
	Diamond = 6.0,
	Glitched = 15.0,
})

BrainrotConfig.MUTATION_ORDER = table.freeze({ "Normal", "Golden", "Diamond", "Glitched" })

-- Visual treatment per mutation, applied by ModelFactory and EffectsController.
BrainrotConfig.MUTATION_STYLE = table.freeze({
	Normal = { tint = Color3.fromRGB(255, 255, 255), sparkle = false, chromatic = false },
	Golden = { tint = Color3.fromRGB(255, 208, 92), sparkle = false, chromatic = false },
	Diamond = { tint = Color3.fromRGB(168, 236, 255), sparkle = true, chromatic = false },
	Glitched = { tint = Color3.fromRGB(196, 92, 255), sparkle = true, chromatic = true },
})

local M = BrainrotConfig.MUTATIONS

BrainrotConfig.BRAINROTS = table.freeze({
	-- ================= Common =================
	{
		id = "pastuccio_rattoni",
		displayName = "Pastuccio Rattoni",
		rarity = "Common",
		incomePerSecond = 2,
		sellValue = 156,
		mutations = M,
		modelBuilder = "buildPastuccioRattoni",
	},
	{
		id = "ciabatta_piccioni",
		displayName = "Ciabatta Piccioni",
		rarity = "Common",
		incomePerSecond = 2.2,
		sellValue = 172,
		mutations = M,
		modelBuilder = "buildCiabattaPiccioni",
	},
	{
		id = "zuppetta_lumacone",
		displayName = "Zuppetta Lumacone",
		rarity = "Common",
		incomePerSecond = 2.5,
		sellValue = 195,
		mutations = M,
		modelBuilder = "buildZuppettaLumacone",
	},
	{
		id = "grissino_talpini",
		displayName = "Grissino Talpini",
		rarity = "Common",
		incomePerSecond = 2.8,
		sellValue = 218,
		mutations = M,
		modelBuilder = "buildGrissinoTalpini",
	},
	{
		id = "fungetto_rospino",
		displayName = "Fungetto Rospino",
		rarity = "Common",
		incomePerSecond = 3.1,
		sellValue = 242,
		mutations = M,
		modelBuilder = "buildFungettoRospino",
	},
	{
		id = "tostapane_bruchini",
		displayName = "Tostapane Bruchini",
		rarity = "Common",
		incomePerSecond = 3.4,
		sellValue = 265,
		mutations = M,
		modelBuilder = "buildTostapaneBruchini",
	},

	-- ================= Uncommon =================
	{
		id = "bananutto_gorilloni",
		displayName = "Bananutto Gorilloni",
		rarity = "Uncommon",
		incomePerSecond = 6.5,
		sellValue = 507,
		mutations = M,
		modelBuilder = "buildBananuttoGorilloni",
	},
	{
		id = "cornetto_volpini",
		displayName = "Cornetto Volpini",
		rarity = "Uncommon",
		incomePerSecond = 7,
		sellValue = 546,
		mutations = M,
		modelBuilder = "buildCornettoVolpini",
	},
	{
		id = "sardinella_gattoni",
		displayName = "Sardinella Gattoni",
		rarity = "Uncommon",
		incomePerSecond = 7.8,
		sellValue = 608,
		mutations = M,
		modelBuilder = "buildSardinellaGattoni",
	},
	{
		id = "pomodrone_ricci",
		displayName = "Pomodrone Ricci",
		rarity = "Uncommon",
		incomePerSecond = 8.5,
		sellValue = 663,
		mutations = M,
		modelBuilder = "buildPomodroneRicci",
	},
	{
		id = "biscottino_armadillo",
		displayName = "Biscottino Armadillo",
		rarity = "Uncommon",
		incomePerSecond = 9.2,
		sellValue = 718,
		mutations = M,
		modelBuilder = "buildBiscottinoArmadillo",
	},
	{
		id = "salamino_furettoni",
		displayName = "Salamino Furettoni",
		rarity = "Uncommon",
		incomePerSecond = 10,
		sellValue = 780,
		mutations = M,
		modelBuilder = "buildSalaminoFurettoni",
	},

	-- ================= Rare =================
	{
		id = "espressone_squalino",
		displayName = "Espressone Squalino",
		rarity = "Rare",
		incomePerSecond = 22,
		sellValue = 1716,
		mutations = M,
		modelBuilder = "buildEspressoneSqualino",
	},
	{
		id = "missilino_alligatore",
		displayName = "Missilino Alligatore",
		rarity = "Rare",
		incomePerSecond = 24,
		sellValue = 1872,
		mutations = M,
		modelBuilder = "buildMissilinoAlligatore",
	},
	{
		id = "calzone_pipistrello",
		displayName = "Calzone Pipistrello",
		rarity = "Rare",
		incomePerSecond = 26,
		sellValue = 2028,
		mutations = M,
		modelBuilder = "buildCalzonePipistrello",
	},
	{
		id = "limoncello_fenicotti",
		displayName = "Limoncello Fenicotti",
		rarity = "Rare",
		incomePerSecond = 29,
		sellValue = 2262,
		mutations = M,
		modelBuilder = "buildLimoncelloFenicotti",
	},
	{
		id = "focaccia_cinghiale",
		displayName = "Focaccia Cinghiale",
		rarity = "Rare",
		incomePerSecond = 32,
		sellValue = 2496,
		mutations = M,
		modelBuilder = "buildFocacciaCinghiale",
	},

	-- ================= Epic =================
	{
		id = "vulcanetto_rinoceronte",
		displayName = "Vulcanetto Rinoceronte",
		rarity = "Epic",
		incomePerSecond = 76,
		sellValue = 5928,
		mutations = M,
		modelBuilder = "buildVulcanettoRinoceronte",
	},
	{
		id = "ombrellone_mantide",
		displayName = "Ombrellone Mantide",
		rarity = "Epic",
		incomePerSecond = 84,
		sellValue = 6552,
		mutations = M,
		modelBuilder = "buildOmbrelloneMantide",
	},
	{
		id = "turbinello_aquilotto",
		displayName = "Turbinello Aquilotto",
		rarity = "Epic",
		incomePerSecond = 92,
		sellValue = 7176,
		mutations = M,
		modelBuilder = "buildTurbinelloAquilotto",
	},
	{
		id = "marmellata_ippopotamo",
		displayName = "Marmellata Ippopotamo",
		rarity = "Epic",
		incomePerSecond = 100,
		sellValue = 7800,
		mutations = M,
		modelBuilder = "buildMarmellataIppopotamo",
	},

	-- ================= Legendary =================
	{
		id = "cattedrale_balenotto",
		displayName = "Cattedrale Balenotto",
		rarity = "Legendary",
		incomePerSecond = 260,
		sellValue = 20280,
		mutations = M,
		modelBuilder = "buildCattedraleBalenotto",
	},
	{
		id = "meteorito_scorpione",
		displayName = "Meteorito Scorpione",
		rarity = "Legendary",
		incomePerSecond = 290,
		sellValue = 22620,
		mutations = M,
		modelBuilder = "buildMeteoritoScorpione",
	},
	{
		id = "fulminaccio_condorini",
		displayName = "Fulminaccio Condorini",
		rarity = "Legendary",
		incomePerSecond = 320,
		sellValue = 24960,
		mutations = M,
		modelBuilder = "buildFulminaccioCondorini",
	},

	-- ================= Mythic =================
	{
		id = "nebulosa_krakenetto",
		displayName = "Nebulosa Krakenetto",
		rarity = "Mythic",
		incomePerSecond = 900,
		sellValue = 70200,
		mutations = M,
		modelBuilder = "buildNebulosaKrakenetto",
	},
	{
		id = "paradosso_sfingelli",
		displayName = "Paradosso Sfingelli",
		rarity = "Mythic",
		incomePerSecond = 1050,
		sellValue = 81900,
		mutations = M,
		modelBuilder = "buildParadossoSfingelli",
	},
} :: { BrainrotDef })

local byId: { [string]: BrainrotDef } = {}
for _, brainrot in BrainrotConfig.BRAINROTS do
	assert(byId[brainrot.id] == nil, `BrainrotConfig: duplicate id "{brainrot.id}"`)
	byId[brainrot.id] = brainrot
end

BrainrotConfig.COUNT = #BrainrotConfig.BRAINROTS

function BrainrotConfig.get(id: string): BrainrotDef?
	return byId[id]
end

function BrainrotConfig.exists(id: string): boolean
	return byId[id] ~= nil
end

function BrainrotConfig.mutationMultiplier(brainrotId: string, mutation: string): number
	local def = byId[brainrotId]
	if not def then
		return 0
	end
	return def.mutations[mutation] or 0
end

-- Income for one placed brainrot, before the rebirth multiplier.
function BrainrotConfig.incomeFor(brainrotId: string, mutation: string): number
	local def = byId[brainrotId]
	if not def then
		return 0
	end
	return def.incomePerSecond * (def.mutations[mutation] or 0)
end

function BrainrotConfig.sellValueFor(brainrotId: string, mutation: string): number
	local def = byId[brainrotId]
	if not def then
		return 0
	end
	return math.floor(def.sellValue * (def.mutations[mutation] or 0))
end

function BrainrotConfig.ofRarity(rarity: string): { BrainrotDef }
	local out: { BrainrotDef } = {}
	for _, brainrot in BrainrotConfig.BRAINROTS do
		if brainrot.rarity == rarity then
			table.insert(out, brainrot)
		end
	end
	return out
end

return table.freeze(BrainrotConfig)
