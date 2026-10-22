#!/usr/bin/env bash
# Deterministic checks for the worked example. Each check states what a
# gate must do and fails if it does not. Most checks change one thing on a
# scratch copy (put one deprecated line back, or apply one saved agent
# proposal) and require a named gate to catch it, so a gate that stopped
# working would show up here.
#
#   bin/check.sh
#
# Needs Docker and `composer install`. Takes a few minutes.
# Exit codes: 0 every check passed, 1 at least one failed.

set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here" || exit 1
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

passed=0
failed=0
ok()  { passed=$((passed + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /' | head -30; }

# gates <tree> [env...]: runs bin/gates.sh, sets $out and $st
gates() { local tree="$1"; shift; out="$(env "$@" bin/gates.sh "$tree" 2>&1)"; st=$?; }

# expect <name> <exit> <line>...: each line must appear exactly in $out
expect() {
    local name="$1" want="$2"; shift 2
    local missing=""
    [ "$st" -eq "$want" ] || missing="exit $st, wanted $want"
    for line in "$@"; do
        printf '%s\n' "$out" | grep -qxF -- "$line" || missing="$missing
missing: $line"
    done
    if [ -z "$missing" ]; then ok "$name"; else bad "$name" "$missing
$out"; fi
}

# tree_from <name> <step diffs...>: legacy/ plus the given diffs, in order
tree_from() {
    local dir="$scratch/$1"; shift
    rm -rf "$dir"; cp -R legacy "$dir"
    for d in "$@"; do (cd "$dir" && patch -p1 --silent < "$here/$d") || return 1; done
    echo "$dir"
}

# mutate <tree> <file> <perl expression>: the edit must change the file
mutate() {
    local file="$1/$2"; cp "$file" "$file.orig"
    perl -0pi -e "$3" "$file"
    if cmp -s "$file" "$file.orig"; then rm "$file.orig"; return 1; fi
    rm "$file.orig"
}

rector() { # <runtime version> <config> <tree dir>: runs Rector on <tree dir>/build
    docker run --rm --network none -v "$here/vendor":/v:ro -v "$3":/w -w /w "php:$1-cli" \
        php /v/bin/rector process --config "$2" --no-progress-bar --no-diffs >/dev/null 2>&1
}

echo "== Starting points"

gates legacy
expect "legacy fails on 8.3 to 8.5 and passes on 8.2" 1 \
    "PASS lint-declared-7.4 (low-stock-notifier)" "PASS lint-8.2" "PASS lint-8.5" \
    "PASS tests-8.2" "FAIL tests-8.3" "FAIL tests-8.4" "FAIL tests-8.5" \
    "PASS phpstan-floor" "FAIL phpstan-target"

counts=""
for v in 8.2 8.3 8.4 8.5; do
    n="$(docker run --rm --network none -v "$here":/w -w /w "php:$v-cli" php tests/supervise.php legacy | sed -n 's/.* \([0-9]*\) distinct deprecations.*/\1/p')"
    counts="$counts $n"
done
[ "$counts" = " 0 1 8 14" ] && ok "legacy deprecations per version are 0, 1, 8, 14" \
    || bad "legacy deprecations per version" "got:$counts"

gates upgraded
expect "upgraded passes every gate" 0 "ALL GATES PASSED for upgraded"

spaced="$scratch/path with spaces"; cp -R upgraded "$spaced"
gates "$spaced"
expect "upgraded/ at a path containing spaces passes every gate" 0 \
    "PASS lint-declared-8.2 (low-stock-notifier)" "ALL GATES PASSED for $spaced"

echo "== Reproduction"

out="$(bin/reproduce.sh 2>&1)"; st=$?
expect "bin/reproduce.sh rebuilds upgraded/ from legacy/ and passes" 0 \
    "PASS Rector output matches steps/01-rector.diff" "PASS build/ is identical to upgraded/" \
    "ALL GATES PASSED for build"

for v in 8.2 8.5; do
    dir="$scratch/rector-$v"; mkdir -p "$dir"; cp -R legacy "$dir/build"; cp rector.php "$dir/"
    rector "$v" rector.php "$dir"
    if diff -r "$dir/build" "$(tree_from after01 steps/01-rector.diff)" >/dev/null; then
        ok "rector.php gives the same output when Rector runs on PHP $v"
    else
        bad "rector.php output on PHP $v differs from steps/01-rector.diff"
    fi
done

for v in 8.2 8.5; do
    dir="$scratch/naive-$v"; mkdir -p "$dir"; cp -R legacy "$dir/build"; cp rector-naive.php "$dir/"
    rector "$v" rector-naive.php "$dir"
done
if grep -q 'new LSN_Mail_Logger()->log' "$scratch/naive-8.5/build/wordpress/low-stock-notifier/low-stock-notifier.php" \
   && ! grep -q '?LSN_Settings' "$scratch/naive-8.2/build/wordpress/low-stock-notifier/includes/class-lsn-threshold.php"; then
    ok "rector-naive.php output depends on the PHP that runs Rector (8.4 syntax on 8.5, no nullable fix on 8.2)"
else
    bad "rector-naive.php runtime dependence not reproduced"
fi
gates "$scratch/naive-8.5/build"
expect "rector-naive.php output made on PHP 8.5 fails lint on 8.2 and 8.3, and PHPStan sees a dropped type" 1 \
    "FAIL lint-8.2" "FAIL lint-8.3" "PASS lint-8.4" "PASS lint-8.5" "FAIL phpstan-target" \
    "     /work/src/magento/app/code/Example/StockFeed/Model/FeedParser.php:13:Method Example\\StockFeed\\Model\\FeedParser::__construct() has parameter \$logger with no type specified."

echo "== Saved agent proposals"

base="$(tree_from base steps/01-rector.diff steps/02-requires-php.diff)"
for run in agent/runs/after-rector-*/ agent/runs/legacy-only-*/; do
    name="$(basename "$run")"
    case "$name" in
        after-rector-*) tree="$scratch/p-$name"; rm -rf "$tree"; cp -R "$base" "$tree" ;;
        *)              tree="$scratch/p-$name"; rm -rf "$tree"; cp -R legacy "$tree" ;;
    esac
    (cd "$tree" && patch -p1 --silent < "$here/$run/proposal.diff")
    gates "$tree"
    case "$name" in
        after-rector-haiku-1)
            expect "$name (exit() instead of an exception) is refused by every test gate" 1 \
                "FAIL tests-8.2" "FAIL tests-8.5" \
                "     FAIL supervisor: the test process ended before reporting every result" ;;
        after-rector-haiku-2)
            expect "$name (defined('E_STRICT') guard) is refused on 8.4, 8.5 and by PHPStan" 1 \
                "PASS tests-8.3" "FAIL tests-8.4" "FAIL tests-8.5" "FAIL phpstan-target" ;;
        legacy-only-haiku-1)
            expect "$name (static::class) is refused on every version" 1 \
                "FAIL tests-8.2" "FAIL tests-8.5" "     FAIL wp: subclass logs to the base channel" ;;
        legacy-only-haiku-2)
            expect "$name (get_class(\$this) and exit()) is refused on every version" 1 \
                "FAIL tests-8.2" "     FAIL wp: subclass logs to the base channel" \
                "     FAIL supervisor: the test process ended before reporting every result" ;;
        *)
            expect "$name passes every gate" 0 "ALL GATES PASSED for $tree" ;;
    esac
