I fixed every deprecation listed in gate-report.txt by editing files under src only. I could not run PHP or the gates, so none of it has been run. I checked each change by reading tests/run.php, which expects the 8.2 output byte for byte. I did not run PHPStan.

All changes are valid on PHP 8.2 and keep the same behaviour there. Paths are relative to `src/`.

**wordpress/low-stock-notifier/includes/class-lsn-logger.php**
- `get_class()` became `self::class` in `channel()`. A no-argument `get_class()` returned the class that defines the method, and `self::class` is exactly that. The subclass `LSN_Mail_Logger` still logs to `lsn_logger`, as the test expects. `static::class` would have changed that.
- `E_STRICT => 'strict'` became `2048 => 'strict'`, with a comment. The constant is deprecated in 8.4, and 2048 is its value on 8.2, so the label lookup is unchanged.

**wordpress/low-stock-notifier/includes/class-lsn-threshold.php**
- The constructor parameter is now `?LSN_Settings $settings = null`, which removes the 8.4 implicit-nullable deprecation.
- `(integer)` became `(int)` to fix the 8.5 non-canonical cast.

**wordpress/low-stock-notifier/includes/class-lsn-report.php**
- A product with no category now uses `''` instead of `null` as the array key. `null` was already cast to `''`, so the group key and the CSV output are unchanged, but 8.5 deprecates `null` as an array offset.
- Both `fputcsv()` calls now pass `',', '"', '\\'`. That is the current default escape character, so the output is unchanged on 8.2 (the test expects `"Arm 32\" wide"`) and does not depend on the default changing.

**wordpress/low-stock-notifier/low-stock-notifier.php**
- `trigger_error(..., E_USER_ERROR)` became `throw new RuntimeException('Low Stock Notifier: no recipient configured')`, because passing `E_USER_ERROR` is deprecated since 8.4. The code still stops before the report is built or emailed, as the "stops, and sends nothing" test requires. In production this ends the cron run with an uncaught exception rather than a fatal error.

**magento/app/code/Example/StockFeed/Model/FeedParser.php**
- The constructor parameter is now `?LoggerInterface $logger = null`, which removes the 8.4 implicit-nullable deprecation.
- `str_getcsv($line)` became `str_getcsv($line, ',', '"', '\\')`. The supplier escapes quotes with a backslash, so the escape character has to stay explicit.
- `(double)` became `(float)` and `(boolean)` became `(bool)` to fix the 8.5 non-canonical casts.

**magento/app/code/Example/StockFeed/Model/MimeGuard.php**
- I removed the `finfo_close($finfo)` call. It is deprecated in 8.5, and the finfo object is freed automatically when the function returns, so nothing changes.

**magento/app/code/Example/StockFeed/Model/SupplierClient.php**
- I removed `$property->setAccessible(true)`. It is deprecated in 8.5 and has had no effect since PHP 8.1, so 8.2 is unaffected. The plugin header declares `Requires PHP: 7.4`, and this change would break private-property reads there, but nothing in this task targets below 8.2, so I left it.
