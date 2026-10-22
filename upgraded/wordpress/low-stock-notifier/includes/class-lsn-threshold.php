<?php

defined('ABSPATH') || exit;

class LSN_Settings
{
    public function default_threshold()
    {
        return get_option('lsn_default_threshold', '5');
    }
}

class LSN_Threshold
{
    private $settings;

    public function __construct(?LSN_Settings $settings = null)
    {
        $this->settings = $settings ?: new LSN_Settings();
    }

    public function for_product(array $product)
    {
        $raw = isset($product['threshold']) ? $product['threshold'] : $this->settings->default_threshold();
        return (int) $raw;
    }
}
