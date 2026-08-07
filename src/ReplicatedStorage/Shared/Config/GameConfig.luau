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
