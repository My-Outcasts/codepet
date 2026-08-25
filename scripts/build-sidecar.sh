#!/bin/bash
#
# Bundle the local chat sidecar into the app's resources.
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

echo "▸ typechecking functions/"
(cd functions && npx tsc --noEmit)

echo "▸ bundling the sidecar into one self-contained file"
(cd functions && npx esbuild src/local/chatSidecar.ts \
  --bundle \
  --platform=node \
  --target=node20 \
  --format=cjs \
  --outfile="$OUT")

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

echo "▸ done: $OUT"
echo "  $(wc -c < "$OUT" | tr -d ' ') bytes"
