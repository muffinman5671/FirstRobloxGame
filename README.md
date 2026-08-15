# Mine For Brainrots

A Roblox mining-and-collection experience: descend a procedurally generated
shaft, break blocks for brainrot ore, convert ore into original brainrot
characters, and place them on podiums that generate passive income.

Built as a Rojo-managed project. Luau only, server-authoritative, no
third-party packages.

---

## Setup

### 1. Toolchain

The project pins its tools in `aftman.toml`. With [Aftman] installed:

```bash
aftman install
```

If you already have Rojo 7.7.0 on your PATH, you can skip this — the pin exists
for reproducibility, not as a hard requirement.

[Aftman]: https://github.com/LPGhatguy/aftman

### 2. Serve

```bash
rojo serve default.project.json --port 34872
```

### 3. Connect from Studio

Open the place in Studio, then **Rojo** tab → **Connect** (defaults to
`localhost:34872`). The tree syncs live; edit files on disk and Studio updates.

To build a standalone place file instead of syncing:

```bash
rojo build default.project.json -o Mine-For-Brainrots.rbxlx
```

### 4. Enable API services

DataService needs DataStore access. In Studio: **Game Settings → Security →
Enable Studio Access to API Services**. Without it the service falls back to
in-memory storage, warns once, and your progress won't persist between test
sessions — the game still boots and plays.

---

## Folder mapping

`default.project.json` maps the source tree onto the DataModel:

| On disk | In Studio |
| --- | --- |
| `src/ReplicatedStorage/Shared/` | `ReplicatedStorage.Shared` |
| `src/ServerScriptService/Server/` | `ServerScriptService.Server` |
| `src/StarterPlayer/StarterPlayerScripts/Client/` | `StarterPlayer.StarterPlayerScripts.Client` |

Remote instances are **not** in the source tree. `RemoteRegistry.build()` creates
them at boot under `ReplicatedStorage.Net` from the single declaration in
`Shared/Remotes/RemoteRegistry.luau`.

---

## Architecture

Both the server and the client boot in two phases:

- **Init** — build state, register signals. A service may not call another
  service here; only `BOOT_ORDER` guarantees sequencing, not readiness.
- **Start** — connect events, spawn loops, call other services. Everything has
  finished `Init` by now.

Server services live in `Server/Services/` and are listed in `BOOT_ORDER` in
`Server/init.server.luau`. A module that exists but isn't listed warns at boot
rather than silently not running.

All player state flows through `DataService`. Nothing else touches
`DataStoreService`. Profiles are session-locked: a second server can't load a
profile while a live one holds the lock, which is what prevents duplication
across a fast rejoin.

---

## Tuning balance

**Every balance number lives in `Shared/Config/`.** System code contains no
magic numbers.

- `GameConfig.luau` — all tunables and the progression curve constants. The
  three that matter most:
  - `CostGrowth` (1.55) — cost multiplier per upgrade tier. Raising it
    lengthens the whole game.
  - `IncomeGrowth` (1.8) — brainrot income per rarity step. Kept above
    `CostGrowth` so spending always buys more than it cost.
  - `PickaxePowerGrowth` (1.45) — deliberately below `CostGrowth` so raw damage
    never outruns block HP scaling.
- `LayerConfig.luau` — the six depth bands, their HP multipliers and unlock costs.
- `OreConfig.luau` — ore definitions and per-layer spawn weights.
- `BrainrotConfig.luau` — character income, sell value, mutation multipliers.
- `ToolConfig.luau` — **generated** from the `GameConfig` curves. Only display
  names are authored here, so no tier can drift off the curve by hand.

Balance targets the config is tuned toward: first conversion ~2 min, layer 2
~8 min, first Epic ~20 min, first rebirth ~60–75 min.

### Adding a new ore

Append one entry to `OreConfig.ORES`:

```lua
{
    id = "my_ore",
    displayName = "My Ore",
    rarity = "Rare",
    color = Color3.fromRGB(120, 90, 200),
    baseValue = 65,
    hardness = 3,
    weightPerUnit = 2,
    layers = { [3] = 40, [4] = 20 },   -- layerIndex -> spawn weight
    convertsTo = { "some_brainrot_id" },
}
```

That's the whole edit. `MineService` builds its per-layer spawn tables from this
file at boot.

### Adding a new brainrot

Append one entry to `BrainrotConfig.BRAINROTS`, point at least one ore's
`convertsTo` at its id, and add the matching builder function to `ModelFactory`.

```lua
{
    id = "my_brainrot",
    displayName = "My Brainrot",
    rarity = "Epic",
    incomePerSecond = 80,
    sellValue = 6240,
    mutations = BrainrotConfig.MUTATIONS,
    modelBuilder = "buildMyBrainrot",
}
```