done

echo "== Each fix reverted on a copy of upgraded/ must be caught"

revert() { # <name> <file> <perl expression> <expected lines...>
    local name="$1" file="$2" expr="$3"; shift 3
    local tree="$scratch/revert"; rm -rf "$tree"; cp -R upgraded "$tree"
    if ! mutate "$tree" "$file" "$expr"; then bad "$name (the edit changed nothing)"; return; fi
    gates "$tree"
    expect "$name" 1 "$@"
}
wp=wordpress/low-stock-notifier
mg=magento/app/code/Example/StockFeed

revert "get_class() restored: caught on 8.3 and later" "$wp/includes/class-lsn-logger.php" \
    's/strtolower\(self::class\)/strtolower(get_class())/' "PASS tests-8.2" "FAIL tests-8.3"
revert "self::class changed to static::class: caught on every version" "$wp/includes/class-lsn-logger.php" \
    's/self::class/static::class/' "FAIL tests-8.2" "     FAIL wp: subclass logs to the base channel"
revert "implicit nullable restored: caught on 8.4 and by PHPStan" "$wp/includes/class-lsn-threshold.php" \
    's/\?LSN_Settings \$settings = null/LSN_Settings \$settings = null/' "PASS tests-8.3" "FAIL tests-8.4" "FAIL phpstan-target"
