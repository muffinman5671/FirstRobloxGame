--!strict
--[[
	SessionLockTest
	The session-lock rules, driven with synthetic servers.

	Every other suite in this folder tests a shared module. This one reaches into
	ServerScriptService, because the rules it covers are the ones that decide
	whether two servers can both write a player's profile -- and there is no way
	to reproduce two servers from a single Studio instance. So instead of two
	servers, this drives the pure predicates with two hand-built lock contexts.

	That is not the same as testing real contention. It tests that the protocol
	says the right thing; ContentionProbe (see README) tests that a real
	DataStore agrees.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)

type SessionLock = SharedTypes.SessionLock

return function(t)
	--[[
		The module lives in ServerScriptService, which a client cannot see, so
		this suite has to skip there rather than take the whole run down.

		Reachability is tested directly rather than inferred from
		RunService:IsServer(), which returns false in Edit mode -- the exact
		context the command bar runs in. Asking that question skipped the entire
		suite while still reporting a pass, which is the worst of both.
	]]
	local services = ServerScriptService:FindFirstChild("Server")
	local module = if services then services:FindFirstChild("Services") else nil
	module = if module then module:FindFirstChild("DataService") else nil

	if not module then
		t.ok(true, "session lock suite skipped (DataService not reachable from here)")
		return
	end

	local DataService = require(module :: ModuleScript)
	local internal = DataService._internal
	local claimsLock = internal.claimsLock
	local isLockStaleAt = internal.isLockStaleAt
	local STALE = internal.LOCK_STALE_SECONDS

	local NOW = 1_700_000_000 -- fixed, so these assertions never depend on the clock

	type LockFields = {
		jobId: string,
		placeId: number?,
		heartbeatUnix: number?,
		studio: boolean?,
	}

	local function lock(fields: LockFields): SessionLock
		return {
			jobId = fields.jobId,
			placeId = fields.placeId or 1234,
			heartbeatUnix = fields.heartbeatUnix or NOW,
			studio = fields.studio,
		}
	end

	local liveA = { jobId = "job-a", studio = false, placeId = 1234 }
	local liveB = { jobId = "job-b", studio = false, placeId = 1234 }
	local studio1 = { jobId = "studio_play_1_11111", studio = true, placeId = 1234 }
	local studio2 = { jobId = "studio_play_2_22222", studio = true, placeId = 1234 }

	-- ---------- ownership: the ordinary cases ----------
	t.ok(not claimsLock(nil, liveA), "an absent lock is not owned by anyone")
	t.ok(claimsLock(lock({ jobId = "job-a" }), liveA), "a server owns a lock carrying its own jobId")
	t.ok(not claimsLock(lock({ jobId = "job-a" }), liveB), "a server does not own another server's lock")

	-- ---------- ownership: Studio ----------
	t.ok(
		claimsLock(lock({ jobId = studio1.jobId, studio = true }), studio2),
		"a Studio session claims a lock left by an earlier Studio session on this place"
	)
	t.ok(
		not claimsLock(lock({ jobId = studio1.jobId, studio = true, placeId = 9999 }), studio2),
		"a Studio session does not claim a Studio lock from a different place"
	)

	--[[
		The important one. If this ever passes for a live server, a developer
		testing in Studio can have their session overwritten by a player joining
		the published game -- which is worse than the lockout this whole
		mechanism exists to fix.
	]]
	t.ok(
		not claimsLock(lock({ jobId = studio1.jobId, studio = true }), liveA),
		"a live server never claims a Studio lock"
	)
	t.ok(
		not claimsLock(lock({ jobId = "job-b", studio = nil }), studio1),
		"a Studio session never claims a live server's lock"
	)

	-- A lock written before the `studio` field existed must read as a live
	-- server's, which is the safe direction: it is waited out, not stolen.
	t.ok(
		not claimsLock(lock({ jobId = "job-legacy" }), studio1),
		"a lock predating the studio flag is treated as a live server's"
	)

	-- ---------- staleness ----------
	t.ok(isLockStaleAt(nil, NOW), "an absent lock counts as stale")
	t.ok(not isLockStaleAt(lock({ jobId = "job-a" }), NOW), "a lock heartbeating now is live")
	t.ok(
		not isLockStaleAt(lock({ jobId = "job-a", heartbeatUnix = NOW - (STALE - 1) }), NOW),
		"a lock one second inside the window is still live"
	)
	t.ok(
		isLockStaleAt(lock({ jobId = "job-a", heartbeatUnix = NOW - STALE }), NOW),
		"a lock exactly at the window is stale"
	)
	t.ok(
		isLockStaleAt(lock({ jobId = "job-a", heartbeatUnix = 0 }), NOW),
		"a lock with no heartbeat is stale"
	)

	-- The stale window has to sit well above the autosave interval, or two live
	-- servers would steal each other's locks between heartbeats.
	t.ok(
		STALE >= GameConfig.AutosaveSeconds * 5,
		"the stale window comfortably exceeds the autosave interval",
		`stale {STALE}s vs autosave {GameConfig.AutosaveSeconds}s`
	)

	-- ---------- the acquire decision, as loadProfile makes it ----------
	-- Mirrors tryAcquire's guard: refuse only when the lock is someone else's
	-- *and* still warm.
	local function mayAcquire(existing: SessionLock?, context: any): boolean
		return not (existing ~= nil and not claimsLock(existing, context) and not isLockStaleAt(existing, NOW))
	end

	t.ok(mayAcquire(nil, liveA), "a profile with no lock can be acquired")
	t.ok(mayAcquire(lock({ jobId = "job-a" }), liveA), "a profile already locked by us can be re-acquired")
	t.ok(
		not mayAcquire(lock({ jobId = "job-b" }), liveA),
		"a profile locked by another live server is refused"
	)
	t.ok(
		mayAcquire(lock({ jobId = "job-b", heartbeatUnix = NOW - STALE }), liveA),
		"a profile whose lock went stale is taken over"
	)
	t.ok(
		mayAcquire(lock({ jobId = studio1.jobId, studio = true }), studio2),
		"a fresh Studio session takes over from its own previous session immediately"
	)
	t.ok(
		not mayAcquire(lock({ jobId = "job-b" }), studio2),
		"a Studio session still waits out a live server's lock"
	)

	-- ---------- this server's own context ----------
	local context = internal.lockContext
	t.ok(type(context.jobId) == "string" and context.jobId ~= "", "this server has a non-empty jobId")
	t.equal(context.studio, RunService:IsStudio(), "the studio flag matches the environment")
	t.equal(context.placeId, game.PlaceId, "the lock context carries this place's id")
	t.ok(
		claimsLock(lock({ jobId = context.jobId }), context),
		"this server recognises a lock it wrote itself"
	)
end
