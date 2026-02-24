<?php

return [
    'consumer_key' => env('PESAPAL_CONSUMER_KEY'),
    'consumer_secret' => env('PESAPAL_CONSUMER_SECRET'),
    'sandbox' => env('PESAPAL_SANDBOX', true),
    'sandbox_url' => 'https://cybqa.pesapal.com/pesapalv3',
    'production_url' => 'https://pay.pesapal.com/v3',
    'ipn_id' => env('PESAPAL_IPN_ID'),
    'callback_url' => env('PESAPAL_CALLBACK_URL'),
    'ipn_url' => env('PESAPAL_IPN_URL'),
    'currency' => env('PESAPAL_CURRENCY', 'TZS'),
    'token_cache_ttl' => 240,
];
