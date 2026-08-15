--!strict
--[[
	ContentionProbe
	Two servers fighting over one profile, against the real DataStore.

	Why this exists
	  A single Studio instance is one server, so genuine two-server contention
	  cannot be reproduced here. What *can* be reproduced is the protocol: the
	  lock rules take the acquiring server's identity as an argument, so this
	  drives DataService's own transforms with two synthetic identities against
	  one live key. Every decision under test is made by production code -- this
	  module supplies the identities and the key, nothing else.

	What it therefore does and does not prove
	  Proves: the transforms agree with the protocol when run against real
	  DataStore semantics, including UpdateAsync's serialization of concurrent
	  writers to one key.
	  Does not prove: cross-server behaviour under real network partitions, or
	  that two Roblox servers see each other's writes as promptly as two threads
	  in one server do. Those still need two real servers.

	Running it -- in Play mode, not Edit
	    print(require(game.ReplicatedStorage.Shared.Tests.ContentionProbe).run())

	  The concurrent section does not work from the Edit-mode command bar. A
	  second simultaneous acquire enters UpdateAsync, runs its transform exactly
	  once, and never returns; it was still parked after 45 seconds. It is not
	  the lock logic and not DataStore contention -- the same race against the
	  raw store, including transforms that cancel, completes in milliseconds, and
	  the request budget was nowhere near exhausted. Whatever it is, it lives in
	  the Edit VM: every assertion here passes in Play.

	Deliberately not part of TestRunner.runAll(): it makes ~20 live DataStore
	calls and takes a few seconds, and a unit suite should do neither.

	It writes only to PROBE_KEY, never to a player's key. It leaves that key
	behind with an unlocked throwaway document, which is harmless -- nothing
	reads it but this probe.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local ContentionProbe = {}

local PROBE_KEY = "probe_contention"

type Report = {
	passed: number,
	failed: number,
	lines: { string },
}

local function check(report: Report, condition: boolean, label: string, detail: string?)
	if condition then
		report.passed += 1
		table.insert(report.lines, "  ok   " .. label)
	else
		report.failed += 1
		table.insert(report.lines, ("  FAIL %s%s"):format(label, if detail then "  -> " .. detail else ""))
	end
end

local function describe(lock: any): string
	if not lock then
		return "none"
	end
	return `{lock.jobId}{if lock.studio then " (studio)" else ""} @ {lock.heartbeatUnix}`
end

function ContentionProbe.run(): string
	--[[
		Reachability rather than RunService:IsServer(), which is false in Edit
		mode -- the context the command bar actually runs in.
	]]
	local services = ServerScriptService:FindFirstChild("Server")
	local module = if services then services:FindFirstChild("Services") else nil
	module = if module then module:FindFirstChild("DataService") else nil

	if not module then
		return "ContentionProbe: DataService is not reachable from here. Run it from the command bar or a server Script."
	end

	local DataService = require(module :: ModuleScript)
	local internal = DataService._internal :: any

	local report: Report = { passed = 0, failed = 0, lines = {} }

	--[[
		A probe that silently ran against the in-memory fallback would pass and
		prove nothing at all -- the fallback has no concurrency and no real
		UpdateAsync. Refuse rather than mislead.
	]]
	if DataService.isUsingMockStore() then
		return "ContentionProbe: refusing to run against the in-memory store.\n"
			.. "Enable Studio Access to API Services (Game Settings > Security) and try again."
	end

	local updateAsync = internal.updateAsync
	local acquireTransform = internal.acquireTransform
	local saveTransform = internal.saveTransform
	local lockFor = internal.lockFor
	local defaultProfile = internal.defaultProfile
	local STALE = internal.LOCK_STALE_SECONDS

	-- Two servers that are not this one, so a stray production lock can never be
	-- mistaken for either.
	local serverA = { jobId = "probe-server-a", studio = false, placeId = game.PlaceId }
	local serverB = { jobId = "probe-server-b", studio = false, placeId = game.PlaceId }

	-- Helpers -------------------------------------------------------------

	-- Reads through UpdateAsync with a transform that returns nil, so the read
	-- goes through the same path as every other call here and writes nothing.
	-- UpdateAsync hands back nil for a cancelled transform, so the value has to
	-- come out through an upvalue rather than the return.
	local function readLock(): any
		local seen: any = nil
		updateAsync(PROBE_KEY, "probe read", function(existing)
			seen = if existing then existing.lock else nil
			return nil
		end)
		return seen
	end

	local function reset()
		updateAsync(PROBE_KEY, "probe reset", function()
			return { data = defaultProfile(), lock = nil }
		end)
	end

	local function acquire(context: any): (boolean, any)
		local outcome = { contended = false, reclaimed = false }
		local ok, doc = updateAsync(PROBE_KEY, "probe acquire", acquireTransform(context, outcome))
		return ok and doc ~= nil, outcome
	end

	local function save(context: any, release: boolean): (boolean, any)
		local outcome = { refused = false }
		local ok, doc =
			updateAsync(PROBE_KEY, "probe save", saveTransform(context, defaultProfile(), release, outcome))
		return ok and doc ~= nil, outcome
	end

	-- Age the stored lock, standing in for a server that stopped heartbeating.
	-- Setup only: nothing here is the logic under test.
	local function ageLock(seconds: number)
		updateAsync(PROBE_KEY, "probe age lock", function(existing)
			if not existing or not existing.lock then
				return nil
			end
			existing.lock.heartbeatUnix -= seconds
			return existing
		end)
	end

	-- Scenarios -----------------------------------------------------------

	reset()
	check(report, readLock() == nil, "the probe key starts unlocked")

	-- 1. Uncontested acquire.
	local okA, outcomeA = acquire(serverA)
	check(report, okA and not outcomeA.contended, "server A acquires a free profile")
	local held = readLock()
	check(report, held ~= nil and held.jobId == serverA.jobId, "the stored lock names server A", describe(held))

	-- 2. B is refused while A's lock is warm. This is the assertion the whole
	--    mechanism exists for: without it, both servers load and one overwrites.
	local okB, outcomeB = acquire(serverB)
	check(report, not okB and outcomeB.contended, "server B is refused while A holds a warm lock")
	held = readLock()
	check(report, held ~= nil and held.jobId == serverA.jobId, "a refused acquire left A's lock untouched", describe(held))

	-- 3. A keeps saving normally while it holds the lock.
	local savedA, saveOutcomeA = save(serverA, false)
	check(report, savedA and not saveOutcomeA.refused, "server A saves while holding its own lock")

	-- 4. A stops heartbeating; B takes over the stale lock.
	ageLock(STALE + 60)
	local okBStale, outcomeBStale = acquire(serverB)
	check(report, okBStale and not outcomeBStale.contended, "server B takes over a stale lock")
	held = readLock()
	check(report, held ~= nil and held.jobId == serverB.jobId, "the stored lock now names server B", describe(held))

	-- 5. A, still live and unaware, must not clobber B.
	local savedAAfter, saveOutcomeAAfter = save(serverA, false)
	check(report, not savedAAfter, "server A's save is not reported as written after losing the lock")
	check(report, saveOutcomeAAfter.refused, "server A's save is refused rather than clobbering B")
	held = readLock()
	check(report, held ~= nil and held.jobId == serverB.jobId, "B's lock survived A's attempted save", describe(held))

	-- 6. B leaves cleanly; the lock is gone in the same write.
	local released = save(serverB, true)
	check(report, released, "server B releases on save")
	check(report, readLock() == nil, "releasing cleared the lock")

	-- 7. Studio reclaim, against live infrastructure. This is the fix for the
	--    stop-and-restart lockout: same place, Studio-marked, different jobId.
	reset()
	local studioOld = { jobId = "probe-studio-old", studio = true, placeId = game.PlaceId }
	local studioNew = { jobId = "probe-studio-new", studio = true, placeId = game.PlaceId }
	local liveServer = { jobId = "probe-live", studio = false, placeId = game.PlaceId }

	acquire(studioOld)
	held = readLock()
	check(report, held ~= nil and held.studio == true, "a Studio session marks its lock", describe(held))

	local okStudio, outcomeStudio = acquire(studioNew)
	check(report, okStudio and not outcomeStudio.contended, "a fresh Studio session reclaims the previous one's lock")
	check(report, outcomeStudio.reclaimed, "the reclaim is reported, not silent")

	-- And the direction that must never reverse.
	local okLive, outcomeLive = acquire(liveServer)
	check(report, not okLive and outcomeLive.contended, "a live server refuses to reclaim a warm Studio lock")

	-- 8. Concurrency. Fire several acquires at once against one key; UpdateAsync
	--    serializes them, so exactly one may come away holding the lock.
	reset()
	local CONTENDERS = 5
	local wins = 0
	local losses = 0
	local finished = 0

	for i = 1, CONTENDERS do
		task.spawn(function()
			local context = { jobId = `probe-racer-{i}`, studio = false, placeId = game.PlaceId }
			local won = acquire(context)
			if won then
				wins += 1
			else
				losses += 1
			end
			finished += 1
		end)
	end

	local deadline = os.clock() + 30
	while finished < CONTENDERS and os.clock() < deadline do
		task.wait(0.1)
	end

	check(report, finished == CONTENDERS, `all {CONTENDERS} concurrent acquires completed`, `finished {finished}`)
	check(report, wins == 1, "exactly one concurrent acquire won the lock", `{wins} won, {losses} refused`)
	check(report, losses == CONTENDERS - 1, "every other concurrent acquire was refused", `{losses} refused`)

	held = readLock()
	check(report, held ~= nil, "a lock is held after the race", describe(held))

	-- Leave the key unlocked so a later run starts clean.
	reset()

	table.insert(report.lines, "")
	table.insert(report.lines, ("%d passed, %d failed"):format(report.passed, report.failed))
	return "ContentionProbe (live DataStore)\n" .. table.concat(report.lines, "\n")
end

return ContentionProbe
