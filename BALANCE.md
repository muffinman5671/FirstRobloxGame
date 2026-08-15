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
| 1 | Cracked Trowel | 3 | 1.6 | 18 | free |
| 2 | Tin Pick | 4.35 | 1.68 | 18.6 | 500 |
| 3 | Iron Pick | 6.31 | 1.77 | 19.3 | 780 |
| 4 | Steel Pick | 9.15 | 1.85 | 19.9 | 1,200 |
| 5 | Tungsten Pick | 13.26 | 1.94 | 20.5 | 1,900 |
| 6 | Obsidian Pick | 19.23 | 2.02 | 21.2 | 2,900 |
| 7 | Quartz Pick | 27.88 | 2.11 | 21.8 | 4,500 |
| 8 | Cobalt Pick | 40.43 | 2.19 | 22.4 | 6,900 |
| 9 | Titanium Pick | 58.62 | 2.27 | 23.1 | 11,000 |
| 10 | Plasma Pick | 85 | 2.36 | 23.7 | 17,000 |
| 11 | Meteor Pick | 123.25 | 2.44 | 24.3 | 26,000 |
| 12 | Prism Pick | 178.72 | 2.53 | 24.9 | 40,000 |
| 13 | Voltaic Pick | 259.14 | 2.61 | 25.6 | 62,000 |
| 14 | Magma Pick | 375.76 | 2.69 | 26.2 | 96,000 |
| 15 | Abyssal Pick | 544.85 | 2.78 | 26.8 | 150,000 |
| 16 | Chrono Pick | 790.03 | 2.86 | 27.5 | 230,000 |
| 17 | Nebula Pick | 1,145.54 | 2.95 | 28.1 | 360,000 |
| 18 | Singularity Pick | 1,661.03 | 3.03 | 28.7 | 550,000 |
| 19 | Paradox Pick | 2,408.49 | 3.12 | 29.4 | 860,000 |
| 20 | Static Breaker | 3,492.31 | 3.2 | 30 | 1,300,000 |

Swing speed and reach interpolate linearly rather than geometrically — they are
feel knobs, not power knobs, so they stay off the cost curve.

Damage per second at tier 20 is ~11,175. The toughest block in the game
(Mythic ore, hardness 8, in The Static) has 41,600 HP — about 3.7 seconds.

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

4 at start, 24 maximum. Total cost to max out: **~58.9M**.

| Slots owned | Cost of the next |
| --- | --- |
| 4 | 5,000 |
| 5 | 7,800 |
| 6 | 12,000 |
| 7 | 19,000 |
| 8 | 29,000 |
| 9 | 45,000 |
| 10 | 69,000 |
| 11 | 110,000 |
| 12 | 170,000 |
| 13 | 260,000 |
| 14 | 400,000 |
| 15 | 620,000 |
| 16 | 960,000 |
| 17 | 1,500,000 |
| 18 | 2,300,000 |
| 19 | 3,600,000 |
| 20 | 5,500,000 |
| 21 | 8,600,000 |
| 22 | 13,000,000 |
| 23 | 21,000,000 |
| 24 | maxed |

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
`sum(incomePerSecond × mutation) × rebirthMultiplier` over brainrots placed in
**unlocked** slots. Fractional coins carry between ticks, so a 2.5/sec brainrot
pays 5 every two seconds rather than being floored to 2 forever.

Offline earnings pay **50%** of the live rate, capped at **4 hours**. Leaving
the game running is always better than not, but returning still pays.

---

## Targets (§7) — measured

40 seeds, generated by `Shared/Tests/BalanceModel.luau`:

```lua
print(require(game.ReplicatedStorage.Shared.Tests.BalanceModel).run({ seeds = 40 }))
```

| Milestone | Target | Measured (avg) | Range | Ratio |
| --- | --- | --- | --- | --- |
| First conversion | ~2 min | **2.0 min** | 1.0–2.9 | 0.98× |
| Layer 2 | ~8 min | **8.7 min** | 3.2–13.3 | 1.08× |
| First Epic+ brainrot | ~20 min | **21.3 min** | 8.7–63.9 | 1.07× |
| First rebirth | ~60–75 min | **53.7 min** | 26.6–109.1 | 0.80× |

All four land within ±30% of target.

Past the doc's last target, where the numbers are reported rather than aimed at:

| Milestone | Measured (avg) | Range | Seeds reaching it |
| --- | --- | --- | --- |
| Layer 4 (Crystalis) | **81.3 min** | 37.4–127.4 | 40/40 |
| Layer 5 (Magmadeep) | **177.6 min** | 99.9–349.0 | 40/40 |
| Layer 6 (The Static) | **391.2 min** | 247.0–482.2 | 34/40 |

Six of forty seeds do not reach The Static inside the model's 8-hour cap. A
complete run of the content is most of a working day.

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
