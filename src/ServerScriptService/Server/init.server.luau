--!strict
--[[
	Server bootstrap
	Owns boot order and the service registry. Every server system is a module
	under Services/ exposing an optional Init() and Start().

	Two phases, deliberately:
	  Init  -- build state, register signals. No service may call another
	           service's methods here, because ordering within a phase is only
	           guaranteed by BOOT_ORDER, not by readiness.
	  Start -- connect events, spawn loops, touch other services. By now every
	           service has completed Init.

	Add a service by writing the module and adding its name to BOOT_ORDER. A
	name in the list with no matching module is a hard error, so a typo can't
	silently drop a system.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)

-- Remotes exist before any service starts, so nothing races the client's
-- WaitForChild on first join.
RemoteRegistry.build()

export type Service = {
	Name: string?,
	Init: (() -> ())?,
	Start: (() -> ())?,
	[any]: any,
}

--[[
	Boot order. Dependencies point upward: a service may depend on anything
	above it during Start, and on nothing during Init.

	AntiCheatService boots early because every other service's remote handlers
	call into it.
]]
local BOOT_ORDER = {
	"DataService",
	"AntiCheatService",
	"MineService",
	"InventoryService",
	"MiningService",
	"EconomyService",
	"ShopService",
	"ConversionService",
	"PlotService",
	"IncomeService",
	"LeaderboardService",
}

local servicesFolder = script:WaitForChild("Services")

local registry: { [string]: Service } = {}
local ordered: { Service } = {}

-- ==========================================================================
-- Load
-- ==========================================================================

for _, name in BOOT_ORDER do
	local module = servicesFolder:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `[Boot] BOOT_ORDER lists "{name}" but Services/{name} is not a ModuleScript`)

	local service = require(module) :: Service
	assert(type(service) == "table", `[Boot] Services/{name} must return a table`)

	registry[name] = service
	table.insert(ordered, service)
end

-- Catch modules that exist but were never registered -- almost always a
-- forgotten BOOT_ORDER entry rather than an intentional omission.
for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") and not registry[child.Name] then
		warn(`[Boot] Services/{child.Name} exists but is not in BOOT_ORDER; it will not run`)
	end
end

-- ==========================================================================
-- Init
-- ==========================================================================

for index, service in ordered do
	local name = BOOT_ORDER[index]
	if service.Init then
		local ok, err = pcall(service.Init)
		if not ok then
			error(`[Boot] {name}.Init failed: {err}`, 0)
		end
	end
end

-- ==========================================================================
-- Start
-- ==========================================================================

for index, service in ordered do
	local name = BOOT_ORDER[index]
	if service.Start then
		local ok, err = pcall(service.Start)
		if not ok then
			error(`[Boot] {name}.Start failed: {err}`, 0)
		end
	end
end

-- Published so later services can resolve each other by name without threading
-- references through every constructor.
local ServerRegistry = {}

function ServerRegistry.get(name: string): Service
	local service = registry[name]
	assert(service, `[Boot] no service named "{name}"`)
	return service
end

function ServerRegistry.tryGet(name: string): Service?
	return registry[name]
end

_G.ServerRegistry = ServerRegistry

print(`[Boot] Mine For Brainrots server ready ({#ordered} service{if #ordered == 1 then "" else "s"})`)
