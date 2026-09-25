<?php

return [
    /*
    | Default nameservers shown on the hosting welcome email when a server
    | has none configured (servers.nameservers is null).
    */
    'default_nameservers' => array_filter(array_map('trim', explode(',', env('HOSTING_DEFAULT_NAMESERVERS',
        'ns55.superdnssite.com,ns56.superdnssite.com'
    )))),

    /*
    | "Upgrade now, pay later" for bandwidth-suspended accounts (docs/hosting-bandwidth-upgrade.md).
    */
    'pay_later_upgrade_max'            => (float) env('HOSTING_PAY_LATER_UPGRADE_MAX', 500000), // invoice total cap (TZS)
    'pay_later_upgrade_due_days'       => 3,   // invoice due = today + N
    'pay_later_upgrade_cooldown_days'  => 60,  // max one per account per N days
    'pay_later_upgrade_overdue_days'   => 7,   // other invoice overdue by more than N days blocks it
    'pay_later_upgrade_staff_alert_after_days' => 2, // unpaid more than N days past due -> alert staff
];
