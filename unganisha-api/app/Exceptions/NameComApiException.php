<?php

namespace App\Exceptions;

class NameComApiException extends \Exception
{
    public function __construct(string $message, public int $httpStatus = 0)
    {
        parent::__construct($message);
    }
}
