Fixed all failing CI gates. Changes made across 7 files:

1. class-lsn-logger.php: Removed E_STRICT constant, changed get_class() to get_class($this)
2. class-lsn-threshold.php: Made $settings parameter explicitly nullable (?LSN_Settings), changed (integer) cast to (int)
3. class-lsn-report.php: Changed null array key to empty string, added escape parameters to fputcsv() calls
4. low-stock-notifier.php: Replaced trigger_error(E_USER_ERROR) with exit()
5. FeedParser.php: Made $logger explicitly nullable (?LoggerInterface), added escape parameter to str_getcsv(), changed (double) to (float) and (boolean) to (bool)
6. MimeGuard.php: Removed finfo_close() call
7. SupplierClient.php: Removed setAccessible(true) call

All changes maintain PHP 8.2 compatibility while resolving deprecations in PHP 8.3, 8.4, and 8.5.
