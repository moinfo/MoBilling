<?php

namespace App\Services\Registrar;

use App\Models\DomainTld;
use App\Models\NameComSettings;

/**
 * Name.com TLD catalog + selling prices. READ-ONLY toward Name.com (one paced
 * GET /tldpricing). Never touches non-namecom rows (FRED .tz etc.), and a re-sync
 * never overwrites manual price overrides or the enabled/disabled choice.
 *
 * Selling price (whole TZS) = ROUND(usd x rate) + fixed markup, per operation.
 */
class NameComPricingService
{
    public static function sellingPrice(?float $usd, NameComSettings $s): ?float
    {
        if ($usd === null) return null;
        return (float) (round($usd * $s->usd_rate) + round($s->fixed_markup));
    }

    /** @return array{register: ?float, renew: ?float, transfer: ?float} */
    public static function pricesFor(?float $ur, ?float $un, ?float $ut, NameComSettings $s): array
    {
        return [
            'register' => self::sellingPrice($ur, $s),
            'renew'    => self::sellingPrice($un, $s),
            'transfer' => self::sellingPrice($ut, $s),
        ];
    }

    private static function usd($v): ?float
    {
        return is_numeric($v) ? round((float) $v, 2) : null;
    }

    private static function same(?float $a, ?float $b): bool
    {
        return ($a === null && $b === null) || ($a !== null && $b !== null && abs($a - $b) < 0.005);
    }

    /** Formula prices for the operations that are NOT manually overridden. */
    public static function autoPrices(DomainTld $row, array $p): array
    {
        $ops = $row->overridden_ops ?? [];
        $out = [];
        foreach (['register', 'renew', 'transfer'] as $op) {
            if (!in_array($op, $ops, true)) $out["{$op}_price"] = $p[$op] ?? 0;
        }
        return $out;
    }

    /** @return array{created:int, updated:int, changed:int, unchanged:int, skipped_other_registrar:int, skipped_invalid:int, total:int} */
    public function sync(string $tenantId, NameComDriver $driver): array
    {
        $entries = $driver->tldPricing(1);
        $settings = NameComSettings::forTenant($tenantId);
        $now = now();
        $out = ['created' => 0, 'updated' => 0, 'changed' => 0, 'unchanged' => 0, 'skipped_other_registrar' => 0, 'skipped_invalid' => 0, 'total' => count($entries)];

        $existing = DomainTld::where('tenant_id', $tenantId)->get()->keyBy('tld');

        foreach ($entries as $e) {
            $tld = strtolower(trim((string) ($e['tld'] ?? ''), '. '));
            // orderable names only: ASCII labels (IDN TLDs cannot pass the order name validation)
            if (!preg_match('/^[a-z]{2,63}(\.[a-z]{2,63})*$/', $tld)) { $out['skipped_invalid']++; continue; }

            $ur = self::usd($e['registrationPrice'] ?? null);
            $un = self::usd($e['renewalPrice'] ?? null);
            $ut = self::usd($e['transferInPrice'] ?? null);
            $p = self::pricesFor($ur, $un, $ut, $settings);
            $row = $existing->get($tld);

            if (!$row) {
                DomainTld::create([
                    'tenant_id' => $tenantId, 'tld' => $tld, 'registrar' => 'namecom',
                    'register_price' => $p['register'] ?? 0, 'renew_price' => $p['renew'] ?? 0, 'transfer_price' => $p['transfer'] ?? 0,
                    'years_min' => 1, 'years_max' => 10,
                    'is_active' => false,            // owner enables TLDs deliberately
                    'is_unmanaged' => true,          // renewals etc. stay in the manual queue
                    'usd_register' => $ur, 'usd_renew' => $un, 'usd_transfer' => $ut,
                    'usd_synced_at' => $now,
                ]);
                $out['created']++;
                continue;
            }

            if ($row->registrar !== 'namecom') { $out['skipped_other_registrar']++; continue; }

            $changed = !self::same($row->usd_register, $ur) || !self::same($row->usd_renew, $un) || !self::same($row->usd_transfer, $ut);
            $upd = ['usd_register' => $ur, 'usd_renew' => $un, 'usd_transfer' => $ut, 'usd_synced_at' => $now];
            if ($changed) {
                $upd['usd_changed'] = true;
                $upd['usd_prev'] = ['register' => $row->usd_register, 'renew' => $row->usd_renew, 'transfer' => $row->usd_transfer, 'at' => $now->toIso8601String()];
                $upd += self::autoPrices($row, $p); // manual per-operation overrides are kept
                $out['changed']++;
            } else {
                $out['unchanged']++;
            }
            // is_active and overridden prices are never touched here
            $row->update($upd);
            $out['updated']++;

            // A TLD that lost registration support must not stay on sale.
            if ($ur === null && $row->is_active) $row->update(['is_active' => false]);
        }

        return $out;
    }

    /** Re-apply the current rate/markup to every non-overridden operation of the Name.com rows. Returns rows changed. */
    public function recompute(string $tenantId): int
    {
        $s = NameComSettings::forTenant($tenantId);
        $n = 0;
        DomainTld::where('tenant_id', $tenantId)->where('registrar', 'namecom')->each(function (DomainTld $r) use ($s, &$n) {
            $p = self::pricesFor($r->usd_register, $r->usd_renew, $r->usd_transfer, $s);
            $new = self::autoPrices($r, $p);
            $diff = false;
            foreach ($new as $k => $v) if ((float) $r->{$k} !== (float) $v) $diff = true;
            if ($diff) {
                $r->update($new);
                $n++;
            }
        });
        return $n;
    }
}