revert "fputcsv escape argument removed: caught on 8.4" "$wp/includes/class-lsn-report.php" \
    "s/, escape: '\\\\\\\\'\\)/)/" "PASS tests-8.3" "FAIL tests-8.4"
revert "str_getcsv escape set to '': caught on every version" "$mg/Model/FeedParser.php" \
    "s/escape: '\\\\\\\\'/escape: ''/" "FAIL tests-8.2" "     FAIL magento: feed parser keeps backslash-escaped quotes"
revert "E_STRICT restored: caught on 8.4 and by PHPStan" "$wp/includes/class-lsn-logger.php" \
    "s/(E_NOTICE     => 'notice',\\n)/\$1        E_STRICT     => 'strict',\\n/" "PASS tests-8.3" "FAIL tests-8.4" "FAIL phpstan-target"
revert "E_USER_ERROR restored: caught on 8.4" "$wp/low-stock-notifier.php" \
    "s/throw new RuntimeException\\(('[^']*')\\);/trigger_error(\$1, E_USER_ERROR);/" "PASS tests-8.3" "FAIL tests-8.4"
revert "exit() instead of the exception: caught on every version" "$wp/low-stock-notifier.php" \
    "s/throw new RuntimeException\\(('[^']*')\\);/exit(\$1);/" "FAIL tests-8.2" \
    "     FAIL supervisor: the test process ended before reporting every result"
revert "null category restored: caught on 8.5" "$wp/includes/class-lsn-report.php" \
    "s/\\\$product\\['category'\\] : '';/\\\$product['category'] : null;/" "PASS tests-8.4" "FAIL tests-8.5"
revert "(integer) cast restored: caught on 8.5 and by PHPStan" "$wp/includes/class-lsn-threshold.php" \
    's/\(int\) \$raw/(integer) \$raw/' "PASS tests-8.4" "FAIL tests-8.5" "FAIL phpstan-target"
revert "finfo_close() restored: caught on 8.5 and by PHPStan" "$mg/Model/MimeGuard.php" \
    's/(\$type = finfo_buffer\(\$finfo, \$contents\);\n)/$1        finfo_close(\$finfo);\n/' "PASS tests-8.4" "FAIL tests-8.5" "FAIL phpstan-target"
revert "setAccessible() restored: caught on 8.5 and by PHPStan" "$mg/Model/SupplierClient.php" \
    's/(\$property = new \\ReflectionProperty\(Connection::class, .lastFeedAt.\);\n)/$1        \$property->setAccessible(true);\n/' \
    "PASS tests-8.4" "FAIL tests-8.5" "FAIL phpstan-target"
revert "Requires PHP back to 7.4: caught by the declared-version lint" "$wp/low-stock-notifier.php" \
    's/Requires PHP: 8\.2/Requires PHP: 7.4/' "FAIL lint-declared-7.4 (low-stock-notifier)" "PASS lint-8.2"
revert "PHP 8.4 syntax (new without brackets): caught by lint on 8.2 and 8.3" "$wp/low-stock-notifier.php" \
    's/\(new LSN_Mail_Logger\(\)\)->log/new LSN_Mail_Logger()->log/' "FAIL lint-8.2" "FAIL lint-8.3" "PASS lint-8.4"
revert "PHP 8.5 function on an untested path: caught only by phpstan-floor" "$wp/includes/class-lsn-report.php" \
    's/(    public function to_csv)/    \/** \@param array<string, mixed> \$grouped *\/\n    public function first_group(array \$grouped): mixed\n    {\n        return array_first(\$grouped);\n    }\n\n$1/' \
    "PASS tests-8.2" "PASS tests-8.5" "FAIL phpstan-floor" "PASS phpstan-target"

# Code under test that installs its own error handler, with E_STRICT back
handler_tree="$scratch/own-handler"; rm -rf "$handler_tree"; cp -R upgraded "$handler_tree"
if mutate "$handler_tree" "$wp/low-stock-notifier.php" "s/(defined\\('ABSPATH'\\) \\|\\| exit;\\n)/\$1set_error_handler(function () { return true; });\\n/" \
   && mutate "$handler_tree" "$wp/includes/class-lsn-logger.php" "s/(E_NOTICE     => 'notice',\\n)/\$1        E_STRICT     => 'strict',\\n/"; then
    gates "$handler_tree"
    expect "a plugin that installs its own error handler: refused on every version" 1 \
        "PASS lint-8.2" "PASS lint-8.5" "FAIL tests-8.2" "FAIL tests-8.5" \
        "     FAIL load: plugin and module files compile and load" "FAIL phpstan-target"
