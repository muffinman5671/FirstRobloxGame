# Balance

Every number here is generated from `src/ReplicatedStorage/Shared/Config/`.
If you change a config value, this document is stale — regenerate it rather
than editing it by hand.

The tool tables are *derived* from the curve constants in `GameConfig.luau`, so
editing a single growth constant moves every tier at once:

| Constant | Value | Effect |
| --- | --- | --- |
| `CostGrowth` | 1.55 | Price multiplier per tier, shared by pickaxes, backpacks, and podium slots |
| `IncomeGrowth` | 1.8 | Brainrot income per rarity step. Kept **above** `CostGrowth` so spending always buys more than it cost |
| `PickaxePowerGrowth` | 1.45 | Damage per tier. Kept **below** `CostGrowth` so damage never outruns block HP scaling |
| `RebirthCostGrowth` | 3.2 | Rebirth price multiplier |
| `RebirthMultiplierStep` | 0.35 | Added to the multiplier per rebirth |

---

## Layers

| # | Layer | Depth (studs) | HP mult | Unlock cost |
| --- | --- | --- | --- | --- |
| 1 | Topsoil | 0–70 | 1× | free |
| 2 | Stonecore | 70–180 | 3.5× | 2,500 |
| 3 | Ironvein | 180–330 | 12× | 28,000 |
| 4 | Crystalis | 330–520 | 42× | 310,000 |
| 5 | Magmadeep | 520–760 | 150× | 3,400,000 |
| 6 | The Static | 760–1,040 | 520× | 38,000,000 |

Block HP = `BlockBaseHp (10) × layer HP mult × ore hardness`.

Layers unlock in order — you cannot buy Crystalis while Ironvein is locked.

---

## Ores

`Layers` reads `layer:spawn weight`. Weights are relative within a layer.

| Ore | Rarity | Value | Hardness | Weight | Layers | Gate |
| --- | --- | --- | --- | --- | --- | --- |
| Loam Clod | Common | 5 | 1 | 1 | 1:100 | — |
| Pebble Grit | Common | 7 | 1 | 1 | 1:70 2:45 | — |
| Slate Marrow | Common | 9 | 2 | 1 | 2:80 3:30 | — |
| Cinder Flake | Common | 12 | 2 | 1 | 2:55 3:40 | — |
| Rustcap Nodule | Uncommon | 20 | 2 | 1 | 2:48 3:12 | — |
| Bananini Pith | Uncommon | 24 | 2 | 2 | 2:36 3:10 | — |
| Copperbloom Sprig | Uncommon | 28 | 3 | 1 | 2:24 3:52 | — |
| Sootglass Bead | Uncommon | 33 | 3 | 2 | 3:44 4:18 | — |
| Cappuccino Shard | Rare | 62 | 3 | 2 | 3:40 4:25 | — |
| Patapim Geode | Rare | 70 | 4 | 2 | 3:28 4:34 | — |
| Sahur Clinker | Rare | 78 | 4 | 2 | 4:38 5:16 | — |
| Cappuccina Quartz | Rare | 85 | 4 | 2 | 4:30 5:22 | — |
| Crocodilo Slag | Epic | 205 | 5 | 3 | 4:14 5:34 | — |
| Tralala Prism | Epic | 232 | 5 | 3 | 5:26 6:14 | — |
| Watermelini Resin | Epic | 258 | 6 | 3 | 5:20 6:18 | — |
| Saturnita Core | Legendary | 720 | 6 | 4 | 5:8 6:22 | — |
| Spiderini Ember | Legendary | 830 | 7 | 4 | 6:18 | — |
| Elefanto Arcglass | Legendary | 940 | 7 | 4 | 6:14 | — |
| Medussi Voidpearl | Mythic | 2,850 | 8 | 4 | 6:6 | 3 rebirths |
| Garama Paradox | Mythic | 3,400 | 8 | 4 | 6:4 | 3 rebirths |

**Topsoil is deliberately Common-only**, and the top 2 block rows carry filler
rock regardless of layer (`OreFreeSurfaceRows`), so the surface reads as clean
ground and real veins are something you dig down to find.

Backpack capacity is **weight**, not item count — one Voidpearl fills four
times the space of a Loam Clod.

