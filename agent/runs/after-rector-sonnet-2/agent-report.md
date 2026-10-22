I made three edits, one per failing deprecation in gate-report.txt. I could not run PHP, so none of it is tested. I traced each change against tests/run.php by reading only.

1. `src/wordpress/low-stock-notifier/includes/class-lsn-logger.php`, line 11: replaced `E_STRICT => 'strict'` with the literal `2048 => 'strict'` plus a comment.
   - Why: the `E_STRICT` constant is deprecated in 8.4 and 8.5, which failed tests-8.4, tests-8.5 and phpstan-target.
   - `E_STRICT` is 2048 on every version, so the lookup table is identical on 8.2, and the label mapping is unchanged.

2. `src/wordpress/low-stock-notifier/includes/class-lsn-report.php`, line 23: the fallback for a missing category is now `''` instead of `null`.
   - Why: `$grouped[null][]` is deprecated in 8.5 ("null as array offset").
   - PHP already converted a `null` key to `''`, so the grouping, the `ksort` order and the CSV output are the same. The test 'products without a category are grouped under the empty key' expects `''`.

3. `src/wordpress/low-stock-notifier/low-stock-notifier.php`, line 28: replaced `trigger_error(..., E_USER_ERROR)` with `throw new RuntimeException('Low Stock Notifier: no recipient configured')`.
   - Why: passing `E_USER_ERROR` to `trigger_error()` is deprecated since 8.4, which failed tests-8.4 and tests-8.5.
   - A throw still stops the callback before any report is built or mail is sent. The 'stops, and sends nothing' test catches `Throwable`, so it still passes. `RuntimeException` exists on 8.2 as well.
   - Production behaviour changes slightly. Before, `E_USER_ERROR` was a fatal error. Now an uncaught exception ends the cron run instead, and `RuntimeException` is catchable where the old fatal was not.

I made no changes under the Magento module. It had no failures in the report, and I read its three model files and found nothing else that needed fixing.
