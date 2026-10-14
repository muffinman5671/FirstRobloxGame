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

--[[
	Edge length of a single mine block, in studs. Blocks are Parts, never Terrain.

	Note what this does *not* change: a block's HP is BlockBaseHp * hpMultiplier *
	hardness, with no size term, so a bigger block costs the same swings and
	yields the same ore. What it changes is how much shaft one block covers --
	at 6 a player descends 50% further per block broken than at 4, and the same
	volume of mine is a third fewer parts to stream.
]]
GameConfig.BlockSize = 6

-- Blocks per chunk axis. 4 -> chunks of 4x4x4 blocks = 24x24x24 studs = 64 parts.
-- Larger chunks mean fewer streaming decisions but chunkier hitches on load.
GameConfig.ChunkBlocks = 4

-- Half-width of the shaft in blocks. 8 -> a 17-block-wide square shaft (~102
-- studs). Widen for more players mining side by side; costs parts per layer as
-- the square of this, so it is the expensive dimension to grow.
GameConfig.ShaftRadiusBlocks = 8

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
	standing on it are not: the plot row spans X +-216 and the shaft is a 102-stud
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
GameConfig.HubPlotHalfX = 196 -- plot row reaches +-161; 19 studs of lawn, then wall
GameConfig.HubPlotZMin = -180 -- back pair dropped south to clear the arms; 16 studs to the wall

--[[
	Where the plot band ends and the stem takes over -- and therefore where the
	shoulder wall runs. Walked north repeatedly as the row moved toward the mine.

	**What actually limits it:** the plot band is tiled as one solid rectangle up
	to here while only the stem is split around the shaft, so a value at or past
	the shaft's south lip (ShaftCenterZ - shaftHalf = 29) tiles the band straight
	over the hole. 22 leaves a 7-stud landing between the gateway and the lip.

	It does *not* have to stay south of the spawn pad, which an earlier revision
	of this comment claimed. The pad only needs floor under it, and the band is
	floor too -- at 22 it straddles the seam, resting on tiles from both, which
	is fine. Believing otherwise cost the row 12 studs it could have had.

	Moving the shaft does not help either: the distance from the row to the lip
	is (lip - HubPlotZMax) + WallThickness + margin, and shifting ShaftCenterZ
	moves the lip and the gateway together. Only this value, the wall thickness
	and the margin matter.
]]
GameConfig.HubPlotZMax = 25
GameConfig.HubMineHalfX = 120 -- stem half-width; shaft is +-51, leaving 53 a side
GameConfig.HubMineZMax = 180 -- stem's north rim; shaft's far lip is 131

GameConfig.HubThickness = 20

--[[
	The hub floor: a flat two-tone checkerboard, laid as square tiles.

	Matched to reference art. It used to be quantized noise -- the same hash the
	mine blocks use, deliberately irregular so the lawn read as ground rather
	than a tiled floor. The reference does the opposite: a regular checker, flat
	colour, no material grain, the same treatment as the walls. So the noise is
	gone and the two shades alternate on (column + row).

	Still geometry rather than a texture -- DESIGN.md 2a, and a texture would
	need an asset ID this project does not ship.
]]
GameConfig.HubTileSize = 12

-- The two floor checker steps, as palette indices. Same idea as the wall's,
-- and far enough apart to read as a check rather than as uneven lighting.
GameConfig.HubCheckerShades = { 1, 3 }

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
	ChunkStreamTickSeconds, plus fall speed. Walk speed is 24 (set as
	StarterPlayer.CharacterWalkSpeed in default.project.json, the same way
	FallenPartsDestroyHeight is -- neither is writable from a script), so a tick
	covers 12 studs against 8 at the old default of 16. 40 was a 5x margin then;
	48 keeps it above 4x now.

	Blocks are 6 studs, so this radius is 8 blocks rather than the 10 it was at
	BlockSize 4 -- the safe set is fewer parts than the number suggests.
]]
GameConfig.SafeLoadRadius = 48

--[[
	The plaza: the paved square between the four bases and the mine, and the
	place the shops stand.

	This replaced a stone path -- a cross bar, a spine to the shaft, two spurs
	and a branch east to the shops. The path was the right shape for a hub whose
	shops lived off in the stem beside the shaft, but it made the courtyard the
	bases face into a lawn you crossed rather than a place you arrived at. One
	square does the same connecting job and gives the shops somewhere to be.

	Its bounds are not written down here. MineService derives them from the plot
	row and the shaft lip, so moving a plot moves the plaza with it rather than
	silently opening a strip of lawn between the two.

	Raised PlazaRaise above the lawn. The lawn tiles run underneath it, and a
	flush slab would sit coplanar with them and z-fight -- the same trap the plot
	floors and the wall footing both fell into.
]]
GameConfig.PlazaTileSize = 10
GameConfig.PlazaRaise = 0.05
GameConfig.PlazaColor = Color3.fromRGB(150, 158, 170)
GameConfig.PlazaCheckerShades = { 1, 2 } -- adjacent steps: paving joints, not a chequerboard
GameConfig.PlazaBorderShade = 4 -- one darker course all round, so the square has an edge

--[[
	Lamp standards around the plaza, given as offsets from its own bounds so the
	ring survives the plaza being resized.

	`inset` is how far in from the edge they stand; the two rows sit clear of the
	turned plots' entrances and of the spawn pad. Neon heads and no PointLight:
	this is an outdoor daylight surface, and the hub's light budget is spent on
	the plot interiors, where the roof cuts the skylight.
]]
GameConfig.PlazaLampInset = 8
GameConfig.PlazaLampsPerRow = 5
GameConfig.PlazaLampHeight = 17

