Fixed all failing PHP 8.4/8.5 gates. Three files modified:

1. **class-lsn-logger.php**: Removed E_STRICT from static array, added conditional dynamic loading in log() method using defined() check for PHP 8.2 backward compatibility.

2. **low-stock-notifier.php**: Replaced trigger_error(..., E_USER_ERROR) with throw new RuntimeException() to avoid PHP 8.4+ deprecation warning.

3. **class-lsn-report.php**: Changed null to empty string for array offsets to avoid PHP 8.5 deprecation warning on "Using null as an array offset".

All changes maintain PHP 8.2 compatibility while eliminating deprecation warnings in PHP 8.4+ gates.
