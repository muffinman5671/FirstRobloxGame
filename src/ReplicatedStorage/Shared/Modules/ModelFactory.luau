--!strict
--[[
	ModelFactory
	Builds every brainrot from Instance.new primitives. No meshes, no textures,
	no asset IDs -- see DESIGN.md §2.

	ART TODO (all 26): these are silhouette blockouts, not finished art. Each
	builder captures the character's recognisable shape in four to seven flat
	blocks so a podium reads correctly at a glance and from across the plot.
	Replacing a builder with proper geometry is a local change: nothing outside
	this file knows how a character is assembled.

	Shapes stay blocky and colours flat, per the brutalist/pixelated/cartoony
	direction. Anything that wants to look smooth is the wrong instinct here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local ModelFactory = {}

-- ==========================================================================
-- Blockout DSL
-- ==========================================================================

type Spec = {
	size: Vector3,
	offset: Vector3,
	color: Color3,
	shape: string?, -- "Block" (default) | "Ball" | "Cylinder"
	rotation: Vector3?, -- degrees, applied before the offset
	material: Enum.Material?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Shared palette. Flat, saturated, cartoon poster colours.
local C = {
	skin = rgb(214, 168, 122),
	fur = rgb(126, 88, 58),
	darkFur = rgb(84, 58, 40),
	grey = rgb(150, 154, 162),
	darkGrey = rgb(84, 88, 96),
	white = rgb(238, 240, 246),
	black = rgb(34, 34, 40),
	green = rgb(96, 178, 84),
	darkGreen = rgb(58, 120, 56),
	blue = rgb(74, 140, 220),
	navy = rgb(38, 66, 128),
	red = rgb(214, 68, 58),
	orange = rgb(238, 142, 48),
	yellow = rgb(240, 208, 72),
	brown = rgb(140, 96, 56),
	cream = rgb(238, 218, 172),
	pink = rgb(238, 148, 176),
	purple = rgb(154, 96, 214),
	teal = rgb(72, 186, 178),
	wood = rgb(158, 116, 70),
	metal = rgb(176, 180, 190),
}

-- Shorthand: p(size, offset, colour, shape, rotation)
local function p(size: Vector3, offset: Vector3, color: Color3, shape: string?, rotation: Vector3?): Spec
	return { size = size, offset = offset, color = color, shape = shape, rotation = rotation }
end

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- ==========================================================================
-- Builders
-- ==========================================================================
-- Each returns a flat list of blocks in local space, Y up, origin at the base.

local BUILDERS: { [string]: () -> { Spec } } = {}

-- ---------- Common ----------

BUILDERS.buildBobritoBandito = function()
	return {
		p(v(3.4, 2.6, 2.2), v(0, 1.3, 0), C.fur),
		p(v(2.2, 1.8, 1.8), v(0, 3.3, 0.2), C.fur),
		p(v(2.4, 0.7, 0.3), v(0, 3.5, 1.0), C.black), -- bandit mask
		p(v(2.6, 0.5, 1.6), v(0, 0.3, -1.6), C.darkFur), -- flat tail
		p(v(0.8, 0.9, 0.8), v(-0.9, 0.45, 1.0), C.darkFur),
		p(v(0.8, 0.9, 0.8), v(0.9, 0.45, 1.0), C.darkFur),
	}
end

BUILDERS.buildBonecaAmbalabu = function()
	return {
		p(v(3.6, 1.4, 3.6), v(0, 0.7, 0), C.black, "Cylinder", v(0, 0, 90)), -- tyre
		p(v(2.0, 2.0, 2.0), v(0, 2.4, 0), C.green, "Ball"), -- frog head
		p(v(0.7, 0.7, 0.7), v(-0.6, 3.4, 0.4), C.white, "Ball"),
		p(v(0.7, 0.7, 0.7), v(0.6, 3.4, 0.4), C.white, "Ball"),
		p(v(0.5, 1.6, 0.5), v(-1.2, 0.8, 0), C.green),
		p(v(0.5, 1.6, 0.5), v(1.2, 0.8, 0), C.green),
	}
end

BUILDERS.buildTrippiTroppi = function()
	return {
		p(v(3.0, 1.6, 2.0), v(0, 0.8, 0), C.orange), -- shrimp body
		p(v(1.8, 1.6, 1.6), v(0, 2.2, 0.4), C.cream), -- cat head
		p(v(0.5, 0.8, 0.4), v(-0.6, 3.2, 0.4), C.cream),
		p(v(0.5, 0.8, 0.4), v(0.6, 3.2, 0.4), C.cream),
		p(v(0.6, 0.6, 1.4), v(0, 0.9, -1.6), C.orange),
		p(v(0.6, 0.6, 1.0), v(0, 1.5, -2.2), C.orange, nil, v(35, 0, 0)),
	}
end

BUILDERS.buildTrulimeroTrulicina = function()
	return {
		p(v(1.8, 2.0, 3.4), v(0, 1.2, 0), C.blue), -- fish body
		p(v(1.4, 1.4, 1.4), v(0, 2.8, 0.8), C.cream),
		p(v(0.4, 0.7, 0.4), v(-0.45, 3.6, 0.8), C.cream),
		p(v(0.4, 0.7, 0.4), v(0.45, 3.6, 0.8), C.cream),
		p(v(0.3, 1.6, 1.4), v(0, 1.6, -2.0), C.navy), -- tail fin
		p(v(0.8, 0.9, 0.8), v(-1.0, 0.45, 0.6), C.blue),
		p(v(0.8, 0.9, 0.8), v(1.0, 0.45, 0.6), C.blue),
	}
end

BUILDERS.buildBananitaDolphinita = function()
	return {
		p(v(1.8, 1.8, 4.0), v(0, 1.4, 0), C.yellow), -- banana-dolphin body
		p(v(1.4, 1.2, 1.6), v(0, 1.6, 2.2), C.yellow), -- snout
		p(v(0.4, 1.4, 1.0), v(0, 2.8, -0.4), C.cream), -- dorsal
		p(v(0.3, 1.2, 1.6), v(0, 1.6, -2.4), C.cream),
		p(v(0.5, 0.5, 0.5), v(-0.5, 2.0, 1.8), C.black, "Ball"),
		p(v(0.5, 0.5, 0.5), v(0.5, 2.0, 1.8), C.black, "Ball"),
	}
end

BUILDERS.buildPiccioneMacchina = function()
	return {
		p(v(3.6, 1.6, 2.2), v(0, 0.9, 0), C.grey), -- car body
		p(v(2.0, 1.0, 1.8), v(0, 2.0, -0.2), C.darkGrey), -- cabin
		p(v(1.2, 1.4, 1.2), v(0, 2.6, 1.2), C.teal), -- pigeon head
		p(v(0.5, 0.4, 0.7), v(0, 2.6, 2.0), C.orange), -- beak
		p(v(0.9, 0.9, 0.5), v(-1.5, 0.5, 1.0), C.black, "Cylinder", v(0, 0, 90)),
		p(v(0.9, 0.9, 0.5), v(1.5, 0.5, 1.0), C.black, "Cylinder", v(0, 0, 90)),
		p(v(0.9, 0.9, 0.5), v(-1.5, 0.5, -1.0), C.black, "Cylinder", v(0, 0, 90)),
		p(v(0.9, 0.9, 0.5), v(1.5, 0.5, -1.0), C.black, "Cylinder", v(0, 0, 90)),
	}
end

-- ---------- Uncommon ----------

BUILDERS.buildBrrBrrPatapim = function()
	return {
		p(v(2.6, 3.2, 2.6), v(0, 1.6, 0), C.wood), -- trunk body
		p(v(2.0, 1.6, 2.0), v(0, 4.0, 0), C.skin), -- face
		p(v(1.0, 0.6, 0.8), v(0, 3.8, 1.2), C.skin), -- nose
		p(v(3.2, 0.8, 0.8), v(0, 4.9, -0.4), C.darkGreen), -- foliage brow
		p(v(0.8, 1.6, 0.8), v(-1.6, 1.4, 0), C.wood, nil, v(0, 0, 25)),
		p(v(0.8, 1.6, 0.8), v(1.6, 1.4, 0), C.wood, nil, v(0, 0, -25)),
		p(v(1.0, 0.6, 1.6), v(-0.7, 0.3, 0.6), C.wood),
		p(v(1.0, 0.6, 1.6), v(0.7, 0.3, 0.6), C.wood),
	}
end

BUILDERS.buildChimpanziniBananini = function()
	return {
		p(v(2.0, 3.4, 2.0), v(0, 1.7, 0), C.yellow), -- banana body
		p(v(1.0, 0.8, 1.0), v(0, 3.6, 0), C.darkGreen), -- stem
		p(v(1.6, 1.4, 1.4), v(0, 2.6, 0.9), C.fur), -- monkey face
		p(v(0.5, 0.6, 0.3), v(-0.9, 2.8, 0.7), C.fur),
		p(v(0.5, 0.6, 0.3), v(0.9, 2.8, 0.7), C.fur),
		p(v(0.7, 1.4, 0.7), v(-1.2, 1.2, 0), C.fur),
		p(v(0.7, 1.4, 0.7), v(1.2, 1.2, 0), C.fur),
	}
end

BUILDERS.buildCappuccinoAssassino = function()
	return {
		p(v(2.6, 2.4, 2.6), v(0, 1.2, 0), C.white, "Cylinder", v(0, 0, 90)), -- cup
		p(v(2.8, 0.4, 2.8), v(0, 2.5, 0), C.brown, "Cylinder", v(0, 0, 90)), -- crema
		p(v(1.0, 0.5, 1.0), v(0, 2.8, 0), C.black), -- eyes slot
		p(v(0.6, 1.8, 0.6), v(-1.6, 1.4, 0), C.black, nil, v(0, 0, 30)),
		p(v(0.6, 1.8, 0.6), v(1.6, 1.4, 0), C.black, nil, v(0, 0, -30)),
		p(v(0.3, 2.2, 0.3), v(1.9, 2.4, 0), C.metal, nil, v(0, 0, -40)), -- blade
		p(v(0.8, 0.8, 0.8), v(-0.7, 0.4, 0.6), C.black),
		p(v(0.8, 0.8, 0.8), v(0.7, 0.4, 0.6), C.black),
	}
end

BUILDERS.buildBurbaloniLuliloli = function()
	return {
		p(v(3.2, 3.2, 3.2), v(0, 1.6, 0), C.brown, "Ball"), -- coconut
		p(v(1.8, 1.6, 1.6), v(0, 2.6, 1.4), C.fur), -- capybara face
		p(v(0.5, 0.5, 0.4), v(-0.5, 3.2, 1.9), C.black, "Ball"),
		p(v(0.5, 0.5, 0.4), v(0.5, 3.2, 1.9), C.black, "Ball"),
		p(v(0.9, 0.6, 0.9), v(-1.0, 0.3, 0.8), C.fur),
		p(v(0.9, 0.6, 0.9), v(1.0, 0.3, 0.8), C.fur),
	}
end

BUILDERS.buildGlorboFruttodrillo = function()
	return {
		p(v(2.4, 1.8, 4.4), v(0, 1.0, 0), C.green), -- croc body
		p(v(1.8, 1.0, 2.2), v(0, 1.0, 2.6), C.darkGreen), -- snout
		p(v(2.6, 2.0, 2.6), v(0, 2.6, -1.0), C.red, "Ball"), -- fruit shell
		p(v(0.5, 0.5, 0.5), v(-0.6, 1.7, 2.6), C.yellow, "Ball"),
		p(v(0.5, 0.5, 0.5), v(0.6, 1.7, 2.6), C.yellow, "Ball"),
		p(v(0.8, 0.7, 0.8), v(-1.1, 0.35, 1.4), C.darkGreen),
		p(v(0.8, 0.7, 0.8), v(1.1, 0.35, 1.4), C.darkGreen),
	}
end

BUILDERS.buildFrigoCamelo = function()
	return {
		p(v(3.0, 4.2, 2.4), v(0, 2.1, 0), C.white), -- fridge
		p(v(0.2, 4.0, 2.2), v(1.55, 2.1, 0), C.grey), -- door seam
		p(v(1.6, 1.4, 1.4), v(0, 4.6, 1.2), C.cream), -- camel head
		p(v(0.6, 1.4, 0.6), v(0, 5.4, 0.6), C.cream, nil, v(-20, 0, 0)),
		p(v(1.2, 1.0, 1.2), v(0, 4.9, -0.6), C.cream), -- hump
		p(v(0.7, 1.0, 0.7), v(-1.0, 0.5, 0.8), C.cream),
		p(v(0.7, 1.0, 0.7), v(1.0, 0.5, 0.8), C.cream),
	}
end

-- ---------- Rare ----------

BUILDERS.buildTralaleroTralala = function()
	return {
		p(v(2.2, 2.2, 5.0), v(0, 1.8, 0), C.blue), -- shark body
		p(v(1.6, 1.4, 2.0), v(0, 1.8, 2.8), C.blue), -- snout
		p(v(1.5, 0.4, 1.4), v(0, 1.2, 2.6), C.white), -- mouth
		p(v(0.4, 1.8, 1.2), v(0, 3.4, -0.4), C.navy), -- dorsal
		p(v(0.3, 1.6, 1.6), v(0, 2.2, -3.0), C.navy), -- tail
		p(v(1.2, 0.5, 2.0), v(-1.0, 0.6, 1.4), C.white), -- sneaker
		p(v(1.2, 0.5, 2.0), v(1.0, 0.6, 1.4), C.white),
		p(v(1.2, 0.4, 2.0), v(-1.0, 0.2, 1.4), C.red),
		p(v(1.2, 0.4, 2.0), v(1.0, 0.2, 1.4), C.red),
	}
end

BUILDERS.buildTungTungTungSahur = function()
	return {
		p(v(2.4, 4.0, 2.4), v(0, 2.0, 0), C.wood), -- log body
		p(v(2.0, 0.6, 2.0), v(0, 4.2, 0), C.brown, "Cylinder", v(0, 0, 90)),
		p(v(1.4, 0.5, 0.4), v(0, 2.6, 1.2), C.black), -- eyes
		p(v(1.0, 0.8, 0.3), v(0, 1.6, 1.2), C.black), -- mouth
		p(v(0.6, 2.2, 0.6), v(-1.5, 2.4, 0), C.wood, nil, v(0, 0, 20)),
		p(v(0.6, 2.2, 0.6), v(1.5, 2.4, 0), C.wood, nil, v(0, 0, -20)),
		p(v(0.5, 2.6, 0.5), v(2.1, 3.2, 0), C.brown, nil, v(0, 0, -55)), -- bat
		p(v(0.9, 0.7, 1.4), v(-0.7, 0.35, 0.4), C.brown),
		p(v(0.9, 0.7, 1.4), v(0.7, 0.35, 0.4), C.brown),
	}
end

BUILDERS.buildBallerinaCappuccina = function()
	return {
		p(v(2.4, 2.2, 2.4), v(0, 3.6, 0), C.white, "Cylinder", v(0, 0, 90)), -- cup head
		p(v(2.6, 0.4, 2.6), v(0, 4.8, 0), C.brown, "Cylinder", v(0, 0, 90)),
		p(v(1.2, 2.0, 0.9), v(0, 1.8, 0), C.pink), -- torso
		p(v(3.0, 0.6, 3.0), v(0, 1.2, 0), C.pink, "Cylinder", v(0, 0, 90)), -- tutu
		p(v(0.5, 1.4, 0.5), v(-0.5, 0.7, 0), C.cream),
		p(v(0.5, 1.4, 0.5), v(0.5, 0.7, 0), C.cream),
		p(v(0.45, 1.6, 0.45), v(-1.1, 2.4, 0), C.cream, nil, v(0, 0, 40)),
		p(v(0.45, 1.6, 0.45), v(1.1, 2.4, 0), C.cream, nil, v(0, 0, -40)),
	}
end

BUILDERS.buildLiriliLarila = function()
	return {
		p(v(2.6, 2.6, 3.2), v(0, 2.2, 0), C.grey), -- elephant body
		p(v(2.0, 1.8, 1.6), v(0, 3.0, 1.8), C.grey),
		p(v(0.7, 2.2, 0.7), v(0, 2.0, 2.4), C.grey, nil, v(20, 0, 0)), -- trunk
		p(v(0.4, 1.6, 1.6), v(-1.2, 3.2, 1.6), C.grey), -- ears
		p(v(0.4, 1.6, 1.6), v(1.2, 3.2, 1.6), C.grey),
		p(v(1.8, 1.8, 0.3), v(0, 2.6, -1.8), C.cream), -- clock face
		p(v(0.8, 1.0, 0.8), v(-0.9, 0.5, 0.8), C.grey),
		p(v(0.8, 1.0, 0.8), v(0.9, 0.5, 0.8), C.grey),
		p(v(0.9, 1.4, 0.9), v(0, 4.4, -0.6), C.darkGreen), -- cactus crown
	}
end

BUILDERS.buildBombombiniGusini = function()
	return {
		p(v(2.0, 1.8, 4.6), v(0, 1.8, 0), C.white), -- goose fuselage
		p(v(1.0, 1.8, 1.0), v(0, 3.2, 1.8), C.white), -- neck
		p(v(1.2, 1.0, 1.4), v(0, 4.1, 2.2), C.white), -- head
		p(v(0.5, 0.4, 0.8), v(0, 4.0, 3.0), C.orange), -- beak
		p(v(4.6, 0.3, 1.2), v(0, 2.0, -0.4), C.grey), -- wings
		p(v(0.8, 0.8, 1.8), v(-0.9, 0.9, -1.6), C.darkGrey), -- engines
		p(v(0.8, 0.8, 1.8), v(0.9, 0.9, -1.6), C.darkGrey),
	}
end

-- ---------- Epic ----------

BUILDERS.buildBombardiroCrocodilo = function()
	return {
		p(v(2.4, 2.0, 5.6), v(0, 2.2, 0), C.darkGreen), -- fuselage
		p(v(1.8, 1.2, 2.4), v(0, 2.2, 3.2), C.green), -- snout
		p(v(1.6, 0.4, 2.2), v(0, 1.6, 3.2), C.white), -- teeth
		p(v(6.4, 0.4, 1.6), v(0, 2.6, -0.4), C.darkGrey), -- wings
		p(v(0.9, 0.9, 2.0), v(-1.8, 1.9, -0.6), C.grey), -- engines
		p(v(0.9, 0.9, 2.0), v(1.8, 1.9, -0.6), C.grey),
		p(v(0.4, 1.6, 1.4), v(0, 3.4, -2.6), C.darkGrey), -- tail fin
		p(v(0.6, 0.6, 0.6), v(-0.7, 2.8, 3.4), C.yellow, "Ball"),
		p(v(0.6, 0.6, 0.6), v(0.7, 2.8, 3.4), C.yellow, "Ball"),
	}
end

BUILDERS.buildOrangutiniAnanassini = function()
	return {
		p(v(3.0, 3.4, 3.0), v(0, 1.7, 0), C.yellow), -- pineapple body
		p(v(0.5, 2.0, 0.5), v(-0.6, 4.2, 0), C.darkGreen, nil, v(0, 0, 18)),
		p(v(0.5, 2.4, 0.5), v(0, 4.4, 0), C.darkGreen),
		p(v(0.5, 2.0, 0.5), v(0.6, 4.2, 0), C.darkGreen, nil, v(0, 0, -18)),
		p(v(2.0, 1.8, 1.6), v(0, 2.6, 1.6), C.orange), -- ape face
		p(v(0.5, 0.5, 0.4), v(-0.5, 2.9, 2.3), C.black, "Ball"),
		p(v(0.5, 0.5, 0.4), v(0.5, 2.9, 2.3), C.black, "Ball"),
		p(v(0.9, 2.2, 0.9), v(-1.8, 1.6, 0), C.orange, nil, v(0, 0, 15)),
		p(v(0.9, 2.2, 0.9), v(1.8, 1.6, 0), C.orange, nil, v(0, 0, -15)),
	}
end

BUILDERS.buildTigrulliniWatermelini = function()
	return {
		p(v(3.4, 3.0, 3.4), v(0, 1.6, 0), C.green), -- melon body
		p(v(3.2, 0.4, 3.2), v(0, 3.0, 0), C.red, "Cylinder", v(0, 0, 90)),
		p(v(2.0, 1.8, 1.6), v(0, 3.4, 1.2), C.orange), -- tiger head
		p(v(0.35, 0.9, 0.3), v(-0.6, 3.4, 2.0), C.black),
		p(v(0.35, 0.9, 0.3), v(0.6, 3.4, 2.0), C.black),
		p(v(0.6, 0.7, 0.4), v(-0.8, 4.3, 1.0), C.orange),
		p(v(0.6, 0.7, 0.4), v(0.8, 4.3, 1.0), C.orange),
		p(v(0.9, 0.8, 0.9), v(-1.1, 0.4, 1.2), C.orange),
		p(v(0.9, 0.8, 0.9), v(1.1, 0.4, 1.2), C.orange),
	}
end

BUILDERS.buildGirafaCelestre = function()
	return {
		p(v(2.6, 2.2, 4.0), v(0, 3.0, 0), C.yellow), -- body
		p(v(1.2, 4.0, 1.2), v(0, 5.6, 1.4), C.yellow, nil, v(-12, 0, 0)), -- neck
		p(v(1.4, 1.2, 1.8), v(0, 7.6, 2.0), C.cream), -- head
		p(v(0.3, 0.7, 0.3), v(-0.4, 8.4, 1.8), C.brown),
		p(v(0.3, 0.7, 0.3), v(0.4, 8.4, 1.8), C.brown),
		p(v(0.8, 2.0, 0.8), v(-1.0, 1.0, 1.4), C.yellow),
		p(v(0.8, 2.0, 0.8), v(1.0, 1.0, 1.4), C.yellow),
		p(v(0.8, 2.0, 0.8), v(-1.0, 1.0, -1.4), C.yellow),
		p(v(0.8, 2.0, 0.8), v(1.0, 1.0, -1.4), C.yellow),
		p(v(0.6, 0.6, 0.6), v(0, 8.8, 2.0), C.white, "Ball"), -- star
	}
end

-- ---------- Legendary ----------

BUILDERS.buildLaVaccaSaturnoSaturnita = function()
	return {
		p(v(3.6, 2.8, 5.0), v(0, 2.6, 0), C.white), -- cow body
		p(v(1.6, 1.2, 1.6), v(-0.8, 3.4, 1.2), C.black), -- patches
		p(v(1.4, 1.0, 1.4), v(1.0, 2.4, -1.4), C.black),
		p(v(2.0, 1.8, 1.8), v(0, 3.2, 3.0), C.white), -- head
		p(v(1.2, 0.8, 0.8), v(0, 2.8, 3.8), C.pink), -- muzzle
		p(v(0.4, 0.8, 0.4), v(-0.7, 4.2, 2.8), C.cream),
		p(v(0.4, 0.8, 0.4), v(0.7, 4.2, 2.8), C.cream),
		p(v(0.9, 2.4, 0.9), v(-1.2, 1.2, 1.6), C.white),
		p(v(0.9, 2.4, 0.9), v(1.2, 1.2, 1.6), C.white),
		p(v(0.9, 2.4, 0.9), v(-1.2, 1.2, -1.6), C.white),
		p(v(0.9, 2.4, 0.9), v(1.2, 1.2, -1.6), C.white),
		p(v(9.0, 0.35, 9.0), v(0, 3.2, 0), C.orange, "Cylinder", v(0, 0, 90)), -- ring
	}
end

BUILDERS.buildChimpanziniSpiderini = function()
	return {
		p(v(2.8, 2.4, 3.2), v(0, 2.2, 0), C.darkFur), -- abdomen
		p(v(2.0, 1.8, 1.8), v(0, 2.8, 2.0), C.fur), -- ape head
		p(v(0.6, 0.6, 0.4), v(-0.5, 3.1, 2.8), C.red, "Ball"),
		p(v(0.6, 0.6, 0.4), v(0.5, 3.1, 2.8), C.red, "Ball"),
		p(v(0.5, 3.0, 0.5), v(-1.9, 2.2, 1.0), C.black, nil, v(0, 0, 55)),
		p(v(0.5, 3.0, 0.5), v(1.9, 2.2, 1.0), C.black, nil, v(0, 0, -55)),
		p(v(0.5, 3.0, 0.5), v(-2.1, 2.2, -0.6), C.black, nil, v(0, 0, 65)),
		p(v(0.5, 3.0, 0.5), v(2.1, 2.2, -0.6), C.black, nil, v(0, 0, -65)),
		p(v(0.5, 2.6, 0.5), v(-1.7, 1.6, -2.0), C.black, nil, v(0, 0, 45)),
		p(v(0.5, 2.6, 0.5), v(1.7, 1.6, -2.0), C.black, nil, v(0, 0, -45)),
	}
end

BUILDERS.buildCocofantoElefanto = function()
	return {
		p(v(4.0, 3.4, 4.6), v(0, 2.4, 0), C.grey), -- elephant body
		p(v(3.4, 3.4, 3.4), v(0, 4.8, 1.0), C.brown, "Ball"), -- coconut head
		p(v(0.9, 2.8, 0.9), v(0, 3.4, 2.6), C.grey, nil, v(25, 0, 0)), -- trunk
		p(v(0.5, 2.2, 2.2), v(-1.9, 5.0, 0.8), C.grey),
		p(v(0.5, 2.2, 2.2), v(1.9, 5.0, 0.8), C.grey),
		p(v(1.1, 2.2, 1.1), v(-1.4, 1.1, 1.6), C.grey),
		p(v(1.1, 2.2, 1.1), v(1.4, 1.1, 1.6), C.grey),
		p(v(1.1, 2.2, 1.1), v(-1.4, 1.1, -1.6), C.grey),
		p(v(1.1, 2.2, 1.1), v(1.4, 1.1, -1.6), C.grey),
	}
end

-- ---------- Mythic ----------

BUILDERS.buildGraipussMedussi = function()
	return {
		p(v(4.4, 3.4, 4.4), v(0, 4.0, 0), C.purple, "Ball"), -- bell
		p(v(1.0, 1.0, 0.5), v(-0.9, 4.2, 2.0), C.white, "Ball"),
		p(v(1.0, 1.0, 0.5), v(0.9, 4.2, 2.0), C.white, "Ball"),
		p(v(0.7, 3.4, 0.7), v(-1.6, 1.8, 1.0), C.purple),
		p(v(0.7, 3.4, 0.7), v(0, 1.6, 1.8), C.purple),
		p(v(0.7, 3.4, 0.7), v(1.6, 1.8, 1.0), C.purple),
		p(v(0.7, 3.0, 0.7), v(-1.4, 1.8, -1.4), C.purple),
		p(v(0.7, 3.0, 0.7), v(1.4, 1.8, -1.4), C.purple),
		p(v(1.4, 1.4, 1.4), v(0, 6.2, 0), C.teal, "Ball"),
	}
end

BUILDERS.buildGaramaMadundung = function()
	return {
		p(v(4.2, 4.4, 4.2), v(0, 2.2, 0), C.darkGrey), -- monolith body
		p(v(3.0, 1.2, 3.0), v(0, 5.0, 0), C.metal), -- crown slab
		p(v(2.2, 2.0, 0.4), v(0, 3.4, 2.1), C.yellow), -- glyph face
		p(v(0.8, 0.8, 0.5), v(-0.7, 3.8, 2.3), C.black),
		p(v(0.8, 0.8, 0.5), v(0.7, 3.8, 2.3), C.black),
		p(v(1.0, 3.2, 1.0), v(-2.4, 2.4, 0), C.darkGrey, nil, v(0, 0, 12)),
		p(v(1.0, 3.2, 1.0), v(2.4, 2.4, 0), C.darkGrey, nil, v(0, 0, -12)),
		p(v(0.6, 0.6, 0.6), v(0, 6.0, 0), C.red, "Ball"),
	}
end

-- ==========================================================================
-- Assembly
-- ==========================================================================

local SHAPE: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

local function buildPart(spec: Spec, tint: Color3): BasePart
	local part = Instance.new("Part")
	part.Shape = SHAPE[spec.shape or "Block"] or Enum.PartType.Block
	part.Size = spec.size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	-- Mutation tint is a lerp rather than a replacement, so a Golden character
	-- still reads as itself rather than as a gold blob.
	part.Color = spec.color:Lerp(tint, if tint == Color3.new(1, 1, 1) then 0 else 0.55)

	local cf = CFrame.new(spec.offset)
	if spec.rotation then
		cf = cf
			* CFrame.Angles(
				math.rad(spec.rotation.X),
				math.rad(spec.rotation.Y),
				math.rad(spec.rotation.Z)
			)
	end
	part.CFrame = cf
	return part
end

--[[
	Builds a brainrot model at the origin, base at Y = 0, scaled so its height
	is roughly GameConfig.BrainrotHeight. The caller positions it.

	Returns nil for an unknown id or a character whose builder is missing --
	PlotService treats that as "don't place" rather than erroring, so one bad
	config entry can't take a plot down.
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
	local model = Instance.new("Model")
	model.Name = def.displayName

	local specs = builder()
	local tallest: BasePart? = nil
	local maxY = -math.huge

	for _, spec in specs do
		local part = buildPart(spec, style.tint)
		part.Parent = model
		local top = spec.offset.Y + spec.size.Y / 2
		if top > maxY then
			maxY = top
			tallest = part
		end
	end

	-- Anchor the model on the lowest part so ScaleTo and pivoting behave.
	model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")

	if maxY > 0 then
		local scale = GameConfig.BrainrotHeight / maxY
		if math.abs(scale - 1) > 0.01 then
			model:ScaleTo(scale)
		end
	end

	if style.sparkle then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 14
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = NumberRange.new(1, 2)
		emitter.Size = NumberSequence.new(0.35)
		emitter.Color = ColorSequence.new(style.tint)
		emitter.LightEmission = 0.6
		-- Square particles, per the art direction: no soft round sparkles.
		emitter.Texture = ""
		emitter.Parent = model.PrimaryPart
	end

	return model
end

-- Which builders exist, for the Tests/ suite's coverage check.
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