--[[
	A lamp closer than this to a shop's centre is moved outward along the edge
	until it clears, rather than left crowding the building.

	The lamps ring the plaza on a fixed inset and the shops sit on the same
	flanks, so the two want the same ground. Moved rather than skipped: a gap in
	the ring is more noticeable than a lamp four studs further out, and the lamp
	is still doing its job.

	A radius, not a real footprint test, because the furniture is built before
	the shops and does not know their dimensions -- so it is deliberately larger
	than any real footprint and catches "uncomfortably close" as well as
	"overlapping". The build is checked for actual overlaps afterwards, which is
	what would catch this being set wrong.
]]
GameConfig.PlazaLampShopClearance = 20
GameConfig.PlazaLampNudge = 4 -- studs per attempt, outward from the plaza centre

--[[
	Centre monument: a stepped plinth carrying the same crossed-hammer emblem as
	the plot headers. Geometry only, like everything else here.
]]
GameConfig.PlazaMonumentSteps = 3
GameConfig.PlazaMonumentBase = 18

--[[
	Lawn decoration around the mine.

	The three grass regions in the stem -- a corridor either side of the shaft
	and the apron behind it -- were bare tiled floor with nothing on them but the
	leaderboards. HubDecor scatters props across them on a jittered grid.

	Deterministic, from DecorSeed: the world is shared, so two servers of the
	same place should not have different lawns, and a fixed layout is something
	a screenshot can be compared against.
]]
GameConfig.DecorSeed = 20260912

--[[
	Grid cell, jitter, and the chance a cell is even tried -- one set per pass.

	**Two passes, large props first.** The first attempt used one grid for
	everything and the result was 15 flower patches to a single tree: a big prop
	is rejected far more often than a small one, both by its own footprint
	needing to fit inside the region and by the spacing check, so running them in
	one pool lets the small props take every contested spot. Placing the trees,
	boulders and crates first on a coarse grid, then filling the gaps with bushes
	and flowers on a fine one, puts the eye-catching things where they belong and
	still fills in around them.

	Jitter stays under half its pass's pitch, or props from neighbouring cells
	trade places and the grid shows through as a diagonal.

	Note that spacing rejection, not the grid, is what actually caps density: two
	conifers need about 17 studs between centres. Simulated over the real region
	bounds, a 24-stud pitch placed four props across the whole hub.
]]
GameConfig.DecorLargePitch = 16
GameConfig.DecorLargeJitter = 6
GameConfig.DecorLargeDensity = 0.85

GameConfig.DecorSmallPitch = 9
GameConfig.DecorSmallJitter = 3.5
GameConfig.DecorSmallDensity = 0.8

--[[
	Keep-outs, in studs.

	`Shaft` is measured out from the rim and is the one that matters most: the
	lip is walked, and a tree on it is a tree you fall past. `Wall` keeps props
	off the retaining wall's inner face, `Spacing` holds two props' own footprint
	circles apart, and `Clearance` inflates a prop before it is tested against
	anything already built, so nothing ends up touching a stall or a board.
]]
GameConfig.DecorShaftMargin = 10
GameConfig.DecorWallMargin = 4
GameConfig.DecorSpacing = 2
GameConfig.DecorClearance = 3

--[[
	Relative frequency within a pass. Weights only compete against others in the
	same tier -- which tier a prop belongs to is a fact about the prop and lives
	with its radius in HubDecor.

	Trees carry the large pass because they are the silhouette you see from
	across the hub; crates are rarer because they are a mining detail and read as
	litter in quantity.
]]
GameConfig.DecorWeights = {
	conifer = 4,
	broadleaf = 4,
	boulder = 3,
	crates = 2,
	bush = 5,
	flowers = 3,
}

--[[
	Decoration colours, authored rather than derived.

	Not run through `cartoonify` like the ground is: that multiplies saturation
	by 1.45, which is right for pulling a layer's muted rock toward poster colour
	and wrong for a colour already picked to look the way it looks.
]]
GameConfig.DecorPalette = {
	bark = Color3.fromRGB(112, 76, 48),
	barkDark = Color3.fromRGB(88, 58, 36),
	leafDeep = Color3.fromRGB(38, 122, 62),
	leafMid = Color3.fromRGB(58, 158, 74),
	leafLight = Color3.fromRGB(96, 196, 92),
	stone = Color3.fromRGB(132, 138, 148),
	stoneDark = Color3.fromRGB(104, 110, 122),
	stoneLight = Color3.fromRGB(158, 164, 174),
	crate = Color3.fromRGB(176, 126, 70),
	crateDark = Color3.fromRGB(126, 86, 46),
	crateBand = Color3.fromRGB(88, 96, 110),
	soil = Color3.fromRGB(84, 62, 42),
}

-- Flower heads, picked one per stem. Bright and few: they are 1.4-stud cubes
-- and have to read as colour from across the corridor.
GameConfig.DecorFlowerColors = {
	Color3.fromRGB(248, 96, 112),
	Color3.fromRGB(255, 208, 56),
	Color3.fromRGB(120, 176, 255),
	Color3.fromRGB(226, 132, 246),
	Color3.fromRGB(255, 246, 236),
}

GameConfig.PlazaPalette = {
	kerb = Color3.fromRGB(120, 128, 140),
	stone = Color3.fromRGB(96, 104, 118),
	post = Color3.fromRGB(52, 58, 70),
	lamp = Color3.fromRGB(255, 246, 224),
	emblem = Color3.fromRGB(214, 221, 230),
}

