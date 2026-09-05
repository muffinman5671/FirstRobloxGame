#!/usr/bin/env bash
# Regenerates the local analysis inputs. Run once per machine, and again after a
# Roblox release if new API shows up as an unknown type.
#
#   rojo sourcemap  -- teaches luau-lsp the instance tree, so a require of
#                      game.ReplicatedStorage.Shared.X resolves instead of
#                      reporting "unknown require". Without it analyze emits
#                      hundreds of false positives and is useless.
#   globalTypes     -- Roblox API surface for the type checker.
#   roblox.yml      -- selene's standard library.
set -euo pipefail
cd "$(dirname "$0")/.."

rojo sourcemap default.project.json --output sourcemap.json
curl -sL -o .tooling/globalTypes.d.luau \
  https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
curl -sL -o .tooling/api-docs.json \
  https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/api-docs/en-us.json
selene generate-roblox-std
echo "refreshed."
