<?php
/**
 * Runs tests/run.php as a separate process and judges its complete output
 * only after that process has ended. This is the test gate.
 *
 * Usage: php tests/supervise.php <tree>
 *
 * The run passes only if all of these hold:
 *   - the child exited with status 0 and printed END;
 *   - every test in tests/expected-tests.txt reported PASS exactly once;
 *   - no test reported FAIL;
 *   - no DEPRECATED line appeared at any point, including after END
 *     (shutdown functions and final destructors run after it);
 *   - nothing else was printed on stdout, and nothing at all on stderr,
 *     where PHP writes diagnostics raised while the runner's error handler
 *     is not installed.
 *
 * A child that exits 0 after a failure, or ends early, therefore fails.
 * This is a check on ordinary code, not a sandbox: PHP running inside the
 * child can still suppress its own diagnostics or print forged results.
 *
 * Exit codes: 0 passed, 1 failed, 2 usage error.
 */

error_reporting(E_ALL);

if ($argc !== 2 || !is_dir($argv[1])) {
    fwrite(STDERR, "usage: php tests/supervise.php <tree>\n");
    exit(2);
}

$expected = array_values(array_filter(array_map('trim', file(__DIR__ . '/expected-tests.txt')), 'strlen'));
$command = [
    PHP_BINARY,
    '-d', 'display_errors=stderr',
    '-d', 'error_reporting=-1',
    '-d', 'log_errors=0',
    __DIR__ . '/run.php',
    $argv[1],
];
$process = proc_open($command, [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
if (!is_resource($process)) {
    echo "FAIL supervisor: could not start the test process\n";
    exit(1);
}
fclose($pipes[0]);

// Read both streams to the end without letting either pipe fill up.
$out = ['1' => '', '2' => ''];
$open = [1 => $pipes[1], 2 => $pipes[2]];
while ($open !== []) {
    $read = array_values($open);
    $write = null;
    $except = null;
    if (stream_select($read, $write, $except, 5) === false) {
        break;
    }
    foreach ($read as $stream) {
        $key = (string) array_search($stream, $open, true);
        $chunk = fread($stream, 8192);
        if ($chunk === '' || $chunk === false) {
            if (feof($stream)) {
                fclose($stream);
                unset($open[(int) $key]);
            }
            continue;
        }
        $out[$key] .= $chunk;
    }
}
$status = proc_close($process);

$problems = [];
$passed = [];
$failed = [];
$deprecations = [];   // distinct lines, so a deprecation hit in a loop counts once
$ended = false;
$lines = $out['1'] === '' ? [] : explode("\n", rtrim($out['1'], "\n"));
foreach ($lines as $i => $line) {
    echo $line, "\n";
    if (strncmp($line, 'PASS ', 5) === 0) {
        $name = substr($line, 5);
        if (isset($passed[$name]) || isset($failed[$name])) {
            $problems[] = 'result reported twice: ' . $name;
        }
        $passed[$name] = true;
        if ($ended) {
            $problems[] = 'result reported after END: ' . $name;
        }
    } elseif (strncmp($line, 'FAIL ', 5) === 0) {
        $failed[substr($line, 5)] = true;
    } elseif (strncmp($line, 'DEPRECATED ', 11) === 0) {
        $deprecations[$line] = true;
    } elseif (strncmp($line, 'END ', 4) === 0 && !$ended) {
        $ended = true;
    } elseif (strncmp($line, '     ', 5) === 0 && $i > 0 && strncmp($lines[$i - 1], 'FAIL ', 5) === 0) {
        // the reason line that follows a FAIL line
    } else {
        $problems[] = 'unexpected output: ' . $line;
    }
}
foreach (explode("\n", trim($out['2'])) as $line) {
    if (trim($line) !== '') {
        $problems[] = 'PHP diagnostic outside the runner: ' . trim($line);
    }
}
foreach ($expected as $name) {
    if (!isset($passed[$name]) && !isset($failed[$name])) {
        $problems[] = 'no result for: ' . $name;
    }
}
foreach (array_keys($passed + $failed) as $name) {
    if (!in_array($name, $expected, true)) {
        $problems[] = 'result for an unknown test: ' . $name;
    }
}
if (!$ended) {
    $problems[] = 'the test process ended before reporting every result';
}
if ($status !== 0) {
    $problems[] = 'the test process exited with status ' . $status;
}

foreach ($problems as $problem) {
    echo 'FAIL supervisor: ', $problem, "\n";
}
$ok = $problems === [] && $failed === [] && $deprecations === [];
printf(
    "PHP %s: %d of %d tests passed, %d failed, %d distinct deprecations, %d supervisor findings, %s\n",
    PHP_VERSION,
    count($passed),
    count($expected),
    count($failed),
    count($deprecations),
    count($problems),
    $ok ? 'PASS' : 'FAIL'
);
exit($ok ? 0 : 1);
