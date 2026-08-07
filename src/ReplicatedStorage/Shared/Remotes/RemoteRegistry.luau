--!strict
--[[
	RemoteRegistry
	Single declaration of every remote in the game. The server creates them at
	boot; the client waits for them. Nothing anywhere else calls Instance.new on
	a RemoteEvent, so there is exactly one list to audit when checking the
	"every remote validated server-side" acceptance item.

	`direction` documents intent and is asserted at call sites:
	  ClientToServer -- client asks, server validates and decides
	  ServerToClient -- server informs, client renders
	  Bidirectional  -- RemoteFunction request/response

	AntiCheatService rate-limits every entry here by name, so adding a remote
	automatically inherits throttling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteRegistry = {}

local FOLDER_NAME = "Net"
local WAIT_TIMEOUT = 20

export type RemoteKind = "Event" | "Function"
export type Direction = "ClientToServer" | "ServerToClient" | "Bidirectional"

export type RemoteSpec = {
	name: string,
	kind: RemoteKind,
	direction: Direction,
}

RemoteRegistry.SPECS = table.freeze({
	-- ---- Mining ------------------------------------------------------------
	{ name = "RequestSwing", kind = "Event", direction = "ClientToServer" },
	{ name = "BlockDamaged", kind = "Event", direction = "ServerToClient" },
	{ name = "BlockBroken", kind = "Event", direction = "ServerToClient" },
	{ name = "BackpackFull", kind = "Event", direction = "ServerToClient" },
	{ name = "OreCredited", kind = "Event", direction = "ServerToClient" },

	-- ---- Economy -----------------------------------------------------------
	{ name = "ProfileUpdated", kind = "Event", direction = "ServerToClient" },
	{ name = "CoinsChanged", kind = "Event", direction = "ServerToClient" },
	{ name = "GetProfileSnapshot", kind = "Function", direction = "Bidirectional" },
	{ name = "RequestSell", kind = "Function", direction = "Bidirectional" },
	{ name = "RequestPurchase", kind = "Function", direction = "Bidirectional" },
	{ name = "RequestEquip", kind = "Function", direction = "Bidirectional" },
	{ name = "RequestUnlockLayer", kind = "Function", direction = "Bidirectional" },
	{ name = "RequestRebirth", kind = "Function", direction = "Bidirectional" },
	{ name = "LayerUnlocked", kind = "Event", direction = "ServerToClient" },

	-- ---- Conversion --------------------------------------------------------
	{ name = "RequestConvert", kind = "Function", direction = "Bidirectional" },
	{ name = "ConversionResult", kind = "Event", direction = "ServerToClient" },

	-- ---- Plots and income --------------------------------------------------
	{ name = "PlotAssigned", kind = "Event", direction = "ServerToClient" },
	{ name = "RequestPlace", kind = "Function", direction = "Bidirectional" },
	{ name = "RequestUnplace", kind = "Function", direction = "Bidirectional" },
	{ name = "RequestSellBrainrot", kind = "Function", direction = "Bidirectional" },
	{ name = "PlacementChanged", kind = "Event", direction = "ServerToClient" },
	{ name = "IncomeTick", kind = "Event", direction = "ServerToClient" },
	{ name = "OfflineEarnings", kind = "Event", direction = "ServerToClient" },

	-- ---- Presentation ------------------------------------------------------
	{ name = "NotifyToast", kind = "Event", direction = "ServerToClient" },
} :: { RemoteSpec })

local specByName: { [string]: RemoteSpec } = {}
for _, spec in RemoteRegistry.SPECS do
	assert(specByName[spec.name] == nil, `RemoteRegistry: duplicate remote "{spec.name}"`)
	specByName[spec.name] = spec
end

local folder: Folder? = nil

local function className(kind: RemoteKind): string
	return if kind == "Event" then "RemoteEvent" else "RemoteFunction"
end

--[[
	Server-only. Creates the Net folder and every remote in it, then parents the
	folder to ReplicatedStorage in one step so clients never observe a partially
	populated registry.
]]
function RemoteRegistry.build(): Folder
	assert(RunService:IsServer(), "RemoteRegistry.build is server-only")

	if folder then
		return folder
	end

	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end

	local built = Instance.new("Folder")
	built.Name = FOLDER_NAME

	for _, spec in RemoteRegistry.SPECS do
		local remote = Instance.new(className(spec.kind))
		remote.Name = spec.name
		remote.Parent = built
	end

	built.Parent = ReplicatedStorage
	folder = built
	return built
end

local function getFolder(): Folder
	if folder then
		return folder
	end

	if RunService:IsServer() then
		return RemoteRegistry.build()
	end

	local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	assert(found and found:IsA("Folder"), `RemoteRegistry: "{FOLDER_NAME}" never replicated`)
	folder = found :: Folder
	return folder :: Folder
end

-- Fetch by name. Errors on an unregistered name rather than returning nil, so a
-- typo fails at the call site instead of silently no-oping.
function RemoteRegistry.get(name: string): RemoteEvent | RemoteFunction
	local spec = specByName[name]
	assert(spec, `RemoteRegistry: no remote named "{name}"`)

	local remote = getFolder():WaitForChild(name, WAIT_TIMEOUT)
	assert(remote, `RemoteRegistry: "{name}" never replicated`)
	return remote :: any
end

function RemoteRegistry.event(name: string): RemoteEvent
	local spec = specByName[name]
	assert(spec and spec.kind == "Event", `RemoteRegistry: "{name}" is not a RemoteEvent`)
	return RemoteRegistry.get(name) :: RemoteEvent
end

function RemoteRegistry.func(name: string): RemoteFunction
	local spec = specByName[name]
	assert(spec and spec.kind == "Function", `RemoteRegistry: "{name}" is not a RemoteFunction`)
	return RemoteRegistry.get(name) :: RemoteFunction
end

function RemoteRegistry.getSpec(name: string): RemoteSpec?
	return specByName[name]
end

return RemoteRegistry
