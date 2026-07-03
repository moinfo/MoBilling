<?php

namespace App\Exceptions;

class WhmApiException extends \Exception
{
    public function __construct(public string $whmFunction, string $reason)
    {
        parent::__construct("WHM {$whmFunction} failed: {$reason}");
    }
}