--[[
	The three shops, moved out of the middle of the plaza and up to the mine
	mouth, flanking the walk between the square and the shaft.

	Two corridors of lawn run either side of the shaft: from the retaining wall's
	inner face at x = +-101 to the shaft's edge at x = +-51, so 50 studs each.
	A stall is 26 wide, which centres at x = +-76 with 12 studs to spare on both
	sides; +-78 is that, nudged the couple of studs toward where the corridor is
	actually walked.

	Sell and Tools share the west corridor in a north-south row. Their lit
	circles are 22 across and must not overlap -- standing in two at once would
	have one panel opening while the other closes -- so they are 30 apart, which
	leaves 8 studs of clear ground between the two circles.

	Each faces the way its geometry already points: the two market stalls have
	their counter on the south side, meeting a player coming up from the square,
	and the exchange has its counter on the west, facing the shaft walk.
]]
--[[
	All three back onto the plaza's north edge at Z = 29 -- where the paving
	meets the grass round the shaft -- in a row facing south into the square.

	Slid west of centre so they sit off the mouth of the mine rather than across
	it. They do not clear it entirely: the shaft is 102 studs wide (X +-51)
	against a 200-stud plaza, so the north edge offers only 49 studs of frontage
	either side, and a pair of stalls 30.9 wide apiece needs 65. Tools is as far
	west as the paving allows, and Sell still laps the western edge of the
	opening by ~17 studs, down from 28.5 before the slide. Clearing it completely
	means giving up either this edge or the pair being side by side.

	Each is placed by where its turned footprint lands, not its centre, so the
	backs sit ~1.5 studs off the grass line.

	Yaw is degrees about Y, applied the same way PlotLayout's is, and each
	builder has its own idea of "front":

	  the market stalls (sell, tools) put their counter on local -Z, which a yaw
	  of t sends to world (-sin t, 0, -cos t)
	  the exchange puts its counter on local -X, which goes to (-cos t, 0, sin t)

	Both are 18 degrees off square, tilted toward the middle of the square. The
	market stalls face south-southeast on -18; the exchange needs -72 for the
	mirrored look, because its front is a different local axis. The two are not
	interchangeable.
]]
--[[
	The two market stalls' shell size. Both are built from these, so they cannot
	drift apart.

	18 x 13 is not a taste decision, it is the largest that clears the mine.
	Turned 18 degrees a stall's footprint measures w*cos18 + (d+3)*sin18 across,
	and two of them plus a gap have to fit the 49 studs of north edge between the
	plaza's west corner and the mouth of the shaft at X -51:

	    26 x 17 -> 30.9 each, 64.8 for the pair   (the old size; 16 too wide)
	    20 x 14 -> 24.3 each, 51.6                (still over)
	    18 x 13 -> 22.1 each, 47.1                (fits, with ~4 studs to spare)

	Post height stays at 13. Shrinking it too would have squeezed the 5.4 studs
	of headroom between the counter top and the awning that the goods on the
	counter are sized to fit in.
]]
GameConfig.MarketStallWidth = 18
GameConfig.MarketStallDepth = 13
GameConfig.MarketStallPostHeight = 13

--[[
	The lit circle in front of each shop. 14 across, where it used to be 22:
	at 22 it was wider than the 18-wide stall standing on it, which is what made
	it read as a puddle of colour rather than a place to stand. It is also the
	trigger radius, so 14 means stepping within 7 studs of its centre.

	Shrinking it fixed something else by accident. At 22 the sell and tools
	circles were 26 apart with 22 studs of radius between them -- a 4-stud gap,
	the tightest they have been, and they must never touch or one panel opens as
	the other closes. At 14 that gap is 12.
]]
GameConfig.ShopPadDiameter = 14

--[[
	How the disc is made up, from the reference art: a saturated rim burning
	round a washed-out middle, with a grid of small raised studs across it.

	`Rim` is how much saturated edge shows around the pale face. `StudPitch` and
	`StudSize` set the texture -- the studs are geometry rather than a texture
	map, both because the project ships no asset IDs and because the reference's
	pattern is genuinely raised.

	Pitch is the expensive one: it costs studs as the square of the radius over
	it. At 14 across and a pitch of 1.6 that is ~37 studs per pad, ~111 across
	the three shops, which is nothing beside the mine but would climb fast on a
	bigger circle.
]]
GameConfig.ShopPadRim = 1.4
GameConfig.ShopPadStudPitch = 1.6
GameConfig.ShopPadStudSize = 0.9

--[[
	`padOffset` is in each shop's own frame, so the circle sits in front of the
	counter rather than under the middle of the building.

	It differs per shop because "in front" is a different local axis for each:
	the market stalls put their counter on -Z and the exchange on -X, and the
	exchange's counter is further from its centre than a stall's, so it needs
	the longer reach. Both land the circle's near edge just past the counter
	face, which is where a player actually stands to use the shop.
]]
GameConfig.ShopLayout = {
	sell = {
		position = Vector3.new(-62.5, 0, 17),
		yaw = -18,
		padOffset = Vector3.new(0, 0, -14),
		padColour = Color3.fromRGB(224, 64, 64),
	},
	tools = {
		position = Vector3.new(-88.5, 0, 17),
		yaw = -18,
		padOffset = Vector3.new(0, 0, -14),
		padColour = Color3.fromRGB(248, 180, 44),
	},
	convert = {
		position = Vector3.new(70, 0, 13),
		yaw = -72,
		padOffset = Vector3.new(-20, 0, 0),
		padColour = Color3.fromRGB(96, 216, 255),
	},
}

-- CollectionService tag on the shops' standing circles. MineService tags them,
-- UIController watches for them; it lives here so neither side owns a string
-- literal the other has to match.
GameConfig.PanelPadTag = "PanelPad"

-- Attribute on a standing circle naming which shop it belongs to, matching the
-- ShopLayout keys above. The panel a pad opens is not a reliable identity --
-- the sell stall opens the same Backpack panel the HUD button does.
GameConfig.ShopKeyAttribute = "ShopKey"

