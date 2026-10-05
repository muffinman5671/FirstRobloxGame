--!strict
--[[
	HubDecor
	Trees, rocks, bushes, flowers and crates on the grass around the mine.

	The three grass regions in the stem -- a corridor either side of the shaft
	and the apron behind it -- were bare tiled floor carrying nothing but the two
	leaderboards. This fills them.

	Geometry only, per DESIGN.md §2a: no meshes, no textures, no asset IDs. A
	tree is a stack of boxes at stepped shades, which is also what makes it read
	as cartoon rather than as a low-poly model that fell short.

	Not a service. MineService owns hub scenery and calls `build` from its own
	pass; this is here because MineService is already 2,200 lines and the
	scattering logic is self-contained.

	Placement is deterministic from GameConfig.DecorSeed. The world is shared, so
	two servers of the same place should not have different lawns, and a fixed
	layout is something a screenshot can be compared against.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local HubDecor = {}

type Region = { minX: number, maxX: number, minZ: number, maxZ: number }
type Obstacle = { minX: number, maxX: number, minZ: number, maxZ: number }

-- A prop reports the radius of ground it wants. Everything else -- spacing,
-- clearance from built things -- is measured out from that one number.
type Prop = { radius: number, tier: string, build: (Instance, Vector3, Random) -> () }

-- Mirrors an entry of GameConfig.LeaderboardPlacements. Declared so both the
-- keep-out pass and the surround builder read it as something typed rather than
-- as an unknown table.
type BoardPlacement = { position: Vector3, yaw: number, accent: Color3 }

-- Placement runs once per tier, large first. See GameConfig's decor block for
-- why: in one pool the small props take every contested spot.
local LARGE, SMALL = "large", "small"

local SURFACE = GameConfig.SurfaceY

-- ==========================================================================
-- Part helper
-- ==========================================================================

--[[
	`y` is the *bottom* of the box, measured from the lawn, because every prop
	here is described as a thing standing on the ground and converting each one
	to a centre by hand is how a tree ends up half sunk.
]]
local function box(
	parent: Instance,
	name: string,
	at: Vector3,
	size: Vector3,
	y: number,
	colour: Color3,
	yaw: number?
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Locked = true
	part.CanCollide = true
	part.Size = size
	part.Color = colour
	-- SmoothPlastic throughout: Enum.Material.Ground and friends drain part
	-- colour toward grey, which has cost this project a rebuild before.
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(at.X, SURFACE + y + size.Y / 2, at.Z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	part.Parent = parent
	return part
end

--[[
	The same thing in a rotated frame, for the board surrounds.

	`origin` sits on the lawn at the board's centre, yawed so local +X runs along
	the board's width and local -Z is the way it faces. Describing the dressing in
	that frame means one symmetric layout serves both boards, whichever way each
	is turned -- and there is no chance of the two drifting apart the way two
	hand-written world layouts would.
]]
local function localBox(
	parent: Instance,
	name: string,
	origin: CFrame,
	lx: number,
	lz: number,
	size: Vector3,
	y: number,
	colour: Color3,
	material: Enum.Material?
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Locked = true
	part.CanCollide = true
	part.Size = size
	part.Color = colour
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = origin * CFrame.new(lx, y + size.Y / 2, lz)
	part.Parent = parent
	return part
end

-- ==========================================================================
-- Props
-- ==========================================================================
--[[
	Each prop is a handful of boxes at stepped shades. Two things keep them from
	reading as a kit of identical objects: every stacked piece takes its own
	small random yaw, so no two silhouettes line up, and sizes carry a few studs
	of variation. Neither costs a part.
]]

local function jitterYaw(rng: Random, spread: number): number
	return (rng:NextNumber() - 0.5) * 2 * spread
end

local function conifer(parent: Instance, at: Vector3, rng: Random)
	local pal = GameConfig.DecorPalette
	local scale = 0.85 + rng:NextNumber() * 0.4

	box(parent, "Trunk", at, Vector3.new(2.4, 5 * scale, 2.4), 0, pal.bark, jitterYaw(rng, 20))
	box(parent, "Trunk", at, Vector3.new(1.9, 4 * scale, 1.9), 5 * scale, pal.barkDark, jitterYaw(rng, 20))

	-- Three skirts, each narrower and lighter than the one below. Overlapped
	-- rather than stacked edge to edge, so the steps read as a single tapered
	-- mass instead of three separate slabs.
	local skirts: { { width: number, height: number, colour: Color3 } } = {
		{ width = 11.5, height = 5.0, colour = pal.leafDeep },
		{ width = 8.5, height = 4.5, colour = pal.leafMid },
		{ width = 5.5, height = 4.0, colour = pal.leafLight },
	}
	local y = 7.5 * scale
	for _, skirt in skirts do
		local width = skirt.width * scale
		local height = skirt.height * scale
		box(parent, "Needles", at, Vector3.new(width, height, width), y, skirt.colour, jitterYaw(rng, 45))
		y += height * 0.72
	end
end

local function broadleaf(parent: Instance, at: Vector3, rng: Random)
	local pal = GameConfig.DecorPalette
	local scale = 0.85 + rng:NextNumber() * 0.35

	box(parent, "Trunk", at, Vector3.new(2.8, 7.5 * scale, 2.8), 0, pal.bark, jitterYaw(rng, 20))

	-- One big crown plus two smaller lobes pushed off centre, which is what
	-- stops a cube of leaves from looking like a cube of leaves.
	box(parent, "Canopy", at, Vector3.new(11 * scale, 7 * scale, 11 * scale), 6.5 * scale, pal.leafMid, jitterYaw(rng, 45))

	for _ = 1, 2 do
		local angle = rng:NextNumber() * math.pi * 2
		local reach = 3.4 * scale
		local lobe = at + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		local size = (5.5 + rng:NextNumber() * 2) * scale
		local colour = if rng:NextNumber() < 0.5 then pal.leafLight else pal.leafDeep
		box(parent, "Canopy", lobe, Vector3.new(size, size, size), (9 + rng:NextNumber() * 2) * scale, colour, jitterYaw(rng, 45))
	end
end

local function boulder(parent: Instance, at: Vector3, rng: Random)
	local pal = GameConfig.DecorPalette
	local shades = { pal.stone, pal.stoneDark, pal.stoneLight }

	for index = 1, 2 + rng:NextInteger(0, 1) do
		local size = 3.2 + rng:NextNumber() * 3.4
		local angle = rng:NextNumber() * math.pi * 2
		local reach = rng:NextNumber() * 2.6
		local spot = at + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)

		-- Sunk a third of the way in, so they sit *in* the ground rather than
		-- resting on it like dropped luggage.
		box(
			parent,
			"Boulder",
			spot,
			Vector3.new(size, size * 0.8, size * (0.8 + rng:NextNumber() * 0.4)),
			-size * 0.26,
			shades[(index - 1) % #shades + 1],
			jitterYaw(rng, 45)
		)
	end
end

local function bush(parent: Instance, at: Vector3, rng: Random)
	local pal = GameConfig.DecorPalette
	local shades = { pal.leafMid, pal.leafDeep, pal.leafLight }

	for index = 1, 2 + rng:NextInteger(0, 1) do
		local size = 2.8 + rng:NextNumber() * 2.2
		local angle = rng:NextNumber() * math.pi * 2
		local reach = rng:NextNumber() * 2
		local spot = at + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		box(
			parent,
			"Bush",
			spot,
			Vector3.new(size, size * 0.85, size),
			-0.4,
			shades[(index - 1) % #shades + 1],
			jitterYaw(rng, 45)
		)
	end
end

local function flowers(parent: Instance, at: Vector3, rng: Random)
	local pal = GameConfig.DecorPalette
	local heads = GameConfig.DecorFlowerColors

	-- A patch of turned soil under them, so the stems have somewhere to be
	-- rather than standing straight out of mown lawn.
	box(parent, "Bed", at, Vector3.new(6.5, 0.5, 6.5), -0.1, pal.soil, jitterYaw(rng, 45))

	for _ = 1, 3 + rng:NextInteger(0, 2) do
		local angle = rng:NextNumber() * math.pi * 2
		local reach = rng:NextNumber() * 2.3
		local spot = at + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		local height = 1.6 + rng:NextNumber() * 1.1

		box(parent, "Stem", spot, Vector3.new(0.45, height, 0.45), 0.3, pal.leafDeep)
		box(
			parent,
			"Bloom",
			spot,
			Vector3.new(1.5, 1.5, 1.5),
			0.3 + height,
			heads[rng:NextInteger(1, #heads)],
			jitterYaw(rng, 45)
		)
	end
end

local function crates(parent: Instance, at: Vector3, rng: Random)
	local pal = GameConfig.DecorPalette

	--[[
		Mining spoil, near enough the shaft to read as belonging to it.

		A crate is three parts: the box, a lighter lid proud of it, and a dark
		band round the middle. The band is what makes a brown cube look like a
		crate -- without it the stack is a stack of brown cubes.
	]]
	local y = 0
	for index = 1, 2 + rng:NextInteger(0, 1) do
		local size = 5.5 - (index - 1) * 0.9
		local angle = jitterYaw(rng, 25)
		local drift = (index - 1) * 0.9
		local spot = at + Vector3.new((rng:NextNumber() - 0.5) * drift, 0, (rng:NextNumber() - 0.5) * drift)

		box(parent, "Crate", spot, Vector3.new(size, size * 0.8, size), y, pal.crate, angle)
		box(parent, "CrateBand", spot, Vector3.new(size + 0.3, size * 0.16, size + 0.3), y + size * 0.32, pal.crateBand, angle)
		box(parent, "CrateLid", spot, Vector3.new(size * 0.92, size * 0.12, size * 0.92), y + size * 0.8, pal.crateDark, angle)

		y += size * 0.8 + 0.12
	end
end

--[[
	Dressing round a leaderboard.

	The scatter keeps well clear of the boards on purpose -- a tree in front of
	the face is the one thing that must never happen -- so the ground around each
	one was bare. This fills it deliberately instead: a paved standing area in
	front, a planter at each front corner, a conifer set back at each end, and two
	lamp bollards marking where you stand to read.

	Everything is either beside the cabinet or low enough to see over. The tallest
	thing in front is a 5.5-stud bollard against a board whose face starts at 9.

	Built before the scatter collects its keep-outs, so the random pass sees all
	of this as something to avoid and fills in around it.
]]
--[[
	The apron: everything in front of a board.

	A paved standing area, a planter of blooms at each front corner, two lamp
	bollards marking where you stand, and a conifer set back at each end to frame
	the cabinet without reaching across its face.

	Every offset is held off the cabinet by measurement, not by eye. The plinth
	runs to local z +-3.5 and the frame bars to local x +-(halfW + 2.2); a first
	pass put the mat 1.5 studs under the plinth, the planters 1.25 into it, and a
	conifer's bottom skirt 1.7 into the frame.
]]
local function boardApron(model: Instance, origin: CFrame, placement: BoardPlacement, halfW: number, rng: Random)
	local pal = GameConfig.DecorPalette
	local plaza = GameConfig.PlazaPalette
	local heads = GameConfig.DecorFlowerColors

	-- Raised clear of the lawn rather than laid flush: a coplanar slab z-fights
	-- with the floor tile under it, the trap the plaza, the plot floors and the
	-- wall footing each fell into first.
	local matDepth = 10
	local matZ = -9
	localBox(model, "Mat", origin, 0, matZ, Vector3.new(halfW * 1.4, 0.3, matDepth), 0.02, plaza.stone)
	localBox(model, "MatInlay", origin, 0, matZ, Vector3.new(halfW * 1.15, 0.2, matDepth - 3.4), 0.32, plaza.kerb)

	for _, side in { -1, 1 } do
		local px = side * (halfW + 5.5)
		localBox(model, "Planter", origin, px, -3, Vector3.new(5.5, 3.2, 7), 0, plaza.kerb)
		localBox(model, "PlanterSoil", origin, px, -3, Vector3.new(4.6, 0.5, 6.1), 3.2, pal.soil)

		for bloom = 1, 3 do
			local bx = px + (bloom - 2) * 1.5
			local bz = -3 + (rng:NextNumber() - 0.5) * 3.6
			local height = 1.4 + rng:NextNumber() * 0.8
			localBox(model, "Stem", origin, bx, bz, Vector3.new(0.4, height, 0.4), 3.7, pal.leafDeep)
			localBox(
				model,
				"Bloom",
				origin,
				bx,
				bz,
				Vector3.new(1.4, 1.4, 1.4),
				3.7 + height,
				heads[rng:NextInteger(1, #heads)]
			)
		end

		--[[
			Lamp bollards on the front corners of the mat. Neon heads in the
			board's own accent -- the thing that ties the dressing to the board
			rather than making it more lawn -- and Neon on a small head only,
			never on anything large.
		]]
		local lampX = side * GameConfig.BoardSurroundLampSpread
		localBox(model, "BollardPost", origin, lampX, -13, Vector3.new(1.8, 5.5, 1.8), 0, plaza.post)
		localBox(
			model,
			"BollardHead",
			origin,
			lampX,
			-13,
			Vector3.new(2.6, 2.6, 2.6),
			5.5,
			placement.accent,
			Enum.Material.Neon
		)

		local treeAt = origin * CFrame.new(side * (halfW + 14), 0, 2)
		conifer(model, Vector3.new(treeAt.Position.X, SURFACE, treeAt.Position.Z), rng)
	end
end

--[[
	The backdrop: everything between a board and the wall it stands against.

	Both boards back onto a retaining wall 32 studs behind them, and that strip
	was bare. What goes in it is chosen for what it does to the *silhouette*,
	because from anywhere in the corridor the board is read against this: a pair
	of banner poles carrying the board's accent and rising almost to its crown, a
	staggered line of conifers massing green behind the cabinet, and low bushes
	and boulders tucked along the foot of the wall.

	Depths are fractions of the gap to the wall rather than fixed studs, so the
	whole arrangement travels if a board is moved -- the same reasoning as the
	plaza lamps being placed off the plaza's own bounds.
]]
local function boardBackdrop(model: Instance, origin: CFrame, placement: BoardPlacement, halfW: number, rng: Random)
	-- Distance from the board's centre to the wall's inner face, behind it.
	local wallZ = GameConfig.HubMineHalfX - GameConfig.WallThickness - math.abs(placement.position.X)
	if wallZ < 20 then
		-- Nothing sensible fits. Better to place none than to grow a tree
		-- through the retaining wall.
		return
	end

	--[[
		Banner standards either side of the cabinet.

		Sized off a screenshot, not off paper. The first version was a 32-stud
		mast in the plaza's post colour, which is nearly black: against the sky it
		read as a bare spike taller than every tree, and it took the eye clean off
		the board it was supposed to be framing. Now it is a 20-stud timber pole
		-- shorter than the board's 33-stud face and about the height of the
		conifers behind it -- carrying a banner big enough to read as cloth.
	]]
	for _, side in { -1, 1 } do
		local px = side * (halfW + 3)
		local pz = wallZ * 0.19
		localBox(model, "BannerPole", origin, px, pz, Vector3.new(1.6, 20, 1.6), 0, GameConfig.DecorPalette.bark)
		localBox(model, "Banner", origin, px, pz, Vector3.new(8, 9, 0.6), 9, placement.accent)
		-- A small Neon cap, which is all the glow a pole should carry: Neon has no
		-- intensity control, so anything larger washes to white.
		localBox(
			model,
			"BannerFinial",
			origin,
			px,
			pz,
			Vector3.new(2.2, 2.2, 2.2),
			20,
			placement.accent,
			Enum.Material.Neon
		)
	end

	-- A staggered line rather than a row: three evenly spaced conifers read as
	-- planting, three in a straight line read as a fence.
	local treeZ = wallZ * 0.47
	for _, offset in { -21, 1, 22 } do
		local at = origin * CFrame.new(offset, 0, treeZ + (rng:NextNumber() - 0.5) * 2.4)
		conifer(model, Vector3.new(at.Position.X, SURFACE, at.Position.Z), rng)
	end

	-- Scrub along the foot of the wall, filling the gap under the treeline.
	local scrubZ = wallZ * 0.84
	for _, offset in { -30, -10, 10, 30 } do
		local at = origin * CFrame.new(offset + (rng:NextNumber() - 0.5) * 3, 0, scrubZ)
		bush(model, Vector3.new(at.Position.X, SURFACE, at.Position.Z), rng)
	end

	-- And a boulder at each far corner, so the treeline has somewhere to stop.
	for _, side in { -1, 1 } do
		local at = origin * CFrame.new(side * (halfW + 16), 0, wallZ * 0.66)
		boulder(model, Vector3.new(at.Position.X, SURFACE, at.Position.Z), rng)
	end
end

--[[
	Dressing round a leaderboard, front and back.

	The scatter keeps well clear of the boards on purpose -- a tree in front of
	the face is the one thing that must never happen -- so the ground around each
	one was bare. This fills it deliberately instead.

	Built before the scatter collects its keep-outs, so the random pass sees all
	of it as something to avoid and fills in around it.
]]
local function boardSurround(parent: Instance, placement: BoardPlacement, rng: Random)
	local origin = CFrame.new(placement.position.X, SURFACE, placement.position.Z)
		* CFrame.Angles(0, math.rad(placement.yaw), 0)
	local halfW = GameConfig.LeaderboardFaceWidth / 2

	local model = Instance.new("Model")
	model.Name = "Decor_boardSurround"
	model.Parent = parent

	boardApron(model, origin, placement, halfW, rng)
	boardBackdrop(model, origin, placement, halfW, rng)
end

local PROPS: { [string]: Prop } = {
	conifer = { radius = 7.0, tier = LARGE, build = conifer },
	broadleaf = { radius = 7.5, tier = LARGE, build = broadleaf },
	boulder = { radius = 5.5, tier = LARGE, build = boulder },
	crates = { radius = 5.5, tier = LARGE, build = crates },
	bush = { radius = 4.0, tier = SMALL, build = bush },
	flowers = { radius = 4.0, tier = SMALL, build = flowers },
}

-- ==========================================================================
-- Where things may stand
-- ==========================================================================

--[[
	World-space AABB of a part, done properly.

	`Position ± Size/2` is only the bounding box of an axis-aligned part, and two
	of the three shops are turned (yaw -18 and -72). The extent along each world
	axis is the sum of the three local half-extents projected onto it -- signs do
	not matter because they are all under an abs.

	For a keep-out test an AABB of a rotated part is a *superset* of the part, so
	it rejects slightly more ground than it strictly has to. That is the safe
	direction: the cost is a foot of unused lawn, not a tree inside a stall.
]]
local function boundsOf(part: BasePart): Obstacle
	local cf = part.CFrame
	local half = part.Size / 2
	local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector

	local ex = math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(look.X) * half.Z
	local ez = math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(look.Z) * half.Z
	local centre = cf.Position

	return { minX = centre.X - ex, maxX = centre.X + ex, minZ = centre.Z - ez, maxZ = centre.Z + ez }
end

--[[
	Everything already standing on the lawn that a prop must not touch.

	Read off the built parts rather than recomputed from config, so moving a
	stall moves the hole in the scatter with it. Only things reaching above the
	lawn count: the floor tiles are all top-at-SurfaceY and every prop overlaps
	one by definition, so including them would reject the entire world.
]]
local function collectObstacles(built: Instance): { Obstacle }
	local obstacles: { Obstacle } = {}

	for _, descendant in built:GetDescendants() do
		if descendant:IsA("BasePart") then
			local cf = descendant.CFrame
			local half = descendant.Size / 2
			local reach = math.abs(cf.RightVector.Y) * half.X
				+ math.abs(cf.UpVector.Y) * half.Y
				+ math.abs(cf.LookVector.Y) * half.Z

			if cf.Position.Y + reach > SURFACE + 0.2 then
				table.insert(obstacles, boundsOf(descendant))
			end
		end
	end

	--[[
		Two things on the lawn are built by services that start *after*
		MineService -- the leaderboards by LeaderboardService and the four bases
		by PlotService -- so they are not in `built` yet and have to be described
		from config instead.

		Both footprints are deliberately generous. A board is something you stand
		in front of and read, and a base is something you walk into; neither wants
		a tree against its face.
	]]
	--[[
		Both boards are yawed +-90, so their width lies along Z and their depth
		along X whichever side of the shaft they are on. Written out as the two
		half-extents rather than branching on the yaw, since a board that was not
		side-on would want a different footprint anyway.
	]]
	local standing = GameConfig.LeaderboardFaceWidth / 2 + 6
	local boards: { [string]: BoardPlacement } = GameConfig.LeaderboardPlacements
	for _, placement in boards do
		table.insert(obstacles, {
			minX = placement.position.X - 16,
			maxX = placement.position.X + 16,
			minZ = placement.position.Z - standing,
			maxZ = placement.position.Z + standing,
		})
	end

	--[[
		The plots. Two of the four are turned 90 degrees, which swaps which of
		width and depth lies along X -- the same reason a rotated part cannot be
		measured with Position +- Size/2.
	]]
	local approach = GameConfig.PlotKerbDepth + 6
	for _, plot in GameConfig.PlotLayout do
		local turned = math.abs(plot.yaw) == 90
		local halfX = (if turned then GameConfig.PlotDepth else GameConfig.PlotWidth) / 2 + approach
		local halfZ = (if turned then GameConfig.PlotWidth else GameConfig.PlotDepth) / 2 + approach
		table.insert(obstacles, {
			minX = plot.position.X - halfX,
			maxX = plot.position.X + halfX,
			minZ = plot.position.Z - halfZ,
			maxZ = plot.position.Z + halfZ,
		})
	end

	return obstacles
end

-- ==========================================================================
-- Scatter
-- ==========================================================================

--[[
	Weighted pick over DecorWeights.

	Sorted by key first: `pairs` order over a table is not stable between runs,
	and an unstable order would make the seed meaningless -- the same seed would
	lay out a different lawn on the next boot.
]]
local function weightedPicker(tier: string): (Random) -> string
	local weights: { [string]: number } = GameConfig.DecorWeights
	local names: { string } = {}
	for name in weights do
		local prop = PROPS[name]
		if prop and prop.tier == tier then
			table.insert(names, name)
		end
	end
	table.sort(names)

	local total = 0
	for _, name in names do
		total += weights[name]
	end

	return function(rng: Random): string
		local roll = rng:NextNumber() * total
		for _, name in names do
			roll -= weights[name]
			if roll <= 0 then
				return name
			end
		end
		return names[#names]
	end
end

--[[
	Scatters one region.

	A jittered grid rather than free random points: uniform random clumps, and
	the fix for clumping is a rejection loop whose cost is unbounded. A grid with
	jitter under half the pitch cannot clump, always terminates, and the gaps
	from skipped cells are what keep it from reading as an orchard.
]]
type Pass = { pitch: number, jitter: number, density: number, pick: (Random) -> string }

local function scatter(
	parent: Instance,
	region: Region,
	rng: Random,
	pass: Pass,
	obstacles: { Obstacle },
	placed: { { x: number, z: number, radius: number } }
): number
	local pitch = pass.pitch
	local jitter = pass.jitter
	local clearance = GameConfig.DecorClearance
	local spacing = GameConfig.DecorSpacing

	local sizeX, sizeZ = region.maxX - region.minX, region.maxZ - region.minZ
	if sizeX <= 0 or sizeZ <= 0 then
		return 0
	end

	-- Divide the span rather than stepping a fixed pitch and clamping the last
	-- column -- the trap that shipped three times on the floor and the wall.
	local cols = math.max(1, math.round(sizeX / pitch))
	local rows = math.max(1, math.round(sizeZ / pitch))
	local stepX, stepZ = sizeX / cols, sizeZ / rows

	local count = 0

	for ix = 0, cols - 1 do
		for iz = 0, rows - 1 do
			if rng:NextNumber() > pass.density then
				continue
			end

			local name = pass.pick(rng)
			local prop = PROPS[name]
			local x = region.minX + (ix + 0.5) * stepX + (rng:NextNumber() - 0.5) * 2 * jitter
			local z = region.minZ + (iz + 0.5) * stepZ + (rng:NextNumber() - 0.5) * 2 * jitter

			-- Jitter can push a prop past its region's edge; the region is
			-- already inset from the wall and the shaft, but its own footprint
			-- has to fit inside it too.
			if
				x - prop.radius < region.minX
				or x + prop.radius > region.maxX
				or z - prop.radius < region.minZ
				or z + prop.radius > region.maxZ
			then
				continue
			end

			local blocked = false

			local reach = prop.radius + clearance
			for _, obstacle in obstacles do
				if
					x + reach > obstacle.minX
					and x - reach < obstacle.maxX
					and z + reach > obstacle.minZ
					and z - reach < obstacle.maxZ
				then
					blocked = true
					break
				end
			end

			if not blocked then
				for _, other in placed do
					local gap = prop.radius + other.radius + spacing
					if (Vector2.new(x - other.x, z - other.z)).Magnitude < gap then
						blocked = true
						break
					end
				end
			end

			if not blocked then
				local model = Instance.new("Model")
				model.Name = `Decor_{name}`
				model.Parent = parent
				prop.build(model, Vector3.new(x, SURFACE, z), rng)

				table.insert(placed, { x = x, z = z, radius = prop.radius })
				count += 1
			end
		end
	end

	return count
end

-- ==========================================================================
-- Entry point
-- ==========================================================================

--[[
	Fills the grass around the mine and returns how many props landed.

	`built` is whatever already exists on the lawn -- MineService's hub folder --
	and is read for keep-outs, not written to. Props go into `parent`.
]]
--[[
	Fills the lawn and returns how many props landed.

	`built` is whatever already stands on the grass -- MineService's hub folder --
	and is read for keep-outs, not written to. `plaza` is the paved square's
	bounds, passed in rather than re-derived: MineService works them out from the
	plot row and the shaft lip, and a second copy of that derivation here would
	be a second thing to keep in step.

	Six regions, in two groups. Around the shaft: a corridor either side and the
	apron behind it -- the grass at the mine mouth, which is the part with
	nothing on it but the two boards. Around the bases: the outer lawn of the
	plot band, west, east and south of the plaza. It is one continuous lawn and
	the bare parts of it are contiguous, so decorating only the stem would have
	left the larger half untouched.
]]
function HubDecor.build(parent: Instance, built: Instance, plaza: Region): number
	local shaftHalf = (GameConfig.ShaftRadiusBlocks + 0.5) * GameConfig.BlockSize
	local cx, cz = GameConfig.ShaftCenterX, GameConfig.ShaftCenterZ
	local wallMargin = GameConfig.WallThickness + GameConfig.DecorWallMargin

	-- Walkable extents: each band's outer rim, less the wall, less a margin so
	-- nothing grows out of the wall's inner face.
	local stemInner = GameConfig.HubMineHalfX - wallMargin
	local bandInner = GameConfig.HubPlotHalfX - wallMargin
	local northRim = GameConfig.HubMineZMax - wallMargin
	local bandSouth = GameConfig.HubPlotZMin + wallMargin

	-- The shaft rim is walked, and it is a hole: a prop on it is a prop you fall
	-- past. Held off by its own margin on all four sides.
	local margin = GameConfig.DecorShaftMargin
	local southLip, northLip = cz - shaftHalf, cz + shaftHalf

	local regions: { Region } = {
		-- Around the mine: a corridor each side of the shaft, then the apron.
		{ minX = -stemInner, maxX = cx - shaftHalf - margin, minZ = southLip, maxZ = northLip },
		{ minX = cx + shaftHalf + margin, maxX = stemInner, minZ = southLip, maxZ = northLip },
		{ minX = -stemInner, maxX = stemInner, minZ = northLip + margin, maxZ = northRim },

		-- Around the bases: the lawn outside the paving, on three sides. The
		-- plots stand inside the west, east and south regions and are cut out of
		-- them by the keep-out list, not by the bounds.
		{ minX = -bandInner, maxX = plaza.minX, minZ = bandSouth, maxZ = GameConfig.HubPlotZMax },
		{ minX = plaza.maxX, maxX = bandInner, minZ = bandSouth, maxZ = GameConfig.HubPlotZMax },
		{ minX = plaza.minX, maxX = plaza.maxX, minZ = bandSouth, maxZ = plaza.minZ - 4 },
	}

	local rng = Random.new(GameConfig.DecorSeed)

	--[[
		Board dressing before anything else, and before the keep-outs are
		collected: `built` is the hub folder and `parent` sits inside it, so these
		land in the obstacle list on their own and the random pass fills in around
		them rather than through them.
	]]
	local boards: { [string]: BoardPlacement } = GameConfig.LeaderboardPlacements
	for _, placement in boards do
		boardSurround(parent, placement, rng)
	end

	local obstacles = collectObstacles(built)
	local placed: { { x: number, z: number, radius: number } } = {}

	local passes: { Pass } = {
		{
			pitch = GameConfig.DecorLargePitch,
			jitter = GameConfig.DecorLargeJitter,
			density = GameConfig.DecorLargeDensity,
			pick = weightedPicker(LARGE),
		},
		{
			pitch = GameConfig.DecorSmallPitch,
			jitter = GameConfig.DecorSmallJitter,
			density = GameConfig.DecorSmallDensity,
			pick = weightedPicker(SMALL),
		},
	}

	-- Both passes share `placed`, so the small props see the large ones and fill
	-- around them rather than through them.
	local total = 0
	for _, pass in passes do
		for _, region in regions do
			total += scatter(parent, region, rng, pass, obstacles, placed)
		end
	end

	-- Scattered props only. The board surrounds are placed, not scattered, and
	-- counting them here would hide the scatter falling to nothing.
	return total
end

return HubDecor
