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
];
