<?php

return [
    /*
     | Tenant that owns brand-new client signups from the public portal
     | register page (/portal/register). Existing clients are matched by
     | email and keep their own tenant. Null disables new-client signup.
     */
    'default_tenant_id' => env('PORTAL_DEFAULT_TENANT_ID'),
];
