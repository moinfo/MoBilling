<?php

namespace App\Services\Registrar;

use App\Exceptions\RegistrarApiException;
use App\Models\DomainTld;

/**
 * Multi-TLD domain search ("foo" -> foo.com, foo.net, foo.co.tz ...).
 *
 * plan():  no network. One row per TLD (typed TLD first, then popular on-sale TLDs), with TZS prices.
 * check(): fills availability. All Name.com TLDs go out in ONE checkAvailability call; FRED TLDs
 *          are checked per domain exactly like the single-domain endpoint. Read-only.
 *
 * Audience 'portal'/'public' never see the registrar brand or wholesale cost; only 'staff' gets
 * `via` and the "enable it in Settings" hints.
 */
class DomainSuggestService
{
    public const MAX_TLDS = 12;
    public const DEFAULT_ROWS = 10;

    public function __construct(private DomainRegistrarManager $registrar) {}

    /** @return array{label: string, tld: ?string}|null null = invalid input */
    public static function parse(string $input): ?array
    {
        $s = strtolower(trim($input));
        $s = preg_replace('#^https?://#', '', $s);
        $s = preg_replace('#^www\.#', '', $s);
        $s = explode('/', $s, 2)[0];
        if ($s === '' || strlen($s) > 253) return null;
        $parts = explode('.', $s, 2);
        $label = $parts[0];
        $tld = isset($parts[1]) ? trim($parts[1], '.') : null;
        if (!preg_match('/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/', $label)) return null;
        if ($tld !== null && $tld !== '' && !preg_match('/^[a-z]{2,63}(\.[a-z]{2,63})*$/', $tld)) return null;
        return ['label' => $label, 'tld' => $tld ?: null];
    }

    /** @param string[]|null $only restrict to these TLDs (already-listed rows re-checked progressively) */
    public function plan(string $tenantId, string $label, ?string $typedTld, string $audience, ?array $only = null, int $max = self::DEFAULT_ROWS): array
    {
        $max = min($max, self::MAX_TLDS);
        $catalog = DomainTld::onSaleCatalog($tenantId);
        $tlds = [];
        if ($only !== null) {
            $tlds = array_slice(array_values(array_unique($only)), 0, self::MAX_TLDS);
        } else {
            if ($typedTld) $tlds[] = $typedTld;
            foreach ($catalog->where('is_popular', true) as $t) $tlds[] = $t->tld;
            if (count(array_unique($tlds)) < 4) foreach ($catalog as $t) $tlds[] = $t->tld; // nothing flagged popular: show what is on sale
            $tlds = array_slice(array_values(array_unique($tlds)), 0, $max);
        }

        $rows = [];
        foreach ($tlds as $tld) {
            $row = $this->baseRow($tenantId, $label, $tld, $audience, $typedTld === $tld);
            $rows[] = $row;
        }
        return $rows;
    }

    private function baseRow(string $tenantId, string $label, string $tld, string $audience, bool $typed): array
    {
        $pricing = DomainTld::priceFor($tenantId, $tld);
        $staff = $audience === 'staff';
        $row = [
            'tld' => $tld, 'name' => "{$label}.{$tld}", 'typed' => $typed, 'popular' => (bool) ($pricing?->is_popular),
            'offered' => (bool) $pricing, 'status' => 'pending', 'message' => null,
            'register_price' => $pricing ? (float) $pricing->register_price : null,
            'years_min' => $pricing?->years_min, 'years_max' => $pricing?->years_max,
            'can_order' => false,
            'check_group' => $pricing && $pricing->registrar === 'namecom' ? 'batch' : 'single', // neutral: UI sends all 'batch' rows in one request
        ];
        if ($staff) $row['via'] = $pricing ? ($pricing->registrar === 'namecom' ? 'namecom' : ($pricing->is_unmanaged ? 'manual' : 'fred')) : null;

        if (!$pricing) {
            $row['status'] = 'not_offered';
            $off = DomainTld::disabledNameCom($tenantId, $tld);
            if ($staff) $row['message'] = $off ? sprintf(DomainTld::DISABLED_HINT, $tld) : "No pricing configured for .{$tld} - add it in Settings > Domains.";
            else $row['message'] = "We don't currently offer .{$tld} domains.";
            if ($staff && $off) $row['status'] = 'disabled';
        } elseif ($pricing->registrar !== 'namecom' && $pricing->is_unmanaged) {
            // no live registry behind this TLD
            $row['status'] = $staff ? 'manual' : 'cannot_check';
            $row['message'] = $staff ? 'Manually fulfilled - verify availability yourself before ordering.' : 'We cannot check this one online - please contact us.';
            $row['can_order'] = $staff;
        }
        return $row;
    }

