<?php

namespace App\Exceptions;

class MikrotikApiException extends \Exception
{
    public function __construct(public string $action, string $reason)
    {
        parent::__construct("MikroTik {$action} failed: {$reason}");
    }
}
