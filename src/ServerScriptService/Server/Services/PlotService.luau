--!strict
--[[
	PlotService
	Private base plots: claiming, podiums, and placing brainrots on them.

	Plots are built once at boot, not per join. Claiming then costs a table
	write rather than making a joining player wait on geometry, and releasing a
	plot is a matter of clearing its podiums rather than destroying and
	rebuilding walls.

	Slot state is authoritative on the profile (`placedBrainrots`), not on the
	world. The models on podiums are a rendering of that list; wiping them and
	rebuilding from the profile always produces the correct plot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local Format = require(ReplicatedStorage.Shared.Modules.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ModelFactory = require(ReplicatedStorage.Shared.Modules.ModelFactory)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

type Profile = SharedTypes.Profile
type PurchaseResult = SharedTypes.PurchaseResult

local PlotService = {}
PlotService.Name = "PlotService"

local AntiCheatService
local DataService
local EconomyService

-- (player, plotIndex)
PlotService.PlotAssigned = Signal.new()
-- (player)
PlotService.PlacementChanged = Signal.new()

local trove = Trove.new()

type Plot = {
	index: number,
	model: Model,
	origin: CFrame,
	podiums: { BasePart },
	sign: TextLabel?,
	owner: Player?,
	models: { [number]: Model }, -- slot -> spawned brainrot
}

local plots: { Plot } = {}
local byPlayer: { [Player]: Plot } = {}
local plotFolder: Folder


-- ==========================================================================
-- Construction
-- ==========================================================================

local function makePart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.Concrete
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Podium n sits in a PodiumsPerRow grid on the floor, numbered left to right,
-- front to back, so slot 1 is always the nearest-left podium.
local function podiumOffset(slot: number): Vector3
	local index = slot - 1
	local col = index % GameConfig.PodiumsPerRow
	local row = math.floor(index / GameConfig.PodiumsPerRow)

	local rows = math.ceil(GameConfig.MaxPlotSlots / GameConfig.PodiumsPerRow)
	local x = (col - (GameConfig.PodiumsPerRow - 1) / 2) * GameConfig.PodiumSpacing
	local z = (row - (rows - 1) / 2) * GameConfig.PodiumSpacing

	return Vector3.new(x, GameConfig.PodiumSize.Y / 2, z)
end

--[[
	A SurfaceGui carrying one scaled text label.

	Face is always Back: a Part's Front is its -Z side, and every sign in a plot
	has to read from +Z, which is the side you walk up from.

	`region` restricts the text to part of the face. TextScaled fills whatever
	box it is given, so a board that also carries an emblem has to hand the text
	less than the whole face or the two draw over each other.
]]
local function label(part: BasePart, text: string, colour: Color3, canvas: Vector2, region: UDim2?): TextLabel
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Back
	surface.CanvasSize = canvas
	surface.Parent = part

	local line = Instance.new("TextLabel")
	line.Size = region or UDim2.fromScale(1, 1)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.GothamBlack
	line.TextScaled = true
	line.TextColor3 = colour
	line.Text = text
	line.Parent = surface
	return line
end

--[[
	Builds one plot from its PlotLayout entry.

	Everything below is placed relative to `origin`, so the yaw carries the whole
	plot with it -- glazing, header and podium grid all stay in the same relation
	to the open side however the plot is turned.

	Plan, front edge inward: kerb, then the facade (corner pillar, glazed bay,
	bay pillar, a 36-stud entrance, and the mirror of that), then the podium
	grid, then the rarity display wall across the back. The roof and its arched
	header sit over all of it.
]]
local function buildPlot(index: number): Plot
	local layout = GameConfig.PlotLayout[index]
	local origin = CFrame.new(layout.position) * CFrame.Angles(0, math.rad(layout.yaw), 0)
	local pal = GameConfig.PlotPalette

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local halfW, halfD = GameConfig.PlotWidth / 2, GameConfig.PlotDepth / 2
	local wallH, wallT = GameConfig.PlotWallHeight, GameConfig.PlotWallThickness
	local roofT = GameConfig.PlotRoofThickness
	local over = GameConfig.PlotRoofOverhang
	local pillar = GameConfig.PlotPillarSize
	local pillarH = wallH + roofT

	-- Inner face of the back wall. Walls sit inside the footprint rather than
	-- centred on it, so PlotWidth and PlotDepth stay the true outer dimensions
	-- the row's clearances are measured from.
	local wallInner = -(halfD - wallT)

	local function place(
		name: string,
		size: Vector3,
		offset: CFrame,
		colour: Color3,
		props: { [string]: any }?
	): BasePart
		local part = makePart(name, size, origin * offset, colour, model)
		if props then
			for key, value in props do
				(part :: any)[key] = value
			end
		end
		return part
	end

	local glassProps = {
		Material = Enum.Material.Glass,
		Transparency = GameConfig.PlotGlassTransparency,
		Reflectance = GameConfig.PlotGlassReflectance,
	}

	--[[
		Glazes one run: a solid dado, glass panes, the mullions between them, and
		a head rail closing it under the roof.

		`base` centres the run; its local X runs along the wall and its local Z is
		the wall's normal, so one function does the side walls (turned a quarter
		turn) and the two front bays.

		Panes divide the run rather than stepping a fixed pitch and clamping the
		last one. Clamping leaves a sliver pane at one end of every run -- the
		same defect that shipped three times on the hub floor, wall and path.

		Glass is thinner than the mullions on purpose, so the bars stand proud of
		the glazing instead of sitting buried flush in it.
	]]
	local function glaze(name: string, base: CFrame, length: number, panes: number)
		local dado = GameConfig.PlotGlassDadoHeight
		local head = GameConfig.PlotGlassHeadHeight
		local mull = GameConfig.PlotMullionWidth
		local glassH = wallH - dado - head
		local glassY = dado + glassH / 2
		local pitch = length / panes

		place(`{name}Dado`, Vector3.new(length, dado, wallT), base * CFrame.new(0, dado / 2, 0), pal.frame)
		place(`{name}Head`, Vector3.new(length, head, wallT), base * CFrame.new(0, wallH - head / 2, 0), pal.frame)

		for i = 1, panes do
			place(
				`{name}Pane{i}`,
				Vector3.new(pitch - mull, glassH, wallT * 0.6),
				base * CFrame.new(-length / 2 + (i - 0.5) * pitch, glassY, 0),
				pal.glass,
				glassProps
			)
		end
		for i = 0, panes do
			place(
				`{name}Mullion{i}`,
				Vector3.new(mull, glassH, wallT),
				base * CFrame.new(-length / 2 + i * pitch, glassY, 0),
				pal.mullion
			)
		end
	end

	-- Floor, and the kerb that steps the forecourt up off the lawn. Raised
	-- PlotFloorRaise rather than laid flush: the lawn tiles run underneath the
	-- whole plot, and a flush slab z-fought as green streaks through it.
	place(
		"Floor",
		Vector3.new(GameConfig.PlotWidth, GameConfig.PlotFloorThickness, GameConfig.PlotDepth),
		CFrame.new(0, GameConfig.PlotFloorRaise - GameConfig.PlotFloorThickness / 2, 0),
		pal.floor
	)

	local kerbD = GameConfig.PlotKerbDepth
	local kerbTop = GameConfig.PlotFloorRaise + GameConfig.PlotKerbRaise
	place(
		"Kerb",
		Vector3.new(GameConfig.PlotWidth + over * 2, 3, kerbD),
		CFrame.new(0, kerbTop - 1.5, halfD + kerbD / 2),
		pal.kerb
	)

	-- The back wall stays solid: it is the display wall, and glazing it would
	-- put the lawn behind the rarity cases.
	place(
		"WallBack",
		Vector3.new(GameConfig.PlotWidth, wallH, wallT),
		CFrame.new(0, wallH / 2, wallInner - wallT / 2),
		pal.frameDark
	)

	-- Side walls, glazed between the corner pillars.
	local sideRun = GameConfig.PlotDepth - pillar * 2
	for _, sx in { -1, 1 } do
		glaze(
			if sx < 0 then "SideLeft" else "SideRight",
			CFrame.new(sx * (halfW - wallT / 2), 0, 0) * CFrame.Angles(0, math.rad(90), 0),
			sideRun,
			GameConfig.PlotGlassPanesPerSide
		)
	end

	--[[
		Corner pillars, running the full height into the roof, plus the two that
		split the facade into two glazed bays and a central opening.

		PlotPillarSize went 8 -> 6. At 8 a corner pillar spanned x 32..40 and
		z 20..28 while the corner podiums reach x 34 and z 22, so every corner bit
		a 2x2 stud notch out of a podium. At 6 the two abut exactly, and the bay
		pillars are shallow in Z for the same reason.
	]]
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			place(
				"Pillar",
				Vector3.new(pillar, pillarH, pillar),
				CFrame.new(sx * (halfW - pillar / 2), pillarH / 2, sz * (halfD - pillar / 2)),
				pal.frame
			)
		end
	end

	local bayX = GameConfig.PlotFrontPillarOffsetX
	local fpW, fpD = GameConfig.PlotFrontPillarWidth, GameConfig.PlotFrontPillarDepth
	for _, sx in { -1, 1 } do
		place("BayPillar", Vector3.new(fpW, pillarH, fpD), CFrame.new(sx * bayX, pillarH / 2, halfD - fpD / 2), pal.frame)
	end

	-- Glazed front bays, from the corner pillar's inner face to the bay pillar.
	local bayInner = bayX + fpW / 2
	local bayRun = (halfW - pillar) - bayInner
	for _, sx in { -1, 1 } do
		glaze(
			if sx < 0 then "BayLeft" else "BayRight",
			CFrame.new(sx * (bayInner + bayRun / 2), 0, halfD - wallT / 2),
			bayRun,
			2
		)
	end

	-- Light strips down the front face of every pillar. They stop below the
	-- fascia, which starts at wallH - PlotFasciaHeight.
	for _, x in { -(halfW - pillar / 2), -bayX, bayX, halfW - pillar / 2 } do
		place("PillarStrip", Vector3.new(1.2, 12, 0.6), CFrame.new(x, 10, halfD + 0.3), pal.light, {
			Material = Enum.Material.Neon,
		})
	end

	-- Roof oversails on every side, above head height so the overhang costs no
	-- usable floor. The fascia closes its front edge.
	place(
		"Roof",
		Vector3.new(GameConfig.PlotWidth + over * 2, roofT, GameConfig.PlotDepth + over * 2),
		CFrame.new(0, wallH + roofT / 2, 0),
		pal.frame
	)

	local fasciaH = GameConfig.PlotFasciaHeight
	place(
		"Fascia",
		Vector3.new(GameConfig.PlotWidth + over * 2, fasciaH, over),
		CFrame.new(0, wallH - fasciaH / 2, halfD + over / 2),
		pal.frame
	)

	--[[
		Recessed ceiling panels, in a grid rather than the old long strips.

		Neon only glows, it does not light anything, and the roof cuts the
		skylight -- the first build of this had podiums disappearing into a black
		interior. Every PlotCeilingLampEvery-th panel carries a real PointLight,
		which holds the count at two per plot rather than one per panel.
	]]
	local cols, rows = GameConfig.PlotCeilingPanelCols, GameConfig.PlotCeilingPanelRows
	local panelIndex = 0
	for row = 1, rows do
		for col = 1, cols do
			panelIndex += 1
			local panel = place(
				"CeilingPanel",
				Vector3.new(13, 0.8, 9),
				CFrame.new(
					(col - (cols + 1) / 2) * (GameConfig.PlotWidth / cols),
					wallH - 0.6,
					(row - (rows + 1) / 2) * (GameConfig.PlotDepth / rows)
				),
				pal.light,
				{ Material = Enum.Material.Neon }
			)

			if panelIndex % GameConfig.PlotCeilingLampEvery == 0 then
				local lamp = Instance.new("PointLight")
				lamp.Color = pal.lamp
				lamp.Range = GameConfig.PlotLampRange
				lamp.Brightness = GameConfig.PlotLampBrightness
				lamp.Shadows = false
				lamp.Parent = panel
			end
		end
	end

	--[[
		Rarity display cases across the back wall, standing on a counter.

		Colours come from the Rarity module rather than being picked here, so a
		case matches the tint that rarity already carries everywhere in the UI.
		Five cases, not six: the reference shows a five-case run, and Mythic reads
		better as the thing the cases do not promise you.

		They occupy the 4 studs between the wall's inner face and the rear podium
		row, held at PlotDisplayCaseY -- above a brainrot standing on that row --
		so they cost no slot.
	]]
	local caseSize = GameConfig.PlotDisplayCaseSize
	local caseY = GameConfig.PlotDisplayCaseY
	local cases = GameConfig.PlotDisplayCases
	local counterD = 4
	local displayRun = GameConfig.PlotWidth - pillar * 2

	place("DisplayCounter", Vector3.new(displayRun, 5, counterD), CFrame.new(0, 2.5, wallInner + counterD / 2), pal.frame)
	place(
		"DisplayCounterLip",
		Vector3.new(displayRun, 0.7, 0.4),
		CFrame.new(0, 4.4, wallInner + counterD + 0.2),
		pal.light,
		{ Material = Enum.Material.Neon }
	)

	for i = 1, cases do
		local rarity = Rarity.ORDER[i]
		local tint = Rarity.color(rarity)
		local x = (i - (cases + 1) / 2) * (displayRun / cases)

		place(`Case{rarity}`, caseSize, CFrame.new(x, caseY, wallInner + caseSize.Z / 2), pal.frameDark)

		--[[
			The recess behind the ore is a *darkened* rarity tint, not a Neon one.

			Built the other way round first -- glowing backboard, plain cubes --
			and the cubes came out as black silhouettes against a blown-out panel.
			Neon has no intensity control, so whichever of the two carries it wins
			the eye completely; the reference puts the glow on the ore.
		]]
		place(
			`CaseRecess{rarity}`,
			Vector3.new(caseSize.X - 2, caseSize.Y - 2, 0.4),
			CFrame.new(x, caseY, wallInner + caseSize.Z + 0.2),
			Color3.new(tint.R * 0.3, tint.G * 0.3, tint.B * 0.3)
		)

		-- Three tumbled cubes standing in for an ore cluster. Geometry, because
		-- the project ships no meshes (DESIGN.md 2a).
		local spots = { Vector3.new(-2.6, -1.4, 0), Vector3.new(2.4, -1.0, 0), Vector3.new(-0.1, 1.6, 0) }
		for j, spot in spots do
			place(
				`CaseOre{rarity}{j}`,
				Vector3.new(2.2, 2.2, 2.2),
				CFrame.new(x + spot.X, caseY + spot.Y, wallInner + caseSize.Z + 1.6)
					* CFrame.Angles(math.rad(18 * j), math.rad(24 * j), math.rad(15 * j)),
				tint,
				{ Material = Enum.Material.Neon }
			)
		end

		local plate = place(
			`CaseLabel{rarity}`,
			Vector3.new(caseSize.X, 2.6, 0.6),
			CFrame.new(x, caseY + caseSize.Y / 2 + 1.6, wallInner + caseSize.Z + 0.3),
			pal.frameDark
		)
		label(plate, string.upper(rarity), pal.accentMetal, Vector2.new(260, 60))
	end

	--[[
		Arched name header over the entrance: a parapet standing on the roof's
		front edge, an arch over it, the owner's name on a board across its face,
		and crossed hammers above that.

		The board used to sit on the back wall facing in, on the reasoning that
		you enter from +Z and read it looking back. Above the door is what tells
		you whose base you are walking up to, which is the more useful question
		from outside.
	]]
	local parapetW, parapetH = GameConfig.PlotParapetWidth, GameConfig.PlotParapetHeight
	local parapetY = wallH + roofT + parapetH / 2
	local parapetZ = halfD + over / 2 - 0.5

	place("Parapet", Vector3.new(parapetW, parapetH, 3), CFrame.new(0, parapetY, parapetZ), pal.frame)

	-- The arch itself: PlotArchSteps blocks across the parapet, each rising to a
	-- sine hump. No meshes in this project, so a curve is a stack of blocks.
	local steps = GameConfig.PlotArchSteps
	local stepW = parapetW / steps
	for i = 1, steps do
		local h = GameConfig.PlotArchRise * math.sin(math.pi * (i - 0.5) / steps)
		place(
			"ArchStep",
			Vector3.new(stepW, h, 3),
			CFrame.new((i - (steps + 1) / 2) * stepW, wallH + roofT + parapetH + h / 2, parapetZ),
			pal.frame
		)
	end

	local band = place("Sign", Vector3.new(parapetW - 8, 7, 0.6), CFrame.new(0, parapetY - 2.5, parapetZ + 1.8), pal.sign)
	local signLabel = label(band, "UNCLAIMED", Color3.fromRGB(238, 240, 246), Vector2.new(560, 150))

	for _, tilt in { 34, -34 } do
		local hammer = CFrame.new(0, parapetY + 5.5, parapetZ + 1.9) * CFrame.Angles(0, 0, math.rad(tilt))
		place("HammerHandle", Vector3.new(1.5, 10, 0.8), hammer, pal.accentMetal)
		place("HammerHead", Vector3.new(4.6, 3, 1), hammer * CFrame.new(0, 4.2, 0), pal.accentMetal)
	end

	--[[
		Free-standing forecourt board, front-left just past the kerb. This is the
		reference's sidewalk sign: the thing that says what the building is for
		before you have walked into it.

		Its base is sunk below SurfaceY deliberately. Everything else that sits on
		y = 0 is buried inside the plot's own floor slab, but this stands out on
		the lawn, where a bottom face exactly on the tile plane z-fights.
	]]
	local streetZ = halfD + GameConfig.PlotStreetSignForward
	local streetX = -(halfW - 8)
	place("StreetSignBase", Vector3.new(9, 2, 5), CFrame.new(streetX, 0.1, streetZ), pal.frameDark)
	for _, dx in { -3, 3 } do
		place("StreetSignPost", Vector3.new(1.4, 8, 1.4), CFrame.new(streetX + dx, 4.4, streetZ), pal.frame)
	end

	local board = place("StreetSign", Vector3.new(13, 14, 1.2), CFrame.new(streetX, 14.5, streetZ), pal.sign)
	label(
		board,
		"Collect Ores\nUpgrade Your Base\nGet Rich!",
		Color3.fromRGB(238, 240, 246),
		Vector2.new(260, 280),
		UDim2.fromScale(1, 0.74)
	)
	-- Crossed hammers in the quarter of the board the text was kept out of.
	for _, tilt in { 40, -40 } do
		place(
			"StreetSignMark",
			Vector3.new(5.5, 1.2, 0.6),
			CFrame.new(streetX, 10.2, streetZ + 0.9) * CFrame.Angles(0, 0, math.rad(tilt)),
			pal.accentMetal
		)
	end

	local podiums: { BasePart } = {}
	for slot = 1, GameConfig.MaxPlotSlots do
		local podium = place(`Podium{slot}`, GameConfig.PodiumSize, CFrame.new(podiumOffset(slot)), pal.podium)
		podium:SetAttribute("Slot", slot)
		podiums[slot] = podium
	end

	model.Parent = plotFolder

	return {
		index = index,
		model = model,
		origin = origin,
		podiums = podiums,
		sign = signLabel,
		owner = nil,
		models = {},
	}
end

-- ==========================================================================
-- Rendering placed brainrots
-- ==========================================================================

local function clearSlot(plot: Plot, slot: number)
	local existing = plot.models[slot]
	if existing then
		existing:Destroy()
		plot.models[slot] = nil
	end
end

local function renderSlot(plot: Plot, slot: number, brainrotId: string, mutation: string, rebirths: number)
	clearSlot(plot, slot)

	local model = ModelFactory.create(brainrotId, mutation)
	if not model then
		return
	end

	local podium = plot.podiums[slot]
	if not podium then
		model:Destroy()
		return
	end

	model:PivotTo(podium.CFrame * CFrame.new(0, GameConfig.PodiumSize.Y / 2, 0))
	model.Parent = plot.model

	local def = BrainrotConfig.get(brainrotId)
	if def then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(190, 52)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, GameConfig.BrainrotHeight + 1.6, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 140
		billboard.Adornee = podium
		billboard.Parent = model

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, 0, 0.55, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextColor3 = Rarity.color(def.rarity)
		name.Text = if mutation == "Normal" then def.displayName else `{mutation} {def.displayName}`
		name.Parent = billboard

		local income = Instance.new("TextLabel")
		income.Size = UDim2.new(1, 0, 0.45, 0)
		income.Position = UDim2.fromScale(0, 0.55)
		income.BackgroundTransparency = 1
		income.Font = Enum.Font.GothamBold
		income.TextScaled = true
		income.TextColor3 = Color3.fromRGB(120, 232, 140)
		-- Matches what IncomeService actually pays: base x mutation x rebirth.
		income.Text = Format.rate(
			BrainrotConfig.incomeFor(brainrotId, mutation) * ToolConfig.rebirthMultiplier(rebirths)
		)
		income.Parent = billboard
	end

	plot.models[slot] = model
end

--[[
	Rebuilds every podium from the profile. Called on claim and after any
	placement change -- rebuilding the whole plot is cheap at 24 slots and
	removes any chance of the world disagreeing with the save.
]]
local function renderPlot(plot: Plot)
	for slot in plot.models do
		clearSlot(plot, slot)
	end

	local player = plot.owner
	if not player then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local owned: { [string]: SharedTypes.OwnedBrainrot } = {}
	for _, entry in profile.brainrotsOwned do
		owned[entry.uid] = entry
	end

	for _, placed in profile.placedBrainrots do
		local entry = owned[placed.uid]
		if entry and placed.slot >= 1 and placed.slot <= profile.plotSlots then
			renderSlot(plot, placed.slot, entry.brainrotId, entry.mutation, profile.rebirths)
		end
	end

	-- Podiums beyond the player's purchased slot count are visually inert.
	for slot, podium in plot.podiums do
		local active = slot <= profile.plotSlots
		podium.Transparency = if active then 0 else 0.72
		podium.Color = if active then Color3.fromRGB(58, 62, 72) else Color3.fromRGB(42, 44, 52)
	end
end

PlotService.renderPlot = renderPlot

-- ==========================================================================
-- Claim / release
-- ==========================================================================

local function claim(player: Player)
	if byPlayer[player] then
		return
	end

	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			byPlayer[player] = plot
			if plot.sign then
				plot.sign.Text = player.DisplayName
			end

			renderPlot(plot)
			RemoteRegistry.event("PlotAssigned"):FireClient(player, plot.index, plot.origin.Position)
			PlotService.PlotAssigned:Fire(player, plot.index)
			return
		end
	end

	warn(`[PlotService] no free plot for {player.Name} ({#plots} built)`)
end

local function release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end

	for slot in plot.models do
		clearSlot(plot, slot)
	end
	plot.owner = nil
	if plot.sign then
		plot.sign.Text = "UNCLAIMED"
	end
	byPlayer[player] = nil
end

function PlotService.plotFor(player: Player): Plot?
	return byPlayer[player]
end

-- ==========================================================================
-- Placement
-- ==========================================================================

local function findOwned(profile: Profile, uid: string): SharedTypes.OwnedBrainrot?
	for _, entry in profile.brainrotsOwned do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

local function slotOccupant(profile: Profile, slot: number): string?
	for _, placed in profile.placedBrainrots do
		if placed.slot == slot then
			return placed.uid
		end
	end
	return nil
end

function PlotService.place(player: Player, uid: any, slot: any): PurchaseResult
	if type(uid) ~= "string" or type(slot) ~= "number" or slot ~= math.floor(slot) then
		return { ok = false, reason = "bad_request" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end
	if not byPlayer[player] then
		return { ok = false, reason = "no_plot" }
	end
	if slot < 1 or slot > profile.plotSlots then
		return { ok = false, reason = "slot_not_unlocked" }
	end
	if not findOwned(profile, uid) then
		return { ok = false, reason = "not_owned" }
	end
	if slotOccupant(profile, slot) then
		return { ok = false, reason = "slot_occupied" }
	end

	for _, placed in profile.placedBrainrots do
		if placed.uid == uid then
			return { ok = false, reason = "already_placed" }
		end
	end

	DataService.update(player, function(p)
		table.insert(p.placedBrainrots, { uid = uid, slot = slot })
	end)

	renderPlot(byPlayer[player])
	RemoteRegistry.event("PlacementChanged"):FireClient(player)
	PlotService.PlacementChanged:Fire(player)
	DataService.pushSnapshot(player)
	return { ok = true }
end

function PlotService.unplace(player: Player, slot: any): PurchaseResult
	if type(slot) ~= "number" or slot ~= math.floor(slot) then
		return { ok = false, reason = "bad_request" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end
	if not slotOccupant(profile, slot) then
		return { ok = false, reason = "slot_empty" }
	end

	DataService.update(player, function(p)
		for index = #p.placedBrainrots, 1, -1 do
			if p.placedBrainrots[index].slot == slot then
				table.remove(p.placedBrainrots, index)
			end
		end
	end)

	local plot = byPlayer[player]
	if plot then
		renderPlot(plot)
	end
	RemoteRegistry.event("PlacementChanged"):FireClient(player)
	PlotService.PlacementChanged:Fire(player)
	DataService.pushSnapshot(player)
	return { ok = true }
end

--[[
	Sells a brainrot outright. Placed ones are unplaced first, so a sale can
	never leave a podium rendering something the player no longer owns.
]]
function PlotService.sellBrainrot(player: Player, uid: any): PurchaseResult
	if type(uid) ~= "string" then
		return { ok = false, reason = "bad_request" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local entry = findOwned(profile, uid)
	if not entry then
		return { ok = false, reason = "not_owned" }
	end

	local payout = BrainrotConfig.sellValueFor(entry.brainrotId, entry.mutation)

	DataService.update(player, function(p)
		for index = #p.placedBrainrots, 1, -1 do
			if p.placedBrainrots[index].uid == uid then
				table.remove(p.placedBrainrots, index)
			end
		end
		for index = #p.brainrotsOwned, 1, -1 do
			if p.brainrotsOwned[index].uid == uid then
				table.remove(p.brainrotsOwned, index)
			end
		end
	end)

	if payout > 0 then
		EconomyService.award(player, payout)
	end

	local plot = byPlayer[player]
	if plot then
		renderPlot(plot)
	end
	RemoteRegistry.event("PlacementChanged"):FireClient(player)
	PlotService.PlacementChanged:Fire(player)
	DataService.pushSnapshot(player)
	return { ok = true, coins = DataService.get(player).coins }
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function PlotService.Init()
	AntiCheatService = require(script.Parent.AntiCheatService)
	DataService = require(script.Parent.DataService)
	EconomyService = require(script.Parent.EconomyService)

	plotFolder = trove:Add(Instance.new("Folder"))
	plotFolder.Name = "Plots"
end

function PlotService.Start()
	plotFolder.Parent = Workspace
	for index = 1, GameConfig.PlotCount do
		table.insert(plots, buildPlot(index))
	end

	RemoteRegistry.func("RequestPlace").OnServerInvoke = function(player, uid, slot)
		if not AntiCheatService.guard(player, "RequestPlace") then
			return { ok = false, reason = "rate_limited" }
		end
		return PlotService.place(player, uid, slot)
	end

	RemoteRegistry.func("RequestUnplace").OnServerInvoke = function(player, slot)
		if not AntiCheatService.guard(player, "RequestUnplace") then
			return { ok = false, reason = "rate_limited" }
		end
		return PlotService.unplace(player, slot)
	end

	RemoteRegistry.func("RequestSellBrainrot").OnServerInvoke = function(player, uid)
		if not AntiCheatService.guard(player, "RequestSellBrainrot") then
			return { ok = false, reason = "rate_limited" }
		end
		return PlotService.sellBrainrot(player, uid)
	end

	-- A plot is claimed once the profile exists, so the podiums can be built
	-- from saved placements rather than appearing empty and then popping in.
	DataService.ProfileLoaded:Connect(function(player: Player)
		claim(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			claim(player)
		end
	end

	DataService.ProfileReleased:Connect(function(player: Player)
		release(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		release(player)
	end)

	-- Buying a podium slot changes how many are active, so the plot needs a
	-- repaint even though no brainrot moved.
	local ShopService = require(script.Parent.ShopService)
	ShopService.Purchased:Connect(function(player: Player, itemId: string)
		if itemId == ShopService.PLOT_SLOT_ID then
			local plot = byPlayer[player]
			if plot then
				renderPlot(plot)
			end
		end
	end)
end

function PlotService.stats()
	local claimed = 0
	for _, plot in plots do
		if plot.owner then
			claimed += 1
		end
	end
	return { built = #plots, claimed = claimed }
end

--[[
	Builds the empty plot shells into `parent`, for MineService's Edit-mode hub
	preview. Geometry only: podium occupants come from player profiles, which do
	not exist outside a running game.

	buildPlot parents into the plotFolder upvalue, so point that at the caller's
	folder for the duration rather than duplicating it -- a copy would be a
	second definition of a plot, and the two would drift.

	Deliberately does not touch `plots`. That list is the live registry Start()
	builds and claim/release mutate; a preview writing into it would leave the
	service believing it already had four plots.
]]
function PlotService.appendPreview(parent: Instance): number
	local folder = Instance.new("Folder")
	folder.Name = "Plots"

	local previous = plotFolder
	plotFolder = folder

	local ok, err = pcall(function()
		for index = 1, GameConfig.PlotCount do
			buildPlot(index)
		end
	end)

	plotFolder = previous

	if not ok then
		folder:Destroy()
		error(`[PlotService] preview build failed: {err}`, 0)
	end

	folder.Parent = parent
	return #folder:GetChildren()
end

return PlotService
