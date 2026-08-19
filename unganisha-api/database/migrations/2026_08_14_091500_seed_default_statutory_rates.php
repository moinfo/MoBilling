<?php

use App\Models\Tenant;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Same default figures the now-removed hardcoded payroll_settings NSSF,
 * WCF and SDL percentage columns used — moved into the new statutory_rates
 * catalog so they're just data, editable/extendable (e.g. adding NHIF)
 * without a code change. Still only commonly-cited defaults, not
 * guaranteed current — verify with TRA/an accountant before relying on
 * them for real payroll.
 */
return new class extends Migration
{
    public function up(): void
    {
        $defaults = [
            ['name' => 'NSSF', 'employee_percent' => 10.00, 'employer_percent' => 10.00, 'reduces_taxable_income' => true],
            ['name' => 'WCF', 'employee_percent' => 0.00, 'employer_percent' => 0.50, 'reduces_taxable_income' => false],
            ['name' => 'SDL', 'employee_percent' => 0.00, 'employer_percent' => 3.50, 'reduces_taxable_income' => false],
        ];

        foreach (Tenant::withoutGlobalScopes()->pluck('id') as $tenantId) {
            foreach ($defaults as $rate) {
                $exists = DB::table('statutory_rates')->where('tenant_id', $tenantId)->where('name', $rate['name'])->exists();
                if (!$exists) {
                    DB::table('statutory_rates')->insert(array_merge($rate, [
                        'id' => (string) Str::uuid(),
                        'tenant_id' => $tenantId,
                        'is_active' => true,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]));
                }
            }
        }
    }

    public function down(): void {}
};
