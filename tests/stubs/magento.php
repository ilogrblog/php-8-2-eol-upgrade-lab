<?php
// Just enough of Magento, PSR-3 and the supplier SDK for the module to load.

namespace Magento\Framework\Component {
    class ComponentRegistrar
    {
        const MODULE = 'module';
        public static $registered = [];
        public static function register($type, $name, $path)
        {
            self::$registered[$type][$name] = $path;
        }
    }
}

namespace Psr\Log {
    interface LoggerInterface
    {
        public function warning($message, array $context = []);
    }
}

namespace Acme\SupplierSdk {
    class Connection
    {
        private $lastFeedAt;
        public function __construct($lastFeedAt)
        {
            $this->lastFeedAt = $lastFeedAt;
        }
    }
}
