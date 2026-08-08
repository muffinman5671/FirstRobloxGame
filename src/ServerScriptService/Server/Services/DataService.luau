--!strict
--[[
	DataService
	Session-locked profile storage. Every other service reads and writes player
	state through this module -- nothing else touches DataStoreService.

	Session locking
	  The DataStore key holds { data = Profile, lock = SessionLock }. A server
	  may only load a profile if the lock is absent, already its own, or stale
	  (no heartbeat for LOCK_STALE_SECONDS). Autosaves refresh the heartbeat, so
	  a live server holds its lock indefinitely and a crashed one releases it
	  after the stale window. This is what stops two servers from duplicating a
	  player's coins across a rapid rejoin.

	Retry
	  Every DataStore call goes through `attempt`, which retries with
	  exponential backoff and jitter. A load that exhausts its retries kicks the
	  player rather than handing them a blank profile that would overwrite real
	  data on the next save.

	Studio
	  With API access disabled, DataStoreService throws on first use. Rather
	  than spamming errors, the service falls back to an in-memory store so the
	  game still boots clean for iteration. It warns exactly once and never does
	  this on a live server.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteRegistry = require(ReplicatedStorage.Shared.Remotes.RemoteRegistry)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local SharedTypes = require(ReplicatedStorage.Shared.Modules.SharedTypes)
local ToolConfig = require(ReplicatedStorage.Shared.Config.ToolConfig)

type Profile = SharedTypes.Profile
type StoredDocument = SharedTypes.StoredDocument
type SessionLock = SharedTypes.SessionLock

local DataService = {}
DataService.Name = "DataService"

-- Bump when the Profile shape changes, and add a matching MIGRATIONS entry.
local SCHEMA_VERSION = 1

local STORE_NAME = "PlayerProfiles"
local STORE_SCOPE = "v1"
local KEY_PREFIX = "player_"

-- A lock older than this is considered abandoned by a dead server. Must exceed
-- the autosave interval by a comfortable margin or live servers would steal
-- each other's locks between heartbeats.
local LOCK_STALE_SECONDS = 15 * 60

local MAX_ATTEMPTS = 5
local BACKOFF_BASE_SECONDS = 0.5
local BACKOFF_MAX_SECONDS = 8

-- How long a load may spend acquiring a contested lock before giving up.
local LOCK_ACQUIRE_ATTEMPTS = 6
local LOCK_RETRY_SECONDS = 4

local JOB_ID = if game.JobId ~= "" then game.JobId else `studio_{RunService:IsRunning() and "play" or "edit"}_{os.clock()}`

-- ==========================================================================
-- Default profile
-- ==========================================================================

local function defaultProfile(): Profile
	return {
		schemaVersion = SCHEMA_VERSION,
		coins = 0,
		gems = 0,
		rebirths = 0,
		ownedTools = {
			[ToolConfig.STARTER_PICKAXE] = true,
			[ToolConfig.STARTER_BACKPACK] = true,
		},
		equippedPickaxe = ToolConfig.STARTER_PICKAXE,
		equippedBackpack = ToolConfig.STARTER_BACKPACK,
		oreCounts = {},
		brainrotsOwned = {},
		placedBrainrots = {},
		unlockedLayers = { 1 },
		indexDiscovered = {},
		pityCounter = 0,
		plotSlots = GameConfig.StartingPlotSlots,
		lastOnlineUnix = 0,
		playtime = 0,
	}
end

--[[
	Migrations, keyed by the version being migrated *from*. Each returns the
	profile at version key+1. They run in sequence, so a v1 profile loaded
	against a v4 server passes through 1->2, 2->3, 3->4.

	Keep them total: a migration must never assume a field exists.
]]
local MIGRATIONS: { [number]: (Profile) -> Profile } = {
	-- [1] = function(profile)
	--     profile.newField = 0
	--     profile.schemaVersion = 2
	--     return profile
	-- end,
}

-- ==========================================================================
-- Table helpers
-- ==========================================================================

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end

	local out = {}
	for key, item in value :: any do
		out[key] = deepCopy(item)
	end
	return (out :: any) :: T
end

--[[
	Fills in keys the template has and the stored profile lacks, without
	clobbering existing values. This is the safety net for fields added between
	schema bumps, and for a partially written save.
]]
local function reconcile(stored: any, template: any): any
	if type(stored) ~= "table" then
		return deepCopy(template)
	end

	for key, templateValue in template do
		if stored[key] == nil then
			stored[key] = deepCopy(templateValue)
		elseif type(templateValue) == "table" and type(stored[key]) == "table" then
			-- Only recurse into dictionary-shaped defaults. Arrays like
			-- brainrotsOwned are player data and must not inherit template rows.
			if next(templateValue) ~= nil and templateValue[1] == nil then
				reconcile(stored[key], templateValue)
			end
		end
	end

	return stored
end

local function migrate(profile: Profile?): Profile
	if type(profile) ~= "table" then
		return defaultProfile()
	end

	local working = profile :: Profile
	working.schemaVersion = working.schemaVersion or 1

	while working.schemaVersion < SCHEMA_VERSION do
		local step = MIGRATIONS[working.schemaVersion]
		if not step then
			warn(
				`[DataService] no migration from schema {working.schemaVersion}; `
					.. `reconciling against v{SCHEMA_VERSION} defaults instead`
			)
			working.schemaVersion = SCHEMA_VERSION
			break
		end

		local before = working.schemaVersion
		working = step(working)
		assert(working.schemaVersion > before, `[DataService] migration {before} did not advance schemaVersion`)
	end

	return reconcile(working, defaultProfile()) :: Profile
end

-- ==========================================================================
-- Store access (real, or in-memory fallback in Studio)
-- ==========================================================================

local realStore: DataStore? = nil
local mockStore: { [string]: StoredDocument }? = nil
local warnedAboutMock = false

--[[
	Studio blocks DataStore access in two different places depending on how the
	place is set up:
	  unsaved place  -- GetDataStore itself throws
	  saved but unpublished, or API access off -- GetDataStore succeeds and
	    every operation throws instead
	Both mean the same thing, and neither is retryable, so they're detected by
	message and treated as permanent.
]]
local API_ACCESS_HINTS = {
	"StudioAccessToApisNotAllowed",
	"API access is not enabled",
	"Cannot write to DataStore from studio",
	"publish this place",
}

local function isApiAccessError(err: any): boolean
	local text = tostring(err)
	for _, hint in API_ACCESS_HINTS do
		if string.find(text, hint, 1, true) then
			return true
		end
	end
	return false
end

local function useMockStore(reason: string)
	if RunService:IsStudio() then
		if not warnedAboutMock then
			warnedAboutMock = true
			mockStore = {}
			warn(
				`[DataService] DataStores unavailable ({reason}). `
					.. `Falling back to in-memory storage for this Studio session -- progress will not persist. `
					.. `Enable Studio Access to API Services to test real saves.`
			)
		end
		return
	end

	-- On a live server this is not recoverable; surface it loudly.
	error(`[DataService] DataStores unavailable on a live server: {reason}`, 0)
end

local function getStore(): DataStore?
	if realStore then
		return realStore
	end
	if mockStore then
		return nil
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME, STORE_SCOPE)
	end)

	if ok and result then
		realStore = result
		return realStore
	end

	useMockStore(tostring(result))
	return nil