--[[
	Slack, in studs, added to the sell circle's own radius before the server
	will refuse a sale.

	Ore can only be sold at the stall. Both sides measure the same built part --
	the client greys the Sell buttons out at exactly the circle that opens the
	panel, so the affordance and the trigger agree. The server allows this much
	beyond it: a sale fired on the last frame before the player crossed the edge
	is in flight for a round trip, and refusing that reads as the button being
	broken rather than as a rule.
]]
GameConfig.SellRangeTolerance = 10

-- Depth, in studs below SurfaceY, past which the HUD's return-to-surface button
-- lights up. Below this the player is already at the hub and the button would
-- do nothing.
GameConfig.SurfaceReturnMinDepth = 8

--[[
	Shop colours, pushed up to the saturation of the reference art: the stalls
	there are poster-bright, and a muted brown stall beside a bright UI reads as
	unfinished rather than as restrained.

	`pad` is only the fallback. Each shop's standing circle takes that shop's own
	accent instead (ShopLayout's `padColour`), the way the reference's yellow
	stall stands on a yellow circle -- so the circle says which shop it belongs
	to before you can read the sign.
]]
GameConfig.ShopPalette = {
	stripeA = Color3.fromRGB(224, 64, 64), -- awning red
	stripeB = Color3.fromRGB(248, 248, 244),
	wood = Color3.fromRGB(152, 106, 62),
	post = Color3.fromRGB(112, 86, 62),
	machineBody = Color3.fromRGB(42, 46, 74),
	machineTrim = Color3.fromRGB(78, 122, 214),
	machineGlow = Color3.fromRGB(96, 216, 255),
	pad = Color3.fromRGB(46, 190, 120), -- fallback only; see padColour above
	toolStripe = Color3.fromRGB(248, 180, 44), -- the tool shop's awning, against the sell stall's red

	-- Each stall carries a little of what it deals in, so you can tell them
	-- apart from across the plaza without reading the sign.
	ore = Color3.fromRGB(122, 130, 142), -- rough rock in the sell stall's crate
	coin = Color3.fromRGB(238, 196, 62), -- what it pays out, stacked on the counter
	pack = Color3.fromRGB(86, 118, 74), -- the tool shop's backpack canvas
	packTrim = Color3.fromRGB(58, 46, 36), -- its straps and buckles
	sack = Color3.fromRGB(178, 152, 104), -- burlap, so the sell stall's sacks are not more crates
}
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

	Wall and lawn are both checkerboards now, matched to reference art. The lawn
	used to be quantized noise so it would read as ground rather than as a tiled
	floor; the reference gives both surfaces the same regular grid, so that
	distinction is gone.
]]
GameConfig.WallHeight = 60 -- studs of checkered face standing above SurfaceY
GameConfig.WallThickness = 16 -- inward from the hub rim

--[[
	Wall face.

	A flat checkerboard and a grass coping, and nothing else. The plinth, string
	course, per-tile relief and pilasters that used to be here are gone: the
	reference walls are unbroken planes of fine check with a green lip on top,
	and every one of those details read as an interruption against it.

	WallHeight must stay a whole multiple of WallTileSize or the top row comes
	out a sliver. 10 into 60 gives 6 rows, which is about what the reference
	shows across a wall of this height.
]]
GameConfig.WallTileSize = 10 -- square checker tile; 60 / 10 = 6 rows
GameConfig.WallCapHeight = 7 -- the grass coping
GameConfig.WallCapOverhang = 3 -- oversails both faces and both ends, so corners close
GameConfig.WallFootingDepth = 1.5 -- skirt outside the rim, hiding the floor slab edge

-- The two checker steps, as indices into the shade palette. Far apart on
-- purpose: adjacent steps are a 7% difference and read as one flat colour at
-- any distance.
GameConfig.WallCheckerShades = { 0, 3 }

-- Warm tan, matched to the reference walls, and lighter than the brown it
-- replaced -- that one was pushed hard to survive being read in shadow. The
-- 1.45 saturation multiplier still applies, so this lands around 222,157,92
-- rather than the orange that a naively "tan-looking" pick turns into.
GameConfig.WallColor = Color3.fromRGB(198, 158, 118)

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
GameConfig.PaletteShadeRange = 0.2

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
GameConfig.CartoonSaturation = 1.62
GameConfig.CartoonValueBoost = 1.2

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

	Rows, not studs: 2 rows at BlockSize 6 is the top 12 studs.
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

--[[
	Material used for any Uncommon-or-better ore block, unless the ore declares
	its own.

	This was Metal, which was the wrong instinct: Metal is dark and mirror-like,
	so a valuable block read as a *dim* block that happened to catch a highlight.
	The flat body plus glowing flecks below is what makes ore pop -- the colour
	does the work, and nothing about the body fights it.
]]
GameConfig.OreMaterial = Enum.Material.SmoothPlastic

--[[
	Mine block bodies.

	Every layer used to carry its own granular material -- Sand, Cobblestone,
	Pebble, Ice, Sandstone, Marble. Roblox lights those for realism, which is
	exactly the grey-ward drag `cartoonify` exists to fight, so the two were
	pulling against each other and the material was winning.

	Flat instead, and let colour carry the layer's identity. This is the same
	move the hub floor and the retaining wall already made, and the reason the
	surface reads as illustrated while the mine did not. Surface detail is not
	lost: it comes from the raised pixel tiles below, which is what DESIGN.md 2a
	asks for anyway.
]]
GameConfig.MineBlockMaterial = Enum.Material.SmoothPlastic

--[[
	Ore flecks.

	An ore block's raised tiles are Neon in a brightened version of the ore's own
	colour, so a vein glows from inside its rock rather than being a differently
	coloured cube. With Bloom's threshold at 1.2 these halo, which is what
	catches the eye from down the shaft.

	Neon on the *tiles*, never on the body: Neon has no intensity control, and a
	whole Neon block washes to white and turns everything in front of it into a
	black silhouette. That has already cost this project one rebuild -- glow
	belongs on the small foreground feature.
]]
GameConfig.OrePixelTiles = 4
GameConfig.OreFleckBrighten = 0.35

