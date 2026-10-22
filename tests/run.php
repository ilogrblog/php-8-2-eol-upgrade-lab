<?php
/**
 * Characterisation tests for the fixture, run once per PHP version.
 *
 * Do not use this file as a gate on its own: run it through
 * tests/supervise.php, which judges the whole output after this process
 * has ended. Code under test can call exit(), register shutdown functions
 * or change error handling, and any of those can end or alter this process
 * after a result has been printed.
 *
 * Usage: php tests/run.php <tree>      e.g. php tests/run.php legacy
 *
 * The expected values were recorded from the legacy code on PHP 8.2, so a
 * change that alters behaviour fails here even when it silences a warning.
 * Every result and every deprecation is written the moment it happens,
 * straight to the STDOUT stream rather than through echo, so that output
 * buffering by the code under test can neither swallow nor delay it:
 *   PASS <test>
 *   FAIL <test>, followed by an indented reason line
 *   DEPRECATED <file>:<line> <message>
 *   END <tests run>   (after the last test)
 */

error_reporting(E_ALL);
ini_set('display_errors', 'stderr');

if ($argc !== 2 || !is_dir($argv[1])) {
    fwrite(STDERR, "usage: php tests/run.php <tree>\n");
    exit(2);
}
$tree = realpath($argv[1]);

$deprecated = 0;
$handler = function ($level, $message, $file, $line) use ($tree, &$deprecated) {
    $where = str_replace($tree . '/', '', $file) . ':' . $line;
    if ($level === E_DEPRECATED || $level === E_USER_DEPRECATED) {
        $deprecated++;
        fwrite(STDOUT, 'DEPRECATED ' . $where . ' ' . $message . "\n");
        return true;
    }
    // Everything else, including E_USER_ERROR, stops the code under test.
    throw new ErrorException($message, 0, $level, $file, $line);
};
set_error_handler($handler);

// Code under test that installs its own error handler would hide
// deprecations from this runner. Check after each test, and put ours back.
// A handler removed and restored within one test is not visible here; the
// supervisor catches the diagnostics PHP prints while ours is absent.
function handler_replaced()
{
    global $handler;
    $current = set_error_handler($handler);
    if ($current === $handler) {
        restore_error_handler();
        return false;
    }
    return true;
}

require __DIR__ . '/stubs/wordpress.php';
require __DIR__ . '/stubs/magento.php';

$plugin = $tree . '/wordpress/low-stock-notifier';
$module = $tree . '/magento/app/code/Example/StockFeed';

$results = [];
function check($name, callable $test)
{
    global $results;
    try {
        $test();
        if (handler_replaced()) {
            throw new RuntimeException('the code under test replaced the error handler');
        }
        $results[$name] = true;
        fwrite(STDOUT, 'PASS ' . $name . "\n");
    } catch (Throwable $e) {
        handler_replaced();
        $results[$name] = false;
        fwrite(STDOUT, 'FAIL ' . $name . "\n     " . get_class($e) . ': ' . $e->getMessage() . "\n");
    }
}
function same($expected, $actual, $label = 'value')
{
    if ($expected !== $actual) {
        throw new RuntimeException($label . ' expected ' . var_export($expected, true) . ' got ' . var_export($actual, true));
    }
}

check('load: plugin and module files compile and load', function () use ($plugin, $module) {
    require_once $plugin . '/low-stock-notifier.php';
    require_once $module . '/registration.php';
    require_once $module . '/Model/FeedParser.php';
    require_once $module . '/Model/MimeGuard.php';
    require_once $module . '/Model/SupplierClient.php';
});

$products = [
    ['sku' => 'BR-10', 'name' => 'Wall bracket', 'stock' => 2, 'category' => 'brackets'],
    ['sku' => 'AR-32', 'name' => 'Arm 32\" wide', 'stock' => 4, 'category' => 'arms', 'threshold' => '6 units'],
    ['sku' => 'SC-01', 'name' => 'Loose screws', 'stock' => 1],
    ['sku' => 'BR-20', 'name' => 'Ceiling bracket', 'stock' => 40, 'category' => 'brackets'],
];

$expectedCsv = "category,sku,name,stock\n"
    . ",SC-01,\"Loose screws\",1\n"
    . "arms,AR-32,\"Arm 32\\\" wide\",4\n"
    . "brackets,BR-10,\"Wall bracket\",2\n";

check('wp: threshold falls back to the option and casts leading digits', function () {
    $GLOBALS['stub_options'] = ['lsn_default_threshold' => '5'];
    $threshold = new LSN_Threshold();
    same(5, $threshold->for_product(['sku' => 'X']), 'default');
    same(6, $threshold->for_product(['threshold' => '6 units']), 'per product');
});

