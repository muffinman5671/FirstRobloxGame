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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LayerConfig = require(ReplicatedStorage.Shared.Config.LayerConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

local MineService = {}
MineService.Name = "MineService"

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
	part.Material = Enum.Material.Slate
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
local function applyPatches(part: BasePart, gx: number, gy: number, gz: number, material: Enum.Material, base: Color3)
	releasePatches(part)

	if GameConfig.PixelTilesPerBlock <= 0 then
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

	for index = 1, GameConfig.PixelTilesPerBlock do
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
			patch.Material = material
			patch.Color = quantize(base, (shadeOf(gx, gy, gz) + GameConfig.PixelTileShadeOffset + index) % GameConfig.PaletteShades)
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
		if topExposed and layer.topMaterial then
			material = layer.topMaterial
			base = layer.topColor or layer.baseColor
		else
			material = layer.material
			base = layer.baseColor
		end
		reflectance = 0
	else
		-- Ore veins are metallic and reflective against the matte rock, scaled
		-- by rarity, so something valuable is obvious without a UI marker.
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
		applyPatches(part, gx, gy, gz, material, base)
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

local function buildHub()
	local half = (RADIUS + 0.5) * BLOCK
	local cx, cz = GameConfig.ShaftCenterX, GameConfig.ShaftCenterZ
	local extent = GameConfig.HubExtent
	local thickness = GameConfig.HubThickness
	local y = GameConfig.SurfaceY - thickness * 0.5

	-- Four slabs forming a ring, leaving a square opening over the shaft.
	local slabs = {
		{ minX = -extent, maxX = extent, minZ = -extent, maxZ = cz - half },
		{ minX = -extent, maxX = extent, minZ = cz + half, maxZ = extent },
		{ minX = -extent, maxX = cx - half, minZ = cz - half, maxZ = cz + half },
		{ minX = cx + half, maxX = extent, minZ = cz - half, maxZ = cz + half },
	}

	for index, slab in slabs do
		local sizeX = slab.maxX - slab.minX
		local sizeZ = slab.maxZ - slab.minZ
		if sizeX > 0 and sizeZ > 0 then
			local part = Instance.new("Part")
			part.Name = `HubSlab{index}`
			part.Anchored = true
			part.Locked = true
			part.Size = Vector3.new(sizeX, thickness, sizeZ)
			part.Position = Vector3.new((slab.minX + slab.maxX) * 0.5, y, (slab.minZ + slab.maxZ) * 0.5)
			part.Color = Color3.fromRGB(112, 108, 100)
			part.Material = Enum.Material.Ground
			part.TopSurface = Enum.SurfaceType.Smooth
			part.Parent = hubFolder
		end
	end

	-- Spawn right at the lip of the shaft. Anywhere further and a new player has
	-- to work out that the grass square in the middle of a grey floor is the
	-- thing they're meant to walk to.
	local spawn = Instance.new("SpawnLocation")
	hubSpawnPosition = Vector3.new(cx, GameConfig.SurfaceY + 4, cz - half - 6)
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Locked = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(cx, GameConfig.SurfaceY + 0.5, cz - half - 6)
	spawn.Color = Color3.fromRGB(86, 196, 118)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Parent = hubFolder
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
-- Diagnostics
-- ==========================================================================

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

	buildHub()
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
