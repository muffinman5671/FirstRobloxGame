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

local ConvertFrame = require(script.Parent.Parent.UI.ConvertFrame)
local HUD = require(script.Parent.Parent.UI.HUD)
local IndexFrame = require(script.Parent.Parent.UI.IndexFrame)
local InventoryFrame = require(script.Parent.Parent.UI.InventoryFrame)
local NotifyController = require(script.Parent.NotifyController)
local RebirthFrame = require(script.Parent.Parent.UI.RebirthFrame)
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
local hud, inventory, shop, convert, index, rebirth

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
	not_enough_ore = "Not enough ore for a roll",
	no_plot = "No plot assigned yet",
	slot_not_unlocked = "Buy that podium slot first",
	slot_occupied = "That podium is taken",
	slot_empty = "Nothing on that podium",
	already_placed = "Already on a podium",
	empty_outcome_table = "Something went wrong",
	rate_limited = "Slow down",
	profile_not_loaded = "Still loading your save",
	unknown_item = "That item doesn't exist",
	unknown_ore = "That ore doesn't exist",
	unknown_layer = "That layer doesn't exist",
	bad_request = "Something went wrong",
	bad_layer = "Something went wrong",
}

-- Notifications belong to NotifyController; this is just a shorthand.
local toast = NotifyController.toast

-- ==========================================================================
-- Snapshot
-- ==========================================================================

local function render()
	hud:update(snapshot)
	inventory:update(snapshot)
	shop:update(snapshot)
	convert:update(snapshot)
	index:update(snapshot)
	rebirth:update(snapshot)
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
	convert = ConvertFrame.new(screen)
	index = IndexFrame.new(screen)
	rebirth = RebirthFrame.new(screen)
end

function UIController.Start()
	-- Only one panel at a time; two overlapping modals on a phone is unusable.
	-- One panel at a time; clicking the open one closes it. Two overlapping
	-- modals on a phone is unusable.
	local panels = {
		inventory = inventory,
		shop = shop,
		convert = convert,
		index = index,
		rebirth = rebirth,
	}

	hud:onOpen(function(which)
		local target = panels[which]
		local opening = target ~= nil and not target.instance.Visible
		for name, panel in panels do
			panel:setVisible(opening and name == which)
		end
	end)

	rebirth:onRebirth(function()
		request("RequestRebirth")
	end)

	inventory:onSell(function(oreId)
		request("RequestSell", oreId)
	end)

	convert:onConvert(function(oreId)
		-- The reveal is driven by the ConversionResult event rather than this
		-- return value, so the animation fires the same way however the roll
		-- was triggered.
		request("RequestConvert", oreId)
	end)

	convert:onPlace(function(uid, slot)
		request("RequestPlace", uid, slot)
	end)

	convert:onUnplace(function(slot)
		request("RequestUnplace", slot)
	end)

	convert:onSellBrainrot(function(uid)
		request("RequestSellBrainrot", uid)
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

	-- NotifyToast, BackpackFull, PlotAssigned, and OfflineEarnings are handled
	-- by NotifyController; this controller only listens to what changes state
	-- it owns.
	trove:Connect(RemoteRegistry.event("ConversionResult").OnClientEvent, function(result)
		convert:showReveal(result)
	end)

	trove:Connect(RemoteRegistry.event("PlacementChanged").OnClientEvent, function()
		-- The server pushes a snapshot alongside this; the toast is the
		-- immediate acknowledgement so a placement never feels ignored.
		toast("Plot updated", Theme.COLOR.accent)
	end)

	trove:Connect(RemoteRegistry.event("IncomeTick").OnClientEvent, function(_, rate: number)
		if snapshot then
			snapshot.incomePerSecond = rate
			hud:update(snapshot)
		end
	end)

	trove:Connect(RemoteRegistry.event("OreCredited").OnClientEvent, function()
		-- Cheap local refresh; the authoritative snapshot follows on sale or
		-- purchase. Mining fires this constantly, so it must not hit a remote.
		if snapshot then
			hud:update(snapshot)
		end
	end)

	trove:Connect(RunService.RenderStepped, function()
		hud:updateDepth()
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
