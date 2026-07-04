<?php

return [
    /*
    | Default nameservers shown on the hosting welcome email when a server
    | has none configured (servers.nameservers is null).
    */
    'default_nameservers' => array_filter(array_map('trim', explode(',', env('HOSTING_DEFAULT_NAMESERVERS',
        'ns55.superdnssite.com,ns56.superdnssite.com'
    )))),
];