-- ==========================================================================
-- Swing animation and block health bar
-- ==========================================================================

-- Length of one procedural pickaxe swing, in seconds. Clamped at runtime to
-- stay under the equipped pickaxe's cooldown so swings never overlap; at the
-- fastest tier the swing compresses rather than being dropped. 0.34 leaves the
-- starter pickaxe (a 0.4s cooldown) a short beat at rest between swings.
GameConfig.SwingAnimSeconds = 0.34

-- Phase boundaries within that swing, as fractions: wind up, then strike, then
-- rebound. The strike is deliberately the shortest -- it is the only part meant
-- to look fast -- and StrikeEnd is also the instant the head lands, so hit
-- feedback is timed off it rather than off the server's reply.
GameConfig.SwingAnimWindupEnd = 0.34
GameConfig.SwingAnimStrikeEnd = 0.52

-- The rebound after contact, as a damped cosine over the remaining time. Decay
-- is how hard it settles; cycles counts half-turns, so 1.5 lands exactly at
-- rest after one visible bounce back past it. Raise decay for a deader,
-- heavier pickaxe, lower it for a springier one.
GameConfig.SwingAnimReboundDecay = 3.4
GameConfig.SwingAnimReboundCycles = 1.5

-- Where the pickaxe sits in the hand before any animation is layered on.
GameConfig.SwingAnimBaseGrip = CFrame.new(0, -0.8, 0)

--[[
	Wrist. The Grip runs the same swing curve this far behind the arm, so the
	head trails the hand through the arc and whips past it afterwards instead of
	moving rigidly with it.

	A fraction of the swing, not seconds, so it scales with pickaxe speed. Keep
	it well under StrikeEnd - WindupEnd (0.18): at a lag that size the head is
	still fully wound back on the frame the arm reaches the block, which reads
	as a broken weld rather than as follow-through. At 0.05 the head is roughly
	neutral at contact and peaks a moment after -- 33 degrees of trail, about a
	frame of delay. Peak angles below are in degrees.
]]
GameConfig.SwingAnimWristLag = 0.05
GameConfig.SwingAnimGripPitch = 34
GameConfig.SwingAnimGripRoll = 12

-- Idle sway between swings: degrees, and radians per second. Small enough to
-- read as breathing rather than as a second animation.
GameConfig.SwingAnimIdleSway = 2.5
GameConfig.SwingAnimIdleRate = 1.7

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

--[[
	Ore units granted per broken block, before backpack capacity is applied.

	Exactly one. It was 1-2 until swing speed went up by half. Left alone, that
	change raised ore per minute by the same half and pulled every §7 milestone
	in with it -- first rebirth modelled at 0.59x of its target. Blocks now break
	about 1.5x as fast and pay 1/1.5 as much, so ore per minute, and the pacing
	that hangs off it, is where it was while the mining itself is quicker.

	Raise Max to hand out more ore per block; BALANCE.md's milestone table is
	where to see what that costs.
]]
GameConfig.OreYieldMin = 1
GameConfig.OreYieldMax = 1

-- ==========================================================================
-- Critical hits
-- ==========================================================================

--[[
	Each accepted swing has CritChance of landing as a critical hit, which
	multiplies its damage by CritMultiplier. Rolled on the server; the client is
	only told the outcome so it can show it.

	These are here for feel rather than for power. Every swing otherwise does
	exactly the same thing, and a number that sometimes jumps is what makes
	holding the button down worth watching. Expected damage rises by
	CritChance * (CritMultiplier - 1) -- 10% at these values -- and BalanceModel
	charges mining time with that folded in.
]]
GameConfig.CritChance = 0.1
GameConfig.CritMultiplier = 2

-- Floating damage numbers above a struck block: seconds on screen, and studs
-- risen over that time. The pool is how many can be alive at once before the
-- oldest is recycled; the fastest pickaxe keeps about three in the air.
GameConfig.HitNumberSeconds = 0.55
GameConfig.HitNumberRise = 3
GameConfig.HitNumberPool = 8

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

-- How early a swing may arrive against its cooldown and still land, in
-- seconds. Absorbs network jitter. MiningService repays it out of the next
-- swing's cooldown, so it buys a burst and never a faster sustained rate. An
-- absolute time rather than a fraction of the cooldown, because jitter does not
-- shrink when the pickaxe gets faster.
GameConfig.SwingJitterSlackSeconds = 0.1

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

-- Podiums a new player has, and the most anyone can own. Ten is the whole
-- showroom: PodiumLayout below places exactly MaxPlotSlots of them, so raising
-- this means adding entries there, not just changing the number.
GameConfig.StartingPlotSlots = 4
GameConfig.MaxPlotSlots = 10

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
--[[
	Where each plot sits, and which way it faces.

	A plot's open side is its local +Z, so `yaw` is what points that side
	somewhere: 0 faces north up the map toward the shaft, +90 faces east, -90
	west. The two end plots are turned inward, which makes the row a shallow U
	opening onto the walk north -- every plot's podiums face the courtyard
	instead of two of them presenting a side wall to it.

	Explicit coordinates rather than origin-plus-spacing: once two of the four
	are rotated, the footprints stop being interchangeable (a turned plot is
	PlotDepth wide and PlotWidth deep) and a single pitch cannot express the
	arrangement.

	The two turned plots are the arms, standing forward to flank the entrance;
	the unturned pair sits behind them. The four are separated in Z as well as
	X, so no two share a band of the map -- each reads as its own building.

	Getting that separation cost the back pair its proximity, and there was no
	way around it. The arms can only come forward as far as the shoulder wall
	allows (HubPlotZMax, capped by the shaft lip -- see its note), which was 7
	studs of the 24 they overlapped by. The remaining 17 had to come from the
	back pair moving south, which is why they are now ~116 studs off the lip
	while the arms are 28.

	Footprints at PlotWidth 80 / PlotDepth 56 (including roof overhang):
	  1  x -162..-102  z  -83..   1   (turned, opens east)
	  2  x  -90..  -6  z -148.. -86
	  3  x    6..  90  z -148.. -86
	  4  x  102.. 162  z  -83..   1   (turned, opens west)
	4-stud gap between the arms and the back pair; 12-stud gaps across the middle.
]]
GameConfig.PlotLayout = {
	{ position = Vector3.new(-132, 0, -41), yaw = 90 },
	{ position = Vector3.new(-48, 0, -118), yaw = 0 },
	{ position = Vector3.new(48, 0, -118), yaw = 0 },
	{ position = Vector3.new(132, 0, -41), yaw = -90 },
}