else
    bad "own-handler mutation changed nothing"
fi

echo "== Supervisor: late, hidden and overridden results"

# Each case inserts one line after the plugin's ABSPATH check (line 10 of
# the entry file) and must be refused by the supervisor for its own reason,
# while lint still passes. The same tree run without the supervisor passes,
# which shows the supervisor is what refuses it.
late() { # <name> <php line> <expected lines...>
    local name="$1" line="$2"; shift 2
    local tree="$scratch/late-$name"; rm -rf "$tree"; cp -R upgraded "$tree"
    if ! LINE="$line" perl -0pi -e 's/(defined\(.ABSPATH.\) \|\| exit;\n)/$1$ENV{LINE}\n/' "$tree/$wp/low-stock-notifier.php" \
       || cmp -s "$tree/$wp/low-stock-notifier.php" "upgraded/$wp/low-stock-notifier.php"; then
        bad "$name (the edit changed nothing)"; return
    fi
    if [ "$name" = "failed-test-then-exit-0" ]; then
        mutate "$tree" "$wp/includes/class-lsn-logger.php" 's/self::class/static::class/' || { bad "$name (second edit changed nothing)"; return; }
    fi
    gates "$tree"
    expect "$name: refused by the supervisor" 1 "PASS lint-8.2" "PASS lint-8.5" "$@"
    gates "$tree" TEST_ENTRY=tests/run.php
    expect "$name: passes the test gates without the supervisor" "$st" "PASS tests-8.2" "PASS tests-8.5"
}
late failed-test-then-exit-0 'register_shutdown_function(function () { exit(0); });' \
    "FAIL tests-8.2" "FAIL tests-8.5" "     FAIL wp: subclass logs to the base channel"
late deprecation-in-shutdown "register_shutdown_function(function () { trigger_error('late probe', E_USER_DEPRECATED); });" \
    "FAIL tests-8.2" "FAIL tests-8.5" "     DEPRECATED wordpress/low-stock-notifier/low-stock-notifier.php:10 late probe"
late deprecation-in-final-destructor "\$GLOBALS['lateProbe'] = new class { public function __destruct() { trigger_error('late destructor', E_USER_DEPRECATED); } };" \
    "FAIL tests-8.2" "FAIL tests-8.5" "     DEPRECATED wordpress/low-stock-notifier/low-stock-notifier.php:10 late destructor"
late handler-removed-and-restored "\$old = set_error_handler(function () { return false; }); restore_error_handler(); restore_error_handler(); trigger_error('probe', E_USER_DEPRECATED); set_error_handler(\$old);" \
    "FAIL tests-8.2" "FAIL tests-8.5" "     FAIL supervisor: PHP diagnostic outside the runner: Deprecated: probe in /work/src/wordpress/low-stock-notifier/low-stock-notifier.php on line 10"

late buffered-deprecation-in-shutdown "register_shutdown_function(function (): void { ob_start(); trigger_error('late buffered warning', E_USER_DEPRECATED); ob_end_clean(); });" \
    "FAIL tests-8.2" "FAIL tests-8.5" "     DEPRECATED wordpress/low-stock-notifier/low-stock-notifier.php:10 late buffered warning"
late buffered-deprecation-in-final-destructor "\$GLOBALS['lateBuffered'] = new class { public function __destruct() { ob_start(); trigger_error('late buffered destructor', E_USER_DEPRECATED); ob_end_clean(); } };" \
    "FAIL tests-8.2" "FAIL tests-8.5" "     DEPRECATED wordpress/low-stock-notifier/low-stock-notifier.php:10 late buffered destructor"

# A correct tree whose code discards an output buffer at shutdown must still
# pass: the runner's records do not go through PHP's output buffers.
clean="$scratch/clean-buffer"; rm -rf "$clean"; cp -R upgraded "$clean"
if LINE='ob_start(); register_shutdown_function(function (): void { ob_end_clean(); });' \
    perl -0pi -e 's/(defined\(.ABSPATH.\) \|\| exit;\n)/$1$ENV{LINE}\n/' "$clean/$wp/low-stock-notifier.php" \
    && ! cmp -s "$clean/$wp/low-stock-notifier.php" "upgraded/$wp/low-stock-notifier.php"; then
    gates "$clean"
    expect "a correct tree that discards an output buffer at shutdown still passes" 0 \
        "PASS tests-8.2" "PASS tests-8.5" "ALL GATES PASSED for $clean"
