--!strict
--[[
	EffectsController
	Block break bursts and hit feedback.

	Particles are square and short-lived, per the art direction: no soft round
	sparkles, no long fades. Emitters are pooled and parented to a reusable
	anchor part, because spawning an emitter per broken block would allocate
	several times a second during normal mining.

	No sounds. Every Roblox sound needs an asset ID, and DESIGN.md §2 forbids
	hardcoding IDs we cannot verify. ART TODO: add mining, break, and reveal
	sounds once real asset IDs exist.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Modules.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Theme = require(script.Parent.Parent.UI.Theme)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

local EffectsController = {}
EffectsController.Name = "EffectsController"

local player = Players.LocalPlayer
local trove = Trove.new()

-- Bursts further away than this are skipped entirely. On a 20-player server
-- most breaks are happening somewhere the player cannot see.
local MAX_EFFECT_DISTANCE = 120
local POOL_SIZE = 12
local BURST_LIFETIME = 0.7

-- Chips off an ordinary hit, and off a critical one. A crit is gold everywhere
-- it shows -- the chips and the number -- so the two read as one event.
local CHIP_COLOR = Color3.fromRGB(238, 240, 246)
local CRIT_COLOR = Theme.COLOR.coins
local CHIP_COUNT, CRIT_CHIP_COUNT = 5, 14

local folder: Folder
local pool: { BasePart } = {}
local nextIndex = 1

local function makeEmitterPart(): BasePart
	local part = Instance.new("Part")
	part.Name = "Burst"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Emitter"
	-- Empty texture renders as a flat square, which is what we want.
	emitter.Texture = ""
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Lifetime = NumberRange.new(0.3, BURST_LIFETIME)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -42, 0)
	emitter.Rotation = NumberRange.new(0, 90)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	-- Stepped rather than a smooth taper, matching the art direction.
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(0.51, 0.25),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	emitter.Parent = part

	return part
end

-- Round-robin rather than free-list: a burst is fire-and-forget, and cycling
-- means the oldest emitter is always the one reused.
local function acquire(): BasePart
	local part = pool[nextIndex]
	nextIndex = nextIndex % #pool + 1
	return part
end

local function burst(position: Vector3, color: Color3, count: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		if (root.Position - position).Magnitude > MAX_EFFECT_DISTANCE then
			return
		end
	end

	local part = acquire()
	part.Position = position

	local emitter = part:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter.Color = ColorSequence.new(color)
		emitter:Emit(count)
	end
end

-- ==========================================================================
-- Hit numbers
-- ==========================================================================
--[[
	The damage of each swing, floated off the block it landed on.

	Pooled round-robin like the bursts, and for the same reason. Each number is
	a BillboardGui on its own invisible anchor rather than adorned to the block:
	blocks are pooled server-side, so the part a number was raised on may be a
	different block somewhere else before the number has finished rising.

	Snappy rather than soft, per the art direction: the number lands oversized,
	drops to size within a few frames, rises on an ease-out and is gone. The
	only fade is the last fraction of its life, so it does not blink out.
]]

-- Fractions of a number's life: how long the landing pop takes to settle, and
-- when the closing fade begins.
local POP_FRACTION = 0.18
local FADE_FROM = 0.7

-- How far a number is scattered sideways from the block's centre, in studs, so
-- a run of hits on one block reads as separate numbers rather than one that
-- flickers.
local SCATTER = 1.5

local TEXT_SIZE, CRIT_TEXT_SIZE = 24, 34
local POP_SCALE, CRIT_POP_SCALE = 1.5, 2.1

type HitNumber = {
	anchor: BasePart,
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke?,
	scale: UIScale,
	startedAt: number,
	popFrom: number,
}

local hitNumbers: { HitNumber } = {}
local nextHitNumber = 1
local scatter = Random.new()

local function makeHitNumber(): HitNumber
	local anchor = Instance.new("Part")
	anchor.Name = "HitNumber"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = folder

	-- Parented to the anchor, which makes the anchor its adornee. Sized in
	-- pixels so a number reads the same at any reach.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Number"
	gui.Size = UDim2.fromOffset(160, 52)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = anchor

	local label = Theme.label("", {
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT.number,
		TextSize = TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	label.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Parent = label

	return {
		anchor = anchor,
		gui = gui,
		label = label,
		-- Theme.label adds the glyph outline; it has to fade with the text.
		stroke = label:FindFirstChildOfClass("UIStroke"),
		scale = scale,
		startedAt = 0,
		popFrom = POP_SCALE,
	}
end

local function showHitNumber(position: Vector3, amount: number, crit: boolean)
	if #hitNumbers == 0 then
		return
	end

	-- Oldest first, whether or not it has finished: a number cut short by a
	-- newer one is better than a hit that shows nothing.
	local number = hitNumbers[nextHitNumber]
	nextHitNumber = nextHitNumber % #hitNumbers + 1

	number.anchor.Position = position
		+ Vector3.new(scatter:NextNumber(-SCATTER, SCATTER), 0, scatter:NextNumber(-SCATTER, SCATTER))

	local text = Format.abbreviate(math.max(1, math.round(amount)))
	number.label.Text = if crit then text .. "!" else text
	number.label.TextColor3 = if crit then CRIT_COLOR else Theme.COLOR.text
	number.label.TextSize = if crit then CRIT_TEXT_SIZE else TEXT_SIZE
	number.label.TextTransparency = 0
	if number.stroke then
		number.stroke.Transparency = 0
	end

	number.popFrom = if crit then CRIT_POP_SCALE else POP_SCALE
	number.scale.Scale = number.popFrom
	number.gui.StudsOffsetWorldSpace = Vector3.zero
	number.startedAt = os.clock()
	number.gui.Enabled = true
end

--[[
	Heartbeat rather than RenderStepped: nothing here depends on the camera or
	the character's pose this frame, and RenderStepped work holds the frame up.
]]
local function stepHitNumbers()
	local now = os.clock()

	for _, number in hitNumbers do
		if number.gui.Enabled then
			local t = (now - number.startedAt) / GameConfig.HitNumberSeconds

			if t >= 1 then
				number.gui.Enabled = false
			else
				-- Ease-out cubic: most of the rise happens straight away.
				local k = 1 - t
				number.gui.StudsOffsetWorldSpace = Vector3.new(0, GameConfig.HitNumberRise * (1 - k * k * k), 0)

				number.scale.Scale = if t < POP_FRACTION
					then number.popFrom + (1 - number.popFrom) * (t / POP_FRACTION)
					else 1

				local fade = if t > FADE_FROM then (t - FADE_FROM) / (1 - FADE_FROM) else 0
				number.label.TextTransparency = fade
				if number.stroke then
					number.stroke.Transparency = fade
				end
			end
		end
	end
end

function EffectsController.Init()
	folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = Workspace.CurrentCamera or Workspace
	trove:Add(folder)

	for _ = 1, POOL_SIZE do
		table.insert(pool, makeEmitterPart())
	end

	for _ = 1, GameConfig.HitNumberPool do
		table.insert(hitNumbers, makeHitNumber())
	end
end

function EffectsController.Start()
	-- A break anyone can see: fired to all clients, filtered by distance here.
	trove:Connect(RemoteRegistry.event("BlockBroken").OnClientEvent, function(position: Vector3, oreId: string)
		if typeof(position) ~= "Vector3" then
			return
		end
		local ore = OreConfig.get(oreId)
		burst(position, if ore then ore.color else Color3.fromRGB(150, 150, 150), 18)
	end)

	--[[
		A hit only the swinging player sees. The server sends one for every
		swing that lands, including the one that breaks the block, which
		arrives with a fraction of 0.
	]]
	trove:Connect(
		RemoteRegistry.event("BlockDamaged").OnClientEvent,
		function(position: Vector3, fraction: number?, amount: number?, crit: boolean?)
			if typeof(position) ~= "Vector3" then
				return
			end

			local isCrit = crit == true
			if isCrit then
				burst(position, CRIT_COLOR, CRIT_CHIP_COUNT)
			elseif type(fraction) ~= "number" or fraction > 0 then
				-- The breaking hit skips its chips: BlockBroken's burst is
				-- already going off in the same place.
				burst(position, CHIP_COLOR, CHIP_COUNT)
			end

			if type(amount) == "number" then
				showHitNumber(position, amount, isCrit)
			end
		end
	)

	-- Ore landing in the bag: a small flash at the player, so a credit is
	-- visible even when the block that dropped it is off screen.
	trove:Connect(RemoteRegistry.event("OreCredited").OnClientEvent, function(oreId: string)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local ore = OreConfig.get(oreId)
			burst(root.Position + Vector3.new(0, 3, 0), if ore then ore.color else Color3.fromRGB(200, 200, 200), 4)
		end
	end)

	trove:Connect(RunService.Heartbeat, stepHitNumbers)
end

function EffectsController.Stop()
	trove:Clean()
	table.clear(pool)
	table.clear(hitNumbers)
end

return EffectsController
