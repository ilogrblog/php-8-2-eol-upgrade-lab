<?php
// Deprecation fixes only, for code that must keep running on PHP 8.2
// while servers move to 8.4 or 8.5.
//
// Tested claim, not a general one: on this fixture, the output of these
// rules lints and passes every test on PHP 8.2 to 8.5. On other code it
// may not. RemoveGetClassGetParentClassNoArgsRector rewrites
// get_parent_class() with no arguments as parent::class, which is a fatal
// error in a class that has no parent (and, inside a trait, a fatal error
// only when the method is called). Before running this configuration,
// search for get_parent_class() with no arguments and replace each call
// by hand with get_parent_class(self::class), which returns the same value
// on every version without the deprecation. counterexamples/ shows all
// three cases, and bin/check.sh runs them.

use Rector\Config\RectorConfig;
use Rector\Php81\Rector\MethodCall\RemoveReflectionSetAccessibleCallsRector;
use Rector\Php83\Rector\FuncCall\RemoveGetClassGetParentClassNoArgsRector;
use Rector\Php84\Rector\FuncCall\AddEscapeArgumentRector;
use Rector\Php84\Rector\Param\ExplicitNullableParamTypeRector;
use Rector\Php85\Rector\FuncCall\ArrayKeyExistsNullToEmptyStringRector;
use Rector\Removing\Rector\FuncCall\RemoveFuncCallRector;
use Rector\Renaming\Rector\Cast\RenameCastRector;
use Rector\Renaming\ValueObject\RenameCast;
use Rector\ValueObject\PhpVersion;
use PhpParser\Node\Expr\Cast\Bool_;
use PhpParser\Node\Expr\Cast\Double;
use PhpParser\Node\Expr\Cast\Int_;
use PhpParser\Node\Expr\Cast\String_;

return RectorConfig::configure()
    ->withPaths([__DIR__ . '/build'])
    // In Rector 2.6.7 and 2.7.0, a rule that declares a minimum PHP version runs only
    // when the project version reaches it. The nullable-parameter and CSV
    // rules below declare PHP 8.4, so name the target here; without this
    // line the project version comes from composer.json, or from whichever
    // PHP binary runs Rector. Other rules differ: the reflection rule
    // declares PHP 8.1, and the two configured rules declare no minimum.
    // Rules tied to a polyfill package can run above the project version
    // when that package is installed.
    ->withPhpVersion(PhpVersion::PHP_85)
    ->withRules([
        RemoveGetClassGetParentClassNoArgsRector::class, // 8.3
        ExplicitNullableParamTypeRector::class,          // 8.4
        AddEscapeArgumentRector::class,                  // 8.4
        RemoveReflectionSetAccessibleCallsRector::class, // 8.5 deprecates the call
        ArrayKeyExistsNullToEmptyStringRector::class,    // 8.5
    ])
    ->withConfiguredRule(RenameCastRector::class, [      // 8.5
        new RenameCast(Int_::class, Int_::KIND_INTEGER, Int_::KIND_INT),
        new RenameCast(Bool_::class, Bool_::KIND_BOOLEAN, Bool_::KIND_BOOL),
        new RenameCast(Double::class, Double::KIND_DOUBLE, Double::KIND_FLOAT),
        new RenameCast(String_::class, String_::KIND_BINARY, String_::KIND_STRING),
    ])
    ->withConfiguredRule(RemoveFuncCallRector::class, [  // 8.5
        'curl_close', 'curl_share_close', 'finfo_close', 'imagedestroy', 'xml_parser_free',
    ]);
