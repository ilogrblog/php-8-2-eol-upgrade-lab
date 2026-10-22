I edited all seven files that the failing gates flagged. I could not run PHP or the gates, so none of this has been run. I checked each change by hand against the gate report and against the expected values in tests/run.php, which I read but did not edit. Every change is valid on PHP 8.2 and keeps the recorded behaviour.

All paths are under DIR/src.

1. `wordpress/low-stock-notifier/includes/class-lsn-logger.php`
   - `strtolower(get_class())` is now `strtolower(self::class)`. Argument-less `get_class()` is deprecated in 8.3, and it returned the class that defines the method. `self::class` is that same class, so `LSN_Mail_Logger` still logs to the `lsn_logger` channel.
   - The `E_STRICT` key in `$labels` is now the literal `2048` with a comment. `E_STRICT` is deprecated in 8.4, and 2048 is its value, so `log(E_STRICT, ...)` still gives the `strict` label rather than `unknown`.

2. `wordpress/low-stock-notifier/includes/class-lsn-threshold.php`
   - The constructor parameter is now `?LSN_Settings $settings = null`, because implicit nullable types are deprecated in 8.4.
   - `(integer)` is now `(int)`, because the non-canonical cast is deprecated in 8.5. The result is the same.

3. `wordpress/low-stock-notifier/includes/class-lsn-report.php`
   - A missing category is now `''` instead of `null` when used as the array key. Using null as an array offset is deprecated in 8.5. PHP already turned null into `''`, so the uncategorised group is still under the empty key.
   - Both `fputcsv` calls now pass `',', '"', '\\'`. The missing `$escape` argument is deprecated in 8.4. Passing the old default keeps the CSV output byte-identical.

4. `wordpress/low-stock-notifier/low-stock-notifier.php`
   - `trigger_error(..., E_USER_ERROR)` is now `throw new RuntimeException(...)` with the same message, because `E_USER_ERROR` is deprecated in 8.4. It still stops the run before the report is built or mailed, which is what the "stops, and sends nothing" test checks.

5. `magento/app/code/Example/StockFeed/Model/FeedParser.php`
   - The constructor parameter is now `?LoggerInterface $logger = null`.
   - `str_getcsv($line)` is now `str_getcsv($line, ',', '"', '\\')`. This keeps the supplier's backslash-escaped quotes (`"Arm 32\" wide"`) parsing as before.
   - `(double)` is now `(float)` and `(boolean)` is now `(bool)`, because the non-canonical casts are deprecated in 8.5.

6. `magento/app/code/Example/StockFeed/Model/MimeGuard.php`
   - I removed `finfo_close($finfo)`. It is deprecated in 8.5, and finfo objects are freed automatically.

7. `magento/app/code/Example/StockFeed/Model/SupplierClient.php`
   - I removed `$property->setAccessible(true)`. It is deprecated in 8.5 and has had no effect since 8.1, so it is not needed on 8.2.

These changes should clear every deprecation listed for tests-8.3, 8.4 and 8.5, and every phpstan-target finding. I did not touch the lint gates or phpstan-floor, which were already passing.
