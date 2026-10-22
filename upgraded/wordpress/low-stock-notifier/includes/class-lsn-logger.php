<?php

defined('ABSPATH') || exit;

class LSN_Logger
{
    private static $labels = [
        E_ERROR      => 'error',
        E_WARNING    => 'warning',
        E_NOTICE     => 'notice',
        E_DEPRECATED => 'deprecated',
    ];

    /** @var array<int, string> */
    public $lines = [];

    /**
     * The log channel is the class that defines this method, so every
     * subclass writes to the same channel as the base logger.
     */
    public function channel()
    {
        return strtolower(self::class);
    }

    public function log($level, $message)
    {
        $label = isset(self::$labels[$level]) ? self::$labels[$level] : 'unknown';
        $this->lines[] = sprintf('[%s] %s: %s', $this->channel(), $label, $message);
        return end($this->lines);
    }
}

class LSN_Mail_Logger extends LSN_Logger
{
}
