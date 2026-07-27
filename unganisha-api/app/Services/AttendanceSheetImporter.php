<?php

namespace App\Services;

use App\Models\User;
use Carbon\Carbon;

/**
 * Imports an iVMS-4200 Time & Attendance export (CSV) into attendance.
 *
 * The export's columns vary by report type and locale, so the caller supplies a
 * mapping (which column is the person, the date, the times). Two time shapes are
 * supported:
 *   - 'inout'  : the row already has a check-in column and a check-out column.
 *   - 'single' : one punch per row (a time or datetime); rows are grouped per
 *                person+day and reduced to earliest-in / latest-out.
 * Staff are matched by name or by device employee number. Unmatched identities
 * are reported back so the operator can fix the mapping and re-upload.
 */
class AttendanceSheetImporter
{
    public function __construct(private AttendanceUpserter $upserter) {}

    /**
     * Read a CSV file into [headers, rows] for preview/mapping.
     *
     * @return array{headers:string[],rows:array<int,array<int,string>>,total:int}
     */
    public function parse(string $path, int $previewLimit = 8): array
    {
        $headers = [];
        $rows = [];
        $total = 0;

        if (($h = fopen($path, 'r')) !== false) {
            // Strip a UTF-8 BOM if present.
            $first = fgets($h);
            if ($first !== false) {
                $first = preg_replace('/^\xEF\xBB\xBF/', '', $first);
                rewind($h);
                if ($first !== null && str_starts_with($first, "\xEF\xBB\xBF")) {
                    fseek($h, 3);
                }
            }
            $line = 0;
            while (($data = fgetcsv($h)) !== false) {
                if ($data === [null] || (count($data) === 1 && trim((string) $data[0]) === '')) {
                    continue; // blank line
                }
                if ($line === 0) {
                    $headers = array_map(fn ($v) => trim((string) $v), $data);
                } else {
                    $total++;
                    if (count($rows) < $previewLimit) {
                        $rows[] = array_map(fn ($v) => trim((string) $v), $data);
                    }
                }
                $line++;
            }
            fclose($h);
        }

        return ['headers' => $headers, 'rows' => $rows, 'total' => $total];
    }

    /**
     * Import the file per the mapping.
     *
     * @param  array{
     *   match_by:string, identity_col:int, date_col:?int,
     *   time_mode:string, in_col:?int, out_col:?int, time_col:?int
     * }  $map
     * @return array{days:int,matched_rows:int,unmatched:array<string,int>,skipped:int}
     */
    public function import(string $tenantId, string $path, array $map): array
    {
        // person identity => user id
        $users = User::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('is_active', true)
            ->get(['id', 'name', 'device_employee_no']);
        $byName = $users->keyBy(fn ($u) => $this->norm($u->name));
        $byNo   = $users->filter(fn ($u) => $u->device_employee_no)->keyBy(fn ($u) => (string) $u->device_employee_no);

        $matchByName = ($map['match_by'] ?? 'name') === 'name';
        $single = ($map['time_mode'] ?? 'single') === 'single';

        // grouped[userId][date] = Carbon[]
        $grouped = [];
        $matchedRows = 0;
        $skipped = 0;
        $unmatched = [];

        if (($h = fopen($path, 'r')) === false) {
            return ['days' => 0, 'matched_rows' => 0, 'unmatched' => [], 'skipped' => 0];
        }
        $line = 0;
        while (($data = fgetcsv($h)) !== false) {
            if ($line++ === 0) {
                continue; // header
            }
            if ($data === [null]) {
                continue;
            }
            $cell = fn ($i) => $i === null || $i < 0 ? null : trim((string) ($data[$i] ?? ''));

            $identity = $cell($map['identity_col']);
            if ($identity === null || $identity === '') {
                $skipped++;
                continue;
            }

            $user = $matchByName ? $byName->get($this->norm($identity)) : $byNo->get($identity);
            if (!$user) {
                $unmatched[$identity] = ($unmatched[$identity] ?? 0) + 1;
                continue;
            }

            // Resolve the day + the swipe time(s) for this row.
            $dateStr = $map['date_col'] !== null ? $cell($map['date_col']) : null;

            if ($single) {
                $t = $this->parseDateTime($cell($map['time_col']), $dateStr);
                if (!$t) { $skipped++; continue; }
                $grouped[$user->id][$t->toDateString()][] = $t;
                $matchedRows++;
            } else {
                $in  = $this->parseDateTime($cell($map['in_col']), $dateStr);
                $out = $this->parseDateTime($cell($map['out_col']), $dateStr);
                if (!$in && !$out) { $skipped++; continue; }
                $day = ($in ?? $out)->toDateString();
                foreach ([$in, $out] as $t) {
                    if ($t) { $grouped[$user->id][$day][] = $t; }
                }
                $matchedRows++;
            }
        }
        fclose($h);

        $days = 0;
        foreach ($grouped as $uid => $perDay) {
            foreach ($perDay as $day => $times) {
                if ($this->upserter->applyDay($tenantId, $uid, $day, $times)) {
                    $days++;
                }
            }
        }

        return ['days' => $days, 'matched_rows' => $matchedRows, 'unmatched' => $unmatched, 'skipped' => $skipped];
    }

    private function norm(string $s): string
    {
        return preg_replace('/\s+/', ' ', mb_strtolower(trim($s)));
    }

    /**
     * Parse a time or datetime cell. If $value is time-only (HH:MM[:SS]) a
     * separate $dateStr supplies the day; a full datetime is used as-is.
     */
    private function parseDateTime(?string $value, ?string $dateStr): ?Carbon
    {
        $value = $value !== null ? trim($value) : '';
        if ($value === '' || $value === '-') {
            return null;
        }
        try {
            // time-only → needs a date
            if (preg_match('/^\d{1,2}:\d{2}(:\d{2})?$/', $value)) {
                if (!$dateStr) {
                    return null;
                }
                return Carbon::parse(trim($dateStr) . ' ' . $value);
            }
            return Carbon::parse($value);
        } catch (\Throwable) {
            return null;
        }
    }
}
