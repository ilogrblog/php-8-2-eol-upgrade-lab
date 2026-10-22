<?php
/**
 * Plugin Name: Low Stock Notifier
 * Description: Emails a CSV of products that have fallen below their stock threshold.
 * Version: 1.4.2
 * Requires PHP: 8.2
 */

defined('ABSPATH') || exit;

require_once __DIR__ . '/includes/class-lsn-logger.php';
require_once __DIR__ . '/includes/class-lsn-threshold.php';
require_once __DIR__ . '/includes/class-lsn-report.php';

add_action('lsn_daily_check', 'lsn_run_daily_check');

/**
 * Cron callback: build the low-stock report and email it.
 *
 * @param array $products Product rows from the shop, injected for testing.
 * @return int Number of products reported.
 */
function lsn_run_daily_check($products = null)
{
    $recipient = get_option('lsn_recipient', '');
    if ($recipient === '') {
        // Without a recipient the report must not be built or sent.
        throw new RuntimeException('Low Stock Notifier: no recipient configured');
    }

    $products = $products === null ? apply_filters('lsn_products', []) : $products;
    $report = new LSN_Report(new LSN_Threshold());
    $low = $report->low_stock($products);

    wp_mail($recipient, 'Low stock report', $report->to_csv($low));
    (new LSN_Mail_Logger())->log(E_NOTICE, count($low) . ' products reported');

    return count($low);
}
