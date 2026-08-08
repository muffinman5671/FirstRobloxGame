--!strict
--[[
	MiningService
	Validates swings and applies damage. This is the game's main attack surface,
	so every field in a RequestSwing is treated as hostile.

	A swing is accepted only if all of these hold:
	  1. the profile is loaded
	  2. the character is alive
	  3. the payload is a real Vector3 with finite components
	  4. the block exists in MineService's grid and still has HP
	  5. the block is within the equipped pickaxe's reach of the character
	  6. the player's swing cooldown has elapsed
	  7. the block's layer is unlocked
	  8. the ore's rebirth gate is satisfied

	Damage is always pickaxe.power * rebirthMultiplier, read server-side from
	the profile. The client never sends a damage number, a block id, or an ore
	id -- only where it swung.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LayerConfig = require(ReplicatedStorage.Shared.Config.LayerConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

local MiningService = {}
MiningService.Name = "MiningService"

local DataService
local InventoryService
local MineService

type SwingState = {
	lastSwingClock: number,
	windowStart: number,
	windowCount: number,
	violations: number,
	throttledUntil: number,
}

local swingState: { [Player]: SwingState } = {}

-- Sliding window for the rate check, in seconds.
local RATE_WINDOW = 3
-- How long a player is ignored after tripping the rate limit.
local THROTTLE_SECONDS = 2

local function stateFor(player: Player): SwingState
	local state = swingState[player]
	if not state then
		state = {
			lastSwingClock = 0,
			windowStart = os.clock(),
			windowCount = 0,
			violations = 0,
			throttledUntil = 0,
		}
		swingState[player] = state
	end
	return state
end

local function isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	-- Rejects NaN (x ~= x) and both infinities in one test.
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < math.huge
		and math.abs(v.Y) < math.huge
		and math.abs(v.Z) < math.huge
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function hasUnlockedLayer(profile: any, layerIndex: number): boolean
	for _, index in profile.unlockedLayers do
		if index == layerIndex then
			return true
		end
	end
	return false
end

--[[
	Rate limiting. The pickaxe already imposes a cooldown; this catches a client
	that ignores it. Exceeding the expected rate by SwingRateViolationFactor
	over the window throttles the player briefly and logs it.

	Deliberately forgiving on a single burst -- ping spikes bunch swings
	together -- and progressively harsher on repeat offenders.
]]
local function passesRateLimit(player: Player, state: SwingState, swingsPerSecond: number): boolean
	local now = os.clock()

	if now < state.throttledUntil then
		return false
	end

	if now - state.windowStart >= RATE_WINDOW then
		state.windowStart = now
		state.windowCount = 0
	end

	state.windowCount += 1

	local allowed = swingsPerSecond * RATE_WINDOW * GameConfig.SwingRateViolationFactor
	if state.windowCount > allowed then
		state.violations += 1
		state.throttledUntil = now + THROTTLE_SECONDS * state.violations
		warn(
			`[MiningService] {player.Name} exceeded swing rate `
				.. `({state.windowCount} in {RATE_WINDOW}s, allowed {math.floor(allowed)}); `
				.. `throttled (violation #{state.violations})`
		)
		return false
	end

	return true
end

-- Every refusal path goes through here, so DebugMining gives a complete picture
-- of why a swing did nothing rather than a silent return.
local function refuse(player: Player, reason: string, detail: string?)
	if GameConfig.DebugMining then
		print(`[MiningService] refused swing from {player.Name}: {reason}{if detail then ` ({detail})` else ""}`)
	end
end

local function onSwing(player: Player, rawPosition: any)
	if not isFiniteVector(rawPosition) then
		return refuse(player, "payload is not a finite Vector3", typeof(rawPosition))
	end
	local position = rawPosition :: Vector3

	local profile = DataService.get(player)
	if not profile then
		return refuse(player, "profile not loaded")
	end

	local root = characterRoot(player)
	if not root then
		return refuse(player, "no living character")
	end

	local pickaxe = ToolConfig.getPickaxe(profile.equippedPickaxe)
		or ToolConfig.getPickaxe(ToolConfig.STARTER_PICKAXE)
	if not pickaxe then
		return refuse(player, "equipped pickaxe is not a real pickaxe", profile.equippedPickaxe)
	end

	local state = stateFor(player)
	if not passesRateLimit(player, state, pickaxe.swingsPerSecond) then
		return refuse(player, "rate limited")
	end

	-- Cooldown, with a tolerance for ping jitter.
	local now = os.clock()
	local cooldown = (1 / pickaxe.swingsPerSecond) * (1 - GameConfig.SwingCooldownTolerance)
	if now - state.lastSwingClock < cooldown then
		return refuse(player, "swing cooldown", `{string.format("%.2f", now - state.lastSwingClock)}s < {string.format("%.2f", cooldown)}s`)
	end

	local block = MineService.blockAt(position)
	if not block then
		return refuse(player, "no block at that position", tostring(position))
	end

	-- Reach is measured to the block centre from the character root.
	local reach = pickaxe.reach + GameConfig.ReachTolerance
	local distance = (block.part.Position - root.Position).Magnitude
	if distance > reach then
		return refuse(player, "out of reach", `{string.format("%.1f", distance)} > {string.format("%.1f", reach)}`)
	end

	if not hasUnlockedLayer(profile, block.layerIndex) then
		local layer = LayerConfig.get(block.layerIndex)
		RemoteRegistry.event("NotifyToast"):FireClient(
			player,
			"locked_layer",
			`{if layer then layer.displayName else "This layer"} is locked`
		)
		return refuse(player, "layer locked", tostring(block.layerIndex))
	end

	local ore = OreConfig.get(block.oreId)
	if ore and ore.minRebirths and profile.rebirths < ore.minRebirths then
		RemoteRegistry.event("NotifyToast"):FireClient(
			player,
			"locked_ore",
			`{ore.displayName} needs {ore.minRebirths} rebirths`
		)
		return
	end

	state.lastSwingClock = now

	local damage = pickaxe.power * ToolConfig.rebirthMultiplier(profile.rebirths)
	local result, hit = MineService.damageAt(position, damage)

	if GameConfig.DebugMining then
		print(
			`[MiningService] {player.Name} hit {block.oreId} for {damage} -> {result} `
				.. `({string.format("%.1f", distance)} studs)`
		)
	end

	if result == "missing" or not hit then
		return
	end

	if result == "damaged" then
		RemoteRegistry.event("BlockDamaged"):FireClient(player, position, hit.hp / hit.maxHp)
		return
	end

	-- Broken.
	local yield = math.random(GameConfig.OreYieldMin, GameConfig.OreYieldMax)
	local credited = InventoryService.tryAdd(player, hit.oreId, yield)

	-- Everyone nearby should see the break, not just the miner.
	RemoteRegistry.event("BlockBroken"):FireAllClients(position, hit.oreId)

	if credited > 0 then
		DataService.update(player, function(p)
			p.indexDiscovered[hit.oreId] = true
		end)
	end

	MineService.BlockBroken:Fire(player, hit.oreId, hit.layerIndex, position)
end

-- ==========================================================================
-- The pickaxe tool
-- ==========================================================================

--[[
	A real Roblox Tool, not just a client input handler. Three reasons:
	  - it's the affordance players expect; the pickaxe is visible in hand
	  - Tool.Activated gives mobile the standard fire button and console the
	    standard trigger, with no per-platform input code
	  - equipping is an unambiguous "I am mining now" signal, so clicking a
	    shop UI or the world never fires a swing

	Built from primitives -- no asset IDs. ART TODO: replace the head and handle
	with proper meshes and add a swing animation.
]]
local function buildPickaxeTool(def): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.displayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("MiningPickaxe", true)
	tool:SetAttribute("PickaxeId", def.id)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 3.2, 0.4)
	handle.Color = Color3.fromRGB(104, 74, 48)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	-- Head brightens with tier so an upgrade is visible at a glance.
	local tierProgress = (def.tier - 1) / math.max(1, #ToolConfig.PICKAXES - 1)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2.2, 0.55, 0.55)
	head.Color = Color3.fromRGB(120, 120, 128):Lerp(Color3.fromRGB(232, 226, 255), tierProgress)
	head.Material = Enum.Material.Metal
	head.CanCollide = false
	head.Massless = true
	head.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle

	head.CFrame = handle.CFrame * CFrame.new(0, 1.5, 0)

	tool.Grip = CFrame.new(0, -0.8, 0)
	return tool
end

-- Replaces whatever pickaxe the player is holding with the one their profile
-- says is equipped, then equips it so they can mine immediately on spawn.
local function givePickaxe(player: Player)
	local profile = DataService.get(player)
	local character = player.Character
	if not profile or not character then
		return
	end

	local def = ToolConfig.getPickaxe(profile.equippedPickaxe) or ToolConfig.getPickaxe(ToolConfig.STARTER_PICKAXE)
	if not def then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	-- Clear any stale pickaxe, in Backpack and in hand.
	for _, container in { backpack, character } do
		for _, item in container:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("MiningPickaxe") then
				item:Destroy()
			end
		end
	end

	local tool = buildPickaxeTool(def)
	tool.Parent = backpack

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:EquipTool(tool)
	end
end

MiningService.givePickaxe = givePickaxe

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function MiningService.Init()
	DataService = require(script.Parent.DataService)
	InventoryService = require(script.Parent.InventoryService)
	MineService = require(script.Parent.MineService)
end

function MiningService.Start()
	RemoteRegistry.event("RequestSwing").OnServerEvent:Connect(function(player, position)
		local ok, err = pcall(onSwing, player, position)
		if not ok then
			warn(`[MiningService] swing from {player.Name} errored: {err}`)
		end
	end)

	-- Hand out the pickaxe on every spawn. The character can appear before the
	-- profile finishes loading, so wait for it rather than defaulting to the
	-- starter tool for someone who owns better.
	local function onCharacter(player: Player)
		task.spawn(function()
			if DataService.waitFor(player, 20) then
				givePickaxe(player)
			end
		end)
	end

	local function watch(player: Player)
		if player.Character then
			onCharacter(player)
		end
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)

	Players.PlayerRemoving:Connect(function(player)
		swingState[player] = nil
	end)
end

-- Exposed for tests and the admin readout.
function MiningService.stateFor(player: Player): SwingState?
	return swingState[player]
end

return MiningService
