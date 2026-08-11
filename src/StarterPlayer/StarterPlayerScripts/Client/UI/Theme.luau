--!strict
--[[
	Theme
	Every colour, size, and font the UI uses, plus constructors for the handful
	of shapes it's built from.

	The art direction (DESIGN.md §2a) is enforced here rather than repeated in
	each frame: square corners, hard borders, flat fills, no gradients, no drop
	shadows. If a panel anywhere looks rounded or soft, it bypassed this module.

	Nothing here touches game state -- it is presentation only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)

local Theme = {}

-- ==========================================================================
-- Palette
-- ==========================================================================

Theme.COLOR = table.freeze({
	-- Dark slate, per the doc's §6 brief.
	panel = Color3.fromRGB(26, 28, 34),
	panelRaised = Color3.fromRGB(36, 39, 47),
	panelSunken = Color3.fromRGB(18, 19, 24),
	border = Color3.fromRGB(12, 13, 17),
	borderLight = Color3.fromRGB(64, 69, 82),

	text = Color3.fromRGB(238, 240, 246),
	textDim = Color3.fromRGB(148, 154, 170),
	textDisabled = Color3.fromRGB(96, 100, 114),

	accent = Color3.fromRGB(120, 232, 140),
	coins = Color3.fromRGB(248, 208, 88),
	danger = Color3.fromRGB(236, 96, 96),
	warn = Color3.fromRGB(240, 200, 90),

	buttonIdle = Color3.fromRGB(46, 50, 60),
	buttonHover = Color3.fromRGB(58, 63, 76),
	buttonDisabled = Color3.fromRGB(32, 34, 41),
})

Theme.rarityColor = Rarity.color

-- ==========================================================================
-- Metrics
-- ==========================================================================

Theme.METRIC = table.freeze({
	border = 2, -- hard, uniform, never a gradient
	pad = 10,
	gap = 8,
	-- Nothing interactive is smaller than this. Doc §2: 44px minimum tap target.
	tapTarget = 44,
	rowHeight = 40,
	headerHeight = 42,
	barHeight = 18,
})

Theme.FONT = table.freeze({
	heading = Enum.Font.GothamBlack,
	body = Enum.Font.GothamBold,
	number = Enum.Font.GothamBold,
})

Theme.TEXT_SIZE = table.freeze({
	title = 20,
	heading = 17,
	body = 15,
	small = 13,
})

-- ==========================================================================
-- Constructors
-- ==========================================================================

--[[
	A bordered box. Roblox's own BorderSizePixel draws inside the frame and
	fights layout, so a border here is a parent frame in the border colour with
	the fill inset by `border` on every side. Returns (outer, inner) -- parent
	children to `inner`.
]]
function Theme.panel(props: { [string]: any }?): (Frame, Frame)
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = Theme.COLOR.border
	outer.BorderSizePixel = 0

	local inner = Instance.new("Frame")
	inner.BackgroundColor3 = Theme.COLOR.panel
	inner.BorderSizePixel = 0
	inner.Size = UDim2.new(1, -Theme.METRIC.border * 2, 1, -Theme.METRIC.border * 2)
	inner.Position = UDim2.fromOffset(Theme.METRIC.border, Theme.METRIC.border)
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

	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	return label
end

--[[
	A square, hard-edged button. Returns (button) with hover and disabled
	states already wired. Set `button:SetAttribute("Enabled", false)` to grey it
	out -- the click handler should also check it.
]]
function Theme.button(text: string, props: { [string]: any }?): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Theme.COLOR.buttonIdle
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Theme.FONT.body
	button.TextSize = Theme.TEXT_SIZE.body
	button.TextColor3 = Theme.COLOR.text
	button.Text = text
	button.Size = UDim2.new(1, 0, 0, Theme.METRIC.tapTarget)
	button:SetAttribute("Enabled", true)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = Theme.METRIC.border
	stroke.Color = Theme.COLOR.border
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local function refresh(hovered: boolean)
		local enabled = button:GetAttribute("Enabled") ~= false
		if not enabled then
			button.BackgroundColor3 = Theme.COLOR.buttonDisabled
			button.TextColor3 = Theme.COLOR.textDisabled
		else
			button.BackgroundColor3 = if hovered then Theme.COLOR.buttonHover else Theme.COLOR.buttonIdle
			button.TextColor3 = Theme.COLOR.text
		end
	end

	button.MouseEnter:Connect(function()
		refresh(true)
	end)
	button.MouseLeave:Connect(function()
		refresh(false)
	end)
	button:GetAttributeChangedSignal("Enabled"):Connect(function()
		refresh(false)
	end)
	refresh(false)

	if props then
		for key, value in props do
			(button :: any)[key] = value
		end
	end
	return button
end

--[[
	A flat progress bar. Returns (outer, fill) -- set fill.Size to
	UDim2.fromScale(fraction, 1). No tween, no gradient; it snaps.
]]
function Theme.bar(fillColor: Color3): (Frame, Frame)
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = Theme.COLOR.border
	outer.BorderSizePixel = 0
	outer.Size = UDim2.new(1, 0, 0, Theme.METRIC.barHeight)

	local track = Instance.new("Frame")
	track.BackgroundColor3 = Theme.COLOR.panelSunken
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, -Theme.METRIC.border * 2, 1, -Theme.METRIC.border * 2)
	track.Position = UDim2.fromOffset(Theme.METRIC.border, Theme.METRIC.border)
	track.Parent = outer

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track

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
