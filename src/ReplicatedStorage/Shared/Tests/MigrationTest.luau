--!strict
--[[
	MigrationTest
	Profiles saved under an older schema, loaded by this one.

	The 1 -> 2 step is the one with consequences: it lowers the podium cap, so
	it has to take slots away from a profile that already owns them without
	taking the coins that bought them or the brainrots standing on them.

	Runs wherever DataService is reachable, on the same reasoning as
	SessionLockTest: its `_internal` table is the only way at `migrate`, and
	the module lives under ServerScriptService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

return function(t)
	local services = ServerScriptService:FindFirstChild("Server")
	local module = if services then services:FindFirstChild("Services") else nil
	module = if module then module:FindFirstChild("DataService") else nil

	if not module then
		t.ok(true, "migration suite skipped (DataService not reachable from here)")
		return
	end

	local internal = (require(module :: ModuleScript) :: any)._internal
	local migrate = internal.migrate

	t.equal(internal.SCHEMA_VERSION, 2, "this suite is written against schema 2")
	t.equal(GameConfig.MaxPlotSlots, 10, "this suite is written against a cap of 10 podiums")

	-- A schema-1 save that had bought every podium the old cap allowed and
	-- filled some of them, on both sides of the new cap.
	local function oversized(): any
		return {
			schemaVersion = 1,
			coins = 1000,
			gems = 0,
			rebirths = 2,
			ownedTools = {},
			equippedPickaxe = "pickaxe_1",
			equippedBackpack = "backpack_1",
			oreCounts = {},
			brainrotsOwned = {
				{ uid = "a", brainrotId = "bobrito_bandito", mutation = "Normal", acquiredUnix = 0 },
				{ uid = "b", brainrotId = "trippi_troppi", mutation = "Golden", acquiredUnix = 0 },
				{ uid = "c", brainrotId = "frigo_camelo", mutation = "Normal", acquiredUnix = 0 },
			},
			placedBrainrots = { { uid = "a", slot = 3 }, { uid = "b", slot = 10 }, { uid = "c", slot = 17 } },
			unlockedLayers = { 1, 2 },
			indexDiscovered = {},
			pityCounter = 4,
			plotSlots = 24,
			lastOnlineUnix = 0,
			playtime = 0,
		}
	end

	local moved = migrate(oversized())

	t.equal(moved.schemaVersion, 2, "a schema-1 profile comes out at schema 2")
	t.equal(moved.plotSlots, 10, "slots above the cap are taken away")

	-- The fourteen slots from 11 to 24, at the prices BALANCE.md listed for
	-- them under schema 1.
	local paid = 69000 + 110000 + 170000 + 260000 + 400000 + 620000 + 960000
		+ 1500000 + 2300000 + 3600000 + 5500000 + 8600000 + 13000000 + 21000000
	t.equal(moved.coins, 1000 + paid, "and every one of them is refunded at what it cost")

	t.equal(#moved.placedBrainrots, 2, "a brainrot on a podium that no longer exists is unplaced")
	local slots = {}
	for _, placed in moved.placedBrainrots do
		slots[placed.slot] = placed.uid
	end
	t.ok(slots[3] == "a" and slots[10] == "b", "placements at or under the cap are untouched")
	t.equal(#moved.brainrotsOwned, 3, "nothing owned is lost, only unplaced")

	t.equal(moved.dailyStreak, 0, "the daily streak starts at zero")
	t.equal(moved.dailyLastClaimDay, 0, "and the profile reads as never having claimed")
	t.equal(moved.rebirths, 2, "unrelated fields survive the migration")
	t.equal(moved.pityCounter, 4, "including ones the client never sees")

	-- The ordinary case: a profile already inside the cap pays and loses nothing.
	local small = oversized()
	small.plotSlots = 6
	small.placedBrainrots = { { uid = "a", slot = 6 } }
	local kept = migrate(small)
	t.equal(kept.plotSlots, 6, "a profile under the cap keeps its slot count")
	t.equal(kept.coins, 1000, "and is refunded nothing")
	t.equal(#kept.placedBrainrots, 1, "and keeps everything it had placed")

	-- A save with the fields missing altogether still has to come out whole.
	local sparse = migrate({ schemaVersion = 1 } :: any)
	t.equal(sparse.schemaVersion, 2, "a sparse profile still migrates")
	t.equal(sparse.plotSlots, GameConfig.StartingPlotSlots, "and is filled in from the defaults")

	-- Loading twice must not refund twice.
	local again = migrate(moved)
	t.equal(again.coins, moved.coins, "migrating an already-migrated profile changes nothing")
end