    /**
     * Fill availability for every still-pending row. Read-only.
     * @param array[] $rows from plan()
     */
    public function check(string $tenantId, array $rows): array
    {
        $nc = []; $other = [];
        foreach ($rows as $i => $r) {
            if ($r['status'] !== 'pending') continue;
            $p = DomainTld::priceFor($tenantId, $r['tld']);
            if (!$p) continue;
            if ($p->registrar === 'namecom') $nc[$i] = $r['name']; else $other[$i] = [$r['name'], $p];
        }

        if ($nc) {
            try {
                $res = $this->registrar->namecomFor($tenantId)->checkAvailabilityMany(array_values($nc));
                foreach ($nc as $i => $name) $rows[$i] = $this->apply($rows[$i], $res[$name] ?? null);
            } catch (\Throwable $e) {
                if (!$e instanceof RegistrarApiException && !$e instanceof \App\Exceptions\NameComApiException && !$e instanceof \InvalidArgumentException) throw $e;
                report($e);
                foreach ($nc as $i => $name) $rows[$i] = $this->apply($rows[$i], null);
            }
        }
        foreach ($other as $i => [$name, $p]) {
            try {
                $rows[$i] = $this->apply($rows[$i], $this->registrar->checkFor($tenantId, $name, $p));
            } catch (RegistrarApiException $e) {
                report($e);
                $rows[$i] = $this->apply($rows[$i], null);
            }
        }
        return $rows;
    }

    private function apply(array $row, ?array $res): array
    {
        if ($res === null) {
            $row['status'] = 'cannot_check';
        } elseif ($res['available']) {
            $row['status'] = 'available';
            $row['can_order'] = true;
        } else {
            $row['status'] = !empty($res['premium']) ? 'unavailable' : 'taken';
        }
        return $row;
    }

    /** Validation rules shared by the staff / portal / public suggest endpoints. */
    public static function rules(): array
    {
        return [
            'name'   => 'required|string|max:253',
            'tlds'   => 'sometimes|string|max:400',
            'check'  => 'sometimes|boolean',
        ];
    }

    /**
     * Whole endpoint body. Returns [payload, http status].
     * `tlds=com,net` re-plans just those TLDs (the UI uses it to check rows progressively); `check=0` skips availability.
     */
    public function respond(string $tenantId, array $data, string $audience): array
    {
        $p = self::parse($data['name']);
        if (!$p) return [['message' => 'Enter a domain name using letters, numbers and hyphens, e.g. mybusiness or mybusiness.com.'], 422];

        $only = null;
        if (isset($data['tlds']) && $data['tlds'] !== '') {
            $only = array_values(array_filter(array_map(fn ($t) => strtolower(trim($t, ". \t")), explode(',', $data['tlds']))));
            if (count($only) > self::MAX_TLDS) return [['message' => 'At most ' . self::MAX_TLDS . ' TLDs per request.'], 422];
            foreach ($only as $t) if (!preg_match('/^[a-z]{2,63}(\.[a-z]{2,63})*$/', $t)) return [['message' => 'Invalid TLD list.'], 422];
        }

        $rows = $this->plan($tenantId, $p['label'], $p['tld'], $audience, $only);
        if (filter_var($data['check'] ?? true, FILTER_VALIDATE_BOOLEAN)) $rows = $this->check($tenantId, $rows);

        return [['label' => $p['label'], 'typed_tld' => $p['tld'], 'data' => $rows], 200];
    }
}
