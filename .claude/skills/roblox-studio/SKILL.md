---
name: roblox-studio
description: Workflow, verification and rendering gotchas for this Roblox project (Rojo + Studio MCP). Use whenever editing Luau under src/, driving the Roblox_Studio MCP tools, building or changing hub/mine geometry, or taking Studio screenshots. Covers checking Luau before it reaches Studio, the Edit-mode require cache, the screen_capture camera trap, and the material/colour and tiling traps that have each cost a rebuild.
---

# Roblox Studio workflow

Hard-won on this repo. Each item below cost at least one wasted rebuild.

## Check Luau before it reaches Studio

There is no runtime feedback loop until code is synced *and* something forces a
fresh `require`. Run this first, every time:

```bash
.tooling/check.sh
```

It runs `luau-lsp analyze`, `selene` and `stylua --check`. On a fresh machine run
`.tooling/refresh.sh` once to fetch the type definitions and standard library.

**`analyze` is worthless without `--sourcemap`.** Without it, every
`require(game.ReplicatedStorage.Shared.X)` reports `Unknown require` and the real
findings drown in hundreds of false positives. `rojo sourcemap` builds it;
`check.sh` regenerates it each run because it goes stale when files move.

## Rojo

- `rojo serve default.project.json --port 34872`. Does not persist — restart it
  every session.
- **After any Rojo restart, Studio needs a manual Disconnect → Connect.** You
  cannot do this from a tool; ask.
- Rojo 7.7.0 crashes on rapid successive writes to one file. Assemble the whole
  new file and write it **once** rather than making several small edits.

## Edit-mode `require` caches by instance

Editing a ModuleScript's source does **not** affect an already-required copy, so
a synced change appears to do nothing and a naive check passes on stale code.

To verify a change for real without a Play cycle, clone the modules under `_T`
names, string-patch their `require` paths to point at each other, require the
clone, then destroy the clones:

```lua
local cfgClone = RS.Shared.Config.GameConfig:Clone()
cfgClone.Name = "GameConfig_T"; cfgClone.Parent = RS

local mineClone = Services.MineService:Clone()
mineClone.Name = "MineService_T"
mineClone.Source = mineClone.Source
    :gsub("require%(ReplicatedStorage%.Shared%.Config%.GameConfig%)",
          'require(game:GetService("ReplicatedStorage").GameConfig_T)')
    :gsub("script%.Parent%.PlotService", "script.Parent.PlotService_T")
mineClone.Parent = Services

require(mineClone).buildPreview()
```

Clone every module you changed - a clone that requires a *stale* dependency still
reads the old values. Always destroy the clones afterwards.

**Sweep leftovers first.** A probe that errors before its cleanup line leaves its
`_T` clone parented, and a name lookup returns the FIRST match - so the next run
silently requires the *old* source and fails somewhere unrelated. This cost an
hour: a crashed probe left a `GameConfig_T` from before some new keys existed,
and every later build died on `attempt to perform arithmetic (add) on number and
nil` deep inside a module that was itself perfectly correct. Start every
clone-based run with:

```lua
for _, root in { ReplicatedStorage, ServerScriptService } do
    for _, d in root:GetDescendants() do
        if d.Name:match("_T$") then d:Destroy() end
    end
end
```

The same trap applies to requiring the *real* module in a probe: if it was
required earlier in the Studio session, you get the cached copy from before your
edits. Read config through a fresh clone even for a read-only check.

## Seeing the surface without pressing Play

```lua
require(game.ServerScriptService.Server.Services.MineService).buildPreview()
```

Builds hub floor, wall, plaza, shops, **lawn decoration, the plot shells and the
leaderboard cabinets** into `Workspace.HubPreview`; `.clearPreview()` removes it.
`Start()` clears a stale one first. Surface only - the mine streams around a
character that does not exist in Edit, so mine blocks are never in the preview.

A **SurfaceGui parented to a Part in Workspace does render in the Edit viewport**,
unlike a ScreenGui in CoreGui - so the leaderboards can be read without pressing
Play. The preview fills them with placeholder ranks, because DataStores are not
reachable from Edit and an empty board shows nothing about the layout.

## screen_capture

- **Passing `camera_position`/`look_at_position` times out every time.** Set the
  camera from Luau instead, then call `screen_capture` with no arguments.
- Setting `CurrentCamera.CFrame` alone keeps the **position** but Studio
  overrides the look direction — every shot ends up aimed at sky. Set
  `cam.Focus` as well and it sticks exactly:

```lua
cam.CFrame = CFrame.lookAt(pos, target, Vector3.new(0, 1, 0))
cam.Focus = CFrame.new(target)
```

- Wide shots still time out sometimes. Retry once before concluding anything.
- `start_stop_play` is unreliable, and "Game Stopped" can be a lie — check
  `get_studio_state` before assuming you are back in Edit.

## A backgrounded Studio does not render, and that breaks two things

If the Studio window is not in the foreground it stops rendering, and **every
render-phase callback stops with it**. Measured in a Play session:

```
over 1s -- RenderStepped=0  Stepped=61  Heartbeat=61
```

So `RenderStepped` and `BindToRenderStep` never fire, while `Stepped` and
`Heartbeat` run normally at 60 Hz. Anything driven from the render phase —
MiningController's targeting loop, SwingAnimator's pose — is simply inert, and
it looks exactly like a bug in the code rather than in the harness. `screen_capture`
times out in the same state, so there is no visual fallback either.

Check it before concluding a render-bound feature is broken, and verify the
logic another way: **writing `Motor6D.Transform` from a `Stepped` connection does
pose the rig**, so a render-bound animation can be held at a fixed pose from
`Stepped` and measured numerically. Ask for the window to be foregrounded if the
animation itself has to be watched.

## Colour and material

- `Enum.Material.Ground` drains part colour to grey. A correctly brown wall
  rendered as slate until it was switched to `SmoothPlastic`. Check a material
  against a screenshot before trusting `.Color`.
- `cartoonify` multiplies saturation by **1.62** and value by 1.2, so a colour
  picked to look right on its own comes out orange. Mine block bodies are
  `SmoothPlastic` (GameConfig.MineBlockMaterial) for the same reason the wall is:
  a grained material is shaded for realism, which is the grey-ward drag
  `cartoonify` exists to undo, and the material wins.
- Faces pointing away from the sun get `SurfaceAmbient`, a blue-grey, which
  drains a gentle brown to mauve. **Tune colours against a lit screenshot, not on
  paper.**
- `Lighting.Ambient` in `default.project.json` is the surface value, so Edit mode
  matches runtime. `AtmosphereController` only applies per-layer ambient at
  runtime.

## Tiling: never clamp the last column

Stepping a fixed pitch across a span and clamping the final row/column leaves a
sliver tile down two edges of every rectangle. This shipped three times — wall
face, hub floor, path — and is visible as a broken pattern at every corner.

Divide the span instead, so every tile in a rectangle is identical:

```lua
local columns = math.max(1, math.round(length / pitch))
local step = length / columns
```

The edges still land exactly where asked, which was the reason for clamping.
Anything else laid on the same grid (pilasters) must take **whole columns**, or
it cuts tiles in half and leaves slivers down its sides.

## Rules that must not be undone

- **No textures, meshes or sounds anywhere** — each needs a Roblox asset ID and
  this project hardcodes none. "Less blocky" therefore means *more* geometry, not
  smoother geometry (DESIGN.md 2a).
- Detail comes from small blocks at varying shades, per the mine's own approach.