check('wp: products without a category are grouped under the empty key', function () use ($products) {
    $GLOBALS['stub_options'] = ['lsn_default_threshold' => '5'];
    $report = new LSN_Report(new LSN_Threshold());
    $low = $report->low_stock($products);
    same(['', 'arms', 'brackets'], array_keys($low), 'group keys');
    same(['SC-01'], array_column($low[''], 'sku'), 'uncategorised');
});

check('wp: CSV output is byte-identical to the legacy report', function () use ($products, $expectedCsv) {
    $GLOBALS['stub_options'] = ['lsn_default_threshold' => '5'];
    $report = new LSN_Report(new LSN_Threshold());
    same($expectedCsv, $report->to_csv($report->low_stock($products)), 'csv');
});

check('wp: subclass logs to the base channel', function () {
    $logger = new LSN_Mail_Logger();
    same('lsn_logger', $logger->channel(), 'channel');
    same('[lsn_logger] notice: hello', $logger->log(E_NOTICE, 'hello'), 'line');
    same('[lsn_logger] deprecated: old', $logger->log(E_DEPRECATED, 'old'), 'line');
});

check('wp: daily check emails the report and returns the count', function () use ($products, $expectedCsv) {
    $GLOBALS['stub_options'] = ['lsn_recipient' => 'stock@example.test', 'lsn_default_threshold' => '5'];
    $GLOBALS['stub_mail'] = [];
    same(3, lsn_run_daily_check($products), 'count');
    same(1, count($GLOBALS['stub_mail']), 'mails sent');
    same('stock@example.test', $GLOBALS['stub_mail'][0]['to'], 'recipient');
    same($expectedCsv, $GLOBALS['stub_mail'][0]['message'], 'body');
    same(['lsn_run_daily_check'], $GLOBALS['stub_actions']['lsn_daily_check'], 'hook');
});

check('wp: daily check stops, and sends nothing, without a recipient', function () use ($products) {
    $GLOBALS['stub_options'] = ['lsn_default_threshold' => '5'];
    $GLOBALS['stub_mail'] = [];
    $stopped = false;
    try {
        lsn_run_daily_check($products);
    } catch (Throwable $e) {
        $stopped = true;
    }
    same(true, $stopped, 'stopped');
    same(0, count($GLOBALS['stub_mail']), 'mails sent');
});

$feed = "sku,name,qty\n"
    . "AR-32,\"Arm 32\\\" wide\",4\n"
    . "BR-10,Wall bracket,0.0\n"
    . "broken line\n"
    . "SC-01,\"Screws, pack of 50\",12.5\n";

check('magento: feed parser keeps backslash-escaped quotes', function () use ($feed) {
    $warnings = [];
    $logger = new class($warnings) implements Psr\Log\LoggerInterface {
        private $sink;
        public function __construct(array &$sink) { $this->sink = &$sink; }
        public function warning($message, array $context = []) { $this->sink[] = $message; }
    };
    $rows = (new Example\StockFeed\Model\FeedParser($logger))->parse($feed);
    same(['AR-32', 'BR-10', 'SC-01'], array_column($rows, 'sku'), 'skus');
    same('Arm 32\" wide', $rows[0]['name'], 'escaped name');
    same('Screws, pack of 50', $rows[2]['name'], 'comma name');
    same([4.0, 0.0, 12.5], array_column($rows, 'qty'), 'qty');
    same([true, false, true], array_column($rows, 'in_stock'), 'in stock');
    same(['Skipping malformed feed line 4'], $warnings, 'warnings');
});

check('magento: feed parser works without a logger', function () use ($feed) {
    same(3, count((new Example\StockFeed\Model\FeedParser())->parse($feed)), 'rows');
});

check('magento: MIME guard accepts text and refuses a PNG', function () {
    $guard = new Example\StockFeed\Model\MimeGuard();
    same(true, $guard->isAcceptable("sku,name,qty\nAR-32,Arm,4\n"), 'text');
    same(false, $guard->isAcceptable("\x89PNG\r\n\x1a\n" . str_repeat("\0", 32)), 'png');
});

check('magento: supplier client reads the private timestamp', function () {
    $client = new Example\StockFeed\Model\SupplierClient(new Acme\SupplierSdk\Connection('2026-09-28T02:00:00Z'));
    same('2026-09-28T02:00:00Z', $client->lastFeedAt(), 'timestamp');
});

check('magento: module registers itself', function () use ($module) {
    same(realpath($module), realpath(Magento\Framework\Component\ComponentRegistrar::$registered['module']['Example_StockFeed']), 'path');
});

$failed = count(array_filter($results, function ($passed) { return !$passed; }));
fwrite(STDOUT, 'END ' . count($results) . "\n");
// This status covers only what happened before END. Deprecations raised
// later, and a shutdown function that calls exit(), are for the supervisor.
exit($failed === 0 && $deprecated === 0 ? 0 : 1);
