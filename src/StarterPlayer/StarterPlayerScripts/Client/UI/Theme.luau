--!strict
--[[
	Theme
	Every colour, size, and font the UI uses, plus constructors for the handful
	of shapes it's built from.

	The art direction (DESIGN.md 2a) is enforced here rather than repeated in
	each frame: **chunky rounded corners, a heavy near-black outline on
	everything, a soft vertical gradient on every fill, and outlined text**. If a
	panel anywhere looks flat, square or unoutlined, it bypassed this module.

	This replaced a brutalist pass -- square corners, flat fills, 2px borders --
	on reference art the owner supplied. The three things that carry the style
	are, in order: the outline (thick, near-black, on every shape), the corner
	radius, and the text stroke. Colour is the least of it; a panel in the wrong
	hue but with the right outline still reads as belonging.

	Nothing here touches game state -- it is presentation only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)

local Theme = {}

-- ==========================================================================
-- Palette
-- ==========================================================================

Theme.COLOR = table.freeze({
	-- Deep indigo rather than the old slate. The reference art sits its panels
	-- in a saturated dark violet, which gives the accent colours far more to
	-- push against than a neutral grey does.
	panel = Color3.fromRGB(40, 33, 66),
	panelRaised = Color3.fromRGB(58, 48, 92),
	panelSunken = Color3.fromRGB(26, 21, 46),

	-- The outline. Near-black rather than black so it still reads as a drawn
	-- line against a pure-black background.
	border = Color3.fromRGB(10, 8, 20),
	borderLight = Color3.fromRGB(124, 108, 186),

	text = Color3.fromRGB(255, 255, 255),
	textDim = Color3.fromRGB(186, 178, 214),
	textDisabled = Color3.fromRGB(128, 122, 150),

	accent = Color3.fromRGB(96, 232, 138), -- green: money, gains, confirms
	accentAlt = Color3.fromRGB(64, 198, 255), -- cyan: information, index
	header = Color3.fromRGB(186, 62, 214), -- magenta: title bands
	coins = Color3.fromRGB(255, 208, 56),
	danger = Color3.fromRGB(238, 66, 66),
	warn = Color3.fromRGB(250, 178, 44),
	reward = Color3.fromRGB(255, 112, 64), -- orange-red: the daily reward, and nothing else

	buttonIdle = Color3.fromRGB(86, 74, 130),
	buttonHover = Color3.fromRGB(106, 93, 158),
	buttonDisabled = Color3.fromRGB(54, 48, 74),
})

Theme.rarityColor = Rarity.color

-- ==========================================================================
-- Metrics
-- ==========================================================================

Theme.METRIC = table.freeze({
	-- Kept at 2 because frames inset their content by it. The *visible* outline
	-- is `stroke`, drawn outside the shape by UIStroke, so it costs no layout.
	border = 2,
	stroke = 4, -- the heavy outline on every shape
	strokeThin = 3, -- on small shapes, where 4 swallows the fill
	textStroke = 2, -- glyph outline
	corner = 14,
	cornerSmall = 8,

	pad = 10,
	gap = 8,
	-- Nothing interactive is smaller than this. Doc 2: 44px minimum tap target.
	tapTarget = 44,
	rowHeight = 40,
	headerHeight = 46,
	barHeight = 20,
})

Theme.FONT = table.freeze({
	heading = Enum.Font.GothamBlack,
	body = Enum.Font.GothamBold,
	number = Enum.Font.GothamBlack,
})

Theme.TEXT_SIZE = table.freeze({
	title = 22,
	heading = 18,
	body = 15,
	small = 13,
})

-- ==========================================================================
-- Primitives
-- ==========================================================================

function Theme.corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.METRIC.corner)
	corner.Parent = parent
	return corner
end

