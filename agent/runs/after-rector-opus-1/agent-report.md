I made three edits, all in the WordPress plugin, one for each deprecation in gate-report.txt. Nothing has been run: I could not execute PHP, so whether the gates now pass is unconfirmed. I did check each change by reading tests/run.php, which compares results against values recorded on PHP 8.2 and counts any deprecation as a failure.

1. `src/wordpress/low-stock-notifier/includes/class-lsn-logger.php`: removed the `E_STRICT => 'strict'` entry from the `$labels` map.
   - **Why:** this fixes the tests-8.4, tests-8.5 and phpstan-target failures at line 11. `E_STRICT` is deprecated from 8.4, and PHP 8 never raises that level anyway. The tests only log `E_NOTICE` and `E_DEPRECATED`, which are unchanged.
   - **One difference:** a caller passing level 2048 directly would now get "unknown" instead of "strict". Nothing in the code does that.
   - I left `self::class` in `channel()` as it is. A test requires subclasses to log to the base channel.

2. `src/wordpress/low-stock-notifier/low-stock-notifier.php`, line 28: replaced `trigger_error(..., E_USER_ERROR)` with `throw new RuntimeException('Low Stock Notifier: no recipient configured')`.
   - **Why:** passing `E_USER_ERROR` to `trigger_error()` is deprecated from 8.4, and the 8.4 notice itself says to throw an exception instead.
   - **Behaviour:** as before, the check stops and sends no mail when no recipient is set, which the test expects. The file has no namespace, so the class resolves to the global one. This works on 8.2.
   - I did not use `exit` because the test catches the stop as an exception, and an `exit` would end the whole test run.

3. `src/wordpress/low-stock-notifier/includes/class-lsn-report.php`, line 23: a product with no category now falls back to `''` instead of `null`.
   - **Why:** PHP 8.5 deprecates using `null` as an array key. PHP already turned a `null` key into `''`, so the grouping, key order and CSV output stay exactly the same.

I made no changes to the Magento module, `tests/` or `gate-report.txt`. The Magento module had no failing gates.

Separately from the gates, the plugin header says `Requires PHP: 7.4`, but `to_csv()` uses named arguments (`escape:`), which need PHP 8.0. It works on 8.2, so no gate fails, but the header understates the minimum version. I left it alone to keep the change minimal.
