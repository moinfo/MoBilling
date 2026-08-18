<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Wires the pricing page's advertised differences into real enforcement
 * (see User::getPermissionNames()/planPermissionCeiling()) — until now
 * subscription_plan_permissions was populated by nobody, so every plan had
 * zero permissions and the ceiling stayed a no-op for everyone.
 *
 * Only the differences the pricing copy actually advertises as
 * feature-level (not usage-count) toggles are gated: Advanced Reports
 * (Professional+), SMS Notifications (Professional+), Multi-user access
 * (Business+), Custom branding (Business+). Everything else the app does
 * (clients, invoices, domains, hosting, HR/payroll, statutory, etc.) is
 * NOT advertised as plan-differentiated, so it's included on every plan —
 * this migration only *removes* the four gated groups from lower tiers,
 * it never restricts anything the pricing page doesn't actually promise.
 *
 * "Unlimited invoices/clients/users" and support-level promises (priority/
 * dedicated/24-7 support, SLA) are usage quotas and service commitments,
 * not permissions — out of scope here, flagged separately to the user.
 * Business and Enterprise end up permission-identical: every remaining
 * Enterprise-only line item (API access, white-label PDFs, custom
 * integrations) has no corresponding permission in the system yet.
 */
return new class extends Migration
{
    private const ADVANCED_REPORTS = [
        'reports.profit_loss', 'reports.statutory', 'reports.subscription', 'reports.expense',
        'reports.communication', 'reports.satisfaction', 'reports.system_records', 'reports.system_verifications',
    ];
    private const SMS = ['menu.sms'];
    private const MULTI_USER = ['menu.users', 'settings.users', 'menu.roles'];
    private const BRANDING = ['settings.company'];

    public function up(): void
    {
        $allNames = DB::table('permissions')->pluck('name')->all();

        $gatedGroups = fn (array $excluded) => array_values(array_diff($allNames, $excluded));

        $plans = [
            'Starter' => $gatedGroups(array_merge(self::ADVANCED_REPORTS, self::SMS, self::MULTI_USER, self::BRANDING)),
            'Professional' => $gatedGroups(array_merge(self::MULTI_USER, self::BRANDING)),
            'Business' => $allNames,
            'Enterprise' => $allNames,
        ];

        $permIdsByName = DB::table('permissions')->pluck('id', 'name');

        foreach ($plans as $planName => $names) {
            $planId = DB::table('subscription_plans')->where('name', $planName)->value('id');
            if (!$planId) {
                continue;
            }

            $rows = collect($names)
                ->map(fn ($name) => $permIdsByName[$name] ?? null)
                ->filter()
                ->map(fn ($permId) => ['subscription_plan_id' => $planId, 'permission_id' => $permId])
                ->all();

            DB::table('subscription_plan_permissions')->where('subscription_plan_id', $planId)->delete();
            foreach (array_chunk($rows, 500) as $chunk) {
                DB::table('subscription_plan_permissions')->insert($chunk);
            }
        }
    }

    public function down(): void
    {
        $planIds = DB::table('subscription_plans')
            ->whereIn('name', ['Starter', 'Professional', 'Business', 'Enterprise'])
            ->pluck('id');

        DB::table('subscription_plan_permissions')->whereIn('subscription_plan_id', $planIds)->delete();
    }
};