---

## Art and IP

The characters use the established "Italian brainrot" meme names that circulate
widely online. **Names are shared; artwork is not.** No mesh, texture, model, or
asset ID from any other Roblox experience is used or referenced, and no asset ID
appears anywhere in the source — `ModelFactory` builds every character from
`Instance.new` primitives, and placeholder art is marked `-- ART TODO` at the
builder. Silhouettes, hub, UI, and progression are original to this project.

These names are shared with other live Roblox experiences, and Roblox moderates
games that read as clones of popular ones. Keeping the visual design and
progression visibly distinct is a deliberate requirement, not a nicety. See
DESIGN.md §2.

---

## Build status

| Phase | Scope | State |
| --- | --- | --- |
| A | Project scaffold, configs, DataService | Done |
| B | Mine generation, mining | Done |
| C | Inventory, economy, shop | Done |
| D | Conversion, plots, income | Done |
| E | UI polish, effects, leaderboards, tests | Done |

11 server services, 4 client controllers, 7 UI modules.

## Tests

Plain-Luau assertion suites, no framework. Run from the Studio command bar:

```lua
print(require(game.ReplicatedStorage.Shared.Tests.TestRunner).runAll())
```

Covers weighted-roll distribution over 100k seeded rolls, the pity guarantee,
number formatting, the generated tool curves against their config constants,
conversion odds, and the session-lock rules. 132 assertions.

Two heavier tools sit alongside the suite and are deliberately *not* part of
`runAll()` — one makes live DataStore calls, the other runs a simulation:

```lua
print(require(game.ReplicatedStorage.Shared.Tests.ContentionProbe).run())
print(require(game.ReplicatedStorage.Shared.Tests.BalanceModel).run({ seeds = 40 }))
```

`ContentionProbe` plays two synthetic servers against one live DataStore key
using DataService's own `UpdateAsync` transforms. **Run it in Play mode** — its
concurrent section hangs from the Edit-mode command bar, for reasons that are
not the lock logic; the module header records what was ruled out.
`BalanceModel` is the §7 milestone model; see BALANCE.md for its output and its
assumptions.

## Verified against live infrastructure

The place is published and Studio Access to API Services is enabled, so the
DataStore path has been exercised for real rather than against the in-memory
fallback:

- Write/read round trip, with nested dictionaries and arrays intact
- Session lock written alongside the data, carrying jobId and placeId, with the
  heartbeat advancing on each save
- Stale-lock takeover after the 15-minute window
- Refusal to clobber a lock held by a live server, leaving both that lock and
  its data untouched
- Release on leave — after the session ends the final data is written and
  `lock` is `nil`, so a rejoin is not blocked
- A Studio session reclaiming the lock its own previous Play session left
  behind, and a live server correctly *refusing* to do the same
- OrderedDataStore reachable, so the leaderboards rank real data

This is worth doing rather than trusting: it caught a silent data-loss bug that
108 unit assertions and every prior play test had missed. `UpdateAsync` returns
`nil` when its transform returns `nil`, and the surrounding `pcall` succeeds
either way — so a save that deliberately backed off from a foreign lock looked
identical to one that wrote. It reported success **and cleared the dirty flag**,
so the autosave loop stopped retrying and that player's progress would never
have been written again. The in-memory fallback cannot reproduce it, because it
never returns `nil` from a cancelled transform.

## Known gaps

- **True multi-server contention is still untested.** `ContentionProbe` now
  drives DataService's own transforms with two synthetic server identities
  against one live key, so the protocol is exercised against real DataStore
  semantics — acquire, refuse, stale takeover, refused save, release. What it
  cannot reproduce is two *actual* servers: same-server writers see each other's
  writes immediately and never race across a network. The logic is tested; the
  concurrency is not.
- **`BindToClose` under a real shutdown.** Verified via stopping Play, which
  fires the same path, but not against an actual server shutdown with the 30
  second budget Roblox allows.
- **No human playthrough.** The §7 balance targets are *modelled*, not played —
  see the measured table and its caveats in BALANCE.md. The model now scales
  travel time with depth, which turned out to change the milestones by less than
  the seed-to-seed variance; it still plays optimally, so the figures remain a
  lower bound on how long a person takes.
- **There is no way back up the mine.** No lift, no rope, no return-to-hub
  control — the only teleport is the void catcher below the mine floor. From
  Magmadeep the climb is roughly 90 seconds of jumping, every trip. It costs
  nothing economically, because passive income accrues while you climb, so no
  measurement in BALANCE.md flags it. It is a playtest question.
- **Art is blockout only.** Every brainrot is a primitive silhouette marked
  `-- ART TODO` in `ModelFactory`, and there are no sounds, because every Roblox
  sound needs an asset ID and the project hardcodes none.
