#!/bin/bash
#
# Bundle the local sidecars into the app's resources.
#
# THREE bundles, not one, because the three shapes are genuinely different: `chatSidecar`
# streams a tool-calling conversation, `oneShotSidecar` runs the non-streaming functions
# (enrichBrief, synthesizeBrief, generateRoadmap, runTask) that answer with one JSON body,
# and `vcSidecar` runs a multi-agent meeting that streams the virtual-company frame order.
# They share the prompt builders and the `claude -p` flags they import, not a process — and
# they fail independently, so a broken meeting cannot take onboarding down with it.
#
# WHY A BUNDLER AND NOT JUST `tsc`. Xcode's synchronized resource group FLATTENS what it
# copies — measured: `codepet/Resources/Fonts/*.ttf` land directly in
# `Contents/Resources/`. So a compiled tree loses its directory structure, and every
# `require("../companyChatCore")` loses its target. esbuild inlines the whole graph into
# ONE file, which is the only shape that survives that flattening. The sidecar re-invokes
# itself with `--mcp-server` for the same reason, rather than spawning a sibling.
#
# WHY THE OUTPUT IS GITIGNORED. It is build output. Committing it would mean a second copy
# of companyChatCore's prompt assembly living in the repo, silently going stale against the
# one the Cloud Function uses — the exact drift `buildChatRequest` was extracted to make
# impossible.
#
# A build that skips this step is not broken: `LocalChatStreamer.resolveSidecarPath`
# returns nil, the router reports `localUnavailable`, and the founder is told the local
# runner is missing rather than being quietly charged for a cloud turn.
#
# Run before archiving, and after any change under functions/src/.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
# `.jsbundle`, not `.js`, and that is load-bearing. Xcode classifies `.js` as SOURCE, so a
# target with no JavaScript compiler silently drops it — measured: the file built, landed in
# codepet/Resources/, and was simply absent from Contents/Resources/ afterwards, with no
# warning. An extension Xcode has no opinion about is copied as a resource instead. `node`
# does not care what the file is called.
OUT="$ROOT/codepet/Resources/chatSidecar.js"
OUT_ONESHOT="$ROOT/codepet/Resources/oneShotSidecar.js"
OUT_VC="$ROOT/codepet/Resources/vcSidecar.js"

echo "▸ typechecking functions/"
(cd functions && npx tsc --noEmit)

echo "▸ bundling the sidecars into self-contained files"
(cd functions && npx esbuild src/local/chatSidecar.ts \
  --bundle \
  --platform=node \
  --target=node20 \
  --format=cjs \
  --outfile="$OUT")
(cd functions && npx esbuild src/local/oneShotSidecar.ts \
  --bundle \
  --platform=node \
  --target=node20 \
  --format=cjs \
  --outfile="$OUT_ONESHOT")
(cd functions && npx esbuild src/local/vcSidecar.ts \
  --bundle \
  --platform=node \
  --target=node20 \
  --format=cjs \
  --outfile="$OUT_VC")

# Node 20 is what this machine has while functions/package.json declares 22 for the Cloud
# Functions runtime. The sidecar runs on the FOUNDER's node, not Google's, so it targets
# the lower of the two — a bundle emitting node-22 syntax would break on a founder still
# on 20.

echo "▸ verifying it runs, and that both modes are reachable"
node "$OUT" --mcp-server /dev/null </dev/null >/dev/null 2>&1 || true
printf '%s\n' '{"jsonrpc":"2.0","id":0,"method":"tools/list","params":{}}' \
  | node "$OUT" --mcp-server <(echo '[{"name":"navigate","description":"go","input_schema":{"type":"object"}}]') \
  | grep -q '"navigate"' \
  && echo "  ✓ server mode answers tools/list"

# The one-shot smoke check costs NO tokens on purpose: an unknown op is refused before any
# `claude` is spawned, so this proves the bundle loads and its registry answers without
# spending a turn of whoever is building.
printf '%s\n' '{"op":"nope","body":{}}' \
  | { node "$OUT_ONESHOT" || true; } \
  | grep -q '"unknown_op"' \
  && echo "  ✓ one-shot mode refuses an op it does not have"

echo "▸ done: $OUT"
echo "  $(wc -c < "$OUT" | tr -d ' ') bytes"
# Same zero-token check for the meeting: an invalid payload is refused by the shared
# validator before any agent is called.
printf '%s\n' '{"request":""}' \
  | { node "$OUT_VC" || true; } \
  | grep -q '"invalid_payload"' \
  && echo "  ✓ meeting mode refuses an invalid payload"

echo "▸ done: $OUT_ONESHOT"
echo "  $(wc -c < "$OUT_ONESHOT" | tr -d ' ') bytes"
echo "▸ done: $OUT_VC"
echo "  $(wc -c < "$OUT_VC" | tr -d ' ') bytes"
