#!/usr/bin/env bash
# Checks that the scripts refuse and isolate what they should. Needs Docker
# only for the preflight (a stand-in `docker` records the calls; no
# container is started), so it takes a few seconds.
#
#   bin/check-safety.sh
#
# Exit codes: 0 every check passed, 1 at least one failed.

set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

passed=0
failed=0
ok()  { passed=$((passed + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /' | head -20; }

# A `docker` that records every call and starts nothing.
shim="$scratch/shim"; mkdir -p "$shim"
cat > "$shim/docker" <<'SH'
#!/bin/sh
echo "$@" >> "$DOCKER_LOG"
exit 0
SH
chmod +x "$shim/docker"

# copy_repo <dir>: a copy of the repository with the scripts and a vendor/
# stub that satisfies the preflight; nothing from vendor/ is used.
copy_repo() {
    mkdir -p "$1"
    cp -R "$here/bin" "$here/legacy" "$here/upgraded" "$here/steps" "$here/rector.php" "$1/"
    mkdir -p "$1/vendor/bin"; : > "$1/vendor/bin/phpstan"; : > "$1/vendor/bin/rector"
}

out="$("$here/bin/gates.sh" 2>&1)"; st=$?
[ "$st" -eq 2 ] && ok "gates.sh with no argument exits 2" || bad "gates.sh with no argument exits 2" "exit $st: $out"

copy_repo "$scratch/novendor"; rm -rf "$scratch/novendor/vendor"
out="$(PATH="$shim:$PATH" DOCKER_LOG="$scratch/log0" "$scratch/novendor/bin/gates.sh" upgraded 2>&1)"; st=$?
[ "$st" -eq 2 ] && printf '%s\n' "$out" | grep -q "composer install" \
    && ok "gates.sh without vendor/ stops and says to run composer install" \
    || bad "gates.sh without vendor/" "exit $st: $out"

# Every container the scripts start must have no network.
no_network() { # <log file>: true only if the log has run calls and each has --network none
    grep -q '^run ' "$1" && ! grep '^run ' "$1" | grep -vq -- '--network none'
}
copy_repo "$scratch/gates"
PATH="$shim:$PATH" DOCKER_LOG="$scratch/log1" "$scratch/gates/bin/gates.sh" upgraded >/dev/null 2>&1
no_network "$scratch/log1" && ok "gates.sh starts every container with --network none ($(grep -c '^run ' "$scratch/log1") containers)" \
    || bad "gates.sh containers without --network none" "$(grep '^run ' "$scratch/log1" | grep -v -- '--network none')"
! grep '^run ' "$scratch/log1" | grep -vq -- ':/work/src:ro' \
    && ok "gates.sh mounts the tree under test read-only in every container" \
    || bad "gates.sh tree mount is not read-only"

# Sabotage: the same assertion must fail when the flag is missing.
copy_repo "$scratch/sabotaged"
sed -i.bak 's/docker run --rm --network none/docker run --rm/' "$scratch/sabotaged/bin/gates.sh"
PATH="$shim:$PATH" DOCKER_LOG="$scratch/log2" "$scratch/sabotaged/bin/gates.sh" upgraded >/dev/null 2>&1
no_network "$scratch/log2" && bad "the network check accepted a gates.sh without --network none" \
    || ok "the network check rejects a gates.sh without --network none"

# reproduce.sh must not delete a build/ it did not create.
copy_repo "$scratch/repro"; mkdir "$scratch/repro/build"; echo precious > "$scratch/repro/build/mine.txt"
out="$(PATH="$shim:$PATH" DOCKER_LOG="$scratch/log3" "$scratch/repro/bin/reproduce.sh" 2>&1)"; st=$?
[ "$st" -eq 2 ] && [ "$(cat "$scratch/repro/build/mine.txt")" = precious ] && printf '%s\n' "$out" | grep -q "was not created by this script" \
    && ok "reproduce.sh refuses a build/ it did not create and leaves it alone" \
    || bad "reproduce.sh foreign build/" "exit $st: $out"

# And it starts Rector with no network, the repository read-only except build/.
rm -rf "$scratch/repro/build"
PATH="$shim:$PATH" DOCKER_LOG="$scratch/log4" "$scratch/repro/bin/reproduce.sh" >/dev/null 2>&1
line="$(grep '^run ' "$scratch/log4" | head -n 1)"
case "$line" in
    *"--network none"*":/work:ro"*"/build:/work/build"*) ok "reproduce.sh runs Rector with no network, repository read-only except build/" ;;
    *) bad "reproduce.sh Rector container" "$line" ;;
esac

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
