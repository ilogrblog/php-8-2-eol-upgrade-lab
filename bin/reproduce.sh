#!/usr/bin/env bash
# Rebuilds the upgrade from the legacy tree and checks it matches upgraded/.
#
#   1. copy legacy/ to build/
#   2. run Rector with rector.php (needs `composer install`)
#   3. compare the result with steps/01-rector.diff
#   4. apply steps/02-requires-php.diff (the human decision)
#   5. apply steps/03-agent-accepted.diff (the saved agent proposal)
#   6. compare build/ with upgraded/, then run every gate on it
#
# No AI account is needed: step 5 replays a saved proposal.
#
# This script deletes and recreates build/ inside this folder, and Rector
# rewrites the files in it. It touches nothing else. It refuses to run if
# build/ exists and was not created by this script, so it cannot delete a
# folder of yours. Rector runs in a container with no network.
#
# Exit codes: 0 reproduced and all gates passed, 1 reproduction failed,
# 2 environment error (no Docker, no composer install, foreign build/).

set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
marker=.lab-build   # created inside build/ by this script

if ! command -v docker >/dev/null 2>&1; then
    echo "error: Docker is required but was not found" >&2
    exit 2
fi
if ! docker info >/dev/null 2>&1; then
    echo "error: Docker is installed but not running" >&2
    exit 2
fi
if [ ! -e vendor/bin/rector ]; then
    echo "error: Rector is missing; run 'composer install' in $here first" >&2
    exit 2
fi
if [ -e build ] && [ ! -f "build/$marker" ]; then
    echo "error: $here/build exists and was not created by this script; move it away first" >&2
    exit 2
fi

echo "WARNING: recreating $here/build and running Rector on it (lab copy only; nothing else is changed)"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

rm -rf build
cp -R legacy build
: > "build/$marker"
docker run --rm --network none --user "$(id -u):$(id -g)" \
    -v "$here":/work:ro -v "$here/build":/work/build -w /work php:8.5-cli \
    php vendor/bin/rector process --config rector.php --no-progress-bar --no-diffs

cp -R legacy "$scratch/a"
cp -R build "$scratch/b"
rm -f "$scratch/b/$marker"
(cd "$scratch" && git diff --no-index --no-prefix a b > rector.diff) || true
if ! cmp -s "$scratch/rector.diff" steps/01-rector.diff; then
    echo "FAIL Rector output differs from steps/01-rector.diff"
    diff "$scratch/rector.diff" steps/01-rector.diff || true
    exit 1
fi
echo "PASS Rector output matches steps/01-rector.diff"

(cd build && patch -p1 --silent < ../steps/02-requires-php.diff)
(cd build && patch -p1 --silent < ../steps/03-agent-accepted.diff)
if ! diff -r -x "$marker" build upgraded > /dev/null; then
    echo "FAIL build/ differs from upgraded/"
    diff -r -x "$marker" build upgraded || true
    exit 1
fi
echo "PASS build/ is identical to upgraded/"

bin/gates.sh build
