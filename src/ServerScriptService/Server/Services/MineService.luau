--!strict
--[[
	MineService
	Owns the shaft: block state, chunk streaming, the part pool, and regrowth.

	Authority
	  Every block's oreId / hp / maxHp lives in a server-side dictionary keyed by
	  grid position. Parts carry a display-only `CrackStage` attribute that the
	  server writes and never reads back. Deleting or editing a part on a client
	  changes nothing -- the server's grid is the only truth.

	Storage
	  The full shaft is ~44,000 blocks, far too many to keep records for. Ore is
	  therefore *derived* from grid position by a seeded RNG, so an untouched
	  block costs zero memory and every server agrees on what's where. Only
	  blocks that have been damaged or broken get an entry:
	    damage[key] -- partial HP, survives streaming so walking away doesn't
	                   reset your progress on a block
	    broken[key] -- os.clock() at which it regrows

	Part count
	  Materializing every block in a streamed chunk would put ~10k parts in the
	  world. Instead only *exposed* blocks get a part: one with at least one
	  neighbour that is air, out of bounds, or broken. A solid untouched shaft
	  therefore costs one surface layer, and breaking a block reveals exactly the
	  neighbours that just became visible. This is the difference between hitting
	  the 60 FPS / 20 player target and not.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LayerConfig = require(ReplicatedStorage.Shared.Config.LayerConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local HubDecor = require(script.Parent.Parent.World.HubDecor)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

local MineService = {}
MineService.Name = "MineService"

local PANEL_PAD_TAG = GameConfig.PanelPadTag

local BLOCK = GameConfig.BlockSize
local CHUNK = GameConfig.ChunkBlocks
local RADIUS = GameConfig.ShaftRadiusBlocks
local MAX_GY = math.floor(LayerConfig.MAX_DEPTH / BLOCK) - 1

-- Chunk index range on the horizontal axes. The shaft is narrow, so this is a
-- handful of values and the streamer can iterate it exhaustively.
local MIN_C = math.floor(-RADIUS / CHUNK)
local MAX_C = math.floor(RADIUS / CHUNK)

export type ActiveBlock = {
	part: BasePart,
	oreId: string,
	hp: number,
	maxHp: number,
	layerIndex: number,
	gx: number,
	gy: number,
	gz: number,
}

-- Fired after a block is destroyed. (player, oreId, layerIndex, position)
MineService.BlockBroken = Signal.new()

local trove = Trove.new()

local mineFolder: Folder
local hubFolder: Folder
local hubSpawnPosition = Vector3.new(0, 4, 0)

local active: { [string]: ActiveBlock } = {}
local damage: { [string]: number } = {}
local broken: { [string]: number } = {}
local liveChunks: { [string]: boolean } = {}

local pool: { BasePart } = {}
local spawnTables: { [number]: { Rarity.WeightedEntry } } = {}
-- Common-only subset of each layer's table, used for the ore-free surface rows.
local fillerTables: { [number]: { Rarity.WeightedEntry } } = {}

-- ==========================================================================
-- Grid math
-- ==========================================================================

local function keyOf(gx: number, gy: number, gz: number): string
	return `{gx}:{gy}:{gz}`
end

local function chunkKeyOf(cx: number, cy: number, cz: number): string
	return `{cx}:{cy}:{cz}`
end

local function inBounds(gx: number, gy: number, gz: number): boolean
	return gx >= -RADIUS and gx <= RADIUS and gz >= -RADIUS and gz <= RADIUS and gy >= 0 and gy <= MAX_GY
end

local function blockCenter(gx: number, gy: number, gz: number): Vector3
	return Vector3.new(
		GameConfig.ShaftCenterX + gx * BLOCK,
		GameConfig.SurfaceY - gy * BLOCK - BLOCK * 0.5,
		GameConfig.ShaftCenterZ + gz * BLOCK
	)
end

-- Inverse of blockCenter. Clients send a block's centre, so rounding is exact;
-- a position that doesn't round onto a real block simply fails the lookup.
local function gridFromPosition(position: Vector3): (number, number, number)
	return math.round((position.X - GameConfig.ShaftCenterX) / BLOCK),
		math.round((GameConfig.SurfaceY - position.Y - BLOCK * 0.5) / BLOCK),
		math.round((position.Z - GameConfig.ShaftCenterZ) / BLOCK)
end

MineService.blockCenter = blockCenter
MineService.gridFromPosition = gridFromPosition
MineService.inBounds = inBounds

function MineService.depthOf(gy: number): number
	return gy * BLOCK + BLOCK * 0.5
end

function MineService.layerIndexAt(gy: number): number
	return LayerConfig.indexForDepth(MineService.depthOf(gy))
end

-- ==========================================================================
-- Ore derivation
-- ==========================================================================

--[[
	Ore is a pure function of grid position, so it needs no storage and is
	identical on every server. The multiply-and-wrap scrambles sequential grid
	keys, which would otherwise produce visibly banded ore if fed to Random.new
	directly.

	Note this uses the *ungated* spawn table. Rebirth-locked ore still generates
	in the world -- the world is shared, so it cannot vary per player -- and the
	gate is enforced at swing time by MiningService instead.
]]
local function oreIdFor(gx: number, gy: number, gz: number, layerIndex: number): string
	local packed = (gx + 4096) * 4194304 + (gy + 4096) * 8192 + (gz + 4096)
	local seed = packed * 2654435761 % 2147483647

	-- The top rows are filler rock only, so the surface reads as clean ground.
	local entries = if gy < GameConfig.OreFreeSurfaceRows and #fillerTables[layerIndex] > 0
		then fillerTables[layerIndex]
		else spawnTables[layerIndex]

	local picked = Rarity.roll(entries, Random.new(seed))
	return if picked then picked.id else entries[1].id
end

MineService.oreIdFor = oreIdFor

local function maxHpFor(oreId: string, layerIndex: number): number
	local ore = OreConfig.get(oreId)
	local layer = LayerConfig.get(layerIndex)
	if not ore or not layer then
		return GameConfig.BlockBaseHp
	end
	return math.max(1, math.floor(GameConfig.BlockBaseHp * layer.hpMultiplier * ore.hardness))
end

MineService.maxHpFor = maxHpFor

-- ==========================================================================
-- Solidity and exposure
-- ==========================================================================

local function isSolid(gx: number, gy: number, gz: number): boolean
	if not inBounds(gx, gy, gz) then
		return false
	end
	return broken[keyOf(gx, gy, gz)] == nil
end

local NEIGHBOURS = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

-- A block earns a part only if something adjacent to it is air. Fully buried
-- blocks still exist in the grid and can still be reached -- they materialize
-- the moment a neighbour breaks.
local function isExposed(gx: number, gy: number, gz: number): boolean
	for _, offset in NEIGHBOURS do
		if not isSolid(gx + offset.X, gy + offset.Y, gz + offset.Z) then
			return true
		end
	end
	return false
end

-- ==========================================================================
-- Part pool
-- ==========================================================================

local function createPart(): BasePart
	local part = Instance.new("Part")
	part.Size = Vector3.new(BLOCK, BLOCK, BLOCK)
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false -- nothing uses touch events; skip the physics cost
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = GameConfig.MineBlockMaterial
	return part
end

local function acquirePart(): BasePart
	local part = table.remove(pool)
	if part then
		return part
	end
	return createPart()
end

-- ==========================================================================
-- Pixel tiles
-- ==========================================================================

local patchPool: { BasePart } = {}

local function acquirePatch(): BasePart
	local patch = table.remove(patchPool)
	if patch then
		return patch
	end

	local part = Instance.new("Part")
	part.Name = "Pixel"
	part.Anchored = true
	part.CanCollide = false
	-- Critical: mining raycasts must pass through tiles and hit the block, or
	-- every swing would target a decoration that has no block state.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function releasePatches(part: BasePart)
	for _, child in part:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Pixel" then
			child.Parent = nil
			table.insert(patchPool, child)
		end
	end
end

local function releasePart(part: BasePart)
	releasePatches(part)
	part:SetAttribute("CrackStage", nil)
	part:SetAttribute("OreId", nil)
	part:SetAttribute("HpFraction", nil)
	part.Parent = nil
	table.insert(pool, part)
end

-- ==========================================================================
-- Materialize / dematerialize
-- ==========================================================================

--[[
	A layer reads as one substance, with rarer ore showing through as veins:

	  Common ore  -- the layer's own material and colour. This is the filler
	                 rock, so grass sits on exposed topsoil, slate below it,
	                 basalt deeper, and so on down to The Static.
	  Uncommon+   -- keeps the ore's own colour so it stands out against the
	                 filler, and its own material if it declares one.

	Recomputed rather than stored: a block's top face can become exposed later
	when the block above it breaks, and dirt should turn to grass when that
	happens.
]]
-- Which step of the layer's colour ramp this block sits on. Deterministic, and
-- scrambled with a different constant than the ore hash so shade and ore type
-- don't end up correlated (which would give the wall diagonal stripes).
local function shadeOf(gx: number, gy: number, gz: number): number
	local packed = (gx + 4096) * 4194304 + (gy + 4096) * 8192 + (gz + 4096)
	return packed * 40503 % 2147483647 % GameConfig.PaletteShades
end

--[[
	Pushes a colour toward flat illustrated paint before the palette is applied.

	Roblox lights and shades its materials for realism, which drags everything
	toward grey. Raising saturation and value counteracts that, and the value
	floor keeps the darkest layers reading as coloured rather than collapsing to
	black once the palette's lower steps are applied on top.
]]
local function cartoonify(base: Color3): Color3
	local h, s, v = base:ToHSV()
	return Color3.fromHSV(
		h,
		math.clamp(s * GameConfig.CartoonSaturation, 0, 1),
		math.clamp(math.max(v * GameConfig.CartoonValueBoost, GameConfig.CartoonMinValue), 0, 1)
	)
end

-- Snaps a colour onto one of PaletteShades discrete steps around the base.
-- Deliberately quantized: a continuous jitter would read as soft lighting,
-- which is the opposite of the flat, poster-like look.
local function quantize(base: Color3, shade: number): Color3
	local mid = (GameConfig.PaletteShades - 1) / 2
	if mid <= 0 then
		return base
	end

	local t = ((shade - mid) / mid) * GameConfig.PaletteShadeRange
	if t >= 0 then
		return base:Lerp(Color3.new(1, 1, 1), t)
	end
	return base:Lerp(Color3.new(0, 0, 0), -t)
end

local function crackStageFor(hp: number, maxHp: number): number
	if hp >= maxHp then
		return 0
	end
	return math.clamp(math.floor((1 - hp / maxHp) * GameConfig.CrackStages) + 1, 1, GameConfig.CrackStages)
end

-- Independent hash per (block, tile index) so tile placement doesn't correlate
-- with the block's own shade or its ore.
local function patchHash(gx: number, gy: number, gz: number, index: number): number
	local packed = (gx + 4096) * 4194304 + (gy + 4096) * 8192 + (gz + 4096)
	return (packed * 2246822519 + index * 374761393) % 2147483647
end

--[[
	Lays raised tiles on the block's exposed faces. Deterministic, so a block
	looks identical every time it streams in, and skipped entirely for faces
	buried in rock.
]]
--[[
	Raised tiles on the exposed faces.

	`look` describes the tiles rather than the block, because on an ore block
	they are not the same thing: the body is flat rock-coloured plastic and the
	tiles are Neon flecks of the ore. Passing the body's material and colour and
	deriving the rest here would have put that decision in two places.
]]
type PatchLook = { material: Enum.Material, colour: Color3, count: number, glow: boolean }

local function applyPatches(part: BasePart, gx: number, gy: number, gz: number, look: PatchLook)
	releasePatches(part)

	if look.count <= 0 then
		return
	end

	local exposed = {}
	for _, offset in NEIGHBOURS do
		if not isSolid(gx + offset.X, gy + offset.Y, gz + offset.Z) then
			table.insert(exposed, offset)
		end
	end
	if #exposed == 0 then
		return
	end

	local grid = GameConfig.PixelTileGrid
	local cell = BLOCK / grid
	local relief = GameConfig.PixelTileRelief
	local center = blockCenter(gx, gy, gz)

	local used: { [string]: boolean } = {}

	for index = 1, look.count do
		local h = patchHash(gx, gy, gz, index)
		local normal = exposed[(h % #exposed) + 1]

		-- Two in-face cell coordinates, from independent digits of the hash.
		local u = math.floor(h / 7) % grid
		local v = math.floor(h / 53) % grid

		local slot = `{normal.X},{normal.Y},{normal.Z}:{u},{v}`
		if not used[slot] then
			used[slot] = true

			-- Tangent axes: whichever two the face normal doesn't use.
			local tangentA = if normal.X ~= 0 then Vector3.yAxis else Vector3.xAxis
			local tangentB = if normal.Z ~= 0 then Vector3.yAxis else Vector3.zAxis
			if normal.Y ~= 0 then
				tangentA, tangentB = Vector3.xAxis, Vector3.zAxis
			end

			local offsetA = (u - (grid - 1) / 2) * cell
			local offsetB = (v - (grid - 1) / 2) * cell

			local patch = acquirePatch()
			patch.Size = tangentA * cell + tangentB * cell + Vector3.new(math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z)) * relief
			patch.Position = center
				+ normal * (BLOCK / 2 + relief / 2)
				+ tangentA * offsetA
				+ tangentB * offsetB
			patch.Material = look.material
			--[[
				A fleck is one flat colour, not a step on the block's ramp. Ramping
				a Neon colour does nothing useful -- Neon ignores shading, so the
				steps would be invisible -- and a vein reads better as one bright
				hue anyway.
			]]
			patch.Color = if look.glow
				then look.colour
				else quantize(
					look.colour,
					(shadeOf(gx, gy, gz) + GameConfig.PixelTileShadeOffset + index) % GameConfig.PaletteShades
				)
			patch.Parent = part
		end
	end
end

local function applyAppearance(
	part: BasePart,
	gx: number,
	gy: number,
	gz: number,
	oreId: string,
	layerIndex: number,
	crackStage: number,
	-- Tiles depend on which faces are exposed, which only changes when a
	-- neighbour breaks. Taking damage repaints the block but must not churn the
	-- tile pool on every single swing.
	rebuildTiles: boolean
)
	local layer = LayerConfig.get(layerIndex)
	local ore = OreConfig.get(oreId)
	if not layer then
		return
	end

	-- Grass caps only the top rows. Digging down exposes plenty of new top
	-- faces, and turning each one into a grass block puts lawn underground.
	local topExposed = not isSolid(gx, gy - 1, gz) and gy <= GameConfig.GrassMaxRow
	local isFiller = ore == nil or ore.rarity == "Common"

	local material, base, reflectance
	if isFiller then
		base = if topExposed and layer.topColor then layer.topColor else layer.baseColor
		-- Flat, not the layer's granular material: see GameConfig.MineBlockMaterial.
		-- Roblox shades a grained surface for realism, which is the same grey-ward
		-- drag `cartoonify` exists to undo, and the material was winning.
		material = GameConfig.MineBlockMaterial
		reflectance = 0
	else
		material = ore.material or GameConfig.OreMaterial
		base = ore.color
		reflectance = GameConfig.OreReflectance[ore.rarity] or 0
	end

	base = cartoonify(base)
	local color = quantize(base, shadeOf(gx, gy, gz))

	-- Damage reads on the block itself, not only in the HUD.
	if crackStage > 0 then
		color = color:Lerp(Color3.new(0, 0, 0), math.min(0.6, crackStage * GameConfig.CrackDarkenPerStage))
	end

	part.Material = material
	part.Color = color
	part.Reflectance = reflectance

	if rebuildTiles then
		--[[
			Ore gets more flecks and they glow; filler gets the usual couple in a
			neighbouring step of its own ramp.

			The fleck colour is the ore pushed toward white rather than the ore
			itself. Neon renders a colour at roughly its own brightness, so a deep
			ore -- Obsidian, Voidstone -- would glow dark, which is nothing. Lifted
			first, they all read as light.
		]]
		if isFiller then
			applyPatches(part, gx, gy, gz, {
				material = material,
				colour = base,
				count = GameConfig.PixelTilesPerBlock,
				glow = false,
			})
		else
			applyPatches(part, gx, gy, gz, {
				material = Enum.Material.Neon,
				colour = base:Lerp(Color3.new(1, 1, 1), GameConfig.OreFleckBrighten),
				count = GameConfig.OrePixelTiles,
				glow = true,
			})
		end
	end
end

local function materialize(gx: number, gy: number, gz: number): ActiveBlock?
	local key = keyOf(gx, gy, gz)
	if active[key] then
		return active[key]
	end
	if not isSolid(gx, gy, gz) or not isExposed(gx, gy, gz) then
		return nil
	end

	local layerIndex = MineService.layerIndexAt(gy)
	local oreId = oreIdFor(gx, gy, gz, layerIndex)
	local maxHp = maxHpFor(oreId, layerIndex)

	local part = acquirePart()
	part.Position = blockCenter(gx, gy, gz)
	part.Name = key

	local hp = damage[key] or maxHp
	local stage = crackStageFor(hp, maxHp)
	applyAppearance(part, gx, gy, gz, oreId, layerIndex, stage, true)

	-- Display only. The client reads these for the crack tint and the block
	-- health bar; the server never trusts them.
	part:SetAttribute("OreId", oreId)
	part:SetAttribute("CrackStage", stage)
	part:SetAttribute("HpFraction", hp / maxHp)

	part.Parent = mineFolder

	local block: ActiveBlock = {
		part = part,
		oreId = oreId,
		hp = hp,
		maxHp = maxHp,
		layerIndex = layerIndex,
		gx = gx,
		gy = gy,
		gz = gz,
	}
	active[key] = block
	return block
end

local function dematerialize(key: string)
	local block = active[key]
	if not block then
		return
	end

	-- Partial progress persists in `damage` so streaming out mid-swing doesn't
	-- silently heal the block.
	if block.hp < block.maxHp then
		damage[key] = block.hp
	end

	active[key] = nil
	releasePart(block.part)
end

-- ==========================================================================
-- Chunk streaming
-- ==========================================================================

-- Centre of the block span a chunk covers, used for the streaming distance test.
local function chunkCenter(cx: number, cy: number, cz: number): Vector3
	return Vector3.new(
		GameConfig.ShaftCenterX + (cx * CHUNK + (CHUNK - 1) * 0.5) * BLOCK,
		GameConfig.SurfaceY - (cy * CHUNK + (CHUNK - 1) * 0.5) * BLOCK - BLOCK * 0.5,
		GameConfig.ShaftCenterZ + (cz * CHUNK + (CHUNK - 1) * 0.5) * BLOCK
	)
end

local function forEachBlockInChunk(cx: number, cy: number, cz: number, fn: (number, number, number) -> ())
	for gx = cx * CHUNK, cx * CHUNK + CHUNK - 1 do
		for gy = cy * CHUNK, cy * CHUNK + CHUNK - 1 do
			for gz = cz * CHUNK, cz * CHUNK + CHUNK - 1 do
				if inBounds(gx, gy, gz) then
					fn(gx, gy, gz)
				end
			end
		end
	end
end

--[[
	Marks the chunk live and materializes whichever of its blocks are missing.

	Deliberately gap-filling rather than run-once: a pass that exhausts its
	budget partway through a chunk is finished by the next tick, so a chunk can
	never be left permanently half-built. materialize() is idempotent, so
	re-running over a complete chunk costs a table lookup per block.
]]
local function loadChunk(cx: number, cy: number, cz: number, budget: { n: number })
	liveChunks[chunkKeyOf(cx, cy, cz)] = true

	forEachBlockInChunk(cx, cy, cz, function(gx, gy, gz)
		if budget.n <= 0 then
			return
		end
		if not active[keyOf(gx, gy, gz)] and materialize(gx, gy, gz) then
			budget.n -= 1
		end
	end)
end

local function unloadChunk(cx: number, cy: number, cz: number)
	local key = chunkKeyOf(cx, cy, cz)
	if not liveChunks[key] then
		return
	end
	liveChunks[key] = nil

	forEachBlockInChunk(cx, cy, cz, function(gx, gy, gz)
		dematerialize(keyOf(gx, gy, gz))
	end)
end

local function playerPositions(): { Vector3 }
	local out: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(out, root.Position)
		end
	end
	return out
end

--[[
	Ground safety pass.

	Runs before the budgeted chunk load and ignores the budget: every solid,
	exposed block within SafeLoadRadius of a player materializes now. Without
	this, a player descending faster than the streamer can keep up walks onto a
	floor that doesn't exist yet and falls through the shaft.

	It deliberately materializes blocks whose chunk isn't "live" -- the chunk
	loader will adopt them on its next pass, and dematerialize() is keyed on the
	block, not the chunk, so nothing leaks.
]]
local function safetyPass(positions: { Vector3 })
	local reach = math.ceil(GameConfig.SafeLoadRadius / BLOCK)
	local radiusSq = GameConfig.SafeLoadRadius * GameConfig.SafeLoadRadius

	for _, position in positions do
		local px, py, pz = gridFromPosition(position)

		for gx = px - reach, px + reach do
			for gy = py - reach, py + reach do
				for gz = pz - reach, pz + reach do
					if inBounds(gx, gy, gz) and not active[keyOf(gx, gy, gz)] then
						if (blockCenter(gx, gy, gz) - position).Magnitude ^ 2 <= radiusSq then
							if materialize(gx, gy, gz) then
								-- Claim the chunk so the normal reclaim path
								-- owns these blocks; otherwise a safety block
								-- outside any live chunk would never be freed.
								liveChunks[chunkKeyOf(
									math.floor(gx / CHUNK),
									math.floor(gy / CHUNK),
									math.floor(gz / CHUNK)
								)] = true
							end
						end
					end
				end
			end
		end
	end
end

local function streamPass()
	local positions = playerPositions()

	-- Ground first, always. Everything below is best-effort.
	safetyPass(positions)

	if #positions == 0 then
		for key in liveChunks do
			local cx, cy, cz = string.match(key, "(-?%d+):(-?%d+):(-?%d+)")
			unloadChunk(tonumber(cx) :: number, tonumber(cy) :: number, tonumber(cz) :: number)
		end
		return
	end

	local wanted: { [string]: { number } } = {}
	local maxCy = math.floor(MAX_GY / CHUNK)
	local verticalReach = math.ceil(GameConfig.ChunkStreamRadius / (CHUNK * BLOCK))

	for _, position in positions do
		-- Only the vertical band near the player is worth testing; the shaft is
		-- narrow enough that both horizontal axes are iterated in full.
		local playerCy = math.floor((GameConfig.SurfaceY - position.Y) / (CHUNK * BLOCK))

		for cy = math.max(0, playerCy - verticalReach), math.min(maxCy, playerCy + verticalReach) do
			for cx = MIN_C, MAX_C do
				for cz = MIN_C, MAX_C do
					local key = chunkKeyOf(cx, cy, cz)
					if not wanted[key] then
						if (chunkCenter(cx, cy, cz) - position).Magnitude <= GameConfig.ChunkStreamRadius then
							wanted[key] = { cx, cy, cz }
						end
					end
				end
			end
		end
	end

	-- Reclaim on the wider radius, never on `wanted`, so a player pacing a
	-- chunk border can't thrash the pool.
	for key in liveChunks do
		if not wanted[key] then
			local sx, sy, sz = string.match(key, "(-?%d+):(-?%d+):(-?%d+)")
			local cx, cy, cz = tonumber(sx) :: number, tonumber(sy) :: number, tonumber(sz) :: number

			local center = chunkCenter(cx, cy, cz)
			local nearest = math.huge
			for _, position in positions do
				nearest = math.min(nearest, (center - position).Magnitude)
			end

			if nearest > GameConfig.ChunkReclaimRadius then
				unloadChunk(cx, cy, cz)
			end
		end
	end

	local budget = { n = GameConfig.MaxBlocksPerStreamTick }
	for _, coords in wanted do
		if budget.n <= 0 then
			break
		end
		loadChunk(coords[1], coords[2], coords[3], budget)
	end
end

-- ==========================================================================
-- Damage and regrowth
-- ==========================================================================

--[[
	Applies damage to the block at a world position.
	Returns (result, block) where result is one of:
	  "missing"  -- no such block, or it's already broken
	  "damaged"  -- still standing
	  "broken"   -- destroyed by this hit

	MiningService is the only caller; all validation happens there.
]]
function MineService.damageAt(position: Vector3, amount: number): (string, ActiveBlock?)
	local gx, gy, gz = gridFromPosition(position)
	if not inBounds(gx, gy, gz) then
		return "missing", nil
	end

	local key = keyOf(gx, gy, gz)
	local block = active[key]
	if not block or broken[key] then
		return "missing", nil
	end

	block.hp -= amount

	if block.hp > 0 then
		damage[key] = block.hp
		local stage = crackStageFor(block.hp, block.maxHp)
		block.part:SetAttribute("CrackStage", stage)
		block.part:SetAttribute("HpFraction", block.hp / block.maxHp)
		applyAppearance(block.part, gx, gy, gz, block.oreId, block.layerIndex, stage, false)
		return "damaged", block
	end

	-- Destroyed.
	broken[key] = os.clock() + GameConfig.BlockRegenSeconds
	damage[key] = nil
	active[key] = nil
	releasePart(block.part)

	-- Neighbours that were buried a moment ago may now be exposed. The one
	-- directly below may also already be active, in which case its top face is
	-- newly exposed and its appearance needs refreshing (dirt -> grass).
	for _, offset in NEIGHBOURS do
		local nx, ny, nz = gx + offset.X, gy + offset.Y, gz + offset.Z
		if isSolid(nx, ny, nz) then
			local existing = active[keyOf(nx, ny, nz)]
			if existing then
				applyAppearance(
					existing.part,
					nx,
					ny,
					nz,
					existing.oreId,
					existing.layerIndex,
					crackStageFor(existing.hp, existing.maxHp),
					true
				)
			else
				local chunkKey = chunkKeyOf(math.floor(nx / CHUNK), math.floor(ny / CHUNK), math.floor(nz / CHUNK))
				if liveChunks[chunkKey] then
					materialize(nx, ny, nz)
				end
			end
		end
	end

	return "broken", block
end

-- Returns the live block at a position without mutating it. Used for
-- validation and for the client's target readout.
function MineService.blockAt(position: Vector3): ActiveBlock?
	local gx, gy, gz = gridFromPosition(position)
	if not inBounds(gx, gy, gz) then
		return nil
	end
	return active[keyOf(gx, gy, gz)]
end

local function regrowPass()
	local now = os.clock()
	local due: { string } = {}

	for key, readyAt in broken do
		if now >= readyAt then
			table.insert(due, key)
		end
	end

	for _, key in due do
		broken[key] = nil

		local sx, sy, sz = string.match(key, "(-?%d+):(-?%d+):(-?%d+)")
		local gx, gy, gz = tonumber(sx) :: number, tonumber(sy) :: number, tonumber(sz) :: number

		local chunkKey = chunkKeyOf(math.floor(gx / CHUNK), math.floor(gy / CHUNK), math.floor(gz / CHUNK))
		if liveChunks[chunkKey] then
			materialize(gx, gy, gz)
		end
	end
end

-- ==========================================================================
-- World construction
-- ==========================================================================

-- The hub is the same substance as the mine's top row, so it takes layer 1's
-- grass colour rather than one of its own. Change it there and both follow.
local function grassBase(): Color3
	local surface = LayerConfig.get(1)
	return cartoonify((surface and surface.topColor) or Color3.fromRGB(102, 180, 62))
end

--[[
	Fills a rectangle with floor tiles at roughly HubTileSize, two shades
	alternating on a checkerboard.

	The rectangle's edges must land exactly where they were asked to -- the shaft
	opening is defined by the mine's block grid, and a pitch that missed would
	widen the hole or crowd it. Dividing the span into equal parts lands them
	exactly while leaving every tile identical; stepping a fixed pitch and
	clamping the last row also lands them, but leaves a sliver down two edges.

	Parity is per rectangle, off the column and row index. The five rectangles
	have their own pitches, so a world-coordinate parity would not stay in phase
	across them anyway, and the seams fall on the shaft lip where the check is
	interrupted regardless.
]]
local function tileFloor(name: string, minX: number, maxX: number, minZ: number, maxZ: number, base: Color3)
	local pitch = GameConfig.HubTileSize
	local thickness = GameConfig.HubThickness
	local shades = GameConfig.HubCheckerShades

	local sizeX, sizeZ = maxX - minX, maxZ - minZ
	if sizeX <= 0 or sizeZ <= 0 then
		return
	end

	local cols = math.max(1, math.round(sizeX / pitch))
	local rows = math.max(1, math.round(sizeZ / pitch))
	local stepX, stepZ = sizeX / cols, sizeZ / rows

	for ix = 0, cols - 1 do
		local x0 = minX + ix * stepX

		for iz = 0, rows - 1 do
			local z0 = minZ + iz * stepZ

			local tile = Instance.new("Part")
			tile.Name = name
			tile.Anchored = true
			tile.Locked = true
			tile.Size = Vector3.new(stepX, thickness, stepZ)
			tile.Position = Vector3.new(x0 + stepX * 0.5, GameConfig.SurfaceY - thickness * 0.5, z0 + stepZ * 0.5)
			tile.Color = quantize(base, shades[(ix + iz) % 2 + 1])
			tile.Material = Enum.Material.SmoothPlastic
			tile.TopSurface = Enum.SurfaceType.Smooth
			tile.BottomSurface = Enum.SurfaceType.Smooth
			tile.Parent = hubFolder
		end
	end
end

local function buildHub()
	local half = (RADIUS + 0.5) * BLOCK
	local cx, cz = GameConfig.ShaftCenterX, GameConfig.ShaftCenterZ
	local base = grassBase()

	local plotHalfX = GameConfig.HubPlotHalfX
	local mineHalfX = GameConfig.HubMineHalfX
	local join = GameConfig.HubPlotZMax

	--[[
		The plot band is solid -- nothing is cut out of it. Only the stem holds the
		shaft, so only the stem is split, into the same ring of four the square hub
		used: full-width strips south and north of the opening, and two fillers
		either side of it.
	]]
	local slabs = {
		{ minX = -plotHalfX, maxX = plotHalfX, minZ = GameConfig.HubPlotZMin, maxZ = join },
		{ minX = -mineHalfX, maxX = mineHalfX, minZ = join, maxZ = cz - half },
		{ minX = -mineHalfX, maxX = mineHalfX, minZ = cz + half, maxZ = GameConfig.HubMineZMax },
		{ minX = -mineHalfX, maxX = cx - half, minZ = cz - half, maxZ = cz + half },
		{ minX = cx + half, maxX = mineHalfX, minZ = cz - half, maxZ = cz + half },
	}

	for index, slab in slabs do
		tileFloor(`HubTile{index}`, slab.minX, slab.maxX, slab.minZ, slab.maxZ, base)
	end

	-- Spawn right at the lip of the shaft. Anywhere further and a new player has
	-- to work out which part of the field they're meant to walk to.
	--
	-- Pale stone, because the floor is grass now: a green pad on a green lawn is
	-- not a landmark.
	local spawn = Instance.new("SpawnLocation")
	hubSpawnPosition = Vector3.new(cx, GameConfig.SurfaceY + 4, cz - half - 6)
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Locked = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(cx, GameConfig.SurfaceY + 0.5, cz - half - 6)
	spawn.Color = Color3.fromRGB(228, 216, 182)
	spawn.Material = Enum.Material.Sandstone
	spawn.Duration = 0
	spawn.Parent = hubFolder
end

--[[
	The retaining wall: a checkerboard face on the hub's rim, capped with grass.

	The outline is the two bands' union, walked as eight straight runs. Each run
	stops where the next begins rather than overlapping, so no corner is built
	twice: the plot band's side walls stop short of its south run, the shoulder
	runs stop at the stem, and the stem's north run fills only what its own side
	walls leave. Where the bands meet, the shoulder runs and the stem's side
	walls share a south face, so the join reads as one flush gateway.

	Flat by intent. This carried a plinth, per-tile relief, a string course and
	pilasters; the reference art is an unbroken plane of fine check under a green
	lip, and against that every one of those details read as an interruption. The
	only thing standing off the face now is the coping's oversail.

	A run is described by its long axis and the rim it stands on: `bOuter` is
	that rim's coordinate and `inward` the direction the wall thickens, so every
	course is the same arithmetic regardless of which way the run faces.

	Columns divide the run's length evenly rather than stepping a fixed pitch and
	clamping -- clamping leaves a sliver tile at the end of every run, which is a
	visible break in the check at eight corners.
]]
local wallTileCount = 0

local function buildWall()
	local pitch = GameConfig.WallTileSize
	local surface = GameConfig.SurfaceY
	local t = GameConfig.WallThickness
	local height = GameConfig.WallHeight
	local capH = GameConfig.WallCapHeight

	local px = GameConfig.HubPlotHalfX
	local pz = GameConfig.HubPlotZMin
	local join = GameConfig.HubPlotZMax
	local mx = GameConfig.HubMineHalfX
	local mz = GameConfig.HubMineZMax

	local dirt = cartoonify(GameConfig.WallColor)
	local shades = GameConfig.WallCheckerShades
	local grass = quantize(grassBase(), GameConfig.PaletteShades - 1)
	local rows = math.max(1, math.round(height / pitch))
	local built = 0

	local function box(name, x, y, z, sx, sy, sz, colour, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Locked = true
		part.Size = Vector3.new(sx, sy, sz)
		part.Position = Vector3.new(x, y, z)
		part.Color = colour
		part.Material = material
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = hubFolder
		built += 1
	end

	--[[
		Lays one course. `aFrom`/`aTo` bound it along the run, `depth` is how far
		it reaches from the rim, and the y pair is its vertical span. Handles both
		run orientations so no course has to know which way it faces.
	]]
	local function course(r, name, aFrom, aTo, depth, y0, y1, colour, material)
		if aTo <= aFrom then
			return
		end
		local aC, aS = (aFrom + aTo) * 0.5, aTo - aFrom
		local bC, bS = r.bOuter + r.inward * depth * 0.5, depth
		local yC, yS = (y0 + y1) * 0.5, y1 - y0

		if r.alongX then
			box(name, aC, yC, bC, aS, yS, bS, colour, material)
		else
			box(name, bC, yC, aC, bS, yS, aS, colour, material)
		end
	end

	local runs = {
		{ name = "WallPlotSouth", alongX = true, aFrom = -px, aTo = px, bOuter = pz, inward = 1 },
		{ name = "WallPlotWest", alongX = false, aFrom = pz + t, aTo = join, bOuter = -px, inward = 1 },
		{ name = "WallPlotEast", alongX = false, aFrom = pz + t, aTo = join, bOuter = px, inward = -1 },
		{ name = "WallShoulderWest", alongX = true, aFrom = -px + t, aTo = -mx, bOuter = join, inward = -1 },
		{ name = "WallShoulderEast", alongX = true, aFrom = mx, aTo = px - t, bOuter = join, inward = -1 },
		{ name = "WallMineWest", alongX = false, aFrom = join - t, aTo = mz, bOuter = -mx, inward = 1, footFrom = join },
		{ name = "WallMineEast", alongX = false, aFrom = join - t, aTo = mz, bOuter = mx, inward = -1, footFrom = join },
		{ name = "WallMineNorth", alongX = true, aFrom = -mx + t, aTo = mx - t, bOuter = mz, inward = -1 },
	}

	for _, r in runs do
		local length = r.aTo - r.aFrom
		local columns = math.max(1, math.round(length / pitch))
		local step = length / columns

		--[[
			Footing. The hub floor is a HubThickness-deep green slab, so from outside
			the map its edge shows beneath the wall. This skirt covers it.

			It sits *outside* the rim rather than on it. Laid on the rim it occupied
			exactly the same volume as the floor tiles underneath -- 84 of them per
			run, tops coplanar at SurfaceY -- and the z-fight painted a tan strip
			along the base of every wall from the inside. Outside the rim it
			overlaps nothing and still hides the edge.
		]]
		do
			local skirt = GameConfig.WallFootingDepth
			local bC = r.bOuter - r.inward * skirt * 0.5
			-- footFrom trims the skirt where a run does not border the void: the
			-- stem's jambs continue south of the gateway, and along that stretch
			-- they stand on plot-band floor with no edge to hide.
			local from = r.footFrom or r.aFrom
			local aC, aS = (from + r.aTo) * 0.5, r.aTo - from
			local yC = surface - GameConfig.HubThickness * 0.5
			local colour = quantize(dirt, shades[1])
			if r.alongX then
				box(`{r.name}Footing`, aC, yC, bC, aS, GameConfig.HubThickness, skirt, colour, Enum.Material.SmoothPlastic)
			else
				box(`{r.name}Footing`, bC, yC, aC, skirt, GameConfig.HubThickness, aS, colour, Enum.Material.SmoothPlastic)
			end
		end
		for column = 0, columns - 1 do
			local a0 = r.aFrom + column * step

			for row = 0, rows - 1 do
				course(
					r,
					r.name,
					a0,
					a0 + step,
					t,
					surface + row * pitch,
					surface + (row + 1) * pitch,
					quantize(dirt, shades[(column + row) % 2 + 1]),
					Enum.Material.SmoothPlastic
				)
			end
		end

		--[[
			Coping, oversailing both faces -- and both ends. The end oversail is what
			closes the corners: a cap that stopped at its run's end left the square
			where two runs meet covered by neither, a notch with the cap's green end
			face showing through it. Extending every cap by the overhang makes the
			two caps at a corner overlap instead, which costs nothing to look at.
		]]
		local over = GameConfig.WallCapOverhang
		local aC, aS = (r.aFrom + r.aTo) * 0.5, length + over * 2
		local bC = r.bOuter + r.inward * (t * 0.5)
		local yC = surface + height + capH * 0.5
		if r.alongX then
			box(`{r.name}Cap`, aC, yC, bC, aS, capH, t + over * 2, grass, Enum.Material.SmoothPlastic)
		else
			box(`{r.name}Cap`, bC, yC, aC, t + over * 2, capH, aS, grass, Enum.Material.SmoothPlastic)
		end
	end

	wallTileCount = built
	return built
end

--[[
	The plaza: the paved square the four bases face into, running from their
	kerbs up to the shaft lip.

	Bounds are derived, not written down. North is the shaft lip; south is the
	outer face of the back pair's kerbs; east and west are the outer faces of the
	turned pair's. Moving a plot therefore moves the plaza with it, instead of
	quietly opening a strip of lawn between a base and the square it is supposed
	to open onto.
]]
local function plazaBounds(): (number, number, number, number)
	local shaftHalf = (RADIUS + 0.5) * BLOCK

	-- Distance from a plot's centre to the outer face of its kerb, along the
	-- axis it faces. The turned plots face along X and the back pair along Z,
	-- but the measurement is the same either way.
	local toKerb = GameConfig.PlotDepth / 2 + GameConfig.PlotKerbDepth

	local halfX = math.abs(GameConfig.PlotLayout[1].position.X) - toKerb
	local minZ = GameConfig.PlotLayout[2].position.Z + GameConfig.PlotDepth / 2 + GameConfig.PlotKerbDepth
	local maxZ = GameConfig.ShaftCenterZ - shaftHalf

	return -halfX, halfX, minZ, maxZ
end

--[[
	Paves it. One rectangle, divided evenly in both axes -- stepping a fixed
	pitch and clamping the last row would leave a sliver course down two edges,
	which is the defect the hub floor, the wall and the old path each shipped.

	The outermost course is a shade darker, so the square reads as a square from
	inside it rather than as paving that happens to stop.

	The spawn pad is left standing on top rather than cut around. It is a stud
	proud and pale sandstone on grey paving, so it still reads as the landmark it
	is, and a hole would break the checker at four seams for nothing.
]]
local function buildPlaza(): number
	local minX, maxX, minZ, maxZ = plazaBounds()
	local pitch = GameConfig.PlazaTileSize
	local stone = GameConfig.PlazaColor
	local shades = GameConfig.PlazaCheckerShades
	local y = GameConfig.SurfaceY + GameConfig.PlazaRaise - 0.5

	local sizeX, sizeZ = maxX - minX, maxZ - minZ
	local cols = math.max(1, math.round(sizeX / pitch))
	local rows = math.max(1, math.round(sizeZ / pitch))
	local stepX, stepZ = sizeX / cols, sizeZ / rows
	local built = 0

	for ix = 0, cols - 1 do
		for iz = 0, rows - 1 do
			local edge = ix == 0 or iz == 0 or ix == cols - 1 or iz == rows - 1
			local tile = Instance.new("Part")
			tile.Name = if edge then "PlazaKerb" else "PlazaTile"
			tile.Anchored = true
			tile.Locked = true
			tile.Size = Vector3.new(stepX, 1, stepZ)
			tile.Position = Vector3.new(minX + (ix + 0.5) * stepX, y, minZ + (iz + 0.5) * stepZ)
			tile.Color = quantize(stone, if edge then GameConfig.PlazaBorderShade else shades[(ix + iz) % 2 + 1])
			tile.Material = Enum.Material.SmoothPlastic
			tile.TopSurface = Enum.SurfaceType.Smooth
			tile.BottomSurface = Enum.SurfaceType.Smooth
			tile.Parent = hubFolder
			built += 1
		end
	end

	return built
end

--[[
	Lamp standards and the centre monument.

	Two rows of lamps, inset from the plaza's south and north edges. Not down the
	middle: a file of lamps either side of the centre line would draw the path
	back in, and the point of a square is that you cross it however you like.

	The north row skips the centre column, which is the spawn pad and the walk
	off the lip into the shaft.
]]
local function buildPlazaFurniture(): number
	local minX, maxX, minZ, maxZ = plazaBounds()
	local pal = GameConfig.PlazaPalette
	local inset = GameConfig.PlazaLampInset
	local built = 0

	local function box(name, size, cf, colour, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Locked = true
		part.Size = size
		part.CFrame = cf
		part.Color = colour
		part.Material = material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = hubFolder
		built += 1
		return part
	end

	--[[
		One lamp. The base is sunk half below SurfaceY: it stands on paving whose
		top is only PlazaRaise proud, and a base sitting exactly on the lawn plane
		underneath would put two horizontal faces in the same place.
	]]
	local function lamp(x: number, z: number)
		local h = GameConfig.PlazaLampHeight
		box("PlazaLampBase", Vector3.new(3.6, 2, 3.6), CFrame.new(x, 0.4, z), pal.stone)
		box("PlazaLampPost", Vector3.new(1.4, h, 1.4), CFrame.new(x, h / 2 + 1.2, z), pal.post)
		box("PlazaLampGlass", Vector3.new(3, 3, 3), CFrame.new(x, h + 1.6, z), pal.lamp, Enum.Material.Neon)
		box("PlazaLampCap", Vector3.new(4.2, 1, 4.2), CFrame.new(x, h + 3.6, z), pal.post)
	end

	--[[
		How crowded a spot is by the shops, as a fraction of the clearance the
		nearest one wants: below 1 is too close.

		A ratio rather than a distance because there are two things to stay out
		of and they want different room -- the building, which wants
		PlazaLampShopClearance, and the lit circle in front of it, which only
		wants its own radius plus a margin. Testing the building alone was wrong
		the moment the circles moved off the shop centres: a lamp could clear the
		stall by 20 studs and still be standing in the middle of its pad.
	]]
	local function shopCrowding(x: number, z: number): number
		local padRoom = GameConfig.ShopPadDiameter / 2 + 3
		local worst = math.huge

		for _, layout in GameConfig.ShopLayout do
			local origin = CFrame.new(layout.position) * CFrame.Angles(0, math.rad(layout.yaw), 0)
			local pad = origin * layout.padOffset
			worst = math.min(
				worst,
				Vector2.new(x - layout.position.X, z - layout.position.Z).Magnitude
					/ GameConfig.PlazaLampShopClearance,
				Vector2.new(x - pad.X, z - pad.Z).Magnitude / padRoom
			)
		end
		return worst
	end

	--[[
		Shops and lamps compete for the same ground: the ring runs on a fixed
		inset from the plaza edge and the shops sit on those same flanks.

		A crowded lamp walks *away from the shop crowding it* until it clears.
		Away from the shop rather than away from the plaza centre: a shop can sit
		either side of a lamp, and pushing outward regardless drove the lamp at
		(-46, 21) straight through the sell stall and into the tool shop beyond
		it, so it cleared neither and was dropped.

		Sliding along the edge is tried first, since that keeps the ring reading
		as a ring. When the plaza edge cuts that short -- which happens to the
		corner lamps, with a shop inboard of them and nowhere outboard to go --
		it falls back to stepping in toward the middle of the square. Only a lamp
		that can do neither is dropped.
	]]
	local function clears(x: number, z: number): boolean
		return shopCrowding(x, z) >= 1
	end

	local function slide(x: number, z: number, dx: number, dz: number): (number, number, boolean)
		local step = GameConfig.PlazaLampNudge
		for _ = 1, 40 do
			x += dx * step
			z += dz * step
			if x < minX + 3 or x > maxX - 3 or z < minZ + 3 or z > maxZ - 3 then
				return x, z, false
			end
			if clears(x, z) then
				return x, z, true
			end
		end
		return x, z, false
	end

	local function placeLamp(x: number, z: number)
		if clears(x, z) then
			lamp(x, z)
			return
		end

		--[[
			Which side of the thing crowding us are we on? Step that way.

			The crowding thing may be a building or a circle, so this weighs both
			the same way `shopCrowding` does. Picking the nearest building alone
			would send a lamp crowded by a pad off in whichever direction that
			pad's shop happened to sit.
		]]
		local padRoom = GameConfig.ShopPadDiameter / 2 + 3
		local nearestX, best = x, math.huge
		for _, layout in GameConfig.ShopLayout do
			local origin = CFrame.new(layout.position) * CFrame.Angles(0, math.rad(layout.yaw), 0)
			local pad = origin * layout.padOffset

			local toShop = Vector2.new(x - layout.position.X, z - layout.position.Z).Magnitude
				/ GameConfig.PlazaLampShopClearance
			if toShop < best then
				best, nearestX = toShop, layout.position.X
			end

			local toPad = Vector2.new(x - pad.X, z - pad.Z).Magnitude / padRoom
			if toPad < best then
				best, nearestX = toPad, pad.X
			end
		end

		local ax, az, okX = slide(x, z, if x >= nearestX then 1 else -1, 0)
		if okX then
			lamp(ax, az)
			return
		end

		-- Edge cut that short; try stepping in toward the middle of the square.
		local bx, bz, okZ = slide(x, z, 0, if z > (minZ + maxZ) / 2 then -1 else 1)
		if okZ then
			lamp(bx, bz)
		end
	end

	local perRow = GameConfig.PlazaLampsPerRow
	local spanX = (maxX - inset) - (minX + inset)
	for i = 1, perRow do
		local x = (minX + inset) + (i - 1) * (spanX / (perRow - 1))
		placeLamp(x, minZ + inset)
		-- Skip the middle of the north row: that column is the spawn pad and the
		-- walk off the lip.
		if i ~= math.ceil(perRow / 2) then
			placeLamp(x, maxZ - inset)
		end
	end

	--[[
		Centre monument: a stepped plinth under the same crossed hammers the plot
		headers carry, so the square and the buildings around it are plainly the
		same place. Blocks, not a mesh -- this project ships no asset ids.
	]]
	local cx = (minX + maxX) / 2
	local cz = (minZ + maxZ) / 2
	local steps = GameConfig.PlazaMonumentSteps
	local baseW = GameConfig.PlazaMonumentBase
	local top = 0

	for i = 1, steps do
		local w = baseW * (1 - (i - 1) / (steps + 1))
		local h = 1.8
		box("MonumentStep", Vector3.new(w, h, w), CFrame.new(cx, top + h / 2, cz), pal.stone)
		top += h
	end

	local pillarH = 9
	box("MonumentPillar", Vector3.new(5, pillarH, 5), CFrame.new(cx, top + pillarH / 2, cz), pal.post)
	top += pillarH

	for _, tilt in { 34, -34 } do
		local hammer = CFrame.new(cx, top + 5, cz) * CFrame.Angles(0, 0, math.rad(tilt))
		box("MonumentHammerHandle", Vector3.new(1.5, 10, 1.5), hammer, pal.emblem)
		box("MonumentHammerHead", Vector3.new(4.6, 3, 2), hammer * CFrame.new(0, 4.2, 0), pal.emblem)
	end

	return built
end

--[[
	The three shops around the plaza: a striped market stall for selling, an ore
	exchange for the ore-to-brainrot conversion (and, on its other tab, placing
	and selling the brainrots that come out of it), and a tool shop for
	pickaxes, backpacks, podium slots and layer keys.

	Each stands on a lit circle that opens its menu when you walk into it. The
	menus used to open from HUD buttons that worked anywhere on the map, which
	left these buildings as pure scenery -- a picture of a shop next to a button
	that was the actual shop. Now the building is the shop.

	The circles are the whole interaction: no ProximityPrompt, no key to press.
	See `standingPad` below and UIController's pad watcher.
]]
--[[
	Scenery on the grass around the mine.

	Last of the hub builders on purpose: it reads everything already standing --
	wall, plaza, lamps, stalls, pads -- off the built parts to decide where it
	may not put anything, so it has to run after all of them.
]]
local function buildDecor()
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = hubFolder

	local minX, maxX, minZ, maxZ = plazaBounds()
	local placed = HubDecor.build(folder, hubFolder, { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ })
	if placed == 0 then
		warn("[MineService] lawn decoration placed nothing; check the keep-out margins")
	end
end

local function buildShops()
	local pal = GameConfig.ShopPalette
	local built = 0

	local function box(name, size, cf, colour, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Locked = true
		part.Size = size
		part.CFrame = cf
		part.Color = colour
		part.Material = material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = hubFolder
		built += 1
		return part
	end

	--[[
		The heavy outline every floating shop sign carries.

		A UIStroke rather than TextStrokeTransparency: the built-in stroke is a
		single pixel and disappears against the plaza at any distance, where the
		reference art's world labels are outlined as thickly as its UI. This is
		the same treatment Theme.textStroke gives screen text, so a sign reads as
		belonging to the same game as the panel it opens.
	]]
	local function worldLabelStroke(label: TextLabel)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.fromRGB(10, 8, 20)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
	end

	--[[
		The lit circle in front of each shop, and the thing that opens its menu:
		step into the circle and the panel appears, step out and it closes.

		Built as concentric discs rather than one flat plate, each a little
		smaller and a little higher than the one under it, so from above you read
		a glowing outer ring, a dim band, a glowing inner ring and a dim middle.
		A single Neon disc was a pancake of flat colour; this is the same idea a
		lit pad has in any game that uses one.

		The stagger matters as much as the sizes: each disc's top sits above the
		last, so no two horizontal faces share a plane. Stacking them flush would
		z-fight across the whole circle.

		Only the outer disc is tagged and carries the panel name. UIController
		reads the radius off *that* part, so the ring you can see is exactly the
		trigger -- there is no second, invisible volume to keep in sync with it.

		Cylinders laid flat: the thin axis is X and the quarter turn about Z
		stands them face-up, which is why the client cannot just take Size.X / 2.
	]]
	local function standingPad(key: string, at: CFrame, panel: string, tint: Color3?)
		local d = GameConfig.ShopPadDiameter
		local bright = tint or pal.pad

		--[[
			A solid glowing disc, not a set of rings.

			The reference pad is one filled circle whose rim burns saturated and
			whose middle washes out almost to white, carrying a grid of small
			studs. Neon does the washing-out on its own -- it drives a bright
			colour toward white -- so the two discs are the same hue at different
			distances from white rather than two different colours.

			Every layer's top sits at its own height. Two flat discs sharing a
			plane z-fight across their whole face, which is the most visible
			version of that bug there is.
		]]
		local face = bright:Lerp(Color3.new(1, 1, 1), 0.5)
		local stud = bright:Lerp(Color3.new(1, 1, 1), 0.28)

		local function disc(name: string, size: number, y: number, colour: Color3, transparency: number?): BasePart
			local part = box(
				name,
				Vector3.new(0.4, size, size),
				at * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
				colour,
				Enum.Material.Neon
			)
			part.Shape = Enum.PartType.Cylinder
			part.CanCollide = false
			if transparency then
				part.Transparency = transparency
			end
			return part
		end

		--[[
			The spill of light on the ground outside the rim, in three steps.

			Built rather than left to the engine: Lighting's BloomEffect runs at
			Threshold 2, which Neon never reaches, so nothing here haloes on its
			own. Dropping that threshold would give the real thing but is a global
			change -- every Neon surface in the game would start to glow -- so the
			pad carries its own.

			Three rings rather than one because a single translucent disc has a
			hard edge and reads as a second ring rather than as light. Each is
			wider and fainter than the last, and they overlap, so the annuli
			compound inward: faintest at the outside, strongest against the rim.
			Stepped rather than smoothly faded is also what DESIGN.md 2a asks of
			effects.
		]]
		for _, step in { { 6, 0.85 }, { 4, 0.72 }, { 2, 0.55 } } do
			disc("ShopPadGlow", d + step[1], 0.02 + step[1] * 0.01, bright, step[2])
		end

		local rim = disc("ShopPad", d, 0.12, bright)
		rim:SetAttribute("UIPanel", panel)
		-- Which shop this is, as opposed to which panel it opens: the sell
		-- stall opens the same Backpack panel the HUD button does, so the panel
		-- name cannot identify it.
		rim:SetAttribute(GameConfig.ShopKeyAttribute, key)
		CollectionService:AddTag(rim, PANEL_PAD_TAG)

		local faceDiameter = d - GameConfig.ShopPadRim * 2
		disc("ShopPadFace", faceDiameter, 0.26, face)

		--[[
			The studs, laid on a square grid and clipped to the face.

			Geometry rather than a texture, which is the project's standing
			constraint and here happens to be what the reference is doing anyway:
			the pattern is raised, not printed.

			`limit` is where a stud's *edge* may reach, so it takes the stud's
			radius off the face's -- taking the whole diameter off, as the first
			pass did, pulled the grid two rings short and left a bare pale band
			round the outside that the reference does not have.
		]]
		local pitch = GameConfig.ShopPadStudPitch
		local studSize = GameConfig.ShopPadStudSize
		local limit = faceDiameter / 2 - studSize / 2 - 0.2
		local reach = math.floor(limit / pitch)

		for ix = -reach, reach do
			for iz = -reach, reach do
				local x, z = ix * pitch, iz * pitch
				if math.sqrt(x * x + z * z) <= limit then
					local part = box(
						"ShopPadStud",
						Vector3.new(0.3, studSize, studSize),
						at * CFrame.new(x, 0.4, z) * CFrame.Angles(0, 0, math.rad(90)),
						stud,
						Enum.Material.Neon
					)
					part.Shape = Enum.PartType.Cylinder
					part.CanCollide = false
				end
			end
		end
	end

	--[[
		Every shop is built against an origin CFrame rather than in world axes, so
		its yaw carries the whole stall -- counter, awning, stock and sign all keep
		the same relation to the front however the building is turned. Same reason
		PlotService builds a plot relative to its own origin.

		The pad hangs off that origin too, at the layout's `padOffset`, which is
		in the shop's *local* frame: it sits in front of the counter rather than
		under the middle of the building, and turning the shop turns the pad with
		it. Local, because "in front" is a different world direction for each of
		them -- the market stalls face along their -Z and the exchange along
		its -X.
	]]
	local function shopAt(key: string, panel: string)
		local layout = GameConfig.ShopLayout[key]
		local origin = CFrame.new(layout.position) * CFrame.Angles(0, math.rad(layout.yaw), 0)
		standingPad(key, origin * CFrame.new(layout.padOffset), panel, layout.padColour)

		return function(name: string, size: Vector3, offset: CFrame, colour: Color3, material: Enum.Material?)
			return box(name, size, origin * offset, colour, material)
		end
	end

	--------------------------------------------------------------------
	-- The market stalls
	--------------------------------------------------------------------
	--[[
		The shell the sell stall and the tool shop share: four posts, a rail
		frame, a striped awning with a scalloped valance under its front edge, a
		counter, and the billboard over the lot.

		Factored because the two are the same building in different colours, and
		they had drifted into two copies of the same twenty lines -- every change
		to one had to be remembered for the other, and twice it wasn't.

		`dress` places whatever that shop sells on its counter, which is the only
		part that genuinely differs. It gets the stall's dimensions rather than
		closing over them, so the goods move with the counter when the stall is
		resized instead of hanging off the end of it.
	]]
	local function marketStall(
		place: (string, Vector3, CFrame, Color3, Enum.Material?) -> BasePart,
		prefix: string,
		stripe: Color3,
		labelText: string,
		labelColour: Color3,
		dress: ((string, Vector3, CFrame, Color3, Enum.Material?) -> BasePart, number, number, number) -> ()
	)
		local w, d = GameConfig.MarketStallWidth, GameConfig.MarketStallDepth
		local postH = GameConfig.MarketStallPostHeight
		local awningY = postH + 1.2
		local awningBottom = awningY - 1.6
		local frontZ = -(d + 3) / 2
		local counterZ = -d / 2 + 3

		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				place(
					`{prefix}Post`,
					Vector3.new(2.4, postH, 2.4),
					CFrame.new(sx * (w / 2 - 1), postH / 2, sz * (d / 2 - 1)),
					pal.post
				)
			end
		end

		-- Rails tying the posts together, so the frame reads as built rather
		-- than as four sticks holding up a lid.
		place(`{prefix}Rail`, Vector3.new(w - 2, 0.8, 0.8), CFrame.new(0, postH * 0.55, d / 2 - 1), pal.post)
		for _, sx in { -1, 1 } do
			place(`{prefix}Rail`, Vector3.new(0.8, 0.8, d - 2), CFrame.new(sx * (w / 2 - 1), postH * 0.55, 0), pal.post)
		end

		local stripes = 8
		local sw = w / stripes
		for i = 0, stripes - 1 do
			local x = -w / 2 + (i + 0.5) * sw
			local colour = if i % 2 == 0 then stripe else pal.stripeB
			place(`{prefix}Awning`, Vector3.new(sw, 3.2, d + 3), CFrame.new(x, awningY, 0), colour)
			-- A scalloped valance hung off the front edge, one tab per stripe,
			-- carrying the stripe colour down past the awning line.
			place(
				`{prefix}Valance`,
				Vector3.new(sw * 0.72, 1.6, 0.6),
				CFrame.new(x, awningBottom - 0.8, frontZ + 0.3),
				colour
			)
		end

		place(`{prefix}Counter`, Vector3.new(w - 3, 2, 5), CFrame.new(0, 6.2, counterZ), pal.wood)
		place(`{prefix}CounterLeg`, Vector3.new(w - 6, 5.2, 2.4), CFrame.new(0, 2.6, counterZ), pal.wood)

		dress(place, w, d, counterZ)

		local anchor = place(`{prefix}Label`, Vector3.new(1, 1, 1), CFrame.new(0, postH + 7, 0), labelColour)
		anchor.Transparency = 1
		anchor.CanCollide = false

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(190, 70)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 260
		gui.Parent = anchor

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.Text = labelText
		text.TextColor3 = labelColour
		text.Parent = gui
		worldLabelStroke(text)
	end

	--[[
		Where a stall's goods go, in terms of its own width.

		`goods` is the offset for anything standing on the counter: at w = 18 the
		corner posts' inner faces are at 6.8, so w/2 - 6 = 3 leaves room for a
		5-wide crate or backpack beside it. The first pass used w/4, which was
		fine at the old 26-wide stall and pushed both straight into the posts once
		it shrank.

		`floor` is for the one item each stall stands on the ground beside the
		counter, out of the way of everything on top of it.
	]]
	local function goodsOffsets(w: number): (number, number)
		return w / 2 - 6, w / 2 - 4.5
	end

	--[[
		The sell stall: a crate of rough ore on one side of the counter, the coins
		it pays for it stacked on the other, and sacks on the floor beside them.

		Everything fits under the awning. The counter top is at 7.2 and the awning
		underside at postH + 1.2 - 1.6 = 12.6, and an earlier pass sized the crate
		to look right on its own and drove the ore pile straight through the roof.

		A balance stood on the counter here briefly. At this stall size its pans
		could not clear the ore pile without being pushed off the counter's front
		edge, so the sacks do the "this place deals in bulk" job instead, from
		ground level where there is room.
	]]
	local function dressSell(place, w: number, _d: number, counterZ: number)
		local goods, floor = goodsOffsets(w)

		place("StallCrate", Vector3.new(5, 2.8, 4.6), CFrame.new(-goods, 8.6, counterZ), pal.wood)
		for i, spot in { Vector3.new(-1.2, 0, -0.6), Vector3.new(1, 0.2, 0.5), Vector3.new(-0.1, 1.2, 0) } do
			place(
				"StallOre",
				Vector3.new(1.6, 1.6, 1.6),
				CFrame.new(-goods + spot.X, 9.5 + spot.Y, counterZ + spot.Z)
					* CFrame.Angles(math.rad(21 * i), math.rad(27 * i), math.rad(16 * i)),
				pal.ore
			)
		end

		-- Coins are cylinders laid flat: the thin axis is X and the quarter turn
		-- about Z stands them face-up, the same trick the standing pads use. The
		-- stall's yaw is about Y, so it does not disturb that. Stacked at exactly
		-- their own thickness so they touch rather than float.
		for i = 0, 2 do
			local coin = place(
				"StallCoin",
				Vector3.new(0.5, 3.4, 3.4),
				CFrame.new(goods, 7.45 + i * 0.5, counterZ) * CFrame.Angles(0, 0, math.rad(90)),
				pal.coin
			)
			coin.Shape = Enum.PartType.Cylinder
		end

		for i, spot in { Vector3.new(0, 0, 0), Vector3.new(1.2, 0, 1.3), Vector3.new(-0.9, 0, 1.5) } do
			place(
				"StallSack",
				Vector3.new(2.6, 2.4, 2.2),
				CFrame.new(floor + spot.X, 1.2, 1 + spot.Z) * CFrame.Angles(0, math.rad(23 * i), 0),
				pal.sack
			)
		end
	end

	--[[
		The tool shop: a rack of pickaxes behind the counter, a backpack on it,
		and a barrel of spare handles on the floor beside it.

		Two picks, not three. Three fitted the old 26-wide stall; across an
		18-wide rack their heads are 4.58 across once tilted, so three of them
		need 13.7 studs against the 13.6 between the posts -- they overlapped each
		other and the corner post both.

		The rack sits forward of the back rail rather than on it, and the barrel
		is on the floor: a barrel deep enough to read as one would sink through
		the counter top to reach the handles standing out of it.
	]]
	local function dressTools(place, w: number, d: number, counterZ: number)
		local goods, floor = goodsOffsets(w)

		place("ToolPack", Vector3.new(5, 4.2, 3.6), CFrame.new(-goods, 9.3, counterZ), pal.pack)
		place("ToolPackFlap", Vector3.new(5.2, 1.4, 3.8), CFrame.new(-goods, 11.6, counterZ), pal.packTrim)
		place("ToolPackStrap", Vector3.new(1.1, 4, 0.5), CFrame.new(-goods, 9.4, counterZ - 1.9), pal.packTrim)

		local rackZ = d / 2 - 2.6
		place("ToolRack", Vector3.new(w - 6, 9, 1), CFrame.new(0, 8, rackZ), pal.post)
		for _, sx in { -1, 1 } do
			-- Handle and head apiece, tilted: geometry, because the project ships
			-- no meshes.
			local at = CFrame.new(sx * 3.2, 8, rackZ - 0.7) * CFrame.Angles(0, 0, math.rad(18))
			place("ToolPickHandle", Vector3.new(0.9, 7, 0.7), at, pal.wood)
			place("ToolPickHead", Vector3.new(4.4, 1.3, 0.9), at * CFrame.new(0, 3, 0), pal.machineTrim)
		end

		local barrel = place(
			"ToolBarrel",
			Vector3.new(4.4, 4, 4),
			CFrame.new(floor, 2.2, 1) * CFrame.Angles(0, 0, math.rad(90)),
			pal.wood
		)
		barrel.Shape = Enum.PartType.Cylinder
		for i = -1, 1 do
			place(
				"ToolHandle",
				Vector3.new(0.6, 5, 0.6),
				CFrame.new(floor + i * 0.8, 6.9, 1 + i * 0.4)
					* CFrame.Angles(math.rad(8 * i), 0, math.rad(10 * i)),
				pal.wood
			)
		end
	end

	--------------------------------------------------------------------
	-- Sell stall
	--------------------------------------------------------------------
	-- The sell stall's circle opens the Bag, which is where selling ore actually
	-- happens; the stall is the place in the world that flow belongs to.
	marketStall(shopAt("sell", "inventory"), "Stall", pal.stripeA, "SELL", pal.stripeA, dressSell)

	--------------------------------------------------------------------
	-- Ore exchange stall
	--------------------------------------------------------------------
	local exchange = shopAt("convert", "convert")

	local exW, exD, exPostH = 24, 16, 13
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			exchange(
				"ExchangePost",
				Vector3.new(2.4, exPostH, 2.4),
				CFrame.new(sx * (exW / 2 - 1), exPostH / 2, sz * (exD / 2 - 1)),
				pal.machineTrim
			)
		end
	end

	exchange("ExchangeCanopy", Vector3.new(exW + 2, 3, exD + 2), CFrame.new(0, exPostH + 1.5, 0), pal.machineBody)
	-- The neon trim marks the same face as the counter (west), not just an
	-- arbitrary edge, so the lit side of the roof is the side you approach.
	exchange(
		"ExchangeCanopyTrim",
		Vector3.new(0.6, 0.6, exD + 2),
		CFrame.new(-exW / 2 - 1, exPostH - 0.1, 0),
		pal.machineGlow,
		Enum.Material.Neon
	)

	--[[
		Counter on the west side, the way the old cabinet's screen already faced
		-- onto the walk from the sell stall and the bases, rather than the
		shaft.

		The sell stall's counter runs across its open front, perpendicular to
		its corner posts, so the two never meet. This one runs along the same
		wall its posts stand on, so its length has to stop short of them
		instead: exD - 6 keeps its ends inside the posts at +-(exD/2 - 1) with
		a clear gap, where exD - 3 (the sell stall's own margin, sized for the
		perpendicular case) still overlapped them.
	]]
	exchange("ExchangeCounter", Vector3.new(5, 2, exD - 6), CFrame.new(-exW / 2 + 3, 6.2, 0), pal.machineBody)
	exchange(
		"ExchangeCounterLeg",
		Vector3.new(2.4, 5.2, exD - 6),
		CFrame.new(-exW / 2 + 3, 2.6, 0),
		pal.machineTrim
	)

	-- The "?" screen, sized to the counter rather than to loom over it -- the
	-- old 9x9 panel on a standalone cabinet read as a monolith next to a
	-- player, not a shop. It stands on the counter (top at 7.2) rather than
	-- into it, clear of the canopy (underside at 13) above.
	local screen = exchange(
		"ExchangeScreen",
		Vector3.new(0.6, 4, 4),
		CFrame.new(-exW / 2 + 5.4, 10, 0),
		pal.machineGlow,
		Enum.Material.Neon
	)

	local screenGui = Instance.new("SurfaceGui")
	screenGui.Face = Enum.NormalId.Left
	screenGui.CanvasSize = Vector2.new(140, 140)
	screenGui.LightInfluence = 0
	screenGui.Parent = screen

	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Font = Enum.Font.GothamBlack
	mark.TextScaled = true
	mark.Text = "?"
	mark.TextColor3 = Color3.fromRGB(255, 255, 255)
	mark.Parent = screenGui

	--[[
		A hopper on the roof, widening upward: this is the machine you feed ore
		into. The canopy tops out at exPostH + 3, so the stack starts there.
	]]
	for i = 1, 3 do
		local w = 5 + (i - 1) * 2.5
		exchange(
			"ExchangeHopper",
			Vector3.new(w, 2, w),
			CFrame.new(0, exPostH + 4 + (i - 1) * 2, 0),
			pal.machineTrim
		)
	end

	--[[
		The rarities it can roll, as a row of lit bulbs over the counter, in
		Rarity.ORDER and using Rarity's own colours -- the same tints the reveal
		and the plot display cases use, so a Legendary reads as the same colour
		wherever you meet it.

		Spaced 2.2 apart so the outermost stays inside the corner posts, which
		start at |z| = exD/2 - 1 - 1.2.
	]]
	local bulbs = 5
	for i = 1, bulbs do
		exchange(
			`ExchangeBulb{Rarity.ORDER[i]}`,
			Vector3.new(1, 1.4, 1.4),
			CFrame.new(-exW / 2 + 0.2, 12.2, (i - (bulbs + 1) / 2) * 2.2),
			Rarity.color(Rarity.ORDER[i]),
			Enum.Material.Neon
		)
	end

	-- Higher than the other two stalls' labels, which sit at postH + 7: the
	-- hopper now occupies that height and would swallow the billboard.
	local exchangeAnchor = exchange("ExchangeLabel", Vector3.new(1, 1, 1), CFrame.new(0, exPostH + 12, 0), pal.machineGlow)
	exchangeAnchor.Transparency = 1
	exchangeAnchor.CanCollide = false

	local exchangeGui = Instance.new("BillboardGui")
	exchangeGui.Size = UDim2.fromOffset(220, 70)
	exchangeGui.AlwaysOnTop = false
	exchangeGui.MaxDistance = 260
	exchangeGui.Parent = exchangeAnchor

	local exchangeText = Instance.new("TextLabel")
	exchangeText.Size = UDim2.fromScale(1, 1)
	exchangeText.BackgroundTransparency = 1
	exchangeText.Font = Enum.Font.GothamBlack
	exchangeText.TextScaled = true
	exchangeText.Text = "CONVERT"
	exchangeText.TextColor3 = pal.machineGlow
	exchangeText.Parent = exchangeGui
	worldLabelStroke(exchangeText)

	--------------------------------------------------------------------
	-- Tool shop
	--------------------------------------------------------------------
	marketStall(shopAt("tools", "shop"), "Tool", pal.toolStripe, "TOOLS", pal.toolStripe, dressTools)

	return built
end
--[[
	Roblox picks at random among enabled SpawnLocations, so a place that ships
	with the stock one at the origin will drop half its players ~50 studs from
	the shaft with no idea where to go.

	Disabled rather than destroyed: this is someone else's place content, the
	change is trivially reversible, and the warning says exactly what happened.
]]
local function claimSpawns()
	local disabled = {}

	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and not descendant:IsDescendantOf(hubFolder) and descendant.Enabled then
			descendant.Enabled = false
			table.insert(disabled, descendant:GetFullName())
		end
	end

	if #disabled > 0 then
		warn(
			`[MineService] disabled {#disabled} SpawnLocation(s) outside the hub so players spawn at the `
				.. `shaft: {table.concat(disabled, ", ")}. Delete them from the place, or re-enable them if `
				.. `this was deliberate.`
		)
	end
end

-- ==========================================================================
-- Edit-mode preview
-- ==========================================================================

--[[
	Builds the surface -- hub floor, retaining wall and the empty plot
	shells -- into Workspace without running the game, so it can be looked at
	and adjusted in Edit mode. From the command bar:

		require(game.ServerScriptService.Server.Services.MineService).buildPreview()

	and .clearPreview() to remove it again.

	Surface only. The mine is streamed in chunks around a player's character,
	and in Edit mode there is no character to stream around, so there is nothing
	sensible to show below the lip of the shaft. Podiums come up empty for the
	same reason: their contents live in player profiles.

	The folder is found by name so Start() can delete a stale one: a preview
	left behind in a saved place would otherwise sit inside the real hub at
	runtime, doubled and z-fighting.
]]
local PREVIEW_NAME = "HubPreview"

function MineService.clearPreview(): boolean
	local existing = Workspace:FindFirstChild(PREVIEW_NAME)
	if existing then
		existing:Destroy()
		return true
	end
	return false
end

function MineService.buildPreview(): string
	MineService.clearPreview()

	local folder = Instance.new("Folder")
	folder.Name = PREVIEW_NAME

	--[[
		buildHub and buildWall both parent into the hubFolder upvalue, so
		point that at the preview folder for the duration rather than copying
		their bodies -- a copy is a second definition of the surface, and the two
		would drift the first time either was touched.
	]]
	local previous = hubFolder
	hubFolder = folder

	local ok, err = pcall(function()
		buildHub()
		buildWall()
		buildPlaza()
		buildPlazaFurniture()
		buildShops()
		buildDecor()
	end)

	hubFolder = previous

	if not ok then
		folder:Destroy()
		error(`[MineService] preview build failed: {err}`, 0)
	end

	--[[
		Plots belong to PlotService. Required lazily and guarded, so that a
		convenience for Edit mode never becomes a reason for MineService to
		depend on a sibling service on the boot path.
	]]
	local okPlots, plotsErr = pcall(function()
		require(script.Parent.PlotService).appendPreview(folder)
	end)
	if not okPlots then
		warn(`[MineService] preview: plots skipped ({plotsErr})`)
	end

	-- Same arrangement for the boards, and the same reason: a convenience for
	-- Edit must never become a boot-path dependency on a sibling service.
	local okBoards, boardsErr = pcall(function()
		require(script.Parent.LeaderboardService).appendPreview(folder)
	end)
	if not okBoards then
		warn(`[MineService] preview: leaderboards skipped ({boardsErr})`)
	end

	folder.Parent = Workspace

	local parts = 0
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	return `{PREVIEW_NAME}: {parts} parts`
end

-- ==========================================================================
-- Diagnostics
-- ==========================================================================

--[[
	Returns the character to the hub.

	The mine had no way back up: from Magmadeep it was roughly ninety seconds of
	jumping, which is not a challenge, it is a walk. Now that ore can only be
	sold at the stall, that walk is on the critical path of the loop and had to
	go.

	PivotTo rather than setting the root's CFrame, so the whole assembly moves
	together -- a tool welded to the hand stays welded. Velocity is cleared
	first, or a player who was falling arrives at the hub still falling and
	punches straight through the floor.
]]
function MineService.returnToSurface(player: Player): boolean
	local character = player.Character
	if not character or not character.Parent then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end

	-- Scatter arrivals across the spawn pad. Two players riding up together on
	-- the same stud shove each other off it.
	local spread = 3
	local offset = Vector3.new((math.random() - 0.5) * 2 * spread, 0, (math.random() - 0.5) * 2 * spread)

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(CFrame.new(hubSpawnPosition + offset))
	return true
end

function MineService.stats()
	local activeCount, chunkCount, brokenCount, damagedCount = 0, 0, 0, 0
	for _ in active do
		activeCount += 1
	end
	for _ in liveChunks do
		chunkCount += 1
	end
	for _ in broken do
		brokenCount += 1
	end
	for _ in damage do
		damagedCount += 1
	end

	local tileCount = 0
	for _, block in active do
		for _, child in block.part:GetChildren() do
			if child:IsA("BasePart") and child.Name == "Pixel" then
				tileCount += 1
			end
		end
	end

	return {
		activeBlocks = activeCount,
		liveChunks = chunkCount,
		brokenBlocks = brokenCount,
		damagedBlocks = damagedCount,
		pooledParts = #pool,
		activeTiles = tileCount,
		pooledTiles = #patchPool,
		wallTiles = wallTileCount,
		maxGy = MAX_GY,
	}
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function MineService.Init()
	-- Ungated spawn tables, one per layer, built once. Rebirth-locked ore is
	-- included: the world is shared, so generation cannot vary per player.
	for index = 1, LayerConfig.COUNT do
		spawnTables[index] = OreConfig.spawnTableForLayer(index, math.huge) :: any

		-- Filler-only variant for the ore-free surface rows.
		local filler = {}
		for _, entry in spawnTables[index] do
			if entry.rarity == "Common" then
				table.insert(filler, entry)
			end
		end
		fillerTables[index] = filler
	end

	mineFolder = trove:Add(Instance.new("Folder"))
	mineFolder.Name = "Mine"

	hubFolder = trove:Add(Instance.new("Folder"))
	hubFolder.Name = "Hub"

	for _ = 1, GameConfig.BlockPoolPrewarm do
		table.insert(pool, createPart())
	end
end

function MineService.Start()
	--[[
		Roblox destroys any part below FallenPartsDestroyHeight, which defaults
		to -500. The mine floor is at -1040, so on the default a player mining
		Magmadeep or The Static has their character deleted out from under them.

		The property is plugin-security and cannot be written from a script, so
		it's set in default.project.json instead. Verify it here rather than
		assuming: a place built without that project file would look fine right
		up until someone reached the deep layers.
	]]
	local floorY = GameConfig.SurfaceY - LayerConfig.MAX_DEPTH - GameConfig.VoidCatchMargin
	if Workspace.FallenPartsDestroyHeight > floorY then
		warn(
			`[MineService] Workspace.FallenPartsDestroyHeight is {Workspace.FallenPartsDestroyHeight}, `
				.. `above the void-catch line ({floorY}). Characters will be destroyed before they can be `
				.. `rescued, and players in the deepest layers will be deleted. Set it to {floorY - 200} `
				.. `in Workspace's properties.`
		)
	end

	-- A preview left in a saved place would sit inside the real hub, doubled
	-- and z-fighting. Clear it before anything else builds.
	MineService.clearPreview()

	local AntiCheatService = require(script.Parent.AntiCheatService)
	RemoteRegistry.func("RequestSurfaceTeleport").OnServerInvoke = function(player: Player)
		if not AntiCheatService.guard(player, "RequestSurfaceTeleport") then
			return { ok = false, reason = "rate_limited" }
		end
		if not MineService.returnToSurface(player) then
			return { ok = false, reason = "no_character" }
		end
		return { ok = true }
	end

	buildHub()
	buildWall()
	buildPlaza()
	buildPlazaFurniture()
	buildShops()
	buildDecor()
	hubFolder.Parent = Workspace
	mineFolder.Parent = Workspace
	claimSpawns()

	MineService.MineFolder = mineFolder

	trove:Add(task.spawn(function()
		while true do
			task.wait(GameConfig.ChunkStreamTickSeconds)
			local ok, err = pcall(streamPass)
			if not ok then
				warn(`[MineService] stream pass failed: {err}`)
			end
		end
	end))

	trove:Add(task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(regrowPass)
			if not ok then
				warn(`[MineService] regrow pass failed: {err}`)
			end
		end
	end))

	--[[
		Void catcher. The safety pass should stop anyone falling through
		unloaded floor, but a player can still end up under the world by
		clipping a corner or being pushed. Rather than let them fall forever,
		return them to the hub.

		This is a backstop, not the fix -- if it starts firing regularly, the
		streaming budget is the thing to look at.
	]]
	trove:Add(task.spawn(function()
		while true do
			task.wait(GameConfig.VoidCatchTickSeconds)

			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and root.Position.Y < floorY then
					root.AssemblyLinearVelocity = Vector3.zero
					root.CFrame = CFrame.new(hubSpawnPosition)
					warn(`[MineService] caught {player.Name} below the mine floor; returned to hub`)
				end
			end
		end
	end))
end

function MineService.Stop()
	trove:Clean()
	table.clear(active)
	table.clear(liveChunks)
	table.clear(pool)
end

return MineService