---

## Brainrots

Mutation columns show the resulting income per second.

| Brainrot | Rarity | $/sec | Sell | Golden 2.5× | Diamond 6× | Glitched 15× |
| --- | --- | --- | --- | --- | --- | --- |
| Bobrito Bandito | Common | 2 | 156 | 5 | 12 | 30 |
| Boneca Ambalabu | Common | 2.2 | 172 | 5.5 | 13.2 | 33 |
| Trippi Troppi | Common | 2.5 | 195 | 6.25 | 15 | 37.5 |
| Trulimero Trulicina | Common | 2.8 | 218 | 7 | 16.8 | 42 |
| Bananita Dolphinita | Common | 3.1 | 242 | 7.75 | 18.6 | 46.5 |
| Piccione Macchina | Common | 3.4 | 265 | 8.5 | 20.4 | 51 |
| Brr Brr Patapim | Uncommon | 6.5 | 507 | 16.25 | 39 | 97.5 |
| Chimpanzini Bananini | Uncommon | 7 | 546 | 17.5 | 42 | 105 |
| Cappuccino Assassino | Uncommon | 7.8 | 608 | 19.5 | 46.8 | 117 |
| Burbaloni Luliloli | Uncommon | 8.5 | 663 | 21.25 | 51 | 127.5 |
| Glorbo Fruttodrillo | Uncommon | 9.2 | 718 | 23 | 55.2 | 138 |
| Frigo Camelo | Uncommon | 10 | 780 | 25 | 60 | 150 |
| Tralalero Tralala | Rare | 22 | 1,716 | 55 | 132 | 330 |
| Tung Tung Tung Sahur | Rare | 24 | 1,872 | 60 | 144 | 360 |
| Ballerina Cappuccina | Rare | 26 | 2,028 | 65 | 156 | 390 |
| Lirilì Larilà | Rare | 29 | 2,262 | 72.5 | 174 | 435 |
| Bombombini Gusini | Rare | 32 | 2,496 | 80 | 192 | 480 |
| Bombardiro Crocodilo | Epic | 76 | 5,928 | 190 | 456 | 1,140 |
| Orangutini Ananassini | Epic | 84 | 6,552 | 210 | 504 | 1,260 |
| Tigrullini Watermelini | Epic | 92 | 7,176 | 230 | 552 | 1,380 |
| Girafa Celestre | Epic | 100 | 7,800 | 250 | 600 | 1,500 |
| La Vacca Saturno Saturnita | Legendary | 260 | 20,280 | 650 | 1,560 | 3,900 |
| Chimpanzini Spiderini | Legendary | 290 | 22,620 | 725 | 1,740 | 4,350 |
| Cocofanto Elefanto | Legendary | 320 | 24,960 | 800 | 1,920 | 4,800 |
| Graipuss Medussi | Mythic | 900 | 70,200 | 2,250 | 5,400 | 13,500 |
| Garama and Madundung | Mythic | 1,050 | 81,900 | 2,625 | 6,300 | 15,750 |

Sell value is 78× base income throughout. Income bands do not overlap between
rarities — the weakest Epic out-earns the strongest Rare — which `EconomyTest`
asserts.

---

## Pickaxes

