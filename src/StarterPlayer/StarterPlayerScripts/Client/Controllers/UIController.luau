--!strict
--[[
	UIController
	Owns the ScreenGui, the profile snapshot the frames render from, and the
	wiring between a click and a remote call.

	The frames themselves are dumb views: they never call a remote and never
	decide whether something is allowed. Everything routes through here, so
	there is one place to look when a button does nothing.

	Toasts are handled inline for now. NotifyController takes them over in phase
	E along with the rarity reveal; the remote it will listen to already exists.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HUD = require(script.Parent.Parent.UI.HUD)
local InventoryFrame = require(script.Parent.Parent.UI.InventoryFrame)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local ShopFrame = require(script.Parent.Parent.UI.ShopFrame)
local Theme = require(script.Parent.Parent.UI.Theme)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

type ProfileSnapshot = SharedTypes.ProfileSnapshot

local UIController = {}
UIController.Name = "UIController"

local player = Players.LocalPlayer
local trove = Trove.new()

local snapshot: ProfileSnapshot? = nil
local screen: ScreenGui
local hud, inventory, shop
local toastLabel: TextLabel
local toastUntil = 0

-- Human-readable text for the refusal reasons the server sends back. An
-- unmapped reason falls through to the raw string rather than being swallowed,
-- so a new server-side refusal is visible instead of silently doing nothing.
local REASON_TEXT: { [string]: string } = {
	cannot_afford = "Not enough coins",
	already_owned = "Already owned",
	already_equipped = "Already equipped",
	not_owned = "You don't own that",
	previous_tier_missing = "Buy the previous tier first",
	previous_layer_locked = "Unlock the layer above first",
	already_unlocked = "Already unlocked",
	max_slots = "All podium slots unlocked",
	nothing_to_sell = "Nothing to sell",
	none_held = "You don't have any of that",
	rate_limited = "Slow down",
	profile_not_loaded = "Still loading your save",
	unknown_item = "That item doesn't exist",
	unknown_ore = "That ore doesn't exist",
	unknown_layer = "That layer doesn't exist",
	bad_request = "Something went wrong",
	bad_layer = "Something went wrong",
}

-- ==========================================================================
-- Toasts
-- ==========================================================================

local function toast(message: string, color: Color3?)
	toastLabel.Text = message
	toastLabel.TextColor3 = color or Theme.COLOR.text
	toastLabel.Visible = true
	toastUntil = os.clock() + 2.5
end

-- ==========================================================================
-- Snapshot
-- ==========================================================================

local function render()
	hud:update(snapshot)
	inventory:update(snapshot)
	shop:update(snapshot)
end

local function setSnapshot(next: ProfileSnapshot?)
	snapshot = next
	render()
end

--[[
	Runs a RemoteFunction and reports the outcome.

	Every server handler returns { ok, reason, coins }, so refusals surface as a
	toast rather than as a button that appears to do nothing. The server pushes
	a fresh snapshot on success, so there is no optimistic local mutation here
	and the UI can never show a purchase that didn't happen.
]]
local function request(remoteName: string, ...): boolean
	local args = table.pack(...)
	local ok, result = pcall(function()
		return RemoteRegistry.func(remoteName):InvokeServer(table.unpack(args, 1, args.n))
	end)

	if not ok then
		warn(`[UIController] {remoteName} failed: {result}`)
		toast("Connection problem", Theme.COLOR.danger)
		return false
	end

	if type(result) ~= "table" then
		return false
	end

	if not result.ok then
		local reason = result.reason
		toast(REASON_TEXT[reason] or tostring(reason), Theme.COLOR.danger)
		return false
	end

	return true
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function UIController.Init()
	screen = Instance.new("ScreenGui")
	screen.Name = "MineForBrainrots"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	trove:Add(screen)

	-- One UIScale for the whole tree, driven by viewport size so tap targets
	-- stay usable on a phone.
	local scale = Instance.new("UIScale")
	scale.Parent = screen

	local function applyScale()
		local camera = workspace.CurrentCamera
		if camera then
			scale.Scale = Theme.scaleFor(camera.ViewportSize)
		end
	end
	applyScale()

	local camera = workspace.CurrentCamera
	if camera then
		trove:Connect(camera:GetPropertyChangedSignal("ViewportSize"), applyScale)
	end

	hud = HUD.new(screen)
	inventory = InventoryFrame.new(screen)
	shop = ShopFrame.new(screen)

	toastLabel = Theme.label("", {
		Name = "Toast",
		Size = UDim2.new(0, 420, 0, 32),
		Position = UDim2.new(0.5, -210, 0, 12),
		BackgroundColor3 = Theme.COLOR.panelSunken,
		BackgroundTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 10,
	})
	toastLabel.Parent = screen
end

function UIController.Start()
	-- Only one panel at a time; two overlapping modals on a phone is unusable.
	hud:onOpen(function(which)
		local openInventory = which == "inventory" and not inventory.instance.Visible
		local openShop = which == "shop" and not shop.instance.Visible
		inventory:setVisible(openInventory)
		shop:setVisible(openShop)
	end)

	inventory:onSell(function(oreId)
		request("RequestSell", oreId)
	end)

	shop:onPurchase(function(itemId)
		request("RequestPurchase", itemId)
	end)

	shop:onEquip(function(itemId)
		request("RequestEquip", itemId)
	end)

	shop:onUnlockLayer(function(layerIndex)
		request("RequestUnlockLayer", layerIndex)
	end)

	-- Server-pushed state.
	trove:Connect(RemoteRegistry.event("ProfileUpdated").OnClientEvent, function(next: ProfileSnapshot)
		setSnapshot(next)
	end)

	trove:Connect(RemoteRegistry.event("CoinsChanged").OnClientEvent, function(total: number)
		if snapshot then
			snapshot.coins = total
			hud:update(snapshot)
			shop:update(snapshot)
		end
	end)

	trove:Connect(RemoteRegistry.event("NotifyToast").OnClientEvent, function(kind: string, message: string)
		toast(message, if kind == "purchase" or kind == "layer_unlocked" then Theme.COLOR.accent else Theme.COLOR.warn)
	end)

	trove:Connect(RemoteRegistry.event("BackpackFull").OnClientEvent, function()
		toast("Backpack full -- sell your ore", Theme.COLOR.warn)
	end)

	trove:Connect(RemoteRegistry.event("OreCredited").OnClientEvent, function()
		-- Cheap local refresh; the authoritative snapshot follows on sale or
		-- purchase. Mining fires this constantly, so it must not hit a remote.
		if snapshot then
			hud:update(snapshot)
		end
	end)

	-- Depth ticks every frame; the toast timer rides along rather than spawning
	-- a second loop.
	trove:Connect(RunService.RenderStepped, function()
		hud:updateDepth()
		if toastLabel.Visible and os.clock() > toastUntil then
			toastLabel.Visible = false
		end
	end)

	-- First fetch. The profile may still be loading, so retry rather than
	-- rendering an empty HUD forever.
	task.spawn(function()
		for _ = 1, 20 do
			local ok, result = pcall(function()
				return RemoteRegistry.func("GetProfileSnapshot"):InvokeServer()
			end)
			if ok and result then
				setSnapshot(result)
				return
			end
			task.wait(0.5)
		end
		warn("[UIController] profile snapshot never arrived")
	end)
end

function UIController.Stop()
	trove:Clean()
end

return UIController
