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
local Workspace = game:GetService("Workspace")

local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
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

function EffectsController.Init()
	folder = Instance.new("Folder")
	folder.Name = "Effects"
	folder.Parent = Workspace.CurrentCamera or Workspace
	trove:Add(folder)

	for _ = 1, POOL_SIZE do
		table.insert(pool, makeEmitterPart())
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

	-- A hit only the swinging player sees, so it stays small.
	trove:Connect(RemoteRegistry.event("BlockDamaged").OnClientEvent, function(position: Vector3)
		if typeof(position) ~= "Vector3" then
			return
		end
		burst(position, Color3.fromRGB(238, 240, 246), 5)
	end)

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
end

function EffectsController.Stop()
	trove:Clean()
	table.clear(pool)
end

return EffectsController
