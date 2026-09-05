#!/usr/bin/env bash
# Pre-sync check. Run before letting Rojo push to Studio: Edit-mode require
# caching means a broken module sits there looking fine until something forces a
# fresh require, so a syntax error can survive a sync and a naive smoke test.
#
# GATES on syntax only -- luau-lsp's parser and selene's, which currently report
# zero between them. That is the failure this catches and nothing else can.
#
# Everything else is advisory and printed with --all:
#   * ~690 luau-lsp TypeErrors. The source is nonstrict Luau with inferred
#     types, so these are the type checker wanting annotations, not defects.
#     Gating on them would mean a typing project first.
#   * ~51 selene warnings, plus one intentional if_same_then_else in
#     MiningController (mouse and touch branches do the same thing under
#     different conditions).
#   * stylua differs throughout; the source was hand-formatted and predates it.
#     Adopting stylua is a deliberate one-off commit.
set -uo pipefail
cd "$(dirname "$0")/.."

rojo sourcemap default.project.json --output sourcemap.json >/dev/null

out=$(luau-lsp analyze --sourcemap=sourcemap.json \
        --definitions=.tooling/globalTypes.d.luau --no-strict-dm-types src 2>&1)
syntax=$(printf '%s\n' "$out" | grep -c 'SyntaxError:' || true)
types=$(printf '%s\n' "$out" | grep -c 'TypeError:' || true)
parse=$(selene src 2>&1 | awk '/parse errors/ { print $1; exit }')
parse=${parse:-0}

echo "syntax errors : $syntax   (gating)"
echo "parse errors  : $parse   (gating)"
echo "type errors   : $types   (advisory baseline)"

if [ "$syntax" -ne 0 ]; then
  printf '%s\n' "$out" | grep 'SyntaxError:'
fi

if [ "${1:-}" = "--all" ]; then
  echo; echo "── luau-lsp type findings (first 40) ──"
  printf '%s\n' "$out" | grep 'TypeError:' | head -40
  echo; echo "── selene ──"; selene src || true
fi

if [ "$syntax" -eq 0 ] && [ "$parse" -eq 0 ]; then
  echo "OK"
  exit 0
fi
exit 1
