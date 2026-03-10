#!/usr/bin/env bash
set -euo pipefail

source "./script/base.sh" # Setup log funcs, OS, etc

# Setup output dir
OUT_DIR=../doc/gen-sol
log "Cleaning output dir"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
log "This dir is generated from 'gen-sol-doc.sh'. Any files added may be lost" > "$OUT_DIR/README.md"

# This runs the first time to generate the SUMMARY.md file but it may awkwardly causes 2 out dirs
log "Generating Markdown..."
forge doc --out "$OUT_DIR"

log "Creating SUMMARY.md..."
cd "$OUT_DIR/src"
find contract -type f -name 'contract.*.md' | sort \
  | sed -E 's|contract/(v1_0/.*/)?contract\.([^/]+)\.md|- [\2](contract/\1contract.\2.md)|' \
  | awk 'BEGIN { print "# Summary\n" } { print }' > SUMMARY.md
cd -

# Run HTTP server to browse HTML docs and open default browser
log "Running HTTP server to browse HTML docs..."
forge doc --out "$OUT_DIR" --serve --open --port 4000

# Cleanup docs
rm -rf ../doc/gen-sol/
