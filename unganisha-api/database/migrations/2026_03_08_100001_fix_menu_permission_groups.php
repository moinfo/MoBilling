<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Reorganize menu permission group_names to match the actual sidebar
 * navigation structure. This makes the Roles permission picker intuitive.
 */
return new class extends Migration
{
    public function up(): void
    {
        $updates = [
            // Top-level navigation items
            'menu.dashboard'            => 'Navigation',
            'menu.collection'           => 'Navigation',
            'menu.followups'            => 'Navigation',
            'menu.satisfaction_calls'   => 'Navigation',

            // Billing group (matches sidebar "Billing" section)
            'menu.clients'              => 'Billing',
            'menu.products'             => 'Billing',
            'menu.quotations'           => 'Billing',
            'menu.proformas'            => 'Billing',
            'menu.invoices'             => 'Billing',
            'menu.payments_in'          => 'Billing',
            'menu.client_subscriptions' => 'Billing',
            'menu.next_bills'           => 'Billing',

            // Statutory group
            'menu.statutories'          => 'Statutory',
            'menu.statutory_bills'      => 'Statutory',
            'menu.bill_categories'      => 'Statutory',
            'menu.payments_out'         => 'Statutory',

            // Expenses group
            'menu.expense_categories'   => 'Expenses',
            'menu.expenses'             => 'Expenses',

            // Other top-level items
            'menu.reports'              => 'Other',
            'menu.sms'                  => 'Other',
            'menu.automation'           => 'Other',
            'menu.users'               => 'Other',
        ];

        foreach ($updates as $name => $group) {
            DB::table('permissions')
                ->where('name', $name)
                ->update(['group_name' => $group]);
        }
    }

    public function down(): void
    {
        // Revert to original groups
        $reverts = [
            'menu.clients'    => 'Navigation',
            'menu.products'   => 'Navigation',
            'menu.sms'        => 'Navigation',
            'menu.automation' => 'Navigation',
            'menu.reports'    => 'Navigation',
            'menu.users'      => 'Navigation',
            'menu.satisfaction_calls' => 'satisfaction_calls',
        ];

        foreach ($reverts as $name => $group) {
            DB::table('permissions')
                ->where('name', $name)
                ->update(['group_name' => $group]);
        }
    }
};
