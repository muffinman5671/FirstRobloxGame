--!strict
--[[
	AtmosphereController
	Applies each layer's fog and ambient light from the player's depth.

	Every LayerDef has carried fogColor, fogEnd and ambientColor since the
	layers were authored, and nothing read them -- so all six bands lit exactly
	alike and the edge of the world was plainly visible from the hub. This is
	the missing half.

	Client-side, and deliberately so. Two players can stand in different layers
	at the same moment, and Lighting is per-client state; driving it from the
	server would mean the deepest player decided what everyone else saw.

	Nothing here is authoritative. It reads the local character's position and
	writes to Lighting -- a client that lies to itself about the fog gains
	nothing, so there is no validation to do.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local LayerConfig = require(ReplicatedStorage.Shared.Config.LayerConfig)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

local AtmosphereController = {}
AtmosphereController.Name = "AtmosphereController"

local player = Players.LocalPlayer
local trove = Trove.new()

type Atmosphere = {
	fogColor: Color3,
	fogEnd: number,
	ambient: Color3,
}

-- Above ground is not any layer's business: layer 1 begins at the surface and
-- runs 70 studs down, and open-field fog is not shaft fog.
local SURFACE: Atmosphere = {
	fogColor = GameConfig.SurfaceFogColor,
	fogEnd = GameConfig.SurfaceFogEnd,
	ambient = GameConfig.SurfaceAmbient,
}

local current: Atmosphere? = nil

local function targetFor(depth: number): Atmosphere
	if depth <= 0 then
		return SURFACE
	end

	local layer = LayerConfig.forDepth(depth)
	return {
		fogColor = layer.fogColor,
		fogEnd = layer.fogEnd,
		ambient = layer.ambientColor,
	}
end

local function apply(state: Atmosphere)
	Lighting.FogColor = state.fogColor
	Lighting.FogEnd = state.fogEnd
	Lighting.FogStart = state.fogEnd * GameConfig.FogStartFraction
	Lighting.Ambient = state.ambient
end

--[[
	Exponential smoothing rather than a lerp on a fixed step, so the blend takes
	the same wall-clock time at 30fps as at 240. FogBlendSeconds is the time
	constant: after that long, roughly 63% of the way there.
]]
local function blend(from: Atmosphere, to: Atmosphere, dt: number): Atmosphere
	local alpha = 1 - math.exp(-dt / math.max(GameConfig.FogBlendSeconds, 1e-3))
	return {
		fogColor = from.fogColor:Lerp(to.fogColor, alpha),
		fogEnd = from.fogEnd + (to.fogEnd - from.fogEnd) * alpha,
		ambient = from.ambient:Lerp(to.ambient, alpha),
	}
end

local function depthOfCharacter(): number?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	return GameConfig.SurfaceY - root.Position.Y
end

function AtmosphereController.Init()
	-- Nothing to build. Lighting is set on the first frame that finds a
	-- character, and snapped rather than blended so the player never watches
	-- the world fade in from whatever the place file happened to specify.
end

function AtmosphereController.Start()
	trove:Connect(RunService.RenderStepped, function(dt: number)
		local depth = depthOfCharacter()
		if not depth then
			return
		end

		local target = targetFor(depth)

		if not current then
			current = target
			apply(target)
			return
		end

		current = blend(current :: Atmosphere, target, dt)
		apply(current :: Atmosphere)
	end)

	-- A respawn puts the player back on the surface. Snapping on the next frame
	-- beats blending 700 studs of fog back up while they stand in the hub.
	trove:Connect(player.CharacterAdded, function()
		current = nil
	end)
end

function AtmosphereController.Stop()
	trove:Clean()
	current = nil
end

return AtmosphereController