end

local function keyFor(userId: number): string
	return KEY_PREFIX .. tostring(userId)
end

--[[
	Runs `fn` with exponential backoff and jitter. Returns (ok, resultOrError).
	`label` only appears in warnings, to make a retry storm identifiable.
]]
local function attempt<T>(label: string, fn: () -> T): (boolean, any)
	local lastError: any = nil

	for tries = 1, MAX_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end

		lastError = result

		-- Permanent. Retrying can't help and would flood the log five times
		-- over before failing anyway.
		if isApiAccessError(result) then
			return false, result
		end

		if tries < MAX_ATTEMPTS then
			local delay = math.min(BACKOFF_BASE_SECONDS * 2 ^ (tries - 1), BACKOFF_MAX_SECONDS)
			-- Jitter stops 20 players' autosaves from retrying in lockstep.
			task.wait(delay + math.random() * delay * 0.5)
		end
	end

	warn(`[DataService] {label} failed after {MAX_ATTEMPTS} attempts: {lastError}`)
	return false, lastError
end

-- Mock-store equivalent of UpdateAsync, so both paths share call sites.
local function mockUpdate(key: string, transform: (StoredDocument?) -> StoredDocument?): StoredDocument?
	local store = mockStore
	if not store then
		return nil
	end

	local updated = transform(deepCopy(store[key]))
	if updated ~= nil then
		store[key] = deepCopy(updated)
	end
	return updated
