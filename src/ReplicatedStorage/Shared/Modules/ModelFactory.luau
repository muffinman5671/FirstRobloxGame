--!strict
--[[
	ModelFactory
	Builds every brainrot from Instance.new primitives. No meshes, no textures,
	no asset IDs -- see DESIGN.md §2.

	Art pass, not blockouts. Each character is 10-16 flat blocks chosen to make
	its silhouette readable from across a plot, in the brutalist / pixelated /
	cartoony direction: hard edges, flat colour, no gradients, no smooth shapes
	where a blocky one will read.

	Authoring
	  Builders use a small fluent DSL rather than writing part tables by hand.
	  `pair` mirrors across X, which is most of what a creature is -- legs,
	  arms, ears, eyes, wings -- and halves both the typing and the chance of a
	  lopsided character.

	      b:add(size, offset, colour, opts)   one part
	      b:pair(size, offset, colour, opts)  that part and its mirror
	      b:eyes(spread, y, z, size, colour)  a symmetric pair of eyes

	  `opts` takes { shape = "Ball" | "Cylinder", rot = Vector3 (degrees),
	  material = Enum.Material }. Rotations are mirrored correctly by `pair`,
	  so a limb angled outward on one side angles outward on the other.

	Models are ground-aligned and scaled to GameConfig.BrainrotHeight at build
	time, so a builder can work in whatever units read most naturally.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local ModelFactory = {}

-- ==========================================================================
-- Palette
-- ==========================================================================

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local C = {
	skin = rgb(224, 178, 132),
	fur = rgb(132, 92, 60),
	darkFur = rgb(88, 60, 40),
	paleFur = rgb(198, 160, 118),
	grey = rgb(158, 162, 170),
	darkGrey = rgb(88, 92, 100),
	steel = rgb(122, 130, 142),
	white = rgb(244, 246, 250),
	bone = rgb(226, 220, 202),
	black = rgb(30, 30, 36),
	green = rgb(104, 188, 88),
	darkGreen = rgb(58, 126, 58),
	leaf = rgb(74, 158, 68),
	blue = rgb(72, 146, 226),
	navy = rgb(34, 62, 132),
	sky = rgb(126, 196, 240),
	red = rgb(222, 68, 58),
	darkRed = rgb(150, 40, 36),
	orange = rgb(244, 148, 46),
	yellow = rgb(246, 214, 70),
	gold = rgb(226, 176, 48),
	brown = rgb(146, 100, 58),
	cream = rgb(242, 224, 178),
	pink = rgb(242, 152, 180),
	purple = rgb(158, 98, 220),
	teal = rgb(66, 190, 182),
	wood = rgb(164, 120, 72),
	darkWood = rgb(116, 82, 48),
	metal = rgb(182, 188, 198),
	lava = rgb(238, 106, 40),
}

-- ==========================================================================
-- Builder DSL
-- ==========================================================================

type Spec = {
	size: Vector3,
	offset: Vector3,
	color: Color3,
	shape: string?,
	rotation: Vector3?,
	material: Enum.Material?,
}

type Opts = { shape: string?, rot: Vector3?, material: Enum.Material? }

local Build = {}
Build.__index = Build

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function newBuild()
	return setmetatable({ specs = {} :: { Spec } }, Build)
end

function Build:add(size: Vector3, offset: Vector3, color: Color3, opts: Opts?)
	table.insert(self.specs, {
		size = size,
		offset = offset,
		color = color,
		shape = opts and opts.shape,
		rotation = opts and opts.rot,
		material = opts and opts.material,
	})
	return self
end

-- Adds the part and its mirror across X. Yaw and roll are negated so an arm
-- angled away from the body on one side does the same on the other.
function Build:pair(size: Vector3, offset: Vector3, color: Color3, opts: Opts?)
	self:add(size, offset, color, opts)

	local rot = opts and opts.rot
	local mirroredRot = if rot then v(rot.X, -rot.Y, -rot.Z) else nil
	self:add(size, v(-offset.X, offset.Y, offset.Z), color, {
		shape = opts and opts.shape,
		rot = mirroredRot,
		material = opts and opts.material,
	})
	return self
end

-- Eyes are frequent enough, and fiddly enough to get symmetric by hand, to
-- deserve their own verb. Adds a dark pupil in front of a pale sclera.
function Build:eyes(spread: number, y: number, z: number, size: number, sclera: Color3?)
	self:pair(v(size, size, size * 0.55), v(spread, y, z), sclera or C.white, { shape = "Ball" })
	self:pair(v(size * 0.5, size * 0.5, size * 0.4), v(spread, y, z + size * 0.32), C.black, { shape = "Ball" })
	return self
end

-- ==========================================================================
-- Builders
-- ==========================================================================

local BUILDERS: { [string]: () -> { Spec } } = {}

-- ---------- Common ----------

BUILDERS.buildBobritoBandito = function()
	local b = newBuild()
	b:add(v(3.4, 2.6, 2.4), v(0, 1.5, 0), C.fur)
	b:add(v(2.6, 0.8, 2.0), v(0, 0.5, 0.3), C.paleFur)
	b:add(v(2.2, 1.9, 1.9), v(0, 3.4, 0.3), C.fur)
	b:add(v(2.3, 0.75, 0.35), v(0, 3.6, 1.25), C.black)
	b:add(v(1.0, 0.6, 0.5), v(0, 3.0, 1.25), C.darkFur)
	b:add(v(0.9, 0.5, 0.2), v(0, 2.75, 1.35), C.white)
	b:eyes(0.62, 3.65, 1.15, 0.42)
	b:pair(v(0.55, 0.55, 0.3), v(0.95, 4.3, 0.2), C.darkFur)
	b:add(v(2.8, 0.45, 1.9), v(0, 0.45, -1.9), C.darkFur, { rot = v(-12, 0, 0) })
	b:pair(v(0.85, 0.95, 0.9), v(1.0, 0.5, 0.95), C.darkFur)
	b:pair(v(0.7, 1.5, 0.7), v(1.75, 1.6, 0.2), C.fur, { rot = v(0, 0, -14) })
	return b.specs
end

BUILDERS.buildBonecaAmbalabu = function()
	local b = newBuild()
	b:add(v(4.0, 1.5, 4.0), v(0, 0.75, 0), C.black, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(3.0, 1.0, 3.0), v(0, 0.75, 0), C.darkGrey, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(2.2, 1.9, 2.2), v(0, 2.5, 0.1), C.green, { shape = "Ball" })
	b:add(v(2.0, 0.5, 1.6), v(0, 1.85, 0.4), C.darkGreen)
	b:eyes(0.66, 3.35, 0.55, 0.62)
	b:pair(v(0.5, 1.7, 0.5), v(1.25, 0.85, 0.2), C.green, { rot = v(0, 0, 16) })
	b:pair(v(0.9, 0.4, 1.2), v(1.35, 0.2, 0.7), C.darkGreen)
	b:pair(v(0.45, 1.3, 0.45), v(1.0, 2.6, -0.5), C.green, { rot = v(0, 0, -34) })
	return b.specs
end

BUILDERS.buildTrippiTroppi = function()
	local b = newBuild()
	b:add(v(3.0, 1.7, 2.2), v(0, 0.95, 0), C.orange)
	b:add(v(2.6, 0.6, 1.9), v(0, 1.75, -0.1), C.red)
	b:add(v(1.9, 1.7, 1.7), v(0, 2.6, 0.5), C.cream)
	b:add(v(0.7, 0.4, 0.4), v(0, 2.45, 1.35), C.pink)
	b:eyes(0.52, 2.85, 0.95, 0.44)
	b:pair(v(0.55, 0.85, 0.4), v(0.68, 3.55, 0.4), C.cream)
	b:pair(v(0.28, 0.5, 0.22), v(0.68, 3.6, 0.4), C.pink)
	b:add(v(0.6, 0.6, 1.5), v(0, 1.1, -1.75), C.orange)
	b:add(v(0.55, 1.1, 0.9), v(0, 1.8, -2.4), C.orange, { rot = v(38, 0, 0) })
	b:pair(v(0.75, 0.7, 1.0), v(1.0, 0.35, 0.75), C.orange)
	return b.specs
end

BUILDERS.buildTrulimeroTrulicina = function()
	local b = newBuild()
	b:add(v(1.9, 2.2, 3.4), v(0, 1.5, 0), C.blue)
	b:add(v(1.5, 0.8, 3.0), v(0, 0.7, 0), C.sky)
	b:add(v(1.6, 1.6, 1.6), v(0, 3.0, 0.9), C.cream)
	b:eyes(0.46, 3.25, 1.55, 0.42)
	b:pair(v(0.45, 0.8, 0.35), v(0.55, 3.9, 0.85), C.cream)
	b:add(v(0.35, 1.7, 1.5), v(0, 1.9, -2.1), C.navy, { rot = v(18, 0, 0) })
	b:pair(v(1.3, 0.3, 0.9), v(1.1, 1.4, 0.2), C.navy, { rot = v(0, 0, -22) })
	b:add(v(0.3, 1.1, 0.9), v(0, 2.9, -0.6), C.navy)
	b:pair(v(0.8, 0.9, 0.8), v(1.05, 0.45, 0.7), C.blue)
	return b.specs
end

BUILDERS.buildBananitaDolphinita = function()
	local b = newBuild()
	b:add(v(1.9, 2.0, 3.6), v(0, 1.7, 0), C.yellow)
	b:add(v(1.5, 1.2, 1.7), v(0, 1.7, 2.3), C.yellow, { rot = v(-10, 0, 0) })
	b:add(v(1.0, 0.7, 0.9), v(0, 1.5, 3.1), C.cream)
	b:add(v(1.6, 0.9, 1.4), v(0, 2.6, -1.5), C.gold)
	b:add(v(0.7, 0.9, 0.7), v(0, 3.3, -1.9), C.darkGreen)
	b:add(v(0.4, 1.4, 1.1), v(0, 3.0, -0.2), C.cream)
	b:eyes(0.55, 2.15, 2.55, 0.4)
	b:pair(v(1.2, 0.28, 0.85), v(1.1, 1.3, 0.4), C.cream, { rot = v(0, 0, -18) })
	b:add(v(0.3, 1.0, 1.4), v(0, 1.9, -2.4), C.cream)
	return b.specs
end

BUILDERS.buildPiccioneMacchina = function()
	local b = newBuild()
	b:add(v(3.6, 1.3, 2.3), v(0, 1.0, 0), C.grey)
	b:add(v(3.2, 0.5, 2.1), v(0, 1.75, 0), C.red)
	b:add(v(2.1, 1.1, 1.8), v(0, 2.3, -0.35), C.darkGrey)
	b:add(v(1.9, 0.8, 0.2), v(0, 2.35, 0.5), C.sky)
	b:add(v(1.3, 1.4, 1.3), v(0, 2.9, 1.25), C.teal)
	b:add(v(0.5, 0.42, 0.75), v(0, 2.8, 2.05), C.orange)
	b:eyes(0.42, 3.2, 1.75, 0.34)
	b:add(v(1.0, 0.5, 0.9), v(0, 3.7, 0.8), C.teal)
	b:pair(v(1.0, 1.0, 0.55), v(1.55, 0.55, 1.15), C.black, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:pair(v(1.0, 1.0, 0.55), v(1.55, 0.55, -1.15), C.black, { shape = "Cylinder", rot = v(0, 0, 90) })
	return b.specs
end

-- ---------- Uncommon ----------

BUILDERS.buildBrrBrrPatapim = function()
	local b = newBuild()
	b:add(v(2.7, 3.4, 2.7), v(0, 1.8, 0), C.wood)
	b:add(v(2.9, 0.5, 2.9), v(0, 0.3, 0), C.darkWood)
	b:add(v(2.2, 1.8, 2.0), v(0, 4.2, 0.15), C.skin)
	b:add(v(1.1, 0.8, 1.0), v(0, 3.95, 1.15), C.skin)
	b:add(v(0.5, 0.3, 0.3), v(0, 3.6, 1.5), C.darkFur)
	b:eyes(0.62, 4.6, 0.95, 0.46)
	b:add(v(3.4, 0.7, 1.2), v(0, 5.3, -0.2), C.darkGreen)
	b:add(v(2.4, 0.6, 1.0), v(0, 5.8, -0.4), C.leaf)
	b:pair(v(0.85, 1.9, 0.85), v(1.75, 1.7, 0), C.wood, { rot = v(0, 0, 26) })
	b:pair(v(0.7, 0.7, 0.7), v(2.35, 2.7, 0), C.darkWood)
	b:pair(v(1.1, 0.65, 1.8), v(0.75, 0.32, 0.7), C.darkWood)
	return b.specs
end

BUILDERS.buildChimpanziniBananini = function()
	local b = newBuild()
	b:add(v(2.1, 3.4, 2.1), v(0, 1.9, 0), C.yellow)
	b:add(v(1.7, 0.9, 1.7), v(0, 3.8, 0), C.gold)
	b:add(v(0.8, 0.9, 0.8), v(0, 4.35, 0), C.darkGreen)
	b:add(v(0.35, 2.6, 1.5), v(1.05, 2.0, 0), C.gold, { rot = v(0, 0, 8) })
	b:add(v(1.7, 1.5, 1.4), v(0, 2.7, 1.0), C.fur)
	b:add(v(1.2, 0.9, 0.9), v(0, 2.35, 1.5), C.paleFur)
	b:eyes(0.44, 2.95, 1.6, 0.38)
	b:pair(v(0.55, 0.7, 0.32), v(0.95, 2.95, 0.75), C.fur)
	b:pair(v(0.75, 1.6, 0.75), v(1.35, 1.4, 0.1), C.fur, { rot = v(0, 0, 12) })
	b:pair(v(0.8, 0.6, 1.1), v(0.7, 0.3, 0.5), C.fur)
	return b.specs
end

BUILDERS.buildCappuccinoAssassino = function()
	local b = newBuild()
	b:add(v(2.7, 2.5, 2.7), v(0, 1.4, 0), C.white, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(2.9, 0.4, 2.9), v(0, 2.75, 0), C.brown, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(2.4, 0.35, 2.4), v(0, 2.95, 0), C.cream, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(3.0, 0.5, 3.0), v(0, 0.25, 0), C.bone, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(0.4, 1.3, 1.3), v(1.55, 1.5, 0), C.white)
	b:eyes(0.55, 2.0, 1.3, 0.44)
	b:add(v(1.0, 0.25, 0.3), v(0, 1.35, 1.35), C.black)
	b:pair(v(0.55, 1.9, 0.55), v(1.5, 1.5, 0.35), C.black, { rot = v(0, 0, 32) })
	b:add(v(0.28, 2.4, 0.5), v(2.15, 2.6, 0.35), C.metal, { rot = v(0, 0, -46) })
	b:pair(v(0.8, 0.85, 1.1), v(0.75, 0.42, 0.6), C.black)
	return b.specs
end

BUILDERS.buildBurbaloniLuliloli = function()
	local b = newBuild()
	b:add(v(3.4, 3.2, 3.4), v(0, 1.7, 0), C.brown, { shape = "Ball" })
	b:pair(v(0.9, 0.35, 0.9), v(0.9, 3.1, -0.4), C.darkWood)
	b:add(v(1.9, 1.7, 1.5), v(0, 2.5, 1.5), C.fur)
	b:add(v(1.3, 0.9, 0.7), v(0, 2.2, 2.1), C.paleFur)
	b:add(v(0.5, 0.35, 0.3), v(0, 2.5, 2.4), C.darkFur)
	b:eyes(0.55, 3.05, 2.0, 0.42)
	b:pair(v(0.5, 0.5, 0.35), v(0.85, 3.5, 1.35), C.fur)
	b:pair(v(0.95, 0.6, 1.0), v(1.05, 0.32, 0.9), C.fur)
	b:pair(v(0.6, 0.55, 0.6), v(1.55, 1.5, 0.9), C.fur, { rot = v(0, 0, -20) })
	return b.specs
end

BUILDERS.buildGlorboFruttodrillo = function()
	local b = newBuild()
	b:add(v(2.4, 1.7, 4.2), v(0, 1.0, 0), C.green)
	b:add(v(2.0, 0.9, 2.2), v(0, 0.95, 2.6), C.darkGreen)
	b:add(v(1.9, 0.35, 2.0), v(0, 1.35, 2.6), C.green)
	b:add(v(1.7, 0.22, 1.9), v(0, 1.1, 2.6), C.white)
	b:add(v(2.6, 2.2, 2.4), v(0, 2.6, -1.1), C.red, { shape = "Ball" })
	b:add(v(0.7, 0.8, 0.7), v(0, 3.7, -1.4), C.darkGreen)
	b:eyes(0.6, 1.95, 2.35, 0.44, C.yellow)
	b:pair(v(0.4, 0.5, 0.4), v(0.55, 2.0, 0.2), C.darkGreen)
	b:pair(v(0.4, 0.5, 0.4), v(0.55, 2.0, -0.6), C.darkGreen)
	b:pair(v(0.85, 0.7, 0.9), v(1.15, 0.36, 1.5), C.darkGreen)
	b:pair(v(0.85, 0.7, 0.9), v(1.15, 0.36, -1.2), C.darkGreen)
	b:add(v(0.5, 0.6, 1.6), v(0, 0.9, -2.6), C.green, { rot = v(-14, 0, 0) })
	return b.specs
end

BUILDERS.buildFrigoCamelo = function()
	local b = newBuild()
	b:add(v(3.0, 4.2, 2.5), v(0, 2.3, 0), C.white)
	b:add(v(0.18, 4.0, 2.3), v(1.5, 2.3, 0), C.grey)
	b:add(v(0.25, 1.6, 0.25), v(1.5, 2.9, 1.0), C.steel)
	b:add(v(3.1, 0.35, 2.6), v(0, 4.55, 0), C.grey)
	b:add(v(1.4, 1.1, 1.4), v(0, 5.15, -0.5), C.cream)
	b:add(v(1.7, 1.5, 1.5), v(0, 5.0, 1.2), C.cream)
	b:add(v(1.0, 0.8, 0.8), v(0, 4.7, 1.9), C.paleFur)
	b:eyes(0.5, 5.35, 1.75, 0.4)
	b:pair(v(0.42, 0.9, 0.35), v(0.62, 5.85, 0.9), C.cream)
	b:pair(v(0.75, 1.0, 0.75), v(1.05, 0.5, 0.85), C.cream)
	b:pair(v(0.75, 1.0, 0.75), v(1.05, 0.5, -0.85), C.cream)
	return b.specs
end

-- ---------- Rare ----------

BUILDERS.buildTralaleroTralala = function()
	local b = newBuild()
	b:add(v(2.3, 2.3, 5.0), v(0, 2.1, 0), C.blue)
	b:add(v(1.9, 1.0, 4.2), v(0, 1.3, 0.2), C.white)
	b:add(v(1.7, 1.5, 2.0), v(0, 2.1, 2.9), C.blue)
	b:add(v(1.6, 0.35, 1.8), v(0, 1.45, 2.9), C.white)
	b:add(v(1.5, 0.2, 1.7), v(0, 1.6, 2.95), C.black)
	b:eyes(0.62, 2.6, 3.1, 0.42)
	b:add(v(0.42, 1.9, 1.3), v(0, 3.8, -0.3), C.navy, { rot = v(-12, 0, 0) })
	b:pair(v(1.5, 0.32, 1.0), v(1.2, 1.7, 0.4), C.navy, { rot = v(0, 0, -24) })
	b:add(v(0.35, 1.8, 1.4), v(0, 2.6, -3.0), C.navy, { rot = v(24, 0, 0) })
	b:pair(v(1.25, 0.55, 2.2), v(1.0, 0.65, 1.5), C.white)
	b:pair(v(1.3, 0.42, 2.3), v(1.0, 0.24, 1.5), C.red)
	b:pair(v(1.28, 0.18, 0.9), v(1.0, 0.95, 1.9), C.white)
	return b.specs
end

BUILDERS.buildTungTungTungSahur = function()
	local b = newBuild()
	b:add(v(2.5, 4.0, 2.5), v(0, 2.2, 0), C.wood)
	b:add(v(2.7, 0.45, 2.7), v(0, 4.35, 0), C.darkWood)
	b:add(v(2.7, 0.45, 2.7), v(0, 0.35, 0), C.darkWood)
	b:add(v(1.6, 0.55, 0.25), v(0, 2.9, 1.3), C.black)
	b:eyes(0.5, 2.9, 1.28, 0.42)
	b:add(v(1.2, 0.9, 0.28), v(0, 1.7, 1.3), C.black)
	b:add(v(1.0, 0.3, 0.2), v(0, 1.95, 1.38), C.white)
	b:pair(v(0.65, 2.2, 0.65), v(1.55, 2.5, 0), C.wood, { rot = v(0, 0, 18) })
	b:add(v(0.5, 2.8, 0.5), v(2.3, 3.5, 0), C.darkWood, { rot = v(0, 0, -52) })
	b:add(v(0.75, 0.9, 0.75), v(3.15, 4.2, 0), C.brown)
	b:pair(v(0.95, 0.75, 1.6), v(0.72, 0.38, 0.4), C.darkWood)
	return b.specs
end

BUILDERS.buildBallerinaCappuccina = function()
	local b = newBuild()
	b:add(v(2.4, 2.3, 2.4), v(0, 4.0, 0), C.white, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(2.6, 0.35, 2.6), v(0, 5.15, 0), C.brown, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(2.1, 0.3, 2.1), v(0, 5.32, 0), C.cream, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(0.35, 1.1, 1.1), v(1.35, 4.0, 0), C.white)
	b:eyes(0.5, 4.35, 1.25, 0.4)
	b:add(v(0.7, 0.2, 0.25), v(0, 3.6, 1.25), C.pink)
	b:add(v(1.3, 2.1, 1.0), v(0, 2.0, 0), C.pink)
	b:add(v(3.2, 0.55, 3.2), v(0, 1.25, 0), C.pink, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(2.6, 0.4, 2.6), v(0, 1.55, 0), C.white, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:pair(v(0.5, 1.5, 0.5), v(0.45, 0.75, 0), C.cream)
	b:pair(v(0.6, 0.3, 0.9), v(0.45, 0.15, 0.25), C.pink)
	b:pair(v(0.48, 1.7, 0.48), v(1.15, 2.7, 0), C.cream, { rot = v(0, 0, 42) })
	return b.specs
end

BUILDERS.buildLiriliLarila = function()
	local b = newBuild()
	b:add(v(2.8, 2.6, 3.2), v(0, 2.4, 0), C.grey)
	b:add(v(2.2, 1.9, 1.7), v(0, 3.1, 1.9), C.grey)
	b:add(v(0.8, 2.4, 0.8), v(0, 2.0, 2.5), C.grey, { rot = v(26, 0, 0) })
	b:add(v(0.7, 0.7, 0.7), v(0, 0.95, 3.15), C.darkGrey)
	b:pair(v(0.35, 1.8, 1.8), v(1.3, 3.3, 1.75), C.grey)
	b:eyes(0.62, 3.6, 2.6, 0.42)
	b:pair(v(0.32, 0.32, 1.0), v(0.75, 2.35, 2.5), C.bone, { rot = v(-18, 0, 0) })
	b:add(v(1.9, 1.9, 0.35), v(0, 2.8, -1.8), C.cream)
	b:add(v(1.6, 1.6, 0.2), v(0, 2.8, -1.95), C.bone)
	b:add(v(0.16, 0.9, 0.16), v(0, 3.1, -2.05), C.black)
	b:add(v(0.7, 0.16, 0.16), v(0.3, 2.8, -2.05), C.black)
	b:add(v(1.0, 1.5, 1.0), v(0, 4.5, -0.6), C.darkGreen)
	b:pair(v(0.4, 0.8, 0.4), v(0.65, 4.9, -0.6), C.darkGreen, { rot = v(0, 0, 24) })
	b:pair(v(0.85, 1.1, 0.85), v(0.95, 0.55, 0.9), C.grey)
	b:pair(v(0.85, 1.1, 0.85), v(0.95, 0.55, -0.9), C.grey)
	return b.specs
end

BUILDERS.buildBombombiniGusini = function()
	local b = newBuild()
	b:add(v(2.1, 1.9, 4.6), v(0, 2.0, 0), C.white)
	b:add(v(1.7, 0.7, 4.0), v(0, 1.25, 0), C.bone)
	b:add(v(1.0, 1.9, 1.0), v(0, 3.3, 1.9), C.white, { rot = v(-14, 0, 0) })
	b:add(v(1.3, 1.1, 1.5), v(0, 4.3, 2.35), C.white)
	b:add(v(0.55, 0.42, 0.9), v(0, 4.15, 3.15), C.orange)
	b:eyes(0.44, 4.55, 2.9, 0.36)
	b:add(v(5.0, 0.32, 1.3), v(0, 2.35, -0.3), C.grey)
	b:pair(v(0.5, 0.5, 1.0), v(2.2, 2.35, -0.4), C.steel)
	b:pair(v(0.95, 0.95, 1.9), v(1.0, 1.15, -1.5), C.darkGrey, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:pair(v(0.7, 0.7, 0.5), v(1.0, 1.15, -2.5), C.lava, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(0.35, 1.4, 1.1), v(0, 3.2, -2.2), C.grey)
	b:pair(v(0.9, 0.9, 1.6), v(0.75, 0.6, -0.2), C.darkRed)
	return b.specs
end

-- ---------- Epic ----------

BUILDERS.buildBombardiroCrocodilo = function()
	local b = newBuild()
	b:add(v(2.5, 2.1, 5.6), v(0, 2.4, 0), C.darkGreen)
	b:add(v(2.1, 0.9, 4.8), v(0, 1.5, 0.2), C.green)
	b:add(v(2.0, 1.2, 2.6), v(0, 2.3, 3.3), C.green)
	b:add(v(1.9, 0.35, 2.4), v(0, 1.65, 3.3), C.darkGreen)
	b:add(v(1.8, 0.22, 2.3), v(0, 1.82, 3.35), C.white)
	b:eyes(0.68, 3.05, 3.5, 0.46, C.yellow)
	b:pair(v(0.35, 0.45, 0.35), v(0.7, 3.0, 1.6), C.green)
	b:pair(v(0.35, 0.45, 0.35), v(0.7, 3.0, 0.8), C.green)
	b:add(v(6.6, 0.42, 1.7), v(0, 2.7, -0.4), C.darkGrey)
	b:pair(v(1.0, 1.0, 2.1), v(1.9, 2.05, -0.6), C.steel, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:pair(v(0.75, 0.75, 0.5), v(1.9, 2.05, -1.75), C.lava, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(0.42, 1.7, 1.5), v(0, 3.6, -2.7), C.darkGrey)
	b:pair(v(1.4, 0.3, 0.9), v(0.9, 3.5, -2.4), C.darkGrey)
	b:pair(v(0.85, 0.9, 1.7), v(0.85, 1.1, -1.4), C.darkGreen)
	return b.specs
end

BUILDERS.buildOrangutiniAnanassini = function()
	local b = newBuild()
	b:add(v(3.0, 3.4, 3.0), v(0, 1.9, 0), C.yellow)
	b:pair(v(0.5, 0.5, 0.2), v(0.7, 2.6, 1.55), C.gold)
	b:pair(v(0.5, 0.5, 0.2), v(0.7, 1.4, 1.55), C.gold)
	b:add(v(0.55, 2.1, 0.55), v(-0.65, 4.4, 0), C.darkGreen, { rot = v(0, 0, 22) })
	b:add(v(0.55, 2.5, 0.55), v(0, 4.6, 0), C.darkGreen)
	b:add(v(0.55, 2.1, 0.55), v(0.65, 4.4, 0), C.darkGreen, { rot = v(0, 0, -22) })
	b:add(v(0.5, 1.7, 0.5), v(0, 4.3, 0.7), C.leaf, { rot = v(24, 0, 0) })
	b:add(v(2.1, 1.9, 1.6), v(0, 2.8, 1.7), C.orange)
	b:add(v(1.5, 1.1, 0.9), v(0, 2.4, 2.25), C.skin)
	b:eyes(0.52, 3.15, 2.35, 0.42)
	b:pair(v(0.62, 0.85, 0.35), v(1.1, 3.2, 1.5), C.orange)
	b:pair(v(0.95, 2.3, 0.95), v(1.85, 1.7, 0.1), C.orange, { rot = v(0, 0, 14) })
	b:pair(v(0.9, 0.6, 1.2), v(0.85, 0.32, 0.6), C.orange)
	return b.specs
end

BUILDERS.buildTigrulliniWatermelini = function()
	local b = newBuild()
	b:add(v(3.4, 3.0, 3.4), v(0, 1.7, 0), C.darkGreen, { shape = "Ball" })
	b:pair(v(0.28, 2.9, 0.6), v(1.0, 1.7, 0), C.green)
	b:add(v(3.3, 0.4, 3.3), v(0, 3.05, 0), C.red, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(3.0, 0.2, 3.0), v(0, 3.2, 0), C.pink, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(2.1, 1.9, 1.7), v(0, 3.6, 1.3), C.orange)
	b:add(v(1.4, 1.0, 0.9), v(0, 3.25, 1.85), C.cream)
	b:add(v(0.5, 0.35, 0.3), v(0, 3.55, 2.15), C.pink)
	b:eyes(0.55, 3.95, 1.95, 0.44, C.yellow)
	b:pair(v(0.3, 0.95, 0.28), v(0.65, 3.6, 2.05), C.black)
	b:pair(v(0.65, 0.75, 0.42), v(0.88, 4.5, 1.15), C.orange)
	b:pair(v(0.32, 0.38, 0.22), v(0.88, 4.5, 1.32), C.pink)
	b:pair(v(0.95, 0.85, 1.0), v(1.15, 0.42, 1.25), C.orange)
	return b.specs
end

BUILDERS.buildGirafaCelestre = function()
	local b = newBuild()
	b:add(v(2.7, 2.3, 4.0), v(0, 3.2, 0), C.yellow)
	b:pair(v(0.6, 0.6, 0.6), v(0.85, 3.9, 1.0), C.brown)
	b:pair(v(0.55, 0.55, 0.55), v(0.9, 2.9, -0.8), C.brown)
	b:add(v(1.2, 4.2, 1.2), v(0, 5.9, 1.5), C.yellow, { rot = v(-10, 0, 0) })
	b:pair(v(0.45, 0.45, 0.45), v(0.4, 5.2, 1.9), C.brown)
	b:pair(v(0.45, 0.45, 0.45), v(0.4, 6.8, 1.6), C.brown)
	b:add(v(1.5, 1.3, 1.9), v(0, 8.0, 2.1), C.cream)
	b:add(v(1.0, 0.6, 0.7), v(0, 7.7, 2.9), C.paleFur)
	b:eyes(0.5, 8.35, 2.6, 0.4)
	b:pair(v(0.28, 0.75, 0.28), v(0.42, 8.9, 1.9), C.brown)
	b:pair(v(0.24, 0.24, 0.24), v(0.42, 9.3, 1.9), C.cream, { shape = "Ball" })
	b:pair(v(0.45, 0.8, 0.32), v(0.78, 8.5, 1.7), C.cream)
	b:pair(v(0.85, 2.2, 0.85), v(1.0, 1.1, 1.4), C.yellow)
	b:pair(v(0.85, 2.2, 0.85), v(1.0, 1.1, -1.4), C.yellow)
	b:add(v(0.9, 0.9, 0.9), v(0, 9.6, 2.1), C.white, { shape = "Ball" })
	return b.specs
end

-- ---------- Legendary ----------

BUILDERS.buildLaVaccaSaturnoSaturnita = function()
	local b = newBuild()
	b:add(v(3.6, 2.9, 5.0), v(0, 2.7, 0), C.white)
	b:add(v(1.7, 1.3, 1.7), v(-0.9, 3.6, 1.2), C.black)
	b:add(v(1.5, 1.1, 1.5), v(1.0, 2.5, -1.5), C.black)
	b:add(v(1.2, 1.0, 1.2), v(-1.1, 2.3, -0.4), C.black)
	b:add(v(2.1, 1.9, 1.8), v(0, 3.4, 3.1), C.white)
	b:add(v(1.4, 1.0, 0.9), v(0, 2.95, 3.8), C.pink)
	b:pair(v(0.3, 0.3, 0.25), v(0.4, 3.0, 4.2), C.black, { shape = "Ball" })
	b:eyes(0.6, 3.9, 3.85, 0.44)
	b:pair(v(0.42, 0.85, 0.4), v(0.78, 4.4, 2.9), C.cream, { rot = v(0, 0, 18) })
	b:pair(v(0.5, 0.55, 0.35), v(1.15, 3.6, 2.9), C.white)
	b:pair(v(0.9, 2.5, 0.9), v(1.25, 1.25, 1.7), C.white)
	b:pair(v(0.92, 0.7, 0.92), v(1.25, 0.35, 1.7), C.black)
	b:pair(v(0.9, 2.5, 0.9), v(1.25, 1.25, -1.7), C.white)
	b:pair(v(0.92, 0.7, 0.92), v(1.25, 0.35, -1.7), C.black)
	b:add(v(9.4, 0.3, 9.4), v(0, 3.3, 0), C.orange, { shape = "Cylinder", rot = v(6, 0, 90) })
	b:add(v(8.0, 0.22, 8.0), v(0, 3.45, 0), C.gold, { shape = "Cylinder", rot = v(6, 0, 90) })
	return b.specs
end

BUILDERS.buildChimpanziniSpiderini = function()
	local b = newBuild()
	b:add(v(3.0, 2.5, 3.4), v(0, 2.3, 0), C.darkFur, { shape = "Ball" })
	b:add(v(2.4, 1.7, 2.0), v(0, 2.5, -1.9), C.black, { shape = "Ball" })
	b:add(v(2.0, 1.8, 1.8), v(0, 2.9, 2.0), C.fur)
	b:add(v(1.4, 1.0, 0.9), v(0, 2.55, 2.6), C.paleFur)
	b:pair(v(0.62, 0.62, 0.4), v(0.52, 3.25, 2.75), C.red, { shape = "Ball" })
	b:pair(v(0.34, 0.34, 0.3), v(1.0, 2.95, 2.6), C.red, { shape = "Ball" })
	b:pair(v(0.55, 0.7, 0.32), v(1.05, 3.3, 1.75), C.fur)
	b:pair(v(0.5, 3.2, 0.5), v(1.9, 2.4, 1.0), C.black, { rot = v(0, 0, 58) })
	b:pair(v(0.42, 2.2, 0.42), v(3.1, 1.4, 1.0), C.black, { rot = v(0, 0, -34) })
	b:pair(v(0.5, 3.2, 0.5), v(2.1, 2.3, -0.5), C.black, { rot = v(0, 0, 66) })
	b:pair(v(0.42, 2.2, 0.42), v(3.3, 1.3, -0.5), C.black, { rot = v(0, 0, -30) })
	b:pair(v(0.5, 2.8, 0.5), v(1.8, 1.9, -2.2), C.black, { rot = v(0, 0, 48) })
	b:pair(v(0.42, 1.9, 0.42), v(2.9, 1.0, -2.4), C.black, { rot = v(0, 0, -32) })
	return b.specs
end

BUILDERS.buildCocofantoElefanto = function()
	local b = newBuild()
	b:add(v(4.2, 3.4, 4.8), v(0, 2.5, 0), C.grey)
	b:add(v(3.6, 3.4, 3.6), v(0, 5.0, 1.1), C.brown, { shape = "Ball" })
	b:pair(v(0.9, 0.4, 0.9), v(0.9, 6.5, 0.9), C.darkWood)
	b:add(v(1.9, 1.5, 1.4), v(0, 4.5, 2.7), C.brown)
	b:add(v(0.95, 3.0, 0.95), v(0, 3.4, 3.1), C.grey, { rot = v(28, 0, 0) })
	b:add(v(1.05, 0.8, 1.05), v(0, 2.0, 3.9), C.darkGrey)
	b:pair(v(0.5, 2.3, 2.3), v(1.95, 5.1, 0.9), C.grey)
	b:pair(v(0.42, 1.9, 1.9), v(2.15, 5.1, 0.9), C.paleFur)
	b:eyes(0.85, 5.2, 2.55, 0.5)
	b:pair(v(0.4, 0.4, 1.6), v(0.95, 3.6, 3.0), C.bone, { rot = v(-24, 0, 0) })
	b:pair(v(1.15, 2.3, 1.15), v(1.45, 1.15, 1.7), C.grey)
	b:pair(v(1.2, 0.5, 1.2), v(1.45, 0.25, 1.7), C.darkGrey)
	b:pair(v(1.15, 2.3, 1.15), v(1.45, 1.15, -1.7), C.grey)
	b:pair(v(1.2, 0.5, 1.2), v(1.45, 0.25, -1.7), C.darkGrey)
	return b.specs
end

-- ---------- Mythic ----------

BUILDERS.buildGraipussMedussi = function()
	local b = newBuild()
	b:add(v(4.6, 3.6, 4.6), v(0, 4.2, 0), C.purple, { shape = "Ball" })
	b:add(v(4.0, 0.5, 4.0), v(0, 2.6, 0), C.pink, { shape = "Cylinder", rot = v(0, 0, 90) })
	b:add(v(2.4, 1.4, 2.4), v(0, 5.9, 0), C.teal, { shape = "Ball" })
	b:add(v(1.4, 1.0, 1.4), v(0, 6.7, 0), C.sky, { shape = "Ball" })
	b:eyes(1.0, 4.4, 2.1, 0.72)
	b:add(v(2.0, 0.3, 0.3), v(0, 3.5, 2.15), C.pink)
	b:pair(v(0.75, 3.4, 0.75), v(1.6, 1.7, 1.1), C.purple)
	b:pair(v(0.6, 1.6, 0.6), v(1.9, 0.5, 1.5), C.pink, { rot = v(0, 0, -22) })
	b:add(v(0.75, 3.2, 0.75), v(0, 1.6, 2.0), C.purple)
	b:add(v(0.6, 1.5, 0.6), v(0, 0.45, 2.4), C.pink, { rot = v(-20, 0, 0) })
	b:pair(v(0.75, 3.0, 0.75), v(1.5, 1.8, -1.5), C.purple)
	b:pair(v(0.6, 1.4, 0.6), v(1.8, 0.6, -1.9), C.pink, { rot = v(0, 0, -18) })
	b:pair(v(0.55, 0.55, 0.55), v(2.3, 5.1, 0), C.teal, { shape = "Ball" })
	return b.specs
end

BUILDERS.buildGaramaMadundung = function()
	local b = newBuild()
	b:add(v(4.2, 4.6, 4.2), v(0, 2.3, 0), C.darkGrey)
	b:add(v(4.6, 0.5, 4.6), v(0, 0.25, 0), C.black)
	b:add(v(3.2, 1.2, 3.2), v(0, 5.2, 0), C.steel)
	b:add(v(2.4, 0.6, 2.4), v(0, 6.0, 0), C.metal)
	b:add(v(2.4, 2.2, 0.35), v(0, 3.5, 2.15), C.gold)
	b:add(v(1.8, 1.6, 0.2), v(0, 3.5, 2.3), C.yellow)
	b:pair(v(0.85, 0.85, 0.4), v(0.72, 3.9, 2.4), C.black)
	b:add(v(1.4, 0.3, 0.3), v(0, 2.8, 2.4), C.black)
	b:pair(v(0.35, 1.6, 0.35), v(1.5, 5.5, 0), C.gold, { rot = v(0, 0, 18) })
	b:pair(v(1.0, 3.2, 1.0), v(2.4, 2.5, 0), C.darkGrey, { rot = v(0, 0, 10) })
	b:pair(v(0.8, 0.8, 0.8), v(2.9, 0.7, 0), C.black)
	b:add(v(0.8, 0.8, 0.8), v(0, 6.6, 0), C.red, { shape = "Ball" })
	b:pair(v(0.3, 0.3, 0.3), v(1.1, 6.3, 0), C.red, { shape = "Ball" })
	return b.specs
end

-- ==========================================================================
-- Assembly
-- ==========================================================================

local SHAPE: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

-- Shifts a colour's hue, used only by the Glitched mutation. Each part gets a
-- different shift, which is what reads as corruption rather than as a tint.
local function hueShift(color: Color3, amount: number): Color3
	local h, s, val = color:ToHSV()
	return Color3.fromHSV((h + amount) % 1, math.min(1, s * 1.15), val)
end

local function buildPart(spec: Spec, style, index: number): BasePart
	local part = Instance.new("Part")
	part.Shape = SHAPE[spec.shape or "Block"] or Enum.PartType.Block
	part.Size = spec.size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = style.material or spec.material or Enum.Material.SmoothPlastic

	local color = spec.color
	if style.chromatic then
		-- Irrational step so the pattern never visibly repeats across parts.
		color = hueShift(color, index * 0.148)
	end
	if style.blend and style.blend > 0 then
		color = color:Lerp(style.tint, style.blend)
	end
	part.Color = color

	local cf = CFrame.new(spec.offset)
	if spec.rotation then
		cf = cf * CFrame.Angles(
			math.rad(spec.rotation.X),
			math.rad(spec.rotation.Y),
			math.rad(spec.rotation.Z)
		)
	end
	part.CFrame = cf
	return part
end

--[[
	Builds a brainrot at the origin with its base at Y = 0, scaled so its height
	is roughly GameConfig.BrainrotHeight. The caller positions it.

	Returns nil for an unknown id or a missing builder -- PlotService treats
	that as "don't place" rather than erroring, so one bad config entry cannot
	take a plot down.
]]
function ModelFactory.create(brainrotId: string, mutation: string): Model?
	local def = BrainrotConfig.get(brainrotId)
	if not def then
		return nil
	end

	local builder = BUILDERS[def.modelBuilder]
	if not builder then
		warn(`[ModelFactory] no builder "{def.modelBuilder}" for {brainrotId}`)
		return nil
	end

	local style = BrainrotConfig.MUTATION_STYLE[mutation] or BrainrotConfig.MUTATION_STYLE.Normal
	local specs = builder()
	if #specs == 0 then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = def.displayName

	local anchor: BasePart? = nil
	for index, spec in specs do
		local part = buildPart(spec, style, index)
		part.Parent = model
		anchor = anchor or part
	end

	--[[
		Deliberately NO PrimaryPart.

		Model:GetPivot() returns the PrimaryPart's CFrame whenever one is set
		and ignores WorldPivot entirely. PlotService positions models with
		PivotTo, so a PrimaryPart would mean placement is measured from
		whichever part happened to be built first -- sinking tall characters
		into the podium and floating squat ones above it.

		With no PrimaryPart, WorldPivot governs, and we set it to the base
		centre below.
	]]

	--[[
		Force the pivot to world axes BEFORE measuring anything.

		Model:GetBoundingBox returns a box aligned to the model's pivot
		orientation, and a fresh Model inherits its pivot from its first part.
		Characters whose first block is a rotated cylinder -- Cappuccino
		Assassino and Ballerina Cappuccina both start with one turned 90 degrees
		-- were therefore measured in a rotated frame, so "height" was read off
		the world X axis and they came out scaled and grounded wrongly.
	]]
	model.WorldPivot = CFrame.identity

	--[[
		Measure with GetBoundingBox rather than from the spec offsets.

		Computing extents as `offset ± size/2` ignores rotation, and a part
		tilted 45 degrees is meaningfully taller than its own Y size, so
		characters with angled limbs came out mis-scaled.

		Scale before grounding: ScaleTo scales about the pivot, so aligning the
		base first would only move it again.
	]]
	local _, measured = model:GetBoundingBox()
	if measured.Y > 0 then
		local scale = GameConfig.BrainrotHeight / measured.Y
		if math.abs(scale - 1) > 0.01 then
			model:ScaleTo(scale)
		end
	end

	-- Park the model at the origin with its base on Y = 0. Parts are moved
	-- directly rather than via PivotTo, so the result does not depend on
	-- whatever the pivot happens to be at this point.
	local box, size = model:GetBoundingBox()
	local shift = Vector3.new(-box.Position.X, -(box.Position.Y - size.Y / 2), -box.Position.Z)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.CFrame = part.CFrame + shift
		end
	end

	-- The origin is now the base centre, which is the point that should land on
	-- the podium surface when PlotService calls PivotTo.
	model.WorldPivot = CFrame.identity

	if style.sparkle and anchor then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 12
		emitter.Lifetime = NumberRange.new(0.5, 1.0)
		emitter.Speed = NumberRange.new(0.8, 1.8)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new(0.3)
		emitter.Color = ColorSequence.new(style.tint)
		emitter.LightEmission = 0.5
		-- Square particles, per the art direction: no soft round sparkles.
		emitter.Texture = ""
		emitter.Parent = anchor
	end

	return model
end

-- How many parts a character is made of, for the Tests/ suite and for
-- budgeting podium cost.
function ModelFactory.partCount(brainrotId: string): number
	local def = BrainrotConfig.get(brainrotId)
	local builder = def and BUILDERS[def.modelBuilder]
	return if builder then #builder() else 0
end

function ModelFactory.builderNames(): { string }
	local names = {}
	for name in BUILDERS do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function ModelFactory.hasBuilder(name: string): boolean
	return BUILDERS[name] ~= nil
end

return ModelFactory
