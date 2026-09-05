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

--[[
	Hub platform built by MineService, top surface at SurfaceY.

	Two rectangles, not one square. The square was 720 across and the things
	standing on it are not: the plot row spans X +-216 and the shaft is a 52-stud
	hole, so a single extent wide enough for the plots left ~250 studs of empty
	lawn behind them and a shaft sitting in the middle of a field.

	So: a wide band holding the plot row, and a narrow stem running north to the
	shaft. The stem's width is set by what has to fit beside the shaft -- the
	leaderboard row on its west wall, and room to walk past on either side --
	not by the plot row, which is nearly three times wider.

	Both bands are measured to the *outer* rim. The wall stands inside that,
	reaching WallThickness inward, so the walkable figures are each of these
	less 16.
]]
GameConfig.HubPlotHalfX = 252 -- plot row reaches +-216; 20 studs of lawn, then wall
GameConfig.HubPlotZMin = -188 -- plot backs are at -152, same 20-stud margin
GameConfig.HubPlotZMax = -20 -- where the plot band ends and the stem takes over
GameConfig.HubMineHalfX = 96 -- stem half-width; shaft is only +-26
GameConfig.HubMineZMax = 162 -- stem's north rim; shaft's far lip is 106

GameConfig.HubThickness = 20

--[[
	The hub floor is laid as square tiles rather than four big slabs, each tile
	taking its own step of the grass ramp. Same trick the mine blocks use: a
	single flat slab reads as a single flat slab no matter what material is on
	it, and this is the cheapest way to get a lawn that looks drawn rather than
	extruded (DESIGN.md 2a -- detail from geometry, not from texture, because a
	texture needs an asset ID and this project ships none).

	Dropped 40 -> 16 once the hub shrank. At 40 the lawn was ~73 tiles over the
	tightened footprint and read as a handful of flat quadrants; 16 gives ~460,
	which is back around what the old 720-square cost at its coarser pitch.

	Every rectangle's edges must land exactly where they were asked -- the shaft
	opening is defined by the mine's block grid -- so the span is divided into
	equal columns rather than stepped at a fixed pitch and clamped. Clamping
	lands the edges too, but leaves a sliver tile along two edges of every
	rectangle, which is exactly the defect the wall had.
]]
GameConfig.HubTileSize = 16

--[[
	Lawn relief. Each tile's top is dropped by 0, half, or all of this.

	Downward, not upward: the path sits only PathRaise above the surface, and a
	lawn tile lifted higher than that would poke through it. Sinking instead
	keeps SurfaceY the ceiling, so anything laid on the lawn stays on top of it.
]]
GameConfig.HubRelief = 0.35

--[[
	Ground scatter -- grass clumps and the odd stone sitting on the lawn.

	Placed per floor tile rather than free-scattered, so density follows the
	lawn and nothing needs a spatial index. Non-colliding, so a player never
	catches on one. Seeded, because the world is shared and every server has to
	grow the same lawn.
]]
GameConfig.HubScatterSeed = 20260905
GameConfig.HubScatterChance = 0.3 -- of lawn tiles that get a clump
GameConfig.HubScatterStoneChance = 0.18 -- of those clumps, how many are stone
GameConfig.HubScatterSizeMin = 2.5
GameConfig.HubScatterSizeMax = 5.5
GameConfig.HubScatterHeightMin = 0.9
GameConfig.HubScatterHeightMax = 2.4

--[[
	The path from the plots to the shaft.

	A spine running north from the plot row to the spawn pad, and a cross bar in
	front of the plots feeding into it. Without it the hub is an undifferentiated
	green field and nothing tells a new player which way the mine is.

	Laid as tiles like the lawn, in the same dirt colour as Topsoil, and raised a
	hair above the grass so the two never z-fight where they overlap.

	Width 16 with a 16-stud tile made the spine literally one paver wide and the
	cross bar one paver deep, which is why it read as a row of big squares. 28
	wide on an 8-stud paver is four across -- a path rather than a line of tiles.
]]
GameConfig.PathTileSize = 8
GameConfig.PathWidth = 28
GameConfig.PathRaise = 0.05

-- Paver relief, upward: the path is already above the lawn, so lifting is safe
-- here where it is not on the grass. Smaller than the lawn's, because an uneven
-- path reads as broken rather than natural.
GameConfig.PathRelief = 0.12

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

