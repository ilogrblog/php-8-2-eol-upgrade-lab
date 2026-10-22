<?php

defined('ABSPATH') || exit;

class LSN_Report
{
    private $threshold;

    public function __construct(LSN_Threshold $threshold)
    {
        $this->threshold = $threshold;
    }

    /**
     * Products at or below their threshold, grouped by category.
     * Products without a category are grouped under the empty key.
     */
    public function low_stock(array $products)
    {
        $grouped = [];
        foreach ($products as $product) {
            if ($product['stock'] <= $this->threshold->for_product($product)) {
                $category = isset($product['category']) ? $product['category'] : null;
                $grouped[$category][] = $product;
            }
        }
        ksort($grouped);
        return $grouped;
    }

    public function to_csv(array $grouped)
    {
        $handle = fopen('php://temp', 'w+');
        fputcsv($handle, ['category', 'sku', 'name', 'stock']);
        foreach ($grouped as $category => $products) {
            foreach ($products as $product) {
                fputcsv($handle, [$category, $product['sku'], $product['name'], $product['stock']]);
            }
        }
        rewind($handle);
        $csv = stream_get_contents($handle);
        fclose($handle);
        return $csv;
    }
}