GameConfig.PlotCount = #GameConfig.PlotLayout

--[[
	Leaderboards: a row along Z on the west side of the stem, turned to face
	east across it.

	They used to stand on the walk between the plots and the shaft, facing back
	down it -- which put two 38x26 slabs directly across the one sightline that
	should always be clear, the one that tells you where the mine is. Standing
	them side-on keeps them readable on the way past without their being the
	thing you have to walk around.

	X -72 puts them against the stem's west wall (walkable edge -104). Z moved
	40 -> 60 when HubPlotZMax was pushed north to 0: at 40 the nearer board
	reached z -1, which after that move was inside the gateway rather than past
	it, so it stood in the doorway.
]]
--[[
	One board on each side of the shaft, facing each other across it.

	They used to stand in a row down the west corridor, which meant walking one
	side of the mine showed you both and the other side showed you neither -- and
	it left the east corridor with nothing in it at all. Split, each corridor has
	a landmark, and whichever way you walk round the shaft you pass one.

	Z 70 is level with the middle of the shaft (its lips are 29 and 131), so a
	38-wide board sits between 51 and 89 with room either end. X +-72 puts each
	against its own wall, whose inner face is at +-104.

	Yaw turns the cabinet's face inward. A board's SurfaceGui is on its Front,
	which points down local -Z, so -90 aims it at +X and +90 at -X.
]]
GameConfig.LeaderboardPlacements = {
	coins = { position = Vector3.new(-72, 0, 70), yaw = -90, accent = Color3.fromRGB(96, 232, 138) },
	rebirths = { position = Vector3.new(72, 0, 70), yaw = 90, accent = Color3.fromRGB(186, 62, 214) },
}

--[[
	The dressing round each board: a paved standing area in front, a planter at
	each front corner, a conifer set back at each end, and two lamp bollards
	marking where you stand to read it.

	Arranged rather than scattered. The random pass deliberately keeps well clear
	of the boards, and loosening it would have put a tree in front of the face --
	the one place nothing may stand. So the surround is placed in the board's own
	local frame, symmetric about it, with everything either beside the cabinet or
	low enough to see over.

	The lamp heads take the board's own accent, which is what ties the dressing to
	the board rather than making it more lawn.
]]
GameConfig.BoardSurroundLampSpread = 13

-- Height of the board's *centre*. Raised 14 -> 21 when the boards were given
-- legs: at 14 the bottom edge sat a stud off the grass, so there was nowhere for
-- a post to go and the slab read as floating.
GameConfig.LeaderboardHeight = 21

--[[
	Leaderboard cabinet, in studs. The face is what the SurfaceGui draws on; the
	frame is the heavy outline DESIGN.md 2b asks for, built as geometry because
	this is a world object and 2a wants detail from parts rather than texture.
]]
GameConfig.LeaderboardFaceWidth = 38
GameConfig.LeaderboardFaceHeight = 24
GameConfig.LeaderboardFrame = 2.2
GameConfig.LeaderboardPostHeight = 9

--[[
	Board colours, matching the UI's palette in Theme.luau.

	Duplicated rather than shared because Theme lives in StarterPlayerScripts and
	a server script cannot require it. Keep the two in step by hand: these are
	the same values, and a board that drifts off-palette is the one thing in the
	hub that would look like a different game.
]]
GameConfig.BoardPalette = {
	panel = Color3.fromRGB(40, 33, 66),
	panelRaised = Color3.fromRGB(54, 45, 84),
	panelSunken = Color3.fromRGB(28, 23, 48),
	border = Color3.fromRGB(10, 8, 20),
	post = Color3.fromRGB(30, 25, 46),
	text = Color3.fromRGB(244, 242, 255),
	textDim = Color3.fromRGB(166, 158, 196),
	coins = Color3.fromRGB(255, 208, 56),
}

-- Rank badges. Beyond third everyone gets `other`, which is the point of a
-- podium: three colours, then the field.
GameConfig.BoardRankColors = {
	Color3.fromRGB(255, 208, 56),
	Color3.fromRGB(206, 214, 226),
	Color3.fromRGB(214, 140, 72),
}
GameConfig.BoardRankOther = Color3.fromRGB(84, 74, 118)
--[[
	Plot size is set by what the showroom has to hold. PodiumLayout puts a stage
	of four across the back and three podiums down each side wall, and its
	numbers are held off these two: shrink the plot and the wall podiums meet
	the corner pillars before anything else gives.

	80 x 56 was sized for the 6 x 4 grid of 24 podiums this replaced. It is kept
	because the hub's clearances, the plaza and the retaining wall are all
	measured off this footprint -- the room simply has more open floor in it.
]]
GameConfig.PlotWidth = 80
GameConfig.PlotDepth = 56

