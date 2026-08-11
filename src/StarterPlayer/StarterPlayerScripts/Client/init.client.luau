--!strict
--[[
	Client bootstrap
	Mirrors the server's two-phase boot. Controllers live under Controllers/ and
	expose an optional Init() and Start().

	Remaining phases append here in this order:
	  UIController, EffectsController, NotifyController
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)

export type Controller = {
	Name: string?,
	Init: (() -> ())?,
	Start: (() -> ())?,
	[any]: any,
}

local CONTROLLER_ORDER: { string } = {
	"MiningController",
	"UIController",
}

-- Blocks until the server's remote folder has replicated, so no controller has
-- to defend against a missing remote.
RemoteRegistry.get("GetProfileSnapshot")

local controllersFolder = script:FindFirstChild("Controllers")

local registry: { [string]: Controller } = {}
local ordered: { Controller } = {}

if controllersFolder then
	for _, name in CONTROLLER_ORDER do
		local module = controllersFolder:FindFirstChild(name)
		assert(
			module and module:IsA("ModuleScript"),
			`[Boot] CONTROLLER_ORDER lists "{name}" but Controllers/{name} is not a ModuleScript`
		)

		local controller = require(module) :: Controller
		assert(type(controller) == "table", `[Boot] Controllers/{name} must return a table`)

		registry[name] = controller
		table.insert(ordered, controller)
	end

	for _, child in controllersFolder:GetChildren() do
		if child:IsA("ModuleScript") and not registry[child.Name] then
			warn(`[Boot] Controllers/{child.Name} exists but is not in CONTROLLER_ORDER; it will not run`)
		end
	end
elseif #CONTROLLER_ORDER > 0 then
	error("[Boot] CONTROLLER_ORDER is populated but Controllers/ does not exist", 0)
end

for index, controller in ordered do
	local name = CONTROLLER_ORDER[index]
	if controller.Init then
		local ok, err = pcall(controller.Init)
		if not ok then
			error(`[Boot] {name}.Init failed: {err}`, 0)
		end
	end
end

for index, controller in ordered do
	local name = CONTROLLER_ORDER[index]
	if controller.Start then
		local ok, err = pcall(controller.Start)
		if not ok then
			error(`[Boot] {name}.Start failed: {err}`, 0)
		end
	end
end

local ClientRegistry = {}

function ClientRegistry.get(name: string): Controller
	local controller = registry[name]
	assert(controller, `[Boot] no controller named "{name}"`)
	return controller
end

function ClientRegistry.tryGet(name: string): Controller?
	return registry[name]
end

_G.ClientRegistry = ClientRegistry
