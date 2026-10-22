I made three edits, all in the WordPress plugin, to fix every failing gate in gate-report.txt. I could not run anything here, so none of this has been checked by running the gates. I did read tests/run.php and checked each change against what it expects.

1. `src/wordpress/low-stock-notifier/includes/class-lsn-logger.php` (line 11): removed the `E_STRICT => 'strict'` entry from `$labels`.
   - **Why:** using the `E_STRICT` constant is deprecated from PHP 8.4 on, which failed tests-8.4, tests-8.5 and phpstan-target.
   - **PHP 8.2:** PHP 8 never raises `E_STRICT`, so the label could not be reached there either. No test logs at that level.
   - **Left alone:** `self::class` in `channel()`, because the test requires subclasses to log to the base `lsn_logger` channel.

2. `src/wordpress/low-stock-notifier/low-stock-notifier.php` (line 28): replaced `trigger_error(..., E_USER_ERROR)` with `throw new RuntimeException('Low Stock Notifier: no recipient configured');`.
   - **Why:** passing `E_USER_ERROR` to `trigger_error()` is deprecated from 8.4 on.
   - **Behaviour:** an uncaught exception still stops the cron run before the report is built or mailed. That is what the "stops, and sends nothing, without a recipient" test checks.
   - **PHP 8.2:** this works on 8.2.
   - **Namespace:** the file is in the global namespace, so no `use` statement is needed.

3. `src/wordpress/low-stock-notifier/includes/class-lsn-report.php` (line 23): products with no category now get `''` instead of `null`.
   - **Why:** using `null` as an array offset is deprecated in 8.5.
   - **Behaviour:** PHP already turned a `null` key into `''`, so the grouping, the `ksort` order and the CSV output are byte-identical on every version.

I did not touch the Magento module, tests/ or gate-report.txt. The Magento module had no failing gates.

Separately, the plugin header says "Requires PHP: 7.4", but the code already uses named arguments (`fputcsv(..., escape: '\\')`), which need PHP 8.0. I left the header as it is because it is outside this task.