--[[
	A plot is a mining-base pavilion, not a walled shed.

	Restyled off the "MINING BASE" reference: a charcoal frame of pillars under
	a deep overhanging roof, glazed side bays either side of an open entrance,
	a lit rarity display wall at the back, recessed ceiling panels, and an
	arched name header carrying a crossed-hammer emblem.

	What this replaced was three solid stone walls. Those read as a bunker from
	outside and hid the podium grid until you had walked in, which is backwards
	for the one structure whose whole job is to show off what you own. Glass on
	the sides and the front bays is the change that matters; everything else
	here is trim on top of it.
]]
GameConfig.PlotWallHeight = 22
GameConfig.PlotWallThickness = 2
GameConfig.PlotRoofThickness = 4
GameConfig.PlotRoofOverhang = 2 -- roof oversails the walls; above head height, so it costs no floor
GameConfig.PlotPillarSize = 6 -- square corner pillars, inset to sit flush in plan
GameConfig.PlotFasciaHeight = 5 -- band under the front roof edge, carrying the header

--[[
	The two facade pillars that split the front into two glazed bays and a
	central opening.

	Offset is from the plot centre. At 18 the bays are 18 wide and the entrance
	36, which is the reference's rhythm. They are shallow in Z and pushed to the
	front edge deliberately, so the floor behind them stays clear: the front
	pair of wall podiums stands in the bay between each of these and its corner
	pillar.
]]
GameConfig.PlotFrontPillarOffsetX = 18
GameConfig.PlotFrontPillarWidth = 6
GameConfig.PlotFrontPillarDepth = 6

--[[
	Glazing. A solid dado carries the glass up off the slab -- glass landing on
	the floor reads as a hole, not a window -- and a head rail closes it under
	the roof. Panes are divided across the run, never stepped-and-clamped; the
	sliver-tile trap the hub floor, wall and path each fell into applies just as
	much to a wall of windows.
]]
GameConfig.PlotGlassDadoHeight = 3
GameConfig.PlotGlassHeadHeight = 2
GameConfig.PlotGlassPanesPerSide = 4
GameConfig.PlotMullionWidth = 1.2
GameConfig.PlotGlassTransparency = 0.62
GameConfig.PlotGlassReflectance = 0.12

--[[
	Recessed ceiling panels, in a grid rather than the old four long strips.
	Neon only glows, it does not light anything, and the roof cuts the skylight,
	so every Nth panel carries a real PointLight. Kept at two per plot: four
	plots times a lamp per panel would be 32 lights on a budget the hub already
	fought for.
]]
GameConfig.PlotCeilingPanelCols = 4
GameConfig.PlotCeilingPanelRows = 2
GameConfig.PlotCeilingLampEvery = 3
GameConfig.PlotLampRange = 44
GameConfig.PlotLampBrightness = 1.8

--[[
	Rarity display cases along the back wall, filled from Rarity.ORDER so the
	colours are the same ones every UI surface uses. Five, not six: the
	reference shows a five-case run, and Mythic reads better as the thing the
	cases do not promise you.

	They hang on the back wall above the display counter, behind the stage, so
	they cost no floor.
]]
GameConfig.PlotDisplayCases = 5
GameConfig.PlotDisplayCaseSize = Vector3.new(13, 9, 3)
-- Centre height. The cases span 8 to 17; a brainrot on the stage tops out at 10
-- (stage 1 + podium 3 + BrainrotHeight 6), so most of each case shows over it.
GameConfig.PlotDisplayCaseY = 12.5

--[[
	The arched header over the entrance. The project ships no meshes, so a curve
	is a stack of blocks: PlotArchSteps blocks across the parapet, each rising to
	a sine hump PlotArchRise tall. Thirteen reads as an arch; below about seven it
	reads as a staircase.
]]
GameConfig.PlotArchSteps = 13
GameConfig.PlotArchRise = 6
GameConfig.PlotParapetWidth = 48
GameConfig.PlotParapetHeight = 12

-- Kerb apron across the plot front. Stands proud of the floor rather than flush
-- so it reads as a step up onto the forecourt from the lawn.
GameConfig.PlotKerbDepth = 4
GameConfig.PlotKerbRaise = 0.5

-- Free-standing forecourt sign, this far proud of the plot's front edge. Small
-- enough not to disturb the row's clearances, which are measured off PlotDepth.
GameConfig.PlotStreetSignForward = 5

--[[
	Palette. Raw Color3 rather than the hub's cartoonify pipeline: these are
	already muted blue-greys and a 1.45 saturation multiplier turns the charcoal
	lilac.

	`light` used to be gold. The reference's ceiling panels and pillar strips are
	white, and gold ones washed the whole interior warm.
]]
GameConfig.PlotPalette = {
	frame = Color3.fromRGB(52, 58, 70), -- pillars, roof, fascia: the charcoal shell
	frameDark = Color3.fromRGB(34, 39, 49), -- recesses, the display wall, sign faces
	mullion = Color3.fromRGB(92, 101, 116), -- glazing bars between panes
	glass = Color3.fromRGB(150, 196, 228),
	accentMetal = Color3.fromRGB(214, 221, 230),
	light = Color3.fromRGB(252, 253, 255), -- the emissive panels themselves
	lamp = Color3.fromRGB(255, 250, 240), -- what those panels cast: warm white
	floor = Color3.fromRGB(198, 202, 209),
	kerb = Color3.fromRGB(166, 173, 182),
	sign = Color3.fromRGB(30, 35, 45),
	podium = Color3.fromRGB(112, 124, 144),
}
--[[
	Plot floor. Raised a hair above SurfaceY rather than laid flush: the lawn
	tiles run underneath the whole plot, and a flush slab put 42 of them
	coplanar with it, which z-fought as green streaks through the floor. Same
	fix the path used to have, and the same trap the wall footing fell into.
]]
GameConfig.PlotFloorThickness = 4
GameConfig.PlotFloorRaise = 0.06

