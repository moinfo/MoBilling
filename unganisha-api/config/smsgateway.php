<?php

return [
    'base_url' => env('SMS_GATEWAY_URL', 'https://messaging-service.co.tz'),
    'master_authorization' => env('SMS_GATEWAY_MASTER_AUTH'),
    'timeout' => env('SMS_GATEWAY_TIMEOUT', 30),
];
