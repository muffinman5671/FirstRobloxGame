--!strict
--[[
	IncomeService
	Passive income from placed brainrots, and the offline earnings a player
	comes back to.

	Rate is recomputed from the profile every tick rather than cached. A cached
	rate has to be invalidated on placement, sale, rebirth, and slot purchase,
	and the first one anybody forgets silently pays the wrong amount forever.
	Twenty-four entries per player per second is nothing.

	Offline earnings are deliberately paid at a fraction of the online rate and
	capped, so leaving the game running is always better than not -- but coming
	back after a night still feels like a reward.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Shared.Config.BrainrotConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)
local Trove = require(ReplicatedStorage.Shared.Modules.Trove)

type Profile = SharedTypes.Profile

local IncomeService = {}
IncomeService.Name = "IncomeService"

local DataService
local EconomyService

local trove = Trove.new()

-- Fractional coins carry between ticks, so a 2.5/sec brainrot pays 5 every two
-- seconds instead of being floored to 2 forever.
local carry: { [Player]: number } = {}

-- ==========================================================================
-- Rate
-- ==========================================================================

--[[
	Coins per second from everything currently on a podium.

	Only counts placements in slots the player has actually unlocked. Without
	that check, refunding or losing slots would leave a brainrot in slot 20
	still paying out while invisible on the plot.
]]
function IncomeService.rateFor(profile: Profile): number
	if #profile.placedBrainrots == 0 then
		return 0
	end

	local owned: { [string]: SharedTypes.OwnedBrainrot } = {}
	for _, entry in profile.brainrotsOwned do
		owned[entry.uid] = entry
	end

	local total = 0
	for _, placed in profile.placedBrainrots do
		if placed.slot >= 1 and placed.slot <= profile.plotSlots then
			local entry = owned[placed.uid]
			if entry then
				total += BrainrotConfig.incomeFor(entry.brainrotId, entry.mutation)
			end
		end
	end

	return total * ToolConfig.rebirthMultiplier(profile.rebirths)
end

function IncomeService.rateForPlayer(player: Player): number
	local profile = DataService.get(player)
	return if profile then IncomeService.rateFor(profile) else 0
end

-- ==========================================================================
-- Offline earnings
-- ==========================================================================

--[[
	Pays for time away, then tells the client so it can show the
	"While you were away" popup.

	Silent when there's nothing to pay: a first-time player, or one who was
	away with an empty plot, shouldn't get a popup announcing zero.
]]
local function payOffline(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local last = profile.lastOnlineUnix
	if last <= 0 then
		return -- first session; there is no "away" to pay for
	end

	local away = os.time() - last
	if away <= 0 then
		return
	end

	local rate = IncomeService.rateFor(profile)
	if rate <= 0 then
		return
	end

	local capped = math.min(away, GameConfig.OfflineEarningsCapSeconds)
	local payout = math.floor(rate * capped * GameConfig.OfflineEarningsRate)
	if payout <= 0 then
		return
	end

	EconomyService.award(player, payout)
	RemoteRegistry.event("OfflineEarnings"):FireClient(player, {
		coins = payout,
		seconds = capped,
		wasCapped = away > GameConfig.OfflineEarningsCapSeconds,
	})
end

IncomeService.payOffline = payOffline

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

function IncomeService.Init()
	DataService = require(script.Parent.DataService)
	EconomyService = require(script.Parent.EconomyService)

	-- Lets DataService put a live $/sec into the client snapshot without
	-- knowing how income is computed.
	DataService.setIncomeProvider(function(player: Player)
		return IncomeService.rateForPlayer(player)
	end)
end

function IncomeService.Start()
	DataService.ProfileLoaded:Connect(function(player: Player)
		-- Placements have to be loaded before the rate means anything, which
		-- they are by the time ProfileLoaded fires.
		payOffline(player)
	end)

	DataService.ProfileReleased:Connect(function(player: Player)
		carry[player] = nil
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		carry[player] = nil
	end)

	trove:Add(task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)

			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					local rate = IncomeService.rateFor(profile)
					if rate > 0 then
						local pending = (carry[player] or 0) + rate * GameConfig.IncomeTickSeconds
						local whole = math.floor(pending)
						carry[player] = pending - whole

						if whole > 0 then
							EconomyService.award(player, whole)
							RemoteRegistry.event("IncomeTick"):FireClient(player, whole, rate)
						end
					end
				end
			end
		end
	end))
end

function IncomeService.Stop()
	trove:Clean()
	table.clear(carry)
end

return IncomeService
