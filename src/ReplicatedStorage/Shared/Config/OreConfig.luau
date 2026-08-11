--!strict
--[[
	OreConfig
	20 ores across the six layers. `layers` maps layer index -> spawn weight, so
	an ore can straddle bands with different commonness in each.

	`convertsTo` lists the brainrots this ore biases toward in the Conversion
	Chamber. Those entries get their weight multiplied by
	GameConfig.ConversionOreBias; everything else still rolls at base weight, so
	no ore ever hard-locks an outcome. Every brainrot in BrainrotConfig is
	reachable from at least one ore -- the Tests/ suite asserts it.

	Layer 1 is deliberately Common-only: see GameConfig.OreFreeSurfaceRows.

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
		convertsTo = { "bobrito_bandito", "trulimero_trulicina" },
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
		convertsTo = { "boneca_ambalabu", "piccione_macchina" },
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
		convertsTo = { "trippi_troppi", "bananita_dolphinita" },
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
		convertsTo = { "bananita_dolphinita", "piccione_macchina" },
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
		convertsTo = { "glorbo_fruttodrillo", "frigo_camelo" },
	},
	{
		id = "bananini_pith",
		displayName = "Bananini Pith",
		rarity = "Uncommon",
		color = Color3.fromRGB(214, 194, 88),
		baseValue = 24,
		hardness = 2,
		weightPerUnit = 2,
		-- See rustcap_nodule: layer 1 carries filler rock only.
		layers = { [2] = 36, [3] = 10 },
		convertsTo = { "chimpanzini_bananini", "burbaloni_luliloli" },
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
		convertsTo = { "brr_brr_patapim", "burbaloni_luliloli" },
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
		convertsTo = { "frigo_camelo", "cappuccino_assassino" },
	},

	-- ================= Rare =================
	{
		id = "cappuccino_ore",
		displayName = "Cappuccino Shard",
		rarity = "Rare",
		color = Color3.fromRGB(84, 52, 38),
		baseValue = 62,
		hardness = 3,
		weightPerUnit = 2,
		layers = { [3] = 40, [4] = 25 },
		convertsTo = { "cappuccino_assassino", "ballerina_cappuccina" },
	},
	{
		id = "patapim_geode",
		displayName = "Patapim Geode",
		rarity = "Rare",
		color = Color3.fromRGB(122, 96, 190),
		baseValue = 70,
		hardness = 4,
		weightPerUnit = 2,
		layers = { [3] = 28, [4] = 34 },
		convertsTo = { "brr_brr_patapim", "lirili_larila" },
	},
	{
		id = "sahur_clinker",
		displayName = "Sahur Clinker",
		rarity = "Rare",
		color = Color3.fromRGB(196, 138, 92),
		baseValue = 78,
		hardness = 4,
		weightPerUnit = 2,
		layers = { [4] = 38, [5] = 16 },
		convertsTo = { "tung_tung_tung_sahur", "bombombini_gusini" },
	},
	{
		id = "cappuccina_quartz",
		displayName = "Cappuccina Quartz",
		rarity = "Rare",
		color = Color3.fromRGB(238, 132, 158),
		baseValue = 85,
		hardness = 4,
		weightPerUnit = 2,
		layers = { [4] = 30, [5] = 22 },
		convertsTo = { "ballerina_cappuccina", "tralalero_tralala" },
	},

	-- ================= Epic =================
	{
		id = "crocodilo_slag",
		displayName = "Crocodilo Slag",
		rarity = "Epic",
		color = Color3.fromRGB(206, 88, 62),
		baseValue = 205,
		hardness = 5,
		weightPerUnit = 3,
		layers = { [4] = 14, [5] = 34 },
		convertsTo = { "bombardiro_crocodilo", "girafa_celestre" },
	},
	{
		id = "tralala_prism",
		displayName = "Tralala Prism",
		rarity = "Epic",
		color = Color3.fromRGB(120, 206, 232),
		baseValue = 232,
		hardness = 5,
		weightPerUnit = 3,
		layers = { [5] = 26, [6] = 14 },
		convertsTo = { "tralalero_tralala", "orangutini_ananassini" },
	},
	{
		id = "watermelini_resin",
		displayName = "Watermelini Resin",
		rarity = "Epic",
		color = Color3.fromRGB(126, 208, 96),
		baseValue = 258,
		hardness = 6,
		weightPerUnit = 3,
		layers = { [5] = 20, [6] = 18 },
		convertsTo = { "tigrullini_watermelini", "orangutini_ananassini" },
	},

	-- ================= Legendary =================
	{
		id = "saturnita_core",
		displayName = "Saturnita Core",
		rarity = "Legendary",
		color = Color3.fromRGB(64, 118, 208),
		baseValue = 720,
		hardness = 6,
		weightPerUnit = 4,
		layers = { [5] = 8, [6] = 22 },
		convertsTo = { "la_vacca_saturno_saturnita", "chimpanzini_spiderini" },
	},
	{
		id = "spiderini_ember",
		displayName = "Spiderini Ember",
		rarity = "Legendary",
		color = Color3.fromRGB(248, 148, 40),
		baseValue = 830,
		hardness = 7,
		weightPerUnit = 4,
		layers = { [6] = 18 },
		convertsTo = { "chimpanzini_spiderini", "cocofanto_elefanto" },
	},
	{
		id = "elefanto_arcglass",
		displayName = "Elefanto Arcglass",
		rarity = "Legendary",
		color = Color3.fromRGB(232, 228, 128),
		baseValue = 940,
		hardness = 7,
		weightPerUnit = 4,
		layers = { [6] = 14 },
		convertsTo = { "cocofanto_elefanto", "la_vacca_saturno_saturnita" },
	},

	-- ================= Mythic =================
	-- Gated behind rebirths, per the doc's "rebirth unlocks exclusive ore tiers".
	{
		id = "medussi_voidpearl",
		displayName = "Medussi Voidpearl",
		rarity = "Mythic",
		color = Color3.fromRGB(42, 32, 78),
		baseValue = 2850,
		hardness = 8,
		weightPerUnit = 4,
		layers = { [6] = 6 },
		convertsTo = { "graipuss_medussi", "garama_madundung" },
		minRebirths = 3,
	},
	{
		id = "garama_paradox",
		displayName = "Garama Paradox",
		rarity = "Mythic",
		color = Color3.fromRGB(236, 240, 252),
		baseValue = 3400,
		hardness = 8,
		weightPerUnit = 4,
		layers = { [6] = 4 },
		convertsTo = { "garama_madundung", "graipuss_medussi" },
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
