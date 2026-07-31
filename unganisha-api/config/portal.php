<?php

return [
    /*
     | Tenant that owns brand-new client signups from the public portal
     | register page (/portal/register). Existing clients are matched by
     | email and keep their own tenant. Null disables new-client signup.
     */
    'default_tenant_id' => env('PORTAL_DEFAULT_TENANT_ID'),

    /*
     | Tenant whose TLD pricing and registrar account answer the public,
     | unauthenticated domain availability check (/api/public/domains/check)
     | used by the moinfo.co.tz search box. A white-label host that matches a
     | tenant's custom_domain wins over this; it is only the fallback for the
     | platform's own hostname. Falls back to default_tenant_id, since that is
     | the tenant a resulting signup would land on anyway. Null disables the
     | public check (the endpoint then reports the search as unavailable).
     */
    'storefront_tenant_id' => env('PORTAL_STOREFRONT_TENANT_ID', env('PORTAL_DEFAULT_TENANT_ID')),

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
