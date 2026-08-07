--!strict
--[[
	SharedTypes
	Every shape that crosses a boundary -- config to system, server to client,
	memory to DataStore -- is declared once here and imported everywhere else.

	Profile note: this table is serialized to a DataStore, so it must stay
	JSON-round-trippable. That means no mixed array/dict tables and no numeric
	keys (JSON turns those into strings and the round trip stops matching the
	type). `unlockedLayers` is an array of indices for exactly that reason.
]]

local SharedTypes = {}

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type MutationId = "Normal" | "Golden" | "Diamond" | "Glitched"

-- ==========================================================================
-- Config shapes
-- ==========================================================================

export type OreDef = {
	id: string,
	displayName: string,
	rarity: Rarity,
	color: Color3,
	baseValue: number, -- coins per unit when sold raw
	hardness: number, -- HP multiplier for the block
	weightPerUnit: number, -- backpack space consumed
	layers: { [number]: number }, -- layerIndex -> spawn weight
	convertsTo: { string }, -- BrainrotDef ids this ore biases toward
	minRebirths: number?, -- gated ore tiers; nil means always available
}

export type BrainrotDef = {
	id: string,
	displayName: string,
	rarity: Rarity,
	incomePerSecond: number,
	sellValue: number,
	mutations: { [string]: number }, -- MutationId -> income multiplier
	modelBuilder: string, -- function name in ModelFactory
}

export type LayerDef = {
	index: number,
	id: string,
	displayName: string,
	minDepth: number, -- studs below GameConfig.SurfaceY, inclusive
	maxDepth: number, -- exclusive
	hpMultiplier: number,
	unlockCost: number,
	ambientColor: Color3,
	fogColor: Color3,
	fogEnd: number,
}

export type PickaxeDef = {
	id: string,
	displayName: string,
	tier: number,
	power: number, -- damage per swing, before rebirth multiplier
	swingsPerSecond: number,
	reach: number, -- studs, before GameConfig.ReachTolerance
	price: number,
}

export type BackpackDef = {
	id: string,
	displayName: string,
	tier: number,
	capacity: number, -- total weight units
	price: number,
}

-- ==========================================================================
-- Runtime shapes
-- ==========================================================================

-- A single mine block's authoritative server state. Never mirrored to
-- attributes on the Part -- clients only ever see replicated crack stages.
export type BlockState = {
	oreId: string,
	hp: number,
	maxHp: number,
	layerIndex: number,
}

-- Grid coordinate of a block or chunk. Integer components.
export type GridKey = string -- "x:y:z", produced by MineService.toKey

export type OwnedBrainrot = {
	uid: string,
	brainrotId: string,
	mutation: MutationId,
	acquiredUnix: number,
}

export type PlacedBrainrot = {
	uid: string, -- matches an OwnedBrainrot.uid
	slot: number, -- 1-based podium index
}

-- ==========================================================================
-- Persisted profile
-- ==========================================================================

export type Profile = {
	schemaVersion: number,
	coins: number,
	gems: number,
	rebirths: number,
	ownedTools: { [string]: boolean },
	equippedPickaxe: string,
	equippedBackpack: string,
	oreCounts: { [string]: number },
	brainrotsOwned: { OwnedBrainrot },
	placedBrainrots: { PlacedBrainrot },
	unlockedLayers: { number },
	indexDiscovered: { [string]: boolean },
	pityCounter: number,
	plotSlots: number,
	lastOnlineUnix: number,
	playtime: number,
}

-- What the DataStore key actually holds: the profile plus the session lock.
export type StoredDocument = {
	data: Profile,
	lock: SessionLock?,
}

export type SessionLock = {
	jobId: string,
	placeId: number,
	heartbeatUnix: number,
}

-- ==========================================================================
-- Cross-boundary payloads
-- ==========================================================================

-- Trimmed profile the client is allowed to see. Excludes lock state and
-- anything the client has no business knowing.
export type ProfileSnapshot = {
	coins: number,
	gems: number,
	rebirths: number,
	ownedTools: { [string]: boolean },
	equippedPickaxe: string,
	equippedBackpack: string,
	oreCounts: { [string]: number },
	brainrotsOwned: { OwnedBrainrot },
	placedBrainrots: { PlacedBrainrot },
	unlockedLayers: { number },
	indexDiscovered: { [string]: boolean },
	plotSlots: number,
	incomePerSecond: number,
}

export type ConversionResult = {
	ok: boolean,
	reason: string?,
	brainrotId: string?,
	mutation: MutationId?,
	rarity: Rarity?,
	pityFired: boolean?,
	isNewDiscovery: boolean?,
}

export type PurchaseResult = {
	ok: boolean,
	reason: string?,
	coins: number?,
}

return SharedTypes