else
    bad "clean-buffer edit changed nothing"
fi

echo "== Declared minimum PHP version"

declared() { # <name> <base tree> <perl expression or ''> <exit> <expected lines...>
    local name="$1" base="$2" expr="$3" want="$4"; shift 4
    local tree slug
    slug="$(printf '%s' "$name" | tr -c 'A-Za-z0-9.-' '-')"; tree="$scratch/declared-$slug"; rm -rf "$tree"; cp -R "$base" "$tree"
    if [ -n "$expr" ] && ! mutate "$tree" "$wp/low-stock-notifier.php" "$expr"; then bad "$name (the edit changed nothing)"; return; fi
    if [ "$name" = "two plugins: the second is linted on its own declared version" ]; then
        mkdir -p "$tree/wordpress/second"
        printf '%s\n' '<?php' '/**' ' * Plugin Name: Second' ' * Requires PHP: 7.4' ' */' '' 'function second_probe(): int' '{' '    return intdiv(num1: 7, num2: 2);' '}' > "$tree/wordpress/second/second.php"
    fi
    gates "$tree"
    expect "$name" "$want" "$@"
}
declared "missing Requires PHP header fails the gate" upgraded 's/ \* Requires PHP: 8\.2\n//' 1 \
    "FAIL lint-declared (low-stock-notifier)" "     FAIL missing Requires PHP header in wordpress/low-stock-notifier/low-stock-notifier.php" "PASS lint-8.2"
declared "malformed Requires PHP header fails the gate" upgraded 's/Requires PHP: 8\.2/Requires PHP: 8.x/' 1 \
    "FAIL lint-declared (low-stock-notifier)" "     FAIL malformed Requires PHP header in wordpress/low-stock-notifier/low-stock-notifier.php: 8.x" "PASS lint-8.2"
declared "no Plugin Name header fails the gate" upgraded 's/ \* Plugin Name: Low Stock Notifier\n//' 1 \
    "FAIL lint-declared (low-stock-notifier)" "     FAIL no plugin entry file: no PHP file in low-stock-notifier/ has a Plugin Name header" "PASS lint-8.2"
declared "patch version 7.4.0 on legacy/ lints on PHP 7.4 and passes" legacy 's/Requires PHP: 7\.4/Requires PHP: 7.4.0/' 1 \
    "PASS lint-declared-7.4.0 (low-stock-notifier)" "PASS tests-8.2"
declared "patch version 7.4.0 on upgraded/ fails on the named argument" upgraded 's/Requires PHP: 8\.2/Requires PHP: 7.4.0/' 1 \
    "FAIL lint-declared-7.4.0 (low-stock-notifier)" \
    "     Parse error: syntax error, unexpected ':', expecting ')' in src/wordpress/low-stock-notifier/includes/class-lsn-report.php on line 34" "PASS lint-8.2"
declared "two plugins: the second is linted on its own declared version" upgraded '' 1 \
    "PASS lint-declared-8.2 (low-stock-notifier)" "FAIL lint-declared-7.4 (second)" "PASS lint-8.2" "PASS tests-8.2"

echo "== phpstan-floor probes on untested code"

probe() { # <name> <file body> <floor runtime or ''> <exit> <expected lines...>
    local name="$1" body="$2" runtime="$3" want="$4"; shift 4
    local tree slug
    slug="$(printf '%s' "$name" | tr -c 'A-Za-z0-9.-' '-')"; tree="$scratch/probe-$slug"; rm -rf "$tree"; cp -R upgraded "$tree"
    printf '%s\n' "$body" > "$tree/$wp/probe.php"
    if [ -n "$runtime" ]; then gates "$tree" FLOOR_RUNTIME="$runtime"; else gates "$tree"; fi
    expect "$name" "$want" "PASS lint-8.2" "PASS tests-8.2" "PASS tests-8.5" "$@"
}
probe "PHP 8.4 function: caught by phpstan-floor" \
    '<?php
