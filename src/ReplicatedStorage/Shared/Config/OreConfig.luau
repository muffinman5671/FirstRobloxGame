--!strict
--[[
	OreConfig
	20 ores across the six layers. `layers` maps layer index -> spawn weight, so
	an ore can straddle bands with different commonness in each.

	`convertsTo` lists the brainrots this ore biases toward in the Conversion
	Chamber. Those entries get their weight multiplied by
	GameConfig.ConversionOreBias; everything else still rolls at base weight, so
	no ore ever hard-locks an outcome.

	Adding an ore: append an entry here and give it at least one layer weight.
	Nothing else needs editing -- MineService builds its per-layer tables from
	this file at boot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)

type OreDef = SharedTypes.OreDef

local OreConfig = {}

OreConfig.ORES = table.freeze({
	-- ================= Common =================
	{
		id = "loam_clod",
		displayName = "Loam Clod",
		rarity = "Common",
		color = Color3.fromRGB(126, 100, 72),
		baseValue = 5,
		hardness = 1,
		weightPerUnit = 1,
		layers = { [1] = 100 },
		convertsTo = { "pastuccio_rattoni", "grissino_talpini" },
	},
	{
		id = "pebble_grit",
		displayName = "Pebble Grit",
		rarity = "Common",
		color = Color3.fromRGB(148, 148, 142),
		baseValue = 7,
		hardness = 1,
		weightPerUnit = 1,
		layers = { [1] = 70, [2] = 45 },
		convertsTo = { "ciabatta_piccioni", "tostapane_bruchini" },
	},
	{
		id = "slate_marrow",
		displayName = "Slate Marrow",
		rarity = "Common",
		color = Color3.fromRGB(96, 102, 110),
		baseValue = 9,
		hardness = 2,
		weightPerUnit = 1,
		layers = { [2] = 80, [3] = 30 },
		convertsTo = { "zuppetta_lumacone", "fungetto_rospino" },
	},
	{
		id = "cinder_flake",
		displayName = "Cinder Flake",
		rarity = "Common",
		color = Color3.fromRGB(72, 66, 64),
		baseValue = 12,
		hardness = 2,
		weightPerUnit = 1,
		layers = { [2] = 55, [3] = 40 },
		convertsTo = { "fungetto_rospino", "tostapane_bruchini" },
	},

	-- ================= Uncommon =================
	{
		id = "rustcap_nodule",
		displayName = "Rustcap Nodule",
		rarity = "Uncommon",
		color = Color3.fromRGB(168, 96, 54),
		baseValue = 20,
		hardness = 2,
		weightPerUnit = 1,
		-- Topsoil is deliberately ore-free: no Uncommon-or-better ore spawns
		-- in layer 1, so the surface reads as plain ground and real veins are
		-- something you dig down to find.
		layers = { [2] = 48, [3] = 12 },
		convertsTo = { "cornetto_volpini", "salamino_furettoni" },
	},
	{
		id = "bananutto_pith",
		displayName = "Bananutto Pith",
		rarity = "Uncommon",
		color = Color3.fromRGB(214, 194, 88),
		baseValue = 24,
		hardness = 2,
		weightPerUnit = 2,
		-- See rustcap_nodule: layer 1 carries filler rock only.
		layers = { [2] = 36, [3] = 10 },
		convertsTo = { "bananutto_gorilloni", "pomodrone_ricci" },
	},
	{
		id = "copperbloom_sprig",
		displayName = "Copperbloom Sprig",
		rarity = "Uncommon",
		color = Color3.fromRGB(96, 178, 150),
		baseValue = 28,
		hardness = 3,
		weightPerUnit = 1,
		layers = { [2] = 24, [3] = 52 },
		convertsTo = { "sardinella_gattoni", "biscottino_armadillo" },
	},
	{
		id = "sootglass_bead",
		displayName = "Sootglass Bead",
		rarity = "Uncommon",
		color = Color3.fromRGB(58, 60, 78),
		baseValue = 33,
		hardness = 3,
		weightPerUnit = 2,
		layers = { [3] = 44, [4] = 18 },
		convertsTo = { "salamino_furettoni", "biscottino_armadillo" },
	},

	-- ================= Rare =================
	{
		id = "espressone_ore",
		displayName = "Espressone Shard",
		rarity = "Rare",
		color = Color3.fromRGB(84, 52, 38),
		baseValue = 62,
		hardness = 3,
		weightPerUnit = 2,
		layers = { [3] = 40, [4] = 25 },
		convertsTo = { "espressone_squalino", "calzone_pipistrello" },
	},
	{
		id = "gattone_geode",
		displayName = "Gattone Geode",
		rarity = "Rare",
		color = Color3.fromRGB(122, 96, 190),
		baseValue = 70,
		hardness = 4,
		weightPerUnit = 2,
		layers = { [3] = 28, [4] = 34 },
		convertsTo = { "focaccia_cinghiale", "limoncello_fenicotti" },
	},
	{
		id = "calzone_clinker",
		displayName = "Calzone Clinker",
		rarity = "Rare",
		color = Color3.fromRGB(196, 138, 92),
		baseValue = 78,
		hardness = 4,
		weightPerUnit = 2,
		layers = { [4] = 38, [5] = 16 },
		convertsTo = { "calzone_pipistrello", "missilino_alligatore" },
	},
	{
		id = "fenicotti_quartz",
		displayName = "Fenicotti Quartz",
		rarity = "Rare",
		color = Color3.fromRGB(238, 132, 158),
		baseValue = 85,
		hardness = 4,
		weightPerUnit = 2,
		layers = { [4] = 30, [5] = 22 },
		convertsTo = { "limoncello_fenicotti", "espressone_squalino" },
	},

	-- ================= Epic =================
	{
		id = "missilino_slag",
		displayName = "Missilino Slag",
		rarity = "Epic",
		color = Color3.fromRGB(206, 88, 62),
		baseValue = 205,
		hardness = 5,
		weightPerUnit = 3,
		layers = { [4] = 14, [5] = 34 },
		convertsTo = { "missilino_alligatore", "vulcanetto_rinoceronte" },
	},
	{
		id = "aquilotto_prism",
		displayName = "Aquilotto Prism",
		rarity = "Epic",
		color = Color3.fromRGB(120, 206, 232),
		baseValue = 232,
		hardness = 5,
		weightPerUnit = 3,
		layers = { [5] = 26, [6] = 14 },
		convertsTo = { "turbinello_aquilotto", "ombrellone_mantide" },
	},
	{
		id = "mantide_resin",
		displayName = "Mantide Resin",
		rarity = "Epic",
		color = Color3.fromRGB(126, 208, 96),
		baseValue = 258,
		hardness = 6,
		weightPerUnit = 3,
		layers = { [5] = 20, [6] = 18 },
		convertsTo = { "ombrellone_mantide", "marmellata_ippopotamo" },
	},

	-- ================= Legendary =================
	{
		id = "balenotto_core",
		displayName = "Balenotto Core",
		rarity = "Legendary",
		color = Color3.fromRGB(64, 118, 208),
		baseValue = 720,
		hardness = 6,
		weightPerUnit = 4,
		layers = { [5] = 8, [6] = 22 },
		convertsTo = { "cattedrale_balenotto", "meteorito_scorpione" },
	},
	{
		id = "scorpione_ember",
		displayName = "Scorpione Ember",
		rarity = "Legendary",
		color = Color3.fromRGB(248, 148, 40),
		baseValue = 830,
		hardness = 7,
		weightPerUnit = 4,
		layers = { [6] = 18 },
		convertsTo = { "meteorito_scorpione", "fulminaccio_condorini" },
	},
	{
		id = "condorini_arcglass",
		displayName = "Condorini Arcglass",
		rarity = "Legendary",
		color = Color3.fromRGB(232, 228, 128),
		baseValue = 940,
		hardness = 7,
		weightPerUnit = 4,
		layers = { [6] = 14 },
		convertsTo = { "fulminaccio_condorini", "cattedrale_balenotto" },
	},

	-- ================= Mythic =================
	-- Gated behind rebirths, per the doc's "rebirth unlocks exclusive ore tiers".
	{
		id = "krakenetto_voidpearl",
		displayName = "Krakenetto Voidpearl",
		rarity = "Mythic",
		color = Color3.fromRGB(42, 32, 78),
		baseValue = 2850,
		hardness = 8,
		weightPerUnit = 4,
		layers = { [6] = 6 },
		convertsTo = { "nebulosa_krakenetto", "paradosso_sfingelli" },
		minRebirths = 3,
	},
	{
		id = "sfingelli_paradox",
		displayName = "Sfingelli Paradox",
		rarity = "Mythic",
		color = Color3.fromRGB(236, 240, 252),
		baseValue = 3400,
		hardness = 8,
		weightPerUnit = 4,
		layers = { [6] = 4 },
		convertsTo = { "paradosso_sfingelli", "nebulosa_krakenetto" },
		minRebirths = 3,
	},
} :: { OreDef })

local byId: { [string]: OreDef } = {}
for _, ore in OreConfig.ORES do
	assert(byId[ore.id] == nil, `OreConfig: duplicate ore id "{ore.id}"`)
	byId[ore.id] = ore
end

OreConfig.COUNT = #OreConfig.ORES

function OreConfig.get(id: string): OreDef?
	return byId[id]
end

function OreConfig.exists(id: string): boolean
	return byId[id] ~= nil
end

--[[
	Spawn table for a layer, as weighted entries ready for Rarity.roll.
	`rebirths` filters out ore tiers the player hasn't earned yet -- passing 0
	gives the table a fresh account sees.
]]
function OreConfig.spawnTableForLayer(layerIndex: number, rebirths: number): { { id: string, weight: number, rarity: string } }
	local entries = {}
	for _, ore in OreConfig.ORES do
		local weight = ore.layers[layerIndex]
		if weight and weight > 0 then
			if not ore.minRebirths or rebirths >= ore.minRebirths then
				table.insert(entries, { id = ore.id, weight = weight, rarity = ore.rarity })
			end
		end
	end

	-- Stable order so a seeded Random reproduces in tests.
	table.sort(entries, function(a, b)
		return a.id < b.id
	end)
	return entries
end

-- Every ore that can appear in a layer, ignoring rebirth gates. Used by the
-- Index and the layer preview cards.
function OreConfig.oresInLayer(layerIndex: number): { OreDef }
	local out: { OreDef } = {}
	for _, ore in OreConfig.ORES do
		if ore.layers[layerIndex] then
			table.insert(out, ore)
		end
	end
	return out
end

return table.freeze(OreConfig)
