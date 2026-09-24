<?php

namespace App\Exceptions;

class LinodeApiException extends \Exception
{
    public function __construct(string $message, public int $httpStatus = 0, public array $errors = [])
    {
        parent::__construct($message);
    }
}
