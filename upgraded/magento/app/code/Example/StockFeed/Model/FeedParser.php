<?php

namespace Example\StockFeed\Model;

use Psr\Log\LoggerInterface;

/**
 * Parses the supplier's nightly stock feed. The supplier escapes quotes
 * inside fields with a backslash, for example: "Arm 32\" wide".
 */
class FeedParser
{
    private $logger;

    public function __construct(?LoggerInterface $logger = null)
    {
        $this->logger = $logger;
    }

    /**
     * @return array<int, array{sku: string, name: string, qty: float, in_stock: bool}>
     */
    public function parse($feed)
    {
        $rows = [];
        foreach (preg_split('/\R/', trim($feed)) as $number => $line) {
            if ($number === 0) {
                continue; // header row
            }
            $fields = str_getcsv($line, escape: '\\');
            if (count($fields) !== 3) {
                if ($this->logger) {
                    $this->logger->warning('Skipping malformed feed line ' . ($number + 1));
                }
                continue;
            }
            $rows[] = [
                'sku'      => $fields[0],
                'name'     => $fields[1],
                'qty'      => (float) $fields[2],
                'in_stock' => (bool) (float) $fields[2],
            ];
        }
        return $rows;
    }
}
