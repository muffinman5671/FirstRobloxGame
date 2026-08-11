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
- **Established brainrot names, original assets.** The characters use the recognised "Italian brainrot" meme names that circulate widely online (e.g. `Tralalero Tralala`, `Bombardiro Crocodilo`, `Tung Tung Tung Sahur`, `La Vacca Saturno Saturnita`). Names and short phrases are used; **artwork is not**. Do not copy, trace, or reference meshes, textures, models, or asset IDs from any other Roblox experience. Do not hardcode any asset ID you cannot verify — build every character from `Instance.new` primitives and mark art placeholders with `-- ART TODO`. Do not reference real brands or copyrighted works beyond the meme names themselves.
  - **Known risk, accepted deliberately:** these names are shared with other live Roblox experiences. Roblox moderates games that read as clones of popular ones. Silhouettes, hub layout, UI, and progression are ours and should stay visibly distinct.
- **Brutalist + pixelated.** The whole game follows the art direction in §2a — no exceptions for "just this one screen".
- **Mobile + console friendly.** Touch controls, gamepad navigation, UI scaled with `UIScale` driven by viewport size. Nothing smaller than 44px tap targets.
- **Performance:** target 60 FPS with 20 players. Mining blocks are `Part` instances, not `Terrain`. Use chunk streaming, part pooling, and `CollectionService` tags. No per-frame `FindFirstChild` in hot paths.

## 2a. Art Direction — Brutalist / Pixelated

One look, applied everywhere: world, characters, UI, and effects. If a choice
makes something smoother, softer, or more rounded, it is the wrong choice.

**The three words**

- **Brutalist** — heavy, honest mass. Slab geometry and blunt volumes. Nothing
  is decorated; form comes from shape, not ornament.
- **Pixelated** — hard edges and a deliberately small colour palette. Colour is
  quantized to discrete steps, never smoothly interpolated. Sub-block detail is
  built from more blocks.
- **Cartoony** — surfaces are illustrated, not photographed. Chunky, graphic
  materials and punchy saturated colour, the way a stylised platformer looks
  rather than a render of real rock.

**Rules**

1. **Chunky illustrated materials.** Prefer Roblox's graphic, large-feature
   materials — `LeafyGrass`, `Cobblestone`, `Pebble`, `Sand`, `Sandstone`,
   `Ice`, `Marble` — over its photoreal ones (`Ground`, `Rock`, `Basalt`,
   `Slate`, `Concrete`, `Glacier`). Detail should read at block scale from
   several studs away. No `Neon`, no glass. Reflectance is reserved for ore, as
   a rarity signal, never as general shine.
2. **Push colour away from grey.** Roblox lights materials for realism, which
   desaturates everything. Saturation and value are boosted before the palette
   is applied (`CartoonSaturation`, `CartoonValueBoost`, `CartoonMinValue`) so
   surfaces read as flat paint rather than lit stone.
3. **Quantized palettes.** Every surface picks from a small per-context ramp
   (3–5 steps) around a base colour. Deterministic per object or per grid
   position, never random per frame.
4. **Hard edges.** Right angles, no bevels, no rounded corners anywhere —
   including UI.
5. **No image textures or asset IDs.** Surface detail comes from Roblox's
   built-in materials plus geometry. Sub-block detail is built from more blocks
   — mine blocks carry small raised pixel tiles on their exposed faces. This
   keeps the "no unverifiable asset IDs" constraint intact by construction.
6. **Colour carries meaning.** Rarity, depth, and state are read through the
   palette first and the material second.

**Applies to**

- **Mine blocks** — per-layer ramp, flat matte, damage shown by darkening the
  block itself rather than only in the HUD.
- **Brainrot characters** — built from unsmoothed primitives, flat colours off
  a per-rarity ramp. Mutations shift the ramp (gold, diamond, glitched) rather
  than adding gloss or particles-as-polish.
- **Hub, plots, and podiums** — concrete slabs and right angles.
- **UI** — square corners, hard 2px borders, flat fills, no drop shadows, no
  gradients. This **overrides** §6's "chunky rounded corners": panels are
  square. Keep the dark slate palette and the saturated per-rarity accent.
- **Effects** — stepped, not smooth. Particles are square. Tweens use discrete
  steps or snappy easing rather than long soft fades.

**Implementation note.** The mine's half of this lives in the `Palette*` and
`CrackDarken*` constants in `GameConfig.luau`, plus `material` / `baseColor` /
`topMaterial` / `topColor` per layer in `LayerConfig.luau`. Anything new that
renders should read from config the same way rather than hardcoding colours.

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
  id = "cappuccino_ore",
  displayName = "Cappuccino Shard",
  rarity = "Rare",              -- Common/Uncommon/Rare/Epic/Legendary/Mythic
  color = Color3.fromRGB(...),
  baseValue = 62,               -- coins per unit when sold raw
  hardness = 3,                 -- HP multiplier for the block
  weightPerUnit = 2,            -- backpack space consumed
  layers = { [3] = 40, [4] = 25 }, -- layerIndex -> spawn weight
  convertsTo = { "cappuccino_assassino", "ballerina_cappuccina" },
}

-- BrainrotConfig entry
{
  id = "cappuccino_assassino",
  displayName = "Cappuccino Assassino",
  rarity = "Uncommon",
  incomePerSecond = 7.8,
  sellValue = 608,
  mutations = { Normal = 1.0, Golden = 2.5, Diamond = 6.0, Glitched = 15.0 },
  modelBuilder = "buildCappuccinoAssassino", -- function name in ModelFactory
}
```

`convertsTo` holds **plain** character ids. Gold, Diamond and Glitched are
mutation tiers rolled separately, not separate characters — otherwise a golden
roll of a `_gold` variant would count gold twice.

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

Build all UI in code (no `.rbxmx` dependency), styled per §2a: dark slate panels, **square corners with hard 2px borders** (not rounded — §2a overrides this), flat fills with no gradients or drop shadows, a saturated accent per rarity, `GothamBold`-family fonts, and snappy stepped open/close rather than soft spring fades. Include:

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
