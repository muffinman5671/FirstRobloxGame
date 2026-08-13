--!strict
--[[
	GameConfig
	Every tunable that isn't a per-entity definition lives here. System code must
	never hardcode a number that appears in this file.

	The curve constants at the bottom drive ToolConfig's generated tiers, so
	changing one value rebalances the whole progression consistently.
]]

local GameConfig = {}

-- ==========================================================================
-- Mine geometry
-- ==========================================================================

-- Edge length of a single mine block, in studs. Blocks are Parts, never Terrain.
-- Changing this rescales the entire shaft; 4 keeps block count sane at depth.
GameConfig.BlockSize = 4

-- Blocks per chunk axis. 4 -> chunks of 4x4x4 blocks = 16x16x16 studs = 64 parts.
-- Larger chunks mean fewer streaming decisions but chunkier hitches on load.
GameConfig.ChunkBlocks = 4

-- Half-width of the shaft in blocks. 6 -> a 13-block-wide square shaft (~52 studs).
-- Widen for more players mining side by side; costs parts linearly per layer.
GameConfig.ShaftRadiusBlocks = 6

-- World Y of the mine ceiling. Depth is measured downward from here, so a block
-- at Y = -120 sits at depth 120.
GameConfig.SurfaceY = 0

-- World XZ the shaft is centred on. Offset from the origin so the hub floor
-- (and the place's stock SpawnLocation at 0,0,0) sits on solid ground rather
-- than over the shaft opening.
GameConfig.ShaftCenterX = 0
GameConfig.ShaftCenterZ = 80

-- Hub platform built by MineService. Its top surface is SurfaceY, with a square
-- opening cut out over the shaft.
GameConfig.HubExtent = 256 -- half-width, studs
GameConfig.HubThickness = 20

-- Blocks materialized per streaming tick. Caps the cost of a single pass so a
-- player teleporting to a fresh depth spreads the work over a few frames
-- instead of hitching.
GameConfig.MaxBlocksPerStreamTick = 220

--[[
	Ground safety.

	The budget above means a fast-moving player can outrun materialization and
	fall through a floor that hasn't spawned yet. Blocks within SafeLoadRadius
	of a player are therefore loaded *before* the budgeted pass and ignore the
	budget entirely -- the floor under your feet is never the thing that gets
	deferred.

	SafeLoadRadius must comfortably exceed how far a player travels in one
	ChunkStreamTickSeconds (walkspeed 16 -> 8 studs, plus fall speed).
]]
GameConfig.SafeLoadRadius = 40

-- A player below the mine floor by this much has fallen out of the world and
-- gets returned to the hub. Generous enough that legitimately standing on the
-- deepest block never trips it.
GameConfig.VoidCatchMargin = 60

-- Checked every this many seconds. Fast enough to catch a fall before it feels
-- like a death, cheap enough to ignore.
GameConfig.VoidCatchTickSeconds = 0.5

-- Crack stages rendered on a damaged block, excluding "undamaged". The server
-- writes the current stage to a part attribute for the client to read; it is
-- display only and is never read back as authoritative state.
GameConfig.CrackStages = 4

-- ==========================================================================
-- Art direction: brutalist / pixelated
-- ==========================================================================
--[[
	The look is flat matte mass with a deliberately small colour palette --
	heavy, blocky, poster-like, no gloss and no gradients. See "Art Direction"
	in DESIGN.md; these constants are the mine's half of it.

	Rather than give every block its layer's exact colour, each one picks a
	discrete shade from a tiny per-layer ramp. A wall then reads as quantized
	pixel noise instead of one flat slab, without any textures or asset IDs.
]]

-- Steps in each layer's ramp. Small on purpose: more shades read as a smooth
-- gradient, which is the opposite of the intent. 3-5 is the usable range.
GameConfig.PaletteShades = 4

-- How far the lightest and darkest steps sit from the layer's base colour.
-- Above ~0.2 the ramp starts to look like lighting rather than palette.
GameConfig.PaletteShadeRange = 0.14

-- Extra darkening per crack stage, so damage is visible on the block itself
-- rather than only in the HUD.
GameConfig.CrackDarkenPerStage = 0.11

--[[
	Pixel tiles.

	A block painted one flat colour still reads as one flat colour no matter how
	good the material is. So each block gets a couple of small raised tiles on
	its *exposed* faces, in a different step of the same ramp -- literal pixels,
	built from geometry rather than from a texture (DESIGN.md §2a: "sub-block
	detail is built from more blocks, not from texture").

	Only exposed faces are tiled, so a buried block costs nothing and the extra
	part count is roughly one to two per visible block.
]]

-- Tiles per block. 0 disables the effect entirely.
GameConfig.PixelTilesPerBlock = 2

-- Cells per face axis. 3 gives a 3x3 grid of possible tile positions, so a tile
-- is a third of a face -- chunky enough to read as a pixel, not as noise.
GameConfig.PixelTileGrid = 3

-- How far a tile stands proud of the face, in studs. Just enough to avoid
-- z-fighting and catch a different shade of light.
GameConfig.PixelTileRelief = 0.06

-- How many ramp steps away a tile's shade sits from its block's. 1 keeps the
-- block reading as one material; larger values look like damage.
GameConfig.PixelTileShadeOffset = 1

--[[
	Cartoon colour treatment.

	Roblox's materials are lit and shaded for realism, which drags every surface
	toward grey. Pushing saturation and value up before the palette is applied
	pulls it back toward flat illustrated colour -- the single biggest lever on
	whether the mine reads as cartoony or as a photo of some rocks.

	Applied to layer colours and ore colours alike, so ore veins stay vivid.
]]
GameConfig.CartoonSaturation = 1.45
GameConfig.CartoonValueBoost = 1.12

-- Floor on value, so the darkest layers still read as coloured rather than
-- collapsing to black under the palette's darker steps.
GameConfig.CartoonMinValue = 0.22

--[[
	Grass only caps blocks in the top rows. Without this, digging down turns
	every newly exposed block into a grass block, and you end up with lawn
	forty studs underground.

	Row index, not studs: row 0 is the surface row whose top face sits at
	SurfaceY. Set to -1 to disable grass caps entirely.
]]
GameConfig.GrassMaxRow = 0

--[[
	Ore is suppressed in the topmost rows of the shaft so the grass surface
	reads as clean ground rather than a speckled mess, and so the first thing a
	player sees is a recognisable landscape. Below this depth ore generates
	normally.

	Rows, not studs: 2 rows at BlockSize 4 is the top 8 studs.
]]
GameConfig.OreFreeSurfaceRows = 2

--[[
	Ore blocks are shinier than the rock around them, scaled by rarity, so a
	valuable vein is obvious at a glance against a matte wall. Common ore is the
	filler rock itself and stays flat.
]]
GameConfig.OreReflectance = {
	Common = 0,
	Uncommon = 0.10,
	Rare = 0.18,
	Epic = 0.28,
	Legendary = 0.40,
	Mythic = 0.55,
}

-- Material used for any Uncommon-or-better ore block, unless the ore declares
-- its own. Metal catches light against the matte layer materials.
GameConfig.OreMaterial = Enum.Material.Metal

-- ==========================================================================
-- Swing animation and block health bar
-- ==========================================================================

-- Length of one procedural pickaxe swing, in seconds. Clamped at runtime to
-- stay under the equipped pickaxe's cooldown so swings never overlap.
GameConfig.SwingAnimSeconds = 0.34

-- Phase boundaries within that swing, as fractions: wind up, then strike, then
-- recover. Strike is deliberately the shortest for a sharp, weighty hit.
GameConfig.SwingAnimWindupEnd = 0.35
GameConfig.SwingAnimStrikeEnd = 0.55

-- Peak angles, in degrees: back over the shoulder, then down through the block.
GameConfig.SwingAnimWindupAngle = 65
GameConfig.SwingAnimStrikeAngle = -50

-- Health bar shown above a block once it has taken damage. Hidden at full HP so
-- an untouched wall isn't covered in UI.
GameConfig.BlockHealthBarWidth = 78
GameConfig.BlockHealthBarHeight = 11
GameConfig.BlockHealthBarOffset = 2.8

-- Streaming hysteresis, in studs. Chunks materialize inside StreamRadius and are
-- only reclaimed past ReclaimRadius, so a player pacing a border can't thrash
-- the part pool. Keep Reclaim comfortably larger than Stream.
GameConfig.ChunkStreamRadius = 96
GameConfig.ChunkReclaimRadius = 144

-- How long a broken block stays gone before it regenerates, in seconds.
-- Low values keep the mine dense; high values push players deeper to find ore.
GameConfig.BlockRegenSeconds = 45

-- Parts pre-allocated into the block pool at boot. Sized to roughly one fully
-- streamed chunk radius so the first descent doesn't allocate mid-frame.
GameConfig.BlockPoolPrewarm = 512

-- ==========================================================================
-- Block health
-- ==========================================================================

-- HP of a hardness-1 block in layer 1. Final HP is:
--   BlockBaseHp * LayerDef.hpMultiplier * OreDef.hardness
GameConfig.BlockBaseHp = 10

-- Ore units granted per broken block, before backpack capacity is applied.
GameConfig.OreYieldMin = 1
GameConfig.OreYieldMax = 2

-- ==========================================================================
-- Tick rates
-- ==========================================================================

-- Passive income accrual interval, in seconds. The doc's 1s heartbeat.
GameConfig.IncomeTickSeconds = 1

-- How often the streamer re-evaluates which chunks should exist. Twice a second
-- is well under how fast a player can cross ChunkStreamRadius.
GameConfig.ChunkStreamTickSeconds = 0.5

-- Profile autosave interval, in seconds. Saves are staggered per player so 20
-- profiles don't hit the DataStore in the same frame.
GameConfig.AutosaveSeconds = 60

-- ==========================================================================
-- Mining validation (server-authoritative; see AntiCheatService)
-- ==========================================================================

-- Extra studs added to the equipped pickaxe's reach before rejecting a swing.
-- Absorbs client/server position desync without opening up reach hacking.
GameConfig.ReachTolerance = 6

-- Fraction of the nominal swing cooldown a client may undershoot before the
-- swing is rejected. 0.15 tolerates ping jitter; higher invites swing spam.
GameConfig.SwingCooldownTolerance = 0.15

-- Sustained swing rate above (pickaxe rate * this) gets logged and throttled.
GameConfig.SwingRateViolationFactor = 1.5

-- Remote calls per player per second, across all remotes, before throttling.
GameConfig.RemoteRateLimitPerSecond = 20

-- Logs every swing request and the exact reason any of them is refused, on both
-- the client and the server. Noisy by design -- it is for answering "I clicked
-- and nothing happened". Flip to true when a swing isn't landing and the output
-- will name the exact check that refused it.
GameConfig.DebugMining = false

-- ==========================================================================
-- Conversion
-- ==========================================================================

-- Ore units consumed by one Conversion Chamber roll.
GameConfig.ConversionOreCost = 15

-- Rolls without an Epic-or-better result before the next roll is guaranteed to
-- be Epic+. Lower = friendlier, and directly moves the "first Epic" milestone.
GameConfig.PityThreshold = 25
GameConfig.PityMinimumRarity = "Epic"

-- How strongly the fed ore biases the outcome table. The ore's own convertsTo
-- entries get their weight multiplied by this; everything else rolls at base.
GameConfig.ConversionOreBias = 6

--[[
	Base roll weight per rarity, before the fed ore's bias is applied. These are
	the numbers the Convert screen's odds table is computed from, so they are
	the honest probabilities the doc asks us to show.

	Roughly a 2.7x drop per rarity step, which puts Mythic near 1 in 800 on an
	unbiased roll -- rare enough to matter, common enough that the pity counter
	is the floor rather than the only route.
]]
GameConfig.ConversionRarityWeights = {
	Common = 1000,
	Uncommon = 370,
	Rare = 135,
	Epic = 40,
	Legendary = 11,
	Mythic = 2,
}

-- Mutation roll weights. Multipliers themselves live per-brainrot in
-- BrainrotConfig so a character can opt out of a tier.
GameConfig.MutationWeights = {
	Normal = 1000,
	Golden = 140,
	Diamond = 24,
	Glitched = 3,
}

-- ==========================================================================
-- Plots and income
-- ==========================================================================

GameConfig.StartingPlotSlots = 4
GameConfig.MaxPlotSlots = 24

-- ==========================================================================
-- Plot geometry
-- ==========================================================================
--[[
	Plots are laid out in a row well clear of the shaft, one per possible
	player, and built once at boot rather than per join -- claiming a plot then
	costs a table write instead of building geometry while someone is waiting.
]]

GameConfig.PlotCount = 20 -- matches the doc's 20-player target
GameConfig.PlotOrigin = Vector3.new(-600, 0, -200)
GameConfig.PlotWidth = 96
GameConfig.PlotDepth = 96
GameConfig.PlotSpacing = 24 -- gap between neighbouring plots
GameConfig.PlotWallHeight = 12
GameConfig.PlotWallThickness = 2
GameConfig.PlotFloorThickness = 4

-- Podiums are laid out in a grid on the plot floor. 6 x 4 holds MaxPlotSlots.
GameConfig.PodiumsPerRow = 6
GameConfig.PodiumSize = Vector3.new(8, 3, 8)
GameConfig.PodiumSpacing = 14

-- Brainrot models are scaled to roughly this height so a Mythic doesn't
-- dwarf the plot and a Common isn't invisible.
GameConfig.BrainrotHeight = 6

-- Offline earnings are accrued at the player's placed-brainrot rate, capped at
-- this many seconds so a month away doesn't trivialize the economy.
GameConfig.OfflineEarningsCapSeconds = 4 * 60 * 60

-- Offline income is paid at this fraction of the online rate.
GameConfig.OfflineEarningsRate = 0.5

-- ==========================================================================
-- Rebirth
-- ==========================================================================

-- Coins required for rebirth N, as RebirthBaseCost * RebirthCostGrowth^(N).
GameConfig.RebirthBaseCost = 250000
GameConfig.RebirthCostGrowth = 3.2

-- Each rebirth adds this to a multiplier that starts at 1.0 and scales both
-- mining damage and passive income.
GameConfig.RebirthMultiplierStep = 0.35

-- Rebirths required before each Mythic-tier ore becomes reachable at all.
GameConfig.RebirthsForMythicOre = 3

-- ==========================================================================
-- Progression curves
-- ==========================================================================
-- ToolConfig generates its tiers from these. The doc's targets: costs ~1.55x
-- per tier, brainrot income ~1.8x per tier.

-- Cost growth per tier, shared by pickaxes, backpacks, and plot slots. This is
-- the single knob that makes upgrades feel earned; raising it lengthens the
-- whole game.
GameConfig.CostGrowth = 1.55

-- Brainrot income growth per rarity step. Kept above CostGrowth so each tier of
-- spending buys more than it costs and the loop stays forward-moving.
GameConfig.IncomeGrowth = 1.8

-- Pickaxe damage growth per tier. Deliberately below CostGrowth so raw damage
-- never outruns block HP scaling and trivializes deep layers.
GameConfig.PickaxePowerGrowth = 1.45

-- Pickaxe tiers, and the tier-1 stats the curve grows from.
GameConfig.PickaxeTiers = 20
GameConfig.PickaxeBasePower = 3
GameConfig.PickaxeBasePrice = 500
GameConfig.PickaxeBaseSwingsPerSecond = 1.6
GameConfig.PickaxeMaxSwingsPerSecond = 3.2
GameConfig.PickaxeBaseReach = 18
GameConfig.PickaxeMaxReach = 30

-- Backpack tiers, and the tier-1 stats the curve grows from.
GameConfig.BackpackTiers = 12
GameConfig.BackpackBaseCapacity = 25
GameConfig.BackpackCapacityGrowth = 1.6
GameConfig.BackpackBasePrice = 400

-- Cost of the Nth extra podium slot, as PlotSlotBasePrice * CostGrowth^N.
GameConfig.PlotSlotBasePrice = 5000

table.freeze(GameConfig.MutationWeights)
return table.freeze(GameConfig)
