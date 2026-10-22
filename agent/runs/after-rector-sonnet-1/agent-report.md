I made three edits, all under DIR/src/wordpress/low-stock-notifier. I could not run PHP, so none of it has been run through the gates. I checked each change by reading tests/run.php.

1. `includes/class-lsn-logger.php`, line 11. I replaced `E_STRICT => 'strict'` in the `$labels` map with `2048 => 'strict'`, plus a comment.
   - **Why:** `E_STRICT` is deprecated on PHP 8.4 and later. That caused the deprecation in tests-8.4 and tests-8.5 and the phpstan-target failure.
   - **Behaviour:** `E_STRICT` is the integer 2048, so the map is identical on 8.2. A literal is used because it works on every version and adds no version check.

2. `low-stock-notifier.php`, line 28. I replaced `trigger_error('Low Stock Notifier: no recipient configured', E_USER_ERROR);` with `throw new RuntimeException('Low Stock Notifier: no recipient configured');`.
   - **Why:** passing `E_USER_ERROR` to `trigger_error()` is deprecated since 8.4, which failed tests-8.4 and tests-8.5.
   - **Behaviour:** the run still stops before any mail is sent. The test "daily check stops, and sends nothing, without a recipient" catches any Throwable, so it should still pass.

3. `includes/class-lsn-report.php`, line 23. In `low_stock()`, the fallback for a product with no category changed from `null` to `''`.
   - **Why:** using `null` as an array offset is deprecated on 8.5, which failed tests-8.5.
   - **Behaviour:** PHP already converted a `null` key to `''`, so the grouping, the `ksort` order and the CSV output are the same. That matches the test "grouped under the empty key".

I read the Magento module (`FeedParser.php`, `MimeGuard.php`, `SupplierClient.php`) and changed nothing there. Its gates already pass, and I saw no other 8.4 or 8.5 problems in it.

`low-stock-notifier.php` declares `Requires PHP: 7.4`, but `class-lsn-report.php` and `FeedParser.php` use named arguments (`escape: '\\'`), which need PHP 8.0 or later. It is not a failing gate, so I left it alone. The header is probably wrong.
