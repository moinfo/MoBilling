<?php

return [
    /*
     | Tenant that owns brand-new client signups from the public portal
     | register page (/portal/register). Existing clients are matched by
     | email and keep their own tenant. Null disables new-client signup.
     */
    'default_tenant_id' => env('PORTAL_DEFAULT_TENANT_ID'),

    /*
     | Hostnames a tenant may NOT claim as a white-label custom_domain.
     | These are the platform's own hosts — allowing a tenant to claim one
     | would let them capture default-domain signups. The host of
     | FRONTEND_URL is added automatically at validation time.
     */
    'reserved_hostnames' => array_filter(array_map('trim', explode(',', env('PORTAL_RESERVED_HOSTNAMES',
        'mobilling.co.tz,www.mobilling.co.tz,localhost,127.0.0.1'
    )))),
];