| # | Pickaxe | Power | Swings/s | Reach | Price |
| --- | --- | --- | --- | --- | --- |
| 1 | Cracked Trowel | 3 | 2.5 | 18 | free |
| 2 | Tin Pick | 4.35 | 2.63 | 18.6 | 500 |
| 3 | Iron Pick | 6.31 | 2.76 | 19.3 | 780 |
| 4 | Steel Pick | 9.15 | 2.89 | 19.9 | 1,200 |
| 5 | Tungsten Pick | 13.26 | 3.03 | 20.5 | 1,900 |
| 6 | Obsidian Pick | 19.23 | 3.16 | 21.2 | 2,900 |
| 7 | Quartz Pick | 27.88 | 3.29 | 21.8 | 4,500 |
| 8 | Cobalt Pick | 40.43 | 3.42 | 22.4 | 6,900 |
| 9 | Titanium Pick | 58.62 | 3.55 | 23.1 | 11,000 |
| 10 | Plasma Pick | 85 | 3.68 | 23.7 | 17,000 |
| 11 | Meteor Pick | 123.25 | 3.82 | 24.3 | 26,000 |
| 12 | Prism Pick | 178.72 | 3.95 | 24.9 | 40,000 |
| 13 | Voltaic Pick | 259.14 | 4.08 | 25.6 | 62,000 |
| 14 | Magma Pick | 375.76 | 4.21 | 26.2 | 96,000 |
| 15 | Abyssal Pick | 544.85 | 4.34 | 26.8 | 150,000 |
| 16 | Chrono Pick | 790.03 | 4.47 | 27.5 | 230,000 |
| 17 | Nebula Pick | 1,145.54 | 4.61 | 28.1 | 360,000 |
| 18 | Singularity Pick | 1,661.03 | 4.74 | 28.7 | 550,000 |
| 19 | Paradox Pick | 2,408.49 | 4.87 | 29.4 | 860,000 |
| 20 | Static Breaker | 3,492.31 | 5 | 30 | 1,300,000 |

Swing speed and reach interpolate linearly rather than geometrically — they are
feel knobs, not power knobs, so they stay off the cost curve.

Damage per second at tier 20 is ~17,460 before crits, ~19,200 with them. The
toughest block in the game (Mythic ore, hardness 8, in The Static) has 41,600
HP — about 2.4 seconds, or 2.2 with crits.

### Critical hits

Each swing has a **10%** chance to crit for **2×** damage, rolled on the server.
Expected damage is 10% above the Power column.

### Ore per block

Every broken block pays **exactly 1** unit. It was 1–2 while the starter
pickaxe swung 1.6 times a second; swing speed then went up by half (1.6 → 2.5 at
tier 1, 3.2 → 5 at tier 20), and the yield came down by the same factor so that
ore per minute stayed where it was. Blocks break faster; the pacing in the
Targets table below did not move with them.

---

## Backpacks

| # | Backpack | Capacity | Price |
| --- | --- | --- | --- |
| 1 | Paper Sack | 25 | free |
| 2 | Canvas Pouch | 40 | 400 |
| 3 | Leather Satchel | 64 | 620 |
| 4 | Miner's Duffel | 102 | 960 |
| 5 | Reinforced Pack | 164 | 1,500 |
| 6 | Hauler Rig | 262 | 2,300 |
| 7 | Cargo Harness | 419 | 3,600 |
| 8 | Freight Frame | 671 | 5,500 |
| 9 | Gravity Well Pack | 1,074 | 8,600 |
| 10 | Compressor Rig | 1,718 | 13,000 |
| 11 | Voidfold Satchel | 2,749 | 21,000 |
| 12 | Infinity Crate | 4,398 | 32,000 |

---

## Conversion odds

One roll costs **20 units of a single ore type**.

> **Ceiling worth knowing:** the starter backpack holds 25 weight, and Topsoil's
> two ores split roughly 59/41, so the largest single-type stack one trip can
> produce is about **15 units**. A conversion cost far above that gates the
> first roll behind a backpack upgrade instead of behind mining. 20 is
> deliberately just past one trip and comfortably inside two.

| Rarity | Base | Feeding Cappuccino Shard |
| --- | --- | --- |
| Common | 65.992% | 51.648% |
| Uncommon | 24.417% | 35.035% |
| Rare | 7.424% | 11.621% |
| Epic | 1.760% | 1.377% |
| Legendary | 0.363% | 0.284% |
| Mythic | 0.044% | 0.034% |

**Reading the bias column:** an ore multiplies its own `convertsTo` targets by
`ConversionOreBias` (6×) and leaves everything else at base weight. Because the
odds renormalise, bands the ore doesn't name go *down*. Cappuccino Shard points
at an Uncommon and a Rare, so those rise and Epic+ falls slightly. That is
working as intended — feeding a rare ore is how you bias toward rare outcomes.

Every character stays reachable from every ore. A Common ore can still produce
a Mythic, which is what keeps early conversions worth doing.

**Pity:** after 16 rolls without an Epic-or-better, the next roll is guaranteed
to be one. `RarityTest` asserts the gap never exceeds the configured threshold
over 30,000 rolls.