end

local function updateAsync(key: string, label: string, transform: (StoredDocument?) -> StoredDocument?): (boolean, StoredDocument?)
	local store = getStore()

	if not store then
		if mockStore then
			return true, mockUpdate(key, transform)
		end
		return false, nil
	end

	local ok, result = attempt(label, function()
		return store:UpdateAsync(key, transform)
	end)

	if ok then
		return true, result
	end

	-- The store constructed fine but the operation was refused on API access.
	-- Fall back here too, then drop the real store so later calls go straight
	-- to the mock instead of failing again first.
	if isApiAccessError(result) then
		useMockStore(tostring(result))
		if mockStore then
			realStore = nil
			return true, mockUpdate(key, transform)
		end
	end

	return false, nil
end

-- ==========================================================================
-- Session state
-- ==========================================================================

type Session = {
	player: Player,
	profile: Profile,
	joinedClock: number,
	dirty: boolean,
	releasing: boolean,
}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}

DataService.ProfileLoaded = Signal.new()
DataService.ProfileReleased = Signal.new()

local function isLockOurs(lock: SessionLock?): boolean
	return lock ~= nil and lock.jobId == JOB_ID
end

local function isLockStale(lock: SessionLock?): boolean
	if not lock then
		return true
	end
	return (os.time() - (lock.heartbeatUnix or 0)) >= LOCK_STALE_SECONDS
end

local function freshLock(): SessionLock
	return {
		jobId = JOB_ID,
		placeId = game.PlaceId,
		heartbeatUnix = os.time(),
	}
end

-- ==========================================================================
-- Load / save / release
-- ==========================================================================

--[[
	Acquires the session lock and returns the migrated profile.
	Returns nil when another live server holds the lock -- the caller retries,
	then kicks if the contention never clears.
]]
local function tryAcquire(userId: number): (boolean, Profile?, string?)
	local contended = false

	local ok, document = updateAsync(keyFor(userId), `load {userId}`, function(existing)
		local doc: StoredDocument = existing or { data = nil :: any, lock = nil }

		if doc.lock and not isLockOurs(doc.lock) and not isLockStale(doc.lock) then
			-- Someone live owns this profile. Cancel the write entirely.
			contended = true
			return nil
		end

		doc.data = migrate(doc.data)
		doc.lock = freshLock()
		return doc
	end)

	if contended then
		return false, nil, "locked"
	end
	if not ok or not document then
		return false, nil, "store_error"
	end

	return true, document.data, nil
end

local function loadProfile(player: Player)
	if sessions[player] or loading[player] then
		return
	end
	loading[player] = true

	local profile: Profile? = nil
	local lastReason: string? = nil

	for tries = 1, LOCK_ACQUIRE_ATTEMPTS do
		if not player.Parent then
			loading[player] = nil
			return
		end

		local ok, loaded, reason = tryAcquire(player.UserId)
		if ok and loaded then
			profile = loaded
			break
		end

		lastReason = reason
		if reason == "locked" and tries < LOCK_ACQUIRE_ATTEMPTS then
			task.wait(LOCK_RETRY_SECONDS)
		elseif reason ~= "locked" then
			break
		end
	end

	loading[player] = nil

	if not profile then
		if not player.Parent then
			return
		end
		warn(`[DataService] could not load profile for {player.Name} ({lastReason})`)
		player:Kick(
			if lastReason == "locked"
				then "Your save is still in use by another server. Please rejoin in a moment."
				else "Could not load your save. Please rejoin -- your progress is safe."
		)
		return
	end

	-- Player left while we were loading; hand the lock straight back.
	if not player.Parent then
		task.spawn(function()
			updateAsync(keyFor(player.UserId), `abandon {player.UserId}`, function(existing)
				if existing and isLockOurs(existing.lock) then
					existing.lock = nil
					return existing
				end
				return nil
			end)
		end)
		return
	end

	sessions[player] = {
		player = player,
		profile = profile,
		joinedClock = os.clock(),
		dirty = false,
		releasing = false,
	}

	DataService.ProfileLoaded:Fire(player, profile)