--[[
	The retaining wall.

	A square parapet standing on the hub's rim: a checkerboard of two dirt
	shades, capped with a grass lip. Standing anywhere on the hub you see a
	built earth wall and a green top edge rather than the platform's rim and the
	void past it.

	This replaced a ridge of terraced grass mounds. The mounds sat on a ring
	inset from the edge and grew *inward* by half their width, which is what
	forced the hub's old clearance arithmetic -- widen either the plot row or a
	mound and hills would grow through the outer plots. A wall occupies a fixed
	WallThickness on the rim and reaches inward by nothing, so that whole class
	of bug is gone with it.

	The pattern is a true checkerboard, which is a deliberate break from the
	lawn's quantized noise. The lawn wants to read as ground, where a regular
	grid would look like a tiled floor instead; the wall is a built structure,
	and a built structure is exactly where a regular grid belongs.

	Sizing: tiles are square at WallTileSize, and WallHeight is kept a whole
	multiple of it so the top row is never a sliver. 24 into 96 gives 4 rows,
	and about 290 parts around the two bands' 1730-stud outline -- down from 480
	when the hub was a 2880-stud square, and comfortably under the lawn's ~320.
]]
GameConfig.WallHeight = 96 -- face height, plinth included, before the coping goes on
GameConfig.WallThickness = 16 -- inward from the hub rim

--[[
	Face detailing.

	A 96-stud slab in one flat plane of 24-stud squares read as a box no matter
	what colour was on it. The fix is the one DESIGN.md already prescribes for
	sub-block detail -- more geometry, not smoother geometry -- so the face is
	now a proper wall section: a plinth at the bottom, a finer checker above it,
	a string course under an overhanging coping, and pilasters at intervals to
	break the long runs.

	Tiles dropped 24 -> 16, which also puts the checker density closer to the
	reference art (5 rows of face instead of 3). (WallHeight - WallPlinthHeight)
	must stay a whole multiple of WallTileSize or the top row comes out a sliver.
]]
GameConfig.WallTileSize = 16 -- square checker tile; (96 - 16) / 16 = 5 rows
GameConfig.WallPlinthHeight = 16 -- base course, one tile row tall
GameConfig.WallStringHeight = 4 -- thin band between the face and the coping
GameConfig.WallCapHeight = 7 -- the grass coping itself
GameConfig.WallCapOverhang = 3 -- coping oversails both faces, for a shadow line
GameConfig.WallProud = 2 -- how far the plinth and string course stand out

--[[
	Per-tile relief. Each tile is pushed out from the rim by 0, half, or all of
	this, picked by the same hash the mine blocks use for shade. Small on
	purpose: enough that the face catches light unevenly and stops reading as a
	single plane, not so much that it looks damaged.
]]
GameConfig.WallRelief = 0.6

-- Buttresses along each run, and on its first and last column -- so every
-- corner gets one, and the 504-stud south run is not one unbroken sweep.
-- A pilaster occupies a whole column of the face grid rather than a fixed
-- width: off the grid it cut tiles in half and left slivers down its sides.
GameConfig.WallPilasterSpacing = 64
GameConfig.WallPilasterProud = 3

-- The two checker steps, as indices into the shade palette. Far apart on
-- purpose: adjacent steps are a 7% difference and read as one flat colour at
-- any distance.
GameConfig.WallCheckerShades = { 0, 3 }

-- Pushed warm and saturated on purpose, which looks wrong written down:
-- cartoonify multiplies saturation by 1.45, leaving the base at 168,93,25.
-- But every face of the wall points inward, away from the sun, and
-- SurfaceAmbient is a blue-grey -- which drains a gentler brown to mauve. The
-- flat material carries no texture to hide that either. Tuned against a lit
-- screenshot rather than on paper; re-tune it the same way.
GameConfig.WallColor = Color3.fromRGB(150, 104, 62)

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
-- Atmosphere
-- ==========================================================================
--[[
	Every LayerDef has carried fogColor, fogEnd and ambientColor since the
	layers were written, and until now nothing read any of them: the per-layer
	atmosphere was specced and never wired up, which is why all six layers lit
	identically and why you could see straight off the edge of the world.
	AtmosphereController applies them from the client, off the local player's
	depth.

	These are the above-ground values, which no LayerDef can supply -- layer 1
	starts at the surface and runs 70 studs down, and the fog that suits a shaft
	is not the fog that suits an open field.
]]