### Mutations

| Mutation | Multiplier | Chance |
| --- | --- | --- |
| Normal | 1× | 85.69% |
| Golden | 2.5× | 12.00% |
| Diamond | 6× | 2.06% |
| Glitched | 15× | 0.26% |

Rolled independently of the character, so any character can appear at any tier.

---

## Podium slots

4 at start, 10 maximum. Total cost to max out: **117,800**.

| Slots owned | Cost of the next |
| --- | --- |
| 4 | 5,000 |
| 5 | 7,800 |
| 6 | 12,000 |
| 7 | 19,000 |
| 8 | 29,000 |
| 9 | 45,000 |
| 10 | maxed |

The cap was 24 until schema 2. A profile that owned more than 10 is refunded
for every slot above the cap at the price it paid, and anything standing on a
podium that no longer exists is returned to storage, still owned.

The four starting podiums are the stage across the back of the base. The six
bought after that alternate left wall, right wall, from the stage toward the
door (`GameConfig.PodiumLayout`).

Capping the podiums did not slow the game down in the model. With 24 slots the
simulated player ended on about 37,500 coins a second, and with 10 on about
20,300 — but it reached The Static sooner (292 minutes against 317), because
the fourteen slots it no longer buys cost 58.1M between them, and that goes on
layer keys instead.

---

## Daily rewards

One claim per UTC day. Consecutive days walk down the table; the day after
day 7 is day 1 again, and missing a whole day sends the streak back to day 1.

Each day pays the **larger** of a flat amount and some minutes of the player's
passive income at the moment they claim:

| Day | Flat | Or minutes of income | At 10/sec | At 1,000/sec |
| --- | --- | --- | --- | --- |
| 1 | 250 | 5 | 3,000 | 300,000 |
| 2 | 500 | 8 | 4,800 | 480,000 |
| 3 | 1,000 | 10 | 6,000 | 600,000 |
| 4 | 2,000 | 15 | 9,000 | 900,000 |
| 5 | 4,000 | 20 | 12,000 | 1,200,000 |
| 6 | 7,500 | 30 | 18,000 | 1,800,000 |
| 7 | 15,000 | 60 | 36,000 | 3,600,000 |

A full week is 148 minutes of income, about 21 a day. Offline earnings can pay
up to 120 minutes' worth for a single absence (4 hours at half rate), so the
daily reward is always the smaller of the two. That is the intent: it is for
coming back, and it should not outweigh what the brainrots earned while away.

A new player's first reward is open the moment they join, and the model below
assumes they take it.

---

## Rebirth

| Rebirth | Cost | Multiplier after |
| --- | --- | --- |
| 0 → 1 | 250,000 | 1.35× |
| 1 → 2 | 800,000 | 1.70× |
| 2 → 3 | 2,600,000 | 2.05× |
| 3 → 4 | 8,200,000 | 2.40× |
| 4 → 5 | 26,000,000 | 2.75× |
| 5 → 6 | 84,000,000 | 3.10× |
| 6 → 7 | 270,000,000 | 3.45× |

The multiplier applies to mining damage, passive income, **and** ore sale value.

**Resets:** coins, all pickaxes and backpacks, carried ore.
**Keeps:** unlocked layers, owned and placed brainrots, podium slots, index.

Keeping layer keys is deliberate. They are the largest coin sink in the game;
wiping them every rebirth would make rebirth a punishment rather than a boost.
Mythic ore requires 3 rebirths.

---

## Passive income

Income ticks once per second at
`sum(incomePerSecond × mutation) × rebirthMultiplier × (1 + index bonus)` over
brainrots placed in **unlocked** slots. Fractional coins carry between ticks, so
a 2.5/sec brainrot pays 5 every two seconds rather than being floored to 2
forever.

### Index bonus

The collection log pays. Each character discovered adds **+1%** to passive
income, and finishing a whole rarity band adds that band's set bonus on top:

| Band | Characters | Set bonus |
| --- | --- | --- |
| Common | 6 | +5% |
| Uncommon | 6 | +8% |
| Rare | 5 | +12% |
| Epic | 4 | +20% |
| Legendary | 3 | +30% |
| Mythic | 2 | +50% |

