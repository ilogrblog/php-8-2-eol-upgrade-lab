#!/usr/bin/env bash
# Runs every gate against one tree of the fixture.
#
#   bin/gates.sh legacy
#   bin/gates.sh upgraded
#
# Gates, in order:
#   lint-declared   php -l on each WordPress plugin under its "Requires PHP";
#                   a plugin entry file with no valid header fails this gate
#   lint-8.x        php -l on every file under each PHP version (newer syntax)
#   tests-8.x       tests/supervise.php under each PHP version, which runs
#                   tests/run.php and judges its whole output after it ends
#   phpstan-floor   PHPStan with phpVersion 8.2 to 8.5, run on PHP 8.2 so it
#                   also sees constants that 8.2 does not define
#   phpstan-target  PHPStan with phpVersion 8.5, run on PHP 8.5 (deprecations,
#                   new type errors)
#
# Every gate runs even after one fails, so the report is complete.
# Exit codes: 0 all gates passed, 1 at least one gate failed, 2 usage or
# environment error (no argument, no Docker, no composer install).
# Needs Docker and `composer install` (for PHPStan). Override the versions
# with PHP_VERSIONS="8.3 8.4" if your platform needs a different range.
#
# Safe to run on a copy of your code: the tree is mounted read-only into
# containers that have no network, and nothing is written to it.

set -u

here="$(cd "$(dirname "$0")/.." && pwd)"
if [ $# -ne 1 ] || [ ! -d "$1" ]; then
    echo "usage: bin/gates.sh <tree>" >&2
    exit 2
fi
tree="$(cd "$1" && pwd)"
if ! command -v docker >/dev/null 2>&1; then
    echo "error: Docker is required but was not found" >&2
    exit 2
fi
if ! docker info >/dev/null 2>&1; then
    echo "error: Docker is installed but not running" >&2
    exit 2
fi
if [ ! -e "$here/vendor/bin/phpstan" ]; then
    echo "error: PHPStan is missing; run 'composer install' in $here first" >&2
    exit 2
fi
versions="${PHP_VERSIONS:-8.2 8.3 8.4 8.5}"
floor="${versions%% *}"
target="${versions##* }"
# The next four are overridden only by bin/check.sh, to prove each matters.
tests_dir="${TESTS_DIR:-$here/tests}"
phpstan_dir="${PHPSTAN_DIR:-$here/phpstan}"
test_entry="${TEST_ENTRY:-tests/supervise.php}"
floor_runtime="${FLOOR_RUNTIME:-$floor}"
failed=0

run() { # image, then the command to run inside /work
    local image="$1"; shift
    docker run --rm --network none \
        -v "$tree":/work/src:ro \
        -v "$tests_dir":/work/tests:ro \
        -v "$phpstan_dir":/work/phpstan:ro \
        -v "$here/vendor":/work/vendor:ro \
        -w /work "php:$image-cli" "$@"
}

report() { # gate name, exit status, output
    if [ "$2" -eq 0 ]; then
        echo "PASS $1"
    else
        echo "FAIL $1"
        printf '%s\n' "$3" | grep -E 'Parse error|FAIL|DEPRECATED|Requires PHP|:[0-9]+:' | awk '!seen[$0]++' | sed 's/^/     /' | head -20
        failed=1
    fi
}

# A WordPress plugin promises to run on the version in its "Requires PHP"
# header, which can be older than any server you run. Lint it there too.
# Entry files are the PHP files directly inside a plugin directory that
# carry a "Plugin Name:" header. Every plugin directory must have one, and
# each entry file must declare Requires PHP as 7.4, 8.2 or 8.2.0 style.
for dir in "$tree"/wordpress/*/; do
    [ -d "$dir" ] || continue
    plugin="$(basename "$dir")"
    entries=()
    for f in "$dir"*.php; do
        [ -f "$f" ] && grep -q '^[[:space:]/*#]*Plugin Name:' "$f" && entries+=("$f")
    done
    if [ "${#entries[@]}" -eq 0 ]; then
        report "lint-declared ($plugin)" 1 "FAIL no plugin entry file: no PHP file in $plugin/ has a Plugin Name header"
        continue
    fi
    for main in "${entries[@]}"; do
        rel="${main#"$tree"/}"
        declared="$(sed -n 's/^[[:space:]/*#]*Requires PHP:[[:space:]]*//p' "$main" | head -n 1 | tr -d '[:space:]')"
        if [ -z "$declared" ]; then
            report "lint-declared ($plugin)" 1 "FAIL missing Requires PHP header in $rel"
            continue
        fi
        if ! printf '%s' "$declared" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
            report "lint-declared ($plugin)" 1 "FAIL malformed Requires PHP header in $rel: $declared"
            continue
        fi
        image="$(printf '%s' "$declared" | cut -d. -f1,2)"
        out="$(run "$image" sh -c 'status=0; for f in $(find "src/wordpress/'"$plugin"'" -name "*.php" | sort); do php -l "$f" >/tmp/lint 2>&1 || { cat /tmp/lint; status=1; }; done; exit $status' 2>&1)"
        report "lint-declared-$declared ($plugin)" $? "$out"
    done
done

for v in $versions; do
    out="$(run "$v" sh -c 'status=0; for f in $(find src -name "*.php" | sort); do php -l "$f" >/tmp/lint 2>&1 || { cat /tmp/lint; status=1; }; done; exit $status' 2>&1)"
    report "lint-$v" $? "$out"
done

for v in $versions; do
    out="$(run "$v" php "$test_entry" src 2>&1)"
    report "tests-$v" $? "$out"
done

for gate in "floor $floor_runtime" "target $target"; do
    read -r name runtime <<< "$gate"
    out="$(run "$runtime" php -d memory_limit=1G vendor/bin/phpstan analyse -c "phpstan/$name.neon" \
        --no-progress --error-format=raw src 2>&1)"
    report "phpstan-$name" $? "$out"
done

if [ "$failed" -eq 0 ]; then
    echo "ALL GATES PASSED for $1"
else
    echo "GATES FAILED for $1"
fi
exit "$failed"
