<?php

return [
    'api_version' => env('WHATSAPP_API_VERSION', 'v18.0'),
    'timeout' => env('WHATSAPP_TIMEOUT', 30),
    'otp_template' => env('WHATSAPP_OTP_TEMPLATE', 'otp_code'),
    'otp_language' => env('WHATSAPP_OTP_LANG', 'en'),
];
