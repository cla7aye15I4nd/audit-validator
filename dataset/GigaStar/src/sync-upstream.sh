#!/usr/bin/env bash
set -euo pipefail
set -x

# Upstream info to sync
REPO=gs
URL=git@github.com:gigastario/$REPO.git
BRANCH=main
DIR=bd/bc-contract

echo "fetching upstream changes"
git remote add $REPO $URL
git fetch $REPO $BRANCH

echo "replacing local"
rm -rf $DIR
git archive --format=tar $REPO/$BRANCH $DIR | tar -x
git add -A -- $DIR

echo "safety check"
git diff --cached --name-only | grep -v "^$DIR/" && echo "ERROR: unexpected changes staged" && exit 1 || true

echo "cleanup upstream"
REV=$(git rev-parse --short $REPO/$BRANCH)
git remote remove $REPO

echo "comitting changes with upstream provenance"
git commit -m "Sync $DIR from $REPO/$BRANCH rev: $REV"
git push origin main

echo "done"
