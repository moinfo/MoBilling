<?php

namespace App\Services;

class OfflinePaymentException extends \RuntimeException
{
    public function __construct(string $message, public int $status = 422, public string $errorCode = 'error', public array $extra = [])
    {
        parent::__construct($message);
    }
}
