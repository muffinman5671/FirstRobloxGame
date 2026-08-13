--!strict
--[[
	ConversionService
	Turns ore into brainrots.

	One roll costs GameConfig.ConversionOreCost units of a single ore type. The
	fed ore biases the outcome table but never restricts it, so a Common ore can
	still produce a Mythic -- rarely.

	The pity counter is the floor: after GameConfig.PityThreshold rolls without
	an Epic-or-better, the next roll is guaranteed to be one. It lives on the
	profile and is never sent to the client, because a client that could see it
	would time its rolls.

	Mutation is rolled separately from the character. This is the decision
	recorded in DESIGN.md §4: convertsTo holds plain ids, and Golden / Diamond /
	Glitched are tiers applied on top, not separate characters.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local Conversion = require(ReplicatedStorage.Shared.Modules.Conversion)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local OreConfig = require(ReplicatedStorage.Shared.Config.OreConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)

type ConversionResult = SharedTypes.ConversionResult

local ConversionService = {}
ConversionService.Name = "ConversionService"

local AntiCheatService
local DataService
local InventoryService

-- (player, brainrotId, mutation, isNewDiscovery)
ConversionService.Converted = Signal.new()

-- Seeded per server, not per call: constructing a Random per roll is both
-- wasteful and a classic source of correlated results.
local rng = Random.new()

-- ==========================================================================
-- Rolling
-- ==========================================================================

local function rollMutation(): string
	local picked = Rarity.rollMap(Conversion.mutationTable(), rng)
	return picked or "Normal"
end

--[[
	Performs one conversion. Returns a ConversionResult describing what
	happened, which the caller both returns to the requesting client and
	broadcasts for the reveal animation.
]]
function ConversionService.convert(player: Player, oreId: any): ConversionResult
	if type(oreId) ~= "string" then
		return { ok = false, reason = "bad_request" }
	end

	local profile = DataService.get(player)
	if not profile then
		return { ok = false, reason = "profile_not_loaded" }
	end

	local ore = OreConfig.get(oreId)
	if not ore then
		return { ok = false, reason = "unknown_ore" }
	end

	local cost = Conversion.cost()
	local held = profile.oreCounts[oreId] or 0
	if held < cost then
		return { ok = false, reason = "not_enough_ore" }
	end

	-- Take payment first. If anything below fails the player has still spent
	-- the ore, so nothing below is allowed to fail: the roll is pure and the
	-- grant is a table write.
	local taken = InventoryService.remove(player, oreId, cost)
	if taken < cost then
		return { ok = false, reason = "not_enough_ore" }
	end

	local entries = Conversion.outcomeTable(oreId)
	local picked, nextPity, pityFired = Rarity.rollWithPity(entries, profile.pityCounter, {
		threshold = GameConfig.PityThreshold,
		minimumRarity = GameConfig.PityMinimumRarity :: any,
	}, rng)

	if not picked then
		-- Cannot happen with a populated config, but refunding beats silently
		-- eating the ore.
		InventoryService.tryAdd(player, oreId, cost)
		return { ok = false, reason = "empty_outcome_table" }
	end

	local mutation = rollMutation()
	local def = BrainrotConfig.get(picked.id)
	local isNew = profile.indexDiscovered[picked.id] ~= true

	DataService.update(player, function(p)
		table.insert(p.brainrotsOwned, {
			uid = HttpService:GenerateGUID(false),
			brainrotId = picked.id,
			mutation = mutation :: any,
			acquiredUnix = os.time(),
		})
		p.indexDiscovered[picked.id] = true
		p.pityCounter = nextPity
	end)

	local result: ConversionResult = {
		ok = true,
		brainrotId = picked.id,
		mutation = mutation :: any,
		rarity = picked.rarity,
		pityFired = pityFired,
		isNewDiscovery = isNew,
	}

	-- Drives the suspense-then-reveal animation, whose length scales with
	-- rarity via Rarity.REVEAL_SECONDS.
	RemoteRegistry.event("ConversionResult"):FireClient(player, result)
	ConversionService.Converted:Fire(player, picked.id, mutation, isNew)

	if def and Rarity.atLeast(picked.rarity, "Legendary") then
		DataService.saveNow(player)
	end
	DataService.pushSnapshot(player)

	return result
end

-- Odds for the Convert screen. Server-computed so the UI can't be tricked into
-- displaying something other than what will actually be rolled.
function ConversionService.oddsFor(oreId: string?)
	return {
		rarity = Conversion.rarityOdds(oreId),
		mutation = Conversion.mutationOdds(),
		cost = Conversion.cost(),
	}
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function ConversionService.Init()
	AntiCheatService = require(script.Parent.AntiCheatService)
	DataService = require(script.Parent.DataService)
	InventoryService = require(script.Parent.InventoryService)
end

function ConversionService.Start()
	RemoteRegistry.func("RequestConvert").OnServerInvoke = function(player, oreId)
		if not AntiCheatService.guard(player, "RequestConvert") then
			return { ok = false, reason = "rate_limited" }
		end
		if not AntiCheatService.isId(oreId) then
			AntiCheatService.report(player, "bad_convert_payload", typeof(oreId), "severe")
			return { ok = false, reason = "bad_request" }
		end
		return ConversionService.convert(player, oreId)
	end
end

-- Exposed for the Tests/ suite.
ConversionService._internal = {
	rollMutation = rollMutation,
	setRandom = function(replacement: Random)
		rng = replacement
	end,
}

return ConversionService
