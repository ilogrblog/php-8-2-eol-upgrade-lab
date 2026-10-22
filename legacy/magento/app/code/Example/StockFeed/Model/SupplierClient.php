<?php

namespace Example\StockFeed\Model;

use Acme\SupplierSdk\Connection;

/**
 * The supplier SDK keeps the last feed timestamp in a private property
 * and offers no getter, so the module reads it by reflection.
 */
class SupplierClient
{
    private $connection;

    public function __construct(Connection $connection)
    {
        $this->connection = $connection;
    }

    public function lastFeedAt()
    {
        $property = new \ReflectionProperty(Connection::class, 'lastFeedAt');
        $property->setAccessible(true);
        return $property->getValue($this->connection);
    }
}