/** @param array<int, int> $a */
function new_function_probe(array $a): ?int { return array_find($a, fn (int $x): bool => $x > 1); }' '' 1 \
    "FAIL phpstan-floor" "     /work/src/wordpress/low-stock-notifier/probe.php:3:Function array_find not found." "PASS phpstan-target"
probe "PHP 8.4 class: caught by phpstan-floor" \
    '<?php
function new_class_probe(): \ReflectionConstant { return new \ReflectionConstant("PHP_VERSION"); }' '' 1 \
    "FAIL phpstan-floor" "     /work/src/wordpress/low-stock-notifier/probe.php:2:Instantiated class ReflectionConstant not found." "PASS phpstan-target"
probe "PHP 8.4 constant: caught by phpstan-floor running on PHP 8.2" \
    '<?php
function new_constant_probe(): int { return PHP_OUTPUT_HANDLER_PROCESSED; }' '' 1 \
    "FAIL phpstan-floor" "     /work/src/wordpress/low-stock-notifier/probe.php:2:Constant PHP_OUTPUT_HANDLER_PROCESSED not found." "PASS phpstan-target"
probe "the same constant passes phpstan-floor when PHPStan runs on PHP 8.5" \
    '<?php
function new_constant_probe(): int { return PHP_OUTPUT_HANDLER_PROCESSED; }' 8.5 0 \
    "PASS phpstan-floor" "PASS phpstan-target"
out="$(docker run --rm --network none php:8.2-cli php -r 'var_dump(PHP_OUTPUT_HANDLER_PROCESSED);' 2>&1)"
printf '%s\n' "$out" | grep -q 'Undefined constant "PHP_OUTPUT_HANDLER_PROCESSED"' \
    && ok "that constant is undefined at run time on PHP 8.2" || bad "constant on PHP 8.2" "$out"

echo "== Rector counterexample: get_parent_class() without a parent"

cx="$scratch/counterexample"; rm -rf "$cx"; mkdir -p "$cx"; cp -R counterexamples/get-parent-class "$cx/build"; cp rector.php "$cx/"
rector 8.5 rector.php "$cx"
php_in() { docker run --rm --network none -v "$cx":/w -w /w "php:$1-cli" php -d error_reporting=-1 "${@:2}" 2>&1; }
cls="$(php_in 8.2 -l build/no-parent-class.php)"
grep -q 'return parent::class;' "$cx/build/no-parent-class.php" \
    && printf '%s\n' "$cls" | grep -q 'Cannot use "parent" when current class scope has no parent' \
    && ok "rector.php turns get_parent_class() in a parentless class into parent::class, which fails lint on 8.2" \
    || bad "parentless class counterexample" "$cls"
lint="$(php_in 8.2 -l build/no-parent-trait.php)"; runout="$(php_in 8.2 build/no-parent-trait.php)"
grep -q 'return parent::class;' "$cx/build/no-parent-trait.php" \
    && printf '%s\n' "$lint" | grep -q 'No syntax errors detected' \
    && printf '%s\n' "$runout" | grep -q 'Cannot use "parent" when current class scope has no parent' \
    && ok "inside a trait the same rewrite passes lint and fails only when called" \
    || bad "trait counterexample" "$lint
$runout"
# safe_equivalent <dir>: both programs must exit 0 on 8.2 and 8.5, print
# exactly the five expected results, and the replacement must print no
# deprecation. Returns 0 only if all of that holds.
expected_results='bool(false)
string(4) "Base"
string(4) "Base"
string(4) "Base"
bool(false)'
safe_equivalent() {
    local dir="$1" v a b sa sb
    for v in 8.2 8.5; do
        a="$(docker run --rm --network none -v "$dir":/w -w /w "php:$v-cli" php -d error_reporting=0 original-calls.php 2>&1)"; sa=$?
        b="$(docker run --rm --network none -v "$dir":/w -w /w "php:$v-cli" php -d error_reporting=-1 safe-replacement.php 2>&1)"; sb=$?
        [ "$sa" -eq 0 ] && [ "$sb" -eq 0 ] || return 1
        [ "$a" = "$expected_results" ] && [ "$b" = "$expected_results" ] || return 1
        printf '%s\n' "$b" | grep -qi deprecated && return 1
    done
    return 0
}
safe_equivalent "$here/counterexamples/get-parent-class" \
    && ok "get_parent_class(self::class) returns what the original calls return, with no deprecation, on 8.2 and 8.5" \
    || bad "safe replacement differs, fails or deprecates"
