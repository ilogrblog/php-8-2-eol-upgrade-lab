<?php
// Just enough of WordPress for the plugin to load and be exercised.

define('ABSPATH', __DIR__ . '/');

$GLOBALS['stub_options'] = [];
$GLOBALS['stub_actions'] = [];
$GLOBALS['stub_mail'] = [];

function get_option($name, $default = false)
{
    return array_key_exists($name, $GLOBALS['stub_options']) ? $GLOBALS['stub_options'][$name] : $default;
}

function add_action($hook, $callback)
{
    $GLOBALS['stub_actions'][$hook][] = $callback;
    return true;
}

function apply_filters($hook, $value)
{
    return $value;
}

function wp_mail($to, $subject, $message)
{
    $GLOBALS['stub_mail'][] = ['to' => $to, 'subject' => $subject, 'message' => $message];
    return true;
}
