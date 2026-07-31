<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | Here you may configure your settings for cross-origin resource sharing
    | or "CORS". This determines what cross-origin operations may execute
    | in web browsers. You are free to adjust these settings as needed.
    |
    | To learn more: https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS
    |
    */

    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    'allowed_methods' => ['*'],

    // moinfo.co.tz is here for the public domain search on the marketing site;
    // localhost:3000 is that site's Next.js dev server.
    'allowed_origins' => [
        'http://localhost:3000',
        'http://localhost:5173',
        'http://localhost:5174',
        'https://mobilling.co.tz',
        'https://moinfo.co.tz',
        'https://www.moinfo.co.tz',
    ],

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => true,

];
