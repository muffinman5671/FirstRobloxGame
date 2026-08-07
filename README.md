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

Every brainrot in this project is original to it. Names, silhouettes, and
builders are invented in a generic surreal animal/object-mashup style; nothing
references an existing meme character, real brand, or third-party asset. No
asset IDs appear anywhere in the source — `ModelFactory` builds each character
from `Instance.new` primitives, and placeholder art is marked `-- ART TODO` at
the builder.

---

## Build status

| Phase | Scope | State |
| --- | --- | --- |
| A | Project scaffold, configs, DataService | Done |
| B | Mine generation, mining | Not started |
| C | Inventory, economy, shop | Not started |
| D | Conversion, plots, income | Not started |
| E | UI polish, effects, leaderboards, tests | Not started |