--[[
	Deliberately far. The first attempt at this was 620, which put 36% haze on
	the ridge and 67% on its corners -- at any normal camera distance the
	scenery simply dissolved into grey, which is a strange way to treat the one
	piece of it whose entire job is being seen.

	Above ground the retaining wall is what hides the void, so fog up here is
	only for depth. At 1800 the fog does not begin until 504 studs
	(FogStartFraction), and since the hub was tightened the farthest corner of
	the wall is the plot band's, at 313 studs. Nothing built now reaches the
	ramp at all: the hub reads clean, and the fog only bites on whatever lies
	beyond the wall.
]]
GameConfig.SurfaceFogEnd = 1800
GameConfig.SurfaceFogColor = Color3.fromRGB(198, 214, 232)
GameConfig.SurfaceAmbient = Color3.fromRGB(126, 134, 148)

-- Fog begins this fraction of the way to FogEnd. Low values read as haze the
-- moment you look up; too high and the fall-off becomes a visible wall.
GameConfig.FogStartFraction = 0.28

--[[
	Seconds for the atmosphere to cross most of the way to a new layer's values.
	Crossing a band boundary should feel like descending, not like a cut -- but
	long blends mean the surface fog is still lifting when you are 40 studs down.
]]
GameConfig.FogBlendSeconds = 0.8

-- ==========================================================================
-- Tick rates
-- ==========================================================================

-- Passive income accrual interval, in seconds. The doc's 1s heartbeat.
GameConfig.IncomeTickSeconds = 1

--[[
	How often accumulated coin changes are pushed to the client.

	EconomyService.award used to fire a CoinsChanged remote on every call. That
	is harmless at one call per second from income, but any code path awarding
	coins in a loop floods the client -- a balance simulation doing exactly that
	locked up a Studio session during development. Deltas are now accumulated
	and flushed on this interval instead.

	5 pushes per second is well past what a coin counter needs to feel live.
]]
GameConfig.CoinsPushIntervalSeconds = 0.2

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

--[[
	Ore units consumed by one Conversion Chamber roll.

	Chosen by sweeping this against the §7 milestones, not by intuition. 15 put
	the first conversion at ~1 min against a ~2 min target; 25 pushed it to
	~2.3 min but dragged every later milestone with it.

	There is a hard ceiling here worth knowing about. The starter backpack holds
	25 weight, and Topsoil's two ores split roughly 59/41, so the largest
	single-type stack one trip can produce is about 15 units. A cost far above
	that gates the first conversion behind a backpack upgrade rather than behind
	mining, which is not the intended early loop.
]]
GameConfig.ConversionOreCost = 20

--[[
	Rolls without an Epic-or-better result before the next is guaranteed to be
	Epic+. Lower is friendlier, and this is the reliable lever on the "first
	Epic" milestone -- raising Epic's roll weight would move every later
	milestone too.

	16 rather than 20 or 25: at 20 the first Epic modelled at ~28.6 min against
	a ~20 min target; 16 brings it to ~22.9 without measurably touching the
	rebirth timing.
]]
GameConfig.PityThreshold = 16
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

--[[
	Four plots, laid out in a row just north of the shaft.

	This is fewer than the doc's 20-player target on purpose, and the trade is
	real: PlotService hands out plots first-come, so player five onwards gets a
	warning and no plot, which means no podiums and no passive income for them.
	Raise this (and widen the row, or it will run off the hub) if the place is
	ever opened past four players.

	The row sits inside the hub slab rather than 600 studs away across empty
	space, so the walk from the shaft to your podiums is a few seconds.
]]
GameConfig.PlotCount = 4
GameConfig.PlotOrigin = Vector3.new(-168, 0, -120)

--[[
	Leaderboards: a row along Z on the west side of the stem, turned to face
	east across it.

	They used to stand on the walk between the plots and the shaft, facing back
	down it -- which put two 38x26 slabs directly across the one sightline that
	should always be clear, the one that tells you where the mine is. Standing
	them side-on keeps them readable on the way past without their being the
	thing you have to walk around.

	Moved from X -132 when the hub was tightened: -132 is outside the stem and
	would have left them standing in the void. -72 puts them against the stem's
	west wall (walkable edge -80), still side-on to the walk north.
]]
GameConfig.LeaderboardCenter = Vector3.new(-72, 0, 40)
GameConfig.LeaderboardSpacing = 44
GameConfig.LeaderboardHeight = 14
--[[
	Width is set by the podium grid: PodiumsPerRow (6) at PodiumSpacing (14) is
	70 studs plus a podium, so anything under ~86 pushes podiums through the
	side walls. Depth only needs the 4 rows that hold MaxPlotSlots, which is 50,
	so it was trimmed from 96 -- a row of four 96-deep plots made the hub wider
	than the ridge could close around.
]]
GameConfig.PlotWidth = 96
GameConfig.PlotDepth = 64
GameConfig.PlotSpacing = 16 -- gap between neighbouring plots
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
