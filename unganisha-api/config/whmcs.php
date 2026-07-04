<?php

return [
    /*
    | Parallel-operation mode (docs/WHMCS_PARALLEL_OPERATION.md).
    |
    | While true, WHMCS remains the primary billing system for the data
    | imported from it: MoBilling's automations SKIP every record carrying a
    | legacy_id (imported subscriptions, invoices, domains) so clients are
    | never billed/dunned by both systems at once. MoBilling-native records
    | are unaffected.
    |
    | Flip to false at FINAL CUTOVER (after the delta import + WHMCS cron off).
    */
    'parallel_mode' => env('WHMCS_PARALLEL_MODE', true),

    /*
    | Credit the client's wallet for the unused portion when they downgrade
    | to a cheaper plan (WHMCS "Automatically Credit on Product Downgrade").
    | Credit = (old_price - new_price) × remaining-term-fraction × quantity.
    */
    'credit_on_downgrade' => env('WHMCS_CREDIT_ON_DOWNGRADE', true),

    /*
    | Auto-terminate long-overdue SUSPENDED services (WHMCS "Auto Terminate").
    |
    | Number of days a subscription must remain suspended before it is
    | automatically terminated (hosting account deleted, subscription status
    | set to 'terminated'). The clock starts from metadata.suspended_at
    | (written when the service is suspended), falling back to updated_at.
    |
    | SAFE DEFAULT: 0 = feature DISABLED. This is a destructive action (it
    | deletes the cPanel account and its data), so it stays off until an
    | operator sets WHMCS_AUTO_TERMINATE_DAYS to a positive value (e.g. 30).
    */
    'auto_terminate_suspended_days' => (int) env('WHMCS_AUTO_TERMINATE_DAYS', 0),
];
