# Claude Code Prompt — "Mine For Brainrots" (Roblox)

> Copy everything below the line into Claude Code as a single prompt.

---

Build a complete, playable Roblox experience called **Mine For Brainrots**. It fuses the mining/upgrade loop of *Mining Simulator* with the collect-and-display income loop of *Steal a Brainrot*. Produce a full Rojo-managed project with Luau source that I can sync into Roblox Studio and press Play on. Do not stub systems out — every system described below must actually function end to end.

## 1. Core Gameplay Loop

1. Player spawns at a hub with a starter pickaxe and a small backpack.
2. Player descends into a procedurally generated mine shaft made of destructible blocks.
3. Swinging the pickaxe damages a block; when its HP hits zero it breaks and drops ore into the backpack.
4. Deeper layers contain rarer, higher-value **brainrot ores**.
5. When the backpack is full, the player returns to the surface (or uses a teleport pad) and sells raw ore for coins, OR feeds ore into the **Conversion Chamber**.
6. The Conversion Chamber turns ore into a **Brainrot character** — a weighted roll where ore rarity biases the outcome table.
7. Brainrots are placed on numbered podiums on the player's private base plot. Each podium generates passive income per second.
8. Passive income + ore sales buy: better pickaxes, bigger backpacks, faster movement, more podium slots, and access keys to deeper layers.
9. Rebirth resets coins/tools for a permanent multiplier and unlocks exclusive ore tiers.

## 2. Hard Constraints

- **Luau only.** No third-party packages beyond what I list. Target current Roblox API — do not use deprecated members (no `BodyVelocity`, no `wait()`, no `spawn()`; use `task.wait`, `task.spawn`, `LinearVelocity`).
- **Server-authoritative.** The client requests actions; the server validates and owns all state. Assume every client is an exploiter.
- **Original IP only.** The "brainrot" characters must be original parodies built from Roblox primitives and free-to-use meshes — invented names and silhouettes in the surreal animal/object mashup style (e.g. `Espressone Squalino`, `Missilino Alligatore`, `Bananutto Gorilloni`). Do not reference, name, or replicate existing meme characters, real brands, or copyrighted assets. Do not hardcode any asset IDs you cannot verify — use `Instance.new` primitives and mark art placeholders with `-- ART TODO`.
- **Mobile + console friendly.** Touch controls, gamepad navigation, UI scaled with `UIScale` driven by viewport size. Nothing smaller than 44px tap targets.
- **Performance:** target 60 FPS with 20 players. Mining blocks are `Part` instances, not `Terrain`. Use chunk streaming, part pooling, and `CollectionService` tags. No per-frame `FindFirstChild` in hot paths.

## 3. Project Structure

Use Rojo with this layout. Write `default.project.json`, `.gitignore`, `aftman.toml`, and a `README.md` with setup steps.

```
src/
  ReplicatedStorage/
    Shared/
      Config/
        OreConfig.luau          -- ore defs, per-layer spawn weights
        BrainrotConfig.luau     -- character defs, income, rarity
        ToolConfig.luau         -- pickaxes, backpacks, prices
        LayerConfig.luau        -- depth bands, HP scaling, unlock cost
        GameConfig.luau         -- tunables: chunk size, cap, tick rates
      Modules/
        Signal.luau
        Trove.luau              -- cleanup helper
        Rarity.luau             -- weighted roll + pity system
        Format.luau             -- 1.25K / 3.4M / 12.1B number abbreviation
        SharedTypes.luau        -- Luau type exports for all state
      Remotes/
        RemoteRegistry.luau     -- creates + fetches all Remotes by name
  ServerScriptService/
    Server/
      init.server.luau          -- boot order, service registry
      Services/
        DataService.luau        -- session-locked profiles, autosave, retry
        MineService.luau        -- chunk gen, block registry, break logic
        MiningService.luau      -- swing validation, damage, cooldowns
        InventoryService.luau   -- ore counts, capacity enforcement
        EconomyService.luau     -- coins, sales, purchases, rebirth
        ConversionService.luau  -- ore -> brainrot rolls
        PlotService.luau        -- plot claim/release, podium slots
        IncomeService.luau      -- passive income accrual + offline earnings
        ShopService.luau        -- purchase validation
        AntiCheatService.luau   -- rate limits, distance checks, sanity checks
        LeaderboardService.luau -- OrderedDataStore top-10 boards
  StarterPlayer/
    StarterPlayerScripts/
      Client/
        init.client.luau
        Controllers/
          MiningController.luau  -- input, target selection, swing anim
          UIController.luau
          EffectsController.luau -- particles, block crack decals, sounds
          NotifyController.luau  -- toasts, rarity reveal animation
        UI/
          HUD.luau               -- coins, backpack meter, depth indicator
          ShopFrame.luau
          InventoryFrame.luau
          ConvertFrame.luau
          IndexFrame.luau        -- collection log of discovered brainrots
```

## 4. Data & Config Schemas

Define these as strongly typed Luau tables. All balance numbers live in config — no magic numbers in system code.

```lua
-- OreConfig entry
{
  id = "espressone_ore",
  displayName = "Espressone Shard",
  rarity = "Rare",              -- Common/Uncommon/Rare/Epic/Legendary/Mythic
  color = Color3.fromRGB(...),
  baseValue = 45,               -- coins per unit when sold raw
  hardness = 3,                 -- HP multiplier for the block
  weightPerUnit = 1,            -- backpack space consumed
  layers = { [3] = 40, [4] = 25 }, -- layerIndex -> spawn weight
  convertsTo = { "espressone_squalino", "espressone_squalino_gold" },
}

-- BrainrotConfig entry
{
  id = "espressone_squalino",
  displayName = "Espressone Squalino",
  rarity = "Rare",
  incomePerSecond = 12,
  sellValue = 900,
  mutations = { Normal = 1.0, Golden = 2.5, Diamond = 6.0, Glitched = 15.0 },
  modelBuilder = "buildEspressoneSqualino", -- function name in ModelFactory
}
```

