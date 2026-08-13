--!strict
--[[
	BrainrotConfig
	26 brainrot characters across the six rarities.

	These use the established "Italian brainrot" meme names that circulate
	widely online. No artwork, mesh, or asset ID from any other experience is
	used or referenced: ModelFactory builds every character from Instance.new
	primitives, and each builder is marked `-- ART TODO` for its art pass. See
	DESIGN.md §2 for the IP position.

	Income scales ~3.4x per rarity step, which is GameConfig.IncomeGrowth (1.8)
	applied across roughly two upgrade tiers per rarity band. The numbers here
	are unchanged from the previous roster, so the balance pass still holds.

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

--[[
	Visual treatment per mutation, applied by ModelFactory and EffectsController.

	`material` overrides the character's own so a tier is readable from across
	the plot rather than only up close. Deliberately avoids Neon and Glass, per
	the art direction: Metal and Ice still read as flat blocks at a distance.

	`chromatic` shifts each part's hue by a different amount, which is what
	makes Glitched look wrong on purpose rather than merely purple.
]]
BrainrotConfig.MUTATION_STYLE = table.freeze({
	Normal = {
		tint = Color3.fromRGB(255, 255, 255),
		blend = 0,
		material = nil,
		sparkle = false,
		chromatic = false,
	},
	Golden = {
		tint = Color3.fromRGB(255, 198, 64),
		blend = 0.78,
		material = Enum.Material.Metal,
		sparkle = false,
		chromatic = false,
	},
	Diamond = {
		tint = Color3.fromRGB(176, 240, 255),
		blend = 0.72,
		material = Enum.Material.Ice,
		sparkle = true,
		chromatic = false,
	},
	Glitched = {
		tint = Color3.fromRGB(206, 84, 255),
		blend = 0.55,
		material = Enum.Material.Foil,
		sparkle = true,
		chromatic = true,
	},
})

local M = BrainrotConfig.MUTATIONS

BrainrotConfig.BRAINROTS = table.freeze({
	-- ================= Common =================
	{
		id = "bobrito_bandito",
		displayName = "Bobrito Bandito",
		rarity = "Common",
		incomePerSecond = 2,
		sellValue = 156,
		mutations = M,
		modelBuilder = "buildBobritoBandito",
	},
	{
		id = "boneca_ambalabu",
		displayName = "Boneca Ambalabu",
		rarity = "Common",
		incomePerSecond = 2.2,
		sellValue = 172,
		mutations = M,
		modelBuilder = "buildBonecaAmbalabu",
	},
	{
		id = "trippi_troppi",
		displayName = "Trippi Troppi",
		rarity = "Common",
		incomePerSecond = 2.5,
		sellValue = 195,
		mutations = M,
		modelBuilder = "buildTrippiTroppi",
	},
	{
		id = "trulimero_trulicina",
		displayName = "Trulimero Trulicina",
		rarity = "Common",
		incomePerSecond = 2.8,
		sellValue = 218,
		mutations = M,
		modelBuilder = "buildTrulimeroTrulicina",
	},
	{
		id = "bananita_dolphinita",
		displayName = "Bananita Dolphinita",
		rarity = "Common",
		incomePerSecond = 3.1,
		sellValue = 242,
		mutations = M,
		modelBuilder = "buildBananitaDolphinita",
	},
	{
		id = "piccione_macchina",
		displayName = "Piccione Macchina",
		rarity = "Common",
		incomePerSecond = 3.4,
		sellValue = 265,
		mutations = M,
		modelBuilder = "buildPiccioneMacchina",
	},

	-- ================= Uncommon =================
	{
		id = "brr_brr_patapim",
		displayName = "Brr Brr Patapim",
		rarity = "Uncommon",
		incomePerSecond = 6.5,
		sellValue = 507,
		mutations = M,
		modelBuilder = "buildBrrBrrPatapim",
	},
	{
		id = "chimpanzini_bananini",
		displayName = "Chimpanzini Bananini",
		rarity = "Uncommon",
		incomePerSecond = 7,
		sellValue = 546,
		mutations = M,
		modelBuilder = "buildChimpanziniBananini",
	},
	{
		id = "cappuccino_assassino",
		displayName = "Cappuccino Assassino",
		rarity = "Uncommon",
		incomePerSecond = 7.8,
		sellValue = 608,
		mutations = M,
		modelBuilder = "buildCappuccinoAssassino",
	},
	{
		id = "burbaloni_luliloli",
		displayName = "Burbaloni Luliloli",
		rarity = "Uncommon",
		incomePerSecond = 8.5,
		sellValue = 663,
		mutations = M,
		modelBuilder = "buildBurbaloniLuliloli",
	},
	{
		id = "glorbo_fruttodrillo",
		displayName = "Glorbo Fruttodrillo",
		rarity = "Uncommon",
		incomePerSecond = 9.2,
		sellValue = 718,
		mutations = M,
		modelBuilder = "buildGlorboFruttodrillo",
	},
	{
		id = "frigo_camelo",
		displayName = "Frigo Camelo",
		rarity = "Uncommon",
		incomePerSecond = 10,
		sellValue = 780,
		mutations = M,
		modelBuilder = "buildFrigoCamelo",
	},

	-- ================= Rare =================
	{
		id = "tralalero_tralala",
		displayName = "Tralalero Tralala",
		rarity = "Rare",
		incomePerSecond = 22,
		sellValue = 1716,
		mutations = M,
		modelBuilder = "buildTralaleroTralala",
	},
	{
		id = "tung_tung_tung_sahur",
		displayName = "Tung Tung Tung Sahur",
		rarity = "Rare",
		incomePerSecond = 24,
		sellValue = 1872,
		mutations = M,
		modelBuilder = "buildTungTungTungSahur",
	},
	{
		id = "ballerina_cappuccina",
		displayName = "Ballerina Cappuccina",
		rarity = "Rare",
		incomePerSecond = 26,
		sellValue = 2028,
		mutations = M,
		modelBuilder = "buildBallerinaCappuccina",
	},
	{
		id = "lirili_larila",
		displayName = "Lirilì Larilà",
		rarity = "Rare",
		incomePerSecond = 29,
		sellValue = 2262,
		mutations = M,
		modelBuilder = "buildLiriliLarila",
	},
	{
		id = "bombombini_gusini",
		displayName = "Bombombini Gusini",
		rarity = "Rare",
		incomePerSecond = 32,
		sellValue = 2496,
		mutations = M,
		modelBuilder = "buildBombombiniGusini",
	},

	-- ================= Epic =================
	{
		id = "bombardiro_crocodilo",
		displayName = "Bombardiro Crocodilo",
		rarity = "Epic",
		incomePerSecond = 76,
		sellValue = 5928,
		mutations = M,
		modelBuilder = "buildBombardiroCrocodilo",
	},
	{
		id = "orangutini_ananassini",
		displayName = "Orangutini Ananassini",
		rarity = "Epic",
		incomePerSecond = 84,
		sellValue = 6552,
		mutations = M,
		modelBuilder = "buildOrangutiniAnanassini",
	},
	{
		id = "tigrullini_watermelini",
		displayName = "Tigrullini Watermelini",
		rarity = "Epic",
		incomePerSecond = 92,
		sellValue = 7176,
		mutations = M,
		modelBuilder = "buildTigrulliniWatermelini",
	},
	{
		id = "girafa_celestre",
		displayName = "Girafa Celestre",
		rarity = "Epic",
		incomePerSecond = 100,
		sellValue = 7800,
		mutations = M,
		modelBuilder = "buildGirafaCelestre",
	},

	-- ================= Legendary =================
	{
		id = "la_vacca_saturno_saturnita",
		displayName = "La Vacca Saturno Saturnita",
		rarity = "Legendary",
		incomePerSecond = 260,
		sellValue = 20280,
		mutations = M,
		modelBuilder = "buildLaVaccaSaturnoSaturnita",
	},
	{
		id = "chimpanzini_spiderini",
		displayName = "Chimpanzini Spiderini",
		rarity = "Legendary",
		incomePerSecond = 290,
		sellValue = 22620,
		mutations = M,
		modelBuilder = "buildChimpanziniSpiderini",
	},
	{
		id = "cocofanto_elefanto",
		displayName = "Cocofanto Elefanto",
		rarity = "Legendary",
		incomePerSecond = 320,
		sellValue = 24960,
		mutations = M,
		modelBuilder = "buildCocofantoElefanto",
	},

	-- ================= Mythic =================
	{
		id = "graipuss_medussi",
		displayName = "Graipuss Medussi",
		rarity = "Mythic",
		incomePerSecond = 900,
		sellValue = 70200,
		mutations = M,
		modelBuilder = "buildGraipussMedussi",
	},
	{
		id = "garama_madundung",
		displayName = "Garama and Madundung",
		rarity = "Mythic",
		incomePerSecond = 1050,
		sellValue = 81900,
		mutations = M,
		modelBuilder = "buildGaramaMadundung",
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
