# PHP 8.2 end-of-life upgrade lab: Rector, PHPStan and PHP version gates

Companion to the [iLogr](https://ilogr.com/) article **[PHP 8.2 End of Life: Upgrading WordPress and Magento Code to PHP 8.4 and 8.5 with Rector, PHPStan and an AI Agent](https://ilogr.com/php-8-2-end-of-life-upgrade-rector-phpstan/)**.

A small, deliberately old WordPress plugin and Magento module, upgraded so that the same code runs cleanly on PHP 8.2, 8.3, 8.4 and 8.5. Rector does the mechanical fixes, PHPStan and versioned PHP containers act as gates, and an AI agent's saved proposals handle the rest. No AI account is needed to reproduce it.

> **Before you use it:** this is example code, provided as is and without warranty of any kind. Use it on a development machine or a staging copy first, never on a live site, store or database, and take a backup of anything you point it at. Rector rewrites files in place, so never point `rector.php` at a live site or store. Everything you do with this code is entirely at your own risk, and nobody who wrote or published it accepts any responsibility for loss, damage or downtime.

## Requirements

- Docker, able to pull the `php:7.4-cli`, `php:8.2-cli`, `php:8.3-cli`, `php:8.4-cli` and `php:8.5-cli` images (PHP 7.4 is used once, to lint the plugin under its declared `Requires PHP: 7.4`).
- Composer 2, to install Rector and PHPStan into `vendor/`. If you have no Composer, the `composer:2` image does the same job.
- `bash`, `git` (for `git diff --no-index`), `patch` and `perl`. The scripts run on the bash 3.2 that ships with macOS.

**Minimum supported:** PHP 8.2 is the floor the example code must keep running on (the whole point of the lab). The tooling needs Rector 2.6 or later and PHPStan 2.2 or later, because the lab uses a `phpVersion` range, which PHPStan accepts from 2.0 (see `composer.json`).

The gate containers have no network access and mount the code under test read-only. Only `composer install` and the first image pull use the network.

## Run it

```bash
composer install
```

If you do not have Composer, use the official image instead:

```bash
docker run --rm -v "$PWD":/app -w /app composer:2 install --no-interaction
```

Then:

```bash
bin/gates.sh legacy      # fails on 8.3, 8.4 and 8.5; passes on 8.2
bin/gates.sh upgraded    # every gate passes
bin/reproduce.sh         # legacy + Rector + steps 02 and 03 must equal upgraded/
bin/check.sh             # 72 checks, several minutes
bin/check-safety.sh      # 7 checks that the scripts refuse and isolate what they should
```

`bin/gates.sh` exit codes: 0 all gates passed, 1 at least one failed, 2 usage or environment error (no argument, no Docker, no `composer install`). `PHP_VERSIONS="8.3 8.4"` narrows the version range, for example to a Magento release that supports only those. The first version is also where `phpstan-floor` runs and the last is where `phpstan-target` runs; change `phpVersion` in `phpstan/floor.neon` and `phpstan/target.neon` to match.

`bin/reproduce.sh` deletes and recreates `build/` inside this folder and runs Rector on it, and it prints a warning before it does. It refuses to run if a `build/` exists that it did not create, so it cannot delete a folder of yours.

## Expected results

| Command | Expected |
| --- | --- |
| `bin/gates.sh legacy` | exit 1; `tests-8.2` and `phpstan-floor` pass, `tests-8.3` to `tests-8.5` and `phpstan-target` fail |
| `bin/gates.sh upgraded` | exit 0, `ALL GATES PASSED for upgraded` |
| `bin/reproduce.sh` | exit 0; Rector output matches `steps/01-rector.diff`, `build/` equals `upgraded/`, all gates pass |
| `bin/check.sh` | `72 passed, 0 failed` |
| `bin/check-safety.sh` | `7 passed, 0 failed` |

Deprecations the tests record on each PHP version:

| PHP | Legacy deprecations | After Rector | Upgraded |
| --- | --- | --- | --- |
| 8.2 | 0 | 0 | 0 |
| 8.3 | 1 | 0 | 0 |
| 8.4 | 8 | 2 | 0 |
| 8.5 | 14 | 3 | 0 |

All twelve tests pass on every version at every stage; the fixes only have to remove deprecations without changing behaviour.

## What is here

| Path | Contents |
| --- | --- |
| `legacy/` | The starting point: `wordpress/low-stock-notifier` and `magento/app/code/Example/StockFeed` |
| `upgraded/` | The finished result, which passes every gate |
| `steps/` | The three diffs between them: Rector, one human decision, one accepted agent proposal |
| `rector.php` | Deprecation fixes only, pinned to PHP 8.5; on this fixture the output lints and passes on 8.2 to 8.5 (see the counterexample below) |
| `rector-naive.php` | `withPhpSets(php85: true)`, kept to show why the pinned version exists |
| `phpstan/` | `floor.neon` (8.2 to 8.5), `target.neon` (8.5), `level8.neon`, and their baselines |
| `tests/run.php` | Twelve characterisation tests recorded on PHP 8.2; writes each result and deprecation straight to STDOUT as it happens, so output buffering in the code under test cannot hide it |
| `tests/supervise.php` | The test gate: runs `tests/run.php` as a separate process and judges its whole output after it ends |
| `tests/expected-tests.txt` | The twelve test names the supervisor requires |
| `tests/stubs/` | Minimal stand-ins for the WordPress and Magento functions the fixture calls |
| `counterexamples/get-parent-class/` | Where `rector.php` breaks code, and the hand replacement that does not |
| `agent/` | The agent prompt, twelve saved proposals with the agents' own summaries, and the verdicts |
| `bin/gates.sh` | Runs every gate against one tree |
| `bin/reproduce.sh` | Rebuilds `upgraded/` from `legacy/` and runs the gates on it |
| `bin/check.sh` | Deterministic checks that each gate refuses what it should |
| `bin/check-safety.sh` | Checks that the scripts refuse a foreign `build/`, stop without Docker or `vendor/`, and start every container without a network |
| `composer.json`, `composer.lock` | Rector, PHPStan and the PHPStan deprecation rules, pinned |

## The gates

| Gate | What it runs | What it catches |
| --- | --- | --- |
| `lint-declared-<version>` | `php -l` on each plugin under its `Requires PHP` header (`7.4` or `7.4.0`); a plugin entry file with no valid header fails as `lint-declared (<plugin>)` | Syntax newer than the plugin promises to support |
| `lint-8.2` to `lint-8.5` | `php -l` on every file | Syntax newer than the oldest server |
| `tests-8.2` to `tests-8.5` | `tests/supervise.php` | Deprecations at run time, including in shutdown functions and final destructors; PHP diagnostics printed while the runner's handler is absent; missing results; any change in recorded behaviour |
| `phpstan-floor` | PHPStan level 6, `phpVersion` 8.2 to 8.5, running on PHP 8.2 | Functions, classes and constants that do not exist on 8.2 |
| `phpstan-target` | PHPStan level 6, `phpVersion` 8.5, running on PHP 8.5, with deprecation rules | Deprecations on paths the tests do not execute, and new type errors |

The supervisor passes a run only if the child printed a PASS for every name in `tests/expected-tests.txt`, printed no FAIL, deprecation or other output, wrote nothing to stderr, printed END, and exited 0. It is a check on ordinary code, not a sandbox: code running in the test process can still silence its own diagnostics or print lines that look like passes.

PHPStan runs the floor analysis on PHP 8.2 because it reads constants from the PHP it runs on: run on 8.5, it did not report `PHP_OUTPUT_HANDLER_PROCESSED`, which 8.2 does not define. Functions and classes were reported either way.

The level 6 baseline was generated from `legacy/` against the floor, so it records old type debt and none of the deprecations.

## Limits

- The fixture is small, and the WordPress and Magento functions it calls are stubs in `tests/stubs/`. This is not a WordPress or Magento installation, and it says nothing about third-party plugins or extensions.
- The tests cover the behaviour that the upgrade could plausibly change. They are not a full test suite for either component.
- The agent proposals are twelve recorded runs, not a measurement of any model.
- `rector.php` lists the rules this fixture needed, and its output is only known to be safe for this fixture. `RemoveGetClassGetParentClassNoArgsRector` turns `get_parent_class()` with no arguments into `parent::class`: in a class with no parent that no longer compiles, and in a trait it compiles and fails when called (`counterexamples/get-parent-class/`). Replace those calls by hand with `get_parent_class(self::class)` before running Rector. A real codebase may need other rules from Rector's PHP sets; add each only after reading its diff, and let the gates confirm it.

## Tested versions

- PHP: official Docker images 7.4.33 (declared-version lint only), 8.2.35, 8.3.36, 8.4.27 and 8.5.12.
- Rector 2.7.0, PHPStan 2.3.1 and `phpstan/phpstan-deprecation-rules` 2.0.5, as pinned in `composer.lock`. The same 72 checks also pass with Rector 2.6.7 and PHPStan 2.2.16, the versions the article's version-gating notes refer to.
- Composer 2.10.3, Docker 29.7.2, on macOS. The scripts are ShellCheck-clean at warning level (ShellCheck 0.11.0).

Later versions may report different counts or messages; the article explains what each result means.

## Licence

MIT, because the repository's main purpose is a set of command-line gates and the PHP they exercise. The example plugin in `legacy/` and `upgraded/` is a stand-in written for this lab: it runs only against the stubs in `tests/stubs/` and never loads WordPress, and the MIT licence is compatible with the GPL that WordPress code normally uses. If you turn any of it into a real plugin, check the licence your distribution needs. See `LICENSE`.

More code that accompanies iLogr guides: [github.com/ilogrblog](https://github.com/ilogrblog).