broken="$scratch/counterexample-broken"; rm -rf "$broken"; mkdir -p "$broken"
printf '<?php exit(1);\n' > "$broken/original-calls.php"; cp "$broken/original-calls.php" "$broken/safe-replacement.php"
if safe_equivalent "$broken"; then
    bad "the equivalence check accepted two programs that both exit 1"
else
    ok "the equivalence check rejects two programs that both exit 1 with no output"
fi

echo "== The gates themselves"

tree="$scratch/p-after-rector-haiku-1"
gates "$tree" TEST_ENTRY=tests/run.php
expect "without the supervisor, the exit() proposal passes every gate" 0 \
    "PASS tests-8.2" "PASS tests-8.5" "ALL GATES PASSED for $tree"

tests_copy="$scratch/tests-echo"; rm -rf "$tests_copy"; cp -R tests "$tests_copy"
if mutate "$tests_copy" run.php "s/fwrite\(STDOUT, ('DEPRECATED ' \. \\\$where \. ' ' \. \\\$message \. \"\\\\n\")\);/echo \$1;/"; then
    gates "$scratch/late-buffered-deprecation-in-shutdown" TESTS_DIR="$tests_copy"
    expect "with deprecations written through echo, the buffered shutdown deprecation passes every gate" 0 \
        "PASS tests-8.2" "PASS tests-8.5"
else
    bad "echo mutation changed nothing"
fi

tests_copy="$scratch/tests-no-handler-check"; rm -rf "$tests_copy"; cp -R tests "$tests_copy"
if mutate "$tests_copy" run.php 's/if \(\$current === \$handler\) \{/if (true) {/'; then
    gates "$handler_tree" TESTS_DIR="$tests_copy"
    expect "without the runner's handler check, the own-handler tree passes the test gates" 1 \
        "PASS tests-8.2" "PASS tests-8.5" "FAIL phpstan-target"
else
    bad "handler check mutation changed nothing"
fi

stan_copy="$scratch/phpstan-range"; rm -rf "$stan_copy"; cp -R phpstan "$stan_copy"
if mutate "$stan_copy" target.neon 's/phpVersion: 80500/phpVersion:\n        min: 80200\n        max: 80500/'; then
    gates legacy PHPSTAN_DIR="$stan_copy"
    expect "with a version range starting at 8.2, phpstan-target reports no deprecations in legacy/" 1 \
        "PASS phpstan-target"
else
    bad "phpVersion range mutation changed nothing"
fi

stan_copy="$scratch/phpstan-buried"; rm -rf "$stan_copy"; cp -R phpstan "$stan_copy"; : > "$stan_copy/baseline.neon"
docker run --rm --network none -v "$here/legacy":/work/src:ro -v "$stan_copy":/work/phpstan -v "$here/vendor":/work/vendor:ro \
    -v "$here/tests":/work/tests:ro -w /work php:8.5-cli php -d memory_limit=1G vendor/bin/phpstan analyse \
    -c phpstan/target.neon --no-progress --generate-baseline phpstan/baseline.neon src >/dev/null 2>&1
gates legacy PHPSTAN_DIR="$stan_copy"
expect "a baseline generated against 8.5 hides every deprecation from phpstan-target" 1 \
    "PASS phpstan-target" "FAIL tests-8.5"

stan() { docker run --rm --network none -v "$here/$1":/work/src:ro -v "$here/phpstan":/work/phpstan:ro -v "$here/vendor":/work/vendor:ro \
    -v "$here/tests":/work/tests:ro -w /work php:8.5-cli php -d memory_limit=1G vendor/bin/phpstan analyse \
    --no-progress --error-format=raw "${@:2}" src 2>&1; }
out="$(stan upgraded -c phpstan/level8.neon)"; st=$?
[ "$st" -eq 0 ] && ok "upgraded/ passes level 8 with its level-8 baseline" || bad "level 8 on upgraded/" "$out"
n="$(stan upgraded -c phpstan/target.neon -l 8 | grep -c ':[0-9]*:')"
[ "$n" -eq 8 ] && ok "raising upgraded/ from level 6 to 8 reports 8 errors the level-6 baseline does not cover" \
    || bad "level 8 new errors" "got $n, wanted 8"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