end

--[[
	Writes the profile back. `release` clears the lock as part of the same
	UpdateAsync so a leave never leaves a lock behind, even if the server dies
	immediately after.
]]
local function saveProfile(player: Player, release: boolean): boolean
	local session = sessions[player]
	if not session then
		return false
	end

	-- Fold this session's elapsed time in before writing.
	local now = os.clock()
	session.profile.playtime += now - session.joinedClock
	session.joinedClock = now
	session.profile.lastOnlineUnix = os.time()

	local payload = deepCopy(session.profile)

	local ok = updateAsync(keyFor(player.UserId), `save {player.UserId}`, function(existing)
		local doc: StoredDocument = existing or { data = payload, lock = nil }

		-- If our lock was stolen while we were live, don't clobber whoever owns
		-- it now. Losing one session's progress beats corrupting the newer one.
		if doc.lock and not isLockOurs(doc.lock) and not isLockStale(doc.lock) then
			warn(`[DataService] lock for {player.Name} was taken by another server; skipping save`)
			return nil
		end

		doc.data = payload
		doc.lock = if release then nil else freshLock()
		return doc
	end)

	if ok then
		session.dirty = false
	end
	return ok
end

local function releaseProfile(player: Player)
	local session = sessions[player]
	if not session or session.releasing then
		return
	end
	session.releasing = true

	saveProfile(player, true)

	sessions[player] = nil
	DataService.ProfileReleased:Fire(player)
end

-- ==========================================================================
-- Public API
-- ==========================================================================

-- Live profile, or nil if it hasn't finished loading. Callers that can't
-- tolerate nil should use WaitForProfile.
function DataService.get(player: Player): Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

function DataService.isLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

-- Yields until the profile is available. Returns nil on timeout or if the
-- player leaves first.
function DataService.waitFor(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)

	while os.clock() < deadline do
		local session = sessions[player]
		if session then
			return session.profile
		end
		if not player.Parent then
			return nil
		end
		task.wait(0.1)
	end

	return nil
end

--[[
	The only sanctioned way to mutate a profile. Marks the session dirty so the
	next autosave actually writes.

	    DataService.update(player, function(profile)
	        profile.coins += 100
	    end)

	Returns false if the profile isn't loaded, so callers can bail rather than
	silently dropping a reward.
]]
function DataService.update(player: Player, mutator: (Profile) -> ()): boolean
	local session = sessions[player]
	if not session then
		return false
	end

	mutator(session.profile)
	session.dirty = true
	return true
end

-- Forces a write now. Used before high-stakes moments (rebirth, big purchase)
-- where losing the last 60 seconds would be especially bad.
function DataService.saveNow(player: Player): boolean
	return saveProfile(player, false)
end

-- Read-only copy, safe to hand to code that shouldn't mutate live state.
function DataService.snapshot(player: Player): Profile?
	local session = sessions[player]
	return if session then deepCopy(session.profile) else nil
end

--[[
	Income is owned by IncomeService, which doesn't exist until phase D. It
	registers a provider here so the client snapshot can carry a live $/sec
	without DataService having to know how income is computed.
]]
local incomeProvider: ((Player) -> number)? = nil

function DataService.setIncomeProvider(provider: (Player) -> number)
	incomeProvider = provider
end