--[[
	Podiums: ten, arranged as a showroom rather than a grid.

	Four stand on a low stage across the back, under the rarity cases and facing
	the entrance. Three more run down each side wall, turned to face in across
	the room. The middle of the floor is left open, with a runner from the door
	to the stage, so walking in puts everything you own around you instead of in
	rows you have to walk between.

	The order here is the order slots unlock in, chosen so the room is symmetric
	at every size: the four starting slots are the stage, and each one bought
	after that alternates left wall, right wall, working from the stage toward
	the door.

	`position` is the podium's centre on the plot floor in the plot's own frame,
	where +Z is the open side. `yaw` turns its front, and a brainrot faces the
	way its podium does. `stage` stands it on the dais.

	The numbers are held off the built plot, not picked by eye. Wall podiums at
	x 29 put the plinth's outer edge at 33.5, half a stud inside the corner
	pillars (34) and 4.5 off the glazing; the front pair end at z 24.5, a stud
	and a half short of the front bays' glass.
]]
GameConfig.PodiumLayout = table.freeze({
	{ position = Vector3.new(-19.5, 0, -14.5), yaw = 0, stage = true },
	{ position = Vector3.new(-6.5, 0, -14.5), yaw = 0, stage = true },
	{ position = Vector3.new(6.5, 0, -14.5), yaw = 0, stage = true },
	{ position = Vector3.new(19.5, 0, -14.5), yaw = 0, stage = true },
	{ position = Vector3.new(-29, 0, -1), yaw = 90, stage = false },
	{ position = Vector3.new(29, 0, -1), yaw = -90, stage = false },
	{ position = Vector3.new(-29, 0, 9.5), yaw = 90, stage = false },
	{ position = Vector3.new(29, 0, 9.5), yaw = -90, stage = false },
	{ position = Vector3.new(-29, 0, 20), yaw = 90, stage = false },
	{ position = Vector3.new(29, 0, 20), yaw = -90, stage = false },
})
assert(#GameConfig.PodiumLayout == GameConfig.MaxPlotSlots, "GameConfig: PodiumLayout must place exactly MaxPlotSlots podiums")

-- A podium's envelope: X and Z are the cap a brainrot stands on, Y is the height
-- of that standing surface above whatever the podium is built on. The plinth
-- under it is PodiumPlinthOverhang wider on every side.
GameConfig.PodiumSize = Vector3.new(8, 3, 8)
GameConfig.PodiumPlinthOverhang = 0.5

-- The stage under the back row: how wide it is, how high, and the plot-frame Z
-- of its front edge. Its back runs under the display counter. One stud is a
-- step a character walks straight up.
GameConfig.PodiumStageWidth = 54
GameConfig.PodiumStageHeight = 1
GameConfig.PodiumStageFrontZ = -7

-- Width of the runner from the entrance to the stage. Narrower than the
-- 36-stud doorway on purpose, so it reads as a path through it.
GameConfig.PodiumRunnerWidth = 14

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
-- Index bonus
-- ==========================================================================
--[[
	The collection log pays. Every character discovered adds
	IndexBonusPerDiscovery to passive income, and finishing a whole rarity band
	adds that band's IndexSetBonus on top. The parts sum into one bonus that
	multiplies income alongside the rebirth multiplier; see IndexBonus.luau. It
	survives rebirth, because the index does.

	Without it the Index was a list with a percentage on it. A new character
	mattered only if it out-earned whatever was already on a podium, so a
	first-ever Common and a fifth duplicate of it were the same event.

	Sized so the opening hour barely moves and the long game has something to
	chase: a dozen early discoveries and the Common set come to about +17%,
	while the whole index is +151% -- more than four rebirths' worth, behind the
	two rarest bands, which between them are under half a percent of rolls.
]]
GameConfig.IndexBonusPerDiscovery = 0.01
GameConfig.IndexSetBonus = table.freeze({
	Common = 0.05,
	Uncommon = 0.08,
	Rare = 0.12,
	Epic = 0.2,
	Legendary = 0.3,
	Mythic = 0.5,
})

-- ==========================================================================
-- Daily rewards
-- ==========================================================================
--[[
	One reward per UTC day, claimed from the Daily screen. Consecutive days walk
	down this list; the day after the last entry starts it again, and missing a
	whole day sends the streak back to the first. The rules are in
	Shared/Modules/DailyReward.

	Each day pays whichever is larger: the flat `coins`, or `incomeMinutes` of
	the player's passive income as it stands when they claim. The flat amount is
	what a new player gets -- day 1 is a little under two starter backpacks of
	ore -- and the income half is what stops the reward meaning nothing once
	they are earning thousands a second.

	Minutes, not hours, on purpose. Offline earnings already pay for the time
	away; this pays for coming back, and it should not be the bigger of the two.
]]
GameConfig.DailyRewards = table.freeze({
	table.freeze({ coins = 250, incomeMinutes = 5 }),
	table.freeze({ coins = 500, incomeMinutes = 8 }),
	table.freeze({ coins = 1000, incomeMinutes = 10 }),
	table.freeze({ coins = 2000, incomeMinutes = 15 }),
	table.freeze({ coins = 4000, incomeMinutes = 20 }),
	table.freeze({ coins = 7500, incomeMinutes = 30 }),
	table.freeze({ coins = 15000, incomeMinutes = 60 }),
})

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
-- Swing speed runs linearly from Base at tier 1 to Max at the last tier. These
-- set how busy mining feels: at 1.6 the starter pickaxe took 2.5s to break the
-- first block in the game, which is a long time to hold a button for one cube.
GameConfig.PickaxeBaseSwingsPerSecond = 2.5
GameConfig.PickaxeMaxSwingsPerSecond = 5
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
