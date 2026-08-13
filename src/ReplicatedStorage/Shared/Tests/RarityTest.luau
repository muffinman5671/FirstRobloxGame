--!strict
--[[
	RarityTest
	The doc's §8.4 requirement: distribution over 100k rolls within tolerance,
	and pity firing correctly.

	Every roll here is seeded, so a failure is reproducible rather than a coin
	flip that fails one run in twenty.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Rarity = require(ReplicatedStorage.Shared.Modules.Rarity)

return function(t)
	-- ---------- ordering ----------
	t.equal(#Rarity.ORDER, 6, "six rarities")
	t.ok(Rarity.rank("Mythic") > Rarity.rank("Common"), "Mythic outranks Common")
	t.ok(Rarity.atLeast("Legendary", "Epic"), "Legendary satisfies an Epic minimum")
	t.ok(not Rarity.atLeast("Rare", "Epic"), "Rare does not satisfy an Epic minimum")
	t.ok(Rarity.atLeast("Epic", "Epic"), "a rarity satisfies itself")

	-- ---------- distribution ----------
	local entries = {
		{ id = "c", weight = 700, rarity = "Common" },
		{ id = "u", weight = 200, rarity = "Uncommon" },
		{ id = "r", weight = 80, rarity = "Rare" },
		{ id = "e", weight = 15, rarity = "Epic" },
		{ id = "l", weight = 4, rarity = "Legendary" },
		{ id = "m", weight = 1, rarity = "Mythic" },
	}

	local N = 100000
	local rng = Random.new(20260812)
	local counts: { [string]: number } = {}
	for _ = 1, N do
		local picked = Rarity.roll(entries, rng)
		counts[picked.id] = (counts[picked.id] or 0) + 1
	end

	local expected = { c = 0.70, u = 0.20, r = 0.08, e = 0.015, l = 0.004, m = 0.001 }
	for id, want in expected do
		local got = (counts[id] or 0) / N
		-- Tolerance scales with rarity: the Mythic bucket sees ~100 hits in
		-- 100k, so its sampling error is inherently much larger than Common's.
		local tolerance = if want >= 0.1 then 0.02 elseif want >= 0.01 then 0.01 else want * 0.35
		t.near(got, want, tolerance, `weight {id} lands within tolerance over {N} rolls`)
	end

	local total = 0
	for _, n in counts do
		total += n
	end
	t.equal(total, N, "every roll returned something")

	-- ---------- weights of zero ----------
	local zeroed = {
		{ id = "a", weight = 0, rarity = "Common" },
		{ id = "b", weight = 10, rarity = "Common" },
	}
	local sawZero = false
	for _ = 1, 500 do
		if Rarity.roll(zeroed, rng).id == "a" then
			sawZero = true
		end
	end
	t.ok(not sawZero, "a zero-weight entry is never selected")
	t.equal(Rarity.roll({}, rng), nil, "an empty table rolls nil")

	-- ---------- odds ----------
	local odds = Rarity.odds(entries)
	local sum = 0
	for _, chance in odds do
		sum += chance
	end
	t.near(sum, 1, 1e-9, "odds sum to exactly 1")
	t.near(odds.c, 0.70, 1e-9, "odds match the declared weights")

	-- ---------- pity ----------
	local config = { threshold = GameConfig.PityThreshold, minimumRarity = "Epic" }
	local pity = 0
	local gap, worstGap, fired = 0, 0, 0
	local prng = Random.new(99)

	for _ = 1, 30000 do
		local picked, nextPity, didFire = Rarity.rollWithPity(entries, pity, config, prng)
		pity = nextPity
		gap += 1
		if didFire then
			fired += 1
		end
		if Rarity.atLeast(picked.rarity, "Epic") then
			worstGap = math.max(worstGap, gap)
			gap = 0
		end
	end

	t.ok(worstGap <= config.threshold, `Epic+ gap never exceeds the threshold (worst {worstGap})`, worstGap)
	t.ok(fired > 0, "pity actually fired during the run")

	-- A natural Epic+ must reset the counter without firing pity.
	local onlyEpic = { { id = "e", weight = 1, rarity = "Epic" } }
	local _, resetPity, naturalFired = Rarity.rollWithPity(onlyEpic, 5, config, prng)
	t.equal(resetPity, 0, "a natural Epic resets the pity counter")
	t.ok(not naturalFired, "a natural Epic does not report pity")

	-- A sub-minimum result must increment, not reset.
	local onlyCommon = { { id = "c", weight = 1, rarity = "Common" } }
	local _, bumped = Rarity.rollWithPity(onlyCommon, 5, config, prng)
	t.equal(bumped, 6, "a Common result increments the pity counter")

	-- Pity with no qualifying entry must not hang or lose the counter.
	local held, heldFired
	local _, heldCounter, wasFired = Rarity.rollWithPity(onlyCommon, config.threshold - 1, config, prng)
	held, heldFired = heldCounter, wasFired
	t.ok(not heldFired, "pity cannot fire when nothing qualifies")
	t.ok(held >= config.threshold - 1, "counter is preserved when pity cannot be satisfied", held)
end
