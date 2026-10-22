Fixed all three failing gates by making minimal, backward-compatible changes:

1. **class-lsn-logger.php:11** - Removed deprecated E_STRICT constant from $labels array. Constant was deprecated in PHP 8.4 and removed in 8.5; removing it is safe and maintains 8.2 compatibility.

2. **low-stock-notifier.php:28** - Replaced trigger_error() with E_USER_ERROR with exit() call. E_USER_ERROR parameter is deprecated in 8.4/removed in 8.5; exit() achieves the same halt behavior on all versions.

3. **class-lsn-report.php:23** - Changed null fallback for category key to empty string ''. Using null as array offset is deprecated in 8.5; empty string is valid on all versions and matches documented behavior.

All changes maintain full compatibility with PHP 8.2 through 8.5 while fixing the deprecation warnings and phpstan errors.