--[[
	The outline. `Border` mode draws it *outside* the shape, so it never eats
	into the fill or shifts a layout -- which is why the old 2px inset-border
	approach could be dropped without re-measuring every frame.
]]
function Theme.stroke(parent: Instance, thickness: number?, colour: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or Theme.METRIC.stroke
	stroke.Color = colour or Theme.COLOR.border
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

--[[
	The sheen every fill carries: lighter at the top, deeper at the bottom.

	A UIGradient multiplies whatever BackgroundColor3 the shape already has, so
	this is written as a brightness ramp rather than as two colours -- one helper
	works on a green button, a magenta header and a dark panel alike, and none of
	them has to know its own colour to be shaded.
]]
function Theme.sheen(parent: Instance, top: number?, bottom: number?): UIGradient
	local topScale = top or 1.18
	local bottomScale = bottom or 0.82

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90 -- top to bottom
	gradient.Color = ColorSequence.new(
		Color3.new(topScale, topScale, topScale),
		Color3.new(bottomScale, bottomScale, bottomScale)
	)
	gradient.Parent = parent
	return gradient
end

-- The glyph outline. Contextual mode strokes the text rather than the box,
-- which is what we want on a label whose background is transparent.
function Theme.textStroke(label: Instance, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or Theme.METRIC.textStroke
	stroke.Color = Theme.COLOR.border
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

-- ==========================================================================
-- Constructors
-- ==========================================================================

--[[
	A panel. Returns (outer, inner) -- parent children to `inner`.

	`outer` carries the look; `inner` is a transparent full-size frame the
	contents sit in. The pair is kept even though the outline no longer needs a
	second frame to draw it, because every caller already parents to `inner`.
]]
function Theme.panel(props: { [string]: any }?): (Frame, Frame)
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = Theme.COLOR.panel
	outer.BorderSizePixel = 0
	Theme.corner(outer)
	Theme.stroke(outer)
	Theme.sheen(outer, 1.1, 0.88)

	local inner = Instance.new("Frame")
	inner.Name = "Content"
	inner.BackgroundTransparency = 1
	inner.BorderSizePixel = 0
	inner.Size = UDim2.fromScale(1, 1)
	inner.Parent = outer

	if props then
		for key, value in props do
			(outer :: any)[key] = value
		end
	end

	return outer, inner
end

function Theme.label(text: string, props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT.body
	label.TextSize = Theme.TEXT_SIZE.body
	label.TextColor3 = Theme.COLOR.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = text
	Theme.textStroke(label)

	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	return label
end

--[[
	A button. Returns it with hover and disabled states wired. Set
	`button:SetAttribute("Enabled", false)` to grey it out -- the click handler
	should check it too.

	Pass `accent` in props to colour it (the Shop and Index buttons in the
	reference are saturated green and cyan); it is consumed here rather than
	assigned to the instance. The text uses the built-in TextStroke rather than a
	UIStroke, because an instance gets one UIStroke and the button spends its on
	the outline.

	A button that is one of a set -- a tab -- takes
	`button:SetAttribute("Selected", true)` rather than having its colours
	poked from outside. Two reasons it has to work this way: `refresh` reassigns
	both colours on every hover, so anything set externally survives only until
	the pointer crosses it; and the caller cannot know that dark text is now
	unreadable, because the black glyph outline this style adds swallows it.
	`activeColour` overrides what Selected looks like.
]]
function Theme.button(text: string, props: { [string]: any }?): TextButton
	local accent = props and props.accent
	local activeColour = props and props.activeColour
	if props then
		props.accent = nil
		props.activeColour = nil
	end

	local idle = (accent :: Color3?) or Theme.COLOR.buttonIdle
	local active = (activeColour :: Color3?) or Theme.COLOR.accent

	local button = Instance.new("TextButton")
	button.BackgroundColor3 = idle
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Theme.FONT.heading
	button.TextSize = Theme.TEXT_SIZE.body
	button.TextColor3 = Theme.COLOR.text
	button.TextStrokeColor3 = Theme.COLOR.border
	button.TextStrokeTransparency = 0
	button.Text = text
	button.Size = UDim2.new(1, 0, 0, Theme.METRIC.tapTarget)
	button:SetAttribute("Enabled", true)
	button:SetAttribute("Selected", false)

	Theme.corner(button, Theme.METRIC.cornerSmall)
	Theme.stroke(button, Theme.METRIC.strokeThin)
	Theme.sheen(button)

	-- Text stays white in every state bar disabled. White on a black outline
	-- reads against any accent, which is the point of outlining it.
	local function refresh(hovered: boolean)
		if button:GetAttribute("Enabled") == false then
			button.BackgroundColor3 = Theme.COLOR.buttonDisabled
			button.TextColor3 = Theme.COLOR.textDisabled
			return
		end

		local base = if button:GetAttribute("Selected") then active else idle
		button.BackgroundColor3 = if hovered then base:Lerp(Color3.new(1, 1, 1), 0.18) else base
		button.TextColor3 = Theme.COLOR.text
	end

	button.MouseEnter:Connect(function()
		refresh(true)
	end)
	button.MouseLeave:Connect(function()
		refresh(false)
	end)
	for _, attribute in { "Enabled", "Selected" } do
		button:GetAttributeChangedSignal(attribute):Connect(function()
			refresh(false)
		end)
	end
	refresh(false)

	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	return button
end

--[[
	A panel's title band, with its own outline and its own close button -- the
	reference draws the header as a distinct bar sitting on the panel rather than
	as a flat strip of different colour.

	Returns (header, close). Inset by the stroke width so its outline sits beside
	the panel's rather than on top of it. Content below still starts at
	headerHeight, so this drops into the frames' existing layout arithmetic.
]]
function Theme.header(title: string, props: { [string]: any }?): (Frame, TextButton)
	local accent = (props and props.accent :: Color3?) or Theme.COLOR.header
	local inset = Theme.METRIC.stroke

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = accent
	header.BorderSizePixel = 0
	header.Position = UDim2.fromOffset(inset, inset)
	header.Size = UDim2.new(1, -inset * 2, 0, Theme.METRIC.headerHeight)
	Theme.corner(header, Theme.METRIC.cornerSmall)
	Theme.stroke(header, Theme.METRIC.strokeThin)
	Theme.sheen(header, 1.25, 0.78)

	local label = Theme.label(title:upper(), {
		Font = Theme.FONT.heading,
		TextSize = Theme.TEXT_SIZE.title,
		Size = UDim2.new(1, -Theme.METRIC.tapTarget - Theme.METRIC.pad, 1, 0),
		Position = UDim2.fromOffset(Theme.METRIC.pad + 2, 0),
	})
	label.Parent = header

	local close = Theme.button("X", {
		accent = Theme.COLOR.danger,
		TextSize = Theme.TEXT_SIZE.heading,
		Size = UDim2.fromOffset(Theme.METRIC.tapTarget - 8, Theme.METRIC.headerHeight - 10),
		Position = UDim2.new(1, -Theme.METRIC.tapTarget + 3, 0, 5),
	})
	close.Parent = header

	return header, close
end

--[[
	Turns a frame the caller has already made and sized into a card: a panel's
	treatment, one step down in corner radius and sheen, for the elements that
	repeat down a list.

	Takes an existing frame rather than making one because the four call sites
	share only the look -- each wants its own size, colour and layout order.
]]
function Theme.card(frame: GuiObject): GuiObject
	Theme.corner(frame, Theme.METRIC.cornerSmall)
	Theme.stroke(frame, Theme.METRIC.strokeThin)
	Theme.sheen(frame, 1.08, 0.9)
	return frame
end

--[[
	The rarity or accent stripe down the left of a card.

	Inset and rounded rather than flush to the card's edge: a square bar in the
	corner of a rounded card shows its own corners sticking out past the curve.
	Cards leave their labels clear of x = 13, which this still fits inside.
]]
function Theme.accentBar(colour: Color3): Frame
	local bar = Instance.new("Frame")
	bar.Name = "AccentBar"
	bar.BackgroundColor3 = colour
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0, 6, 1, -10)
	bar.Position = UDim2.fromOffset(5, 5)
	Theme.corner(bar, 3)
	Theme.sheen(bar)
	return bar
end

--[[
	A progress bar. Returns (outer, fill) -- set fill.Size to
	UDim2.fromScale(fraction, 1).

	The fill is rounded like everything else, which means at very low fractions
	it collapses to a lozenge narrower than its own corner radius. That reads
	fine, and is preferable to a square nub on an otherwise rounded UI.
]]
function Theme.bar(fillColor: Color3): (Frame, Frame)
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = Theme.COLOR.panelSunken
	outer.BorderSizePixel = 0
	outer.ClipsDescendants = true
	outer.Size = UDim2.new(1, 0, 0, Theme.METRIC.barHeight)
	Theme.corner(outer, Theme.METRIC.cornerSmall)
	Theme.stroke(outer, Theme.METRIC.strokeThin)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = outer
	Theme.corner(fill, Theme.METRIC.cornerSmall)
	Theme.sheen(fill)

	return outer, fill
end

-- Vertical list layout with the standard gap. Saves repeating four lines.
function Theme.list(parent: Instance, padding: number?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding or Theme.METRIC.gap)
	layout.Parent = parent
	return layout
end

function Theme.padding(parent: Instance, amount: number?): UIPadding
	local pad = Instance.new("UIPadding")
	local value = UDim.new(0, amount or Theme.METRIC.pad)
	pad.PaddingTop = value
	pad.PaddingBottom = value
	pad.PaddingLeft = value
	pad.PaddingRight = value
	pad.Parent = parent
	return pad
end

--[[
	UI scale for the viewport. Phones get a slightly larger scale so 44px tap
	targets stay 44 real pixels rather than shrinking with the layout.
]]
function Theme.scaleFor(viewport: Vector2): number
	local shortEdge = math.min(viewport.X, viewport.Y)
	if shortEdge <= 500 then
		return 0.82
	elseif shortEdge <= 800 then
		return 0.92
	end
	return 1
end

return Theme
