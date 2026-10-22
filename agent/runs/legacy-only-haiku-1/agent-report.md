Fixed all 42 failing gates across 7 files in the WordPress plugin and Magento module by addressing PHP 8.2-8.5 compatibility issues:

1. class-lsn-logger.php: Removed E_STRICT, changed get_class() to static::class
2. class-lsn-threshold.php: Added explicit nullable type (?LSN_Settings), fixed (integer) to (int)
3. class-lsn-report.php: Changed null to empty string for array offsets, added escape parameter to fputcsv()
4. low-stock-notifier.php: Replaced E_USER_ERROR trigger_error() with exception throw
5. FeedParser.php: Added explicit nullable type (?LoggerInterface), added escape parameter to str_getcsv(), fixed (double) to (float) and (boolean) to (bool)
6. MimeGuard.php: Removed deprecated finfo_close() call
7. SupplierClient.php: Removed deprecated setAccessible(true) call

All changes are backward compatible with PHP 8.2 while passing PHP 8.3-8.5 gates.
