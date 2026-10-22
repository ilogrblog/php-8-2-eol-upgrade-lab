<?php
// The one-line configuration most guides show. Kept to demonstrate why
// the gates run on PHP 8.2 as well as the target: do not use it for a
// migration that must stay deployable on 8.2.

use Rector\Config\RectorConfig;

return RectorConfig::configure()
    ->withPaths([__DIR__ . '/build'])
    ->withPhpSets(php85: true);
