<?php

namespace Example\StockFeed\Model;

/**
 * Refuses uploads that are not plain text before the parser sees them.
 */
class MimeGuard
{
    public function isAcceptable($contents)
    {
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $type = finfo_buffer($finfo, $contents);

        return in_array($type, ['text/plain', 'text/csv'], true);
    }
}
