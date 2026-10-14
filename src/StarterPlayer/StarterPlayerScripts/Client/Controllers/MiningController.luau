--!strict
--[[
	MiningController
	Input, target selection, and the swing loop.

	Purely a requester. It picks a block, rate-limits itself to the equipped
	pickaxe's speed to avoid spamming a server that would reject the extras
	anyway, and fires RequestSwing with the block's centre. Every decision that
	matters -- damage, whether the block breaks, whether ore is credited -- is
	the server's.

	The local reach and cooldown checks exist so the game feels responsive, not
	as security. Bypassing them just gets the swing dropped server-side.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local SwingAnimator = require(script.Parent.Parent.Animation.SwingAnimator)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local MiningController = {}
MiningController.Name = "MiningController"

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local trove = Trove.new()

local snapshot: ProfileSnapshot? = nil
local mineFolder: Folder? = nil

local holding = false
local equipped = false
local lastSwingClock = 0
local aimPosition: Vector2? = nil

-- Cached per spawn. The targeting path runs every frame and must not do
-- instance lookups; see DESIGN.md §2.
local rootPart: BasePart? = nil

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.IgnoreWater = true

-- ==========================================================================
-- Equipped pickaxe
-- ==========================================================================

local function currentPickaxe()
	local equipped = if snapshot then snapshot.equippedPickaxe else ToolConfig.STARTER_PICKAXE
	return ToolConfig.getPickaxe(equipped) or ToolConfig.getPickaxe(ToolConfig.STARTER_PICKAXE)
end

-- ==========================================================================
-- Targeting
-- ==========================================================================

--[[
	Aim ray.

	UserInputService reports mouse and touch positions in *screen* space, which
	excludes the top-bar inset, while ViewportPointToRay expects viewport space,
	which includes it. Mixing the two aims consistently high by the inset
	height. ScreenPointToRay does the conversion, so it's the right call for any
	input-derived point; the no-aim fallback is genuinely a viewport centre.
]]
local function aimRay(): Ray
	if aimPosition then
		return camera:ScreenPointToRay(aimPosition.X, aimPosition.Y)
	end
	local viewport = camera.ViewportSize
	return camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
end

--[[
	Returns (block, inRange). A block with inRange = false is what the player is
	looking at but cannot hit yet -- the highlight renders that state in red
	rather than showing nothing, because "nothing happens when I click" with no
	explanation is exactly how a reach problem stays invisible.
]]
local function resolveTarget(): (BasePart?, boolean)
	if not mineFolder then
		return nil, false
	end

	local pickaxe = currentPickaxe()
	if not pickaxe then
		return nil, false
	end

	-- Cached on spawn rather than looked up here: this runs every frame, and
	-- DESIGN.md §2 forbids per-frame FindFirstChild in hot paths.
	local root = rootPart
	if not root or not root.Parent then
		return nil, false
	end

	local ray = aimRay()
	raycastParams.FilterDescendantsInstances = { mineFolder }

	-- Cast well past reach so we can still report an out-of-range target.
	local result = Workspace:Raycast(ray.Origin, ray.Direction * (pickaxe.reach + 240), raycastParams)
	if not result or not result.Instance then
		return nil, false
	end

	local part = result.Instance
	-- Measured from the character, not the camera: the camera sits behind the
	-- player in third person and would otherwise inflate the effective reach.
	return part, (part.Position - root.Position).Magnitude <= pickaxe.reach
end

-- ==========================================================================
-- Target highlight
-- ==========================================================================

local IN_RANGE = Color3.fromRGB(120, 232, 140)
local OUT_OF_RANGE = Color3.fromRGB(236, 96, 96)

-- Impact punch on the outline: colour, how long it decays over, and the two
-- ends of the thickness and surface ramps.
local FLASH = Color3.fromRGB(255, 252, 226)
local FLASH_SECONDS = 0.16
local LINE_REST, LINE_FLASH = 0.035, 0.11
local SURFACE_REST, SURFACE_FLASH = 0.88, 0.45

local impactClock = -math.huge
local highlight: SelectionBox? = nil

local function ensureHighlight(): SelectionBox
	if highlight and highlight.Parent then
		return highlight
	end

	local box = Instance.new("SelectionBox")
	box.Name = "MiningTarget"
	box.LineThickness = LINE_REST
	box.Transparency = 0.15
	box.SurfaceTransparency = SURFACE_REST
	box.Parent = camera

	highlight = box
	trove:Add(box)
	return box
end

local function showTarget(part: BasePart?, inRange: boolean)
	local box = ensureHighlight()
	box.Adornee = part

	if not part then
		return
	end

	--[[
		Punch the outline on the frame the head actually lands, then let it
		decay. The server's BlockDamaged burst is the authoritative feedback,
		but it arrives a round trip later -- long enough that the hit reads as
		unconnected to the swing that caused it. This one is timed off the
		animation, so contact and reaction happen together.
	]]
	local since = os.clock() - impactClock
	local flash = if since < FLASH_SECONDS then 1 - since / FLASH_SECONDS else 0
	flash *= flash

	local color = if inRange then IN_RANGE else OUT_OF_RANGE
	box.Color3 = color:Lerp(FLASH, flash)
	box.SurfaceColor3 = box.Color3
	box.LineThickness = LINE_REST + (LINE_FLASH - LINE_REST) * flash
	box.SurfaceTransparency = SURFACE_REST + (SURFACE_FLASH - SURFACE_REST) * flash
end

-- ==========================================================================
-- Block health bar
-- ==========================================================================
--[[
	Shown above the block being aimed at, but only once it has actually taken
	damage -- an untouched wall stays clean. Reads the HpFraction attribute the
	server writes; it is display only and the client never reports it back.

	Square corners and hard borders, per the art direction in DESIGN.md.
]]

local healthGui: BillboardGui? = nil
local healthFill: Frame? = nil

local function ensureHealthBar(): BillboardGui
	if healthGui and healthGui.Parent then
		return healthGui
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "BlockHealth"
	gui.Size = UDim2.fromOffset(GameConfig.BlockHealthBarWidth, GameConfig.BlockHealthBarHeight)
	gui.StudsOffsetWorldSpace = Vector3.new(0, GameConfig.BlockHealthBarOffset, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Parent = camera

	local border = Instance.new("Frame")
	border.Size = UDim2.fromScale(1, 1)
	border.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	border.BorderSizePixel = 0
	border.Parent = gui

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -4, 1, -4)
	track.Position = UDim2.fromOffset(2, 2)
	track.BackgroundColor3 = Color3.fromRGB(52, 52, 60)
	track.BorderSizePixel = 0
	track.Parent = border

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = IN_RANGE
	fill.BorderSizePixel = 0
	fill.Parent = track

	healthGui = gui
	healthFill = fill
	trove:Add(gui)
	return gui
end

local function showHealth(part: BasePart?)
	local gui = ensureHealthBar()

	local fraction = if part then part:GetAttribute("HpFraction") else nil
	if not part or type(fraction) ~= "number" or fraction >= 1 then
		gui.Enabled = false
		gui.Adornee = nil
		return
	end

	gui.Adornee = part
	gui.Enabled = true

	local clamped = math.clamp(fraction, 0, 1)
	if healthFill then
		healthFill.Size = UDim2.fromScale(clamped, 1)
		-- Green through amber to red as the block gives way.
		healthFill.BackgroundColor3 = if clamped > 0.5
			then Color3.fromRGB(120, 232, 140):Lerp(Color3.fromRGB(240, 200, 90), (1 - clamped) * 2)
			else Color3.fromRGB(240, 200, 90):Lerp(Color3.fromRGB(236, 96, 96), 1 - clamped * 2)
	end
end

-- ==========================================================================
-- Swing loop
-- ==========================================================================

local function step()
	if not equipped then
		showTarget(nil, false)
		showHealth(nil)
		return
	end

	local pickaxe = currentPickaxe()
	if not pickaxe then
		return
	end

	-- The swing itself poses on its own render bind, one step after the
	-- Animator, so there is nothing to drive from here.
	local target, inRange = resolveTarget()

	-- The highlight and health bar update whether or not the button is held, so
	-- the player can see what they're aiming at, whether they're close enough,
	-- and how far through the block they are.
	showTarget(target, inRange)
	showHealth(if inRange then target else nil)

	if not holding or not target or not inRange then
		return
	end

	local now = os.clock()
	if now - lastSwingClock < 1 / pickaxe.swingsPerSecond then
		return
	end

	lastSwingClock = now
	SwingAnimator.swing(1 / pickaxe.swingsPerSecond)
	RemoteRegistry.event("RequestSwing"):FireServer(target.Position)

	if GameConfig.DebugMining then
		print(`[MiningController] sent swing at {target.Name}`)
	end
end

-- ==========================================================================
-- Input
-- ==========================================================================

--[[
	Swinging is gated on the pickaxe Tool being equipped and activated, rather
	than on raw mouse/touch input. Tool.Activated already maps to click, tap on
	the mobile fire button, and ButtonR2 on a gamepad, so there's no per-platform
	branch here -- and clicking a shop button can never be mistaken for a swing.
]]
local toolTrove = trove:Extend()

-- A pickaxe parented to the character *is* an equipped pickaxe; Roblox moves it
-- back to the Backpack on unequip.
local function bindTool(tool: Tool)
	toolTrove:Clean()
	equipped = true
	SwingAnimator.setTool(tool)

	if GameConfig.DebugMining then
		print(`[MiningController] pickaxe equipped: {tool.Name}`)
	end

	toolTrove:Connect(tool.Activated, function()
		holding = true
		if GameConfig.DebugMining then
			local target, inRange = resolveTarget()
			print(
				`[MiningController] Activated -- target={if target then target.Name else "NONE"} `
					.. `inRange={inRange} aim={if aimPosition then "mouse" else "screen centre"}`
			)
		end
	end)
	toolTrove:Connect(tool.Deactivated, function()
		holding = false
	end)
	toolTrove:Connect(tool.Unequipped, function()
		holding = false
		equipped = false
		SwingAnimator.setTool(nil)
	end)
end

local function watchCharacter(character: Model)
	holding = false
	equipped = false
	SwingAnimator.attach(character)

	-- The root may not exist yet on a fresh character; wait off-thread so this
	-- never blocks the boot sequence.
	rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		task.spawn(function()
			local found = character:WaitForChild("HumanoidRootPart", 10)
			if found and found:IsA("BasePart") and player.Character == character then
				rootPart = found
			end
		end)
	end

	for _, item in character:GetChildren() do
		if item:IsA("Tool") and item:GetAttribute("MiningPickaxe") then
			bindTool(item)
		end
	end

	trove:Connect(character.ChildAdded, function(child)
		if child:IsA("Tool") and child:GetAttribute("MiningPickaxe") then
			bindTool(child)
		end
	end)

	trove:Connect(character.ChildRemoved, function(child)
		if child:IsA("Tool") and child:GetAttribute("MiningPickaxe") then
			holding = false
			equipped = false
			SwingAnimator.setTool(nil)
		end
	end)
end

-- Mouse position is still tracked, but only to aim; it never starts a swing.
local function onInputChanged(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		aimPosition = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.UserInputType == Enum.UserInputType.Touch and holding then
		aimPosition = Vector2.new(input.Position.X, input.Position.Y)
	end
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function MiningController.Init()
	camera = Workspace.CurrentCamera
end

function MiningController.Start()
	-- The mine folder appears when MineService starts; on a fast client that
	-- can be after this controller runs.
	task.spawn(function()
		local found = Workspace:WaitForChild("Mine", 30)
		if found and found:IsA("Folder") then
			mineFolder = found
		else
			warn("[MiningController] Workspace.Mine never appeared; mining disabled")
		end
	end)

	-- Initial state. The profile may still be loading, so retry rather than
	-- caching a nil and running on starter-tool assumptions forever.
	task.spawn(function()
		local getSnapshot = RemoteRegistry.func("GetProfileSnapshot")
		for _ = 1, 20 do
			local ok, result = pcall(function()
				return getSnapshot:InvokeServer()
			end)
			if ok and result then
				snapshot = result
				return
			end
			task.wait(0.5)
		end
		warn("[MiningController] profile snapshot never arrived; using starter tool stats")
	end)

	trove:Connect(RemoteRegistry.event("ProfileUpdated").OnClientEvent, function(updated: ProfileSnapshot)
		snapshot = updated
	end)

	-- Fired the frame the pickaxe head lands, not when the server answers.
	SwingAnimator.onImpact(function()
		impactClock = os.clock()
	end)

	trove:Connect(UserInputService.InputChanged, onInputChanged)

	-- Releasing the button outside the window never fires Deactivated.
	trove:Connect(UserInputService.WindowFocusReleased, function()
		holding = false
	end)

	if player.Character then
		watchCharacter(player.Character)
	end
	trove:Connect(player.CharacterAdded, watchCharacter)

	-- Runs every frame, not only while swinging: the highlight is what tells the
	-- player what they're aiming at and whether it's in reach.
	trove:Connect(RunService.RenderStepped, step)

	trove:Connect(player.CharacterRemoving, function()
		holding = false
		equipped = false
		rootPart = nil
		SwingAnimator.detach()
		showTarget(nil, false)
		showHealth(nil)
	end)
end

function MiningController.Stop()
	-- The animator holds a render-step bind of its own, which the trove never
	-- sees; unbinding it is the whole reason detach exists.
	SwingAnimator.detach()
	trove:Clean()
end

return MiningController