--[[
	The client-facing projection of a profile. Deliberately not the whole thing:
	lock state, playtime, and the pity counter stay server-side. Pity in
	particular must not leak, or a client could time its rolls.
]]
function DataService.buildSnapshot(player: Player): SharedTypes.ProfileSnapshot?
	local session = sessions[player]
	if not session then
		return nil
	end

	local profile = session.profile
	return {
		coins = profile.coins,
		gems = profile.gems,
		rebirths = profile.rebirths,
		ownedTools = deepCopy(profile.ownedTools),
		equippedPickaxe = profile.equippedPickaxe,
		equippedBackpack = profile.equippedBackpack,
		oreCounts = deepCopy(profile.oreCounts),
		brainrotsOwned = deepCopy(profile.brainrotsOwned),
		placedBrainrots = deepCopy(profile.placedBrainrots),
		unlockedLayers = deepCopy(profile.unlockedLayers),
		indexDiscovered = deepCopy(profile.indexDiscovered),
		plotSlots = profile.plotSlots,
		incomePerSecond = if incomeProvider then incomeProvider(player) else 0,
	}
end

-- Pushes a fresh snapshot to one client. Services call this after any change
-- the client needs to see immediately rather than on its next poll.
function DataService.pushSnapshot(player: Player)
	local snapshot = DataService.buildSnapshot(player)
	if snapshot then
		RemoteRegistry.event("ProfileUpdated"):FireClient(player, snapshot)
	end
end

function DataService.getSchemaVersion(): number
	return SCHEMA_VERSION
end

-- True when running against the in-memory Studio fallback. Other services use
-- this to soften warnings that would otherwise be alarming in Studio.
function DataService.isUsingMockStore(): boolean
	return mockStore ~= nil
end

-- ==========================================================================
-- Lifecycle
-- ==========================================================================

local autosaveThread: thread? = nil
local connections: { RBXScriptConnection } = {}

function DataService.Init()
	-- Nothing to wire up before other services register; the store is created
	-- lazily on first access so Studio's API-access warning happens once, at
	-- the first real load, rather than at boot.
end

function DataService.Start()
	-- The client's first read of its own state. Returns nil if the profile is
	-- still loading; the client retries rather than caching a blank.
	RemoteRegistry.func("GetProfileSnapshot").OnServerInvoke = function(player: Player)
		return DataService.buildSnapshot(player)
	end

	-- Push a snapshot as soon as the profile exists, so a client that joined
	-- before its data loaded doesn't have to poll.
	DataService.ProfileLoaded:Connect(function(player: Player)
		DataService.pushSnapshot(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		task.spawn(loadProfile, player)
	end))

	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		releaseProfile(player)
	end))

	-- Autosave. Each pass walks the sessions and saves the dirty ones, spacing
	-- writes across the interval so 20 profiles don't burst the request budget.
	autosaveThread = task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveSeconds)

			local pending: { Player } = {}
			for player, session in sessions do
				if session.dirty and not session.releasing then
					table.insert(pending, player)
				end
			end

			if #pending > 0 then
				local spacing = GameConfig.AutosaveSeconds / (#pending + 1)
				for _, player in pending do
					if sessions[player] then
						saveProfile(player, false)
					end
					task.wait(spacing)
				end
			end
		end
	end)

	-- Final flush. BindToClose blocks shutdown until every profile is released,
	-- which is the last chance to clear locks cleanly.
	game:BindToClose(function()
		if mockStore then
			return
		end

		local remaining = 0
		for player in sessions do
			remaining += 1
			task.spawn(function()
				releaseProfile(player)
				remaining -= 1
			end)
		end

		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- Only used by tests and hot-reload paths; a live server never stops the service.
function DataService.Stop()
	if autosaveThread then
		task.cancel(autosaveThread)
		autosaveThread = nil
	end

	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	for player in sessions do
		releaseProfile(player)
	end
end

-- Exposed for the Tests/ suite: lets migration and reconcile logic be exercised
-- without a DataStore.
DataService._internal = {
	defaultProfile = defaultProfile,
	migrate = migrate,
	reconcile = reconcile,
	deepCopy = deepCopy,
	SCHEMA_VERSION = SCHEMA_VERSION,
	LOCK_STALE_SECONDS = LOCK_STALE_SECONDS,
}

return DataService
