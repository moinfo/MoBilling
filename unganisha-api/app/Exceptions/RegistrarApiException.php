<?php

namespace App\Exceptions;

class RegistrarApiException extends \Exception
{
    public function __construct(public string $action, string $reason)
    {
        parent::__construct("Registrar {$action} failed: {$reason}");
    }
}