The parts add together and the total multiplies income alongside the rebirth
multiplier. A full index is **+151%**. The bonus survives rebirth, because the
index does. Ore discoveries are recorded in the same index but pay nothing.

Offline earnings pay **50%** of the live rate, capped at **4 hours**. Leaving
the game running is always better than not, but returning still pays.

---

## Targets (§7) — measured

120 seeds, generated by `Shared/Tests/BalanceModel.luau`:

```lua
print(require(game.ReplicatedStorage.Shared.Tests.BalanceModel).run({ seeds = 120 }))
```

| Milestone | Target | Measured (avg) | Range | Ratio |
| --- | --- | --- | --- | --- |
| First conversion | ~2 min | **1.9 min** | 1.9–1.9 | 0.97× |
| Layer 2 | ~8 min | **8.2 min** | 4.3–13.1 | 1.03× |
| First Epic+ brainrot | ~20 min | **15.3 min** | 2.9–47.0 | 0.77× |
| First rebirth | ~60–75 min | **45.3 min** | 12.7–76.5 | 0.67× |

**Three of the four land within ±30% of target. First rebirth does not:** it
models at 0.67×, just under the band's 0.70× floor. It was 0.72× on these same
120 seeds before the daily reward existed, and the 250 coins a new player now
claims at minute zero are what moved it the rest of the way — they buy the
first upgrades a trip sooner, and that compounds. Nothing was retuned to pull
it back. `RebirthBaseCost` is the knob that moves this milestone and little
else, if it should be.

These were 40-seed figures until this measurement. At 40 seeds first Epic read
0.69× here and 0.77× at 120 with nothing else changed, which is conversion luck
rather than anything in the config, so the table now uses the larger sample.

Past the doc's last target, where the numbers are reported rather than aimed at:

| Milestone | Measured (avg) | Range | Seeds reaching it |
| --- | --- | --- | --- |
| Layer 4 (Crystalis) | **75.5 min** | 34.1–137.2 | 120/120 |
| Layer 5 (Magmadeep) | **150.7 min** | 57.1–275.2 | 120/120 |
| Layer 6 (The Static) | **295.0 min** | 165.1–447.3 | 116/120 |

Four seeds in 120 do not reach The Static inside the model's 8-hour cap. A
complete run of the content is still most of a working day.

### The swing-speed change, attributed (2026-10-04)

Swing speed went from 1.6–3.2 to 2.5–5 swings a second, crits and the index
bonus were added, and ore per block came down from 1–2 to exactly 1. Same 40
seeds each time, one change added per row:

| Configuration | First conversion | Layer 2 | First Epic+ | First rebirth | Layer 6 |
| --- | --- | --- | --- | --- | --- |
| Before (1.6–3.2 swings/s, yield 1–2) | 2.0 | 8.7 | 21.3 | 53.7 | 391.2 |
| Faster swings only | 1.5 | 7.1 | 12.2 | 39.9 | 301.6 |
| + crits | 1.5 | 7.1 | 11.7 | 37.9 | 305.0 |
| + index bonus | 1.5 | 7.1 | 11.4 | 36.7 | 262.9 |
| + yield fixed at 1 (**shipped**) | 1.9 | 8.8 | 17.2 | 49.6 | 323.4 |

Faster swings on their own put first rebirth at 0.59× of target, and with crits
and the index bonus on top it reached 0.54× with first Epic at 0.57× — outside
the ±30% band, and a third off the length of the game. Two ways of paying that
back were measured. Raising `BlockBaseHp` to 17 restores the pacing (0.95×,
1.02×, 0.99×, 0.72×) but leaves a block taking as long to break as it did
before, which is the thing the change was for. Fixing the yield at 1 keeps
blocks breaking about 1.5× as fast and takes the same factor out of what each
one pays, so ore per minute is unchanged. That is the one shipped.

The late game still models about 17% quicker than before. Most of that is the
index bonus, which is small in the first hour and large by Layer 6, and it is
intended. The two Layer 6 averages are also not quite like for like: six seeds
used to miss the 8-hour cap and were left out of the old one.

### How this was measured, and what it isn't

