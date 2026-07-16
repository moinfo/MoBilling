<?php

namespace App\Console\Commands;

use App\Models\StaffReportHoliday;
use App\Models\StaffReportPenalty;
use App\Models\Tenant;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * Seed Tanzania public holidays into each tenant's staff-report holiday list
 * for a year. Fixed national days + Easter (computed) are exact; the Islamic
 * feasts shift with the moon so they're best-estimate — adjust if the sighted
 * date differs. Idempotent, and it refunds any daily deduction on a seeded day.
 */
class SeedTzHolidays extends Command
{
    protected $signature = 'staff-reports:seed-tz-holidays {--year= : Calendar year (default: current)} {--tenant= : Limit to one tenant id}';
    protected $description = 'Seed Tanzania public holidays into staff-report holidays';

    public function handle(): int
    {
        $year = (int) ($this->option('year') ?: now()->year);

        $holidays = $this->tzHolidays($year);

        $tenants = $this->option('tenant')
            ? Tenant::whereKey($this->option('tenant'))->pluck('id')
            : Tenant::pluck('id');

        $added = 0;
        $refunded = 0;
        foreach ($tenants as $tenantId) {
            foreach ($holidays as $date => $name) {
                $h = StaffReportHoliday::withoutGlobalScopes()->firstOrCreate(
                    ['tenant_id' => $tenantId, 'date' => $date],
                    ['name' => $name],
                );
                if ($h->wasRecentlyCreated) {
                    $added++;
                }
                // refund any daily missing-deduction already charged for that day
                $refunded += StaffReportPenalty::withoutGlobalScopes()
                    ->where('tenant_id', $tenantId)
                    ->where('report_type', 'daily')->where('penalty_type', 'missing')
                    ->whereDate('period_date', $date)->delete();
            }
        }

        $this->info("Seeded {$year} TZ holidays: {$added} added across {$tenants->count()} tenant(s), {$refunded} daily deduction(s) refunded.");
        return self::SUCCESS;
    }

    /** [Y-m-d => name] for the given year. */
    private function tzHolidays(int $year): array
    {
        $fixed = [
            "$year-01-01" => "New Year's Day",
            "$year-01-12" => 'Zanzibar Revolution Day',
            "$year-04-07" => 'Karume Day',
            "$year-04-26" => 'Union Day',
            "$year-05-01" => 'Workers Day',
            "$year-07-07" => 'Saba Saba',
            "$year-08-08" => 'Nane Nane (Farmers Day)',
            "$year-10-14" => 'Nyerere Day',
            "$year-12-09" => 'Independence Day',
            "$year-12-25" => 'Christmas Day',
            "$year-12-26" => 'Boxing Day',
        ];

        // Easter (Computus) → Good Friday & Easter Monday
        $easter = $this->easter($year);
        $fixed[$easter->copy()->subDays(2)->toDateString()] = 'Good Friday';
        $fixed[$easter->copy()->addDay()->toDateString()]   = 'Easter Monday';

        // Islamic feasts — moon-sighting dependent, adjust if needed
        $islamic = [
            2026 => [
                '2026-03-20' => 'Idd El Fitr (approx)',
                '2026-05-27' => 'Idd El Hajj (approx)',
                '2026-08-26' => 'Maulid (approx)',
            ],
            2027 => [
                '2027-03-10' => 'Idd El Fitr (approx)',
                '2027-05-17' => 'Idd El Hajj (approx)',
                '2027-08-15' => 'Maulid (approx)',
            ],
        ];
        if (isset($islamic[$year])) {
            $fixed += $islamic[$year];
        }

        ksort($fixed);
        return $fixed;
    }

    /** Easter Sunday (Gregorian) via the Anonymous algorithm. */
    private function easter(int $year): Carbon
    {
        $a = $year % 19;
        $b = intdiv($year, 100);
        $c = $year % 100;
        $d = intdiv($b, 4);
        $e = $b % 4;
        $f = intdiv($b + 8, 25);
        $g = intdiv($b - $f + 1, 3);
        $h = (19 * $a + $b - $d - $g + 15) % 30;
        $i = intdiv($c, 4);
        $k = $c % 4;
        $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7;
        $m = intdiv($a + 11 * $h + 22 * $l, 451);
        $month = intdiv($h + $l - 7 * $m + 114, 31);
        $day = (($h + $l - 7 * $m + 114) % 31) + 1;

        return Carbon::create($year, $month, $day)->startOfDay();
    }
}