Ship **6 depth layers** (Topsoil, Stonecore, Ironvein, Crystalis, Magmadeep, The Static), **at least 18 ores**, and **at least 24 brainrots** spread across rarities, plus a 4-tier mutation system that multiplies income and applies a visual effect (gold tint, sparkle particles, chromatic shader-ish highlight).

## 5. System Requirements

**MineService** — Generate the mine as chunks of 4×4×4 stud blocks in a shaft grid below the hub. Generate lazily: only materialize chunks within N studs of any player, and reclaim parts to a pool when nobody is near. Each block stores `oreId`, `hp`, `maxHp` in a server-side dictionary keyed by grid position — never trust attributes on the part. Blocks regenerate after a configurable delay so the mine never empties permanently. Layer index is derived from Y position.

**MiningService** — Client sends `RequestSwing(blockPosition)`. Server validates: player is alive, within reach distance, swing cooldown elapsed (based on pickaxe speed), block exists and has HP. Server applies `damage = pickaxe.power * rebirthMultiplier`, replicates crack state, and on break credits ore if capacity allows. If the backpack is full, fire a `BackpackFull` remote and stop crediting. Log and throttle any player exceeding expected swing rate.

**ConversionService** — Consumes a configurable ore cost, rolls a weighted table biased by which ore was fed in, applies a pity counter that guarantees an Epic+ every N rolls, rolls a mutation, and grants the brainrot. Fire a client remote that plays a suspense-then-reveal animation scaled to rarity.

**PlotService** — Assign each joining player an unclaimed base plot. Build the plot from a template: a floor, walls, a sign with the owner's name, and podiums (start with 4 slots, expandable to 24 via purchase). Placing a brainrot spawns its model on a podium with a floating billboard showing name, mutation, and $/sec. Release and wipe the plot on leave.

**IncomeService** — Accrue income on a 1-second server heartbeat: sum of all placed brainrots' `incomePerSecond * mutationMultiplier * rebirthMultiplier`. Cap offline earnings at 4 hours on rejoin and show a "While you were away" popup.

**DataService** — Session-locked profile store with retry/backoff, autosave every 60s, save on leave and on `BindToClose`. Schema-versioned with a migration function. Profile shape:

```lua
{ schemaVersion, coins, gems, rebirths, ownedTools, equippedPickaxe,
  equippedBackpack, oreCounts, brainrotsOwned, placedBrainrots,
  unlockedLayers, indexDiscovered, pityCounter, lastOnlineUnix, playtime }
```

**AntiCheatService** — Rate limit every remote per player. Reject swings beyond reach, purchases the player can't afford, placements into occupied or unowned slots, and conversions without ore. Never accept a client-supplied price, value, or quantity.

## 6. UI Requirements

Build all UI in code (no `.rbxmx` dependency), styled cohesively: dark slate panels, chunky rounded corners, a saturated accent per rarity, `GothamBold`-family fonts, and spring-tweened open/close. Include:

- **HUD:** coins (abbreviated), $/sec, backpack fill bar with color shift as it fills, current depth in studs, equipped pickaxe icon.
- **Shop:** tabbed (Pickaxes / Backpacks / Plot Slots / Layer Keys), each card showing stat delta vs. currently equipped, owned/equipped/locked states, and a disabled-with-reason state when unaffordable.
- **Inventory:** ore grid with counts, total sale value, "Sell All" and per-ore sell.
- **Convert:** pick an ore, show the outcome odds table honestly, roll button, reveal sequence.
- **Index:** collection log of all brainrots with silhouettes for undiscovered ones and a completion percentage.
- **Rebirth:** requirement check, multiplier preview, confirm dialog.

## 7. Balance Targets

Tune the config so a fresh player reaches: first conversion in ~2 min, layer 2 in ~8 min, first Epic brainrot in ~20 min, first rebirth in ~60–75 min. Costs should follow a geometric curve (~1.55× per tier) while income follows ~1.8× per tier so upgrades always feel earned but attainable. Put every one of these curve constants in `GameConfig.luau` with a comment explaining its effect.

## 8. Deliverables & Acceptance

1. Full source per the tree above, no `TODO` in logic paths (art placeholders excepted).
2. `README.md`: install Aftman/Rojo, `rojo serve`, connect from Studio, folder mapping, how to tune balance, how to add a new ore or brainrot in one config edit each.
3. `BALANCE.md`: table of every ore, brainrot, and tool with its numbers.
4. A `Tests/` folder with plain-Luau assertion scripts for `Rarity.luau` (distribution over 100k rolls within tolerance, pity fires correctly), `Format.luau`, and economy price math.
5. Before you finish, self-review against this checklist and report on each: no deprecated APIs; every remote validated server-side; no client-authoritative currency; all connections cleaned up on player leave; no memory leaks from block pooling; game boots with zero output errors.

Work in this order and tell me when each phase is done: **(A)** project scaffold + configs + data service, **(B)** mine generation + mining, **(C)** inventory + economy + shop, **(D)** conversion + plots + income, **(E)** UI polish + effects + leaderboards + tests. Ask me before deviating from any structural decision above; make small balance judgment calls yourself and note them.