A **model**, not a human playthrough. It runs the real config and the real
shared `Conversion` module — the same outcome table and pity the server rolls —
and computes mining time analytically from pickaxe power against block HP.

The model itself is now checked in, at `Shared/Tests/BalanceModel.luau`. The
previous version was not: it lived only in a Studio session, so the numbers it
produced could not be reproduced or argued with once that session closed. Every
figure above regenerates from the repo.

Simulated player policy: always mine the deepest unlocked layer, roll whenever a
conversion is affordable, hold back the largest sub-cost stack rather than
selling it, **buy the next layer unlock as soon as it is affordable** and
otherwise buy the cheapest upgrade, stop upgrading once within reach of a
rebirth, and rebirth as soon as the cost is met.

Travel scales with depth, and asymmetrically: descent at 55 studs/sec (mostly
falling), ascent at 7 studs/sec (jumping block to block), plus 12s of hub
walking and 2s per menu interaction.

### What changed since the last measurement, and why the numbers moved

The earlier table was produced by a different model with two assumptions worth
naming, because between them they account for the whole difference:

- **It charged a flat 12s per round trip.** Replacing that with depth-scaled
  travel turned out to matter far less than expected — see below.
- **It bought whichever upgrade was cheapest.** This is the one that mattered.
  Tool tiers grow at `CostGrowth` from a 400–500 coin base, so the cheapest
  option stays under Ironvein's 28,000 until roughly tier 11 — and the simulated
  player reached its first rebirth having unlocked **two of the six layers**,
  with a tier-9 pickaxe and no reason to own one. A model that never buys the
  content is not modelling a player, and it was flattering every milestone that
  depends on depth.

### The travel question, answered

Depth-scaled travel was added to test whether late-game figures were optimistic.
They were, but **not because of travel**. Sweeping the ascent speed across the
plausible range and past it:

| Ascent (studs/sec) | Layer 2 | First rebirth | Layer 5 | Layer 6 |
| --- | --- | --- | --- | --- |
| 4.4 (pure jump-climbing) | 8.1 | 58.3 | 177.6 | 416.8 |
| 7 (the model's assumption) | 7.6 | 55.3 | 184.6 | 412.7 |
| 16 (walkspeed — as if a lift existed) | 7.6 | 48.1 | 158.9 | 419.6 |
| instant (travel is free) | 7.5 | 47.3 | 164.0 | 407.0 |

Making travel *free* moves Layer 6 by 1.4%, which is well inside the seed noise
in the same table. The reason is structural: **passive income accrues while you
travel**, and by the mid-game progression is income-bound rather than trip-bound.
Time spent climbing is not time spent not earning.

So the cost of the climb is not economic. It is experiential, and that does not
show up in any of these numbers:

> There is no lift, rope, or return-to-hub control anywhere in the game. The
> only teleport is `MineService`'s void catcher, which fires *below* the mine
> floor and warns when it does — a backstop, not a route. Coming back up from
> Magmadeep means jumping roughly 130 blocks, about 90 seconds, every trip.

A model cannot tell you whether that is boring. A playtest can, and it is the
first thing to watch for in one.

**Where else to distrust these numbers:**

- **The model plays well.** It never misclicks, never wanders, never stops to
  read anything. Real players are slower.
- **Variance is wide, and wider than the effects being measured.** First Epic
  ranges 8.7–63.9 min across seeds, driven by conversion luck. Differences under
  roughly 15% between two runs of this model are noise, not signal — at 12 seeds
  first Epic read 1.31× and at 40 seeds it reads 1.07×, and nothing changed but
  the sample.
- **Podium slots are assumed optimal.** The model always places its highest-income
  brainrots and buys a slot whenever it has more characters than podiums.

The tuning history is worth keeping: `ConversionOreCost` was originally 15
(first conversion ~1.0 min, too fast), briefly 25 (~2.3 min, but it dragged
every later milestone), and settled at 20 after sweeping seven cost/pity
combinations rather than guessing. `PityThreshold` went 25 → 16 for the same
reason — at 25 the first Epic modelled at ~28.6 min.

A real timed playthrough is still worth doing before launch. This narrows where
to look; it does not replace playing the game.
