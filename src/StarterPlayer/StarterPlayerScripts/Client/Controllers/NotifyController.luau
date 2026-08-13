--!strict
--[[
	NotifyController
	Owns every transient message the player sees.

	Toasts were living inline in UIController, where a single label meant a
	burst of events overwrote each other and only the last survived. This queues
	them instead, so "Bought Iron Pick" followed immediately by "Backpack full"
	shows both.

	UIController requires this module directly to report refusals; the two are
	peers under Controllers/, so no registry lookup is needed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Modules.Format)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Theme = require(script.Parent.Parent.UI.Theme)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

local NotifyController = {}
NotifyController.Name = "NotifyController"

local player = Players.LocalPlayer
local trove = Trove.new()

local MAX_VISIBLE = 4
local SECONDS_PER_TOAST = 2.6

type Toast = { label: TextLabel, until_: number }

local container: Frame
local pool: { TextLabel } = {}
local active: { Toast } = {}
local queue: { { text: string, color: Color3 } } = {}

-- ==========================================================================
-- Toast plumbing
-- ==========================================================================

local function acquireLabel(): TextLabel
	local label = table.remove(pool)
	if label then
		return label
	end

	label = Theme.label("", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Theme.COLOR.panelSunken,
		BackgroundTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = Theme.TEXT_SIZE.small,
	})

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = Theme.METRIC.border
	stroke.Color = Theme.COLOR.border
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label

	return label
end

local function releaseLabel(label: TextLabel)
	label.Parent = nil
	table.insert(pool, label)
end

--[[
	Queues a message. Safe to call from anywhere on the client, including
	before Start has run -- the queue drains once the container exists.
]]
function NotifyController.toast(text: string, color: Color3?)
	table.insert(queue, { text = text, color = color or Theme.COLOR.text })
end

function NotifyController.error(text: string)
	NotifyController.toast(text, Theme.COLOR.danger)
end

function NotifyController.success(text: string)
	NotifyController.toast(text, Theme.COLOR.accent)
end

local function step()
	if not container then
		return
	end

	local now = os.clock()

	-- Retire expired toasts.
	for index = #active, 1, -1 do
		if now >= active[index].until_ then
			releaseLabel(active[index].label)
			table.remove(active, index)
		end
	end

	-- Promote queued messages into free slots.
	while #active < MAX_VISIBLE and #queue > 0 do
		local pending = table.remove(queue, 1)
		local label = acquireLabel()
		label.Text = pending.text
		label.TextColor3 = pending.color
		label.Parent = container
		table.insert(active, { label = label, until_ = now + SECONDS_PER_TOAST })
	end

	-- Re-stack so the oldest sits on top and there are no gaps.
	for index, toast in active do
		toast.label.LayoutOrder = index
	end
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function NotifyController.Init()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("MineForBrainrots", 20)
	if not gui then
		warn("[NotifyController] ScreenGui never appeared; notifications disabled")
		return
	end

	container = Instance.new("Frame")
	container.Name = "Toasts"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromOffset(420, 140)
	container.Position = UDim2.new(0.5, -210, 0, 12)
	container.ZIndex = 30
	container.Parent = gui
	trove:Add(container)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = container
end

function NotifyController.Start()
	trove:Connect(RemoteRegistry.event("NotifyToast").OnClientEvent, function(kind: string, message: string)
		local color = if kind == "purchase" or kind == "layer_unlocked" or kind == "rebirth"
			then Theme.COLOR.accent
			else Theme.COLOR.warn
		NotifyController.toast(message, color)
	end)

	trove:Connect(RemoteRegistry.event("BackpackFull").OnClientEvent, function()
		NotifyController.toast("Backpack full -- sell your ore", Theme.COLOR.warn)
	end)

	trove:Connect(RemoteRegistry.event("PlotAssigned").OnClientEvent, function(index: number)
		NotifyController.success(`Plot {index} is yours`)
	end)

	trove:Connect(RemoteRegistry.event("OfflineEarnings").OnClientEvent, function(payload)
		if not payload or (payload.coins or 0) <= 0 then
			return
		end
		local suffix = if payload.wasCapped then " (capped)" else ""
		-- Concatenated: `$$` in an interpolated string is two literal dollars.
		NotifyController.toast(
			"While you were away: $"
				.. Format.abbreviate(payload.coins)
				.. " over "
				.. Format.duration(payload.seconds)
				.. suffix,
			Theme.COLOR.coins
		)
	end)

	trove:Connect(RunService.RenderStepped, step)
end

function NotifyController.Stop()
	trove:Clean()
	table.clear(active)
	table.clear(queue)
	table.clear(pool)
end

return NotifyController
